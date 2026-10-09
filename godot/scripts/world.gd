class_name World
extends RefCounted

signal feed(text: String, color: Color)
signal synergy_unlocked(player, build_id: String, build_name: String, color: Color)
signal wave_started(n: int)
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
var location := Locations.CITY
var road_kind := "asphalt"

var tanks: Array = []
var tank_grid := SpatialGrid.new()
var bullet_grid := SpatialGrid.new()
var bullets: Array = []
var mines: Array = []
var acid_pools: Array = []
var perk_drops: Array = []
var wrecks: Array = []
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

var match_rewards := {"kills": 0, "captures": 0, "wins": 0}

var boss_alive := false

var storm_summoned := false

var base = null
var wave := 0
var wave_state := "delay"
var wave_timer := 0
var defense_wave_size := 0

var airstrike_cooldown := 0
var airstrikes: Array = []

var time_limit := 0
var flood_duration := 1
var flood_tiles: Array = []
var flood_idx := 0
var max_flood_depth := 1
var flood_level := 0.0

var used_names := {}
var puppet := false
var bolts: Array = []
var scorches: Array = []
var shockwaves: Array = []
var barrels: Array = []
var power_generators: Array = []
var rammer_meltdowns: Array = []

var _storm_rng: Rng
var _tree_tiles: PackedInt32Array = PackedInt32Array()
var _tree_cache_tick := -100000
var _trees_felled := 0
var _last_ffa_boss_kills: Dictionary = {}

var tutorial_stage := 0
var tutorial_marker := Vector2.ZERO
var tutorial_targets: Array = []
var tutorial_barrels: Array = []
var tutorial_barrel_targets: Array = []
var tutorial_drone = null
var tutorial_mine_dummy = null
var tutorial_ice_dummy = null
var tutorial_acid_dummy = null
var tutorial_step_timer := 0

# Трекеры выполнения действий для пошаговых заданий обучения
var tut_dist_fwd := 0.0
var tut_dist_bwd := 0.0
var tut_turned_left := false
var tut_turned_right := false
var tut_bricks_destroyed := 0

func _init(opts: Dictionary) -> void:
	map = opts["map"]
	level = opts["level"]
	mode = String(opts["mode"])
	difficulty_key = String(opts.get("difficulty", "medium"))
	difficulty = Cfg.DIFFICULTY.get(difficulty_key, Cfg.DIFFICULTY["medium"])
	players = opts["players"]
	player_level = int(opts.get("player_level", 1))
	if mode == "tutorial":
		tutorial_stage = 1
		tutorial_marker = Vector2(float(map.cols * Cfg.TILE) * 0.5, float(map.rows * Cfg.TILE) * 0.5)
		tutorial_step_timer = 0
	for p in players:
		p.map = map

	var seed_mix: int = (Time.get_ticks_msec() ^ (int(level["seed"]) * 2654435761)) & 0xFFFFFFFF
	var fixed_seed: int = int(opts.get("rng_seed", -1))
	if fixed_seed >= 0:
		seed_mix = fixed_seed & 0xFFFFFFFF
	rng = Rng.new(seed_mix)

	location = String(level.get("location", Locations.CITY))
	var loc := Locations.get_location(location)
	road_kind = String(loc.get("road_kind", "asphalt"))
	var wx_opts := _weather_opts(opts)
	wx_opts["allowed"] = loc.get("weather", [])
	weather = WeatherSystem.new(int(level["seed"]), wx_opts)
	_storm_rng = Rng.new((int(level["seed"]) ^ 0x57012) & 0xFFFFFFFF)
	particles = Ent.ParticleSystem.new()

	if mode == "defense":
		_setup_defense_base()

	puppet = bool(opts.get("puppet", false))
	if puppet:
		return

	_spawn_combatants()
	_spawn_pickups()
	_spawn_weapon_pickups()
	_spawn_flags()
	_spawn_arena_interactives()
	if mode == "koth":
		_setup_koth()
	if mode == "defense":
		_setup_defense_wave_start()

const PING_LIFE := 150

var shot_pings: Array = []

func notify_shot(shooter) -> void:
	if shooter == null or shooter.ability_active("silencer"):
		return
	var wx_noise: float = weather.noise_scale if weather != null else 1.0
	var reach: float = Cfg.BOT_HEAR_RANGE * float(shooter.mods.get("noiseMult", 1.0)) * wx_noise

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
		t.brain.hear_shot(shooter.x, shooter.y, shooter)

func spawn_shockwave(x: float, y: float, radius: float, kind: String = "shockwave", color: Color = Color("#ff55ff"), duration: int = 24) -> void:
	shockwaves.append({
		"x": x,
		"y": y,
		"radius": radius,
		"kind": kind,
		"color": color,
		"life": duration,
		"max_life": duration,
	})

func _update_shockwaves() -> void:
	for i in range(shockwaves.size() - 1, -1, -1):
		shockwaves[i]["life"] -= 1
		if int(shockwaves[i]["life"]) <= 0:
			shockwaves.remove_at(i)

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
	if not map.is_drivable(map.row_at(y), map.col_at(x)):
		return

	strike_lightning(x, y)

func strike_lightning(x: float, y: float, attacker = null) -> void:
	bolts.append({"x": x, "y": y, "life": 14,
		"seed": tick * 31 + int(rng.nextf() * 100000.0)})
	scorches.append(Vector2(x, y))
	while scorches.size() > Cfg.MAX_SCORCH:
		scorches.pop_front()

	var r2: float = Cfg.LIGHTNING_RADIUS * Cfg.LIGHTNING_RADIUS
	var hit := {}
	for t in tanks:
		if not t.alive:
			continue
		var dx: float = t.x - x
		var dy: float = t.y - y
		if dx * dx + dy * dy > r2:
			continue
		deal_damage(t, Cfg.LIGHTNING_DAMAGE, attacker, "lightning")
		hit[t.id] = true

	particles.burst(x, y, [Cfg.bolt_core, Cfg.bolt_glow, Color.WHITE],
		22, 3, 7, 20, 44, rng)
	add_shake(7.0, x, y)
	Sfx.play("thunder", x, y)
	weather.flash = maxf(weather.flash, 0.45)

	if attacker != null and attacker.alive and attacker.flags.has("chainLightning"):
		_chain_lightning(x, y, attacker, hit)

func _chain_lightning(x: float, y: float, attacker, already_hit: Dictionary) -> void:
	var candidates := []
	var r2: float = Cfg.CHAIN_LIGHTNING_RADIUS * Cfg.CHAIN_LIGHTNING_RADIUS
	for t in tanks:
		if not t.alive or already_hit.has(t.id) or not are_hostile(attacker, t):
			continue
		var dx: float = t.x - x
		var dy: float = t.y - y
		var d2 := dx * dx + dy * dy
		if d2 > r2:
			continue
		candidates.append([d2, t])
	candidates.sort_custom(func(a, b): return a[0] < b[0])

	var chain_dmg: float = Cfg.LIGHTNING_DAMAGE * Cfg.CHAIN_LIGHTNING_DMG_MULT
	for i in mini(Cfg.CHAIN_LIGHTNING_MAX_TARGETS, candidates.size()):
		var t = candidates[i][1]
		deal_damage(t, chain_dmg, attacker, "lightning")
		scorches.append(Vector2(t.x, t.y))
		while scorches.size() > Cfg.MAX_SCORCH:
			scorches.pop_front()
		particles.burst(t.x, t.y, [Cfg.bolt_core, Cfg.bolt_glow], 10, 2, 5, 14, 26, rng)

var _tank_completed_builds := {}

func check_tank_synergies(tank) -> void:
	if tank == null:
		return
	if not _tank_completed_builds.has(tank.id):
		_tank_completed_builds[tank.id] = []
	var known: Array = _tank_completed_builds[tank.id]

	for build in Perks.BUILDS:
		var b_id: String = String(build["id"])
		if known.has(b_id):
			continue
		if Perks.is_build_complete(b_id, tank.perk_ids):
			known.append(b_id)
			_on_synergy_unlocked(tank, build)

func check_player_synergies(player) -> void:
	if player == null:
		return
	if player.tank != null:
		check_tank_synergies(player.tank)
	else:
		for build in Perks.BUILDS:
			var b_id: String = String(build["id"])
			if Perks.is_build_complete(b_id, player.perk_ids):
				if b_id == "lightning" and not storm_summoned and weather != null:
					storm_summoned = true
					weather.set_condition("storm")
					weather.locked = true
					weather.flash = 0.8
					feed.emit(I18n.t("feed.stormSummoned", {"name": player.name},
						"%s активировал синергию «Владыка бури» — над полем боя разразилась вечная гроза!" % player.name),
						Color("#8899ff"))

func _on_synergy_unlocked(tank, build: Dictionary) -> void:
	var b_id: String = String(build["id"])
	var b_name: String = String(build.get("name", "Синергия"))
	var b_col: Color = build.get("color", Color("#f59e0b"))
	var p_name: String = tank.name
	if tank.owner != null and String(tank.owner.name) != "":
		p_name = tank.owner.name

	# 1. Feed notification
	var feed_text := "⚡ %s активировал синергию «%s»!" % [p_name, b_name]
	feed.emit(feed_text, b_col)

	# 2. Visual & Audio celebration
	spawn_shockwave(tank.x, tank.y, 120.0, "synergy", b_col, 24)
	particles.burst(tank.x, tank.y, [b_col, Color.WHITE, Color("#ffe066")], 28, 3, 7, 20, 48, rng)
	damage_number.emit(tank.x, tank.y - 38, "⚡ СИНЕРГИЯ: " + b_name.to_upper() + "!", b_col)
	add_shake(5.0, tank.x, tank.y)
	Sfx.play("unlock")

	# 3. Build-specific initialization
	if b_id == "lightning":
		if weather != null and not storm_summoned:
			storm_summoned = true
			weather.set_condition("storm")
			weather.locked = true
			weather.flash = 0.85
			Sfx.play("thunder", tank.x, tank.y)

	synergy_unlocked.emit(tank.owner, b_id, b_name, b_col)

func maybe_summon_storm(player) -> void:
	check_player_synergies(player)

func _update_lightning_lord() -> void:
	if weather == null or weather.condition != "storm":
		return
	if tick % Cfg.LIGHTNING_EVERY != 0:
		return
	for holder in tanks:
		if not holder.alive or not holder.flags.has("lightningLord"):
			continue
		var chance := Cfg.LIGHTNING_LORD_CHANCE
		if holder.flags.has("skyStrike") and holder.flags.has("chainLightning"):
			chance = Cfg.LIGHTNING_LORD_SYNERGY_CHANCE
		if rng.nextf() > chance:
			continue
		var target = _nearest_hostile(holder)
		if target != null:
			strike_lightning(target.x, target.y, holder)

func _nearest_hostile(tank):
	var best = null
	var best_d2 := INF
	for other in tanks:
		if other == tank or not other.alive or not are_hostile(tank, other):
			continue
		var dx: float = other.x - tank.x
		var dy: float = other.y - tank.y
		var d2 := dx * dx + dy * dy
		if d2 < best_d2:
			best_d2 = d2
			best = other
	return best

func _update_treefall() -> void:
	if weather == null or not weather.fells_trees:
		return
	if _trees_felled >= Cfg.STORM_FELL_MAX:
		return
	if tick % Cfg.STORM_FELL_EVERY != 0:
		return

	if _tree_tiles.is_empty() or tick - _tree_cache_tick > 600:
		_rebuild_tree_cache()
	if _tree_tiles.is_empty():
		return

	for _try in 8:
		var idx := int(_storm_rng.nextf() * float(_tree_tiles.size())) % _tree_tiles.size()
		var cell := _tree_tiles[idx]
		var r := cell / map.cols
		var c := cell % map.cols
		if map.get_tile(r, c) != Cfg.T_TREE:
			continue
		map.set_tile(r, c, Cfg.T_EMPTY)
		_trees_felled += 1
		var px := c * Cfg.TILE + Cfg.TILE * 0.5
		var py := r * Cfg.TILE + Cfg.TILE * 0.5
		particles.burst(px, py, [Cfg.tree, Cfg.tree_dark], 12, 2, 6, 18, 32, _storm_rng)
		add_shake(2.0, px, py)
		Sfx.play("crack", px, py)
		return

