extends Node

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

	var left_need: float = ui.main_menu._left_panel.get_combined_minimum_size().y
	var left_pos: Vector2 = ui.main_menu._left_panel.position
	var left_bottom: float = left_pos.y + left_need
	var left_fits: bool = left_bottom <= MIN_SCREEN.y - 20.0 and left_pos.y >= 20.0
	print("левая панель: высота %.0f px, позиция y=%.0f px, низ=%.0f px" % [left_need, left_pos.y, left_bottom])

	var fits := need <= MIN_SCREEN.y - 40.0
	var failures := 0
	if fits:
		print("  ок: панель настроек влезает, запас %.0f px" % (MIN_SCREEN.y - 40.0 - need))
	else:
		failures += 1
		print("  ОШИБКА: панель настроек выше экрана на %.0f px" % (need - (MIN_SCREEN.y - 40.0)))

	if left_fits:
		print("  ок: левая панель влезает, отступ снизу %.0f px, сверху %.0f px" % [MIN_SCREEN.y - left_bottom, left_pos.y])
	else:
		failures += 1
		print("  ОШИБКА: левая панель не влезает! y=%.0f, низ=%.0f" % [left_pos.y, left_bottom])

	print("=== ПРОВЕРКА МЕНЮ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(failures)
