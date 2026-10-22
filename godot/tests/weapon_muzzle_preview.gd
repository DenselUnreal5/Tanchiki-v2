extends Node
class Gallery extends WorldView:
	var samples: Array[Tank] = []
	func _ready() -> void: texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		for tank in samples: _draw_tank(tank)
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color("#101922")
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var gallery := Gallery.new()
	gallery.scale = Vector2.ONE * 5
	add_child(gallery)
	var cannons := ["ice", "acid", "fire", "shock"]
	var skins := ["steampunk", "arctic_frost", "magma"]
	for col in 4:
		var title := UiKit.label(I18n.dn(Cannons.get_cannon(cannons[col]), "name", "cannon"), 18, Cfg.UI_TEXT, true)
		title.position = Vector2(45 + col * 320, 12)
		add_child(title)
	for row in 3:
		for col in 4:
			var tank := Tank.new({"x": (160 + col * 320)/5.0, "y": (135 + row * 220)/5.0, "team": "player", "name": "", "color_key": "p1", "class_id": "standard", "chassis": "standard", "max_hp": 100, "speed": 0, "fire_rate": 30, "cannon_id": cannons[col], "cosmetics": {"skin": skins[row]}})
			tank.spawn_protect = 0
			tank.body_angle = -PI/2
			tank.turret_angle = -1.85
			gallery.samples.append(tank)
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://weapon_muzzles.png")
	print("MUZZLE PREVIEW: steampunk, frost and magma; ice, acid, fire and shock")
	get_tree().quit(0)
