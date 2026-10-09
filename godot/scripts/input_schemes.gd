class_name Ctl
extends RefCounted

const DEFAULT_KEYS := {
	"p1_up": KEY_W, "p1_down": KEY_S, "p1_left": KEY_A, "p1_right": KEY_D,
	"p1_fire": KEY_SPACE, "p1_mine": KEY_E, "p1_dash": KEY_SHIFT,
	"p1_airstrike": KEY_F, "p1_ability": KEY_Q,
	"p2_up": KEY_UP, "p2_down": KEY_DOWN, "p2_left": KEY_LEFT, "p2_right": KEY_RIGHT,
	"p2_turret_left": KEY_COMMA, "p2_turret_right": KEY_PERIOD,
	"p2_fire": KEY_SLASH, "p2_mine": KEY_DELETE,
	"p2_dash": KEY_KP_ADD, "p2_ability": KEY_KP_SUBTRACT,
}

static func key_name(action: String) -> String:
	var code := Sets.key_for(action)
	if code <= 0:
		return "?"
	return OS.get_keycode_string(code)

static func empty_command() -> Dictionary:
	return {"mx": 0.0, "my": 0.0, "ax": 0.0, "ay": 0.0,
		"fire": false, "mine": false, "dash": false, "airstrike": false,
		"ability": false}

static func apply_command(tank: Tank, world, cmd: Dictionary) -> void:
	if tank == null or not tank.alive or cmd.is_empty():
		return

	# 1. Приоритет спасения и выживания (Dash / Shield & Escape Ability)
	if bool(cmd.get("dash", false)):
		tank.dash(Vector2(float(cmd.get("mx", 0.0)), float(cmd.get("my", 0.0))))
	if bool(cmd.get("ability", false)):
		tank.use_ability(world)

	# 2. Тактический приоритет (Авиаудар, Мины)
	if bool(cmd.get("airstrike", false)):
		world.trigger_airstrike(tank.owner)
	if bool(cmd.get("mine", false)):
		tank.place_mine(world)

	# 3. Боевой приоритет (Стрельба)
	if bool(cmd.get("fire", false)):
		tank.shoot(world)

	# 4. Локомоция (Движение и прицеливание)
	tank.thrust(float(cmd.get("mx", 0.0)), float(cmd.get("my", 0.0)))
	tank.aim_at(float(cmd.get("ax", 0.0)), float(cmd.get("ay", 0.0)))

static func is_key_down(key: int) -> bool:
	if key <= 0:
		return false
	if Input.is_physical_key_pressed(key) or Input.is_key_pressed(key):
		return true
	# Поддержка русской раскладки клавиатуры (ЙЦУКЕН / Cyrillic keycodes)
	match key:
		KEY_Q:
			return Input.is_key_pressed(1049) or Input.is_key_pressed(1081) or Input.is_physical_key_pressed(1049) or Input.is_physical_key_pressed(1081)
		KEY_W:
			return Input.is_key_pressed(1062) or Input.is_key_pressed(1094) or Input.is_physical_key_pressed(1062) or Input.is_physical_key_pressed(1094)
		KEY_E:
			return Input.is_key_pressed(1059) or Input.is_key_pressed(1091) or Input.is_physical_key_pressed(1059) or Input.is_physical_key_pressed(1091)
		KEY_R:
			return Input.is_key_pressed(1050) or Input.is_key_pressed(1082) or Input.is_physical_key_pressed(1050) or Input.is_physical_key_pressed(1082)
		KEY_A:
			return Input.is_key_pressed(1060) or Input.is_key_pressed(1092) or Input.is_physical_key_pressed(1060) or Input.is_physical_key_pressed(1092)
		KEY_S:
			return Input.is_key_pressed(1067) or Input.is_key_pressed(1099) or Input.is_physical_key_pressed(1067) or Input.is_physical_key_pressed(1099)
		KEY_D:
			return Input.is_key_pressed(1042) or Input.is_key_pressed(1074) or Input.is_physical_key_pressed(1042) or Input.is_physical_key_pressed(1074)
		KEY_F:
			return Input.is_key_pressed(1040) or Input.is_key_pressed(1072) or Input.is_physical_key_pressed(1040) or Input.is_physical_key_pressed(1072)
		1049, 1081:
			return Input.is_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_Q)
		1059, 1091:
			return Input.is_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_E)
		1062, 1094:
			return Input.is_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_W)
		1060, 1092:
			return Input.is_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_A)
		1067, 1099:
			return Input.is_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_S)
		1042, 1074:
			return Input.is_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_D)
	return false

