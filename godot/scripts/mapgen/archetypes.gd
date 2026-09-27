class_name Archetypes
extends RefCounted

## Генератор архитектурных стилей и макро-топологий карт.
## Преобразует базовую сетку в уникальные тактические арены:
## цитадели, лабиринты, кольцевые развязки, промышленные Ж/Д узлы, каньоны и площади.

const POOL := ["avenues", "plaza", "river", "fortress", "radial", "labyrinths", "industrial", "canyon"]

static func apply(map: GameMap, rng: Rng, arch: String, cols: int, rows: int,
		mode: String, loc: Dictionary) -> void:
	match arch:
		"fortress":
			_apply_fortress(map, rng, cols, rows, mode, loc)
		"labyrinths":
			_apply_labyrinths(map, rng, cols, rows, mode, loc)
		"industrial":
			_apply_industrial(map, rng, cols, rows, mode, loc)
		"canyon":
			_apply_canyon(map, rng, cols, rows, mode, loc)
		"radial":
			_apply_radial(map, rng, cols, rows, mode, loc)
		"plaza":
			_apply_plaza(map, rng, cols, rows, mode, loc)
		"avenues":
			_apply_avenues(map, rng, cols, rows, mode, loc)
		_:
			pass

## -----------------------------------------------------------------------
## 1. ЦИТАДЕЛЬ (fortress): Мощный центральный форт со рвом, бастионами и мостами
## -----------------------------------------------------------------------
static func _apply_fortress(map: GameMap, rng: Rng, cols: int, rows: int,
		mode: String, loc: Dictionary) -> void:
	var cr := rows / 2
	var cc := cols / 2

	# Внешние угловые форпосты в четырёх секторах карты
	var corner_offsets: Array[Vector2i] = [
		Vector2i(6, 6),
		Vector2i(6, cols - 7),
		Vector2i(rows - 7, 6),
		Vector2i(rows - 7, cols - 7)
	]
	for cp: Vector2i in corner_offsets:
		if not _is_protected(cp.x, cp.y, mode, rows, cols):
			_fill_rect(map, cp.x - 2, cp.x + 2, cp.y - 2, cp.y + 2, Cfg.T_WALL)
			map.set_tile(cp.x, cp.y, Cfg.T_ROAD)
			# Амбразуры
			map.set_tile(cp.x - 2, cp.y, Cfg.T_ROAD)
			map.set_tile(cp.x + 2, cp.y, Cfg.T_ROAD)

	# Центральная Цитадель
	var fw := mini(22, cols - 16)
	var fh := mini(18, rows - 14)
	if fw < 12 or fh < 10:
		return

	var r0 := cr - fh / 2
	var r1 := cr + fh / 2
	var c0 := cc - fw / 2
	var c1 := cc + fw / 2

	# 1. Защитный ров с водой вокруг крепости
	for r in range(r0 - 2, r1 + 3):
		for c in range(c0 - 2, c1 + 3):
			if r >= 2 and r < rows - 2 and c >= 2 and c < cols - 2:
				if not _is_protected(r, c, mode, rows, cols):
					map.set_tile(r, c, Cfg.T_WATER)

	# 2. Внутренний плац крепости (асфальт/мостовая)
	_fill_rect(map, r0, r1, c0, c1, Cfg.T_ROAD)

	# 3. Внешние крепостные стены (периметр)
	for c in range(c0, c1 + 1):
		_safe_set(map, r0, c, Cfg.T_WALL, mode, rows, cols)
		_safe_set(map, r1, c, Cfg.T_WALL, mode, rows, cols)
	for r in range(r0, r1 + 1):
		_safe_set(map, r, c0, Cfg.T_WALL, mode, rows, cols)
		_safe_set(map, r, c1, Cfg.T_WALL, mode, rows, cols)

	# 4. Четыре массивных бастиона по углам крепости (3x3 бетон с кирпичным ядром)
	var bast_rows: Array[int] = [r0, r1 - 2]
	var bast_cols: Array[int] = [c0, c1 - 2]
	for br: int in bast_rows:
		for bc: int in bast_cols:
			_fill_rect(map, br, br + 2, bc, bc + 2, Cfg.T_WALL)
			map.set_tile(br + 1, bc + 1, Cfg.T_BRICK)

	# 5. Мосты-въезды через ров (Север, Юг, Запад, Восток)
	# Ширина въезда 2-3 тайла для свободного проезда танков
	_carve_gate_and_bridge(map, r0 - 2, r0 + 1, cc - 1, cc + 1, mode, rows, cols)
	_carve_gate_and_bridge(map, r1 - 1, r1 + 2, cc - 1, cc + 1, mode, rows, cols)
	_carve_gate_and_bridge(map, cr - 1, cr + 1, c0 - 2, c0 + 1, mode, rows, cols)
	_carve_gate_and_bridge(map, cr - 1, cr + 1, c1 - 1, c1 + 2, mode, rows, cols)

	# 6. Внутренние укрытия плаца
	if mode != "defense":
		# В центре — командный бункер
		_fill_rect(map, cr - 1, cr + 1, cc - 2, cc + 2, Cfg.T_BRICK)
		map.set_tile(cr, cc, Cfg.T_WALL)
		# Боковые огневые позиции
		map.set_tile(cr - 2, cc - 4, Cfg.T_WALL)
		map.set_tile(cr + 2, cc - 4, Cfg.T_WALL)
		map.set_tile(cr - 2, cc + 4, Cfg.T_WALL)
		map.set_tile(cr + 2, cc + 4, Cfg.T_WALL)

