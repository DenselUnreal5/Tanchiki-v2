class_name BuildEnvironment
extends RefCounted

## Match-scoped terrain influence. One activation per build, independent of respawns.
## The host owns gameplay; clients receive bounded presentation state in snapshot extra.
const IDS := ["acid_hunter", "ice_hunter", "fire_hunter", "shock_hunter", "stealth_hunter", "juggernaut", "ghost_sniper", "fortress", "gunner"]
const ZONES_PER_BUILD := 18
const WARNING_TICKS := 120
const RADIUS := 30.0
const PULSE_TICKS := 60
var active: Dictionary = {}
var zones: Array = []

static func owner_key(tank) -> int:
	return int(tank.net_id) if tank.net_id > 0 else -int(tank.id)

func _owner(world, key: int):
	for tank in world.tanks:
		if owner_key(tank) == key: return tank
	return null

func activate(world, tank, build_id: String) -> void:
	if world.puppet or tank == null or not tank.alive or not IDS.has(build_id) or active.has(build_id): return
	active[build_id] = {"owner": owner_key(tank), "start": world.tick}
	# Separate seeded generator: discovering candidate cells never consumes combat RNG.
	var random := Rng.new(int(world.level.get("seed", 0)) ^ ((IDS.find(build_id) + 1) * 7919))
	var candidates := []
	var protected := _protected_positions(world)
	for row in range(2, world.map.rows - 2):
		for col in range(2, world.map.cols - 2):
			if build_id == "stealth_hunter" and world.map.get_tile(row, col) == Cfg.T_ROAD: continue
			if _safe_cell(world, row, col, protected): candidates.append(Vector2(col, row))
	candidates = random.shuffled(candidates)
	var desired_count := clampi(world.map.tiles.size() / 450, 6, ZONES_PER_BUILD)
	var count := 0
	for cell in candidates:
		var pos: Vector2 = (cell + Vector2.ONE * 0.5) * Cfg.TILE
		var crowded := false
		for zone in zones:
			if pos.distance_squared_to(Vector2(zone.x, zone.y)) < pow(RADIUS * 2.5, 2):
				crowded = true
				break
		if crowded: continue
		zones.append({"id": build_id, "x": pos.x, "y": pos.y, "start": world.tick, "grown": false})
		count += 1
		if count >= desired_count: break

func _protected_positions(world) -> Array:
	var positions := []
	for tank in world.tanks: positions.append(Vector2(tank.spawn_x, tank.spawn_y))
	for flag in world.flags: positions.append(Vector2(flag.x, flag.y))
	for row in world.map.rows:
		for col in world.map.cols:
			if world.map.get_tile(row, col) in [Cfg.T_BASE_P, Cfg.T_BASE_E]:
				positions.append(Vector2((col + 0.5) * Cfg.TILE, (row + 0.5) * Cfg.TILE))
	return positions

func _safe_cell(world, row: int, col: int, protected: Array = []) -> bool:
	# Never cover bridges, water, buildings, bases, objectives or spawn approaches.
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if not world.map.get_tile(row + dr, col + dc) in [Cfg.T_EMPTY, Cfg.T_GRASS, Cfg.T_SAND, Cfg.T_ROAD, Cfg.T_DUNE]: return false
	var pos := Vector2((col + 0.5) * Cfg.TILE, (row + 0.5) * Cfg.TILE)
	if protected.is_empty(): protected = _protected_positions(world)
	for point in protected:
		if pos.distance_squared_to(point) < pow(Cfg.TILE * 4.5, 2): return false
	return true

func ready_at(world, build_id: String) -> bool:
	return active.has(build_id) and world.tick - int(active[build_id].start) >= WARNING_TICKS

func _inside(zone: Dictionary, tank) -> bool:
	return Vector2(tank.x - float(zone.x), tank.y - float(zone.y)).length_squared() <= RADIUS * RADIUS

func _hostile(world, build_id: String, tank) -> bool:
	if not active.has(build_id): return false
	return world.are_hostile(_owner(world, int(active[build_id].owner)), tank)

func speed_multiplier(world, tank) -> float:
	var factor := 1.0
	for zone in zones:
		var id: String = zone.id
		if not ready_at(world, id) or not _inside(zone, tank): continue
		if _owner(world, int(active[id].owner)) == null: continue
		if id == "ice_hunter" and _hostile(world, id, tank): factor = minf(factor, 0.65)
		elif id == "acid_hunter" and _hostile(world, id, tank): factor = minf(factor, 0.8)
		elif id == "juggernaut":
			factor = minf(factor, 0.8) if _hostile(world, id, tank) else maxf(factor, 1.12)
	return factor