func _rebuild_tree_cache() -> void:
	_tree_tiles = PackedInt32Array()
	for r in range(1, map.rows - 1):
		for c in range(1, map.cols - 1):
			if map.get_tile(r, c) == Cfg.T_TREE:
				_tree_tiles.append(r * map.cols + c)
	_tree_cache_tick = tick

static func tank_info(t: Tank) -> Dictionary:
	return {
		"id": t.net_id, "team": t.team, "name": t.name,
		"color_key": t.color_key, "chassis": t.chassis_id,
		"max_hp": t.max_hp, "speed": t.speed, "fire_rate": t.fire_rate,
		"owner_peer": t.owner_peer, "cosmetics": t.cosmetics,
		"cannon_id": t.cannon_id,
	}

func roster() -> Array:
	var out := []
	for t in tanks:
		out.append(tank_info(t))
	return out

func step_cosmetic() -> void:
	tick += 1
	Sfx.advance()
	weather.update()
	particles.update()
	_update_shockwaves()
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

static func _weather_opts(opts: Dictionary) -> Dictionary:
	var out := {}
	var wx := String(opts.get("weather", "auto"))
	if wx != "auto" and wx != "":
		out["condition"] = wx
	var tod := String(opts.get("daytime", "auto"))
	match tod:
		"day":
			out["phase"] = 0.30
		"dusk":
			out["phase"] = 0.52
		"night":
			out["phase"] = 0.70
		"midnight":
			out["phase"] = 0.75
	return out

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

func area_for(team: String) -> Dictionary:
	if mode == "ctf":
		return level["areas"]["player"] if team == "player" else level["areas"]["enemy"]
	if mode == "defense" and team == "player":
		return level["areas"]["player"]
	if mode == "defense":
		return level["areas"]["enemy"]
	return level["areas"]["any"]

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
	var is_ctf := mode == "ctf"
	var is_defense := mode == "defense"

	for i in players.size():
		var player = players[i]
		var team := ""
		if is_ctf:
			team = "player" if i == 0 else "enemy"
		elif is_defense or mode == "tutorial":
			team = "player"
		else:
			team = "human_%d" % i
		var tank := _spawn_player_tank(player, team)
		if mode == "tutorial":
			tank.x = float(map.cols * Cfg.TILE) * 0.5
			tank.y = float(map.rows - 5) * Cfg.TILE + Cfg.TILE * 0.5
			tank.angle = -PI * 0.5
			tank.body_angle = -PI * 0.5
			tank.turret_angle = -PI * 0.5
			tank.flags["mines"] = true
			tank.cannon_id = "standard"
			tank.set_chassis("standard")
			tank.color_key = "p1"
			tank.cosmetics = {}
			player.equipped_cannon = "standard"
			player.color_key = "p1"
			player.cosmetics = {}
			player.upgrade_mods = {}
			tank.weapon = ""
			if tank.ability_id == "":
				tank.ability_id = "bulwark"
			tank.ability_cd = 0

	if is_ctf:
		var size: int = Cfg.MODES["ctf"]["team_size"]
		var humans_player := 1
		var humans_enemy := players.size() - humans_player
		_spawn_bot_team("player", maxi(0, size - humans_player), "ally")
		_spawn_bot_team("enemy", maxi(0, size - humans_enemy), "enemy")
	elif mode == "koth":
		var total_enemies: int = int(Cfg.MODES["koth"]["enemies"])
		var bosses: Array = ["boss_rammer", "boss_chimera", "boss"]
		var elite_roster: Array = ["heavy", "sniper", "mortar", "scout", "grunt"]
		for i in total_enemies:
			var forced_type := ""
			if i < bosses.size():
				forced_type = bosses[i]
			else:
				forced_type = elite_roster[(i - bosses.size()) % elite_roster.size()]
			_spawn_bot("bot_%d" % i, "enemy", forced_type)
	elif mode == "defense":
		pass
	elif mode == "tutorial":
		feed.emit("🎯 ЭТАП 1: Маневрирование [W/A/S/D] — доберитесь до контрольной точки!", Color("#ffd700"))
	else:
		for i in int(difficulty["enemies"]):
			_spawn_bot("bot_%d" % i, "enemy")

func _spawn_player_tank(player, team: String) -> Tank:
	var spot := _free_spot(team)
	var hp: float = float(difficulty["player_hp"])
	if mode == "defense":
		hp = round(hp * Cfg.DEFENSE_PLAYER_HP_MULT)
	var tank := Tank.new({
		"x": spot.x, "y": spot.y, "team": team, "name": player.name,
		"owner": player, "max_hp": hp,
		"speed": Cfg.PLAYER_SPEED, "fire_rate": Cfg.PLAYER_FIRE_RATE,
		"dmg_scale": Cfg.PLAYER_DMG_MULT,
		"color_key": "p1" if mode == "tutorial" else player.color_key,
		"upgrade_mods": {} if mode == "tutorial" else player.upgrade_mods,
		"cosmetics": {} if mode == "tutorial" else player.cosmetics,
		"cannon_id": "standard" if mode == "tutorial" else player.equipped_cannon,
		"chassis": "standard",
	})
	tank.net_id = Net.next_tank_id()
	tank.owner_peer = int(player.peer_id)
	player.tank = tank
	tanks.append(tank)
	if Net.role == "host":
		Net.host_tank_spawned(tank_info(tank))
	return tank

func _spawn_bot_team(team: String, count: int, color_key: String) -> void:
	for i in count:
		_spawn_bot(team, color_key)

func _spawn_bot(team: String, color_key: String, forced_type: String = "") -> Tank:
	var diff := difficulty
	var type := EnemyTypes.pick(ramp, rng, forced_type)
	if bool(type["boss"]) and boss_alive and mode != "koth":
		type = EnemyTypes.get_type("grunt")
	var boss_mult := {"hp": 1.0, "dmg": 1.0}
	if bool(type["boss"]):
		boss_mult = _boss_stat_mult()
	var base_hp_val: float = float(type.get("base_hp", 0.0))
	var calc_hp: float = (base_hp_val if base_hp_val > 0.0 else float(diff["enemy_hp"]) * float(type["hp_mult"])) * ramp * float(boss_mult["hp"])
	var spot := _free_spot(team)
	var tank := Tank.new({
		"x": spot.x, "y": spot.y, "team": team,
		"name": _unique_bot_name(type), "owner": null,
		"max_hp": round(calc_hp),
		"speed": float(diff["enemy_speed"]) * float(type["speed_mult"]),
		"fire_rate": maxi(4, int(round(float(diff["enemy_fire_rate"]) * float(type["fire_rate_mult"])))),
		"color_key": String(type["color_key"]) if color_key == "enemy" else color_key,
		"chassis": String(type.get("chassis", "standard")),
		"dmg_scale": float(type["dmg_scale"]) * float(boss_mult["dmg"]),
	})
	tank.net_id = Net.next_tank_id()
	tank.enemy_type = type
	if bool(type["boss"]):
		tank.is_boss = true
		tank.boss_stat_mult = float(boss_mult["hp"])
		var boss_type_id: String = String(type.get("id", ""))
		if boss_type_id == "boss_rammer":
			tank.is_rammer_boss = true
			tank.perk_ids = []
		elif boss_type_id == "boss_chimera":
			tank.is_chimera_boss = true
			tank.chimera_cloak_timer = int(Cfg.CHIMERA_CLOAK_INTERVAL * 0.35)
			tank.perk_ids = []
		else:
			tank.perk_ids = ["bot_boss_twin", "bot_boss_barrage"]
		tank.recompute()
		boss_alive = true
	var acc_bonus := float(type["accuracy_bonus"])
	if mode == "defense" and defense_wave_size > 0:
		var wave_factor := float(defense_wave_size) / float(Cfg.DEFENSE_FIRST_WAVE)
		acc_bonus -= clampf(Cfg.DEFENSE_ENEMY_ACCURACY_PENALTY * wave_factor,
			Cfg.DEFENSE_ENEMY_ACCURACY_PENALTY, Cfg.DEFENSE_ACCURACY_PENALTY_MAX)
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
	if Net.role == "host":
		Net.host_tank_spawned(tank_info(tank))
	return tank

func _spawn_pickups() -> void:
	var count := Cfg.PICKUP_MIN + int(rng.nextf() * float(Cfg.PICKUP_MAX - Cfg.PICKUP_MIN + 1))
	for i in count:
		var spot := map.find_free_spot(rng, level["areas"]["any"], 16, 16)
		if spot != Vector2.INF:
			pickups.append(Ent.Pickup.new(spot.x, spot.y, "health", rng))

func _spawn_weapon_pickups() -> void:
	for id in Weapons.ids():
		var spot := map.find_free_spot(rng, level["areas"]["any"], 16, 16)
		if spot != Vector2.INF:
			weapon_pickups.append(Ent.WeaponPickup.new(spot.x, spot.y, id, rng))

var _last_flag_spot := Vector2.INF

func _spawn_flags() -> void:
	if mode != "ctf":
		return
	_spawn_next_ctf_flag()

func _spawn_next_ctf_flag() -> void:
	flags.clear()
	var spot := _pick_next_flag_spot()
	var flag := Ent.Flag.new(spot.x, spot.y, "neutral")
	flags.append(flag)
	feed.emit(I18n.t("feed.flagSpawned", {}, "⚑ На поле боя появился флаг!"), Color("#ffd700"))

func _pick_next_flag_spot() -> Vector2:
	var spots_list: Array = []
	if level.has("flag_spots"):
		var fs = level["flag_spots"]
		if fs is Array and not fs.is_empty():
			spots_list = fs
		elif fs is Dictionary:
			if fs.has("neutral") and not (fs["neutral"] as Array).is_empty():
				spots_list = fs["neutral"]
			elif fs.has("spots") and not (fs["spots"] as Array).is_empty():
				spots_list = fs["spots"]
			else:
				spots_list = fs.get("player", []) + fs.get("enemy", [])

	var p_home = home_for("player")
	var e_home = home_for("enemy")
	var candidates: Array = []
	for s in spots_list:
		var p: Vector2 = s if s is Vector2 else Vector2(float(s["x"]), float(s["y"]))
		if _last_flag_spot != Vector2.INF and p.distance_to(_last_flag_spot) < 64.0:
			continue
		if p_home != null and p.distance_to(p_home) < 96.0:
			continue
		if e_home != null and p.distance_to(e_home) < 96.0:
			continue
		candidates.append(p)

	if not candidates.is_empty():
		var chosen: Vector2 = candidates[int(rng.nextf() * candidates.size()) % candidates.size()]
		_last_flag_spot = chosen
		return chosen

	var area = level.get("areas", {}).get("any", null)
	if area != null:
		var spot := map.find_free_spot(rng, area, 24, 24)
		if spot != Vector2.INF:
			_last_flag_spot = spot
			return spot
	var def_spot := Vector2(float(map.cols * Cfg.TILE) * 0.5, float(map.rows * Cfg.TILE) * 0.5)
	_last_flag_spot = def_spot
	return def_spot

