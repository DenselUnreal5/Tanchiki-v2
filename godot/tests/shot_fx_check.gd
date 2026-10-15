extends Node2D

class IdleControl extends RefCounted:
	func apply(_tank, _player, _world) -> void:
		pass

var failures := 0
var world: World
var player: PlayerState
var shooters: Array[Tank] = []
var targets: Array[Tank] = []
var seen := {}

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func _ready() -> void:
	player = PlayerState.new(0, "VFX", "p1", null)
	var map := GameMap.new(40, 24)
	map.fill(Cfg.T_EMPTY)
	world = World.new({"map": map, "level": {"seed": 42}, "mode": "ffa",
		"difficulty": "medium", "players": [], "puppet": true, "rng_seed": 42})
	player.viewport = Rect2(0, 0, 1280, 720)
	player.camera = Vector2(640, 360)
	for i in 5:
		var cannon: String = ["standard", "acid", "fire", "shock", "ice"][i]
		var owner := PlayerState.new(i, cannon, "p1", IdleControl.new())
		var shooter := Tank.new({"x": 350.0, "y": 100.0 + i * 115,
			"team": "player", "owner": owner, "color_key": "p1", "cannon_id": cannon,
			"max_hp": 100.0, "speed": 2.0, "fire_rate": 30, "name": cannon})
		owner.tank = shooter
		shooter.spawn_protect = 0
		var target := Tank.new({"x": 510.0, "y": shooter.y, "team": "enemy",
			"color_key": "enemy", "max_hp": 10000.0, "speed": 0.0,
			"fire_rate": 30, "name": "Target"})
		target.spawn_protect = 0
		world.tanks.append_array([shooter, target])
		shooters.append(shooter)
		targets.append(target)
	var view := WorldView.new()
	view.world = world
	view.player = player
	add_child(view)
	for i in 5:
		var label := Label.new()
		label.position = Vector2(80, 87 + i * 115)
		label.text = ["STANDARD", "ACID", "FLAMETHROWER", "ELECTRIC", "ICE / FREEZE"][i]
		add_child(label)
	for frame in 410:
		if frame == 0 or frame == 75:
			for shooter in shooters:
				shooter.fire_cooldown = 0
				shooter.aim_at(510, shooter.y)
				check(shooter.shoot(world), "fire " + shooter.cannon_id)
		world.step()
		for e in world.shot_effects:
			seen[String(e.kind) + "/" + String(e.anim)] = true
		if frame == 55:
			check(targets[4].freeze_ticks > 0, "ice freezes target")
			check(targets[3].hp < targets[3].max_hp, "electric hit damages target")
		if frame in [6, 35, 55, 90]:
			await get_tree().process_frame
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var path := "res://../build/shot-fx-%03d.png" % frame
				get_viewport().get_texture().get_image().save_png(path)
		await get_tree().process_frame
	for kind in ["", "acid", "fire", "shock", "freeze"]:
		check(seen.has(kind + "/muzzle"), "muzzle emitted: " + kind)
		check(seen.has(kind + "/impact"), "impact emitted: " + kind)
	check(world.shot_effects.is_empty(), "expired effects removed")
	check(targets[4].freeze_ticks == 0, "freeze ends and overlay disappears with status")
	for i in 200:
		world.add_shot_effect("acid", "impact", Vector2.ZERO)
	check(world.shot_effects.size() == 160, "effect queue bounded")
	print("SHOT FX CHECK failures=", failures)
	get_tree().quit(1 if failures else 0)
