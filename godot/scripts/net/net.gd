extends Node

const PORT := 8124
const MAX_PLAYERS := 4
const SNAP_EVERY := 3
const INTERP_DELAY_TICKS := 7

const GAME_TAG := "tanchiki-v2"
const MAX_LOBBY := 2
const _LOBBY_TYPE_PUBLIC := 2
const _LOBBY_TYPE_PRIVATE := 0
const _LOBBY_CMP_EQUAL := 0
const _LOBBY_DIST_WORLDWIDE := 3
const _STEAM_RESULT_OK := 1
const _STEAM_ENTER_OK := 1
const _STEAM_ENTER_GONE := 2
const _STEAM_ENTER_FULL := 4

signal lobby_changed
signal match_starting(settings: Dictionary)
signal net_error(text: String)
signal disconnected
signal countdown_changed(seconds_left: int)
signal lobby_entered
signal lobby_list_updated

var current_tick: int = 0

func _physics_process(_delta: float) -> void:
	current_tick += 1

var role := ""
var lobby := {}
var dedicated := false
var dedicated_target_players := 2
var my_name := ""

var _game: Node = null
var _peer: MultiplayerPeer = null
var _next_tank_id := 1
var _commands := {}
var _snaps: Array = []
var _interp_cache_t := -1
var _interp_cache_prev := {}
var _roster := {}
var _match_active := false
var countdown_left := -1
var _countdown_token := 0

var _steam_lobby_id := 0
var lobby_pending := ""
var room_name := ""
var _pending_room_name := ""
var lobby_browser_results: Array = []

var stat_snap_out := 0
var stat_snap_in := 0
var stat_snap_lost := 0
var stat_snap_late := 0
var stat_cmd_in := 0
var stat_cmd_late := 0
var stat_tank_spawn_out := 0
var rtt_msec := 0.0
var last_snap_tick := 0

var _net_log: PackedStringArray = []

var _cmd_seq := 0
var _cmd_last := {}
var _snap_seq := 0
var _last_snap_seq := -1

var debug_loss := 0.0
var debug_lag_msec := 0.0
var _delayed: Array = []
var _dbg_rng := RandomNumberGenerator.new()

var is_online: bool:
	get: return role != ""

var is_authority: bool:
	get: return role != "client"

func _ready() -> void:
	NetTransport.SteamTransport.boot()
	if my_name == "":
		my_name = I18n.t("net.player", {}, "Игрок")
	_dbg_rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_steam_connect_invite_signals()
	_boot_join_lobby = _parse_connect_lobby()
	if _boot_join_lobby != 0:
		call_deferred("_do_boot_join")

func bind_game(g: Node) -> void:
	_game = g

func _process(_delta: float) -> void:
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

	var enet := _peer as ENetMultiplayerPeer
	if role == "client" and enet != null:
		var st: ENetPacketPeer = enet.get_peer(1)
		if st != null:
			rtt_msec = float(st.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

func _send(callable: Callable) -> void:
	if debug_loss > 0.0 and _dbg_rng.randf() < debug_loss:
		return
	if debug_lag_msec > 0.0:
		_delayed.append({"due": current_tick + int(round(debug_lag_msec * Cfg.TICK_HZ / 1000.0)),
			"call": callable})
		return
	callable.call()

func stats() -> Dictionary:
	var stale := 0
	if last_snap_tick > 0:
		stale = int((current_tick - last_snap_tick) * 1000.0 / Cfg.TICK_HZ)
	return {
		"role": role, "rtt": rtt_msec, "stale_msec": stale,
		"snap_in": stat_snap_in, "snap_out": stat_snap_out,
		"snap_lost": stat_snap_lost, "snap_late": stat_snap_late,
		"cmd_in": stat_cmd_in, "cmd_late": stat_cmd_late,
	}

var transport: NetTransport = NetTransport.EnetTransport.new(PORT)

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
	_netlog("[net] host_game: слушаю порт %d" % port)
	return true

func host_dedicated(port: int, target_players: int) -> bool:
	transport = NetTransport.EnetTransport.new(port)
	if not host_game(port):
		return false
	dedicated = true
	dedicated_target_players = clampi(target_players, 1, MAX_PLAYERS - 1)
	return true

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
	_netlog("[net] join_game: подключаюсь к %s:%d" % [address, port])
	return true

func leave(notify: bool = true) -> void:
	var was_playing := _match_active and role == "client"
	if role != "":
		save_log_to_game_folder()
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
	if _steam_lobby_id != 0:
		var s := _steam()
		if s != null:
			s.leaveLobby(_steam_lobby_id)
		_steam_lobby_id = 0
	room_name = ""
	lobby_pending = ""
	_join_target_lobby = 0
	pending_invite = {}
	lobby_changed.emit()
	if was_playing and notify:
		disconnected.emit()

func _netlog(msg: String) -> void:
	print(msg)
	_net_log.append(msg)

func save_log_to_game_folder() -> void:
	if _net_log.is_empty():
		return
	var dst := OS.get_executable_path().get_base_dir().path_join("network_log.txt")
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(_net_log))
	f.close()

