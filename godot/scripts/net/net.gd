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

var is_online: bool:
	get: return role != ""

## Считает мир только хост. Офлайн-игра — тоже «хост» по смыслу.
var is_authority: bool:
	get: return role != "client"

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func bind_game(g: Node) -> void:
	_game = g

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

func leave() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	role = ""
	lobby.clear()
	_commands.clear()
	_snaps.clear()
	_roster.clear()
	_match_active = false
	lobby_changed.emit()

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
	leave()

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
	_snaps.clear()
	_roster.clear()
	for info in roster:
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
	_roster[int(info["id"])] = info
	if _game != null and _game.world != null:
		_game.net_spawn_puppet(info)

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
	_rpc_command.rpc_id(1, NetProtocol.encode_command(cmd))

@rpc("any_peer", "unreliable")
func _rpc_command(data: PackedByteArray) -> void:
	if role != "host":
		return
	_commands[multiplayer.get_remote_sender_id()] = NetProtocol.decode_command(data)

## Последний ввод игрока — его читает сетевая схема управления.
func command_of(peer_id: int) -> Dictionary:
	return _commands.get(peer_id, {})

# ---------------------------------------------------------------- снапшоты
func host_broadcast(tick: int, tanks: Array, bullets: Array, extra: Dictionary) -> void:
	if role != "host" or lobby.size() <= 1:
		return
	_rpc_snapshot.rpc(NetProtocol.encode_snapshot(tick, tanks, bullets, extra))

@rpc("authority", "unreliable")
func _rpc_snapshot(data: PackedByteArray) -> void:
	var snap := NetProtocol.decode_snapshot(data)
	# Пакеты приходят не по порядку: старый после нового просто отбрасываем,
	# иначе картинка дёрнется назад.
	if not _snaps.is_empty() and int(snap["tick"]) <= int(_snaps[-1]["data"]["tick"]):
		return
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
	if _game != null and _game.world != null:
		_game.net_apply_map_delta(delta)

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
	if _game != null and _game.world != null:
		_game.world.map.apply_snapshot_bytes(data)
		print("[Net] карта пересинхронизирована (%d байт)" % data.size())

func host_event(kind: String, args: Dictionary) -> void:
	if role != "host" or lobby.size() <= 1:
		return
	_rpc_event.rpc(kind, args)

@rpc("authority", "reliable")
func _rpc_event(kind: String, args: Dictionary) -> void:
	if _game != null:
		_game.net_apply_event(kind, args)
