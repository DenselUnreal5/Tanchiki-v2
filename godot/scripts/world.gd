# ============================================================================
# world.gd — состояние партии и правила режимов.
#
# World — единственный владелец игрового состояния. Он же отвечает за
# начисление урона и фрагов. Всё, что нужно показать на экране, World отдаёт
# сигналами и ничего не знает про интерфейс.
# ============================================================================
class_name World
extends RefCounted

signal feed(text: String, color: Color)
signal damage_number(x: float, y: float, text: String, color: Color)
signal kill(victim, killer, source: String, suicide: bool)
signal player_died(player)
signal player_damage(player, amount: float)
signal global_xp(amount: int)
signal reward(kind: String, amount: int, who: String)
signal stat(key: String, value: int, mode: String)
signal bot_perk(tank, perk: Dictionary)
signal session_level_up(player, levels: int)
signal flag_event(type: String, flag, tank)
signal respawned(player)
signal finished(result: Dictionary)

const BOT_NAMES := [
	"Рыжий", "Серый", "Чёрный", "Белый", "Тигр", "Ястреб", "Волк", "Медведь",
	"Скорпион", "Пантера", "Сокол", "Кобра", "Шакал", "Фантом", "Рейдер",
	"Гром", "Шторм", "Клинок", "Дикий", "Капитан", "Барс", "Кремень",
]

## Сколько тиков брошенный флаг лежит до автоматического возврата.
const FLAG_RETURN_TIMEOUT := 15 * 60

var map: GameMap
var level: Dictionary
var mode: String
var difficulty_key: String
var difficulty: Dictionary
var players: Array = []
var player_level := 1

var rng: Rng
var weather: WeatherSystem

var tanks: Array = []
var bullets: Array = []
var mines: Array = []
var perk_drops: Array = []
## Горящие остовы подбитых танков — только декорация.
var wrecks: Array = []
## Обломки разрушенных построек.
var debris: Array = []
var pickups: Array = []
var weapon_pickups: Array = []
var flags: Array = []
var particles: Ent.ParticleSystem

var tick := 0
var ramp := 1.0
var ramp_timer := 0

var team_score := {"player": 0, "enemy": 0}
var finished_flag := false
var result := {}

## Накопленные за партию монеты (для итогового разбора наград).
var match_rewards := {"kills": 0, "captures": 0, "wins": 0}

## Жив ли сейчас босс — одновременно босс один.
var boss_alive := false

## Оборона: база, номер волны и таймер до следующей волны.
var base = null            # {x, y, max_hp, hp, radius}
var wave := 0
var wave_state := "delay"  # delay — пауза, active — враги на поле
var wave_timer := 0

## Авиаудар («Оборона»): тиков до готовности, 0 — доступен.
var airstrike_cooldown := 0
var airstrikes: Array = []

## «Царь горы»: лимит времени и затопление.
var time_limit := 0
var flood_duration := 1
var flood_tiles: Array = []
var flood_idx := 0
var max_flood_depth := 1
var flood_level := 0.0

var used_names := {}
## Мир клиента: шага симуляции нет, состояние приходит по сети.
var puppet := false
## Разряды молний и следы от них. Разряд живёт доли секунды, след —
## до конца партии.
var bolts: Array = []
var scorches: Array = []

func _init(opts: Dictionary) -> void:
	map = opts["map"]
	level = opts["level"]
	mode = String(opts["mode"])
	difficulty_key = String(opts["difficulty"])
	difficulty = Cfg.DIFFICULTY[difficulty_key]
	players = opts["players"]
	player_level = int(opts.get("player_level", 1))
	for p in players:
		p.map = map

	# Затравка обычно мешается со временем: две партии на одной карте не
	# должны разыгрываться одинаково. Замер перков — исключение: он сравнивает
	# партии между собой, и при разных стартах разница перка тонет в разбросе.
	var seed_mix: int = (Time.get_ticks_msec() ^ (int(level["seed"]) * 2654435761)) & 0xFFFFFFFF
	var fixed_seed: int = int(opts.get("rng_seed", -1))
	if fixed_seed >= 0:
		seed_mix = fixed_seed & 0xFFFFFFFF
	rng = Rng.new(seed_mix)

	# Погода и атмосфера — детерминированы по seed карты.
	weather = WeatherSystem.new(int(level["seed"]), _weather_opts(opts))
	particles = Ent.ParticleSystem.new()

	# У клиента сетевой партии мир — марионетка: карта та же (собрана по тому
	# же seed), но танки, аптечки и флаги не рождаются здесь, а приходят
	# от хоста. Иначе на каждом экране была бы своя расстановка.
	puppet = bool(opts.get("puppet", false))
	if puppet:
		return

	_spawn_combatants()
	_spawn_pickups()
	_spawn_weapon_pickups()
	_spawn_flags()
	if mode == "koth":
		_setup_koth()
	if mode == "defense":
		_setup_defense()

## Сколько тиков отметка выстрела держится на миникарте: слух даёт свежее
## направление, а не постоянную картинку.
const PING_LIFE := 150

## Недавние выстрелы: {x, y, tick, team, reach}. Читает миникарта — «Острый
## слух» показывает точку там, где стреляли, даже если стрелка не видно.
var shot_pings: Array = []

## Выстрел слышен. Боты без цели идут проверять источник — это и делает
## «Глушитель» и «Глушение» осмысленными: тихая стрельба не собирает толпу.
func notify_shot(shooter) -> void:
	if shooter == null or shooter.ability_active("silencer"):
		return
	var reach: float = Cfg.BOT_HEAR_RANGE * float(shooter.mods.get("noiseMult", 1.0))

	# Та же дальность идёт и в отметку на миникарте: заглушенный выстрел
	# должен и слышаться ближе, и отмечаться только вблизи.
	shot_pings.append({
		"x": shooter.x, "y": shooter.y, "tick": tick,
		"team": shooter.team, "reach": reach,
	})
	while shot_pings.size() > 48:
		shot_pings.pop_front()

	var r2 := reach * reach
	for t in tanks:
		if t == shooter or not t.alive or t.brain == null:
			continue
		if not are_hostile(shooter, t):
			continue
		var dx: float = t.x - shooter.x
		var dy: float = t.y - shooter.y
		if dx * dx + dy * dy > r2:
			continue
		t.brain.hear_shot(shooter.x, shooter.y)

## Гроза бьёт разрядами в землю рядом с игроком. Именно рядом: молния
## в другом конце карты — это звук без картинки, а игроку нужно видеть,
## куда ударило, и успеть отъехать.
func _update_storm() -> void:
	for i in range(bolts.size() - 1, -1, -1):
		bolts[i]["life"] -= 1
		if int(bolts[i]["life"]) <= 0:
			bolts.remove_at(i)

	if weather == null or weather.condition != "storm":
		return
	if tick % Cfg.LIGHTNING_EVERY != 0:
		return
	if rng.nextf() > Cfg.LIGHTNING_CHANCE:
		return

	# Точка удара: рядом с кем-то из живых игроков, но не в упор.
	var anchor = null
	for p in players:
		if p.tank != null and p.tank.alive:
			anchor = p.tank
			break
	if anchor == null:
		return
	var angle := rng.nextf() * TAU
	var dist := 120.0 + rng.nextf() * 260.0
	var x := clampf(anchor.x + cos(angle) * dist, 32.0, map.width - 32.0)
	var y := clampf(anchor.y + sin(angle) * dist, 32.0, map.height - 32.0)
	# В стену молния не бьёт: удар должен быть виден на открытом месте.
	if not map.is_drivable(map.row_at(y), map.col_at(x)):
		return

	strike_lightning(x, y)

