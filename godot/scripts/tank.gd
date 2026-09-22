class_name Tank
extends RefCounted

const ENVIRONMENTAL := ["water", "lightning"]

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

var is_boss := false
var boss_phase := 1
var enrage_speed_mult := 1.0
var enrage_fire_rate_mult := 1.0
var enrage_shield_ticks := 0
var boss_stat_mult := 1.0
var telegraph_ticks := 0
var telegraph_kind := ""

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

var is_player_controlled: bool:
	get: return owner != null

var carrying_flag: bool:
	get: return flag != null

var can_fire: bool:
	get: return alive and fire_cooldown <= 0 and not overheated

func _update_heat(world) -> void:
	if owner == null:
		return
	if heat > 0.0:
		heat = maxf(0.0, heat - Cfg.HEAT_COOL * float(mods["heatCoolMult"]))
	if overheated:
		if world.tick % 5 == 0:
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
	if next_ability != ability_id:
		ability_timer = 0
		ability_id = next_ability
	if not upgrade_mods.is_empty():
		mods = _apply_upgrade_mods(mods)
	max_hp = maxf(1.0, round(base_max_hp * float(mods["maxHPMult"])))
	speed = base_speed * float(mods["speedMult"]) * enrage_speed_mult
	fire_rate = maxi(4, int(round(float(base_fire_rate) * float(mods["fireRateMult"]) * enrage_fire_rate_mult)))
	hp = clampf(round(max_hp * hp_ratio), 1.0, max_hp)
	if not flags.has("shield"):
		shield_hp = 0.0

func thrust(dx: float, dy: float) -> void:
	if dx == 0.0 and dy == 0.0:
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
	turret_angle = atan2(ty - y, tx - x)

func slew_turret_to(target: float) -> void:
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
	if freeze_ticks > 0:
		freeze_ticks -= 1
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
				world.deal_damage(self, tick_dmg, acid_attacker, "acid")
				if acid_stacks >= Cfg.ACID_STACK_MAX and acid_attacker != null \
						and acid_attacker.alive and acid_attacker.flags.has("acidCloud"):
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

	if freeze_ticks <= 0:
		if owner != null:
			owner.control(self, world)
		elif brain != null:
			brain.update(self, world)

	if dash_range > 0.0:
		var boost := speed * Cfg.DASH_SPEED_MULT
		vx = cos(angle) * boost
		vy = sin(angle) * boost

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
	_check_water(world)
	_try_ram(world)

	vx *= Cfg.FRICTION
	vy *= Cfg.FRICTION

	body_angle = Rng.rotate_toward(body_angle, angle,
		absf(angle - body_angle) * BODY_TURN_RATE + 0.02)

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
		return false
	fire_cooldown = reload_ticks()
	_after_shot()

	var muzzle_x := x + cos(turret_angle) * muzzle_len
	var muzzle_y := y + sin(turret_angle) * muzzle_len
	var scale_v := dmg_scale

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
	var n := Cfg.BOSS_BARRAGE_BULLETS
	for i in n:
		var off := (float(i) - float(n - 1) * 0.5) * Cfg.BOSS_BARRAGE_SPREAD * 2.0 / float(n - 1)
		world.bullets.append(Ent.Bullet.new(muzzle_x, muzzle_y, turret_angle + off,
			self, Cfg.BOSS_BARRAGE_DMG_SCALE * dmg_scale))
	world.particles.burst(muzzle_x, muzzle_y, [Color("#ff3355"), Color("#ffaa33")], 14, 3, 6, 14, 24, world.rng)
	world.add_shake(5.0, muzzle_x, muzzle_y)
	Sfx.play("shoot_heavy", muzzle_x, muzzle_y)

func place_mine(world) -> bool:
	if not flags.has("mines") or mine_cooldown > 0:
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

func dash() -> bool:
	if not alive or dash_cooldown > 0 or dash_range > 0.0:
		return false
	dash_cooldown = Cfg.DASH_COOLDOWN
	dash_range = Cfg.DASH_DISTANCE
	dash_stall = 0
	var boost := speed * Cfg.DASH_SPEED_MULT
	vx = cos(angle) * boost
	vy = sin(angle) * boost
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
	if not alive or ability_id == "" or ability_cd > 0:
		return false
	var ab := Abilities.get_ability(ability_id)
	if ab.is_empty():
		return false

	ability_cd = int(ab["cooldown"])
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
	world.particles.burst(x, y, [Color("#9dff5c"), Color("#4a7a2a"), Color.WHITE],
		30, 3, 7, 26, 52, world.rng)
	world.add_shake(9.0, x, y)

func take_damage(world, amount: float, attacker, source: String) -> Dictionary:
	var result := {"applied": 0.0, "killed": false, "evaded": false, "reflected": 0.0}
	if not alive:
		return result
	if spawn_protect > 0 and not ENVIRONMENTAL.has(source):
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
		world.particles.burst(x, y, [Cfg.shield], 5, 2, 4, 12, 12, world.rng)
		return false
	if float(mods["evasionChance"]) > 0.0 and world.rng.nextf() < float(mods["evasionChance"]):
		world.particles.burst(x, y, [Color("#00ffff"), Color("#aaffff")], 5, 2, 3, 10, 14, world.rng)
		return false
	var duration_mult: float = float(attacker.mods["freezeDurationMult"]) if attacker != null else 1.0
	freeze_ticks = int(round(float(ticks) * duration_mult))
	if attacker != null and float(attacker.mods["freezeDashTicks"]) > 0.0:
		attacker.turbo_timer = maxi(attacker.turbo_timer, int(attacker.mods["freezeDashTicks"]))
	vx = 0.0
	vy = 0.0
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
	vx = 0.0
	vy = 0.0
	shield_hp = 0.0
	turbo_timer = 0
	shadow_timer = 0
	ability_timer = 0
	dash_range = 0.0
	telegraph_ticks = 0
	enrage_shield_ticks = 0
	freeze_ticks = 0
	acid_stacks = 0
	acid_ticks_left = 0
	acid_tick_timer = 0
	acid_attacker = null

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
	acid_stacks = 0
	acid_ticks_left = 0
	acid_tick_timer = 0
	acid_attacker = null
	last_attacker = null
	flag = null
	boss_phase = 1
	enrage_speed_mult = 1.0
	enrage_fire_rate_mult = 1.0
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
