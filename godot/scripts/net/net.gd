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
## компромисс между задержкой и устойчивостью к джиттеру. В тиках
## current_tick (60 Гц), не в секундах: 0.12 с × 60 ≈ 7.
const INTERP_DELAY_TICKS := 7

## Сбор в лобби идёт поверх Steam-лобби. Основной путь — приглашение друга
## (приватное лобби, ни SteamID, ни код наружу не идут). Для тех, кого нет
## в друзьях, есть публичное лобби с четырёхзначным кодом; SteamID хоста и
## там не публикуется — он берётся из getLobbyOwner уже после входа в лобби.
## В лобби ровно двое — хост и один гость.
const GAME_TAG := "tanchiki-v2"
const MAX_LOBBY := 2
## Значения enum Steam.* из GodotSteam 4.22. Держим числами, чтобы файл
## грузился и в сборке без расширения — там сетевой путь через Steam недоступен.
const _LOBBY_TYPE_PUBLIC := 2
const _LOBBY_CMP_EQUAL := 0
const _LOBBY_DIST_WORLDWIDE := 3
const _STEAM_RESULT_OK := 1
const _STEAM_ENTER_OK := 1  # CHAT_ROOM_ENTER_RESPONSE_SUCCESS

signal lobby_changed
signal match_starting(settings: Dictionary)
signal net_error(text: String)
signal disconnected
## -1 — отсчёта нет; иначе секунд до старта партии. Считает хост, клиенты
## только показывают присланное число.
signal countdown_changed(seconds_left: int)
## Игра позвала нас в сетевое лобби (принятое приглашение Steam или запуск
## по ссылке «Join Game»). UI должен открыть экран сети сам.
signal lobby_entered

## Глобальный сетевой тик: строго растёт в _physics_process, 60 раз в
## секунду (движок тикает физику с такой частотой — см. project.godot,
## [physics] common/physics_ticks_per_second). Живёт всё время работы
## процесса, не завязан на матч и НЕ сбрасывается в leave() — это часы
## сетевого слоя (TTL команд, буфер интерполяции, иск. лаг), а не партии.
var current_tick: int = 0

func _physics_process(_delta: float) -> void:
	current_tick += 1

## "" — офлайн, "host" — хозяин партии, "client" — присоединившийся.
var role := ""
## peer_id -> {name, color_key, cosmetics, ready}
var lobby := {}
## Выделенный сервер: этот хост — без своего танка, только считает партию.
## Ставится в host_dedicated(); game.gd проверяет перед созданием
## локального игрока в start_match().
var dedicated := false
## Сколько ГОСТЕЙ (не считая самого сервера) нужно для автостарта партии на
## выделенном сервере — без «Готов», по одному числу подключений.
var dedicated_target_players := 2
## Имя по умолчанию. Переводится при запуске: в английской игре в поле имени
## не должно стоять русское слово. Дальше это значение принадлежит игроку —
## смена языка его уже не трогает, иначе стёрла бы введённое им имя.
var my_name := ""

var _game: Node = null
## Тип нарочно общий, а не ENetMultiplayerPeer: транспорт сменный, и Steam
## вернёт сюда свой peer. Ничего специфичного для ENet отсюда не вызывается.
var _peer: MultiplayerPeer = null
var _next_tank_id := 1
## id танка -> команда последнего ввода (только у хоста).
var _commands := {}
## Буфер снапшотов у клиента: [{t, data}].
var _snaps: Array = []
## Кэш словаря «id танка -> запись» для младшего снапшота интерполяции —
## ключ по его "t" (тик current_tick). render_state() вызывается на частоте
## кадра (до 144 Гц), а сама пара снапшотов меняется на частоте их прихода
## (20 Гц): без кэша словарь пересобирался в разы чаще, чем менялась пара,
## которую он описывает.
var _interp_cache_t := -1
var _interp_cache_prev := {}
var _roster := {}
var _match_active := false
## -1 — отсчёта нет; иначе секунд до старта. См. countdown_changed.
var countdown_left := -1
## Растёт при каждом запуске/отмене отсчёта — асинхронный цикл в
## host_begin_countdown сверяется с ним и молча выходит, если отсчёт
## успел смениться другим или отмениться, пока он спал между секундами.
var _countdown_token := 0