static func vibrate(player, weak_magnitude: float, strong_magnitude: float, duration: float) -> void:
	if player == null or not Sets.pad_vibration or player.scheme == null:
		return
	if "device" in player.scheme:
		Input.start_joy_vibration(int(player.scheme.device), weak_magnitude, strong_magnitude, duration)

class MouseAimScheme extends RefCounted:
	var allow_arrows := true
	var mouse := Vector2.ZERO

	func _init(allow_arrows_: bool = true) -> void:
		allow_arrows = allow_arrows_

	func hints() -> Array:
		return [
			"[%s][%s][%s][%s] %s" % [Ctl.key_name("p1_up"), Ctl.key_name("p1_left"),
				Ctl.key_name("p1_down"), Ctl.key_name("p1_right"), I18n.t("hint.move", {}, "движение")],
			"[%s] %s" % [I18n.t("hint.mouse", {}, "мышь"), I18n.t("hint.aim", {}, "прицел")],
			"[%s] / [%s] %s" % [I18n.t("hint.lmb", {}, "ЛКМ"), Ctl.key_name("p1_fire"),
				I18n.t("hint.fire", {}, "выстрел")],
			"[%s] / [%s] %s" % [Ctl.key_name("p1_mine"), I18n.t("hint.rmb", {}, "ПКМ"),
				I18n.t("hint.mine", {}, "мина")],
			"[%s] %s" % [Ctl.key_name("p1_dash"), I18n.t("hint.dash", {}, "рывок-таран")],
			"[%s] %s" % [Ctl.key_name("p1_ability"), I18n.t("hint.ability", {}, "способность перка")],
			"[%s] %s" % [Ctl.key_name("p1_airstrike"), I18n.t("hint.airstrike", {}, "авиаудар (Оборона)")],
		]

	func read_command(player) -> Dictionary:
		var cmd := Ctl.empty_command()
		var mx := 0.0
		var my := 0.0
		if Ctl.is_key_down(Sets.key_for("p1_up")) or (allow_arrows and (Input.is_physical_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_UP))):
			my -= 1.0
		if Ctl.is_key_down(Sets.key_for("p1_down")) or (allow_arrows and (Input.is_physical_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_DOWN))):
			my += 1.0
		if Ctl.is_key_down(Sets.key_for("p1_left")) or (allow_arrows and (Input.is_physical_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_LEFT))):
			mx -= 1.0
		if Ctl.is_key_down(Sets.key_for("p1_right")) or (allow_arrows and (Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_RIGHT))):
			mx += 1.0

		var w: Vector2 = player.screen_to_world(mouse.x, mouse.y)
		cmd["mx"] = mx
		cmd["my"] = my
		cmd["ax"] = w.x
		cmd["ay"] = w.y
		cmd["fire"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Ctl.is_key_down(Sets.key_for("p1_fire"))
		cmd["mine"] = Ctl.is_key_down(Sets.key_for("p1_mine")) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		cmd["dash"] = Ctl.is_key_down(Sets.key_for("p1_dash"))
		cmd["airstrike"] = Ctl.is_key_down(Sets.key_for("p1_airstrike"))
		cmd["ability"] = Ctl.is_key_down(Sets.key_for("p1_ability")) or Ctl.is_key_down(KEY_Q)
		return cmd

	func apply(tank: Tank, player, world) -> void:
		Ctl.apply_command(tank, world, read_command(player))

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

class KeyboardAimScheme extends RefCounted:
	var turret_slew := 0.07
	var follow_slew := 0.05
	var _debug_printed_keys := false
	var _debug_last_state := ""

	func hints() -> Array:
		return [
			"[%s][%s][%s][%s] %s" % [Ctl.key_name("p2_up"), Ctl.key_name("p2_left"),
				Ctl.key_name("p2_down"), Ctl.key_name("p2_right"), I18n.t("hint.move", {}, "движение")],
			"[%s][%s] %s" % [Ctl.key_name("p2_turret_left"), Ctl.key_name("p2_turret_right"),
				I18n.t("hint.turret", {}, "поворот башни")],
			"[%s] %s" % [Ctl.key_name("p2_fire"), I18n.t("hint.fire", {}, "выстрел")],
			"[%s] %s" % [Ctl.key_name("p2_mine"), I18n.t("hint.mine", {}, "мина")],
			"[%s] %s" % [Ctl.key_name("p2_dash"), I18n.t("hint.dash", {}, "рывок-таран")],
			"[%s] %s" % [Ctl.key_name("p2_ability"), I18n.t("hint.ability", {}, "способность перка")],
		]

	func apply(tank: Tank, player, world) -> void:
		if not _debug_printed_keys:
			_debug_printed_keys = true
			print("[P2-DEBUG] коды клавиш: up=%d down=%d left=%d right=%d turret_left=%d turret_right=%d fire=%d mine=%d dash=%d ability=%d" % [
				Sets.key_for("p2_up"), Sets.key_for("p2_down"), Sets.key_for("p2_left"), Sets.key_for("p2_right"),
				Sets.key_for("p2_turret_left"), Sets.key_for("p2_turret_right"), Sets.key_for("p2_fire"),
				Sets.key_for("p2_mine"), Sets.key_for("p2_dash"), Sets.key_for("p2_ability")])

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
		var firing := Input.is_physical_key_pressed(Sets.key_for("p2_fire"))

		if dx != 0.0 or dy != 0.0 or rot_left or rot_right or firing:
			var state := "dx=%.1f dy=%.1f rot_l=%s rot_r=%s fire=%s | vx=%.1f vy=%.1f" % [
				dx, dy, rot_left, rot_right, firing, tank.vx, tank.vy]
			if state != _debug_last_state:
				_debug_last_state = state
				print("[P2-DEBUG] ", state)
		elif _debug_last_state != "":
			_debug_last_state = ""

		if rot_left and not rot_right:
			tank.turret_angle -= turret_slew
		elif rot_right and not rot_left:
			tank.turret_angle += turret_slew
		elif moving and not firing:
			tank.turret_angle = Rng.rotate_toward(tank.turret_angle, tank.angle, follow_slew)

		# 1. Приоритет спасения и выживания
		if Ctl.is_key_down(Sets.key_for("p2_dash")) or Input.is_physical_key_pressed(KEY_KP_ADD):
			tank.dash(Vector2(dx, dy))
		if Ctl.is_key_down(Sets.key_for("p2_ability")) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT):
			tank.use_ability(world)
		# 2. Тактический приоритет
		if Ctl.is_key_down(Sets.key_for("p2_mine")) or Input.is_physical_key_pressed(KEY_DELETE):
			tank.place_mine(world)
		# 3. Боевой приоритет
		if firing:
			tank.shoot(world)

