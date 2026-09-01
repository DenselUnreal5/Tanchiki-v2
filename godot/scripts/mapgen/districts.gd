# ============================================================================
# districts.gd — застройка квартала по его району.
#
# Третий этап конвейера. Раньше тип квартала бросался кубиком независимо
# от соседей, и склад оказывался между парком и жилым домом. На референсах
# видно обратное: город состоит из связных зон — центр, жильё, промышленность,
# парк, — и каждая узнаётся с одного взгляда.
#
# Район квартала приходит из плана; здесь он превращается в тайлы.
# Каждая функция красит один квартал и ничего не знает об остальной карте:
# так их можно менять и добавлять по одной.
# ============================================================================
class_name Districts
extends RefCounted

## Раскладка квартала по типу района.
## @param loc правила локации: чем застелена земля и дворы
static func paint(map: GameMap, rng: Rng, block: Dictionary,
		loc: Dictionary = {}) -> void:
	var ground: int = int(loc.get("ground_tile", Cfg.T_GRASS))
	var yard: int = int(loc.get("yard_tile", Cfg.T_ROAD))
	var r0: int = int(block["r0"])
	var r1: int = int(block["r1"])
	var c0: int = int(block["c0"])
	var c1: int = int(block["c1"])
	# Узкие полоски у кромки карты застраивать нечем — газон.
	if r1 - r0 < 2 or c1 - c0 < 2:
		_fill(map, r0, r1, c0, c1, ground)
		return

	match String(block["district"]):
		"downtown":
			_downtown(map, rng, r0, r1, c0, c1, yard)
		"industrial":
			_industrial(map, rng, r0, r1, c0, c1, yard)
		"park":
			_park(map, rng, r0, r1, c0, c1, ground)
		_:
			_residential(map, rng, r0, r1, c0, c1, ground)

