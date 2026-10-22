class_name ShotFx
extends Node2D

# Presentation only: uses simulation ticks, never consumes the gameplay RNG.
const SHEETS := {
	"standard": preload("res://art/fx/tank_shots/tank_shots.tres"),
	"acid": preload("res://art/fx/acid_shots/acid_shots.tres"),
	"fire": preload("res://art/fx/flamethrower_shots/flamethrower_shots.tres"),
	"shock": preload("res://art/fx/electric_shots/electric_shots.tres"),
	"freeze": preload("res://art/fx/ice_shots/ice_shots.tres"),
	"rammer": preload("res://art/fx/rammer_attacks/rammer_attacks.tres"),
	"chimera": preload("res://art/fx/chimera_attacks/chimera_attacks.tres"),
}
const TRAVEL := {"standard": "projectile", "acid": "projectile",
	"fire": "flame_stream", "shock": "projectile", "freeze": "ice_shards"}
const STREAM_SPACING := 13.0
const STREAM_FLOW := 5.0
const STREAM_GROW := 20.0
const TRAIL_ANCHOR := 0.87
const TRAIL_MIN := 12.0
const TRAIL_LEAD := 8.0
const UNDER_TANK_ALPHA := 0.3
var view: WorldView

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/shot_pixels.gdshader")
	material = mat

func _process(_delta: float) -> void:
	queue_redraw()

static func kind_of(mode: String) -> String:
	return mode if SHEETS.has(mode) else "standard"

func _sprite(kind: String, anim: String, age: int, pos: Vector2,
		angle: float, size: Vector2, anchor: Vector2 = Vector2(0.5, 0.5),
		flip: bool = false, opacity: float = 1.0) -> void:
	if not view.in_view(pos.x, pos.y, maxf(size.x, size.y)):
		return
	var frames: SpriteFrames = SHEETS[kind]
	var count := frames.get_frame_count(anim)
	var frame := int(float(maxi(age, 0)) * frames.get_animation_speed(anim) / 60.0)
	if frames.get_animation_loop(anim):
		frame %= count
	elif frame >= count:
		return
	draw_set_transform((view.view_off + pos).round(), angle, Vector2(-1, 1) if flip else Vector2.ONE)
	var rect := Rect2(-anchor * size, size)
	if flip:
		rect.position.x = -(1.0 - anchor.x) * size.x
	draw_texture_rect(frames.get_frame_texture(anim, frame), rect, false, Color(1, 1, 1, opacity))

func _under_tank_fade(w: World, px: float, py: float, radius: float) -> float:
	var fade := 1.0
	for t in w.tanks:
		if not t.alive:
			continue
		var reach: float = radius + t.hit_r
		var dx: float = t.x - px
		var dy: float = t.y - py
		var d2 := dx * dx + dy * dy
		if d2 >= reach * reach:
			continue
		var k := sqrt(d2) / reach
		fade = minf(fade, lerpf(UNDER_TANK_ALPHA, 1.0, k * k))
	return fade

func _draw_acid_stream(w: World, t: Tank) -> void:
	var start := Vector2(t.x + cos(t.turret_angle) * t.muzzle_len, t.y + sin(t.turret_angle) * t.muzzle_len)
	var end_p: Vector2 = t.chimera_stream_target_point
	var length := start.distance_to(end_p)
	if length < 8.0:
		return
	var dir := (end_p - start) / length
	var angle := dir.angle()
	var age := Cfg.CHIMERA_STREAM_BURST_TICKS - t.chimera_stream_timer
	var reach := minf(length, float(age + 1) * STREAM_GROW)
	var opacity := 0.55 if t.is_chimera_clone else 1.0
	_sprite("chimera", "acid_stream_loop", w.tick, start, angle,
		Vector2(reach / 0.92, Cfg.CHIMERA_STREAM_WIDTH * 1.8), Vector2(0.04, 0.5), false, opacity)
	if reach >= length:
		_sprite("chimera", "acid_splash", w.tick % 24, end_p, 0.0, Vector2.ONE * 44.0, Vector2(0.5, 0.5), false, opacity)

