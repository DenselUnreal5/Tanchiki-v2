extends Node

var failures := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [OK] " + what)
	else:
		failures += 1
		print("  [FAIL] " + what)

func _ready() -> void:
	print("--- НАЧАЛО ТЕСТА ДЖАГГЕРНАУТА-ТАРАНА (RAMMER BOSS) ---")

	# 1. Проверка конфигурации Cfg
	_check(Cfg.RAMMER_BOSS_BASE_HP == 3400.0, "Cfg.RAMMER_BOSS_BASE_HP равен 3400 (текущее: %s)" % Cfg.RAMMER_BOSS_BASE_HP)
	_check(Cfg.RAMMER_TELEGRAPH_TICKS == 32, "Cfg.RAMMER_TELEGRAPH_TICKS уменьшен до 32 тиков (текущее: %d)" % Cfg.RAMMER_TELEGRAPH_TICKS)
	_check(Cfg.RAMMER_CHARGE_SPEED == 12.0, "Cfg.RAMMER_CHARGE_SPEED увеличен до 12.0 (текущее: %s)" % Cfg.RAMMER_CHARGE_SPEED)
	_check(Cfg.RAMMER_SPIN_DURATION_TICKS == 75, "Cfg.RAMMER_SPIN_DURATION_TICKS равен 75 (текущее: %d)" % Cfg.RAMMER_SPIN_DURATION_TICKS)
	_check(Cfg.RAMMER_SPIN_COOLDOWN_TICKS == 240, "Cfg.RAMMER_SPIN_COOLDOWN_TICKS равен 240 (текущее: %d)" % Cfg.RAMMER_SPIN_COOLDOWN_TICKS)
	_check(Cfg.RAMMER_SPIN_MELEE_DMG == 48.0, "Cfg.RAMMER_SPIN_MELEE_DMG равен 48.0 (текущее: %s)" % Cfg.RAMMER_SPIN_MELEE_DMG)

	# 2. Проверка EnemyTypes
	var enemy_def: Dictionary = EnemyTypes.LIST.get("boss_rammer", {})
	_check(not enemy_def.is_empty(), "boss_rammer присутствует в EnemyTypes.LIST")
	_check(float(enemy_def.get("hp_mult", 0.0)) == 34.0, "boss_rammer hp_mult равен 34.0 (3400 HP)")
	_check(float(enemy_def.get("dmg_scale", 0.0)) == 1.4, "boss_rammer dmg_scale равен 1.4")

	# 3. Инициализация босса и проверка статов
	var rammer := Tank.new({
		"x": 300.0, "y": 300.0, "team": "enemy", "name": "Джаггернаут-Таран",
		"owner": null, "color_key": "boss_rammer",
		"max_hp": 3400.0, "speed": 100.0, "fire_rate": 30, "chassis_id": "boss_rammer"
	})
	rammer.is_rammer_boss = true
	rammer.is_boss = true
	rammer.enemy_type = enemy_def
	rammer.recompute()

	_check(rammer.is_rammer_boss, "rammer.is_rammer_boss установлен в true")
	_check(rammer.max_hp >= 3400.0, "rammer.max_hp равен или выше 3400.0 (текущее: %s)" % rammer.max_hp)

	# 4. Проверка телеграфа атаки
	rammer.spawn_protect = 0
	rammer.start_rammer_charge(500.0, 300.0, null)
	_check(rammer.rammer_state == "telegraph", "rammer_state перешел в 'telegraph'")
	_check(rammer.rammer_telegraph_ticks == Cfg.RAMMER_TELEGRAPH_TICKS, "rammer_telegraph_ticks выставлен в 32")

	# 5. Проверка раскрутки (start_rammer_spin) и разброса мин
	var map := GameMap.new(10, 10)
	var p1 := PlayerState.new(0, "P1", "p1", null)
	var world := World.new({
		"map": map,
		"level": {"seed": 1234},
		"mode": "ffa",
		"difficulty": "normal",
		"players": [p1],
		"puppet": true
	})
	world.tanks.append(rammer)

	var victim := Tank.new({
		"x": 330.0, "y": 300.0, "team": "player", "name": "Жертва",
		"owner": null, "color_key": "p1", "max_hp": 200.0, "speed": 100.0, "fire_rate": 30
	})
	victim.spawn_protect = 0
	world.tanks.append(victim)

	rammer.rammer_state = "idle"
	rammer.rammer_spin_cooldown = 0
	rammer.start_rammer_spin(world)

	_check(rammer.rammer_state == "spin", "rammer_state перешел в 'spin'")
	_check(rammer.rammer_spin_ticks == Cfg.RAMMER_SPIN_DURATION_TICKS, "rammer_spin_ticks выставлен в 75")

	# Проверка кинетической дефлексии во время раскрутки (-35% урона)
	var dmg_res := rammer.take_damage(world, 100.0, victim, "bullet")
	_check(is_equal_approx(float(dmg_res["applied"]), 65.0), "Кинетическая дефлексия снижает урон на 35%% (получено %.1f из 100)" % float(dmg_res["applied"]))

	var initial_victim_hp: float = victim.hp
	var initial_mines_count: int = world.mines.size()

	# Симулируем 76 тиков мира
	for i in 76:
		world.tick += 1
		rammer._update_rammer_boss(world)

	_check(world.mines.size() > initial_mines_count, "Раскрутка раскидала мины вокруг себя (мин создано: %d)" % (world.mines.size() - initial_mines_count))
	_check(victim.hp < initial_victim_hp, "Жертва получила контактный урон от раскрутки (HP: %.1f -> %.1f)" % [initial_victim_hp, victim.hp])
	_check(rammer.rammer_state == "idle", "По окончании раскрутки rammer_state вернулся в 'idle'")
	_check(rammer.rammer_spin_cooldown >= 238 and rammer.rammer_spin_cooldown <= Cfg.RAMMER_SPIN_COOLDOWN_TICKS, "rammer_spin_cooldown выставлен в ~240 (текущее: %d)" % rammer.rammer_spin_cooldown)

	# 6. Проверка бестиария
	var b_entry: Dictionary = Bestiary.get_entry("boss_rammer")
	_check(not b_entry.is_empty(), "Бестиарий содержит boss_rammer")
	_check(b_entry.get("hp_val", "").begins_with("3400"), "В бестиарии указано 3400 HP")
	var has_spin_ability := false
	for ab in b_entry.get("abilities", []):
		if ab.get("name", "") == "Вихревая раскрутка":
			has_spin_ability = true
			break
	_check(has_spin_ability, "В бестиарии добавлена способность 'Вихревая раскрутка'")

	print("=== ПРОВЕРКА ДЖАГГЕРНАУТА-ТАРАНА ЗАВЕРШЕНА, ошибок: %d ===" % failures)
	get_tree().quit(failures)
