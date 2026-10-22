extends Node

class Gallery extends WorldView:
	var samples: Array = []
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		for tank in samples:
			_draw_tank(tank)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	var class_gallery := OS.get_cmdline_user_args().has("--class-guns")
	var logical_height := 660 if class_gallery else 960
	get_window().size = Vector2i(1280, logical_height)
	get_window().content_scale_size = Vector2i(1280, logical_height)
	var background := ColorRect.new()
	background.color = Color("#14212a")
	background.size = Vector2(1280, logical_height)
	add_child(background)
	var gallery := Gallery.new()
	gallery.scale = Vector2(2.5, 2.5)
	add_child(gallery)
	var skins := TankClasses.ids() if class_gallery else ["none"] + TankSkinArt.PALETTES.keys()
	for col in Cannons.LIST.size():
		var label := Label.new()
		label.text = Cannons.LIST[col].name
		label.position = Vector2(190 + col * 210, 12)
		label.add_theme_font_override("font", Fonts.bold)
		label.add_theme_font_size_override("font_size", 18)
		add_child(label)
	for row in skins.size():
		var skin: String = skins[row]
		var label := Label.new()
		label.text = TankClasses.get_entry(skin).name if class_gallery else Cosmetics.get_cosmetic("skin", skin).name
		label.position = Vector2(10, 82 + row * 96)
		label.add_theme_font_override("font", Fonts.regular)
		label.add_theme_font_size_override("font_size", 16)
		add_child(label)
		for col in Cannons.LIST.size():
			var tank := Tank.new({"x": (230 + col * 210) / 2.5, "y": (92 + row * 96) / 2.5, "team": "player", "name": "", "color_key": "p1", "max_hp": 100.0, "speed": 2.0, "fire_rate": 30, "cannon_id": Cannons.LIST[col].id, "cosmetics": {"skin": "none" if class_gallery else skin}, "class_id": skin if class_gallery else "standard", "chassis": TankClasses.get_entry(skin).chassis if class_gallery else "standard"})
			tank.spawn_protect = 0
			tank.body_angle = 0
			tank.turret_angle = -0.2
			gallery.samples.append(tank)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://class_guns.png" if class_gallery else "user://tank_skins.png")
	var failures := 0
	var capture_scale := Vector2(image.get_width() / 1280.0, image.get_height() / float(logical_height))
	for row in skins.size():
		var signatures := {}
		for col in Cannons.LIST.size():
			var region := image.get_region(Rect2i(Vector2i(Vector2(180 + col * 210, 40 + row * 96) * capture_scale), Vector2i(Vector2(160, 90) * capture_scale)))
			signatures[hash(region.get_data())] = true
		if signatures.size() != Cannons.LIST.size():
			failures += 1
			print("FAIL: weapons indistinguishable for ", skins[row])
	print("TANK SKINS VISUAL: failures=", failures)
	get_tree().quit(1 if failures else 0)
