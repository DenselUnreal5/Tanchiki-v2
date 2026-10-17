class_name ElectricGlow
extends RefCounted

const BLUE := Color("#287eff")
const YELLOW := Color("#ffd34d")
const CORE := Color("#fff29a")

## Stepped blue halo and yellow center, shared by storm bolts and tank arcs.
static func draw_path(canvas: CanvasItem, points: PackedVector2Array, alpha: float, flash_scale: float, compact: bool = false) -> void:
	canvas.draw_polyline(points, Color(BLUE, alpha * flash_scale * 0.18), 5.0 if compact else 12.0)
	canvas.draw_polyline(points, Color(BLUE, alpha * flash_scale * 0.65), 3.0 if compact else 8.0)
	canvas.draw_polyline(points, Color(YELLOW, alpha * flash_scale * 0.60), 2.0 if compact else 4.0)
	# Combat information remains visible when reduced flashes attenuate the halo.
	canvas.draw_polyline(points, Color(CORE, alpha * 0.95), 1.0 if compact else 2.0)

static func draw_spark(canvas: CanvasItem, point: Vector2, radius: float, alpha: float, flash_scale: float) -> void:
	var p := point.round()
	canvas.draw_rect(Rect2(p - Vector2(radius + 1, 1), Vector2(radius * 2 + 3, 3)), Color(BLUE, alpha * flash_scale * 0.25))
	canvas.draw_rect(Rect2(p - Vector2(1, radius + 1), Vector2(3, radius * 2 + 3)), Color(BLUE, alpha * flash_scale * 0.25))
	canvas.draw_rect(Rect2(p - Vector2(radius, 0), Vector2(radius * 2 + 1, 1)), Color(YELLOW, alpha))
	canvas.draw_rect(Rect2(p - Vector2(0, radius), Vector2(1, radius * 2 + 1)), Color(CORE, alpha))

## Pure geometry: stable while paused, no simulation RNG or stored particles.
static func link_points(start: Vector2, end: Vector2, seed_value: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var delta := end - start
	var side := Vector2(-delta.y, delta.x).normalized()
	var steps := clampi(int(delta.length() / 12.0), 3, 32)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var jitter := (Rng.hash01(seed_value + i * 977, 29) - 0.5) * 18.0 * sin(t * PI)
		points.append((start.lerp(end, t) + side * jitter).round())
	points[0] = start.round()
	points[steps] = end.round()
	return points
