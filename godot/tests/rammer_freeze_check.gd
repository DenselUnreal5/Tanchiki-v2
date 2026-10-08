extends Node

func _ready() -> void:
	print("--- START RAMMER FREEZE REPRO TEST ---")
	test_rammer_freeze_during_charge()
	print("--- TEST COMPLETED SUCCESSFULLY ---")
	get_tree().quit(0)

func test_rammer_freeze_during_charge() -> void:
	var seed_val := 42
	var level := LevelGen.generate(1, "koth", seed_val, Locations.CITY, "arena")
	var p0 := PlayerState.new(0, "Player 1", "p1", Ctl.MouseAimScheme.new(0))
	p0.equipped_cannon = "freeze"
	
	var world := World.new({
		"map": level["map"], "level": level, "mode": "koth",
		"difficulty": "normal",
		"players": [p0],
		"player_level": 1,
		"puppet": false,
		"weather": "clear",
		"daytime": "noon",
		"rng_seed": seed_val,
	})
	
	var player_tank = p0.tank
	print("Player tank: %s at (%.1f, %.1f), hp=%.1f" % [player_tank.name, player_tank.x, player_tank.y, player_tank.hp])
	
	# Find or spawn rammer boss
	var rammer_tank: Tank = null
	for t in world.tanks:
		if t.is_rammer_boss:
			rammer_tank = t
			break
	if rammer_tank == null:
		rammer_tank = world._spawn_bot("enemy", "enemy", "boss_rammer")
	
	rammer_tank.x = player_tank.x + 120.0
	rammer_tank.y = player_tank.y
	print("Rammer boss at (%.1f, %.1f), hp=%.1f" % [rammer_tank.x, rammer_tank.y, rammer_tank.hp])
	
	# Force rammer to charge player
	rammer_tank.start_rammer_charge(player_tank.x, player_tank.y, world)
	print("Rammer state: %s, telegraph: %d" % [rammer_tank.rammer_state, rammer_tank.rammer_telegraph_ticks])
	
	var ticks := 0
	while rammer_tank.rammer_state != "charge" and ticks < 50:
		world.step()
		ticks += 1
	
	print("Rammer entered charge at tick %d, pos=(%.1f, %.1f)" % [ticks, rammer_tank.x, rammer_tank.y])
	
	# FREEZE RAMMER!
	rammer_tank.spawn_protect = 0
	print("player mods keys: ", player_tank.mods.keys())
	print("player freezeDurationMult: ", player_tank.mods.get("freezeDurationMult"))
	var res_f = rammer_tank.apply_freeze(world, player_tank, Cfg.ICE_FREEZE_TICKS)
	print("FREEZE APPLIED: %s, freeze_ticks=%d" % [str(res_f), rammer_tank.freeze_ticks])
	
	# Simulate steps
	for step_i in range(120):
		print("STEP %d: rammer=(%.1f, %.1f) state=%s freeze=%d player_hp=%.1f" % [
			step_i, rammer_tank.x, rammer_tank.y, rammer_tank.rammer_state, rammer_tank.freeze_ticks, player_tank.hp
		])
		world.step()
		if not player_tank.alive:
			print("Player died at step %d" % step_i)
			break
		if not rammer_tank.alive:
			print("Rammer died at step %d" % step_i)
			break

	print("Finished sim loop successfully!")
