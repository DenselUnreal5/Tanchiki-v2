@tool
class_name Cosmetics
extends RefCounted

const TYPES := ["skin", "camo", "hull", "track", "turret"]

static var SKINS := [
	{"id": "none", "type": "skin", "name": "Стандартный", "icon": "⬛", "price": 0,
		"rarity": "common", "desc": "Базовый заводской комплект брони, башни и гусениц."},
	{"id": "cyberpunk", "type": "skin", "name": "Неоновый Киберпанк", "icon": "⚡", "price": 380,
		"rarity": "legendary", "desc": "Полный кибер-комплект: корпус с микросхемами и сканером, футуристическая башня со световым визором и неоновые светящиеся гусеницы.", "color": Color("#00f0ff")},
	{"id": "magma", "type": "skin", "name": "Магма Инферно", "icon": "🌋", "price": 380,
		"rarity": "legendary", "desc": "Полный магма-комплект: базальтовая броня с огненными разломами, башня с лавовым кратером и раскаленные огненные гусеницы.", "color": Color("#ff4500")},
	{"id": "steampunk", "type": "skin", "name": "Стимпанк Титан", "icon": "⚙️", "price": 280,
		"rarity": "epic", "desc": "Полный стимпанк-комплект: клепаная латунная броня с шестернями, паровая башня с манометром и тяжелые бронзовые гусеницы.", "color": Color("#cd7f32")},
	{"id": "void", "type": "skin", "name": "Космическая Бездна", "icon": "🌌", "price": 420,
		"rarity": "legendary", "desc": "Полный космический комплект: броня из темной материи со звездами, башня-сингулярность с вихрем и мерцающие аметистовые гусеницы.", "color": Color("#a855f7")},
	{"id": "dragon", "type": "skin", "name": "Драконья Чешуя", "icon": "🐉", "price": 320,
		"rarity": "epic", "desc": "Полный драконий комплект: изумрудная чешуя с золотым спинным гребнем, рогатая башня с оком дракона и когтистые гусеницы.", "color": Color("#10b981")},
	{"id": "toxic", "type": "skin", "name": "Биоугроза Токсик", "icon": "☣️", "price": 260,
		"rarity": "rare", "desc": "Полный хим-комплект: корпус биозащиты со знаками опасности, башня с колбой едкого токсина и радиоактивные промышленные гусеницы.", "color": Color("#84cc16")},
	{"id": "golden_emperor", "type": "skin", "name": "Золотой Император", "icon": "👑", "price": 500,
		"rarity": "legendary", "desc": "Полный царский комплект: зеркальное 24К золото с пурпурным стягом, коронованная башня с рубином и сплошные золотые гусеницы.", "color": Color("#ffd700")},
	{"id": "arctic_frost", "type": "skin", "name": "Вечная Мерзлота", "icon": "❄️", "price": 300,
		"rarity": "epic", "desc": "Полный ледяной комплект: панцирь из реликтового полярного льда, кристаллическая призма башни и скованные мерзлотой ледяные гусеницы.", "color": Color("#38bdf8")},
]

