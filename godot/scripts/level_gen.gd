# ============================================================================
# level_gen.gd — генерация уровней: город, река, мосты и парки.
#
# Генерация полностью детерминирована от seed: номер уровня 1..5 даёт всегда
# одну и ту же карту, 'random' — случайную.
#
# Карта строится в четыре слоя, порядок важен:
#   1. Сетка улиц и проспектов — асфальт, скелет всей карты.
#   2. Кварталы между улицами — застройка, парки и площади.
#   3. Река поперёк города — стирает всё, через что течёт.
#   4. Мосты по улицам, которые её пересекают, — единственные переправы.
#
# Река идёт последней именно потому, что должна резать готовый город:
# набережная получается там, где вода съела часть квартала, а мост ложится
# ровно на улицу и продолжает её.
# ============================================================================
class_name LevelGen
extends RefCounted

## Зоны спавна в «Захвате флага»: у своей базы по центру кромки карты.
static func _ctf_player_area(cols: int, rows: int) -> Dictionary:
	return {"r0": rows - 8, "r1": rows - 4, "c0": cols / 2 - 8, "c1": cols / 2 + 8}

static func _ctf_enemy_area(cols: int, rows: int) -> Dictionary:
	return {"r0": 3, "r1": 7, "c0": cols / 2 - 8, "c1": cols / 2 + 8}

static func _area_any(cols: int, rows: int) -> Dictionary:
	return {"r0": 3, "r1": rows - 4, "c0": 3, "c1": cols - 4}

## В «Обороне» игроки возрождаются рядом с базой.
static func _defense_player_area(cols: int, rows: int) -> Dictionary:
	return {
		"r0": rows / 2 - 3, "r1": rows / 2 + 3,
		"c0": cols / 2 - 3, "c1": cols / 2 + 3,
	}

## В «Обороне» враги выходят с краёв карты: полоса по периметру, чтобы
## у защитника было время перехватить волну до подхода к центру.
static func _defense_enemy_area(cols: int, rows: int) -> Dictionary:
	return {"r0": 2, "r1": rows - 3, "c0": 2, "c1": cols - 3, "edge": true}

## @param level_num 1..5 либо -1 для случайного
## @param mode ffa | ctf | koth | defense
static func generate(level_num: int, mode: String) -> Dictionary:
	var seed_value := 0
	if level_num < 0:
		seed_value = randi() & 0xFFFFFFFF
	else:
		seed_value = ((level_num - 1) * 7777 + 42) & 0xFFFFFFFF
	var rng := Rng.new(seed_value)

	# Размер карты зависит от режима: «Оборона» вдвое меньше общей (база
	# в центре), «Захват флага» — ещё меньше, чтобы команды постоянно
	# сталкивались, а не искали друг друга.
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

	# -------------------------------------------------------------- рамка
	for r in rows:
		map.set_tile(r, 0, Cfg.T_WALL)
		map.set_tile(r, cols - 1, Cfg.T_WALL)
	for c in cols:
		map.set_tile(0, c, Cfg.T_WALL)
		map.set_tile(rows - 1, c, Cfg.T_WALL)

	# ---------------------------------------------------------------- город
	var city := _build_city(map, rng, cols, rows)

	# ---------------------------------------------------------- река и мосты
	# Только на больших картах: «Оборона» и «Захват флага» собраны под свою
	# геометрию, и река поперёк них ломала бы выверенный баланс.
	if mode == "ffa" or mode == "koth":
		_build_river(map, rng, cols, rows, city["h"])

	var homes := {"player": null, "enemy": null}
	var flag_spots := {"player": [], "enemy": []}

	# -------------------------------------------------------------- CTF
	if mode == "ctf":
		_build_ctf(map, rng, cols, rows, homes, flag_spots)

	# -------------------------------------------------------------- Оборона
	# База — центральная площадь города, вокруг неё чистый асфальт.
	if mode == "defense":
		var cr := rows / 2
		var cc := cols / 2
		_fill_rect(map, cr - 4, cr + 4, cc - 4, cc + 4, Cfg.T_ROAD)
		homes["player"] = Vector2(cc * Cfg.TILE + Cfg.TILE * 0.5, cr * Cfg.TILE + Cfg.TILE * 0.5)

	# Связность прорубается ПОСЛЕ всех правок рельефа.
	map.ensure_connectivity()

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
	}

