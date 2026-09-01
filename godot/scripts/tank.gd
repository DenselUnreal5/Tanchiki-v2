# ============================================================================
# tank.gd — танк: физика, стрельба, урон, перки.
#
# Всё состояние (щит, регенерация, перезарядки, таймеры перков) живёт в самом
# танке либо у его владельца (PlayerState). Число живых игроков ничего
# не ломает: второй игрок в «горячем стуле» полностью независим от первого.
# ============================================================================
class_name Tank
extends RefCounted

## Урон, который спавн-защита НЕ блокирует.
## Источники, которым защита при возрождении не помеха. Гроза не разбирает,
## кто только что появился на карте, — как и вода.
const ENVIRONMENTAL := ["water", "lightning"]

## Скорость поворота башни у ботов, рад/тик. У игрока башня следует за мышью 1:1.
const BOT_TURRET_SLEW := 0.12
## Скорость доворота корпуса, доля от разницы углов за тик.
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
var owner            # PlayerState или null у бота
var is_bot: bool
var color_key: String

var width := Cfg.TANK_W
var height := Cfg.TANK_H
## Силуэт корпуса (ключ TankArt.CHASSIS) и радиус попадания пули.
var chassis_id := "standard"
## Сетевой номер танка: по нему клиент узнаёт, какой присланный танк
## какому его собственному соответствует. Ноль — офлайн-партия.
var net_id := 0
## Чей это танк в сетевой партии: peer_id владельца, 0 — бот.
var owner_peer := 0
## Габарит для рельефа. Он НЕ равен размеру корпуса: переулок в городе шириной
## в один тайл (32 px), и босс с корпусом 34 px в него бы не пролез — а A*
## всё равно построил бы через него маршрут и упёр бы босса в угол. Поэтому
## крупные корпуса ездят по обычному габариту, но пули ловят по своему.
var col_w := Cfg.TANK_W
var col_h := Cfg.TANK_H
var hit_r := Cfg.TANK_HIT_R
## Вылет дульного среза от центра танка — оттуда рождаются снаряды.
var muzzle_len := 18.0

# Базовые характеристики — от них считаются итоговые с учётом перков.
var base_max_hp: float
var base_speed: float
var base_fire_rate: int

## Постоянные улучшения профиля (гараж). Пустой словарь у ботов.
var upgrade_mods := {}
## Косметика {hull, track, turret} — пустой словарь у ботов.
var cosmetics := {}
## Множитель урона танка (типы врагов). У игроков всегда 1.
var dmg_scale := 1.0
## Тип врага (из enemy_types.gd). Пустой словарь у игроков.
var enemy_type := {}

var angle: float
var body_angle: float
var turret_angle: float

## Перки танка. У игрока это ссылка на массив владельца.
var perk_ids: Array = []
var mods := {}
var flags := {}

var max_hp: float
var hp: float
var speed: float
var fire_rate: int

var alive := true
var fire_cooldown := 0
## Нагрев ствола от 0 до 1 и признак срыва в перегрев. Механика только для
## живых игроков: у ботов скорострельность и так задана сложностью.
var heat := 0.0
var overheated := false
## Счётчики для замеров баланса: сколько раз выстрелил и сколько раз
## упёрся в перегрев.
var shots_fired := 0
var overheats := 0
var spawn_protect := Cfg.SPAWN_PROTECT
var respawn_timer := 0

# Состояние перков — у каждого танка своё.
var shield_hp := 0.0
var shield_cooldown := 0
var regen_accum := 0.0
var mine_cooldown := 0
var turbo_timer := 0
var shadow_timer := 0
## Активная способность: id из abilities.gd (пустая строка — нет),
## оставшийся кулдаун и оставшееся время действия, всё в тиках.
var ability_id := ""
var ability_cd := 0
var ability_timer := 0
var dash_range := 0.0
var dash_cooldown := 0
## Сколько тиков подряд рывок не даёт продвижения (упёрлись в стену).
var dash_stall := 0

var in_water := false
var water_timer := 0
## Тики в зыбучем песке — свой счётчик, потому что интервал у него свой.
var quicksand_timer := 0
## Множитель хода от покрытия и его данные — обновляются раз в тик.
var surface_speed := 1.0
var surface := {}
var _tread_timer := 0

