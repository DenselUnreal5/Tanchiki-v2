extends Node

const Weekly = preload("res://scripts/weekly.gd")

var log_lines := []

func log_msg(msg: String) -> void:
	print(msg)
	log_lines.append(msg)
	var f := FileAccess.open("C:/Users/Eskaro/Desktop/кто тут попка/neirogame/Tanchiki-v2/godot/phase34_out.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines))
		f.flush()
		f.close()

func _ready() -> void:
	log_msg("=== НАЧАЛО ТЕСТА ФАЗЫ 3 И ФАЗЫ 4 (ARENA INTERACTIVE & RETENTION) ===")
	var failures := 0

	# ----------------------------------------------------
	# 1. ТЕСТИРОВАНИЕ ФАЗЫ 3: Интерактив арены (Взрывные бочки)
	# ----------------------------------------------------
	log_msg("[1/6] Проверка класса Ent.ExplosiveBarrel...")
	var barrel := Ent.ExplosiveBarrel.new(200.0, 200.0)
	if barrel.hp != 20.0 or not barrel.alive:
		log_msg("ОШИБКА: Неверные начальные параметры бочки")
		failures += 1

	var dummy_scheme = Ctl.KeyboardAimScheme.new()
	var player = PlayerState.new(0, "Тестер", "p1", dummy_scheme)
	player.reset_for_match()

	var level := LevelGen.generate(1, "ffa", 7777, "city")
	var world := World.new({
		"map": level["map"],
		"level": level,
		"mode": "ffa",
		"difficulty": "medium",
		"players": [player],
		"player_level": 1,
		"rng_seed": 7777
	})

	var ptank = player.tank
	ptank.spawn_protect = 0
	ptank.x = 200.0
	ptank.y = 250.0 # 50px away from barrel (inside 120px blast)
	var prev_hp: float = ptank.hp

	# Нанесение урона бочке до взрыва
	barrel.hit(25.0, ptank, world)
	if barrel.alive:
		log_msg("ОШИБКА: Бочка должна была сдетонировать при уроне 25 (HP=20)")
		failures += 1
	if ptank.hp >= prev_hp:
		log_msg("ОШИБКА: Танк в радиусе 50px не получил AoE урон от взрыва бочки")
		failures += 1
	else:
		log_msg("УСПЕХ: Взрыв бочки нанес AoE урон танку (HP: %.1f -> %.1f)" % [prev_hp, ptank.hp])

	# ----------------------------------------------------
	# 2. ТЕСТИРОВАНИЕ ФАЗЫ 3: Генераторы поля (PowerGenerator)
	# ----------------------------------------------------
	log_msg("[2/6] Проверка класса Ent.PowerGenerator...")
	var gen := Ent.PowerGenerator.new(400.0, 400.0)
	if gen.radius <= 0.0 or gen.aura_radius < 100.0:
		log_msg("ОШИБКА: Неверные параметры генератора поля")
		failures += 1

	# Вражеский танк в радиусе ЭМИ
	var enemy_tank := world._spawn_bot("bot_test", "enemy")
	enemy_tank.spawn_protect = 0
	enemy_tank.x = 420.0
	enemy_tank.y = 400.0
	enemy_tank.hp = 60.0

	# Союзный танк в радиусе ЭМИ
	ptank.x = 380.0
	ptank.y = 400.0
	ptank.shield_hp = 0.0

	# Принудительная разрядка ЭМИ
	gen.discharge(world, ptank.team)

	if enemy_tank.stun_ticks <= 0:
		log_msg("ОШИБКА: Вражеский танк не оглушен ЭМИ-импульсом генератора")
		failures += 1
	else:
		log_msg("УСПЕХ: Вражеский танк оглушен на %d тиков" % enemy_tank.stun_ticks)

	if ptank.shield_hp < 50.0:
		log_msg("ОШИБКА: Союзный танк не получил +50 щита от разрядки генератора")
		failures += 1
	else:
		log_msg("УСПЕХ: Союзный танк получил щит: %.1f" % ptank.shield_hp)

	if gen.cooldown <= 0:
		log_msg("ОШИБКА: Генератор поля не ушел на перезарядку после разрядки")
		failures += 1

	# ----------------------------------------------------
	# 3. ТЕСТИРОВАНИЕ ФАЗЫ 3: Спавн бочек и генераторов в проходах
	# ----------------------------------------------------
	log_msg("[3/6] Проверка спавна интерактивов арены в World...")
	if world.barrels.is_empty():
		log_msg("ОШИБКА: На арене не заспавнены взрывные бочки")
		failures += 1
	else:
		log_msg("УСПЕХ: Заспавнено взрывных бочек: %d" % world.barrels.size())

	if world.power_generators.is_empty():
		log_msg("ОШИБКА: На арене не заспавнены генераторы поля")
		failures += 1
	else:
		log_msg("УСПЕХ: Заспавнено генераторов поля: %d" % world.power_generators.size())

	# ----------------------------------------------------
	# 4. ТЕСТИРОВАНИЕ ФАЗЫ 4: Модуль Weekly Challenges
	# ----------------------------------------------------
	log_msg("[4/6] Проверка модуля Weekly...")
	var w_key := Weekly.week_key()
	log_msg("Ключ недели: %s" % w_key)
	if not w_key.contains("-W"):
		log_msg("ОШИБКА: Неверный формат ключа недели: %s" % w_key)
		failures += 1

	var w_chal := Weekly.current_challenge()
	log_msg("Текущее испытание недели: %s (%s)" % [w_chal.get("name"), w_chal.get("mutator")])
	if w_chal.is_empty() or not w_chal.has("mutator"):
		log_msg("ОШИБКА: Еженедельное испытание не содержит мутатора")
		failures += 1

	var time_left := Weekly.time_until_next_week()
	if time_left.get("total_seconds", 0) <= 0:
		log_msg("ОШИБКА: Некорректный таймер до конца недели: %s" % str(time_left))
		failures += 1

	# ----------------------------------------------------
	# 5. ТЕСТИРОВАНИЕ ФАЗЫ 4: Прогресс недели и награды в Profile
	# ----------------------------------------------------
	log_msg("[5/6] Проверка отслеживания и выдачи награды в Profile...")
	var w_prog := Prof.get_weekly_progress()
	if not w_prog.has("challenge"):
		log_msg("ОШИБКА: Prof.get_weekly_progress() не вернул данные")
		failures += 1

	var counter_key: String = String(w_chal.get("counter", "kills"))
	var needed: int = int(w_chal.get("need", 10))
	Prof.bump_weekly(counter_key, needed)

	var w_prog_done := Prof.get_weekly_progress()
	if not bool(w_prog_done["done"]):
		log_msg("ОШИБКА: Испытание недели должно было быть выполнено")
		failures += 1

	var pre_money := Prof.money
	Prof.weekly["claimed"] = false
	var claim_res := Prof.claim_weekly()
	if not bool(claim_res.get("ok", false)):
		log_msg("ОШИБКА: Не удалось забрать награду за недельное испытание: %s" % str(claim_res))
		failures += 1
	elif Prof.money <= pre_money:
		log_msg("ОШИБКА: Монеты за испытание не начислены")
		failures += 1
	else:
		log_msg("УСПЕХ: Награда за недельное испытание получена (+%d монет)" % int(claim_res["reward"]))

	# ----------------------------------------------------
	# 6. ТЕСТИРОВАНИЕ ФАЗЫ 4: Steam Leaderboards & Offline Fallback
	# ----------------------------------------------------
	log_msg("[6/6] Проверка таблиц лидеров (Steam & Local Fallback)...")
	if not SteamStats.LEADERBOARDS.has("survival_waves"):
		log_msg("ОШИБКА: SteamStats.LEADERBOARDS не содержит 'survival_waves'")
		failures += 1
	if not SteamStats.LEADERBOARDS.has("survival_score"):
		log_msg("ОШИБКА: SteamStats.LEADERBOARDS не содержит 'survival_score'")
		failures += 1
	if not SteamStats.LEADERBOARDS.has("weekly"):
		log_msg("ОШИБКА: SteamStats.LEADERBOARDS не содержит 'weekly'")
		failures += 1

	Prof.record_local_leaderboard("survival_waves", "Игрок", 15)
	var records := Prof.get_local_leaderboard("survival_waves")
	if records.is_empty():
		log_msg("ОШИБКА: Таблица лидеров survival_waves пуста")
		failures += 1
	else:
		var top1 = records[0]
		log_msg("Топ-1 рекорд survival_waves: %s — %s (всего записей: %d)" % [top1.get("name"), top1.get("score"), records.size()])

	if failures == 0:
		log_msg("=== ВСЕ ТЕСТЫ ФАЗЫ 3 И ФАЗЫ 4 УСПЕШНО ПРОЙДЕНЫ! ===")
		get_tree().quit(0)
	else:
		log_msg("=== ТЕСТ ЗАВЕРШЕН С ОШИБКАМИ: %d ===" % failures)
		get_tree().quit(1)
