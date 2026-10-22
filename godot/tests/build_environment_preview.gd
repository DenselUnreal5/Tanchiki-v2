extends Node

class Sample extends WorldView:
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		_view = Rect2(0, 0, 416, 224)
		_draw_tiles()
		BuildEnvironmentFx.draw(self, world, _view, Sets.fx_quality)

var samples: Array = []
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 960)
	get_window().content_scale_size = Vector2i(1280, 960)
	var background := ColorRect.new()
	background.size = Vector2(1280, 960)
	background.color = Color("#111c24")
	add_child(background)
	for i in BuildEnvironment.IDS.size():
		var id: String = BuildEnvironment.IDS[i]
		var build: Dictionary = Perks.get_build(id)
		var pos := Vector2(12 + (i % 3) * 420, 50 + (i / 3) * 300)
		var label := Label.new()
		label.position = pos
		label.text = String(build.name)
		label.add_theme_font_override("font", Fonts.bold)
		label.add_theme_color_override("font_color", build.color)
		label.add_theme_font_size_override("font_size", 20)
		add_child(label)
		var container := SubViewportContainer.new()
		container.position = pos + Vector2(0, 32)
		add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(416, 224)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)
		var map := GameMap.new(13, 7)
		map.fill(Cfg.T_GRASS)
		for r in map.rows:
			map.set_tile(r, 10, Cfg.T_WATER)
			map.set_tile(r, 11, Cfg.T_WATER)
		map.set_tile(3, 10, Cfg.T_BRIDGE)
		map.set_tile(3, 11, Cfg.T_BRIDGE)
		if id == "stealth_hunter":
			for cell in [Vector2i(5, 2), Vector2i(6, 2), Vector2i(5, 3), Vector2i(4, 3)]: map.set_tile(cell.y, cell.x, Cfg.T_TREE)
		var world := World.new({"map": map, "level": {"seed": 42}, "mode": "ffa", "difficulty": "medium", "players": [], "puppet": true, "rng_seed": 17})
		world.tick = 180
		world.build_environment.active[id] = {"owner": 7, "start": 0}
		world.build_environment.zones = [{"id": id, "x": 176.0, "y": 112.0, "start": 0, "grown": true}, {"id": id, "x": 240.0, "y": 176.0, "start": 0, "grown": true}]
		var sample := Sample.new()
		sample.world = world
		viewport.add_child(sample)
		samples.append({"sample": sample, "viewport": viewport, "world": world, "id": id})
	await RenderingServer.frame_post_draw
	var state := []
	for entry in samples:
		var image: Image = entry.viewport.get_texture().get_image()
		var center := image.get_region(Rect2i(144, 80, 64, 64))
		state.append({"image": center.get_data(), "rng": entry.world.rng.state, "map": entry.world.map.version})
		if entry.id in ["acid_hunter", "shock_hunter"]:
			var water := image.get_pixel(10 * 32 + 16, 16)
			check(water.g > water.b if entry.id == "acid_hunter" else water.b > water.r, entry.id + ": river uses transformed palette")
	await RenderingServer.frame_post_draw
	for i in samples.size():
		var entry: Dictionary = samples[i]
		var image: Image = entry.viewport.get_texture().get_image()
		check(image.get_region(Rect2i(144, 80, 64, 64)).get_data() == state[i].image, entry.id + ": paused render stays stable")
		check(entry.world.rng.state == state[i].rng and entry.world.map.version == state[i].map, entry.id + ": rendering never mutates gameplay")
		entry.world.tick = 60
		entry.sample.queue_redraw()
	await RenderingServer.frame_post_draw
	for i in samples.size():
		var entry: Dictionary = samples[i]
		var image: Image = entry.viewport.get_texture().get_image()
		check(image.get_region(Rect2i(144, 80, 64, 64)).get_data() != state[i].image, entry.id + ": warning differs from active terrain")
		entry.world.tick = 180
		entry.sample.queue_redraw()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://build_environment.png")
	Sets.fx_quality = 0
	Sets.reduce_flashes = true
	for entry in samples: entry.sample.queue_redraw()
	await RenderingServer.frame_post_draw
	check(not get_viewport().get_texture().get_image().is_empty(), "low effects and reduced flashes render successfully")
	for entry in samples: entry.world.dispose()
	print("=== BUILD ENVIRONMENT VISUAL: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
