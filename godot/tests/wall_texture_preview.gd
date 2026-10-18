extends Node2D

class Sample extends WorldView:
	func _ready() -> void:
		pass
	func _draw() -> void:
		_draw_ground_range(0, 6, 0, 9)
		_draw_tile_range(0, 6, 0, 9)

var worlds: Array[World] = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1024, 576)
	var labels := ["ГОРОД", "ПУСТЫНЯ", "ЗИМА", "ЗОНА", "БЕРЕГ", "ДЖУНГЛИ"]
	for i in 6:
		var loc: String = ["city", "dust", "frost", "exclusion", "shore", "jungle"][i]
		var map := GameMap.new(10, 7)
		map.fill(Cfg.T_GRASS)
		for r in 7:
			map.set_tile(r, 0, Cfg.T_WALL)
			map.set_tile(r, 9, Cfg.T_WALL)
		for c in 10:
			map.set_tile(0, c, Cfg.T_WALL)
			map.set_tile(6, c, Cfg.T_WALL)
		map.set_tile(3, 4, Cfg.T_WALL)
		map.set_tile(3, 5, Cfg.T_WALL)
		map.set_tile(3, 2, Cfg.T_BRICK)
		var world := World.new({"map": map, "level": {"seed": 42, "location": loc},
			"mode": "ffa", "difficulty": "medium", "players": [], "puppet": true})
		worlds.append(world)
		var origin := Vector2(16 + (i % 3) * 336, 40 + (i / 3) * 264)
		var label := Label.new()
		label.position = origin - Vector2(0, 24)
		label.text = labels[i]
		add_child(label)
		var sample := Sample.new()
		sample.world = world
		sample.position = origin
		add_child(sample)
	for frame in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://wall_texture_preview.png")
	print("WALL PREVIEW OK: six biomes")
	for world in worlds: world.dispose()
	get_tree().quit()
