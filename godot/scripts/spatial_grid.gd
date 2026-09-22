class_name SpatialGrid
extends RefCounted

const CELL := 96.0

var _cells := {}

static func _key(x: float, y: float) -> Vector2i:
	return Vector2i(int(floor(x / CELL)), int(floor(y / CELL)))

func rebuild(tanks: Array) -> void:
	_cells.clear()
	for t in tanks:
		if not t.alive:
			continue
		var k := _key(t.x, t.y)
		if _cells.has(k):
			_cells[k].append(t)
		else:
			_cells[k] = [t]

func query(x: float, y: float, r: float) -> Array:
	var out := []
	# floor(r/CELL)+1 — минимальный радиус колец ячеек, гарантированно
	# захватывающий всё в пределах r от (x,y), даже если (x,y) у самого
	# края своей ячейки. ceil(r/CELL)+1 (как было раньше) даёт лишнее
	# кольцо почти всегда — например при r=32, CELL=96 сканировал 5x5=25
	# ячеек вместо необходимых 3x3=9.
	var span := int(floor(r / CELL)) + 1
	var kx := int(floor(x / CELL))
	var ky := int(floor(y / CELL))
	for dx in range(-span, span + 1):
		for dy in range(-span, span + 1):
			var cell = _cells.get(Vector2i(kx + dx, ky + dy))
			if cell != null:
				out.append_array(cell)
	return out