## -----------------------------------------------------------------------
## 2. ЛАБИРИНТ (labyrinths): Плотные разрушаемые кирпичные коридоры и залы
## -----------------------------------------------------------------------
static func _apply_labyrinths(map: GameMap, rng: Rng, cols: int, rows: int,
		mode: String, loc: Dictionary) -> void:
	# Разбиваем карту на сектора лабиринта с широкими (2 тайла) проходами,
	# выполненными из кирпича T_BRICK с колоннами T_WALL для рикошетов.
	var step := 4
	for r in range(4, rows - 5, step):
		for c in range(4, cols - 5, step):
			if _is_protected(r, c, mode, rows, cols):
				continue
			var roll := rng.nextf()
			if roll < 0.35:
				# Т-образная или крестовая стена
				_safe_set(map, r, c, Cfg.T_WALL, mode, rows, cols)
				_safe_set(map, r + 1, c, Cfg.T_BRICK, mode, rows, cols)
				_safe_set(map, r - 1, c, Cfg.T_BRICK, mode, rows, cols)
				_safe_set(map, r, c + 1, Cfg.T_BRICK, mode, rows, cols)
				_safe_set(map, r, c - 1, Cfg.T_BRICK, mode, rows, cols)
			elif roll < 0.65:
				# Угловой тактический блок
				_safe_set(map, r, c, Cfg.T_WALL, mode, rows, cols)
				_safe_set(map, r + 1, c, Cfg.T_BRICK, mode, rows, cols)
				_safe_set(map, r + 2, c, Cfg.T_BRICK, mode, rows, cols)
				_safe_set(map, r, c + 1, Cfg.T_BRICK, mode, rows, cols)
				_safe_set(map, r, c + 2, Cfg.T_BRICK, mode, rows, cols)
			elif roll < 0.85:
				# Зал с колонной по центру
				_safe_set(map, r, c, Cfg.T_WALL, mode, rows, cols)
				_safe_set(map, r + 1, c + 1, Cfg.T_BRICK, mode, rows, cols)
				_safe_set(map, r - 1, c - 1, Cfg.T_BRICK, mode, rows, cols)

	# Открываем перекрёстки для манёвров (расчищаем ключевые залы)
	var halls: Array[Vector2i] = [
		Vector2i(rows / 3, cols / 3),
		Vector2i(rows / 3, cols * 2 / 3),
		Vector2i(rows * 2 / 3, cols / 3),
		Vector2i(rows * 2 / 3, cols * 2 / 3),
	]
	for hall: Vector2i in halls:
		_fill_rect(map, hall.x - 2, hall.x + 2, hall.y - 2, hall.y + 2, Cfg.T_ROAD)
		map.set_tile(hall.x, hall.y, Cfg.T_WALL)

