# ============================================================================
# water_gen.gd — река, берега и мосты.
#
# Четвёртый этап конвейера, и он идёт последним из «природных»: река режет
# уже готовый город. Набережная получается там, где вода съела часть
# квартала, — так же, как в настоящем городе, выросшем вокруг реки.
# ============================================================================
class_name WaterGen
extends RefCounted

## Больше четырёх переправ на карту не бывает: мост — узкое место, за
## которое дерутся, а не одна из дюжины равнозначных дорог.
const MAX_BRIDGES := 4

## Прокладывает реку и мосты. h_streets — горизонтальные улицы из плана:
## по ним и ставятся переправы, чтобы мост продолжал улицу, а не обрывался
## посреди квартала.
static func carve(map: GameMap, rng: Rng, cols: int, rows: int, h_streets: Array) -> void:
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

	shore(map, 1, rows - 2, int(base - amp) - half - 2, int(base + amp) + half + 2)

	# Переправы выбираются не подряд и не случайно, а равномерно по всей
	# длине реки: иначе три моста рядом оставляли бы полкарты без переправы.
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

## Обводит воду песком.
##
## Асфальт песком не засыпается. Это не косметика: замер связности показал,
## что берег съедал соседние дорожные тайлы, и улица обрывалась — в главную
## сеть попадало 15–45% асфальта вместо почти всего.
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

## Кладёт мост на одну улицу: настил над водой плюс въезды на оба берега.
static func _bridge(map: GameMap, street: Dictionary, left: PackedInt32Array,
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