## Разряд в точку: урон, след, звук и вспышка.
func strike_lightning(x: float, y: float) -> void:
	# Номер разряда нужен только для формы ломаной, поэтому берётся из
	# счётчика тиков и целой части случайного числа — своего метода
	# у Rng для целых нет.
	bolts.append({"x": x, "y": y, "life": 14,
		"seed": tick * 31 + int(rng.nextf() * 100000.0)})
	scorches.append(Vector2(x, y))
	while scorches.size() > Cfg.MAX_SCORCH:
		scorches.pop_front()

	var r2: float = Cfg.LIGHTNING_RADIUS * Cfg.LIGHTNING_RADIUS
	for t in tanks:
		if not t.alive:
			continue
		var dx: float = t.x - x
		var dy: float = t.y - y
		if dx * dx + dy * dy > r2:
			continue
		deal_damage(t, Cfg.LIGHTNING_DAMAGE, null, "lightning")

	particles.burst(x, y, [Cfg.bolt_core, Cfg.bolt_glow, Color.WHITE],
		22, 3, 7, 20, 44, rng)
	add_shake(7.0, x, y)
	Sfx.play("thunder", x, y)
	weather.flash = maxf(weather.flash, 0.45)

# ------------------------------------------------------------------- сеть
## Описание танка для клиента: всё, что не меняется каждый тик и потому
## не место ему в снапшоте — имя, команда, расцветка, силуэт, косметика.
static func tank_info(t: Tank) -> Dictionary:
	return {
		"id": t.net_id, "team": t.team, "name": t.name,
		"color_key": t.color_key, "chassis": t.chassis_id,
		"max_hp": t.max_hp, "speed": t.speed, "fire_rate": t.fire_rate,
		"owner_peer": t.owner_peer, "cosmetics": t.cosmetics,
	}

func roster() -> Array:
	var out := []
	for t in tanks:
		out.append(tank_info(t))
	return out

## Косметический шаг для клиента: время идёт, частицы летят, погода меняется,
## но ни одно правило игры не выполняется — иначе клиент начал бы спорить
## с хостом о том, кто в кого попал.
func step_cosmetic() -> void:
	tick += 1
	Sfx.advance()
	weather.update()
	particles.update()
	for piece in debris:
		piece.update()
	var live_debris := []
	for piece in debris:
		if piece.alive:
			live_debris.append(piece)
	debris = live_debris
	for w in wrecks:
		w.update()
	var live_wrecks := []
	for w in wrecks:
		if w.alive:
			live_wrecks.append(w)
	wrecks = live_wrecks

## Выбор игрока из меню превращается в закреплённые условия. «Своя» и
## «Цикл» ничего не закрепляют — погода идёт сама, как раньше.
static func _weather_opts(opts: Dictionary) -> Dictionary:
	var out := {}
	var wx := String(opts.get("weather", "auto"))
	if wx != "auto" and wx != "":
		out["condition"] = wx
	# Фаза цикла: 0 — рассвет, 0.25 — день, 0.5 — закат, 0.75 — ночь.
	# Полночь берётся серединой ночной половины, там темнее всего.
	var tod := String(opts.get("daytime", "auto"))
	match tod:
		"day":
			out["phase"] = 0.30
		"dusk":
			out["phase"] = 0.52
		"night":
			out["phase"] = 0.70
		"midnight":
			# Ровно ключевая точка «ночь» — самая тёмная в цикле. Замер
			# поймал обратное: фаза 0.88 уже ползёт к рассвету, и «полночь»
			# получалась светлее «ночи».
			out["phase"] = 0.75
	return out

# ------------------------------------------------------------------ команды
## Враждебность определяется только несовпадением команд.
func are_hostile(a, b) -> bool:
	if a == null or b == null:
		return false
	return a.team != b.team

func home_for(team: String):
	if mode != "ctf":
		return null
	return level["homes"]["player"] if team == "player" else level["homes"]["enemy"]

func enemy_home_for(team: String):
	if mode != "ctf":
		return null
	return level["homes"]["enemy"] if team == "player" else level["homes"]["player"]

## Зона респауна для команды.
func area_for(team: String) -> Dictionary:
	if mode == "ctf":
		return level["areas"]["player"] if team == "player" else level["areas"]["enemy"]
	if mode == "defense" and team == "player":
		return level["areas"]["player"]
	if mode == "defense":
		return level["areas"]["enemy"]
	return level["areas"]["any"]

# ------------------------------------------------------------------ создание
func _unique_bot_name(type: Dictionary) -> String:
	var list: Array = I18n.bot_names()
	if list.is_empty():
		list = BOT_NAMES
	var free := []
	for n in list:
		if not used_names.has(n):
			free.append(n)
	var name := ""
	if free.is_empty():
		name = I18n.t("bot.fallback", {"n": used_names.size() + 1}, "Бот-%d" % (used_names.size() + 1))
	else:
		name = String(rng.pick(free))
	used_names[name] = true
	if not type.is_empty() and bool(type.get("boss", false)):
		return "«%s»" % name
	return name

func _free_spot(team: String, w: float = Cfg.TANK_W, h: float = Cfg.TANK_H) -> Vector2:
	var spot := map.find_free_spot(rng, area_for(team), w, h)
	if spot != Vector2.INF:
		return spot
	spot = map.find_free_spot(rng, level["areas"]["any"], w, h)
	if spot != Vector2.INF:
		return spot
	return Vector2(Cfg.TILE * 4, Cfg.TILE * 4)

func _spawn_combatants() -> void:
	var diff := difficulty
	var is_ctf := mode == "ctf"
	var is_defense := mode == "defense"

	# ---- люди -----------------------------------------------------------
	for i in players.size():
		var player = players[i]
		# В FFA у каждого своя команда, в CTF первый игрок ведёт «player»,
		# второй — «enemy». В «Обороне» все люди на одной стороне.
		var team := ""
		if is_ctf:
			team = "player" if i == 0 else "enemy"
		elif is_defense:
			team = "player"
		else:
			team = "human_%d" % i
		var spot := _free_spot(team)
		var hp: float = float(diff["player_hp"])
		if is_defense:
			# В «Обороне» игрок один против орды — запас прочности выше.
			hp = round(hp * Cfg.DEFENSE_PLAYER_HP_MULT)
		var tank := Tank.new({
			"x": spot.x, "y": spot.y, "team": team, "name": player.name,
			"owner": player, "max_hp": hp,
			"speed": Cfg.PLAYER_SPEED, "fire_rate": Cfg.PLAYER_FIRE_RATE,
			"dmg_scale": Cfg.PLAYER_DMG_MULT,
			"color_key": player.color_key,
			"upgrade_mods": player.upgrade_mods,
			"cosmetics": player.cosmetics,
		})
		tank.net_id = Net.next_tank_id()
		tank.owner_peer = int(player.peer_id)
		player.tank = tank
		tanks.append(tank)

	# ---- боты -----------------------------------------------------------
	if is_ctf:
		var size: int = Cfg.MODES["ctf"]["team_size"]
		# Команда игрока получает на одного бота меньше за каждого живого
		# человека в ней, чтобы составы были равными.
		var humans_player := 1
		var humans_enemy := players.size() - humans_player
		_spawn_bot_team("player", maxi(0, size - humans_player), "ally")
		_spawn_bot_team("enemy", maxi(0, size - humans_enemy), "enemy")
	elif mode == "koth":
		# «Царь горы»: ровно столько врагов, сколько задано в режиме.
		for i in int(Cfg.MODES["koth"]["enemies"]):
			_spawn_bot("bot_%d" % i, "enemy")
	elif mode == "defense":
		# «Оборона»: враги приходят волнами, первая ставится в _setup_defense.
		pass
	else:
		for i in int(diff["enemies"]):
			_spawn_bot("bot_%d" % i, "enemy")