## Код текущего лобби: хост генерирует, гость вводит. Пусто офлайн и при
## прямом подключении по адресу.
var lobby_code := ""
## Хэндл Steam-лобби (0 — нет). Есть только у пути «по коду».
var _steam_lobby_id := 0
## "host" | "join", пока не пришёл асинхронный колбэк Steam — для строки
## «Создаём…/Ищем…» в UI. Пусто — операции нет.
var lobby_pending := ""

# ------------------------------------------------------------- диагностика
## Счётчики за партию. Без них про «потери и лаги» нечего сказать: сеть
## либо работает, либо нет, а насколько плохо — не видно.
var stat_snap_out := 0     # отправлено снапшотов (хост)
var stat_snap_in := 0      # принято снапшотов (клиент)
var stat_snap_lost := 0    # не дошло, посчитано по разрывам нумерации
var stat_snap_late := 0    # пришло с опозданием и отброшено
var stat_cmd_in := 0       # принято пакетов ввода (хост)
var stat_cmd_late := 0     # ввод, пришедший не по порядку
var stat_tank_spawn_out := 0  # ушедших host_tank_spawned (хост)
var rtt_msec := 0.0        # время оборота до хоста
var last_snap_tick := 0    # current_tick, когда пришёл последний снапшот

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
	# Steam поднимается на старте, а не при первой партии: SteamID нужен
	# уже в меню, чтобы игрок мог его скопировать и передать.
	NetTransport.SteamTransport.boot()
	if my_name == "":
		my_name = I18n.t("net.player", {}, "Игрок")
	_dbg_rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Приглашения ловим всегда: игрок мог их получить, ещё не открыв экран сети.
	_steam_connect_invite_signals()
	# «Join Game» из друзей при закрытой игре: Steam кладёт «+connect_lobby <id>».
	_boot_join_lobby = _parse_connect_lobby()
	if _boot_join_lobby != 0:
		call_deferred("_do_boot_join")

func bind_game(g: Node) -> void:
	_game = g