func _spawn_arena_interactives() -> void:
	barrels.clear()
	power_generators.clear()
	if puppet or mode == "tutorial":
		return

	var raw_chokes = level.get("choke_points", [])
	var chokes: Array[Vector2] = []
	if raw_chokes is Array:
		for pt in raw_chokes:
			if pt is Vector2:
				chokes.append(pt)

	var p_homes: Array = []
	for p in players:
		if p.tank != null:
			p_homes.append(Vector2(p.tank.x, p.tank.y))
	if level.has("homes"):
		var h = level["homes"]
		if h is Dictionary:
			if h.get("player") != null:
				p_homes.append(h["player"])
			if h.get("enemy") != null:
				p_homes.append(h["enemy"])

	var target_barrels: int = 3 + int(rng.nextf() * 3.0)
	if mode == "defense":
		target_barrels += 2

	var used_spots: Array[Vector2] = []
	var available_chokes: Array[Vector2] = chokes.duplicate()

	for i in range(available_chokes.size() - 1, 0, -1):
		var j: int = int(rng.nextf() * float(i + 1))
		var tmp = available_chokes[i]
		available_chokes[i] = available_chokes[j]
		available_chokes[j] = tmp

	var num_generators := 1
	if (mode == "defense" or mode == "ffa" or mode == "koth") and map.cols >= 24:
		num_generators = 2

	for i in num_generators:
		var gen_spot: Vector2 = Vector2.INF
		var center := Vector2(map.width * 0.5, map.height * 0.5)
		var best_idx := -1
		var best_dist := INF
		for idx in available_chokes.size():
			var pt = available_chokes[idx]
			var d := pt.distance_to(center)
			var too_close := false
			for s in used_spots:
				if pt.distance_to(s) < 130.0:
					too_close = true
					break
			if not too_close and d < best_dist:
				best_dist = d
				best_idx = idx

		if best_idx >= 0:
			gen_spot = available_chokes[best_idx]
			available_chokes.remove_at(best_idx)
		else:
			gen_spot = map.find_free_spot(rng, level["areas"]["any"], 36, 36)

		if gen_spot != Vector2.INF:
			power_generators.append(Ent.PowerGenerator.new(gen_spot.x, gen_spot.y))
			used_spots.append(gen_spot)

	for pt in available_chokes:
		if barrels.size() >= target_barrels:
			break
		var safe := true
		for h in p_homes:
			if pt.distance_to(h) < 90.0:
				safe = false
				break
		for s in used_spots:
			if pt.distance_to(s) < 55.0:
				safe = false
				break
		if safe:
			barrels.append(Ent.ExplosiveBarrel.new(pt.x, pt.y))
			used_spots.append(pt)

	while barrels.size() < target_barrels:
		var spot := map.find_free_spot(rng, level["areas"]["any"], 24, 24)
		if spot == Vector2.INF:
			break
		var safe := true
		for h in p_homes:
			if spot.distance_to(h) < 90.0:
				safe = false
				break
		for s in used_spots:
			if spot.distance_to(s) < 55.0:
				safe = false
				break
		if safe:
			barrels.append(Ent.ExplosiveBarrel.new(spot.x, spot.y))
			used_spots.append(spot)
		else:
			break

func _setup_defense_base() -> void:
	var home = level["homes"]["player"]
	base = {
		"x": home.x, "y": home.y,
		"max_hp": float(Cfg.MODES["defense"]["base_hp"]),
		"hp": float(Cfg.MODES["defense"]["base_hp"]),
		"radius": float(Cfg.MODES["defense"]["base_radius"]),
	}

func _setup_defense_wave_start() -> void:
	wave = 0
	wave_state = "delay"
	wave_timer = int(Cfg.MODES["defense"]["start_delay"])

func _setup_wave(n: int) -> void:
	wave = n
	wave_state = "active"
	wave_started.emit(n)
	var base_size := Cfg.DEFENSE_FIRST_WAVE
	var level_bonus := 0
	if Cfg.DEFENSE_PLAYER_LEVEL_BONUS:
		level_bonus = mini(Cfg.DEFENSE_LEVEL_BONUS_CAP, maxi(0, player_level - 1))
	var wave_growth := n - 1
	var size := mini(Cfg.DEFENSE_WAVE_CAP, base_size + level_bonus + wave_growth)
	defense_wave_size = size
	ramp = minf(Cfg.RAMP_MAX, 1.0 + float(n - 1) * Cfg.DEFENSE_RAMP_STEP)
	for i in size:
		_spawn_bot("enemy", "enemy")
	var total_waves := int(Cfg.MODES["defense"]["waves"])
	var endless_boss := n > total_waves and (n - total_waves) % Cfg.DEFENSE_ENDLESS_BOSS_EVERY == 0
	if Cfg.DEFENSE_BOSS_WAVES.has(n) or endless_boss:
		_spawn_boss()
	wave_timer = Cfg.DEFENSE_WAVE_TIMEOUT
	if n <= total_waves:
		feed.emit(I18n.t("feed.wave",
			{"cur": n, "total": total_waves, "n": size},
			"🌊 Волна %d из %d: %d %s" % [n, total_waves, size,
				I18n.plural(size, "враг", "врага", "врагов")]),
			Color("#ff8833"))
	else:
		feed.emit(I18n.t("feed.wave.endless", {"cur": n, "n": size},
			"🌊 Волна %d: %d %s" % [n, size, I18n.plural(size, "враг", "врага", "врагов")]),
			Color("#ff8833"))

func _spawn_boss() -> Tank:
	boss_alive = false
	var boss_pool := ["boss", "boss_rammer", "boss_chimera"]
	var boss_id: String = boss_pool[int(rng.nextf() * boss_pool.size()) % boss_pool.size()]
	var tank := _spawn_bot("enemy", "enemy", boss_id)
	boss_alive = true
	return tank

func _spawn_ffa_boss() -> Tank:
	boss_alive = false
	var team_name := "boss_%d" % (tanks.size() + 1)
	var boss_pool := ["boss", "boss_rammer", "boss_chimera"]
	var boss_id: String = boss_pool[int(rng.nextf() * boss_pool.size()) % boss_pool.size()]
	var tank := _spawn_bot(team_name, "enemy", boss_id)
	boss_alive = true
	return tank

func _boss_stat_mult() -> Dictionary:
	var extra_players := maxf(0.0, float(players.size() - 1))
	var wave_depth := 0.0
	if mode == "defense" and wave > 0:
		wave_depth = maxf(0.0, float(wave - 1))
	var hp_mult := (1.0 + extra_players * Cfg.BOSS_HP_PER_EXTRA_PLAYER) \
		* (1.0 + wave_depth * Cfg.BOSS_HP_PER_WAVE)
	var dmg_mult := (1.0 + extra_players * Cfg.BOSS_DMG_PER_EXTRA_PLAYER) \
		* (1.0 + wave_depth * Cfg.BOSS_DMG_PER_WAVE)
	return {
		"hp": clampf(hp_mult, 1.0, Cfg.BOSS_HP_MULT_CAP),
		"dmg": clampf(dmg_mult, 1.0, Cfg.BOSS_DMG_MULT_CAP),
	}

func _update_defense() -> void:
	if finished_flag or base == null:
		return

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

	if float(base["hp"]) <= 0.0:
		_finish(I18n.t("winner.horde", {}, "Орда"), -1, "",
			I18n.t("reason.defenseBase", {"n": wave},
				"База уничтожена на волне %d — оборона пала" % wave))
		return

	if wave_state == "delay":
		if _alive_enemy_count() == 0 and float(base["hp"]) < float(base["max_hp"]):
			base["hp"] = minf(float(base["max_hp"]),
				float(base["hp"]) + float(base["max_hp"]) * Cfg.DEFENSE_BASE_REGEN_PER_TICK)
		wave_timer -= 1
		if wave_timer <= 0:
			_setup_wave(wave + 1)
		return

	if _alive_enemy_count() > 0:
		wave_timer -= 1
		if wave_timer <= 0:
			_setup_wave(wave + 1)
		return

	if wave == int(Cfg.MODES["defense"]["waves"]):
		match_rewards["wins"] += Cfg.REWARD_WIN
		reward.emit("win", Cfg.REWARD_WIN, players[0].name if players.size() > 0 else "")
		feed.emit(I18n.t("feed.defenseEndless", {"n": wave},
			"🌊 Все %d волн отбиты — оборона продолжается без конца!" % wave), Color("#ffee55"))
	wave_state = "delay"
	wave_timer = int(Cfg.MODES["defense"]["wave_delay"])

func _alive_enemy_count() -> int:
	var n := 0
	for tank in tanks:
		if tank.alive and tank.is_bot:
			n += 1
	return n

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

func _setup_koth() -> void:
	time_limit = int(Cfg.MODES["koth"]["duration"])
	flood_duration = int(Cfg.MODES["koth"]["flood_duration"])
	_scatter_mines()
	flood_tiles = []
	for r in map.rows:
		for c in map.cols:
			var tile := map.get_tile(r, c)
			if tile == Cfg.T_WALL:
				continue
			var depth: int = mini(mini(r, map.rows - 1 - r), mini(c, map.cols - 1 - c))
			flood_tiles.append([depth, r, c])
	flood_tiles.sort_custom(func(a, b): return a[0] < b[0])
	flood_idx = 0
	max_flood_depth = mini(map.rows, map.cols) / 2
	flood_level = 0.0

func _scatter_mines() -> void:
	var empty := []
	for r in range(2, map.rows - 2):
		for c in range(2, map.cols - 2):
			if map.get_tile(r, c) == Cfg.T_EMPTY:
				empty.append([r, c])
	if empty.is_empty():
		return
	var count := maxi(1, int(float(empty.size()) * Cfg.MINE_SCATTER_FRACTION))
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
		var near_tank := false
		for t in tanks:
			if t.alive and Vector2(t.x - x, t.y - y).length() < Cfg.TILE * 2:
				near_tank = true
				break
		if near_tank:
			continue
		mines.append(Ent.Mine.new(x, y, null, Cfg.SCATTER_MINE_LIFE))
		placed += 1

func _update_flood() -> void:
	flood_level = (float(tick) / float(flood_duration)) * float(max_flood_depth)
	while flood_idx < flood_tiles.size():
		var t = flood_tiles[flood_idx]
		if float(t[0]) > flood_level:
			break
		if map.get_tile(t[1], t[2]) != Cfg.T_WATER:
			map.set_tile(t[1], t[2], Cfg.T_WATER)
		flood_idx += 1

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
				maybe_summon_storm(tank.owner)
				Sfx.play("pickup")
				damage_number.emit(tank.x, tank.y - 26, String(perk["icon"]), Color("#ff88ff"))
				feed.emit(I18n.t("feed.perkPicked",
					{"name": tank.name, "icon": perk["icon"], "perk": I18n.dn(perk, "name", "perk")},
					"%s подобрал перк %s %s" % [tank.name, perk["icon"], perk["name"]]), Color("#ff88ff"))
			else:
				if tank.perk_ids.size() < Cfg.BOT_MAX_PERKS and not tank.perk_ids.has(drop.perk_id):
					tank.perk_ids.append(drop.perk_id)
					tank.recompute()
					check_tank_synergies(tank)
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

func step() -> void:
	if finished_flag:
		return
	tick += 1
	Sfx.advance()
	weather.update()
	if mode == "koth":
		_update_flood()
	_update_storm()
	_update_shockwaves()
	_update_lightning_lord()
	_update_treefall()

	tank_grid.rebuild(tanks)
	for tank in tanks:
		tank.update(self)
	tank_grid.rebuild(tanks)
	_separate_tanks()

	for b in bullets:
		b.update(self)
	var live_bullets := []
	for b in bullets:
		if b.alive:
			live_bullets.append(b)
	bullets = live_bullets
	# Даёт ботам (BotBrain.find_incoming_bullet) искать угрожающие пули по
	# сетке вместо перебора всех пуль на карте на каждого бота.
	bullet_grid.rebuild(bullets)

	for m in mines:
		m.update(self)
	var live_mines := []
	for m in mines:
		if m.alive:
			live_mines.append(m)
	mines = live_mines
	_update_acid_pools()

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

	# Интерактив арены: взрывные бочки и генераторы поля
	for b in barrels:
		b.update(self)
	for tank in tanks:
		if not tank.alive:
			continue
		for b in barrels:
			if not b.alive:
				continue
			var dx: float = tank.x - b.x
			var dy: float = tank.y - b.y
			var col_r: float = tank.hit_r + b.radius
			if dx * dx + dy * dy <= col_r * col_r:
				b.hit(25.0, tank, self)
	var live_barrels := []
	for b in barrels:
		if b.alive:
			live_barrels.append(b)
	barrels = live_barrels

	for g in power_generators:
		g.update(self)

	_update_rammer_meltdowns()

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
	if mode == "tutorial":
		_update_tutorial()
	_update_respawns()
	_update_ramp()

	for p in players:
		p.tick()
		p.update_camera()

	if not finished_flag:
		_check_victory()

func _separate_tanks() -> void:
	for a in tanks:
		if not a.alive:
			continue
		for b in tank_grid.query(a.x, a.y, 32.0):
			if b.id <= a.id or not b.alive:
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
		var hp_mult := float(tank.enemy_type.get("hp_mult", 1.0)) if not tank.enemy_type.is_empty() else 1.0
		tank.base_max_hp = round(float(difficulty["enemy_hp"]) * hp_mult * ramp * tank.boss_stat_mult)
		tank.recompute()
	feed.emit(I18n.t("feed.ramp", {}, "Враги стали сильнее!"), Color("#ff8833"))

