# ============================================================================
# entities.gd — снаряды, мины, аптечки, флаги и частицы.
#
# Частицы живут в пуле с жёстким лимитом: каждый взрыв создаёт 30–50 частиц,
# и в замесе на 22 бота без лимита массив раздувается до десятков тысяч.
#
# Все классы — внутренние, обращение через Ent.Bullet, Ent.Mine и т.д.
# Ссылки на Tank/World намеренно нетипизированы: иначе получается циклическая
# зависимость между скриптами.
# ============================================================================
class_name Ent
extends RefCounted

const MAX_PARTICLES := 1200

# ---------------------------------------------------------------------------
# Частицы
# ---------------------------------------------------------------------------
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

	## Добавляет частицу. При переполнении пула затирает самую старую.
	## vx_bias/vy_bias сдвигают случайную скорость в нужную сторону: огонь и
	## дым должны подниматься вверх, а не разлетаться во все стороны.
	func spawn(x: float, y: float, col: Color, sz: float, lf: float, rng: Rng,
			vx_bias: float = 0.0, vy_bias: float = 0.0) -> void:
		var i := 0
		if count < max_count:
			i = count
			count += 1
		else:
			# Ищем самую «дожившую» частицу и переиспользуем её слот.
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

	## Взрыв: пачка частиц из палитры.
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
			# Компактизация на месте: живые частицы сдвигаются в начало.
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

