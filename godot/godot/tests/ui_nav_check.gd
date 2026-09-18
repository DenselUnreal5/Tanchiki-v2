# ============================================================================
# ui_nav_check.gd — навигация по интерфейсу геймпадом/клавиатурой.
#
# Проверяет то, чего не видно в headless и на снимках: что при открытии
# каждого экрана фокус куда-то встаёт (без этого крестовина мертва), что
# «назад» (ui_cancel) закрывает верхний оверлей, что кнопка A нажимает
# карточку перка, и что режим навигации переключается с мыши на геймпад
# и обратно (рамка фокуса появляется и исчезает).
#
# Нужен настоящий Viewport — фокус и push_input в headless не работают:
#   godot --path godot --resolution 1280x720 res://tests/ui_nav_check.tscn
# ============================================================================
extends Node

var game: Node
var failures := 0

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(30)

	var ui = game.ui

	# ---- главное меню: фокус на «ИГРАТЬ» -------------------------------
	ui.show_menu()
	await _frames(6)
	_check(_focus() == ui._menu_start_btn, "в меню фокус на кнопке ИГРАТЬ")

	# ---- каждый экран оставляет фокус внутри себя --------------------
	for pair in [["_settings", "open_settings", "close_settings"],
			["_stats", "open_stats", "close_stats"],
			["_daily", "open_daily", "close_daily"],
			["_net", "open_net", "close_net"]]:
		var root = ui.get(pair[0])
		ui.call(pair[1])
		await _frames(8)
		var f = _focus()
		_check(f != null and root.is_ancestor_of(f),
			"%s: фокус внутри экрана" % pair[1])
		# ui_cancel закрывает верхний оверлей
		_send_action("ui_cancel")
		await _frames(8)
		_check(not root.visible, "%s: ui_cancel закрыл экран" % pair[1])

	# ---- хаб глушит фокус кнопок меню за собой ----------------------
	ui.open_gallery()
	await _frames(8)
	_check(_focus() != null and ui._hub.is_ancestor_of(_focus()),
		"хаб: фокус внутри")
	_check(ui._menu_start_btn.focus_mode == Control.FOCUS_NONE,
		"пока открыт хаб, кнопки меню не ловят фокус")
	ui.close_hub()
	await _frames(8)
	_check(ui._menu_start_btn.focus_mode == Control.FOCUS_ALL,
		"после закрытия хаба фокус кнопок меню вернулся")

	# ---- choice_row: крестовина влево-вправо между вариантами -------
	ui.open_settings()
	await _frames(8)
	var flow := _first_flow(ui._settings_body)
	if _check(flow != null and flow.get_child_count() >= 2, "в настройках есть ряд вариантов"):
		flow.get_child(0).grab_focus()
		await _frames(2)
		_send_action("ui_right")
		await _frames(4)
		_check(_focus() == flow.get_child(1), "ui_right переводит фокус на следующий вариант")
	ui.close_settings()
	await _frames(6)

	# ---- выбор перка: A нажимает карточку --------------------------
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	await _frames(8)
	if _check(game.state == "perk", "после старта открыт выбор перка"):
		var pf = _focus()
		_check(pf != null and ui._perk.is_ancestor_of(pf), "фокус на карточке перка")
		var before: int = game.perk_player.perk_ids.size() if game.perk_player != null else 0
		# ui_accept на кнопке разбирается в её _gui_input, а туда синтетический
		# InputEventAction не доходит — шлём настоящую клавишу.
		await _tap_key(KEY_ENTER)
		await _frames(6)
		var after: int = game.perk_player.perk_ids.size() if game.perk_player != null else 0
		var advanced: bool = game.state != "perk" or after > before or not ui._perk.visible
		_check(advanced, "кнопка A выбрала перк под фокусом")
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
		await _frames(2)

	# ---- режим навигации: мышь ↔ геймпад --------------------------
	_send(_pad_button(0))
	await _frames(4)
	_check(Sets.pad_ui, "кнопка геймпада включает режим навигации")
	_check(ui._nav_theme.get_stylebox("focus", "Button") is StyleBoxFlat,
		"в режиме навигации у кнопок есть рамка фокуса")
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(6, 6)
	_send(mm)
	await _frames(4)
	_check(not Sets.pad_ui, "движение мыши возвращает мышиный режим")
	_check(ui._nav_theme.get_stylebox("focus", "Button") is StyleBoxEmpty,
		"в мышином режиме рамки фокуса нет")

	if failures == 0:
		print("ВСЕ ПРОВЕРКИ НАВИГАЦИИ ПРОШЛИ")
	else:
		print("ПРОВАЛЕНО ПРОВЕРОК: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()

func _first_flow(node: Node) -> HFlowContainer:
	if node is HFlowContainer and node.get_child_count() >= 2 \
			and node.get_child(0) is Button:
		return node
	for c in node.get_children():
		var f := _first_flow(c)
		if f != null:
			return f
	return null

func _pad_button(idx: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = idx
	e.pressed = true
	return e

func _send(ev: InputEvent) -> void:
	get_viewport().push_input(ev)

func _send_action(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	get_viewport().push_input(e)

## Настоящее нажатие клавиши: down, кадр, up. Кнопки срабатывают на
## отпускании (ACTION_MODE_BUTTON_RELEASE), поэтому нужны оба события.
func _tap_key(keycode: int) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	get_viewport().push_input(down)
	await _frames(2)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	get_viewport().push_input(up)

func _check(ok: bool, what: String) -> bool:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ПРОВАЛ: ", what)
	return ok

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
