extends Node

var failures := 0
var log_lines: Array = []

func _log(s: String) -> void:
	print(s)
	log_lines.append(s)

func _check(ok: bool, desc: String) -> void:
	if ok:
		_log("  [OK] " + desc)
	else:
		failures += 1
		_log("  [FAIL] " + desc)

func _ready() -> void:
	_log("--- НАЧАЛО ТЕСТА БАЛАНСНЫХ ПРАВОК И УСТРАНЕНИЯ ФРУСТРАЦИИ ---")

	# 1. Ракеты (dmg_scale = 2.4, splash_r = 50.0)
	var rocket_def: Dictionary = Weapons.get_weapon("rockets")
	_check(is_equal_approx(float(rocket_def.get("dmg_scale", 0.0)), 2.4),
		"Ракеты: dmg_scale равен 2.4 (текущее: %s)" % rocket_def.get("dmg_scale"))
	_check(is_equal_approx(float(rocket_def.get("splash_r", 0.0)), 50.0),
		"Ракеты: splash_r равен 50.0 (текущее: %s)" % rocket_def.get("splash_r"))

	# 2. Стандартная пушка (+15% к скорости полета снаряда)
	var standard_cannon: Dictionary = Cannons.get_cannon("standard")
	_check(is_equal_approx(float(standard_cannon.get("bullet_speed_mult", 1.0)), 1.15),
		"Стандартная пушка: bullet_speed_mult равен 1.15 (текущее: %s)" % standard_cannon.get("bullet_speed_mult"))

	var map := GameMap.new(10, 10)
	var p1 := PlayerState.new(0, "P1", "p1", null)
	var world := World.new({
		"map": map,
		"level": {"seed": 100},
		"mode": "ffa",
		"difficulty": "normal",
		"players": [p1],
		"puppet": true
	})

	var test_tank := Tank.new({
		"x": 100.0, "y": 100.0, "team": "player", "name": "Игрок",
		"owner": p1, "color_key": "p1", "max_hp": 100.0, "speed": 100.0, "fire_rate": 30
	})
	test_tank.cannon_id = "standard"
	test_tank.weapon = ""
	test_tank.spawn_protect = 0
	world.tanks.append(test_tank)

	var bullet := Ent.Bullet.new(test_tank.x, test_tank.y, 0.0, test_tank)
	var bullet_speed := Vector2(bullet.vx, bullet.vy).length()
	_check(is_equal_approx(bullet_speed, Cfg.BULLET_SPEED * 1.15),
		"Снаряд стандартной пушки летит с бонусом +15%% (скорость: %.2f, базовая: %.2f)" % [bullet_speed, Cfg.BULLET_SPEED])

	# 3. Перк «Вампир»: Hard Cap 12 HP в секунду
	var vampire_perk: Dictionary = Perks.get_perk("vampire")
	_check(not vampire_perk.is_empty(), "Перк «Вампир» существует")
	test_tank.perk_ids = ["vampire"]
	test_tank.recompute()
	test_tank.hp = 50.0

	var dummy := Tank.new({
		"x": 140.0, "y": 100.0, "team": "enemy", "name": "Враг",
		"owner": null, "color_key": "enemy", "max_hp": 500.0, "speed": 100.0, "fire_rate": 30
	})
	dummy.spawn_protect = 0
	world.tanks.append(dummy)

	# Наносим урон через world.deal_damage: 100 урона * 0.15 = 15 HP, но Hard Cap = 12 HP
	var initial_hp := test_tank.hp
	world.deal_damage(dummy, 100.0, test_tank, "bullet")
	var healed := test_tank.hp - initial_hp
	_check(is_equal_approx(healed, 12.0),
		"Вампир: исцеление ограничено Hard Cap 12 HP/сек (исцелено: %.1f из 15.0 возможных)" % healed)

	# Еще один удар в том же 60-тиковом окне не должен лечить сверх 12 HP
	var hp_before_second_hit := test_tank.hp
	world.deal_damage(dummy, 50.0, test_tank, "bullet")
	var second_healed := test_tank.hp - hp_before_second_hit
	_check(is_equal_approx(second_healed, 0.0),
		"Вампир: повторный удар в том же 60-тиковом окне заблокирован капом (исцелено: %.1f)" % second_healed)

	# 4. Перк «Отражение»: 45% возврат и 0.8 сек оглушения (Stun) атакующего бота
	var reflect_perk: Dictionary = Perks.get_perk("reflect")
	var reflect_frac: float = float(reflect_perk.get("mods", {}).get("reflectFraction", 0.0))
	_check(is_equal_approx(reflect_frac, 0.45),
		"Перк «Отражение»: reflectFraction равен 0.45 (текущее: %s)" % reflect_frac)

	test_tank.perk_ids = ["reflect"]
	test_tank.recompute()
	var dummy_hp_before := dummy.hp
	dummy.stun_ticks = 0
	world.deal_damage(test_tank, 40.0, dummy, "bullet")
	var reflected_dmg := dummy_hp_before - dummy.hp
	_check(is_equal_approx(reflected_dmg, 18.0), # 40 * 0.45 = 18
		"Отражение: возвращено 45%% урона (нанесено 40, вернулось: %.1f)" % reflected_dmg)
	_check(dummy.stun_ticks >= 48,
		"Отражение: атакующий оглушен на 0.8 сек / 48 тиков (stun_ticks: %d)" % dummy.stun_ticks)

	# 5. Перк «Камикадзе»: 130 HP урона
	_check(is_equal_approx(Cfg.KAMIKAZE_DMG, 130.0),
		"Cfg.KAMIKAZE_DMG увеличен до 130.0 (текущее: %s)" % Cfg.KAMIKAZE_DMG)

	# 6. Перк «Магнит»: притягивание ящиков с оружием +20% к эффективности лечения аптечки
	var magnet_perk: Dictionary = Perks.get_perk("magnet")
	var heal_mult: float = float(magnet_perk.get("mods", {}).get("pickupHealMult", 1.0))
	_check(is_equal_approx(heal_mult, 1.2),
		"Перк «Магнит»: pickupHealMult равен 1.2 (+20%% к лечению) (текущее: %s)" % heal_mult)

	test_tank.perk_ids = ["magnet"]
	test_tank.recompute()

	# Проверяем притягивание ящика с оружием
	world.weapon_pickups.clear()
	var wp := Ent.WeaponPickup.new(test_tank.x + 35.0, test_tank.y, "shotgun")
	world.weapon_pickups.append(wp)
	var initial_pickup_x: float = wp.x
	world._update_weapon_pickups()
	var pulled_pickup_x: float = wp.x
	_check(pulled_pickup_x < initial_pickup_x,
		"Магнит: ящик с оружием притягивается к танку (X: %.1f -> %.1f)" % [initial_pickup_x, pulled_pickup_x])

	# 7. ИИ Снайпер: лазерный целеуказатель 0.45 сек (27 тиков)
	var sniper_tank := Tank.new({
		"x": 200.0, "y": 200.0, "team": "enemy", "name": "Снайпер",
		"owner": null, "color_key": "enemy", "max_hp": 100.0, "speed": 100.0, "fire_rate": 30,
		"chassis": "sniper", "chassis_id": "sniper"
	})
	var aim: float = atan2(test_tank.y - sniper_tank.y, test_tank.x - sniper_tank.x)
	sniper_tank.turret_angle = aim
	sniper_tank.fire_cooldown = 0
	sniper_tank.spawn_protect = 0
	var sniper_brain := BotBrain.new({"role": "sniper", "fire_range": 600.0, "accuracy": 1.0})
	sniper_brain.react_timer = 0
	sniper_tank.brain = sniper_brain
	world.tanks.append(sniper_tank)

	sniper_brain._try_fire(sniper_tank, world, test_tank, 100.0, true)
	_check(sniper_tank.sniper_laser_ticks == 27,
		"Снайпер: взведен телеграф лазера на 27 тиков (0.45 сек) (текущее: %d)" % sniper_tank.sniper_laser_ticks)

	# 8. Джаггернаут-Таран: радиус взрыва реактора 260 px и задержка 1.5 сек (90 тиков)
	_check(is_equal_approx(Cfg.RAMMER_EXPLOSION_RADIUS, 260.0),
		"Cfg.RAMMER_EXPLOSION_RADIUS равен 260.0 (текущее: %s)" % Cfg.RAMMER_EXPLOSION_RADIUS)
	_check(Cfg.RAMMER_MELTDOWN_TICKS == 90,
		"Cfg.RAMMER_MELTDOWN_TICKS равен 90 (текущее: %d)" % Cfg.RAMMER_MELTDOWN_TICKS)

	var rammer := Tank.new({
		"x": 300.0, "y": 300.0, "team": "enemy", "name": "Босс-Таран",
		"owner": null, "color_key": "boss_rammer", "max_hp": 3400.0, "speed": 100.0, "fire_rate": 30,
		"chassis_id": "boss_rammer"
	})
	rammer.is_rammer_boss = true
	world.tanks.append(rammer)

	world.rammer_meltdowns.clear()
	world._kill_tank(rammer, test_tank, "bullet")
	_check(world.rammer_meltdowns.size() == 1,
		"Гибель Тарана активирует отложенную перегрузку реактора (активных перегрузок: %d)" % world.rammer_meltdowns.size())
	if not world.rammer_meltdowns.is_empty():
		var meltdown = world.rammer_meltdowns[0]
		_check(int(meltdown["ticks"]) == 90,
			"Таймер перегрузки инициализирован на 90 тиков (1.5 сек) (текущее: %s)" % meltdown["ticks"])

	_log("=== ПРОВЕРКА БАЛАНСНЫХ ПРАВОК И УСТРАНЕНИЯ ФРУСТРАЦИИ ЗАВЕРШЕНА, ошибок: %d ===" % failures)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://test_report.txt"), FileAccess.WRITE)
	if f != null:
		for l in log_lines:
			f.store_line(l)
		f.close()
	get_tree().quit(failures)
