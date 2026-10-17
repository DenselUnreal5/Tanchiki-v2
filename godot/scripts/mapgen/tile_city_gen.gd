class_name TileCityGen
extends RefCounted

const BLOCK_MIN := 4
const BLOCK_MAX := 6
const MERGE_SHARE := 0.2
const STAIR_PRUNE := 1.0
const RIVER_JOG := 0.15
const OUTSKIRT_TREE := 0.07
const OUTSKIRT_HOUSE := 0.024

static var _style := {}

class Lattice extends RefCounted:
	var xs: Array = []
	var ys: Array = []
	var h := {}
	var v := {}
	var keep := {}
	var kind := {}
	var alley := []

static func _st(key: String, fallback: float) -> float:
	return float(_style.get(key, fallback))

static func build(map: GameMap, rng: Rng, cols: int, rows: int, arch: String, want_river: bool,
		style: Dictionary = {}) -> Dictionary:
	_style = style
	for r in range(1, rows - 1):
		for c in range(1, cols - 1):
			map.set_tile(r, c, Cfg.T_GRASS)

	var lat := Lattice.new()
	lat.xs = _lines(rng, cols)
	lat.ys = _lines(rng, rows)
	for j in lat.ys.size():
		for i in lat.xs.size() - 1:
			lat.h[Vector2i(i, j)] = true
	for i in lat.xs.size():
		for j in lat.ys.size() - 1:
			lat.v[Vector2i(i, j)] = true

	match arch:
		"radial":
			_make_center(lat, "arena", true)
		"plaza":
			_make_center(lat, "park", false)
		"avenues":
			_make_stair(lat, rng)
	var small := cols * rows < 5000
	_make_ponds(lat, rng, int(_st("ponds_small", 1.0)) if small else int(_st("ponds_large", 2.0)))
	_merge_random(lat, rng)

	var links := _paint_roads(map, lat)
	if want_river:
		var used := {}
		for k in int(_st("rivers_small", 1.0)) if small else int(_st("rivers", 1.0)):
			_carve_river(map, lat, rng, used)
	_plant_alleys(map, lat)
	_fill_regions(map, lat, rng)
	_fill_outskirts(map, lat, rng)

	return {"v": [], "h": [], "blocks": [], "circles": [], "seeds": [], "links": links}

static func tidy(map: GameMap, skip: Rect2i = Rect2i()) -> void:
	_join_diagonals(map)
	var changed := true
	var guard := 0
	while changed and guard < 64:
		guard += 1
		changed = false
		for r in range(2, map.rows - 2):
			for c in range(2, map.cols - 2):
				if skip.has_point(Vector2i(c, r)):
					continue
				var t := map.get_tile(r, c)
				if t == Cfg.T_ROAD and _degree(map, r, c, true) <= 1:
					map.set_tile(r, c, Cfg.T_GRASS)
					changed = true
				elif t == Cfg.T_WATER and _degree(map, r, c, false) <= 1:
					map.set_tile(r, c, Cfg.T_GRASS)
					changed = true
				elif t == Cfg.T_BRIDGE:
					var fix := _bridge_fix(map, r, c)
					if fix != Cfg.T_BRIDGE:
						map.set_tile(r, c, fix)
						changed = true

static func _join_diagonals(map: GameMap) -> void:
	for r in range(1, map.rows - 2):
		for c in range(1, map.cols - 1):
			if not _is_tile(map, r, c, true):
				continue
			for dc in [-1, 1]:
				var c2: int = c + dc
				if not _is_tile(map, r + 1, c2, true):
					continue
				if _is_tile(map, r + 1, c, true) or _is_tile(map, r, c2, true):
					continue
				if _open_ground(map.get_tile(r + 1, c)):
					map.set_tile(r + 1, c, Cfg.T_ROAD)
				elif _open_ground(map.get_tile(r, c2)):
					map.set_tile(r, c2, Cfg.T_ROAD)

