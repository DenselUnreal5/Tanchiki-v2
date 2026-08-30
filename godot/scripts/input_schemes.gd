# ============================================================================
# input_schemes.gd — схемы управления.
#
# Всё читается по ФИЗИЧЕСКОЙ клавише (is_physical_key_pressed), поэтому
# раскладка (русская/английская) не имеет значения, а Numpad работает
# независимо от NumLock.
#
# Наводка и выстрел у второго игрока разделены: можно прицелиться молча.
# ============================================================================
class_name Ctl
extends RefCounted

## Общая структура команды управления танком.
static func empty_command() -> Dictionary:
	return {"mx": 0.0, "my": 0.0, "ax": 0.0, "ay": 0.0,
		"fire": false, "mine": false, "dash": false, "airstrike": false,
		"ability": false}

## Применяет команду к танку.
static func apply_command(tank: Tank, world, cmd: Dictionary) -> void:
	if tank == null or not tank.alive or cmd.is_empty():
		return
	tank.thrust(float(cmd["mx"]), float(cmd["my"]))
	tank.aim_at(float(cmd["ax"]), float(cmd["ay"]))
	if bool(cmd["fire"]):
		tank.shoot(world)
	if bool(cmd["mine"]):
		tank.place_mine(world)
	if bool(cmd["dash"]):
		tank.dash()
	if bool(cmd["airstrike"]):
		world.trigger_airstrike(tank.owner)
	if bool(cmd.get("ability", false)):
		tank.use_ability(world)

# ---------------------------------------------------------------------------
# Управление мышью: WASD + прицел мышью. Основная схема первого игрока.
# ---------------------------------------------------------------------------
class MouseAimScheme extends RefCounted:
	## Разрешить стрелки как дубль WASD (одиночная игра).
	var allow_arrows := true
	## Позиция курсора в координатах окна — обновляется игрой каждый кадр.
	var mouse := Vector2.ZERO

	func _init(allow_arrows_: bool = true) -> void:
		allow_arrows = allow_arrows_

	func hints() -> Array:
		return [
			"[W][A][S][D] движение",
			"[мышь] прицел",
			"[ЛКМ] / [Space] выстрел",
			"[E] / [ПКМ] мина",
			"[Shift] рывок-таран",
			"[Q] способность перка",
			"[F] авиаудар (Оборона)",
		]

	func read_command(player) -> Dictionary:
		var cmd := Ctl.empty_command()
		var mx := 0.0
		var my := 0.0
		if Input.is_physical_key_pressed(KEY_W) or (allow_arrows and Input.is_physical_key_pressed(KEY_UP)):
			my -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or (allow_arrows and Input.is_physical_key_pressed(KEY_DOWN)):
			my += 1.0
		if Input.is_physical_key_pressed(KEY_A) or (allow_arrows and Input.is_physical_key_pressed(KEY_LEFT)):
			mx -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or (allow_arrows and Input.is_physical_key_pressed(KEY_RIGHT)):
			mx += 1.0

		var w: Vector2 = player.screen_to_world(mouse.x, mouse.y)
		cmd["mx"] = mx
		cmd["my"] = my
		cmd["ax"] = w.x
		cmd["ay"] = w.y
		cmd["fire"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)
		cmd["mine"] = Input.is_physical_key_pressed(KEY_E) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		cmd["dash"] = Input.is_key_pressed(KEY_SHIFT) and not Input.is_physical_key_pressed(KEY_KP_0)
		cmd["airstrike"] = Input.is_physical_key_pressed(KEY_F)
		cmd["ability"] = Input.is_physical_key_pressed(KEY_Q)
		return cmd

	func apply(tank: Tank, player, world) -> void:
		Ctl.apply_command(tank, world, read_command(player))

# ---------------------------------------------------------------------------
# Сетевая схема: ввод не читается с клавиатуры, а берётся из последнего
# пакета, пришедшего от этого игрока. Живёт только у хоста — именно он
# применяет чужой ввод к чужим танкам.
#
# Пакет намеренно не сбрасывается после применения: при потере одного кадра
# ввода танк продолжает ехать, куда ехал, а не дёргается в стоп-кадр.
# ---------------------------------------------------------------------------
class NetScheme extends RefCounted:
	var peer_id := 0

	func _init(peer_id_: int) -> void:
		peer_id = peer_id_

	func hints() -> Array:
		return []

	func apply(tank: Tank, player, world) -> void:
		var cmd: Dictionary = Net.command_of(peer_id)
		if cmd.is_empty():
			return
		Ctl.apply_command(tank, world, cmd)

# ---------------------------------------------------------------------------
# Клавиатурная схема второго игрока («горячий стул»).
#
# Стрелки или Numpad 8/4/6/2 — движение. Башня по умолчанию доворачивается
# в сторону движения, а если держать клавиши поворота (< >, Numpad 7/9),
# она управляется вручную и сохраняет угол после отпускания.
# ---------------------------------------------------------------------------
class KeyboardAimScheme extends RefCounted:
	var turret_slew := 0.07   # рад/тик при ручном повороте
	var follow_slew := 0.05   # рад/тик при доворотe за корпусом

	func hints() -> Array:
		return [
			"[↑][←][↓][→] движение",
			"[<][>] поворот башни",
			"[Правый Shift] / [Num 0] выстрел",
			"[Num .] / [Правый Ctrl] мина",
			"[Num +] рывок-таран",
			"[Num -] способность перка",
		]

	func apply(tank: Tank, player, world) -> void:
		var dx := 0.0
		var dy := 0.0
		if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_KP_8):
			dy -= 1.0
		if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_KP_2):
			dy += 1.0
		if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_KP_4):
			dx -= 1.0
		if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_KP_6):
			dx += 1.0
		var moving := dx != 0.0 or dy != 0.0
		tank.thrust(dx, dy)

		var rot_left := Input.is_physical_key_pressed(KEY_COMMA) or Input.is_physical_key_pressed(KEY_KP_7)
		var rot_right := Input.is_physical_key_pressed(KEY_PERIOD) or Input.is_physical_key_pressed(KEY_KP_9)

		if rot_left and not rot_right:
			tank.turret_angle -= turret_slew
		elif rot_right and not rot_left:
			tank.turret_angle += turret_slew
		elif moving:
			# Ручного поворота нет — башня плавно смотрит туда, куда едем.
			tank.turret_angle = Rng.rotate_toward(tank.turret_angle, tank.angle, follow_slew)

		if Input.is_physical_key_pressed(KEY_KP_0) or Input.is_physical_key_pressed(KEY_KP_5) \
				or Input.is_physical_key_pressed(KEY_SLASH) or Input.is_physical_key_pressed(KEY_KP_ENTER):
			tank.shoot(world)
		if Input.is_physical_key_pressed(KEY_KP_PERIOD) or Input.is_physical_key_pressed(KEY_DELETE):
			tank.place_mine(world)
		if Input.is_physical_key_pressed(KEY_KP_ADD):
			tank.dash()
		if Input.is_physical_key_pressed(KEY_KP_SUBTRACT):
			tank.use_ability(world)