func _spawn_bot_team(team: String, count: int, color_key: String) -> void:
	# Союзники в CTF — только рядовые: сбалансированная помощь людям.
	var forced := "grunt" if team == "player" else ""
	for i in count:
		_spawn_bot(team, color_key, forced)

## Создаёт бота. Тип выбирается по рампе сложности.
##
## Цвет корпуса задаёт вызывающий, и только для врагов он уступает цвету
## типа: тогда по силуэту видно, кто перед тобой — разведчик, тяжёлый или
## босс. Союзники всегда синие («ally»), иначе в командном бою их не
## отличить от противника — до этой правки аргумент color_key просто
## терялся, и союзные боты в CTF выезжали в красном.
func _spawn_bot(team: String, color_key: String, forced_type: String = "") -> Tank:
	var diff := difficulty
	var type := EnemyTypes.pick(ramp, rng, forced_type)
	# Босс на поле боя только один: пока жив — не спавним второго.
	if bool(type["boss"]) and boss_alive:
		type = EnemyTypes.get_type("grunt")
	var spot := _free_spot(team)
	var tank := Tank.new({
		"x": spot.x, "y": spot.y, "team": team,
		"name": _unique_bot_name(type), "owner": null,
		"max_hp": round(float(diff["enemy_hp"]) * float(type["hp_mult"]) * ramp),
		"speed": float(diff["enemy_speed"]) * float(type["speed_mult"]),
		"fire_rate": maxi(4, int(round(float(diff["enemy_fire_rate"]) * float(type["fire_rate_mult"])))),
		"color_key": String(type["color_key"]) if color_key == "enemy" else color_key,
		"chassis": String(type.get("chassis", "standard")),
		"dmg_scale": float(type["dmg_scale"]),
	})
	tank.net_id = Net.next_tank_id()
	tank.enemy_type = type
	if bool(type["boss"]):
		boss_alive = true
	# В «Обороне» враги метят чуть хуже: их много, и перекрёстный огонь
	# из всех стволов убивал защитника ещё до подхода к базе.
	var acc_bonus := float(type["accuracy_bonus"])
	if mode == "defense":
		acc_bonus -= Cfg.DEFENSE_ENEMY_ACCURACY_PENALTY
	tank.brain = BotBrain.new({
		"accuracy": minf(0.98, float(diff["enemy_accuracy"]) + acc_bonus),
		"react_time": int(round(float(diff["enemy_react_time"]) * float(type["react_mult"]))),
		"role": String(type["role"]),
		"fire_range": float(type["fire_range"]),
		"keep_min": float(type["keep_min"]),
		"keep_max": float(type["keep_max"]),
		"lobbed": bool(type["lobbed"]),
		"survival": mode == "koth",
		"rng": rng,
	})
	if bool(type["boss"]):
		particles.burst(tank.x, tank.y, [Color("#e74c3c"), Color("#ffaa33")], 24, 3, 6, 20, 30, rng)
		feed.emit(I18n.t("feed.boss", {"icon": type["icon"], "name": tank.name},
			"%s %s — БОСС на поле боя!" % [type["icon"], tank.name]), Color("#e74c3c"))
	tanks.append(tank)
	# Волны «Обороны» и подкрепления рождаются посреди партии: снапшот
	# их только двигает, а кто это такой — приходит отдельно и надёжно.
	if Net.role == "host":
		Net.host_tank_spawned(tank_info(tank))
	return tank

func _spawn_pickups() -> void:
	var count := Cfg.PICKUP_MIN + int(rng.nextf() * float(Cfg.PICKUP_MAX - Cfg.PICKUP_MIN + 1))
	for i in count:
		var spot := map.find_free_spot(rng, level["areas"]["any"], 16, 16)
		if spot != Vector2.INF:
			pickups.append(Ent.Pickup.new(spot.x, spot.y))

## Разбрасывает power-up оружия — по одному каждого типа.
func _spawn_weapon_pickups() -> void:
	for id in Weapons.ids():
		var spot := map.find_free_spot(rng, level["areas"]["any"], 16, 16)
		if spot != Vector2.INF:
			weapon_pickups.append(Ent.WeaponPickup.new(spot.x, spot.y, id))

func _spawn_flags() -> void:
	if mode != "ctf":
		return
	for s in level["flag_spots"]["enemy"]:
		flags.append(Ent.Flag.new(s.x, s.y, "enemy"))
	for s in level["flag_spots"]["player"]:
		flags.append(Ent.Flag.new(s.x, s.y, "player"))

# ------------------------------------------------------- «Оборона»
## Подготовка режима: база в центре карты и первая волна.
func _setup_defense() -> void:
	var home = level["homes"]["player"]
	base = {
		"x": home.x, "y": home.y,
		"max_hp": float(Cfg.MODES["defense"]["base_hp"]),
		"hp": float(Cfg.MODES["defense"]["base_hp"]),
		"radius": float(Cfg.MODES["defense"]["base_radius"]),
	}
	# Первая волна выходит через start_delay после старта.
	wave = 0
	wave_state = "delay"
	wave_timer = int(Cfg.MODES["defense"]["start_delay"])

## Запускает волну: спавнит врагов и переводит режим в активное состояние.
## Первая волна — ровно DEFENSE_FIRST_WAVE, каждая следующая — столько же
## плюс вклад уровня игрока (с капом) и небольшой рост по номеру волны.
func _setup_wave(n: int) -> void:
	wave = n
	wave_state = "active"
	var base_size := Cfg.DEFENSE_FIRST_WAVE
	var level_bonus := 0
	if Cfg.DEFENSE_PLAYER_LEVEL_BONUS:
		level_bonus = mini(Cfg.DEFENSE_LEVEL_BONUS_CAP, maxi(0, player_level - 1))
	# Рост волн стал линейным: раньше он был вдвое медленнее (n-1)/2, и на
	# «Средне» оборона держалась почти без усилий.
	var wave_growth := n - 1
	var size := mini(Cfg.DEFENSE_WAVE_CAP, base_size + level_bonus + wave_growth)
	# Волна сложнее — типы врагов становятся злее.
	ramp = minf(Cfg.RAMP_MAX, 1.0 + float(n - 1) * Cfg.DEFENSE_RAMP_STEP)
	for i in size:
		# Вся волна — одна команда «enemy»: враги воюют только с защитниками.
		_spawn_bot("enemy", "enemy")
	if Cfg.DEFENSE_BOSS_WAVES.has(n):
		_spawn_boss()
	# Волна не ждёт полной зачистки: по истечении таймаута выходит следующая.
	wave_timer = Cfg.DEFENSE_WAVE_TIMEOUT
	feed.emit(I18n.t("feed.wave",
		{"cur": n, "total": Cfg.MODES["defense"]["waves"], "n": size},
		"🌊 Волна %d из %d: %d %s" % [n, Cfg.MODES["defense"]["waves"], size,
			I18n.plural(size, "враг", "врага", "врагов")]),
		Color("#ff8833"))

## Гарантированный босс: даже если с ранних волн жив ещё один.
func _spawn_boss() -> Tank:
	boss_alive = false
	var tank := _spawn_bot("enemy", "enemy", "boss")
	boss_alive = true
	return tank

