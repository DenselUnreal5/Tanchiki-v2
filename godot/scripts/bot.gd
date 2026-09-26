class_name BotBrain
extends RefCounted

const STATE_PATROL := "patrol"
const STATE_COMBAT := "combat"
const STATE_GO_FLAG := "goFlag"
const STATE_RETURN_FLAG := "returnFlag"
const STATE_ESCORT := "escort"
const STATE_RECOVER_FLAG := "recoverFlag"
const CTF_STATES := [STATE_GO_FLAG, STATE_RETURN_FLAG, STATE_ESCORT, STATE_RECOVER_FLAG]

var base_accuracy := 0.75
var react_time := 20
var role := "attacker"
var rng: Rng
var fire_range := Cfg.BOT_FIRE_RANGE
var keep_min := Cfg.BOT_KEEP_MIN
var keep_max := Cfg.BOT_KEEP_MAX
var lobbed := false
var survival := false

var owner_mods := {}

var state := STATE_PATROL
var target = null
var noise_x := 0.0
var noise_y := 0.0
var noise_timer := 0
var dest_x := 0.0
var dest_y := 0.0
var state_timer := 0
var react_timer := 0
var strafe_dir := 1
var strafe_timer := 0
var dodge_timer := 0
var dodge_scan_timer := 0
var path: Array = []
var path_idx := 0
var path_timer := 0
var path_goal_x := 0.0
var path_goal_y := 0.0
var stuck_timer := 0
var last_x := 0.0
var last_y := 0.0
var dash_timer := 0

var unstick_timer := 0
var unstick_angle := 0.0
var unstick_free := 0
var repath_now := false
var last_steer_off := 0.0
var waypoint_dist := INF
var waypoint_stall := 0
var path_cooldown := 0
var perception_timer := 0
var _los_cache := false
var _aim_noise := 0.0
var _aim_noise_timer := 0

const STEER_OFFSETS := [
	0.0, 0.3, -0.3, 0.6, -0.6, 0.95, -0.95, 1.35, -1.35,
	1.8, -1.8, 2.3, -2.3, 2.8, -2.8,
]

var frozen_ticks := 0
var worst_frozen := 0
var worst_frozen_info := ""

func _init(opts: Dictionary) -> void:
	base_accuracy = float(opts.get("accuracy", 0.75))
	react_time = int(opts.get("react_time", 20))
	role = String(opts.get("role", "attacker"))
	rng = opts.get("rng", Rng.new(1))
	fire_range = float(opts.get("fire_range", Cfg.BOT_FIRE_RANGE))
	keep_min = float(opts.get("keep_min", Cfg.BOT_KEEP_MIN))
	keep_max = float(opts.get("keep_max", Cfg.BOT_KEEP_MAX))
	lobbed = bool(opts.get("lobbed", false))
	survival = bool(opts.get("survival", false))
	reset()

func reset() -> void:
	state = STATE_PATROL
	target = null
	dest_x = 0.0
	dest_y = 0.0
	state_timer = 0
	react_timer = 0
	strafe_dir = 1 if rng.nextf() < 0.5 else -1
	strafe_timer = 0
	dodge_timer = 0
	path = []
	path_idx = 0
	# Нулевой таймер у всех ботов сразу означает, что все они запросят
	# первый (самый дорогой) A*-поиск в один и тот же тик — например при
	# старте матча или начале волны в Defense. Разброс по первым
	# BOT_PATH_REFRESH тикам размазывает эту нагрузку по времени.
	path_timer = int(rng.nextf() * float(Cfg.BOT_PATH_REFRESH))
	path_goal_x = 0.0
	path_goal_y = 0.0
	stuck_timer = 0
	frozen_ticks = 0
	last_x = 0.0
	last_y = 0.0
	dash_timer = 0
	unstick_timer = 0
	unstick_angle = 0.0
	unstick_free = 0
	repath_now = false
	last_steer_off = 0.0
	waypoint_dist = INF
	waypoint_stall = 0
	path_cooldown = 0
	perception_timer = 0
	_aim_noise = 0.0
	_aim_noise_timer = 0

