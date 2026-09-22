class_name MenuTankView
extends WorldView

var display_tank: Tank
var glow_tex: GradientTexture2D
var muzzle := 0.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if display_tank == null:
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
