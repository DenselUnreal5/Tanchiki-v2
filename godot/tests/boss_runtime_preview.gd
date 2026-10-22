extends Node

class Gallery extends WorldView:
	var samples: Array[Tank] = []
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		for tank in samples: _draw_tank(tank)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 800)
	get_window().content_scale_size = Vector2i(1280, 800)
	var bg := ColorRect.new()
	bg.color = Color("#14212a")
	bg.size = Vector2(1280, 800)
	add_child(bg)
	var gallery := Gallery.new()
	gallery.scale = Vector2.ONE * 3
	var map := GameMap.new(40, 25)
	map.fill(Cfg.T_GRASS)
	gallery.world = World.new({"map": map, "level": {"seed": 42, "location": "city"}, "mode": "ffa", "players": [], "puppet": true})
	gallery.world.tick = 120
	add_child(gallery)
	var ids := ["boss", "boss_rammer", "boss_chimera", "chimera_clone"]
	for col in ids.size():
		var entry := Bestiary.get_entry(ids[col])
		var label := Label.new()
		label.text = Bestiary.text(entry, "name")
		label.position = Vector2(25 + col * 320, 12)
		label.add_theme_font_override("font", Fonts.bold)
		label.add_theme_font_size_override("font_size", 16)
		add_child(label)
		for row in 4:
			var tank := Tank.new({"x": (160 + col * 320)/3.0, "y": (132 + row * 180)/3.0,
				"name": "", "team": "enemy", "chassis": entry.chassis,
				"color_key": entry.color_key, "max_hp": 100, "speed": 0, "fire_rate": 30})
			tank.enemy_type = EnemyTypes.get_type(ids[col])
			tank.is_boss = true
			tank.is_rammer_boss = ids[col] == "boss_rammer"
			tank.is_chimera_boss = ids[col] == "boss_chimera"
			tank.is_chimera_clone = ids[col] == "chimera_clone"
			tank.spawn_protect = 0
			tank.body_angle = -PI/2
			tank.turret_angle = -PI/2
			if row == 1:
				tank.body_angle = -0.4
				tank.turret_angle = -2.2
			elif row == 2:
				tank.freeze_ticks = 120
				tank.burn_ticks = 180
				tank.burn_stacks = 2
				tank.hp = 40
			elif row == 3: tank.color_key = "silhouette"
			gallery.samples.append(tank)
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://boss_runtime.png")
	# Exercise the exact same renderer used by the dossier/main menu (no world).
	gallery.world = null
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://boss_dossier.png")
	print("BOSS RUNTIME PREVIEW OK: four models, independent rotation, statuses, silhouettes, world and menu")
	get_tree().quit(0)
