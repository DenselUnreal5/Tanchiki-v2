class_name Tank
extends RefCounted

const ENVIRONMENTAL := ["water", "lightning"]

# CC Priority Levels (Иерархия контроля и боевых состояний):
# 5: CC_DEAD      - Смерть (alive == false)
# 4: CC_STASIS    - Абсолютный стазис / Заморозка (freeze_ticks > 0)
# 3: CC_STUN      - Жесткий контроль / Оглушение (stun_ticks > 0, rammer_daze_ticks > 0)
# 2: CC_FORCED    - Вынужденные спец-действия (dash_range > 0, разгон таранщика, вихрь)
# 1: CC_SOFT      - Мягкие модификаторы (кислота, вода, зыбучие пески, перегрев)
# 0: CC_BASE      - Базовое управление
const CC_NONE := 0
const CC_SOFT := 1
const CC_FORCED := 2
const CC_STUN := 3
const CC_STASIS := 4
const CC_DEAD := 5

const INPUT_BUFFER_WINDOW := 10 # ~166 мс предввода при 60 тиках/сек

const BOT_TURRET_SLEW := 0.12
const BODY_TURN_RATE := 0.15

static var _next_id := 1

var id: int
var x: float
var y: float
var vx := 0.0
var vy := 0.0
var spawn_x: float
var spawn_y: float

var team: String
var name: String
var owner
var is_bot: bool
var color_key: String

var width := Cfg.TANK_W
var height := Cfg.TANK_H
var chassis_id := "standard"
var net_id := 0
var owner_peer := 0
var col_w := Cfg.TANK_W
var col_h := Cfg.TANK_H
var hit_r := Cfg.TANK_HIT_R
var muzzle_len := 18.0

var base_max_hp: float
var base_speed: float
var base_fire_rate: int

var upgrade_mods := {}
var cosmetics := {}
var dmg_scale := 1.0
var enemy_type := {}

var angle: float
var body_angle: float
var turret_angle: float

var perk_ids: Array = []
var mods := {}
var flags := {}

var max_hp: float
var hp: float
var speed: float
var fire_rate: int

var alive := true
var fire_cooldown := 0
var heat := 0.0
var overheated := false
var shots_fired := 0
var overheats := 0
var spawn_protect := Cfg.SPAWN_PROTECT
var respawn_timer := 0

var shield_hp := 0.0
var shield_cooldown := 0
var regen_accum := 0.0
var mine_cooldown := 0
var turbo_timer := 0
var shadow_timer := 0
var ability_id := ""
var ability_cd := 0
var ability_timer := 0
var dash_range := 0.0
var dash_cooldown := 0
var dash_stall := 0
var dash_dir := Vector2.ZERO
var dash_invuln_ticks := 0
var stun_ticks := 0

# Буферизация действий игрока (Input Buffer)
var buffer_fire_ticks := 0
var buffer_dash_ticks := 0
var buffer_dash_dir := Vector2.ZERO
var buffer_ability_ticks := 0

var is_boss := false
var boss_phase := 1
var enrage_speed_mult := 1.0
var enrage_fire_rate_mult := 1.0
var enrage_shield_ticks := 0
var boss_stat_mult := 1.0
var telegraph_ticks := 0
var telegraph_kind := ""
var sniper_laser_ticks := 0
var vampire_heal_window_tick := 0
var vampire_heal_this_sec := 0.0

var is_rammer_boss := false
var rammer_state := "idle"
var rammer_telegraph_ticks := 0
var rammer_charge_ticks := 0
var rammer_cooldown_ticks := 0
var rammer_dir := 0.0
var rammer_mine_timer := 0
var rammer_charge_mine_timer := 0
var rammer_base_damage_dealt := 0.0
var rammer_charge_hit: Array = []
var rammer_daze_ticks := 0
var rammer_spin_ticks := 0
var rammer_spin_cooldown := 0
var rammer_spin_mine_timer := 0
var rammer_spin_angle := 0.0
var rammer_spin_hit: Array = []

var is_chimera_boss := false
var is_chimera_clone := false
var chimera_clone_parent = null
var chimera_cloak_timer := 0
var chimera_pool_timer := 0
var chimera_clones_spawned := false
var chimera_ambush_ready := false
var chimera_stream_active := false
var chimera_stream_timer := 0
var chimera_stream_cd := 0
var chimera_stream_warmup_ticks := 0
var chimera_stream_target_point := Vector2.ZERO
var chimera_stream_overdrive := false
var boss_damage_grace_ticks := 0
var acid_stream_hit_accum := 0.0

var in_water := false
var water_timer := 0
var quicksand_timer := 0
var surface_speed := 1.0
var surface := {}
var _tread_timer := 0

var weapon := ""
var weapon_timer := 0

var cannon_id := "standard"

var freeze_ticks := 0
var cryo_immunity_ticks := 0
var director_hp_applied := 1.0
var director_speed_applied := 1.0
var director_acc_applied := 0.0
var director_react_applied := 1.0
var freeze_max_ticks := 240
var acid_stacks := 0
var acid_ticks_left := 0
var acid_tick_timer := 0
var acid_dmg_scale := 1.0
var acid_attacker = null

var sky_strike_cooldown := 0
var sky_strike_ready := false

var flag = null
var brain = null

var kills := 0
var deaths := 0
var damage_dealt := 0.0

var blocked_ticks := 0
var stall_ticks := 0
var worst_stall := 0
var wants_move := false

var last_attacker = null
var last_attacker_tick := -1000000

func _init(opts: Dictionary) -> void:
	id = _next_id
	_next_id += 1
	x = float(opts["x"])
	y = float(opts["y"])
	spawn_x = x
	spawn_y = y

	team = String(opts["team"])
	name = String(opts["name"])
	owner = opts.get("owner", null)
	is_bot = owner == null
	color_key = String(opts.get("color_key", "enemy"))
	chassis_id = String(opts.get("chassis", "standard"))
	net_id = int(opts.get("net_id", 0))
	owner_peer = int(opts.get("owner_peer", 0))
	var shape := TankArt.chassis(chassis_id)
	width = float(shape["w"])
	height = float(shape["h"])
	hit_r = TankArt.hit_radius(width, height)
	muzzle_len = TankArt.muzzle_len(shape)
	col_w = minf(width, TankArt.MAX_COLLIDE_W)
	col_h = minf(height, TankArt.MAX_COLLIDE_H)

	base_max_hp = float(opts["max_hp"])
	base_speed = float(opts["speed"])
	base_fire_rate = int(opts["fire_rate"])

	upgrade_mods = opts.get("upgrade_mods", {})
	cosmetics = opts.get("cosmetics", {})
	dmg_scale = float(opts.get("dmg_scale", 1.0))
	cannon_id = String(opts.get("cannon_id", "standard"))

	angle = -PI / 2.0 if owner != null else PI / 2.0
	body_angle = angle
	turret_angle = angle

	perk_ids = owner.perk_ids if owner != null else []
	mods = Perks.base_modifiers()
	flags = {}

	max_hp = base_max_hp
	hp = base_max_hp
	speed = base_speed
	fire_rate = base_fire_rate

	recompute()
	hp = max_hp

func set_chassis(id: String) -> void:
	chassis_id = id
	var shape := TankArt.chassis(chassis_id)
	width = float(shape["w"])
	height = float(shape["h"])
	hit_r = TankArt.hit_radius(width, height)
	muzzle_len = TankArt.muzzle_len(shape)
	col_w = minf(width, TankArt.MAX_COLLIDE_W)
	col_h = minf(height, TankArt.MAX_COLLIDE_H)

var is_player_controlled: bool:
	get: return owner != null

var carrying_flag: bool:
	get: return flag != null

var can_fire: bool:
	get: return alive and freeze_ticks <= 0 and stun_ticks <= 0 and rammer_daze_ticks <= 0 and fire_cooldown <= 0 and not overheated and not is_rammer_boss and not is_chimera_boss and not is_chimera_clone

func get_cc_level() -> int:
	if not alive:
		return CC_DEAD
	if freeze_ticks > 0:
		return CC_STASIS
	if stun_ticks > 0 or rammer_daze_ticks > 0:
		return CC_STUN
	if dash_range > 0.0 or (is_rammer_boss and (rammer_state == "charge" or rammer_state == "spin")):
		return CC_FORCED
	if acid_stacks > 0 or in_water or quicksand_timer > 0 or overheated:
		return CC_SOFT
	return CC_NONE

func can_act(max_cc_allowed: int = CC_SOFT) -> bool:
	return get_cc_level() <= max_cc_allowed

func interrupt_current_action(target_cc_level: int) -> void:
	if target_cc_level >= CC_STUN:
		dash_range = 0.0
		dash_stall = 0
		if is_rammer_boss:
			rammer_state = "idle"
			rammer_telegraph_ticks = 0
			rammer_charge_ticks = 0
			rammer_spin_ticks = 0
			rammer_charge_hit.clear()
			rammer_spin_hit.clear()
		if is_chimera_boss or is_chimera_clone:
			chimera_stream_active = false
			chimera_stream_warmup_ticks = 0
			chimera_stream_timer = 0
	if target_cc_level >= CC_STASIS:
		vx = 0.0
		vy = 0.0
		if is_rammer_boss:
			rammer_daze_ticks = Cfg.RAMMER_DAZE_TICKS
	if target_cc_level >= CC_DEAD:
		vx = 0.0
		vy = 0.0
		heat = 0.0
		overheated = false
		turbo_timer = 0
		shadow_timer = 0
		ability_timer = 0
		dash_invuln_ticks = 0
		buffer_fire_ticks = 0
		buffer_dash_ticks = 0
		buffer_ability_ticks = 0

