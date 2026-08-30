# ============================================================================
# bot.gd — «мозг» бота: конечный автомат + A*.
#
# Тактики: предсказание позиции цели, обнаружение по прямой видимости,
# уклонение от пуль, отход на низком HP, оценка угроз, удержание дистанции,
# сопровождение флагоносца, тактическое патрулирование, проверка численного
# перевеса, стрейф со случайной сменой направления и рывок-таран.
# ============================================================================
class_name BotBrain
extends RefCounted

const STATE_PATROL := "patrol"
const STATE_COMBAT := "combat"
const STATE_GO_FLAG := "goFlag"
const STATE_RETURN_FLAG := "returnFlag"
const STATE_ESCORT := "escort"
const STATE_RECOVER_FLAG := "recoverFlag"
## Состояния, в которых роль в CTF уже выбрана и её не надо пересматривать.
const CTF_STATES := [STATE_GO_FLAG, STATE_RETURN_FLAG, STATE_ESCORT, STATE_RECOVER_FLAG]

var base_accuracy := 0.75
var react_time := 20
var role := "attacker"
var rng: Rng
var fire_range := Cfg.BOT_FIRE_RANGE
var keep_min := Cfg.BOT_KEEP_MIN
var keep_max := Cfg.BOT_KEEP_MAX
var lobbed := false
## «Царь горы»: приоритет — пережить всех, а не набить фраги.
var survival := false

var owner_mods := {}

var state := STATE_PATROL
var target = null
## Куда идти проверять услышанный выстрел и сколько ещё тиков это делать.
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
var path: Array = []
var path_idx := 0
var path_timer := 0
var path_goal_x := 0.0
var path_goal_y := 0.0
var stuck_timer := 0
var last_x := 0.0
var last_y := 0.0
var dash_timer := 0

## Вызволение из затора: направление и оставшиеся тики.
var unstick_timer := 0
var unstick_angle := 0.0
## Сколько тиков подряд вызволение уже даёт ход — тогда оно прекращается.
var unstick_free := 0
## Просьба перестроить маршрут на следующем шаге.
var repath_now := false
## Сторона последнего обхода препятствия — гасит дребезг влево-вправо.
var last_steer_off := 0.0
## Контроль прогресса к текущей путевой точке.
var waypoint_dist := INF
var waypoint_stall := 0
## Пауза перед повторной попыткой построить маршрут после неудачи.
var path_cooldown := 0
## Тиков до следующего пересмотра цели.
var perception_timer := 0

## Углы обхода препятствия: сначала почти прямо, затем всё круче.
const STEER_OFFSETS := [
	0.0, 0.3, -0.3, 0.6, -0.6, 0.95, -0.95, 1.35, -1.35,
	1.8, -1.8, 2.3, -2.3, 2.8, -2.8,
]