func deal_damage(target, amount: float, attacker, source: String) -> float:
	if target == null or not target.alive or amount <= 0.0:
		return 0.0
	if attacker != null and attacker.alive and attacker.flags.has("berserk"):
		var ratio: float = attacker.hp / attacker.max_hp if attacker.max_hp > 0.0 else 0.0
		if ratio <= 0.4:
			amount *= 1.6
	var is_ambush: bool = attacker != null and source == "bullet" \
		and (attacker.ability_active("silencer") \
			or target.last_attacker != attacker \
			or tick - target.last_attacker_tick > Cfg.AMBUSH_UNAWARE_TICKS)
	var is_stealth_crit := false
	if is_ambush:
		if attacker.flags.has("predator") and attacker.flags.has("forest") and attacker.flags.has("shadow"):
			amount *= Cfg.STEALTH_HUNTER_CRIT_MULT
			is_stealth_crit = true
		else:
			var ambush_mult := float(attacker.mods["ambushDmgMult"])
			if attacker.ability_active("silencer"):
				ambush_mult = maxf(ambush_mult, Cfg.SILENCER_AMBUSH_MULT)
			if ambush_mult > 1.0:
				amount *= ambush_mult

	var is_sniper_crit := false
	if source == "bullet" and attacker != null and attacker.alive \
			and attacker.flags.has("sniper") and attacker.flags.has("evasion") and attacker.flags.has("keenEar"):
		var dx_gs: float = attacker.x - target.x
		var dy_gs: float = attacker.y - target.y
		if dx_gs * dx_gs + dy_gs * dy_gs >= Cfg.GHOST_SNIPER_RANGE * Cfg.GHOST_SNIPER_RANGE:
			amount *= Cfg.GHOST_SNIPER_CRIT_MULT
			is_sniper_crit = true

	var is_corroded_hit := false
	if source != "acid" and target.acid_stacks > 0 and target.acid_attacker != null \
			and target.acid_attacker.flags.has("corrodingArmor"):
		amount *= Cfg.CORRODING_ARMOR_MULT
		is_corroded_hit = true

	# Ребаланс урона боссов и защита от ваншота
	if attacker != null and attacker.alive and attacker.is_boss:
		if mode == "koth" and target != null and not target.is_player_controlled and not target.is_boss:
			amount *= Cfg.BOSS_KOTH_BOT_DMG_MULT
		if target != null and target.is_player_controlled:
			if target.boss_damage_grace_ticks > 0 and source == "bullet":
				amount *= Cfg.BOSS_BURST_GRACE_REDUCTION
			elif amount >= target.max_hp * 0.20:
				target.boss_damage_grace_ticks = Cfg.BOSS_BURST_GRACE_TICKS
			amount = minf(amount, target.max_hp * Cfg.BOSS_HIT_CAP_FRACTION)

	var res: Dictionary = target.take_damage(self, amount, attacker, source)
	if bool(res["evaded"]) or float(res["applied"]) <= 0.0:
		return 0.0

	if is_stealth_crit:
		particles.burst(target.x, target.y, [Color("#10b981"), Color("#34d399"), Color.WHITE], 20, 3, 7, 18, 36, rng)
		damage_number.emit(target.x, target.y - 34, "🌿 ЗАСАДА! ×2.5", Color("#10b981"))
		add_shake(4.5, target.x, target.y)
	if is_sniper_crit:
		particles.burst(target.x, target.y, [Color("#a855f7"), Color("#c084fc"), Color.WHITE], 20, 3, 7, 20, 40, rng)
		damage_number.emit(target.x, target.y - 34, "🎯 СНАЙПЕР! +60%", Color("#a855f7"))
		add_shake(4.0, target.x, target.y)
	if is_corroded_hit:
		particles.burst(target.x, target.y, [Color("#84cc16"), Color("#a3e635")], 8, 2, 4, 10, 20, rng)
		damage_number.emit(target.x, target.y - 34, "🦴 РАЗЪЕДАНИЕ +40%", Color("#84cc16"))

	if is_ambush and float(attacker.mods["ambushDashTicks"]) > 0.0:
		attacker.turbo_timer = maxi(attacker.turbo_timer, int(attacker.mods["ambushDashTicks"]))

	target.last_attacker = attacker
	target.last_attacker_tick = tick
	if target.brain != null and attacker != null and attacker != target and attacker.alive and are_hostile(target, attacker):
		target.brain.on_damaged(attacker)

	if float(res["reflected"]) > 0.0 and attacker != null and attacker.alive:
		deal_damage(attacker, float(res["reflected"]), target, "reflect")
		if (source == "bullet" or source == "ram") and attacker.stun_ticks <= 0 and not attacker.is_boss:
			attacker.stun_ticks = Cfg.REFLECT_STUN_TICKS
			particles.burst(attacker.x, attacker.y, [Color("#38bdf8"), Color.WHITE], 10, 2, 4, 10, 20, rng)
			damage_number.emit(attacker.x, attacker.y - 30, "⚡ СТАН 0.8с!", Color("#38bdf8"))

	if attacker != null:
		attacker.damage_dealt += float(res["applied"])
		if attacker.owner != null:
			attacker.owner.damage_dealt += float(res["applied"])
			player_damage.emit(attacker.owner, float(res["applied"]))
		if float(attacker.mods["lifestealFraction"]) > 0.0 and attacker.alive:
			if tick - attacker.vampire_heal_window_tick >= 60:
				attacker.vampire_heal_window_tick = tick
				attacker.vampire_heal_this_sec = 0.0
			var max_heal_allowed: float = maxf(0.0, 12.0 - attacker.vampire_heal_this_sec)
			var raw_heal := float(res["applied"]) * float(attacker.mods["lifestealFraction"])
			var heal := floorf(minf(raw_heal, max_heal_allowed))
			if heal > 0.0:
				attacker.vampire_heal_this_sec += heal
				attacker.hp = minf(attacker.max_hp, attacker.hp + heal)

	var applied_int := int(round(float(res["applied"])))
	if applied_int > 0:
		var num_color: Color = Color("#84cc16") if (source == "acid" or source == "acid_stream") else (
			Color("#ff4444") if target.owner != null else Color("#ffee55")
		)
		damage_number.emit(target.x, target.y - 20, "-%d" % applied_int, num_color)
	if target.owner != null:
		if source == "acid_stream":
			target.owner.damage_flash = maxi(target.owner.damage_flash, 5)
			target.owner.clean_streak = 0
		else:
			target.owner.damage_flash = 12
			target.owner.shake = maxf(target.owner.shake, 5.0)
			target.owner.clean_streak = 0
			Sfx.play("hit")
	elif source == "bullet":
		Sfx.play("hit", target.x, target.y)

	if bool(res["killed"]):
		_kill_tank(target, attacker, source)
	return float(res["applied"])

func execute_frozen_kill(victim, attacker) -> void:
	if victim == null or not victim.alive:
		return
	var is_boss: bool = not victim.enemy_type.is_empty() and bool(victim.enemy_type.get("boss", false))
	var amount: float = victim.max_hp * Cfg.FROZEN_BOSS_RAM_FRACTION if is_boss else victim.hp
	victim.hp = maxf(0.0, victim.hp - amount)
	victim.freeze_ticks = 0
	victim.freeze_max_ticks = 0
	if is_boss and victim.is_rammer_boss:
		victim.rammer_state = "cooldown"
		victim.rammer_cooldown_ticks = Cfg.RAMMER_COOLDOWN_TICKS
		victim.rammer_daze_ticks = Cfg.RAMMER_DAZE_TICKS
		victim.rammer_charge_ticks = 0
		victim.rammer_telegraph_ticks = 0
		victim.rammer_spin_ticks = 0
		victim.rammer_charge_hit.clear()
		victim.rammer_spin_hit.clear()
		victim.vx = 0.0
		victim.vy = 0.0
	victim.last_attacker = attacker
	victim.last_attacker_tick = tick
	if attacker != null:
		attacker.damage_dealt += amount
		if attacker.owner != null:
			attacker.owner.damage_dealt += amount
			player_damage.emit(attacker.owner, amount)

	# Special Ice Shatter VFX & SFX!
	spawn_shockwave(victim.x, victim.y, 90.0, "freeze", Color("#38bdf8"), 22)
	particles.burst(victim.x, victim.y, [Color("#00f0ff"), Color("#aaeeff"), Color.WHITE, Color("#38bdf8")], 36, 4, 9, 28, 60, rng)
	Sfx.play("crack", victim.x, victim.y)
	add_shake(7.0, victim.x, victim.y)
	if weather != null:
		weather.flash = maxf(weather.flash, 0.4)

	if is_boss:
		damage_number.emit(victim.x, victim.y - 34, "❄️ ЛЕДЯНОЙ УДАР! -%d" % int(round(amount)), Color("#00f0ff"))
	else:
		damage_number.emit(victim.x, victim.y - 34, "❄️ РАСКОЛ ЛЬДА!", Color("#00f0ff"))

	if victim.owner != null:
		victim.owner.damage_flash = 12
		victim.owner.shake = maxf(victim.owner.shake, 8.0)
		Sfx.play("hit")
	if victim.hp <= 0.0:
		_kill_tank(victim, attacker, "ice")

func maybe_freeze_shot_kill(victim, attacker) -> void:
	if victim == null or not victim.alive or attacker == null or not attacker.alive:
		return
	if not (attacker.flags.has("deepFreeze") and attacker.flags.has("frostDash") and attacker.flags.has("chilledBarrel")):
		return
	if victim.is_boss:
		return
	execute_frozen_kill(victim, attacker)

func _juggernaut_shock(killer, ox: float, oy: float) -> void:
	spawn_shockwave(ox, oy, Cfg.JUGGERNAUT_SHOCK_R, "ram", Color("#ef4444"), 24)
	for other in tanks:
		if other == killer or not other.alive or not are_hostile(killer, other):
			continue
		var dx: float = other.x - ox
		var dy: float = other.y - oy
		var d := sqrt(dx * dx + dy * dy)
		if d > Cfg.JUGGERNAUT_SHOCK_R or d <= 0.001:
			continue
		var k: float = 1.0 - d / Cfg.JUGGERNAUT_SHOCK_R
		deal_damage(other, Cfg.JUGGERNAUT_SHOCK_DMG * k, killer, "blast")
		other.vx += (dx / d) * Cfg.JUGGERNAUT_SHOCK_PUSH * k
		other.vy += (dy / d) * Cfg.JUGGERNAUT_SHOCK_PUSH * k
	particles.burst(ox, oy, [Color("#ffaa33"), Color("#ff5533"), Color.WHITE], 24, 3, 7, 20, 48, rng)
	damage_number.emit(ox, oy - 32, "💥 СОКРУШИТЕЛЬНЫЙ ТАРАН!", Color("#ef4444"))
	Sfx.play("explosion", ox, oy)
	add_shake(8.0, ox, oy)

func _start_rammer_meltdown(victim) -> void:
	rammer_meltdowns.append({
		"x": victim.x,
		"y": victim.y,
		"ticks": Cfg.RAMMER_MELTDOWN_TICKS,
		"max_ticks": Cfg.RAMMER_MELTDOWN_TICKS,
		"name": victim.name,
		"victim": victim
	})
	Sfx.play("siren", victim.x, victim.y)
	feed.emit(I18n.t("feed.rammerMeltdown", {"name": victim.name},
		"⚠️ ПЕРЕГРУЗКА РЕАКТОРА %s! ВЗРЫВ ЧЕРЕЗ 1.5 СЕК — НАЗАД!" % victim.name), Color("#ef4444"))
	add_shake(12.0, victim.x, victim.y)

func _update_rammer_meltdowns() -> void:
	if rammer_meltdowns.is_empty():
		return
	var kept := []
	for m in rammer_meltdowns:
		m["ticks"] -= 1
		var progress: float = 1.0 - (float(m["ticks"]) / float(m["max_ticks"]))
		if tick % 5 == 0:
			particles.burst(m["x"], m["y"], [Color("#ef4444"), Color("#f97316"), Color("#fbbf24")], 6, 2, 5, 12, 28, rng)
			add_shake(2.0 * progress, m["x"], m["y"])
		if int(m["ticks"]) <= 0:
			_rammer_death_explosion(m["victim"])
		else:
			kept.append(m)
	rammer_meltdowns = kept