func _self_info() -> Dictionary:
	return {
		"name": my_name,
		"color_key": Prof.equipped_color1,
		"cosmetics": Prof.equipped_cosmetics(),
		"cannon_id": Prof.equipped_cannon,
		"ready": false,
	}

func _on_peer_connected(id: int) -> void:
	if role != "host":
		return
	_netlog("[net] peer_connected: %d" % id)
	_rpc_lobby.rpc_id(id, lobby)

func _on_peer_disconnected(id: int) -> void:
	if role != "host":
		return
	if countdown_left >= 0:
		host_cancel_countdown()
	lobby.erase(id)
	_commands.erase(id)
	_cmd_last.erase(id)
	if _game != null and _game.has_method("net_peer_left"):
		_game.net_peer_left(id)
	if _steam_lobby_id != 0:
		var s := _steam()
		if s != null:
			s.setLobbyJoinable(_steam_lobby_id, true)
	_rpc_lobby.rpc(lobby)
	lobby_changed.emit()

func _on_connected() -> void:
	_netlog("[net] connected_to_server")
	_rpc_hello.rpc_id(1, _self_info())

func _on_connect_failed() -> void:
	_netlog("[net] connection_failed")
	net_error.emit(I18n.t("net.err.failed", {}, "Сервер не отвечает"))
	leave()

func _on_server_disconnected() -> void:
	_netlog("[net] server_disconnected")
	net_error.emit(I18n.t("net.err.lost", {}, "Соединение с хостом потеряно"))
	disconnected.emit()
	leave(false)

@rpc("any_peer", "reliable")
func _rpc_hello(info: Dictionary) -> void:
	if role != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	if _match_active:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var cap := (dedicated_target_players + 1) if dedicated else MAX_LOBBY
	if not lobby.has(id) and lobby.size() >= cap:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if countdown_left >= 0:
		host_cancel_countdown()
	lobby[id] = info
	_rpc_lobby.rpc(lobby)
	lobby_changed.emit()
	if lobby.size() >= MAX_LOBBY and _steam_lobby_id != 0:
		var s := _steam()
		if s != null:
			s.setLobbyJoinable(_steam_lobby_id, false)
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

var _join_target_lobby := 0
var pending_invite := {}
var _boot_join_lobby := 0

func _steam() -> Object:
	if not Engine.has_singleton("Steam"):
		return null
	return Engine.get_singleton("Steam")

static func _steam_ready() -> bool:
	return NetTransport.SteamTransport.new().available()

func _steam_connect_signals() -> void:
	var s := _steam()
	if s == null:
		return
	for pair in [["lobby_created", _on_steam_lobby_created],
			["lobby_match_list", _on_steam_lobby_match_list],
			["lobby_joined", _on_steam_lobby_joined]]:
		if not s.is_connected(pair[0], pair[1]):
			s.connect(pair[0], pair[1])

func _steam_connect_invite_signals() -> void:
	var s := _steam()
	if s == null:
		return
	if not s.is_connected("join_requested", _on_steam_join_requested):
		s.connect("join_requested", _on_steam_join_requested)
	if not s.is_connected("lobby_invite", _on_steam_lobby_invite):
		s.connect("lobby_invite", _on_steam_lobby_invite)

