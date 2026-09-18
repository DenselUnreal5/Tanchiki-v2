# ============================================================================
# net_pause_keepalive.gd — хост на паузе (или в выборе перка) не должен
# выбрасывать клиента: раньше через NET_DEAD_MSEC (8 с) тишины клиент выходил
# в меню, потому что замерший мир не шлёт снапшоты.
#
# Запускается двумя процессами:
#   godot --headless --path . res://tests/net_pause_keepalive.tscn -- host [nokeep]
#   godot --headless --path . res://tests/net_pause_keepalive.tscn -- client
# «nokeep» отключает пульс у хоста — тест обязан тогда упасть (контроль).
# ============================================================================
extends Node

const PORT := 8151
const PAUSE_SEC := 11.0

var game: Node
var failures := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var role := String(args[0]) if args.size() > 0 else "host"
	var nokeep := args.has("nokeep")
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(3)
	if role == "host":
		await _run_host(nokeep)
	else:
		await _run_client()
	print("=== %s ЗАВЕРШЁН, проблем: %d ===" % [role.to_upper(), failures])
	Net.leave()
	await _frames(2)
	get_tree().quit(1 if failures > 0 else 0)

func _run_host(nokeep: bool) -> void:
	_check(Net.host_game(PORT), "порт открыт")
	var t0 := Time.get_ticks_msec()
	while Net.lobby.size() < 2 and Time.get_ticks_msec() - t0 < 20000:
		await _frames(1)
	_check(Net.lobby.size() >= 2, "клиент подключился")
	if Net.lobby.size() < 2:
		return
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["difficulty"] = "easy"
	game.ui.settings["level"] = 1
	Net.host_begin_countdown()
	t0 = Time.get_ticks_msec()
	while Net.countdown_left != 0 and Time.get_ticks_msec() - t0 < 10000:
		await _frames(1)
	game.start_match()
	_dismiss_perks()
	await _frames(120)
	var tick_before: int = game.world.tick
	game.pause()
	_check(game.state == "paused", "хост на паузе")
	if nokeep:
		game._keepalive_msec = 1 << 60  # контроль: пульс отключён
	var p0 := Time.get_ticks_msec()
	# Лобби проверяем на 9-й секунде — пока клиент ещё в своём окне ожидания
	# (позже он сам выйдет по таймеру и лобби по праву опустеет).
	while Time.get_ticks_msec() - p0 < 9000:
		await _frames(1)
	_check(Net.lobby.size() >= 2, "клиент всё ещё в лобби хоста (9 с паузы, > NET_DEAD 8 с)")
	while Time.get_ticks_msec() - p0 < int(PAUSE_SEC * 1000.0):
		await _frames(1)
	_check(game.state == "paused", "хост всё ещё на паузе")
	_check(game.world.tick == tick_before or game.world.tick - tick_before < 3,
		"мир на паузе не шагает (тик %d -> %d)" % [tick_before, game.world.tick])

func _run_client() -> void:
	_check(Net.join_game("127.0.0.1", PORT), "подключение начато")
	var t0 := Time.get_ticks_msec()
	while game.world == null and Time.get_ticks_msec() - t0 < 40000:
		await _frames(1)
	_check(game.world != null, "мир клиента собран")
	if game.world == null:
		return
	_dismiss_perks()
	# Клиент живёт, пока хост стоит на паузе PAUSE_SEC секунд.
	var w0 := Time.get_ticks_msec()
	var kicked := false
	while Time.get_ticks_msec() - w0 < int((PAUSE_SEC + 1.0) * 1000.0):
		await _frames(1)
		if game.world == null or Net.role != "client":
			kicked = true
			break
	_check(not kicked, "клиента не выбросило в меню за %.0f с паузы хоста" % PAUSE_SEC)
	if not kicked:
		_check(int(Net.stats()["stale_msec"]) < 2000,
			"снапшоты продолжают приходить (тишина %d мс)" % int(Net.stats()["stale_msec"]))

func _dismiss_perks() -> void:
	var g := 0
	while game.state == "perk" and g < 20:
		g += 1
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