func _update_heat(world) -> void:
	if owner == null:
		return
	if heat > 0.0:
		heat = maxf(0.0, heat - Cfg.HEAT_COOL * float(mods["heatCoolMult"]))
	if overheated:
		if world != null and world.particles != null and world.tick % 5 == 0:
			var a := turret_angle
			world.particles.spawn(
				x + cos(a) * muzzle_len, y + sin(a) * muzzle_len,
				Color(0.85, 0.85, 0.88, 0.8), 2.0, 14.0, world.rng,
				cos(a) * 0.2 - 0.1, sin(a) * 0.2 - 0.35)
		if heat <= Cfg.HEAT_RESUME + float(mods["heatResumeAdd"]):
			overheated = false

func _after_shot() -> void:
	shots_fired += 1
	if owner == null:
		return
	var heat_mult := 1.0
	if weapon != "":
		heat_mult = float(Weapons.get_weapon(weapon).get("heat_mult", 1.0))
	elif cannon_id != "" and cannon_id != "standard":
		heat_mult = float(Cannons.get_cannon(cannon_id).get("heat_mult", 1.0))
		if cannon_id == "ice":
			heat_mult *= float(mods["iceHeatMult"])
	var gain: float = Cfg.HEAT_PER_SHOT * float(mods["heatPerShotMult"]) * heat_mult
	if ability_active("overclock"):
		gain = 0.0
	heat = minf(1.0, heat + gain)
	if heat >= 1.0 and not overheated:
		overheated = true
		overheats += 1
		Sfx.play("steam", x, y)

func reload_ticks() -> int:
	if ability_active("overdrive") or ability_active("overclock"):
		return maxi(3, int(round(float(fire_rate) * Cfg.OVERDRIVE_RELOAD_MULT)))
	return fire_rate

func _apply_upgrade_mods(src: Dictionary) -> Dictionary:
	var out := src.duplicate()
	for key in upgrade_mods.keys():
		var value := float(upgrade_mods[key])
		if value == 0.0:
			continue
		if key == "regenPerMinute":
			out[key] = float(out.get(key, 0.0)) + value
		else:
			out[key] = float(out.get(key, 1.0)) * value
	return out

func recompute() -> void:
	var hp_ratio := hp / max_hp if max_hp > 0.0 else 1.0
	mods = Perks.compute_modifiers(perk_ids, is_bot)
	flags = Perks.compute_flags(perk_ids, is_bot)
	var next_ability := Perks.active_ability_of(perk_ids, is_bot)
	if next_ability != "":
		if next_ability != ability_id:
			ability_timer = 0
			ability_id = next_ability
	elif perk_ids.is_empty() and ability_id != "":
		# Preserve manually granted active ability (e.g. during tutorial or special mission modes)
		pass
	elif next_ability != ability_id:
		ability_timer = 0
		ability_id = next_ability
	if not upgrade_mods.is_empty():
		mods = _apply_upgrade_mods(mods)
	Mutators.apply_mods(mods)
	max_hp = maxf(1.0, round(base_max_hp * float(mods["maxHPMult"])))
	speed = base_speed * float(mods["speedMult"]) * enrage_speed_mult
	fire_rate = maxi(4, int(round(float(base_fire_rate) * float(mods["fireRateMult"]) * enrage_fire_rate_mult)))
	hp = clampf(round(max_hp * hp_ratio), 1.0, max_hp)
	if has_build("stealth_hunter"):
		mods["evasionChance"] = 1.0 - (1.0 - float(mods.get("evasionChance", 0.0))) * 0.75
	if is_chimera_boss:
		mods["evasionChance"] = 1.0 - (1.0 - float(mods.get("evasionChance", 0.0))) * 0.75
	if is_chimera_clone:
		mods["evasionChance"] = 1.0 - (1.0 - float(mods.get("evasionChance", 0.0))) * 0.80
	if not flags.has("shield"):
		shield_hp = 0.0

func has_build(build_id: String) -> bool:
	return Perks.is_build_complete(build_id, perk_ids)

func completed_builds() -> Array:
	return Perks.completed_builds(perk_ids)

func thrust(dx: float, dy: float) -> void:
	if dx == 0.0 and dy == 0.0:
		return
	if not alive or freeze_ticks > 0 or stun_ticks > 0 or rammer_daze_ticks > 0:
		return
	var length := sqrt(dx * dx + dy * dy)
	dx /= length
	dy /= length
	var mult := 1.0
	if turbo_timer > 0:
		mult *= 1.5
	mult *= surface_speed
	var accel := speed * Cfg.ACCEL_FACTOR * mult
	vx += dx * accel
	vy += dy * accel
	angle = atan2(dy, dx)
	wants_move = true

func aim_at(tx: float, ty: float) -> void:
	if not alive or freeze_ticks > 0 or stun_ticks > 0:
		return
	turret_angle = atan2(ty - y, tx - x)

func slew_turret_to(target: float) -> void:
	if not alive or freeze_ticks > 0 or stun_ticks > 0:
		return
	turret_angle = Rng.rotate_toward(turret_angle, target, BOT_TURRET_SLEW)

func update(world) -> void:
	if not alive:
		return

	if spawn_protect > 0:
		spawn_protect -= 1
	if fire_cooldown > 0:
		fire_cooldown -= 1
	_update_heat(world)
	if mine_cooldown > 0:
		mine_cooldown -= 1
	if shield_cooldown > 0:
		shield_cooldown -= 1
	if ability_cd > 0:
		ability_cd -= 1
	if ability_timer > 0:
		ability_timer -= 1
	if turbo_timer > 0:
		turbo_timer -= 1
	if shadow_timer > 0:
		shadow_timer -= 1
	if dash_cooldown > 0:
		dash_cooldown -= 1
	if dash_invuln_ticks > 0:
		dash_invuln_ticks -= 1
	if weapon_timer > 0:
		weapon_timer -= 1
		if weapon_timer <= 0:
			weapon = ""
	if telegraph_ticks > 0:
		telegraph_ticks -= 1
		if telegraph_ticks <= 0:
			_resolve_telegraphed_attack(world)
	if enrage_shield_ticks > 0:
		enrage_shield_ticks -= 1
	if stun_ticks > 0:
		stun_ticks -= 1
	if rammer_daze_ticks > 0:
		rammer_daze_ticks -= 1
	if world == null:
		return
	if cryo_immunity_ticks > 0:
		cryo_immunity_ticks -= 1
	if freeze_ticks > 0:
		freeze_ticks -= 1
		if freeze_ticks % 14 == 0 and world != null and world.particles != null:
			world.particles.burst(x, y, [Color("#aaeeff"), Color("#e0f7fa")], 2, 1, 2, 6, 12, world.rng)
		if freeze_ticks == 0:
			freeze_max_ticks = 0
			if world != null and world.particles != null:
				world.particles.burst(x, y, [Color("#00f0ff"), Color("#aaeeff"), Color.WHITE], 18, 3, 6, 16, 32, world.rng)
			Sfx.play("crack", x, y)
	if acid_ticks_left > 0:
		acid_ticks_left -= 1
		if acid_ticks_left <= 0:
			acid_stacks = 0
		else:
			acid_tick_timer -= 1
			if acid_tick_timer <= 0:
				acid_tick_timer = Cfg.ACID_TICK_INTERVAL
				var acid_mult: float = float(acid_attacker.mods["acidDmgMult"]) if acid_attacker != null else 1.0
				var tick_dmg: float = Cfg.ACID_DMG_PER_STACK_TICK * float(acid_stacks) * acid_dmg_scale * acid_mult
				if acid_attacker != null and acid_attacker.is_boss:
					tick_dmg = minf(tick_dmg, max_hp * Cfg.BOSS_HIT_CAP_FRACTION)
				world.deal_damage(self, tick_dmg, acid_attacker, "acid")
				if acid_stacks >= Cfg.ACID_STACK_MAX and acid_attacker != null \
						and acid_attacker.alive and acid_attacker.flags.has("acidCloud"):
					world.particles.burst(x, y, [Color("#84cc16"), Color("#a3e635"), Color.WHITE], 14, 2, 5, 14, 28, world.rng)
					world.damage_number.emit(x, y - 24, "☁️ ЕДКОЕ ОБЛАКО", Color("#84cc16"))
					for other in world.tanks:
						if other == self or not other.alive or not world.are_hostile(acid_attacker, other):
							continue
						var dx_ac: float = other.x - x
						var dy_ac: float = other.y - y
						if dx_ac * dx_ac + dy_ac * dy_ac > Cfg.ACID_CLOUD_RADIUS * Cfg.ACID_CLOUD_RADIUS:
							continue
						other.apply_acid(world, acid_attacker, acid_dmg_scale)

	if flags.has("skyStrike") and world.weather != null and world.weather.condition == "storm":
		if sky_strike_cooldown > 0:
			sky_strike_cooldown -= 1
		elif not sky_strike_ready:
			sky_strike_ready = true

	wants_move = false
	_update_surface(world)
	_update_regen()
	_update_shield(world)
	_update_boss_phase(world)

	if is_rammer_boss:
		_update_rammer_boss(world)
	if is_chimera_boss or is_chimera_clone:
		_update_chimera_boss(world)

	if freeze_ticks <= 0:
		if is_player_controlled:
			_process_input_buffer(world)

		if is_rammer_boss and (rammer_state == "charge" or rammer_state == "spin" or rammer_state == "telegraph"):
			pass
		elif owner != null:
			owner.control(self, world)
		elif brain != null:
			brain.update(self, world)

		if not (is_rammer_boss and (rammer_state == "charge" or rammer_state == "spin")):
			if dash_range > 0.0:
				var boost := speed * Cfg.DASH_SPEED_MULT
				var ddir: Vector2 = dash_dir if dash_dir != Vector2.ZERO else Vector2(cos(angle), sin(angle))
				vx = ddir.x * boost
				vy = ddir.y * boost

			var before_x := x
			var before_y := y
			_move(world)
			var moved := Vector2(x - before_x, y - before_y).length()

			if wants_move and moved < 0.2:
				stall_ticks += 1
				worst_stall = maxi(worst_stall, stall_ticks)
			else:
				stall_ticks = 0

			if dash_range > 0.0:
				dash_range -= moved
				if moved < 0.15:
					dash_stall += 1
					if dash_stall >= 3:
						dash_range = 0.0
				else:
					dash_stall = 0
				if dash_range <= 0.0:
					dash_range = 0.0
					dash_stall = 0
	else:
		vx = 0.0
		vy = 0.0
		dash_range = 0.0
		dash_stall = 0
	_check_water(world)
	_try_ram(world)

	vx *= Cfg.FRICTION
	vy *= Cfg.FRICTION

	body_angle = Rng.rotate_toward(body_angle, angle,
		absf(angle - body_angle) * BODY_TURN_RATE + 0.02)