var accuracy: float:
	get: return clampf(base_accuracy + float(owner_mods.get("accuracyBonus", 0.0)), 0.1, 0.98)

func update(tank: Tank, world) -> void:
	owner_mods = tank.mods
	rng = world.rng

	if state_timer > 0:
		state_timer -= 1
	if react_timer > 0:
		react_timer -= 1
	if dodge_timer > 0:
		dodge_timer -= 1
	if dash_timer > 0:
		dash_timer -= 1
	strafe_timer -= 1
	if strafe_timer <= 0:
		strafe_dir *= -1
		strafe_timer = 20 + int(rng.nextf() * 40.0)
	_track_stuck(tank)

	perception_timer -= 1
	if perception_timer <= 0 or target == null or not _target_valid(tank, world, target):
		target = find_best_threat(tank, world, lobbed)
		perception_timer = 3 + int(rng.nextf() * 3.0)
		_los_cache = false
		if target != null:
			_los_cache = world.map.has_line_of_sight(tank.x, tank.y, target.x, target.y)
	var tgt = target
	var target_dist := INF
	var has_shot := false
	if tgt != null:
		target_dist = Vector2(tgt.x - tank.x, tgt.y - tank.y).length()
		has_shot = true if lobbed else _los_cache

	if tank.is_rammer_boss:
		if tank.rammer_state == "telegraph" or tank.rammer_state == "charge":
			return
		if tank.rammer_state == "idle":
			if tgt != null and target_dist < 520.0:
				tank.start_rammer_charge(tgt.x, tgt.y, world)
				return
			elif world.mode == "defense" and world.base != null:
				var d_b := Vector2(world.base["x"] - tank.x, world.base["y"] - tank.y).length()
				if d_b < 480.0:
					tank.start_rammer_charge(world.base["x"], world.base["y"], world)
					return

	if tank.is_chimera_boss:
		# When cloaked, Chimera stalks into ambush position (behind/flanking the target)
		if tank.shadow_timer > 0 and tgt != null:
			var flank_angle: float = tgt.body_angle + PI
			var stalk_dist := 130.0
			var flank_x: float = tgt.x + cos(flank_angle) * stalk_dist
			var flank_y: float = tgt.y + sin(flank_angle) * stalk_dist
			_move_toward(tank, world, flank_x, flank_y)
			tank.slew_turret_to(atan2(tgt.y - tank.y, tgt.x - tank.x))
			if target_dist <= 220.0 and has_shot:
				_try_fire(tank, world, tgt, target_dist, has_shot)
			return

	_maybe_use_ability(tank, world, target_dist, has_shot)

	if dodge_timer <= 0:
		dodge_scan_timer -= 1
	if dodge_timer <= 0 and dodge_scan_timer <= 0:
		dodge_scan_timer = 1 + int(rng.nextf() * 2.0)
		var incoming = find_incoming_bullet(tank, world, Cfg.BOT_DODGE_LOOKAHEAD)
		if incoming != null:
			var bullet_angle: float = atan2(incoming.vy, incoming.vx)
			var side := 1.0 if rng.nextf() < 0.5 else -1.0
			var dodge_angle: float = bullet_angle + (PI / 2.0) * side
			_steer(tank, world, tank.x + cos(dodge_angle) * 60.0, tank.y + sin(dodge_angle) * 60.0)
			dodge_timer = 15
			_try_fire(tank, world, tgt, target_dist, has_shot)
			return

	if unstick_timer > 0:
		unstick_timer -= 1
		if Vector2(tank.vx, tank.vy).length() > 0.6:
			unstick_free += 1
			if unstick_free >= 4:
				unstick_timer = 0
		else:
			unstick_free = 0
		tank.thrust(cos(unstick_angle), sin(unstick_angle))
		_try_fire(tank, world, tgt, target_dist, has_shot)
		_track_frozen(tank, tgt, target_dist)
		return
	if stuck_timer > 24:
		unstick_free = 0
		_begin_unstick(tank, world)
		tank.thrust(cos(unstick_angle), sin(unstick_angle))
		_track_frozen(tank, tgt, target_dist)
		return

	if noise_timer > 0:
		noise_timer -= 1
		if tgt == null:
			var sound_dir := atan2(noise_y - tank.y, noise_x - tank.x)
			tank.slew_turret_to(sound_dir)
			_move_toward(tank, world, noise_x, noise_y)
			_try_fire(tank, world, tgt, target_dist, has_shot)
			_track_frozen(tank, tgt, target_dist)
			return

	_decide(tank, world, tgt, target_dist)

	if state == STATE_COMBAT:
		_do_combat(tank, world, tgt, target_dist, has_shot)
	else:
		_move_toward(tank, world, dest_x, dest_y)
		_try_fire(tank, world, tgt, target_dist, has_shot)

	_track_frozen(tank, tgt, target_dist)

