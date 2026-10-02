class_name LevelGen
extends RefCounted

const Archetypes = preload("res://scripts/mapgen/archetypes.gd")
const MAX_BRIDGES := WaterGen.MAX_BRIDGES

static func _ctf_player_area(cols: int, rows: int) -> Dictionary:
	return {"r0": rows - 8, "r1": rows - 4, "c0": cols / 2 - 8, "c1": cols / 2 + 8}

static func _ctf_enemy_area(cols: int, rows: int) -> Dictionary:
	return {"r0": 3, "r1": 7, "c0": cols / 2 - 8, "c1": cols / 2 + 8}

static func _area_any(cols: int, rows: int) -> Dictionary:
	return {"r0": 3, "r1": rows - 4, "c0": 3, "c1": cols - 4}

static func _defense_player_area(cols: int, rows: int) -> Dictionary:
	return {
		"r0": rows / 2 - 3, "r1": rows / 2 + 3,
		"c0": cols / 2 - 3, "c1": cols / 2 + 3,
	}

static func _defense_enemy_area(cols: int, rows: int) -> Dictionary:
	return {"r0": 2, "r1": rows - 3, "c0": 2, "c1": cols - 3, "edge": true}

static func generate(level_num: int, mode: String, seed_override: int = -1,
		location: String = Locations.CITY, archetype: String = "auto") -> Dictionary:
	var seed_value := 0
	if seed_override >= 0:
		seed_value = seed_override
	elif level_num < 0:
		seed_value = randi() & 0xFFFFFFFF
	else:
		seed_value = ((level_num - 1) * 7777 + 42) & 0xFFFFFFFF
	var rng := Rng.new(seed_value)
	var loc_id := Locations.resolve(location, rng)
	var loc := Locations.get_location(loc_id)

	var arch := archetype
	if arch == "auto" or arch == "":
		var arch_pool := ["avenues", "plaza", "river", "fortress", "labyrinths", "industrial", "radial", "canyon"]
		arch = arch_pool[int(rng.nextf() * arch_pool.size()) % arch_pool.size()]

	var cols := Cfg.COLS
	var rows := Cfg.ROWS
	if mode == "defense":
		cols = Cfg.COLS / 2
		rows = Cfg.ROWS / 2
	elif mode == "ctf":
		cols = Cfg.CTF_COLS
		rows = Cfg.CTF_ROWS
	var map := GameMap.new(cols, rows)
	map.fill(Cfg.T_EMPTY)

	for r in rows:
		map.set_tile(r, 0, Cfg.T_WALL)
		map.set_tile(r, cols - 1, Cfg.T_WALL)
	for c in cols:
		map.set_tile(0, c, Cfg.T_WALL)
		map.set_tile(rows - 1, c, Cfg.T_WALL)

	var plan: Dictionary
	if String(loc.get("terrain", "grid")) == "organic":
		# Полная замена уличной сетки клеточным автоматом (скальные гряды/
		# заросли между полянами и тропами) — см. OrganicGen. plan остаётся
		# валидным пустым словарём для потребителей вроде
		# world_view.gd::_build_road_class() (дорог тут просто нет).
		plan = {"v": [], "h": [], "blocks": [], "circles": [], "seeds": [], "links": []}
		OrganicGen.build(map, rng, cols, rows, loc)
	else:
		plan = MapPlan.build(rng, cols, rows, loc)
		RoadNet.paint(map, plan)
		for block in plan["blocks"]:
			Districts.paint(map, rng, block, loc)
		RoadNet.restripe_streets(map, plan)
		RoadNet.paint_links(map, plan)

	# Применение архитектурного стиля карты
	if arch == "radial" and mode in ["ffa", "koth", "defense"] and bool(loc.get("arterials", true)):
		_build_radial(map, rng, cols, rows, loc)
	elif arch == "avenues" and mode in ["ffa", "koth", "defense"] and bool(loc.get("arterials", true)):
		_build_avenues(map, rng, cols, rows, loc)
	else:
		Archetypes.apply(map, rng, arch, cols, rows, mode, loc)

	var river_weight: float = float(loc["river"])
	if arch == "river" and river_weight < 0.8:
		river_weight = 1.0

	if loc_id == "shore":
		# Архипелаг вместо реки через центр — залив на одной стороне карты
		# + острова с мостами (см. WaterGen.carve_archipelago). Заменяет
		# обычную реку для этой локации целиком, во всех режимах.
		WaterGen.carve_archipelago(map, rng, cols, rows, loc)
	elif (mode == "ffa" or mode == "koth" or arch == "river") and river_weight > 0.0:
		if loc_id == "city":
			WaterGen.carve_city_canals(map, rng, cols, rows, plan["h"])
		else:
			WaterGen.carve(map, rng, cols, rows, plan["h"], river_weight)

	Locations.overgrow(map, rng, loc)
	Locations.carve_oases(map, rng, loc)

	var homes := {"player": null, "enemy": null}
	var flag_spots := {"player": [], "enemy": []}
	if mode == "ctf":
		_build_ctf(map, rng, cols, rows, homes, flag_spots)
	if mode == "defense":
		var cr := rows / 2
		var cc := cols / 2
		_fill_rect(map, cr - 4, cr + 4, cc - 4, cc + 4, Cfg.T_ROAD)
		homes["player"] = Vector2(cc * Cfg.TILE + Cfg.TILE * 0.5, cr * Cfg.TILE + Cfg.TILE * 0.5)

	map.ensure_connectivity()
	RoadNet.repair(map)

	var areas := {}
	if mode == "ctf":
		areas["player"] = _ctf_player_area(cols, rows)
		areas["enemy"] = _ctf_enemy_area(cols, rows)
	elif mode == "defense":
		areas["player"] = _defense_player_area(cols, rows)
		areas["enemy"] = _defense_enemy_area(cols, rows)
	else:
		areas["player"] = _area_any(cols, rows)
		areas["enemy"] = _area_any(cols, rows)
	areas["any"] = _area_any(cols, rows)

	return {
		"map": map,
		"seed": seed_value,
		"mode": mode,
		"requested_level": level_num,
		"homes": homes,
		"flag_spots": flag_spots,
		"areas": areas,
		"plan": plan,
		"location": loc_id,
		"archetype": arch,
	}

