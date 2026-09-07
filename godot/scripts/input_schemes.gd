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

## Клавиши по умолчанию для переназначаемых действий (см. Sets.key_for/
## Sets.set_key, вкладка «Управление» в настройках). Один физический
## keycode на действие — там, где в схемах ниже раньше было несколько
## клавиш-дублей одного действия, дефолт здесь — только одна из них
## (обычно самая «настоящая», не-numpad), остальные варианты убраны.
## Мышь (ЛКМ/ПКМ у игрока 1) и Num-дубли движения/башни игрока 2 —
## отдельная, непереназначаемая механика, сюда не входят.
const DEFAULT_KEYS := {
	"p1_up": KEY_W, "p1_down": KEY_S, "p1_left": KEY_A, "p1_right": KEY_D,
	"p1_fire": KEY_SPACE, "p1_mine": KEY_E, "p1_dash": KEY_SHIFT,
	"p1_airstrike": KEY_F, "p1_ability": KEY_Q,
	"p2_up": KEY_UP, "p2_down": KEY_DOWN, "p2_left": KEY_LEFT, "p2_right": KEY_RIGHT,
	"p2_turret_left": KEY_COMMA, "p2_turret_right": KEY_PERIOD,
	"p2_fire": KEY_SLASH, "p2_mine": KEY_DELETE,
	"p2_dash": KEY_KP_ADD, "p2_ability": KEY_KP_SUBTRACT,
}

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
		if Input.is_physical_key_pressed(Sets.key_for("p1_up")) or (allow_arrows and Input.is_physical_key_pressed(KEY_UP)):
			my -= 1.0
		if Input.is_physical_key_pressed(Sets.key_for("p1_down")) or (allow_arrows and Input.is_physical_key_pressed(KEY_DOWN)):
			my += 1.0
		if Input.is_physical_key_pressed(Sets.key_for("p1_left")) or (allow_arrows and Input.is_physical_key_pressed(KEY_LEFT)):
			mx -= 1.0
		if Input.is_physical_key_pressed(Sets.key_for("p1_right")) or (allow_arrows and Input.is_physical_key_pressed(KEY_RIGHT)):
			mx += 1.0

		var w: Vector2 = player.screen_to_world(mouse.x, mouse.y)
		cmd["mx"] = mx
		cmd["my"] = my
		cmd["ax"] = w.x
		cmd["ay"] = w.y
		cmd["fire"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(Sets.key_for("p1_fire"))
		cmd["mine"] = Input.is_physical_key_pressed(Sets.key_for("p1_mine")) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		cmd["dash"] = Input.is_physical_key_pressed(Sets.key_for("p1_dash"))
		cmd["airstrike"] = Input.is_physical_key_pressed(Sets.key_for("p1_airstrike"))
		cmd["ability"] = Input.is_physical_key_pressed(Sets.key_for("p1_ability"))
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
		if Input.is_physical_key_pressed(Sets.key_for("p2_up")) or Input.is_physical_key_pressed(KEY_KP_8):
			dy -= 1.0
		if Input.is_physical_key_pressed(Sets.key_for("p2_down")) or Input.is_physical_key_pressed(KEY_KP_2):
			dy += 1.0
		if Input.is_physical_key_pressed(Sets.key_for("p2_left")) or Input.is_physical_key_pressed(KEY_KP_4):
			dx -= 1.0
		if Input.is_physical_key_pressed(Sets.key_for("p2_right")) or Input.is_physical_key_pressed(KEY_KP_6):
			dx += 1.0
		var moving := dx != 0.0 or dy != 0.0
		tank.thrust(dx, dy)

		var rot_left := Input.is_physical_key_pressed(Sets.key_for("p2_turret_left")) or Input.is_physical_key_pressed(KEY_KP_7)
		var rot_right := Input.is_physical_key_pressed(Sets.key_for("p2_turret_right")) or Input.is_physical_key_pressed(KEY_KP_9)

		if rot_left and not rot_right:
			tank.turret_angle -= turret_slew
		elif rot_right and not rot_left:
			tank.turret_angle += turret_slew
		elif moving:
			# Ручного поворота нет — башня плавно смотрит туда, куда едем.
			tank.turret_angle = Rng.rotate_toward(tank.turret_angle, tank.angle, follow_slew)

		if Input.is_physical_key_pressed(Sets.key_for("p2_fire")):
			tank.shoot(world)
		if Input.is_physical_key_pressed(Sets.key_for("p2_mine")):
			tank.place_mine(world)
		if Input.is_physical_key_pressed(Sets.key_for("p2_dash")):
			tank.dash()
		if Input.is_physical_key_pressed(Sets.key_for("p2_ability")):
			tank.use_ability(world)

# ---------------------------------------------------------------------------
# Геймпад. Левый стик — ход, правый — наводка, спусковые крючки — огонь.
#
# Наводка стиком отличается от наводки мышью принципиально: мышь задаёт ТОЧКУ,
# а стик — НАПРАВЛЕНИЕ. Поэтому точка прицеливания строится впереди танка по
# направлению стика, а когда стик отпущен, прежний угол сохраняется — иначе
# башня прыгала бы в ноль каждый раз, когда игрок убирает большой палец.
#
# Мёртвая зона обязательна: стики почти всегда возвращают ненулевые значения
# в покое, и без неё танк медленно ползёт сам по себе.
# ---------------------------------------------------------------------------
class GamepadScheme extends RefCounted:
	## Номер устройства: 0 — первый подключённый геймпад.
	var device := 0
	## Последняя точка прицеливания в мире. Держится между кадрами.
	var aim := Vector2.ZERO
	var _aim_ready := false
	## Мир партии. Ставится игрой каждый кадр (game.gd:_process) и нужен
	## автоприцелу: список танков, проверка вражды и линия видимости.
	var world = null

	## На каком расстоянии перед танком ставится точка прицела. На попадание
	## это не влияет — башня всё равно смотрит по направлению, — но слишком
	## близкая точка делает наводку дёрганой.
	const AIM_REACH := 260.0

	# ---- автоприцел ---------------------------------------------------------
	## Мягкое притяжение к ближайшей цели, и только пока игрок целится правым
	## стиком (цель должна попасть в конус вокруг направления стика). Стик
	## отпущен — притяжения нет вовсе. Полный захват не делаем: игрок сохраняет
	## контроль и может увести прицел на другого врага.
	##
	## ASSIST_RANGE  — радиус поиска цели, px.
	## ASSIST_CONE   — половина угла конуса от направления стика, градусы:
	##                 цель вне конуса игнорируется, чтобы прицел не прыгал
	##                 к тому, на кого игрок не смотрит.
	## ASSIST_PULL   — доля пути от угла стика к точному углу на цель.
	const ASSIST_RANGE := 320.0
	const ASSIST_CONE := 35.0
	const ASSIST_PULL := 0.6

	func _init(device_: int = 0) -> void:
		device = device_

	func hints() -> Array:
		var h := [
			"[левый стик] движение",
			"[правый стик] прицел",
			"[RT] / [A] выстрел",
			"[LT] / [B] мина",
			"[LB] рывок-таран",
			"[Y] способность перка",
			"[RB] авиаудар (Оборона)",
		]
		if Sets.pad_aim_assist:
			h.append("автоприцел: доводка к ближайшему врагу")
		return h

	## Ось с мёртвой зоной. Ниже порога — ровный ноль, выше — растяжка
	## остатка на весь ход, чтобы у самого порога не было ступеньки.
	func _axis(a: JoyAxis) -> float:
		var v := Input.get_joy_axis(device, a)
		var dz: float = Sets.pad_deadzone
		if absf(v) <= dz:
			return 0.0
		return signf(v) * (absf(v) - dz) / maxf(0.001, 1.0 - dz)

	func read_command(player) -> Dictionary:
		var cmd := Ctl.empty_command()
		cmd["mx"] = _axis(JOY_AXIS_LEFT_X)
		cmd["my"] = _axis(JOY_AXIS_LEFT_Y)

		var tank = player.tank
		var ax := _axis(JOY_AXIS_RIGHT_X)
		var ay := _axis(JOY_AXIS_RIGHT_Y)
		if tank != null:
			var dir := Vector2(ax, ay)
			if dir.length() > 0.2:
				var sdir := dir.normalized()
				aim = _assist_aim(tank, sdir)
				_aim_ready = true
			elif not _aim_ready:
				# Пока игрок не трогал правый стик, целимся туда, куда едем.
				var move := Vector2(float(cmd["mx"]), float(cmd["my"]))
				var ahead := move.normalized() if move.length() > 0.2 else Vector2.RIGHT
				aim = Vector2(tank.x, tank.y) + ahead * AIM_REACH
		cmd["ax"] = aim.x
		cmd["ay"] = aim.y

		# Крючок считается нажатым с середины хода: полное нажатие требовать
		# незачем, а срабатывание от касания мешает целиться.
		var rt := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		var lt := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.5
		cmd["fire"] = rt or Input.is_joy_button_pressed(device, JOY_BUTTON_A)
		cmd["mine"] = lt or Input.is_joy_button_pressed(device, JOY_BUTTON_B)
		cmd["dash"] = Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER)
		cmd["ability"] = Input.is_joy_button_pressed(device, JOY_BUTTON_Y)
		cmd["airstrike"] = Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
		return cmd

	## Точка прицела при заданном направлении стика. Без автоприцела (или без
	## подходящей цели) — просто впереди танка по стику; с автоприцелом —
	## подкрученная на ASSIST_PULL к точному углу на ближайшего врага.
	func _assist_aim(tank, sdir: Vector2) -> Vector2:
		var base := Vector2(tank.x, tank.y) + sdir * AIM_REACH
		if not Sets.pad_aim_assist or world == null:
			return base
		var tgt = _nearest_target(tank, sdir)
		if tgt == null:
			return base
		var cur := sdir.angle()
		var want := Vector2(tgt.x - tank.x, tgt.y - tank.y).angle()
		var blended := cur + wrapf(want - cur, -PI, PI) * ASSIST_PULL
		return Vector2(tank.x, tank.y) + Vector2.from_angle(blended) * AIM_REACH

	## Ближайший видимый враг в радиусе и в конусе вокруг направления стика,
	## или null. «Ближайший» — по прямой дистанции среди прошедших отбор.
	func _nearest_target(tank, stick_dir: Vector2):
		if world == null or not ("tanks" in world):
			return null
		var cone_cos := cos(deg_to_rad(ASSIST_CONE))
		var best = null
		var best_d := ASSIST_RANGE
		for t in world.tanks:
			if t == tank or not t.alive:
				continue
			if not world.are_hostile(tank, t):
				continue
			var off := Vector2(t.x - tank.x, t.y - tank.y)
			var d := off.length()
			if d > best_d or d < 1.0:
				continue
			if off.normalized().dot(stick_dir) < cone_cos:
				continue
			if not world.map.has_line_of_sight(tank.x, tank.y, t.x, t.y):
				continue
			best_d = d
			best = t
		return best

	func apply(tank: Tank, player, world_) -> void:
		world = world_
		Ctl.apply_command(tank, world_, read_command(player))