## -----------------------------------------------------------------------
## 3. ПРОМЗОНА / Ж/Д УЗЕЛ (industrial): Ж/Д пути, составы вагонов, цистерны
## -----------------------------------------------------------------------
static func _apply_industrial(map: GameMap, rng: Rng, cols: int, rows: int,
		mode: String, loc: Dictionary) -> void:
	# 2 сквозные железнодорожные ветки через всю карту
	var tracks: Array[int] = [int(rows * 0.35), int(rows * 0.65)]
	for tr: int in tracks:
		if tr < 4 or tr >= rows - 4:
			continue
		# Полоса отчуждения / гравий
		_fill_rect(map, tr - 1, tr + 2, 2, cols - 3, Cfg.T_SAND)
		# Сами рельсы (две колеи дороги)
		for c in range(2, cols - 2):
			if not _is_protected(tr, c, mode, rows, cols):
				map.set_tile(tr, c, Cfg.T_ROAD)
				map.set_tile(tr + 1, c, Cfg.T_ROAD)

		# Составы товарных вагонов (цепочки 1x5 тайлов стен и кирпича с зазорами для проезда)
		var c := 6
		while c < cols - 8:
			var car_len := 4 + int(rng.nextf() * 3.0)
			if rng.nextf() < 0.70 and not _is_protected(tr, c, mode, rows, cols):
				for dc in car_len:
					var tile := Cfg.T_WALL if (dc == 0 or dc == car_len - 1) else Cfg.T_BRICK
					map.set_tile(tr, c + dc, tile)
			c += car_len + 3 # 3 тайла между вагонами для свободного проезда

	# Цилиндрические топливные резервуары (круглые цистерны 4x4)
	var depot_spots: Array[Vector2i] = [
		Vector2i(int(rows * 0.20), int(cols * 0.25)),
		Vector2i(int(rows * 0.20), int(cols * 0.75)),
		Vector2i(int(rows * 0.80), int(cols * 0.25)),
		Vector2i(int(rows * 0.80), int(cols * 0.75))
	]
	for ds: Vector2i in depot_spots:
		if not _is_protected(ds.x, ds.y, mode, rows, cols) and ds.x > 3 and ds.x < rows - 4:
			_draw_circular_tank(map, ds.x, ds.y, 3)

## -----------------------------------------------------------------------
## 4. КАНЬОН (canyon): Скалистые ущелья, расщелины и стратегические мосты
## -----------------------------------------------------------------------
static func _apply_canyon(map: GameMap, rng: Rng, cols: int, rows: int,
		mode: String, loc: Dictionary) -> void:
	# Горизонтальное ущелье, рассекающее карту пополам с мостами
	var mid_r := rows / 2
	var chasm_w := 3
	var r0 := mid_r - 1
	var r1 := mid_r + chasm_w - 2

	# Скалистые гряды вдоль каньона
	for c in range(2, cols - 2):
		if not _is_protected(mid_r, c, mode, rows, cols):
			map.set_tile(r0, c, Cfg.T_WATER)
			map.set_tile(r0 + 1, c, Cfg.T_WATER)
			# Песчаные осыпи по берегам
			if rng.nextf() < 0.60:
				_safe_set(map, r0 - 1, c, Cfg.T_QUICKSAND, mode, rows, cols)
			if rng.nextf() < 0.60:
				_safe_set(map, r1 + 1, c, Cfg.T_QUICKSAND, mode, rows, cols)

	# 3-4 укреплённых моста через каньон (Запад, Центр, Восток)
	var bridge_cols: Array[int] = [int(cols * 0.20), int(cols * 0.40), int(cols * 0.60), int(cols * 0.80)]
	for bc: int in bridge_cols:
		for dr in range(r0 - 2, r1 + 3):
			map.set_tile(dr, bc, Cfg.T_BRIDGE)
			map.set_tile(dr, bc + 1, Cfg.T_BRIDGE)
		# Оборонительные доты на въездах на мост
		_safe_set(map, r0 - 2, bc - 1, Cfg.T_WALL, mode, rows, cols)
		_safe_set(map, r0 - 2, bc + 2, Cfg.T_WALL, mode, rows, cols)
		_safe_set(map, r1 + 2, bc - 1, Cfg.T_WALL, mode, rows, cols)
		_safe_set(map, r1 + 2, bc + 2, Cfg.T_WALL, mode, rows, cols)

	# Скальные выступы и монолиты на плато
	for i in 12:
		var pr := rng.range_i(3, rows - 4)
		var pc := rng.range_i(3, cols - 4)
		if absi(pr - mid_r) > 3 and not _is_protected(pr, pc, mode, rows, cols):
			_fill_rect(map, pr - 1, pr + 1, pc - 1, pc + 1, Cfg.T_WALL)
			map.set_tile(pr, pc, Cfg.T_BRICK)