## Временное оружие (power-up): id из weapons.gd или пустая строка.
var weapon := ""
## Оставшиеся тики действия оружия.
var weapon_timer := 0

var flag = null       # Ent.Flag
var brain = null      # BotBrain

# Статистика за матч (для табло).
var kills := 0
var deaths := 0
var damage_dealt := 0.0

## Диагностика навигации: тиков в контакте со стеной, текущая и худшая
## серия «стою на месте» (танк жив, но за тик не сдвинулся).
var blocked_ticks := 0
var stall_ticks := 0
var worst_stall := 0
## Запрашивал ли кто-то движение в этом тике (ставится в thrust).
var wants_move := false

## Кто последним нанёс урон — для корректного начисления фрага.
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
	# Силуэт задаёт и вид, и габариты: у босса корпус крупнее, и пули он
	# ловит соответственно.
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

## Нагрев ствола: копится от выстрелов, стекает сам. Перегрев — не штраф
## за частую стрельбу, а её потолок: очередь остаётся быстрой, но держать
## её бесконечно нельзя.
func _update_heat(world) -> void:
	if owner == null:
		return
	if heat > 0.0:
		heat = maxf(0.0, heat - Cfg.HEAT_COOL * float(mods["heatCoolMult"]))
	if overheated:
		# Пар из ствола, пока остывает.
		if world.tick % 5 == 0:
			var a := turret_angle
			world.particles.spawn(
				x + cos(a) * muzzle_len, y + sin(a) * muzzle_len,
				Color(0.85, 0.85, 0.88, 0.8), 2.0, 14.0, world.rng,
				cos(a) * 0.2 - 0.1, sin(a) * 0.2 - 0.35)
		if heat <= Cfg.HEAT_RESUME + float(mods["heatResumeAdd"]):
			overheated = false

## Учёт выстрела: нагрев и срыв в перегрев.
func _after_shot() -> void:
	shots_fired += 1
	if owner == null:
		return
	# «Разгон»: на время действия ствол не греется вовсе.
	#
	# Перк трижды переделывался по замеру. Сначала он давал вдвое быстрее
	# перезарядку ценой вдвое быстрого нагрева — и был строго вреден: 1.15
	# выстрела в секунду против 1.38 без него, −14 урона в секунду. Снятие
	# двойной платы дало −4, полное снятие платы — всего +2. Причина не в
	# числах, а в рычаге: при непрерывном огне узкое место — нагрев, а не
	# перезарядка, и разгон давил не туда, дублируя «Форсаж».
	#
	# Поэтому плата убрана вместе с самим нагревом: четыре секунды ствол
	# держит любой темп, а цена — откат и то, что активный перк всего один.
	var gain: float = Cfg.HEAT_PER_SHOT * float(mods["heatPerShotMult"])
	if ability_active("overclock"):
		gain = 0.0
	heat = minf(1.0, heat + gain)
	if heat >= 1.0 and not overheated:
		overheated = true
		overheats += 1
		Sfx.play("steam", x, y)

## Время до следующего выстрела.## Время до следующего выстрела. «Форсаж» режет его вдвое, поэтому считается
## здесь, а не в каждом из трёх видов стрельбы.
func reload_ticks() -> int:
	if ability_active("overdrive") or ability_active("overclock"):
		return maxi(3, int(round(float(fire_rate) * Cfg.OVERDRIVE_RELOAD_MULT)))
	return fire_rate

## Накладывает постоянные улучшения гаража на модификаторы.
## regenPerMinute складывается (это «скорость», а не множитель),
## остальное перемножается.
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

