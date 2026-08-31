# ============================================================================
# net.gd — сетевая игра. Автозагрузка «Net».
#
# Модель — «хост-авторитет»: один из игроков крутит настоящий мир целиком,
# включая ботов, а остальные шлют только ввод и рисуют присланное состояние.
# Клиент не считает ни физику, ни попадания, поэтому расхождений между
# экранами не бывает по построению.
#
# Почему не детерминированный шаг-в-шаг (lockstep), к которому проект вроде бы
# располагает — фиксированные 60 Гц и сеяный ГПСЧ: в lockstep любой кадр ждёт
# ввода самого медленного игрока, а одно расхождение в последнем знаке float
# разводит партии навсегда и чинится только полным пересбором. Для аркады
# с сорока танками авторитет одной стороны проще и надёжнее.
#
# Что летит по сети:
#   надёжно   — старт партии (seed + режим), состав танков, изменения карты,
#               лента событий, итог партии;
#   ненадёжно — снапшот состояния 20 раз в секунду и ввод игрока 60 раз
#               в секунду. Потерянный снапшот не чинят: через 50 мс придёт
#               следующий, а переспрашивать устаревшее состояние бессмысленно.
#
# Карта не передаётся вовсе: генератор детерминирован, поэтому хватает seed —
# двадцати байт вместо мегабайта тайлов.
# ============================================================================
extends Node

const PORT := 8124
const MAX_PLAYERS := 4
## Снапшот раз в три тика — те же 20 Гц, что и у веб-версии.
const SNAP_EVERY := 3
## Клиент рисует прошлое: показывать надо между двумя пришедшими снапшотами,
## иначе на каждой потере пакета танки замирают. Две длины интервала —
## компромисс между задержкой и устойчивостью к джиттеру.
const INTERP_DELAY := 0.12

signal lobby_changed
signal match_starting(settings: Dictionary)
signal net_error(text: String)
signal disconnected

## "" — офлайн, "host" — хозяин партии, "client" — присоединившийся.
var role := ""
## peer_id -> {name, color_key, cosmetics, ready}
var lobby := {}
var my_name := "Игрок"

var _game: Node = null
var _peer: ENetMultiplayerPeer = null
var _next_tank_id := 1
## id танка -> команда последнего ввода (только у хоста).
var _commands := {}
## Буфер снапшотов у клиента: [{t, data}].
var _snaps: Array = []
var _roster := {}
var _match_active := false

# ------------------------------------------------------------- диагностика
## Счётчики за партию. Без них про «потери и лаги» нечего сказать: сеть
## либо работает, либо нет, а насколько плохо — не видно.
var stat_snap_out := 0     # отправлено снапшотов (хост)
var stat_snap_in := 0      # принято снапшотов (клиент)
var stat_snap_lost := 0    # не дошло, посчитано по разрывам нумерации
var stat_snap_late := 0    # пришло с опозданием и отброшено
var stat_cmd_in := 0       # принято пакетов ввода (хост)
var stat_cmd_late := 0     # ввод, пришедший не по порядку
var rtt_msec := 0.0        # время оборота до хоста
var last_snap_msec := 0    # когда пришёл последний снапшот

## Номер исходящей команды и последний принятый номер по каждому игроку.
var _cmd_seq := 0
var _cmd_last := {}
## Номер исходящего снапшота и последний принятый — по разрывам между
## ними считаются потери.
var _snap_seq := 0
var _last_snap_seq := -1

# --------------------------------------------------- искусственные условия
## Доля намеренно теряемых пакетов и добавочная задержка. Ноль — обычная
## работа. Нужны, чтобы плохую сеть можно было воспроизвести и починить,
## а не рассуждать о ней умозрительно.
var debug_loss := 0.0
var debug_lag_msec := 0.0
var _delayed: Array = []
var _dbg_rng := RandomNumberGenerator.new()

var is_online: bool:
	get: return role != ""

## Считает мир только хост. Офлайн-игра — тоже «хост» по смыслу.
var is_authority: bool:
	get: return role != "client"

