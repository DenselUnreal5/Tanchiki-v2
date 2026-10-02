class_name WaterGen
extends RefCounted

const MAX_BRIDGES := 32
const SINGLE_RIVER_MAX_BRIDGES := 4
const MIN_CITY_BRIDGE_SPACING := 7

static func carve_city_canals(map: GameMap, rng: Rng, cols: int, rows: int,
		h_streets: Array) -> void:
	# 3 до 5 узких речек/каналов
	var num_rivers: int = 3 + int(rng.nextf() * 3.0)
	var margin := 8
	var available_w: float = float(cols - 2 * margin)
	var slot_w: float = available_w / float(num_rivers)

	var sorted_streets := h_streets.duplicate()
	sorted_streets.sort_custom(func(a, b): return int(a["pos"]) < int(b["pos"]))

	for i in num_rivers:
		var slot_min: float = float(margin) + float(i) * slot_w
		var base: float = slot_min + slot_w * (0.32 + rng.nextf() * 0.36)

		# Река шириной от 1 до 3 тайлов
		var river_w: int = 1 + int(rng.nextf() * 3.0)
		var half_l: int = (river_w - 1) / 2
		var half_r: int = river_w / 2

		var amp: float = 1.4 + rng.nextf() * 1.8
		var freq: float = 0.045 + rng.nextf() * 0.035
		var phase: float = rng.nextf() * TAU
		var freq2: float = freq * (2.1 + rng.nextf() * 0.4)
		var phase2: float = rng.nextf() * TAU

		var left := PackedInt32Array()
		var right := PackedInt32Array()
		left.resize(rows)
		right.resize(rows)

		for r in rows:
			var centre: float = base + sin(float(r) * freq + phase) * amp + sin(float(r) * freq2 + phase2) * (amp * 0.3)
			var c_mid: int = int(roundf(centre))
			var c0: int = clampi(c_mid - half_l, 1, cols - 2)
			var c1: int = clampi(c_mid + half_r, 1, cols - 2)
			left[r] = c0
			right[r] = c1

			if r <= 0 or r >= rows - 1:
				continue
			for c in range(c0, c1 + 1):
				map.set_tile(r, c, Cfg.T_WATER)

		# Мосты вдоль данного канала: частые, но строго не ближе MIN_CITY_BRIDGE_SPACING
		var placed_rows: Array[int] = []
		for st in sorted_streets:
			var pos: int = int(st["pos"])
			var sw: int = int(st.get("w", 2))
			if pos < 2 or pos + sw > rows - 2:
				continue

			var too_close := false
			for br in placed_rows:
				if absi(pos - br) < MIN_CITY_BRIDGE_SPACING:
					too_close = true
					break
			if too_close:
				continue

			# Гораздо меньшие мосты: толщиной 1-2 ряда, ширина русла + 1 тайл на въезды
			var bw: int = mini(2, sw)
			for dr in bw:
				var r: int = pos + dr
				if r <= 0 or r >= rows - 1:
					continue
				var bc0: int = maxi(1, left[r] - 1)
				var bc1: int = mini(cols - 2, right[r] + 1)
				for c in range(bc0, bc1 + 1):
					if map.get_tile(r, c) != Cfg.T_WALL:
						map.set_tile(r, c, Cfg.T_BRIDGE)
				if bc0 > 1 and map.get_tile(r, bc0 - 1) == Cfg.T_BRICK:
					map.set_tile(r, bc0 - 1, Cfg.T_ROAD)
				if bc1 < cols - 2 and map.get_tile(r, bc1 + 1) == Cfg.T_BRICK:
					map.set_tile(r, bc1 + 1, Cfg.T_ROAD)

			placed_rows.append(pos)

		# Если на длинном отрезке канала нет моста (> 14 тайлов), добавляем аккуратный переход
		var last_r := 1
		for br in placed_rows:
			if br - last_r >= 14:
				var aux_r := (last_r + br) / 2
				_place_aux_bridge(map, aux_r, left, right, cols, rows)
			last_r = br
		if (rows - 2) - last_r >= 14:
			var aux_r2 := (last_r + rows - 2) / 2
			_place_aux_bridge(map, aux_r2, left, right, cols, rows)

