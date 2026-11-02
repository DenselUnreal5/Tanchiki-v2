extends "res://tests/reel.gd"

const SPECS := {
	"scout": {
		"class": "scout", "loc": "dust", "weather": "clear", "time": "day", "seed": 8303,
		"hook_sub": "The Scout", "feat": "SCOUT", "feat_sub": "Plus 30% speed",
		"pay": "DASH", "pay_sub": "Recharges faster", "kind": "drive",
	},
	"heavy": {
		"class": "heavy", "loc": "frost", "weather": "clear", "time": "day", "seed": 8404,
		"hook_sub": "The Brute", "feat": "BRUTE", "feat_sub": "Ram damage x3",
		"pay": "ONE HIT.", "pay_sub": "THEY'RE GONE.", "kind": "ram",
	},
	"sniper": {
		"class": "sniper", "loc": "shore", "weather": "clear", "time": "dusk", "seed": 8505,
		"hook_sub": "The Sniper", "feat": "SNIPER", "feat_sub": "Double damage",
		"pay": "ONE SHOT.", "pay_sub": "ONE WRECK.", "kind": "snipe",
	},
	"boss": {
		"class": "heavy", "loc": "city", "weather": "clear", "time": "day", "seed": 8707,
		"hook_sub": "The Juggernaut", "feat": "BOSS", "feat_sub": "Charges through walls",
		"pay": "GET OUT", "pay_sub": "OF THE LANE.", "kind": "boss",
	},
	"storm": {
		"class": "standard", "loc": "city", "weather": "storm", "time": "night", "seed": 7202,
		"hook_sub": "The storm", "feat": "LIGHTNING", "feat_sub": "It hits tanks and walls",
		"pay": "THE MAP", "pay_sub": "FIGHTS BACK.", "kind": "storm",
	},
}

const FRAMES_TOTAL := 375

var feature := "scout"
var spec := {}
var _lines := {}
var _pilot: RefCounted
var _stars: Array = []
var _parked: Array = []
var _homes := {}
var _player_home := Vector2.ZERO
var _pin_player := true
var _pin_stars := true
var _boss = null
var _origin := Vector2i.ZERO
var _phase := ""
var _rammed := 0

func _texts() -> Dictionary:
	return {"en": _lines}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--feature="):
			feature = a.substr(10)
	if not SPECS.has(feature):
		feature = "scout"
	spec = SPECS[feature]
	_lines = {
		"hook": "DEVLOG", "hook_sub": spec["hook_sub"],
		"feat": spec["feat"], "feat_sub": spec["feat_sub"],
		"pay": spec["pay"], "pay_sub": spec["pay_sub"],
		"end": "IRON STORM", "end_sub": "DEVLOG",
	}
	subs_name = "feature_" + feature
	await _setup()
	process_priority = 1000
	await _video()
	_teardown()

func _process(_delta: float) -> void:
	super._process(_delta)
	_pin_stage()

func _video() -> void:
	var prev_class := String(Prof.equipped_class)
	Prof.equipped_class = String(spec["class"])
	await _start("ffa", String(spec["loc"]), String(spec["weather"]), String(spec["time"]), int(spec["seed"]))
	Prof.equipped_class = prev_class
	_stage()
	_pilot = DrivePilot.new()
	game.players[0].scheme = _pilot
	for i in FRAMES_TOTAL:
		_keep_alive()
		_direct(i)
		await _frames(1)
	_close_cue()
	await _end_match()

