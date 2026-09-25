class_name World
extends RefCounted

signal feed(text: String, color: Color)
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

var _storm_rng: Rng
var _tree_tiles: PackedInt32Array = PackedInt32Array()
var _tree_cache_tick := -100000
var _trees_felled := 0
var _last_ffa_boss_kills: Dictionary = {}

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
		t.brain.hear_shot(shooter.x, shooter.y)

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

func maybe_summon_storm(player) -> void:
	if player == null or storm_summoned or weather == null:
		return
	var build := Perks.get_build("lightning")
	if build.is_empty():
		return
	for pid in (build["perks"] as Array):
		if not player.has_perk(String(pid)):
			return
	storm_summoned = true
	weather.set_condition("storm")
	weather.locked = true
	feed.emit(I18n.t("feed.stormSummoned", {"name": player.name},
		"%s собрал Грозовой билд — гроза теперь не утихнет до конца партии" % player.name),
		Color("#8899ff"))

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
		elif is_defense:
			team = "player"
		else:
			team = "human_%d" % i
		_spawn_player_tank(player, team)

	if is_ctf:
		var size: int = Cfg.MODES["ctf"]["team_size"]
		var humans_player := 1
		var humans_enemy := players.size() - humans_player
		_spawn_bot_team("player", maxi(0, size - humans_player), "ally")
		_spawn_bot_team("enemy", maxi(0, size - humans_enemy), "enemy")
	elif mode == "koth":
		for i in int(Cfg.MODES["koth"]["enemies"]):
			_spawn_bot("bot_%d" % i, "enemy")
	elif mode == "defense":
		pass
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
		"color_key": player.color_key,
		"upgrade_mods": player.upgrade_mods,
		"cosmetics": player.cosmetics,
		"cannon_id": player.equipped_cannon,
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
	if bool(type["boss"]) and boss_alive:
		type = EnemyTypes.get_type("grunt")
	var boss_mult := {"hp": 1.0, "dmg": 1.0}
	if bool(type["boss"]):
		boss_mult = _boss_stat_mult()
	var spot := _free_spot(team)
	var tank := Tank.new({
		"x": spot.x, "y": spot.y, "team": team,
		"name": _unique_bot_name(type), "owner": null,
		"max_hp": round(float(diff["enemy_hp"]) * float(type["hp_mult"]) * ramp * float(boss_mult["hp"])),
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
	var tank := _spawn_bot("enemy", "enemy", "boss")
	boss_alive = true
	return tank

func _spawn_ffa_boss() -> Tank:
	boss_alive = false
	var team_name := "boss_%d" % (tanks.size() + 1)
	var tank := _spawn_bot(team_name, "enemy", "boss")
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
	if is_ambush:
		if attacker.flags.has("predator") and attacker.flags.has("forest") and attacker.flags.has("shadow"):
			amount *= Cfg.STEALTH_HUNTER_CRIT_MULT
		elif float(attacker.mods["ambushDmgMult"]) > 1.0:
			amount *= float(attacker.mods["ambushDmgMult"])

	if source == "bullet" and attacker != null and attacker.alive \
			and attacker.flags.has("sniper") and attacker.flags.has("evasion") and attacker.flags.has("keenEar"):
		var dx_gs: float = attacker.x - target.x
		var dy_gs: float = attacker.y - target.y
		if dx_gs * dx_gs + dy_gs * dy_gs >= Cfg.GHOST_SNIPER_RANGE * Cfg.GHOST_SNIPER_RANGE:
			amount *= Cfg.GHOST_SNIPER_CRIT_MULT

	if source != "acid" and target.acid_stacks > 0 and target.acid_attacker != null \
			and target.acid_attacker.flags.has("corrodingArmor"):
		amount *= Cfg.CORRODING_ARMOR_MULT

	var res: Dictionary = target.take_damage(self, amount, attacker, source)
	if bool(res["evaded"]) or float(res["applied"]) <= 0.0:
		return 0.0

	if is_ambush and float(attacker.mods["ambushDashTicks"]) > 0.0:
		attacker.turbo_timer = maxi(attacker.turbo_timer, int(attacker.mods["ambushDashTicks"]))

	target.last_attacker = attacker
	target.last_attacker_tick = tick

	if float(res["reflected"]) > 0.0 and attacker != null and attacker.alive:
		deal_damage(attacker, float(res["reflected"]), target, "reflect")

	if attacker != null:
		attacker.damage_dealt += float(res["applied"])
		if attacker.owner != null:
			attacker.owner.damage_dealt += float(res["applied"])
			player_damage.emit(attacker.owner, float(res["applied"]))
		if float(attacker.mods["lifestealFraction"]) > 0.0 and attacker.alive:
			var heal := floorf(float(res["applied"]) * float(attacker.mods["lifestealFraction"]))
			if heal > 0.0:
				attacker.hp = minf(attacker.max_hp, attacker.hp + heal)

	damage_number.emit(target.x, target.y - 20,
		"-%d" % int(round(float(res["applied"]))),
		Color("#ff4444") if target.owner != null else Color("#ffee55"))
	if target.owner != null:
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
	victim.last_attacker = attacker
	victim.last_attacker_tick = tick
	if attacker != null:
		attacker.damage_dealt += amount
		if attacker.owner != null:
			attacker.owner.damage_dealt += amount
			player_damage.emit(attacker.owner, amount)
	damage_number.emit(victim.x, victim.y - 20, "-%d" % int(round(amount)),
		Color("#ff4444") if victim.owner != null else Color("#ffee55"))
	if victim.owner != null:
		victim.owner.damage_flash = 12
		victim.owner.shake = maxf(victim.owner.shake, 8.0)
		Sfx.play("hit")
	if victim.hp <= 0.0:
		_kill_tank(victim, attacker, "ram")

func maybe_freeze_shot_kill(victim, attacker) -> void:
	if victim == null or not victim.alive or attacker == null or not attacker.alive:
		return
	if not victim.enemy_type.is_empty() and bool(victim.enemy_type.get("boss", false)):
		return
	if not (attacker.flags.has("deepFreeze") and attacker.flags.has("frostDash") and attacker.flags.has("chilledBarrel")):
		return
	execute_frozen_kill(victim, attacker)

func _juggernaut_shock(killer, ox: float, oy: float) -> void:
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
	particles.burst(ox, oy, [Color("#ffaa33"), Color("#ff5533"), Color.WHITE], 16, 2, 5, 16, 30, rng)
	add_shake(5.0, ox, oy)

func _kill_tank(victim, killer, source: String) -> void:
	if source == "ram" and killer != null and killer.alive \
			and killer.flags.has("ram") and killer.flags.has("thickArmor") and killer.flags.has("kamikaze"):
		_juggernaut_shock(killer, victim.x, victim.y)
	victim.on_death(self, killer)
	victim.respawn_timer = Cfg.RESPAWN_DELAY
	if Sets.wrecks:
		wrecks.append(Ent.Wreck.new(victim, rng))

	if not victim.enemy_type.is_empty() and bool(victim.enemy_type.get("boss", false)):
		boss_alive = false

	if mode == "koth":
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
	var allowed := []
	for p in Perks.LIST:
		if Perks.is_perk_allowed_in_mode(p["id"], mode):
			allowed.append(p)
	if allowed.is_empty():
		return
	var perk: Dictionary = rng.pick(allowed)
	perk_drops.append(Ent.PerkPickup.new(victim.x, victim.y, String(perk["id"]), rng))
	particles.burst(victim.x, victim.y, [Color("#ff88ff"), Color.WHITE], 8, 2, 4, 12, 18, rng)

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
		if mode == "defense" and tank.is_bot:
			continue
		if mode == "ffa" and tank.is_boss:
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

func _check_victory() -> void:
	if mode == "defense":
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
	if mode == "ffa":
		return {"current": player.kills, "target": int(Cfg.MODES["ffa"]["frag_limit"])}
	var team: String = player.tank.team if player.tank != null else "player"
	return {"current": int(team_score.get(team, 0)), "target": int(Cfg.MODES["ctf"]["cap_limit"])}
