extends Node

func _ready() -> void:
	var level := LevelGen.generate(1, "ffa", 42, "dust")
	var map := GameMap.new(30, 20)
	map.fill(Cfg.T_SAND)
	for c in 30:
		map.set_tile(10, c, Cfg.T_ROAD)
		map.set_tile(11, c, Cfg.T_ROAD)
	for r in 20:
		map.set_tile(r, 11, Cfg.T_ROAD)
		map.set_tile(r, 12, Cfg.T_ROAD)
	for r in range(2, 8):
		for c in range(3, 9):
			if Vector2(c - 5.5, r - 4.5).length() < 2.8:
				map.set_tile(r, c, Cfg.T_QUICKSAND)
	for r in range(13, 19):
		for c in range(21, 28):
			if Vector2(c - 24, r - 16).length() < 3:
				map.set_tile(r, c, Cfg.T_WATER)
	var oil_cells := []
	for r in range(3, 8):
		for c in range(17, 26):
			if Materials.variant_at(r, c) == 2 and (r + c) % 3 == 0:
				map.set_tile(r, c, Cfg.T_BRICK)
				oil_cells.append(Vector2i(c, r))
	for cell in [Vector2i(3, 14), Vector2i(6, 16), Vector2i(15, 3), Vector2i(18, 16), Vector2i(27, 9)]:
		map.set_tile(cell.y, cell.x, Cfg.T_TREE)
	for cell in [Vector2i(3, 18), Vector2i(4, 18)]:
		map.set_tile(cell.y, cell.x, Cfg.T_WALL)
	level["map"] = map
	var world := World.new({"map": map, "level": level, "mode": "ffa", "players": [], "puppet": true})
	world.weather = WeatherSystem.new(84, {"condition": "clear", "phase": 0.25})
	var player := PlayerState.new(0, "Preview", "p1", null)
	player.viewport = Rect2(0, 0, 960, 640)
	player.camera = Vector2(480, 320)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var view := WorldView.new()
	view.world = world
	view.player = player
	viewport.add_child(view)
	for frame in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://../screenshots/desert-terrain-updated.png")
	for cell in oil_cells:
		world.hit_building(cell.y, cell.x, 999, "blast", cell.x * 32 + 16, cell.y * 32 + 16, null)
	for frame in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://../screenshots/desert-oil-destroyed.png")
	get_tree().quit()
