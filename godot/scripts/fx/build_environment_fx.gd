class_name BuildEnvironmentFx
extends RefCounted

static var _water_textures: Dictionary = {}

static func _water_texture(acid: bool) -> CanvasTexture:
	if _water_textures.has(acid): return _water_textures[acid]
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var palette := [Color("#4b6330"), Color("#566e36"), Color("#60783e"), Color("#698244")] if acid else [Color("#233c62"), Color("#28466b"), Color("#2b4d73"), Color("#31577c")]
	for y in 32:
		for x in 32:
			var value := Rng.hash01(x / 2 + (y / 2) * 31, 79)
			image.set_pixel(x, y, palette[clampi(int(value * 4), 0, 3)])
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_water_textures[acid] = texture
	return texture

static func draw(canvas: CanvasItem, world, view: Rect2, detail: int) -> void:
	for zone in world.build_environment.zones:
		var pos := Vector2(zone.x, zone.y)
		if not view.grow(60).has_point(pos): continue
		var id: String = zone.id
		var color: Color = Perks.get_build(id).get("color", Color.WHITE)
		if not world.build_environment.ready_at(world, id):
			PixelFx.disk(canvas, pos, BuildEnvironment.RADIUS, Color(color, 0.12), true)
			PixelFx.ring(canvas, pos, BuildEnvironment.RADIUS, 0, TAU, 24, Color(color, 0.65), 2)
			continue
		match id:
			"acid_hunter":
				AcidPoolFx.draw(canvas, {"x": pos.x, "y": pos.y, "radius": BuildEnvironment.RADIUS, "timer": 1, "max_life": 1}, world.tick, detail)
			"ice_hunter":
				PixelFx.disk(canvas, pos, 30, Color("#709cac", 0.65), true)
				for i in 5:
					var p := pos + Vector2((i * 17 % 43) - 21, (i * 23 % 39) - 19)
					PixelFx.line(canvas, p + Vector2(-5, -5), p + Vector2(4, 3), Color("#c2e8e9", 0.8), 2)
					PixelFx.line(canvas, p, p + Vector2(7, -5), Color("#b6dbe5", 0.6), 2)
			"fire_hunter":
				PixelFx.disk(canvas, pos, 30, Color("#2c221e", 0.8), true)
				for i in (3 if detail > 0 else 1):
					PixelFx.flame(canvas, pos + Vector2((i - 1) * 16, (i % 2) * 9), 8, world.tick + i * 17, 0.7 * Sets.flash_scale())
			"shock_hunter":
				PixelFx.disk(canvas, pos, 30, Color("#20354c", 0.65), true)
				for side in [-1, 1]:
					canvas.draw_rect(Rect2(pos + Vector2(side * 22 - 3, -5), Vector2(6, 10)), Color("#83939d"))
				if world.tick % 60 < 24:
					var points := ElectricGlow.link_points(pos + Vector2(-22, 0), pos + Vector2(22, 0), world.tick / 6 + int(pos.x))
					ElectricGlow.draw_path(canvas, points, 0.8, Sets.flash_scale(), true)
			"stealth_hunter":
				PixelFx.disk(canvas, pos, 30, Color("#274b30", 0.3), true)
			"juggernaut":
				PixelFx.disk(canvas, pos, 30, Color("#332d2a", 0.6), true)
				for i in 9:
					var p := pos + Vector2((i * 17 % 45) - 22, (i * 29 % 41) - 20)
					canvas.draw_rect(Rect2(p, Vector2(5 + i % 3, 3 + i % 2)), Color("#8c8372") if i % 2 else Color("#605c56"))
			"fortress", "gunner":
				PixelFx.disk(canvas, pos, 30, Color("#29343e", 0.65), true)
				for side in [-1, 1]:
					var p := pos + Vector2(side * 19 - 5, -5)
					canvas.draw_rect(Rect2(p, Vector2(10, 10)), Color("#5b6466"))
					canvas.draw_rect(Rect2(p + Vector2(2, 3), Vector2(6, 3)), color)
				var center_color := Color(color, 0.6)
				PixelFx.line(canvas, pos + Vector2(-7, 0), pos + Vector2(7, 0), center_color, 3)
				if id == "fortress": PixelFx.line(canvas, pos + Vector2(0, -7), pos + Vector2(0, 7), center_color, 3)
			"ghost_sniper":
				# Low drifting bands stay below hulls, preserving nearby silhouettes.
				PixelFx.disk(canvas, pos, 30, Color("#777a95", 0.24), true)
				for i in (4 if detail > 0 else 2):
					var drift := float((world.tick / 4 + i * 13) % 30) - 15
					canvas.draw_rect(Rect2(pos + Vector2(-22 + drift, -18 + i * 10), Vector2(30, 5)), Color("#a1a2b8", 0.20))

static func draw_water(canvas: CanvasItem, world, pos: Vector2, row: int, col: int) -> bool:
	var env: BuildEnvironment = world.build_environment
	var acid: bool = env.ready_at(world, "acid_hunter")
	var shock: bool = env.ready_at(world, "shock_hunter")
	if not acid and not shock: return false
	# Dynamic draw path also runs over cached terrain. No per-frame map invalidation.
	canvas.draw_texture_rect(_water_texture(acid), Rect2(pos, Vector2.ONE * Cfg.TILE), false)
	var phase: int = (world.tick / 8 + row * 3 + col * 7) % 20
	for i in 2:
		var p := pos + Vector2(4 + (phase + i * 11) % 23, 7 + i * 13)
		canvas.draw_rect(Rect2(p, Vector2(7, 2)), Color("#9fb75b") if acid else Color("#4e91c9"))
	if acid and (row + col) % 3 == 0:
		canvas.draw_rect(Rect2(pos + Vector2(11, 13), Vector2(3, 3)), Color("#c2d27b"))
	if shock and (row + col) % 4 == 0 and world.tick % 60 < 20:
		ElectricGlow.draw_path(canvas, ElectricGlow.link_points(pos + Vector2(3, 20), pos + Vector2(27, 8), row * 11 + col + world.tick / 6), 0.65, Sets.flash_scale(), true)
	var shore := Color("#7b8560") if acid else Color("#61758c")
	for edge in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if world.map.get_tile(row + edge.y, col + edge.x) in [Cfg.T_WATER, Cfg.T_BRIDGE]: continue
		var start := pos + Vector2(0 if edge.x <= 0 else Cfg.TILE - 2, 0 if edge.y <= 0 else Cfg.TILE - 2)
		canvas.draw_rect(Rect2(start, Vector2(2, Cfg.TILE) if edge.x != 0 else Vector2(Cfg.TILE, 2)), shore)
	return true