## Диагностика навигации: сколько тиков подряд бот простоял, хотя до цели
## далеко (то есть он не «дежурит у базы», а действительно застрял).
var frozen_ticks := 0
var worst_frozen := 0
## Обстоятельства самого долгого простоя — чтобы понимать, что именно чинить.
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
	path_timer = 0
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

	# ---- восприятие -------------------------------------------------------
	# Раньше здесь было два прохода по всем танкам с проверкой прямой
	# видимости. Отбор кандидатов у них одинаковый (жив, враг, в радиусе
	# обзора, виден), поэтому «ближайший видимый» пуст ровно тогда же, когда
	# пуста «лучшая угроза» — второй проход был чистой тратой времени,
	# а проверка видимости самая дорогая операция в кадре.
	#
	# Сам перебор целей тоже не нужен каждый тик: 40 ботов в «Царе горы»
	# давали больше сотни трассировок за тик. Пересматриваем цель раз в
	# несколько тиков, а прицеливание и стрельба остаются покадровыми.
	perception_timer -= 1
	if perception_timer <= 0 or target == null or not _target_valid(tank, world, target):
		target = find_best_threat(tank, world)
		perception_timer = 3 + int(rng.nextf() * 3.0)
	var tgt = target
	var target_dist := INF
	var has_shot := false
	if tgt != null:
		target_dist = Vector2(tgt.x - tank.x, tgt.y - tank.y).length()
		has_shot = world.map.has_line_of_sight(tank.x, tank.y, tgt.x, tgt.y)

	# ---- активная способность --------------------------------------------
	_maybe_use_ability(tank, world, target_dist, has_shot)

	# ---- уклонение от летящей пули ---------------------------------------
	if dodge_timer <= 0:
		var incoming = find_incoming_bullet(tank, world, Cfg.BOT_DODGE_LOOKAHEAD)
		if incoming != null:
			var bullet_angle: float = atan2(incoming.vy, incoming.vx)
			var side := 1.0 if rng.nextf() < 0.5 else -1.0
			var dodge_angle: float = bullet_angle + (PI / 2.0) * side
			_steer(tank, world, tank.x + cos(dodge_angle) * 60.0, tank.y + sin(dodge_angle) * 60.0)
			dodge_timer = 15
			# Уклоняясь, всё равно пытаемся отвечать.
			_try_fire(tank, world, tgt, target_dist, has_shot)
			return

	# ---- вызволение из затора --------------------------------------------
	# Проверяется до выбора состояния: застрявший в бою танк раньше мог
	# простоять у стены несколько секунд, потому что боевые манёвры идут
	# мимо _move_toward, где жила единственная попытка выбраться.
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

	# ---- услышанный выстрел ----------------------------------------------
	# Цели нет, но рядом стреляли: идём на звук. Именно поэтому «Глушитель»
	# и «Глушение» имеют смысл — тихая стрельба не собирает вокруг толпу.
	#
	# Проверка стоит ПОСЛЕ вызволения из затора: в первой версии она была
	# выше и перехватывала управление у застрявшего бота — замер показал
	# рост самого долгого упора с 9 тиков до 55.
	if noise_timer > 0:
		noise_timer -= 1
		if tgt == null:
			# Идти на звук надо маршрутом, а не рулением: _steer обходит
			# препятствие только локально, и бот, у которого источник звука
			# за домом, упирается в стену намертво. Замер поймал упор
			# в 8910 тиков — почти две с половиной минуты в стену.
			_move_toward(tank, world, noise_x, noise_y)
			_try_fire(tank, world, tgt, target_dist, has_shot)
			_track_frozen(tank, tgt, target_dist)
			return

	# ---- выбор состояния --------------------------------------------------
	_decide(tank, world, tgt, target_dist)

	# ---- исполнение -------------------------------------------------------
	if state == STATE_COMBAT:
		_do_combat(tank, world, tgt, target_dist, has_shot)
	else:
		_move_toward(tank, world, dest_x, dest_y)
		_try_fire(tank, world, tgt, target_dist, has_shot)

	_track_frozen(tank, tgt, target_dist)

## Замер «бот стоит, хотя ему есть куда ехать».
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

# ------------------------------------------------------------------ решения
func _decide(tank: Tank, world, tgt, target_dist: float) -> void:
	# 1. Несём флаг — домой, это важнее любого боя.
	if tank.carrying_flag:
		var home = world.home_for(tank.team)
		if home != null:
			state = STATE_RETURN_FLAG
			dest_x = home.x
			dest_y = home.y
			return

	# 2. Есть цель в радиусе боя — вступаем в бой.
	# Атакующие в CTF держат короткий радиус: их дело — флаг, а отстреливаться
	# они будут и по дороге (огонь ведётся в любом состоянии).
	var engage := Cfg.BOT_COMBAT_RANGE
	if world.mode == "ctf" and role != "defender" and not tank.carrying_flag:
		engage = Cfg.BOT_CTF_ENGAGE_RANGE
	if tgt != null and target_dist < engage:
		if state != STATE_COMBAT:
			state = STATE_COMBAT
			# Задержка реакции: бот «замечает» противника не мгновенно.
			react_timer = react_time
		return

	# 2.5. «Оборона»: враги идут ломать базу.
	if world.mode == "defense" and world.base != null and tank.is_bot:
		var d_base := Vector2(world.base["x"] - tank.x, world.base["y"] - tank.y).length()
		if d_base > 30.0:
			state = STATE_PATROL
			state_timer = 60
			dest_x = world.base["x"]
			dest_y = world.base["y"]
			return

	# 3. Режим CTF: роли по флагам.
	if world.mode == "ctf":
		# Выбор роли держится state_timer тиков. Без этого он пересчитывался
		# каждый тик, а внутри стоят случайные броски (0.3 / 0.5) — бот
		# метался между «догнать флаг» и «сопровождать своего», цель прыгала
		# по карте, маршрут строился заново почти каждый тик, и в итоге бот
		# топтался на месте вместо игры в захват.
		if state_timer > 0 and CTF_STATES.has(state):
			return
		if _decide_ctf(tank, world):
			return

	# 4. Иначе патруль.
	if state != STATE_PATROL or state_timer <= 0:
		state = STATE_PATROL
		state_timer = 60 + int(rng.nextf() * 120.0)
		var point := _pick_patrol_point(tank, world)
		dest_x = point.x
		dest_y = point.y

