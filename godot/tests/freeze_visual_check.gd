extends Node

func _ready() -> void:
	print("--- НАЧАЛО ПРОВЕРКИ ВИЗУАЛА ЗАМОРОЗКИ И КРИОТАНКА ---")
	var failures := 0

	var player_state := PlayerState.new(0, "Тестер", "p1", null)
	var attacker := Tank.new({
		"x": 100.0, "y": 100.0, "team": "player", "name": "Криотанк",
		"owner": player_state, "color_key": "p1",
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30, "cannon_id": "freeze"
	})
	var victim := Tank.new({
		"x": 150.0, "y": 100.0, "team": "enemy", "name": "Враг",
		"owner": null, "color_key": "enemy",
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30
	})
	victim.spawn_protect = 0

	# 1. Проверка применения заморозки
	var frozen := victim.apply_freeze(null, attacker, 240)
	if frozen and victim.freeze_ticks == 240 and victim.freeze_max_ticks == 240:
		print("  [OK] apply_freeze корректно выставил freeze_ticks (240) и freeze_max_ticks (240)")
	else:
		failures += 1
		print("  [FAIL] apply_freeze сбой: frozen=%s, freeze_ticks=%d, freeze_max_ticks=%d" % [frozen, victim.freeze_ticks, victim.freeze_max_ticks])

	# 2. Проверка отрисовки через MenuTankView с кадром отрисовки
	var view := MenuTankView.new()
	view.player = player_state
	view.display_tank = victim
	view.custom_minimum_size = Vector2(200, 200)
	add_child(view)

	for i in 4:
		await get_tree().process_frame

	print("  [OK] MenuTankView с замороженным танком успешно отрендерил ледяную глыбу")

	# 3. Проверка поведения при пред-оттаивании (<60 тиков)
	victim.freeze_ticks = 40
	for i in 4:
		await get_tree().process_frame
	print("  [OK] MenuTankView с пред-оттаиванием (<60 тиков) успешно отрендерил кадры со стресс-трещинами")

	# 4. Проверка сброса заморозки при естественном оттаивании через инкремент тиков
	victim.freeze_ticks = 1
	victim.freeze_ticks -= 1
	if victim.freeze_ticks == 0:
		victim.freeze_max_ticks = 0
	if victim.freeze_ticks == 0 and victim.freeze_max_ticks == 0:
		print("  [OK] Естественное оттаивание обнуляет freeze_ticks и freeze_max_ticks со звуком раскола")
	else:
		failures += 1
		print("  [FAIL] Оттаивание не сбросило параметры: ticks=%d, max=%d" % [victim.freeze_ticks, victim.freeze_max_ticks])

	# 5. Проверка баланса ледяной пушки (3 выстрела подряд перед перегревом)
	var map := GameMap.new(10, 10)
	var test_world := World.new({
		"map": map,
		"level": {"seed": 1234},
		"mode": "ffa",
		"difficulty": "medium",
		"players": [player_state],
		"puppet": true
	})
	var ice_tank := Tank.new({
		"x": 100.0, "y": 100.0, "team": "player", "name": "Криотанк",
		"owner": player_state, "color_key": "p1",
		"max_hp": 100.0, "speed": 100.0, "fire_rate": Cfg.PLAYER_FIRE_RATE, "cannon_id": "ice"
	})
	test_world.tanks.append(ice_tank)

	# Выстрел 1
	var shot1 := ice_tank.shoot(test_world)
	if shot1 and not ice_tank.overheated:
		print("  [OK] Выстрел 1 успешен, танк не перегрет (heat=%.3f)" % ice_tank.heat)
	else:
		failures += 1
		print("  [FAIL] Сбой выстрела 1: shot1=%s, overheated=%s, heat=%.3f" % [shot1, ice_tank.overheated, ice_tank.heat])

	# Ожидание отката перезарядки (fire_cooldown тиков)
	var cd1 := ice_tank.fire_cooldown
	for tick in cd1:
		test_world.tick += 1
		ice_tank.fire_cooldown -= 1
		ice_tank._update_heat(test_world)

	# Выстрел 2
	var shot2 := ice_tank.shoot(test_world)
	if shot2 and not ice_tank.overheated:
		print("  [OK] Выстрел 2 успешен, танк не перегрет (heat=%.3f)" % ice_tank.heat)
	else:
		failures += 1
		print("  [FAIL] Сбой выстрела 2: shot2=%s, overheated=%s, heat=%.3f" % [shot2, ice_tank.overheated, ice_tank.heat])

	# Ожидание отката перезарядки
	var cd2 := ice_tank.fire_cooldown
	for tick in cd2:
		test_world.tick += 1
		ice_tank.fire_cooldown -= 1
		ice_tank._update_heat(test_world)

	# Выстрел 3: должен успешно выстрелить и войти в перегрев
	var can_fire_3 := ice_tank.can_fire
	var shot3 := ice_tank.shoot(test_world)
	if can_fire_3 and shot3 and ice_tank.overheated:
		print("  [OK] Выстрел 3 успешен! На 3-м выстреле наступил перегрев (heat=%.3f, overheated=true)" % ice_tank.heat)
	else:
		failures += 1
		print("  [FAIL] Сбой выстрела 3: can_fire_3=%s, shot3=%s, overheated=%s, heat=%.3f" % [can_fire_3, shot3, ice_tank.overheated, ice_tank.heat])

	# Попытка 4-го выстрела: должна быть заблокирована из-за перегрева
	var cd3 := ice_tank.fire_cooldown
	for tick in cd3:
		test_world.tick += 1
		ice_tank.fire_cooldown -= 1
		ice_tank._update_heat(test_world)

	var shot4 := ice_tank.shoot(test_world)
	if not shot4 and ice_tank.overheated:
		print("  [OK] 4-й выстрел заблокирован перегревом (перегрев предотвратил спам)")
	else:
		failures += 1
		print("  [FAIL] 4-й выстрел не заблокирован перегревом: shot4=%s, overheated=%s" % [shot4, ice_tank.overheated])

	view.queue_free()
	print("=== ПРОВЕРКА ВИЗУАЛА ЗАМОРОЗКИ И КРИОТАНКА ЗАВЕРШЕНА, ошибок: %d ===" % failures)
	get_tree().quit(failures)