## Каждый тик «Оборона»: урон базе и контроль волн.
func _update_defense() -> void:
	if finished_flag or base == null:
		return

	# Враги рядом с базой ломают её.
	if float(base["hp"]) > 0.0:
		var attackers := 0
		for tank in tanks:
			if not tank.alive or not tank.is_bot:
				continue
			var dx: float = tank.x - base["x"]
			var dy: float = tank.y - base["y"]
			var r: float = base["radius"]
			if dx * dx + dy * dy <= r * r:
				attackers += 1
		if attackers > 0:
			base["hp"] = maxf(0.0, float(base["hp"]) - attackers * float(Cfg.MODES["defense"]["base_dps"]))

	# Режим проигран — база уничтожена.
	if float(base["hp"]) <= 0.0:
		_finish(I18n.t("winner.horde", {}, "Орда"), -1, "",
			I18n.t("reason.defenseBase", {}, "База уничтожена — оборона пала"))
		return

	# В паузе база лечится (пока её никто не бьёт), потом ждём следующую волну.
	if wave_state == "delay":
		if _alive_enemy_count() == 0 and float(base["hp"]) < float(base["max_hp"]):
			base["hp"] = minf(float(base["max_hp"]),
				float(base["hp"]) + float(base["max_hp"]) * Cfg.DEFENSE_BASE_REGEN_PER_TICK)
		wave_timer -= 1
		if wave_timer <= 0:
			_setup_wave(wave + 1)
		return

	# В активной фазе: когда все враги волны мертвы — короткая пауза,
	# а после последней волны — победа.
	if _alive_enemy_count() > 0:
		# Затянувшуюся волну подпирает следующая: без этого осторожный игрок
		# отстреливал врагов по одному сколько угодно долго.
		wave_timer -= 1
		if wave_timer <= 0 and wave < int(Cfg.MODES["defense"]["waves"]):
			_setup_wave(wave + 1)
		return

	if wave >= int(Cfg.MODES["defense"]["waves"]):
		_finish(I18n.t("winner.defenders", {}, "Защитники"),
			players[0].index if players.size() > 0 else 0, "player",
			I18n.t("reason.defenseWon", {"n": Cfg.MODES["defense"]["waves"]},
				"Все %d волн отбиты — оборона устояла" % Cfg.MODES["defense"]["waves"]))
	else:
		wave_state = "delay"
		wave_timer = int(Cfg.MODES["defense"]["wave_delay"])

func _alive_enemy_count() -> int:
	var n := 0
	for tank in tanks:
		if tank.alive and tank.is_bot:
			n += 1
	return n

# ------------------------------------------------------------- авиаудар
## Супер-способность «Обороны»: на каждого живого врага с неба летит
## самонаводящаяся ракета. Только первый игрок, только в этом режиме.
func trigger_airstrike(player) -> bool:
	if mode != "defense" or finished_flag or airstrike_cooldown > 0:
		return false
	if player == null or player.index != 0 or player.tank == null or not player.tank.alive:
		return false
	var enemies := []
	for t in tanks:
		if t.alive and t.is_bot and are_hostile(player.tank, t):
			enemies.append(t)
	if enemies.is_empty():
		return false
	for target in enemies:
		airstrikes.append(Ent.StrikeRocket.new(target, player.tank, self))
	airstrike_cooldown = Cfg.AIRSTRIKE_COOLDOWN
	Sfx.play("airstrike")
	feed.emit(I18n.t("feed.airstrike", {"n": enemies.size()},
		"✈ Авиаудар по %d целям!" % enemies.size()), Color("#ffaa33"))
	return true

func _update_airstrike() -> void:
	for r in airstrikes:
		r.update(self)
	var alive_rockets := []
	for r in airstrikes:
		if r.alive:
			alive_rockets.append(r)
	airstrikes = alive_rockets
	if airstrike_cooldown > 0:
		airstrike_cooldown -= 1

# ------------------------------------------------------- «Царь горы»
## Подготовка режима: мины и карта затопления.
func _setup_koth() -> void:
	time_limit = int(Cfg.MODES["koth"]["duration"])
	# Затопление идёт быстрее лимита партии.
	flood_duration = int(Cfg.MODES["koth"]["flood_duration"])
	_scatter_mines()
	# Дистанция до ближайшего края карты в тайлах — по ней идёт затопление.
	flood_tiles = []
	for r in map.rows:
		for c in map.cols:
			var tile := map.get_tile(r, c)
			if tile == Cfg.T_WALL:
				continue  # бетон не тонет
			var depth: int = mini(mini(r, map.rows - 1 - r), mini(c, map.cols - 1 - c))
			flood_tiles.append([depth, r, c])
	flood_tiles.sort_custom(func(a, b): return a[0] < b[0])
	flood_idx = 0
	max_flood_depth = mini(map.rows, map.cols) / 2
	flood_level = 0.0

## Мины на 5% пустой площади карты, подальше от точек спавна.
func _scatter_mines() -> void:
	var empty := []
	for r in range(2, map.rows - 2):
		for c in range(2, map.cols - 2):
			if map.get_tile(r, c) == Cfg.T_EMPTY:
				empty.append([r, c])
	var count := maxi(1, int(float(empty.size()) * Cfg.MINE_SCATTER_FRACTION))
	# Частичный Фишер-Йетс: первые count позиций — случайные.
	for i in count:
		var j := int(rng.nextf() * empty.size()) % empty.size()
		var tmp = empty[i]
		empty[i] = empty[j]
		empty[j] = tmp
	var placed := 0
	var i2 := 0
	while i2 < empty.size() and placed < count:
		var cell = empty[i2]
		i2 += 1
		var x: float = cell[1] * Cfg.TILE + Cfg.TILE * 0.5
		var y: float = cell[0] * Cfg.TILE + Cfg.TILE * 0.5
		# Не класть мины впритык к танкам — чтобы не взрываться на респауне.
		var near_tank := false
		for t in tanks:
			if t.alive and Vector2(t.x - x, t.y - y).length() < Cfg.TILE * 2:
				near_tank = true
				break
		if near_tank:
			continue
		mines.append(Ent.Mine.new(x, y, null, Cfg.SCATTER_MINE_LIFE))
		placed += 1

## Медленно заливает карту водой от краёв к центру.
func _update_flood() -> void:
	flood_level = (float(tick) / float(flood_duration)) * float(max_flood_depth)
	while flood_idx < flood_tiles.size():
		var t = flood_tiles[flood_idx]
		if float(t[0]) > flood_level:
			break
		if map.get_tile(t[1], t[2]) != Cfg.T_WATER:
			map.set_tile(t[1], t[2], Cfg.T_WATER)
		flood_idx += 1

## Обновляет выпавшие перки и проверяет их подбор.
func _update_perk_drops() -> void:
	for drop in perk_drops:
		drop.update()
		if not drop.active:
			continue
		for tank in tanks:
			if not tank.alive:
				continue
			if Vector2(tank.x - drop.x, tank.y - drop.y).length() > 26.0:
				continue
			var perk := Perks.get_perk(drop.perk_id)
			if perk.is_empty():
				continue
			if tank.owner != null:
				tank.owner.equip_perk(drop.perk_id)
				Sfx.play("pickup")
				damage_number.emit(tank.x, tank.y - 26, String(perk["icon"]), Color("#ff88ff"))
				feed.emit(I18n.t("feed.perkPicked",
					{"name": tank.name, "icon": perk["icon"], "perk": I18n.dn(perk, "name", "perk")},
					"%s подобрал перк %s %s" % [tank.name, perk["icon"], perk["name"]]), Color("#ff88ff"))
			else:
				# Бот тоже подбирает, пока не упрётся в лимит перков.
				if tank.perk_ids.size() < Cfg.BOT_MAX_PERKS and not tank.perk_ids.has(drop.perk_id):
					tank.perk_ids.append(drop.perk_id)
					tank.recompute()
					feed.emit(I18n.t("feed.perkPicked",
						{"name": tank.name, "icon": perk["icon"], "perk": I18n.dn(perk, "name", "perk")},
						"%s подобрал перк %s %s" % [tank.name, perk["icon"], perk["name"]]), Color("#ffaa44"))
			drop.active = false
			break
	var kept := []
	for d in perk_drops:
		if d.active:
			kept.append(d)
	perk_drops = kept