func host_lobby(name: String) -> void:
	if lobby_pending != "":
		return
	if not _steam_ready() or _steam() == null:
		net_error.emit(I18n.t("net.err.noSteamInvite", {}, "Для игры через Steam нужен Steam"))
		return
	if not (transport is NetTransport.SteamTransport):
		set_transport(NetTransport.SteamTransport.new())
	_steam_connect_signals()
	_pending_room_name = name.strip_edges()
	if _pending_room_name == "":
		_pending_room_name = I18n.t("net.room.default", {"name": my_name}, "Игра %s" % my_name)
	lobby_pending = "host"
	lobby_changed.emit()
	_netlog("[net] host_lobby: создаю лобби, название='%s'" % _pending_room_name)
	_steam().createLobby(_LOBBY_TYPE_PUBLIC, MAX_LOBBY)

func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	_netlog("[net] lobby_created: result=%d lobby_id=%d" % [result, lobby_id])
	if lobby_pending != "host":
		return
	lobby_pending = ""
	var s := _steam()
	if result != _STEAM_RESULT_OK or s == null:
		net_error.emit(I18n.t("net.err.steamHost", {}, "Steam не дал открыть игру"))
		lobby_changed.emit()
		return
	if not host_game():
		s.leaveLobby(lobby_id)
		return
	_steam_lobby_id = lobby_id
	s.setLobbyData(lobby_id, "game", GAME_TAG)
	s.setLobbyData(lobby_id, "host_name", my_name)
	room_name = _pending_room_name
	_pending_room_name = ""
	s.setLobbyData(lobby_id, "room_name", room_name)
	lobby_changed.emit()

func invite_overlay() -> void:
	if role != "host" or _steam_lobby_id == 0:
		return
	var s := _steam()
	if s != null:
		s.activateGameOverlayInviteDialog(_steam_lobby_id)

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
	_netlog("[net] join_lobby_id: пробую войти в %d" % lobby_id)
	_enter_steam_lobby(lobby_id)

func _enter_steam_lobby(lobby_id: int) -> void:
	_join_target_lobby = lobby_id
	_steam().joinLobby(lobby_id)

func refresh_lobby_list() -> void:
	if not _steam_ready() or _steam() == null:
		net_error.emit(I18n.t("net.err.noSteamInvite", {}, "Для игры через Steam нужен Steam"))
		return
	if not (transport is NetTransport.SteamTransport):
		set_transport(NetTransport.SteamTransport.new())
	_steam_connect_signals()
	var s := _steam()
	s.addRequestLobbyListStringFilter("game", GAME_TAG, _LOBBY_CMP_EQUAL)
	s.addRequestLobbyListDistanceFilter(_LOBBY_DIST_WORLDWIDE)
	_netlog("[net] refresh_lobby_list: запрашиваю список (tag=%s)" % GAME_TAG)
	s.requestLobbyList()

func _on_steam_lobby_match_list(lobbies: Array) -> void:
	_netlog("[net] lobby_match_list: найдено %d лобби" % lobbies.size())
	var s := _steam()
	var out := []
	if s != null:
		for lid in lobbies:
			var id := int(lid)
			var host_name := String(s.getLobbyData(id, "host_name"))
			var room_name_here := String(s.getLobbyData(id, "room_name"))
			var members := int(s.getNumLobbyMembers(id))
			var max_members := int(s.getLobbyMemberLimit(id))
			_netlog("[net]   лобби %d: host='%s' room='%s' %d/%d" %
				[id, host_name, room_name_here, members, max_members])
			out.append({
				"id": id,
				"host_name": host_name,
				"room_name": room_name_here,
				"members": members,
				"max_members": max_members,
			})
	lobby_browser_results = out
	lobby_list_updated.emit()