# ============================================================== примитивы

## Заливка прямоугольника (в тайлах) без выхода на внешнюю рамку.
static func _fill_rect(map: GameMap, r0: int, r1: int, c0: int, c1: int, tile: int) -> void:
	for r in range(maxi(1, r0), mini(map.rows - 2, r1) + 1):
		for c in range(maxi(1, c0), mini(map.cols - 2, c1) + 1):
			map.set_tile(r, c, tile)

## Расчищает прямоугольник до земли — используется командными режимами.
static func _clear_rect(map: GameMap, r0: int, r1: int, c0: int, c1: int) -> void:
	_fill_rect(map, r0, r1, c0, c1, Cfg.T_EMPTY)

## Симметричный блок укрытия: кирпич с бетонным ядром.
static func _cover_block(map: GameMap, r: int, c: int, w: int, h: int) -> void:
	for dr in h:
		for dc in w:
			map.set_tile(r + dr, c + dc, Cfg.T_BRICK)
	if w >= 2 and h >= 2:
		map.set_tile(r + h / 2, c + w / 2, Cfg.T_WALL)

# ================================================================== город

## Раскладывает улицы вдоль одной оси. Возвращает список {pos, w}:
## pos — координата первой полосы, w — ширина (2 — улица, 3 — проспект).
static func _street_line(rng: Rng, size: int, block_min: int, block_max: int) -> Array:
	var out := []
	var p := 3 + int(rng.nextf() * 3.0)
	while p < size - 5:
		var w := 3 if rng.nextf() < 0.28 else 2
		out.append({"pos": p, "w": w})
		p += w + block_min + int(rng.nextf() * float(block_max - block_min + 1))
	return out

## Промежутки между улицами — это и есть кварталы.
static func _gaps(streets: Array, size: int) -> Array:
	var out := []
	var prev := 1
	for st in streets:
		var pos: int = int(st["pos"])
		if pos - 1 >= prev:
			out.append([prev, pos - 1])
		prev = pos + int(st["w"])
	if size - 2 >= prev:
		out.append([prev, size - 2])
	return out

## Режет отрезок [a, b] переулками: сами линии переулков в результат
## не попадают, поэтому между участками остаётся проезд.
static func _split(a: int, b: int, cuts: Array) -> Array:
	var out := []
	var start := a
	for cut in cuts:
		var x: int = int(cut)
		if x - 1 >= start:
			out.append([start, x - 1])
		start = x + 1
	if b >= start:
		out.append([start, b])
	return out

## Строит городскую сетку и застраивает кварталы.
## Возвращает {"v": [...], "h": [...]} — списки улиц, они нужны мостам.
static func _build_city(map: GameMap, rng: Rng, cols: int, rows: int) -> Dictionary:
	# Кварталы вдоль длинной оси чуть крупнее — так город не выглядит
	# нарезанным на одинаковые квадраты.
	var v := _street_line(rng, cols, 9, 14)
	var h := _street_line(rng, rows, 7, 11)

	for st in v:
		var w: int = int(st["w"])
		for dc in w:
			var c: int = int(st["pos"]) + dc
			if c <= 0 or c >= cols - 1:
				continue
			for r in range(1, rows - 1):
				map.set_tile(r, c, Cfg.T_ROAD)
	for st in h:
		var w: int = int(st["w"])
		for dr in w:
			var r: int = int(st["pos"]) + dr
			if r <= 0 or r >= rows - 1:
				continue
			for c in range(1, cols - 1):
				map.set_tile(r, c, Cfg.T_ROAD)

	var row_gaps := _gaps(h, rows)
	var col_gaps := _gaps(v, cols)
	for rg in row_gaps:
		for cg in col_gaps:
			var r0: int = int(rg[0])
			var r1: int = int(rg[1])
			var c0: int = int(cg[0])
			var c1: int = int(cg[1])
			# Узкие полоски у кромки карты застраивать нечем — газон.
			if r1 - r0 < 2 or c1 - c0 < 2:
				_fill_rect(map, r0, r1, c0, c1, Cfg.T_GRASS)
				continue
			var roll := rng.nextf()
			if roll < 0.18:
				_block_park(map, rng, r0, r1, c0, c1)
			elif roll < 0.28:
				_block_square(map, rng, r0, r1, c0, c1)
			else:
				_block_houses(map, rng, r0, r1, c0, c1)

	return {"v": v, "h": h}