func _process_input_buffer(world) -> void:
	# Исполнение буферизованных действий в порядке приоритета:
	# 1. Спасение и маневр (Dash)
	if buffer_dash_ticks > 0:
		buffer_dash_ticks -= 1
		if can_act(CC_SOFT) and dash_cooldown <= 0 and dash_range <= 0.0:
			dash(buffer_dash_dir)
	# 2. Способность
	if buffer_ability_ticks > 0:
		buffer_ability_ticks -= 1
		if can_act(CC_SOFT) and ability_cd <= 0 and ability_id != "":
			use_ability(world)
	# 3. Выстрел
	if buffer_fire_ticks > 0:
		buffer_fire_ticks -= 1
		if can_fire:
			shoot(world)

func predict_move(world, cmd: Dictionary) -> void:
	if not alive:
		return
	if turbo_timer > 0:
		turbo_timer -= 1
	wants_move = false
	_update_surface(world)
	thrust(float(cmd.get("mx", 0.0)), float(cmd.get("my", 0.0)))
	aim_at(float(cmd.get("ax", 0.0)), float(cmd.get("ay", 0.0)))
	_move(world, false)
	vx *= Cfg.FRICTION
	vy *= Cfg.FRICTION
	body_angle = Rng.rotate_toward(body_angle, angle,
		absf(angle - body_angle) * BODY_TURN_RATE + 0.02)

func _update_surface(world) -> void:
	surface = Surfaces.of_tile(world.map.tile_at_pixel(x, y), world.road_kind)
	surface_speed = float(surface["speed"])
	if ability_active("grip"):
		surface_speed = maxf(surface_speed, float(Surfaces.ASPHALT["speed"]))
	elif surface_speed < 1.0:
		surface_speed = lerpf(surface_speed, 1.0, clampf(float(mods["softGrip"]), 0.0, 1.0))
	elif surface_speed > 1.0:
		surface_speed *= float(mods["roadSpeedMult"])

	if world.weather != null and not ability_active("grip"):
		surface_speed *= world.weather.traction

	var spd := sqrt(vx * vx + vy * vy)
	if spd < 0.45:
		return
	if world.tick % 6 == 0:
		var back := angle + PI
		world.particles.spawn(
			x + cos(back) * 12.0 + (world.rng.nextf() - 0.5) * 8.0,
			y + sin(back) * 12.0 + (world.rng.nextf() - 0.5) * 8.0,
			surface["dust"], 1.5 + world.rng.nextf() * 1.5, 8.0 + world.rng.nextf() * 10.0,
			world.rng, cos(back) * 0.3, sin(back) * 0.3)
	if owner != null:
		_tread_timer -= 1
		if _tread_timer <= 0:
			_tread_timer = 16
			Sfx.play(String(surface["tread"]), x, y)

func _update_regen() -> void:
	var per_minute := float(mods["regenPerMinute"])
	if per_minute <= 0.0 or hp >= max_hp:
		return
	regen_accum += per_minute / float(Cfg.TICK_HZ * 60)
	if regen_accum >= 1.0:
		var heal := floorf(regen_accum)
		regen_accum -= heal
		hp = minf(max_hp, hp + heal)

func _update_shield(world) -> void:
	if not flags.has("shield"):
		return
	if shield_hp <= 0.0 and shield_cooldown <= 0:
		shield_hp = Cfg.SHIELD_HP
		shield_cooldown = Cfg.SHIELD_COOLDOWN
		world.particles.burst(x, y, [Cfg.shield, Color("#88ddff")], 10, 2, 4, 12, 20, world.rng)

func _update_boss_phase(world) -> void:
	if not is_boss or max_hp <= 0.0:
		return
	var ratio := hp / max_hp
	if is_rammer_boss:
		if boss_phase < 2 and ratio <= 0.5:
			boss_phase = 2
			enrage_speed_mult = 1.15
			recompute()
			world.feed.emit(I18n.t("feed.rammerEnrage", {"name": name},
				"%s в ярости — таран теперь оставляет мины!" % name), Color("#ff3355"))
			world.particles.burst(x, y, [Color("#ff3355"), Color("#ffaa33")], 24, 3, 6, 20, 34, world.rng)
			world.add_shake(7.0, x, y)
			Sfx.play("thunder", x, y)
		return

	if boss_phase < 2 and ratio <= Cfg.BOSS_PHASE2_HP:
		boss_phase = 2
		enrage_speed_mult = Cfg.BOSS_PHASE2_SPEED_MULT
		enrage_fire_rate_mult = Cfg.BOSS_PHASE2_FIRE_RATE_MULT
		recompute()
		world.feed.emit(I18n.t("feed.bossEnrage", {"name": name},
			"%s впадает в ярость!" % name), Color("#ff3355"))
		world.particles.burst(x, y, [Color("#ff3355"), Color("#ffaa33")], 24, 3, 6, 20, 34, world.rng)
		world.add_shake(6.0, x, y)
		Sfx.play("thunder", x, y)
	elif boss_phase < 3 and ratio <= Cfg.BOSS_PHASE3_HP:
		boss_phase = 3
		enrage_speed_mult = Cfg.BOSS_PHASE3_SPEED_MULT
		enrage_fire_rate_mult = Cfg.BOSS_PHASE3_FIRE_RATE_MULT
		enrage_shield_ticks = Cfg.BOSS_PHASE3_SHIELD_TICKS
		ability_cd = 0
		recompute()
		world.feed.emit(I18n.t("feed.bossEnrage2", {"name": name},
			"%s на последнем издыхании — берегитесь!" % name), Color("#ff3355"))
		world.particles.burst(x, y, [Cfg.shield, Color("#ff3355")], 30, 3, 7, 22, 38, world.rng)
		world.add_shake(9.0, x, y)
		Sfx.play("thunder", x, y)

func start_rammer_charge(tx: float, ty: float, world) -> void:
	if not is_rammer_boss or not alive or rammer_state != "idle":
		return
	rammer_state = "telegraph"
	var is_enraged: bool = max_hp > 0.0 and (hp / max_hp) <= 0.5
	rammer_telegraph_ticks = 22 if is_enraged else Cfg.RAMMER_TELEGRAPH_TICKS
	rammer_dir = atan2(ty - y, tx - x)
	angle = rammer_dir
	body_angle = rammer_dir
	turret_angle = rammer_dir
	if world != null:
		if world.particles != null:
			world.particles.burst(x, y, [Color("#ff6600"), Color("#ffcc00")], 12, 2, 4, 10, 20, world.rng)
		world.add_shake(4.0, x, y)
	Sfx.play("thunder", x, y)

func start_rammer_spin(world) -> void:
	if not is_rammer_boss or not alive or rammer_state != "idle":
		return
	rammer_state = "spin"
	rammer_spin_ticks = Cfg.RAMMER_SPIN_DURATION_TICKS
	rammer_spin_mine_timer = 4
	rammer_spin_angle = body_angle
	rammer_spin_hit.clear()
	vx = 0.0
	vy = 0.0
	if world != null:
		world.spawn_shockwave(x, y, 70.0, "ram", Color("#ff6600"), 18)
		if world.particles != null:
			world.particles.burst(x, y, [Color("#ff6600"), Color("#ffcc00"), Color.WHITE], 22, 3, 6, 16, 30, world.rng)
		world.add_shake(6.0, x, y)
	Sfx.play("thunder", x, y)

