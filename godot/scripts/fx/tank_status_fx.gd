class_name TankStatusFx
extends RefCounted

const BURN := 1
const ACID := 2
const SHOCK := 4

## Presentation only. No stored particles, simulation mutations or random draws.
static func active(tank: Tank) -> int:
	if not tank.alive:
		return 0
	return (BURN if tank.burn_ticks > 0 else 0) | (ACID if tank.acid_stacks > 0 else 0) | (SHOCK if tank.stun_ticks > 0 else 0)

static func body_tints(tank: Tank) -> Array:
	var colors := []
	if tank.acid_stacks > 0:
		colors.append(Color("#91ac54", minf(0.16, 0.05 + tank.acid_stacks * 0.025)))
	if tank.burn_ticks > 0:
		colors.append(Color("#ca713d", 0.08 + mini(tank.burn_stacks, 3) * 0.015))
	if tank.stun_ticks > 0:
		colors.append(Color("#89b8c5", 0.10))
	return colors

static func _point(local: Vector2, tank: Tank) -> Vector2:
	return local.rotated(tank.body_angle + PI / 2.0).round()

static func draw_underlay(canvas: CanvasItem, tank: Tank, tick: int, detail: int = 2) -> void:
	if (active(tank) & BURN) == 0:
		return
	var scale := clampf(tank.height / 30.0, 0.75, 2.4)
	var engine := _point(Vector2(0, tank.height * 0.30), tank)
	var count := 2 if detail > 0 else 1
	for i in count:
		var phase := (tick + tank.id * 7 + i * 17) % 40
		var rise := floorf(phase * 0.6) * scale
		var p := (engine + Vector2(sin((phase + i * 11) * 0.16) * 4.0, -8.0 - rise)).floor()
		var size := floorf((3.0 + phase * 0.07) * scale)
		var alpha := (1.0 - phase / 40.0) * 0.42
		canvas.draw_rect(Rect2(p, Vector2(size, size)), Color("#555b57", alpha))
		canvas.draw_rect(Rect2(p + Vector2(2, -2), Vector2(size - 1, size)), Color("#73766a", alpha * 0.6))

static func draw(canvas: CanvasItem, tank: Tank, tick: int, flash_scale: float = 1.0, detail: int = 2) -> void:
	var flags := active(tank)
	if flags == 0:
		return
	if flags & ACID:
		_acid(canvas, tank, tick, detail)
	if flags & BURN:
		_fire(canvas, tank, tick, detail)
	if flags & SHOCK:
		_shock(canvas, tank, tick, flash_scale, detail)

static func _fire(canvas: CanvasItem, tank: Tank, tick: int, detail: int) -> void:
	var scale := clampf(tank.height / 30.0, 0.75, 2.4)
	var anchors := [Vector2(-tank.width * 0.38, tank.height * 0.18),
		Vector2(tank.width * 0.38, tank.height * 0.25)]
	if tank.burn_stacks > 1 and detail > 0:
		anchors.append(Vector2(0, tank.height * 0.38))
	if detail == 0:
		anchors.resize(1)
	var fade := clampf(tank.burn_ticks / 20.0, 0.35, 1.0)
	for i in anchors.size():
		var p := _point(anchors[i], tank)
		var frame := (tick / 4 + tank.id * 3 + i * 5) % 6
		var height := (6.0 + (frame % 3) * 2.0 + mini(tank.burn_stacks, 3)) * scale
		var sway := (-1.0 if frame % 2 else 1.0) * scale
		canvas.draw_rect(Rect2((p + Vector2(-4 * scale, -height * 0.45)).floor(), Vector2(2 * scale, height * 0.45 + scale)), Color("#8f432b", fade))
		canvas.draw_rect(Rect2((p + Vector2(-2 * scale, -height)).floor(), Vector2(3 * scale, height + scale)), Color("#c35d30", fade))
		canvas.draw_rect(Rect2((p + Vector2(scale, -height * 0.65)).floor(), Vector2(3 * scale, height * 0.65 + scale)), Color("#c35d30", fade))
		canvas.draw_rect(Rect2((p + Vector2(-scale + sway, -height - 2 * scale)).floor(), Vector2(scale, 3 * scale)), Color("#dc883d", fade))
		canvas.draw_rect(Rect2((p + Vector2(-scale, -height * 0.65)).floor(), Vector2(2 * scale, height * 0.65 + scale)), Color("#e89d44", fade))
		canvas.draw_rect(Rect2((p + Vector2(scale, -height * 0.35)).floor(), Vector2(2 * scale, height * 0.35 + scale)), Color("#e89d44", fade))
		canvas.draw_rect(Rect2((p + Vector2(0, -height * 0.30)).floor(), Vector2(scale, height * 0.30 + scale)), Color("#f2ce7c", fade))
		if detail > 0:
			var ember := (tick + i * 13 + tank.id) % 28
			canvas.draw_rect(Rect2((p + Vector2(sway * 2, -height - ember * 0.45)).floor(), Vector2.ONE * scale), Color("#e9b86c", fade * (1.0 - ember / 28.0)))