# ------------------------------------------------------------------ шаг
func step() -> void:
	if finished_flag:
		return
	tick += 1
	Sfx.advance()
	weather.update()
	if mode == "koth":
		_update_flood()
	_update_storm()

	for tank in tanks:
		tank.update(self)
	_separate_tanks()

	for b in bullets:
		b.update(self)
	var live_bullets := []
	for b in bullets:
		if b.alive:
			live_bullets.append(b)
	bullets = live_bullets

	for m in mines:
		m.update(self)
	var live_mines := []
	for m in mines:
		if m.alive:
			live_mines.append(m)
	mines = live_mines

	for piece in debris:
		piece.update()
	var live_debris := []
	for piece in debris:
		if piece.alive:
			live_debris.append(piece)
	debris = live_debris

	for wreck in wrecks:
		wreck.update(self)
	var live_wrecks := []
	for wreck in wrecks:
		if wreck.alive:
			live_wrecks.append(wreck)
	wrecks = live_wrecks

	if mode == "defense":
		_update_airstrike()

	particles.update()

	if mode == "ctf":
		_update_flags()
	_update_pickups()
	_update_weapon_pickups()
	if mode == "koth":
		_update_perk_drops()
	if mode == "defense":
		_update_defense()
	_update_respawns()
	_update_ramp()

	for p in players:
		p.tick()
		p.update_camera()

	if not finished_flag:
		_check_victory()

## Мягкое расталкивание: без него боты слипаются в кучу в узких проходах.
func _separate_tanks() -> void:
	for i in tanks.size():
		var a = tanks[i]
		if not a.alive:
			continue
		for j in range(i + 1, tanks.size()):
			var b = tanks[j]
			if not b.alive:
				continue
			var dx: float = a.x - b.x
			var dy: float = a.y - b.y
			if dx * dx + dy * dy > 1024.0:
				continue
			a.separate_from(b)

func _update_ramp() -> void:
	ramp_timer += 1
	if ramp_timer < Cfg.RAMP_INTERVAL:
		return
	ramp_timer = 0
	if ramp >= Cfg.RAMP_MAX:
		return
	ramp = minf(Cfg.RAMP_MAX, ramp + Cfg.RAMP_STEP)
	for tank in tanks:
		if not tank.is_bot:
			continue
		# Меняем БАЗОВУЮ характеристику и пересчитываем — иначе бонус затёрся бы
		# при следующем пересчёте перков. Множитель типа врага сохраняется.
		var hp_mult := float(tank.enemy_type.get("hp_mult", 1.0)) if not tank.enemy_type.is_empty() else 1.0
		tank.base_max_hp = round(float(difficulty["enemy_hp"]) * hp_mult * ramp)
		tank.recompute()
	feed.emit(I18n.t("feed.ramp", {}, "Враги стали сильнее!"), Color("#ff8833"))

# ------------------------------------------------------------------ урон
## Единая точка нанесения урона. Здесь же — вся атрибуция.
## source: bullet | ram | mine | water | kamikaze | reflect | airstrike
func deal_damage(target, amount: float, attacker, source: String) -> float:
	if target == null or not target.alive or amount <= 0.0:
		return 0.0
	# «Берсерк»: пока HP атакующего ≤ 40%, его урон увеличен.
	if attacker != null and attacker.alive and attacker.flags.has("berserk"):
		var ratio: float = attacker.hp / attacker.max_hp if attacker.max_hp > 0.0 else 0.0
		if ratio <= 0.4:
			amount *= 1.6
	# «Глушение»: попадание по тому, кто вас ещё не нашёл, бьёт сильнее.
	# Это и есть плата за тишину — иначе перк только отваживал цели.
	if attacker != null and source == "bullet" 			and float(attacker.mods["ambushDmgMult"]) > 1.0 			and target.brain != null and target.brain.target != attacker:
		amount *= float(attacker.mods["ambushDmgMult"])

	var res: Dictionary = target.take_damage(self, amount, attacker, source)
	if bool(res["evaded"]) or float(res["applied"]) <= 0.0:
		return 0.0

	target.last_attacker = attacker
	target.last_attacker_tick = tick

	# Обратный урон от «Отражения» — до проверки смерти, чтобы взаимное
	# уничтожение работало предсказуемо.
	if float(res["reflected"]) > 0.0 and attacker != null and attacker.alive:
		deal_damage(attacker, float(res["reflected"]), target, "reflect")

	# Учёт нанесённого урона и вампиризм.
	if attacker != null:
		attacker.damage_dealt += float(res["applied"])
		if attacker.owner != null:
			attacker.owner.damage_dealt += float(res["applied"])
			player_damage.emit(attacker.owner, float(res["applied"]))
		if float(attacker.mods["lifestealFraction"]) > 0.0 and attacker.alive:
			var heal := floorf(float(res["applied"]) * float(attacker.mods["lifestealFraction"]))
			if heal > 0.0:
				attacker.hp = minf(attacker.max_hp, attacker.hp + heal)

	# Обратная связь: цифры урона и вспышка только у пострадавшего игрока.
	damage_number.emit(target.x, target.y - 20,
		"-%d" % int(round(float(res["applied"]))),
		Color("#ff4444") if target.owner != null else Color("#ffee55"))
	if target.owner != null:
		target.owner.damage_flash = 12
		target.owner.shake = maxf(target.owner.shake, 5.0)
		target.owner.clean_streak = 0
		# По себе попадание слышно всегда, где бы ни стояла камера.
		Sfx.play("hit")
	elif source == "bullet":
		# Чужие попадания — с привязкой к месту: перестрелка на другом
		# конце карты должна доноситься, а не бить в ухо.
		Sfx.play("hit", target.x, target.y)

	if bool(res["killed"]):
		_kill_tank(target, attacker, source)
	return float(res["applied"])

func _kill_tank(victim, killer, source: String) -> void:
	victim.on_death(self, killer)
	victim.respawn_timer = Cfg.RESPAWN_DELAY
	if Sets.wrecks:
		wrecks.append(Ent.Wreck.new(victim, rng))

	# Босс убит — можно снова спавнить нового.
	if not victim.enemy_type.is_empty() and bool(victim.enemy_type.get("boss", false)):
		boss_alive = false

	# «Царь горы»: убитый роняет случайный перк.
	if mode == "koth":
		_drop_perk(victim)

	# Флаг выпадает на месте гибели.
	if victim.flag != null:
		var f = victim.flag
		victim.flag = null
		f.drop(victim.x, victim.y, FLAG_RETURN_TIMEOUT)
		flag_event.emit("dropped", f, victim)

	# ---- начисление фрага ----------------------------------------------
	var suicide: bool = killer == null or killer == victim
	if not suicide and are_hostile(killer, victim):
		killer.kills += 1
		if killer.owner != null:
			_credit_player_kill(killer.owner, victim, source)
		elif killer.is_bot:
			_maybe_give_bot_perk(killer)

	if victim.owner != null:
		victim.owner.deaths += 1
		victim.owner.clean_streak = 0
		player_died.emit(victim.owner)

	kill.emit(victim, null if suicide else killer, source, suicide)

