extends Node

const FIRE_PERKS := ["napalm", "slow_burn", "fire_wall", "fireproof", "flashover"]
const SHOCK_PERKS := ["high_voltage", "long_stun", "arc_chain", "capacitor", "overload"]

var failures := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	_check_data()
	_check_fire()
	_check_shock()
	_check_builds()
	print("=== ПРОВЕРКА ПЕРКОВ СПЕЦПУШЕК ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _arena(cannon: String, perks: Array) -> World:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, "ffa", 6161, "city")
	var world := World.new({
		"map": level["map"], "level": level, "mode": "ffa", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 6161,
	})
	world.map.fill(Cfg.T_EMPTY)
	world.tanks = [player.tank]
	world.barrels.clear()
	world.pickups.clear()
	world.weapon_pickups.clear()
	world.power_generators.clear()
	var ptank: Tank = player.tank
	ptank.x = 400.0
	ptank.y = 400.0
	ptank.vx = 0.0
	ptank.vy = 0.0
	ptank.spawn_protect = 0
	ptank.cannon_id = cannon
	ptank.perk_ids = perks.duplicate()
	ptank.recompute()
	return world

func _spawn(world: World, x: float, y: float) -> Tank:
	var t: Tank = world._spawn_bot("enemy", "enemy", "grunt")
	t.x = x
	t.y = y
	t.spawn_protect = 0
	t.brain = null
	t.max_hp = 5000.0
	t.hp = 5000.0
	return t

func _fire_at(world: World, shooter: Tank, target: Tank) -> Ent.Bullet:
	shooter.aim_at(target.x, target.y)
	shooter.fire_cooldown = 0
	shooter.heat = 0.0
	shooter.overheated = false
	var before := world.bullets.size()
	shooter.shoot(world)
	return world.bullets[before] if world.bullets.size() > before else null

func _fly(world: World, bullet, max_ticks: int = 200) -> void:
	for i in max_ticks:
		world.step()
		if bullet == null or not bullet.alive:
			return

func _check_data() -> void:
	print("[1/4] Перки и билды в данных")
	for pair in [[FIRE_PERKS, "fire"], [SHOCK_PERKS, "shock"]]:
		for id in pair[0]:
			var p := Perks.get_perk(id)
			var ok: bool = not p.is_empty() and String(Perks.CANNON_REQUIRED.get(id, "")) == pair[1] \
				and Perks.is_perk_allowed_for_cannon(id, pair[1]) and not Perks.is_perk_allowed_for_cannon(id, "standard") \
				and Perks.unlock_level_of(id) > 0 and PerkIcons.texture_of(id) != null \
				and I18n.EN.has("perk.%s.name" % id) and I18n.EN.has("perk.%s.desc" % id)
			_check(ok, "перк %s: пушка «%s», уровень %d, иконка и перевод" % [id, pair[1], Perks.unlock_level_of(id)])
	for b in [["fire_hunter", "fire_ring"], ["shock_hunter", "storm_pulse"]]:
		var build := Perks.get_build(b[0])
		_check(not build.is_empty() and String(build.get("active", "")) == b[1] and (build["perks"] as Array).size() == 3
			and I18n.EN.has("build.%s.name" % b[0]) and not Abilities.get_ability(b[1]).is_empty()
			and PerkIcons.texture_of(b[1]) != null,
			"билд %s даёт способность %s" % [b[0], b[1]])

func _burn_damage(world: World, target: Tank, attacker: Tank) -> float:
	target.hp = target.max_hp
	target.burn_ticks = 0
	target.ignite(world, attacker)
	var before := target.hp
	for i in 60:
		target._update_burn(world)
	return before - target.hp

func _check_fire() -> void:
	print("[2/4] Перки Огнемёта")
	var world := _arena("fire", [])
	var ptank: Tank = world.players[0].tank
	var target := _spawn(world, 600.0, 400.0)
	var plain := _burn_damage(world, target, ptank)
	target.ignite(world, ptank)
	var plain_ticks := target.burn_ticks
	world.spawn_fire_patch(500.0, 500.0, ptank)
	var plain_patch = world.fire_patches[world.fire_patches.size() - 1]

	world = _arena("fire", ["napalm"])
	ptank = world.players[0].tank
	target = _spawn(world, 600.0, 400.0)
	var napalm := _burn_damage(world, target, ptank)
	_check(plain > 0.0 and is_equal_approx(napalm / plain, 1.5), "Напалм: горение %.1f → %.1f урона за секунду" % [plain, napalm])

	world = _arena("fire", ["slow_burn"])
	ptank = world.players[0].tank
	target = _spawn(world, 600.0, 400.0)
	target.ignite(world, ptank)
	world.spawn_fire_patch(500.0, 500.0, ptank)
	var long_patch = world.fire_patches[world.fire_patches.size() - 1]
	_check(target.burn_ticks == int(round(plain_ticks * 1.6)) and long_patch.timer == int(round(plain_patch.timer * 1.6)),
		"Долгое горение: горение %d → %d тиков, лужа %d → %d" % [plain_ticks, target.burn_ticks, plain_patch.timer, long_patch.timer])

	world = _arena("fire", ["fire_wall"])
	ptank = world.players[0].tank
	world.spawn_fire_patch(500.0, 500.0, ptank)
	var wide_patch = world.fire_patches[world.fire_patches.size() - 1]
	_check(is_equal_approx(wide_patch.radius, plain_patch.radius * 1.5),
		"Огненный вал: лужа %.0f → %.0f px" % [plain_patch.radius, wide_patch.radius])

	world = _arena("fire", [])
	ptank = world.players[0].tank
	var pyro := _spawn(world, 600.0, 400.0)
	_check(ptank.ignite(world, pyro), "без перка танк игрока загорается")
	world = _arena("fire", ["fireproof"])
	ptank = world.players[0].tank
	pyro = _spawn(world, 600.0, 400.0)
	_check(not ptank.ignite(world, pyro) and ptank.burn_ticks == 0, "Огнеупорный корпус: танк не загорается")

	for with_perk in [false, true]:
		world = _arena("fire", ["flashover"] if with_perk else [])
		ptank = world.players[0].tank
		var burning := _spawn(world, 700.0, 400.0)
		var near := _spawn(world, 750.0, 400.0)
		var far := _spawn(world, 900.0, 400.0)
		burning.ignite(world, ptank)
		burning.alive = false
		world._kill_tank(burning, ptank, "fire")
		if with_perk:
			_check(near.burn_ticks > 0 and far.burn_ticks == 0, "Вспышка: горящий враг при гибели поджёг соседа, дальний цел")
		else:
			_check(near.burn_ticks == 0, "без Вспышки сосед не загорается")

func _shock_hit(perks: Array) -> Dictionary:
	var world := _arena("shock", perks)
	var ptank: Tank = world.players[0].tank
	var target := _spawn(world, 600.0, 400.0)
	var side_a := _spawn(world, 650.0, 450.0)
	var side_b := _spawn(world, 650.0, 350.0)
	var far := _spawn(world, 900.0, 600.0)
	var b := _fire_at(world, ptank, target)
	var cooldown := ptank.fire_cooldown
	_fly(world, b)
	return {
		"dmg": target.max_hp - target.hp, "stun": target.stun_ticks + 1, "cooldown": cooldown,
		"side_dmg": [side_a.max_hp - side_a.hp, side_b.max_hp - side_b.hp],
		"side_stun": side_a.stun_ticks > 0 and side_b.stun_ticks > 0,
		"far_dmg": far.max_hp - far.hp,
	}

func _check_shock() -> void:
	print("[3/4] Перки Громовержца")
	var plain := _shock_hit([])
	_check(is_equal_approx(float(plain["dmg"]), Cfg.SHOCK_DMG) and float(plain["side_dmg"][0]) == 0.0,
		"без перков молния бьёт только цель на %.0f" % plain["dmg"])
	var hv := _shock_hit(["high_voltage"])
	_check(is_equal_approx(float(hv["dmg"]), Cfg.SHOCK_DMG * 1.6), "Высокое напряжение: урон %.0f → %.0f" % [plain["dmg"], hv["dmg"]])
	var ls := _shock_hit(["long_stun"])
	_check(int(ls["stun"]) > int(plain["stun"]) and absi(int(ls["stun"]) - int(round(plain["stun"] * 1.5))) <= 2,
		"Глубокий разряд: стан %d → %d тиков" % [plain["stun"], ls["stun"]])
	var arc := _shock_hit(["arc_chain"])
	_check(float(arc["side_dmg"][0]) > 0.0 and float(arc["side_dmg"][1]) > 0.0 and bool(arc["side_stun"])
		and float(arc["far_dmg"]) == 0.0 and is_equal_approx(float(arc["side_dmg"][0]), Cfg.SHOCK_DMG * 0.5),
		"Цепной разряд: перескок на 2 соседей по %.0f урона со станом, дальний цел" % arc["side_dmg"][0])
	var cap := _shock_hit(["capacitor"])
	_check(absi(int(cap["cooldown"]) - int(round(plain["cooldown"] * 0.75))) <= 1,
		"Конденсатор: перезарядка %d → %d тиков" % [plain["cooldown"], cap["cooldown"]])

	for with_perk in [false, true]:
		var world := _arena("shock", ["overload"] if with_perk else [])
		var ptank: Tank = world.players[0].tank
		var target := _spawn(world, 600.0, 400.0)
		target.stun_ticks = 30
		var dealt := world.deal_damage(target, 10.0, ptank, "bullet")
		if with_perk:
			_check(is_equal_approx(dealt, 13.0), "Перегрузка: по оглушённому 10 → %.1f урона" % dealt)
		else:
			_check(is_equal_approx(dealt, 10.0), "без Перегрузки по оглушённому обычный урон")

func _check_builds() -> void:
	print("[4/4] Билды")
	var world := _arena("fire", ["napalm", "slow_burn", "flashover"])
	var ptank: Tank = world.players[0].tank
	_check(ptank.has_build("fire_hunter") and ptank.ability_id == "fire_ring", "Инферно собран — способность «Огненное кольцо»")
	var near := _spawn(world, 480.0, 400.0)
	var far := _spawn(world, 700.0, 400.0)
	var patches_before := world.fire_patches.size()
	ptank.ability_cd = 0
	_check(ptank.use_ability(world), "«Огненное кольцо» срабатывает")
	_check(near.burn_ticks > 0 and far.burn_ticks == 0, "кольцо поджигает ближнего врага, дальний цел")
	_check(world.fire_patches.size() - patches_before == Cfg.FIRE_RING_PATCHES, "вокруг танка %d луж пламени" % Cfg.FIRE_RING_PATCHES)
	_check(ptank.ability_cd == Cfg.FIRE_RING_COOLDOWN, "перезарядка кольца 10 с")

	world = _arena("shock", ["high_voltage", "arc_chain", "overload"])
	ptank = world.players[0].tank
	_check(ptank.has_build("shock_hunter") and ptank.ability_id == "storm_pulse", "Громовой молот собран — способность «Электробуря»")
	near = _spawn(world, 520.0, 400.0)
	near.stun_guard_ticks = 100
	far = _spawn(world, 800.0, 400.0)
	ptank.ability_cd = 0
	_check(ptank.use_ability(world), "«Электробуря» срабатывает")
	_check(near.stun_ticks > 0 and absf(near.max_hp - near.hp - Cfg.STORM_PULSE_DMG) < 0.5,
		"буря оглушает ближнего врага сквозь защиту и наносит %.0f урона" % (near.max_hp - near.hp))
	_check(far.stun_ticks == 0 and far.hp == far.max_hp, "дальний враг не задет")
	_check(ptank.ability_cd == Cfg.STORM_PULSE_COOLDOWN, "перезарядка бури 12 с")