## -----------------------------------------------------------------------
## 5. КОЛЬЦА И ЛУЧИ (radial): Радиально-кольцевая планировка дорог
## -----------------------------------------------------------------------
static func _apply_radial(map: GameMap, rng: Rng, cols: int, rows: int,
		mode: String, loc: Dictionary) -> void:
	var cr := rows / 2
	var cc := cols / 2

	# Центральная ротонда / площадь
	_fill_rect(map, cr - 4, cr + 4, cc - 4, cc + 4, Cfg.T_ROAD)
	if mode != "defense":
		_fill_rect(map, cr - 1, cr + 1, cc - 1, cc + 1, Cfg.T_WALL)
		map.set_tile(cr, cc, Cfg.T_ROAD)

	# 2 концентрических кольцевых бульвара
	var radii: Array[float] = [8.0, 15.0]
	for rad: float in radii:
		var int_rad := int(rad)
		for dr in range(-int_rad - 1, int_rad + 2):
			for dc in range(-int_rad - 1, int_rad + 2):
				var r := cr + dr
				var c := cc + dc
				if r < 2 or r >= rows - 2 or c < 2 or c >= cols - 2:
					continue
				if _is_protected(r, c, mode, rows, cols):
					continue
				var d := sqrt(float(dr * dr + dc * dc))
				if absf(d - rad) <= 1.1:
					map.set_tile(r, c, Cfg.T_ROAD)

	# 8 радиальных лучевых проспектов от центра (N, S, W, E, NW, NE, SW, SE)
	var max_reach := maxi(rows, cols)
	var cardinal_dirs: Array[int] = [-1, 1]
	for step in range(4, max_reach / 2):
		# Ортогональные лучи (шириной 2)
		for s: int in cardinal_dirs:
			var dr: int = step * s
			_safe_set(map, cr + dr, cc, Cfg.T_ROAD, mode, rows, cols)
			_safe_set(map, cr + dr, cc + 1, Cfg.T_ROAD, mode, rows, cols)
			var dc: int = step * s
			_safe_set(map, cr, cc + dc, Cfg.T_ROAD, mode, rows, cols)
			_safe_set(map, cr + 1, cc + dc, Cfg.T_ROAD, mode, rows, cols)
		# Диагональные лучи
		for sign_r: int in cardinal_dirs:
			for sign_c: int in cardinal_dirs:
				var dr: int = int(float(step) * 0.707) * sign_r
				var dc: int = int(float(step) * 0.707) * sign_c
				_safe_set(map, cr + dr, cc + dc, Cfg.T_ROAD, mode, rows, cols)
				_safe_set(map, cr + dr, cc + dc + sign_c, Cfg.T_ROAD, mode, rows, cols)

## -----------------------------------------------------------------------
## 6. ГРАНДИОЗНАЯ ПЛОЩАДЬ (plaza): Парадный ансамбль, монумент, аллеи
## -----------------------------------------------------------------------
static func _apply_plaza(map: GameMap, rng: Rng, cols: int, rows: int,
		mode: String, loc: Dictionary) -> void:
	var cr := rows / 2
	var cc := cols / 2
	var pw := mini(20, cols - 12)
	var ph := mini(16, rows - 10)
	var r0 := cr - ph / 2
	var r1 := cr + ph / 2
	var c0 := cc - pw / 2
	var c1 := cc + pw / 2

	# Парадное мощение площади
	_fill_rect(map, r0, r1, c0, c1, Cfg.T_ROAD)

	# Центральный мемориал (если не база защиты)
	if mode != "defense":
		_fill_rect(map, cr - 1, cr + 1, cc - 1, cc + 1, Cfg.T_WALL)

	# 4 угловых парковых сквера с деревьями и укрытиями
	var sq_rows: Array[int] = [r0 + 2, r1 - 4]
	var sq_cols: Array[int] = [c0 + 2, c1 - 4]
	for sr: int in sq_rows:
		for sc: int in sq_cols:
			_fill_rect(map, sr, sr + 2, sc, sc + 2, Cfg.T_GRASS)
			map.set_tile(sr + 1, sc + 1, Cfg.T_TREE)
			map.set_tile(sr, sc, Cfg.T_BRICK)

	# Колоннады по бокам площади для перестрелок из-за укрытий
	for r in range(r0 + 2, r1 - 1, 2):
		_safe_set(map, r, c0 + 1, Cfg.T_WALL, mode, rows, cols)
		_safe_set(map, r, c1 - 1, Cfg.T_WALL, mode, rows, cols)