## Архетип "radial": кольцевые бульвары + лучевые улицы от центра карты —
## та же точка, что уже использует "ядерный" seed района в
## MapPlan._district_seeds() и куда сходится схлопывание карты в KOTH
## (World._setup_koth()'s flood_tiles, отсортированные по расстоянию от
## края) — совпадение центра усиливает связку с KOTH без лишней
## координации кода. Рисуется поверх уже готовой сетки/зданий, как и
## plaza/fortress — гарантия ширины/формы держится конструктивно.
static func _build_radial(map: GameMap, rng: Rng, cols: int, rows: int,
		loc: Dictionary) -> void:
	var cx := float(cols) / 2.0
	var cy := float(rows) / 2.0
	var w: float = float(loc.get("arterial_w", MapPlan.ARTERIAL_W))
	var min_dim := float(mini(cols, rows))
	var radii := [min_dim * 0.32]
	if cols >= 100 and rng.nextf() < 0.5:
		radii.append(min_dim * 0.46)
	for radius in radii:
		RoadNet.paint_ring(map, cx, cy, radius, w)
	var spokes := 5 + int(rng.nextf() * 3.0)
	var phase := rng.nextf() * TAU / float(spokes)
	for i in spokes:
		RoadNet.paint_spoke(map, cx, cy, phase + TAU * float(i) / float(spokes), w)

	var outer: float = radii[radii.size() - 1] + w * 2.0
	for r in range(1, rows - 1):
		for c in range(1, cols - 1):
			var dr := float(r) - cy
			var dc := float(c) - cx
			if sqrt(dr * dr + dc * dc) <= outer:
				continue
			var t := map.get_tile(r, c)
			if t == Cfg.T_ROAD or t == Cfg.T_BRIDGE or t == Cfg.T_WATER:
				continue
			map.set_tile(r, c, Cfg.T_EMPTY)

	var cover_count := maxi(4, int(min_dim / 14.0))
	var placed := 0
	var tries := 0
	while placed < cover_count and tries < cover_count * 12:
		tries += 1
		var rr := 2 + int(rng.nextf() * float(rows - 4))
		var cc := 2 + int(rng.nextf() * float(cols - 4))
		var dr2 := float(rr) - cy
		var dc2 := float(cc) - cx
		var dist := sqrt(dr2 * dr2 + dc2 * dc2)
		if dist <= outer + 3.0:
			continue
		if map.get_tile(rr, cc) != Cfg.T_EMPTY:
			continue
		_cover_block(map, rr, cc, 2, 2)
		placed += 1