## Пересчитывает характеристики из базовых значений и текущих перков.
## Вызывается при любом изменении набора перков — именно это устраняет
## «залипший» бонус HP при снятии перка.
func recompute() -> void:
	var hp_ratio := hp / max_hp if max_hp > 0.0 else 1.0
	mods = Perks.compute_modifiers(perk_ids, is_bot)
	flags = Perks.compute_flags(perk_ids, is_bot)
	var next_ability := Perks.active_ability_of(perk_ids, is_bot)
	if next_ability != ability_id:
		ability_timer = 0
		ability_id = next_ability
	# Постоянные улучшения из гаража перемножаются с бонусами перков.
	if not upgrade_mods.is_empty():
		mods = _apply_upgrade_mods(mods)
	max_hp = maxf(1.0, round(base_max_hp * float(mods["maxHPMult"])))
	speed = base_speed * float(mods["speedMult"])
	fire_rate = maxi(4, int(round(float(base_fire_rate) * float(mods["fireRateMult"]))))
	# Сохраняем долю здоровья: рост максимума лечит пропорционально,
	# снижение не убивает мгновенно.
	hp = clampf(round(max_hp * hp_ratio), 1.0, max_hp)
	if not flags.has("shield"):
		shield_hp = 0.0

## Применяет ускорение по нормализованному направлению.
func thrust(dx: float, dy: float) -> void:
	if dx == 0.0 and dy == 0.0:
		return
	var length := sqrt(dx * dx + dy * dy)
	dx /= length
	dy /= length
	var mult := 1.0
	if turbo_timer > 0:
		mult *= 1.5
	# Покрытие под гусеницами: по асфальту ход ровнее и быстрее, по песку
	# танк буксует. Множитель к ускорению — это множитель к предельной
	# скорости, потому что предел равен accel / (1 - FRICTION).
	mult *= surface_speed
	var accel := speed * Cfg.ACCEL_FACTOR * mult
	vx += dx * accel
	vy += dy * accel
	angle = atan2(dy, dx)
	wants_move = true

func aim_at(tx: float, ty: float) -> void:
	turret_angle = atan2(ty - y, tx - x)

## Плавный доворот башни — используется ботами.
func slew_turret_to(target: float) -> void:
	turret_angle = Rng.rotate_toward(turret_angle, target, BOT_TURRET_SLEW)

# ------------------------------------------------------------------ шаг
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

	wants_move = false
	_update_surface(world)
	_update_regen()
	_update_shield(world)

	# Управление: человек через владельца, бот через свой «мозг».
	if owner != null:
		owner.control(self, world)
	elif brain != null:
		brain.update(self, world)

	# Рывок-таран: пока не проехали DASH_DISTANCE, скорость ×DASH_SPEED_MULT.
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
		# Рывок гасится пройденным расстоянием. Если танк упёрся в стену,
		# расстояние не набирается — без отдельной проверки он оставался бы
		# в рывке вечно, а «мозг» в это время не рулит вообще.
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

## Читает покрытие под центром танка и оставляет след из-под гусениц.
func _update_surface(world) -> void:
	surface = Surfaces.of_tile(world.map.tile_at_pixel(x, y), world.road_kind)
	surface_speed = float(surface["speed"])
	# «Шипы»: любое покрытие держит как асфальт, пока способность активна.
	if ability_active("grip"):
		surface_speed = maxf(surface_speed, float(Surfaces.ASPHALT["speed"]))
	elif surface_speed < 1.0:
		# «Вездеход» отыгрывает штраф мягкого грунта, не давая при этом
		# преимущества на асфальте: это перк проходимости, а не скорости.
		surface_speed = lerpf(surface_speed, 1.0, clampf(float(mods["softGrip"]), 0.0, 1.0))
	elif surface_speed > 1.0:
		surface_speed *= float(mods["roadSpeedMult"])

	# Погода поверх покрытия: по снегу танк разгоняется и держит дорогу
	# заметно хуже, по мокрому асфальту — чуть хуже. «Шипы» это отменяют,
	# на то они и шипы.
	if world.weather != null and not ability_active("grip"):
		surface_speed *= world.weather.traction

	var spd := sqrt(vx * vx + vy * vy)
	if spd < 0.45:
		return
	# Пыль и крошка летят из-под гусениц тем чаще, чем быстрее ход.
	if world.tick % 6 == 0:
		var back := angle + PI
		world.particles.spawn(
			x + cos(back) * 12.0 + (world.rng.nextf() - 0.5) * 8.0,
			y + sin(back) * 12.0 + (world.rng.nextf() - 0.5) * 8.0,
			surface["dust"], 1.5 + world.rng.nextf() * 1.5, 8.0 + world.rng.nextf() * 10.0,
			world.rng, cos(back) * 0.3, sin(back) * 0.3)
	# Звук трака — только у живых игроков: сорок ботов превратили бы его в кашу.
	if owner != null:
		_tread_timer -= 1
		if _tread_timer <= 0:
			_tread_timer = 16
			Sfx.play(String(surface["tread"]), x, y)

