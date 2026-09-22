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

	var fits := need <= MIN_SCREEN.y - 40.0
	var failures := 0
	if fits:
		print("  ок: панель влезает, запас %.0f px" % (MIN_SCREEN.y - 40.0 - need))
	else:
		failures = 1
		print("  ОШИБКА: панель выше экрана на %.0f px" % (need - (MIN_SCREEN.y - 40.0)))

	print("=== ПРОВЕРКА МЕНЮ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(failures)