static func _open_ground(t: int) -> bool:
	return t == Cfg.T_GRASS or t == Cfg.T_EMPTY or t == Cfg.T_SAND or t == Cfg.T_TREE

static func _is_tile(map: GameMap, r: int, c: int, paved: bool) -> bool:
	var t := map.get_tile(r, c)
	if t == Cfg.T_BRIDGE:
		return true
	return t == (Cfg.T_ROAD if paved else Cfg.T_WATER)

static func _degree(map: GameMap, r: int, c: int, paved: bool) -> int:
	var d := 0
	if _is_tile(map, r - 1, c, paved):
		d += 1
	if _is_tile(map, r + 1, c, paved):
		d += 1
	if _is_tile(map, r, c - 1, paved):
		d += 1
	if _is_tile(map, r, c + 1, paved):
		d += 1
	return d

static func _landing(map: GameMap, r: int, c: int) -> bool:
	var t := map.get_tile(r, c)
	return _is_tile(map, r, c, true) or (t != Cfg.T_WATER and GameMap.is_drivable_tile(t))

static func _bridge_fix(map: GameMap, r: int, c: int) -> int:
	var road_v := _landing(map, r - 1, c) and _landing(map, r + 1, c)
	var road_h := _landing(map, r, c - 1) and _landing(map, r, c + 1)
	var water_v := _is_tile(map, r - 1, c, false) and _is_tile(map, r + 1, c, false)
	var water_h := _is_tile(map, r, c - 1, false) and _is_tile(map, r, c + 1, false)
	if (road_v and water_h) or (road_h and water_v):
		return Cfg.T_BRIDGE
	if road_v or road_h:
		return Cfg.T_ROAD
	if water_v or water_h:
		return Cfg.T_WATER
	return Cfg.T_GRASS

static func _lines(rng: Rng, n: int) -> Array:
	var out := [0]
	var span := 0
	while true:
		var gap := 1 + BLOCK_MIN + int(rng.nextf() * float(BLOCK_MAX - BLOCK_MIN + 1))
		if 2 + span + gap > n - 3:
			break
		span += gap
		out.append(span)
	var shift := 2 + ((n - 3) - (2 + span)) / 2
	for k in out.size():
		out[k] = int(out[k]) + shift
	return out

static func _deg(lat: Lattice, i: int, j: int) -> int:
	var d := 0
	if lat.h.get(Vector2i(i - 1, j), false):
		d += 1
	if lat.h.get(Vector2i(i, j), false):
		d += 1
	if lat.v.get(Vector2i(i, j - 1), false):
		d += 1
	if lat.v.get(Vector2i(i, j), false):
		d += 1
	return d

static func _ends(type: int, key: Vector2i) -> Array:
	if type == 0:
		return [key, Vector2i(key.x + 1, key.y)]
	return [key, Vector2i(key.x, key.y + 1)]

static func _seg(lat: Lattice, type: int) -> Dictionary:
	return lat.h if type == 0 else lat.v

static func _connected(lat: Lattice) -> bool:
	var start := Vector2i(-1, -1)
	var total := 0
	for i in lat.xs.size():
		for j in lat.ys.size():
			if _deg(lat, i, j) > 0:
				total += 1
				if start.x < 0:
					start = Vector2i(i, j)
	if total == 0:
		return false
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		var nbs := []
		if lat.h.get(Vector2i(p.x - 1, p.y), false):
			nbs.append(Vector2i(p.x - 1, p.y))
		if lat.h.get(p, false):
			nbs.append(Vector2i(p.x + 1, p.y))
		if lat.v.get(Vector2i(p.x, p.y - 1), false):
			nbs.append(Vector2i(p.x, p.y - 1))
		if lat.v.get(p, false):
			nbs.append(Vector2i(p.x, p.y + 1))
		for nb in nbs:
			if not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return seen.size() == total

