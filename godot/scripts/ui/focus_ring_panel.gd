# ============================================================================
# focus_ring_panel.gd — PanelContainer, умеющий получать фокус геймпада/
# клавиатуры и рисующий вокруг себя рамку сам. Обычные PanelContainer/
# Container ничего не знают про фокус (это встроено только в интерактивные
# виджеты вроде Button/Range, а не в контейнеры), а UiKit.focus_ring()
# применяется только через тему конкретных типов (_apply_nav_mode в
# ui_root.gd). Некликабельная цель фокуса: карточки достижений и заглушка
# «МАКС» у прокачанного до предела улучшения в Гараже.
# ============================================================================
class_name FocusRingPanel
extends PanelContainer

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	if has_focus():
		draw_style_box(UiKit.focus_ring(), Rect2(Vector2.ZERO, size))