class TouchScheme extends RefCounted:
	var move := Vector2.ZERO
	var aim := Vector2.ZERO
	var mine := false
	var dash := false
	var ability := false
	var airstrike := false
	var _facing := Vector2.RIGHT
	var world = null

	const AIM_REACH := 260.0
	const STICK_DEADZONE := 0.18
	const FIRE_THRESHOLD := 0.55

	func hints() -> Array:
		return [
			I18n.t("hint.touch.move", {}, "левый экран: двигать пальцем — движение"),
			I18n.t("hint.touch.aim", {}, "правый экран: двигать пальцем — прицел, сильнее — огонь"),
			I18n.t("hint.touch.buttons", {}, "кнопки справа: рывок, мина, способность, авиаудар"),
		]

	func release_all() -> void:
		move = Vector2.ZERO
		aim = Vector2.ZERO
		mine = false
		dash = false
		ability = false
		airstrike = false

	func read_command(player) -> Dictionary:
		var cmd := Ctl.empty_command()
		var m := move if move.length() > STICK_DEADZONE else Vector2.ZERO
		cmd["mx"] = m.x
		cmd["my"] = m.y
		if aim.length() > STICK_DEADZONE:
			_facing = aim.normalized()
		elif m != Vector2.ZERO:
			_facing = m.normalized()
		var tank = player.tank
		if tank != null:
			cmd["ax"] = tank.x + _facing.x * AIM_REACH
			cmd["ay"] = tank.y + _facing.y * AIM_REACH
		cmd["fire"] = aim.length() >= FIRE_THRESHOLD
		cmd["mine"] = mine
		cmd["dash"] = dash
		cmd["ability"] = ability
		cmd["airstrike"] = airstrike
		return cmd

	func apply(tank: Tank, player, world_) -> void:
		world = world_
		Ctl.apply_command(tank, world_, read_command(player))

