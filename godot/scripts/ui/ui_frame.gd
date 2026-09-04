# ============================================================================
# ui_frame.gd — декоративная накладка «военной техники»: уголки-скобы по
# углам панели и слабые сканлайны поверх. Никаких текстур — как и весь
# остальной интерфейс, рисуется процедурно (см. menu_scene.gd).
#
# Добавляется последним ребёнком поверх готовой панели: сама не ловит мышь
# и не участвует в раскладке.
# ============================================================================
class_name UiFrame
extends Control

var color: Color = Color("#33e6c9")
var bracket_len := 16.0
var bracket_inset := 4.0
var scanlines := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_corner(Vector2(bracket_inset, bracket_inset), Vector2(1, 1))
	_draw_corner(Vector2(size.x - bracket_inset, bracket_inset), Vector2(-1, 1))
	_draw_corner(Vector2(bracket_inset, size.y - bracket_inset), Vector2(1, -1))
	_draw_corner(Vector2(size.x - bracket_inset, size.y - bracket_inset), Vector2(-1, -1))
	if scanlines:
		_draw_scanlines()

## Уголок-скоба: буква «Г», развёрнутая по знаку dir в нужную сторону.
func _draw_corner(at: Vector2, dir: Vector2) -> void:
	draw_line(at, at + Vector2(bracket_len * dir.x, 0), color, 2.0)
	draw_line(at, at + Vector2(0, bracket_len * dir.y), color, 2.0)
	draw_circle(at, 2.0, color)

func _draw_scanlines() -> void:
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(color, 0.035), 1.0)
		y += 3.0