## Архетип "avenues": одна или две диагональные магистрали угол-в-угол
## через всю карту, поверх уже готовой сетки/зданий — режут прямоугольные
## кварталы на треугольные/трапециевидные куски (RoadNet.paint_thick_line
## тот же примитив, что и лучи "radial", просто между двумя произвольными
## точками, а не от центра до края). Если проведены обе — на пересечении
## в центре карты ставится маленькая площадь-«арка» как landmark.
static func _build_avenues(map: GameMap, rng: Rng, cols: int, rows: int,
		loc: Dictionary) -> void:
	var w: float = float(loc.get("arterial_w", MapPlan.ARTERIAL_W))
	var m := 3.0
	var backslash := [Vector2(m, m), Vector2(float(cols) - 1.0 - m, float(rows) - 1.0 - m)]
	var slash := [Vector2(float(cols) - 1.0 - m, m), Vector2(m, float(rows) - 1.0 - m)]

	var draw_backslash := rng.nextf() < 0.5
	var draw_both := rng.nextf() < 0.35
	if draw_both:
		RoadNet.paint_thick_line(map, backslash[0].x, backslash[0].y, backslash[1].x, backslash[1].y, w)
		RoadNet.paint_thick_line(map, slash[0].x, slash[0].y, slash[1].x, slash[1].y, w)
		_thin_along_line(map, rng, backslash[0].x, backslash[0].y, backslash[1].x, backslash[1].y, w)
		_thin_along_line(map, rng, slash[0].x, slash[0].y, slash[1].x, slash[1].y, w)
		var cr := rows / 2
		var cc := cols / 2
		_fill_rect(map, cr - 3, cr + 3, cc - 3, cc + 3, Cfg.T_ROAD)
		map.set_tile(cr - 3, cc, Cfg.T_WALL)
		map.set_tile(cr + 3, cc, Cfg.T_WALL)
		map.set_tile(cr, cc - 3, Cfg.T_WALL)
		map.set_tile(cr, cc + 3, Cfg.T_WALL)
	else:
		var line: Array = backslash if draw_backslash else slash
		RoadNet.paint_thick_line(map, line[0].x, line[0].y, line[1].x, line[1].y, w)
		_thin_along_line(map, rng, line[0].x, line[0].y, line[1].x, line[1].y, w)

static func _thin_along_line(map: GameMap, rng: Rng, x0: float, y0: float, x1: float, y1: float,
		w: float) -> void:
	var dx := x1 - x0
	var dy := y1 - y0
	var dist := sqrt(dx * dx + dy * dy)
	if dist < 0.001:
		return
	var steps := int(ceil(dist / 0.6))
	var nx := -dy / dist
	var ny := dx / dist
	var inner := w * 1.5
	var outer := w * 4.5
	var band_steps := int(ceil((outer - inner) / 0.6))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var px := x0 + dx * t
		var py := y0 + dy * t
		for side in [-1.0, 1.0]:
			for j in band_steps + 1:
				if rng.nextf() >= 0.18:
					continue
				var band := inner + (outer - inner) * float(j) / float(band_steps)
				var tx: float = px + nx * band * side
				var ty: float = py + ny * band * side
				var r := int(round(ty))
				var c := int(round(tx))
				if r <= 0 or c <= 0 or r >= map.rows - 1 or c >= map.cols - 1:
					continue
				var tile := map.get_tile(r, c)
				if tile == Cfg.T_BRICK or tile == Cfg.T_WALL:
					map.set_tile(r, c, Cfg.T_EMPTY)

static func _fill_rect(map: GameMap, r0: int, r1: int, c0: int, c1: int, tile: int) -> void:
	for r in range(maxi(1, r0), mini(map.rows - 2, r1) + 1):
		for c in range(maxi(1, c0), mini(map.cols - 2, c1) + 1):
			map.set_tile(r, c, tile)

