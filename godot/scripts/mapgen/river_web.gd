class_name RiverWeb
extends RefCounted

# Rivers occupy block interiors, crossing streets at right angles. The graph
# has four wandering arms and additional alternate routes between those arms.
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const BRIDGE_BUDGET := 56 # Bounded mesh; reserve room for coast/other features.

static func carve(map: GameMap, rng: Rng, xs: Array, ys: Array, protected: Dictionary, density: int = 1) -> Dictionary:
	var nx := xs.size() - 1
	var ny := ys.size() - 1
	var nodes := {}
	var costs := {}
	for y in ny:
		for x in nx:
			var cell := Vector2i(x, y)
			if protected.has(cell): continue
			var lo := Vector2i(int(xs[x]) + 2, int(ys[y]) + 2)
			var hi := Vector2i(int(xs[x + 1]) - 2, int(ys[y + 1]) - 2)
			if hi.x < lo.x or hi.y < lo.y: continue
			nodes[cell] = Vector2i(rng.range_i(lo.x, hi.x + 1), rng.range_i(lo.y, hi.y + 1))
			costs[cell] = 1.0 + rng.nextf() * 3.5
	if nodes.size() < 6: return {}
	var hub := Vector2i(-1, -1)
	var best := INF
	for cell: Vector2i in nodes:
		var distance := Vector2(cell).distance_squared_to(Vector2(nx, ny) * 0.5)
		if distance < best:
			best = distance
			hub = cell
	var state := {"edges": {}, "cells": {}, "bridges": 0}
	var boundaries := [[], [], [], []]
	for cell: Vector2i in nodes:
		if cell.x == 0: boundaries[0].append(cell)
		if cell.x == nx - 1: boundaries[1].append(cell)
		if cell.y == 0: boundaries[2].append(cell)
		if cell.y == ny - 1: boundaries[3].append(cell)
	# Shuffle which arm goes first: even constrained small maps vary by seed.
	for side in rng.shuffled([0, 1, 2, 3]):
		var candidates: Array = boundaries[side]
		if candidates.is_empty(): continue
		var target: Vector2i = rng.pick(candidates)
		var path := _path(hub, target, nodes, costs, {}, 1.0)
		if not _commit(map, rng, path, nodes, state): continue
		var point: Vector2i = nodes[target]
		var end := point
		match int(side):
			0: end.x = 1
			1: end.x = map.cols - 2
			2: end.y = 1
			3: end.y = map.rows - 2
		_paint(map, _line(point, end), state)
	# Join existing arms via unused edges to form loops and extra junctions.
	var loops := 0
	for attempt in 64:
		if loops >= 3 + mini(1, maxi(0, density - 1)): break
		var cells: Array = state.cells.keys()
		if cells.size() < 4: break
		var a: Vector2i = rng.pick(cells)
		var b: Vector2i = rng.pick(cells)
		var distance := absi(a.x - b.x) + absi(a.y - b.y)
		if distance < 4 or distance > 10: continue
		var path := _path(a, b, nodes, costs, state.edges, 8.0)
		var new_edges := 0
		for i in range(1, path.size()):
			if not state.edges.has(_edge(path[i - 1], path[i])): new_edges += 1
		if new_edges < 3: continue
		if _commit(map, rng, path, nodes, state): loops += 1
	var junctions := 0
	for cell: Vector2i in state.cells:
		var degree := 0
		for direction: Vector2i in DIRECTIONS:
			if state.edges.has(_edge(cell, cell + direction)): degree += 1
		if degree >= 3: junctions += 1
	return {"nodes": state.cells.size(), "edges": state.edges.size(), "junctions": junctions,
		"loops": maxi(0, state.edges.size() - state.cells.size() + 1), "bridges": state.bridges}

static func _edge(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x > b.x or (a.x == b.x and a.y > b.y): return Vector4i(b.x, b.y, a.x, a.y)
	return Vector4i(a.x, a.y, b.x, b.y)

static func _path(start: Vector2i, goal: Vector2i, nodes: Dictionary, costs: Dictionary, existing: Dictionary, penalty: float) -> Array[Vector2i]:
	var open: Array[Vector2i] = [start]
	var distance := {start: 0.0}
	var previous := {}
	while not open.is_empty():
		var index := 0
		var best := INF
		for i in open.size():
			var point: Vector2i = open[i]
			var score: float = distance[point] + absi(goal.x - point.x) + absi(goal.y - point.y)
			if score < best:
				best = score
				index = i
		var current: Vector2i = open[index]
		open.remove_at(index)
		if current == goal:
			var result: Array[Vector2i] = [goal]
			while current != start:
				current = previous[current]
				result.push_front(current)
			return result
		for direction: Vector2i in DIRECTIONS:
			var next := current + direction
			if not nodes.has(next): continue
			var cost: float = (float(costs[current]) + float(costs[next])) * 0.5
			if existing.has(_edge(current, next)): cost *= penalty
			var candidate: float = distance[current] + cost
			if candidate >= float(distance.get(next, INF)): continue
			distance[next] = candidate
			previous[next] = current
			if not open.has(next): open.append(next)
	return []

static func _commit(map: GameMap, rng: Rng, path: Array[Vector2i], nodes: Dictionary, state: Dictionary) -> bool:
	if path.size() < 2: return false
	var tiles := {}
	for i in range(1, path.size()):
		if state.edges.has(_edge(path[i - 1], path[i])): continue
		var a: Vector2i = nodes[path[i - 1]]
		var b: Vector2i = nodes[path[i]]
		# Bend in the block interior, never along a road or at its junction.
		var bend := Vector2i(a.x, b.y) if rng.nextf() < 0.5 else Vector2i(b.x, a.y)
		for point in _line(a, bend) + _line(bend, b): tiles[point] = true
	if not _paint(map, tiles.keys(), state): return false
	for i in range(1, path.size()): state.edges[_edge(path[i - 1], path[i])] = true
	for cell in path: state.cells[cell] = true
	return true

static func _line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	while a != b:
		a += Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		out.append(a)
	return out

static func _paint(map: GameMap, points: Array, state: Dictionary) -> bool:
	var crossings := 0
	for point: Vector2i in points:
		if map.get_tile(point.y, point.x) == Cfg.T_ROAD: crossings += 1
	if int(state.bridges) + crossings > BRIDGE_BUDGET: return false
	for point: Vector2i in points:
		var tile := map.get_tile(point.y, point.x)
		if tile == Cfg.T_ROAD: map.set_tile(point.y, point.x, Cfg.T_BRIDGE)
		elif tile != Cfg.T_BRIDGE and tile != Cfg.T_WALL: map.set_tile(point.y, point.x, Cfg.T_WATER)
	state.bridges += crossings
	return true
