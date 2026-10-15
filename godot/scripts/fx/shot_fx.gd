class_name ShotFx
extends Node2D

# Presentation only: uses simulation ticks, never consumes the gameplay RNG.
const SHEETS := {
	"standard": preload("res://art/fx/tank_shots/tank_shots.tres"),
	"acid": preload("res://art/fx/acid_shots/acid_shots.tres"),
	"fire": preload("res://art/fx/flamethrower_shots/flamethrower_shots.tres"),
	"shock": preload("res://art/fx/electric_shots/electric_shots.tres"),
	"freeze": preload("res://art/fx/ice_shots/ice_shots.tres"),
}
const TRAVEL := {"standard": "projectile", "acid": "projectile",
	"fire": "flame_stream", "shock": "projectile", "freeze": "ice_shards"}
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

func _draw() -> void:
	if view == null or view.world == null or view.player == null:
		return
	var w: World = view.world
	for patch in w.fire_patches:
		var phase := 6 + (w.tick + int(patch.x + patch.y)) % 12
		var alpha := clampf(float(patch.timer) / 45.0, 0.0, 0.8)
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
		var pos := Vector2(b.x, b.y)
		var angle := atan2(b.vy, b.vx)
		# Leading tip stays at the actual collision point. Flame sheets point left.
		_sprite(kind, TRAVEL[kind], w.tick - maxi(b.fx_spawn_tick, 0), pos,
			angle, size, Vector2(0.87, 0.5), kind == "fire")
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
		if not t.alive or t.freeze_ticks <= 0:
			continue
		# Open center leaves the tank silhouette readable; expires with the status.
		var size := Vector2.ONE * maxf(t.hit_r * 3.5, 62.0)
		var alpha := 0.85 if t.freeze_ticks > 45 else 0.45 + 0.4 * float(t.freeze_ticks) / 45.0
		_sprite("freeze", "freeze_loop", w.tick, Vector2(t.x, t.y), 0.0,
			size, Vector2(0.5, 0.5), false, alpha)
