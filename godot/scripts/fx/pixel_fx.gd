class_name PixelFx
extends RefCounted

# Shared two-pixel drawing vocabulary for transient combat effects.
# Shapes are cached textures or bounded polylines; no per-frame image generation.
static var _disks: Dictionary = {}

static func disk_texture(rough: bool = false) -> CanvasTexture:
	if _disks.has(rough): return _disks[rough]
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2(floorf(x / 2.0) * 2 + 1 - 32, floorf(y / 2.0) * 2 + 1 - 32)
			var edge := 30.0
			if rough: edge += sin(p.angle() * 5.0) * 1.5 + sin(p.angle() * 9.0)
			if p.length() <= edge: image.set_pixel(x, y, Color.WHITE)
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_disks[rough] = texture
	return texture

static func disk(canvas: CanvasItem, pos: Vector2, radius: float, color: Color, rough: bool = false) -> void:
	if radius <= 0 or color.a <= 0: return
	var extent := maxf(1.0, roundf(radius))
	canvas.draw_texture_rect(disk_texture(rough), Rect2((pos - Vector2.ONE * extent).round(), Vector2.ONE * extent * 2), false, color)

static func ring(canvas: CanvasItem, pos: Vector2, radius: float, from: float, to: float, _count: int, color: Color, width: float = 1.0) -> void:
	if radius <= 0 or color.a <= 0 or is_equal_approx(from, to): return
	var points := PackedVector2Array()
	var steps := clampi(int(absf(to - from) * radius / 3.0), 8, 192)
	for i in steps + 1:
		var angle := lerpf(from, to, float(i) / steps)
		var p := ((pos + Vector2(cos(angle), sin(angle)) * radius) / 2.0).round() * 2.0
		if points.is_empty() or points[-1] != p: points.append(p)
	if points.size() > 1: canvas.draw_polyline(points, color, maxf(1.0, roundf(width)), false)

static func line(canvas: CanvasItem, start: Vector2, end: Vector2, color: Color, width: float = 1.0) -> void:
	canvas.draw_line(start.round(), end.round(), color, maxf(1, roundf(width)), false)

static func polygon(canvas: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	var snapped := PackedVector2Array()
	for p in points:
		var q := p.round()
		if snapped.is_empty() or snapped[-1] != q: snapped.append(q)
	if snapped.size() > 1 and snapped[-1] == snapped[0]: snapped.remove_at(snapped.size() - 1)
	if snapped.size() >= 3: canvas.draw_colored_polygon(snapped, color)

static func flame(canvas: CanvasItem, pos: Vector2, radius: float, tick: int, alpha: float = 1.0) -> void:
	var unit := maxf(1.0, roundf(radius / 4.0))
	for i in 3:
		var phase := posmod(tick + i * 11 + int(pos.x), 24)
		var base := (pos + Vector2((i - 1) * unit * 2, unit)).round()
		var height := unit * (3 + (phase / 6) % 3)
		var sway := unit if phase < 12 else -unit
		canvas.draw_rect(Rect2(base - Vector2(unit * 2, height), Vector2(unit * 4, height + unit)), Color("#8f432b", alpha))
		canvas.draw_rect(Rect2(base - Vector2(unit, height - unit), Vector2(unit * 2, height)), Color("#c35d30", alpha))
		canvas.draw_rect(Rect2(base + Vector2(sway, -height - unit), Vector2(unit, unit * 2)), Color("#dc883d", alpha))
		canvas.draw_rect(Rect2(base - Vector2(unit, height * 0.5), Vector2(unit * 2, ceilf(height * 0.5))), Color("#e89d44", alpha))
		canvas.draw_rect(Rect2(base - Vector2(0, unit), Vector2(unit, unit)), Color("#f2ce7c", alpha))

static func glow_texture() -> CanvasTexture:
	# Four discrete brightness bands, nearest filtered; no smooth gradient halo.
	if _disks.has("glow"): return _disks["glow"]
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			var alpha := 0.0
			if d < 0.22: alpha = 1.0
			elif d < 0.45: alpha = 0.45
			elif d < 0.7: alpha = 0.20
			elif d < 0.95: alpha = 0.07
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_disks["glow"] = texture
	return texture

static func barrier(canvas: CanvasItem, radius: float, tick: int, color: Color) -> void:
	# Separated armor-like plates leave the hull visible and read as a shield.
	var pulse := 0.85 + 0.15 * sin(tick * 0.15)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var left := Vector2(cos(angle - 0.25), sin(angle - 0.25))
		var right := Vector2(cos(angle + 0.25), sin(angle + 0.25))
		polygon(canvas, PackedVector2Array([left * radius, right * radius,
			right * (radius - 3.0), left * (radius - 3.0)]), Color(color, color.a * pulse))
		line(canvas, left * radius, right * radius, Color(color.lightened(0.35), color.a * pulse), 1)

static func smoke_puff(canvas: CanvasItem, pos: Vector2, alpha: float) -> void:
	var p := pos.round()
	canvas.draw_rect(Rect2(p + Vector2(-6, -5), Vector2(12, 11)), Color("#59615b", alpha))
	canvas.draw_rect(Rect2(p + Vector2(-8, -2), Vector2(16, 5)), Color("#59615b", alpha))
	canvas.draw_rect(Rect2(p + Vector2(-3, -7), Vector2(7, 14)), Color("#59615b", alpha))
	canvas.draw_rect(Rect2(p + Vector2(-4, -5), Vector2(7, 3)), Color("#858b7f", alpha * 0.6))
	canvas.draw_rect(Rect2(p + Vector2(3, 3), Vector2(3, 2)), Color("#3d4942", alpha * 0.6))

static func reticle(canvas: CanvasItem, pos: Vector2, radius: float, color: Color) -> void:
	for x in [-1, 1]:
		for y in [-1, 1]:
			var corner := pos + Vector2(x, y) * radius
			line(canvas, corner, corner - Vector2(x * 3.0, 0), color)
			line(canvas, corner, corner - Vector2(0, y * 3.0), color)
