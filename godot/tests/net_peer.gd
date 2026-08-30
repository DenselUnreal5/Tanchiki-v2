# ============================================================================
# net_peer.gd — интеграционная проверка сетевой партии.
#
# Запускается двумя процессами: один хостом, второй клиентом. Один процесс
# тут не годится — высокоуровневая сеть Godot живёт на дереве сцены, и двух
# независимых пиров в одном дереве не сделать.
#
#   godot --headless --path . tests/net_peer.tscn -- host
#   godot --headless --path . tests/net_peer.tscn -- client
#
# Обе стороны печатают отпечаток карты и сводку состояния. Совпадение
# отпечатков доказывает, что карта собралась одинаково по одному seed —
# именно ради этого карта и не передаётся по сети.
# ============================================================================
extends Node

var game: Node
var failures := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var role := String(args[0]) if args.size() > 0 else "host"
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(3)

	if role == "host":
		await _run_host()
	else:
		await _run_client()

	print("=== %s ЗАВЕРШЁН, проблем: %d ===" % [role.to_upper(), failures])
	Net.leave()
	await _frames(2)
	get_tree().quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------- хост
func _run_host() -> void:
	Net.my_name = "Хост"
	_check(Net.host_game(), "порт открыт")
	# Ждём клиента.
	var guard := 0
	while Net.lobby.size() < 2 and guard < 900:
		guard += 1
		await _frames(1)
	_check(Net.lobby.size() >= 2, "клиент подключился (в лобби %d)" % Net.lobby.size())
	if Net.lobby.size() < 2:
		return

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["difficulty"] = "medium"
	game.ui.settings["level"] = 1
	game.start_match()
	_dismiss_perks()
	_check(game.world != null, "мир создан")
	_check(game.remote_players.size() == 1, "сетевой игрок заведён")

	# Танк сетевого игрока обязан существовать в мире хоста.
	var remote_tank_ok := false
	for t in game.world.tanks:
		if t.owner_peer != 0 and t.owner_peer != multiplayer.get_unique_id():
			remote_tank_ok = true
	_check(remote_tank_ok, "танк клиента есть в мире хоста")

	# Отпечаток снимается дважды: до боя он проверяет, что карта собралась
	# одинаково по seed, после боя — что разрушения доехали до клиента.
	print("  карта хоста до боя: %s" % _map_hash(game.world.map))
	await _frames(420)
	_check(game.world.tick > 200, "партия крутится (тик %d)" % game.world.tick)
	print("  танков: %d, пуль: %d" % [game.world.tanks.size(), game.world.bullets.size()])

	# Дальше мир замирает: сверять карты в движении бессмысленно — хост
	# уйдёт вперёд на те разрушения, которые клиент ещё не получил.
	game.pause()
	await _frames(60)
	# Последний отпечаток отправляем принудительно: клиент сверит его
	# со своим и, если надо, попросит карту целиком. Мир при этом уже
	# замер, поэтому сверка честная — обе стороны на одном состоянии.
	# Отпечаток замершего мира шлём несколько раз подряд: клиент сверяется
	# по последнему пришедшему, и так он гарантированно попадёт на тот,
	# что снят с уже неподвижной карты.
	print("  карта хоста после боя: %s" % _map_hash(game.world.map))
	for i in 6:
		Net.host_event("mapsum", {"h": game.world.map.checksum()})
		await _frames(30)
	await _frames(120)

# ----------------------------------------------------------------- клиент
func _run_client() -> void:
	Net.my_name = "Клиент"
	_check(Net.join_game("127.0.0.1"), "подключение начато")

	var guard := 0
	while game.world == null and guard < 1200:
		guard += 1
		await _frames(1)
	_check(game.world != null, "хост объявил партию, мир собран")
	if game.world == null:
		return
	_dismiss_perks()

	_check(game.world.puppet, "мир клиента — марионетка (сам ничего не считает)")
	print("  карта клиента до боя: %s" % _map_hash(game.world.map))

	await _frames(420)
	# Ждём финальную сверку от замершего хоста. Сравнивать раньше нельзя:
	# хост ушёл бы вперёд на те разрушения, которые к нам ещё не доехали,
	# и тест ловил бы задержку пакета вместо расхождения.
	# Ждём, пока хост замрёт и отстреляется финальными отпечатками.
	await _frames(330)
	print("  карта клиента после боя: %s" % _map_hash(game.world.map))
	print("  сверок карты: %d, расхождений: %d" % [game.net_sums, game.net_desyncs])
	_check(game.net_sums > 0, "сверка отпечатка карты работает")
	# Главная проверка: последняя сверка снята с неподвижной карты у обеих
	# сторон, поэтому отпечатки обязаны совпасть.
	print("  последняя сверка: свой %08x, хоста %08x"
		% [game.net_last_mine, game.net_last_theirs])
	_check(game.net_last_mine == game.net_last_theirs,
		"карта клиента совпала с хостовой")
	_check(game.world.tanks.size() > 0, "состав пришёл: танков %d" % game.world.tanks.size())

	# Состояние должно двигаться: если снапшоты не доходят, координаты
	# останутся нулевыми, а мир — застывшим.
	var moved := false
	for t in game.world.tanks:
		if t.x > 1.0 or t.y > 1.0:
			moved = true
	_check(moved, "танки получили координаты от хоста")

	var mine = null
	for t in game.world.tanks:
		if t.owner_peer == multiplayer.get_unique_id():
			mine = t
	_check(mine != null, "свой танк найден и привязан к камере")
	_check(game.players[0].tank == mine, "HUD и камера смотрят на свой танк")

# ------------------------------------------------------------------ утилиты
## Отпечаток карты: по нему сверяется, что генератор дал одно и то же.
func _map_hash(map: GameMap) -> String:
	var h := 5381
	for i in map.tiles.size():
		h = ((h * 33) ^ map.tiles[i]) & 0x7FFFFFFF
	return "%dx%d/%08x" % [map.cols, map.rows, h]

func _dismiss_perks() -> void:
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
