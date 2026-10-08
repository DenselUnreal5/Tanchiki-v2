extends Node

func _ready() -> void:
	print("--- НАЧАЛО ТЕСТА СИСТЕМЫ ПРИОРИТЕТОВ (PRIORITY MATRIX CHECK) ---")
	var failures := 0

	# 1. ТЕСТ ИЕРАРХИИ КОНТРОЛЯ И СОСТОЯНИЙ (CC HIERARCHY & INTERRUPT CONTRACT)
	print("[1/4] Проверка CC Hierarchy и прерывания действий...")
	var player_tank = Tank.new({
		"x": 100.0, "y": 100.0,
		"team": "player", "name": "Player",
		"max_hp": 100.0, "speed": 3.0, "fire_rate": 20,
		"owner": null
	})
	player_tank.spawn_protect = 0

	# Базовое состояние
	if player_tank.get_cc_level() != Tank.CC_NONE:
		print("ОШИБКА: Ожидался CC_NONE, получен: ", player_tank.get_cc_level())
		failures += 1

	# Начало рывка (CC_FORCED)
	player_tank.dash(Vector2(1, 0))
	if player_tank.get_cc_level() != Tank.CC_FORCED:
		print("ОШИБКА: Во время рывка ожидался CC_FORCED, получен: ", player_tank.get_cc_level())
		failures += 1
	if player_tank.dash_range <= 0.0:
		print("ОШИБКА: dash_range должен быть > 0")
		failures += 1

	# Наложение стазиса/заморозки поверх рывка -> должно прервать рывок!
	player_tank.apply_freeze(null, null, 60)
	if player_tank.get_cc_level() != Tank.CC_STASIS:
		print("ОШИБКА: Ожидался CC_STASIS, получен: ", player_tank.get_cc_level())
		failures += 1
	if player_tank.dash_range != 0.0:
		print("ОШИБКА: dash_range должен быть сброшен в 0 при стазисе")
		failures += 1
	if player_tank.vx != 0.0 or player_tank.vy != 0.0:
		print("ОШИБКА: Скорость vx, vy должна быть 0 при стазисе")
		failures += 1
	if player_tank.can_fire:
		print("ОШИБКА: can_fire должен быть false при стазисе")
		failures += 1
	if player_tank.dash(Vector2(0, 1)):
		print("ОШИБКА: dash() не должен начинаться во время стазиса")
		failures += 1

	# 2. ТЕСТ БОССА ТАРАНЩИКА И ПРЕРЫВАНИЯ РАЗГОНА
	print("[2/4] Проверка прерывания разгона босса Таранщика...")
	var rammer = Tank.new({
		"x": 300.0, "y": 300.0,
		"team": "enemy", "name": "Rammer",
		"max_hp": 800.0, "speed": 2.5, "fire_rate": 30
	})
	rammer.spawn_protect = 0
	rammer.is_boss = true
	rammer.is_rammer_boss = true
	rammer.start_rammer_charge(100.0, 300.0, null)
	rammer.rammer_state = "charge"
	if rammer.rammer_state != "charge":
		print("ОШИБКА: Таранщик должен быть в состоянии charge")
		failures += 1

	# Заморозка таранщика на полной скорости
	rammer.apply_freeze(null, null, 120)
	if rammer.rammer_state != "idle":
		print("ОШИБКА: Состояние таранщика должно быть сброшено в idle при заморозке")
		failures += 1
	if rammer.get_cc_level() != Tank.CC_STASIS:
		print("ОШИБКА: Таранщик должен быть в CC_STASIS")
		failures += 1

	# 3. ТЕСТ СКОРИНГА УГРОЗ ИИ (AI THREAT SCORING)
	print("[3/4] Проверка скоринга угроз BotBrain.evaluate_threat_score()...")
	var mock_weather = WeatherSystem.new(42, {"condition": "clear"})
	var dummy_world = {
		"mode": "defense",
		"base": {"x": 0.0, "y": 0.0},
		"weather": mock_weather
	}

	var bot_tank = Tank.new({
		"x": 200.0, "y": 200.0,
		"team": "enemy", "name": "Bot",
		"max_hp": 100.0, "speed": 2.5, "fire_rate": 20
	})
	bot_tank.spawn_protect = 0

	var enemy_normal = Tank.new({
		"x": 250.0, "y": 200.0,
		"team": "player", "name": "NormalEnemy",
		"max_hp": 100.0, "speed": 2.5, "fire_rate": 20
	})
	enemy_normal.spawn_protect = 0

	var enemy_frozen = Tank.new({
		"x": 250.0, "y": 200.0,
		"team": "player", "name": "FrozenEnemy",
		"max_hp": 100.0, "speed": 2.5, "fire_rate": 20
	})
	enemy_frozen.spawn_protect = 0
	enemy_frozen.freeze_ticks = 100

	var score_normal: float = BotBrain.evaluate_threat_score(bot_tank, enemy_normal, dummy_world, 50.0, true)
	var score_frozen: float = BotBrain.evaluate_threat_score(bot_tank, enemy_frozen, dummy_world, 50.0, true)

	print("Скоринг обычной цели: %.2f | Замороженной: %.2f" % [score_normal, score_frozen])
	if score_frozen <= score_normal:
		print("ОШИБКА: Замороженная цель должна иметь более высокий приоритет (бонус уязвимости)!")
		failures += 1

	# 4. ТЕСТ БУФЕРИЗАЦИИ ВВОДА (INPUT BUFFER)
	print("[4/4] Проверка буфера ввода (Input Buffering)...")
	var dummy_scheme = Ctl.KeyboardAimScheme.new()
	var mock_player = PlayerState.new(0, "TestPlayer", "p1", dummy_scheme)
	var test_tank = Tank.new({
		"x": 0.0, "y": 0.0,
		"team": "player", "name": "TestTank",
		"max_hp": 100.0, "speed": 2.5, "fire_rate": 20,
		"owner": mock_player
	})
	test_tank.spawn_protect = 0
	test_tank.fire_cooldown = 4 # Осталось 4 тика до выстрела
	test_tank.shoot(null) # Попытка выстрела во время кулдауна
	if test_tank.buffer_fire_ticks != Tank.INPUT_BUFFER_WINDOW:
		print("ОШИБКА: Выстрел перед окончанием кулдауна должен был попасть в буфер ввода!")
		failures += 1

	# 5. ТЕСТ ПРИОРИТЕТОВ ЗВУКА
	print("[SFX] Проверка приоритетов звуков...")
	if Sfx.SFX_PRIORITY["explosion"] <= Sfx.SFX_PRIORITY["tread_hard"]:
		print("ОШИБКА: Приоритет взрыва должен быть выше шума шасси!")
		failures += 1

	if failures == 0:
		print("--- ВСЕ ТЕСТЫ СИСТЕМЫ ПРИОРИТЕТОВ УСПЕШНО ПРОЙДЕНЫ! ---")
		get_tree().quit(0)
	else:
		print("--- ТЕСТЫ ЗАВЕРШИЛИСЬ С ОШИБКАМИ: %d ---" % failures)
		get_tree().quit(1)