func _draw() -> void:
	if view == null or view.world == null or view.player == null:
		return
	var w: World = view.world
	for patch in w.fire_patches:
		var phase := 6 + (w.tick + int(patch.x + patch.y)) % 12
		var alpha := clampf(float(patch.timer) / 45.0, 0.0, 0.8) * _under_tank_fade(w, patch.x, patch.y, patch.radius)
		_sprite("fire", "fire_burst", phase, Vector2(patch.x, patch.y), 0.0,
			Vector2.ONE * patch.radius * 2.4, Vector2(0.5, 0.5), false, alpha)
	for b in w.bullets:
		if not b.alive or b.lobbed:
			continue
		var kind := kind_of(b.cannon_kind)
		var size := Vector2(25, 20)
		if kind == "fire": size = Vector2(43, 27)
		elif kind == "freeze": size = Vector2(29, 23)
		elif kind == "shock": size = Vector2(34, 20)
		var age := w.tick - maxi(b.fx_spawn_tick, 0)
		var travelled := float(age) * Vector2(b.vx, b.vy).length()
		size.x = minf(size.x, maxf(TRAIL_MIN, (travelled + TRAIL_LEAD) / TRAIL_ANCHOR))
		var pos := Vector2(b.x, b.y)
		var angle := atan2(b.vy, b.vx)
		_sprite(kind, TRAVEL[kind], age, pos,
			angle, size, Vector2(TRAIL_ANCHOR, 0.5), kind == "fire")
	for t in w.tanks:
		if t.alive and t.chimera_stream_active and t.chimera_stream_timer > 0:
			_draw_acid_stream(w, t)
	for e in w.shot_effects:
		var age: int = w.tick - int(e.tick)
		var kind := kind_of(String(e.kind))
		var row: String = e.anim
		var size := Vector2.ONE * float(e.size)
		var anchor := Vector2(0.5, 0.5)
		var flip := row == "muzzle"
		if flip: anchor.x = 0.18
		_sprite(kind, row, age, e.pos, float(e.angle), size, anchor, flip)
	for t in w.tanks:
		if t.alive and t.freeze_ticks <= 0:
			_boss_attack(t, w.tick)
		if not t.alive or t.freeze_ticks <= 0:
			continue
		# Open center leaves the tank silhouette readable; expires with the status.
		var size := Vector2.ONE * maxf(t.hit_r * 3.5, 62.0)
		var alpha := 0.85 if t.freeze_ticks > 45 else 0.45 + 0.4 * float(t.freeze_ticks) / 45.0
		_sprite("freeze", "freeze_loop", w.tick, Vector2(t.x, t.y), 0.0,
			size, Vector2(0.5, 0.5), false, alpha)

func _boss_attack(t: Tank, tick: int) -> void:
	var pos := Vector2(t.x, t.y)
	if t.is_rammer_boss:
		if t.rammer_state == "charge":
			var dir := Vector2.from_angle(t.rammer_dir)
			_sprite("rammer", "charge_dust", tick, pos - dir * 26.0,
				t.rammer_dir, Vector2(100, 76), Vector2(0.6, 0.5), false, 0.8)
		elif t.rammer_state == "spin":
			_sprite("rammer", "spin_loop", tick, pos, 0.0, Vector2.ONE * 150.0,
				Vector2(0.5, 0.5), false, 0.7)
	if not (t.is_chimera_boss or t.is_chimera_clone):
		return
	var muzzle := pos + Vector2.from_angle(t.turret_angle) * t.muzzle_len
	if t.chimera_stream_warmup_ticks > 0:
		var progress := 1.0 - float(t.chimera_stream_warmup_ticks) / float(Cfg.CHIMERA_STREAM_WARMUP_TICKS)
		_sprite("chimera", "acid_charge", int(clampf(progress, 0.0, 1.0) * 23.0),
			muzzle, t.turret_angle, Vector2(34, 34))