func _ready() -> void:
	_dbg_rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func bind_game(g: Node) -> void:
	_game = g

## Отложенная отправка и замер оборота. Задержка нужна только отладке:
## в обычной игре очередь всегда пуста и цикл ничего не стоит.
func _process(_delta: float) -> void:
	if not _delayed.is_empty():
		var now := Time.get_ticks_msec()
		var keep := []
		for item in _delayed:
			if int(item["due"]) <= now:
				(item["call"] as Callable).call()
			else:
				keep.append(item)
		_delayed = keep

	# Оборот до хоста меряется средствами ENet: своей нумерации для этого
	# заводить незачем.
	if role == "client" and _peer != null:
		var st := _peer.get_peer(1)
		if st != null:
			rtt_msec = float(st.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

## Отправка с учётом отладочных условий: часть пакетов теряется, остальные
## уходят с задержкой.
func _send(callable: Callable) -> void:
	if debug_loss > 0.0 and _dbg_rng.randf() < debug_loss:
		return
	if debug_lag_msec > 0.0:
		_delayed.append({"due": Time.get_ticks_msec() + int(debug_lag_msec),
			"call": callable})
		return
	callable.call()

## Сводка состояния сети для HUD и тестов.
func stats() -> Dictionary:
	var stale := 0
	if last_snap_msec > 0:
		stale = Time.get_ticks_msec() - last_snap_msec
	return {
		"role": role, "rtt": rtt_msec, "stale_msec": stale,
		"snap_in": stat_snap_in, "snap_out": stat_snap_out,
		"snap_lost": stat_snap_lost, "snap_late": stat_snap_late,
		"cmd_in": stat_cmd_in, "cmd_late": stat_cmd_late,
	}

# ------------------------------------------------------------------ сессия
func host_game(port: int = PORT) -> bool:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		net_error.emit(I18n.t("net.err.host", {}, "Не удалось открыть порт %d" % port))
		return false
	multiplayer.multiplayer_peer = _peer
	role = "host"
	lobby = {1: _self_info()}
	lobby_changed.emit()
	return true

func join_game(address: String, port: int = PORT) -> bool:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		net_error.emit(I18n.t("net.err.join", {}, "Не удалось подключиться к %s" % address))
		return false
	multiplayer.multiplayer_peer = _peer
	role = "client"
	lobby = {}
	lobby_changed.emit()
	return true

## @param notify сообщить игре, что партия оборвалась. Ложь только там,
##        где игра уже сама уходит в меню — иначе выйдет двойной переход.
func leave(notify: bool = true) -> void:
	# Уход посреди партии — это тот же обрыв, только по своей воле. Без
	# сообщения игре клиент оставался в бою с застывшей картинкой: снапшоты
	# больше не приходят, а мир он не считает.
	var was_playing := _match_active and role == "client"
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	role = ""
	lobby.clear()
	_commands.clear()
	_cmd_last.clear()
	_snaps.clear()
	_delayed.clear()
	_roster.clear()
	_match_active = false
	_last_snap_seq = -1
	_snap_seq = 0
	last_snap_msec = 0
	lobby_changed.emit()
	if was_playing and notify:
		disconnected.emit()

func _self_info() -> Dictionary:
	return {
		"name": my_name,
		"color_key": String(Prof.cosmetics.get("color", "p1")),
		"cosmetics": Prof.equipped_cosmetics(),
		"ready": false,
	}

# --------------------------------------------------------------- соединения
func _on_peer_connected(id: int) -> void:
	if role != "host":
		return
	# Новичку отдаём весь лобби-список, себя объявляем ему отдельно.
	_rpc_lobby.rpc_id(id, lobby)

func _on_peer_disconnected(id: int) -> void:
	if role != "host":
		return
	lobby.erase(id)
	# Ввод отключившегося стирается немедленно. Без этого его танк продолжал
	# ехать по последней команде до конца партии — упирался в стену и жёг
	# гусеницы, пока кто-нибудь не подстрелит.
	_commands.erase(id)
	_cmd_last.erase(id)
	if _game != null and _game.has_method("net_peer_left"):
		_game.net_peer_left(id)
	_rpc_lobby.rpc(lobby)
	lobby_changed.emit()

func _on_connected() -> void:
	_rpc_hello.rpc_id(1, _self_info())

func _on_connect_failed() -> void:
	net_error.emit(I18n.t("net.err.failed", {}, "Сервер не отвечает"))
	leave()

func _on_server_disconnected() -> void:
	net_error.emit(I18n.t("net.err.lost", {}, "Соединение с хостом потеряно"))
	disconnected.emit()
	leave(false)

@rpc("any_peer", "reliable")
func _rpc_hello(info: Dictionary) -> void:
	if role != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	lobby[id] = info
	_rpc_lobby.rpc(lobby)
	lobby_changed.emit()

@rpc("authority", "reliable")
func _rpc_lobby(list: Dictionary) -> void:
	lobby = list
	lobby_changed.emit()

# ------------------------------------------------------------------ партия
## Хост объявляет старт: клиенты соберут ту же карту по seed и тем же
## настройкам, поэтому передавать нечего, кроме двадцати байт.
func host_start_match(settings: Dictionary, seed_value: int, roster: Array) -> void:
	if role != "host":
		return
	_match_active = true
	_roster.clear()
	for info in roster:
		_roster[int(info["id"])] = info
	_rpc_match_start.rpc(settings, seed_value, roster)

@rpc("authority", "reliable")
func _rpc_match_start(settings: Dictionary, seed_value: int, roster: Array) -> void:
	if seed_value < 0 or roster.is_empty() or not settings.has("mode"):
		net_error.emit(I18n.t("net.err.start", {},
			"Хост прислал непонятный старт партии"))
		return
	_snaps.clear()
	_last_snap_seq = -1
	_roster.clear()
	for info in roster:
		if _valid_tank_info(info):
			_roster[int(info["id"])] = info
	_match_active = true
	var s := settings.duplicate()
	s["net_seed"] = seed_value
	s["net_roster"] = roster
	match_starting.emit(s)

## Новый танк посреди партии — волны «Обороны» и подкрепления.
func host_tank_spawned(info: Dictionary) -> void:
	if role != "host" or not _match_active:
		return
	_roster[int(info["id"])] = info
	_rpc_tank_spawn.rpc(info)

@rpc("authority", "reliable")
func _rpc_tank_spawn(info: Dictionary) -> void:
	if not _valid_tank_info(info):
		push_warning("[Net] отброшено описание танка без обязательных полей")
		return
	_roster[int(info["id"])] = info
	if _game != null and _game.world != null:
		_game.net_spawn_puppet(info)

## Описание танка приходит по сети, и верить ему на слово нельзя: одно
## отсутствующее поле роняет игру прямо в обработчике пакета. Проверка
## дешевле любого разбора падения у игрока.
static func _valid_tank_info(info: Dictionary) -> bool:
	for key in ["id", "team", "name", "color_key", "chassis", "max_hp",
			"speed", "fire_rate", "owner_peer"]:
		if not info.has(key):
			return false
	return int(info["id"]) > 0

func next_tank_id() -> int:
	_next_tank_id += 1
	return _next_tank_id

func reset_tank_ids() -> void:
	_next_tank_id = 1

# ------------------------------------------------------------------- ввод
## Клиент шлёт свой ввод каждый тик. Ненадёжно: потерянный кадр ввода
# заметен меньше, чем задержка на его повторную доставку.
func send_command(cmd: Dictionary) -> void:
	if role != "client":
		return
	_cmd_seq = (_cmd_seq + 1) & 0xFFFF
	var data := NetProtocol.encode_command(cmd, _cmd_seq)
	_send(func(): _rpc_command.rpc_id(1, data))

@rpc("any_peer", "unreliable")
func _rpc_command(data: PackedByteArray) -> void:
	if role != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	if not lobby.has(id):
		return  # пакет от того, кого в партии нет
	var cmd := NetProtocol.decode_command(data)
	stat_cmd_in += 1

	# UDP не гарантирует порядок: пакет, ушедший раньше, может прийти позже.
	# Без этой проверки опоздавший кадр ввода затирал свежий, и танк дёргался
	# на ровном месте.
	var seq := int(cmd["seq"])
	if _cmd_last.has(id):
		var diff: int = (seq - int(_cmd_last[id])) & 0xFFFF
		if diff == 0 or diff > 32768:
			stat_cmd_late += 1
			return
	_cmd_last[id] = seq

	cmd["at"] = Time.get_ticks_msec()
	_commands[id] = cmd

## Сколько миллисекунд ввод считается годным после последнего пакета.
## Дальше танк отпускает управление вместо того, чтобы вечно ехать по
## последней команде: при обрыве это выглядело как танк-призрак, уходящий
## в стену до конца партии.
const COMMAND_TTL_MSEC := 500

## Последний ввод игрока — его читает сетевая схема управления.
func command_of(peer_id: int) -> Dictionary:
	var cmd: Dictionary = _commands.get(peer_id, {})
	if cmd.is_empty():
		return cmd
	if Time.get_ticks_msec() - int(cmd.get("at", 0)) > COMMAND_TTL_MSEC:
		return {}
	return cmd

# ---------------------------------------------------------------- снапшоты
func host_broadcast(tick: int, tanks: Array, bullets: Array, extra: Dictionary) -> void:
	if role != "host" or lobby.size() <= 1:
		return
	_snap_seq += 1
	var data := NetProtocol.encode_snapshot(_snap_seq, tick, tanks, bullets, extra)
	stat_snap_out += 1
	_send(func(): _rpc_snapshot.rpc(data))

@rpc("authority", "unreliable")
func _rpc_snapshot(data: PackedByteArray) -> void:
	var snap := NetProtocol.decode_snapshot(data)
	var seq := int(snap["seq"])

	# Пакеты приходят не по порядку: старый после нового просто отбрасываем,
	# иначе картинка дёрнется назад.
	if _last_snap_seq >= 0 and seq <= _last_snap_seq:
		stat_snap_late += 1
		return

	# Разрыв в нумерации — это и есть потерянные пакеты.
	if _last_snap_seq >= 0:
		stat_snap_lost += seq - _last_snap_seq - 1
	_last_snap_seq = seq

	stat_snap_in += 1
	last_snap_msec = Time.get_ticks_msec()
	_snaps.append({"t": Time.get_ticks_msec() / 1000.0, "data": snap})
	while _snaps.size() > 8:
		_snaps.pop_front()

## Состояние для отрисовки на текущий момент: танки интерполируются между
## двумя снапшотами, пули доводятся по своей скорости.
##
## Пули именно доводятся, а не интерполируются: они летят по прямой, и
# продолжить их от последнего пакета точнее, чем тянуть между двумя.
func render_state() -> Dictionary:
	if _snaps.is_empty():
		return {}
	var now := Time.get_ticks_msec() / 1000.0
	var target := now - INTERP_DELAY

	var older: Dictionary = _snaps[0]
	var newer: Dictionary = _snaps[-1]
	for i in range(_snaps.size() - 1):
		if float(_snaps[i]["t"]) <= target and float(_snaps[i + 1]["t"]) >= target:
			older = _snaps[i]
			newer = _snaps[i + 1]
			break

	var span: float = maxf(0.001, float(newer["t"]) - float(older["t"]))
	var k: float = clampf((target - float(older["t"])) / span, 0.0, 1.0)

	var tanks := {}
	var prev_by_id := {}
	for t in older["data"]["tanks"]:
		prev_by_id[int(t["id"])] = t
	for t in newer["data"]["tanks"]:
		var id := int(t["id"])
		var p: Dictionary = prev_by_id.get(id, t)
		tanks[id] = {
			"x": lerpf(float(p["x"]), float(t["x"]), k),
			"y": lerpf(float(p["y"]), float(t["y"]), k),
			"body": lerp_angle(float(p["body"]), float(t["body"]), k),
			"turret": lerp_angle(float(p["turret"]), float(t["turret"]), k),
			"hp": float(t["hp"]),
			"shield": float(t["shield"]),
			"flags": int(t["flags"]),
		}

	var ahead: float = maxf(0.0, now - float(newer["t"]))
	var ticks_ahead: float = ahead / Cfg.TICK_SEC
	var bullets := []
	for b in newer["data"]["bullets"]:
		bullets.append({
			"x": float(b["x"]) + float(b["vx"]) * ticks_ahead,
			"y": float(b["y"]) + float(b["vy"]) * ticks_ahead,
			"vx": float(b["vx"]), "vy": float(b["vy"]),
			"player": bool(b["player"]),
		})

	return {"tanks": tanks, "bullets": bullets, "extra": newer["data"]["extra"]}

# ------------------------------------------------------------ карта и лента
## Изменения тайлов уходят надёжно: пропущенное разрушение оставило бы
## у клиента стену, сквозь которую все стреляют.
func host_map_delta(delta: Array) -> void:
	if role != "host" or delta.is_empty() or lobby.size() <= 1:
		return
	_rpc_map_delta.rpc(delta)

@rpc("authority", "reliable")
func _rpc_map_delta(delta: Array) -> void:
	if _game == null or _game.world == null:
		return
	# Пакет мог прийти от старой версии или прийти битым: индекс за границей
	# карты — это падение прямо в обработчике.
	var limit: int = _game.world.map.tiles.size()
	var clean := []
	for entry in delta:
		if not (entry is Array) or entry.size() < 3:
			continue
		var i := int(entry[0])
		if i < 0 or i >= limit:
			continue
		clean.append(entry)
	if clean.size() != delta.size():
		push_warning("[Net] отброшено %d негодных изменений карты"
			% (delta.size() - clean.size()))
	if not clean.is_empty():
		_game.net_apply_map_delta(clean)

## Перк выбирается на экране клиента, а танк живёт у хоста — без этого
## выбор не имел бы никакого действия.
func send_perk(perk_id: String) -> void:
	if role != "client":
		return
	_rpc_perk.rpc_id(1, perk_id)

@rpc("any_peer", "reliable")
func _rpc_perk(perk_id: String) -> void:
	if role != "host" or _game == null:
		return
	_game.net_apply_perk(multiplayer.get_remote_sender_id(), perk_id)

## Событие одному игроку: например, «ты набрал уровень, выбирай перк».
func host_event_to(peer_id: int, kind: String, args: Dictionary) -> void:
	if role != "host":
		return
	_rpc_event.rpc_id(peer_id, kind, args)

## Клиент просит карту целиком: его отпечаток разошёлся с хостовым.
func request_map_resync() -> void:
	if role != "client":
		return
	_rpc_want_map.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_want_map() -> void:
	if role != "host" or _game == null or _game.world == null:
		return
	_rpc_full_map.rpc_id(multiplayer.get_remote_sender_id(),
		_game.world.map.snapshot_bytes())

@rpc("authority", "reliable")
func _rpc_full_map(data: PackedByteArray) -> void:
	if _game == null or _game.world == null:
		return
	var want: int = _game.world.map.tiles.size() * 2
	if data.size() != want:
		push_warning("[Net] карта не того размера: %d вместо %d" % [data.size(), want])
		return
	_game.world.map.apply_snapshot_bytes(data)
	print("[Net] карта пересинхронизирована (%d байт)" % data.size())

func host_event(kind: String, args: Dictionary) -> void:
	if role != "host" or lobby.size() <= 1:
		return
	_rpc_event.rpc(kind, args)

@rpc("authority", "reliable")
func _rpc_event(kind: String, args: Dictionary) -> void:
	if _game == null:
		return
	# Вид события приходит строкой: незнакомую игра просто не понимает,
	# и это нормально — так старый клиент переживает нового хоста.
	if not ["feed", "finish", "perk", "mapsum"].has(kind):
		return
	_game.net_apply_event(kind, args)
