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
		for row in 2:
			for col in 4:
				draw_set_transform(Vector2.ZERO)
				draw_rect(Rect2(col * 100, row * 100, 96, 96), Color("#303b36"))
		for tank in world.tanks:
			_draw_build_tank(tank)

	func _draw_build_tank(tank: Tank) -> void:
		# Gallery omits HUD bars and perk lists so the build effect is readable.
		var pos := Vector2(tank.x, tank.y)
		var hw := tank.width * 0.5
		var hh := tank.height * 0.5
		var palette := Cfg.team_palette(tank.color_key)
		draw_set_transform(pos)
		_draw_ellipse(Vector2(2, 4), hw * 1.05, hh / 1.2, Color(0, 0, 0, 0.25))
		TankBuildFx.draw_underlay(self, tank, world.tick, Sets.flash_scale(), Sets.fx_quality)
		var hull := TankSprites.hull_class(tank)
		if hull != "":
			_draw_tank_sprite(tank, hull, palette, pos, hw, hh, float(world.tick))
		else:
			_draw_tank_shape(tank, palette, TankArt.chassis(tank.chassis_id), pos, hw, hh, float(world.tick))
		draw_set_transform(pos)
		TankBuildFx.draw(self, tank, world.tick, Sets.flash_scale(), Sets.fx_quality)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	var background := ColorRect.new()
	background.color = Color("#17201e")
	background.size = Vector2(1280, 720)
	add_child(background)
	var title := Label.new()
	title.position = Vector2(40, 12)
	title.text = "ЭФФЕКТЫ СОБРАННЫХ БИЛДОВ · 0.9.62"
	title.add_theme_font_override("font", Fonts.bold)
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)
	var map := GameMap.new(20, 12)
	map.fill(Cfg.T_GRASS)
	var world := World.new({"map": map, "level": {"seed": 42}, "mode": "ffa", "difficulty": "medium", "players": [], "puppet": true})
	var view := GalleryView.new()
	view.world = world
	view.position = Vector2(40, 60)
	view.scale = Vector2(3, 3)
	add_child(view)
	for i in Perks.BUILDS.size():
		var build: Dictionary = Perks.BUILDS[i]
		var tank := Tank.new({"x": 48 + (i % 4) * 100, "y": 52 + (i / 4) * 100,
			"team": "player", "name": "", "color_key": "p1", "max_hp": 100.0, "speed": 2.0, "fire_rate": 30})
		tank.body_angle = -PI / 2
		tank.turret_angle = -PI / 2
		tank.spawn_protect = 0
		tank.perk_ids = build.perks.duplicate()
		TankBuildFx.sync(tank, 0)
		world.tanks.append(tank)
		var label := Label.new()
		label.position = Vector2(52 + (i % 4) * 300, 68 + (i / 4) * 300)
		label.text = build.name
		label.add_theme_font_override("font", Fonts.bold)
		label.add_theme_font_size_override("font_size", 16)
		add_child(label)
	if "--capture-builds" in OS.get_cmdline_user_args():
		view.set_process(false)
		for pair in [[12, "activation"], [120, "persistent"]]:
			world.tick = pair[0]
			view.queue_redraw()
			for frame in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := "user://tank_build_%s.png" % pair[1]
			get_viewport().get_texture().get_image().save_png(path)
			print("BUILD PREVIEW OK: ", ProjectSettings.globalize_path(path))
		world.dispose()
		get_tree().quit()
