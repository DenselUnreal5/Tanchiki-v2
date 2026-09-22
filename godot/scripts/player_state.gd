class_name PlayerState
extends RefCounted

var index: int
var name: String
var color_key: String
var scheme
var _auto_kbm_scheme = null
var _auto_pad_scheme = null
var peer_id := 0

var tank: Tank = null

var upgrade_mods := {}
var cosmetics := {}
var equipped_cannon := "standard"

var perk_ids: Array = []
var build_pity: Dictionary = {}

var session_xp := 0
var session_level := 1
var pending_level_ups := 0

var score := 0
var kills := 0
var deaths := 0
var captures := 0
var damage_dealt := 0.0

var kill_ticks: Array = []
var clean_streak := 0

var camera := Vector2.ZERO
var viewport := Rect2(0, 0, 0, 0)

var map: GameMap = null

var damage_flash := 0
var shake := 0.0

func _init(index_: int, name_: String, color_key_: String, scheme_) -> void:
	index = index_
	name = name_
	color_key = color_key_
	scheme = scheme_

func has_perk(id: String) -> bool:
	return perk_ids.has(id)

func equip_perk(id: String) -> bool:
	if has_perk(id):
		return false
	perk_ids.append(id)
	while perk_ids.size() > Cfg.MAX_EQUIPPED_PERKS:
		perk_ids.pop_front()
	_update_build_pity(id)
	if tank != null:
		tank.recompute()
	return true

func _update_build_pity(equipped_id: String) -> void:
	for b in Perks.builds_with_perk(equipped_id):
		var build_id: String = b["id"]
		var complete := true
		for pid in (b["perks"] as Array):
			if not has_perk(pid):
				complete = false
				break
		if complete:
			build_pity.erase(build_id)
		else:
			build_pity[build_id] = Cfg.BUILD_PITY_WINDOW

func unequip_perk(id: String) -> bool:
	var i := perk_ids.find(id)
	if i == -1:
		return false
	perk_ids.remove_at(i)
	if tank != null:
		tank.recompute()
	return true

func reset_for_match() -> void:
	perk_ids.clear()
	build_pity.clear()
	upgrade_mods = {}
	session_xp = 0
	session_level = 1
	pending_level_ups = 0
	score = 0
	kills = 0
	deaths = 0
	captures = 0
	damage_dealt = 0.0
	kill_ticks.clear()
	clean_streak = 0
	damage_flash = 0
	shake = 0.0
	tank = null

func xp_to_next_level() -> int:
	return Cfg.xp_for_session_level(session_level)

func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	session_xp += amount
	var gained := 0
	var guard := 0
	while session_xp >= xp_to_next_level() and guard < 100:
		guard += 1
		session_xp -= xp_to_next_level()
		session_level += 1
		pending_level_ups += 1
		gained += 1
	return gained

func enable_auto_device_switch(kbm_scheme, pad_scheme) -> void:
	_auto_kbm_scheme = kbm_scheme
	_auto_pad_scheme = pad_scheme
	scheme = pad_scheme if Sets.last_input_pad else kbm_scheme

func control(t: Tank, world) -> void:
	if _auto_pad_scheme != null:
		scheme = _auto_pad_scheme if Sets.last_input_pad else _auto_kbm_scheme
		if scheme == _auto_pad_scheme:
			_auto_pad_scheme.device = Sets.last_pad_device
	scheme.apply(t, self, world)

var pickup_radius: float:
	get:
		var mult: float = float(tank.mods["pickupRadiusMult"]) if tank != null else 1.0
		return Cfg.PICKUP_R * mult

func update_camera() -> void:
	var w := viewport.size.x
	var h := viewport.size.y
	var map_w := map.width if map != null else float(Cfg.MAP_W)
	var map_h := map.height if map != null else float(Cfg.MAP_H)
	if tank != null:
		camera.x = tank.x
		camera.y = tank.y
	camera.x = map_w / 2.0 if map_w <= w else clampf(camera.x, w / 2.0, map_w - w / 2.0)
	camera.y = map_h / 2.0 if map_h <= h else clampf(camera.y, h / 2.0, map_h - h / 2.0)

func screen_to_world(screen_x: float, screen_y: float) -> Vector2:
	return Vector2(
		screen_x - viewport.position.x - viewport.size.x / 2.0 + camera.x,
		screen_y - viewport.position.y - viewport.size.y / 2.0 + camera.y)

func contains_screen_point(sx: float, sy: float) -> bool:
	return viewport.has_point(Vector2(sx, sy))

func tick() -> void:
	if damage_flash > 0:
		damage_flash -= 1
	if shake > 0.0:
		shake -= 1.0
