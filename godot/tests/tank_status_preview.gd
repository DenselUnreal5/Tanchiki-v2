extends Node

class GalleryView extends WorldView:
	var clock := 0.0

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		clock += delta * 60.0
		world.tick = int(clock)
		queue_redraw()

	func _draw() -> void:
		for row in 3:
			for col in 5:
				draw_set_transform(Vector2.ZERO)
				draw_rect(Rect2(6 + col * 80, 18 + row * 72, 76, 68), Color("#303b36"))
		for tank in world.tanks:
			_draw_tank(tank)

func _ready() -> void:
	get_window().size = Vector2i(1280, 800)
	var background := ColorRect.new()
	background.color = Color("#17201e")
	background.size = Vector2(1280, 800)
	add_child(background)
	var map := GameMap.new(40, 30)
	map.fill(Cfg.T_GRASS)
	var world := World.new({"map": map, "level": {"seed": 42, "location": "city"},
		"mode": "ffa", "difficulty": "medium", "players": [], "puppet": true})
	var view := GalleryView.new()
	view.world = world
	view.position = Vector2(16, 24)
	view.scale = Vector2(3, 3)
	add_child(view)
	for row in 3:
		for col in 5:
			var tank := Tank.new({"x": 44 + col * 80, "y": 55 + row * 72,
				"team": "player", "color_key": ["p1", "enemy", "p2"][row],
				"chassis": ["standard", "heavy", "mortar"][row], "name": "",
				"max_hp": 100.0, "speed": 0.0, "fire_rate": 30})
			tank.spawn_protect = 0
			tank.body_angle = [-PI / 2.0, 0.0, PI / 4.0][row]
			tank.turret_angle = tank.body_angle - 0.3
			tank.burn_ticks = 150 if col in [1, 4] else 0
			tank.burn_stacks = 2
			tank.acid_stacks = 3 if col in [2, 4] else 0
			tank.acid_ticks_left = 180
			tank.stun_ticks = 60 if col in [3, 4] else 0
			world.tanks.append(tank)
	for col in 5:
		var label := Label.new()
		label.text = ["ОБЫЧНЫЙ", "ГОРЕНИЕ", "КИСЛОТА", "ШОК", "СОВМЕСТНО"][col]
		label.position = Vector2(34 + col * 240, 20)
		label.add_theme_font_override("font", Fonts.bold)
		label.add_theme_font_size_override("font_size", 18)
		add_child(label)
	if OS.get_cmdline_user_args().has("--capture-status"):
		view.set_process(false)
		world.tick = 60
		view.queue_redraw()
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://tank_status")
		var path := "user://tank_status/status_preview.png"
		get_viewport().get_texture().get_image().save_png(path)
		print("STATUS PREVIEW: ", ProjectSettings.globalize_path(path))
		get_tree().quit()