## Жилой квартал: тротуар по периметру, внутри — участки под застройку,
## разделённые переулками.
static func _block_houses(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int) -> void:
	_fill_rect(map, r0, r1, c0, c1, Cfg.T_EMPTY)
	var br0 := r0 + 1
	var br1 := r1 - 1
	var bc0 := c0 + 1
	var bc1 := c1 - 1
	if br1 < br0 or bc1 < bc0:
		return

	var ccuts := []
	if bc1 - bc0 >= 7 and rng.nextf() < 0.7:
		ccuts.append(bc0 + 3 + int(rng.nextf() * float(bc1 - bc0 - 5)))
	var rcuts := []
	if br1 - br0 >= 7 and rng.nextf() < 0.5:
		rcuts.append(br0 + 3 + int(rng.nextf() * float(br1 - br0 - 5)))

	for rl in _split(br0, br1, rcuts):
		for cl in _split(bc0, bc1, ccuts):
			_house(map, rng, int(rl[0]), int(rl[1]), int(cl[0]), int(cl[1]))

## Одна постройка. Материал не задаётся здесь — он выводится из координат
## тайла в Materials, поэтому дом сам «решает», деревянный он или бетонный.
static func _house(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int) -> void:
	var h := r1 - r0 + 1
	var w := c1 - c0 + 1
	if h <= 0 or w <= 0:
		return

	# Пустырь: заброшенный участок с деревьями и остатками фундамента.
	if h < 2 or w < 2 or rng.nextf() < 0.12:
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				var q := rng.nextf()
				if q < 0.09:
					map.set_tile(r, c, Cfg.T_TREE)
				elif q < 0.14:
					map.set_tile(r, c, Cfg.T_BRICK)
		return

	_fill_rect(map, r0, r1, c0, c1, Cfg.T_BRICK)

	# Несущий каркас: пара бетонных колонн, которые не сбить ничем.
	# Из-за них даже полностью разрушенный дом оставляет укрытие.
	if h >= 4 and w >= 4 and rng.nextf() < 0.45:
		map.set_tile(r0 + h / 2, c0 + w / 2, Cfg.T_WALL)
		if rng.nextf() < 0.6:
			map.set_tile(r0 + h / 2, c1 - 1, Cfg.T_WALL)

	# Внутренний двор с подворотнёй — сквозной проезд через дом.
	if h >= 6 and w >= 6 and rng.nextf() < 0.5:
		_fill_rect(map, r0 + 2, r1 - 2, c0 + 2, c1 - 2, Cfg.T_EMPTY)
		var gate := c0 + w / 2
		map.set_tile(r0, gate, Cfg.T_EMPTY)
		map.set_tile(r0 + 1, gate, Cfg.T_EMPTY)
		if rng.nextf() < 0.5:
			map.set_tile(r1, gate, Cfg.T_EMPTY)
			map.set_tile(r1 - 1, gate, Cfg.T_EMPTY)

