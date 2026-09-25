class_name Pathfinding
extends RefCounted

const SQRT2 := 1.4142135623730951
const NODE_BUDGET := 4000
# Соседи клетки в порядке старого двойного цикла dr/dc (-1..1, без 0,0).
const _DR := [-1, -1, -1, 0, 0, 1, 1, 1]
const _DC := [-1, 0, 1, -1, 1, -1, 0, 1]

static var _cells := 0
static var _g_score := PackedFloat64Array()
static var _came_from := PackedInt32Array()
static var _visit_gen := PackedInt32Array()
static var _closed := PackedByteArray()
static var _heap_items := PackedInt32Array()
static var _heap_keys := PackedFloat64Array()
static var _heap_size := 0
static var _generation := 0

static var stat_calls := 0
static var stat_expanded := 0

## Бюджет A* на один тик симуляции (в раскрытых узлах). Если несколько
## ботов решили перестроить путь в один и тот же тик, их поиски стакались
## в один кадр по 30–50 мс. Теперь, когда бюджет тика исчерпан, остальные
## боты едут по старому пути и перестраивают его в следующих тиках.
## Первый поиск в тике разрешён всегда. Всё детерминировано по номеру тика.
const TICK_NODE_BUDGET := 1200
static var _budget_tick := -1
static var _budget_used := 0

static func has_budget(tick: int) -> bool:
	if tick != _budget_tick:
		_budget_tick = tick
		_budget_used = 0
	return _budget_used < TICK_NODE_BUDGET

static func _ensure(size: int) -> void:
	if _cells >= size:
		return
	_cells = size
	_g_score.resize(size)
	_came_from.resize(size)
	_visit_gen.resize(size)
	_closed.resize(size)
	_heap_items.resize(size + 8)
	_heap_keys.resize(size + 8)

static func _heap_clear() -> void:
	_heap_size = 0

static func _heap_swap(a: int, b: int) -> void:
	var ti := _heap_items[a]
	_heap_items[a] = _heap_items[b]
	_heap_items[b] = ti
	var tk := _heap_keys[a]
	_heap_keys[a] = _heap_keys[b]
	_heap_keys[b] = tk

# Кучу крутим без вызова _heap_swap на каждом шаге: в GDScript вызов
# функции заметно дороже самих перестановок (результат тот же).
static func _heap_push(item: int, key: float) -> void:
	if _heap_size >= _heap_items.size():
		return
	var i := _heap_size
	_heap_size += 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _heap_keys[parent] <= key:
			break
		_heap_items[i] = _heap_items[parent]
		_heap_keys[i] = _heap_keys[parent]
		i = parent
	_heap_items[i] = item
	_heap_keys[i] = key

static func _heap_pop() -> int:
	var top := _heap_items[0]
	_heap_size -= 1
	if _heap_size > 0:
		var item := _heap_items[_heap_size]
		var key := _heap_keys[_heap_size]
		var n := _heap_size
		var i := 0
		while true:
			var l := 2 * i + 1
			if l >= n:
				break
			var r := l + 1
			var child := l
			if r < n and _heap_keys[r] < _heap_keys[l]:
				child = r
			if _heap_keys[child] >= key:
				break
			_heap_items[i] = _heap_items[child]
			_heap_keys[i] = _heap_keys[child]
			i = child
		_heap_items[i] = item
		_heap_keys[i] = key
	return top

static func find_path(map: GameMap, start_x: float, start_y: float,
		end_x: float, end_y: float) -> Array:
	var expanded_before := stat_expanded
	var result := _find_path(map, start_x, start_y, end_x, end_y)
	_budget_used += stat_expanded - expanded_before
	return result

