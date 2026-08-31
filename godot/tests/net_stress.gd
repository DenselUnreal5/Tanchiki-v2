# ============================================================================
# net_stress.gd — сетевая партия в плохих условиях.
#
# Обычный net_peer проверяет, что связь вообще работает. Здесь проверяется
# то, ради чего netcode и пишут: партия под потерями пакетов, задержкой
# и обрывом посреди боя.
#
#   godot --headless --path . tests/net_stress.tscn -- host
#   godot --headless --path . tests/net_stress.tscn -- client
#
# Условия задаются обеим сторонам одинаково: хост портит снапшоты,
# клиент — свой ввод.
# ============================================================================
extends Node

## Четверть пакетов в никуда и 120 мс в одну сторону — заметно хуже, чем
## бывает на домашнем интернете, и ровно то, на чём ломается наивный netcode.
const LOSS := 0.25
const LAG_MSEC := 120.0

var game: Node
var failures := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var role := String(args[0]) if args.size() > 0 else "host"
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(3)

	Net.debug_loss = LOSS
	Net.debug_lag_msec = LAG_MSEC

	if role == "host":
		await _run_host()
	else:
		await _run_client()

	print("=== СТРЕСС %s ЗАВЕРШЁН, проблем: %d ===" % [role.to_upper(), failures])
	Net.leave()
	await _frames(2)
	get_tree().quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------- хост
func _run_host() -> void:
	Net.my_name = "Хост"
	_check(Net.host_game(), "порт открыт")
	var guard := 0
	while Net.lobby.size() < 2 and guard < 900:
		guard += 1
		await _frames(1)
	if not _check(Net.lobby.size() >= 2, "клиент подключился"):
		return

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	_dismiss_perks()

	var remote_tank: Tank = null
	for t in game.world.tanks:
		if t.owner_peer != 0 and t.owner_peer != multiplayer.get_unique_id():
			remote_tank = t
	_check(remote_tank != null, "танк клиента есть в мире")

	await _frames(420)
	var st := Net.stats()
	print("  хост: снапшотов отправлено %d, ввода принято %d, опоздавшего %d"
		% [st["snap_out"], st["cmd_in"], st["cmd_late"]])
	_check(int(st["cmd_in"]) > 0, "ввод клиента доходит сквозь потери")

	# ---- обрыв: клиент уходит, хост обязан прибраться ---------------------
	print("  ждём обрыва связи с клиентом…")
	var wait := 0
	while Net.lobby.size() > 1 and wait < 900:
		wait += 1
		await _frames(1)
	_check(Net.lobby.size() == 1, "хост заметил уход клиента")
	await _frames(60)

	_check(game.remote_players.is_empty(), "игрок убран из партии")
	_check(Net.command_of(2).is_empty(), "ввод отключившегося стёрт")
	if remote_tank != null:
		# Танк-призрак: до правки он ехал по последней команде до конца
		# партии. Проверять сдвиг оказалось неверно — мёртвый корпус
		# всё равно расталкивает физика. Правильная проверка: его вообще
		# нет в мире.
		_check(not game.world.tanks.has(remote_tank), "танк ушедшего убран из мира")

# ----------------------------------------------------------------- клиент
func _run_client() -> void:
	Net.my_name = "Клиент"
	_check(Net.join_game("127.0.0.1"), "подключение начато")
	var guard := 0
	while game.world == null and guard < 1200:
		guard += 1
		await _frames(1)
	if not _check(game.world != null, "партия объявлена"):
		return
	_dismiss_perks()

	# Копим статистику под потерями.
	await _frames(420)
	var st := Net.stats()
	var total: int = int(st["snap_in"]) + int(st["snap_lost"])
	var loss_pct := 0.0
	if total > 0:
		loss_pct = float(st["snap_lost"]) * 100.0 / float(total)
	print("  клиент: снапшотов принято %d, потеряно %d (%.0f%%), опоздавших %d, оборот %.0f мс"
		% [st["snap_in"], st["snap_lost"], loss_pct, st["snap_late"], st["rtt"]])

	_check(int(st["snap_in"]) > 30, "снапшоты доходят несмотря на потери")
	_check(int(st["snap_lost"]) > 0, "потери замечены и посчитаны")
	_check(loss_pct > 10.0 and loss_pct < 45.0,
		"измеренные потери близки к заданным 25%% (вышло %.0f%%)" % loss_pct)

	# Главное: картинка не встала. Танки должны двигаться, несмотря на дыры.
	var before := _positions()
	await _frames(90)
	var moved := 0
	var after := _positions()
	for id in after.keys():
		if before.has(id) and before[id].distance_to(after[id]) > 2.0:
			moved += 1
	_check(moved > 0, "мир продолжает двигаться под потерями (танков сдвинулось %d)" % moved)

	# Уходим посреди партии — хост это проверит у себя.
	print("  клиент отключается посреди партии")
	Net.leave()
	await _frames(120)
	_check(game.state == "menu", "клиент вернулся в меню после разрыва")

func _positions() -> Dictionary:
	var out := {}
	if game.world == null:
		return out
	for t in game.world.tanks:
		out[t.net_id] = Vector2(t.x, t.y)
	return out

func _dismiss_perks() -> void:
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

func _check(ok: bool, what: String) -> bool:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
	return ok

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
