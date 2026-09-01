# ============================================================================
# game_map.gd — тайловая карта.
#
# Карта хранится в PackedByteArray, генерация детерминирована от seed.
# Отдельный проход ensure_connectivity() гарантирует связность: иначе
# генератор может запереть область стенами, и бот с A* встанет на месте.
# ============================================================================
class_name GameMap
extends RefCounted

var cols: int
var rows: int
var tiles: PackedByteArray
## Накопленный урон постройки, 0..255. Отдельным массивом, чтобы не трогать
## формат тайлов: тип тайла говорит «что стоит», damage — «насколько разбито».
var damage: PackedByteArray
## Растёт при любом изменении тайла — по нему рендер понимает,
## что кэш миникарты пора перерисовать.
var version := 0

## Счётчики для профилировки (используются дымовым тестом).
static var stat_rect_calls := 0
static var stat_los_calls := 0

func _init(cols_: int = Cfg.COLS, rows_: int = Cfg.ROWS) -> void:
	cols = cols_
	rows = rows_
	tiles = PackedByteArray()
	tiles.resize(cols * rows)
	damage = PackedByteArray()
	damage.resize(cols * rows)

## Тайлы, сквозь которые не проехать.
static func is_solid_tile(tile: int) -> bool:
	return tile == Cfg.T_WALL or tile == Cfg.T_BRICK

## Тайлы, по которым бот согласен строить маршрут.
##
## Асфальт, мост и газон здесь обязаны быть. Их отсутствие обошлось дорого:
## страховка связности считала всю дорожную сеть препятствием и прорубала
## сквозь неё коридоры, стирая улицы и разрезая мосты, а боты не строили
## по дорогам маршрутов вовсе — на городской карте, где асфальта четверть.
static func is_drivable_tile(tile: int) -> bool:
	return tile == Cfg.T_EMPTY or tile == Cfg.T_TREE or tile == Cfg.T_BASE_P \
		or tile == Cfg.T_BASE_E or tile == Cfg.T_SAND \
		or tile == Cfg.T_ROAD or tile == Cfg.T_BRIDGE or tile == Cfg.T_GRASS \
		or tile == Cfg.T_DUNE or tile == Cfg.T_QUICKSAND

var width: float:
	get: return float(cols * Cfg.TILE)

var height: float:
	get: return float(rows * Cfg.TILE)

func in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < rows and col >= 0 and col < cols

func get_tile(row: int, col: int) -> int:
	if not in_bounds(row, col):
		return Cfg.T_WALL  # за краем — стена
	return tiles[row * cols + col]

func set_tile(row: int, col: int, value: int) -> void:
	if not in_bounds(row, col):
		return
	var i := row * cols + col
	if tiles[i] == value:
		return
	tiles[i] = value
	# Новый тайл — целый: иначе на месте разрушенного здания следующее
	# сразу стояло бы с трещинами.
	damage[i] = 0
	version += 1
	# Журнал ведётся здесь, а не у вызывающих: тайлы меняют и снаряды,
	# и гусеницы по деревьям, и потоп в «Царе горы». Замер показал, что
	# при записи по местам вызова карта клиента расходилась с хостом —
	# ровно на те изменения, которые проходили мимо.
	_log_tile(row, col)

func fill(value: int) -> void:
	tiles.fill(value)
	damage.fill(0)
	version += 1

func col_at(x: float) -> int:
	return int(floor(x / Cfg.TILE))

func row_at(y: float) -> int:
	return int(floor(y / Cfg.TILE))

func tile_at_pixel(x: float, y: float) -> int:
	return get_tile(row_at(y), col_at(x))

func is_water_at(x: float, y: float) -> bool:
	return tile_at_pixel(x, y) == Cfg.T_WATER

## Проверяет прямоугольник (центр x,y) на столкновение со стенами.
## Отступ в 2 px по каждой стороне — чтобы танк не цеплялся за углы.
func is_blocked_rect(x: float, y: float, w: float, h: float) -> bool:
	stat_rect_calls += 1
	var hw := w * 0.5 - 2.0
	var hh := h * 0.5 - 2.0
	var c0 := int(floor((x - hw) / Cfg.TILE))
	var c1 := int(floor((x + hw) / Cfg.TILE))
	var r0 := int(floor((y - hh) / Cfg.TILE))
	var r1 := int(floor((y + hh) / Cfg.TILE))
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if not in_bounds(r, c):
				return true
			if is_solid_tile(tiles[r * cols + c]):
				return true
	return false