func _credit_player_kill(player, victim, source: String) -> void:
	player.kills += 1
	player.score += Cfg.SCORE_PER_KILL
	match_rewards["kills"] += Cfg.REWARD_KILL
	reward.emit("kill", Cfg.REWARD_KILL, player.name)

	var levels: int = player.add_xp(Cfg.XP_PER_KILL)
	if levels > 0:
		session_level_up.emit(player, levels)
	global_xp.emit(Cfg.XP_PER_KILL)

	# Бонус за босса: щедрый куш в монетах и XP.
	if not victim.enemy_type.is_empty() and bool(victim.enemy_type.get("boss", false)):
		var boss_reward := Cfg.REWARD_KILL * 5
		match_rewards["kills"] += boss_reward
		reward.emit("boss", boss_reward, player.name)
		global_xp.emit(Cfg.XP_PER_KILL * 3)
		player.score += Cfg.SCORE_PER_KILL * 3
		feed.emit(I18n.t("feed.bossKilled", {"name": player.name, "n": boss_reward},
			"%s уничтожил БОССА! +%d 🪙" % [player.name, boss_reward]), Color("#e74c3c"))

	# Челлендж «убей 5 врагов за 10 секунд».
	player.kill_ticks.append(tick)
	var cutoff := tick - 10 * Cfg.TICK_HZ
	while not player.kill_ticks.is_empty() and int(player.kill_ticks[0]) < cutoff:
		player.kill_ticks.pop_front()
	stat.emit("rapidKills", player.kill_ticks.size(), "max")

	# Серия без полученного урона.
	player.clean_streak += 1
	stat.emit("cleanStreak", player.clean_streak, "max")
	stat.emit("totalKills", 1, "add")

	if source == "ram":
		stat.emit("ramKills", 1, "add")

	# Челленджи «Снайпер» и «Берсерк».
	var killer_tank = player.tank
	if killer_tank != null:
		var kill_dist := Vector2(killer_tank.x - victim.x, killer_tank.y - victim.y).length()
		if kill_dist >= 400.0:
			stat.emit("longKills", 1, "add")
		if kill_dist >= 800.0:
			stat.emit("sniperKills", 1, "add")
		# Мост — единственная переправа через реку и самое узкое место
		# на карте: убийство, сделанное стоя на нём, засчитывается отдельно.
		if map.tile_at_pixel(killer_tank.x, killer_tank.y) == Cfg.T_BRIDGE:
			stat.emit("bridgeKills", 1, "add")
		if killer_tank.max_hp > 0.0 and killer_tank.hp / killer_tank.max_hp <= 0.4:
			stat.emit("lowHpKills", 1, "add")

	# Перки «Турбо» и «Тень» — на конкретном танке.
	if killer_tank != null:
		if float(killer_tank.mods["turboOnKill"]) > 0.0:
			killer_tank.turbo_timer = int(killer_tank.mods["turboOnKill"])
		if float(killer_tank.mods["shadowOnKill"]) > 0.0:
			killer_tank.shadow_timer = int(killer_tank.mods["shadowOnKill"])

func _maybe_give_bot_perk(bot) -> void:
	if bot.perk_ids.size() >= Cfg.BOT_MAX_PERKS:
		return
	if rng.nextf() >= Cfg.BOT_PERK_CHANCE:
		return
	var available := []
	for p in Perks.BOT_LIST:
		if not bot.perk_ids.has(p["id"]):
			available.append(p)
	if available.is_empty():
		return
	var perk: Dictionary = rng.pick(available)
	bot.perk_ids.append(perk["id"])
	bot.recompute()
	particles.burst(bot.x, bot.y - 20, [Color("#ffee55"), Color("#ffffaa")], 8, 2, 4, 15, 20, rng)
	bot_perk.emit(bot, perk)

## Роняет перк на месте гибели — только перки, разрешённые в режиме.
func _drop_perk(victim) -> void:
	var allowed := []
	for p in Perks.LIST:
		if Perks.is_perk_allowed_in_mode(p["id"], mode):
			allowed.append(p)
	if allowed.is_empty():
		return
	var perk: Dictionary = rng.pick(allowed)
	perk_drops.append(Ent.PerkPickup.new(victim.x, victim.y, String(perk["id"])))
	particles.burst(victim.x, victim.y, [Color("#ff88ff"), Color.WHITE], 8, 2, 4, 12, 18, rng)

# ------------------------------------------------------------- постройки
## Максимум обломков на карте: больше на экране всё равно не читается,
## а рисовать их дешевле, чем копить.
const MAX_DEBRIS := 300

## Единая точка попадания по постройке: и пули, и взрывы, и мины идут сюда.
## Следы на материале остаются при любом попадании, обломки и звук — только
## при разрушении.
func hit_building(row: int, col: int, amount: float, source: String,
		x: float, y: float, owner_tank) -> void:
	var mat := Materials.at(row, col)
	# «Осадные снаряды» усиливают любое своё попадание по постройке —
	# и пулю, и мину, и ударную волну. Поэтому множитель применяется здесь,
	# а не в каждом источнике урона по отдельности.
	if owner_tank != null and amount > 0.0:
		amount *= float(owner_tank.mods.get("buildingDmgMult", 1.0))
		# Перки по материалу: железо пулями почти не берётся, поэтому
		# «Консервный нож» и его собратья бьют именно туда, где стена
		# иначе непроходима.
		match String(mat["id"]):
			"wood":
				amount *= float(owner_tank.mods.get("woodDmgMult", 1.0))
			"brick":
				amount *= float(owner_tank.mods.get("brickDmgMult", 1.0))
			"concrete":
				amount *= float(owner_tank.mods.get("concreteDmgMult", 1.0))
			"metal":
				amount *= float(owner_tank.mods.get("metalDmgMult", 1.0))
		if owner_tank.ability_active("breaker"):
			amount *= Cfg.BREAKER_BUILDING_MULT
	# Выбоина в месте попадания: цвет берётся у материала, поэтому дерево
	# сыплет щепой, а бетон — светлой крошкой.
	particles.burst(x, y, [mat["light"], mat["base"], mat["dark"]], 5, 2, 4, 8, 16, rng)
	if int(mat["sparks"]) > 0 and source != "blast":
		# Рикошет по железу: пуля высекает искры, но почти не вредит.
		particles.burst(x, y, [Color("#fff2c0"), Color("#ffb347")], 3, 1, 2, 6, 12, rng)
	if amount <= 0.0:
		return
	if map.apply_damage(row, col, amount, source):
		_destroy_building(row, col, mat, owner_tank)

## Разрушение постройки: разлёт обломков, облако пыли, звук и тряска —
## всё берётся из материала, поэтому у каждого типа зданий свой характер.
func _destroy_building(row: int, col: int, mat: Dictionary, owner_tank) -> void:
	var cx := col * Cfg.TILE + Cfg.TILE * 0.5
	var cy := row * Cfg.TILE + Cfg.TILE * 0.5

	for i in int(mat["pieces"]):
		if debris.size() >= MAX_DEBRIS:
			debris.pop_front()
		debris.append(Ent.Debris.new(
			cx + (rng.nextf() - 0.5) * Cfg.TILE * 0.6,
			cy + (rng.nextf() - 0.5) * Cfg.TILE * 0.6, mat, rng))

	# Пыль: у бетона она гуще и живёт дольше, это задано в материале.
	var dust_amount := 10 + int(mat["pieces"])
	particles.burst(cx, cy, [mat["dust"], mat["light"], mat["base"]],
		dust_amount, 3, 7, 20, 46, rng)
	if int(mat["sparks"]) > 0:
		particles.burst(cx, cy, [Color("#fff2c0"), Color("#ffcc55")],
			int(mat["sparks"]), 1, 3, 10, 22, rng)

	# «Мародёр»: обломки идут в дело.
	if owner_tank != null and owner_tank.alive:
		var heal: float = float(owner_tank.mods.get("scavengeHeal", 0.0))
		if heal > 0.0 and owner_tank.hp < owner_tank.max_hp:
			owner_tank.hp = minf(owner_tank.max_hp, owner_tank.hp + heal)
			particles.burst(owner_tank.x, owner_tank.y,
				[Color("#55dd77")], 4, 1, 3, 8, 14, rng)

	Sfx.play(String(mat["sound"]), cx, cy)
	add_shake(float(mat["shake"]), cx, cy)
	if owner_tank != null and owner_tank.owner != null:
		stat.emit("bricksDestroyed", 1, "add")
		# Бетон и железо держат втрое больше дерева, поэтому их снос —
		# отдельная веха, а не часть общего счётчика.
		var mid := String(mat["id"])
		if mid == "concrete" or mid == "metal":
			stat.emit("concreteDestroyed", 1, "add")

