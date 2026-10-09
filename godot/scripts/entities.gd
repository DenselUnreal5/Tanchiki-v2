class_name Ent
extends RefCounted

const MAX_PARTICLES := 1200

class ParticleSystem extends RefCounted:
	var max_count: int
	var px := PackedFloat32Array()
	var py := PackedFloat32Array()
	var vx := PackedFloat32Array()
	var vy := PackedFloat32Array()
	var size := PackedFloat32Array()
	var life := PackedFloat32Array()
	var max_life := PackedFloat32Array()
	var color: Array = []
	var count := 0

	func _init(max_value: int = 1200) -> void:
		max_count = max_value
		px.resize(max_value)
		py.resize(max_value)
		vx.resize(max_value)
		vy.resize(max_value)
		size.resize(max_value)
		life.resize(max_value)
		max_life.resize(max_value)
		color.resize(max_value)
		color.fill(Color.WHITE)

	func clear() -> void:
		count = 0

	func spawn(x: float, y: float, col: Color, sz: float, lf: float, rng: Rng,
			vx_bias: float = 0.0, vy_bias: float = 0.0) -> void:
		var i := 0
		if count < max_count:
			i = count
			count += 1
		else:
			var worst := 0
			var worst_life := INF
			var k := 0
			while k < max_count:
				if life[k] < worst_life:
					worst_life = life[k]
					worst = k
				k += 7
			i = worst
		px[i] = x
		py[i] = y
		vx[i] = (rng.nextf() - 0.5) * 4.0 + vx_bias
		vy[i] = (rng.nextf() - 0.5) * 4.0 + vy_bias
		size[i] = sz
		life[i] = lf
		max_life[i] = lf
		color[i] = col

	func burst(x: float, y: float, colors: Array, amount: int, size_min: float,
			size_max: float, life_min: float, life_max: float, rng: Rng) -> void:
		for i in amount:
			spawn(x, y,
				colors[int(rng.nextf() * colors.size()) % colors.size()],
				size_min + rng.nextf() * (size_max - size_min),
				life_min + rng.nextf() * (life_max - life_min),
				rng)

	func update() -> void:
		var w := 0
		for i in count:
			var lf := life[i] - 1.0
			if lf <= 0.0:
				continue
			px[w] = px[i] + vx[i]
			py[w] = py[i] + vy[i]
			vx[w] = vx[i] * 0.95
			vy[w] = vy[i] * 0.95
			size[w] = size[i]
			life[w] = lf
			max_life[w] = max_life[i]
			color[w] = color[i]
			w += 1
		count = w