class GamepadScheme extends RefCounted:
	var device := 0
	var aim := Vector2.ZERO
	var _aim_ready := false
	var _move_aim_set := false
	var locked_target = null
	var _r3_prev := false
	var world = null

	const AIM_REACH := 260.0

	const ASSIST_RANGE := 320.0
	const ASSIST_CONE := 35.0
	const ASSIST_PULL := 0.6

	const LOCK_RANGE := 600.0
	const LOCK_BREAK_RANGE := 800.0

	func _init(device_: int = 0) -> void:
		device = device_

	func hints() -> Array:
		var h := [
			"[%s] %s" % [I18n.t("hint.pad.lstick", {}, "левый стик"), I18n.t("hint.move", {}, "движение")],
			"[%s] %s" % [I18n.t("hint.pad.rstick", {}, "правый стик"), I18n.t("hint.aim", {}, "прицел")],
			"[RT] / [A] " + I18n.t("hint.fire", {}, "выстрел"),
			"[LT] / [B] " + I18n.t("hint.mine", {}, "мина"),
			"[LB] " + I18n.t("hint.dash", {}, "рывок-таран"),
			"[Y] " + I18n.t("hint.ability", {}, "способность перка"),
			"[RB] " + I18n.t("hint.airstrike", {}, "авиаудар (Оборона)"),
			"[R3] " + I18n.t("hint.pad.lock", {}, "жёсткий лок на ближайшую цель"),
		]
		if Sets.pad_aim_assist:
			h.append(I18n.t("hint.pad.assist", {}, "автоприцел: доводка к ближайшему врагу"))
		return h

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
		var rt := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		var lt := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.5
		var firing := rt or Input.is_joy_button_pressed(device, JOY_BUTTON_A)

		var r3 := Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK)
		var r3_pressed := r3 and not _r3_prev
		_r3_prev = r3
		if tank != null and r3_pressed:
			var tgt = _find_lock_target(tank)
			if tgt != null:
				locked_target = tgt
		if locked_target != null:
			if not is_instance_valid(locked_target) or not locked_target.alive:
				release_lock()
			elif tank != null and Vector2(locked_target.x - tank.x, locked_target.y - tank.y).length() > LOCK_BREAK_RANGE:
				release_lock()

		var ax := _axis(JOY_AXIS_RIGHT_X)
		var ay := _axis(JOY_AXIS_RIGHT_Y)
		if tank != null and locked_target != null:
			aim = Vector2(locked_target.x, locked_target.y)
			_aim_ready = true
		elif tank != null:
			var dir := Vector2(ax, ay)
			if dir.length() > 0.2:
				var sdir := dir.normalized()
				aim = _assist_aim(tank, sdir)
				_aim_ready = true
			elif not _aim_ready and (not firing or not _move_aim_set):
				var move := Vector2(float(cmd["mx"]), float(cmd["my"]))
				var ahead := move.normalized() if move.length() > 0.2 else Vector2.RIGHT
				aim = Vector2(tank.x, tank.y) + ahead * AIM_REACH
				_move_aim_set = true
		cmd["ax"] = aim.x
		cmd["ay"] = aim.y

		cmd["fire"] = firing
		cmd["mine"] = lt or Input.is_joy_button_pressed(device, JOY_BUTTON_B)
		cmd["dash"] = Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER)
		cmd["ability"] = Input.is_joy_button_pressed(device, JOY_BUTTON_Y)
		cmd["airstrike"] = Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
		return cmd

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

	func _find_lock_target(tank):
		if world == null or not ("tanks" in world):
			return null
		var best = null
		var best_d := LOCK_RANGE
		for t in world.tanks:
			if t == tank or not t.alive:
				continue
			if not world.are_hostile(tank, t):
				continue
			var d := Vector2(t.x - tank.x, t.y - tank.y).length()
			if d > best_d:
				continue
			if not world.map.has_line_of_sight(tank.x, tank.y, t.x, t.y):
				continue
			best_d = d
			best = t
		return best

	func release_lock() -> void:
		locked_target = null
		_aim_ready = false

	func apply(tank: Tank, player, world_) -> void:
		world = world_
		Ctl.apply_command(tank, world_, read_command(player))