func on_trees_driven(tank, count: int) -> void:
	if tank.owner != null:
		stat.emit("treesDriven", count, "add")

func on_water_entered(tank) -> void:
	if tank.owner != null:
		stat.emit("waterEntries", 1, "add")

## Тряска добавляется каждому игроку, который видит точку взрыва.
func add_shake(amount: float, x: float = INF, y: float = INF) -> void:
	for p in players:
		if is_inf(x) or Vector2(p.camera.x - x, p.camera.y - y).length() < 700.0:
			p.shake = maxf(p.shake, amount * Sets.screen_shake)

# ------------------------------------------------------------------ аптечки
func _update_pickups() -> void:
	# В «Царе горы» аптечки подбирают и боты, в остальных режимах — только люди.
	var candidates := []
	for player in players:
		if player.tank != null and player.tank.alive:
			candidates.append(player.tank)
	if mode == "koth":
		for tank in tanks:
			if tank.is_bot and tank.alive:
				candidates.append(tank)

	for pickup in pickups:
		if not pickup.active:
			pickup.respawn_timer -= 1
			if pickup.respawn_timer <= 0:
				var spot := map.find_free_spot(rng, level["areas"]["any"], 16, 16)
				if spot != Vector2.INF:
					pickup.x = spot.x
					pickup.y = spot.y
				pickup.active = true
			continue
		for tank in candidates:
			var radius: float = tank.owner.pickup_radius if tank.owner != null else Cfg.PICKUP_R
			if Vector2(tank.x - pickup.x, tank.y - pickup.y).length() > radius:
				continue
			var heal := maxf(1.0, floorf(tank.max_hp * Cfg.PICKUP_HEAL_FRACTION))
			var before: float = tank.hp
			tank.hp = minf(tank.max_hp, tank.hp + heal)
			var gained := int(round(tank.hp - before))
			pickup.consume()
			Sfx.play("pickup")
			damage_number.emit(tank.x, tank.y - 24, "+%d" % gained, Color("#44ff44"))
			if tank.owner != null:
				feed.emit(I18n.t("feed.medkit", {"name": tank.owner.name, "n": gained},
					"%s: аптечка +%d HP" % [tank.owner.name, gained]), Color("#44ff44"))
				stat.emit("healthPacksCollected", 1, "add")
			else:
				feed.emit(I18n.t("feed.medkit", {"name": tank.name, "n": gained},
					"%s: аптечка +%d HP" % [tank.name, gained]), Color("#44ff44"))
			break

# ------------------------------------------------------------------ power-up оружия
func _update_weapon_pickups() -> void:
	for pickup in weapon_pickups:
		if not pickup.active:
			continue
		pickup.update()
		if not pickup.active:
			continue
		for tank in tanks:
			if not tank.alive or tank.owner == null:
				continue
			var radius: float = tank.owner.pickup_radius
			if Vector2(tank.x - pickup.x, tank.y - pickup.y).length() > radius:
				continue
			var weapon := Weapons.get_weapon(pickup.weapon_id)
			if weapon.is_empty():
				continue
			tank.weapon = String(weapon["id"])
			tank.weapon_timer = int(weapon["duration"])
			pickup.active = false
			Sfx.play("pickup")
			particles.burst(tank.x, tank.y, [weapon["color"], Color.WHITE], 10, 2, 4, 14, 22, rng)
			damage_number.emit(tank.x, tank.y - 26,
				"%s %s!" % [weapon["icon"], I18n.dn(weapon, "name", "weapon")], weapon["color"])
			feed.emit(I18n.t("feed.weapon",
				{"name": tank.owner.name, "icon": weapon["icon"], "weapon": I18n.dn(weapon, "name", "weapon")},
				"%s: %s %s!" % [tank.owner.name, weapon["icon"], weapon["name"]]), weapon["color"])
			break
	var kept := []
	for p in weapon_pickups:
		if p.active:
			kept.append(p)
	weapon_pickups = kept

# ------------------------------------------------------------------ флаги
func _update_flags() -> void:
	# 1. Подбор и возврат при касании.
	for flag in flags:
		if flag.carried:
			continue
		for tank in tanks:
			if not tank.alive:
				continue
			if Vector2(tank.x - flag.x, tank.y - flag.y).length() > 24.0:
				continue

			if flag.team == tank.team:
				# Свой флаг: если он не дома — возвращаем касанием.
				if not flag.at_home:
					flag.return_home()
					Sfx.play("flag")
					flag_event.emit("returned", flag, tank)
					feed.emit(I18n.t("feed.flagReturned", {"name": tank.name},
						"%s вернул свой флаг" % tank.name),
						Cfg.flag_player if flag.team == "player" else Cfg.flag_enemy)
			elif not tank.carrying_flag:
				flag.pick_up(tank)
				tank.flag = flag
				Sfx.play("flag")
				flag_event.emit("taken", flag, tank)
				feed.emit(I18n.t("feed.flagTaken", {"name": tank.name},
					"%s забрал флаг" % tank.name),
					Color("#ffee55") if tank.owner != null else Color("#ff8833"))
			break

	# 2. Флаг едет вместе с носителем.
	for flag in flags:
		if flag.carrier != null:
			if not flag.carrier.alive:
				# Страховка: носитель умер вне _kill_tank.
				var carrier = flag.carrier
				carrier.flag = null
				flag.drop(carrier.x, carrier.y, FLAG_RETURN_TIMEOUT)
				continue
			flag.x = flag.carrier.x
			flag.y = flag.carrier.y
		elif flag.state == "dropped":
			# Брошенный флаг сам возвращается домой по таймеру.
			flag.return_timer -= 1
			if flag.return_timer <= 0:
				flag.return_home()
				flag_event.emit("returned", flag, null)

	# 3. Захват: носитель доехал до своей базы.
	for flag in flags:
		var carrier = flag.carrier
		if carrier == null or not carrier.alive:
			continue
		var home = home_for(carrier.team)
		if home == null or Vector2(carrier.x - home.x, carrier.y - home.y).length() > 40.0:
			continue

		var team: String = carrier.team
		team_score[team] = int(team_score.get(team, 0)) + 1
		carrier.flag = null
		flag.return_home()

		if carrier.owner != null:
			var player = carrier.owner
			player.captures += 1
			player.score += Cfg.SCORE_PER_CAPTURE
			var levels: int = player.add_xp(Cfg.XP_PER_CAPTURE)
			if levels > 0:
				session_level_up.emit(player, levels)
			global_xp.emit(Cfg.XP_PER_CAPTURE)
			match_rewards["captures"] += Cfg.REWARD_CAPTURE
			reward.emit("capture", Cfg.REWARD_CAPTURE, player.name)

		Sfx.play("flag")
		particles.burst(home.x, home.y,
			[Color("#ffee55"), Color("#44ff44"), Color("#4488ff"), Color("#ff44ff")],
			50, 3, 7, 30, 60, rng)
		flag_event.emit("captured", flag, carrier)
		feed.emit(I18n.t("feed.flagCapturedWorld",
			{"name": carrier.name, "a": team_score["player"], "b": team_score["enemy"]},
			"%s захватил флаг! %d:%d" % [carrier.name, team_score["player"], team_score["enemy"]]),
			Color("#ffee55"))
		break  # за тик засчитываем один захват