func _on_steam_lobby_joined(lobby_id: int, _perm: int, _locked: bool, response: int) -> void:
	_netlog("[net] lobby_joined: lobby_id=%d response=%d" % [lobby_id, response])
	if _join_target_lobby != lobby_id:
		return
	_join_target_lobby = 0
	var s := _steam()
	if s == null or response != _STEAM_ENTER_OK:
		lobby_pending = ""
		room_name = ""
		var msg := I18n.t("net.err.joinLobby", {}, "Не удалось войти в лобби")
		if response == _STEAM_ENTER_FULL:
			msg = I18n.t("net.err.lobbyFull", {}, "Лобби уже заполнено")
		elif response == _STEAM_ENTER_GONE:
			msg = I18n.t("net.err.lobbyGone", {}, "Это лобби больше не существует")
		net_error.emit(msg)
		lobby_changed.emit()
		return
	var owner := int(s.getLobbyOwner(lobby_id))
	var room_here := String(s.getLobbyData(lobby_id, "room_name"))
	if not join_game(str(owner)):
		lobby_pending = ""
		room_name = ""
		lobby_changed.emit()
		return
	_steam_lobby_id = lobby_id
	room_name = room_here
	lobby_pending = ""
	pending_invite = {}
	lobby_changed.emit()

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

func host_begin_countdown(duration: int = 5) -> void:
	if role != "host" or _match_active or countdown_left >= 0:
		return
	_countdown_token += 1
	var token := _countdown_token
	var left := duration
	_broadcast_countdown(left)
	while left > 0:
		await get_tree().create_timer(1.0).timeout
		if token != _countdown_token or role != "host":
			return
		left -= 1
		_broadcast_countdown(left)

func host_cancel_countdown() -> void:
	if role != "host" or countdown_left < 0:
		return
	_countdown_token += 1
	_broadcast_countdown(-1)

func _broadcast_countdown(seconds_left: int) -> void:
	_rpc_countdown.rpc(seconds_left)
	countdown_left = seconds_left
	countdown_changed.emit(seconds_left)

@rpc("authority", "reliable")
func _rpc_countdown(seconds_left: int) -> void:
	countdown_left = seconds_left
	countdown_changed.emit(seconds_left)

func begin_match() -> void:
	if role == "host":
		_match_active = true

func host_start_match(settings: Dictionary, seed_value: int, roster: Array) -> void:
	if role != "host":
		return
	_match_active = true
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
		return
	var cmd := NetProtocol.decode_command(data)
	stat_cmd_in += 1

	var seq := int(cmd["seq"])
	if _cmd_last.has(id):
		var diff: int = (seq - int(_cmd_last[id])) & 0xFFFF
		if diff == 0 or diff > 32768:
			stat_cmd_late += 1
			return
	_cmd_last[id] = seq

	cmd["at"] = current_tick
	_commands[id] = cmd

const COMMAND_TTL_TICKS := 30

func command_of(peer_id: int) -> Dictionary:
	var cmd: Dictionary = _commands.get(peer_id, {})
	if cmd.is_empty():
		return cmd
	if current_tick - int(cmd.get("at", 0)) > COMMAND_TTL_TICKS:
		return {}
	return cmd

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

	if _last_snap_seq >= 0 and seq <= _last_snap_seq:
		stat_snap_late += 1
		return

	if _last_snap_seq >= 0:
		stat_snap_lost += seq - _last_snap_seq - 1
	_last_snap_seq = seq

	stat_snap_in += 1
	last_snap_tick = current_tick
	_snaps.append({"t": current_tick, "data": snap})
	while _snaps.size() > 8:
		_snaps.pop_front()

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

	var span: float = maxf(1.0, float(int(newer["t"]) - int(older["t"])))
	var k: float = clampf(float(target - int(older["t"])) / span, 0.0, 1.0)

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

func host_map_delta(delta: Array) -> void:
	if role != "host" or delta.is_empty() or lobby.size() <= 1:
		return
	_rpc_map_delta.rpc(delta)

@rpc("authority", "reliable")
func _rpc_map_delta(delta: Array) -> void:
	if _game == null or _game.world == null:
		return
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

func send_perk(perk_id: String) -> void:
	if role != "client":
		return
	_rpc_perk.rpc_id(1, perk_id)

@rpc("any_peer", "reliable")
func _rpc_perk(perk_id: String) -> void:
	if role != "host" or _game == null:
		return
	_game.net_apply_perk(multiplayer.get_remote_sender_id(), perk_id)

func host_event_to(peer_id: int, kind: String, args: Dictionary) -> void:
	if role != "host":
		return
	_rpc_event.rpc_id(peer_id, kind, args)

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
	if not ["feed", "finish", "perk", "mapsum"].has(kind):
		return
	_game.net_apply_event(kind, args)