## Городской парк: газон, дорожки крест-накрест, деревья и иногда пруд.
static func _block_park(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int) -> void:
	_fill_rect(map, r0, r1, c0, c1, Cfg.T_GRASS)

	var mr := (r0 + r1) / 2
	var mc := (c0 + c1) / 2
	_fill_rect(map, mr, mr, c0, c1, Cfg.T_EMPTY)
	_fill_rect(map, mr - 1, mr - 1, c0, c1, Cfg.T_EMPTY)
	_fill_rect(map, r0, r1, mc, mc, Cfg.T_EMPTY)

	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if map.get_tile(r, c) != Cfg.T_GRASS:
				continue
			var q := rng.nextf()
			if q < 0.17:
				map.set_tile(r, c, Cfg.T_TREE)
			elif q < 0.19:
				# Скамейки и киоски: одиночные укрытия среди зелени.
				map.set_tile(r, c, Cfg.T_BRICK)

	# Пруд в глубине парка — с песчаным берегом его добавит общий проход.
	if r1 - r0 >= 5 and c1 - c0 >= 5 and rng.nextf() < 0.3:
		var pr := r0 + 1 + int(rng.nextf() * float(r1 - r0 - 3))
		var pc := c0 + 1 + int(rng.nextf() * float(c1 - c0 - 3))
		_fill_rect(map, pr, pr + 1, pc, pc + 2, Cfg.T_WATER)
		_sand_shore(map, pr - 1, pr + 2, pc - 1, pc + 3)

## Площадь или парковка: сплошной асфальт с редкими киосками.
static func _block_square(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int) -> void:
	_fill_rect(map, r0, r1, c0, c1, Cfg.T_ROAD)
	var kiosks := 1 + int(rng.nextf() * 3.0)
	for i in kiosks:
		var kr := r0 + int(rng.nextf() * float(maxi(1, r1 - r0)))
		var kc := c0 + int(rng.nextf() * float(maxi(1, c1 - c0)))
		_fill_rect(map, kr, kr + 1, kc, kc + 1, Cfg.T_BRICK)
	# Аллея деревьев вдоль края площади.
	if rng.nextf() < 0.5:
		for c in range(c0, c1 + 1, 2):
			map.set_tile(r0, c, Cfg.T_TREE)

# =========================================================== река и мосты

## Обводит воду песком в указанном прямоугольнике.
static func _sand_shore(map: GameMap, r0: int, r1: int, c0: int, c1: int) -> void:
	for r in range(maxi(1, r0), mini(map.rows - 2, r1) + 1):
		for c in range(maxi(1, c0), mini(map.cols - 2, c1) + 1):
			if map.get_tile(r, c) == Cfg.T_WATER:
				continue
			var near := false
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					if map.get_tile(r + dr, c + dc) == Cfg.T_WATER:
						near = true
						break
				if near:
					break
			if near:
				map.set_tile(r, c, Cfg.T_SAND)

## Река течёт сверху вниз, разрезая город на два берега, и стирает всё,
## через что проходит: дома на её пути превращаются в набережную.
static func _build_river(map: GameMap, rng: Rng, cols: int, rows: int, h_streets: Array) -> void:
	var base := float(cols) * (0.38 + rng.nextf() * 0.24)
	var amp := float(cols) * (0.04 + rng.nextf() * 0.05)
	var freq := 0.055 + rng.nextf() * 0.05
	var phase := rng.nextf() * TAU
	var half := 2 + int(rng.nextf() * 2.0)

	# Границы русла по строкам — по ним потом кладутся мосты.
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	left.resize(rows)
	right.resize(rows)
	for r in rows:
		var centre := base + sin(float(r) * freq + phase) * amp
		var c0 := int(roundf(centre)) - half
		var c1 := int(roundf(centre)) + half
		left[r] = c0
		right[r] = c1
		if r <= 0 or r >= rows - 1:
			continue
		for c in range(maxi(1, c0), mini(cols - 2, c1) + 1):
			map.set_tile(r, c, Cfg.T_WATER)

	_sand_shore(map, 1, rows - 2, int(base - amp) - half - 2, int(base + amp) + half + 2)

	# Мосты: берём улицы, пересекающие реку. Первую и последнюю — обязательно,
	# иначе половина города оказалась бы отрезанной; остальные — через одну,
	# чтобы переправы оставались узкими местами, за которые стоит драться.
	var usable := []
	for st in h_streets:
		var pos: int = int(st["pos"])
		if pos >= 2 and pos + int(st["w"]) <= rows - 2:
			usable.append(st)
	for i in usable.size():
		var force := i == 0 or i == usable.size() - 1
		if not force and rng.nextf() > 0.5:
			continue
		_build_bridge(map, usable[i], left, right, cols)