static func _place_aux_bridge(map: GameMap, r: int, left: PackedInt32Array,
		right: PackedInt32Array, cols: int, rows: int) -> void:
	if r <= 1 or r >= rows - 2:
		return
	var bc0: int = maxi(1, left[r] - 1)
	var bc1: int = mini(cols - 2, right[r] + 1)
	for c in range(bc0, bc1 + 1):
		if map.get_tile(r, c) != Cfg.T_WALL:
			map.set_tile(r, c, Cfg.T_BRIDGE)
	if bc0 > 1 and map.get_tile(r, bc0 - 1) == Cfg.T_BRICK:
		map.set_tile(r, bc0 - 1, Cfg.T_ROAD)
	if bc1 < cols - 2 and map.get_tile(r, bc1 + 1) == Cfg.T_BRICK:
		map.set_tile(r, bc1 + 1, Cfg.T_ROAD)

static func carve(map: GameMap, rng: Rng, cols: int, rows: int,
		h_streets: Array, width: float = 1.0) -> void:
	if width <= 0.0:
		return
	var base := float(cols) * (0.38 + rng.nextf() * 0.24)
	var amp := float(cols) * (0.04 + rng.nextf() * 0.05)
	var freq := 0.055 + rng.nextf() * 0.05
	var phase := rng.nextf() * TAU
	var half := maxi(1, int(round(float(2 + int(rng.nextf() * 2.0)) * width)))

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

	shore(map, 1, rows - 2, int(base - amp) - half - 2, int(base + amp) + half + 2)

	var usable := []
	for st in h_streets:
		var pos: int = int(st["pos"])
		if pos >= 2 and pos + int(st["w"]) <= rows - 2:
			usable.append(st)
	if usable.is_empty():
		# Нет уличной сетки (органический рельеф, см. OrganicGen) или ни
		# одна улица не подошла по границам — переправы всё равно нужны:
		# T_WATER не входит в is_drivable_tile, а
		# GameMap.ensure_connectivity() намеренно не прокладывает
		# аварийный коридор через воду, так что без моста река
		# безвозвратно режет карту пополам.
		var count := clampi((rows - 4) / 14, 1, SINGLE_RIVER_MAX_BRIDGES)
		for i in count:
			var pos: int = 2 + int(round(float(i + 1) * float(rows - 4) / float(count + 1)))
			usable.append({"pos": pos, "w": 2})
	var want: int = mini(SINGLE_RIVER_MAX_BRIDGES, usable.size())
	for i in want:
		var idx := 0
		if want > 1:
			idx = int(round(float(i) * float(usable.size() - 1) / float(want - 1)))
		_bridge(map, usable[idx], left, right, cols)

