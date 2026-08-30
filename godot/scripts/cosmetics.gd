# ============================================================================
# cosmetics.gd — косметика за монеты: рисунки корпуса, гусеницы и башни.
#
# Никакой механики не добавляет — только влияет на отрисовку танка.
# «none» бесплатен и доступен всем; остальное покупается в Гараже.
# ============================================================================
class_name Cosmetics
extends RefCounted

## Камуфляж идёт первым: это базовая окраска корпуса, поверх которой
## ложится рисунок (звезда, пламя и прочие наклейки).
const TYPES := ["camo", "hull", "track", "turret"]

## Камуфляжи. Два цвета пятен смешиваются с командным цветом, а не заменяют
## его: иначе в командном режиме свои и чужие стали бы неразличимы.
static var CAMOS := [
	{"id": "none", "type": "camo", "name": "Без камуфляжа", "icon": "⬛", "price": 0},
	{"id": "digital", "type": "camo", "name": "Цифра", "icon": "🟩", "price": 150,
		"a": Color("#43503a"), "b": Color("#2c3527")},
	{"id": "splinter", "type": "camo", "name": "Осколочный", "icon": "🔷", "price": 170,
		"a": Color("#4a4536"), "b": Color("#2b2f24")},
	{"id": "tiger", "type": "camo", "name": "Тигр", "icon": "🐯", "price": 190,
		"a": Color("#7a5a1e"), "b": Color("#241a0c")},
	{"id": "desert", "type": "camo", "name": "Пустыня", "icon": "🏜️", "price": 160,
		"a": Color("#b09a63"), "b": Color("#7d6a3f")},
	{"id": "urban", "type": "camo", "name": "Город", "icon": "🏙️", "price": 160,
		"a": Color("#6e737a"), "b": Color("#3c4046")},
	{"id": "winter", "type": "camo", "name": "Зима", "icon": "❄️", "price": 180,
		"a": Color("#d5dde4"), "b": Color("#8f9aa6")},
]

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
		"camo":
			return CAMOS
		"hull":
			return HULLS
		"track":
			return TRACKS
		"turret":
			return TURRETS
	return []

static func all() -> Array:
	var out := []
	out.append_array(CAMOS)
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
