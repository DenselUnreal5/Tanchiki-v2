# ============================================================================
# surfaces.gd — свойства покрытий под гусеницами.
#
# До появления города все проходимые тайлы вели себя одинаково. Теперь
# покрытие влияет на ход танка и на то, что летит из-под гусениц:
# по асфальту машина идёт ровно и быстро, по газону вязнет, по песку
# буксует сильнее всего.
#
# Скорость задаётся множителем к ускорению. Предельная скорость танка равна
# accel / (1 - FRICTION), то есть множитель к ускорению — это ровно
# множитель к предельной скорости, без отдельного поля.
# ============================================================================
class_name Surfaces
extends RefCounted

## speed — множитель хода, dust — цвет следа из-под гусениц,
## tread — какой звук трака подходит покрытию (жёсткий или глухой).
static var ASPHALT := {
	"id": "asphalt", "speed": 1.12, "dust": Color("#4a4b50"), "tread": "tread_hard",
}
static var DIRT := {
	"id": "dirt", "speed": 1.0, "dust": Color("#6b6350"), "tread": "tread_soft",
}
static var GRASS := {
	"id": "grass", "speed": 0.92, "dust": Color("#4a6b3a"), "tread": "tread_soft",
}
static var SAND := {
	"id": "sand", "speed": 0.85, "dust": Color("#c9b878"), "tread": "tread_soft",
}

## Покрытие по типу тайла.
static func of_tile(tile: int) -> Dictionary:
	match tile:
		Cfg.T_ROAD, Cfg.T_BRIDGE:
			return ASPHALT
		Cfg.T_GRASS:
			return GRASS
		Cfg.T_SAND:
			return SAND
	return DIRT
