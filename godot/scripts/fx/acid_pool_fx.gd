class_name AcidPoolFx
extends RefCounted

# Four reusable silhouettes. Only presentation hashes are used; no gameplay RNG.
static var _textures: Array[CanvasTexture] = []

static func _texture(variant: int) -> CanvasTexture:
	if _textures.is_empty():
		for seed_value in 4:
			var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
			for y in 64:
				for x in 64:
					var p := Vector2(x - 31.5, y - 31.5)
					var angle := p.angle()
					var edge := 28.0 + 1.8 * sin(angle * 5.0 + seed_value) + sin(angle * 9.0 - seed_value)
					var d := p.length()
					var color := Color.TRANSPARENT
					if d < edge + 2.0:
						color = Color("#293b28", 0.85)
					if d < edge:
						color = Color("#42552d")
					if d < edge - 2.0:
						color = Color("#647e3f")
						var fleck := Rng.hash01((x / 3) + (y / 3) * 71, seed_value + 51)
						if fleck > 0.8: color = Color("#76994c")
						elif fleck < 0.12: color = Color("#536b36")
					if d < edge - 4.0 and p.y < -14 and Rng.hash01(x / 5, seed_value + 3) > 0.35:
						color = Color("#93ad50")
					image.set_pixel(x, y, color)
			var texture := CanvasTexture.new()
			texture.diffuse_texture = ImageTexture.create_from_image(image)
			texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_textures.append(texture)
	return _textures[posmod(variant, 4)]

static func draw(canvas: CanvasItem, pool, tick: int, detail: int) -> void:
	if pool.timer <= 0 or pool.radius <= 0.0:
		return
	var pos := Vector2(pool.x, pool.y).round()
	var life := float(pool.timer) / float(maxi(1, pool.max_life))
	var alpha := clampf(life * 1.5, 0.0, 1.0)
	var radius: float = pool.radius
	var extent := ceilf(radius + 3.0)
	var seed_value := int(pool.x) * 31 + int(pool.y) * 17
	canvas.draw_texture_rect(_texture(seed_value), Rect2(pos - Vector2.ONE * extent, Vector2.ONE * extent * 2.0), false, Color(1, 1, 1, alpha))
	for i in (5 if detail > 0 else 2):
		var phase := posmod(tick + seed_value + i * 13, 48)
		var angle := Rng.hash01(seed_value + i, 71) * TAU
		var distance := radius * (0.2 + Rng.hash01(seed_value + i, 73) * 0.45)
		var bubble := (pos + Vector2(cos(angle), sin(angle)) * distance).round()
		if phase < 28:
			var size := 2.0 if phase < 10 else 4.0
			canvas.draw_rect(Rect2(bubble - Vector2.ONE, Vector2(size, size)), Color("#42552d", alpha))
			canvas.draw_rect(Rect2(bubble, Vector2(size - 1, size - 1)), Color("#93ad50", alpha))
			canvas.draw_rect(Rect2(bubble, Vector2.ONE), Color("#c7d57c", alpha))
		elif phase < 34:
			canvas.draw_rect(Rect2(bubble + Vector2(-3, -2), Vector2(2, 1)), Color("#93ad50", alpha * 0.8))
			canvas.draw_rect(Rect2(bubble + Vector2(3, 1), Vector2(1, 2)), Color("#93ad50", alpha * 0.8))
		if detail > 0 and phase >= 20:
			var vapor := bubble + Vector2(2, -floorf((phase - 20) * 0.4))
			var fade := alpha * (1.0 - float(phase - 20) / 28.0) * 0.35
			canvas.draw_rect(Rect2(vapor, Vector2(4, 3)), Color("#93ad50", fade))
			canvas.draw_rect(Rect2(vapor + Vector2(2, -2), Vector2(3, 3)), Color("#76994c", fade))
