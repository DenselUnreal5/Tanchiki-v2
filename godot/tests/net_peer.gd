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

func _run_host() -> void:
	Net.my_name = "Хост"
	_check(Net.host_game(), "порт открыт")
	var wait_started := Time.get_ticks_msec()
	while Net.lobby.size() < 2 and Time.get_ticks_msec() - wait_started < 15000:
		await _frames(1)
	_check(Net.lobby.size() >= 2, "клиент подключился (в лобби %d)" % Net.lobby.size())
	if Net.lobby.size() < 2:
		return

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["difficulty"] = "medium"
	game.ui.settings["level"] = 1
	game.ui.settings["weather"] = "storm"
	game.ui.settings["location"] = "jungle"

	Net.host_begin_countdown()
	var cd_started := Time.get_ticks_msec()
	while Net.countdown_left != 0 and Time.get_ticks_msec() - cd_started < 8000:
		await _frames(1)
	_check(Net.countdown_left == 0, "отсчёт хоста дошёл до нуля")
	if Net.countdown_left != 0:
		return

	game.start_match()
	_dismiss_perks()
	_check(game.world != null, "мир создан")
	_check(game.remote_players.size() == 1, "сетевой игрок заведён")

	var remote_tank_ok := false
	for t in game.world.tanks:
		if t.owner_peer != 0 and t.owner_peer != multiplayer.get_unique_id():
			remote_tank_ok = true
	_check(remote_tank_ok, "танк клиента есть в мире хоста")

	_check(Net.stat_tank_spawn_out >= 2,
		"host_tank_spawned реально ушёл при спавне игроков (%d раз)" % Net.stat_tank_spawn_out)

	print("  карта хоста до боя: %s" % _map_hash(game.world.map))
	await _frames(420)
	_check(game.world.tick > 200, "партия крутится (тик %d)" % game.world.tick)
	print("  танков: %d, пуль: %d" % [game.world.tanks.size(), game.world.bullets.size()])

	game.pause()
	await _frames(60)
	print("  карта хоста после боя: %s" % _map_hash(game.world.map))
	for i in 6:
		Net.host_event("mapsum", {"h": game.world.map.checksum()})
		await _frames(30)
	await _frames(120)

func _run_client() -> void:
	Net.my_name = "Клиент"
	_check(Net.join_game("127.0.0.1"), "подключение начато")

	var lobby_wait_started := Time.get_ticks_msec()
	while Net.lobby.size() < 2 and Time.get_ticks_msec() - lobby_wait_started < 15000:
		await _frames(1)
	_check(Net.lobby.size() >= 2, "клиент видит обоих в лобби (у себя %d)" % Net.lobby.size())

	var wait_started := Time.get_ticks_msec()
	while game.world == null and Time.get_ticks_msec() - wait_started < 12000:
		await _frames(1)
	_check(game.world != null, "хост объявил партию, мир собран")
	if game.world == null:
		return
	_dismiss_perks()

	_check(game.world.puppet, "мир клиента — марионетка (сам ничего не считает)")
	print("  карта клиента до боя: %s" % _map_hash(game.world.map))

	var predict_guard_started := Time.get_ticks_msec()
	while (game.players.is_empty() or game.players[0].tank == null
			or game._last_reconciled_tick < 0) and Time.get_ticks_msec() - predict_guard_started < 8000:
		await _frames(1)
	if not game.players.is_empty() and game.players[0].tank != null and game._last_reconciled_tick >= 0:
		await _check_prediction(game.players[0].tank)
	else:
		_check(false, "дождались первой сверки своего танка перед проверкой предсказания")

	await _frames(420)
	await _frames(330)
	print("  карта клиента после боя: %s" % _map_hash(game.world.map))
	print("  сверок карты: %d, расхождений: %d" % [game.net_sums, game.net_desyncs])
	_check(game.net_sums > 0, "сверка отпечатка карты работает")
	print("  последняя сверка: свой %08x, хоста %08x"
		% [game.net_last_mine, game.net_last_theirs])
	_check(game.net_last_mine == game.net_last_theirs,
		"карта клиента совпала с хостовой")
	_check(game.world.tanks.size() > 0, "состав пришёл: танков %d" % game.world.tanks.size())

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

func _check_prediction(mine: Tank) -> void:
	var scripted := ScriptedScheme.new()
	game.players[0].scheme = scripted
	var before := Vector2(mine.x, mine.y)
	var tick_before: int = game._last_reconciled_tick
	scripted.cmd = {"mx": 1.0, "my": 0.0, "ax": mine.x + 100.0, "ay": mine.y,
		"fire": false, "mine": false, "dash": false, "airstrike": false, "ability": false}
	var tick_before_move: int = game.world.tick
	var tick_guard := 0
	while int(game.world.tick) <= tick_before_move and tick_guard < 60:
		tick_guard += 1
		await _frames(1)
	var delta := Vector2(mine.x, mine.y) - before
	_check(delta.length() > 0.01,
		"предсказание сдвигает свой танк в тот же тик, не дожидаясь снапшота (Δ=%.3f)" % delta.length())

	var wait_started := Time.get_ticks_msec()
	while game._last_reconciled_tick <= tick_before and Time.get_ticks_msec() - wait_started < 8000:
		await _frames(1)
	var last_reconciled: int = game._last_reconciled_tick
	var reconciled := last_reconciled > tick_before
	_check(reconciled, "пришла новая сверка после включения движения")
	if reconciled:
		var auth := Net.latest_snapshot_tank(mine.net_id)
		var err := Vector2(mine.x - float(auth["x"]), mine.y - float(auth["y"])).length()
		_check(err < 40.0,
			"локальная позиция близка к авторитетной после сверки (Δ=%.1f)" % err)
	scripted.cmd = Ctl.empty_command()

class ScriptedScheme extends RefCounted:
	var cmd: Dictionary = {}
	func read_command(_player) -> Dictionary:
		return cmd

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