class Bullet extends RefCounted:
	var x: float
	var y: float
	var vx: float
	var vy: float
	var owner
	var team: String
	var alive := true
	var life := Cfg.BULLET_LIFE
	var dmg_scale: float
	var pierce := 0
	var explosive := false
	var splash_r: float = Cfg.EXPLOSIVE_R
	var keep_bricks := false
	var from_player := false
	var lobbed := false
	var cannon_kind := ""
	var sky_strike := false
	var acid_burst := false

	func _init(x_: float, y_: float, angle: float, owner_, dmg_scale_: float = 1.0) -> void:
		x = x_
		y = y_
		owner = owner_
		if owner_ == null:
			var sp := Cfg.BULLET_SPEED
			vx = cos(angle) * sp
			vy = sin(angle) * sp
			return
		var speed: float = Cfg.BULLET_SPEED * float(owner_.mods["bulletSpeedMult"])
		if owner_.weapon == "" and (owner_.cannon_id == "" or owner_.cannon_id == "standard"):
			speed *= 1.15
		vx = cos(angle) * speed
		vy = sin(angle) * speed
		team = owner_.team
		dmg_scale = dmg_scale_ * float(owner_.mods["dmgMult"])
		pierce = 1 if owner_.flags.has("piercing") else 0
		explosive = owner_.flags.has("explosive")
		keep_bricks = owner_.flags.has("keepBricks")
		from_player = owner_.owner != null

	func update(world) -> void:
		if not alive:
			return
		x += vx
		y += vy

		if lobbed:
			life -= 1
			if life <= 0:
				_explode(world, null, Cfg.BULLET_DMG_MAX * dmg_scale)
				alive = false
				return
			if x < 0.0 or x > world.map.width or y < 0.0 or y > world.map.height:
				alive = false
				return
			if _hit_barrels(world):
				return
			_hit_tanks(world)
			return

		life -= 1
		if life <= 0:
			alive = false
			return
		if x < 0.0 or x > world.map.width or y < 0.0 or y > world.map.height:
			alive = false
			return
		if _hit_tiles(world):
			return
		if _hit_barrels(world):
			return
		_hit_tanks(world)

	func _hit_tiles(world) -> bool:
		var map: GameMap = world.map
		var row := map.row_at(y)
		var col := map.col_at(x)
		var tile := map.get_tile(row, col)

		if tile == Cfg.T_WALL:
			if pierce > 0:
				pierce -= 1
				return not _pierce_through(world)
			alive = false
			world.particles.burst(x, y, [Color("#888888"), Color("#aaaaaa")], 8, 2, 4, 10, 20, world.rng)
			return true

		if tile == Cfg.T_BRICK:
			if keep_bricks:
				alive = false
				world.hit_building(row, col, 0.0, "bullet", x, y, owner)
				return true
			var dmg := (Cfg.BULLET_DMG_MIN + Cfg.BULLET_DMG_MAX) * 0.5 * dmg_scale
			world.hit_building(row, col, dmg, "bullet", x, y, owner)
			if owner != null and owner.flags.has("woodPierce") 					and String(Materials.at(row, col)["id"]) == "wood":
				return false
			if owner != null and owner.ability_active("breaker"):
				return false
			if pierce > 0:
				pierce -= 1
				return not _pierce_through(world)
			alive = false
			return true

		if tile == Cfg.T_TREE:
			map.set_tile(row, col, Cfg.T_EMPTY)
			world.particles.burst(x, y, [Cfg.tree, Cfg.tree_dark], 8, 2, 4, 10, 20, world.rng)
		return false

	func _pierce_through(world) -> bool:
		var map: GameMap = world.map
		var length := sqrt(vx * vx + vy * vy)
		if length == 0.0:
			length = 1.0
		var step_x := (vx / length) * 4.0
		var step_y := (vy / length) * 4.0
		var max_steps := int(ceil(float(Cfg.TILE * 2) / 4.0))
		for i in max_steps:
			x += step_x
			y += step_y
			if x < 0.0 or x > map.width or y < 0.0 or y > map.height:
				break
			var tile := map.get_tile(map.row_at(y), map.col_at(x))
			if tile != Cfg.T_WALL and tile != Cfg.T_BRICK:
				world.particles.burst(x, y, [Color("#ffddaa"), Color("#888888")], 6, 2, 3, 8, 14, world.rng)
				return true
		alive = false
		return false

	const HIT_QUERY_RADIUS := 40.0

	func _hit_tanks(world) -> bool:
		for tank in world.tank_grid.query(x, y, HIT_QUERY_RADIUS):
			if tank == owner or not tank.alive:
				continue
			if not world.are_hostile(owner, tank):
				continue
			var dx: float = tank.x - x
			var dy: float = tank.y - y
			var hit_r2: float = tank.hit_r * tank.hit_r
			if dx * dx + dy * dy > hit_r2:
				continue

			if cannon_kind == "freeze":
				if tank.apply_freeze(world, owner, Cfg.ICE_FREEZE_TICKS):
					world.maybe_freeze_shot_kill(tank, owner)
				alive = false
				world.particles.burst(x, y, [Color("#aaeeff"), Color.WHITE], 8, 2, 4, 10, 20, world.rng)
				return true
			if cannon_kind == "" and Mutators.cryo_ticks() > 0 and tank.cryo_immunity_ticks <= 0 and tank.freeze_ticks <= 0:
				if tank.apply_freeze(world, null, Mutators.cryo_ticks()):
					tank.cryo_immunity_ticks = Cfg.MUT_CRYO_IMMUNITY_TICKS
			if cannon_kind == "acid":
				var stacks := 5 if acid_burst else 1
				tank.apply_acid(world, owner, dmg_scale, stacks)
				alive = false
				if acid_burst:
					world.particles.burst(x, y, [Color("#84cc16"), Color("#a3e635"), Color.WHITE], 16, 2, 5, 14, 28, world.rng)
					world.spawn_shockwave(x, y, 60.0, "acid", Color("#84cc16"), 18)
				else:
					world.particles.burst(x, y, [Color("#9dff5c"), Color("#4a7a2a")], 8, 2, 4, 10, 20, world.rng)
				return true

			var amount: float = (Cfg.BULLET_DMG_MIN + world.rng.nextf() \
				* (Cfg.BULLET_DMG_MAX - Cfg.BULLET_DMG_MIN)) * dmg_scale
			if owner != null and owner.is_boss:
				amount = minf(amount, tank.max_hp * Cfg.BOSS_HIT_CAP_FRACTION)
			world.deal_damage(tank, amount, owner, "bullet")

			if explosive:
				_explode(world, tank, amount)

			if sky_strike:
				world.strike_lightning(x, y, owner)

			alive = false
			world.particles.burst(x, y, [Color("#ff8833"), Color("#ffee55")], 8, 2, 4, 10, 20, world.rng)
			return true
		return false

	func _hit_barrels(world) -> bool:
		if world == null or not ("barrels" in world) or world.barrels.is_empty():
			return false
		for barrel in world.barrels:
			if not barrel.alive:
				continue
			var dx: float = barrel.x - x
			var dy: float = barrel.y - y
			var hit_r: float = barrel.radius + 6.0
			if dx * dx + dy * dy <= hit_r * hit_r:
				var amount: float = (Cfg.BULLET_DMG_MIN + world.rng.nextf() * (Cfg.BULLET_DMG_MAX - Cfg.BULLET_DMG_MIN)) * dmg_scale
				barrel.hit(amount, owner, world)
				alive = false
				world.particles.burst(x, y, [Color("#ff8833"), Color("#ffee55")], 6, 2, 4, 8, 16, world.rng)
				return true
		return false

	func _explode(world, direct_target, base_damage: float) -> void:
		var r := splash_r
		var r2 := r * r
		for other in world.tank_grid.query(x, y, r):
			if other == direct_target or other == owner or not other.alive:
				continue
			if not world.are_hostile(owner, other):
				continue
			var dx: float = other.x - x
			var dy: float = other.y - y
			if dx * dx + dy * dy > r2:
				continue
			world.deal_damage(other, base_damage * Cfg.EXPLOSIVE_SPLASH, owner, "bullet")
		var map: GameMap = world.map
		var row := map.row_at(y)
		var col := map.col_at(x)
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				if map.get_tile(row + dr, col + dc) != Cfg.T_BRICK:
					continue
				var falloff := 1.0 if (dr == 0 and dc == 0) else 0.5
				world.hit_building(row + dr, col + dc, Cfg.BLAST_TILE_DAMAGE * falloff, "blast",
					(col + dc) * Cfg.TILE + Cfg.TILE * 0.5,
					(row + dr) * Cfg.TILE + Cfg.TILE * 0.5, owner)
		world.particles.burst(x, y, Cfg.explosion, 12, 2, 4, 10, 18, world.rng)
		world.add_shake(8.0, x, y)

