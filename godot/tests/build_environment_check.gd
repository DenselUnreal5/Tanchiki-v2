extends Node

var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)

func make_world() -> World:
	var map := GameMap.new(40, 40)
	map.fill(Cfg.T_GRASS)
	for r in map.rows: map.set_tile(r, 10, Cfg.T_WATER)
	map.set_tile(20, 10, Cfg.T_BRIDGE)
	map.set_tile(2, 2, Cfg.T_BASE_P)
	map.set_tile(7, 7, Cfg.T_WALL)
	var world := World.new({"map": map, "level": {"seed": 42}, "mode": "ffa", "difficulty": "medium", "players": [], "puppet": true, "rng_seed": 17})
	world.tanks = [make_tank(128, 128, "player", 7), make_tank(800, 800, "enemy", 8)]
	world.puppet = false
	return world

func make_tank(x: float, y: float, team: String, net_id: int) -> Tank:
	var tank := Tank.new({"x": x, "y": y, "team": team, "name": "Test", "net_id": net_id, "max_hp": 100.0, "speed": 2.0, "fire_rate": 30})
	tank.spawn_protect = 0
	return tank

func _ready() -> void:
	var world := make_world()
	var owner: Tank = world.tanks[0]
	var enemy: Tank = world.tanks[1]
	var env := world.build_environment
	var rng_state := world.rng.state
	for id in BuildEnvironment.IDS:
		env.activate(world, owner, id)
		check(env.active.has(id), id + ": terrain influence activates")
		var count := 0
		for zone in env.zones:
			if zone.id == id: count += 1
		check(count > 0 and count <= BuildEnvironment.ZONES_PER_BUILD, id + ": bounded areas appear")
		var size := env.zones.size()
		env.activate(world, enemy, id)
		check(env.zones.size() == size and env.active[id].owner == 7, id + ": repeated build cannot multiply or steal terrain")
	check(world.rng.state == rng_state, "terrain placement preserves combat RNG")
	for zone in env.zones:
		check(env._safe_cell(world, world.map.row_at(zone.y), world.map.col_at(zone.x)), "zone avoids structures, bridges, spawn and base approaches")
	var first: Dictionary = env.zones[0]
	enemy.x = first.x
	enemy.y = first.y
	world.tick = 60
	env.update(world)
	check(enemy.hp == 100 and enemy.acid_stacks == 0, "warning period has no damage or status")
	world.tick = 120
	env.update(world)
	check(enemy.hp < 100 and enemy.acid_stacks > 0, "acid puddle damages and corrodes hostile tank")
	check(owner.hp == 100 and owner.acid_stacks == 0, "owner is immune to own environmental hazards")
	check(env.speed_multiplier(world, enemy) == 0.8, "acid puddle slows hostile tank")
	check(world.map.get_tile(2, 2) == Cfg.T_BASE_P and world.map.get_tile(7, 7) == Cfg.T_WALL and world.map.get_tile(20, 10) == Cfg.T_BRIDGE, "protected tiles remain unchanged")
	var trees := 0
	for tile in world.map.tiles:
		if tile == Cfg.T_TREE: trees += 1
	check(trees > 0, "forest build grows real drivable trees")
	var version := world.map.version
	env.update(world)
	check(world.map.version == version, "groves are planted once and do not regrow every update")
	for id in ["ice_hunter", "fire_hunter", "shock_hunter", "juggernaut", "ghost_sniper", "fortress", "gunner"]:
		for zone in env.zones:
			if zone.id != id: continue
			enemy.x = zone.x
			enemy.y = zone.y
			enemy.hp = 100
			enemy.burn_ticks = 0
			enemy.stun_ticks = 0
			enemy.stun_guard_ticks = 0
			env.update(world)
			match id:
				"ice_hunter": check(env.speed_multiplier(world, enemy) == 0.65, "ice field slows enemies")
				"fire_hunter": check(enemy.burn_ticks > 0, "embers ignite hostile tank")
				"shock_hunter": check(enemy.hp < 100 and enemy.stun_ticks > 0, "electric field damages and stuns")
				"juggernaut":
					check(env.speed_multiplier(world, enemy) == 0.8, "rubble slows enemies")
					owner.x = zone.x
					owner.y = zone.y
					check(env.speed_multiplier(world, owner) == 1.12, "rubble gives owner traction advantage")
				"ghost_sniper":
					owner.x = enemy.x + 200
					owner.y = enemy.y
					check(env.obscured(world, owner, enemy), "fog hides distant enemies")
					check(BotBrain.find_best_threat(owner, world) == null, "AI respects local fog")
					owner.x = enemy.x + 100
					check(not env.obscured(world, owner, enemy), "fog reveals close threats")
				"fortress", "gunner":
					owner.x = zone.x
					owner.y = zone.y
					owner.hp = 50
					owner.heat = 50
					env.update(world)
					check(owner.hp == 51 if id == "fortress" else owner.heat == 45, id + ": supply field benefits holder")
					check(enemy.hp == 100, id + ": hostile tank receives no repair")
			break
	# A converted river remains water for movement; banks are hazardous, bridge is safe.
	enemy.x = 10 * Cfg.TILE - 4
	enemy.y = 10.5 * Cfg.TILE
	enemy.hp = 100
	check(env._near_water(world, enemy), "river bank is included in transformed water")
	env.update(world)
	check(enemy.hp < 100 and world.map.get_tile(10, 10) == Cfg.T_WATER, "river transformation has gameplay without changing passability")
	enemy.x = 10.5 * Cfg.TILE
	enemy.y = 20.5 * Cfg.TILE
	check(not env._near_water(world, enemy), "bridge crossing is safe")
	var net := env.snapshot(world.tick)
	var packet := NetProtocol.encode_snapshot(1, 120, [], [], {"build_environment": net})
	var decoded := NetProtocol.decode_snapshot(packet)
	var client := make_world()
	client.puppet = true
	client.tick = 800
	client.build_environment.apply_snapshot(client, decoded.extra.build_environment)
	check(client.build_environment.snapshot(client.tick) == net, "snapshot preserves owners, zones and warning ages across different clocks")
	var hp: float = client.tanks[1].hp
	client.build_environment.update(client)
	check(client.tanks[1].hp == hp, "puppet never simulates environmental damage")
	client.build_environment.apply_snapshot(client, {"builds": [["bad", 1, 0]], "zones": [["bad", 1, 1]]})
	check(client.build_environment.active.is_empty() and client.build_environment.zones.is_empty(), "unknown remote builds are discarded")
	owner.alive = false
	check(env.ready_at(world, "acid_hunter"), "terrain persists after holder death")
	world.dispose()
	client.dispose()
	check(env.active.is_empty() and env.zones.is_empty(), "match cleanup removes all influence")
	var integration := make_world()
	integration.tanks[0].perk_ids = Perks.get_build("acid_hunter").perks.duplicate()
	integration.check_tank_synergies(integration.tanks[0])
	check(integration.build_environment.active.has("acid_hunter"), "real completed synergy activates terrain")
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.world = integration
	var extra: Dictionary = game._net_extra()
	check(extra.build_environment.builds.size() == 1, "host includes terrain in actual game snapshots")
	var remote := make_world()
	remote.puppet = true
	game.world = remote
	game._apply_net_extra(extra)
	check(remote.build_environment.active.has("acid_hunter"), "actual client snapshot handler applies terrain")
	game._apply_net_extra({"score": {"player": 0, "enemy": 0}})
	check(remote.build_environment.active.has("acid_hunter"), "older snapshot without terrain field remains compatible")
	remote.dispose()
	game.world = null
	game.queue_free()
	integration.dispose()
	var respawn_world := make_world()
	var dead: Tank = respawn_world.tanks[0]
	dead.alive = false
	dead.perk_ids = Perks.get_build("ice_hunter").perks.duplicate()
	respawn_world.check_tank_synergies(dead)
	check(respawn_world.build_environment.active.is_empty(), "dead holder does not modify terrain")
	dead.respawn(128, 128)
	respawn_world.check_tank_synergies(dead)
	check(respawn_world.build_environment.active.has("ice_hunter"), "build equipped while dead activates after respawn")
	respawn_world.dispose()
	for location in Locations.ORDER:
		for mode in ["ffa", "ctf", "koth", "defense"]:
			var level := LevelGen.generate(1, mode, 42, location)
			var generated := World.new({"map": level.map, "level": level, "mode": mode, "difficulty": "medium", "players": [], "puppet": true})
			generated.puppet = false
			var holder := make_tank(64, 64, "player", 7)
			generated.tanks = [holder]
			var before := Time.get_ticks_usec()
			generated.build_environment.activate(generated, holder, "acid_hunter")
			var elapsed := (Time.get_ticks_usec() - before) / 1000.0
			check(not generated.build_environment.zones.is_empty(), "%s/%s: real generated map has puddles (%.1f ms)" % [location, mode, elapsed])
			generated.dispose()
	print("=== BUILD ENVIRONMENT: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