static func _find_path(map: GameMap, start_x: float, start_y: float,
		end_x: float, end_y: float) -> Array:
	stat_calls += 1
	_ensure(map.cols * map.rows)
	var cols := map.cols
	var rows := map.rows
	var walk := map.passable
	var start_col := int(floor(start_x / Cfg.TILE))
	var start_row := int(floor(start_y / Cfg.TILE))
	var end_col := int(floor(end_x / Cfg.TILE))
	var end_row := int(floor(end_y / Cfg.TILE))

	if not map.in_bounds(start_row, start_col):
		return []

	if not map.is_drivable(end_row, end_col):
		var alt := _nearest_drivable(map, end_row, end_col, 6)
		if alt.x < 0:
			return []
		end_row = int(alt.x)
		end_col = int(alt.y)

	var start := start_row * cols + start_col
	var goal := end_row * cols + end_col
	if start == goal:
		return []

	_generation += 1
	var gen := _generation
	_heap_clear()
	_g_score[start] = 0.0
	_came_from[start] = -1
	_visit_gen[start] = gen
	_closed[start] = 0
	_heap_push(start, _heuristic(start_row, start_col, end_row, end_col))

	var expanded := 0
	var best_node := start
	var best_h := _heuristic(start_row, start_col, end_row, end_col)

	while _heap_size > 0:
		var current := _heap_pop()
		if _closed[current] == 1 and _visit_gen[current] == gen:
			continue
		_closed[current] = 1
		_visit_gen[current] = gen

		if current == goal:
			return _reconstruct(map, current, gen)
		expanded += 1
		stat_expanded += 1
		if expanded > NODE_BUDGET:
			break

		var cr := current / cols
		var cc := current % cols
		var h := _heuristic(cr, cc, end_row, end_col)
		if h < best_h:
			best_h = h
			best_node = current

		# Тот же обход 8 соседей в том же порядке, что и раньше, но по
		# готовой сетке проходимости map.passable и без вызовов функций на
		# каждого соседа — A* был главным источником фризов симуляции.
		var g_cur := _g_score[current]
		for k in 8:
			var dr: int = _DR[k]
			var dc: int = _DC[k]
			var nr := cr + dr
			var nc := cc + dc
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			var next := nr * cols + nc
			if walk[next] == 0:
				continue
			var diag := dr != 0 and dc != 0
			if diag and (walk[next - dc] == 0 or walk[current + dc] == 0):
				continue
			var seen := _visit_gen[next] == gen
			if seen and _closed[next] == 1:
				continue
			var tentative := g_cur + (SQRT2 if diag else 1.0)
			if seen and tentative >= _g_score[next]:
				continue
			_visit_gen[next] = gen
			_closed[next] = 0
			_g_score[next] = tentative
			_came_from[next] = current
			var hr := float(absi(nr - end_row))
			var hc := float(absi(nc - end_col))
			_heap_push(next, tentative + ((hr + hc) + (SQRT2 - 2.0) * minf(hr, hc)))

	if best_node != start:
		return _reconstruct(map, best_node, gen)
	return []

static func _heuristic(r1: int, c1: int, r2: int, c2: int) -> float:
	var dr := float(absi(r1 - r2))
	var dc := float(absi(c1 - c2))
	return (dr + dc) + (SQRT2 - 2.0) * minf(dr, dc)

static func _reconstruct(map: GameMap, node: int, gen: int) -> Array:
	var raw := []
	var cur := node
	var guard := 0
	while cur != -1 and guard < _cells:
		guard += 1
		raw.append(cur)
		if _visit_gen[cur] != gen:
			break
		cur = _came_from[cur]
	raw.reverse()
	if raw.size() > 0:
		raw.remove_at(0)
	return _smooth(map, raw)

static func _smooth(map: GameMap, cells: Array) -> Array:
	var cols := map.cols
	var points := []
	for cell in cells:
		points.append(Vector2(
			float(cell % cols) * Cfg.TILE + Cfg.TILE * 0.5,
			float(cell / cols) * Cfg.TILE + Cfg.TILE * 0.5))
	if points.size() <= 2:
		return points

	var out := []
	var anchor := 0
	while anchor < points.size() - 1:
		var furthest := anchor + 1
		var j := points.size() - 1
		while j > anchor + 1:
			if map.has_drivable_segment(points[anchor].x, points[anchor].y, points[j].x, points[j].y):
				furthest = j
				break
			j -= 1
		out.append(points[furthest])
		anchor = furthest
	return out

static func _nearest_drivable(map: GameMap, row: int, col: int, radius: int) -> Vector2:
	for rad in range(1, radius + 1):
		for dr in range(-rad, rad + 1):
			for dc in range(-rad, rad + 1):
				if maxi(absi(dr), absi(dc)) != rad:
					continue
				if map.is_drivable(row + dr, col + dc):
					return Vector2(row + dr, col + dc)
	return Vector2(-1, -1)
