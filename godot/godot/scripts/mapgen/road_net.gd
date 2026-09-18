# ============================================================================
# road_net.gd — покраска дорожной сети по плану и её починка.
#
# Второй этап конвейера: берёт план (map_plan.gd) и кладёт асфальт. Здесь же
# живёт починка сетки — сшивание кусков, отрезанных рекой и застройкой.
#
# Порядок покраски важен: сначала обычные улицы, потом магистрали поверх них.
# Магистраль, перерезанная улицей той же ширины, перестаёт читаться как
# главная дорога, а перекрёсток превращается в кашу.
# ============================================================================
class_name RoadNet
extends RefCounted

## Мелкие пятачки асфальта сшивать незачем: от них не зависит проезд.
const MIN_PATCH := 12

static func paint(map: GameMap, plan: Dictionary) -> void:
	# Улицы, потом магистрали: старший ранг кладётся последним.
	for rank in [MapPlan.RANK_STREET, MapPlan.RANK_ARTERIAL]:
		for st in plan["v"]:
			if int(st["rank"]) == rank:
				_paint_line(map, st, true)
		for st in plan["h"]:
			if int(st["rank"]) == rank:
				_paint_line(map, st, false)

	for circle in plan["circles"]:
		_paint_circle(map, circle)

## Перемычки между улицами. Красятся ОТДЕЛЬНО и после застройки кварталов:
## перемычка проходит по середине квартала, а Districts.paint заливает квартал
## целиком — если положить её раньше, застройка её же и сотрёт. Замер поймал
## это сразу: карты с перемычками и без совпали побайтово.
static func paint_links(map: GameMap, plan: Dictionary) -> void:
	for link in plan.get("links", []):
		for r in range(maxi(1, int(link["r0"])), mini(map.rows - 2, int(link["r1"])) + 1):
			for c in range(maxi(1, int(link["c0"])), mini(map.cols - 2, int(link["c1"])) + 1):
				# Воду перемычка не пересекает: для этого есть мосты.
				if map.get_tile(r, c) == Cfg.T_WATER:
					continue
				map.set_tile(r, c, Cfg.T_ROAD)

static func _paint_line(map: GameMap, st: Dictionary, vertical: bool) -> void:
	var w: int = int(st["w"])
	var pos: int = int(st["pos"])
	for d in w:
		var k := pos + d
		if vertical:
			if k <= 0 or k >= map.cols - 1:
				continue
			for r in range(1, map.rows - 1):
				map.set_tile(r, k, Cfg.T_ROAD)
		else:
			if k <= 0 or k >= map.rows - 1:
				continue
			for c in range(1, map.cols - 1):
				map.set_tile(k, c, Cfg.T_ROAD)

## Кольцевая развязка: асфальтовое кольцо с газоном внутри.
##
## Остров делается газоном, а не стеной: кольцо должно быть ориентиром
## и укрытием, а не ловушкой, в которой танк застревает под обстрелом.
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
	# Пара деревьев на острове — иначе он читается как пустой газон.
	map.set_tile(cr, cc, Cfg.T_TREE)
	map.set_tile(cr - 1, cc + 1, Cfg.T_TREE)

# =============================================================== починка
## Сшивает разорванные куски асфальта.
##
## Улицы рисуются сплошными линиями и обязаны пересекаться, но поверх них
## ложатся река, берега и застройка, и часть сетки отрезается. Замер
## связности показывал 15–45% асфальта в главной сети, пока этого этапа
## не было.
##
## Два прохода: после первого куски сливаются, и то, что не дотянулось
## напрямую, находит дорогу через уже сшитого соседа.
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
			# Сначала главная сеть, потом остальные по убыванию. Кусок на
			# дальнем берегу до главной сети посуху не дотянется, зато
			# соединится с соседями по своему берегу — а берега свяжут мосты.
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

## Г-образный коридор. Пробуются оба порядка обхода; воду коридор не
## пересекает — сшивать берега это работа мостов, а не починки.
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
	# Мост не перекрашивается в асфальт. Замер поймал последствия: коридор
	# проходил вдоль моста, резал его надвое и оставлял посреди реки полосу
	# дороги без перил — вместо трёх переправ карта показывала шесть,
	# из которых три были обломками в один-два тайла.
	if t == Cfg.T_WALL or t == Cfg.T_WATER or t == Cfg.T_BRIDGE:
		return
	map.set_tile(r, c, Cfg.T_ROAD)
