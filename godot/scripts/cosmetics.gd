@tool
class_name Cosmetics
extends RefCounted

const TYPES := ["skin", "camo", "hull", "track", "turret"]

static var SKINS := [
	{"id": "none", "type": "skin", "name": "Стандартный", "icon": "⬛", "price": 0,
		"rarity": "common", "desc": "Базовый заводской корпус танка"},
	{"id": "cyberpunk", "type": "skin", "name": "Неоновый Киберпанк", "icon": "⚡", "price": 380,
		"rarity": "legendary", "desc": "Светящиеся микросхемы, неоновые контуры и кибер-сканер", "color": Color("#00f0ff")},
	{"id": "magma", "type": "skin", "name": "Магма Инферно", "icon": "🌋", "price": 380,
		"rarity": "legendary", "desc": "Базальтовая броня с пульсирующими огненными разломами лавы", "color": Color("#ff4500")},
	{"id": "steampunk", "type": "skin", "name": "Стимпанк Титан", "icon": "⚙️", "price": 280,
		"rarity": "epic", "desc": "Кованая латунь, броневые заклёпки и шестерёночные механизмы", "color": Color("#cd7f32")},
	{"id": "void", "type": "skin", "name": "Космическая Бездна", "icon": "🌌", "price": 420,
		"rarity": "legendary", "desc": "Глубокая космическая материя, туманность и мерцающие звёзды", "color": Color("#a855f7")},
	{"id": "dragon", "type": "skin", "name": "Драконья Чешуя", "icon": "🐉", "price": 320,
		"rarity": "epic", "desc": "Изумрудная броня из чешуи древнего дракона с золотыми пластинами", "color": Color("#10b981")},
	{"id": "toxic", "type": "skin", "name": "Биоугроза Токсик", "icon": "☣️", "price": 260,
		"rarity": "rare", "desc": "Предупреждающая маркировка опасности и радиоактивное свечение", "color": Color("#84cc16")},
	{"id": "golden_emperor", "type": "skin", "name": "Золотой Император", "icon": "👑", "price": 500,
		"rarity": "legendary", "desc": "Зеркальное королевское золото с имперским пурпуром и сиянием", "color": Color("#ffd700")},
	{"id": "arctic_frost", "type": "skin", "name": "Вечная Мерзлота", "icon": "❄️", "price": 300,
		"rarity": "epic", "desc": "Осколки реликтового льда, иней и морозные кристаллы", "color": Color("#38bdf8")},
]

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
	{"id": "camo_digital_neon", "type": "camo", "name": "Неоновая цифра", "icon": "⚡", "price": 220,
		"a": Color("#052e2b"), "b": Color("#0d9488")},
	{"id": "camo_lava", "type": "camo", "name": "Лавовый", "icon": "🔥", "price": 220,
		"a": Color("#450a0a"), "b": Color("#ea580c")},
	{"id": "camo_forest", "type": "camo", "name": "Хвойный лес", "icon": "🌲", "price": 180,
		"a": Color("#1c2e17"), "b": Color("#365314")},
	{"id": "camo_ocean", "type": "camo", "name": "Глубинный", "icon": "🌊", "price": 190,
		"a": Color("#0c1b33"), "b": Color("#0284c7")},
	{"id": "camo_carbon", "type": "camo", "name": "Карбон", "icon": "🏁", "price": 240,
		"a": Color("#18181b"), "b": Color("#27272a")},
]

