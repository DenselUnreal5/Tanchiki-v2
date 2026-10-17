extends Node

var failures := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run desert_render_check with a graphics display (X11/Xvfb), not --headless")
		get_tree().quit(2)
		return
	var map := GameMap.new(8, 5)
	map.fill(Cfg.T_SAND)
	map.set_tile(1, 1, Cfg.T_EMPTY)
	map.set_tile(1, 3, Cfg.T_DUNE)
	for c in range(1, 4):
		map.set_tile(3, c, Cfg.T_WATER)
	map.set_tile(3, 3, Cfg.T_BRIDGE)
	var editor := MapEditor.new()
	editor.current_location = "dust"
	var canvas := MapEditor._MapCanvas.new()
	canvas.editor = editor
	canvas.current_map = map
	canvas.size = Vector2(256, 160)
	canvas.zoom = 32.0 / MapEditor.BASE_TILE_PX
	var editor_view := _viewport()
	editor_view.add_child(canvas)

	var level := LevelGen.generate(1, "ffa", 42, "dust")
	level["map"] = map
	var world := World.new({"map": map, "level": level, "mode": "ffa",
		"difficulty": "medium", "players": [], "puppet": true})
	var bake := TileBakeView.new()
	bake.world = world
	var game_view := _viewport()
	game_view.add_child(bake)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var editor_image := editor_view.get_texture().get_image()
	var game_image := game_view.get_texture().get_image()
	for pair in [[editor_image, "editor"], [game_image, "game"]]:
		var image: Image = pair[0]
		var name: String = pair[1]
		var ground := image.get_region(Rect2i(37, 37, 22, 22)).get_data()
		var sand := image.get_region(Rect2i(69, 37, 22, 22)).get_data()
		var dune := image.get_region(Rect2i(101, 37, 22, 22)).get_data()
		_check(ground == sand, name + ": sand must not cover the ground texture with a flat fill")
		_check(sand == dune, name + ": dunes use the same desert palette")
		_check(image.get_pixel(70, 38) != image.get_pixel(78, 48), name + ": sand has visible texture")
	_check(editor_image.get_region(Rect2i(69, 37, 22, 22)).get_data() ==
		game_image.get_region(Rect2i(69, 37, 22, 22)).get_data(), "editor and game render the same desert sand")
	_check(editor_image.get_region(Rect2i(69, 97, 22, 22)).get_data() ==
		game_image.get_region(Rect2i(69, 97, 22, 22)).get_data(), "editor and game render the same desert water and banks")
	_check(editor_image.get_region(Rect2i(93, 101, 3, 22)).get_data() ==
		game_image.get_region(Rect2i(93, 101, 3, 22)).get_data(), "bridges keep adjacent water connected in editor and game")
	editor.free()
	print("=== DESERT RENDER: failures: %d ===" % failures)
	get_tree().quit(1 if failures else 0)

func _viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 160)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	return viewport

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