func _rammer_death_explosion(victim) -> void:
	var exp_r: float = Cfg.RAMMER_EXPLOSION_RADIUS
	spawn_shockwave(victim.x, victim.y, exp_r, "ram", Color("#ff4400"), 50)
	spawn_shockwave(victim.x, victim.y, exp_r * 0.6, "shockwave", Color("#ffaa00"), 36)
	spawn_shockwave(victim.x, victim.y, 100.0, "blast", Color.WHITE, 24)

	particles.burst(victim.x, victim.y, [Color("#ff3300"), Color("#ff7700"), Color("#ffee22"), Color.WHITE, Color("#222222")], 64, 4, 10, 24, 60, rng)
	add_shake(26.0, victim.x, victim.y)
	Sfx.play("explosion", victim.x, victim.y)
	Sfx.play("thunder", victim.x, victim.y)

	feed.emit(I18n.t("feed.rammerExplode", {"name": victim.name},
		"💥 Реактор %s детонирует мощным взрывом (25м)!" % victim.name), Color("#ff4422"))

	for other in tanks.duplicate():
		if other == victim or not other.alive or not are_hostile(victim, other):
			continue
		var dx: float = other.x - victim.x
		var dy: float = other.y - victim.y
		var dist := sqrt(dx * dx + dy * dy)
		if dist > exp_r:
			continue
		var falloff := 1.0 - (dist / exp_r)
		var dmg: float = minf(Cfg.RAMMER_EXPLOSION_DMG * falloff, other.max_hp * Cfg.BOSS_HIT_CAP_FRACTION)
		deal_damage(other, dmg, victim, "blast")
		var push := 14.0 * falloff
		if dist > 0.001:
			other.vx += (dx / dist) * push
			other.vy += (dy / dist) * push

	var reach := int(ceilf(140.0 / float(Cfg.TILE)))
	var v_row: int = map.row_at(victim.y)
	var v_col: int = map.col_at(victim.x)
	for dr in range(-reach, reach + 1):
		for dc in range(-reach, reach + 1):
			var r := v_row + dr
			var c := v_col + dc
			if map.get_tile(r, c) == Cfg.T_BRICK:
				hit_building(r, c, 999.0, "blast", c * Cfg.TILE + 16, r * Cfg.TILE + 16, victim)
			elif map.get_tile(r, c) == Cfg.T_TREE:
				map.set_tile(r, c, Cfg.T_EMPTY)
				particles.burst(c * Cfg.TILE + 16, r * Cfg.TILE + 16, [Cfg.tree, Cfg.tree_dark], 8, 2, 4, 12, 20, rng)

	if mode == "defense" and base != null:
		var d_base := Vector2(base["x"] - victim.x, base["y"] - victim.y).length()
		if d_base <= exp_r:
			var remaining_cap: float = maxf(0.0, Cfg.RAMMER_BASE_MAX_TOTAL_DMG - victim.rammer_base_damage_dealt)
			if remaining_cap > 0.0:
				var falloff := 1.0 - (d_base / exp_r)
				var applied_death_base_dmg: float = minf(remaining_cap, 50.0 * falloff)
				victim.rammer_base_damage_dealt += applied_death_base_dmg
				base["hp"] = maxf(0.0, float(base["hp"]) - applied_death_base_dmg)
				damage_number.emit(base["x"], base["y"] - 30, "-%d БАЗА!" % int(applied_death_base_dmg), Color("#ff4444"))

func spawn_acid_pool(px: float, py: float, r: float, owner_tank, life: int = Cfg.CHIMERA_ACID_POOL_DURATION) -> void:
	acid_pools.append(Ent.AcidPool.new(px, py, r, owner_tank, life))

func _update_acid_pools() -> void:
	if acid_pools.is_empty():
		return
	var live_pools := []
	for pool in acid_pools:
		pool.timer -= 1
		if pool.timer <= 0:
			continue
		live_pools.append(pool)

		var r2: float = pool.radius * pool.radius
		for tank in tank_grid.query(pool.x, pool.y, pool.radius):
			if not tank.alive or not are_hostile(pool.owner, tank):
				continue
			var dx: float = tank.x - pool.x
			var dy: float = tank.y - pool.y
			if dx * dx + dy * dy <= r2:
				tank.surface_speed *= 0.65
				deal_damage(tank, Cfg.CHIMERA_ACID_POOL_DPS, pool.owner, "acid")
				tank.apply_acid(self, pool.owner, 0.4, 1)
				if tick % 8 == 0:
					particles.burst(tank.x, tank.y, [Color("#84cc16"), Color("#a3e635")], 2, 1, 2, 6, 12, rng)

		if tick % 12 == 0 and rng.nextf() < 0.6:
			var ang: float = rng.nextf() * TAU
			var dist: float = rng.nextf() * float(pool.radius) * 0.7
			particles.burst(pool.x + cos(ang) * dist, pool.y + sin(ang) * dist,
				[Color("#84cc16"), Color("#a3e635"), Color("#4d7c0f")], 2, 1, 3, 8, 16, rng)

	acid_pools = live_pools

func spawn_chimera_clone(parent_tank: Tank, side: float) -> Tank:
	var diff := difficulty
	var clone_hp := Cfg.CHIMERA_CLONE_HP * ramp * parent_tank.boss_stat_mult
	var offset_dist := 44.0
	var perp := parent_tank.body_angle + (PI * 0.5) * side
	var spawn_pos := Vector2(parent_tank.x + cos(perp) * offset_dist, parent_tank.y + sin(perp) * offset_dist)
	if map.is_blocked_rect(spawn_pos.x, spawn_pos.y, Cfg.TANK_W, Cfg.TANK_H):
		spawn_pos = Vector2(parent_tank.x, parent_tank.y)

	var clone := Tank.new({
		"x": spawn_pos.x, "y": spawn_pos.y, "team": parent_tank.team,
		"name": "«Фантом-Клон»", "owner": null,
		"max_hp": round(clone_hp),
		"speed": parent_tank.speed * 1.05,
		"fire_rate": maxi(4, int(round(float(diff["enemy_fire_rate"]) * 1.1))),
		"color_key": "boss_chimera",
		"chassis": "boss_chimera",
		"dmg_scale": parent_tank.dmg_scale * 0.6,
	})
	clone.net_id = Net.next_tank_id()
	clone.is_chimera_clone = true
	clone.chimera_clone_parent = parent_tank
	clone.perk_ids = []
	clone.recompute()

	clone.brain = BotBrain.new({
		"accuracy": 0.8,
		"react_time": 15,
		"role": "attacker",
		"fire_range": 150.0,
		"keep_min": 50.0,
		"keep_max": 130.0,
		"lobbed": false,
		"survival": mode == "koth",
		"rng": rng,
	})

	particles.burst(spawn_pos.x, spawn_pos.y, [Color("#84cc16"), Color("#00ffff"), Color("#ff00ff"), Color.WHITE], 24, 3, 6, 16, 28, rng)
	tanks.append(clone)
	if Net.role == "host":
		Net.host_tank_spawned(tank_info(clone))
	return clone

func _chimera_death_acid(victim: Tank) -> void:
	var exp_r := 180.0
	spawn_shockwave(victim.x, victim.y, exp_r, "acid", Color("#84cc16"), 40)
	spawn_shockwave(victim.x, victim.y, exp_r * 0.5, "blast", Color("#a3e635"), 26)

	particles.burst(victim.x, victim.y, [Color("#84cc16"), Color("#a3e635"), Color("#4d7c0f"), Color.WHITE, Color("#182b18")], 56, 4, 9, 24, 55, rng)
	add_shake(18.0, victim.x, victim.y)
	Sfx.play("explosion", victim.x, victim.y)
	Sfx.play("steam", victim.x, victim.y)

	feed.emit(I18n.t("feed.chimeraExplode", {"name": victim.name},
		"☣️ Едкое ядро %s разгерметизировано — потоп кислоты!" % victim.name), Color("#84cc16"))

	for i in 6:
		var a := float(i) / 6.0 * TAU + (rng.nextf() - 0.5) * 0.4
		var d := 24.0 + rng.nextf() * 45.0
		spawn_acid_pool(victim.x + cos(a) * d, victim.y + sin(a) * d, Cfg.CHIMERA_ACID_POOL_RADIUS, victim, Cfg.CHIMERA_ACID_POOL_DURATION)

	for other in tanks:
		if other == victim or not other.alive or not are_hostile(victim, other):
			continue
		var dx: float = other.x - victim.x
		var dy: float = other.y - victim.y
		var dist := sqrt(dx * dx + dy * dy)
		if dist > exp_r:
			continue
		var falloff := 1.0 - (dist / exp_r)
		var dmg: float = minf(80.0 * falloff, other.max_hp * Cfg.BOSS_HIT_CAP_FRACTION)
		deal_damage(other, dmg, victim, "acid")
		other.apply_acid(self, victim, 1.0, Cfg.ACID_STACK_MAX)

	for t in tanks:
		if t.alive and t.is_chimera_clone and t.chimera_clone_parent == victim:
			deal_damage(t, 9999.0, null, "acid")

func _kill_tank(victim, killer, source: String) -> void:
	if victim.is_rammer_boss:
		_start_rammer_meltdown(victim)
	if victim.is_chimera_boss:
		_chimera_death_acid(victim)
	if source == "ram" and killer != null and killer.alive \
			and killer.flags.has("ram") and killer.flags.has("thickArmor") and killer.flags.has("kamikaze"):
		_juggernaut_shock(killer, victim.x, victim.y)
	victim.on_death(self, killer)
	victim.respawn_timer = Cfg.RESPAWN_DELAY
	if Sets.wrecks:
		wrecks.append(Ent.Wreck.new(victim, rng))

	if not victim.enemy_type.is_empty() and bool(victim.enemy_type.get("boss", false)):
		var any_boss_alive := false
		for t in tanks:
			if t != victim and t.alive and not t.enemy_type.is_empty() and bool(t.enemy_type.get("boss", false)):
				any_boss_alive = true
				break
		boss_alive = any_boss_alive

	if mode == "koth":
		if not victim.enemy_type.is_empty() and bool(victim.enemy_type.get("boss", false)):
			# Drop cluster of 3 epic perks + medkit around the boss
			for i in 3:
				var angle_off: float = float(i) * TAU / 3.0
				_drop_perk_at(victim.x + cos(angle_off) * 36.0, victim.y + sin(angle_off) * 36.0)
			pickups.append(Ent.Pickup.new(victim.x, victim.y, "health", rng))
			particles.burst(victim.x, victim.y, [Color("#ffd700"), Color("#ff00ff"), Color("#00ffff")], 32, 3, 7, 24, 40, rng)
			feed.emit(I18n.t("feed.kothBossKilled", {"name": victim.name},
				"💥 БОСС ПОВЕРЖЕН: %s! 3 эпических трофея и аптечка на арене!" % victim.name), Color("#ffd700"))
			Sfx.play("thunder", victim.x, victim.y)
		else:
			_drop_perk(victim)

	if victim.flag != null:
		var f = victim.flag
		victim.flag = null
		f.drop(victim.x, victim.y, FLAG_RETURN_TIMEOUT)
		flag_event.emit("dropped", f, victim)

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
		if victim.owner.scheme.has_method("release_lock"):
			victim.owner.scheme.release_lock()
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

	var victim_type := ""
	if victim.is_chimera_boss and not victim.is_chimera_clone:
		victim_type = "boss_chimera"
	elif victim.is_chimera_clone:
		victim_type = "chimera_clone"
	elif victim.is_rammer_boss:
		victim_type = "boss_rammer"
	elif not victim.enemy_type.is_empty():
		victim_type = String(victim.enemy_type.get("id", "grunt"))
	elif victim.is_boss:
		victim_type = "boss"
	elif victim.is_bot:
		victim_type = "grunt"

	if victim_type != "":
		Prof.record_bestiary_kill(victim_type)

	if not victim.enemy_type.is_empty() and bool(victim.enemy_type.get("boss", false)):
		var boss_reward := Cfg.REWARD_KILL * 5
		match_rewards["kills"] += boss_reward
		reward.emit("boss", boss_reward, player.name)
		stat.emit("bossKills", 1, "add")
		global_xp.emit(Cfg.XP_PER_KILL * 3)
		player.score += Cfg.SCORE_PER_KILL * 3
		feed.emit(I18n.t("feed.bossKilled", {"name": player.name, "n": boss_reward},
			"%s уничтожил БОССА! +%d 🪙" % [player.name, boss_reward]), Color("#e74c3c"))

	if mode == "ffa":
		var milestone: int = int(player.kills / 5) * 5
		var last_milestone: int = int(_last_ffa_boss_kills.get(player.index, 0))
		if milestone > last_milestone and milestone > 0:
			_last_ffa_boss_kills[player.index] = milestone
			_spawn_ffa_boss()

	player.kill_ticks.append(tick)
	var cutoff := tick - 10 * Cfg.TICK_HZ
	while not player.kill_ticks.is_empty() and int(player.kill_ticks[0]) < cutoff:
		player.kill_ticks.pop_front()
	stat.emit("rapidKills", player.kill_ticks.size(), "max")

	player.clean_streak += 1
	stat.emit("cleanStreak", player.clean_streak, "max")
	stat.emit("totalKills", 1, "add")

	if source == "ram":
		stat.emit("ramKills", 1, "add")

	var killer_tank = player.tank
	if killer_tank != null:
		var kill_dist := Vector2(killer_tank.x - victim.x, killer_tank.y - victim.y).length()
		if kill_dist >= 400.0:
			stat.emit("longKills", 1, "add")
		if kill_dist >= 800.0:
			stat.emit("sniperKills", 1, "add")
		if map.tile_at_pixel(killer_tank.x, killer_tank.y) == Cfg.T_BRIDGE:
			stat.emit("bridgeKills", 1, "add")
		if killer_tank.max_hp > 0.0 and killer_tank.hp / killer_tank.max_hp <= 0.4:
			stat.emit("lowHpKills", 1, "add")

	if killer_tank != null:
		if float(killer_tank.mods["turboOnKill"]) > 0.0:
			killer_tank.turbo_timer = int(killer_tank.mods["turboOnKill"])
		if float(killer_tank.mods["shadowOnKill"]) > 0.0:
			killer_tank.shadow_timer += int(killer_tank.mods["shadowOnKill"])

