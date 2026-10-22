class_name WeatherVisuals
extends RefCounted

## Shared, deterministic artwork. Drawing never advances the simulation RNG.
static var _fog: CanvasTexture

static func fog_texture() -> CanvasTexture:
	if _fog != null:
		return _fog
	var noise := FastNoiseLite.new()
	noise.seed = 43127
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.28, 0.42, 0.55, 0.70, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.12),
		Color(1, 1, 1, 0.30), Color(1, 1, 1, 0.52), Color(1, 1, 1, 0.76), Color.WHITE])
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.generate_mipmaps = false
	texture.seamless = true
	texture.color_ramp = ramp
	texture.noise = noise
	_fog = CanvasTexture.new()
	_fog.diffuse_texture = texture
	_fog.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fog.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return _fog

static func draw_fog(canvas: CanvasItem, size: Vector2, tick: int, amount: float, tint: Color) -> void:
	var texture := fog_texture()
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(tint, amount * 0.075))
	var drift := Vector2(fposmod(tick * 0.035, 256.0), fposmod(tick * 0.012, 256.0)).floor()
	canvas.draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size),
		Rect2(drift, size / 8.0), Color(tint, amount * 0.38), false, false)
	canvas.draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size),
		Rect2(Vector2(83, 149) - drift * 0.5, size / 12.0), Color(tint, amount * 0.20), false, false)

static func draw_drop(canvas: CanvasItem, pos: Vector2, length: float, near: bool, wind: int, alpha: float) -> void:
	var p := pos.floor()
	var width := 2.0 if near else 1.0
	var step_y := maxf(2.0, floorf(length / 3.0))
	for i in 3:
		var color := Color("#a6b8c5") if near else Color("#7e95a5")
		color.a = alpha * (0.45 + float(i) * 0.25)
		canvas.draw_rect(Rect2(p + Vector2(-i * wind, i * step_y), Vector2(width, step_y + 1)), color)

static func draw_flake(canvas: CanvasItem, pos: Vector2, size: int, alpha: float) -> void:
	var p := pos.floor()
	var color := Color("#e3e9e7")
	color.a = alpha
	canvas.draw_rect(Rect2(p, Vector2(size, size)), color)
	if size >= 3:
		canvas.draw_rect(Rect2(p + Vector2(1, -1), Vector2(1, 5)), Color("#f6f5e8", alpha * 0.8))
		canvas.draw_rect(Rect2(p + Vector2(-1, 1), Vector2(5, 1)), Color("#f6f5e8", alpha * 0.8))

static func draw_splashes(canvas: CanvasItem, map: GameMap, area: Rect2, offset: Vector2, tick: int, amount: float) -> void:
	for r in range(int(floor(area.position.y / 96.0)), int(ceil(area.end.y / 96.0))):
		for c in range(int(floor(area.position.x / 96.0)), int(ceil(area.end.x / 96.0))):
			var seed_value := r * 7919 + c * 104729
			var h := Rng.hash01(seed_value, 317)
			if h > amount * 0.8:
				continue
			var age := (tick + int(h * 200)) % 39
			if age >= 9:
				continue
			var point := Vector2(c * 96 + 12 + int(h * 70), r * 96 + 12 + int(Rng.hash01(seed_value, 331) * 70))
			var tile := map.get_tile(map.row_at(point.y), map.col_at(point.x))
			if tile in [Cfg.T_WALL, Cfg.T_BRICK, Cfg.T_ADOBE, Cfg.T_TREE]:
				continue
			var pos := (point + offset).floor()
			var radius := 2.0 + floorf(age * 0.35)
			var col := Color("#a5b9bc", (1.0 - age / 9.0) * amount * 0.38)
			canvas.draw_rect(Rect2(pos + Vector2(-radius, 0), Vector2(2, 1)), col)
			canvas.draw_rect(Rect2(pos + Vector2(radius - 1, 0), Vector2(2, 1)), col)
			canvas.draw_rect(Rect2(pos + Vector2(-radius + 1, 2), Vector2(radius * 2 - 2, 1)), col)
			if tile == Cfg.T_WATER:
				canvas.draw_rect(Rect2(pos + Vector2(-radius + 1, -2), Vector2(radius * 2 - 2, 1)), col)

