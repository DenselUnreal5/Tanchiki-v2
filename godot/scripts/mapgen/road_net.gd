class_name RoadNet
extends RefCounted

const MIN_PATCH := 12

static func paint(map: GameMap, plan: Dictionary) -> void:
	for rank in [MapPlan.RANK_STREET, MapPlan.RANK_ARTERIAL]:
		for st in plan["v"]:
			if int(st["rank"]) == rank:
				_paint_line(map, st, true)
		for st in plan["h"]:
			if int(st["rank"]) == rank:
				_paint_line(map, st, false)

	for circle in plan["circles"]:
		_paint_circle(map, circle)

## Districts.paint() красит весь прямоугольник квартала поверх — если волна
## улицы (см. MapPlan.wave_offset) заходит в соседний квартал, район
## закрашивает её. Вызывается после Districts.paint(), перекрашивает те же
## улицы и круги поверх — гарантия ширины/формы держится не вероятностно,
## а конструктивно. Заодно чинит то, что круги красятся в paint() до
## Districts.paint() и уже сегодня могут быть откушены соседним кварталом.
static func restripe_streets(map: GameMap, plan: Dictionary) -> void:
	paint(map, plan)

static func paint_links(map: GameMap, plan: Dictionary) -> void:
	for link in plan.get("links", []):
		for r in range(maxi(1, int(link["r0"])), mini(map.rows - 2, int(link["r1"])) + 1):
			for c in range(maxi(1, int(link["c0"])), mini(map.cols - 2, int(link["c1"])) + 1):
				if map.get_tile(r, c) == Cfg.T_WATER:
					continue
				map.set_tile(r, c, Cfg.T_ROAD)

static func _paint_line(map: GameMap, st: Dictionary, vertical: bool) -> void:
	var w: int = int(st["w"])
	var pos: int = int(st["pos"])
	if vertical:
		for r in range(1, map.rows - 1):
			var off := MapPlan.wave_offset(st, r)
			for d in w:
				var k := pos + off + d
				if k <= 0 or k >= map.cols - 1:
					continue
				map.set_tile(r, k, Cfg.T_ROAD)
	else:
		for c in range(1, map.cols - 1):
			var off := MapPlan.wave_offset(st, c)
			for d in w:
				var k := pos + off + d
				if k <= 0 or k >= map.rows - 1:
					continue
				map.set_tile(k, c, Cfg.T_ROAD)

static func _paint_circle(map: GameMap, circle: Dictionary) -> void:
	var cr: int = int(circle["r"])
	var cc: int = int(circle["c"])
	var rad: int = int(circle["radius"])
	for dr in range(-rad, rad + 1):
		for dc in range(-rad, rad + 1):
			var r := cr + dr
			var c := cc + dc
			if r <= 0 or c <= 0 or r >= map.rows - 1 or c >= map.cols - 1:
				continue
			var d := sqrt(float(dr * dr + dc * dc))
			if d > float(rad):
				continue
			map.set_tile(r, c, Cfg.T_ROAD if d > float(rad) - 3.0 else Cfg.T_GRASS)
	map.set_tile(cr, cc, Cfg.T_TREE)
	map.set_tile(cr - 1, cc + 1, Cfg.T_TREE)

static func repair(map: GameMap) -> void:
	for attempt in 2:
		var groups := _groups(map)
		if groups.size() <= 1:
			return
		groups.sort_custom(func(a, b): return a.size() > b.size())

		var joined := false
		for i in range(1, groups.size()):
			if groups[i].size() < MIN_PATCH:
				continue
			var from: Vector2i = _center_of(map, groups[i])
			for j in groups.size():
				if j == i:
					continue
				if _corridor(map, from, _center_of(map, groups[j])):
					joined = true
					break
		if not joined:
			return

static func _groups(map: GameMap) -> Array:
	var cols := map.cols
	var seen := {}
	var out := []
	for r in range(1, map.rows - 1):
		for c in range(1, cols - 1):
			var i := r * cols + c
			if seen.has(i) or not is_paved(map, r, c):
				continue
			var cells := PackedInt32Array()
			var stack := [i]
			seen[i] = true
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				cells.append(cur)
				var cr := cur / cols
				var cc := cur % cols
				for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var nr: int = cr + int(d[0])
					var nc: int = cc + int(d[1])
					if not is_paved(map, nr, nc):
						continue
					var ni := nr * cols + nc
					if seen.has(ni):
						continue
					seen[ni] = true
					stack.append(ni)
			out.append(cells)
	return out

static func is_paved(map: GameMap, r: int, c: int) -> bool:
	if r < 1 or c < 1 or r >= map.rows - 1 or c >= map.cols - 1:
		return false
	var t := map.get_tile(r, c)
	return t == Cfg.T_ROAD or t == Cfg.T_BRIDGE

static func _center_of(map: GameMap, cells: PackedInt32Array) -> Vector2i:
	var i: int = cells[cells.size() / 2]
	return Vector2i(i / map.cols, i % map.cols)

static func _corridor(map: GameMap, from: Vector2i, to: Vector2i) -> bool:
	for row_first in [true, false]:
		var path := _path(from, to, row_first)
		var dry := true
		for p in path:
			if map.get_tile(p.x, p.y) == Cfg.T_WATER:
				dry = false
				break
		if not dry:
			continue
		for p in path:
			_pave(map, p.x, p.y)
		return true
	return false

static func _path(from: Vector2i, to: Vector2i, row_first: bool) -> Array:
	var out := []
	if row_first:
		var c := from.y
		while c != to.y:
			out.append(Vector2i(from.x, c))
			c += 1 if to.y > c else -1
		var r := from.x
		while r != to.x:
			out.append(Vector2i(r, to.y))
			r += 1 if to.x > r else -1
	else:
		var r2 := from.x
		while r2 != to.x:
			out.append(Vector2i(r2, from.y))
			r2 += 1 if to.x > r2 else -1
		var c2 := from.y
		while c2 != to.y:
			out.append(Vector2i(to.x, c2))
			c2 += 1 if to.y > c2 else -1
	out.append(to)
	return out

static func _pave(map: GameMap, r: int, c: int) -> void:
	if r <= 0 or c <= 0 or r >= map.rows - 1 or c >= map.cols - 1:
		return
	var t := map.get_tile(r, c)
	if t == Cfg.T_WALL or t == Cfg.T_WATER or t == Cfg.T_BRIDGE:
		return
	map.set_tile(r, c, Cfg.T_ROAD)