func _update_rammer_boss(world) -> void:
	if not alive or freeze_ticks > 0:
		vx = 0.0
		vy = 0.0
		return
	if rammer_spin_cooldown > 0:
		rammer_spin_cooldown -= 1

	# Ability 2: Drop a mine behind periodically
	rammer_mine_timer -= 1
	if rammer_mine_timer <= 0:
		rammer_mine_timer = Cfg.RAMMER_MINE_INTERVAL
		var bx := x - cos(body_angle) * (height * 0.5 + 8.0)
		var by := y - sin(body_angle) * (height * 0.5 + 8.0)
		if world != null:
			world.mines.append(Ent.Mine.new(bx, by, self, Cfg.MINE_LIFE))
			if world.particles != null:
				world.particles.burst(bx, by, [Color("#ffaa33"), Color("#666666")], 6, 2, 4, 8, 14, world.rng)

	match rammer_state:
		"spin":
			rammer_spin_ticks -= 1
			vx = 0.0
			vy = 0.0
			# High-speed whirlwind spin
			var spin_speed: float = 0.45
			rammer_spin_angle += spin_speed
			body_angle = rammer_spin_angle
			turret_angle = rammer_spin_angle + 0.3
			angle = rammer_spin_angle

			# Whirling fire & friction sparks around tracks
			if world != null and world.particles != null and world.tick % 2 == 0:
				var spark_a := rammer_spin_angle + randf_range(-0.6, 0.6)
				var spark_dist := width * 0.65
				var sx := x + cos(spark_a) * spark_dist
				var sy := y + sin(spark_a) * spark_dist
				world.particles.burst(sx, sy, [Color("#ff4400"), Color("#ffbb00"), Color("#ffa500")], 3, 2, 4, 10, 20, world.rng)

			# Scatter mines in a 360-degree radial barrage around himself
			rammer_spin_mine_timer -= 1
			if rammer_spin_mine_timer <= 0:
				rammer_spin_mine_timer = Cfg.RAMMER_SPIN_MINE_INTERVAL
				var launch_angle := rammer_spin_angle
				var launch_dist := randf_range(Cfg.RAMMER_SPIN_RADIUS_MIN, Cfg.RAMMER_SPIN_RADIUS_MAX)
				var mx := x + cos(launch_angle) * launch_dist
				var my := y + sin(launch_angle) * launch_dist
				if world != null:
					if world.map != null:
						mx = clampf(mx, Cfg.TILE * 1.5, world.map.width - Cfg.TILE * 1.5)
						my = clampf(my, Cfg.TILE * 1.5, world.map.height - Cfg.TILE * 1.5)
					var m := Ent.Mine.new(mx, my, self, Cfg.MINE_LIFE)
					m.arming_ticks = 25
					world.mines.append(m)
					if world.particles != null:
						world.particles.burst(mx, my, [Color("#ff5500"), Color("#ffdd33"), Color.WHITE], 8, 2, 5, 12, 22, world.rng)
					world.spawn_shockwave(x, y, 45.0, "ram", Color("#ffaa00"), 12)
					Sfx.play("shoot", x, y)
					world.add_shake(3.0, x, y)

			# Rotary buzzsaw collision damage to hostile tanks
			if world != null:
				var melee_r := width * 0.75 + 14.0
				var melee_r2 := melee_r * melee_r
				for other in world.tanks:
					if other == self or not other.alive or not world.are_hostile(self, other):
						continue
					if rammer_spin_hit.has(other) and rammer_spin_ticks % 16 != 0:
						continue
					var d2: float = (other.x - x) * (other.x - x) + (other.y - y) * (other.y - y)
					if d2 <= melee_r2:
						if not rammer_spin_hit.has(other):
							rammer_spin_hit.append(other)
						var knock_a := atan2(other.y - y, other.x - x)
						other.vx += cos(knock_a) * 14.0
						other.vy += sin(knock_a) * 14.0
						world.deal_damage(other, Cfg.RAMMER_SPIN_MELEE_DMG * dmg_scale, self, "ram")
						if world.particles != null:
							world.particles.burst(other.x, other.y, [Color("#ef4444"), Color.WHITE], 12, 2, 5, 14, 24, world.rng)
						world.spawn_shockwave(other.x, other.y, 45.0, "ram", Color("#ef4444"), 14)
						Sfx.play("crack", other.x, other.y)

			# Finish whirlwind spin
			if rammer_spin_ticks <= 0:
				rammer_state = "idle"
				rammer_spin_cooldown = Cfg.RAMMER_SPIN_COOLDOWN_TICKS
				if world != null:
					world.spawn_shockwave(x, y, 110.0, "ram", Color("#ff5500"), 22)
					if world.particles != null:
						world.particles.burst(x, y, [Color("#ff4400"), Color("#ffaa00"), Color.WHITE], 24, 3, 7, 20, 36, world.rng)
					world.add_shake(8.0, x, y)
				Sfx.play("thunder", x, y)

		"telegraph":
			rammer_telegraph_ticks -= 1
			vx *= 0.4
			vy *= 0.4
			if world.tick % 4 == 0:
				world.particles.burst(x, y, [Color("#888888"), Color("#ff6600")], 3, 1, 3, 6, 12, world.rng)
			if rammer_telegraph_ticks <= 0:
				rammer_state = "charge"
				rammer_charge_ticks = Cfg.RAMMER_CHARGE_TICKS
				rammer_charge_mine_timer = 0
				rammer_charge_hit.clear()
				world.spawn_shockwave(x, y, 80.0, "ram", Color("#ff7700"), 20)
				world.particles.burst(x, y, [Color("#ff4400"), Color("#ffbb00"), Color.WHITE], 24, 3, 7, 20, 36, world.rng)
				world.add_shake(12.0, x, y)
				Sfx.play("thunder", x, y)

		"charge":
			rammer_charge_ticks -= 1
			var spd := Cfg.RAMMER_CHARGE_SPEED
			vx = cos(rammer_dir) * spd
			vy = sin(rammer_dir) * spd
			x += vx
			y += vy
			body_angle = rammer_dir
			turret_angle = rammer_dir
			angle = rammer_dir

			if world.tick % 2 == 0:
				world.particles.burst(x, y, [Color("#ff4400"), Color("#ffa500"), Color("#333333")], 4, 2, 5, 8, 18, world.rng)

			# Phase 2 (< 50% HP): Mines dropped continuously during charge
			if max_hp > 0.0 and (hp / max_hp) <= 0.5:
				rammer_charge_mine_timer -= 1
				if rammer_charge_mine_timer <= 0:
					rammer_charge_mine_timer = Cfg.RAMMER_CHARGE_MINE_INTERVAL
					var mx := x - cos(rammer_dir) * (height * 0.5 + 8.0)
					var my := y - sin(rammer_dir) * (height * 0.5 + 8.0)
					var m := Ent.Mine.new(mx, my, self, Cfg.MINE_LIFE)
					m.arming_ticks = Cfg.RAMMER_CHARGE_MINE_ARMING_TICKS
					world.mines.append(m)
					world.particles.burst(mx, my, [Color("#ff4400"), Color("#ffcc00")], 6, 2, 4, 10, 16, world.rng)

			# Destroy obstacles in path
			var map: GameMap = world.map
			var hw := width * 0.5 + 4.0
			var hh := height * 0.5 + 4.0
			var r_min := map.row_at(y - hh)
			var r_max := map.row_at(y + hh)
			var c_min := map.col_at(x - hw)
			var c_max := map.col_at(x + hw)
			var hit_hard := false

			for r in range(r_min, r_max + 1):
				for c in range(c_min, c_max + 1):
					var t: int = map.get_tile(r, c)
					if t == Cfg.T_BRICK or t == Cfg.T_ADOBE:
						world.hit_building(r, c, 999.0, "ram", c * Cfg.TILE + 16, r * Cfg.TILE + 16, self)
					elif t == Cfg.T_TREE:
						map.set_tile(r, c, Cfg.T_EMPTY)
						world.particles.burst(c * Cfg.TILE + 16, r * Cfg.TILE + 16, [Cfg.tree, Cfg.tree_dark], 12, 2, 5, 14, 24, world.rng)
					elif t == Cfg.T_WALL:
						hit_hard = true

			if hit_hard or x <= col_w or x >= map.width - col_w or y <= col_h or y >= map.height - col_h:
				rammer_charge_ticks = 0
				world.spawn_shockwave(x, y, 90.0, "ram", Color("#ff4400"), 22)
				world.add_shake(14.0, x, y)
				Sfx.play("crack", x, y)

			x = clampf(x, col_w * 0.5 + 2.0, map.width - col_w * 0.5 - 2.0)
			y = clampf(y, col_h * 0.5 + 2.0, map.height - col_h * 0.5 - 2.0)

			# Ramming collision with tanks
			for other in world.tanks:
				if other == self or not other.alive or not world.are_hostile(self, other):
					continue
				if rammer_charge_hit.has(other):
					continue
				var d2: float = (other.x - x) * (other.x - x) + (other.y - y) * (other.y - y)
				if d2 <= 42.0 * 42.0:
					rammer_charge_hit.append(other)
					var ram_dmg: float = minf(Cfg.RAMMER_CHARGE_MAX_DMG * dmg_scale, other.max_hp * Cfg.BOSS_HIT_CAP_FRACTION)
					world.deal_damage(other, ram_dmg, self, "ram")
					other.vx += cos(rammer_dir) * 14.0
					other.vy += sin(rammer_dir) * 14.0
					world.spawn_shockwave(other.x, other.y, 60.0, "ram", Color("#ef4444"), 16)
					world.particles.burst(other.x, other.y, [Color("#ff4400"), Color.WHITE], 16, 2, 6, 16, 28, world.rng)
					Sfx.play("crack", other.x, other.y)
					world.add_shake(8.0, other.x, other.y)

			# Defense base rule: max 50 total damage
			if world.mode == "defense" and world.base != null:
				var db := Vector2(world.base["x"] - x, world.base["y"] - y).length()
				if db <= float(world.base["radius"]) + 20.0:
					var remaining_cap: float = maxf(0.0, Cfg.RAMMER_BASE_MAX_TOTAL_DMG - rammer_base_damage_dealt)
					if remaining_cap > 0.0:
						var applied_base_hit := minf(remaining_cap, 50.0)
						rammer_base_damage_dealt += applied_base_hit
						world.base["hp"] = maxf(0.0, float(world.base["hp"]) - applied_base_hit)
						world.damage_number.emit(world.base["x"], world.base["y"] - 30, "-%d БАЗА!" % int(applied_base_hit), Color("#ff4444"))
						world.add_shake(12.0, world.base["x"], world.base["y"])
						Sfx.play("hit")

			if rammer_charge_ticks <= 0:
				rammer_state = "cooldown"
				rammer_cooldown_ticks = Cfg.RAMMER_COOLDOWN_TICKS
				rammer_daze_ticks = Cfg.RAMMER_DAZE_TICKS
				vx = 0.0
				vy = 0.0
				world.damage_number.emit(x, y - 34, "⚡ ОГЛУШЁН!", Color("#ffee55"))
				world.particles.burst(x, y, [Color("#ffee55"), Color("#888888")], 18, 2, 5, 14, 24, world.rng)

		"cooldown":
			rammer_cooldown_ticks -= 1
			if rammer_cooldown_ticks <= 0:
				rammer_state = "idle"

