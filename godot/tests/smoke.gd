# ============================================================================
# smoke.gd — дымовой тест: прогоняет все четыре режима без участия человека.
#
# Запуск:
#   godot --headless --path godot tests/smoke.tscn
#
# Что проверяется: генерация уровня, спавн, боты с A*, урон, режимные правила,
# сборка HUD и отрисовка. Любая ошибка времени выполнения всплывёт в консоли.
# ============================================================================
extends Node

## Сколько логических тиков прогонять на каждый режим (60 тиков = 1 сек).
const TICKS_PER_MODE := 3600

## autopilot — вместо человека танком управляет обычный «мозг» бота.
## Это эталонный игрок средней руки: по нему видно, насколько режим тяжёлый,
## тогда как неподвижный болванчик проигрывает всегда и ничего не показывает.
const CASES := [
	{"mode": "ffa", "game_type": "single", "difficulty": "medium"},
	{"mode": "ffa", "game_type": "hotseat", "difficulty": "hard"},
	{"mode": "ctf", "game_type": "single", "difficulty": "medium", "autopilot": true, "ticks": 20000},
	{"mode": "koth", "game_type": "single", "difficulty": "easy"},
	{"mode": "defense", "game_type": "single", "difficulty": "medium", "autopilot": true, "ticks": 14000},
	# Отдельный прогон под активные способности: перк выдаётся принудительно,
	# потому что автопилот перков не выбирает.
	{"mode": "ffa", "game_type": "single", "difficulty": "medium", "ticks": 3600,
		"autopilot": true, "perk": "shockwave"},
]

## Схема управления «как бот»: подставляется вместо мыши и клавиатуры.
class Autopilot:
	var brain: BotBrain
	var world_ref
	var use_airstrike := false

	func _init(rng: Rng, airstrike: bool) -> void:
		brain = BotBrain.new({"accuracy": 0.8, "react_time": 12, "rng": rng})
		use_airstrike = airstrike

	func apply(tank: Tank, player, world) -> void:
		brain.update(tank, world)
		# Способность жмётся сразу, как только откатилась. В обычных
		# случаях автопилот перков не берёт вовсе (см. _dismiss_perk_dialogs),
		# поэтому срабатывает это только в случае с выданным перком.
		if tank.ability_id != "" and tank.ability_cd <= 0:
			tank.use_ability(world)
		if use_airstrike and world.airstrike_cooldown <= 0:
			world.trigger_airstrike(player)

