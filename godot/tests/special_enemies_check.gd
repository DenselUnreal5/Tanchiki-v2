extends Node

var failures := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	_check_types()
	_check_tesla()
	_check_pyro()
	_check_ai_fires()
	print("=== ПРОВЕРКА СПЕЦТАНКОВ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _arena() -> World:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, "ffa", 3131, "city")
	var world := World.new({
		"map": level["map"], "level": level, "mode": "ffa", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 3131,
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
	return world

func _spawn(world: World, type_id: String, x: float, y: float) -> Tank:
	var t: Tank = world._spawn_bot("enemy", "enemy", type_id)
	t.x = x
	t.y = y
	t.spawn_protect = 0
	t.brain = null
	return t

func _fire_at(world: World, shooter: Tank, target: Tank) -> Ent.Bullet:
	shooter.aim_at(target.x, target.y)
	shooter.fire_cooldown = 0
	var before := world.bullets.size()
	shooter.shoot(world)
	return world.bullets[before] if world.bullets.size() > before else null

func _fly(world: World, bullet, max_ticks: int = 200) -> void:
	for i in max_ticks:
		world.step()
		if bullet == null or not bullet.alive:
			return

func _check_types() -> void:
	print("[1/4] Типы врагов")
	for id in ["pyro", "tesla"]:
		var t := EnemyTypes.get_type(id)
		_check(not t.is_empty() and EnemyTypes.ORDER.has(id), "тип «%s» есть в списке врагов" % id)
		_check(not Bestiary.get_entry(id).is_empty(), "тип «%s» есть в бестиарии" % id)
	_check(String(EnemyTypes.get_type("pyro")["shot"]) == "fire", "огнемётчик стреляет огнём")
	_check(String(EnemyTypes.get_type("tesla")["shot"]) == "shock", "громовержец стреляет молнией")
	var rng := Rng.new(7)
	var seen := {}
	for i in 2000:
		seen[String(EnemyTypes.pick(1.0, rng)["id"])] = true
	_check(seen.has("pyro") and seen.has("tesla"), "оба спецтанка выпадают уже при начальной сложности")
	for mode in ["ffa", "ctf"]:
		var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
		player.reset_for_match()
		var level := LevelGen.generate(1, mode, 4040, "city")
		var world := World.new({
			"map": level["map"], "level": level, "mode": mode, "difficulty": "medium",
			"players": [player], "player_level": 1, "rng_seed": 4040,
		})
		var ids := {}
		for t in world.tanks:
			if not t.enemy_type.is_empty() and world.are_hostile(t, player.tank):
				ids[String(t.enemy_type["id"])] = true
		_check(ids.has("pyro") and ids.has("tesla"), "%s: на старте среди врагов есть оба спецтанка" % mode)
		world.dispose()

func _check_tesla() -> void:
	print("[2/4] Громовержец")
	var world := _arena()
	var ptank: Tank = world.players[0].tank
	var tesla := _spawn(world, "tesla", 400.0, 250.0)
	var b := _fire_at(world, tesla, ptank)
	_check(b != null and b.cannon_kind == "shock", "выстрел — заряд молнии")
	var grunt := _spawn(world, "grunt", 600.0, 600.0)
	grunt.brain = null
	var normal_speed: float = grunt.bullet_speed()
	_check(absf(Vector2(b.vx, b.vy).length() - normal_speed * Cfg.SHOCK_BULLET_SPEED_MULT) < 0.01, "заряд летит быстрее обычной пули")
	var hp0 := ptank.hp
	_fly(world, b)
	_check(is_equal_approx(hp0 - ptank.hp, Cfg.SHOCK_DMG), "попадание наносит %.0f урона (нанесено %.1f)" % [Cfg.SHOCK_DMG, hp0 - ptank.hp])
	_check(ptank.stun_ticks > Cfg.SHOCK_STUN_TICKS - 10 and not ptank.can_fire, "цель оглушена на ~1 с и не может стрелять")
	var stun_left := ptank.stun_ticks
	var b2 := _fire_at(world, tesla, ptank)
	_fly(world, b2)
	_check(ptank.stun_ticks < stun_left, "повторный заряд не продлевает стан (защита от цепного стана)")
	for i in Cfg.SHOCK_STUN_TICKS + 5:
		world.step()
	_check(ptank.stun_ticks == 0, "стан проходит")
	world.dispose()

func _check_pyro() -> void:
	print("[3/4] Огнемётчик")
	var world := _arena()
	var ptank: Tank = world.players[0].tank
	var pyro := _spawn(world, "pyro", 400.0, 230.0)
	var heat0 := ptank.heat
	var b := _fire_at(world, pyro, ptank)
	_check(b != null and b.cannon_kind == "fire", "выстрел — огненный снаряд")
	_fly(world, b)
	_check(world.fire_patches.size() >= 3, "снаряд выжег землю на пути (%d пятен)" % world.fire_patches.size())
	_check(ptank.burn_ticks > 0, "попадание поджигает цель")
	_check(ptank.heat >= heat0 + Cfg.BURN_HIT_HEAT - 0.01, "нагрев ствола вырос (%.2f → %.2f)" % [heat0, ptank.heat])
	ptank.x = 700.0
	ptank.y = 700.0
	var hp0 := ptank.hp
	for i in Cfg.TICK_HZ:
		world.step()
	var lost := hp0 - ptank.hp
	_check(absf(lost - Cfg.BURN_DPS) <= 2.6, "горение отнимает ~%.0f HP в секунду (за секунду %.1f)" % [Cfg.BURN_DPS, lost])
	ptank.burn_ticks = 0
	var patch = world.fire_patches[0]
	ptank.x = patch.x
	ptank.y = patch.y
	world.step()
	_check(ptank.burn_ticks > 0, "проезд через горящее пятно поджигает")
	pyro.x = patch.x + 4.0
	pyro.y = patch.y
	pyro.burn_ticks = 0
	world.step()
	_check(pyro.burn_ticks == 0, "своё пламя огнемётчика не поджигает")
	var r := world.map.row_at(ptank.y)
	var c := world.map.col_at(ptank.x)
	world.map.set_tile(r, c, Cfg.T_WATER)
	world.step()
	world.step()
	_check(ptank.burn_ticks == 0, "вода тушит горящий танк")
	world.dispose()

func _check_ai_fires() -> void:
	print("[4/4] Боты стреляют спецснарядами")
	for id in ["tesla", "pyro"]:
		var world := _arena()
		var t: Tank = world._spawn_bot("enemy", "enemy", id)
		t.x = 400.0
		t.y = 220.0
		t.spawn_protect = 0
		world.players[0].tank.spawn_protect = 100000
		var kind := String(EnemyTypes.get_type(id)["shot"])
		var seen := false
		for i in 600:
			world.step()
			for b in world.bullets:
				if b.owner == t and b.cannon_kind == kind:
					seen = true
			if seen:
				break
		_check(seen, "бот «%s» сам стреляет снарядами «%s»" % [id, kind])
		world.dispose()