class Mine extends RefCounted:
	var x: float
	var y: float
	var owner
	var team: String
	var timer: int
	var alive := true
	var armed: bool
	var arming_ticks: int = 0

	func _init(x_: float, y_: float, owner_, life: int) -> void:
		x = x_
		y = y_
		owner = owner_
		team = owner_.team if owner_ != null else "neutral"
		timer = life
		armed = owner_ == null

	func update(world) -> void:
		timer -= 1
		if timer <= 0:
			alive = false
			return
		if arming_ticks > 0:
			arming_ticks -= 1
			return
		if owner != null and not armed:
			var d := Vector2(x - owner.x, y - owner.y).length()
			if d > Cfg.MINE_TRIGGER_R + 8.0:
				armed = true

		var trigger_r2 := Cfg.MINE_TRIGGER_R * Cfg.MINE_TRIGGER_R
		for tank in world.tanks:
			if not tank.alive or tank == owner:
				continue
			if owner != null and not world.are_hostile(owner, tank):
				continue
			var dx: float = tank.x - x
			var dy: float = tank.y - y
			if dx * dx + dy * dy > trigger_r2:
				continue
			_detonate(world, tank)
			return

	func _detonate(world, direct) -> void:
		world.deal_damage(direct, Cfg.MINE_DMG, owner, "mine")
		var splash_r2 := Cfg.MINE_SPLASH_R * Cfg.MINE_SPLASH_R
		for tank in world.tanks:
			if tank == direct or tank == owner or not tank.alive:
				continue
			if owner != null and not world.are_hostile(owner, tank):
				continue
			var dx: float = tank.x - x
			var dy: float = tank.y - y
			if dx * dx + dy * dy > splash_r2:
				continue
			world.deal_damage(tank, Cfg.MINE_SPLASH_DMG, owner, "mine")
		var map: GameMap = world.map
		var row := map.row_at(y)
		var col := map.col_at(x)
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				if map.get_tile(row + dr, col + dc) != Cfg.T_BRICK:
					continue
				var falloff := 1.0 if (dr == 0 and dc == 0) else 0.55
				world.hit_building(row + dr, col + dc, Cfg.MINE_TILE_DAMAGE * falloff, "blast",
					(col + dc) * Cfg.TILE + Cfg.TILE * 0.5,
					(row + dr) * Cfg.TILE + Cfg.TILE * 0.5, owner)
		world.particles.burst(x, y, Cfg.explosion, 25, 3, 7, 20, 35, world.rng)
		world.add_shake(10.0, x, y)
		Sfx.play("explosion", x, y)
		alive = false

