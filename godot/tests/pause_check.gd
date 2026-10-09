extends Node

var game: Node
var failures := 0

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(30)
	var ui = game.ui

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	await _frames(6)
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	await _frames(4)

	game.pause()
	await _frames(6)
	_check(game.state == "paused" and ui._pause.visible, "пауза открылась")
	_check(ui._pause_restart_btn.visible, "кнопка перезапуска видна в локальной игре")

	ui._pause_restart_btn.pressed.emit()
	await _frames(2)
	_check(game.state == "paused" and ui._pause_restart_armed, "первое нажатие только просит подтверждение")
	var armed_text: String = ui._pause_restart_btn.text
	game.resume()
	game.pause()
	await _frames(4)
	_check(not ui._pause_restart_armed and ui._pause_restart_btn.text != armed_text,
		"подтверждение сбрасывается при новом открытии паузы")

	ui.open_controls()
	await _frames(4)
	_check(ui.is_controls_open, "справка по управлению открылась")
	var lines := _label_texts(ui._controls_body)
	_check(lines.size() >= 6, "в справке есть строки управления (%d)" % lines.size())
	var has_fire := false
	for t in lines:
		if t.contains(Ctl.key_name("p1_fire")):
			has_fire = true
	_check(has_fire, "справка показывает актуальную клавишу выстрела")
	_check(ui.handle_cancel() and not ui.is_controls_open and ui._pause.visible,
		"Esc закрывает справку, пауза остаётся")

	var world_before = game.world
	ui._pause_restart_btn.pressed.emit()
	ui._pause_restart_btn.pressed.emit()
	await _frames(30)
	_check(game.world != null and game.world != world_before, "после подтверждения создан новый матч")
	_check(not ui._pause.visible, "пауза закрыта после перезапуска")
	_check(game.state == "playing" or game.state == "perk", "игра идёт после перезапуска (%s)" % game.state)

	print("=== ПРОВЕРКА ПАУЗЫ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _label_texts(node: Node) -> Array:
	var out := []
	if node is Label:
		out.append(node.text)
	for c in node.get_children():
		out.append_array(_label_texts(c))
	return out

func _check(ok: bool, what: String) -> bool:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
	return ok

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
