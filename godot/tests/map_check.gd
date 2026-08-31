# ============================================================================
# map_check.gd — измерения городской сетки.
#
# «Дороги должны быть непрерывны» — утверждение, которое либо измеряется,
# либо остаётся вкусовщиной. Здесь считается, какая доля асфальта связна
# между собой, сколько на карте мостов и сколько перекрёстков.
# ============================================================================
extends Node

var failures := 0

func _ready() -> void:
	await get_tree().process_frame
	print("режим        асфальт  в сети  перекрёстков  переправ")
	for mode in ["ffa", "koth", "ctf", "defense"]:
		for level in [1, 2, 3, 4, 5]:
			var lvl := LevelGen.generate(level, mode)
			var map: GameMap = lvl["map"]
			var r := _road_stats(map)
			var mark := ""
			if int(r["bridges"]) > LevelGen.MAX_BRIDGES:
				mark = "   ПРЕВЫШЕНО"
				failures += 1
			if float(r["share"]) < 0.70:
				mark += "   СЕТКА РВАНАЯ"
				failures += 1
			print("  %-8s ур.%d  %5d  %5.1f%%  %6d  %6d%s" % [
				mode, level, r["total"], float(r["share"]) * 100.0,
				r["crossings"], r["bridges"], mark])
	print("проблем: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Связность асфальта, число перекрёстков и мостов.
func _road_stats(map: GameMap) -> Dictionary:
	var cols := map.cols
	var rows := map.rows
	var is_road := func(r: int, c: int) -> bool:
		if r < 0 or c < 0 or r >= rows or c >= cols:
			return false
		var t := map.get_tile(r, c)
		return t == Cfg.T_ROAD or t == Cfg.T_BRIDGE

	var total := 0
	var bridge_tiles := 0
	var crossings := 0
	for r in rows:
		for c in cols:
			var t := map.get_tile(r, c)
			if t == Cfg.T_BRIDGE:
				bridge_tiles += 1
			if not is_road.call(r, c):
				continue
			total += 1
			# Перекрёсток: асфальт со всех четырёх сторон.
			if is_road.call(r - 1, c) and is_road.call(r + 1, c) \
					and is_road.call(r, c - 1) and is_road.call(r, c + 1):
				crossings += 1

	# Заливка от первой найденной клетки: доля, попавшая в главную сеть.
	var seen := {}
	var best := 0
	var sizes := []
	for r in rows:
		for c in cols:
			if not is_road.call(r, c) or seen.has(r * cols + c):
				continue
			var size := 0
			var stack := [r * cols + c]
			seen[r * cols + c] = true
			while not stack.is_empty():
				var i: int = stack.pop_back()
				size += 1
				var rr := i / cols
				var cc := i % cols
				for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var nr: int = rr + int(d[0])
					var nc: int = cc + int(d[1])
					if not is_road.call(nr, nc):
						continue
					var ni := nr * cols + nc
					if seen.has(ni):
						continue
					seen[ni] = true
					stack.append(ni)
			best = maxi(best, size)
			sizes.append(size)

	sizes.sort()
	sizes.reverse()
	# Переправа — связный кусок моста, а не отдельный тайл: один мост через
	# реку занимает их два-три десятка.
	var seen_b := {}
	var spans := 0
	for r in rows:
		for c in cols:
			var i0 := r * cols + c
			if map.get_tile(r, c) != Cfg.T_BRIDGE or seen_b.has(i0):
				continue
			spans += 1
			var st := [i0]
			seen_b[i0] = true
			while not st.is_empty():
				var cur: int = st.pop_back()
				var cr := cur / cols
				var cc := cur % cols
				for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var nr: int = cr + int(d[0])
					var nc: int = cc + int(d[1])
					if nr < 0 or nc < 0 or nr >= rows or nc >= cols:
						continue
					if map.get_tile(nr, nc) != Cfg.T_BRIDGE:
						continue
					var ni := nr * cols + nc
					if seen_b.has(ni):
						continue
					seen_b[ni] = true
					st.append(ni)

	return {
		"total": total, "bridges": spans, "bridge_tiles": bridge_tiles,
		"crossings": crossings,
		"share": float(best) / float(maxi(1, total)),
		"top": sizes.slice(0, 5),
	}
