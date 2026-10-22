extends Node

var failures := 0

func _ready() -> void:
	for location in Locations.ORDER:
		var level := LevelGen.generate(1, "ffa", 42, location)
		var map := GameMap.new(12, 10)
		map.fill(Cfg.T_SAND)
		level["map"] = map
		var world := World.new({"map": map, "level": level, "mode": "ffa", "players": [], "puppet": true})
		for tile in [Cfg.T_BRICK, Cfg.T_ADOBE, Cfg.T_TREE]:
			for row in range(2, 8):
				map.set_tile(row, 4, tile)
				for shot in 100:
					var bullet := Ent.Bullet.new(144, row * Cfg.TILE + 16, 0, null)
					bullet.dmg_scale = 1.0
					bullet._hit_tiles(world)
					if map.get_tile(row, 4) == Cfg.T_EMPTY:
						break
				_check(map.get_tile(row, 4) == Cfg.T_EMPTY, "%s: shots destroy tile %d/material %d" % [location, tile, Materials.variant_at(row, 4)])
			map.set_tile(5, 5, tile)
			var bomb := Ent.Bullet.new(176, 176, 0, null)
			for hit in 30:
				bomb._explode(world, null, 100)
			_check(map.get_tile(5, 5) == Cfg.T_EMPTY, location + ": explosions destroy scenery")
		map.set_tile(5, 5, Cfg.T_WALL)
		for hit in 30:
			world.hit_building(5, 5, 9999, "blast", 176, 176, null)
		_check(map.get_tile(5, 5) == Cfg.T_WALL and map.damage[65] == 0, location + ": indestructible blocks survive")
		var generator := Ent.PowerGenerator.new(240, 240)
		world.power_generators.append(generator)
		for shot in 30:
			var bullet := Ent.Bullet.new(240, 240, 0, null)
			bullet.dmg_scale = 1.0
			bullet._hit_generators(world)
		_check(not generator.alive and generator.hp == 0, location + ": shots destroy generators")
		generator.discharge(world, "player")
		_check(generator.cooldown == 0, "destroyed generator cannot discharge")
		var game = load("res://scenes/main.tscn").instantiate()
		game.world = world
		var snapshot: Dictionary = game._net_extra()
		world.power_generators.clear()
		game._apply_net_extra(snapshot)
		_check(world.power_generators.size() == 1 and not world.power_generators[0].alive,
			"destroyed generator persists in multiplayer snapshots")
		game.free()
		map.fill(Cfg.T_SAND)
		map.set_tile(3, 1, Cfg.T_ROAD)
		if location == "dust":
			_check(not map.has_lamp(3, 1), "desert roads have no city streetlights")
		else:
			_check(map.has_lamp(3, 1), "streetlight fixture exists")
			var bullet := Ent.Bullet.new(48, 112, 0, null)
			bullet.dmg_scale = 1.0
			bullet._hit_tiles(world)
			_check(not map.has_lamp(3, 1) and map.get_tile(3, 1) == Cfg.T_ROAD, "shots destroy lamps while preserving roads")
			var remote := GameMap.new(12, 10)
			remote.apply_snapshot_bytes(map.snapshot_bytes())
			_check(not remote.has_lamp(3, 1), "destroyed lamp persists in network snapshots")
		map.fill(Cfg.T_GRASS)
		var bush_found := false
		for r in range(2, 8):
			for c in range(2, 10):
				if map.has_bush(r, c):
					bush_found = true
					world.hit_building(r, c, 999, "blast", c * 32 + 16, r * 32 + 16, null)
					_check(not map.has_bush(r, c), "explosions destroy bushes")
		_check(bush_found, "bush destruction exercised")
	for mode in ["ffa", "ctf", "defense"]:
		for seed_value in [42, 84, 7777, 12345]:
			var level := LevelGen.generate(1, mode, seed_value, "dust")
			var repeat := LevelGen.generate(1, mode, seed_value, "dust")
			var map: GameMap = level.map
			_check(map.tiles == repeat.map.tiles, "deterministic desert: %s/%d" % [mode, seed_value])
			_check(map.tiles.count(Cfg.T_QUICKSAND) > 0, "quicksand present: %s/%d" % [mode, seed_value])
			for home in level.homes.values():
				if home != null:
					_check(map.tile_at_pixel(home.x, home.y) != Cfg.T_QUICKSAND, "base is safe")
	var road := TerrainTextures.road(1, "dust").get_image()
	for y in road.get_height():
		for x in road.get_width():
			var color := road.get_pixel(x, y)
			_check(color.r > color.b and color.r > 0.4, "sandy roads contain no asphalt or white paint")
	print("DESERT ENVIRONMENT failures=", failures)
	get_tree().quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