func _stage() -> void:
	var map = game.world.map
	var tank = game.players[0].tank
	var cr := clampi(8, 2, map.rows - 36)
	var cc := clampi(int(map.cols / 2), 8, map.cols - 8)
	_origin = Vector2i(cr, cc)
	var bots := []
	for t in game.world.tanks:
		if t.is_bot:
			bots.append(t)
	match String(spec["kind"]):
		"storm":
			_clear(map, cr, cc, -5, 6, -5, 6, Cfg.T_GRASS)
			_player_home = _tile_center(cr, cc)
			_pin_player = true
			_adopt(bots, [Vector2i(-3, 3), Vector2i(3, 4)], 500.0)
		"boss":
			_clear(map, cr, cc, -3, 18, -6, 7, Cfg.T_GRASS)
			for dc in range(-6, 7):
				map.set_tile(cr + 5, cc + dc, Cfg.T_WALL)
			_brick_line(map, cr, cc)
			_player_home = _tile_center(cr, cc)
			_pin_player = true
			_pin_stars = false
			_park(bots)
			_boss = game.world._spawn_bot("enemy", "enemy", "boss_rammer")
			_boss.brain = null
			_boss.freeze_ticks = 0
			_home_boss(cr + 14, cc)
		"snipe":
			_clear(map, cr, cc, -3, 16, -4, 5, Cfg.T_GRASS)
			_player_home = _tile_center(cr, cc)
			_pin_player = true
			_adopt(bots, [Vector2i(0, 12)], 900.0)
		"ram":
			_clear(map, cr, cc, -3, 20, -4, 5, Cfg.T_GRASS)
			_player_home = _tile_center(cr, cc)
			_pin_player = true
			_adopt(bots, [Vector2i(0, 3)], 22.0)
		_:
			_clear(map, cr, cc, -2, 32, -3, 4, Cfg.T_GRASS)
			_player_home = _tile_center(cr, cc)
			_pin_player = true
			_adopt(bots, [Vector2i(-4, 8), Vector2i(4, 16)], 500.0)
	tank.x = _player_home.x
	tank.y = _player_home.y
	tank.angle = PI / 2.0
	tank.body_angle = PI / 2.0
	tank.turret_angle = PI / 2.0
	print("feature short ", feature, " class=", tank.class_id)

func _clear(map, cr: int, cc: int, r0: int, r1: int, c0: int, c1: int, tile: int) -> void:
	for dr in range(r0, r1):
		for dc in range(c0, c1):
			map.set_tile(cr + dr, cc + dc, tile)

func _brick_line(map, cr: int, cc: int) -> void:
	for dr in [7, 8]:
		for dc in range(-5, 6):
			map.set_tile(cr + dr, cc + dc, Cfg.T_BRICK)

func _adopt(bots: Array, slots: Array, hp: float) -> void:
	_stars = bots.slice(0, mini(slots.size(), bots.size()))
	_park(bots)
	for i in _stars.size():
		var slot: Vector2i = slots[i]
		var spot := _tile_center(_origin.x + slot.y, _origin.y + slot.x)
		_homes[_stars[i]] = spot
		_stars[i].x = spot.x
		_stars[i].y = spot.y
		_stars[i].max_hp = maxf(hp, 22.0)
		_stars[i].hp = hp
		_stars[i].alive = true

func _park(bots: Array) -> void:
	for t in bots:
		if _stars.has(t):
			continue
		_parked.append(t)
		t.x = 48.0
		t.y = 48.0
		t.freeze_ticks = 8

func _home_boss(row: int, col: int) -> void:
	if _boss == null:
		return
	_boss.x = _tile_center(row, col).x
	_boss.y = _tile_center(row, col).y
	_boss.vx = 0.0
	_boss.vy = 0.0
	_boss.alive = true
	_boss.hp = _boss.max_hp
	_boss.rammer_state = "idle"

func _tile_center(row: int, col: int) -> Vector2:
	return Vector2(col * Cfg.TILE + 16.0, row * Cfg.TILE + 16.0)

func _pin_stage() -> void:
	if game == null or game.world == null or game.players.is_empty():
		return
	var tank = game.players[0].tank
	if tank != null and _player_home != Vector2.ZERO:
		if _pin_player:
			tank.x = _player_home.x
			tank.y = _player_home.y
			tank.vx = 0.0
			tank.vy = 0.0
		game.players[0].update_camera()
	for t in game.world.tanks:
		if not t.is_bot or t == _boss:
			continue
		if not t.alive:
			t.respawn_timer = 999
			continue
		if _pin_stars and _homes.has(t):
			var home: Vector2 = _homes[t]
			t.x = home.x
			t.y = home.y
			t.vx = 0.0
			t.vy = 0.0
			t.freeze_ticks = 8
		elif _parked.has(t):
			t.x = 48.0
			t.y = 48.0
			t.vx = 0.0
			t.vy = 0.0
			t.freeze_ticks = 8