func _track_frozen(tank: Tank, tgt, target_dist: float) -> void:
	var goal_far := true
	if state == STATE_COMBAT:
		goal_far = target_dist > 40.0
	else:
		goal_far = Vector2(dest_x - tank.x, dest_y - tank.y).length() > 40.0
	if goal_far and Vector2(tank.vx, tank.vy).length() < 0.15:
		frozen_ticks += 1
		if frozen_ticks > worst_frozen:
			worst_frozen = frozen_ticks
			worst_frozen_info = "%s dash=%.0f путь=%d/%d stuck=%d вода=%s" % [
				state, tank.dash_range, path_idx, path.size(), stuck_timer, str(tank.in_water)]
	else:
		frozen_ticks = 0

func _decide(tank: Tank, world, tgt, target_dist: float) -> void:
	if tank.carrying_flag:
		var home = world.home_for(tank.team)
		if home != null:
			state = STATE_RETURN_FLAG
			dest_x = home.x
			dest_y = home.y
			return

	var engage := Cfg.BOT_COMBAT_RANGE
	if world.mode == "ctf" and role != "defender" and not tank.carrying_flag:
		engage = Cfg.BOT_CTF_ENGAGE_RANGE
	var stay_range := engage * 1.3 if state == STATE_COMBAT else engage
	if tgt != null and target_dist < stay_range:
		if state != STATE_COMBAT:
			state = STATE_COMBAT
			react_timer = react_time
		return

	if world.mode == "defense" and world.base != null and tank.is_bot:
		var d_base := Vector2(world.base["x"] - tank.x, world.base["y"] - tank.y).length()
		if d_base > 30.0:
			state = STATE_PATROL
			state_timer = 60
			dest_x = world.base["x"]
			dest_y = world.base["y"]
			return

	if world.mode == "ctf":
		if state_timer > 0 and CTF_STATES.has(state):
			return
		if _decide_ctf(tank, world):
			return

	if state != STATE_PATROL or state_timer <= 0:
		state = STATE_PATROL
		state_timer = 60 + int(rng.nextf() * 120.0)
		var point := _pick_patrol_point(tank, world)
		dest_x = point.x
		dest_y = point.y