static func _acid(canvas: CanvasItem, tank: Tank, tick: int, detail: int) -> void:
	var scale := clampf(tank.height / 30.0, 0.75, 2.4)
	var count := mini(5, 2 + tank.acid_stacks) if detail > 0 else 2
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var local := Vector2(side * tank.width * 0.31, (-0.25 + float(i / 2) * 0.23) * tank.height)
		var p := _point(local, tank)
		canvas.draw_rect(Rect2(p - Vector2(2, 1) * scale, Vector2(5, 3) * scale), Color("#42552d", 0.9))
		canvas.draw_rect(Rect2(p - Vector2(1, 2) * scale, Vector2(3, 3) * scale), Color("#93ad50", 0.95))
		canvas.draw_rect(Rect2(p - Vector2(0, 2) * scale, Vector2(2, 1) * scale), Color("#c7d57c", 0.9))
		var phase := (tick + tank.id * 11 + i * 9) % 36
		if phase < 24:
			var drop := (p + Vector2(side * 3.0 * scale, floorf(phase * 0.30) * scale)).floor()
			canvas.draw_rect(Rect2(drop, Vector2(2, 3) * scale), Color("#739240", 0.9 - phase * 0.018))
		if detail > 0:
			var bubble := (p + Vector2(side * 4 * scale, -5 * scale - floorf(phase * 0.24))).floor()
			var alpha := (1.0 - phase / 36.0) * 0.8
			canvas.draw_rect(Rect2(bubble, Vector2(3, 3) * scale), Color("#76994c", alpha))
			canvas.draw_rect(Rect2(bubble + Vector2.ONE * scale, Vector2.ONE * scale), Color("#c4d37a", alpha))

static func _shock(canvas: CanvasItem, tank: Tank, tick: int, flash_scale: float, detail: int) -> void:
	var frame := tick / 4 + tank.id * 3
	var alpha := clampf(tank.stun_ticks / 10.0, 0.4, 1.0)
	var hw := tank.width * 0.5
	var hh := tank.height * 0.5
	for side in [-1.0, 1.0]:
		var points := PackedVector2Array()
		for i in 5:
			var zig := float((frame + i * 3) % 5) - 1.0
			points.append(_point(Vector2(side * (hw + zig), -hh * 0.7 + hh * i * 0.35), tank))
		ElectricGlow.draw_path(canvas, points, alpha, flash_scale, true)
		if detail > 0:
			var origin := points[2]
			var branch := PackedVector2Array([origin,
				origin + _point(Vector2(side * 4, 2), tank),
				origin + _point(Vector2(side * 3, 5), tank)])
			ElectricGlow.draw_path(canvas, branch, alpha * 0.7, flash_scale, true)
			var corner := _point(Vector2(side * (hw + 3), (-0.5 if frame % 2 else 0.5) * hh), tank)
			ElectricGlow.draw_spark(canvas, corner, 2.0, alpha, flash_scale)
	if detail > 0:
		var rear := PackedVector2Array()
		for i in 5:
			rear.append(_point(Vector2(-hw * 0.65 + hw * i * 0.325,
				hh * (0.45 if (frame + i) % 2 else 0.72)), tank))
		ElectricGlow.draw_path(canvas, rear, alpha * 0.75, flash_scale, true)