class StrikeRocket extends RefCounted:
	var x: float
	var y: float
	var target
	var owner
	var alive := true
	var speed := 16.0
	var vx := 0.0
	var vy := 1.0
	var trail_timer := 0

	func _init(target_, owner_, world) -> void:
		target = target_
		owner = owner_
		x = target_.x + (world.rng.nextf() - 0.5) * 300.0
		y = -80.0

	func update(world) -> void:
		if not alive:
			return
		if target == null or not target.alive:
			alive = false
			world.particles.burst(x, y, [Color("#ff9933"), Color("#888888")], 6, 2, 3, 8, 14, world.rng)
			return
		var dx: float = target.x - x
		var dy: float = target.y - y
		var length := sqrt(dx * dx + dy * dy)
		if length < 26.0:
			var dmg: float = Cfg.AIRSTRIKE_DMG + roundf(target.max_hp * Cfg.AIRSTRIKE_MAX_HP_FRACTION)
			world.deal_damage(target, dmg, owner, "airstrike")
			world.particles.burst(x, y, Cfg.explosion, 16, 2, 5, 12, 24, world.rng)
			world.add_shake(8.0, x, y)
			Sfx.play("explosion", x, y)
			alive = false
			return
		vx = (dx / length) * speed
		vy = (dy / length) * speed
		x += vx
		y += vy
		trail_timer += 1
		if trail_timer % 2 == 0:
			world.particles.spawn(x - vx * 2.0, y - vy * 2.0, Color("#ffcc44"), 2.5, 12, world.rng)