## Доля разрушенности постройки, 0..1 — по ней рисуются трещины.
func damage_ratio(row: int, col: int) -> float:
	if not in_bounds(row, col):
		return 0.0
	var mat := Materials.at(row, col)
	return clampf(float(damage[row * cols + col]) / float(mat["hp"]), 0.0, 1.0)

## Наносит урон постройке. Возвращает true, если она разрушена.
## Урон не увеличивает version: перерисовывать кэши (миникарту, затенение)
## нужно только когда тайл действительно исчез.
## Журнал изменений тайлов для сети. Включается только у хоста и только
## на время партии: генерация уровня пишет в карту тысячи раз, и логировать
## её было бы бессмысленно — клиент собирает ту же карту сам по seed.
var net_log_on := false
var net_log: Array = []

func _log_tile(row: int, col: int) -> void:
	if not net_log_on:
		return
	var i := row * cols + col
	net_log.append([i, tiles[i], damage[i]])

## Отпечаток карты. Хост шлёт его клиентам, те сверяют со своим: надёжный
## пакет с изменениями может не дойти при переподключении, и тогда у клиента
## останется стена там, где её давно снесли. Дешевле раз в пять секунд
## сверить одно число, чем гонять карту целиком.
func checksum() -> int:
	var h := 5381
	for i in tiles.size():
		h = ((h * 33) ^ tiles[i]) & 0x7FFFFFFF
	return h

## Полный слепок карты — на случай, если отпечатки разошлись.
## Тайлов одиннадцать видов, урон не больше 255, поэтому байта хватает
## на каждое поле: 16 КБ вместо 64 КБ при передаче целыми числами.
func snapshot_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(tiles.size() * 2)
	for i in tiles.size():
		out[i * 2] = tiles[i] & 0xFF
		out[i * 2 + 1] = damage[i] & 0xFF
	return out

func apply_snapshot_bytes(data: PackedByteArray) -> void:
	if data.size() != tiles.size() * 2:
		return
	for i in tiles.size():
		tiles[i] = data[i * 2]
		damage[i] = data[i * 2 + 1]
	version += 1

## Забирает накопленные изменения и очищает журнал.
func take_net_log() -> Array:
	if net_log.is_empty():
		return []
	var out := net_log
	net_log = []
	return out

func apply_damage(row: int, col: int, amount: float, source: String) -> bool:
	if not in_bounds(row, col):
		return false
	var i := row * cols + col
	if not is_solid_tile(tiles[i]) or tiles[i] == Cfg.T_WALL:
		return false
	var mat := Materials.at(row, col)
	var dealt := amount * Materials.resist(mat, source)
	var total: float = float(damage[i]) + dealt
	if total >= float(mat["hp"]):
		# set_tile сам запишет изменение в журнал.
		set_tile(row, col, Cfg.T_EMPTY)
		return true
	# 255 хватает: самая прочная постройка — 160 единиц.
	damage[i] = int(minf(255.0, total))
	_log_tile(row, col)
	return false

func is_drivable(row: int, col: int) -> bool:
	return in_bounds(row, col) and is_drivable_tile(tiles[row * cols + col])