func _decide_ctf(tank: Tank, world) -> bool:
	var own_flag = null
	for f in world.flags:
		if f.team == tank.team and not f.at_home:
			own_flag = f
			break
	if own_flag != null and not own_flag.carried and (role == "defender" or rng.nextf() < 0.3):
		state = STATE_RECOVER_FLAG
		dest_x = own_flag.x
		dest_y = own_flag.y
		state_timer = 60
		return true

	var ally = null
	for t in world.tanks:
		if t.alive and t != tank and t.team == tank.team and t.carrying_flag:
			ally = t
			break
	if ally != null and (role == "defender" or rng.nextf() < 0.5):
		var a := rng.nextf() * TAU
		var radius := 60.0 + rng.nextf() * 40.0
		state = STATE_ESCORT
		dest_x = ally.x + cos(a) * radius
		dest_y = ally.y + sin(a) * radius
		state_timer = 30
		return true

	var best = null
	var best_dist := INF
	for flag in world.flags:
		if flag.team == tank.team or flag.carried:
			continue
		var d := Vector2(flag.x - tank.x, flag.y - tank.y).length()
		if d < best_dist:
			best_dist = d
			best = flag
	if best != null:
		state = STATE_GO_FLAG
		dest_x = best.x
		dest_y = best.y
		state_timer = 90
		return true

	var home = world.home_for(tank.team)
	if home != null:
		state = STATE_PATROL
		dest_x = home.x + (rng.nextf() - 0.5) * Cfg.TILE * 8.0
		dest_y = home.y + (rng.nextf() - 0.5) * Cfg.TILE * 8.0
		state_timer = 60
		return true
	return false

func _pick_patrol_point(tank: Tank, world) -> Vector2:
	var map: GameMap = world.map
	var mw := map.width
	var mh := map.height
	var options := []

	var is_ffa: bool = world.mode == "ffa"
	if is_ffa:
		if not world.shot_pings.is_empty():
			var ping: Dictionary = world.shot_pings[world.shot_pings.size() - 1]
			options.append({"x": float(ping["x"]), "y": float(ping["y"]), "spread": 4.0})
		for pl in world.players:
			if pl.tank != null and pl.tank.alive and world.are_hostile(tank, pl.tank):
				options.append({"x": pl.tank.x, "y": pl.tank.y, "spread": 6.0})

	var own = world.home_for(tank.team)
	if own != null:
		options.append({"x": own.x, "y": own.y, "spread": 6.0})
	options.append({"x": mw / 2.0, "y": mh / 2.0, "spread": 8.0})
	var hp_ratio := tank.hp / tank.max_hp if tank.max_hp > 0.0 else 1.0
	var retreat_hp := 0.55 if survival else 0.3
	if hp_ratio >= retreat_hp:
		var enemy_home = world.enemy_home_for(tank.team)
		if enemy_home != null:
			options.append({"x": enemy_home.x, "y": enemy_home.y, "spread": 8.0})
	if options.size() < 3:
		options.append({"x": rng.nextf() * mw, "y": rng.nextf() * mh, "spread": 4.0})
		options.append({"x": rng.nextf() * mw, "y": rng.nextf() * mh, "spread": 4.0})
	var pick: Dictionary = options[int(rng.nextf() * options.size()) % options.size()]

	for i in 12:
		var x := clampf(float(pick["x"]) + (rng.nextf() - 0.5) * Cfg.TILE * float(pick["spread"]), Cfg.TILE, mw - Cfg.TILE)
		var y := clampf(float(pick["y"]) + (rng.nextf() - 0.5) * Cfg.TILE * float(pick["spread"]), Cfg.TILE, mh - Cfg.TILE)
		if map.is_drivable(map.row_at(y), map.col_at(x)):
			return Vector2(x, y)
	return Vector2(clampf(float(pick["x"]), Cfg.TILE, mw - Cfg.TILE),
		clampf(float(pick["y"]), Cfg.TILE, mh - Cfg.TILE))