var game: Node

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var failures := 0
	for case in CASES:
		failures += await _run_case(case)

	print("=== ДЫМОВОЙ ТЕСТ ЗАВЕРШЁН, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _run_case(case: Dictionary) -> int:
	game.ui.settings["mode"] = case["mode"]
	game.ui.settings["game_type"] = case["game_type"]
	game.ui.settings["difficulty"] = case["difficulty"]
	game.ui.settings["level"] = 1
	game.start_match()
	_dismiss_perk_dialogs()

	if bool(case.get("autopilot", false)):
		for p in game.players:
			p.scheme = Autopilot.new(game.world.rng, case["mode"] == "defense")
	var forced_perk := String(case.get("perk", ""))
	if forced_perk != "":
		for p in game.players:
			p.perk_ids.append(forced_perk)
			if p.tank != null:
				p.tank.recompute()

	var world: World = game.world
	if world == null:
		print("ОШИБКА [%s]: мир не создан" % case["mode"])
		return 1

	# Режимные счётчики: как часто дерутся за флаг и сколько врагов приходит.
	# Словарь, а не два int: лямбда захватывает локальные переменные по
	# значению, и увеличение обычного счётчика внутри неё пропало бы.
	# Счётчик способностей: лямбда захватывает переменные по значению,
	# поэтому копится он в словаре, а не в int.
	var ability_stats := {"uses": 0}
	world.stat.connect(func(key: String, value: int, _kind: String):
		if key == "abilityUses":
			ability_stats["uses"] += value)

	var flag_stats := {"taken": 0, "returned": 0}
	world.flag_event.connect(func(type: String, _flag, _tank):
		if type == "taken":
			flag_stats["taken"] += 1
		elif type == "returned":
			flag_stats["returned"] += 1)

	# Считаем пройденный ботами путь: «живые, но неподвижные» боты — самая
	# коварная регрессия, по одному лишь числу выживших её не видно.
	var travelled := {}
	var last_pos := {}
	for t in world.tanks:
		travelled[t.id] = 0.0
		last_pos[t.id] = Vector2(t.x, t.y)

	GameMap.stat_rect_calls = 0
	GameMap.stat_los_calls = 0
	Pathfinding.stat_calls = 0
	Pathfinding.stat_expanded = 0
	var ticks := 0
	var limit: int = int(case.get("ticks", TICKS_PER_MODE))
	var t0 := Time.get_ticks_usec()
	while ticks < limit and not world.finished_flag:
		world.step()
		game._update_floaters()
		ticks += 1
		if ticks % 30 == 0:
			for t in world.tanks:
				if not travelled.has(t.id):
					travelled[t.id] = 0.0
					last_pos[t.id] = Vector2(t.x, t.y)
				var now := Vector2(t.x, t.y)
				travelled[t.id] = float(travelled[t.id]) + now.distance_to(last_pos[t.id])
				last_pos[t.id] = now
		# Уровень в партии повышается — закрываем окно выбора перка.
		var pending := false
		for p in game.players:
			if p.pending_level_ups > 0:
				pending = true
				break
		if pending:
			game._process_perk_queue()
			_dismiss_perk_dialogs()

	var problems := 0
	var alive := 0
	for t in world.tanks:
		if t.alive:
			alive += 1
	if world.tanks.is_empty():
		print("ОШИБКА [%s]: не заспавнено ни одного танка" % case["mode"])
		problems += 1
	# Танк не должен уезжать за пределы карты.
	for t in world.tanks:
		if t.x < 0.0 or t.x > world.map.width or t.y < 0.0 or t.y > world.map.height:
			print("ОШИБКА [%s]: танк %s вне карты (%.1f, %.1f)" % [case["mode"], t.name, t.x, t.y])
			problems += 1
			break

	var bot_travel := 0.0
	var bot_count := 0
	var blocked := 0
	var worst_blocked := 0
	var stalls := 0
	var worst_stall := 0
	var frozen := 0
	var worst_frozen := 0
	var worst_info := ""
	for t in world.tanks:
		if t.is_bot:
			bot_count += 1
			bot_travel += float(travelled.get(t.id, 0.0))
			blocked += t.blocked_ticks
			worst_blocked = maxi(worst_blocked, t.blocked_ticks)
			stalls += t.worst_stall
			worst_stall = maxi(worst_stall, t.worst_stall)
			if t.brain != null:
				frozen += t.brain.worst_frozen
				if t.brain.worst_frozen > worst_frozen:
					worst_frozen = t.brain.worst_frozen
					worst_info = t.brain.worst_frozen_info
	var avg_travel := bot_travel / maxf(1.0, float(bot_count))
	if avg_travel < 100.0:
		print("ОШИБКА [%s]: боты почти не двигались (в среднем %.0f px)" % [case["mode"], avg_travel])
		problems += 1

	# Несколько живых кадров: так отрабатывают _draw мира, миникарта и HUD.
	for i in 8:
		await get_tree().process_frame

	# Стоимость одного логического шага: бюджет кадра при 60 Гц — 16.7 мс,
	# и симуляция должна занимать в нём малую долю.
	var ms_per_tick := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, float(ticks))

	# Доля времени, которое бот провёл упираясь в стену, — главный показатель
	# качества навигации.
	var wall_share := 100.0 * float(blocked) / maxf(1.0, float(bot_count * ticks))
	var worst_share := 100.0 * float(worst_blocked) / maxf(1.0, float(ticks))
	var avg_stall := float(stalls) / maxf(1.0, float(bot_count))
	var avg_frozen := float(frozen) / maxf(1.0, float(bot_count))
	if worst_frozen > 180:
		print("ОШИБКА [%s]: бот простоял %d тиков подряд, хотя цель далеко (%s)"
			% [case["mode"], worst_frozen, worst_info])
		problems += 1
	elif worst_frozen > 60:
		print("    самый долгий простой: %d тиков (%s)" % [worst_frozen, worst_info])
	print("[%s / %s] тиков: %d, живых %d/%d, путь: %.0f px, в стену: %.1f%%, упор: макс %d, замер: сред. %.0f / макс %d, шаг: %.2f мс, финиш: %s"
		% [case["mode"], case["game_type"], ticks, alive, world.tanks.size(),
			avg_travel, wall_share, worst_stall, avg_frozen, worst_frozen,
			ms_per_tick, str(world.finished_flag)])
	print("    за тик: проверок стен %.0f, лучей видимости %.0f, A* %.2f (узлов %.0f)" % [
		float(GameMap.stat_rect_calls) / float(ticks),
		float(GameMap.stat_los_calls) / float(ticks),
		float(Pathfinding.stat_calls) / float(ticks),
		float(Pathfinding.stat_expanded) / float(ticks)])
	# Темп стрельбы игрока — то, ради чего вводился перегрев ствола.
	var pt = game.players[0].tank
	if pt != null:
		var minutes: float = float(ticks) / 60.0 / 60.0
		print("    игрок: выстрелов %d (%.2f/с), перегревов %d, фрагов %d"
			% [pt.shots_fired, float(pt.shots_fired) / (float(ticks) / 60.0),
				pt.overheats, pt.kills])

	# Итоговые счётчики режима.
	var kills := 0
	for t in world.tanks:
		kills += t.kills
	if case["mode"] == "ctf":
		print("    флаг: захватов %d:%d, подобран %d раз, возвращён %d, убийств %d"
			% [world.team_score["player"], world.team_score["enemy"],
				flag_stats["taken"], flag_stats["returned"], kills])
	elif case["mode"] == "defense":
		var base_hp := int(world.base["hp"]) if world.base != null else 0
		print("    оборона: волна %d/%d, база %d/%d HP, врагов выпущено %d, убито %d, время %.0f с"
			% [world.wave, Cfg.MODES["defense"]["waves"], base_hp,
				int(Cfg.MODES["defense"]["base_hp"]),
				world.tanks.size() - game.players.size(), kills, float(ticks) / 60.0])
	else:
		print("    убийств: %d, способность применена %d раз" % [kills, int(ability_stats["uses"])])
	if world.finished_flag:
		print("    итог: %s — %s" % [world.result["winner_name"], world.result["reason"]])

	game.to_menu()
	return problems

## Закрывает все окна выбора перка, ничего не выбирая.
func _dismiss_perk_dialogs() -> void:
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