static func _remove_group(lat: Lattice, group: Array) -> bool:
	for item in group:
		var seg := _seg(lat, int(item[0]))
		if not seg.get(item[1], false) or lat.keep.has(Vector3i(int(item[0]), item[1].x, item[1].y)):
			return false
	for item in group:
		_seg(lat, int(item[0]))[item[1]] = false
	var ok := true
	for item in group:
		for e in _ends(int(item[0]), item[1]):
			if _deg(lat, e.x, e.y) == 1:
				ok = false
	if ok:
		ok = _connected(lat)
	if not ok:
		for item in group:
			_seg(lat, int(item[0]))[item[1]] = true
	return ok

static func _keep(lat: Lattice, type: int, key: Vector2i) -> void:
	lat.keep[Vector3i(type, key.x, key.y)] = true

static func _keep_block_ring(lat: Lattice, i0: int, j0: int, size: int) -> void:
	for k in size:
		_keep(lat, 0, Vector2i(i0 + k, j0))
		_keep(lat, 0, Vector2i(i0 + k, j0 + size))
		_keep(lat, 1, Vector2i(i0, j0 + k))
		_keep(lat, 1, Vector2i(i0 + size, j0 + k))

static func _set_kind(lat: Lattice, i0: int, j0: int, size: int, kind: String) -> void:
	for di in size:
		for dj in size:
			lat.kind[Vector2i(i0 + di, j0 + dj)] = kind

static func _group_inner(i0: int, j0: int) -> Array:
	return [[0, Vector2i(i0, j0 + 1)], [0, Vector2i(i0 + 1, j0 + 1)],
		[1, Vector2i(i0 + 1, j0)], [1, Vector2i(i0 + 1, j0 + 1)]]

static func _make_center(lat: Lattice, kind: String, spokes: bool) -> void:
	var nx := lat.xs.size()
	var ny := lat.ys.size()
	if nx < 3 or ny < 3:
		return
	var i0 := nx / 2 - 1
	var j0 := ny / 2 - 1
	if not _remove_group(lat, _group_inner(i0, j0)):
		return
	_keep_block_ring(lat, i0, j0, 2)
	_set_kind(lat, i0, j0, 2, kind)
	if not spokes:
		return
	for i in nx - 1:
		if i < i0 or i >= i0 + 2:
			_keep(lat, 0, Vector2i(i, j0 + 1))
			lat.alley.append([0, Vector2i(i, j0 + 1)])
	for j in ny - 1:
		if j < j0 or j >= j0 + 2:
			_keep(lat, 1, Vector2i(i0 + 1, j))
			lat.alley.append([1, Vector2i(i0 + 1, j)])

static func _make_stair(lat: Lattice, rng: Rng) -> void:
	var nx := lat.xs.size()
	var ny := lat.ys.size()
	var flip := rng.nextf() < 0.5
	var steps_r := nx - 1
	var steps_d := ny - 1
	var done_r := 0
	var done_d := 0
	var i := nx - 1 if flip else 0
	var j := 0
	var nodes := [Vector2i(i, j)]
	while done_r < steps_r or done_d < steps_d:
		var go_r := false
		if done_d >= steps_d:
			go_r = true
		elif done_r < steps_r:
			go_r = float(done_r + 1) / float(steps_r) <= float(done_d + 1) / float(steps_d)
		if go_r:
			var ni := i - 1 if flip else i + 1
			_keep(lat, 0, Vector2i(mini(i, ni), j))
			lat.alley.append([0, Vector2i(mini(i, ni), j)])
			i = ni
			done_r += 1
		else:
			_keep(lat, 1, Vector2i(i, j))
			lat.alley.append([1, Vector2i(i, j)])
			j += 1
			done_d += 1
		nodes.append(Vector2i(i, j))
	for n in nodes:
		var incident := [[0, Vector2i(n.x - 1, n.y)], [0, n], [1, Vector2i(n.x, n.y - 1)], [1, n]]
		for item in rng.shuffled(incident):
			if rng.nextf() < STAIR_PRUNE:
				_remove_group(lat, [item])