## Отложенная отправка и замер оборота. Задержка нужна только отладке:
## в обычной игре очередь всегда пуста и цикл ничего не стоит.
func _process(_delta: float) -> void:
	# Колбэки Steam надо качать каждый кадр, иначе P2P не отвечает вовсе.
	# Дёшево и безвредно, когда Steam не используется: внутри стоит проверка.
	NetTransport.SteamTransport.pump()

	if not _delayed.is_empty():
		var now := current_tick
		var keep := []
		for item in _delayed:
			if int(item["due"]) <= now:
				(item["call"] as Callable).call()
			else:
				keep.append(item)
		_delayed = keep

	# Оборот до хоста меряется средствами ENet: своей нумерации для этого
	# заводить незачем. У другого транспорта такой статистики может не быть —
	# тогда rtt просто остаётся прежним, а не роняет процесс.
	var enet := _peer as ENetMultiplayerPeer
	if role == "client" and enet != null:
		var st: ENetPacketPeer = enet.get_peer(1)
		if st != null:
			rtt_msec = float(st.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

## Отправка с учётом отладочных условий: часть пакетов теряется, остальные
## уходят с задержкой.
func _send(callable: Callable) -> void:
	if debug_loss > 0.0 and _dbg_rng.randf() < debug_loss:
		return
	if debug_lag_msec > 0.0:
		# debug_lag_msec — миллисекунды снаружи (так его выставляют тесты и
		# отладка), но очередь считает в тиках current_tick — переводим один
		# раз на входе.
		_delayed.append({"due": current_tick + int(round(debug_lag_msec * Cfg.TICK_HZ / 1000.0)),
			"call": callable})
		return
	callable.call()

## Сводка состояния сети для HUD и тестов.
func stats() -> Dictionary:
	var stale := 0
	if last_snap_tick > 0:
		# Наружу — по-прежнему миллисекунды: HUD и game.gd::_check_net_alive()
		# сравнивают с NET_WARN_MSEC/NET_DEAD_MSEC, их менять незачем.
		stale = int((current_tick - last_snap_tick) * 1000.0 / Cfg.TICK_HZ)
	return {
		"role": role, "rtt": rtt_msec, "stale_msec": stale,
		"snap_in": stat_snap_in, "snap_out": stat_snap_out,
		"snap_lost": stat_snap_lost, "snap_late": stat_snap_late,
		"cmd_in": stat_cmd_in, "cmd_late": stat_cmd_late,
	}

# ------------------------------------------------------------------ сессия
## Чем доставляются пакеты. Меняется целиком: снапшоты, команды и RPC
## работают поверх высокоуровневого мультиплеера и транспорт не различают.
var transport: NetTransport = NetTransport.EnetTransport.new(PORT)

## Переключает транспорт. Недоступный (Steam без расширения) не ставится:
## иначе игрок нажал бы «Создать» и получил молчание вместо объяснения.
func set_transport(t: NetTransport) -> bool:
	if not t.available():
		net_error.emit(t.unavailable_reason())
		return false
	leave()
	transport = t
	return true

func host_game(port: int = PORT) -> bool:
	leave()
	if transport is NetTransport.EnetTransport:
		(transport as NetTransport.EnetTransport).port = port
	var peer := transport.host(MAX_PLAYERS - 1)
	if peer == null:
		_peer = null
		net_error.emit(transport.error)
		return false
	_peer = peer
	multiplayer.multiplayer_peer = _peer
	role = "host"
	lobby = {1: _self_info()}
	lobby_changed.emit()
	return true

## Выделенный сервер: та же ENet-хостовая партия, но без своего игрока —
## этот процесс только считает мир и раздаёт снапшоты. Транспорт нарочно
## ENet, а не то, что было выбрано раньше в UI: сервер не зависит от Steam.
##
## host_game() сам вызывает leave() первой строкой, а leave() (ниже) сбрасывает
## dedicated/dedicated_target_players — поэтому их выставляют ПОСЛЕ успешного
## host_game(), а не до.
func host_dedicated(port: int, target_players: int) -> bool:
	transport = NetTransport.EnetTransport.new(port)
	if not host_game(port):
		return false
	dedicated = true
	dedicated_target_players = clampi(target_players, 1, MAX_PLAYERS - 1)
	return true

## @param address адрес для ENet либо идентификатор лобби для Steam —
##        для этого слоя это непрозрачная строка.
func join_game(address: String, port: int = PORT) -> bool:
	leave()
	if transport is NetTransport.EnetTransport:
		(transport as NetTransport.EnetTransport).port = port
	var peer := transport.join(address)
	if peer == null:
		_peer = null
		net_error.emit(transport.error)
		return false
	_peer = peer
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
	dedicated = false
	dedicated_target_players = 2
	lobby.clear()
	_commands.clear()
	_cmd_last.clear()
	_snaps.clear()
	_interp_cache_t = -1
	_interp_cache_prev = {}
	_delayed.clear()
	_roster.clear()
	_match_active = false
	countdown_left = -1
	_countdown_token += 1
	_last_snap_seq = -1
	_snap_seq = 0
	last_snap_tick = 0
	# current_tick НЕ сбрасываем: это часы сетевого слоя на весь процесс,
	# а не состояние одного подключения.
	if _steam_lobby_id != 0:
		var s := _steam()
		if s != null:
			s.leaveLobby(_steam_lobby_id)
		_steam_lobby_id = 0
	lobby_code = ""
	lobby_pending = ""
	_join_target_lobby = 0
	pending_invite = {}
	lobby_changed.emit()
	if was_playing and notify:
		disconnected.emit()

func _self_info() -> Dictionary:
	return {
		"name": my_name,
		"color_key": Prof.equipped_color1,
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
	# Состав партии поменялся — отсчёт для прежнего состава уже не годится.
	if countdown_left >= 0:
		host_cancel_countdown()
	lobby.erase(id)
	# Ввод отключившегося стирается немедленно. Без этого его танк продолжал
	# ехать по последней команде до конца партии — упирался в стену и жёг
	# гусеницы, пока кто-нибудь не подстрелит.
	_commands.erase(id)
	_cmd_last.erase(id)
	if _game != null and _game.has_method("net_peer_left"):
		_game.net_peer_left(id)
	# Освободилось место — снова пускаем в лобби по коду.
	if _steam_lobby_id != 0:
		var s := _steam()
		if s != null:
			s.setLobbyJoinable(_steam_lobby_id, true)
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
	# Предел лобби: обычно ровно хост+гость (MAX_LOBBY), но у выделенного
	# сервера своего слота для игрока нет — считаем по dedicated_target_players
	# гостей плюс сам сервер (+1, потому что lobby.size() включает его запись
	# под ключом 1).
	var cap := (dedicated_target_players + 1) if dedicated else MAX_LOBBY
	if not lobby.has(id) and lobby.size() >= cap:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	# Новый игрок в разгар отсчёта — не тот состав, что отсчитывался.
	if countdown_left >= 0:
		host_cancel_countdown()
	lobby[id] = info
	_rpc_lobby.rpc(lobby)
	lobby_changed.emit()
	# Лобби заполнено — закрываем от поиска по коду.
	if lobby.size() >= MAX_LOBBY and _steam_lobby_id != 0:
		var s := _steam()
		if s != null:
			s.setLobbyJoinable(_steam_lobby_id, false)
	# Выделенный сервер сам решает, когда стартовать — набралось нужное число
	# гостей, и «Готов» тут спрашивать не у кого.
	if dedicated and countdown_left < 0 and not _match_active:
		var guests := 0
		for pid in lobby.keys():
			if int(pid) != 1:
				guests += 1
		if guests >= dedicated_target_players:
			host_begin_countdown()

@rpc("authority", "reliable")
func _rpc_lobby(list: Dictionary) -> void:
	lobby = list
	lobby_changed.emit()

# -------------------------------------------------- лобби Steam: инвайты и код
## id Steam-лобби, в которое мы сейчас входим (ждём lobby_joined).
var _join_target_lobby := 0
## Входящее приглашение: {id, name}. Живёт на экране сети, пока не принято
## и не протухло (следующим приглашением, входом или выходом).
var pending_invite := {}
## id лобби из «+connect_lobby» при холодном запуске по «Join Game».
var _boot_join_lobby := 0

## Доступ к синглтону Steam — как в steam_stats.gd. null, если расширения нет.
func _steam() -> Object:
	if not Engine.has_singleton("Steam"):
		return null
	return Engine.get_singleton("Steam")

static func _steam_ready() -> bool:
	return NetTransport.SteamTransport.new().available()

## Колбэки матчмейкинга. Идемпотентно: экран сети пересобирается часто,
## а подписка нужна одна на процесс.
func _steam_connect_signals() -> void:
	var s := _steam()
	if s == null:
		return
	for pair in [["lobby_created", _on_steam_lobby_created],
			["lobby_match_list", _on_steam_lobby_match_list],
			["lobby_joined", _on_steam_lobby_joined]]:
		if not s.is_connected(pair[0], pair[1]):
			s.connect(pair[0], pair[1])

## Приглашение может прийти, когда игрок ещё не открывал экран сети, —
## поэтому эти колбэки подключаются на старте (см. _ready).
func _steam_connect_invite_signals() -> void:
	var s := _steam()
	if s == null:
		return
	if not s.is_connected("join_requested", _on_steam_join_requested):
		s.connect("join_requested", _on_steam_join_requested)
	if not s.is_connected("lobby_invite", _on_steam_lobby_invite):
		s.connect("lobby_invite", _on_steam_lobby_invite)

## Четыре цифры, 1000–9999. Глобальной проверки уникальности нет: 9000
## вариантов, фильтр запроса по точному коду и партия на двоих делают
## совпадение пренебрежимым, а при нём берётся первое лобби из списка.
func _gen_code() -> String:
	return str(randi() % 9000 + 1000)

static func is_code(code: String) -> bool:
	if code.length() != 4:
		return false
	for c in code:
		if c < "0" or c > "9":
			return false
	return true

# --------------------------------------------------------------- создание лобби
## Единственный способ создать Steam-лобби: всегда публичное лобби с
## четырёхзначным кодом. Раньше «пригласить через оверлей Steam» и «дать код»
## были двумя разными типами лобби (приватное без кода / публичное с кодом) —
## объединены в одну, чтобы кнопка «Пригласить друга» в лобби (invite_overlay)
## всегда была рабочей (_steam_lobby_id теперь ставится в любом случае), а код
## всегда был под рукой как запасной способ, если оверлей приглашений Steam не
## открылся (выключен у игрока в настройках — игра этого никак не обнаружит).
func host_lobby() -> void:
	if lobby_pending != "":
		return
	if not _steam_ready() or _steam() == null:
		net_error.emit(I18n.t("net.err.noSteamInvite", {}, "Для игры через Steam нужен Steam"))
		return
	if not (transport is NetTransport.SteamTransport):
		set_transport(NetTransport.SteamTransport.new())
	_steam_connect_signals()
	lobby_pending = "host"
	lobby_changed.emit()
	_steam().createLobby(_LOBBY_TYPE_PUBLIC, MAX_LOBBY)

func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if lobby_pending != "host":
		return
	lobby_pending = ""
	var s := _steam()
	if result != _STEAM_RESULT_OK or s == null:
		net_error.emit(I18n.t("net.err.steamHost", {}, "Steam не дал открыть игру"))
		lobby_changed.emit()
		return
	# host_game() вызывает leave(), поэтому сперва поднимаем хоста, затем
	# пишем данные лобби — иначе leave() их же и сотрёт. SteamID хоста в
	# метаданные НЕ кладём: гость возьмёт его из getLobbyOwner после входа.
	if not host_game():
		s.leaveLobby(lobby_id)
		return
	_steam_lobby_id = lobby_id
	s.setLobbyData(lobby_id, "game", GAME_TAG)
	lobby_code = _gen_code()
	s.setLobbyData(lobby_id, "code", lobby_code)
	lobby_changed.emit()

## Оверлей Steam со списком друзей для приглашения в своё лобби.
func invite_overlay() -> void:
	if role != "host" or _steam_lobby_id == 0:
		return
	var s := _steam()
	if s != null:
		s.activateGameOverlayInviteDialog(_steam_lobby_id)

# ---------------------------------------------------------------- вход в лобби
## Ищет публичное лобби с этим кодом и входит в него.
func join_by_code(code: String) -> void:
	if lobby_pending != "":
		return
	code = code.strip_edges()
	if not is_code(code):
		net_error.emit(I18n.t("net.code.badcode", {}, "Код — это четыре цифры"))
		return
	if not _steam_ready() or _steam() == null:
		net_error.emit(I18n.t("net.err.noSteamCode", {}, "Для игры по коду нужен Steam"))
		return
	if not (transport is NetTransport.SteamTransport):
		set_transport(NetTransport.SteamTransport.new())
	_steam_connect_signals()
	lobby_code = code
	lobby_pending = "join"
	lobby_changed.emit()
	var s := _steam()
	s.addRequestLobbyListStringFilter("game", GAME_TAG, _LOBBY_CMP_EQUAL)
	s.addRequestLobbyListStringFilter("code", code, _LOBBY_CMP_EQUAL)
	s.addRequestLobbyListDistanceFilter(_LOBBY_DIST_WORLDWIDE)
	s.requestLobbyList()

func _on_steam_lobby_match_list(lobbies: Array) -> void:
	# Список приходит только на наш requestLobbyList из join_by_code.
	if lobby_pending != "join" or _join_target_lobby != 0:
		return
	if lobbies.is_empty():
		var wanted := lobby_code
		lobby_pending = ""
		lobby_code = ""
		net_error.emit(I18n.t("net.code.notfound", {"code": wanted},
			"Лобби с кодом %s не найдено" % wanted))
		lobby_changed.emit()
		return
	_enter_steam_lobby(int(lobbies[0]))

## Общий вход в известное Steam-лобби: приглашение, запуск по ссылке, код.
## SteamID хоста берём из getLobbyOwner ПОСЛЕ входа — наружу он не попадает.
func join_lobby_id(lobby_id: int) -> void:
	if lobby_id <= 0 or lobby_pending == "host":
		return
	if not _steam_ready() or _steam() == null:
		net_error.emit(I18n.t("net.err.noSteamInvite", {}, "Для приглашений нужен Steam"))
		return
	if not (transport is NetTransport.SteamTransport):
		set_transport(NetTransport.SteamTransport.new())
	_steam_connect_signals()
	lobby_pending = "join"
	lobby_changed.emit()
	_enter_steam_lobby(lobby_id)

func _enter_steam_lobby(lobby_id: int) -> void:
	_join_target_lobby = lobby_id
	_steam().joinLobby(lobby_id)

func _on_steam_lobby_joined(lobby_id: int, _perm: int, _locked: bool, response: int) -> void:
	if _join_target_lobby != lobby_id:
		return
	_join_target_lobby = 0
	var s := _steam()
	if s == null or response != _STEAM_ENTER_OK:
		lobby_pending = ""
		lobby_code = ""
		net_error.emit(I18n.t("net.err.joinLobby", {}, "Не удалось войти в лобби"))
		lobby_changed.emit()
		return
	var owner := int(s.getLobbyOwner(lobby_id))
	var code_here := String(s.getLobbyData(lobby_id, "code"))
	# join_game() вызывает leave() — _steam_lobby_id и код ставим после него.
	if not join_game(str(owner)):
		lobby_pending = ""
		lobby_code = ""
		lobby_changed.emit()
		return
	_steam_lobby_id = lobby_id
	lobby_code = code_here
	lobby_pending = ""
	pending_invite = {}
	lobby_changed.emit()

# ------------------------------------------------------------ входящие инвайты
func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	pending_invite = {}
	lobby_entered.emit()
	join_lobby_id(lobby_id)

func _on_steam_lobby_invite(inviter: int, lobby_id: int, _game_id: int) -> void:
	var s := _steam()
	var nm := ""
	if s != null:
		nm = String(s.getFriendPersonaName(inviter))
	pending_invite = {"id": lobby_id, "name": nm}
	lobby_changed.emit()

func accept_pending_invite() -> void:
	if pending_invite.is_empty():
		return
	var lid := int(pending_invite.get("id", 0))
	pending_invite = {}
	lobby_entered.emit()
	join_lobby_id(lid)

## «+connect_lobby <id>» — так Steam запускает игру по «Join Game», когда она
## была закрыта. Смотрим обычные аргументы и строку запуска от Steam.
func _parse_connect_lobby() -> int:
	var scan := func(parts) -> int:
		for i in range(parts.size() - 1):
			var a := String(parts[i])
			if a == "+connect_lobby" or a == "connect_lobby":
				return int(parts[i + 1])
		return 0
	var id: int = scan.call(OS.get_cmdline_args())
	if id == 0:
		id = scan.call(OS.get_cmdline_user_args())
	if id == 0:
		var s := _steam()
		if s != null:
			id = scan.call(String(s.getLaunchCommandLine()).split(" ", false))
	return id

func _do_boot_join() -> void:
	await get_tree().process_frame
	if _boot_join_lobby != 0:
		lobby_entered.emit()
		join_lobby_id(_boot_join_lobby)
		_boot_join_lobby = 0

## Хост есть, есть хотя бы один гость и все гости нажали «Готов».
func all_guests_ready() -> bool:
	if role != "host":
		return false
	var guests := 0
	for pid in lobby.keys():
		if int(pid) == 1:
			continue
		guests += 1
		if not bool((lobby[pid] as Dictionary).get("ready", false)):
			return false
	return guests > 0

## Клиент отмечает готовность; хост пересобирает лобби и, если шёл отсчёт для
## прежнего состояния, отменяет его.
func set_ready(v: bool) -> void:
	if role != "client":
		return
	_rpc_ready.rpc_id(1, v)

@rpc("any_peer", "reliable")
func _rpc_ready(v: bool) -> void:
	if role != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	if not lobby.has(id):
		return
	(lobby[id] as Dictionary)["ready"] = v
	if countdown_left >= 0:
		host_cancel_countdown()
	_rpc_lobby.rpc(lobby)
	lobby_changed.emit()

# --------------------------------------------------------------- обратный отсчёт
## Хост запускает синхронный отсчёт перед стартом партии: обе стороны должны
## увидеть одни и те же секунды, а не начать партию вразнобой. Ноль сам по
## себе ничего не запускает — это дело UI, слушающего countdown_changed,
## чтобы net.gd не знал ни про ui_root, ни про game.
func host_begin_countdown(duration: int = 5) -> void:
	if role != "host" or _match_active or countdown_left >= 0:
		return
	_countdown_token += 1
	var token := _countdown_token
	var left := duration
	_broadcast_countdown(left)
	while left > 0:
		await get_tree().create_timer(1.0).timeout
		# Отсчёт мог смениться другим или отмениться, пока мы спали секунду.
		if token != _countdown_token or role != "host":
			return
		left -= 1
		_broadcast_countdown(left)

## Прерывает отсчёт: игрок передумал, состав поменялся, партия уже пошла.
func host_cancel_countdown() -> void:
	if role != "host" or countdown_left < 0:
		return
	_countdown_token += 1
	_broadcast_countdown(-1)

## Единственное место, которое пишет countdown_left: и у хоста, и у клиента
## это отражение того, что реально разослано, а не отдельное состояние.
func _broadcast_countdown(seconds_left: int) -> void:
	_rpc_countdown.rpc(seconds_left)
	# rpc() не выполняет функцию локально — хосту нужно обновить себя сам,
	# как и в _rpc_hello.
	countdown_left = seconds_left
	countdown_changed.emit(seconds_left)

@rpc("authority", "reliable")
func _rpc_countdown(seconds_left: int) -> void:
	countdown_left = seconds_left
	countdown_changed.emit(seconds_left)

# ------------------------------------------------------------------ партия
## Матч официально идёт с точки зрения хоста ещё ДО host_start_match():
## World._init() спавнит игроков и часть ботов раньше, чем до него доходит
## очередь выставить _match_active внутри host_start_match(), и их
## host_tank_spawned() иначе молча не сработал бы (см. ниже — она не шлёт,
## пока флаг ложный). Вызывать до World.new() на хосте.
func begin_match() -> void:
	if role == "host":
		_match_active = true

## Хост объявляет старт: клиенты соберут ту же карту по seed и тем же
## настройкам, поэтому передавать нечего, кроме двадцати байт.
func host_start_match(settings: Dictionary, seed_value: int, roster: Array) -> void:
	if role != "host":
		return
	_match_active = true
	# Отсчёт своё дело сделал. Без сброса лобби, открытое после партии
	# (реванш, разрыв на «Обороне»), встречало бы игрока замершим нулём.
	countdown_left = -1
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
	_interp_cache_t = -1
	_interp_cache_prev = {}
	_last_snap_seq = -1
	_roster.clear()
	for info in roster:
		if _valid_tank_info(info):
			_roster[int(info["id"])] = info
	_match_active = true
	countdown_left = -1
	var s := settings.duplicate()
	s["net_seed"] = seed_value
	s["net_roster"] = roster
	match_starting.emit(s)

## Новый танк — авторитетный спавн игрока при старте партии (см.
## begin_match()) и подкрепления посреди неё (волны «Обороны», босс).
func host_tank_spawned(info: Dictionary) -> void:
	if role != "host" or not _match_active:
		return
	_roster[int(info["id"])] = info
	stat_tank_spawn_out += 1
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

	cmd["at"] = current_tick
	_commands[id] = cmd

## Сколько тиков ввод считается годным после последнего пакета (500 мс при
## 60 Гц). Дальше танк отпускает управление вместо того, чтобы вечно ехать
## по последней команде: при обрыве это выглядело как танк-призрак,
## уходящий в стену до конца партии.
const COMMAND_TTL_TICKS := 30

## Последний ввод игрока — его читает сетевая схема управления.
func command_of(peer_id: int) -> Dictionary:
	var cmd: Dictionary = _commands.get(peer_id, {})
	if cmd.is_empty():
		return cmd
	if current_tick - int(cmd.get("at", 0)) > COMMAND_TTL_TICKS:
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
	last_snap_tick = current_tick
	_snaps.append({"t": current_tick, "data": snap})
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
	var now := current_tick
	var target := now - INTERP_DELAY_TICKS

	var older: Dictionary = _snaps[0]
	var newer: Dictionary = _snaps[-1]
	for i in range(_snaps.size() - 1):
		if int(_snaps[i]["t"]) <= target and int(_snaps[i + 1]["t"]) >= target:
			older = _snaps[i]
			newer = _snaps[i + 1]
			break

	# Меньше тика разницы не бывает — порог 1.0 вместо старого 0.001
	# (тогда target/"t" были секундами-float, теперь целые тики).
	var span: float = maxf(1.0, float(int(newer["t"]) - int(older["t"])))
	var k: float = clampf(float(target - int(older["t"])) / span, 0.0, 1.0)

	# Пара снапшотов меняется на частоте их прихода (20 Гц), а этот метод —
	# на частоте кадра (до 144 Гц): пересобирать словарь на каждый вызов,
	# когда пара обычно та же самая, что и в прошлый раз, — чистые потери.
	var older_t: int = int(older["t"])
	if older_t != _interp_cache_t:
		_interp_cache_t = older_t
		_interp_cache_prev = {}
		for t in older["data"]["tanks"]:
			_interp_cache_prev[int(t["id"])] = t
	var prev_by_id: Dictionary = _interp_cache_prev

	var tanks := {}
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

	# now и "t" уже в тиках — раньше здесь секунды делили на длину тика,
	# теперь оба шага (время→доля секунды→тики) схлопнулись в одно вычитание.
	var ticks_ahead: float = maxf(0.0, float(now - int(newer["t"])))
	var bullets := []
	for b in newer["data"]["bullets"]:
		bullets.append({
			"x": float(b["x"]) + float(b["vx"]) * ticks_ahead,
			"y": float(b["y"]) + float(b["vy"]) * ticks_ahead,
			"vx": float(b["vx"]), "vy": float(b["vy"]),
			"player": bool(b["player"]),
		})

	return {"tanks": tanks, "bullets": bullets, "extra": newer["data"]["extra"]}

## Необработанный (без интерполяции) снимок одного танка из последнего
## пришедшего снапшота — для сверки предсказанного движения СВОЕГО танка.
## В отличие от render_state(), тик здесь в пространстве World.tick (как
## его прислал хост), а не current_tick — то, что нужно клиенту для сверки
## со своим world.tick. Пустой словарь — нет снапшотов или танк не найден.
func latest_snapshot_tank(net_id: int) -> Dictionary:
	if _snaps.is_empty():
		return {}
	var snap: Dictionary = _snaps[-1]["data"]
	for t in snap["tanks"]:
		if int(t["id"]) == net_id:
			return {
				"tick": int(snap["tick"]),
				"x": float(t["x"]), "y": float(t["y"]),
				"body": float(t["body"]), "turret": float(t["turret"]),
			}
	return {}

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