static var CAMOS := [
	{"id": "none", "type": "camo", "name": "Без камуфляжа", "icon": "⬛", "price": 0, "desc": "Стандартная заводская окраска брони."},
	{"id": "digital", "type": "camo", "name": "Цифра", "icon": "🟩", "price": 150, "desc": "Полевой пиксельный камуфляж для пересеченной местности.",
		"a": Color("#43503a"), "b": Color("#2c3527")},
	{"id": "splinter", "type": "camo", "name": "Осколочный", "icon": "🔷", "price": 170, "desc": "Осколочный геометрический камуфляж, ломающий силуэт танка.",
		"a": Color("#4a4536"), "b": Color("#2b2f24")},
	{"id": "tiger", "type": "camo", "name": "Тигр", "icon": "🐯", "price": 190, "desc": "Хищный полосатый камуфляж для внезапных засад.",
		"a": Color("#7a5a1e"), "b": Color("#241a0c")},
	{"id": "desert", "type": "camo", "name": "Пустыня", "icon": "🏜️", "price": 160, "desc": "Песчано-барханный камуфляж для знойных пустошей.",
		"a": Color("#b09a63"), "b": Color("#7d6a3f")},
	{"id": "urban", "type": "camo", "name": "Город", "icon": "🏙️", "price": 160, "desc": "Асфальтово-серый маскировочный окрас для городских кварталов.",
		"a": Color("#6e737a"), "b": Color("#3c4046")},
	{"id": "winter", "type": "camo", "name": "Зима", "icon": "❄️", "price": 180, "desc": "Маскировочный белый покров для заснеженных равнин.",
		"a": Color("#d5dde4"), "b": Color("#8f9aa6")},
	{"id": "camo_digital_neon", "type": "camo", "name": "Неоновая цифра", "icon": "⚡", "price": 220, "desc": "Электронный кибер-камуфляж со светящимися пикселями.",
		"a": Color("#052e2b"), "b": Color("#0d9488")},
	{"id": "camo_lava", "type": "camo", "name": "Лавовый", "icon": "🔥", "price": 220, "desc": "Пылающий камуфляж с прожилками огненной магмы.",
		"a": Color("#450a0a"), "b": Color("#ea580c")},
	{"id": "camo_forest", "type": "camo", "name": "Хвойный лес", "icon": "🌲", "price": 180, "desc": "Глубокий хвойный лесной камуфляж для лесных чащоб.",
		"a": Color("#1c2e17"), "b": Color("#365314")},
	{"id": "camo_ocean", "type": "camo", "name": "Глубинный", "icon": "🌊", "price": 190, "desc": "Глубинный морской градиент для прибрежных операций.",
		"a": Color("#0c1b33"), "b": Color("#0284c7")},
	{"id": "camo_carbon", "type": "camo", "name": "Карбон", "icon": "🏁", "price": 240, "desc": "Углеволоконное карбоновое плетение высокой прочности.",
		"a": Color("#18181b"), "b": Color("#27272a")},
]

static var HULLS := [
	{"id": "none", "type": "hull", "name": "Без рисунка", "icon": "⬛", "price": 0, "desc": "Чистая лобовая броня без эмблем."},
	{"id": "stripes", "type": "hull", "name": "Полосы", "icon": "🎨", "price": 120, "desc": "Штурмовые продольные полосы на лобовой броне."},
	{"id": "star", "type": "hull", "name": "Звезда", "icon": "⭐", "price": 150, "desc": "Командирская звезда боевой доблести."},
	{"id": "flames", "type": "hull", "name": "Пламя", "icon": "🔥", "price": 200, "desc": "Языки яростного огня на лобовой бронеплите."},
	{"id": "cross", "type": "hull", "name": "Крест", "icon": "✚", "price": 100, "desc": "Тактический крест быстрого визуального опознавания."},
	{"id": "chevrons", "type": "hull", "name": "Шевроны", "icon": "🔺", "price": 140, "desc": "Штурмовые шевроны ударной танковой дивизии."},
	{"id": "skull", "type": "hull", "name": "Череп карателя", "icon": "💀", "price": 200, "desc": "Устрашающая эмблема черепа на броне корпуса."},
	{"id": "dragon_crest", "type": "hull", "name": "Дракон", "icon": "🐲", "price": 220, "desc": "Геральдический золотой дракон древней династии."},
	{"id": "biohazard", "type": "hull", "name": "Биохазард", "icon": "☣️", "price": 180, "desc": "Знак биологической и радиационной опасности."},
	{"id": "lightning_bolt", "type": "hull", "name": "Молния", "icon": "⚡", "price": 190, "desc": "Зигзаг грозовой молнии высокого напряжения."},
	{"id": "shark_mouth", "type": "hull", "name": "Пасть акулы", "icon": "🦈", "price": 210, "desc": "Хищный оскал акульей пасти на носу танка."},
	{"id": "wings", "type": "hull", "name": "Крылья", "icon": "🪽", "price": 190, "desc": "Расправленные крылья победы и скорости."},
	{"id": "bullseye", "type": "hull", "name": "Мишень", "icon": "🎯", "price": 150, "desc": "Провокационная концентрическая мишень на капоте."},
]