## @return взяла ли CTF-логика управление на себя
func _decide_ctf(tank: Tank, world) -> bool:
	# Свой флаг унесли или бросили — возвращаем (касание возвращает флаг).
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

	# Союзник несёт флаг — сопровождаем.
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

	# Идём за флагом противника. Прямая видимость не требуется.
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

	# Все чужие флаги уже несут — защищаем свою базу.
	var home = world.home_for(tank.team)
	if home != null:
		state = STATE_PATROL
		dest_x = home.x + (rng.nextf() - 0.5) * Cfg.TILE * 8.0
		dest_y = home.y + (rng.nextf() - 0.5) * Cfg.TILE * 8.0
		state_timer = 60
		return true
	return false

## Патрульная точка: своя база, центр карты или база противника.
func _pick_patrol_point(tank: Tank, world) -> Vector2:
	var map: GameMap = world.map
	var mw := map.width
	var mh := map.height
	var options := []
	var own = world.home_for(tank.team)
	if own != null:
		options.append({"x": own.x, "y": own.y, "spread": 6.0})
	options.append({"x": mw / 2.0, "y": mh / 2.0, "spread": 8.0})
	var enemy_home = world.enemy_home_for(tank.team)
	if enemy_home != null:
		options.append({"x": enemy_home.x, "y": enemy_home.y, "spread": 8.0})
	# В FFA баз нет — добавляем случайные точки по карте.
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

# ------------------------------------------------------------------ бой
func _do_combat(tank: Tank, world, tgt, target_dist: float, has_shot: bool) -> void:
	if tgt == null or not tgt.alive:
		state = STATE_PATROL
		state_timer = 0
		return

	var predicted := predict_position(tank, tgt)
	var aim: float = atan2(predicted.y - tank.y, predicted.x - tank.x)
	_aim(tank, aim)
	tank.angle = aim

	# Рывок уже летит — не рулим, чтобы не сбить курс, только стреляем.
	if tank.dash_range > 0.0:
		_try_fire(tank, world, tgt, target_dist, has_shot)
		return

	var hp_ratio := tank.hp / tank.max_hp
	var enemies := count_nearby(world, tank, 400.0, true)
	var allies := count_nearby(world, tank, 400.0, false)
	var outnumbered := enemies > allies + 1
	# В режиме выживания уходим раньше и дальше: цена смерти здесь —
	# вылет из партии, а не просто штраф.
	var retreat_hp := 0.55 if survival else 0.3
	var back_dist := 200.0 if survival else 150.0

	if hp_ratio < retreat_hp or outnumbered:
		# Отход: держим цель в прицеле, но отъезжаем назад.
		var back := aim + PI
		var range_v := back_dist if hp_ratio < retreat_hp else 120.0
		_steer(tank, world, tank.x + cos(back) * range_v, tank.y + sin(back) * range_v)
	elif _try_dash(tank, world, tgt, target_dist, has_shot):
		pass  # Рывок-таран начат.
	elif target_dist > keep_max:
		_move_toward(tank, world, tgt.x, tgt.y)
	elif target_dist < keep_min:
		_steer(tank, world, tank.x - cos(aim) * 120.0, tank.y - sin(aim) * 120.0)
	else:
		var strafe := aim + (PI / 2.0) * strafe_dir
		var range_v := 60.0 + rng.nextf() * 60.0
		_steer(tank, world, tank.x + cos(strafe) * range_v, tank.y + sin(strafe) * range_v)

	_try_fire(tank, world, tgt, target_dist, has_shot)