func _update_chimera_boss(world) -> void:
	if not alive or freeze_ticks > 0:
		vx = 0.0
		vy = 0.0
		return

	if is_chimera_boss:
		# Ability 1: Predator Cloak
		if shadow_timer > 0:
			chimera_ambush_ready = true
			turbo_timer = maxi(turbo_timer, 2)
		else:
			chimera_cloak_timer -= 1
			if chimera_cloak_timer <= 0:
				chimera_cloak_timer = Cfg.CHIMERA_CLOAK_INTERVAL
				shadow_timer = Cfg.CHIMERA_CLOAK_DURATION
				turbo_timer = Cfg.CHIMERA_CLOAK_DURATION
				chimera_ambush_ready = true
				world.particles.burst(x, y, [Color("#84cc16"), Color("#a3e635"), Color("#182b18")], 20, 2, 5, 14, 26, world.rng)
				world.spawn_shockwave(x, y, 60.0, "acid", Color("#84cc16"), 18)
				Sfx.play("steam", x, y)
				world.feed.emit(I18n.t("feed.chimeraCloak", {"name": name},
					"🧪 %s активирует оптический камуфляж хищника!" % name), Color("#84cc16"))

		# Phase 2 (< 50% HP): Holographic decoy clones
		if max_hp > 0.0 and (hp / max_hp) <= 0.5 and not chimera_clones_spawned:
			chimera_clones_spawned = true
			world.spawn_chimera_clone(self, -1.0)
			world.spawn_chimera_clone(self, 1.0)
			shadow_timer = Cfg.CHIMERA_CLOAK_DURATION
			turbo_timer = Cfg.CHIMERA_CLOAK_DURATION
			chimera_ambush_ready = true
			world.spawn_shockwave(x, y, 80.0, "acid", Color("#84cc16"), 24)
			world.particles.burst(x, y, [Color("#84cc16"), Color("#00ffff"), Color("#ff00ff"), Color.WHITE], 32, 3, 7, 20, 38, world.rng)
			world.damage_number.emit(x, y - 30, "🧪 ГОЛОГРАММЫ!", Color("#84cc16"))
			Sfx.play("thunder", x, y)
			world.feed.emit(I18n.t("feed.chimeraClones", {"name": name},
				"🧪 %s развёртывает голографических клонов и уходит в тень!" % name), Color("#84cc16"))

	# Ability 2: Corrosive Trail (Acid Pools) while moving
	var spd := sqrt(vx * vx + vy * vy)
	if spd > 0.4:
		chimera_pool_timer -= 1
		if chimera_pool_timer <= 0:
			chimera_pool_timer = 50
			var bx := x - cos(body_angle) * (height * 0.45)
			var by := y - sin(body_angle) * (height * 0.45)
			world.spawn_acid_pool(bx, by, Cfg.CHIMERA_ACID_POOL_RADIUS, self, Cfg.CHIMERA_ACID_POOL_DURATION)
			world.particles.burst(bx, by, [Color("#84cc16"), Color("#4d7c0f")], 4, 1, 3, 6, 12, world.rng)

	# Ability 3: Acid Jet Stream with Warmup Telegraph
	if chimera_stream_cd > 0:
		chimera_stream_cd -= 1

	if chimera_stream_active:
		chimera_stream_timer -= 1
		_process_chimera_stream(world)
		if chimera_stream_timer <= 0:
			chimera_stream_active = false
			chimera_stream_cd = Cfg.CHIMERA_STREAM_COOLDOWN
	elif chimera_stream_warmup_ticks > 0:
		chimera_stream_warmup_ticks -= 1
		# Slow down movement during telegraph warmup
		vx *= 0.82
		vy *= 0.82
		_update_chimera_telegraph(world)
		var mx: float = x + cos(turret_angle) * muzzle_len
		var my: float = y + sin(turret_angle) * muzzle_len
		if chimera_stream_warmup_ticks % 8 == 0:
			world.particles.burst(mx, my, [Color("#bef264"), Color("#84cc16"), Color("#ffffff")], 2, 1, 2, 4, 8, world.rng)
		if chimera_stream_warmup_ticks <= 0:
			start_chimera_stream(world)
	elif is_chimera_clone and chimera_clone_parent != null and chimera_clone_parent.alive:
		# Clone synchronizes telegraph warmup with parent
		if chimera_clone_parent.chimera_stream_warmup_ticks > 0 and chimera_stream_warmup_ticks <= 0 and not chimera_stream_active and chimera_stream_cd <= 0:
			start_chimera_warmup(world)
	elif is_chimera_boss and chimera_stream_cd <= 0 and shadow_timer <= 0:
		# Check if target is in front within stream range (150 px) & line of sight
		var has_target_in_range := false
		for other in world.tanks:
			if other == self or not other.alive or other.team == team:
				continue
			var d2: float = (other.x - x) * (other.x - x) + (other.y - y) * (other.y - y)
			if d2 <= Cfg.CHIMERA_STREAM_RANGE * Cfg.CHIMERA_STREAM_RANGE:
				var to_a: float = atan2(other.y - y, other.x - x)
				var diff: float = absf(atan2(sin(turret_angle - to_a), cos(turret_angle - to_a)))
				if diff < 0.55 and world.map.has_line_of_sight(x, y, other.x, other.y):
					has_target_in_range = true
					break
		if has_target_in_range:
			start_chimera_warmup(world)

func start_chimera_warmup(world) -> void:
	chimera_stream_warmup_ticks = Cfg.CHIMERA_STREAM_WARMUP_TICKS
	_update_chimera_telegraph(world)
	var mx: float = x + cos(turret_angle) * muzzle_len
	var my: float = y + sin(turret_angle) * muzzle_len
	Sfx.play("steam", mx, my)
	if is_chimera_boss and not is_chimera_clone:
		world.damage_number.emit(x, y - 24, "⚠️ ЗАРЯДКА КИСЛОТЫ", Color("#a3e635"))

func _update_chimera_telegraph(world) -> void:
	var muzzle_x: float = x + cos(turret_angle) * muzzle_len
	var muzzle_y: float = y + sin(turret_angle) * muzzle_len
	var dir_x: float = cos(turret_angle)
	var dir_y: float = sin(turret_angle)
	var max_len: float = Cfg.CHIMERA_STREAM_RANGE
	var step_size: float = 10.0
	var cur_dist: float = 0.0
	var hit_pos: Vector2 = Vector2(muzzle_x + dir_x * max_len, muzzle_y + dir_y * max_len)
	while cur_dist < max_len:
		cur_dist += step_size
		var test_x: float = muzzle_x + dir_x * cur_dist
		var test_y: float = muzzle_y + dir_y * cur_dist
		var r: int = world.map.row_at(test_y)
		var c: int = world.map.col_at(test_x)
		if not world.map.in_bounds(r, c):
			hit_pos = Vector2(test_x, test_y)
			break
		var tile: int = world.map.get_tile(r, c)
		if GameMap.is_solid_tile(tile):
			hit_pos = Vector2(test_x, test_y)
			break
	chimera_stream_target_point = hit_pos

func start_chimera_stream(world) -> void:
	chimera_stream_active = true
	chimera_stream_timer = Cfg.CHIMERA_STREAM_BURST_TICKS
	chimera_stream_warmup_ticks = 0
	var mx: float = x + cos(turret_angle) * muzzle_len
	var my: float = y + sin(turret_angle) * muzzle_len
	world.spawn_shockwave(mx, my, 32.0, "acid", Color("#84cc16"), 10)
	world.particles.burst(mx, my, [Color("#84cc16"), Color("#a3e635"), Color.WHITE], 10, 2, 4, 10, 18, world.rng)
	Sfx.play("steam", mx, my)
	if is_chimera_boss and not is_chimera_clone:
		world.feed.emit(I18n.t("feed.chimeraStream", {"name": name},
			"🧪 %s заливает сектор непрерывной струёй кислоты!" % name), Color("#a3e635"))