func _update_regen() -> void:
	var per_minute := float(mods["regenPerMinute"])
	if per_minute <= 0.0 or hp >= max_hp:
		return
	# Накопитель вместо счётчика тиков: корректно работает при дробной регенерации.
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

## Раздельное разрешение по осям — позволяет скользить вдоль стен.
func _move(world) -> void:
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
	# Зыбучий песок разбирается первым: он не вода, «Амфибия» от него не
	# спасает, и тонуть в нём не надо — надо застрять и получать по чуть-чуть,
	# пока выбираешься.
	if world.map.tile_at_pixel(x, y) == Cfg.T_QUICKSAND:
		in_water = false
		quicksand_timer += 1
		if quicksand_timer >= Cfg.QUICKSAND_DMG_INTERVAL:
			quicksand_timer = 0
			world.deal_damage(self, Cfg.QUICKSAND_DMG, null, "water")
			world.particles.burst(x, y, [Cfg.quicksand, Cfg.quicksand_wet],
				4, 1, 3, 8, 14, world.rng)
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
	if world.tick % 8 == 0:
		world.particles.burst(x, y, [Cfg.water_light], 1, 2, 2, 10, 10, world.rng)

func _try_ram(world) -> void:
	var spd := sqrt(vx * vx + vy * vy)
	if spd <= Cfg.RAM_MIN_SPEED:
		return
	var r2 := Cfg.TANK_BODY_R * Cfg.TANK_BODY_R
	for other in world.tanks:
		if other == self or not other.alive:
			continue
		if not world.are_hostile(self, other):
			continue
		var dx: float = other.x - x
		var dy: float = other.y - y
		if dx * dx + dy * dy > r2:
			continue
		var damage := floorf(spd * Cfg.RAM_DMG_PER_SPEED * float(mods["ramMult"]))
		if damage <= 0.0:
			continue
		# Начисление фрага и статистику тарана делает World по source == 'ram'.
		world.deal_damage(other, damage, self, "ram")
		var push_angle: float = atan2(dy, dx)
		other.vx += cos(push_angle) * Cfg.RAM_PUSH
		other.vy += sin(push_angle) * Cfg.RAM_PUSH

# ------------------------------------------------------------------ выстрел
func shoot(world) -> bool:
	if not can_fire:
		return false
	fire_cooldown = reload_ticks()
	_after_shot()

	var muzzle_x := x + cos(turret_angle) * muzzle_len
	var muzzle_y := y + sin(turret_angle) * muzzle_len
	var scale_v := dmg_scale

	# Временное оружие переопределяет выстрел.
	var wp := Weapons.get_weapon(weapon) if weapon != "" else {}
	if not wp.is_empty():
		fire_cooldown = maxi(4, int(round(float(reload_ticks()) * float(wp["cooldown_mult"]))))
		_after_shot()
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

	if flags.has("fanShot"):
		for i in range(-1, 2):
			world.bullets.append(Ent.Bullet.new(muzzle_x, muzzle_y,
				turret_angle + i * 0.15, self, 0.45 * scale_v))
	elif flags.has("doubleShot"):
		var perp := turret_angle + PI / 2.0
		var ox := cos(perp) * 6.0
		var oy := sin(perp) * 6.0
		world.bullets.append(Ent.Bullet.new(muzzle_x + ox, muzzle_y + oy, turret_angle, self, scale_v))
		world.bullets.append(Ent.Bullet.new(muzzle_x - ox, muzzle_y - oy, turret_angle, self, scale_v))
	else:
		world.bullets.append(Ent.Bullet.new(muzzle_x, muzzle_y, turret_angle, self, scale_v))

	world.particles.burst(muzzle_x, muzzle_y, [Color("#ffee55"), Color("#ffffaa")], 5, 2, 4, 8, 8, world.rng)
	Sfx.play("shoot", muzzle_x, muzzle_y)
	world.notify_shot(self)
	return true