func _direct(i: int) -> void:
	_pilot.move = Vector2.ZERO
	match String(spec["kind"]):
		"drive":
			if i >= 50 and i < 268:
				_pin_player = false
				_pilot.move = Vector2(0, 1)
			if i == 70 or i == 150 or i == 220:
				_dash()
		"ram":
			if i == 64 or i == 168:
				_offer_ram_target()
				_pin_player = false
				_pin_stars = false
				_dash()
		"snipe":
			if i == 158:
				for t in _stars:
					t.hp = 30.0
			if i == 64 or i == 158:
				_shoot_direct()
		"boss":
			if i == 62 or i == 188:
				_brick_line(game.world.map, _origin.x, _origin.y)
				_home_boss(_origin.x + 14, _origin.y)
				if _boss != null:
					_boss.start_rammer_charge(_player_home.x, _player_home.y, game.world)
		"storm":
			if i > 40 and i < 268 and i % 7 == 0:
				var tank = game.players[0].tank
				var a := float(i) * 0.9
				game.world.strike_lightning(tank.x + cos(a) * 150.0, tank.y + sin(a) * 180.0)
	if i < 50:
		_phase_set("hook")
	elif i < 186:
		_phase_set("feat")
	elif i < 268:
		_phase_set("pay")
	else:
		_pin_player = true
		_phase_set("end")

func _dash() -> void:
	var tank = game.players[0].tank
	if tank == null:
		return
	tank.dash_cooldown = 0
	tank.dash_range = 0.0
	tank.freeze_ticks = 0
	tank.angle = PI / 2.0
	tank.dash(Vector2(0, 1))

func _offer_ram_target() -> void:
	var tank = game.players[0].tank
	if tank == null:
		return
	var victim = null
	for t in _stars + _parked:
		if t != null and t.alive:
			victim = t
			break
	if victim == null and not _parked.is_empty():
		victim = _parked[0]
	if victim == null:
		return
	victim.alive = true
	victim.max_hp = 80.0
	victim.hp = 20.0
	victim.freeze_ticks = 0
	victim.x = tank.x
	victim.y = tank.y + 62.0
	victim.vx = 0.0
	victim.vy = 0.0
	_homes.erase(victim)
	if _parked.has(victim):
		_parked.erase(victim)
	if not _stars.has(victim):
		_stars.append(victim)
	_rammed += 1

func _shoot_direct() -> void:
	var tank = game.players[0].tank
	if tank == null or _stars.is_empty():
		return
	var target = _stars[0]
	tank.aim_at(target.x, target.y)
	tank.fire_cooldown = 0
	tank.overheated = false
	tank.heat = 0.0
	tank.shoot(game.world)

func _phase_set(next: String) -> void:
	if _phase == next:
		return
	_phase = next
	if next == "end":
		create_tween().tween_property(dim, "color:a", 0.82, 0.25)
		caption.position = Vector2(20, 340)
		sub.position = Vector2(20, 470)
		_say_keys("end", "end_sub")
		return
	dim.color.a = 0.0
	caption.position = Vector2(20, 78)
	sub.position = Vector2(20, 188)
	if next == "hook":
		_say_keys("hook", "hook_sub")
	elif next == "feat":
		_say_keys("feat", "feat_sub")
	else:
		_say_keys("pay", "pay_sub")

class DrivePilot extends RefCounted:
	var move := Vector2.ZERO

	func hints() -> Array:
		return []

	func apply(tank: Tank, _player, _world) -> void:
		if move == Vector2.ZERO:
			return
		tank.thrust(move.x, move.y)
		tank.angle = move.angle()