static func _make_ponds(lat: Lattice, rng: Rng, count: int) -> void:
	var nx := lat.xs.size()
	var ny := lat.ys.size()
	if nx < 3 or ny < 3:
		return
	var made := 0
	for attempt in 30:
		if made >= count:
			return
		var i0 := rng.range_i(0, nx - 2)
		var j0 := rng.range_i(0, ny - 2)
		var busy := false
		for di in 2:
			for dj in 2:
				if lat.kind.has(Vector2i(i0 + di, j0 + dj)):
					busy = true
		if busy:
			continue
		if not _remove_group(lat, _group_inner(i0, j0)):
			continue
		_keep_block_ring(lat, i0, j0, 2)
		_set_kind(lat, i0, j0, 2, "pond")
		made += 1

static func _merge_random(lat: Lattice, rng: Rng) -> void:
	var cand := []
	for key in lat.h.keys():
		cand.append([0, key])
	for key in lat.v.keys():
		cand.append([1, key])
	var target := int(float(cand.size()) * _st("merge", MERGE_SHARE))
	var removed := 0
	for item in rng.shuffled(cand):
		if removed >= target:
			return
		if _touches_kind(lat, int(item[0]), item[1]):
			continue
		if _remove_group(lat, [item]):
			removed += 1

static func _touches_kind(lat: Lattice, type: int, key: Vector2i) -> bool:
	var a := Vector2i(key.x, key.y - 1) if type == 0 else Vector2i(key.x - 1, key.y)
	return lat.kind.has(key) or lat.kind.has(a)

static func _paint_roads(map: GameMap, lat: Lattice) -> Array:
	var links := []
	for key in lat.h.keys():
		if not lat.h[key]:
			continue
		var r: int = lat.ys[key.y]
		var c0: int = lat.xs[key.x]
		var c1: int = lat.xs[key.x + 1]
		for c in range(c0, c1 + 1):
			map.set_tile(r, c, Cfg.T_ROAD)
		links.append({"r0": r, "r1": r, "c0": c0, "c1": c1})
	for key in lat.v.keys():
		if not lat.v[key]:
			continue
		var c: int = lat.xs[key.x]
		var r0: int = lat.ys[key.y]
		var r1: int = lat.ys[key.y + 1]
		for r in range(r0, r1 + 1):
			map.set_tile(r, c, Cfg.T_ROAD)
		links.append({"r0": r0, "r1": r1, "c0": c, "c1": c})
	return links

static func _band_ok(lat: Lattice, horizontal: bool, k: int) -> bool:
	var crossings := 0
	if horizontal:
		for i in lat.xs.size() - 1:
			if lat.kind.has(Vector2i(i, k)):
				return false
		for i in lat.xs.size():
			if lat.v.get(Vector2i(i, k), false):
				crossings += 1
	else:
		for j in lat.ys.size() - 1:
			if lat.kind.has(Vector2i(k, j)):
				return false
		for j in lat.ys.size():
			if lat.h.get(Vector2i(k, j), false):
				crossings += 1
	return crossings >= 2

static func _carve_river(map: GameMap, lat: Lattice, rng: Rng, used: Dictionary) -> void:
	var horizontal := rng.nextf() < (0.7 if map.cols >= map.rows else 0.3)
	if used.has("horizontal"):
		horizontal = bool(used["horizontal"])
	var lines_across: Array = lat.ys if horizontal else lat.xs
	var lines_along: Array = lat.xs if horizontal else lat.ys
	var bands := []
	for k in lines_across.size() - 1:
		if _band_ok(lat, horizontal, k) and not used.has(k) and not used.has(k - 1) and not used.has(k + 1):
			bands.append(k)
	if bands.is_empty():
		return
	var band: int = rng.pick(bands)
	used["horizontal"] = horizontal
	used[band] = true
	var lo: int = int(lines_across[band]) + 2
	var hi: int = int(lines_across[band + 1]) - 2
	if hi < lo:
		return
	var pos := rng.range_i(lo, hi + 1)
	var length := map.cols if horizontal else map.rows
	var last_jog := -10
	for t in range(1, length - 1):
		_wet(map, horizontal, pos, t)
		if t < 4 or t >= length - 4 or t - last_jog < 3 or not _far_from(lines_along, t, 2):
			continue
		if not _far_from(lines_along, t + 1, 2) or rng.nextf() >= RIVER_JOG:
			continue
		var npos := pos + (1 if rng.nextf() < 0.5 else -1)
		if npos < lo or npos > hi:
			npos = pos - (npos - pos)
		if npos < lo or npos > hi:
			continue
		_wet(map, horizontal, npos, t)
		pos = npos
		last_jog = t

