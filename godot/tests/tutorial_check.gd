extends Node

const REQUIRED := {
	1: {"X": 1}, 2: {"T": 2}, 3: {"E": 1}, 4: {"G": 1}, 5: {"T": 1, "O": 2},
	6: {"X": 1}, 7: {"M": 1}, 8: {"T": 1}, 9: {"T": 1}, 10: {"E": 1}, 11: {"K": 1},
}

var failures := 0
var log_lines := []

func log_msg(msg: String) -> void:
	print(msg)
	log_lines.append(msg)
	var f := FileAccess.open("user://tutorial_check.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines))
		f.flush()
		f.close()

func _check(ok: bool, what: String) -> void:
	if ok:
		log_msg("  ок: " + what)
	else:
		log_msg("ОШИБКА: " + what)
		failures += 1

func _ready() -> void:
	log_msg("--- ПРОВЕРКА ОБУЧЕНИЯ ---")
	_check_layouts()
	_check_full_run()
	_check_turret_rhythm()
	_check_failures()
	_check_boss_loss()
	Prof.check_achievements()
	_check(Prof.achievements.has("tutorial_master"), "достижение «Курс молодого бойца» открыто")
	log_msg("=== ПРОВЕРКА ОБУЧЕНИЯ ЗАВЕРШЕНА, ошибок: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _new_world() -> World:
	var level := LevelGen.generate(1, "tutorial", 4242, "city")
	var player = PlayerState.new(0, "Новичок", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	player.map = level["map"]
	return World.new({
		"map": level["map"], "level": level, "mode": "tutorial",
		"difficulty": "medium", "players": [player], "player_level": 1,
		"weather": "clear", "daytime": "day", "rng_seed": 4242,
	})

func _steps(world: World, n: int) -> void:
	for i in n:
		world.step()

func _check_layouts() -> void:
	log_msg("[1/4] Полигоны")
	for stage in range(1, Tutorial.TOTAL + 1):
		var rows: Array = TutorialLayouts.layout(stage)
		var ok_size := rows.size() == TutorialLayouts.ROWS
		var counts := {}
		for r in rows.size():
			var line: String = rows[r]
			if line.length() != TutorialLayouts.COLS:
				ok_size = false
			for c in line.length():
				var ch := line[c]
				counts[ch] = int(counts.get(ch, 0)) + 1
				var border := r == 0 or r == rows.size() - 1 or c == 0 or c == line.length() - 1
				if border and ch != "#":
					ok_size = false
		_check(ok_size, "задание %d: полигон %dx%d с глухой рамкой" % [stage, TutorialLayouts.COLS, TutorialLayouts.ROWS])
		_check(int(counts.get("P", 0)) == 1, "задание %d: ровно один старт игрока" % stage)
		var req: Dictionary = REQUIRED[stage]
		for ch in req:
			_check(int(counts.get(ch, 0)) == int(req[ch]), "задание %d: маркеров «%s» — %d" % [stage, ch, int(req[ch])])
		if req.has("X"):
			_check(_reachable(rows), "задание %d: от старта можно доехать до контрольной точки" % stage)
	var tank_pos: Vector2 = TutorialLayouts.markers(5, "T")[0]
	var barrel_pos: Array = TutorialLayouts.markers(5, "O")
	_check(barrel_pos[0].distance_to(barrel_pos[1]) > 120.0, "задание 5: бочки не подрывают друг друга цепочкой")
	var one := _barrel_damage(barrel_pos[0].distance_to(tank_pos))
	var two := one + _barrel_damage(barrel_pos[1].distance_to(tank_pos))
	_check(one < 50.0 and two >= 50.0, "задание 5: одной бочки мало (%.0f), двух хватает (%.0f) на 50 HP" % [one, two])

func _barrel_damage(d: float) -> float:
	if d > 120.0:
		return 0.0
	return 65.0 * (1.0 - (d / 120.0) * 0.65)

func _reachable(rows: Array) -> bool:
	var start := Vector2i(-1, -1)
	var goal := Vector2i(-1, -1)
	for r in rows.size():
		var line: String = rows[r]
		for c in line.length():
			if line[c] == "P":
				start = Vector2i(c, r)
			elif line[c] == "X":
				goal = Vector2i(c, r)
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if n.y < 0 or n.y >= rows.size() or n.x < 0 or n.x >= String(rows[n.y]).length():
				continue
			var ch := String(rows[n.y])[n.x]
			if ch == "#" or ch == "B" or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return false

func _check_turret_rhythm() -> void:
	log_msg("[2b/4] Ритм турели в задании 3")
	var world := _new_world()
	var tut := world.tutorial
	tut.begin_stage(3)
	var ptank: Tank = world.players[0].tank
	ptank.spawn_protect = 0
	var turret = tut.enemy
	var seen := {}
	var shot_ticks := []
	for i in 600:
		ptank.hp = ptank.max_hp
		world.step()
		for b in world.bullets:
			if b.owner == turret and not seen.has(b):
				seen[b] = true
				shot_ticks.append(world.tick)
	var even := true
	for i in range(1, shot_ticks.size()):
		if absi(int(shot_ticks[i]) - int(shot_ticks[i - 1]) - Tutorial.TURRET_FIRE_INTERVAL) > 1:
			even = false
	_check(shot_ticks.size() >= 6, "задание 3: турель стреляет часто (%d выстрелов за 10 с)" % shot_ticks.size())
	_check(even, "задание 3: интервалы между выстрелами ровные (%s)" % str(shot_ticks))
	_check(tut.state == Tutorial.ST_PLAY and tut.stage == 3, "задание 3: игрок жив, задание продолжается")

func _pass_stage(world: World, expect_next: int) -> void:
	var tut := world.tutorial
	var stage := tut.stage
	world.step()
	_check(tut.state == Tutorial.ST_DONE, "задание %d засчитано" % stage)
	_steps(world, Tutorial.DONE_PAUSE - 1)
	_check(tut.stage == stage, "задание %d: пауза перед следующим" % stage)
	world.step()
	_check(tut.stage == expect_next and tut.state == Tutorial.ST_PLAY, "после паузы начато задание %d" % expect_next)

func _check_full_run() -> void:
	log_msg("[2/4] Прохождение всех заданий")
	var world := _new_world()
	var tut := world.tutorial
	var ptank: Tank = world.players[0].tank
	_check(tut != null and tut.stage == 1, "обучение стартует с задания 1")
	_check(int(world.get_tutorial_task_info().get("total", 0)) == Tutorial.TOTAL, "в подсказке всего %d заданий" % Tutorial.TOTAL)

	ptank.x = tut.checkpoint.x
	ptank.y = tut.checkpoint.y
	world.step()
	_check(tut.state == Tutorial.ST_PLAY, "задание 1: точка без всех клавиш W/A/S/D не засчитана")
	for k in tut.keys_used:
		tut.keys_used[k] = true
	_pass_stage(world, 2)

	for t in tut.targets:
		world.deal_damage(t, 9999.0, ptank, "bullet")
	_pass_stage(world, 3)

	ptank.spawn_protect = 0
	for i in Tutorial.DODGES_NEEDED:
		if i > 0:
			_steps(world, Tutorial.DODGE_GAP + 1)
		ptank.dash_invuln_ticks = 10
		world.deal_damage(ptank, 10.0, tut.enemy, "bullet")
	ptank.dash_invuln_ticks = 0
	_check(tut.dodges >= Tutorial.DODGES_NEEDED, "задание 3: уклонения засчитаны (%d)" % tut.dodges)
	var turret = tut.enemy
	world.step()
	var seen := {}
	for b in world.bullets:
		seen[b] = true
	var shots_after := 0
	for i in Tutorial.DONE_PAUSE - 2:
		world.step()
		for b in world.bullets:
			if b.owner == turret and not seen.has(b):
				seen[b] = true
				shots_after += 1
	_check(tut.state == Tutorial.ST_DONE and shots_after == 0, "задание 3: после выполнения турель молчит")
	world.step()
	world.step()
	_check(tut.stage == 4, "после паузы начато задание 4")

	tut.generator.discharge(world, ptank.team)
	_pass_stage(world, 5)

	for b in tut.barrels:
		b.explode(world)
	_check(not tut.targets[0].alive, "задание 5: две бочки уничтожили танк в укрытии")
	_pass_stage(world, 6)

	ptank.x = tut.checkpoint.x
	ptank.y = tut.checkpoint.y
	_pass_stage(world, 7)

	ptank.x = tut.perk_drop.x
	ptank.y = tut.perk_drop.y
	world.step()
	_check(ptank.flags.has("mines"), "задание 7: перк «Миноукладчик» подобран")
	ptank.place_mine(world)
	_pass_stage(world, 8)

	_check(ptank.cannon_id == "ice" and ptank.chassis_id == "light", "задание 8: танк ледяной")
	var ice_dummy = tut.targets[0]
	ice_dummy.apply_freeze(world, ptank, Cfg.ICE_FREEZE_TICKS)
	world.step()
	world.execute_frozen_kill(ice_dummy, ptank)
	_pass_stage(world, 9)

	_check(ptank.cannon_id == "acid" and ptank.chassis_id == "heavy", "задание 9: танк кислотный")
	world.deal_damage(tut.targets[0], 9999.0, ptank, "acid")
	_pass_stage(world, 10)

	_check(ptank.cannon_id == "standard" and ptank.chassis_id == "standard", "задание 10: танк снова стандартный")
	tut.enemy.spawn_protect = 0
	world.deal_damage(tut.enemy, 99999.0, ptank, "bullet")
	_pass_stage(world, 11)

	_check(tut.enemy != null and tut.enemy.is_boss, "задание 11: на поле босс")
	tut.enemy.spawn_protect = 0
	world.deal_damage(tut.enemy, 999999.0, ptank, "bullet")
	world.step()
	_check(world.finished_flag and bool(world.result.get("victory", false)), "победа над боссом завершает обучение")
	_check(int(Prof.stats.get("tutorialCompleted", 0)) >= 1, "статистика «обучение пройдено» записана")
	world.dispose()

func _fail_and_restart(world: World, stage: int, what: String) -> void:
	var tut := world.tutorial
	_steps(world, 2)
	_check(tut.state == Tutorial.ST_FAIL, "задание %d: %s — провал" % [stage, what])
	_steps(world, Tutorial.FAIL_PAUSE)
	var ptank: Tank = world.players[0].tank
	_check(tut.stage == stage and tut.state == Tutorial.ST_PLAY, "задание %d перезапущено" % stage)
	_check(ptank.alive and is_equal_approx(ptank.hp, ptank.max_hp), "задание %d: игрок жив с полным HP" % stage)

func _check_failures() -> void:
	log_msg("[3/4] Провал и перезапуск")
	var world := _new_world()
	var tut := world.tutorial
	var ptank: Tank = world.players[0].tank

	tut.begin_stage(3)
	var old_turret = tut.enemy
	ptank.spawn_protect = 0
	world.deal_damage(ptank, 99999.0, old_turret, "bullet")
	_fail_and_restart(world, 3, "танк уничтожен")
	_check(tut.enemy != null and tut.enemy != old_turret and tut.enemy.alive, "задание 3: турель создана заново")
	_check(tut.dodges == 0, "задание 3: счётчик уклонений сброшен")

	tut.begin_stage(5)
	for b in tut.barrels:
		b.alive = false
	_steps(world, Tutorial.BARREL_GRACE + 1)
	_fail_and_restart(world, 5, "бочки взорваны мимо")
	_check(tut.barrels.size() == 2 and tut.barrels[0].alive and tut.targets[0].alive, "задание 5: бочки и танк на месте")

	tut.begin_stage(8)
	world.deal_damage(tut.targets[0], 9999.0, ptank, "ram")
	_fail_and_restart(world, 8, "манекен разбит без заморозки")

	tut.begin_stage(9)
	world.deal_damage(tut.targets[0], 9999.0, ptank, "ram")
	_fail_and_restart(world, 9, "манекен уничтожен не ядом")
	world.dispose()

func _check_boss_loss() -> void:
	log_msg("[4/4] Поражение от босса")
	var world := _new_world()
	var tut := world.tutorial
	var ptank: Tank = world.players[0].tank
	tut.begin_stage(11)
	ptank.spawn_protect = 0
	world.deal_damage(ptank, 99999.0, null, "bullet")
	_steps(world, 2)
	_check(world.finished_flag, "гибель от босса тоже завершает обучение")
	_check(tut.state == Tutorial.ST_OVER, "обучение помечено завершённым")
	world.dispose()