func _process_chimera_stream(world) -> void:
	if not alive:
		chimera_stream_active = false
		chimera_stream_warmup_ticks = 0
		return

	var muzzle_x: float = x + cos(turret_angle) * muzzle_len
	var muzzle_y: float = y + sin(turret_angle) * muzzle_len
	var dir_x: float = cos(turret_angle)
	var dir_y: float = sin(turret_angle)
	var max_len: float = Cfg.CHIMERA_STREAM_RANGE
	var step_size: float = 10.0
	var cur_dist: float = 0.0
	var hit_pos: Vector2 = Vector2(muzzle_x + dir_x * max_len, muzzle_y + dir_y * max_len)
	var hit_tile_row := -1
	var hit_tile_col := -1

	while cur_dist < max_len:
		cur_dist += step_size
		var test_x: float = muzzle_x + dir_x * cur_dist
		var test_y: float = muzzle_y + dir_y * cur_dist
		var r: int = world.map.row_at(test_y)
		var c: int = world.map.col_at(test_x)
		if not world.map.in_bounds(r, c):
			hit_pos = Vector2(test_x, test_y)
			break
		var tile: int = world.map.get_tile(r, c)
		if GameMap.is_solid_tile(tile):
			hit_pos = Vector2(test_x, test_y)
			hit_tile_row = r
			hit_tile_col = c
			break

	chimera_stream_target_point = hit_pos
	var stream_len: float = Vector2(hit_pos.x - muzzle_x, hit_pos.y - muzzle_y).length()

	# Damage enemy tanks intersecting the acid stream
	var normal_x: float = -dir_y
	var normal_y: float = dir_x
	var radius: float = Cfg.CHIMERA_STREAM_WIDTH * 0.75 + Cfg.TANK_BODY_R * 0.6
	var mult: float = (0.50 if is_chimera_clone else 1.0) * boss_stat_mult * dmg_scale
	var tick_dmg: float = Cfg.CHIMERA_STREAM_TICK_DMG * mult

	for other in world.tanks:
		if other == self or not other.alive or other.team == team:
			continue
		var to_ox: float = other.x - muzzle_x
		var to_oy: float = other.y - muzzle_y
		var proj_len: float = to_ox * dir_x + to_oy * dir_y
		if proj_len < -10.0 or proj_len > stream_len + 15.0:
			continue
		var perp_dist: float = absf(to_ox * normal_x + to_oy * normal_y)
		if perp_dist <= radius:
			world.deal_damage(other, tick_dmg, self, "acid_stream")
			other.acid_stream_hit_accum += tick_dmg
			if other.acid_stream_hit_accum >= 2.0:
				var show_val := int(round(other.acid_stream_hit_accum))
				world.damage_number.emit(other.x, other.y - 20, "-%d" % show_val, Color("#a3e635"))
				other.acid_stream_hit_accum = 0.0
			# Apply acid debuff stack only every 20 ticks (~0.33s), capped at 3 stacks max!
			if chimera_stream_timer % 20 == 0 and other.acid_stacks < 3:
				other.apply_acid(world, self, 1.0, 1)
			if world.rng.nextf() < 0.20:
				world.particles.burst(other.x, other.y, [Color("#84cc16"), Color("#a3e635"), Color("#4d7c0f")], 2, 1, 2, 6, 12, world.rng)

	# Erode bricks if hitting brick wall
	if hit_tile_row != -1 and hit_tile_col != -1:
		var tile: int = world.map.get_tile(hit_tile_row, hit_tile_col)
		if tile == Cfg.T_BRICK:
			world.map.apply_damage(hit_tile_row, hit_tile_col, 0.35, "acid_stream")

	# Periodically spawn a small acid puddle at impact point (every 30 ticks)
	if chimera_stream_timer % 30 == 0:
		world.spawn_acid_pool(hit_pos.x, hit_pos.y, 14.0, self, 80)

	# Sound & particles
	if chimera_stream_timer % 16 == 0:
		Sfx.play("steam", muzzle_x, muzzle_y)

	# Impact splash particles
	world.particles.burst(hit_pos.x, hit_pos.y, [Color("#84cc16"), Color("#a3e635"), Color("#22c55e")], 2, 1, 3, 6, 12, world.rng)


func _move(world, crush_trees: bool = true) -> void:
	var map: GameMap = world.map
	var nx := x + vx
	var ny := y + vy

	var hit := false
	if not map.is_blocked_rect(nx, y, col_w, col_h):
		x = nx
	elif vx != 0.0:
		vx = 0.0
		hit = true
	if not map.is_blocked_rect(x, ny, col_w, col_h):
		y = ny
	elif vy != 0.0:
		vy = 0.0
		hit = true
	if hit:
		blocked_ticks += 1

	if crush_trees:
		_crush_trees(world)

	x = clampf(x, col_w * 0.5 + 2.0, map.width - col_w * 0.5 - 2.0)
	y = clampf(y, col_h * 0.5 + 2.0, map.height - col_h * 0.5 - 2.0)

func _crush_trees(world) -> void:
	var map: GameMap = world.map
	var hw := width * 0.5
	var hh := height * 0.5
	var keep := flags.has("forest")
	var count := 0
	for i in 5:
		var px := x if i == 4 else x + (-hw if i % 2 == 0 else hw)
		var py := y if i == 4 else y + (-hh if i < 2 else hh)
		var row := map.row_at(py)
		var col := map.col_at(px)
		if map.get_tile(row, col) != Cfg.T_TREE:
			continue
		count += 1
		if keep:
			continue
		map.set_tile(row, col, Cfg.T_EMPTY)
		world.particles.burst(col * Cfg.TILE + 16, row * Cfg.TILE + 16,
			[Cfg.tree, Cfg.tree_dark], 10, 2, 5, 15, 25, world.rng)
	if count > 0 and owner != null:
		world.on_trees_driven(self, count)

func _check_water(world) -> void:
	if world.map.tile_at_pixel(x, y) == Cfg.T_QUICKSAND:
		in_water = false
		quicksand_timer += 1
		if quicksand_timer >= Cfg.QUICKSAND_DMG_INTERVAL:
			quicksand_timer = 0
			world.deal_damage(self, Cfg.QUICKSAND_DMG, null, "water")
			world.particles.burst(x, y, [Cfg.quicksand, Cfg.quicksand_wet],
				4, 1, 3, 8, 14, world.rng)
			if owner != null:
				Ctl.vibrate(owner, 0.5, 0.8, 0.25)
		return
	quicksand_timer = 0

	var wet: bool = world.map.is_water_at(x, y)
	if not wet:
		in_water = false
		water_timer = 0
		return
	if not in_water:
		in_water = true
		if owner != null:
			world.on_water_entered(self)
			Ctl.vibrate(owner, 0.3, 0.4, 0.15)
	vx *= Cfg.WATER_DRAG
	vy *= Cfg.WATER_DRAG

	if flags.has("amphibious"):
		water_timer = 0
	else:
		water_timer += 1
		if water_timer >= Cfg.WATER_DMG_INTERVAL:
			water_timer = 0
			world.deal_damage(self, Cfg.WATER_DMG, null, "water")
			world.particles.burst(x, y, [Cfg.water_light, Color("#88aaff")], 5, 2, 4, 12, 18, world.rng)
			if owner != null:
				Sfx.play("water", x, y)
				Ctl.vibrate(owner, 0.4, 0.7, 0.2)
	if world.tick % 8 == 0:
		world.particles.burst(x, y, [Cfg.water_light], 1, 2, 2, 10, 10, world.rng)

func _try_ram(world) -> void:
	if freeze_ticks > 0:
		return
	if is_rammer_boss and rammer_state == "charge":
		return
	var spd := sqrt(vx * vx + vy * vy)
	if spd <= Cfg.RAM_MIN_SPEED:
		return
	var r2 := Cfg.TANK_BODY_R * Cfg.TANK_BODY_R
	for other in world.tank_grid.query(x, y, Cfg.TANK_BODY_R):
		if other == self or not other.alive:
			continue
		if not world.are_hostile(self, other):
			continue
		var dx: float = other.x - x
		var dy: float = other.y - y
		if dx * dx + dy * dy > r2:
			continue
		var damage := floorf(spd * Cfg.RAM_DMG_PER_SPEED * float(mods["ramMult"]))
		if other.freeze_ticks > 0:
			world.execute_frozen_kill(other, self)
		elif damage > 0.0:
			world.deal_damage(other, damage, self, "ram")
		var push_angle: float = atan2(dy, dx)
		other.vx += cos(push_angle) * Cfg.RAM_PUSH
		other.vy += sin(push_angle) * Cfg.RAM_PUSH

func shoot(world) -> bool:
	if not can_fire:
		if alive and is_player_controlled and ((fire_cooldown > 0 and fire_cooldown <= INPUT_BUFFER_WINDOW) or (freeze_ticks > 0 and freeze_ticks <= INPUT_BUFFER_WINDOW)):
			buffer_fire_ticks = INPUT_BUFFER_WINDOW
		return false
	buffer_fire_ticks = 0
	fire_cooldown = reload_ticks()
	_after_shot()

	var muzzle_x := x + cos(turret_angle) * muzzle_len
	var muzzle_y := y + sin(turret_angle) * muzzle_len
	var scale_v := dmg_scale

	if is_chimera_boss or is_chimera_clone:
		return false

	var wp := Weapons.get_weapon(weapon) if weapon != "" else {}
	if not wp.is_empty():
		fire_cooldown = maxi(4, int(round(float(reload_ticks()) * float(wp["cooldown_mult"]))))
		var bullets := int(wp["bullets"])
		for i in bullets:
			var offset := 0.0
			if bullets > 1:
				offset = (float(i) - float(bullets - 1) * 0.5) * float(wp["spread"]) * 2.0 / float(bullets - 1)
			var b := Ent.Bullet.new(muzzle_x, muzzle_y, turret_angle + offset, self,
				float(wp["dmg_scale"]) * scale_v)
			if bool(wp["explosive"]):
				b.explosive = true
				if wp.has("splash_r"):
					b.splash_r = float(wp["splash_r"])
			world.bullets.append(b)
		world.particles.burst(muzzle_x, muzzle_y, [wp["color"], Color.WHITE], 6, 2, 4, 10, 12, world.rng)
		Sfx.play("shoot_heavy", muzzle_x, muzzle_y)
		world.notify_shot(self)
		return true

	var cn := Cannons.get_cannon(cannon_id) if cannon_id != "" and cannon_id != "standard" else {}
	if not cn.is_empty():
		fire_cooldown = maxi(4, int(round(float(reload_ticks()) * float(cn["cooldown_mult"]))))
		var b := Ent.Bullet.new(muzzle_x, muzzle_y, turret_angle, self, float(cn["dmg_scale"]) * scale_v)
		b.cannon_kind = String(cn["mode"])
		b.pierce = 0
		b.explosive = false
		b.keep_bricks = false
		world.bullets.append(b)
		if world != null and world.particles != null:
			world.particles.burst(muzzle_x, muzzle_y, [cn.get("color", Color.WHITE), Color.WHITE], 6, 2, 4, 10, 12, world.rng)
		Sfx.play("shoot_heavy", muzzle_x, muzzle_y)
		world.notify_shot(self)
		return true

	var sky_strike_shot: bool = flags.has("skyStrike") and sky_strike_ready
	if sky_strike_shot:
		sky_strike_ready = false
		sky_strike_cooldown = Cfg.SKY_STRIKE_COOLDOWN

	var directions := [0.0]
	if flags.has("fanShot"):
		directions = [-0.15, 0.0, 0.15]
	var per_bullet_scale := scale_v
	if flags.has("fanShot"):
		per_bullet_scale *= 0.45
	if flags.has("doubleShot"):
		per_bullet_scale *= 0.6
	if flags.has("doubleShot"):
		var perp := turret_angle + PI / 2.0
		var ox := cos(perp) * 6.0
		var oy := sin(perp) * 6.0
		for off in directions:
			var b1 := Ent.Bullet.new(muzzle_x + ox, muzzle_y + oy, turret_angle + off, self, per_bullet_scale)
			var b2 := Ent.Bullet.new(muzzle_x - ox, muzzle_y - oy, turret_angle + off, self, per_bullet_scale)
			if sky_strike_shot:
				b1.sky_strike = true
				sky_strike_shot = false
			world.bullets.append(b1)
			world.bullets.append(b2)
	else:
		for off in directions:
			var b := Ent.Bullet.new(muzzle_x, muzzle_y, turret_angle + off, self, per_bullet_scale)
			if sky_strike_shot:
				b.sky_strike = true
				sky_strike_shot = false
			world.bullets.append(b)

	world.particles.burst(muzzle_x, muzzle_y, [Color("#ffee55"), Color("#ffffaa")], 5, 2, 4, 8, 8, world.rng)
	Sfx.play("shoot", muzzle_x, muzzle_y)
	world.notify_shot(self)
	return true