static func _far_from(lines: Array, t: int, dist: int) -> bool:
	for p in lines:
		if absi(int(p) - t) < dist:
			return false
	return true

static func _wet(map: GameMap, horizontal: bool, pos: int, t: int) -> void:
	var r := pos if horizontal else t
	var c := t if horizontal else pos
	if map.get_tile(r, c) == Cfg.T_ROAD:
		map.set_tile(r, c, Cfg.T_BRIDGE)
	elif map.get_tile(r, c) != Cfg.T_BRIDGE:
		map.set_tile(r, c, Cfg.T_WATER)

static func _plant_alleys(map: GameMap, lat: Lattice) -> void:
	for item in lat.alley:
		var type: int = item[0]
		var key: Vector2i = item[1]
		if not _seg(lat, type).get(key, false):
			continue
		if type == 0:
			var r: int = lat.ys[key.y]
			for c in range(int(lat.xs[key.x]) + 2, int(lat.xs[key.x + 1]) - 1, 2):
				_plant(map, r - 1, c)
				_plant(map, r + 1, c)
		else:
			var c: int = lat.xs[key.x]
			for r in range(int(lat.ys[key.y]) + 2, int(lat.ys[key.y + 1]) - 1, 2):
				_plant(map, r, c - 1)
				_plant(map, r, c + 1)

static func _plant(map: GameMap, r: int, c: int) -> void:
	if map.get_tile(r, c) == Cfg.T_GRASS:
		map.set_tile(r, c, Cfg.T_TREE)

static func _cell_rect(lat: Lattice, i: int, j: int) -> Rect2i:
	var c0: int = int(lat.xs[i]) + 1
	var r0: int = int(lat.ys[j]) + 1
	return Rect2i(c0, r0, int(lat.xs[i + 1]) - c0, int(lat.ys[j + 1]) - r0)

static func _fill_regions(map: GameMap, lat: Lattice, rng: Rng) -> void:
	var nx := lat.xs.size()
	var ny := lat.ys.size()
	var parent := {}
	for i in nx - 1:
		for j in ny - 1:
			parent[Vector2i(i, j)] = Vector2i(i, j)
	for i in nx - 1:
		for j in ny - 1:
			var a := Vector2i(i, j)
			if i + 1 < nx - 1 and not lat.v.get(Vector2i(i + 1, j), false):
				_union(parent, a, Vector2i(i + 1, j))
			if j + 1 < ny - 1 and not lat.h.get(Vector2i(i, j + 1), false):
				_union(parent, a, Vector2i(i, j + 1))
	var regions := {}
	for cell in parent.keys():
		var root: Vector2i = _find(parent, cell)
		if not regions.has(root):
			regions[root] = []
		regions[root].append(cell)
	var roots := regions.keys()
	roots.sort()
	for root in roots:
		var cells: Array = regions[root]
		var kind := ""
		for cell in cells:
			if lat.kind.has(cell):
				kind = String(lat.kind[cell])
		if kind == "pond" or kind == "arena" or kind == "park":
			if cells.size() == 4:
				var lo: Vector2i = cells[0]
				for cell in cells:
					lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
				var rect := Rect2i(int(lat.xs[lo.x]) + 1, int(lat.ys[lo.y]) + 1,
					int(lat.xs[lo.x + 2]) - int(lat.xs[lo.x]) - 1,
					int(lat.ys[lo.y + 2]) - int(lat.ys[lo.y]) - 1)
				match kind:
					"pond":
						_pond(map, rng, rect)
					"arena":
						_arena(map, rng, rect)
					_:
						_park(map, rng, rect)
				continue
		var roll := rng.nextf()
		var house_share := _st("house_share", 0.7)
		var grove_share := _st("grove_share", 0.0)
		var park_share := _st("park_share", 0.18)
		for cell in cells:
			var rect := _cell_rect(lat, cell.x, cell.y)
			if roll < house_share:
				_houses(map, rng, rect)
			elif roll < house_share + grove_share:
				_grove(map, rng, rect)
			elif roll < house_share + grove_share + park_share:
				_park(map, rng, rect)
			else:
				_square(map, rng, rect)

