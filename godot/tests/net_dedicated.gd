# ============================================================================
# net_dedicated.gd — выделенный сервер без своего игрока: проверка боевого
# пути запуска, а не прямых вызовов Net.
#
# В отличие от net_peer.gd (который сам зовёт Net.host_game()/Net.join_game()
# из скрипта), здесь роль и все параметры приходят ТОЛЬКО из настоящих флагов
# командной строки — тест проверяет именно то, что делает game.gd::_ready()
# при боевом запуске: сам разбирает --server/--connect=, сам поднимает
# ENet-хост, сам стартует партию по числу подключившихся, без единого клика
# «Начать партию» и без ручного Net.host_begin_countdown() из теста.
#
# Запускается двумя процессами:
#   godot --headless --path . tests/net_dedicated.tscn --server --players=1 --port=8137
#   godot --headless --path . tests/net_dedicated.tscn --connect=127.0.0.1:8137
#
# Флаги --server/--port=/--players=/--connect= движку не знакомы, поэтому он
# просто передаёт их дальше в OS.get_cmdline_args() как есть — тот же приём,
# каким Steam передаёт «+connect_lobby <id>» (см. Net._parse_connect_lobby()),
# и отдельный «--» перед ними не нужен.
# ============================================================================
extends Node

var game: Node
var failures := 0

func _ready() -> void:
	var cli := Cli.parse()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(3)

	if bool(cli["server"]):
		await _run_server()
	elif String(cli["connect_host"]) != "":
		await _run_client()
	else:
		push_error("[net_dedicated] запустите с --server --players=1 --port=N или --connect=host:port")
		get_tree().quit(1)
		return

	print("=== ЗАВЕРШЁН, проблем: %d ===" % failures)
	Net.leave()
	await _frames(2)
	get_tree().quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------- сервер
func _run_server() -> void:
	# game._ready() уже должен был разобрать флаги и поднять хост сам —
	# ничего из этого тест не делает руками.
	_check(Net.role == "host", "сервер поднял ENet-хост")
	_check(Net.dedicated, "Net.dedicated выставлен")
	_check(game.players.is_empty(), "у сервера нет локального игрока с самого начала")

	# Партия обязана стартовать сама, как только подключится нужное число
	# гостей — тест ни разу не зовёт Net.host_begin_countdown(). Ждём по
	# настенным часам, а не по числу кадров: до старта идёт реальный
	# пятисекундный отсчёт (SceneTreeTimer), а headless крутит кадры то
	# быстрее, то медленнее 60 Гц — фиксированный бюджет кадров под нагрузкой
	# кончается раньше, чем набегают реальные пять секунд (см. net_peer.gd).
	var wait_started := Time.get_ticks_msec()
	while game.world == null and Time.get_ticks_msec() - wait_started < 12000:
		await _frames(1)
	_check(game.world != null, "партия стартовала сама, по числу игроков")
	if game.world == null:
		return

	_check(game.players.is_empty(), "локальных игроков всё ещё нет после старта")
	_check(game.remote_players.size() == 1, "сетевой игрок заведён")
	# Пустые players => _rebuild_views() не создал ни одного SubViewport —
	# рендер и правда пропущен, а не просто незаметен в headless.
	_check(game._views.is_empty(), "вьюпортов не создано — рендер пропущен")

	await _frames(180)
	_check(game.world.tick > 60, "партия крутится (тик %d)" % game.world.tick)

# ------------------------------------------------------------------ клиент
func _run_client() -> void:
	# --connect= обязан сам открыть экран сети — без похода в «Другие способы».
	_check(game.ui.is_net_open, "экран сети открылся сам")

	# То же самое: ждём по настенным часам, а не по числу кадров (см.
	# комментарий в _run_server()).
	var wait_started := Time.get_ticks_msec()
	while game.world == null and Time.get_ticks_msec() - wait_started < 12000:
		await _frames(1)
	_check(game.world != null, "сервер объявил партию, мир собран")
	if game.world == null:
		return
	_dismiss_perks()
	_check(game.world.puppet, "мир клиента — марионетка")

	await _frames(180)
	var mine = null
	for t in game.world.tanks:
		if t.owner_peer == multiplayer.get_unique_id():
			mine = t
	_check(mine != null, "свой танк найден в составе")
	if mine != null:
		_check(mine.x > 1.0 or mine.y > 1.0, "танк получил координаты от сервера")
	_check(game.players[0].tank == mine, "HUD и камера смотрят на свой танк")

# ------------------------------------------------------------------ утилиты
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