## Рывок-таран: бот бросается на цель с повышенной скоростью, чтобы догнать
## её или ударить корпусом.
func _try_dash(tank: Tank, world, tgt, target_dist: float, has_shot: bool) -> bool:
	if tank.dash_cooldown > 0 or tank.dash_range > 0.0:
		return false
	if dash_timer > 0:
		return false
	if tgt == null or not tgt.alive or not has_shot:
		return false
	# Не тараним из отхода и из воды.
	if tank.in_water:
		return false
	if target_dist < 60.0 or target_dist > 320.0:
		return false
	if survival and count_nearby(world, tank, 120.0, true) > 0:
		return false
	# Проверяем, что на пути рывка нет стены.
	var probe := 34.0
	var px := tank.x + cos(tank.angle) * probe
	var py := tank.y + sin(tank.angle) * probe
	if world.map.is_blocked_rect(px, py, tank.width, tank.height):
		return false
	tank.dash()
	dash_timer = 90 + int(rng.nextf() * 60.0)
	return true

func _aim(tank: Tank, a: float) -> void:
	var spread := (1.0 - accuracy) * (rng.nextf() - 0.5) * 0.4
	tank.slew_turret_to(a + spread)

## Услышанный выстрел: запоминаем точку и идём проверять, если нечем заняться.
func hear_shot(sx: float, sy: float) -> void:
	# Пока идём на предыдущий звук, новые не перебивают цель. Иначе в бою
	# у базы выстрелы гремят непрерывно, таймер не истекает никогда, и бот
	# навсегда остаётся в режиме «иду проверять».
	if noise_timer > 0:
		return
	noise_x = sx
	noise_y = sy
	noise_timer = 150

## Когда бот жмёт свою способность.
##
## Правило одно на каждую: волна — только в упор, где она гарантированно
## задевает; нитро — когда цель далеко и надо сокращать дистанцию. Бот не
## копит способность «на потом»: у него нет плана на партию, и невыжатый
## кулдаун — это просто потерянная способность.
func _maybe_use_ability(tank: Tank, world, target_dist: float, has_shot: bool) -> void:
	if tank.ability_id == "" or tank.ability_cd > 0:
		return
	match tank.ability_id:
		"shockwave":
			if target_dist < Cfg.SHOCKWAVE_R * 0.85:
				tank.use_ability(world)
		"nitro":
			if target_dist > 260.0 and target_dist < INF:
				tank.use_ability(world)
		"bulwark":
			if tank.max_hp > 0.0 and tank.hp / tank.max_hp < 0.45:
				tank.use_ability(world)
		"overdrive":
			if has_shot and target_dist < 420.0:
				tank.use_ability(world)

func _try_fire(tank: Tank, world, tgt, target_dist: float, has_shot: bool) -> void:
	if tgt == null or not has_shot:
		return
	if target_dist > fire_range:
		return
	if react_timer > 0 or not tank.can_fire:
		return

	var predicted := predict_position(tank, tgt)
	var aim: float = atan2(predicted.y - tank.y, predicted.x - tank.x)
	_aim(tank, aim)

	# Стреляем только если башня уже смотрит достаточно близко к цели —
	# иначе бот палит в стену рядом с собой.
	var off := absf(atan2(sin(tank.turret_angle - aim), cos(tank.turret_angle - aim)))
	var tolerance := 0.12 + (1.0 - accuracy) * 0.25
	if off > tolerance:
		return

	# Миномёт стреляет по дуге — снаряд перелетает укрытия.
	if lobbed:
		tank.shoot_lobbed(world)
	else:
		tank.shoot(world)

# ------------------------------------------------------------------ движение
func _move_toward(tank: Tank, world, tx: float, ty: float) -> void:
	# Цель рядом — маршрут не нужен, едем напрямую. Заодно это снимает
	# главный источник лишних вызовов A*: у самой цели find_path возвращает
	# пустой путь, а пустой путь раньше означал «строить заново каждый тик».
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

	if need_path:
		path = Pathfinding.find_path(world.map, tank.x, tank.y, tx, ty)
		path_idx = 0
		path_timer = Cfg.BOT_PATH_REFRESH + int(rng.nextf() * 40.0)
		path_goal_x = tx
		path_goal_y = ty
		repath_now = false
		waypoint_dist = INF
		waypoint_stall = 0
		# Пустой ответ означает «дороги нет» — не долбим A* каждый тик.
		path_cooldown = 20 if path.is_empty() else 0
		# Первая точка маршрута может оказаться позади танка — тогда бот
		# сначала откатывался назад. Пропускаем всё, что уже пройдено.
		_skip_passed_waypoints(tank)

	# Идём по путевым точкам, перескакивая уже достигнутые.
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

	# Если к текущей точке маршрута нет прогресса — она недостижима
	# (типичный случай: точка в углу за стеной). Пропускаем её, а не
	# упираемся в стену до истечения таймера маршрута.
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

