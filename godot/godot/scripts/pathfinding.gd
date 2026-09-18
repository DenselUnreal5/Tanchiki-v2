# ============================================================================
# pathfinding.gd — A* по тайловой сетке.
#
# Буферы переиспользуются между вызовами: до 22 ботов ищут путь каждые ~60
# тиков, и аллокация массивов на каждый вызов заметно нагружает сборщик.
# Есть жёсткий лимит раскрытых узлов, чтобы одиночный безнадёжный запрос
# не съедал кадр.
# ============================================================================
class_name Pathfinding
extends RefCounted

const SQRT2 := 1.4142135623730951
## Максимум раскрытых узлов на один запрос.
const NODE_BUDGET := 4000

static var _cells := 0
static var _g_score := PackedFloat64Array()
static var _came_from := PackedInt32Array()
static var _visit_gen := PackedInt32Array()
static var _closed := PackedByteArray()
static var _heap_items := PackedInt32Array()
static var _heap_keys := PackedFloat64Array()
static var _heap_size := 0
static var _generation := 0

## Счётчики для профилировки (используются дымовым тестом).
static var stat_calls := 0
static var stat_expanded := 0

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

# ---------------------------------------------------------------- куча
static func _heap_clear() -> void:
	_heap_size = 0

static func _heap_swap(a: int, b: int) -> void:
	var ti := _heap_items[a]
	_heap_items[a] = _heap_items[b]
	_heap_items[b] = ti
	var tk := _heap_keys[a]
	_heap_keys[a] = _heap_keys[b]
	_heap_keys[b] = tk

static func _heap_push(item: int, key: float) -> void:
	if _heap_size >= _heap_items.size():
		return
	var i := _heap_size
	_heap_size += 1
	_heap_items[i] = item
	_heap_keys[i] = key
	while i > 0:
		var parent := (i - 1) >> 1
		if _heap_keys[parent] <= _heap_keys[i]:
			break
		_heap_swap(i, parent)
		i = parent

static func _heap_pop() -> int:
	var top := _heap_items[0]
	_heap_size -= 1
	if _heap_size > 0:
		_heap_items[0] = _heap_items[_heap_size]
		_heap_keys[0] = _heap_keys[_heap_size]
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var smallest := i
			if l < _heap_size and _heap_keys[l] < _heap_keys[smallest]:
				smallest = l
			if r < _heap_size and _heap_keys[r] < _heap_keys[smallest]:
				smallest = r
			if smallest == i:
				break
			_heap_swap(i, smallest)
			i = smallest
	return top

# ---------------------------------------------------------------- поиск
## Ищет маршрут по проезжаемым тайлам.
## @return Array[Vector2] путевые точки в пикселях (без стартовой)
static func find_path(map: GameMap, start_x: float, start_y: float,
		end_x: float, end_y: float) -> Array:
	stat_calls += 1
	_ensure(map.cols * map.rows)
	var cols := map.cols
	var start_col := int(floor(start_x / Cfg.TILE))
	var start_row := int(floor(start_y / Cfg.TILE))
	var end_col := int(floor(end_x / Cfg.TILE))
	var end_row := int(floor(end_y / Cfg.TILE))

	if not map.in_bounds(start_row, start_col):
		return []

	# Если цель в стене или воде — берём ближайший проезжаемый тайл рядом.
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

		for dr in range(-1, 2):
			for dc in range(-1, 2):
				if dr == 0 and dc == 0:
					continue
				var nr := cr + dr
				var nc := cc + dc
				if not map.is_drivable(nr, nc):
					continue
				# По диагонали нельзя «срезать» угол между двумя стенами.
				if dr != 0 and dc != 0:
					if not map.is_drivable(cr + dr, cc) or not map.is_drivable(cr, cc + dc):
						continue
				var next := nr * cols + nc
				if _visit_gen[next] == gen and _closed[next] == 1:
					continue
				var step := SQRT2 if (dr != 0 and dc != 0) else 1.0
				var tentative := _g_score[current] + step
				var seen := _visit_gen[next] == gen
				if seen and tentative >= _g_score[next]:
					continue
				_visit_gen[next] = gen
				_closed[next] = 0
				_g_score[next] = tentative
				_came_from[next] = current
				_heap_push(next, tentative + _heuristic(nr, nc, end_row, end_col))

	# Полного пути нет — идём хотя бы в сторону цели.
	if best_node != start:
		return _reconstruct(map, best_node, gen)
	return []

static func _heuristic(r1: int, c1: int, r2: int, c2: int) -> float:
	var dr := float(absi(r1 - r2))
	var dc := float(absi(c1 - c2))
	# Восьминаправленная (октильная) метрика — согласована с ценой шага.
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
	# Первый элемент — стартовый тайл, он не нужен.
	if raw.size() > 0:
		raw.remove_at(0)
	return _smooth(map, raw)

## Убирает лишние точки: если из точки A видно точку C по чистой прямой
## (без прорезания углов), промежуточная B не нужна.
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

## Поиск ближайшего проезжаемого тайла в радиусе. Возвращает Vector2(row, col)
## или Vector2(-1, -1).
static func _nearest_drivable(map: GameMap, row: int, col: int, radius: int) -> Vector2:
	for rad in range(1, radius + 1):
		for dr in range(-rad, rad + 1):
			for dc in range(-rad, rad + 1):
				if maxi(absi(dr), absi(dc)) != rad:
					continue
				if map.is_drivable(row + dr, col + dc):
					return Vector2(row + dr, col + dc)
	return Vector2(-1, -1)
