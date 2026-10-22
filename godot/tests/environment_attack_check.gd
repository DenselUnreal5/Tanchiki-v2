extends Node2D

var failures := 0

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func _ready() -> void:
	var count := 0
	for group in EnvironmentArt.ITEMS:
		for id in EnvironmentArt.ITEMS[group]:
			var tex: AtlasTexture = load("res://art/environment/%s/%s.tres" % [group, id])
			check(tex != null and tex.region.size == Vector2(362, 362), group + "/" + id)
			count += 1
	check(count == 36, "36 environment textures load")
	for kind in ["rammer", "chimera"]:
		var frames: SpriteFrames = ShotFx.SHEETS[kind]
		check(frames.get_animation_names().size() == 4, kind + " has four attacks")
		for anim in frames.get_animation_names():
			check(frames.get_frame_count(anim) == 8, kind + "/" + anim + " has eight frames")
	var preview = load("res://art/environment/environment_attack_preview.tscn").instantiate()
	add_child(preview)
	for page in 3:
		preview.show_page(page)
		await _frames(12)
		await _capture("environment-gallery-%d" % page)
	preview.queue_free()
	await _frames(2)
	for location in ["dust", "jungle"]:
		await _world_capture(location)
	print("ENVIRONMENT ATTACK CHECK failures=", failures)
	get_tree().quit(1 if failures else 0)

func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _capture(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png("res://../screenshots/%s.png" % id)
	check(err == OK, "saved " + id)

func _world_capture(location: String) -> void:
	var player := PlayerState.new(0, "Preview", "p1", null)
	player.viewport = Rect2(0, 0, 1280, 720)
	player.camera = Vector2(640, 360)
	var map := GameMap.new(40, 24)
	map.fill(Cfg.T_SAND if location == "dust" else Cfg.T_GRASS)
	for r in [4, 5, 12, 13]:
		for c in range(3, 12): map.set_tile(r, c, Cfg.T_TREE)
	for r in range(15, 18):
		for c in range(4, 8): map.set_tile(r, c, Cfg.T_BRICK)
	var world := World.new({"map": map, "level": {"seed": 84, "location": location},
		"mode": "ffa", "difficulty": "medium", "players": [], "puppet": true})
	world.tick = 18
	world.barrels.append(Ent.ExplosiveBarrel.new(460, 180))
	world.barrels.append(Ent.ExplosiveBarrel.new(520, 180))
	world.barrels[1].ignited = true
	world.power_generators.append(Ent.PowerGenerator.new(680, 180))
	world.power_generators.append(Ent.PowerGenerator.new(890, 180))
	world.power_generators[1].cooldown = 500
	var rammer := Tank.new({"x": 500.0, "y": 390.0, "team": "enemy", "owner": null,
		"color_key": "boss_rammer", "max_hp": 3400.0, "speed": 3.0,
		"fire_rate": 30, "chassis_id": "boss_rammer", "name": "RAMMER"})
	rammer.is_rammer_boss = true
	rammer.rammer_state = "charge"
	rammer.spawn_protect = 0
	var chimera := Tank.new({"x": 780.0, "y": 510.0, "team": "enemy", "owner": null,
		"color_key": "boss_chimera", "max_hp": 2400.0, "speed": 3.0,
		"fire_rate": 30, "chassis_id": "boss_chimera", "name": "CHIMERA"})
	chimera.is_chimera_boss = true
	chimera.chimera_stream_active = true
	chimera.chimera_stream_timer = 60
	chimera.chimera_stream_target_point = Vector2(1100, 510)
	chimera.spawn_protect = 0
	world.tanks.append_array([rammer, chimera])
	world.add_shot_effect("rammer", "ram_impact", Vector2(650, 390), PI, 85)
	world.add_shot_effect("chimera", "phase_shift", Vector2(780, 510), 0, 85)
	world.shot_effects[0].tick -= 8
	world.shot_effects[1].tick -= 8
	var view := WorldView.new()
	view.world = world
	view.player = player
	add_child(view)
	await _frames(15)
	await _capture("environment-world-" + location)
	rammer.rammer_state = "spin"
	rammer.rammer_spin_ticks = 50
	chimera.chimera_stream_active = false
	chimera.chimera_stream_warmup_ticks = 12
	world._rammer_death_explosion(rammer)
	check(world.shot_effects.any(func(e): return e.anim == "meltdown"), "reactor explosion emits meltdown animation")
	await _frames(4)
	view.queue_free()
	await _frames(2)