# ------------------------------------------------------------------ респаун
func _update_respawns() -> void:
	# «Царь горы»: без возрождения — побеждает последний выживший.
	if mode == "koth":
		return
	for tank in tanks:
		if tank.alive:
			continue
		# «Оборона»: враги волн не возрождаются, люди — да.
		if mode == "defense" and tank.is_bot:
			continue
		tank.respawn_timer -= 1
		if tank.respawn_timer > 0:
			continue
		var spot := _free_spot(tank.team)
		tank.respawn(spot.x, spot.y)
		if not tank.enemy_type.is_empty() and bool(tank.enemy_type.get("boss", false)):
			boss_alive = true
		if tank.owner != null:
			tank.owner.update_camera()
			respawned.emit(tank.owner)

# ------------------------------------------------------------------ победа
func _check_victory() -> void:
	# «Оборона»: победу и поражение считает _update_defense.
	if mode == "defense":
		return

	# «Царь горы»: побеждает последний выживший. Время истекло — сильнейший.
	if mode == "koth":
		var alive := []
		for t in tanks:
			if t.alive:
				alive.append(t)

		# Игроков-людей больше нет — партия окончена (поражение).
		var humans_left := false
		for p in players:
			if p.tank != null and p.tank.alive:
				humans_left = true
				break
		if not humans_left:
			_finish(alive[0].name if not alive.is_empty() else I18n.t("winner.nobody", {}, "Никто"),
				-1, "", I18n.t("reason.allDead", {}, "Все игроки уничтожены"))
			return

		if alive.size() == 1:
			var winner = alive[0]
			_finish(winner.name, winner.owner.index if winner.owner != null else -1, "",
				I18n.t("reason.lastStanding", {"name": winner.name},
					"%s остался последним" % winner.name))
			return

		# Тайм-аут: побеждает тот, кто нанёс больше урона.
		if tick >= time_limit:
			var best = alive[0]
			for t in alive:
				if t.damage_dealt > best.damage_dealt:
					best = t
			_finish(best.name, best.owner.index if best.owner != null else -1, "",
				I18n.t("reason.kothTimeout", {}, "Время вышло — побеждает сильнейший"))
		return

	if mode == "ffa":
		var limit: int = Cfg.MODES["ffa"]["frag_limit"]
		var leader = null
		for tank in tanks:
			if tank.kills >= limit and (leader == null or tank.kills > leader.kills):
				leader = tank
		if leader == null:
			return
		_finish(leader.name, leader.owner.index if leader.owner != null else -1, "",
			I18n.t("reason.ffaLimit", {"name": leader.name, "n": leader.kills},
				"%s первым набрал %d фрагов" % [leader.name, leader.kills]))
		return

	var limit: int = Cfg.MODES["ctf"]["cap_limit"]
	var team := ""
	if int(team_score["player"]) >= limit:
		team = "player"
	elif int(team_score["enemy"]) >= limit:
		team = "enemy"
	if team == "":
		return
	var winner_index := -1
	for p in players:
		if p.tank != null and p.tank.team == team:
			winner_index = p.index
			break
	var team_name := I18n.t("team.allies", {}, "Свои") if team == "player" else I18n.t("team.enemies", {}, "Враги")
	_finish(
		I18n.t("winner.teamAllies", {}, "Команда «Свои»") if team == "player" else I18n.t("winner.teamEnemies", {}, "Команда «Враги»"),
		winner_index, team,
		I18n.t("reason.ctfLimit", {"team": team_name, "n": limit},
			"%s захватили %d %s" % [team_name, limit,
				I18n.plural(limit, "флаг", "флага", "флагов")]))

## Завершает партию. victory считается от лица первого игрока, но в результате
## есть и явный победитель — «горячему стулу» нужно показывать, кто выиграл.
func _finish(winner_name: String, winner_player_index: int, winner_team: String, reason: String) -> void:
	finished_flag = true
	var victory := winner_player_index == 0
	if victory:
		match_rewards["wins"] += Cfg.REWARD_WIN
		reward.emit("win", Cfg.REWARD_WIN, winner_name)
	result = {
		"victory": victory,
		"winner_name": winner_name,
		"winner_player_index": winner_player_index,
		"winner_team": winner_team,
		"reason": reason,
		"rewards": match_rewards.duplicate(),
	}
	finished.emit(result)

# ------------------------------------------------------------------ уборка
## Разрывает циклические ссылки партии.
##
## Tank.owner ↔ PlayerState.tank и Tank.flag ↔ Flag.carrier — это циклы, а
## RefCounted считает ссылки и цикл сам не разорвёт: без этого каждая
## сыгранная партия навсегда оставалась бы в памяти.
func dispose() -> void:
	for f in flags:
		f.carrier = null
	for t in tanks:
		t.owner = null
		t.brain = null
		t.flag = null
		t.last_attacker = null
		t.perk_ids = []
	for p in players:
		p.tank = null
		p.map = null
	for r in airstrikes:
		r.target = null
		r.owner = null
	for b in bullets:
		b.owner = null
	for m in mines:
		m.owner = null
	tanks.clear()
	bullets.clear()
	mines.clear()
	wrecks.clear()
	debris.clear()
	flags.clear()
	pickups.clear()
	weapon_pickups.clear()
	perk_drops.clear()
	airstrikes.clear()
	flood_tiles.clear()
	players = []
	particles.clear()

# ------------------------------------------------------------------ табло
## Данные для таблицы результатов, отсортированные по фрагам.
func scoreboard() -> Array:
	var rows := []
	for tank in tanks:
		rows.append({
			"name": tank.name,
			"kills": tank.kills,
			"deaths": tank.deaths,
			"team": tank.team,
			"color_key": tank.color_key,
			"is_human": tank.owner != null,
			"alive": tank.alive,
			"perks": tank.perk_ids.duplicate(),
		})
	rows.sort_custom(func(a, b):
		if a["kills"] != b["kills"]:
			return a["kills"] > b["kills"]
		return a["deaths"] < b["deaths"])
	return rows

func alive_enemies_for(team: String) -> int:
	var n := 0
	for t in tanks:
		if t.alive and t.team != team:
			n += 1
	return n

## Прогресс режима (для полосок в HUD).
func progress_for(player) -> Dictionary:
	if mode == "koth":
		var alive := 0
		for t in tanks:
			if t.alive:
				alive += 1
		return {"current": alive, "target": 1, "total": tanks.size()}
	if mode == "defense":
		return {"current": _alive_enemy_count(), "target": 0,
			"total": int(Cfg.MODES["defense"]["waves"]), "wave": wave}
	if mode == "ffa":
		return {"current": player.kills, "target": int(Cfg.MODES["ffa"]["frag_limit"])}
	var team: String = player.tank.team if player.tank != null else "player"
	return {"current": int(team_score.get(team, 0)), "target": int(Cfg.MODES["ctf"]["cap_limit"])}