static func _cover_block(map: GameMap, r: int, c: int, w: int, h: int) -> void:
	for dr in h:
		for dc in w:
			map.set_tile(r + dr, c + dc, Cfg.T_BRICK)
	if w >= 2 and h >= 2:
		map.set_tile(r + h / 2, c + w / 2, Cfg.T_WALL)

static func _build_ctf(map: GameMap, rng: Rng, cols: int, rows: int,
		homes: Dictionary, flag_spots: Dictionary) -> void:
	var cc := cols / 2
	var mid := rows / 2

	# База врага на севере: асфальтированный плац с защитными укреплениями
	_fill_rect(map, 1, 5, cc - 6, cc + 6, Cfg.T_ROAD)
	map.set_tile(2, cc, Cfg.T_BASE_E)
	homes["enemy"] = Vector2(cc * Cfg.TILE + Cfg.TILE * 0.5, 2 * Cfg.TILE + Cfg.TILE * 0.5)
	map.set_tile(3, cc - 5, Cfg.T_WALL)
	map.set_tile(3, cc + 5, Cfg.T_WALL)
	map.set_tile(4, cc - 3, Cfg.T_BRICK)
	map.set_tile(4, cc + 3, Cfg.T_BRICK)

	# База игрока на юге
	_fill_rect(map, rows - 6, rows - 2, cc - 6, cc + 6, Cfg.T_ROAD)
	map.set_tile(rows - 3, cc, Cfg.T_BASE_P)
	homes["player"] = Vector2(cc * Cfg.TILE + Cfg.TILE * 0.5, (rows - 3) * Cfg.TILE + Cfg.TILE * 0.5)
	map.set_tile(rows - 4, cc - 5, Cfg.T_WALL)
	map.set_tile(rows - 4, cc + 5, Cfg.T_WALL)
	map.set_tile(rows - 5, cc - 3, Cfg.T_BRICK)
	map.set_tile(rows - 5, cc + 3, Cfg.T_BRICK)

	# Выезды с баз на дорожную сеть
	_fill_rect(map, 5, 8, cc - 1, cc + 1, Cfg.T_ROAD)
	_fill_rect(map, rows - 9, rows - 6, cc - 1, cc + 1, Cfg.T_ROAD)

	# Центральные тактические укрытия (без разрезания всей карты)
	for side in [-1, 1]:
		_cover_block(map, mid - 2, cc + side * 8 - 1, 2, 2)
		_cover_block(map, mid + 1, cc + side * 12 - 1, 2, 2)

	var spots := _pick_flag_spots(map, rng, 10,
		int(rows * 0.22), int(rows * 0.78))
	flag_spots["neutral"] = spots
	flag_spots["spots"] = spots
	flag_spots["enemy"] = spots.slice(0, maxi(1, spots.size() / 2))
	flag_spots["player"] = spots.slice(maxi(0, spots.size() / 2), spots.size())

static func _pick_flag_spots(map: GameMap, rng: Rng, count: int, row_from: int, row_to: int) -> Array:
	var spots := []
	var min_gap := float(Cfg.TILE * 10)
	var cols := map.cols
	var rows := map.rows
	var attempt := 0
	while attempt < 300 and spots.size() < count:
		attempt += 1
		var c := 5 + int(rng.nextf() * float(cols - 10))
		var r := row_from + int(rng.nextf() * float(maxi(1, row_to - row_from)))
		if not GameMap.is_drivable_tile(map.get_tile(r, c)):
			continue
		var p := Vector2(c * Cfg.TILE + Cfg.TILE * 0.5, r * Cfg.TILE + Cfg.TILE * 0.5)
		var too_close := false
		for s in spots:
			if s.distance_to(p) < min_gap:
				too_close = true
				break
		if too_close:
			continue
		spots.append(p)

	var fallback_col := cols / 2 - count * 3
	while spots.size() < count:
		var r: int = clampi((row_from + row_to) / 2, 1, rows - 2)
		var c: int = clampi(fallback_col, 1, cols - 2)
		map.set_tile(r, c, Cfg.T_EMPTY)
		spots.append(Vector2(c * Cfg.TILE + Cfg.TILE * 0.5, r * Cfg.TILE + Cfg.TILE * 0.5))
		fallback_col += 4
	return spots