## Архипелаг для локации "shore": залив/океан на одной стороне карты
## (не река через центр — сплошная водная полоса у левого или правого
## края, волнистая береговая линия) + несколько островов, каждый со своим
## деревянным мостом на материк. Мосты кладутся СРАЗУ при постройке
## острова, а не полагаются на общий аварийный рубеж
## GameMap.ensure_connectivity() — тот намеренно не режет коридор через
## T_WATER (_carve_put пропускает воду), так что без явного моста остров
## остался бы недостижим навсегда.
static func carve_archipelago(map: GameMap, rng: Rng, cols: int, rows: int,
		loc: Dictionary) -> void:
	var frac_min: float = float(loc.get("coast_frac_min", 0.18))
	var frac_max: float = float(loc.get("coast_frac_max", frac_min))
	var frac: float = rng.range_f(frac_min, frac_max)
	var from_left := rng.nextf() < 0.5
	var band_w := float(cols) * frac
	var base := band_w * (0.75 + rng.nextf() * 0.3)
	var amp := band_w * 0.26
	var freq := 0.05 + rng.nextf() * 0.04
	var phase := rng.nextf() * TAU

	# Береговая линия: волнистая граница между морем (у выбранного края)
	# и материком — тот же приём синусоиды, что и у WaterGen.carve() для
	# рек, только граница у края карты, а не полосой через середину.
	var boundary := PackedInt32Array()
	boundary.resize(rows)
	for r in range(1, rows - 1):
		var edge_c: int = int(round(base + sin(float(r) * freq + phase) * amp))
		edge_c = clampi(edge_c, 2, int(band_w * 1.6))
		boundary[r] = edge_c
		if from_left:
			for c in range(1, mini(cols - 2, edge_c) + 1):
				map.set_tile(r, c, Cfg.T_WATER)
		else:
			for c in range(maxi(1, cols - 1 - edge_c), cols - 1):
				map.set_tile(r, c, Cfg.T_WATER)

	var island_count := 2 + int(rng.nextf() * 3.0)
	var placed: Array = []
	var attempts := 0
	while placed.size() < island_count and attempts < 200:
		attempts += 1
		var r := 6 + int(rng.nextf() * float(maxi(1, rows - 12)))
		var edge_c: int = boundary[r]
		var margin := 3.0
		var reach := float(edge_c) - margin * 2.0
		if reach < 4.0:
			continue
		var depth := margin + rng.nextf() * reach
		var ic: float
		if from_left:
			ic = depth
		else:
			ic = float(cols - 1) - depth
		var radius := 2.5 + rng.nextf() * 2.0
		var too_close := false
		for p in placed:
			var pc: float = p["c"]
			var pr: float = p["r"]
			var pradius: float = p["radius"]
			if Vector2(ic - pc, float(r) - pr).length() < radius + pradius + 6.0:
				too_close = true
				break
		if too_close:
			continue
		_stamp_island(map, ic, float(r), radius)
		# Мост идёт не до самого края карты, а чуть за береговую линию —
		# на пару тайлов вглубь суши, чтобы гарантированно упереться в
		# сухую землю, а не в кромку воды на волнистой границе.
		var target_c: float = float(edge_c) + 3.0 if from_left else float(cols - 1 - edge_c) - 3.0
		RoadNet.paint_thick_line(map, ic, float(r), target_c, float(r), 2.0, Cfg.T_BRIDGE)
		if radius > 4.0:
			var pier_len := 5.0 + radius
			var target_r: float
			if float(r) < float(rows) * 0.5:
				target_r = maxf(3.0, float(r) - pier_len)
			else:
				target_r = minf(float(rows) - 4.0, float(r) + pier_len)
			RoadNet.paint_thick_line(map, ic, float(r), ic, target_r, 1.5, Cfg.T_BRIDGE)
		placed.append({"c": ic, "r": float(r), "radius": radius})
	shore(map, 1, rows - 2, 1, cols - 2)

static func _stamp_island(map: GameMap, cx: float, cy: float, radius: float) -> void:
	var box := int(ceil(radius)) + 1
	var icx := int(round(cx))
	var icy := int(round(cy))
	for dr in range(-box, box + 1):
		for dc in range(-box, box + 1):
			var r := icy + dr
			var c := icx + dc
			if r <= 0 or c <= 0 or r >= map.rows - 1 or c >= map.cols - 1:
				continue
			if sqrt(float(dr * dr + dc * dc)) <= radius:
				map.set_tile(r, c, Cfg.T_EMPTY)

static func shore(map: GameMap, r0: int, r1: int, c0: int, c1: int) -> void:
	for r in range(maxi(1, r0), mini(map.rows - 2, r1) + 1):
		for c in range(maxi(1, c0), mini(map.cols - 2, c1) + 1):
			var here := map.get_tile(r, c)
			if here == Cfg.T_WATER or here == Cfg.T_ROAD or here == Cfg.T_BRIDGE:
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

static func _bridge(map: GameMap, street: Dictionary, left: PackedInt32Array,
		right: PackedInt32Array, cols: int) -> void:
	var pos: int = int(street["pos"])
	var w: int = int(street["w"])
	for dr in w:
		var r: int = pos + dr
		if r <= 0 or r >= map.rows - 1:
			continue
		var c0: int = maxi(1, left[r] - 2)
		var c1: int = mini(cols - 2, right[r] + 2)
		for c in range(c0, c1 + 1):
			if map.get_tile(r, c) == Cfg.T_WALL:
				continue
			map.set_tile(r, c, Cfg.T_BRIDGE)