## Проверяет, что прямое движение из точки в точку не пересекает
## непроезжаемые тайлы И не «срезает» угол стены (supercover-DDA).
## Танк прямоугольный, в угол не влезает, поэтому маршрут должен этого избегать.
func has_drivable_segment(x1: float, y1: float, x2: float, y2: float) -> bool:
	var x0 := x1 / Cfg.TILE
	var y0 := y1 / Cfg.TILE
	var x1t := x2 / Cfg.TILE
	var y1t := y2 / Cfg.TILE

	var cx := int(floor(x0))
	var cy := int(floor(y0))
	var dx := x1t - x0
	var dy := y1t - y0
	var step_x := 1 if dx > 0.0 else -1
	var step_y := 1 if dy > 0.0 else -1
	var t_delta_x := absf(1.0 / dx) if dx != 0.0 else INF
	var t_delta_y := absf(1.0 / dy) if dy != 0.0 else INF
	var t_max_x := absf(((cx + 1 if dx > 0.0 else cx) - x0) / dx) if dx != 0.0 else INF
	var t_max_y := absf(((cy + 1 if dy > 0.0 else cy) - y0) / dy) if dy != 0.0 else INF
	var ex := int(floor(x1t))
	var ey := int(floor(y1t))

	var guard := 0
	var max_steps := cols + rows + 4
	while guard < max_steps:
		guard += 1
		if not is_drivable(cy, cx):
			return false
		if cx == ex and cy == ey:
			return true
		# Пересечение двух границ одновременно — линия идёт через вершину сетки.
		if absf(t_max_x - t_max_y) < 1e-9:
			t_max_x += t_delta_x
			t_max_y += t_delta_y
			if not is_drivable(cy + step_y, cx + step_x):
				return false
			cx += step_x
			cy += step_y
		elif t_max_x < t_max_y:
			t_max_x += t_delta_x
			cx += step_x
		else:
			t_max_y += t_delta_y
			cy += step_y
		if t_max_x > 1.0 and t_max_y > 1.0:
			return true
	return true

## Есть ли прямая видимость между двумя точками (DDA по сетке).
## Стены и кирпич перекрывают обзор, деревья и вода — нет.
func has_line_of_sight(x1: float, y1: float, x2: float, y2: float) -> bool:
	stat_los_calls += 1
	var col := int(floor(x1 / Cfg.TILE))
	var row := int(floor(y1 / Cfg.TILE))
	var end_col := int(floor(x2 / Cfg.TILE))
	var end_row := int(floor(y2 / Cfg.TILE))

	var dx := x2 - x1
	var dy := y2 - y1
	var step_c := 1 if dx > 0.0 else -1
	var step_r := 1 if dy > 0.0 else -1
	var t_delta_c := absf(float(Cfg.TILE) / dx) if dx != 0.0 else INF
	var t_delta_r := absf(float(Cfg.TILE) / dy) if dy != 0.0 else INF
	var t_max_c := absf((((col + 1) * Cfg.TILE if dx > 0.0 else col * Cfg.TILE) - x1) / dx) if dx != 0.0 else INF
	var t_max_r := absf((((row + 1) * Cfg.TILE if dy > 0.0 else row * Cfg.TILE) - y1) / dy) if dy != 0.0 else INF

	var guard := 0
	var max_steps := cols + rows + 4
	while guard < max_steps:
		guard += 1
		if not in_bounds(row, col):
			return false
		if is_solid_tile(tiles[row * cols + col]):
			return false
		if row == end_row and col == end_col:
			return true
		if t_max_c < t_max_r:
			t_max_c += t_delta_c
			col += step_c
		else:
			t_max_r += t_delta_r
			row += step_r
		if t_max_c > 1.0 and t_max_r > 1.0:
			return true
	return true

## Ищет свободную точку в прямоугольной зоне (в тайлах).
## Зона с флагом edge ограничивает поиск периметром прямоугольника —
## в «Обороне» враги выходят с краёв карты.
## Возвращает Vector2 в пикселях либо Vector2.INF, если не нашлось.
func find_free_spot(rng: Rng, area: Dictionary, w: float, h: float,
		tries: int = 80, avoid_water: bool = true) -> Vector2:
	var r0 := int(ceil(float(area["r0"])))
	var r1 := int(floor(float(area["r1"])))
	var c0 := int(ceil(float(area["c0"])))
	var c1 := int(floor(float(area["c1"])))
	var edge: bool = bool(area.get("edge", false))

	for i in tries:
		var c := 0.0
		var r := 0.0
		if edge:
			# Периметр: случайная из четырёх сторон.
			var side := int(rng.nextf() * 4.0)
			if side == 0:
				r = r0
				c = c0 + rng.nextf() * float(c1 - c0)
			elif side == 1:
				r = r1
				c = c0 + rng.nextf() * float(c1 - c0)
			elif side == 2:
				c = c0
				r = r0 + rng.nextf() * float(r1 - r0)
			else:
				c = c1
				r = r0 + rng.nextf() * float(r1 - r0)
		else:
			c = c0 + rng.nextf() * float(c1 - c0)
			r = r0 + rng.nextf() * float(r1 - r0)
		var x := c * Cfg.TILE + Cfg.TILE * 0.5
		var y := r * Cfg.TILE + Cfg.TILE * 0.5
		if is_blocked_rect(x, y, w, h):
			continue
		if avoid_water and is_water_at(x, y):
			continue
		return Vector2(x, y)

	# Аварийный обход: линейный поиск по зоне.
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if edge and r != r0 and r != r1 and c != c0 and c != c1:
				continue
			var x := c * Cfg.TILE + Cfg.TILE * 0.5
			var y := r * Cfg.TILE + Cfg.TILE * 0.5
			if is_blocked_rect(x, y, w, h):
				continue
			if avoid_water and is_water_at(x, y):
				continue
			return Vector2(x, y)
	return Vector2.INF

