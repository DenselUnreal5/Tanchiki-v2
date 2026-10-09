class_name KillCamView
extends Control

signal finished

const VIEW_SIZE := Vector2(380.0, 250.0)
const HEADER_H := 26.0
const PAD := 6.0

var clip: Dictionary = {}
var map: GameMap = null
var running := false

var _start := 0
var _t := 0.0
var _hold := 0.0
var _center := Vector2.ZERO
var _zoom := 0.5
var _frame_seconds := 1.0 / 30.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = VIEW_SIZE
	size = VIEW_SIZE
	visible = false

func play(clip_: Dictionary, map_: GameMap) -> void:
	clip = clip_
	map = map_
	var frames: Array = clip.get("frames", [])
	if frames.size() < 2:
		stop()
		return
	_frame_seconds = float(clip["sample_every"]) / float(Cfg.TICK_HZ)
	var play_frames := int(round(Cfg.KILLCAM_PLAY_SECONDS / _frame_seconds))
	_start = maxi(0, frames.size() - play_frames)
	_t = 0.0
	_hold = 0.0
	_zoom = Cfg.KILLCAM_ZOOM
	_center = _victim_center(frames[_start])
	running = true
	visible = true
	queue_redraw()

func stop() -> void:
	running = false
	visible = false
	clip = {}
	finished.emit()

func frame_count() -> int:
	return (clip.get("frames", []) as Array).size() - _start

func current_index() -> int:
	var frames: Array = clip.get("frames", [])
	return mini(frames.size() - 1, _start + int(_t / _frame_seconds))

func _victim_center(frame: Dictionary) -> Vector2:
	var t := KillCam.tank_at(frame, int(clip["victim"]))
	if t.is_empty():
		return clip["death_pos"]
	return Vector2(t["x"], t["y"])

func _process(delta: float) -> void:
	if not running:
		return
	var frames: Array = clip["frames"]
	var last_t := float(frames.size() - 1 - _start) * _frame_seconds
	if _t < last_t:
		_t = minf(last_t, _t + delta)
	else:
		_hold += delta
		if _hold >= Cfg.KILLCAM_HOLD_SECONDS:
			stop()
			return
	queue_redraw()

func _to_view(world_pos: Vector2) -> Vector2:
	var body_center := Vector2(VIEW_SIZE.x * 0.5, HEADER_H + (VIEW_SIZE.y - HEADER_H - PAD) * 0.5)
	return body_center + (world_pos - _center) * _zoom

func _tile_color(tile: int) -> Color:
	match tile:
		Cfg.T_WALL:
			return Color("#5d6370")
		Cfg.T_BRICK:
			return Color("#8a4b3a")
		Cfg.T_WATER:
			return Color("#2a5f8f")
		Cfg.T_TREE:
			return Color("#2a6b3a")
		Cfg.T_SAND, Cfg.T_DUNE, Cfg.T_QUICKSAND:
			return Color("#a89a6a")
		Cfg.T_ROAD, Cfg.T_BRIDGE:
			return Color("#4a4a4f")
		Cfg.T_ADOBE:
			return Color("#a3814f")
	return Color("#2c3320")

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.03, 0.04, 0.05, 0.94))
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Cfg.UI_DANGER, false, 2.0)
	if clip.is_empty():
		return
	var body := Rect2(Vector2(PAD, HEADER_H), VIEW_SIZE - Vector2(PAD * 2.0, HEADER_H + PAD))
	var frames: Array = clip["frames"]
	_center = _center.lerp(_victim_center(frames[current_index()]), 0.35)
	_draw_header()
	_draw_tiles(body)
	_draw_actors(body)

func _draw_header() -> void:
	var killer_name := String(clip["killer_name"])
	var src := KillCam.source_label(String(clip["source"]))
	var title := I18n.t("killcam.title.self", {"src": src}, "Повтор: %s" % src)
	if killer_name != "":
		title = I18n.t("killcam.title", {"name": killer_name, "src": src},
			"Повтор: вас уничтожил %s (%s)" % [killer_name, src])
	draw_string(ThemeDB.fallback_font, Vector2(PAD + 2.0, 18.0), "☠ " + title,
		HORIZONTAL_ALIGNMENT_LEFT, VIEW_SIZE.x - PAD * 2.0 - 4.0, 12, Cfg.UI_TEXT)