func _maybe_give_bot_perk(bot) -> void:
	if bot.perk_ids.size() >= Cfg.BOT_MAX_PERKS:
		return
	if rng.nextf() >= Cfg.BOT_PERK_CHANCE:
		return
	var available := []
	for p in Perks.BOT_LIST:
		if bool(p.get("boss_only", false)):
			continue
		if not bot.perk_ids.has(p["id"]):
			available.append(p)
	if available.is_empty():
		return
	var perk: Dictionary = rng.pick(available)
	bot.perk_ids.append(perk["id"])
	bot.recompute()
	particles.burst(bot.x, bot.y - 20, [Color("#ffee55"), Color("#ffffaa")], 8, 2, 4, 15, 20, rng)
	bot_perk.emit(bot, perk)

func _drop_perk(victim) -> void:
	_drop_perk_at(victim.x, victim.y)

func _drop_perk_at(px: float, py: float) -> void:
	var allowed := []
	for p in Perks.LIST:
		if Perks.is_perk_allowed_in_mode(p["id"], mode):
			allowed.append(p)
	if allowed.is_empty():
		return
	var perk: Dictionary = rng.pick(allowed)
	perk_drops.append(Ent.PerkPickup.new(px, py, String(perk["id"]), rng))
	particles.burst(px, py, [Color("#ff88ff"), Color.WHITE], 8, 2, 4, 12, 18, rng)

const MAX_DEBRIS := 300

func hit_building(row: int, col: int, amount: float, source: String,
		x: float, y: float, owner_tank) -> void:
	var mat := Materials.at(row, col, map.get_tile(row, col))
	if owner_tank != null and amount > 0.0:
		amount *= float(owner_tank.mods.get("buildingDmgMult", 1.0))
		match String(mat["id"]):
			"wood":
				amount *= float(owner_tank.mods.get("woodDmgMult", 1.0))
			"brick":
				amount *= float(owner_tank.mods.get("brickDmgMult", 1.0))
			"adobe":
				amount *= float(owner_tank.mods.get("brickDmgMult", 1.0))
			"concrete":
				amount *= float(owner_tank.mods.get("concreteDmgMult", 1.0))
			"metal":
				amount *= float(owner_tank.mods.get("metalDmgMult", 1.0))
		if owner_tank.ability_active("breaker"):
			amount *= Cfg.BREAKER_BUILDING_MULT
	particles.burst(x, y, [mat["light"], mat["base"], mat["dark"]], 5, 2, 4, 8, 16, rng)
	if int(mat["sparks"]) > 0 and source != "blast":
		particles.burst(x, y, [Color("#fff2c0"), Color("#ffb347")], 3, 1, 2, 6, 12, rng)
	if amount <= 0.0:
		return
	if map.apply_damage(row, col, amount, source):
		_destroy_building(row, col, mat, owner_tank)

func _destroy_building(row: int, col: int, mat: Dictionary, owner_tank) -> void:
	if mode == "tutorial":
		tut_bricks_destroyed += 1
	var cx := col * Cfg.TILE + Cfg.TILE * 0.5
	var cy := row * Cfg.TILE + Cfg.TILE * 0.5

	for i in int(mat["pieces"]):
		if debris.size() >= MAX_DEBRIS:
			debris.pop_front()
		debris.append(Ent.Debris.new(
			cx + (rng.nextf() - 0.5) * Cfg.TILE * 0.6,
			cy + (rng.nextf() - 0.5) * Cfg.TILE * 0.6, mat, rng))

	var dust_amount := 10 + int(mat["pieces"])
	particles.burst(cx, cy, [mat["dust"], mat["light"], mat["base"]],
		dust_amount, 3, 7, 20, 46, rng)
	if int(mat["sparks"]) > 0:
		particles.burst(cx, cy, [Color("#fff2c0"), Color("#ffcc55")],
			int(mat["sparks"]), 1, 3, 10, 22, rng)

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
		var mid := String(mat["id"])
		if mid == "concrete" or mid == "metal":
			stat.emit("concreteDestroyed", 1, "add")

func on_trees_driven(tank, count: int) -> void:
	if tank.owner != null:
		stat.emit("treesDriven", count, "add")

func on_water_entered(tank) -> void:
	if tank.owner != null:
		stat.emit("waterEntries", 1, "add")

func add_shake(amount: float, x: float = INF, y: float = INF) -> void:
	for p in players:
		if is_inf(x) or Vector2(p.camera.x - x, p.camera.y - y).length() < 700.0:
			p.shake = maxf(p.shake, amount * Sets.screen_shake)

func _update_pickups() -> void:
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
			if tank.flags.has("magnet"):
				var pull_dist: float = (tank.owner.pickup_radius if tank.owner != null else Cfg.PICKUP_R) * 2.5
				var dx: float = tank.x - pickup.x
				var dy: float = tank.y - pickup.y
				var d := sqrt(dx * dx + dy * dy)
				if d > 0.001 and d <= pull_dist:
					pickup.x += (dx / d) * 2.8
					pickup.y += (dy / d) * 2.8

		for tank in candidates:
			var radius: float = tank.owner.pickup_radius if tank.owner != null else Cfg.PICKUP_R
			if Vector2(tank.x - pickup.x, tank.y - pickup.y).length() > radius:
				continue
			var heal_bonus: float = float(tank.mods.get("pickupHealMult", 1.0))
			var heal := maxf(1.0, floorf(tank.max_hp * Cfg.PICKUP_HEAL_FRACTION * heal_bonus))
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

func _update_weapon_pickups() -> void:
	for pickup in weapon_pickups:
		if not pickup.active:
			continue
		if pickup.has_method("update"):
			pickup.update()
		if not pickup.active:
			continue
		for tank in tanks:
			if tank.alive and tank.flags.has("magnet"):
				var base_r: float = tank.owner.pickup_radius if tank.owner != null else Cfg.PICKUP_R
				var pull_dist: float = base_r * float(tank.mods.get("pickupRadiusMult", 1.0)) * 2.5
				var dx: float = tank.x - pickup.x
				var dy: float = tank.y - pickup.y
				var d := sqrt(dx * dx + dy * dy)
				if d > 0.001 and d <= pull_dist:
					pickup.x += (dx / d) * 2.8
					pickup.y += (dy / d) * 2.8
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

func _update_flags() -> void:
	for flag in flags:
		if flag.carried:
			continue
		for tank in tanks:
			if not tank.alive:
				continue
			if Vector2(tank.x - flag.x, tank.y - flag.y).length() > 24.0:
				continue

			if flag.team == tank.team:
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

	for flag in flags:
		if flag.carrier != null:
			if not flag.carrier.alive:
				var carrier = flag.carrier
				carrier.flag = null
				flag.drop(carrier.x, carrier.y, FLAG_RETURN_TIMEOUT)
				continue
			flag.x = flag.carrier.x
			flag.y = flag.carrier.y
		elif flag.state == "dropped":
			flag.return_timer -= 1
			if flag.return_timer <= 0:
				_spawn_next_ctf_flag()
				flag_event.emit("returned", flag, null)

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
		if int(team_score[team]) < int(Cfg.MODES["ctf"]["cap_limit"]):
			_spawn_next_ctf_flag()
		break

func _update_respawns() -> void:
	if mode == "koth":
		return
	for tank in tanks:
		if tank.alive:
			continue
		if (mode == "defense" or mode == "tutorial") and tank.is_bot:
			continue
		if mode == "ffa" and tank.is_boss:
			continue
		tank.respawn_timer -= 1
		if tank.respawn_timer > 0:
			continue
		var spot := _free_spot(tank.team)
		tank.respawn(spot.x, spot.y)
		if mode == "tutorial" and tank.owner != null:
			if tutorial_stage == 9:
				tank.cannon_id = "ice"
				tank.set_chassis("light")
				tank.color_key = "p5"
				tank.owner.color_key = "p5"
				tank.owner.equipped_cannon = "ice"
			elif tutorial_stage == 10:
				tank.cannon_id = "acid"
				tank.set_chassis("heavy")
				tank.color_key = "p12"
				tank.owner.color_key = "p12"
				tank.owner.equipped_cannon = "acid"
			else:
				tank.cannon_id = "standard"
				tank.set_chassis("standard")
				tank.color_key = "p1"
				tank.owner.color_key = "p1"
				tank.owner.equipped_cannon = "standard"
				if tutorial_stage == 8:
					tank.ability_id = "bulwark"
					tank.ability_cd = 0
		if not tank.enemy_type.is_empty() and bool(tank.enemy_type.get("boss", false)):
			boss_alive = true
		if tank.owner != null:
			tank.owner.update_camera()
			respawned.emit(tank.owner)