static var TRACKS := [
	{"id": "none", "type": "track", "name": "Стандартные", "icon": "⬜", "price": 0, "desc": "Заводские чугунные траки и стальные катки."},
	{"id": "gold", "type": "track", "name": "Золотые", "icon": "✨", "price": 180, "desc": "Гусеничные звенья и катки из полированного золота.", "color": Color("#d4af37")},
	{"id": "steel", "type": "track", "name": "Стальные", "icon": "🪨", "price": 100, "desc": "Усиленные высокопрочные стальные звенья траков.", "color": Color("#9a9a9a")},
	{"id": "ruby", "type": "track", "name": "Рубиновые", "icon": "🔴", "price": 130, "desc": "Алые броневые траки с рубиновым напылением.", "color": Color("#c0392b")},
	{"id": "neon_cyan", "type": "track", "name": "Неоновые", "icon": "⚡", "price": 220, "desc": "Светящиеся неоновые кибер-гусеницы с ярким следом.", "color": Color("#00f0ff")},
	{"id": "magma_track", "type": "track", "name": "Магма", "icon": "🔥", "price": 240, "desc": "Раскаленные гусеницы с искрами горящей лавы.", "color": Color("#ff4500")},
	{"id": "plasma", "type": "track", "name": "Плазма", "icon": "🟣", "price": 210, "desc": "Энергетические плазменные траки фиолетового свечения.", "color": Color("#a855f7")},
	{"id": "emerald_track", "type": "track", "name": "Изумрудные", "icon": "🟢", "price": 200, "desc": "Изумрудные траки с защитными накладками.", "color": Color("#10b981")},
	{"id": "carbon_track", "type": "track", "name": "Карбон", "icon": "⬛", "price": 180, "desc": "Облегченные композитные карбоновые траки.", "color": Color("#1e293b")},
]

static var TURRETS := [
	{"id": "none", "type": "turret", "name": "Стандартная", "icon": "🔘", "price": 0, "desc": "Штатная нарезная башня заводского образца."},
	{"id": "gold", "type": "turret", "name": "Золотая", "icon": "👑", "price": 160, "desc": "Королевская золотая башня с гравировкой.", "color": Color("#d4af37")},
	{"id": "red", "type": "turret", "name": "Алая", "icon": "🔴", "price": 90, "desc": "Штурмовая алая башня быстрого наведения.", "color": Color("#e05555")},
	{"id": "night", "type": "turret", "name": "Ночная", "icon": "🌑", "price": 140, "desc": "Матовая ночная стелс-башня, поглощающая свет.", "color": Color("#11131a")},
	{"id": "cyber_turret", "type": "turret", "name": "Кибер-башня", "icon": "⚡", "price": 220, "desc": "Высокотехнологичная кибер-башня со сканером.", "color": Color("#00f0ff")},
	{"id": "magma_turret", "type": "turret", "name": "Башня Инферно", "icon": "🌋", "price": 240, "desc": "Вулканическая базальтовая башня с лавовым ядром.", "color": Color("#ff4500")},
	{"id": "plasma_turret", "type": "turret", "name": "Плазменная", "icon": "🟣", "price": 210, "desc": "Энергетическая башня с плазменным генератором.", "color": Color("#a855f7")},
	{"id": "steampunk_turret", "type": "turret", "name": "Паровая латунь", "icon": "⚙️", "price": 200, "desc": "Кованая латунная башня с механическим манометром.", "color": Color("#cd7f32")},
	{"id": "chrome_turret", "type": "turret", "name": "Хромированная", "icon": "🪞", "price": 250, "desc": "Зеркальная хромированная башня с отражающим куполом.", "color": Color("#e2e8f0")},
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
