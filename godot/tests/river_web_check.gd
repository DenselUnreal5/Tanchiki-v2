extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
func _ready() -> void:
	var validator = load("res://tests/map_check.gd").new()
	var signatures := {}
	var minimum_junctions := 1000
	var minimum_loops := 1000
	for seed_value in range(32):
		var level := LevelGen.generate(-1, "ffa", seed_value, "city")
		var map: GameMap = level.map
		var graph: Dictionary = level.plan.river
		minimum_junctions = mini(minimum_junctions, int(graph.get("junctions", 0)))
		minimum_loops = mini(minimum_loops, int(graph.get("loops", 0)))
		check(int(graph.get("junctions", 0)) >= 3, "seed %d has several junctions: %s" % [seed_value, graph])
		check(int(graph.get("loops", 0)) >= 1, "seed %d has loops: %s" % [seed_value, graph])
		check(int(graph.get("bridges", 999)) <= RiverWeb.BRIDGE_BUDGET, "bridge budget")
		check(validator._walkable_share(map) >= 0.97, "seed %d remains reachable" % seed_value)
		var water := map.tiles.count(Cfg.T_WATER)
		check(water > 50 and water < map.tiles.size() / 5, "water density remains playable")
		for r in map.rows:
			check(map.get_tile(r, 0) == Cfg.T_WALL and map.get_tile(r, map.cols - 1) == Cfg.T_WALL, "side boundary")
		for c in map.cols:
			check(map.get_tile(0, c) == Cfg.T_WALL and map.get_tile(map.rows - 1, c) == Cfg.T_WALL, "top/bottom boundary")
		signatures[hash(map.tiles)] = true
		if seed_value < 8:
			check(map.tiles == (LevelGen.generate(-1, "ffa", seed_value, "city").map as GameMap).tiles, "identical seed reproduces tile map")
	check(signatures.size() == 32, "different seeds produce different layouts")
	for location in Locations.ORDER:
		for mode in ["ffa", "ctf", "koth", "defense"]:
			var level := LevelGen.generate(-1, mode, 2026, location)
			var map: GameMap = level.map
			var rng := Rng.new(76)
			for team in ["player", "enemy"]:
				for attempt in 8:
					var spot := map.find_free_spot(rng, level.areas[team], 26, 30)
					check(not map.is_blocked_rect(spot.x, spot.y, 26, 30), "%s/%s/%s spawn fits tank" % [location, mode, team])
					check(GameMap.is_drivable_tile(map.get_tile(map.row_at(spot.y), map.col_at(spot.x))), "spawn is on land or bridge")
	validator.free()
	print("RIVER WEB: seeds=32, distinct=%d, min junctions=%d, min loops=%d, spawn samples=448, failures=%d" % [signatures.size(), minimum_junctions, minimum_loops, failures])
	get_tree().quit(1 if failures else 0)
