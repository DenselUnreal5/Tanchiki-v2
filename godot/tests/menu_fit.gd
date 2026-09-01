# ============================================================================
# menu_fit.gd — влезает ли панель настроек боя в экран.
#
# Панель не прокручивается: её высота равна сумме групп. Каждая новая строка
# настроек (режим, сложность, уровень, локация, погода, время, два цвета)
# делает её выше, и в какой-то момент нижние группы уезжают за край экрана —
# молча, без единой ошибки в консоли.
#
# Запуск:
#   godot --headless --path godot tests/menu_fit.tscn
# ============================================================================
extends Node

## Самое маленькое окно, которое игра обязана обслуживать.
const MIN_SCREEN := Vector2(1280, 720)

func _ready() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for i in 6:
		await get_tree().process_frame

	var ui = game.ui
	ui._menu_settings_panel.visible = true
	for i in 6:
		await get_tree().process_frame

	var need: float = ui._menu_settings_panel.get_combined_minimum_size().y
	var groups := 0
	for c in ui._menu_settings.get_children():
		groups += 1
	print("групп настроек: %d, высота панели: %.0f px" % [groups, need])
	print("экран проверки: %.0fx%.0f px" % [MIN_SCREEN.x, MIN_SCREEN.y])

	# Панель центрируется по вертикали, поэтому запас нужен с обеих сторон.
	var fits := need <= MIN_SCREEN.y - 40.0
	var failures := 0
	if fits:
		print("  ок: панель влезает, запас %.0f px" % (MIN_SCREEN.y - 40.0 - need))
	else:
		failures = 1
		print("  ОШИБКА: панель выше экрана на %.0f px" % (need - (MIN_SCREEN.y - 40.0)))

	print("=== ПРОВЕРКА МЕНЮ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(failures)
