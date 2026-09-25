class_name Districts
extends RefCounted

static func paint(map: GameMap, rng: Rng, block: Dictionary,
		loc: Dictionary = {}) -> void:
	var ground: int = int(loc.get("ground_tile", Cfg.T_GRASS))
	var yard: int = int(loc.get("yard_tile", Cfg.T_ROAD))
	var r0: int = int(block["r0"])
	var r1: int = int(block["r1"])
	var c0: int = int(block["c0"])
	var c1: int = int(block["c1"])
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
		"adobe_village":
			VillageGen.paint(map, rng, r0, r1, c0, c1, ground, loc)
		_:
			_residential(map, rng, r0, r1, c0, c1, ground)

static func _downtown(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	var h := r1 - r0 + 1
	var w := c1 - c0 + 1

	# Для просторных кварталов с шансом 18% делаем грандиозную площадь или комплекс
	if h >= 8 and w >= 8 and rng.nextf() < 0.18:
		_grand_plaza(map, rng, r0, r1, c0, c1, yard)
		return

	# Если квартал большой и квадратный — строим квартал со сквозным двором (courtyard)
	if h >= 7 and w >= 7 and rng.nextf() < 0.35:
		_courtyard_block(map, rng, r0, r1, c0, c1, yard)
		return

	_fill(map, r0, r1, c0, c1, Cfg.T_EMPTY)
	var lots := _subdivide(rng, r0 + 1, r1 - 1, c0 + 1, c1 - 1, 6, 0.70)
	for lot in lots:
		var lr0: int = int(lot[0])
		var lr1: int = int(lot[1])
		var lc0: int = int(lot[2])
		var lc1: int = int(lot[3])
		var lh := lr1 - lr0 + 1
		var lw := lc1 - lc0 + 1

		var style := rng.nextf()
		if lh >= 5 and lw >= 5 and style < 0.35:
			_l_building(map, rng, lr0, lr1, lc0, lc1, yard)
		elif lh >= 5 and lw >= 5 and style < 0.60:
			_u_building(map, rng, lr0, lr1, lc0, lc1, yard)
		elif style < 0.85:
			_tower(map, rng, lr0, lr1, lc0, lc1)
		else:
			_twin_towers(map, rng, lr0, lr1, lc0, lc1)

## Здание со сквозным внутренним двором и арками для проезда танков
static func _courtyard_block(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	_fill(map, r0, r1, c0, c1, Cfg.T_BRICK)
	# Внутренний двор
	_fill(map, r0 + 2, r1 - 2, c0 + 2, c1 - 2, yard)

	# Угловые бетонные колонны жесткости
	map.set_tile(r0 + 1, c0 + 1, Cfg.T_WALL)
	map.set_tile(r0 + 1, c1 - 1, Cfg.T_WALL)
	map.set_tile(r1 - 1, c0 + 1, Cfg.T_WALL)
	map.set_tile(r1 - 1, c1 - 1, Cfg.T_WALL)

	# Сквозные проезды (шириной 2 тайла), чтобы танк легко проезжал
	var mid_r := (r0 + r1) / 2
	var mid_c := (c0 + c1) / 2

	if rng.nextf() < 0.5:
		# Ворота север-юг
		_fill(map, r0, r0 + 2, mid_c, mid_c + 1, yard)
		_fill(map, r1 - 2, r1, mid_c, mid_c + 1, yard)
	else:
		# Ворота запад-восток
		_fill(map, mid_r, mid_r + 1, c0, c0 + 2, yard)
		_fill(map, mid_r, mid_r + 1, c1 - 2, c1, yard)

	# В центре двора — памятник или дерево
	if (r1 - r0) >= 8 and (c1 - c0) >= 8:
		map.set_tile(mid_r, mid_c, Cfg.T_WALL)

## Г-образное здание с открытым уютным углом
static func _l_building(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	_fill(map, r0, r1, c0, c1, yard)
	var mid_r := r0 + (r1 - r0) / 2
	var mid_c := c0 + (c1 - c0) / 2

	# 4 возможных ориентации Г-образного корпуса
	var orient := int(rng.nextf() * 4.0) % 4
	match orient:
		0: # Верх и лево
			_fill(map, r0, mid_r, c0, c1, Cfg.T_BRICK)
			_fill(map, mid_r, r1, c0, mid_c, Cfg.T_BRICK)
			map.set_tile(r0 + 1, c0 + 1, Cfg.T_WALL)
		1: # Верх и право
			_fill(map, r0, mid_r, c0, c1, Cfg.T_BRICK)
			_fill(map, mid_r, r1, mid_c, c1, Cfg.T_BRICK)
			map.set_tile(r0 + 1, c1 - 1, Cfg.T_WALL)
		2: # Низ и лево
			_fill(map, mid_r, r1, c0, c1, Cfg.T_BRICK)
			_fill(map, r0, mid_r, c0, mid_c, Cfg.T_BRICK)
			map.set_tile(r1 - 1, c0 + 1, Cfg.T_WALL)
		_: # Низ и право
			_fill(map, mid_r, r1, c0, c1, Cfg.T_BRICK)
			_fill(map, r0, mid_r, mid_c, c1, Cfg.T_BRICK)
			map.set_tile(r1 - 1, c1 - 1, Cfg.T_WALL)

## П-образный комплекс с внутренним парковочным карманом
static func _u_building(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	_fill(map, r0, r1, c0, c1, yard)
	var thick := 2
	var open_side := int(rng.nextf() * 4.0) % 4

	_fill(map, r0, r1, c0, c1, Cfg.T_BRICK)
	match open_side:
		0: # Открыто сверху
			_fill(map, r0, r1 - thick, c0 + thick, c1 - thick, yard)
		1: # Открыто снизу
			_fill(map, r0 + thick, r1, c0 + thick, c1 - thick, yard)
		2: # Открыто слева
			_fill(map, r0 + thick, r1 - thick, c0, c1 - thick, yard)
		_: # Открыто справа
			_fill(map, r0 + thick, r1 - thick, c0 + thick, c1, yard)

## Две башни с тактическим проходом между ними
static func _twin_towers(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int) -> void:
	_fill(map, r0, r1, c0, c1, Cfg.T_EMPTY)
	var h := r1 - r0 + 1
	var w := c1 - c0 + 1
	if w >= h:
		var mid := (c0 + c1) / 2
		_fill(map, r0, r1, c0, mid - 1, Cfg.T_BRICK)
		_fill(map, r0, r1, mid + 1, c1, Cfg.T_BRICK)
		map.set_tile(r0 + h / 2, c0 + (mid - 1 - c0) / 2, Cfg.T_WALL)
		map.set_tile(r0 + h / 2, mid + 1 + (c1 - mid - 1) / 2, Cfg.T_WALL)
	else:
		var mid := (r0 + r1) / 2
		_fill(map, r0, mid - 1, c0, c1, Cfg.T_BRICK)
		_fill(map, mid + 1, r1, c0, c1, Cfg.T_BRICK)
		map.set_tile(r0 + (mid - 1 - r0) / 2, c0 + w / 2, Cfg.T_WALL)
		map.set_tile(mid + 1 + (r1 - mid - 1) / 2, c0 + w / 2, Cfg.T_WALL)

## Классическая монументальная высотка
static func _tower(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int) -> void:
	var h := r1 - r0 + 1
	var w := c1 - c0 + 1
	if h < 2 or w < 2:
		return
	_fill(map, r0, r1, c0, c1, Cfg.T_BRICK)
	if h >= 4 and w >= 4:
		map.set_tile(r0 + h / 2, c0 + w / 2, Cfg.T_WALL)
		if rng.nextf() < 0.6:
			map.set_tile(r0 + h / 2, c1 - 1, Cfg.T_WALL)
	if h >= 6 and w >= 6 and rng.nextf() < 0.55:
		_fill(map, r0 + 2, r1 - 2, c0 + 2, c1 - 2, Cfg.T_EMPTY)
		var gate := c0 + w / 2
		map.set_tile(r0, gate, Cfg.T_EMPTY)
		map.set_tile(r0 + 1, gate, Cfg.T_EMPTY)

## Жилой район с садами, коттеджами и зелеными уголками
static func _residential(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		ground: int) -> void:
	_fill(map, r0, r1, c0, c1, ground)
	var lots := _subdivide(rng, r0 + 1, r1 - 1, c0 + 1, c1 - 1, 4, 0.60)
	for lot in lots:
		var lr0: int = int(lot[0])
		var lr1: int = int(lot[1])
		var lc0: int = int(lot[2])
		var lc1: int = int(lot[3])
		var lh := lr1 - lr0 + 1
		var lw := lc1 - lc0 + 1

		var q := rng.nextf()
		if q < 0.22:
			# Сад с деревьями
			for r in range(lr0, lr1 + 1):
				for c in range(lc0, lc1 + 1):
					if rng.nextf() < 0.35:
						map.set_tile(r, c, Cfg.T_TREE)
		elif q < 0.55 and lh >= 4 and lw >= 4:
			# Г-образный коттедж
			_l_building(map, rng, lr0, lr1, lc0, lc1, ground)
		else:
			# Обычный дом с двориком
			_fill(map, lr0, maxi(lr0, lr1 - 1), lc0, lc1, Cfg.T_BRICK)
			if lw >= 4:
				map.set_tile(lr0 + lh / 2, lc0 + lw / 2, Cfg.T_WALL)

## Промышленный район: контейнеры, ангары, бункеры
static func _industrial(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	_fill(map, r0, r1, c0, c1, yard)
	var h := r1 - r0 + 1
	var w := c1 - c0 + 1

	# Складской терминал с контейнерными рядами
	if h >= 6 and w >= 6 and rng.nextf() < 0.40:
		_container_depot(map, rng, r0 + 1, r1 - 1, c0 + 1, c1 - 1)
		return

	var lots := _subdivide(rng, r0 + 1, r1 - 1, c0 + 1, c1 - 1, 6, 0.45)
	for lot in lots:
		if rng.nextf() < 0.25:
			continue
		var lr0: int = int(lot[0])
		var lr1: int = int(lot[1])
		var lc0: int = int(lot[2])
		var lc1: int = int(lot[3])
		var lh := lr1 - lr0 + 1
		var lw := lc1 - lc0 + 1

		# Ангар с широким въездом
		_fill(map, lr0, lr1, lc0, lc1, Cfg.T_BRICK)
		# Бетонные укрепленные углы
		map.set_tile(lr0, lc0, Cfg.T_WALL)
		map.set_tile(lr0, lc1, Cfg.T_WALL)
		map.set_tile(lr1, lc0, Cfg.T_WALL)
		map.set_tile(lr1, lc1, Cfg.T_WALL)

		# Широкие ворота ангара
		if lw >= 4:
			var gate := lc0 + lw / 2
			map.set_tile(lr1, gate, Cfg.T_EMPTY)
			map.set_tile(lr1, gate + 1, Cfg.T_EMPTY)

## Ряды контейнеров с проездами для танков
static func _container_depot(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int) -> void:
	var r := r0
	while r <= r1 - 1:
		for c in range(c0, c1 + 1):
			if (c - c0) % 3 != 2:
				map.set_tile(r, c, Cfg.T_WALL if rng.nextf() < 0.4 else Cfg.T_BRICK)
		r += 3 # проезд шириной 2 тайла

## Городской парк с прудом, аллеями и памятниками
static func _park(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		ground: int) -> void:
	_fill(map, r0, r1, c0, c1, ground)
	var mr := (r0 + r1) / 2
	var mc := (c0 + c1) / 2

	# Пешеходные аллеи крестом
	_fill(map, mr - 1, mr, c0, c1, Cfg.T_EMPTY)
	_fill(map, r0, r1, mc - 1, mc, Cfg.T_EMPTY)

	# Пруд в одном из секторов парка
	if r1 - r0 >= 6 and c1 - c0 >= 6 and rng.nextf() < 0.65:
		var pr := r0 + 1 + int(rng.nextf() * float(r1 - r0 - 4))
		var pc := c0 + 1 + int(rng.nextf() * float(c1 - c0 - 4))
		_fill(map, pr, pr + 2, pc, pc + 3, Cfg.T_WATER)
		# Песчаный берег вокруг пруда
		for dr in range(-1, 4):
			for dc in range(-1, 5):
				var tr: int = pr + int(dr)
				var tc: int = pc + int(dc)
				if tr >= r0 and tr <= r1 and tc >= c0 and tc <= c1:
					if map.get_tile(tr, tc) == ground:
						map.set_tile(tr, tc, Cfg.T_SAND)

	# Деревья вдоль дорожек
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if map.get_tile(r, c) != ground:
				continue
			var q := rng.nextf()
			if q < 0.24:
				map.set_tile(r, c, Cfg.T_TREE)
			elif q < 0.28:
				map.set_tile(r, c, Cfg.T_BRICK)

	# Беседка или памятник на перекрёстке аллей
	map.set_tile(mr, mc, Cfg.T_WALL)

## Торжественная площадь с памятником и колоннадой
static func _grand_plaza(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	_fill(map, r0, r1, c0, c1, yard)
	var mr := (r0 + r1) / 2
	var mc := (c0 + c1) / 2

	# Центральный монумент (2x2 бетон)
	_fill(map, mr - 1, mr, mc - 1, mc, Cfg.T_WALL)

	# 4 декоративных клумбы по диагоналям
	for dr in [-3, 2]:
		for dc in [-3, 2]:
			var kr: int = mr + int(dr)
			var kc: int = mc + int(dc)
			if kr >= r0 + 1 and kr + 1 <= r1 - 1 and kc >= c0 + 1 and kc + 1 <= c1 - 1:
				_fill(map, kr, kr + 1, kc, kc + 1, Cfg.T_GRASS)
				map.set_tile(kr, kc, Cfg.T_TREE)

## Старая площадь для совместимости
static func _plaza(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		yard: int) -> void:
	_grand_plaza(map, rng, r0, r1, c0, c1, yard)

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
