# ============================================================================
# transport.gd — чем именно доставляются пакеты: ENet или Steam.
#
# Вся сетевая логика игры — снапшоты, команды, сверка карты, RPC — построена
# на высокоуровневом мультиплеере Godot. Ему безразлично, какой под ним
# MultiplayerPeer, поэтому переход на Steam это ЗАМЕНА ТРАНСПОРТА, а не
# переписывание netcode. Здесь и проходит эта граница.
#
# Транспорт обязан уметь ровно две вещи: поднять хоста и подключиться.
# Всё остальное — адрес, порт, лобби, приглашения — его частности, и net.gd
# про них не знает.
#
# Оба транспорта рабочие. ENet ходит по адресу и порту — это локальная сеть
# и проброс портов. Steam ведёт соединение через релей Valve, поэтому проброс
# не нужен, а «адресом» служит SteamID хоста.
#
# ============================================================================
class_name NetTransport
extends RefCounted

## Порт по умолчанию для прямого подключения.
const DEFAULT_PORT := 27015

## Человекочитаемое имя — для меню и сообщений об ошибках.
var name := ""
## Последняя ошибка: транспорт объясняет провал сам, net.gd её только
## показывает и не разбирает.
var error := ""

## Поднимает хоста. Возвращает готовый peer либо null.
## @param max_clients сколько подключений принимать, не считая себя
func host(_max_clients: int) -> MultiplayerPeer:
	return null

## Подключается к хосту. address — адрес для ENet либо идентификатор лобби
## для Steam: для net.gd это непрозрачная строка.
func join(_address: String) -> MultiplayerPeer:
	return null

## Доступен ли транспорт в этой сборке. Steam недоступен без расширения,
## и меню обязано это показывать, а не падать при нажатии.
func available() -> bool:
	return true

## Что показать игроку, если транспорт недоступен.
func unavailable_reason() -> String:
	return ""

# ============================================================================
# ENet: прямое подключение по адресу и порту. Работает в локальной сети
# и через проброс портов, обхода NAT не делает.
# ============================================================================
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

# ============================================================================
# Steam: P2P через релей Valve.
#
# Лобби здесь намеренно не используются: их создание асинхронно (ответ
# приходит колбэком), а транспорту нужен peer прямо сейчас. Поэтому хост
# просто открывается на своём SteamID, а подключение идёт к нему же —
# ровно как к адресу, только адрес это идентификатор игрока.
#
# Что нужно для работы:
#   1. GDExtension GodotSteam с классом SteamMultiplayerPeer;
#   2. App ID: 480 (Spacewar) для разработки, свой — для релиза;
#   3. запущенный клиент Steam.
#
# Проверено на этой машине: расширение 4.22 загружается, steamInitEx(480)
# возвращает status 0, SteamID читается.
# ============================================================================
class SteamTransport extends NetTransport:
	## Тестовый App ID Steam. Лобби и P2P с ним работают, выпускать игру — нет.
	const DEV_APP_ID := 480

	var app_id := DEV_APP_ID
	static var _inited := false

	func _init(app_id_: int = DEV_APP_ID) -> void:
		name = "Steam"
		app_id = app_id_

	## Расширение поставляется отдельной сборкой движка либо GDExtension,
	## поэтому проверяется наличием класса, а не флагом сборки.
	func available() -> bool:
		if not Engine.has_singleton("Steam"):
			return false
		return ClassDB.class_exists("SteamMultiplayerPeer")

	func unavailable_reason() -> String:
		return I18n.t("net.err.noSteam", {},
			"Сборка без Steam: нужен GodotSteam с SteamMultiplayerPeer")

	## Свой идентификатор — его и сообщают тем, кто хочет подключиться.
	## Он же играет роль адреса: у Steam нет ни IP, ни порта.
	static func my_steam_id() -> int:
		if not Engine.has_singleton("Steam"):
			return 0
		return int(Engine.get_singleton("Steam").getSteamID())

	## Инициализация при запуске игры. Без неё не работает ничего: ни SteamID,
	## ни оверлей, ни P2P, — а SteamID нужен уже в меню, до первой партии.
	static func boot(app_id_: int = DEV_APP_ID) -> bool:
		if _inited:
			return true
		if not Engine.has_singleton("Steam") or not ClassDB.class_exists("SteamMultiplayerPeer"):
			return false
		var res: Dictionary = Engine.get_singleton("Steam").steamInitEx(app_id_, true)
		_inited = int(res.get("status", 1)) == 0
		return _inited

	## Steam инициализируется один раз на процесс. Повторный вызов безвреден,
	## но лишний: статус кладём в статическое поле.
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

	## Общая часть: инициализация плюс сам peer с включённым релеем.
	##
	## Релей Valve и есть то, ради чего всё затевалось: он проводит соединение
	## через свои серверы, и проброс портов перестаёт быть нужен.
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

	## address — SteamID хоста строкой. Ни адреса, ни порта у Steam нет:
	## соединение адресуется идентификатором игрока.
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

	## Колбэки Steam качаются вручную: без этого P2P молчит.
	static func pump() -> void:
		if _inited and Engine.has_singleton("Steam"):
			Engine.get_singleton("Steam").run_callbacks()