func _draw_tiles(body: Rect2) -> void:
	if map == null:
		return
	var half := (body.size * 0.5) / _zoom
	var c0 := maxi(0, int(floor((_center.x - half.x) / Cfg.TILE)))
	var c1 := mini(map.cols - 1, int(ceil((_center.x + half.x) / Cfg.TILE)))
	var r0 := maxi(0, int(floor((_center.y - half.y) / Cfg.TILE)))
	var r1 := mini(map.rows - 1, int(ceil((_center.y + half.y) / Cfg.TILE)))
	var tile_px := Cfg.TILE * _zoom
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var top_left := _to_view(Vector2(c * Cfg.TILE, r * Cfg.TILE))
			var rect := Rect2(top_left, Vector2(tile_px + 0.6, tile_px + 0.6)).intersection(body)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			draw_rect(rect, _tile_color(map.get_tile(r, c)))

func _draw_actors(body: Rect2) -> void:
	var frames: Array = clip["frames"]
	var idx := current_index()
	var frame: Dictionary = frames[idx]
	var meta: Dictionary = clip["meta"]
	var victim_id := int(clip["victim"])
	var killer_id := int(clip["killer"])

	var bullets: PackedFloat32Array = frame["bullets"]
	var i := 0
	while i + 3 <= bullets.size():
		var p := _to_view(Vector2(bullets[i], bullets[i + 1]))
		if body.has_point(p):
			var col := Cfg.bullet if bullets[i + 2] > 0.5 else Cfg.bullet_enemy
			draw_circle(p, 2.4, col)
		i += 3

	var tanks: PackedFloat32Array = frame["tanks"]
	i = 0
	while i + Cfg.KILLCAM_TANK_STRIDE <= tanks.size():
		var id := int(tanks[i])
		var pos := _to_view(Vector2(tanks[i + 1], tanks[i + 2]))
		if body.grow(10.0).has_point(pos):
			var info: Dictionary = meta.get(id, {})
			var palette := Cfg.team_palette(String(info.get("color_key", "neutral")))
			var angle := tanks[i + 3]
			var turret := tanks[i + 4]
			var len := Cfg.TANK_H * _zoom
			var wid := Cfg.TANK_W * _zoom
			draw_set_transform(pos, angle, Vector2.ONE)
			draw_rect(Rect2(Vector2(-len * 0.5, -wid * 0.5), Vector2(len, wid)), palette["body"])
			draw_rect(Rect2(Vector2(-len * 0.5, -wid * 0.5), Vector2(len, wid)), palette["trim"], false, 1.0)
			draw_set_transform(pos, turret, Vector2.ONE)
			draw_line(Vector2.ZERO, Vector2(len * 0.85, 0.0), palette["trim"], maxf(1.5, 3.0 * _zoom))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if id == killer_id:
				draw_arc(pos, len * 0.8, 0.0, TAU, 24, Cfg.UI_GOLD, 2.0)
			elif id == victim_id:
				draw_arc(pos, len * 0.8, 0.0, TAU, 24, Cfg.UI_DANGER, 2.0)
		i += Cfg.KILLCAM_TANK_STRIDE

	if killer_id >= 0:
		_draw_killer_arrow(frame, body, killer_id)

	if idx >= frames.size() - 1:
		var dp := _to_view(clip["death_pos"])
		var r := 9.0
		draw_line(dp + Vector2(-r, -r), dp + Vector2(r, r), Cfg.UI_DANGER, 3.0)
		draw_line(dp + Vector2(-r, r), dp + Vector2(r, -r), Cfg.UI_DANGER, 3.0)

	var progress := float(idx - _start) / maxf(1.0, float(frames.size() - 1 - _start))
	draw_rect(Rect2(Vector2(PAD, VIEW_SIZE.y - 4.0), Vector2((VIEW_SIZE.x - PAD * 2.0) * progress, 2.0)), Cfg.UI_DANGER)

func _draw_killer_arrow(frame: Dictionary, body: Rect2, killer_id: int) -> void:
	var t := KillCam.tank_at(frame, killer_id)
	if t.is_empty():
		return
	var p := _to_view(Vector2(t["x"], t["y"]))
	if body.grow(-8.0).has_point(p):
		return
	var mid := body.get_center()
	var dir := (p - mid).normalized()
	var edge := mid + dir * minf(body.size.x, body.size.y) * 0.44
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		edge + dir * 9.0, edge - dir * 5.0 + side * 6.0, edge - dir * 5.0 - side * 6.0]), Cfg.UI_GOLD)