## Отбрасывает точки маршрута, которые остались позади: путь строится от
## клетки танка, и первая точка нередко оказывается у него за спиной.
func _skip_passed_waypoints(tank: Tank) -> void:
	while path_idx < path.size() - 1:
		var here: Vector2 = path[path_idx]
		var next: Vector2 = path[path_idx + 1]
		var to_here := Vector2(here.x - tank.x, here.y - tank.y)
		var to_next := Vector2(next.x - tank.x, next.y - tank.y)
		# Следующая точка ближе и в ту же сторону — текущая уже не нужна.
		if to_next.length() < to_here.length() and to_here.dot(to_next) > 0.0:
			path_idx += 1
		else:
			break

## Ускорение в сторону точки с локальным обходом препятствий.
##
## Направления перебираются с оценкой, а не «первое свободное»: учитываются
## отклонение от нужного курса, свободная длина коридора впереди и сторона,
## выбранная в прошлый раз (иначе бот дёргается влево-вправо у стены).
## Если свободных направлений нет вовсе — сдаём назад, но не стоим столбом.
##
## В режиме выживания («Царь горы») отдельно избегаем воды: карту заливает,
## и даже полоса воды на пути означает тихую гибель.
## @return удалось ли выбрать направление вперёд
func _steer(tank: Tank, world, tx: float, ty: float) -> bool:
	var dx := tx - tank.x
	var dy := ty - tank.y
	if dx * dx + dy * dy < 16.0:
		return true
	var desired := atan2(dy, dx)
	var map: GameMap = world.map
	# Чем быстрее едем, тем дальше смотрим вперёд.
	var probe := clampf(tank.speed * 12.0, 16.0, 34.0)

	# Обычный случай — впереди чисто. Полный перебор направлений нужен только
	# у препятствия, иначе на 40 ботов уходит вчетверо больше проверок.
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
		# Небольшая награда за сохранение стороны обхода — против дребезга.
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

	# Всё вокруг закрыто — сдаём назад, чтобы вырваться из кармана.
	tank.thrust(-cos(desired), -sin(desired))
	return false

## Сколько пикселей свободно по направлению a (до max_dist).
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

# ------------------------------------------------------------------ вызволение
## Бот считается застрявшим, если давно не сдвинулся с места. Тогда он
## бросает текущий манёвр и на несколько десятков тиков едет в заведомо
## свободную сторону, после чего строит маршрут заново.
##
## Раньше это работало только внутри _move_toward, поэтому танк, зажатый
## в бою (там ходят через _steer), мог простоять у стены несколько секунд.
func _begin_unstick(tank: Tank, world) -> void:
	var map: GameMap = world.map
	var goal := Vector2(dest_x - tank.x, dest_y - tank.y)
	var goal_angle := atan2(goal.y, goal.x) if goal.length_squared() > 1.0 else tank.angle

	var best_angle := goal_angle + PI
	var best_score := -INF
	for i in 16:
		var a := TAU * float(i) / 16.0
		# Порога «достаточно свободно» нет намеренно: даже в глухом кармане
		# нужно выбрать лучшее из плохого, иначе бот будет толкаться в стену
		# всё время вызволения.
		var clear := _free_run(map, tank, a, 70.0, 4)
		# Главное — вырваться на простор; при равной свободе выбираем
		# направление, которое меньше уводит от цели.
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

## Замечает, что танк упёрся, чтобы включить вызволение и перестроить маршрут.
func _track_stuck(tank: Tank) -> void:
	var dx := tank.x - last_x
	var dy := tank.y - last_y
	if dx * dx + dy * dy < 0.35:
		stuck_timer += 1
	else:
		stuck_timer = 0
	last_x = tank.x
	last_y = tank.y

# ---------------------------------------------------------------------------
# Восприятие
# ---------------------------------------------------------------------------

## Годится ли ещё выбранная цель: жива, враждебна и в пределах обзора.
func _target_valid(tank: Tank, world, t) -> bool:
	if t == null or not t.alive or not world.are_hostile(tank, t):
		return false
	var dx: float = t.x - tank.x
	var dy: float = t.y - tank.y
	return dx * dx + dy * dy <= Cfg.BOT_SIGHT * Cfg.BOT_SIGHT