class Debris extends RefCounted:
	var x: float
	var y: float
	var vx: float
	var vy: float
	var angle: float
	var spin: float
	var w: float
	var h: float
	var color: Color
	var life: float
	var max_life: float
	var alive := true

	func _init(px: float, py: float, mat: Dictionary, rng: Rng) -> void:
		x = px
		y = py
		var a := rng.nextf() * TAU
		var speed_range: Vector2 = mat["speed"]
		var speed := speed_range.x + rng.nextf() * (speed_range.y - speed_range.x)
		vx = cos(a) * speed
		vy = sin(a) * speed
		angle = rng.nextf() * TAU
		spin = (rng.nextf() - 0.5) * 2.0 * float(mat["spin"])
		var wr: Vector2 = mat["piece_w"]
		var hr: Vector2 = mat["piece_h"]
		w = wr.x + rng.nextf() * (wr.y - wr.x)
		h = hr.x + rng.nextf() * (hr.y - hr.x)
		var shade := rng.nextf()
		color = mat["dark"] if shade < 0.4 else (mat["base"] if shade < 0.8 else mat["light"])
		var lr: Vector2 = mat["life"]
		max_life = lr.x + rng.nextf() * (lr.y - lr.x)
		life = max_life

	func update() -> void:
		life -= 1.0
		if life <= 0.0:
			alive = false
			return
		x += vx
		y += vy
		angle += spin
		vx *= 0.90
		vy *= 0.90
		spin *= 0.92

	var fade: float:
		get: return clampf(life / maxf(1.0, max_life * 0.25), 0.0, 1.0)


class Wreck extends RefCounted:
	var x: float
	var y: float
	var angle: float
	var color_key: String
	var turret_offset: Vector2
	var turret_angle: float
	var scale: float
	var life: int
	var timer: int
	var alive := true

	func _init(tank, rng: Rng) -> void:
		x = tank.x
		y = tank.y
		angle = tank.body_angle
		color_key = tank.color_key
		scale = 1.6 if (not tank.enemy_type.is_empty() and bool(tank.enemy_type.get("boss", false))) else 1.0
		var a := rng.nextf() * TAU
		var d := 10.0 + rng.nextf() * 8.0
		turret_offset = Vector2(cos(a) * d, sin(a) * d) * scale
		turret_angle = rng.nextf() * TAU
		life = Cfg.WRECK_LIFE
		timer = life

	var fade: float:
		get: return clampf(float(timer) / maxf(1.0, float(Cfg.WRECK_FADE)), 0.0, 1.0)

	func update(world) -> void:
		timer -= 1
		if timer <= 0:
			alive = false
			return
		var t := float(timer) / float(life)
		var rng: Rng = world.rng
		if world.tick % 4 == 0 and rng.nextf() < 0.35 + t * 0.5:
			var c: Color = Cfg.explosion[int(rng.nextf() * 2.0) % 2]
			world.particles.spawn(
				x + (rng.nextf() - 0.5) * 14.0 * scale,
				y + (rng.nextf() - 0.5) * 12.0 * scale,
				c, 2.0 + rng.nextf() * 2.5 * scale, 16.0 + rng.nextf() * 14.0,
				rng, 0.0, -1.3)
		if world.tick % 7 == 0:
			world.particles.spawn(
				x + (rng.nextf() - 0.5) * 10.0 * scale,
				y - 4.0,
				Color(0.24, 0.23, 0.22), 3.0 + rng.nextf() * 3.0 * scale,
				26.0 + rng.nextf() * 20.0, rng, -0.2, -0.9)

class Pickup extends RefCounted:
	var x: float
	var y: float
	var type: String
	var active := true
	var respawn_timer := 0
	var bob := 0.0

	func _init(x_: float, y_: float, type_: String = "health", rng: Rng = null) -> void:
		x = x_
		y = y_
		type = type_
		bob = (rng.nextf() if rng != null else randf()) * TAU

	func consume() -> void:
		active = false
		respawn_timer = Cfg.PICKUP_RESPAWN

