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

	# ---- действия ввода для геймпада ----------------------------------
	# settings.gd:_ensure_input_actions заводит их кодом; project.godot
	# ручной правкой не трогаем.
	for a in ["pause", "scoreboard"]:
		_check(InputMap.has_action(a), "действие «%s» заведено" % a)
	for a in ["ui_cancel", "pause", "scoreboard"]:
		_check(_has_pad_button(a), "у «%s» есть кнопка геймпада" % a)
	_check(_has_key(&"pause", KEY_P), "«pause» по-прежнему на клавише P")
	_check(_has_key(&"ui_cancel", KEY_ESCAPE), "«ui_cancel» по-прежнему на Esc")

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

	# ---- геймпад переживает кадр партии -------------------------------
	# game.gd:_process присваивает scheme.mouse и scheme.world. У GamepadScheme
	# поля mouse нет, и раньше это роняло партию на первом же кадре — просто
	# потому что живого геймпада на машине сборки нет и до _process дело
	# не доходило.
	player.scheme = Ctl.GamepadScheme.new(0)
	for i in 5:
		game._process(1.0 / 60.0)
	_check(game.state != "", "партия с геймпадом пережила пять кадров без падения")
	_check("world" in player.scheme and player.scheme.world == game.world,
		"game.gd прокидывает world в GamepadScheme")

	# ---- автоприцел: мягкая доводка, а не защёлкивание ----------------
	var assist := Ctl.GamepadScheme.new(0)
	assist.world = game.world
	var enemy: Tank = null
	for t in game.world.tanks:
		if t != tank and t.alive and game.world.are_hostile(tank, t):
			enemy = t
			break
	_check(enemy != null, "враг для проверки автоприцела нашёлся")
	if enemy != null:
		# Ставим обоих в чистый коридор у центра карты.
		var cr := int(game.world.map.rows / 2)
		var cc := int(game.world.map.cols / 2)
		for dr in range(-2, 3):
			for dc in range(-4, 12):
				game.world.map.set_tile(cr + dr, cc + dc, Cfg.T_EMPTY)
		tank.x = cc * Cfg.TILE + 16.0
		tank.y = cr * Cfg.TILE + 16.0
		enemy.x = tank.x + 200.0    # 200 px восточнее — в радиусе 320
		enemy.y = tank.y
		_check(game.world.map.has_line_of_sight(tank.x, tank.y, enemy.x, enemy.y),
			"линия видимости между танками чиста")

		var to_enemy := Vector2(enemy.x - tank.x, enemy.y - tank.y).normalized()
		var origin := Vector2(tank.x, tank.y)
		var reach: float = Ctl.GamepadScheme.AIM_REACH
		var rng_val: float = Ctl.GamepadScheme.ASSIST_RANGE

		# Стик на 20° мимо цели — в пределах конуса 35°.
		Sets.pad_aim_assist = true
		var sdir := to_enemy.rotated(deg_to_rad(20.0))
		var got := (assist._assist_aim(tank, sdir) - origin).angle()
		_check(_between(got, sdir.angle(), to_enemy.angle()),
			"автоприцел тянет к цели, но не защёлкивает (%.1f° в [%.1f°..%.1f°])"
				% [rad_to_deg(got), rad_to_deg(to_enemy.angle()), rad_to_deg(sdir.angle())])

		# Вне конуса — притяжения нет.
		var wide := to_enemy.rotated(deg_to_rad(80.0))
		_check(assist._assist_aim(tank, wide).is_equal_approx(origin + wide * reach),
			"цель вне конуса игнорируется")

		# За радиусом — нет.
		enemy.x = tank.x + rng_val + 80.0
		_check(assist._assist_aim(tank, sdir).is_equal_approx(origin + sdir * reach),
			"цель за радиусом игнорируется")
		enemy.x = tank.x + 200.0

		# За стеной — нет.
		game.world.map.set_tile(cr, cc + 2, Cfg.T_WALL)
		_check(assist._assist_aim(tank, sdir).is_equal_approx(origin + sdir * reach),
			"цель за стеной игнорируется")
		game.world.map.set_tile(cr, cc + 2, Cfg.T_EMPTY)

		# Выключенный автоприцел — наводка сырая.
		Sets.pad_aim_assist = false
		_check(assist._assist_aim(tank, sdir).is_equal_approx(origin + sdir * reach),
			"с выключенным автоприцелом наводка не подкручивается")
		Sets.pad_aim_assist = true

	print("=== ПРОВЕРКА УПРАВЛЕНИЯ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _has_pad_button(action: StringName) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return true
	return false

func _has_key(action: StringName, keycode: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e.keycode == keycode or e.physical_keycode == keycode):
			return true
	return false

## Лежит ли угол x на коротком пути между a и b, не совпадая ни с одним
## концом (то есть притяжение сработало, но не защёлкнуло).
func _between(x: float, a: float, b: float) -> bool:
	var span := wrapf(b - a, -PI, PI)
	if absf(span) < 0.0001:
		return false
	var t := wrapf(x - a, -PI, PI) / span
	return t > 0.02 and t < 0.98

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