## Оценка угроз: приоритет тем, кто ближе, слабее по HP и несёт наш флаг.
##
## Проверка прямой видимости — самая дорогая операция «мозга», поэтому она
## делается не для всех врагов в радиусе обзора, а только для нескольких
## ближайших: в «Царе горы» на поле бывает 40 ботов, и полный перебор
## съедал больше времени, чем вся остальная симуляция вместе взятая.
## На выбор это не влияет — оценка и так падает с расстоянием.
const THREAT_CANDIDATES := 6

static func find_best_threat(tank: Tank, world):
	var sight2 := Cfg.BOT_SIGHT * Cfg.BOT_SIGHT
	# Ближайшие кандидаты: простая вставка в короткий массив.
	var near: Array = []
	for other in world.tanks:
		if other == tank or not other.alive:
			continue
		if not world.are_hostile(tank, other):
			continue
		var dx: float = other.x - tank.x
		var dy: float = other.y - tank.y
		var d2 := dx * dx + dy * dy
		if d2 > sight2:
			continue
		# «Дымовая завеса»: вплотную вас всё равно видно, но выцеливать
		# издалека уже нечего — на том она и построена.
		if other.ability_active("smoke") and d2 > Cfg.SMOKE_VISION * Cfg.SMOKE_VISION:
			continue
		var i := near.size()
		while i > 0 and float(near[i - 1][0]) > d2:
			i -= 1
		if i < THREAT_CANDIDATES:
			near.insert(i, [d2, other])
			if near.size() > THREAT_CANDIDATES:
				near.resize(THREAT_CANDIDATES)

	var best = null
	var best_score := -INF
	for entry in near:
		var other = entry[1]
		if not world.map.has_line_of_sight(tank.x, tank.y, other.x, other.y):
			continue
		var d := sqrt(float(entry[0]))
		var score := (Cfg.BOT_SIGHT - d) / Cfg.BOT_SIGHT      # ближе — важнее
		score += (1.0 - other.hp / other.max_hp) * 0.6        # добить раненого
		if other.carrying_flag and other.team != tank.team:
			score += 1.5                                      # остановить флагоносца
		if other.is_player_controlled:
			score += 0.25                                     # человек опаснее бота
		if score > best_score:
			best_score = score
			best = other
	return best

## Ближайшая пуля, которая по курсу попадёт в танк.
static func find_incoming_bullet(tank: Tank, world, radius: float):
	var best = null
	var best_t := INF
	for b in world.bullets:
		if not b.alive:
			continue
		if not world.are_hostile(b.owner, tank):
			continue
		# Время сближения по прямой (проекция на направление пули).
		var dx: float = tank.x - b.x
		var dy: float = tank.y - b.y
		var speed2: float = b.vx * b.vx + b.vy * b.vy
		if speed2 == 0.0:
			continue
		var t: float = (dx * b.vx + dy * b.vy) / speed2
		if t < 0.0 or t > 40.0:
			continue  # позади или слишком далеко по времени
		var closest_x: float = b.x + b.vx * t
		var closest_y: float = b.y + b.vy * t
		if Vector2(closest_x - tank.x, closest_y - tank.y).length() > radius:
			continue
		if t < best_t:
			best_t = t
			best = b
	return best

## Сколько врагов (или союзников) рядом.
static func count_nearby(world, tank: Tank, radius: float, hostile: bool) -> int:
	var r2 := radius * radius
	var n := 0
	for other in world.tanks:
		if other == tank or not other.alive:
			continue
		if world.are_hostile(tank, other) != hostile:
			continue
		var dx: float = other.x - tank.x
		var dy: float = other.y - tank.y
		if dx * dx + dy * dy <= r2:
			n += 1
	return n

## Куда стрелять с опережением, чтобы попасть в движущуюся цель.
static func predict_position(shooter: Tank, target) -> Vector2:
	var d := Vector2(target.x - shooter.x, target.y - shooter.y).length()
	var flight_ticks := d / Cfg.BULLET_SPEED
	# Ограничиваем горизонт предсказания, чтобы не уводить прицел в стену.
	var horizon := minf(flight_ticks, 40.0)
	return Vector2(target.x + target.vx * horizon, target.y + target.vy * horizon)