const PERK_DROP_LIFE := 60 * 60

class PerkPickup extends RefCounted:
	var x: float
	var y: float
	var perk_id: String
	var active := true
	var life := 60 * 60
	var bob := 0.0

	func _init(x_: float, y_: float, perk_id_: String, rng: Rng = null) -> void:
		x = x_
		y = y_
		perk_id = perk_id_
		bob = (rng.nextf() if rng != null else randf()) * TAU

	func update() -> void:
		if active:
			life -= 1
			if life <= 0:
				active = false

const WEAPON_PICKUP_LIFE := 60 * 25

class WeaponPickup extends RefCounted:
	var x: float
	var y: float
	var weapon_id: String
	var active := true
	var life := 60 * 25
	var bob := 0.0

	func _init(x_: float, y_: float, weapon_id_: String, rng: Rng = null) -> void:
		x = x_
		y = y_
		weapon_id = weapon_id_
		bob = (rng.nextf() if rng != null else randf()) * TAU

	func update() -> void:
		if active:
			life -= 1
			if life <= 0:
				active = false

class Flag extends RefCounted:
	var home_x: float
	var home_y: float
	var x: float
	var y: float
	var team: String
	var state := "home"
	var carrier = null
	var return_timer := 0

	func _init(x_: float, y_: float, team_: String) -> void:
		home_x = x_
		home_y = y_
		x = x_
		y = y_
		team = team_

	var carried: bool:
		get: return state == "carried"

	var at_home: bool:
		get: return state == "home"

	func pick_up(tank) -> void:
		carrier = tank
		state = "carried"
		return_timer = 0

	func return_home() -> void:
		x = home_x
		y = home_y
		carrier = null
		state = "home"
		return_timer = 0

	func drop(x_: float, y_: float, timeout: int) -> void:
		carrier = null
		if Vector2(x_ - home_x, y_ - home_y).length() < 32.0:
			return_home()
			return
		x = x_
		y = y_
		state = "dropped"
		return_timer = timeout

class AcidPool extends RefCounted:
	var x: float
	var y: float
	var radius: float
	var owner
	var timer: int
	var max_life: int
	var alive := true

	func _init(x_: float, y_: float, r_: float, owner_, life: int) -> void:
		x = x_
		y = y_
		radius = r_
		owner = owner_
		timer = life
		max_life = life


