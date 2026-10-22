extends Node

var failures := 0

func _ready() -> void:
	var baseline := OS.get_cmdline_user_args().has("--baseline")
	var prefix := "citadel-before-" if baseline else "citadel-after-"
	for loc in ["city", "dust", "jungle"]:
		var level := LevelGen.generate(1, "ffa", 84, loc, "fortress")
		var map: GameMap = level.map
		var original_tiles := map.tiles.duplicate()
		var original_passable := map.passable.duplicate()
		var player := PlayerState.new(0, "Preview", "p1", null)
		player.viewport = Rect2(0, 0, 1280, 900)
		player.camera = Vector2(map.width * 0.5, map.height * 0.5)
		var world := World.new({"map": map, "level": level, "mode": "ffa",
			"difficulty": "medium", "players": [], "puppet": true, "rng_seed": 84})
		world.weather = WeatherSystem.new(84, {"condition": "clear", "phase": 0.25})
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 900)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var view := WorldView.new()
		view.world = world
		view.player = player
		vp.add_child(view)
		for frame in 40:
			await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path := "res://../screenshots/%s%s.png" % [prefix, loc]
			var err := vp.get_texture().get_image().save_png(path)
			if err != OK: failures += 1
			print("CAPTURE ", path, " error=", err)
		if map.tiles != original_tiles or map.passable != original_passable:
			failures += 1
			push_error("Rendering changed fortress collision map")
		print("PASS: fortress rendering preserves tiles and passability: ", loc)
		if not baseline:
			var nearest := view.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
			for chunk_view in view.tile_cache._views:
				if chunk_view != null:
					nearest = nearest and chunk_view.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
			for chunk_vp in view.tile_cache._vps:
				if chunk_vp != null:
					nearest = nearest and chunk_vp.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
			if not nearest:
				failures += 1
				push_error("Fortress renderer must use nearest filtering through the tile cache")
			else:
				print("PASS: nearest sampling in live and baked views: ", loc)
			if DisplayServer.get_name() != "headless":
				await _check_rebake(world, vp, player)
		vp.queue_free()
		await get_tree().process_frame
	print("CITADEL VISUAL CHECK failures=", failures)
	get_tree().quit(1 if failures else 0)

func _check_rebake(world: World, vp: SubViewport, player: PlayerState) -> void:
	var bounds := CitadelArt.central_rect(world.map)
	for r in range(bounds.position.y, bounds.end.y):
		for c in range(bounds.position.x, bounds.end.x):
			if world.map.get_tile(r, c) != Cfg.T_BRICK: continue
			var point := Vector2(c * 32 + 16, r * 32 + 16) - player.camera + Vector2(640, 450)
			await RenderingServer.frame_post_draw
			var before := vp.get_texture().get_image().get_pixelv(Vector2i(point))
			world.map.set_tile(r, c, Cfg.T_EMPTY)
			for frame in 12: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var after := vp.get_texture().get_image().get_pixelv(Vector2i(point))
			if before == after:
				failures += 1
				push_error("Citadel roof remained in the tile cache after destruction")
			else:
				print("PASS: destructible masonry rebakes correctly: ", world.location)
			return
