extends Node

var game: Node
var failures := 0
var pause_hits := 0

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for i in 30:
		await get_tree().process_frame
	_check_scheme()
	_check_overlay()
	_check_auto_switch()
	await _check_match()
	print("=== ПРОВЕРКА СЕНСОРНОГО УПРАВЛЕНИЯ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

class FakePlayer:
	var tank = null

func _check_scheme() -> void:
	var s := Ctl.TouchScheme.new()
	var p := FakePlayer.new()
	var cmd := s.read_command(p)
	_check(cmd["mx"] == 0.0 and not cmd["fire"] and not cmd["dash"], "без касаний команда пустая")
	s.move = Vector2(1.0, 0.0)
	cmd = s.read_command(p)
	_check(is_equal_approx(float(cmd["mx"]), 1.0), "левый палец задаёт движение")
	s.move = Vector2(0.1, 0.1)
	cmd = s.read_command(p)
	_check(cmd["mx"] == 0.0 and cmd["my"] == 0.0, "в мёртвой зоне движения нет")
	s.aim = Vector2(0.3, 0.0)
	_check(not s.read_command(p)["fire"], "лёгкий наклон правого стика только целится")
	s.aim = Vector2(0.9, 0.0)
	_check(s.read_command(p)["fire"], "сильный наклон правого стика стреляет")
	s.dash = true
	s.mine = true
	cmd = s.read_command(p)
	_check(cmd["dash"] and cmd["mine"] and not cmd["ability"], "кнопки попадают в команду")
	s.release_all()
	cmd = s.read_command(p)
	_check(not cmd["dash"] and not cmd["fire"] and cmd["mx"] == 0.0, "release_all снимает всё")
	_check(s.hints().size() == 3, "у схемы есть подсказки для справки")

func _check_overlay() -> void:
	var overlay := TouchControls.new()
	add_child(overlay)
	overlay.size = Vector2(1280.0, 720.0)
	var scheme := Ctl.TouchScheme.new()
	overlay.set_scheme(scheme, null, true)
	_check(overlay.visible, "оверлей виден для сенсорной схемы")
	overlay.pause_pressed.connect(func(): pause_hits += 1)

	overlay.begin(0, Vector2(200.0, 500.0))
	overlay.drag(0, Vector2(270.0, 500.0))
	_check(scheme.move.is_equal_approx(Vector2(1.0, 0.0)), "стик движения: сдвиг на радиус даёт 1.0 (%s)" % str(scheme.move))
	overlay.begin(1, Vector2(900.0, 500.0))
	overlay.drag(1, Vector2(900.0, 430.0))
	_check(scheme.aim.is_equal_approx(Vector2(0.0, -1.0)), "стик прицела независим от стика движения (%s)" % str(scheme.aim))
	overlay.drag(1, Vector2(900.0, 1000.0))
	_check(is_equal_approx(scheme.aim.length(), 1.0), "вектор стика не длиннее единицы")
	overlay.finish(0)
	_check(scheme.move == Vector2.ZERO and scheme.aim != Vector2.ZERO, "отпускание левого пальца не трогает правый")
	overlay.finish(1)
	_check(scheme.aim == Vector2.ZERO, "отпускание правого пальца обнуляет прицел")

	var dash_pos := Vector2.ZERO
	for d in overlay.button_defs():
		if d["id"] == "dash":
			dash_pos = d["pos"]
	overlay.begin(2, dash_pos)
	_check(scheme.dash, "кнопка рывка нажата")
	overlay.drag(2, dash_pos + Vector2(500.0, 0.0))
	_check(scheme.dash and scheme.move == Vector2.ZERO, "палец на кнопке не двигает стики")
	overlay.finish(2)
	_check(not scheme.dash, "кнопка рывка отпущена")
	_check(overlay.button_defs().size() == 4, "в обороне есть кнопка авиаудара")
	overlay.set_scheme(scheme, null, false)
	_check(overlay.button_defs().size() == 3, "вне обороны кнопки авиаудара нет")

	overlay.begin(3, overlay.pause_center())
	_check(pause_hits == 1, "кнопка паузы сообщает о нажатии")

	overlay.begin(4, Vector2(300.0, 300.0))
	overlay.drag(4, Vector2(340.0, 300.0))
	overlay.set_scheme(Ctl.MouseAimScheme.new(), null, false)
	_check(not overlay.visible and scheme.move == Vector2.ZERO, "при смене схемы оверлей скрыт, а управление отпущено")
	overlay.queue_free()

func _check_auto_switch() -> void:
	var kbm := Ctl.KeyboardAimScheme.new()
	var pad := Ctl.GamepadScheme.new(0)
	var touch := Ctl.TouchScheme.new()
	var p := PlayerState.new(0, "Тест", "p1", kbm)
	var dummy := Tank.new({"x": 100.0, "y": 100.0, "team": "t", "name": "x", "owner": null,
		"max_hp": 10.0, "speed": 1.0, "fire_rate": 20, "color_key": "p1",
		"chassis": "standard", "dmg_scale": 1.0})
	p.enable_auto_device_switch(kbm, pad, touch)
	var saved_touch := Sets.last_input_touch
	var saved_pad := Sets.last_input_pad
	Sets.last_input_pad = false
	Sets.last_input_touch = true
	touch.move = Vector2(1.0, 0.0)
	p.control(dummy, null)
	_check(p.scheme == touch, "последний ввод — касание: выбрана сенсорная схема")
	Sets.last_input_touch = false
	p.control(dummy, null)
	_check(p.scheme == kbm and touch.move == Vector2.ZERO, "после клавиатуры сенсорная схема отпущена")
	Sets.last_input_touch = saved_touch
	Sets.last_input_pad = saved_pad

func _check_match() -> void:
	var saved_device := Sets.p1_device
	Sets.p1_device = Sets.DEV_TOUCH
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	for i in 6:
		await get_tree().process_frame
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	for i in 4:
		await get_tree().process_frame
	var player = game.players[0]
	_check(player.scheme is Ctl.TouchScheme, "в матче выбрана сенсорная схема")
	_check(game._touch.visible, "оверлей показан во время боя")
	var tank: Tank = player.tank
	tank.spawn_protect = 0
	var start_x := tank.x
	game._touch.begin(0, Vector2(200.0, 500.0))
	game._touch.drag(0, Vector2(270.0, 500.0))
	game._touch.begin(1, Vector2(900.0, 500.0))
	game._touch.drag(1, Vector2(960.0, 500.0))
	for i in 40:
		game.world.step()
	_check(absf(tank.x - start_x) > 10.0, "танк поехал по касанию (%.0f px)" % (tank.x - start_x))
	_check(tank.shots_fired > 0, "сильный прицел вызвал выстрел (%d)" % tank.shots_fired)
	game._touch.finish(0)
	game._touch.finish(1)
	game.pause()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not game._touch.visible, "на паузе оверлей скрыт")
	game.resume()
	Sets.p1_device = saved_device

func _check(ok: bool, what: String) -> bool:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
	return ok
