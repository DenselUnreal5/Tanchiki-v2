extends Node

var log_lines := []

func log_msg(msg: String) -> void:
	print(msg)
	log_lines.append(msg)
	var f := FileAccess.open("user://tutorial_check.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines))
		f.flush()
		f.close()

func _ready() -> void:
	log_msg("--- НАЧАЛО ТЕСТА ОНБОРДИНГА И ТУТОРИАЛА (TUTORIAL CHECK) ---")
	var failures := 0

	# 1. Проверка конфигурации режимов и подсказок загрузки
	log_msg("[1/5] Проверка Cfg.MODES и MenuTips...")
	if not Cfg.MODES.has("tutorial"):
		log_msg("ОШИБКА: Cfg.MODES не содержит режим 'tutorial'")
		failures += 1
	if MenuTips.LIST.size() < 12:
		log_msg("ОШИБКА: Ожидалось минимум 12 подсказок MenuTips, найдено: %d" % MenuTips.LIST.size())
		failures += 1

	# 2. Проверка генерации карты и поиска узких проходов (choke points)
	log_msg("[2/5] Проверка LevelGen и choke points...")
	var level := LevelGen.generate(1, "tutorial", 4242, "city")
	if level["mode"] != "tutorial":
		log_msg("ОШИБКА: level['mode'] != 'tutorial'")
		failures += 1
	if not level.has("choke_points"):
		log_msg("ОШИБКА: level не содержит ключ 'choke_points'")
		failures += 1
	else:
		var chokes: Array[Vector2] = level["choke_points"]
		log_msg("Обнаружено тактических проходов: %d" % chokes.size())
		if chokes.is_empty():
			log_msg("ОШИБКА: На карте не найдено тактических проходов (choke points)")
			failures += 1

	# 3. Инициализация World в режиме tutorial
	log_msg("[3/5] Инициализация World(tutorial)...")
	var dummy_scheme = Ctl.KeyboardAimScheme.new()
	var player = PlayerState.new(0, "Новичок", "p1", dummy_scheme)
	player.reset_for_match()
	player.map = level["map"]

	var world = World.new({
		"map": level["map"],
		"level": level,
		"mode": "tutorial",
		"difficulty": "medium",
		"players": [player],
		"player_level": 1,
		"weather": "clear",
		"daytime": "day",
		"rng_seed": 4242
	})

	if world.tutorial_stage != 1:
		log_msg("ОШИБКА: Начальный этап туториала должен быть 1, получен: %d" % world.tutorial_stage)
		failures += 1
	if player.tank == null:
		log_msg("ОШИБКА: Танк игрока не заспавнен")
		failures += 1
		log_msg("FAIL: %d ошибок" % failures)
		get_tree().quit(1)
		return

	# 4. Пошаговая симуляция этапов 1-10
	log_msg("[4/5] Симуляция прохождения заданий туториала (1-10)...")
	var ptank = player.tank

	# Проверка task_info на Задании 1
	var tinfo1 := world.get_tutorial_task_info()
	if tinfo1["stage"] != 1 or tinfo1["total"] != 12:
		log_msg("ОШИБКА: Некорректные метаданные задания 1: %s" % str(tinfo1))
		failures += 1

	if ptank.cannon_id != "standard" or ptank.chassis_id != "standard":
		log_msg("ОШИБКА: Танк на старте должен быть стандартным: cannon=%s, chassis=%s" % [ptank.cannon_id, ptank.chassis_id])
		failures += 1

	# Задание 1: Движение вперед и назад [W / S]
	world.tut_dist_fwd = 40.0
	world.tut_dist_bwd = 30.0
	world.step()
	if world.tutorial_stage != 2:
		log_msg("ОШИБКА: Ожидался Этап 2 после ходовой части, получен: %d" % world.tutorial_stage)
		failures += 1

	# Задание 2: Маневрирование и контрольная точка
	ptank.x = world.tutorial_marker.x
	ptank.y = world.tutorial_marker.y
	world.step()
	if world.tutorial_stage != 3:
		log_msg("ОШИБКА: Ожидался Этап 3 после маркера, получен: %d" % world.tutorial_stage)
		failures += 1
	if world.tutorial_targets.size() != 2:
		log_msg("ОШИБКА: Ожидалось 2 учебные мишени, создано: %d" % world.tutorial_targets.size())
		failures += 1

	# Задание 3: Прицеливание и стрельба по мишеням
	for target in world.tutorial_targets:
		target.alive = false
	world.step()
	if world.tutorial_stage != 4:
		log_msg("ОШИБКА: Ожидался Этап 4 после поражения мишеней, получен: %d" % world.tutorial_stage)
		failures += 1

	# Задание 4: Разрушение укрытий и рикошеты
	world.tut_bricks_destroyed = 2
	world.step()
	if world.tutorial_stage != 5:
		log_msg("ОШИБКА: Ожидался Этап 5 после разрушения укрытий, получен: %d" % world.tutorial_stage)
		failures += 1
	if world.tutorial_barrels.size() != 2:
		log_msg("ОШИБКА: Ожидалось 2 взрывные бочки на Этапе 5, создано: %d" % world.tutorial_barrels.size())
		failures += 1
	var tinfo5 := world.get_tutorial_task_info()
	if tinfo5["stage"] != 5 or tinfo5["total"] != 12:
		log_msg("ОШИБКА: Некорректные метаданные задания 5: %s" % str(tinfo5))
		failures += 1

	# Задание 5: Взрывные бочки (детонация и AoE цепная реакция)
	world.tutorial_barrels[0].hit(25.0, ptank, world)
	for i in 10:
		world.step()
	if world.tutorial_stage != 6:
		log_msg("ОШИБКА: Ожидался Этап 6 после детонации бочек, получен: %d" % world.tutorial_stage)
		failures += 1

	# Задание 6: Тактический рывок на Shift (i-frames)
	ptank.dash(Vector2(0, -1))
	world.step()
	if world.tutorial_stage != 7:
		log_msg("ОШИБКА: Ожидался Этап 7 после рывка, получен: %d" % world.tutorial_stage)
		failures += 1
	if world.tutorial_mine_dummy == null:
		log_msg("ОШИБКА: Учебная цель для мины не создана")
		failures += 1

	# Задание 7: Тактическая мина [E]
	ptank.place_mine(world)
	world.tutorial_mine_dummy.alive = false
	world.step()
	if world.tutorial_stage != 8:
		log_msg("ОШИБКА: Ожидался Этап 8 после подрыва мины, получен: %d" % world.tutorial_stage)
		failures += 1

	var tinfo8 := world.get_tutorial_task_info()
	if tinfo8["keys"] != "[Q / Й]":
		log_msg("ОШИБКА: Ожидались клавиши [Q / Й] в описании задания 8, получено: %s" % tinfo8["keys"])
		failures += 1

	# Проверка устойчивости: смерть танка и респавн не должны сбрасывать bulwark
	ptank.respawn(ptank.x, ptank.y)
	world.step()
	if ptank.ability_id != "bulwark":
		log_msg("ОШИБКА: Способность танка сброшена после respawn(): '%s'" % ptank.ability_id)
		failures += 1

	# Задание 8: Боевая спецспособность [Q]
	ptank.use_ability(world)
	world.step()
	if world.tutorial_stage != 9:
		log_msg("ОШИБКА: Ожидался Этап 9 после способности, получен: %d" % world.tutorial_stage)
		failures += 1
	if ptank.cannon_id != "ice" or ptank.chassis_id != "light" or ptank.color_key != "p5":
		log_msg("ОШИБКА: Танк на этапе 9 должен быть Ледяным (cannon=ice, chassis=light, color=p5), получено: cannon=%s, chassis=%s, color=%s" % [ptank.cannon_id, ptank.chassis_id, ptank.color_key])
		failures += 1
	if world.tutorial_ice_dummy == null:
		log_msg("ОШИБКА: Учебная цель для заморозки не создана на Этапе 9")
		failures += 1

	# Задание 9: Криогенная заморозка врага
	world.tutorial_ice_dummy.freeze_ticks = 120
	world.step()
	if world.tutorial_stage != 10:
		log_msg("ОШИБКА: Ожидался Этап 10 после заморозки, получен: %d" % world.tutorial_stage)
		failures += 1
	if ptank.cannon_id != "acid" or ptank.chassis_id != "heavy" or ptank.color_key != "p12":
		log_msg("ОШИБКА: Танк на этапе 10 должен быть Кислотным (cannon=acid, chassis=heavy, color=p12), получено: cannon=%s, chassis=%s, color=%s" % [ptank.cannon_id, ptank.chassis_id, ptank.color_key])
		failures += 1
	if world.tutorial_acid_dummy == null:
		log_msg("ОШИБКА: Учебная цель для яда не создана на Этапе 10")
		failures += 1

	# Задание 10: Химический яд и коррозия
	world.tutorial_acid_dummy.acid_stacks = 2
	world.tutorial_step_timer = 50
	world.step()
	if world.tutorial_stage != 11:
		log_msg("ОШИБКА: Ожидался Этап 11 после наложения яда, получен: %d" % world.tutorial_stage)
		failures += 1
	if ptank.cannon_id != "standard" or ptank.chassis_id != "standard" or ptank.color_key != "p1":
		log_msg("ОШИБКА: Танк на этапе 11 должен быть возвращен в стандартный строй (color=p1), получено: cannon=%s, chassis=%s, color=%s" % [ptank.cannon_id, ptank.chassis_id, ptank.color_key])
		failures += 1
	if world.tutorial_drone == null:
		log_msg("ОШИБКА: Спарринг-дрон не создан на Этапе 11")
		failures += 1

	# Задание 11: Боевой спарринг — уничтожение дрона и опыт
	world.tutorial_drone.alive = false
	world.step()
	if world.tutorial_stage != 12:
		log_msg("ОШИБКА: Ожидался Этап 12 после победы над дроном, получен: %d" % world.tutorial_stage)
		failures += 1
	if player.pending_level_ups <= 0:
		log_msg("ОШИБКА: Игрок должен был получить повышение уровня для выбора перка")
		failures += 1

	# Задание 12: Выбор первого боевого перка и завершение курса
	player.equip_perk("double_shot")
	player.pending_level_ups = 0
	for i in 50:
		world.step()

	if not world.finished_flag:
		log_msg("ОШИБКА: Матч обучения должен быть завершен")
		failures += 1
	if not bool(world.result.get("victory", false)):
		log_msg("ОШИБКА: Результат матча должен быть victory == true")
		failures += 1
	if Prof.stats.get("tutorialCompleted", 0) != 1:
		log_msg("ОШИБКА: Статистика tutorialCompleted должна быть равна 1")
		failures += 1

	# 5. Проверка достижений и наград
	log_msg("[5/5] Проверка достижений и наград...")
	Prof.check_achievements()
	if not Prof.achievements.has("tutorial_master"):
		log_msg("ОШИБКА: Достижение 'tutorial_master' не открыто")
		failures += 1
	else:
		log_msg("УСПЕХ: Достижение 'tutorial_master' разблокировано, награда выдана!")

	if failures == 0:
		log_msg("=== ВСЕ ТЕСТЫ ОНБОРДИНГА И ТУТОРИАЛА УСПЕШНО ПРОЙДЕНЫ! ===")
		get_tree().quit(0)
	else:
		log_msg("=== ТЕСТ ЗАВЕРШЕН С ОШИБКАМИ: %d ===" % failures)
		get_tree().quit(1)