func _do_combat(tank: Tank, world, tgt, target_dist: float, has_shot: bool) -> void:
	if tgt == null or not tgt.alive:
		state = STATE_PATROL
		state_timer = 0
		return

	var predicted := predict_position(tank, tgt)
	var aim: float = atan2(predicted.y - tank.y, predicted.x - tank.x)
	_aim(tank, aim)
	tank.angle = aim

	if tank.dash_range > 0.0:
		_try_fire(tank, world, tgt, target_dist, has_shot)
		return

	var hp_ratio := tank.hp / tank.max_hp
	var enemies := count_nearby(world, tank, 400.0, true)
	var allies := count_nearby(world, tank, 400.0, false)
	var is_ffa: bool = world.mode == "ffa"
	var outnumbered: bool = false if is_ffa else (enemies > allies + 1)
	var retreat_hp := 0.20 if is_ffa else (0.55 if survival else 0.3)
	var back_dist := 120.0 if is_ffa else (200.0 if survival else 150.0)

	if hp_ratio < retreat_hp or outnumbered:
		var back := aim + PI
		var range_v := back_dist if hp_ratio < retreat_hp else 120.0
		_steer(tank, world, tank.x + cos(back) * range_v, tank.y + sin(back) * range_v)
	elif not has_shot:
		_move_toward(tank, world, tgt.x, tgt.y)
	elif _try_dash(tank, world, tgt, target_dist, has_shot):
		pass
	elif target_dist > keep_max:
		_move_toward(tank, world, tgt.x, tgt.y)
	elif target_dist < keep_min:
		_steer(tank, world, tank.x - cos(aim) * 120.0, tank.y - sin(aim) * 120.0)
	else:
		var strafe := aim + (PI / 2.0) * strafe_dir
		var range_v := 60.0 + rng.nextf() * 60.0
		_steer(tank, world, tank.x + cos(strafe) * range_v, tank.y + sin(strafe) * range_v)

	_try_fire(tank, world, tgt, target_dist, has_shot)

func _try_dash(tank: Tank, world, tgt, target_dist: float, has_shot: bool) -> bool:
	if tank.is_rammer_boss or tank.dash_cooldown > 0 or tank.dash_range > 0.0:
		return false
	if dash_timer > 0:
		return false
	if tgt == null or not tgt.alive or not has_shot:
		return false
	if tank.in_water:
		return false
	if target_dist < 60.0 or target_dist > 320.0:
		return false
	if survival and count_nearby(world, tank, 120.0, true) > 0:
		return false
	var probe := 34.0
	var px := tank.x + cos(tank.angle) * probe
	var py := tank.y + sin(tank.angle) * probe
	if world.map.is_blocked_rect(px, py, tank.width, tank.height):
		return false
	tank.dash()
	dash_timer = 90 + int(rng.nextf() * 60.0)
	return true

func _aim(tank: Tank, a: float) -> void:
	_aim_noise_timer -= 1
	if _aim_noise_timer <= 0:
		_aim_noise = (1.0 - accuracy) * (rng.nextf() - 0.5) * 0.35
		_aim_noise_timer = 12 + int(rng.nextf() * 10.0)
	tank.slew_turret_to(a + _aim_noise)

func hear_shot(sx: float, sy: float, shooter = null) -> void:
	var d_new := Vector2(sx - last_x, sy - last_y).length_squared()
	var d_old := Vector2(noise_x - last_x, noise_y - last_y).length_squared()
	var is_player: bool = shooter != null and shooter.is_player_controlled

	if noise_timer <= 0 or d_new < d_old or is_player:
		noise_x = sx
		noise_y = sy
		noise_timer = 100
		if target == null or not _los_cache:
			perception_timer = 0

func on_damaged(attacker) -> void:
	if attacker == null or not attacker.alive:
		return
	var should_switch := false
	if target == null or not target.alive:
		should_switch = true
	elif not _los_cache:
		should_switch = true
	elif attacker.is_player_controlled and not target.is_player_controlled:
		should_switch = true
	else:
		var d_curr := Vector2(target.x - last_x, target.y - last_y).length_squared()
		var d_att := Vector2(attacker.x - last_x, attacker.y - last_y).length_squared()
		if d_att < d_curr * 0.8:
			should_switch = true

	if should_switch:
		target = attacker
		state = STATE_COMBAT
		react_timer = mini(react_timer, maxi(2, int(react_time * 0.25)))
		perception_timer = 0
		_los_cache = true