static var HULLS := [
	{"id": "none", "type": "hull", "name": "Без рисунка", "icon": "⬛", "price": 0},
	{"id": "stripes", "type": "hull", "name": "Полосы", "icon": "🎨", "price": 120},
	{"id": "star", "type": "hull", "name": "Звезда", "icon": "⭐", "price": 150},
	{"id": "flames", "type": "hull", "name": "Пламя", "icon": "🔥", "price": 200},
	{"id": "cross", "type": "hull", "name": "Крест", "icon": "✚", "price": 100},
	{"id": "chevrons", "type": "hull", "name": "Шевроны", "icon": "🔺", "price": 140},
	{"id": "skull", "type": "hull", "name": "Череп карателя", "icon": "💀", "price": 200},
	{"id": "dragon_crest", "type": "hull", "name": "Дракон", "icon": "🐲", "price": 220},
	{"id": "biohazard", "type": "hull", "name": "Биохазард", "icon": "☣️", "price": 180},
	{"id": "lightning_bolt", "type": "hull", "name": "Молния", "icon": "⚡", "price": 190},
	{"id": "shark_mouth", "type": "hull", "name": "Пасть акулы", "icon": "🦈", "price": 210},
	{"id": "wings", "type": "hull", "name": "Крылья", "icon": "🪽", "price": 190},
	{"id": "bullseye", "type": "hull", "name": "Мишень", "icon": "🎯", "price": 150},
]

static var TRACKS := [
	{"id": "none", "type": "track", "name": "Стандартные", "icon": "⬜", "price": 0},
	{"id": "gold", "type": "track", "name": "Золотые", "icon": "✨", "price": 180, "color": Color("#d4af37")},
	{"id": "steel", "type": "track", "name": "Стальные", "icon": "🪨", "price": 100, "color": Color("#9a9a9a")},
	{"id": "ruby", "type": "track", "name": "Рубиновые", "icon": "🔴", "price": 130, "color": Color("#c0392b")},
	{"id": "neon_cyan", "type": "track", "name": "Неоновые", "icon": "⚡", "price": 220, "color": Color("#00f0ff")},
	{"id": "magma_track", "type": "track", "name": "Магма", "icon": "🔥", "price": 240, "color": Color("#ff4500")},
	{"id": "plasma", "type": "track", "name": "Плазма", "icon": "🟣", "price": 210, "color": Color("#a855f7")},
	{"id": "emerald_track", "type": "track", "name": "Изумрудные", "icon": "🟢", "price": 200, "color": Color("#10b981")},
	{"id": "carbon_track", "type": "track", "name": "Карбон", "icon": "⬛", "price": 180, "color": Color("#1e293b")},
]

static var TURRETS := [
	{"id": "none", "type": "turret", "name": "Стандартная", "icon": "🔘", "price": 0},
	{"id": "gold", "type": "turret", "name": "Золотая", "icon": "👑", "price": 160, "color": Color("#d4af37")},
	{"id": "red", "type": "turret", "name": "Алая", "icon": "🔴", "price": 90, "color": Color("#e05555")},
	{"id": "night", "type": "turret", "name": "Ночная", "icon": "🌑", "price": 140, "color": Color("#11131a")},
	{"id": "cyber_turret", "type": "turret", "name": "Кибер-башня", "icon": "⚡", "price": 220, "color": Color("#00f0ff")},
	{"id": "magma_turret", "type": "turret", "name": "Башня Инферно", "icon": "🌋", "price": 240, "color": Color("#ff4500")},
	{"id": "plasma_turret", "type": "turret", "name": "Плазменная", "icon": "🟣", "price": 210, "color": Color("#a855f7")},
	{"id": "steampunk_turret", "type": "turret", "name": "Паровая латунь", "icon": "⚙️", "price": 200, "color": Color("#cd7f32")},
	{"id": "chrome_turret", "type": "turret", "name": "Хромированная", "icon": "🪞", "price": 250, "color": Color("#e2e8f0")},
]

static func by_type(type: String) -> Array:
	match type:
		"skin":
			return SKINS
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
	out.append_array(SKINS)
	out.append_array(CAMOS)
	out.append_array(HULLS)
	out.append_array(TRACKS)
	out.append_array(TURRETS)
	return out

static func get_cosmetic(type: String, id: String) -> Dictionary:
	for c in by_type(type):
		if c["id"] == id:
			return c
	return {}

static func color_of(type: String, id: String, fallback: Color) -> Color:
	if id == "" or id == "none":
		return fallback
	var c := get_cosmetic(type, id)
	if c.has("color"):
		return c["color"]
	return fallback
