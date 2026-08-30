# ============================================================================
# perks_check.gd — проверка, что каждый перк действительно что-то делает.
#
# Список перков легко пополнить строкой в таблице, и так же легко получить
# перк, который красиво описан и ни на что не влияет. Здесь каждый новый
# перк надевается на танк, и сравнивается то число, на которое он обязан
# влиять: нагрев, ход по покрытию, урон по материалу, слышимость.
# ============================================================================
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

	# Все перки вообще есть в общем списке и открываются по уровням.
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

	# ---- нагрев ----------------------------------------------------------
	_expect("heat_sink", tank, func(): return float(tank.mods["heatCoolMult"]), 1.0, 1.6)
	_expect("thermal", tank, func(): return float(tank.mods["heatPerShotMult"]), 1.0, 0.75)
	_expect("quick_vent", tank, func(): return float(tank.mods["heatResumeAdd"]), 0.0, 0.25)

	# ---- покрытие --------------------------------------------------------
	# Ставим танк на газон и смотрим, отыгрывает ли «Вездеход» штраф.
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

		# «Шипы» — то же, но по нажатию и на любом грунте.
		tank.perk_ids = ["grip"]
		tank.recompute()
		tank.ability_cd = 0
		tank.use_ability(world)
		tank._update_surface(world)
		_check(tank.surface_speed > plain,
			"«Шипы» на газоне: %.2f -> %.2f" % [plain, tank.surface_speed])
	else:
		_check(false, "газон на карте не найден")

	# ---- материалы -------------------------------------------------------
	_expect("lumberjack", tank, func(): return float(tank.mods["woodDmgMult"]), 1.0, 2.5)
	_expect("can_opener", tank, func(): return float(tank.mods["metalDmgMult"]), 1.0, 2.5)
	_expect("concrete_breaker", tank, func(): return float(tank.mods["concreteDmgMult"]), 1.0, 2.2)

	# ---- слышимость ------------------------------------------------------
	_expect("keen_ear", tank, func(): return float(tank.mods["hearingMult"]), 1.0, 1.7)
	_expect("muffler", tank, func(): return float(tank.mods["noiseMult"]), 1.0, 0.5)

	# «Глушитель» обязан отменять оповещение ботов о выстреле.
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

	print("=== ПРОВЕРКА ПЕРКОВ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Сколько ботов пошло на звук выстрела.
func _count_alerted(world, shooter: Tank) -> int:
	for t in world.tanks:
		if t.brain != null:
			t.brain.noise_timer = 0
	# Ставим ботов рядом, чтобы дальность заведомо не мешала.
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

## Надевает перк и сверяет модификатор до и после.
func _expect(perk_id: String, tank: Tank, probe: Callable, before: float, after: float) -> void:
	tank.perk_ids = []
	tank.recompute()
	var got_before: float = probe.call()
	tank.perk_ids = [perk_id]
	tank.recompute()
	var got_after: float = probe.call()
	_check(absf(got_before - before) < 0.001 and absf(got_after - after) < 0.001,
		"%s: %.2f -> %.2f (ждали %.2f -> %.2f)" % [perk_id, got_before, got_after, before, after])

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
