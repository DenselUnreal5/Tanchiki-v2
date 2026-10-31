extends "res://tests/reel.gd"

# Shorts 9:16: билд «Владыка бури», без смертей и белых вспышек неба.
# Запись:
#   override.cfg: viewport 540×960, stretch expand
#   godot --path godot --write-movie ../marketing/lightning_short.avi --fixed-fps 30 tests/lightning_short.tscn

const CALM_TYPES := ["grunt", "scout", "heavy", "sniper"]
const WARMUP := 24
const PEAK := 210
const STRIKE_EVERY := 14

var _parked := {}
var _saved_shake := 1.0

func _ready() -> void:
	burn = false
	lang = "ru"
	await _setup()
	caption.visible = false
	sub.visible = false
	dim.visible = false
	if not get_tree().process_frame.is_connected(_after_world):
		get_tree().process_frame.connect(_after_world)
	await _peak()
	_teardown()

func _process(_delta: float) -> void:
	if game == null:
		return
	if game.state == "paused":
		game.resume()
	_immortal()

func _after_world() -> void:
	if game == null or game.world == null:
		return
	_immortal()
	_calm_fx()

func _peak() -> void:
	_saved_shake = Sets.screen_shake
	Sets.screen_shake = 0.0
	Sets.killcam = false
	await _start("ffa", "city", "storm", "night", 7202)
	var p = game.players[0]
	var map = game.world.map
	var mid: Vector2 = map.find_free_spot(game.world.rng, {
		"r0": map.rows * 0.42, "r1": map.rows * 0.58,
		"c0": map.cols * 0.42, "c1": map.cols * 0.58
	}, TankArt.MAX_COLLIDE_W, TankArt.MAX_COLLIDE_H)
	if mid != Vector2.INF:
		p.tank.x = mid.x
		p.tank.y = mid.y
	p.equip_perk("lightning_lord")
	p.equip_perk("sky_strike")
	p.equip_perk("chain_lightning")
	game.world.check_tank_synergies(p.tank)
	game.world.maybe_summon_storm(p)
	p.tank.sky_strike_ready = true
	_park_noisy_bots()
	_pull_enemies(5, 150.0)
	_immortal()
	game.hud.hide_hud()
	for i in WARMUP:
		_live()
		if i == 8:
			_strike_cluster()
		await _frames(1)
	print("SHORT_START_FRAME=", Engine.get_frames_drawn())
	for i in PEAK:
		_live()
		if i % STRIKE_EVERY == 0:
			_strike_cluster()
		p.tank.sky_strike_ready = true
		if i % 50 == 25:
			_pull_enemies(5, 150.0)
		await _frames(1)
	print("SHORT_END_FRAME=", Engine.get_frames_drawn())
	Sets.screen_shake = _saved_shake
	await _end_match()

func _live() -> void:
	_skip_perks()
	_immortal()
	_park_noisy_bots()
	for t in game.world.tanks:
		if t.is_bot and not t.perk_ids.is_empty():
			t.perk_ids.clear()
			t.recompute()
	game.hud.hide_hud()

func _immortal() -> void:
	if game == null or game.world == null:
		return
	for t in game.world.tanks:
		t.alive = true
		if t.max_hp < 8000.0:
			t.max_hp = 8000.0
			t.base_max_hp = 8000.0
		t.hp = t.max_hp
	for p in game.players:
		p.damage_flash = 0
		p.shake = 0.0
		if p.tank != null:
			p.tank.alive = true
			p.tank.hp = p.tank.max_hp

func _calm_fx() -> void:
	if game.world.weather != null:
		game.world.weather.flash = minf(game.world.weather.flash, 0.12)
	for p in game.players:
		p.shake = 0.0
		p.damage_flash = 0

func _park_noisy_bots() -> void:
	var map = game.world.map
	var t0 = game.players[0].tank
	var far_r: float = 2.0 if t0.y > map.rows * Cfg.TILE * 0.5 else map.rows - 8.0
	var far_c: float = 2.0 if t0.x > map.cols * Cfg.TILE * 0.5 else map.cols - 8.0
	var area := {"r0": far_r, "r1": far_r + 6.0, "c0": far_c, "c1": far_c + 6.0}
	for t in game.world.tanks:
		if not t.is_bot or not t.alive or CALM_TYPES.has(String(t.enemy_type.get("id", "grunt"))):
			continue
		if int(_parked.get(t.id, -1)) == t.deaths:
			continue
		var spot: Vector2 = map.find_free_spot(game.world.rng, area, TankArt.MAX_COLLIDE_W, TankArt.MAX_COLLIDE_H)
		if spot != Vector2.INF:
			t.x = spot.x
			t.y = spot.y
		_parked[t.id] = t.deaths

func _strike_cluster() -> void:
	var world = game.world
	var t0 = game.players[0].tank
	var targets := []
	for t in world.tanks:
		if t.is_bot and t.alive and t.team != t0.team:
			targets.append(t)
	if targets.is_empty():
		world.strike_lightning(t0.x + 36.0, t0.y - 90.0, t0)
		return
	var t = targets[frame % targets.size()]
	world.strike_lightning(t.x, t.y, t0)
	if world.weather != null:
		world.weather.flash = minf(world.weather.flash, 0.12)