# ---------------------------------------------------------------------------
# Пуля
# ---------------------------------------------------------------------------
class Bullet extends RefCounted:
	var x: float
	var y: float
	var vx: float
	var vy: float
	var owner            # Tank
	var team: String
	var alive := true
	var life := Cfg.BULLET_LIFE
	var dmg_scale: float
	var pierce := 0
	var explosive := false
	var keep_bricks := false
	var from_player := false
	## Миномётный снаряд: летит по дуге и не задевает стены.
	var lobbed := false

	func _init(x_: float, y_: float, angle: float, owner_, dmg_scale_: float = 1.0) -> void:
		x = x_
		y = y_
		owner = owner_
		# Пуля без владельца — марионетка сетевого клиента: она только
		# рисуется, попадания за неё считает хост.
		if owner_ == null:
			var sp := Cfg.BULLET_SPEED
			vx = cos(angle) * sp
			vy = sin(angle) * sp
			return
		var speed: float = Cfg.BULLET_SPEED * float(owner_.mods["bulletSpeedMult"])
		vx = cos(angle) * speed
		vy = sin(angle) * speed
		team = owner_.team
		# Модификаторы владельца фиксируются в момент выстрела: если игрок
		# сменит перк, уже летящая пуля не должна менять свойства на лету.
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

		# Миномётный снаряд перелетает стены, взрывается о танк, а при
		# истечении жизни «приземляется» со взрывом.
		if lobbed:
			life -= 1
			if life <= 0:
				_explode(world, null, Cfg.BULLET_DMG_MAX * dmg_scale)
				alive = false
				return
			if x < 0.0 or x > world.map.width or y < 0.0 or y > world.map.height:
				alive = false
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
			# «Толстая броня»: свои пули не ломают постройки — плата за −20% урона.
			if keep_bricks:
				alive = false
				world.hit_building(row, col, 0.0, "bullet", x, y, owner)
				return true
			# Урон пули по зданию — тот же, что по танку: прочность материала
			# читается в попаданиях.
			var dmg := (Cfg.BULLET_DMG_MIN + Cfg.BULLET_DMG_MAX) * 0.5 * dmg_scale
			world.hit_building(row, col, dmg, "bullet", x, y, owner)
			# «Лесоруб»: доска снаряд не держит. Постоянная версия «Кумулятива»,
			# но только по дереву — и потому не ломающая ценность способности.
			if owner != null and owner.flags.has("woodPierce") 					and String(Materials.at(row, col)["id"]) == "wood":
				return false
			# «Кумулятив»: снаряд не вязнет в стене, а идёт дальше. Ради
			# этого он и берётся — пробить ряд построек одним выстрелом.
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
			# Дерево пулю не останавливает.
		return false

	## Выводит пробивную пулю за пределы стены.
	func _pierce_through(world) -> bool:
		var map: GameMap = world.map
		var length := sqrt(vx * vx + vy * vy)
		if length == 0.0:
			length = 1.0
		var step_x := (vx / length) * 4.0
		var step_y := (vy / length) * 4.0
		# Максимум — две толщины тайла: сквозь более толстую кладку не пробиваем.
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

	func _hit_tanks(world) -> bool:
		# Радиус берётся у самого танка: силуэт и хитбокс должны совпадать,
		# иначе крупный корпус врал бы игроку.
		for tank in world.tanks:
			if tank == owner or not tank.alive:
				continue
			if not world.are_hostile(owner, tank):
				continue
			var dx: float = tank.x - x
			var dy: float = tank.y - y
			var hit_r2: float = tank.hit_r * tank.hit_r
			if dx * dx + dy * dy > hit_r2:
				continue

			var amount: float = (Cfg.BULLET_DMG_MIN + world.rng.nextf() \
				* (Cfg.BULLET_DMG_MAX - Cfg.BULLET_DMG_MIN)) * dmg_scale
			world.deal_damage(tank, amount, owner, "bullet")

			if explosive:
				_explode(world, tank, amount)

			alive = false
			world.particles.burst(x, y, [Color("#ff8833"), Color("#ffee55")], 8, 2, 4, 10, 20, world.rng)
			return true
		return false

	func _explode(world, direct_target, base_damage: float) -> void:
		var r2 := Cfg.EXPLOSIVE_R * Cfg.EXPLOSIVE_R
		for other in world.tanks:
			if other == direct_target or other == owner or not other.alive:
				continue
			if not world.are_hostile(owner, other):
				continue
			var dx: float = other.x - x
			var dy: float = other.y - y
			if dx * dx + dy * dy > r2:
				continue
			world.deal_damage(other, base_damage * Cfg.EXPLOSIVE_SPLASH, owner, "bullet")
		# Снос кирпича в радиусе одного тайла.
		var map: GameMap = world.map
		var row := map.row_at(y)
		var col := map.col_at(x)
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				if map.get_tile(row + dr, col + dc) != Cfg.T_BRICK:
					continue
				# В эпицентре урон полный, по краям — вдвое меньше.
				var falloff := 1.0 if (dr == 0 and dc == 0) else 0.5
				world.hit_building(row + dr, col + dc, Cfg.BLAST_TILE_DAMAGE * falloff, "blast",
					(col + dc) * Cfg.TILE + Cfg.TILE * 0.5,
					(row + dr) * Cfg.TILE + Cfg.TILE * 0.5, owner)
		world.particles.burst(x, y, Cfg.explosion, 12, 2, 4, 10, 18, world.rng)
		world.add_shake(8.0, x, y)

# ---------------------------------------------------------------------------
# Мина
# ---------------------------------------------------------------------------
class Mine extends RefCounted:
	var x: float
	var y: float
	var owner            # Tank или null — «нейтральная» мина с карты «Царя горы»
	var team: String
	var timer: int
	var alive := true
	## Пока хозяин не отъехал, мина не срабатывает на него самого.
	var armed: bool

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
		# Мина вскрывает и постройки рядом — иначе заминировать проход
		# в стене было невозможно.
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

# ---------------------------------------------------------------------------
# Ракета авиаудара («Оборона»)
# ---------------------------------------------------------------------------
## Самонаводящаяся ракета супер-способности. Слетает с неба и пикирует
## на назначенную цель, игнорируя стены.
class StrikeRocket extends RefCounted:
	var x: float
	var y: float
	var target       # Tank
	var owner        # Tank атакующего
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

# ---------------------------------------------------------------------------
# Обломок разрушенной постройки
# ---------------------------------------------------------------------------