func _maybe_use_ability(tank: Tank, world, target_dist: float, has_shot: bool) -> void:
	if tank.is_rammer_boss or tank.ability_id == "" or tank.ability_cd > 0:
		return
	match tank.ability_id:
		"shockwave":
			if target_dist < Cfg.SHOCKWAVE_R * 0.85:
				tank.use_ability(world)
		"nitro":
			var hp_ratio := tank.hp / tank.max_hp if tank.max_hp > 0.0 else 1.0
			var fleeing := hp_ratio < (0.55 if survival else 0.3)
			if fleeing or (target_dist > 260.0 and target_dist < INF):
				tank.use_ability(world)
		"boss_barrage":
			if has_shot and target_dist < 380.0:
				tank.use_ability(world)

func _try_fire(tank: Tank, world, tgt, target_dist: float, has_shot: bool) -> void:
	if tank.is_rammer_boss or tgt == null or not has_shot:
		return
	if target_dist > fire_range:
		return

	var predicted := predict_position(tank, tgt)
	var aim: float = atan2(predicted.y - tank.y, predicted.x - tank.x)
	_aim(tank, aim)

	if react_timer > 0 or not tank.can_fire:
		return

	var off := absf(atan2(sin(tank.turret_angle - aim), cos(tank.turret_angle - aim)))
	var tolerance := 0.14 + (1.0 - accuracy) * 0.25
	if off > tolerance:
		return

	if lobbed:
		tank.shoot_lobbed(world)
	else:
		tank.shoot(world)

func _move_toward(tank: Tank, world, tx: float, ty: float) -> void:
	if Vector2(tx - tank.x, ty - tank.y).length() < 56.0:
		path.clear()
		path_idx = 0
		_steer(tank, world, tx, ty)
		return

	var dgx := tx - path_goal_x
	var dgy := ty - path_goal_y
	var goal_moved := dgx * dgx + dgy * dgy > 90.0 * 90.0
	path_timer -= 1
	var need_path := (path.is_empty() and path_cooldown <= 0) or path_timer <= 0 or goal_moved or repath_now
	if path_cooldown > 0:
		path_cooldown -= 1

	# Бюджет A* на тик исчерпан другими ботами — едем по старому пути,
	# need_path останется в силе и перестроимся в одном из следующих тиков.
	if need_path and Pathfinding.has_budget(world.tick):
		path = Pathfinding.find_path(world.map, tank.x, tank.y, tx, ty)
		path_idx = 0
		path_timer = Cfg.BOT_PATH_REFRESH + int(rng.nextf() * 40.0)
		path_goal_x = tx
		path_goal_y = ty
		repath_now = false
		waypoint_dist = INF
		waypoint_stall = 0
		path_cooldown = 20 if path.is_empty() else 0
		_skip_passed_waypoints(tank)

	while path_idx < path.size():
		var wp: Vector2 = path[path_idx]
		if Vector2(tank.x - wp.x, tank.y - wp.y).length_squared() < 400.0:
			path_idx += 1
			waypoint_dist = INF
			waypoint_stall = 0
		else:
			break

	var target := Vector2(tx, ty)
	if path_idx < path.size():
		target = path[path_idx]

	var d := Vector2(tank.x - target.x, tank.y - target.y).length()
	if d < waypoint_dist - 2.0:
		waypoint_dist = d
		waypoint_stall = 0
	else:
		waypoint_stall += 1
		if waypoint_stall > 40:
			waypoint_stall = 0
			waypoint_dist = INF
			if path_idx < path.size() - 1:
				path_idx += 1
			else:
				repath_now = true

	_steer(tank, world, target.x, target.y)

func _skip_passed_waypoints(tank: Tank) -> void:
	while path_idx < path.size() - 1:
		var here: Vector2 = path[path_idx]
		var next: Vector2 = path[path_idx + 1]
		var to_here := Vector2(here.x - tank.x, here.y - tank.y)
		var to_next := Vector2(next.x - tank.x, next.y - tank.y)
		if to_next.length() < to_here.length() and to_here.dot(to_next) > 0.0:
			path_idx += 1
		else:
			break

