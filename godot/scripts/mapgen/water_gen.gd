class_name WaterGen
extends RefCounted

const MAX_BRIDGES := 4

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
		return
	var want: int = mini(MAX_BRIDGES, usable.size())
	for i in want:
		var idx := 0
		if want > 1:
			idx = int(round(float(i) * float(usable.size() - 1) / float(want - 1)))
		_bridge(map, usable[idx], left, right, cols)

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