func shoot_lobbed(world) -> bool:
	if not can_fire:
		return false
	fire_cooldown = reload_ticks()
	_after_shot()

	var muzzle_x := x + cos(turret_angle) * muzzle_len
	var muzzle_y := y + sin(turret_angle) * muzzle_len
	var b := Ent.Bullet.new(muzzle_x, muzzle_y, turret_angle, self, dmg_scale)
	b.lobbed = true
	b.explosive = true
	world.bullets.append(b)

	world.particles.burst(muzzle_x, muzzle_y, [Color("#ff9933"), Color("#ffcc66")], 6, 2, 4, 10, 12, world.rng)
	Sfx.play("shoot_heavy", muzzle_x, muzzle_y)
	return true

func _resolve_telegraphed_attack(world) -> void:
	var kind := telegraph_kind
	telegraph_kind = ""
	if not alive or kind != "barrage":
		return
	var muzzle_x := x + cos(turret_angle) * muzzle_len
	var muzzle_y := y + sin(turret_angle) * muzzle_len
	var n := Cfg.BOSS_BARRAGE_BULLETS + (Cfg.BOSS_PHASE3_BARRAGE_BONUS_BULLETS if boss_phase >= 3 else 0)
	for i in n:
		var off := (float(i) - float(n - 1) * 0.5) * Cfg.BOSS_BARRAGE_SPREAD * 2.0 / float(n - 1)
		world.bullets.append(Ent.Bullet.new(muzzle_x, muzzle_y, turret_angle + off,
			self, Cfg.BOSS_BARRAGE_DMG_SCALE * dmg_scale))
	world.particles.burst(muzzle_x, muzzle_y, [Color("#ff3355"), Color("#ffaa33")], 14, 3, 6, 14, 24, world.rng)
	world.add_shake(5.0, muzzle_x, muzzle_y)
	Sfx.play("shoot_heavy", muzzle_x, muzzle_y)

func place_mine(world) -> bool:
	if not alive or freeze_ticks > 0 or stun_ticks > 0 or not flags.has("mines") or mine_cooldown > 0:
		return false
	var own := 0
	for m in world.mines:
		if m.owner == self:
			own += 1
	if own >= Cfg.MINE_MAX:
		return false
	world.mines.append(Ent.Mine.new(x, y, self, Cfg.MINE_LIFE))
	mine_cooldown = Cfg.MINE_COOLDOWN
	return true

func dash(move_dir: Vector2 = Vector2.ZERO) -> bool:
	if not alive:
		return false
	if freeze_ticks > 0 or stun_ticks > 0:
		if is_player_controlled and freeze_ticks <= INPUT_BUFFER_WINDOW:
			buffer_dash_ticks = INPUT_BUFFER_WINDOW
			buffer_dash_dir = move_dir
		return false
	if dash_cooldown > 0:
		if is_player_controlled and dash_cooldown <= INPUT_BUFFER_WINDOW:
			buffer_dash_ticks = INPUT_BUFFER_WINDOW
			buffer_dash_dir = move_dir
		return false
	if dash_range > 0.0:
		return false
	buffer_dash_ticks = 0
	dash_cooldown = Cfg.DASH_COOLDOWN
	dash_range = Mutators.dash_distance(Cfg.DASH_DISTANCE)
	dash_stall = 0
	dash_invuln_ticks = 15 # 0.25 сек неуязвимости (i-frames) при 60 тиках/сек
	if move_dir.length_squared() > 0.04:
		dash_dir = move_dir.normalized()
	else:
		dash_dir = Vector2(cos(angle), sin(angle))
	var boost := speed * Cfg.DASH_SPEED_MULT
	vx = dash_dir.x * boost
	vy = dash_dir.y * boost
	Sfx.play("dash", x, y)
	return true

func ability_active(id: String) -> bool:
	return ability_id == id and ability_timer > 0

var ability_ready: float:
	get:
		if ability_id == "":
			return 0.0
		var ab := Abilities.get_ability(ability_id)
		var cd := float(ab.get("cooldown", 1))
		if cd <= 0.0:
			return 1.0
		return clampf(1.0 - float(ability_cd) / cd, 0.0, 1.0)

func use_ability(world) -> bool:
	if not alive or ability_id == "":
		return false
	if freeze_ticks > 0 or stun_ticks > 0:
		if is_player_controlled and freeze_ticks <= INPUT_BUFFER_WINDOW:
			buffer_ability_ticks = INPUT_BUFFER_WINDOW
		return false
	if ability_cd > 0:
		if is_player_controlled and ability_cd <= INPUT_BUFFER_WINDOW:
			buffer_ability_ticks = INPUT_BUFFER_WINDOW
		return false
	var ab := Abilities.get_ability(ability_id)
	if ab.is_empty():
		return false
	buffer_ability_ticks = 0

	ability_cd = int(ab["cooldown"])
	if ability_id == "boss_barrage" and boss_phase >= 3:
		ability_cd = int(round(float(ability_cd) * Cfg.BOSS_PHASE3_BARRAGE_COOLDOWN_MULT))
	ability_timer = int(ab["duration"])

	match ability_id:
		"nitro":
			turbo_timer = maxi(turbo_timer, int(ab["duration"]))
			world.particles.burst(x, y, [Color("#ffee55"), Color("#ffffaa")],
				14, 2, 5, 14, 26, world.rng)
		"overdrive":
			world.particles.burst(x, y, [Color("#ff8833"), Color("#ffcc66")],
				12, 2, 5, 12, 22, world.rng)
		"bulwark":
			world.particles.burst(x, y, [Cfg.shield, Color("#88ccff")],
				14, 2, 5, 12, 20, world.rng)
		"shockwave":
			_shockwave(world)
		"coolant":
			heat = 0.0
			overheated = false
			world.particles.burst(x, y, [Color("#aaeeff"), Color.WHITE],
				16, 2, 5, 14, 26, world.rng)
		"repair":
			hp = minf(max_hp, hp + max_hp * Cfg.REPAIR_FRACTION)
			world.particles.burst(x, y, [Color("#55dd77"), Color("#aaffcc")],
				18, 2, 5, 12, 22, world.rng)
		"acid_bomb":
			_acid_bomb(world)
		"overclock", "grip", "breaker", "silencer", "smoke":
			var ab_color: Color = ab.get("color", Color.WHITE)
			world.particles.burst(x, y, [ab_color, Color.WHITE],
				14, 2, 5, 12, 22, world.rng)
		"boss_barrage":
			telegraph_kind = "barrage"
			telegraph_ticks = int(ab["duration"])
			world.particles.burst(x, y, [Color("#ff3355"), Color.WHITE],
				10, 2, 4, 10, 16, world.rng)

	Sfx.play("thunder" if ability_id == "boss_barrage" \
		else ("explosion" if ability_id == "shockwave" or ability_id == "acid_bomb" else "pickup"), x, y)
	if owner != null:
		world.stat.emit("abilityUses", 1, "add")
	return true

func _shockwave(world) -> void:
	var map = world.map
	var row: int = map.row_at(y)
	var col: int = map.col_at(x)
	var reach := int(ceilf(Cfg.SHOCKWAVE_R / float(Cfg.TILE)))
	for dr in range(-reach, reach + 1):
		for dc in range(-reach, reach + 1):
			var tx := float((col + dc) * Cfg.TILE) + Cfg.TILE * 0.5
			var ty := float((row + dr) * Cfg.TILE) + Cfg.TILE * 0.5
			var d := sqrt((tx - x) * (tx - x) + (ty - y) * (ty - y))
			if d > Cfg.SHOCKWAVE_R:
				continue
			var falloff: float = 1.0 - d / Cfg.SHOCKWAVE_R * 0.6
			world.hit_building(row + dr, col + dc,
				Cfg.SHOCKWAVE_TILE_DAMAGE * falloff, "blast", tx, ty, self)

	for other in world.tanks:
		if other == self or not other.alive or not world.are_hostile(self, other):
			continue
		var dx: float = other.x - x
		var dy: float = other.y - y
		var d := sqrt(dx * dx + dy * dy)
		if d > Cfg.SHOCKWAVE_R or d <= 0.001:
			continue
		var k: float = 1.0 - d / Cfg.SHOCKWAVE_R
		world.deal_damage(other, Cfg.SHOCKWAVE_DMG * k * dmg_scale, self, "blast")
		other.vx += (dx / d) * Cfg.SHOCKWAVE_PUSH * k
		other.vy += (dy / d) * Cfg.SHOCKWAVE_PUSH * k

	world.spawn_shockwave(x, y, Cfg.SHOCKWAVE_R, "shockwave", Color("#ff55ff"), 24)
	world.particles.burst(x, y, [Color("#ff55ff"), Color("#ffaaff"), Color.WHITE],
		30, 3, 7, 26, 52, world.rng)
	world.add_shake(9.0, x, y)