## Разметка связных проезжаемых областей. Возвращает массив массивов индексов.
func label_regions() -> Array:
	var labels := PackedInt32Array()
	labels.resize(cols * rows)
	labels.fill(-1)
	var regions := []
	var queue := PackedInt32Array()
	queue.resize(cols * rows)
	for r in rows:
		for c in cols:
			var start := r * cols + c
			if labels[start] != -1 or not is_drivable_tile(tiles[start]):
				continue
			var id := regions.size()
			var head := 0
			var tail := 0
			queue[tail] = start
			tail += 1
			labels[start] = id
			var cells := PackedInt32Array()
			while head < tail:
				var cur := queue[head]
				head += 1
				cells.append(cur)
				var cr := cur / cols
				var cc := cur % cols
				for k in 4:
					var nr := cr + (-1 if k == 0 else (1 if k == 1 else 0))
					var nc := cc + (-1 if k == 2 else (1 if k == 3 else 0))
					if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
						continue
					var ni := nr * cols + nc
					if labels[ni] != -1 or not is_drivable_tile(tiles[ni]):
						continue
					labels[ni] = id
					queue[tail] = ni
					tail += 1
			regions.append(cells)
	return regions

## Гарантирует, что вся проезжаемая площадь связна: прорубает коридоры
## от каждой изолированной области к самой большой.
func ensure_connectivity() -> int:
	var regions := label_regions()
	if regions.size() <= 1:
		return 0

	var biggest := 0
	for i in range(1, regions.size()):
		if regions[i].size() > regions[biggest].size():
			biggest = i
	var main_cells: PackedInt32Array = regions[biggest]
	var carved := 0

	for i in regions.size():
		if i == biggest:
			continue
		var cells: PackedInt32Array = regions[i]
		# Берём центр области и ближайшую к нему клетку главной области.
		var from: int = cells[cells.size() / 2]
		var fr := from / cols
		var fc := from % cols
		var best: int = main_cells[0]
		var best_d := 1 << 30
		for cell in main_cells:
			var d: int = absi(cell / cols - fr) + absi(cell % cols - fc)
			if d < best_d:
				best_d = d
				best = cell
		carved += _carve_corridor(fr, fc, best / cols, best % cols)
	return carved

## Прорубает Г-образный коридор, не трогая внешнюю рамку карты.
func _carve_corridor(r0: int, c0: int, r1: int, c1: int) -> int:
	var carved := 0
	var step_c := 1 if c1 > c0 else -1
	var c := c0
	while c != c1:
		carved += _carve_put(r0, c)
		c += step_c
	var step_r := 1 if r1 > r0 else -1
	var r := r0
	while r != r1:
		carved += _carve_put(r, c1)
		r += step_r
	carved += _carve_put(r1, c1)
	return carved

func _carve_put(r: int, c: int) -> int:
	if r <= 0 or r >= rows - 1 or c <= 0 or c >= cols - 1:
		return 0
	var i := r * cols + c
	if is_drivable_tile(tiles[i]):
		return 0
	# Воду коридор не трогает. Раньше он клал через неё мост, и замер
	# показал по 13–18 переправ на карту вместо четырёх разрешённых:
	# страховка связности прорубала реку везде, где ей было удобно.
	# Берега соединяют мосты генератора, и только они.
	if tiles[i] == Cfg.T_WATER:
		return 0
	tiles[i] = Cfg.T_EMPTY
	version += 1
	return 1