## -----------------------------------------------------------------------
## 7. ПРОСПЕКТЫ (avenues): Широкие скоростные трассы и сквозные развязки
## -----------------------------------------------------------------------
static func _apply_avenues(map: GameMap, rng: Rng, cols: int, rows: int,
		mode: String, loc: Dictionary) -> void:
	var cr := rows / 2
	var cc := cols / 2

	# Центральный скоростной хайвей (4 тайла шириной)
	_fill_rect(map, cr - 2, cr + 2, 2, cols - 3, Cfg.T_ROAD)
	_fill_rect(map, 2, rows - 3, cc - 2, cc + 2, Cfg.T_ROAD)

	# Разделительные островки безопасности с укрытиями
	for c in range(6, cols - 8, 8):
		if not _is_protected(cr, c, mode, rows, cols):
			map.set_tile(cr, c, Cfg.T_WALL)
			map.set_tile(cr, c + 1, Cfg.T_BRICK)
	for r in range(6, rows - 8, 8):
		if not _is_protected(r, cc, mode, rows, cols):
			map.set_tile(r, cc, Cfg.T_WALL)
			map.set_tile(r + 1, cc, Cfg.T_BRICK)

## -----------------------------------------------------------------------
## Вспомогательные методы геометрии и безопасности
## -----------------------------------------------------------------------

static func _is_protected(r: int, c: int, mode: String, rows: int, cols: int) -> bool:
	if mode == "ctf":
		# Зоны баз флага: Север (ряд 1..6) и Юг (ряд rows-7..rows-2)
		if (r <= 6 or r >= rows - 7) and absi(c - cols / 2) <= 8:
			return true
	elif mode == "defense":
		# Зона штаба в центре (5x5)
		if absi(r - rows / 2) <= 3 and absi(c - cols / 2) <= 3:
			return true
	return false

static func _safe_set(map: GameMap, r: int, c: int, tile: int,
		mode: String, rows: int, cols: int) -> void:
	if r <= 0 or r >= rows - 1 or c <= 0 or c >= cols - 1:
		return
	if _is_protected(r, c, mode, rows, cols):
		return
	map.set_tile(r, c, tile)

static func _fill_rect(map: GameMap, r0: int, r1: int, c0: int, c1: int, tile: int) -> void:
	for r in range(maxi(1, r0), mini(map.rows - 2, r1) + 1):
		for c in range(maxi(1, c0), mini(map.cols - 2, c1) + 1):
			map.set_tile(r, c, tile)

static func _carve_gate_and_bridge(map: GameMap, r0: int, r1: int,
		c0: int, c1: int, mode: String, rows: int, cols: int) -> void:
	for r in range(maxi(1, r0), mini(map.rows - 2, r1) + 1):
		for c in range(maxi(1, c0), mini(map.cols - 2, c1) + 1):
			if not _is_protected(r, c, mode, rows, cols):
				map.set_tile(r, c, Cfg.T_BRIDGE if map.get_tile(r, c) == Cfg.T_WATER else Cfg.T_ROAD)

static func _draw_circular_tank(map: GameMap, cr: int, cc: int, rad: int) -> void:
	for dr in range(-rad, rad + 1):
		for dc in range(-rad, rad + 1):
			var r := cr + dr
			var c := cc + dc
			if r < 1 or r >= map.rows - 1 or c < 1 or c >= map.cols - 1:
				continue
			var d := sqrt(float(dr * dr + dc * dc))
			if d <= float(rad):
				if d > float(rad) - 1.1:
					map.set_tile(r, c, Cfg.T_WALL)
				else:
					map.set_tile(r, c, Cfg.T_BRICK)
