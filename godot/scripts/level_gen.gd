# ============================================================================
# level_gen.gd — оркестратор генерации уровня.
#
# Сам он ничего не рисует. Его дело — порядок этапов и то, что специфично
# для режимов: базы, флаги, зоны спавна.
#
#   1. MapPlan   — план: магистрали, улицы, кварталы, районы, кольца
#   2. RoadNet   — покраска дорожной сети
#   3. Districts — застройка каждого квартала по его району
#   4. WaterGen  — река, берега, до четырёх мостов
#   5. Locations — зарастание пустот песком или лесом
#   6. режим     — базы, флаги, площадки
#   7. связность — проходимость карты и целостность дорожной сети
#
# Локация (город, пустошь, джунгли) не отдельный генератор, а набор правил
# для этого же конвейера: густота сетки, состав районов, ширина реки и то,
# чем зарастают пустоты.
#
# Порядок не переставляется произвольно. Река идёт после города, потому что
# должна резать готовую застройку; связность — последней, потому что чинит
# последствия всех предыдущих этапов.
#
# Раньше все шесть этапов жили в одном файле на шестьсот строк вперемешку,
# и любой вопрос вида «почему этот квартал промышленный» требовал читать
# его целиком. Теперь каждый этап — отдельный модуль в scripts/mapgen.
#
# Генерация детерминирована от seed: номер уровня 1..5 даёт всегда одну и ту
# же карту, -1 — случайную, а сетевая партия передаёт seed хоста.
# ============================================================================
class_name LevelGen
extends RefCounted

## Проброшено наружу ради тестов и документации.
const MAX_BRIDGES := WaterGen.MAX_BRIDGES

# ------------------------------------------------------------------ зоны
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

# ------------------------------------------------------------- генерация
## @param level_num 1..5 либо -1 для случайного
## @param mode ffa | ctf | koth | defense
## @param seed_override сетевая партия передаёт seed хоста: карта у всех
##        собирается локально и обязана совпасть до тайла.
## @param location city | dust | jungle | auto
static func generate(level_num: int, mode: String, seed_override: int = -1,
		location: String = Locations.CITY) -> Dictionary:
	var seed_value := 0
	if seed_override >= 0:
		seed_value = seed_override
	elif level_num < 0:
		seed_value = randi() & 0xFFFFFFFF
	else:
		seed_value = ((level_num - 1) * 7777 + 42) & 0xFFFFFFFF
	var rng := Rng.new(seed_value)
	# Локация тянется из того же генератора, что и карта: при «случайной»
	# в сетевой партии у хоста и клиента обязана совпасть и она.
	var loc_id := Locations.resolve(location, rng)
	var loc := Locations.get_location(loc_id)

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

	for r in rows:
		map.set_tile(r, 0, Cfg.T_WALL)
		map.set_tile(r, cols - 1, Cfg.T_WALL)
	for c in cols:
		map.set_tile(0, c, Cfg.T_WALL)
		map.set_tile(rows - 1, c, Cfg.T_WALL)

	# ---- 1-3: план, дороги, застройка ------------------------------------
	var plan := MapPlan.build(rng, cols, rows, loc)
	RoadNet.paint(map, plan)
	for block in plan["blocks"]:
		Districts.paint(map, rng, block, loc)
	# Перемычки — после застройки, иначе она их сотрёт.
	RoadNet.paint_links(map, plan)

	# ---- 4: река ---------------------------------------------------------
	# Только на больших картах: «Оборона» и «Захват флага» собраны под свою
	# геометрию, и река поперёк них ломала бы выверенный баланс.
	if mode == "ffa" or mode == "koth":
		WaterGen.carve(map, rng, cols, rows, plan["h"], float(loc["river"]))

	# ---- 5: зарастание --------------------------------------------------
	# Идёт по готовому рельефу и трогает только пустую землю, поэтому не
	# может ни разрезать улицу, ни засыпать мост.
	Locations.overgrow(map, rng, loc)
	Locations.carve_oases(map, rng, loc)

	# ---- 6: режим --------------------------------------------------------
	var homes := {"player": null, "enemy": null}
	var flag_spots := {"player": [], "enemy": []}
	if mode == "ctf":
		_build_ctf(map, rng, cols, rows, homes, flag_spots)
	if mode == "defense":
		var cr := rows / 2
		var cc := cols / 2
		_fill_rect(map, cr - 4, cr + 4, cc - 4, cc + 4, Cfg.T_ROAD)
		homes["player"] = Vector2(cc * Cfg.TILE + Cfg.TILE * 0.5, cr * Cfg.TILE + Cfg.TILE * 0.5)

	# ---- 7: связность ----------------------------------------------------
	# Проходимость карты и целостность дорожной сети — разные вещи: пройти
	# можно и через двор, а улица, обрывающаяся посреди квартала, читается
	# как ошибка генерации.
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
	}

# ============================================================== примитивы
static func _fill_rect(map: GameMap, r0: int, r1: int, c0: int, c1: int, tile: int) -> void:
	for r in range(maxi(1, r0), mini(map.rows - 2, r1) + 1):
		for c in range(maxi(1, c0), mini(map.cols - 2, c1) + 1):
			map.set_tile(r, c, tile)

## Симметричный блок укрытия: кирпич с бетонным ядром.
static func _cover_block(map: GameMap, r: int, c: int, w: int, h: int) -> void:
	for dr in h:
		for dc in w:
			map.set_tile(r + dr, c + dc, Cfg.T_BRICK)
	if w >= 2 and h >= 2:
		map.set_tile(r + h / 2, c + w / 2, Cfg.T_WALL)

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

	_fill_rect(map, 1, 6, cc - 8, cc + 8, Cfg.T_ROAD)
	_fill_rect(map, rows - 7, rows - 2, cc - 8, cc + 8, Cfg.T_ROAD)
	map.set_tile(2, cc, Cfg.T_BASE_E)
	map.set_tile(rows - 3, cc, Cfg.T_BASE_P)
	homes["enemy"] = Vector2(cc * Cfg.TILE + Cfg.TILE * 0.5, 2 * Cfg.TILE + Cfg.TILE * 0.5)
	homes["player"] = Vector2(cc * Cfg.TILE + Cfg.TILE * 0.5, (rows - 3) * Cfg.TILE + Cfg.TILE * 0.5)

	# Поперечные подъезды к базам, чтобы дом не запирался застройкой.
	_fill_rect(map, 3, 3, 5, cols - 6, Cfg.T_ROAD)
	_fill_rect(map, rows - 4, rows - 4, 5, cols - 6, Cfg.T_ROAD)

	# Центральная площадь: главное место боя.
	_fill_rect(map, mid - 4, mid + 4, 4, cols - 5, Cfg.T_ROAD)

	# Укрытия на площади — симметрично относительно центра, чтобы ни одна
	# команда не получила преимущества.
	for side in [-1, 1]:
		_cover_block(map, mid - 3, cc + side * 9 - 1, 3, 2)
		_cover_block(map, mid + 1, cc + side * 15 - 1, 2, 3)
	_cover_block(map, mid - 1, cc - 1, 3, 3)

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
