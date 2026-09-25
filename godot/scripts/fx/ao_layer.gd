class_name AoLayer
extends RefCounted

const STRENGTH := 0.45
const SELF_SHADING := 0.55

var _tex: ImageTexture
var _img: Image
var _solid := PackedFloat32Array()
var _data := PackedByteArray()
var _cols := 0
var _rows := 0
var _epoch := -1
var _seen_changes := 0

## Полный пересчёт — только в начале матча и при замене карты целиком;
## дальше по журналу GameMap.changes пересчитываются лишь клетки 3×3
## вокруг изменившихся (раньше каждое разрушение стоило ~20 мс, и
## обновление вдобавок откладывалось на 30 тиков).
func texture(map: GameMap) -> ImageTexture:
	if _tex == null or map.changes_epoch != _epoch or map.cols != _cols or map.rows != _rows:
		_rebuild(map)
		_epoch = map.changes_epoch
		_seen_changes = map.changes.size()
	elif map.changes.size() != _seen_changes:
		_apply_changes(map)
	return _tex

func _rebuild(map: GameMap) -> void:
	_cols = map.cols
	_rows = map.rows
	var count := _cols * _rows

	_solid = PackedFloat32Array()
	_solid.resize(count)
	for r in _rows:
		for c in _cols:
			_solid[r * _cols + c] = 1.0 if GameMap.is_solid_tile(map.get_tile(r, c)) else 0.0

	_data = PackedByteArray()
	_data.resize(count * 4)
	for r in _rows:
		for c in _cols:
			_compute(r, c)
	_upload()

func _apply_changes(map: GameMap) -> void:
	var n := map.changes.size()
	var touched := false
	for k in range(_seen_changes, n):
		var i: int = map.changes[k]
		if i < 0 or i >= _solid.size():
			continue
		var s := 1.0 if GameMap.is_solid_tile(map.tiles[i]) else 0.0
		if s == _solid[i]:
			continue
		_solid[i] = s
		var r := i / _cols
		var c := i % _cols
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				var nr := r + dr
				var nc := c + dc
				if nr >= 0 and nr < _rows and nc >= 0 and nc < _cols:
					_compute(nr, nc)
		touched = true
	_seen_changes = n
	if touched:
		_upload()

func _compute(r: int, c: int) -> void:
	var sum := 0.0
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var nr := r + dr
			var nc := c + dc
			var v := 1.0
			if nr >= 0 and nr < _rows and nc >= 0 and nc < _cols:
				v = _solid[nr * _cols + nc]
			if dr == 0 and dc == 0:
				sum += v
			elif dr == 0 or dc == 0:
				sum += v * 0.7
			else:
				sum += v * 0.45
	var i := r * _cols + c
	var occ := clampf(sum / 5.6 - _solid[i] * SELF_SHADING, 0.0, 1.0)
	_data[i * 4 + 3] = int(occ * STRENGTH * 255.0)

func _upload() -> void:
	_img = Image.create_from_data(_cols, _rows, false, Image.FORMAT_RGBA8, _data)
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)
