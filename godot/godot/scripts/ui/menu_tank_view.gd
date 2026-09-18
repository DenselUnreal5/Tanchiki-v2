# ============================================================================
# menu_tank_view.gd — настоящая отрисовка танка вне боя, для фона меню.
#
# Наследуется от WorldView и вызывает её же _draw_tank() — тот же камуфляж,
# рисунок на корпусе, цвета скинов, что и в матче, вместо ручного дублирования
# этой отрисовки. World у неё нет (мы не в бою), но _draw_tank() это терпит:
# все обращения к world/player внутри неё защищены условиями, которые у
# спокойно стоящего декоративного танка всегда ложны (player.tank == null,
# spawn_protect == 0, ability_timer == 0) — world.* внутри просто не читается.
#
# Рисовать чужим методом «извне» нельзя — Godot разрешает draw_* только
# внутри _draw() того же CanvasItem, поэтому это отдельный узел с одной
# работой, а не вызов _draw_tank() прямо из menu_scene.gd.
# ============================================================================
class_name MenuTankView
extends WorldView

## Танк, который рисуем — единственное, что снаружи обязательно подставлять.
var display_tank: Tank
## Текстура засветки под вспышку выстрела — та же, что строит MenuScene,
## передаётся снаружи, чтобы не заводить вторую такую же.
var glow_tex: GradientTexture2D
## 0..1 — яркость вспышки на срезе ствола; сам тайминг считает MenuScene.
var muzzle := 0.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if display_tank == null:
		return
	_draw_tank(display_tank)
	if muzzle > 0.0 and glow_tex != null:
		var dir := Vector2(cos(display_tank.turret_angle), sin(display_tank.turret_angle))
		# tank.x == tank.y == 0 — центр этого узла и есть позиция танка,
		# смещать вспышку от чего-то ещё не нужно.
		var tip := dir * display_tank.muzzle_len
		_glow(tip, 26.0, Color(1.0, 0.80, 0.35, muzzle * 0.85))
		_glow(tip, 9.0, Color(1.0, 0.95, 0.75, muzzle))

func _glow(center: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(glow_tex,
		Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		false, color)