static func _find(parent: Dictionary, a: Vector2i) -> Vector2i:
	while parent[a] != a:
		parent[a] = parent[parent[a]]
		a = parent[a]
	return a

static func _union(parent: Dictionary, a: Vector2i, b: Vector2i) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra

static func _touches(map: GameMap, r: int, c: int, tile: int) -> bool:
	return map.get_tile(r - 1, c) == tile or map.get_tile(r + 1, c) == tile \
		or map.get_tile(r, c - 1) == tile or map.get_tile(r, c + 1) == tile

static func _free_cells(map: GameMap, rect: Rect2i) -> Array:
	var out := []
	for r in range(rect.position.y, rect.end.y):
		for c in range(rect.position.x, rect.end.x):
			if map.get_tile(r, c) == Cfg.T_GRASS:
				out.append(Vector2i(c, r))
	return out

static func _houses(map: GameMap, rng: Rng, rect: Rect2i) -> void:
	var front := []
	var inner := []
	for p in _free_cells(map, rect):
		if _touches(map, p.y, p.x, Cfg.T_ROAD):
			front.append(p)
		else:
			inner.append(p)
	var want := rng.range_i(int(_st("house_min", 4.0)), int(_st("house_max", 11.0)))
	var placed := 0
	var front_cap := maxi(0, front.size() - 2)
	for p in rng.shuffled(front):
		if placed >= want or placed >= front_cap:
			break
		map.set_tile(p.y, p.x, Cfg.T_BRICK)
		placed += 1
	for p in rng.shuffled(inner):
		if placed >= want:
			break
		map.set_tile(p.y, p.x, Cfg.T_BRICK)
		placed += 1
	var trees := rng.range_i(int(_st("trees_min", 0.0)), int(_st("trees_max", 3.0)))
	for p in rng.shuffled(inner):
		if trees <= 0:
			break
		if map.get_tile(p.y, p.x) == Cfg.T_GRASS:
			map.set_tile(p.y, p.x, Cfg.T_TREE)
			trees -= 1

static func _grove(map: GameMap, rng: Rng, rect: Rect2i) -> void:
	for p in _free_cells(map, rect):
		var chance := 0.45 if _touches(map, p.y, p.x, Cfg.T_ROAD) else 0.8
		if rng.nextf() < chance:
			map.set_tile(p.y, p.x, Cfg.T_TREE)

static func _park(map: GameMap, rng: Rng, rect: Rect2i) -> void:
	for p in _free_cells(map, rect):
		var edge: bool = p.x == rect.position.x or p.y == rect.position.y \
			or p.x == rect.end.x - 1 or p.y == rect.end.y - 1
		if edge and rng.nextf() < 0.45:
			map.set_tile(p.y, p.x, Cfg.T_TREE)

static func _square(map: GameMap, rng: Rng, rect: Rect2i) -> void:
	var trees := rng.range_i(1, 4)
	for p in rng.shuffled(_free_cells(map, rect)):
		if trees <= 0:
			return
		map.set_tile(p.y, p.x, Cfg.T_TREE)
		trees -= 1

