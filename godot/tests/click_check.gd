extends Node

var game: Node
var failures := 0

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(30)

	await _check_main_menu_button("Гараж", func(): return bool(game.ui.is_garage_open))
	game.ui.close_garage()
	await _frames(5)

	await _check_main_menu_button("Галерея перков", func(): return bool(game.ui.is_gallery_open))
	game.ui.close_gallery()
	await _frames(5)

	await _check_main_menu_button("Достижения", func(): return bool(game.ui.is_achievements_open))
	game.ui.close_achievements()
	await _frames(5)

	game.ui.open_gallery()
	await _frames(10)
	await _check_hub_tab("ГАРАЖ", "garage")
	await _check_hub_tab("ДОСТИЖЕНИЯ", "achievements")
	await _check_hub_tab("ГАЛЕРЕЯ ПЕРКОВ", "gallery")

	game.ui.close_hub()
	await _frames(5)
	game.ui.open_settings()
	await _frames(10)
	await _check_and_click("Sci-Fi", func(): return true)
	await _frames(5)
	game.ui.close_settings()
	await _frames(5)

	await _check_main_menu_button("Гараж", func(): return bool(game.ui.is_garage_open))
	game.ui.close_garage()
	await _frames(5)

	await _check_main_menu_button("Галерея перков", func(): return bool(game.ui.is_gallery_open))
	game.ui.close_gallery()
	await _frames(5)

	await _check_main_menu_button("Достижения", func(): return bool(game.ui.is_achievements_open))
	game.ui.close_achievements()
	await _frames(5)

	if failures == 0:
		print("ВСЕ ПРОВЕРКИ ПРОШЛИ")
	else:
		print("ПРОВАЛЕНО ПРОВЕРОК: %d" % failures)
	get_tree().quit()

func _check_and_click(label_substr: String, ok: Callable) -> void:
	var btn := _find_button(game.ui, label_substr)
	if btn == null:
		print("НЕ НАЙДЕНА кнопка: %s" % label_substr)
		failures += 1
		return
	print("кнопка «%s»: найдена, позиция %s" % [label_substr, btn.global_position])
	await _click(btn)
	await _frames(8)
	if not ok.call():
		print("  ПРОВАЛ после клика по «%s»" % label_substr)
		failures += 1

func _check_main_menu_button(label_substr: String, is_open: Callable) -> void:
	var btn := _find_button(game.ui, label_substr)
	if btn == null:
		print("НЕ НАЙДЕНА кнопка меню: %s" % label_substr)
		failures += 1
		return
	print("кнопка меню «%s»: найдена, позиция %s, видима %s" % [label_substr, btn.global_position, btn.visible])
	await _click(btn)
	await _frames(8)
	if is_open.call():
		print("  OK: открылось по клику")
	else:
		print("  ПРОВАЛ: клик по «%s» не открыл экран" % label_substr)
		failures += 1

func _check_hub_tab(label_substr: String, expect_tab: String) -> void:
	var btn := _find_button(game.ui, label_substr)
	if btn == null:
		print("НЕ НАЙДЕНА вкладка хаба: %s" % label_substr)
		failures += 1
		return
	print("вкладка хаба «%s»: найдена, позиция %s" % [label_substr, btn.global_position])
	await _click(btn)
	await _frames(8)
	var active = game.ui.get("_hub_active_tab")
	if active == expect_tab:
		print("  OK: активная вкладка стала «%s»" % expect_tab)
	else:
		print("  ПРОВАЛ: клик по «%s» не переключил вкладку (осталась «%s»)" % [label_substr, active])
		failures += 1

func _find_button(root: Node, label_substr: String) -> Button:
	if root is Button and String(root.text).contains(label_substr):
		return root
	for c in root.get_children():
		var found := _find_button(c, label_substr)
		if found != null:
			return found
	return null

func _click(ctrl: Control) -> void:
	var pos := ctrl.global_position + ctrl.size * 0.5
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	get_viewport().push_input(down)
	await _frames(2)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	get_viewport().push_input(up)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
