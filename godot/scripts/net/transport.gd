class_name NetTransport
extends RefCounted

const DEFAULT_PORT := 27015

var name := ""
var error := ""

func host(_max_clients: int) -> MultiplayerPeer:
	return null

func join(_address: String) -> MultiplayerPeer:
	return null

func available() -> bool:
	return true

func unavailable_reason() -> String:
	return ""

class EnetTransport extends NetTransport:
	var port := DEFAULT_PORT

	func _init(port_: int = DEFAULT_PORT) -> void:
		name = "ENet"
		port = port_

	func host(max_clients: int) -> MultiplayerPeer:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(port, max_clients)
		if err != OK:
			error = I18n.t("net.err.host", {}, "Не удалось открыть порт %d" % port)
			return null
		return peer

	func join(address: String) -> MultiplayerPeer:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_client(address, port)
		if err != OK:
			error = I18n.t("net.err.join", {}, "Не удалось подключиться к %s" % address)
			return null
		return peer

class SteamTransport extends NetTransport:
	const DEV_APP_ID := 480

	var app_id := DEV_APP_ID
	static var _inited := false

	func _init(app_id_: int = DEV_APP_ID) -> void:
		name = "Steam"
		app_id = app_id_

	func available() -> bool:
		if not Engine.has_singleton("Steam"):
			return false
		return ClassDB.class_exists("SteamMultiplayerPeer")

	func unavailable_reason() -> String:
		return I18n.t("net.err.noSteam", {},
			"Сборка без Steam: нужен GodotSteam с SteamMultiplayerPeer")

	static func my_steam_id() -> int:
		if not Engine.has_singleton("Steam"):
			return 0
		return int(Engine.get_singleton("Steam").getSteamID())

	static func boot(app_id_: int = DEV_APP_ID) -> bool:
		if _inited:
			return true
		if not Engine.has_singleton("Steam") or not ClassDB.class_exists("SteamMultiplayerPeer"):
			return false
		var res: Dictionary = Engine.get_singleton("Steam").steamInitEx(app_id_, true)
		_inited = int(res.get("status", 1)) == 0
		return _inited

	func _ensure_init() -> bool:
		if _inited:
			return true
		var steam := Engine.get_singleton("Steam")
		var res: Dictionary = steam.steamInitEx(app_id, true)
		if int(res.get("status", 1)) != 0:
			error = I18n.t("net.err.steamInit", {"why": String(res.get("verbal", ""))},
				"Steam не запустился: %s" % String(res.get("verbal", "")))
			return false
		_inited = true
		return true

	func _make_peer() -> MultiplayerPeer:
		if not available():
			error = unavailable_reason()
			return null
		if not _ensure_init():
			return null
		var peer = ClassDB.instantiate("SteamMultiplayerPeer")
		if peer == null:
			error = unavailable_reason()
			return null
		peer.set_server_relay(true)
		return peer

	func host(_max_clients: int) -> MultiplayerPeer:
		var peer := _make_peer()
		if peer == null:
			return null
		var err: int = peer.create_host(0)
		if err != OK:
			error = I18n.t("net.err.steamHost", {}, "Steam не дал открыть игру")
			return null
		return peer

	func join(address: String) -> MultiplayerPeer:
		var id := address.strip_edges().to_int()
		if id <= 0:
			error = I18n.t("net.err.steamId", {},
				"Это не похоже на SteamID хоста")
			return null
		var peer := _make_peer()
		if peer == null:
			return null
		var err: int = peer.create_client(id, 0)
		if err != OK:
			error = I18n.t("net.err.steamJoin", {}, "Steam не дал подключиться")
			return null
		return peer

	static func pump() -> void:
		if _inited and Engine.has_singleton("Steam"):
			Engine.get_singleton("Steam").run_callbacks()
