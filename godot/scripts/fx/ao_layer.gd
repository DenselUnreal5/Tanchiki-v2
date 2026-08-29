# ============================================================================
# ao_layer.gd — затенение у стен и в углах (двумерный аналог AO).
#
# Настоящий SSAO здесь невозможен: он читает буфер глубины и нормалей, а у
# двумерной сцены их нет. Но исходные данные для перекрытия у нас лучше, чем
# у 3D: известна вся карта. Поэтому считаем карту перекрытия прямо по тайлам.
#
# Как это работает:
#   1. Маска препятствий: стена и кирпич = 1, остальное = 0.
#   2. Взвешенное усреднение 3×3 — в вогнутом углу соседей-стен больше,
#      значит и затенение сильнее. Это ровно то, что делает AO.
#   3. Из результата вычитается сама стена: тень нужна на полу рядом,
#      а не на верхушке стены.
#   4. Текстура размером «пиксель на тайл» растягивается на всю карту,
#      мягкость даёт билинейная фильтрация видеокарты — блюр не нужен.
#
# Пересчёт — только когда карта изменилась (пули ломают кирпич), и не чаще
# чем раз в 30 кадров.
# ============================================================================
class_name AoLayer
extends RefCounted

## Насколько тёмным получается затенение в самом глухом углу.
const STRENGTH := 0.45
## Насколько ослабляется тень на самой стене.
const SELF_SHADING := 0.55
## Минимальный интервал между пересчётами, кадров.
const REBUILD_COOLDOWN := 30

var _tex: ImageTexture
var _img: Image
var _version := -1
var _cooldown := 0

## Актуальная текстура перекрытия для карты.
func texture(map: GameMap) -> ImageTexture:
	if _cooldown > 0:
		_cooldown -= 1
	if _tex == null or (map.version != _version and _cooldown <= 0):
		_rebuild(map)
		_version = map.version
		_cooldown = REBUILD_COOLDOWN
	return _tex

func _rebuild(map: GameMap) -> void:
	var cols := map.cols
	var rows := map.rows
	var count := cols * rows

	# Маска препятствий одним проходом.
	var solid := PackedFloat32Array()
	solid.resize(count)
	for r in rows:
		for c in cols:
			solid[r * cols + c] = 1.0 if GameMap.is_solid_tile(map.get_tile(r, c)) else 0.0

	# Картинка собирается сразу в байтовый буфер: 8000 вызовов set_pixel
	# на большой карте давали заметный рывок при каждом разрушенном кирпиче.
	var data := PackedByteArray()
	data.resize(count * 4)
	for r in rows:
		for c in cols:
			var sum := 0.0
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					var nr := r + dr
					var nc := c + dc
					var v := 1.0  # за краем карты — стена
					if nr >= 0 and nr < rows and nc >= 0 and nc < cols:
						v = solid[nr * cols + nc]
					# Диагонали дают меньший вклад, чем стороны.
					if dr == 0 and dc == 0:
						sum += v
					elif dr == 0 or dc == 0:
						sum += v * 0.7
					else:
						sum += v * 0.45
			var i := r * cols + c
			var occ := clampf(sum / 5.6 - solid[i] * SELF_SHADING, 0.0, 1.0)
			# RGB нулевые: затенение — это чёрный с переменной прозрачностью.
			data[i * 4 + 3] = int(occ * STRENGTH * 255.0)

	_img = Image.create_from_data(cols, rows, false, Image.FORMAT_RGBA8, data)
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)