# --------------------------------------------------------------- деловой
## Центр: плотная застройка во всю глубину квартала, узкие дворы,
## изредка площадь. Здесь дерутся в упор.
static func _downtown(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	if rng.nextf() < 0.14:
		_plaza(map, rng, r0, r1, c0, c1, yard)
		return
	_fill(map, r0, r1, c0, c1, Cfg.T_EMPTY)
	var lots := _subdivide(rng, r0 + 1, r1 - 1, c0 + 1, c1 - 1, 6, 0.75)
	for lot in lots:
		_tower(map, rng, int(lot[0]), int(lot[1]), int(lot[2]), int(lot[3]))

## Высокая коробка с бетонным каркасом и сквозной подворотнёй.
static func _tower(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int) -> void:
	var h := r1 - r0 + 1
	var w := c1 - c0 + 1
	if h < 2 or w < 2:
		return
	_fill(map, r0, r1, c0, c1, Cfg.T_BRICK)
	# Несущие колонны: их не сбить ничем, и разрушенный дом всё равно
	# оставляет укрытие.
	if h >= 4 and w >= 4:
		map.set_tile(r0 + h / 2, c0 + w / 2, Cfg.T_WALL)
		if rng.nextf() < 0.6:
			map.set_tile(r0 + h / 2, c1 - 1, Cfg.T_WALL)
	if h >= 6 and w >= 6 and rng.nextf() < 0.55:
		_fill(map, r0 + 2, r1 - 2, c0 + 2, c1 - 2, Cfg.T_EMPTY)
		var gate := c0 + w / 2
		map.set_tile(r0, gate, Cfg.T_EMPTY)
		map.set_tile(r0 + 1, gate, Cfg.T_EMPTY)

# ----------------------------------------------------------------- жильё
## Жилой квартал: дома мельче, между ними сады и проезды. Боя в упор
## меньше, зато больше обходных путей.
static func _residential(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		ground: int) -> void:
	_fill(map, r0, r1, c0, c1, ground)
	var lots := _subdivide(rng, r0 + 1, r1 - 1, c0 + 1, c1 - 1, 4, 0.55)
	for lot in lots:
		var lr0: int = int(lot[0])
		var lr1: int = int(lot[1])
		var lc0: int = int(lot[2])
		var lc1: int = int(lot[3])
		if rng.nextf() < 0.22:
			# Двор: деревья и кусты вместо дома.
			for r in range(lr0, lr1 + 1):
				for c in range(lc0, lc1 + 1):
					if rng.nextf() < 0.30:
						map.set_tile(r, c, Cfg.T_TREE)
			continue
		# Дом не на всю глубину участка: остаётся палисадник у улицы.
		_fill(map, lr0, maxi(lr0, lr1 - 1), lc0, lc1, Cfg.T_BRICK)

# --------------------------------------------------------- промышленность
## Промзона: длинные склады и открытые площадки под погрузку. Простреливается
## насквозь, укрытий мало — противоположность центру.
static func _industrial(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	_fill(map, r0, r1, c0, c1, yard)
	var lots := _subdivide(rng, r0 + 1, r1 - 1, c0 + 1, c1 - 1, 7, 0.35)
	for lot in lots:
		if rng.nextf() < 0.35:
			continue  # площадка под погрузку
		var lr0: int = int(lot[0])
		var lr1: int = int(lot[1])
		var lc0: int = int(lot[2])
		var lc1: int = int(lot[3])
		_fill(map, lr0, lr1, lc0, lc1, Cfg.T_BRICK)
		# Ворота в торце: склад без входа выглядит глухой коробкой.
		if lc1 - lc0 >= 3:
			map.set_tile(lr1, lc0 + (lc1 - lc0) / 2, Cfg.T_EMPTY)

# ------------------------------------------------------------------ парк
static func _park(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		ground: int) -> void:
	_fill(map, r0, r1, c0, c1, ground)
	var mr := (r0 + r1) / 2
	var mc := (c0 + c1) / 2
	_fill(map, mr - 1, mr, c0, c1, Cfg.T_EMPTY)
	_fill(map, r0, r1, mc, mc, Cfg.T_EMPTY)

	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if map.get_tile(r, c) != ground:
				continue
			var q := rng.nextf()
			if q < 0.17:
				map.set_tile(r, c, Cfg.T_TREE)
			elif q < 0.19:
				map.set_tile(r, c, Cfg.T_BRICK)  # скамейки и киоски

	if r1 - r0 >= 5 and c1 - c0 >= 5 and rng.nextf() < 0.3:
		var pr := r0 + 1 + int(rng.nextf() * float(r1 - r0 - 3))
		var pc := c0 + 1 + int(rng.nextf() * float(c1 - c0 - 3))
		_fill(map, pr, pr + 1, pc, pc + 2, Cfg.T_WATER)

## Площадь или парковка: сплошной асфальт с редкими киосками.
static func _plaza(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	_fill(map, r0, r1, c0, c1, yard)
	for i in 1 + int(rng.nextf() * 3.0):
		var kr := r0 + int(rng.nextf() * float(maxi(1, r1 - r0)))
		var kc := c0 + int(rng.nextf() * float(maxi(1, c1 - c0)))
		_fill(map, kr, kr + 1, kc, kc + 1, Cfg.T_BRICK)

# ------------------------------------------------------------- помощники
## Режет квартал на участки переулками. cell — желаемая сторона участка,
## chance — вероятность реза по каждой оси.
static func _subdivide(rng: Rng, r0: int, r1: int, c0: int, c1: int,
		cell: int, chance: float) -> Array:
	if r1 < r0 or c1 < c0:
		return []
	var rcuts := []
	if r1 - r0 >= cell + 2 and rng.nextf() < chance:
		rcuts.append(r0 + cell / 2 + int(rng.nextf() * float(r1 - r0 - cell)))
	var ccuts := []
	if c1 - c0 >= cell + 2 and rng.nextf() < chance:
		ccuts.append(c0 + cell / 2 + int(rng.nextf() * float(c1 - c0 - cell)))

	var out := []
	for rs in _split(r0, r1, rcuts):
		for cs in _split(c0, c1, ccuts):
			out.append([rs[0], rs[1], cs[0], cs[1]])
	return out

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

static func _fill(map: GameMap, r0: int, r1: int, c0: int, c1: int, tile: int) -> void:
	for r in range(maxi(1, r0), mini(map.rows - 2, r1) + 1):
		for c in range(maxi(1, c0), mini(map.cols - 2, c1) + 1):
			map.set_tile(r, c, tile)