static func draw_snow_cover(canvas: CanvasItem, pos: Vector2, amount: float, seed_value: int, roof: bool = false) -> void:
	if amount <= 0.02:
		return
	# Broad wind-blown patches instead of identical white flecks on every tile.
	if not roof:
		var cluster := 0.5 + sin(pos.x * 0.02 + pos.y * 0.015) * 0.25 + sin(pos.y * 0.037 - pos.x * 0.008) * 0.25
		if cluster < 0.62:
			return
		amount *= smoothstep(0.62, 0.9, cluster)
	for i in 4:
		var h := Rng.hash01(seed_value + i * 43, 419)
		var x := 4.0 + floorf(h * 18.0)
		var y := (4.0 + floorf(Rng.hash01(seed_value + i, 421) * 5.0)) if roof else 4.0 + floorf(Rng.hash01(seed_value + i, 421) * 20.0)
		var color := Color("#e1e7e5", amount * 0.85)
		canvas.draw_rect(Rect2(pos + Vector2(x, y), Vector2(3 + floorf(h * 6), 2)), color)
		canvas.draw_rect(Rect2(pos + Vector2(x + 2, y - 1), Vector2(3, 1)), Color("#f1f1e4", amount * 0.75))

static func bolt_points(top: Vector2, impact: Vector2, seed_value: int) -> PackedVector2Array:
	# Irregular leaders, rather than a regular alternating sawtooth.
	var points := PackedVector2Array()
	var delta := impact - top
	var side := Vector2(-delta.y, delta.x).normalized()
	var steps := clampi(int(delta.length() / 13.0), 12, 48)
	for i in steps + 1:
		var t := float(i) / steps
		var cell := t * 5.0
		var index := int(floorf(cell))
		var coarse := lerpf(Rng.hash01(seed_value + index * 719, 31), Rng.hash01(seed_value + (index + 1) * 719, 31), fmod(cell, 1.0)) - 0.5
		var fine := Rng.hash01(seed_value + i * 977, 11) - 0.5
		var offset := (coarse * 68.0 + fine * 24.0) * sin(t * PI)
		var p := top.lerp(impact, t) + side * offset
		points.append((p / 2.0).round() * 2.0)
	return points

static func draw_bolt(canvas: CanvasItem, top: Vector2, impact: Vector2, seed_value: int, alpha: float, flash_scale: float, age: int = 0, detail: int = 2) -> void:
	if alpha <= 0.0: return
	var points := bolt_points(top, impact, seed_value)
	# The same stepped blue halo / yellow-white core used on shocked hulls.
	ElectricGlow.draw_path(canvas, points, alpha, flash_scale)
	var branches := 4 if detail > 0 else 2
	for i in branches:
		var index := clampi(int(points.size() * (0.22 + i * 0.16)), 1, points.size() - 2)
		var origin := points[index]
		var side := -1.0 if Rng.hash01(seed_value + i * 71, 19) < 0.5 else 1.0
		var reach := 28.0 + Rng.hash01(seed_value + i, 23) * 42.0
		var end := origin + Vector2(side * reach, reach * (0.65 + Rng.hash01(seed_value + i, 29)))
		var fork := bolt_points(origin, end, seed_value + i * 113 + 83)
		ElectricGlow.draw_path(canvas, fork, alpha * 0.55, flash_scale, true)
		if detail > 1:
			var split := fork[fork.size() / 2]
			var tip := split + Vector2(-side * reach * 0.4, reach * 0.45)
			ElectricGlow.draw_path(canvas, ElectricGlow.link_points(split, tip, seed_value + i * 331), alpha * 0.28, flash_scale, true)
	# Ground discharge spreads out and fades; no extra full-screen flash.
	var radius := 14.0 + clampf(float(age), 0, 14) * 1.2
	var glow := Color(ElectricGlow.BLUE, alpha * flash_scale * 0.42)
	canvas.draw_texture_rect(PixelFx.glow_texture(), Rect2(impact - Vector2.ONE * radius * 2, Vector2.ONE * radius * 4), false, glow)
	var rays := 6 if detail > 0 else 3
	for i in rays:
		var angle := i * TAU / rays + Rng.hash01(seed_value + i, 53) * 0.55
		var end := impact + Vector2(cos(angle), sin(angle) * 0.45) * radius
		ElectricGlow.draw_path(canvas, ElectricGlow.link_points(impact, end, seed_value + i * 179), alpha * 0.65, flash_scale, true)
		if detail > 0: ElectricGlow.draw_spark(canvas, end, 2.0, alpha * 0.5, flash_scale)
	ElectricGlow.draw_spark(canvas, impact, 5.0, alpha, flash_scale)
