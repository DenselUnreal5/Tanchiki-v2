# ============================================================================
# hazards.gd — опасный рельеф: вода, зыбучий песок, барханы.
#
# Тайл, который «должен вредить», обязан вредить измеримо. В этом проекте уже
# дважды находился код, который выглядел рабочим и не исполнялся ни разу,
# поэтому здесь всё проверяется числом: сколько HP снял тайл за секунду и
# насколько просел ход.
#
# Запуск:
#   godot --headless --path godot tests/hazards.tscn
# ============================================================================
extends Node

var failures := 0

func _ready() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["location"] = "dust"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 40:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

	var world: World = game.world
	var map: GameMap = world.map
	var tank: Tank = game.players[0].tank

	# ---- пустошь действительно пустошь ---------------------------------
	var counts := _count(map)
	print("пустошь: барханов %d, зыбучки %d, воды %d, асфальта %d"
		% [counts[Cfg.T_DUNE], counts[Cfg.T_QUICKSAND], counts[Cfg.T_WATER],
			counts[Cfg.T_ROAD]])
	_check(counts[Cfg.T_DUNE] > 200, "барханы на карте есть")
	_check(counts[Cfg.T_QUICKSAND] > 0, "зыбучий песок на карте есть")
	_check(counts[Cfg.T_WATER] > 0, "оазисы на карте есть")
	_check(world.road_kind == "dirt", "дороги пустоши — грунтовка (%s)" % world.road_kind)

	# ---- урон от воды и зыбучки ----------------------------------------
	var water_dps := _hazard_dps(world, tank, Cfg.T_WATER, [])
	print("вода: %.0f урона/с" % water_dps)
	_check(water_dps > 5.0, "вода наносит урон")

	var amph := _hazard_dps(world, tank, Cfg.T_WATER, ["amphibious"])
	print("вода с «Амфибией»: %.0f урона/с" % amph)
	_check(amph == 0.0, "«Амфибия» спасает от воды")

	var quick_dps := _hazard_dps(world, tank, Cfg.T_QUICKSAND, [])
	print("зыбучий песок: %.0f урона/с" % quick_dps)
	_check(quick_dps > 5.0, "зыбучий песок наносит урон")

	var quick_amph := _hazard_dps(world, tank, Cfg.T_QUICKSAND, ["amphibious"])
	print("зыбучка с «Амфибией»: %.0f урона/с" % quick_amph)
	_check(quick_amph > 5.0, "«Амфибия» от зыбучки НЕ спасает")

	# ---- ход по покрытиям ----------------------------------------------
	var road := _surface_speed(world, tank, Cfg.T_ROAD)
	var sand := _surface_speed(world, tank, Cfg.T_SAND)
	var dune := _surface_speed(world, tank, Cfg.T_DUNE)
	var quick := _surface_speed(world, tank, Cfg.T_QUICKSAND)
	print("ход: грунтовка %.2f, песок %.2f, бархан %.2f, зыбучка %.2f"
		% [road, sand, dune, quick])
	_check(dune < sand, "бархан медленнее песка")
	_check(quick < dune, "зыбучка медленнее бархана")
	_check(road > sand, "дорога быстрее песка даже без асфальта")

	# ---- погода по локациям --------------------------------------------
	for loc_id in Locations.ORDER:
		var loc := Locations.get_location(loc_id)
		var seen := _weather_run(loc)
		var banned := []
		for k in seen:
			if not loc["weather"].has(k):
				banned.append(k)
		print("%s: за 300 смен погоды встретилось %s" % [loc_id, str(seen)])
		_check(banned.is_empty(),
			"%s не получает запрещённой погоды (лишнее: %s)" % [loc_id, str(banned)])
	var dust_loc := Locations.get_location("dust")
	_check(not dust_loc["weather"].has("snow"), "в пустоши не идёт снег")

	print("=== ПРОВЕРКА РЕЛЬЕФА ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ замеры
## Урон в секунду от стояния на тайле. Танк держится живым принудительно:
## считается скорость урона, а не то, сколько он протянет.
func _hazard_dps(world: World, tank: Tank, tile: int, perks: Array) -> float:
	var spot := _find(world.map, tile)
	if spot.x < 0:
		_check(false, "тайл %d на карте не найден" % tile)
		return 0.0
	tank.perk_ids = perks
	tank.recompute()
	tank.x = spot.y * Cfg.TILE + Cfg.TILE * 0.5
	tank.y = spot.x * Cfg.TILE + Cfg.TILE * 0.5
	tank.hp = tank.max_hp
	tank.water_timer = 0
	tank.quicksand_timer = 0
	var before := tank.hp
	for i in 60:
		tank._check_water(world)
	var lost := before - tank.hp
	tank.perk_ids = []
	tank.recompute()
	tank.hp = tank.max_hp
	return lost

## Множитель хода на тайле.
func _surface_speed(world: World, tank: Tank, tile: int) -> float:
	var spot := _find(world.map, tile)
	if spot.x < 0:
		return -1.0
	tank.x = spot.y * Cfg.TILE + Cfg.TILE * 0.5
	tank.y = spot.x * Cfg.TILE + Cfg.TILE * 0.5
	tank._update_surface(world)
	return tank.surface_speed

## Триста смен погоды подряд: если запрещённое условие вообще может выпасть,
## за столько попыток оно выпадет.
func _weather_run(loc: Dictionary) -> Array:
	var wx := WeatherSystem.new(12345, {"allowed": loc.get("weather", [])})
	var seen := {}
	for i in 300:
		wx._pick_next()
		seen[wx.condition] = true
	return seen.keys()

func _count(map: GameMap) -> Dictionary:
	var out := {}
	for t in [Cfg.T_DUNE, Cfg.T_QUICKSAND, Cfg.T_WATER, Cfg.T_ROAD]:
		out[t] = 0
	for r in map.rows:
		for c in map.cols:
			var t := map.get_tile(r, c)
			if out.has(t):
				out[t] += 1
	return out

func _find(map: GameMap, tile: int) -> Vector2i:
	for r in range(2, map.rows - 2):
		for c in range(2, map.cols - 2):
			if map.get_tile(r, c) == tile:
				return Vector2i(r, c)
	return Vector2i(-1, -1)

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