func _acid_bomb(world) -> void:
	for other in world.tanks:
		if other == self or not other.alive or not world.are_hostile(self, other):
			continue
		var dx: float = other.x - x
		var dy: float = other.y - y
		if dx * dx + dy * dy > Cfg.SHOCKWAVE_R * Cfg.SHOCKWAVE_R:
			continue
		other.apply_acid(world, self, dmg_scale, Cfg.ACID_BOMB_STACKS)

	world.spawn_shockwave(x, y, Cfg.SHOCKWAVE_R, "acid", Color("#84cc16"), 26)

	var spray_count := 36
	for i in spray_count:
		var ang: float = float(i) / float(spray_count) * TAU + (world.rng.nextf() - 0.5) * 0.2
		var spd: float = 3.2 + world.rng.nextf() * 3.0
		var col: Color = Color("#9dff5c") if (i % 2 == 0) else Color("#c4ff60")
		if i % 6 == 0:
			col = Color.WHITE
		world.particles.spawn(x, y, col, 3.5 + world.rng.nextf() * 2.5, 20.0 + world.rng.nextf() * 15.0,
			world.rng, cos(ang) * spd, sin(ang) * spd)

	world.particles.burst(x, y, [Color("#9dff5c"), Color("#4a7a2a"), Color.WHITE],
		30, 3, 7, 26, 52, world.rng)
	world.damage_number.emit(x, y - 32, "☣️ ЧУМНОЙ ШКВАЛ!", Color("#84cc16"))
	world.add_shake(9.0, x, y)
	Sfx.play("steam", x, y)
	Sfx.play("explosion", x, y)

func take_damage(world, amount: float, attacker, source: String) -> Dictionary:
	var result := {"applied": 0.0, "killed": false, "evaded": false, "reflected": 0.0}
	if not alive:
		return result
	if spawn_protect > 0 and not ENVIRONMENTAL.has(source):
		return result
	if dash_invuln_ticks > 0 and not ENVIRONMENTAL.has(source):
		result["evaded"] = true
		if world != null and "particles" in world and world.particles != null:
			world.particles.burst(x, y, [Color("#38bdf8"), Color.WHITE], 5, 2, 3, 10, 14, world.rng)
		return result

	if float(mods["evasionChance"]) > 0.0 and world.rng.nextf() < float(mods["evasionChance"]):
		result["evaded"] = true
		world.particles.burst(x, y, [Color("#00ffff"), Color("#aaffff")], 5, 2, 3, 10, 14, world.rng)
		return result

	var dmg := amount * float(mods["damageTakenMult"])
	if ability_active("bulwark"):
		dmg *= Cfg.BULWARK_DAMAGE_MULT
	if enrage_shield_ticks > 0:
		dmg *= Cfg.BOSS_PHASE3_SHIELD_MULT
	if rammer_daze_ticks > 0:
		dmg *= Cfg.RAMMER_DAZE_DMG_MULT
	if is_rammer_boss and (rammer_state == "charge" or rammer_state == "spin"):
		dmg *= 0.65

	if shield_hp > 0.0:
		var absorbed := minf(shield_hp, dmg)
		shield_hp -= absorbed
		dmg -= absorbed
		world.particles.burst(x, y, [Cfg.shield], 5, 2, 4, 12, 12, world.rng)
		if dmg <= 0.0:
			return result

	if float(mods["reflectFraction"]) > 0.0 and attacker != null and attacker.alive and source != "reflect":
		result["reflected"] = dmg * float(mods["reflectFraction"])

	hp -= dmg
	result["applied"] = dmg

	if hp <= 0.0:
		hp = 0.0
		result["killed"] = true
	return result

func apply_freeze(world, attacker, ticks: int) -> bool:
	if not alive or spawn_protect > 0:
		return false
	if shield_hp > 0.0:
		if world != null and world.particles != null:
			world.particles.burst(x, y, [Cfg.shield], 5, 2, 4, 12, 12, world.rng)
		return false
	if float(mods["evasionChance"]) > 0.0 and world != null and world.rng.nextf() < float(mods["evasionChance"]):
		if world.particles != null:
			world.particles.burst(x, y, [Color("#00ffff"), Color("#aaffff")], 5, 2, 3, 10, 14, world.rng)
		return false
	var duration_mult: float = float(attacker.mods["freezeDurationMult"]) if attacker != null else 1.0
	freeze_ticks = int(round(float(ticks) * duration_mult))
	freeze_max_ticks = freeze_ticks
	if attacker != null and float(attacker.mods["freezeDashTicks"]) > 0.0:
		attacker.turbo_timer = maxi(attacker.turbo_timer, int(attacker.mods["freezeDashTicks"]))

	# Приоритет CC_STASIS: принудительно прерывает любые действия и форсаж
	interrupt_current_action(CC_STASIS)

	if world != null and world.particles != null:
		world.particles.burst(x, y, [Color("#aaeeff"), Color.WHITE], 10, 2, 4, 12, 20, world.rng)
	return true

func apply_acid(world, attacker, dmg_scale_value: float, stacks: int = 1) -> bool:
	if not alive or spawn_protect > 0:
		return false
	if shield_hp > 0.0:
		world.particles.burst(x, y, [Cfg.shield], 5, 2, 4, 12, 12, world.rng)
		return false
	if float(mods["evasionChance"]) > 0.0 and world.rng.nextf() < float(mods["evasionChance"]):
		world.particles.burst(x, y, [Color("#00ffff"), Color("#aaffff")], 5, 2, 3, 10, 14, world.rng)
		return false
	acid_stacks = mini(Cfg.ACID_STACK_MAX, acid_stacks + stacks)
	acid_ticks_left = Cfg.ACID_DURATION_TICKS
	if acid_tick_timer <= 0:
		acid_tick_timer = Cfg.ACID_TICK_INTERVAL
	acid_dmg_scale = dmg_scale_value
	acid_attacker = attacker
	return true

func on_death(world, killer) -> void:
	alive = false
	deaths += 1
	interrupt_current_action(CC_DEAD)
	shield_hp = 0.0
	telegraph_ticks = 0
	enrage_shield_ticks = 0
	freeze_ticks = 0
	freeze_max_ticks = 0
	acid_stacks = 0
	acid_ticks_left = 0
	acid_tick_timer = 0
	acid_attacker = null
	acid_stream_hit_accum = 0.0
	rammer_cooldown_ticks = 0
	rammer_spin_cooldown = 0

	world.particles.burst(x, y, Cfg.explosion, 30, 3, 8, 20, 40, world.rng)
	Sfx.play("explosion", x, y)
	world.add_shake(6.0, x, y)

	if flags.has("kamikaze"):
		var r2 := Cfg.KAMIKAZE_R * Cfg.KAMIKAZE_R
		for other in world.tanks:
			if other == self or not other.alive:
				continue
			if not world.are_hostile(self, other):
				continue
			var dx: float = other.x - x
			var dy: float = other.y - y
			if dx * dx + dy * dy > r2:
				continue
			world.deal_damage(other, Cfg.KAMIKAZE_DMG, self, "kamikaze")
		world.particles.burst(x, y, Cfg.explosion, 40, 4, 8, 25, 45, world.rng)
		world.add_shake(15.0, x, y)

func respawn(nx: float, ny: float) -> void:
	x = nx
	y = ny
	vx = 0.0
	vy = 0.0
	alive = true
	hp = max_hp
	spawn_protect = Cfg.SPAWN_PROTECT * 2
	fire_cooldown = 0
	heat = 0.0
	overheated = false
	respawn_timer = 0
	stall_ticks = 0
	shield_hp = 0.0
	shield_cooldown = 0
	regen_accum = 0.0
	water_timer = 0
	in_water = false
	turbo_timer = 0
	shadow_timer = 0
	ability_timer = 0
	dash_range = 0.0
	dash_cooldown = 0
	dash_stall = 0
	weapon = ""
	weapon_timer = 0
	freeze_ticks = 0
	freeze_max_ticks = 0
	acid_stacks = 0
	acid_ticks_left = 0
	acid_tick_timer = 0
	acid_attacker = null
	last_attacker = null
	flag = null
	boss_phase = 1
	enrage_speed_mult = 1.0
	enrage_fire_rate_mult = 1.0
	chimera_cloak_timer = 0
	chimera_pool_timer = 0
	chimera_clones_spawned = false
	chimera_ambush_ready = false
	chimera_stream_active = false
	chimera_stream_timer = 0
	chimera_stream_cd = 0
	chimera_stream_warmup_ticks = 0
	acid_stream_hit_accum = 0.0
	rammer_state = "idle"
	rammer_telegraph_ticks = 0
	rammer_charge_ticks = 0
	rammer_cooldown_ticks = 0
	rammer_spin_ticks = 0
	rammer_spin_cooldown = 0
	rammer_spin_hit.clear()
	recompute()
	if brain != null:
		brain.reset()

func separate_from(other) -> void:
	var dx: float = x - other.x
	var dy: float = y - other.y
	var d := sqrt(dx * dx + dy * dy)
	var min_dist := Cfg.TANK_BODY_R * 0.9
	if d >= min_dist:
		return
	var nx: float
	var ny: float
	if d == 0.0:
		var a: float = float(id) * 2.399963229728653
		nx = cos(a)
		ny = sin(a)
	else:
		nx = dx / d
		ny = dy / d
	var push := ((min_dist - d) / min_dist) * 0.35
	vx += nx * push
	vy += ny * push
	other.vx -= nx * push
	other.vy -= ny * push