func _steer(tank: Tank, world, tx: float, ty: float) -> bool:
	var dx := tx - tank.x
	var dy := ty - tank.y
	if dx * dx + dy * dy < 16.0:
		return true
	var desired := atan2(dy, dx)
	var map: GameMap = world.map
	var probe := clampf(tank.speed * 12.0, 16.0, 34.0)

	if _free_run(map, tank, desired, probe) >= probe:
		if not (survival and map.is_water_at(tank.x + cos(desired) * probe, tank.y + sin(desired) * probe)):
			last_steer_off = 0.0
			tank.thrust(cos(desired), sin(desired))
			return true

	var best_angle := 0.0
	var best_score := -INF
	for off in STEER_OFFSETS:
		var a: float = desired + off
		var clear := _free_run(map, tank, a, probe)
		if clear <= 0.0:
			continue
		var score: float = clear * 2.0 - absf(off) * 12.0
		if off != 0.0 and signf(off) == signf(last_steer_off) and last_steer_off != 0.0:
			score += 6.0
		if survival:
			var px := tank.x + cos(a) * probe
			var py := tank.y + sin(a) * probe
			if map.is_water_at(px, py):
				score -= 60.0
		if score > best_score:
			best_score = score
			best_angle = a
			last_steer_off = off

	if best_score > -INF:
		tank.thrust(cos(best_angle), sin(best_angle))
		return true

	tank.thrust(-cos(desired), -sin(desired))
	return false

func _free_run(map: GameMap, tank: Tank, a: float, max_dist: float, steps: int = 2) -> float:
	var step := max_dist / float(steps)
	var dist := 0.0
	for i in steps:
		dist += step
		var px := tank.x + cos(a) * dist
		var py := tank.y + sin(a) * dist
		if map.is_blocked_rect(px, py, tank.width, tank.height):
			return dist - step
	return max_dist

func _begin_unstick(tank: Tank, world) -> void:
	var map: GameMap = world.map
	var goal := Vector2(dest_x - tank.x, dest_y - tank.y)
	var goal_angle := atan2(goal.y, goal.x) if goal.length_squared() > 1.0 else tank.angle

	var best_angle := goal_angle + PI
	var best_score := -INF
	for i in 16:
		var a := TAU * float(i) / 16.0
		var clear := _free_run(map, tank, a, 70.0, 4)
		var score := clear - absf(Rng.angle_delta(a, goal_angle)) * 6.0
		if survival and map.is_water_at(tank.x + cos(a) * 40.0, tank.y + sin(a) * 40.0):
			score -= 80.0
		if score > best_score:
			best_score = score
			best_angle = a

	unstick_angle = best_angle
	unstick_timer = 22 + int(rng.nextf() * 16.0)
	stuck_timer = 0
	repath_now = true
	path_timer = 0

func _track_stuck(tank: Tank) -> void:
	var dx := tank.x - last_x
	var dy := tank.y - last_y
	if dx * dx + dy * dy < 0.35:
		stuck_timer += 1
	else:
		stuck_timer = 0
	last_x = tank.x
	last_y = tank.y


func _target_valid(tank: Tank, world, t) -> bool:
	if t == null or not t.alive or not world.are_hostile(tank, t):
		return false
	if t.shadow_timer > 0:
		return false
	var dx: float = t.x - tank.x
	var dy: float = t.y - tank.y
	var d2 := dx * dx + dy * dy
	if t.ability_active("smoke") and d2 > Cfg.SMOKE_VISION * Cfg.SMOKE_VISION:
		return false
	var sight := sight_range(world)
	return d2 <= sight * sight

const THREAT_CANDIDATES := 9

static func sight_range(world) -> float:
	if world == null or world.weather == null:
		return Cfg.BOT_SIGHT
	return Cfg.BOT_SIGHT * world.weather.vision_scale