## Выстрел миномёта: снаряд летит по дуге над стенами.
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

## Ставит мину. Лимит мин отсчитывается для каждого танка отдельно.
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

## Рывок-таран: устремляет танк вперёд с повышенной скоростью на
## DASH_DISTANCE. Кулдаун не даёт спамить.
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

# ------------------------------------------------------------------ урон
## Считает и применяет урон. Всё побочное (табло, статистика, тряска)
## делает World — здесь только математика брони.
## @return {applied, killed, evaded, reflected}
# ------------------------------------------------------------ способности
## Активна ли конкретная способность прямо сейчас.
func ability_active(id: String) -> bool:
	return ability_id == id and ability_timer > 0

## Доля готовности: 1.0 — можно жать, 0.0 — только что нажали.
var ability_ready: float:
	get:
		if ability_id == "":
			return 0.0
		var ab := Abilities.get_ability(ability_id)
		var cd := float(ab.get("cooldown", 1))
		if cd <= 0.0:
			return 1.0
		return clampf(1.0 - float(ability_cd) / cd, 0.0, 1.0)

## Нажатие способности. Клавишу можно держать зажатой: лишние нажатия
## гасит кулдаун, поэтому отдельная обработка «только что нажал» не нужна.
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
			# Переиспользуем готовое состояние ускорения: оно уже учтено
			# и в физике, и в отрисовке следа.
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
			# Мгновенный сброс: снять перегрев в нужный момент ценнее,
			# чем пережидать его.
			heat = 0.0
			overheated = false
			world.particles.burst(x, y, [Color("#aaeeff"), Color.WHITE],
				16, 2, 5, 14, 26, world.rng)
		"repair":
			hp = minf(max_hp, hp + max_hp * Cfg.REPAIR_FRACTION)
			world.particles.burst(x, y, [Color("#55dd77"), Color("#aaffcc")],
				18, 2, 5, 12, 22, world.rng)
		"overclock", "grip", "breaker", "silencer", "smoke":
			# Эффект этих способностей живёт в других местах: в нагреве,
			# в покрытии, в пуле, в слышимости и в глазах ботов. Здесь
			# только вспышка, чтобы нажатие было видно.
			var ab_color: Color = ab.get("color", Color.WHITE)
			world.particles.burst(x, y, [ab_color, Color.WHITE],
				14, 2, 5, 12, 22, world.rng)

	Sfx.play("explosion" if ability_id == "shockwave" else "pickup", x, y)
	if owner != null:
		world.stat.emit("abilityUses", 1, "add")
	return true

## Ударная волна: кольцо урона вокруг танка. По постройкам бьёт как взрыв,
## поэтому бетон держит её лучше дерева — материал решает, как и везде.
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
		# Отброс — половина смысла способности: волной выбивают из упора
		# и разрывают дистанцию, а не только добивают.
		other.vx += (dx / d) * Cfg.SHOCKWAVE_PUSH * k
		other.vy += (dy / d) * Cfg.SHOCKWAVE_PUSH * k

	world.particles.burst(x, y, [Color("#ff55ff"), Color("#ffaaff"), Color.WHITE],
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

## Вызывается World после смерти.
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
	# Кулдаун способности переживает смерть: иначе размен «умер — получил
	# заряженную волну» стал бы выгодной тактикой.
	ability_timer = 0
	dash_range = 0.0
	dash_cooldown = 0
	dash_stall = 0
	weapon = ""
	weapon_timer = 0
	last_attacker = null
	flag = null
	if brain != null:
		brain.reset()

## Мягкое расталкивание, чтобы танки не слипались в одну точку.
func separate_from(other) -> void:
	var dx: float = x - other.x
	var dy: float = y - other.y
	var d := sqrt(dx * dx + dy * dy)
	var min_dist := Cfg.TANK_BODY_R * 0.9
	if d >= min_dist or d == 0.0:
		return
	var push := ((min_dist - d) / min_dist) * 0.35
	var nx := dx / d
	var ny := dy / d
	vx += nx * push
	vy += ny * push
	other.vx -= nx * push
	other.vy -= ny * push
