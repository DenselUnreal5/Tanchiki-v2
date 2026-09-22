@tool
class_name FocusRingPanel
extends PanelContainer

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	if has_focus():
		draw_style_box(UiKit.focus_ring(), Rect2(Vector2.ZERO, size))