static func find_best_threat(tank: Tank, world, lobbed: bool = false):
	var sight := sight_range(world)
	var sight2 := sight * sight
	var is_ffa: bool = world.mode == "ffa"

	var best = null
	var best_score := -INF

	var fallback_threat = null
	var fallback_dist2 := INF

	for other in world.tank_grid.query(tank.x, tank.y, sight):
		if other == tank or not other.alive:
			continue
		if not world.are_hostile(tank, other):
			continue
		if other.shadow_timer > 0:
			continue
		var dx: float = other.x - tank.x
		var dy: float = other.y - tank.y
		var d2 := dx * dx + dy * dy
		if d2 > sight2:
			continue
		if other.ability_active("smoke") and d2 > Cfg.SMOKE_VISION * Cfg.SMOKE_VISION:
			continue

		var has_los: bool = lobbed or world.map.has_line_of_sight(tank.x, tank.y, other.x, other.y)
		if has_los:
			var d := sqrt(d2)
			var score := (sight - d) / sight
			score += (1.0 - other.hp / other.max_hp) * 0.6
			if other.carrying_flag and other.team != tank.team:
				score += 1.5

			# В FFA режиме игрок — главный фокус интереса для ботов
			if other.is_player_controlled:
				score += 1.4 if is_ffa else 0.5
				if d < Cfg.BOT_COMBAT_RANGE:
					score += 0.8

			# Если эта цель недавно нанесла нам урон — возмездие
			if other == tank.last_attacker:
				score += 1.2

			if score > best_score:
				best_score = score
				best = other
		else:
			# Нет прямой видимости: кандидат для сближения, если видимых врагов рядом нет
			var f_dist2 := d2
			if other.is_player_controlled:
				f_dist2 *= 0.4
			if other == tank.last_attacker:
				f_dist2 *= 0.5
			if f_dist2 < fallback_dist2:
				fallback_dist2 = f_dist2
				fallback_threat = other

	if best != null:
		return best

	if fallback_threat != null and is_ffa:
		return fallback_threat

	return null

const INCOMING_BULLET_MAX_RANGE := 600.0

static func find_incoming_bullet(tank: Tank, world, radius: float):
	var best = null
	var best_t := INF
	var reject_r: float = radius + INCOMING_BULLET_MAX_RANGE
	var reject_r2: float = reject_r * reject_r
	for b in world.bullet_grid.query(tank.x, tank.y, reject_r):
		if not b.alive:
			continue
		if not world.are_hostile(b.owner, tank):
			continue
		var dx: float = tank.x - b.x
		var dy: float = tank.y - b.y
		if dx * dx + dy * dy > reject_r2:
			continue
		var speed2: float = b.vx * b.vx + b.vy * b.vy
		if speed2 == 0.0:
			continue
		var t: float = (dx * b.vx + dy * b.vy) / speed2
		if t < 0.0 or t > 40.0:
			continue
		var closest_x: float = b.x + b.vx * t
		var closest_y: float = b.y + b.vy * t
		if Vector2(closest_x - tank.x, closest_y - tank.y).length() > radius:
			continue
		if t < best_t:
			best_t = t
			best = b
	return best

static func count_nearby(world, tank: Tank, radius: float, hostile: bool) -> int:
	var r2 := radius * radius
	var n := 0
	for other in world.tank_grid.query(tank.x, tank.y, radius):
		if other == tank or not other.alive:
			continue
		if world.are_hostile(tank, other) != hostile:
			continue
		var dx: float = other.x - tank.x
		var dy: float = other.y - tank.y
		if dx * dx + dy * dy <= r2:
			n += 1
	return n

static func predict_position(shooter: Tank, target) -> Vector2:
	var d := Vector2(target.x - shooter.x, target.y - shooter.y).length()
	var flight_ticks := d / Cfg.BULLET_SPEED
	var horizon := minf(flight_ticks, 40.0)
	return Vector2(target.x + target.vx * horizon, target.y + target.vy * horizon)
