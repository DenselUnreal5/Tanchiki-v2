extends Node

var game: Node
var failures := 0

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

	var world = game.world
	var tank: Tank = game.players[0].tank

	var total := Perks.all().size()
	var unlockable := {}
	for lvl in Perks.UNLOCK_TABLE.keys():
		for id in Perks.UNLOCK_TABLE[lvl]:
			unlockable[id] = true
	var orphans := []
	for p in Perks.all():
		if not unlockable.has(p["id"]) and not p.has("challenge"):
			orphans.append(String(p["id"]))
	print("перков всего: %d, из них открываются по уровням: %d" % [total, unlockable.size()])
	if not orphans.is_empty():
		print("  не открываются ничем: %s" % str(orphans))

	_expect("heat_sink", tank, func(): return float(tank.mods["heatCoolMult"]), 1.0, 1.6)
	_expect("thermal", tank, func(): return float(tank.mods["heatPerShotMult"]), 1.0, 0.75)
	_expect("quick_vent", tank, func(): return float(tank.mods["heatResumeAdd"]), 0.0, 0.25)

	var map = world.map
	var spot := _find_tile(map, Cfg.T_GRASS)
	if spot.x >= 0:
		tank.x = spot.y * Cfg.TILE + 16.0
		tank.y = spot.x * Cfg.TILE + 16.0
		tank.perk_ids = []
		tank.recompute()
		tank._update_surface(world)
		var plain := tank.surface_speed
		tank.perk_ids = ["all_terrain"]
		tank.recompute()
		tank._update_surface(world)
		var gripped := tank.surface_speed
		_check(gripped > plain, "«Вездеход» на газоне: %.2f -> %.2f" % [plain, gripped])

		tank.perk_ids = ["grip"]
		tank.recompute()
		tank.ability_cd = 0
		tank.use_ability(world)
		tank._update_surface(world)
		_check(tank.surface_speed > plain,
			"«Шипы» на газоне: %.2f -> %.2f" % [plain, tank.surface_speed])
	else:
		_check(false, "газон на карте не найден")

	_check_wood_pierce(world, tank)
	_expect("can_opener", tank, func(): return float(tank.mods["metalDmgMult"]), 1.0, 2.5)
	_expect("concrete_breaker", tank, func(): return float(tank.mods["concreteDmgMult"]), 1.0, 2.2)

	_expect("keen_ear", tank, func(): return float(tank.mods["hearingMult"]), 1.0, 1.7)
	_expect("muffler", tank, func(): return float(tank.mods["noiseMult"]), 1.0, 0.5)
	_expect("muffler", tank, func(): return float(tank.mods["ambushDmgMult"]), 1.0, 1.5)

	_expect("rapid_fire", tank, func(): return float(tank.mods["heatPerShotMult"]), 1.0, 0.7)
	_expect("quick_reload", tank, func(): return float(tank.mods["heatPerShotMult"]), 1.0, 0.55)

	tank.cannon_id = "standard"
	_check(_bullets_fired(world, tank, ["fan_shot"]) == 3, "«Веер» сам по себе даёт 3 пули")
	_check(_bullets_fired(world, tank, ["double_shot"]) == 2, "«Двойной ствол» сам по себе даёт 2 пули")
	_check(_bullets_fired(world, tank, ["fan_shot", "double_shot"]) == 6,
		"«Веер»+«Двойной ствол» вместе дают 6 пуль, а не побеждает один из них")

	tank.perk_ids = ["silencer"]
	tank.recompute()
	tank.ability_cd = 0
	tank.use_ability(world)
	var heard_silent := _count_alerted(world, tank)
	tank.ability_timer = 0
	for t in world.tanks:
		if t.brain != null:
			t.brain.noise_timer = 0
	var heard_loud := _count_alerted(world, tank)
	_check(heard_silent == 0 and heard_loud > 0,
		"«Глушитель»: услышали %d ботов, без него %d" % [heard_silent, heard_loud])

	world.shot_pings.clear()
	world.notify_shot(tank)
	_check(not world.shot_pings.is_empty(),
		"«Острый слух»: выстрел попал в отметки миникарты (%d)" % world.shot_pings.size())

	_check_unlock_table()
	_check_cannon_filter()
	_check_profile_recalc()
	var foe: Tank = _pick_foe(world, tank)
	if foe == null:
		_check(false, "второй танк для проверок урона не найден")
	else:
		_check_reflect_stun(world, tank, foe)
		_check_silencer_ambush(world, tank, foe)
		_check_ice_build_boss(world, tank, foe)

	print("=== ПРОВЕРКА ПЕРКОВ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check_unlock_table() -> void:
	var seen := {}
	var dupes := []
	var max_level := 0
	for lvl in Perks.UNLOCK_TABLE.keys():
		max_level = maxi(max_level, int(lvl))
		for id in Perks.UNLOCK_TABLE[lvl]:
			if seen.has(id):
				dupes.append(id)
			seen[id] = int(lvl)
	_check(dupes.is_empty(), "в таблице уровней нет дублей: %s" % str(dupes))
	var unknown := []
	for id in seen.keys():
		if Perks.get_perk(String(id)).is_empty():
			unknown.append(id)
	_check(unknown.is_empty(), "все перки таблицы существуют: %s" % str(unknown))
	var orphans := []
	var misplaced := []
	for p in Perks.all():
		var in_table: bool = seen.has(p["id"])
		if p.has("challenge") and in_table:
			misplaced.append(String(p["id"]))
		if not p.has("challenge") and not in_table:
			orphans.append(String(p["id"]))
	_check(orphans.is_empty(), "каждый нечелленджевый перк открывается по уровню: %s" % str(orphans))
	_check(misplaced.is_empty(), "челленджевые перки не лежат в таблице: %s" % str(misplaced))
	_check(max_level <= 20, "последний уровень таблицы: %d (максимум 20)" % max_level)
	_check(Perks.UNLOCK_TABLE[1].size() >= 3, "на первом уровне открыто не меньше трёх перков")
	var dependent: Array = Perks.CANNON_REQUIRED.keys() + ["lightning_lord", "sky_strike", "chain_lightning"]
	var early := []
	for id in dependent:
		if int(seen.get(id, 0)) < 10:
			early.append(id)
	_check(early.is_empty(), "перки, зависящие от пушки или грозы, не раньше 10-го уровня: %s" % str(early))

func _check_cannon_filter() -> void:
	for id in ["explosive", "piercing", "sky_strike", "fan_shot", "double_shot"]:
		_check(not Perks.is_perk_allowed_for_cannon(id, "ice") and not Perks.is_perk_allowed_for_cannon(id, "acid"),
			"%s не предлагается с ледяной и кислотной пушкой" % id)
		_check(Perks.is_perk_allowed_for_cannon(id, "standard") and Perks.is_perk_allowed_for_cannon(id, ""),
			"%s предлагается с обычной пушкой" % id)

func _check_profile_recalc() -> void:
	var profile = load("res://scripts/profile.gd").new()
	profile._empty_stats()
	profile._empty_upgrades()
	profile._apply({"globalLevel": 5, "unlocked": ["heat_sink", "rapid_fire", "ram"]})
	_check(not profile.unlocked.has("heat_sink") and not profile.unlocked.has("rapid_fire"),
		"перки таблицы из старого сейва не переносятся, а пересчитываются по уровню")
	_check(profile.unlocked.has("ram"), "челленджевый перк из сейва сохраняется")
	profile.free()

func _pick_foe(world, tank: Tank) -> Tank:
	for t in world.tanks:
		if t != tank and t.alive:
			return t
	return null

func _prepare_duel(tank: Tank, foe: Tank) -> void:
	tank.spawn_protect = 0
	foe.spawn_protect = 0
	foe.perk_ids = []
	foe.recompute()
	foe.hp = foe.max_hp
	foe.stun_ticks = 0
	foe.is_boss = false
	tank.hp = tank.max_hp

func _check_reflect_stun(world, tank: Tank, foe: Tank) -> void:
	tank.perk_ids = ["reflect"]
	tank.recompute()
	_prepare_duel(tank, foe)
	world.deal_damage(tank, 10.0, foe, "acid")
	_check(foe.stun_ticks == 0, "«Отражение»: тики кислоты не оглушают атакующего (%d)" % foe.stun_ticks)
	tank.hp = tank.max_hp
	world.deal_damage(tank, 10.0, foe, "bullet")
	_check(foe.stun_ticks == Cfg.REFLECT_STUN_TICKS,
		"«Отражение»: попадание пули оглушает на %d тиков (%d)" % [Cfg.REFLECT_STUN_TICKS, foe.stun_ticks])
	foe.stun_ticks = 0
	foe.is_boss = true
	tank.hp = tank.max_hp
	world.deal_damage(tank, 10.0, foe, "bullet")
	_check(foe.stun_ticks == 0, "«Отражение»: боссов не оглушает")
	foe.is_boss = false
	tank.perk_ids = []
	tank.recompute()

func _check_silencer_ambush(world, tank: Tank, foe: Tank) -> void:
	tank.perk_ids = ["silencer"]
	tank.recompute()
	_prepare_duel(tank, foe)
	foe.last_attacker = tank
	foe.last_attacker_tick = world.tick
	var plain: float = world.deal_damage(foe, 10.0, tank, "bullet")
	foe.hp = foe.max_hp
	tank.ability_cd = 0
	tank.use_ability(world)
	foe.last_attacker = tank
	foe.last_attacker_tick = world.tick
	var silenced: float = world.deal_damage(foe, 10.0, tank, "bullet")
	_check(plain > 0.0 and absf(silenced / plain - Cfg.SILENCER_AMBUSH_MULT) < 0.01,
		"«Глушитель»: удар из засады %.1f против обычного %.1f (×%.2f)" % [silenced, plain, Cfg.SILENCER_AMBUSH_MULT])
	tank.ability_timer = 0
	tank.perk_ids = []
	tank.recompute()

func _check_ice_build_boss(world, tank: Tank, foe: Tank) -> void:
	tank.perk_ids = ["deep_freeze", "frost_dash", "chilled_barrel"]
	tank.recompute()
	_prepare_duel(tank, foe)
	foe.is_boss = true
	var before := foe.hp
	world.maybe_freeze_shot_kill(foe, tank)
	_check(foe.alive and is_equal_approx(foe.hp, before), "«Абсолютный ноль»: босс не гибнет и не теряет прочность от выстрела")
	foe.is_boss = false
	tank.perk_ids = []
	tank.recompute()

func _check_wood_pierce(world, tank: Tank) -> void:
	var map = world.map
	var spot := Vector2i(-1, -1)
	for r in range(4, map.rows - 4):
		for c in range(4, map.cols - 5):
			if String(Materials.at(r, c)["id"]) == "wood" 					and String(Materials.at(r, c + 1)["id"]) == "wood":
				spot = Vector2i(r, c)
				break
		if spot.x >= 0:
			break
	if spot.x < 0:
		_check(false, "две деревянные клетки подряд на карте не нашлись")
		return

	var survived := 0
	for use_perk in [false, true]:
		map.set_tile(spot.x, spot.y, Cfg.T_BRICK)
		map.set_tile(spot.x, spot.y + 1, Cfg.T_BRICK)
		tank.perk_ids = ["lumberjack"] if use_perk else []
		tank.recompute()
		tank.x = float(spot.y * Cfg.TILE) - Cfg.TILE
		tank.y = float(spot.x * Cfg.TILE) + Cfg.TILE * 0.5
		world.bullets.clear()
		var b = Ent.Bullet.new(tank.x, tank.y, 0.0, tank, Cfg.PLAYER_DMG_MULT)
		world.bullets.append(b)
		for i in 40:
			world.step()
			if not b.alive:
				break
		var broken := 0
		if map.get_tile(spot.x, spot.y) != Cfg.T_BRICK:
			broken += 1
		if map.get_tile(spot.x, spot.y + 1) != Cfg.T_BRICK:
			broken += 1
		if use_perk:
			_check(broken == 2, "«Лесоруб»: одна пуля снесла построек: %d из 2" % broken)
		else:
			survived = broken
			_check(broken == 1, "без перка одна пуля сносит построек: %d (ждали 1)" % broken)
	tank.perk_ids = []
	tank.recompute()

func _count_alerted(world, shooter: Tank) -> int:
	for t in world.tanks:
		if t.brain != null:
			t.brain.noise_timer = 0
	var n := 0
	for t in world.tanks:
		if t == shooter or t.brain == null:
			continue
		t.x = shooter.x + 60.0
		t.y = shooter.y + 60.0
		t.alive = true
		n += 1
		if n >= 3:
			break
	world.notify_shot(shooter)
	var heard := 0
	for t in world.tanks:
		if t.brain != null and t.brain.noise_timer > 0:
			heard += 1
	return heard

func _find_tile(map: GameMap, tile: int) -> Vector2i:
	for r in range(2, map.rows - 2):
		for c in range(2, map.cols - 2):
			if map.get_tile(r, c) == tile:
				return Vector2i(r, c)
	return Vector2i(-1, -1)

func _expect(perk_id: String, tank: Tank, probe: Callable, before: float, after: float) -> void:
	tank.perk_ids = []
	tank.recompute()
	var got_before: float = probe.call()
	tank.perk_ids = [perk_id]
	tank.recompute()
	var got_after: float = probe.call()
	_check(absf(got_before - before) < 0.001 and absf(got_after - after) < 0.001,
		"%s: %.2f -> %.2f (ждали %.2f -> %.2f)" % [perk_id, got_before, got_after, before, after])

func _bullets_fired(world, tank: Tank, perk_ids: Array) -> int:
	tank.perk_ids = perk_ids
	tank.recompute()
	tank.fire_cooldown = 0
	tank.heat = 0.0
	tank.overheated = false
	var before: int = world.bullets.size()
	tank.shoot(world)
	return world.bullets.size() - before

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