## Кладёт мост на одну улицу: настил над водой плюс въезды на оба берега.
static func _build_bridge(map: GameMap, street: Dictionary, left: PackedInt32Array,
		right: PackedInt32Array, cols: int) -> void:
	var pos: int = int(street["pos"])
	var w: int = int(street["w"])
	for dr in w:
		var r: int = pos + dr
		if r <= 0 or r >= map.rows - 1:
			continue
		# Въезды заходят на два тайла берега: мост должен смыкаться
		# с улицей, а не обрываться в песок.
		var c0: int = maxi(1, left[r] - 2)
		var c1: int = mini(cols - 2, right[r] + 2)
		for c in range(c0, c1 + 1):
			if map.get_tile(r, c) == Cfg.T_WALL:
				continue
			map.set_tile(r, c, Cfg.T_BRIDGE)

# ==================================================================== CTF

## Карта «Захвата флага».
##
## Базы стоят по центру верхней и нижней кромки, между ними — открытая
## площадь с укрытиями, а флаги обеих команд поставлены в двух узких полосах
## по разные стороны от центра. Из-за этого обе команды выезжают навстречу
## друг другу и сталкиваются у флагов.
##
## Городская сетка под этим слоем остаётся: подъезды и площадь просто
## ложатся поверх кварталов широкими проспектами.
static func _build_ctf(map: GameMap, rng: Rng, cols: int, rows: int,
		homes: Dictionary, flag_spots: Dictionary) -> void:
	var cc := cols / 2
	var mid := rows / 2

	# --- базы по центру кромок и площадки вокруг них
	_fill_rect(map, 1, 6, cc - 8, cc + 8, Cfg.T_ROAD)
	_fill_rect(map, rows - 7, rows - 2, cc - 8, cc + 8, Cfg.T_ROAD)
	map.set_tile(2, cc, Cfg.T_BASE_E)
	map.set_tile(rows - 3, cc, Cfg.T_BASE_P)
	homes["enemy"] = Vector2(cc * Cfg.TILE + Cfg.TILE * 0.5, 2 * Cfg.TILE + Cfg.TILE * 0.5)
	homes["player"] = Vector2(cc * Cfg.TILE + Cfg.TILE * 0.5, (rows - 3) * Cfg.TILE + Cfg.TILE * 0.5)

	# --- поперечные подъезды к базам, чтобы дом не запирался застройкой
	_fill_rect(map, 3, 3, 5, cols - 6, Cfg.T_ROAD)
	_fill_rect(map, rows - 4, rows - 4, 5, cols - 6, Cfg.T_ROAD)

	# --- центральная площадь: главное место боя
	_fill_rect(map, mid - 4, mid + 4, 4, cols - 5, Cfg.T_ROAD)

	# Укрытия на площади — симметрично относительно центра, чтобы ни одна
	# команда не получила преимущества.
	for side in [-1, 1]:
		_cover_block(map, mid - 3, cc + side * 9 - 1, 3, 2)
		_cover_block(map, mid + 1, cc + side * 15 - 1, 2, 3)
	_cover_block(map, mid - 1, cc - 1, 3, 3)

	# --- флаги в двух полосах вплотную к центру
	var per_team: int = Cfg.MODES["ctf"]["flags_per_team"]
	flag_spots["enemy"] = _pick_flag_spots(map, rng, per_team,
		int(rows * 0.28), int(rows * 0.40))
	flag_spots["player"] = _pick_flag_spots(map, rng, per_team,
		int(rows * 0.60), int(rows * 0.72))

## Разбрасывает точки флагов в горизонтальной полосе, не ближе 10 тайлов
## друг к другу.
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

	# Гарантированный запасной вариант: раскладываем по центру полосы.
	var fallback_col := cols / 2 - count * 3
	while spots.size() < count:
		var r: int = clampi((row_from + row_to) / 2, 1, rows - 2)
		var c: int = clampi(fallback_col, 1, cols - 2)
		map.set_tile(r, c, Cfg.T_EMPTY)
		spots.append(Vector2(c * Cfg.TILE + Cfg.TILE * 0.5, r * Cfg.TILE + Cfg.TILE * 0.5))
		fallback_col += 4
	return spots
