extends Node

var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)

func _ready() -> void:
	var tank := Tank.new({"x": 64, "y": 64, "team": "player", "name": "Build", "max_hp": 100.0, "speed": 2.0, "fire_rate": 30, "net_id": 7})
	for build in Perks.BUILDS:
		tank.perk_ids = (build.perks as Array).slice(0, 2)
		tank.build_fx_started.clear()
		TankBuildFx.sync(tank, 10)
		check(TankBuildFx.active(tank).is_empty(), build.id + ": incomplete build has no effect")
		tank.perk_ids = (build.perks as Array).duplicate()
		var hp := tank.hp
		var mods := tank.mods.duplicate(true)
		TankBuildFx.sync(tank, 20)
		check(TankBuildFx.active(tank).size() == 1 and tank.build_fx_started[build.id] == 20, build.id + ": completing build starts one celebration")
		TankBuildFx.sync(tank, 21)
		check(tank.build_fx_started[build.id] == 20 and tank.hp == hp and tank.mods == mods, build.id + ": later ticks do not restart effect or change stats")
		tank.perk_ids.pop_back()
		TankBuildFx.sync(tank, 22)
		check(tank.build_fx_started.is_empty(), build.id + ": removing a required perk clears effect")
		tank.perk_ids = (build.perks as Array).duplicate()
		TankBuildFx.sync(tank, 23)
		check(tank.build_fx_started[build.id] == 23, build.id + ": rebuilding starts a fresh celebration")
		tank.alive = false
		check(TankBuildFx.active(tank).is_empty(), build.id + ": dead tank has no effect")
		tank.respawn(64, 64)
		TankBuildFx.sync(tank, 300)
		check(tank.build_fx_started[build.id] == 23, build.id + ": respawn retains build without replaying completion")
	var map := GameMap.new(10, 10)
	map.fill(Cfg.T_EMPTY)
	var world := World.new({"map": map, "level": {"seed": 42}, "mode": "ffa", "difficulty": "medium", "players": [], "puppet": true})
	world.tanks = [tank]
	tank.perk_ids = Perks.BUILDS[4].perks.duplicate()
	tank.build_fx_started.clear()
	var rng_state := world.rng.state
	world.step_cosmetic()
	check(tank.build_fx_started.has("ice_hunter") and world.rng.state == rng_state, "cosmetic world update discovers builds without consuming RNG")
	world.check_tank_synergies(tank)
	check(tank.build_fx_started.size() == 1, "existing synergy notification shares cosmetic completion state")
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.world = world
	var extra: Dictionary = game._net_extra()
	check(extra.build_fx.get(7, []) == ["ice_hunter"], "host snapshot includes completed build IDs")
	var data := NetProtocol.encode_snapshot(1, 20, [tank], [], extra)
	var decoded := NetProtocol.decode_snapshot(data)
	check(decoded.extra.build_fx.get(7, []) == ["ice_hunter"], "build cosmetics survive snapshot serialization")
	tank.perk_ids = []
	tank.build_fx_started.clear()
	tank.build_fx_use_remote = false
	var stats := [tank.hp, tank.speed, tank.fire_rate, tank.mods.duplicate(true)]
	game._apply_net_extra({"build_fx": {7: ["lightning", "lightning", "unknown"]}})
	check(TankBuildFx.active(tank).size() == 1 and tank.build_fx_started.has("lightning"), "client displays authoritative builds and ignores duplicate/unknown IDs")
	check(tank.perk_ids.is_empty() and stats == [tank.hp, tank.speed, tank.fire_rate, tank.mods], "remote cosmetics never grant perks or combat bonuses")
	game._apply_net_extra({"build_fx": {}})
	check(TankBuildFx.active(tank).is_empty() and tank.build_fx_started.is_empty(), "client removes effects absent from the next snapshot")
	game._apply_net_extra({"score": {"player": 0, "enemy": 0}})
	check(tank.build_fx_started.is_empty(), "older snapshots without build cosmetics remain valid")
	world.dispose()
	check(tank.build_fx_started.is_empty() and not tank.build_fx_use_remote, "world cleanup clears cosmetic state")
	game.world = null
	game.queue_free()
	print("=== TANK BUILD STATE: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
