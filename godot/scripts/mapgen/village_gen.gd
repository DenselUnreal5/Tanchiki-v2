class_name VillageGen
extends RefCounted

## Плотная кластерная застройка: дротик-размещение мелких построек с
## гарантированным зазором ≥1 тайл (implicit-аллея) вместо прямоугольной
## нарезки квартала, как у Districts. Связность внутри квартала держится
## построением + локальной проверкой, а не общим RoadNet.repair().

static func paint(map: GameMap, rng: Rng, r0: int, r1: int, c0: int, c1: int,
		ground: int, loc: Dictionary) -> void:
	_fill(map, r0, r1, c0, c1, ground)
	var ir0 := r0 + 1
	var ir1 := r1 - 1
	var ic0 := c0 + 1
	var ic1 := c1 - 1
	if ir1 < ir0 or ic1 < ic0:
		return

	var w := ic1 - ic0 + 1
	var h := ir1 - ir0 + 1
	var attempts := maxi(1, int(float(w * h) / 6.0))
	var placed: Array = []
	var placed_area := 0
	var target_area := int(float(w * h) * 0.6)

	for i in attempts:
		if placed_area >= target_area:
			break
		var bw := rng.range_i(2, 5)
		var bh := rng.range_i(2, 4)
		var br0 := ir0 + rng.range_i(0, maxi(1, h - bh + 1))
		var bc0 := ic0 + rng.range_i(0, maxi(1, w - bw + 1))
		var br1 := br0 + bh - 1
		var bc1 := bc0 + bw - 1
		if br1 > ir1 or bc1 > ic1:
			continue
		var overlaps := false
		for p in placed:
			if br0 - 1 <= int(p[1]) and br1 + 1 >= int(p[0]) \
					and bc0 - 1 <= int(p[3]) and bc1 + 1 >= int(p[2]):
				overlaps = true
				break
		if overlaps:
			continue
		_fill(map, br0, br1, bc0, bc1, Cfg.T_ADOBE)
		if bw >= 3 and bh >= 3 and rng.nextf() < 0.25:
			map.set_tile(br0 + bh / 2, bc0 + bw / 2, Cfg.T_WALL)
		placed.append([br0, br1, bc0, bc1])
		placed_area += bw * bh

	_ensure_block_connectivity(map, r0, r1, c0, c1, ground)

static func _ensure_block_connectivity(map: GameMap, r0: int, r1: int,
		c0: int, c1: int, ground: int) -> void:
	var seen := {}
	var stack: Array[Vector2i] = []
	var edge_cols: Array[int] = [c0, c1]
	for r in range(r0, r1 + 1):
		for c in edge_cols:
			if GameMap.is_drivable_tile(map.get_tile(r, c)):
				var key: int = r * map.cols + c
				if not seen.has(key):
					seen[key] = true
					stack.append(Vector2i(r, c))
	var edge_rows: Array[int] = [r0, r1]
	for c in range(c0, c1 + 1):
		for r in edge_rows:
			if GameMap.is_drivable_tile(map.get_tile(r, c)):
				var key: int = r * map.cols + c
				if not seen.has(key):
					seen[key] = true
					stack.append(Vector2i(r, c))

	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in dirs:
			var n: Vector2i = p + d
			if n.x < r0 or n.x > r1 or n.y < c0 or n.y > c1:
				continue
			var key: int = n.x * map.cols + n.y
			if seen.has(key):
				continue
			if not GameMap.is_drivable_tile(map.get_tile(n.x, n.y)):
				continue
			seen[key] = true
			stack.append(n)

	var visited := {}
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var key: int = r * map.cols + c
			if visited.has(key) or seen.has(key):
				continue
			if not GameMap.is_drivable_tile(map.get_tile(r, c)):
				continue
			var pocket: Array[Vector2i] = []
			var pstack: Array[Vector2i] = [Vector2i(r, c)]
			visited[key] = true
			while not pstack.is_empty():
				var p2: Vector2i = pstack.pop_back()
				pocket.append(p2)
				for d in dirs:
					var n: Vector2i = p2 + d
					if n.x < r0 or n.x > r1 or n.y < c0 or n.y > c1:
						continue
					var nk: int = n.x * map.cols + n.y
					if visited.has(nk) or seen.has(nk):
						continue
					if not GameMap.is_drivable_tile(map.get_tile(n.x, n.y)):
						continue
					visited[nk] = true
					pstack.append(n)
			_carve_to_reached(map, pocket, seen, ground)

static func _carve_to_reached(map: GameMap, pocket: Array, reached: Dictionary,
		ground: int) -> void:
	if pocket.is_empty():
		return
	var from: Vector2i = pocket[pocket.size() / 2]
	var best: Vector2i = from
	var best_d := 1 << 30
	for key in reached.keys():
		var r: int = int(key) / map.cols
		var c: int = int(key) % map.cols
		var d: int = (r - from.x) * (r - from.x) + (c - from.y) * (c - from.y)
		if d < best_d:
			best_d = d
			best = Vector2i(r, c)
	var c := from.y
	while c != best.y:
		map.set_tile(from.x, c, ground)
		c += 1 if best.y > c else -1
	var r := from.x
	while r != best.x:
		map.set_tile(r, best.y, ground)
		r += 1 if best.x > r else -1
	map.set_tile(best.x, best.y, ground)

static func _fill(map: GameMap, r0: int, r1: int, c0: int, c1: int, tile: int) -> void:
	for r in range(maxi(1, r0), mini(map.rows - 2, r1) + 1):
		for c in range(maxi(1, c0), mini(map.cols - 2, c1) + 1):
			map.set_tile(r, c, tile)