class ExplosiveBarrel extends RefCounted:
	var x: float
	var y: float
	var radius: float = 14.0
	var hp: float = 20.0
	var max_hp: float = 20.0
	var alive: bool = true
	var flash_timer: int = 0
	var ignited: bool = false
	var fuse_timer: int = 0
	var last_attacker = null

	func _init(x_: float, y_: float) -> void:
		x = x_
		y = y_
		hp = 20.0
		max_hp = 20.0
		alive = true
		flash_timer = 0
		ignited = false
		fuse_timer = 0
		last_attacker = null

	func hit(amount: float, attacker, world) -> void:
		if not alive:
			return
		last_attacker = attacker
		hp -= amount
		flash_timer = 5
		if hp <= 0.0:
			explode(world)

	func ignite(attacker, world, fuse_ticks: int = 12) -> void:
		if not alive or ignited:
			return
		ignited = true
		last_attacker = attacker
		fuse_timer = fuse_ticks

	func update(world) -> void:
		if not alive:
			return
		if flash_timer > 0:
			flash_timer -= 1
		if ignited:
			flash_timer = 3
			fuse_timer -= 1
			if world != null:
				world.particles.spawn(x + (world.rng.nextf() - 0.5) * 8.0, y - 10.0,
					Color("#f97316"), 2.5, 8.0, world.rng, 0.0, -1.5)
			if fuse_timer <= 0:
				explode(world)

	func explode(world) -> void:
		if not alive:
			return
		alive = false
		if world == null:
			return
		if last_attacker != null and last_attacker.owner != null:
			world.stat.emit("barrelsExploded", 1, "add")

		var exp_r := 120.0
		var exp_r2 := exp_r * exp_r
		var base_dmg := 65.0

		# 1. Shockwaves, particles, audio, camera shake, scorches
		world.spawn_shockwave(x, y, exp_r, "blast", Color("#f97316"), 22)
		world.spawn_shockwave(x, y, exp_r * 0.5, "blast", Color("#fbbf24"), 16)
		world.particles.burst(x, y, [Color("#ef4444"), Color("#f97316"), Color("#fbbf24"), Color("#334155"), Color.WHITE], 42, 3, 7, 16, 36, world.rng)
		Sfx.play("explosion", x, y)
		world.add_shake(12.0, x, y)
		world.scorches.append(Vector2(x, y))
		while world.scorches.size() > Cfg.MAX_SCORCH:
			world.scorches.pop_front()

		# 2. Damage tanks and impulse knockback
		for tank in world.tanks:
			if not tank.alive:
				continue
			var dx: float = tank.x - x
			var dy: float = tank.y - y
			var d2: float = dx * dx + dy * dy
			if d2 > exp_r2:
				continue
			var dist: float = sqrt(d2)
			var falloff: float = 1.0 - (dist / exp_r) * 0.65
			var dmg: float = base_dmg * falloff
			world.deal_damage(tank, dmg, last_attacker, "barrel_blast")
			# Knockback impulse
			var push_mag: float = 3.8 * falloff
			var nx: float = dx / maxf(1.0, dist)
			var ny: float = dy / maxf(1.0, dist)
			tank.vx += nx * push_mag
			tank.vy += ny * push_mag

		# 3. Destroy nearby walls and trees in 80px radius
		var map: GameMap = world.map
		var tr_min: int = maxi(0, map.row_at(y - 80.0))
		var tr_max: int = mini(map.rows - 1, map.row_at(y + 80.0))
		var tc_min: int = maxi(0, map.col_at(x - 80.0))
		var tc_max: int = mini(map.cols - 1, map.col_at(x + 80.0))
		for r in range(tr_min, tr_max + 1):
			for c in range(tc_min, tc_max + 1):
				var tile: int = map.get_tile(r, c)
				if tile == Cfg.T_BRICK or tile == Cfg.T_TREE:
					var bx: float = c * Cfg.TILE + Cfg.TILE * 0.5
					var by: float = r * Cfg.TILE + Cfg.TILE * 0.5
					if Vector2(x - bx, y - by).length() <= 80.0:
						world.hit_building(r, c, 100.0, "blast", bx, by, last_attacker)

		# 4. Chain react with other barrels in radius
		for other_barrel in world.barrels:
			if other_barrel == self or not other_barrel.alive:
				continue
			var bdist: float = Vector2(x - other_barrel.x, y - other_barrel.y).length()
			if bdist <= exp_r:
				other_barrel.ignite(last_attacker, world, 4 + int(world.rng.nextf() * 6.0))