func obscured(world, observer, target) -> bool:
	if observer == null or target == null or not world.are_hostile(observer, target): return false
	if not ready_at(world, "ghost_sniper"): return false
	if Vector2(observer.x - target.x, observer.y - target.y).length_squared() <= 140.0 * 140.0: return false
	for zone in zones:
		if zone.id == "ghost_sniper" and (_inside(zone, observer) or _inside(zone, target)): return true
	return false

func _near_water(world, tank) -> bool:
	var row: int = world.map.row_at(tank.y)
	var col: int = world.map.col_at(tank.x)
	# Shore contact only; bridges remain safe, and the river stays impassable.
	if world.map.get_tile(row, col) == Cfg.T_BRIDGE: return false
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if world.map.get_tile(row + dr, col + dc) != Cfg.T_WATER: continue
			var closest := Vector2(clampf(tank.x, (col + dc) * Cfg.TILE, (col + dc + 1) * Cfg.TILE), clampf(tank.y, (row + dr) * Cfg.TILE, (row + dr + 1) * Cfg.TILE))
			if closest.distance_squared_to(Vector2(tank.x, tank.y)) < 12.0 * 12.0: return true
	return false

func update(world) -> void:
	if world.puppet or active.is_empty(): return
	for zone in zones:
		if zone.id != "stealth_hunter" or zone.grown or not ready_at(world, zone.id): continue
		zone.grown = true
		var row: int = world.map.row_at(zone.y)
		var col: int = world.map.col_at(zone.x)
		for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var r: int = row + offset.y
			var c: int = col + offset.x
			if world.map.get_tile(r, c) in [Cfg.T_EMPTY, Cfg.T_GRASS, Cfg.T_SAND, Cfg.T_DUNE]:
				world.map.set_tile(r, c, Cfg.T_TREE)
	if world.tick % PULSE_TICKS != 0: return
	for tank in world.tanks:
		if not tank.alive or tank.spawn_protect > 0: continue
		# Deduplicate per element so touching a bank and puddle never stacks damage.
		var touching := {}
		for zone in zones:
			if ready_at(world, zone.id) and _inside(zone, tank): touching[zone.id] = true
		if _near_water(world, tank):
			for id in ["acid_hunter", "shock_hunter"]:
				if ready_at(world, id): touching[id] = true
		for id in touching:
			if not _hostile(world, id, tank):
				if _owner(world, int(active[id].owner)) == null: continue
				if id == "fortress": tank.hp = minf(tank.max_hp, tank.hp + 1.0)
				elif id == "gunner": tank.heat = maxf(0.0, tank.heat - 5.0)
				continue
			var attacker = _owner(world, int(active[id].owner))
			match id:
				"acid_hunter":
					world.deal_damage(tank, 3.0, attacker, "acid")
					if tank.alive: tank.apply_acid(world, attacker, 0.25, 1)
				"fire_hunter": tank.ignite(world, attacker, false, 0.35)
				"shock_hunter":
					world.deal_damage(tank, 2.0, attacker, "shock")
					if tank.alive: tank.apply_shock(world, attacker, 12)

func snapshot(tick: int) -> Dictionary:
	var builds := []
	for id in active: builds.append([id, active[id].owner, maxi(0, tick - int(active[id].start))])
	var areas := []
	for zone in zones: areas.append([zone.id, zone.x, zone.y])
	return {"builds": builds, "zones": areas}

func apply_snapshot(world, data: Dictionary) -> void:
	if not data.get("builds") is Array or not data.get("zones") is Array: return
	var next := {}
	for entry in data.builds.slice(0, IDS.size()):
		if not entry is Array or entry.size() != 3 or not IDS.has(entry[0]): continue
		next[entry[0]] = {"owner": int(entry[1]), "start": world.tick - clampi(int(entry[2]), 0, 100000000)}
	var areas := []
	for entry in data.zones.slice(0, IDS.size() * ZONES_PER_BUILD):
		if not entry is Array or entry.size() != 3 or not next.has(entry[0]): continue
		var pos := Vector2(float(entry[1]), float(entry[2]))
		if not pos.is_finite() or pos.x < 0 or pos.y < 0 or pos.x >= world.map.width or pos.y >= world.map.height: continue
		areas.append({"id": entry[0], "x": pos.x, "y": pos.y, "start": next[entry[0]].start, "grown": true})
	active = next
	zones = areas

func clear() -> void:
	active.clear()
	zones.clear()