func get_tutorial_task_info() -> Dictionary:
	var info := {
		"stage": tutorial_stage,
		"total": 12,
		"title": "",
		"desc": "",
		"keys": "",
		"progress_text": "",
		"progress": 0.0,
		"done": false
	}
	match tutorial_stage:
		1:
			info["title"] = "ЗАДАНИЕ 1/12: ХОДОВАЯ ЧАСТЬ"
			info["desc"] = "Нажмите [W] для движения вперед и [S] для движения назад"
			info["keys"] = "[W] / [S]"
			var fwd_ok := tut_dist_fwd >= 35.0
			var bwd_ok := tut_dist_bwd >= 25.0
			info["progress_text"] = "Вперед: %s (%d/35 px)   Назад: %s (%d/25 px)" % [
				"✔" if fwd_ok else "—", int(minf(35.0, tut_dist_fwd)),
				"✔" if bwd_ok else "—", int(minf(25.0, tut_dist_bwd))
			]
			info["progress"] = (minf(35.0, tut_dist_fwd) / 35.0 + minf(25.0, tut_dist_bwd) / 25.0) * 0.5
		2:
			info["title"] = "ЗАДАНИЕ 2/12: МАНЕВРИРОВАНИЕ"
			info["desc"] = "Используйте [A] и [D] для поворота и доберитесь до контрольной точки"
			info["keys"] = "[A] / [D]"
			var dist := 0.0
			if not players.is_empty() and players[0].tank != null:
				dist = Vector2(players[0].tank.x - tutorial_marker.x, players[0].tank.y - tutorial_marker.y).length()
			info["progress_text"] = "Дистанция до точки: %d м" % int(dist / 32.0)
			info["progress"] = clampf(1.0 - (dist / 400.0), 0.1, 1.0)
		3:
			info["title"] = "ЗАДАНИЕ 3/12: ПРИЦЕЛИВАНИЕ И СТРЕЛЬБА"
			info["desc"] = "Наведите башню [Мышь] и уничтожьте учебные мишени [ЛКМ / Пробел]"
			info["keys"] = "[ЛКМ] / [Space]"
			var killed := 0
			var total_t := maxi(1, tutorial_targets.size())
			for t in tutorial_targets:
				if not t.alive:
					killed += 1
			info["progress_text"] = "Уничтожено мишеней: %d / %d" % [killed, total_t]
			info["progress"] = float(killed) / float(total_t)
		4:
			info["title"] = "ЗАДАНИЕ 4/12: РАЗРУШЕНИЕ УКРЫТИЙ"
			info["desc"] = "Снаряды разрушают кирпичные стены. Пробейте проход ворот [ЛКМ]!"
			info["keys"] = "[ЛКМ]"
			info["progress_text"] = "Разрушено блоков: %d / 2" % [mini(2, tut_bricks_destroyed)]
			info["progress"] = minf(1.0, float(tut_bricks_destroyed) / 2.0)
		5:
			info["title"] = "ЗАДАНИЕ 5/12: ВЗРЫВНЫЕ БОЧКИ"
			info["desc"] = "Выстрелите по бочке [ЛКМ] или протараньте ее для цепного подрыва целей"
			info["keys"] = "[ЛКМ] / Таран"
			var alive_b := 0
			for b in tutorial_barrels:
				if b.alive:
					alive_b += 1
			var total_b := maxi(1, tutorial_barrels.size())
			var destroyed_b := total_b - alive_b
			info["progress_text"] = "Взорвано бочек: %d / %d" % [destroyed_b, total_b]
			info["progress"] = float(destroyed_b) / float(total_b)
		6:
			info["title"] = "ЗАДАНИЕ 6/12: ТАКТИЧЕСКИЙ РЫВОК"
			info["desc"] = "Нажмите [Shift] во время движения для рывка с неуязвимостью (i-frames)"
			info["keys"] = "[Shift]"
			info["progress_text"] = "Совершите тактический рывок через ворота"
			info["progress"] = 0.5
		7:
			info["title"] = "ЗАДАНИЕ 7/12: ТАКТИЧЕСКАЯ МИНА"
			info["desc"] = "Установите мину [E / ПКМ] на пути приближающейся учебной цели"
			info["keys"] = "[E] / [ПКМ]"
			info["progress_text"] = "Подорвите учебный броневик миной"
			info["progress"] = 0.5
		8:
			info["title"] = "ЗАДАНИЕ 8/12: СПОСОБНОСТЬ МАШИНЫ"
			info["desc"] = "Активируйте боевую способность машины [Q / Й] (энергетический щит)"
			info["keys"] = "[Q / Й]"
			info["progress_text"] = "Активируйте способность машины [Q / Й]"
			info["progress"] = 0.5
		9:
			info["title"] = "ЗАДАНИЕ 9/12: ЛЕДЯНОЙ ТАНК — КРИО-ЗАМОРОЗКА"
			info["desc"] = "Криогенные снаряды сковывают врага льдом. Поразите мишень [ЛКМ]!"
			info["keys"] = "[ЛКМ] Выстрел"
			var frozen: bool = tutorial_ice_dummy != null and tutorial_ice_dummy.freeze_ticks > 0
			info["progress_text"] = "✔ Цель заморожена!" if frozen else "Поразите учебную цель ледяным снарядом"
			info["progress"] = 1.0 if frozen else 0.5
		10:
			info["title"] = "ЗАДАНИЕ 10/12: ХИМ-ТАНК — КИСЛОТНЫЙ ЯД"
			info["desc"] = "Химический яд разъедает броню коррозией. Обстреляйте тяжелую цель [ЛКМ]!"
			info["keys"] = "[ЛКМ] Выстрел"
			var stacks: int = tutorial_acid_dummy.acid_stacks if tutorial_acid_dummy != null else 0
			info["progress_text"] = "Коррозия: %d/5 слоев яда" % stacks if stacks > 0 else "Наложите слои яда на тяжелую цель"
			info["progress"] = minf(1.0, float(stacks) / 3.0) if stacks > 0 else 0.5
		11:
			info["title"] = "ЗАДАНИЕ 11/12: БОЕВОЙ СПАРРИНГ"
			info["desc"] = "Танк возвращен в стандартный строй. Уничтожьте боевого дрона с ИИ!"
			info["keys"] = "БОЙ"
			var hp: float = tutorial_drone.hp if tutorial_drone != null and tutorial_drone.alive else 0.0
			var max_hp: float = tutorial_drone.max_hp if tutorial_drone != null else 45.0
			info["progress_text"] = "Дрон HP: %d / %d" % [int(ceil(hp)), int(max_hp)]
			info["progress"] = 1.0 - (hp / max_hp)
		12:
			info["title"] = "ЗАДАНИЕ 12/12: ВЫБОР БОЕВОГО ПЕРКА"
			info["desc"] = "Повышение уровня! Выберите боевой перк в окне улучшения"
			info["keys"] = "[ЛКМ] Выбор"
			info["progress_text"] = "Выберите перк для завершения курса"
			info["progress"] = 1.0
		_:
			info["title"] = "ОБУЧЕНИЕ ЗАВЕРШЕНО"
			info["desc"] = "Курс молодого бойца успешно пройден! Награда: +100 монет 🪙"
			info["keys"] = "ПОБЕДА"
			info["progress_text"] = "Награда получена (+100 монет)"
			info["progress"] = 1.0
			info["done"] = true
	return info

