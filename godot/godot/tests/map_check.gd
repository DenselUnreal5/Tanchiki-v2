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
	print("локация  режим       асфальт  в сети  перемычек  переправ  проходимо")
	for loc in Locations.ORDER:
		for mode in ["ffa", "koth", "ctf", "defense"]:
			for level in [1, 2, 3, 4, 5]:
				var lvl := LevelGen.generate(level, mode, -1, loc)
				var map: GameMap = lvl["map"]
				var r := _road_stats(map)
				var walk := _walkable_share(map)
				var mark := ""
				if String(lvl["location"]) != loc:
					mark += "   ЛОКАЦИЯ НЕ ТА"
					failures += 1
				if int(r["bridges"]) > LevelGen.MAX_BRIDGES:
					mark += "   ПЕРЕПРАВ БОЛЬШЕ ЧЕТЫРЁХ"
					failures += 1
				# Дорожная сеть должна быть связной там, где дороги вообще
				# есть. В джунглях их мало по замыслу, поэтому порог ниже
				# применяется только к сколько-нибудь заметной сети.
				if r["total"] > 200 and float(r["share"]) < 0.70:
					mark += "   СЕТКА РВАНАЯ"
					failures += 1
				# А вот проходимость карты обязательна везде: остров, куда
				# не доехать, ломает и ботов, и режимные точки.
				if walk < 0.97:
					mark += "   КАРТА РАЗОРВАНА"
					failures += 1
				# Перемычек — прямой счёт. Тайловые метрики («узлов», «петель»)
				# отброшены намеренно: у двухполосной дороги почти каждый тайл
				# имеет три соседа, вся сеть слипается в один узел, и число
				# мерило бы ширину дороги, а не топологию. Каждая перемычка
				# соединяет две уже связанные улицы, то есть добавляет ровно
				# одну независимую петлю и две Т-образные развилки.
				print("  %-7s %-8s ур.%d %5d  %5.1f%%  %8d  %5d  %6.1f%%%s" % [
					loc, mode, level, r["total"], float(r["share"]) * 100.0,
					int(lvl["plan"]["links"].size()), r["bridges"],
					walk * 100.0, mark])
	print("проблем: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Доля проходимой земли, попавшей в главную связную область. Считается
## заливкой от первой проходимой клетки: карта, распавшаяся на острова,
## выглядит на глаз нормально и ломается только в игре.
func _walkable_share(map: GameMap) -> float:
	var total := 0
	var start := Vector2i(-1, -1)
	for r in map.rows:
		for c in map.cols:
			if GameMap.is_drivable_tile(map.get_tile(r, c)):
				total += 1
				if start.x < 0:
					start = Vector2i(r, c)
	if total == 0:
		return 0.0
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var seen := {}
	var stack: Array[Vector2i] = [start]
	seen[start.x * map.cols + start.y] = true
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in dirs:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= map.rows or n.y >= map.cols:
				continue
			var key: int = n.x * map.cols + n.y
			if seen.has(key):
				continue
			if not GameMap.is_drivable_tile(map.get_tile(n.x, n.y)):
				continue
			seen[key] = true
			stack.append(n)
	return float(seen.size()) / float(total)

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
	var forks := 0
	var edges := 0
	for r in rows:
		for c in cols:
			var t := map.get_tile(r, c)
			if t == Cfg.T_BRIDGE:
				bridge_tiles += 1
			if not is_road.call(r, c):
				continue
			total += 1
			# Рёбра считаем по двум направлениям из четырёх: иначе каждое
			# ребро попало бы в счёт дважды.
			if is_road.call(r + 1, c):
				edges += 1
			if is_road.call(r, c + 1):
				edges += 1
			var deg := 0
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				if is_road.call(r + int(d[0]), c + int(d[1])):
					deg += 1
			# Перекрёсток: асфальт со всех четырёх сторон.
			if deg == 4:
				crossings += 1
			# Развилка: ровно три выхода. Это и есть «третий путь», которого
			# в чистой прямоугольной сетке нет нигде, кроме кромки квартала.
			elif deg == 3:
				forks += 1

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

	# Узлы сети — связные группы тайлов со степенью 3 и выше, а не отдельные
	# тайлы. Считать по тайлам нельзя: у широкой дороги их десятки на один
	# перекрёсток, и метрика мерила бы ширину дороги, а не топологию.
	var nodes := 0
	var seen_n := {}
	for r in rows:
		for c in cols:
			var i0 := r * cols + c
			if seen_n.has(i0) or not is_road.call(r, c):
				continue
			var deg0 := 0
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				if is_road.call(r + int(d[0]), c + int(d[1])):
					deg0 += 1
			if deg0 < 3:
				continue
			nodes += 1
			var stn := [i0]
			seen_n[i0] = true
			while not stn.is_empty():
				var cur: int = stn.pop_back()
				var cr := cur / cols
				var cc2 := cur % cols
				for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var nr: int = cr + int(d[0])
					var nc: int = cc2 + int(d[1])
					if not is_road.call(nr, nc):
						continue
					var dn := 0
					for e in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
						if is_road.call(nr + int(e[0]), nc + int(e[1])):
							dn += 1
					if dn < 3:
						continue
					var ni := nr * cols + nc
					if seen_n.has(ni):
						continue
					seen_n[ni] = true
					stn.append(ni)

	# Цикломатическое число графа дорог: рёбра минус вершины плюс компоненты.
	# Это и есть «сколько независимых петель», то есть сколько раз можно
	# доехать до той же точки другим путём.
	return {
		"nodes": nodes,
		"loops": maxi(0, edges - total + 1),
		"forks": forks,
		"total": total, "bridges": spans, "bridge_tiles": bridge_tiles,
		"crossings": crossings,
		"share": float(best) / float(maxi(1, total)),
		"top": sizes.slice(0, 5),
	}
