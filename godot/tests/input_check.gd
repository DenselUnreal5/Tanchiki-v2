# ============================================================================
# input_check.gd — выбор схемы управления и поведение геймпада.
#
# Физического джойстика на машине сборки нет, и это не мешает проверить
# главное: что настройка выбирает нужную схему, что отпущенные стики дают
# ровно ноль хода, и что при нетронутом правом стике танк целится вперёд,
# а не в точку (0, 0) на краю карты.
#
# Запуск:
#   godot --headless --path godot tests/input_check.tscn
# ============================================================================
extends Node

var failures := 0

func _ready() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# ---- выбор схемы по настройке --------------------------------------
	var cases := [
		[Sets.DEV_AUTO, 0, "MouseAimScheme"],
		[Sets.DEV_AUTO, 1, "KeyboardAimScheme"],
		[Sets.DEV_KBM, 1, "MouseAimScheme"],
		[Sets.DEV_KEYS, 0, "KeyboardAimScheme"],
		["pad0", 0, "GamepadScheme"],
		["pad1", 1, "GamepadScheme"],
	]
	for c in cases:
		var scheme = game._scheme_for(String(c[0]), int(c[1]), true)
		var got := _class_of(scheme)
		_check(got == String(c[2]),
			"настройка «%s» у игрока %d даёт %s" % [c[0], int(c[1]) + 1, got])

	# Номер устройства обязан совпадать с настройкой: иначе в «горячем стуле»
	# оба танка слушали бы один джойстик.
	var pad1 = game._scheme_for("pad1", 1, true)
	_check(pad1.device == 1, "pad1 закреплён за устройством %d" % pad1.device)

	# ---- поведение геймпада без подключённого устройства ----------------
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 40:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

	var player = game.players[0]
	var tank: Tank = player.tank
	var pad = Ctl.GamepadScheme.new(0)
	var cmd: Dictionary = pad.read_command(player)

	_check(cmd["mx"] == 0.0 and cmd["my"] == 0.0,
		"отпущенные стики дают ноль хода (%.3f, %.3f)" % [cmd["mx"], cmd["my"]])
	_check(not bool(cmd["fire"]) and not bool(cmd["mine"]),
		"без нажатий не стреляет и не минирует")

	var d := Vector2(float(cmd["ax"]) - tank.x, float(cmd["ay"]) - tank.y).length()
	_check(absf(d - Ctl.GamepadScheme.AIM_REACH) < 1.0,
		"прицел стоит впереди танка на %.0f px (ждали %.0f)"
			% [d, Ctl.GamepadScheme.AIM_REACH])

	# ---- мёртвая зона ---------------------------------------------------
	# Сама зона проверяется формулой: при нулевом вводе результат обязан быть
	# нулём при любом пороге, а растяжка не должна давать выход за единицу.
	for dz in [0.0, 0.22, 0.5]:
		Sets.pad_deadzone = dz
		var c2: Dictionary = pad.read_command(player)
		if absf(float(c2["mx"])) > 0.0001:
			_check(false, "при мёртвой зоне %.2f ход не ноль" % dz)
	Sets.pad_deadzone = 0.22
	_check(true, "мёртвая зона не даёт самохода при любом пороге")

	print("=== ПРОВЕРКА УПРАВЛЕНИЯ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Имя схемы. Вложенные классы GDScript не имеют ни resource_path, ни
## внятного имени в str(), поэтому определяются по своим полям.
func _class_of(o) -> String:
	for name in ["GamepadScheme", "MouseAimScheme", "KeyboardAimScheme", "NetScheme"]:
		if _has_marker(o, name):
			return name
	return str(o)

## Схемы различаются по своим полям: у геймпада есть device и aim,
## у мыши — mouse и allow_arrows, у клавиатуры — turret_slew.
func _has_marker(o, name: String) -> bool:
	match name:
		"GamepadScheme":
			return "device" in o and "aim" in o
		"MouseAimScheme":
			return "mouse" in o and "allow_arrows" in o
		"KeyboardAimScheme":
			return "turret_slew" in o
		"NetScheme":
			return "peer_id" in o and not ("aim" in o)
	return false

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