class PowerGenerator extends RefCounted:
	var x: float
	var y: float
	var radius: float = 24.0
	var aura_radius: float = 110.0
	var capture_progress: float = 0.0 # 0.0 .. 1.0
	var capturing_team: String = ""
	var captured_team: String = ""
	var cooldown: int = 0
	var max_cooldown: int = 1200 # 20 sec cooldown
	var anim_rot: float = 0.0
	var pulse_phase: float = 0.0

	func _init(x_: float, y_: float) -> void:
		x = x_
		y = y_
		radius = 24.0
		aura_radius = 110.0
		capture_progress = 0.0
		capturing_team = ""
		captured_team = ""
		cooldown = 0
		max_cooldown = 1200
		anim_rot = 0.0
		pulse_phase = 0.0

	func update(world) -> void:
		anim_rot += 0.03
		pulse_phase += 0.05

		if cooldown > 0:
			cooldown -= 1
			capture_progress = 0.0
			capturing_team = ""
			if cooldown % 60 == 0 and world != null:
				world.particles.spawn(x + (world.rng.nextf() - 0.5) * 16.0, y - 8.0,
					Color("#94a3b8"), 2.0, 14.0, world.rng, 0.0, -0.8)
			return

		if world == null:
			return

		# Detect tanks within aura
		var r2: float = aura_radius * aura_radius
		var teams_present := {}
		for tank in world.tanks:
			if not tank.alive:
				continue
			var dx: float = tank.x - x
			var dy: float = tank.y - y
			if dx * dx + dy * dy <= r2:
				teams_present[tank.team] = true

		if teams_present.size() == 1:
			var active_team: String = String(teams_present.keys()[0])
			if capturing_team != active_team:
				capturing_team = active_team
				capture_progress = 0.0
			capture_progress += Mutators.emp_charge_scale() / 180.0
			# Spark particles
			if world.tick % 8 == 0:
				world.particles.burst(x, y, [Color("#38bdf8"), Color("#818cf8"), Color.WHITE], 3, 1.5, 3.5, 8, 14, world.rng)
			if capture_progress >= 1.0:
				discharge(world, active_team)
		elif teams_present.is_empty():
			capture_progress = maxf(0.0, capture_progress - 0.005)

	func discharge(world, team: String) -> void:
		cooldown = int(float(max_cooldown) / Mutators.emp_charge_scale())
		for t in world.tanks:
			if t.owner != null and t.team == team:
				world.stat.emit("empDischarged", 1, "add")
				break
		captured_team = team
		capture_progress = 0.0
		capturing_team = ""

		var emp_r := 230.0
		var emp_r2 := emp_r * emp_r
		world.spawn_shockwave(x, y, emp_r, "emp", Color("#38bdf8"), 32)
		world.spawn_shockwave(x, y, emp_r * 0.6, "emp", Color("#06b6d4"), 22)
		world.particles.burst(x, y, [Color("#38bdf8"), Color("#818cf8"), Color("#06b6d4"), Color.WHITE], 48, 2.5, 6.0, 20, 38, world.rng)
		world.add_shake(15.0, x, y)
		Sfx.play("laser", x, y)
		Sfx.play("shield")

		world.feed.emit("⚡ Генератор поля разряжен! ЭМИ-волна поразила противников!", Color("#38bdf8"))

		for tank in world.tanks:
			if not tank.alive:
				continue
			var dx: float = tank.x - x
			var dy: float = tank.y - y
			if dx * dx + dy * dy > emp_r2:
				continue
			var is_foe: bool = (tank.team != team)
			if is_foe:
				tank.stun_ticks = maxi(tank.stun_ticks, 150)
				tank.interrupt_current_action(Tank.CC_STUN)
				world.deal_damage(tank, 30.0, null, "emp")
				world.damage_number.emit(tank.x, tank.y - 20, "⚡ EMP STUN!", Color("#38bdf8"))
				world.particles.burst(tank.x, tank.y, [Color("#38bdf8"), Color.WHITE], 12, 2, 4, 10, 18, world.rng)
			else:
				# Ally buff: instant cooldown reset + 50 shield
				tank.flags["shield"] = true
				tank.shield_hp = minf(50.0, tank.shield_hp + 50.0)
				tank.fire_cooldown = 0
				tank.ability_cd = maxi(0, tank.ability_cd - 300)
				world.damage_number.emit(tank.x, tank.y - 20, "⚡ SHIELD +50", Color("#34d399"))
				world.particles.burst(tank.x, tank.y, [Color("#34d399"), Color("#6ee7b7"), Color.WHITE], 10, 2, 4, 10, 18, world.rng)


