# ============================================================================
# cosmetics.gd — косметика за монеты: рисунки корпуса, гусеницы и башни.
#
# Никакой механики не добавляет — только влияет на отрисовку танка.
# «none» бесплатен и доступен всем; остальное покупается в Гараже.
# ============================================================================
class_name Cosmetics
extends RefCounted

const TYPES := ["hull", "track", "turret"]

## Рисунки корпуса.
const HULLS := [
	{"id": "none", "type": "hull", "name": "Без рисунка", "icon": "⬛", "price": 0},
	{"id": "stripes", "type": "hull", "name": "Камуфляж", "icon": "🎨", "price": 120},
	{"id": "star", "type": "hull", "name": "Звезда", "icon": "⭐", "price": 150},
	{"id": "flames", "type": "hull", "name": "Пламя", "icon": "🔥", "price": 200},
	{"id": "cross", "type": "hull", "name": "Крест", "icon": "✚", "price": 100},
	{"id": "chevrons", "type": "hull", "name": "Шевроны", "icon": "🔺", "price": 140},
]

## Гусеницы.
static var TRACKS := [
	{"id": "none", "type": "track", "name": "Стандартные", "icon": "⬜", "price": 0},
	{"id": "gold", "type": "track", "name": "Золотые", "icon": "✨", "price": 180, "color": Color("#d4af37")},
	{"id": "steel", "type": "track", "name": "Стальные", "icon": "🪨", "price": 100, "color": Color("#9a9a9a")},
	{"id": "ruby", "type": "track", "name": "Рубиновые", "icon": "🔴", "price": 130, "color": Color("#c0392b")},
]

## Башни.
static var TURRETS := [
	{"id": "none", "type": "turret", "name": "Стандартная", "icon": "🔘", "price": 0},
	{"id": "gold", "type": "turret", "name": "Золотая", "icon": "👑", "price": 160, "color": Color("#d4af37")},
	{"id": "red", "type": "turret", "name": "Алая", "icon": "🔴", "price": 90, "color": Color("#e05555")},
	{"id": "night", "type": "turret", "name": "Ночная", "icon": "🌑", "price": 140, "color": Color("#11131a")},
]

static func by_type(type: String) -> Array:
	match type:
		"hull":
			return HULLS
		"track":
			return TRACKS
		"turret":
			return TURRETS
	return []

static func all() -> Array:
	var out := []
	out.append_array(HULLS)
	out.append_array(TRACKS)
	out.append_array(TURRETS)
	return out

## Поиск по типу и id: id уникальны внутри типа, но повторяются между типами.
static func get_cosmetic(type: String, id: String) -> Dictionary:
	for c in by_type(type):
		if c["id"] == id:
			return c
	return {}

## Цвет косметики или заданный запасной.
static func color_of(type: String, id: String, fallback: Color) -> Color:
	if id == "" or id == "none":
		return fallback
	var c := get_cosmetic(type, id)
	if c.has("color"):
		return c["color"]
	return fallback
