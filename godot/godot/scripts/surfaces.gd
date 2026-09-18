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
## Бархан: рыхлый склон, танк ползёт. Проехать можно, но обходить быстрее —
## именно поэтому бархан работает как рельеф, а не как стена.
static var DUNE := {
	"id": "dune", "speed": 0.62, "dust": Color("#bfa967"), "tread": "tread_soft",
}
## Зыбучий песок: почти стоячий ход. Заезжать сюда — ошибка, и она наказуема.
static var QUICKSAND := {
	"id": "quicksand", "speed": 0.34, "dust": Color("#7d6a45"), "tread": "tread_soft",
}
## Грунтовка: быстрее целины, но не асфальт. Локация без асфальта не должна
## получать асфальтовое сцепление только потому, что тайл дороги один и тот же.
static var DIRT_ROAD := {
	"id": "dirt_road", "speed": 1.05, "dust": Color("#6a5a3c"), "tread": "tread_soft",
}

## Покрытие по типу тайла.
##
## @param road_kind чем на этой локации замощены дороги: asphalt | dirt | path.
##        Тайл дороги один и тот же во всех локациях — иначе пришлось бы
##        дублировать всю дорожную логику, — но грунтовка не обязана держать
##        как асфальт.
static func of_tile(tile: int, road_kind: String = "asphalt") -> Dictionary:
	match tile:
		Cfg.T_ROAD, Cfg.T_BRIDGE:
			return ASPHALT if road_kind == "asphalt" else DIRT_ROAD
		Cfg.T_GRASS:
			return GRASS
		Cfg.T_SAND:
			return SAND
		Cfg.T_DUNE:
			return DUNE
		Cfg.T_QUICKSAND:
			return QUICKSAND
	return DIRT