static func _pond(map: GameMap, rng: Rng, rect: Rect2i) -> void:
	var a := rect.position.y + 1
	var b := rect.end.y - 2
	var c := rect.position.x + 1
	var d := rect.end.x - 2
	var m := (a + b) / 2
	var n := (c + d) / 2
	if m - a < 2 or b - m < 2 or n - c < 2 or d - n < 2:
		_park(map, rng, rect)
		return
	for r in range(a, b + 1):
		for cc in range(c, d + 1):
			if r == a or r == b or r == m or cc == c or cc == d or cc == n:
				map.set_tile(r, cc, Cfg.T_WATER)
	for island in [Rect2i(c + 1, a + 1, n - c - 1, m - a - 1), Rect2i(n + 1, a + 1, d - n - 1, m - a - 1),
			Rect2i(c + 1, m + 1, n - c - 1, b - m - 1), Rect2i(n + 1, m + 1, d - n - 1, b - m - 1)]:
		var roll := rng.nextf()
		var spots := _free_cells(map, island)
		if spots.is_empty():
			continue
		var spot: Vector2i = rng.pick(spots)
		if roll < 0.5:
			map.set_tile(spot.y, spot.x, Cfg.T_TREE)
		elif roll < 0.7:
			map.set_tile(spot.y, spot.x, Cfg.T_BRICK)

static func _arena(map: GameMap, rng: Rng, rect: Rect2i) -> void:
	var cx := float(rect.position.x) + float(rect.size.x - 1) * 0.5
	var cy := float(rect.position.y) + float(rect.size.y - 1) * 0.5
	for p in _free_cells(map, rect):
		var edge: bool = p.x == rect.position.x or p.y == rect.position.y \
			or p.x == rect.end.x - 1 or p.y == rect.end.y - 1
		var gate: bool = absf(float(p.x) - cx) <= 1.0 or absf(float(p.y) - cy) <= 1.0
		if edge and not gate:
			map.set_tile(p.y, p.x, Cfg.T_TREE)
	var radius := minf(float(rect.size.x), float(rect.size.y)) * 0.32
	var phase := rng.nextf() * TAU
	for k in 8:
		var ang := phase + TAU * float(k) / 8.0
		var r := int(round(cy + sin(ang) * radius))
		var c := int(round(cx + cos(ang) * radius))
		if map.get_tile(r, c) == Cfg.T_GRASS and not _touches(map, r, c, Cfg.T_ROAD):
			map.set_tile(r, c, Cfg.T_BRICK if k % 2 == 0 else Cfg.T_TREE)
	for corner in [rect.position, Vector2i(rect.end.x - 1, rect.position.y),
			Vector2i(rect.position.x, rect.end.y - 1), rect.end - Vector2i.ONE]:
		if map.get_tile(corner.y, corner.x) == Cfg.T_GRASS:
			map.set_tile(corner.y, corner.x, Cfg.T_TREE)

static func _fill_outskirts(map: GameMap, lat: Lattice, rng: Rng) -> void:
	var x0: int = lat.xs[0]
	var x1: int = lat.xs[lat.xs.size() - 1]
	var y0: int = lat.ys[0]
	var y1: int = lat.ys[lat.ys.size() - 1]
	for r in range(1, map.rows - 1):
		for c in range(1, map.cols - 1):
			if r >= y0 and r <= y1 and c >= x0 and c <= x1:
				continue
			if map.get_tile(r, c) != Cfg.T_GRASS or _touches(map, r, c, Cfg.T_ROAD):
				continue
			var roll := rng.nextf()
			var house := _st("outskirt_house", OUTSKIRT_HOUSE)
			if roll < house:
				map.set_tile(r, c, Cfg.T_BRICK)
			elif roll < house + _st("outskirt_tree", OUTSKIRT_TREE):
				map.set_tile(r, c, Cfg.T_TREE)