func _update_tutorial() -> void:
	if finished_flag or players.is_empty():
		return
	var player = players[0]
	var tank = player.tank
	if tank == null or not tank.alive:
		return

	match tutorial_stage:
		1:
			if tank.vy < -0.2:
				tut_dist_fwd += absf(tank.vy)
			if tank.vy > 0.2:
				tut_dist_bwd += absf(tank.vy)
			if tut_dist_fwd >= 35.0 and tut_dist_bwd >= 25.0:
				Sfx.play("pickup")
				particles.burst(tank.x, tank.y, [Color("#86efac"), Color.WHITE], 16, 2, 5, 12, 24, rng)
				spawn_shockwave(tank.x, tank.y, 40.0, "dash", Color("#86efac"), 12)
				tutorial_stage = 2
				tutorial_step_timer = 0
				feed.emit("✔ Задание 1 выполнено! Двигайтесь к контрольной точке [A/D]!", Color("#86efac"))

		2:
			if tank.vx < -0.2:
				tut_turned_left = true
			if tank.vx > 0.2:
				tut_turned_right = true
			var dist := Vector2(tank.x - tutorial_marker.x, tank.y - tutorial_marker.y).length()
			if dist < 50.0:
				Sfx.play("pickup")
				particles.burst(tutorial_marker.x, tutorial_marker.y,
					[Color("#44ff44"), Color("#88ff88"), Color.WHITE], 22, 2, 6, 16, 32, rng)
				spawn_shockwave(tutorial_marker.x, tutorial_marker.y, 60.0, "dash", Color("#44ff44"), 15)
				tutorial_stage = 3
				tutorial_step_timer = 0
				tutorial_targets.clear()

				var target_offsets := [
					Vector2(-80.0, -110.0),
					Vector2(80.0, -110.0)
				]
				for off in target_offsets:
					var dummy := Tank.new({
						"x": tutorial_marker.x + off.x,
						"y": tutorial_marker.y + off.y,
						"team": "target",
						"name": "Мишень",
						"owner": null,
						"max_hp": 25.0,
						"speed": 0.0,
						"fire_rate": 99999,
						"color_key": "target",
						"chassis": "standard",
						"dmg_scale": 0.0
					})
					dummy.net_id = Net.next_tank_id()
					dummy.is_bot = true
					dummy.brain = null
					tanks.append(dummy)
					tutorial_targets.append(dummy)
					particles.burst(dummy.x, dummy.y, [Color("#eab308"), Color.WHITE], 10, 2, 4, 10, 20, rng)

				feed.emit("🎯 ЗАДАНИЕ 3/9: Огонь [ЛКМ / Пробел] — уничтожьте учебные мишени!", Color("#ffd700"))

		3:
			var remaining := 0
			for t in tutorial_targets:
				if t.alive:
					remaining += 1
			if remaining == 0:
				Sfx.play("crack")
				spawn_shockwave(tank.x, tank.y, 50.0, "ram", Color("#38bdf8"), 14)
				tutorial_stage = 4
				tutorial_step_timer = 0
				feed.emit("🧱 ЗАДАНИЕ 4/9: Разрушение укрытий — расчистите кирпичную стену ворот [ЛКМ]!", Color("#fb923c"))

		4:
			var gate_r := map.rows - 7
			var passed_gate: bool = tank.y < float(gate_r * Cfg.TILE)
			if tut_bricks_destroyed >= 2 or passed_gate:
				Sfx.play("crack")
				spawn_shockwave(tank.x, tank.y, 45.0, "dash", Color("#f97316"), 14)
				tutorial_stage = 5
				tutorial_step_timer = 0
				tutorial_barrels.clear()
				tutorial_barrel_targets.clear()

				var barrel_y := float(gate_r - 2) * Cfg.TILE
				var b1 := Ent.ExplosiveBarrel.new(tutorial_marker.x - 30.0, barrel_y)
				var b2 := Ent.ExplosiveBarrel.new(tutorial_marker.x + 30.0, barrel_y)
				barrels.append(b1)
				barrels.append(b2)
				tutorial_barrels.append(b1)
				tutorial_barrels.append(b2)
				particles.burst(b1.x, b1.y, [Color("#f97316"), Color.WHITE], 12, 2, 4, 10, 20, rng)
				particles.burst(b2.x, b2.y, [Color("#f97316"), Color.WHITE], 12, 2, 4, 10, 20, rng)

				var tgt_positions := [
					Vector2(tutorial_marker.x - 64.0, barrel_y),
					Vector2(tutorial_marker.x + 64.0, barrel_y)
				]
				for p in tgt_positions:
					var dummy := Tank.new({
						"x": p.x,
						"y": p.y,
						"team": "target",
						"name": "Мишень укрытия",
						"owner": null,
						"max_hp": 25.0,
						"speed": 0.0,
						"fire_rate": 99999,
						"color_key": "target",
						"chassis": "standard",
						"dmg_scale": 0.0
					})
					dummy.net_id = Net.next_tank_id()
					dummy.is_bot = true
					dummy.brain = null
					tanks.append(dummy)
					tutorial_barrel_targets.append(dummy)
					particles.burst(p.x, p.y, [Color("#eab308"), Color.WHITE], 8, 2, 3, 8, 16, rng)

				feed.emit("💥 ЗАДАНИЕ 5/10: Взрывные бочки — уничтожьте бочку [ЛКМ] или тараном для цепного взрыва!", Color("#f97316"))

		5:
			var all_barrels_gone := true
			for b in tutorial_barrels:
				if b.alive:
					all_barrels_gone = false
					break
			var targets_dead := true
			for t in tutorial_barrel_targets:
				if t.alive:
					targets_dead = false
					break
			if all_barrels_gone or (targets_dead and tutorial_step_timer > 30):
				Sfx.play("pickup")
				spawn_shockwave(tank.x, tank.y, 45.0, "dash", Color("#38bdf8"), 14)
				tutorial_stage = 6
				tutorial_step_timer = 0
				feed.emit("⚡ ЗАДАНИЕ 6/10: Рывок [Shift] — совершите рывок с кадрами неуязвимости (i-frames)!", Color("#38bdf8"))
			else:
				tutorial_step_timer += 1

		6:
			if tank.dash_invuln_ticks > 0 or tank.dash_range > 0.0:
				Sfx.play("dash")
				tank.flags["mines"] = true
				tank.mine_cooldown = 0
				tutorial_stage = 7
				tutorial_step_timer = 0

				var dummy_pos := Vector2(tutorial_marker.x, tutorial_marker.y - 70.0)
				var mine_dummy := Tank.new({
					"x": dummy_pos.x,
					"y": dummy_pos.y,
					"team": "target",
					"name": "Учебный броневик",
					"owner": null,
					"max_hp": 30.0,
					"speed": 0.5,
					"fire_rate": 99999,
					"color_key": "target",
					"chassis": "standard",
					"dmg_scale": 0.0
				})
				mine_dummy.net_id = Net.next_tank_id()
				mine_dummy.is_bot = true
				mine_dummy.brain = null
				tanks.append(mine_dummy)
				tutorial_mine_dummy = mine_dummy
				particles.burst(dummy_pos.x, dummy_pos.y, [Color("#eab308"), Color.WHITE], 10, 2, 4, 10, 20, rng)

				feed.emit("💣 ЗАДАНИЕ 7/10: Тактическая мина — установите мину [E / ПКМ] на пути броневика!", Color("#fbbf24"))

		7:
			var dummy_dead: bool = tutorial_mine_dummy != null and not tutorial_mine_dummy.alive
			var mine_placed: bool = tank.mine_cooldown > 0 or not mines.is_empty()
			if dummy_dead or (mine_placed and tutorial_step_timer > 60):
				Sfx.play("pickup")
				tank.ability_id = "bulwark"
				tank.ability_cd = 0
				tank.ability_timer = 0
				tutorial_stage = 8
				tutorial_step_timer = 0
				feed.emit("🛡 ЗАДАНИЕ 8/12: Способность машины — активируйте боевой щит [Q / Й]!", Color("#60a5fa"))
			else:
				tutorial_step_timer += 1
				if tutorial_mine_dummy != null and tutorial_mine_dummy.alive:
					tutorial_mine_dummy.thrust(0, 0.5)

		8:
			if tank.ability_id != "bulwark":
				tank.ability_id = "bulwark"
				if tank.ability_timer <= 0:
					tank.ability_cd = 0

			var q_input: bool = (
				Ctl.is_key_down(Sets.key_for("p1_ability")) or
				Ctl.is_key_down(KEY_Q) or
				Input.is_joy_button_pressed(0, JOY_BUTTON_Y) or
				(player.scheme != null and player.scheme.has_method("read_command") and
				 bool(player.scheme.read_command(player).get("ability", false)))
			)

			if q_input and tank.ability_timer <= 0 and tank.ability_cd <= 0:
				tank.use_ability(self)

			if tank.ability_timer > 0 or tank.ability_cd > 0 or q_input:
				Sfx.play("pickup")
				tutorial_stage = 9
				tutorial_step_timer = 0
				feed.emit("✔ Задание 8 выполнено! Энергетический щит активирован!", Color("#60a5fa"))

				# Трансформация танка игрока в Ледяной крио-танк (p5 бирюзовый, легкое шасси)
				tank.cannon_id = "ice"
				tank.set_chassis("light")
				tank.color_key = "p5"
				player.color_key = "p5"
				player.equipped_cannon = "ice"
				particles.burst(tank.x, tank.y, [Color("#aaeeff"), Color("#7fdfff"), Color.WHITE], 28, 3, 6, 16, 32, rng)
				spawn_shockwave(tank.x, tank.y, 60.0, "dash", Color("#7fdfff"), 16)
				Sfx.play("crack", tank.x, tank.y)

				# Спавн учебной цели для крио-заморозки (без неуязвимости)
				var ice_pos := Vector2(tutorial_marker.x, tutorial_marker.y - 90.0)
				var ice_dummy := Tank.new({
					"x": ice_pos.x,
					"y": ice_pos.y,
					"team": "target",
					"name": "Учебный разведчик",
					"owner": null,
					"max_hp": 35.0,
					"speed": 0.8,
					"fire_rate": 99999,
					"color_key": "target",
					"chassis": "light",
					"dmg_scale": 0.0
				})
				ice_dummy.net_id = Net.next_tank_id()
				ice_dummy.is_bot = true
				ice_dummy.brain = null
				ice_dummy.spawn_protect = 0
				tanks.append(ice_dummy)
				tutorial_ice_dummy = ice_dummy
				particles.burst(ice_pos.x, ice_pos.y, [Color("#38bdf8"), Color.WHITE], 14, 2, 4, 10, 20, rng)
				feed.emit("❄️ ЗАДАНИЕ 9/12: Ледяной танк — поразите цель [ЛКМ] для сковывания брони льдом!", Color("#7fdfff"))
			else:
				tutorial_step_timer += 1

		9:
			# Этап 9: Ледяной танк — Заморозка цели
			if tank.cannon_id != "ice":
				tank.cannon_id = "ice"
				tank.set_chassis("light")
			if tank.color_key != "p5":
				tank.color_key = "p5"
				player.color_key = "p5"

			var ice_frozen: bool = tutorial_ice_dummy != null and (tutorial_ice_dummy.freeze_ticks > 0 or not tutorial_ice_dummy.alive)
			if ice_frozen:
				Sfx.play("crack", tank.x, tank.y)
				spawn_shockwave(tank.x, tank.y, 50.0, "ram", Color("#7fdfff"), 14)
				tutorial_stage = 10
				tutorial_step_timer = 0
				feed.emit("✔ Задание 9 выполнено! Цель скована криогенным льдом!", Color("#7fdfff"))

				if tutorial_ice_dummy != null:
					tutorial_ice_dummy.alive = false

				# Трансформация танка игрока в Химический кислотный танк (p12 изумрудный, тяжелое шасси)
				tank.cannon_id = "acid"
				tank.set_chassis("heavy")
				tank.color_key = "p12"
				player.color_key = "p12"
				player.equipped_cannon = "acid"
				particles.burst(tank.x, tank.y, [Color("#84cc16"), Color("#a3e635"), Color.WHITE], 32, 3, 6, 16, 32, rng)
				spawn_shockwave(tank.x, tank.y, 65.0, "acid", Color("#84cc16"), 18)
				Sfx.play("steam", tank.x, tank.y)

				# Спавн тяжелой учебной цели для химического яда
				var acid_pos := Vector2(tutorial_marker.x, tutorial_marker.y - 100.0)
				var acid_dummy := Tank.new({
					"x": acid_pos.x,
					"y": acid_pos.y,
					"team": "target",
					"name": "Тяжелая мишень",
					"owner": null,
					"max_hp": 80.0,
					"speed": 0.0,
					"fire_rate": 99999,
					"color_key": "target",
					"chassis": "heavy",
					"dmg_scale": 0.0
				})
				acid_dummy.net_id = Net.next_tank_id()
				acid_dummy.is_bot = true
				acid_dummy.brain = null
				acid_dummy.spawn_protect = 0
				tanks.append(acid_dummy)
				tutorial_acid_dummy = acid_dummy
				particles.burst(acid_pos.x, acid_pos.y, [Color("#84cc16"), Color.WHITE], 16, 2, 5, 12, 24, rng)
				feed.emit("🧪 ЗАДАНИЕ 10/12: Хим-танк — обстреляйте тяжелую цель [ЛКМ], распылив разъедающий яд!", Color("#84cc16"))
			else:
				tutorial_step_timer += 1
				if tutorial_ice_dummy != null and tutorial_ice_dummy.alive and tutorial_ice_dummy.freeze_ticks <= 0:
					tutorial_ice_dummy.thrust(0.6 * sin(float(tick) * 0.05), -0.3)

		10:
			# Этап 10: Химический танк — Наложение яда и коррозии
			if tank.cannon_id != "acid":
				tank.cannon_id = "acid"
				tank.set_chassis("heavy")
			if tank.color_key != "p12":
				tank.color_key = "p12"
				player.color_key = "p12"

			var stacks: int = tutorial_acid_dummy.acid_stacks if tutorial_acid_dummy != null else 0
			var acid_applied: bool = tutorial_acid_dummy != null and (
				(stacks >= 1 and tutorial_step_timer >= 45) or not tutorial_acid_dummy.alive
			)
			if acid_applied:
				Sfx.play("steam", tank.x, tank.y)
				spawn_shockwave(tank.x, tank.y, 50.0, "acid", Color("#84cc16"), 14)
				tutorial_stage = 11
				tutorial_step_timer = 0
				feed.emit("✔ Задание 10 выполнено! Броня цели разъедена химической коррозией!", Color("#84cc16"))

				if tutorial_acid_dummy != null:
					tutorial_acid_dummy.alive = false

				# Возврат танка игрока в Стандартный танк (p1 зеленый, стандартное шасси)
				tank.cannon_id = "standard"
				tank.set_chassis("standard")
				tank.color_key = "p1"
				player.color_key = "p1"
				player.equipped_cannon = "standard"
				particles.burst(tank.x, tank.y, [Color("#ffd700"), Color.WHITE], 24, 2, 5, 14, 28, rng)
				Sfx.play("pickup")

				# Спавн боевого дрона для спарринга
				var drone_pos := Vector2(tutorial_marker.x, tutorial_marker.y - 120.0)
				var drone := Tank.new({
					"x": drone_pos.x,
					"y": drone_pos.y,
					"team": "enemy",
					"name": "Учебный дрон",
					"owner": null,
					"max_hp": 45.0,
					"speed": 1.3,
					"fire_rate": 80,
					"color_key": "enemy",
					"chassis": "standard",
					"dmg_scale": 0.35
				})
				drone.net_id = Net.next_tank_id()
				drone.is_bot = true
				drone.spawn_protect = 0
				drone.brain = BotBrain.new({
					"accuracy": 0.45,
					"react_time": 25,
					"role": "attacker",
					"fire_range": 320.0,
					"keep_min": 70.0,
					"keep_max": 200.0,
					"rng": rng,
				})
				tanks.append(drone)
				tutorial_drone = drone
				particles.burst(drone_pos.x, drone_pos.y, [Color("#f43f5e"), Color.WHITE], 16, 2, 5, 12, 24, rng)
				feed.emit("⚔️ ЗАДАНИЕ 11/12: Боевой спарринг — танк возвращен в строй. Уничтожьте боевого дрона!", Color("#f43f5e"))
			else:
				tutorial_step_timer += 1

		11:
			# Этап 11: Боевой спарринг
			if tank.cannon_id != "standard":
				tank.cannon_id = "standard"
				tank.set_chassis("standard")

			if tutorial_drone != null and not tutorial_drone.alive:
				var needed_xp: int = maxi(1, player.xp_to_next_level() - player.session_xp)
				player.add_xp(needed_xp)
				Sfx.play("levelup")
				tutorial_stage = 12
				tutorial_step_timer = 0
				feed.emit("🌟 ЗАДАНИЕ 12/12: Повышение уровня! Выберите боевой перк для завершения курса!", Color("#a855f7"))

		12:
			# Этап 12: Выбор первого перка
			if player.pending_level_ups == 0 and not player.perk_ids.is_empty():
				tutorial_step_timer += 1
				if tutorial_step_timer >= 45:
					tutorial_stage = 13
					Prof.bump_stat("tutorialCompleted", 1)
					feed.emit("🏆 Курс молодого бойца завершен! Награда: +100 монет 🪙", Color("#ffd700"))
					_finish(player.name, 0, "player", "Курс молодого бойца успешно пройден! Награда: +100 монет")

func _check_victory() -> void:
	if mode == "defense" or mode == "tutorial":
		return

	if mode == "koth":
		var alive := []
		for t in tanks:
			if t.alive:
				alive.append(t)

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
	acid_pools.clear()
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
	shockwaves.clear()
	barrels.clear()
	power_generators.clear()
	rammer_meltdowns.clear()
	tutorial_targets.clear()
	tutorial_barrels.clear()
	tutorial_barrel_targets.clear()
	tutorial_drone = null
	tutorial_mine_dummy = null
	tutorial_ice_dummy = null
	tutorial_acid_dummy = null

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
	if mode == "tutorial":
		return {"current": mini(tutorial_stage, 12), "target": 12, "total": 12, "task": get_tutorial_task_info()}
	if mode == "ffa":
		return {"current": player.kills, "target": int(Cfg.MODES["ffa"]["frag_limit"])}
	var team: String = player.tank.team if player.tank != null else "player"
	return {"current": int(team_score.get(team, 0)), "target": int(Cfg.MODES["ctf"]["cap_limit"])}
