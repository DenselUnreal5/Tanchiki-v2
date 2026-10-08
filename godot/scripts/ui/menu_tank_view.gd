class_name MenuTankView
extends WorldView

var display_tank: Tank
var glow_tex: GradientTexture2D
var muzzle := 0.0
var auto_turret := false
var center_in_rect := false
var is_locked := false
var custom_minimum_size := Vector2.ZERO:
	set(v):
		custom_minimum_size = v
		if size == Vector2.ZERO:
			size = v
var size := Vector2.ZERO

func _process(_delta: float) -> void:
	if auto_turret and display_tank != null:
		display_tank.turret_angle = sin(Time.get_ticks_msec() * 0.0015) * 0.85
	queue_redraw()

func _draw() -> void:
	if display_tank == null:
		return
	if center_in_rect:
		view_off = size * 0.5
	if is_locked:
		var orig_col: String = display_tank.color_key
		display_tank.color_key = "silhouette"
		_draw_tank(display_tank)
		display_tank.color_key = orig_col
		var center_pt := view_off if center_in_rect else size * 0.5
		draw_circle(center_pt, 20.0, Color(0.06, 0.08, 0.10, 0.85))
		draw_arc(center_pt, 20.0, 0.0, TAU, 32, Color(Cfg.UI_BORDER, 0.65), 1.5)
		var body_rect := Rect2(center_pt.x - 6.0, center_pt.y - 2.0, 12.0, 10.0)
		draw_rect(body_rect, Color(Cfg.UI_MUTED, 0.9), true)
		draw_arc(center_pt + Vector2(0.0, -2.0), 4.5, PI, TAU, 16, Color(Cfg.UI_MUTED, 0.9), 2.0)
		return
	_draw_tank(display_tank)
	if muzzle > 0.0 and glow_tex != null:
		var dir := Vector2(cos(display_tank.turret_angle), sin(display_tank.turret_angle))
		var tip := dir * display_tank.muzzle_len
		_glow(tip, 26.0, Color(1.0, 0.80, 0.35, muzzle * 0.85))
		_glow(tip, 9.0, Color(1.0, 0.95, 0.75, muzzle))

func _glow(center: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(glow_tex,
		Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		false, color)