## Кусок здания: летит от места разрушения, крутится, тормозит и ложится
## на землю. Форма и поведение задаются материалом — щепка длинная и вертлявая,
## бетонная плита тяжёлая и почти не крутится.
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
		# Цвет из палитры материала, чтобы обломки читались как его куски.
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
		# Трение: обломок проезжает по земле и останавливается.
		vx *= 0.90
		vy *= 0.90
		spin *= 0.92

	## Прозрачность: последняя четверть жизни уходит в ноль.
	var fade: float:
		get: return clampf(life / maxf(1.0, max_life * 0.25), 0.0, 1.0)

# ---------------------------------------------------------------------------
# Горящий остов
# ---------------------------------------------------------------------------

## Остаётся на месте уничтоженного танка: несколько секунд горит и дымит,
## потом гаснет и исчезает. Чистая декорация — ни столкновений, ни урона,
## поэтому в расчётах боя не участвует.
class Wreck extends RefCounted:
	var x: float
	var y: float
	## Угол корпуса в момент гибели: остов лежит так, как стоял танк.
	var angle: float
	## Ключ палитры подбитого танка — обгоревший корпус сохраняет оттенок.
	var color_key: String
	## Башню сносит взрывом: она лежит рядом под своим углом.
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

	## Доля оставшейся жизни: 1 — только что подбит, 0 — вот-вот исчезнет.
	var fade: float:
		get: return clampf(float(timer) / maxf(1.0, float(Cfg.WRECK_FADE)), 0.0, 1.0)

	func update(world) -> void:
		timer -= 1
		if timer <= 0:
			alive = false
			return
		var t := float(timer) / float(life)   # огонь стихает к концу
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

# ---------------------------------------------------------------------------
# Аптечка
# ---------------------------------------------------------------------------
class Pickup extends RefCounted:
	var x: float
	var y: float
	var type: String
	var active := true
	var respawn_timer := 0
	var bob := 0.0

	func _init(x_: float, y_: float, type_: String = "health") -> void:
		x = x_
		y = y_
		type = type_
		bob = randf() * TAU

	func consume() -> void:
		active = false
		respawn_timer = Cfg.PICKUP_RESPAWN

# ---------------------------------------------------------------------------
# Выпавший перк («Царь горы»)
# ---------------------------------------------------------------------------
## Время, которое выпавший перк лежит на земле до исчезновения, тиков.
const PERK_DROP_LIFE := 60 * 60

class PerkPickup extends RefCounted:
	var x: float
	var y: float
	var perk_id: String
	var active := true
	var life := 60 * 60
	var bob := 0.0

	func _init(x_: float, y_: float, perk_id_: String) -> void:
		x = x_
		y = y_
		perk_id = perk_id_
		bob = randf() * TAU

	func update() -> void:
		if active:
			life -= 1
			if life <= 0:
				active = false

# ---------------------------------------------------------------------------
# Power-up оружия
# ---------------------------------------------------------------------------
## Время, которое оружие лежит на карте до исчезновения, тиков.
const WEAPON_PICKUP_LIFE := 60 * 25

class WeaponPickup extends RefCounted:
	var x: float
	var y: float
	var weapon_id: String
	var active := true
	var life := 60 * 25
	var bob := 0.0

	func _init(x_: float, y_: float, weapon_id_: String) -> void:
		x = x_
		y = y_
		weapon_id = weapon_id_
		bob = randf() * TAU

	func update() -> void:
		if active:
			life -= 1
			if life <= 0:
				active = false

# ---------------------------------------------------------------------------
# Флаг (CTF)
# ---------------------------------------------------------------------------
class Flag extends RefCounted:
	var home_x: float
	var home_y: float
	var x: float
	var y: float
	var team: String
	## Состояние хранится явно: флаг, брошенный ровно на своей базе, иначе
	## одновременно считался бы и «дома», и «брошенным с таймером возврата».
	var state := "home"  # home | carried | dropped
	var carrier = null   # Tank
	## Тиков до автоматического возврата брошенного флага.
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

	## Бросает флаг. Упавший на свою базу считается сразу возвращённым.
	func drop(x_: float, y_: float, timeout: int) -> void:
		carrier = null
		if Vector2(x_ - home_x, y_ - home_y).length() < 32.0:
			return_home()
			return
		x = x_
		y = y_
		state = "dropped"
		return_timer = timeout
