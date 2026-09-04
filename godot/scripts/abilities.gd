# ============================================================================
# abilities.gd — активные способности танка.
#
# До этого все перки были пассивными: выбрал — и дальше он работает сам.
# Активная способность отличается тем, что её нужно нажать вовремя, и это
# единственная механика в игре, где решает момент, а не набор.
#
# Способность не выбирается отдельно: перк с полем "active" кладёт её в
# слот танка. Так система остаётся модульной — чтобы добавить способность,
# достаточно описать её здесь и завести перк, который её выдаёт.
#
# Длительности в тиках (60 в секунду), как и весь остальной баланс.
# ============================================================================
class_name Abilities
extends RefCounted

static var LIST := [
	{
		"id": "nitro", "name": "Нитро", "icon": "🚀",
		"desc": "2.5 с ускорения ×1.5",
		"color": Color("#ffee55"), "cooldown": 420, "duration": 150,
	},
	{
		"id": "overdrive", "name": "Форсаж", "icon": "🔥",
		"desc": "4 с перезарядка вдвое быстрее",
		"color": Color("#ff8833"), "cooldown": 600, "duration": 240,
	},
	{
		"id": "bulwark", "name": "Бастион", "icon": "🛡",
		"desc": "3 с урон по вам снижен на 60%",
		"color": Color("#44aaff"), "cooldown": 720, "duration": 180,
	},
	{
		# Мгновенная: длительности нет, весь эффект — в момент нажатия.
		"id": "shockwave", "name": "Ударная волна", "icon": "💠",
		"desc": "Взрыв вокруг: сносит постройки, бьёт и отбрасывает врагов",
		"color": Color("#ff55ff"), "cooldown": 540, "duration": 0,
	},

	# --- вторая волна: каждая привязана к своей механике ---------------
	{
		# Мгновенная. Смысл в том, чтобы снять перегрев в самый нужный
		# момент, а не пережидать его.
		"id": "coolant", "name": "Продувка ствола", "icon": "🧊",
		"desc": "Сбрасывает весь жар разом",
		"color": Color("#88ddff"), "cooldown": 600, "duration": 0,
	},
	{
		"id": "overclock", "name": "Разгон", "icon": "⚙",
		"desc": "2.5 с двойной темп, ствол не греется",
		# Окно короче и откат длиннее, чем у «Форсажа», именно потому, что
		# внутри окна нагрева нет вовсе. С прежними 4 с и откатом 13 с замер
		# давал +86 урона в секунду — вдвое больше лучшего перка в игре.
		"color": Color("#ff5533"), "cooldown": 900, "duration": 150,
	},
	{
		"id": "grip", "name": "Шипы", "icon": "🕸",
		"desc": "5 с любое покрытие держит как асфальт",
		"color": Color("#aaccff"), "cooldown": 540, "duration": 300,
	},
	{
		"id": "breaker", "name": "Кумулятив", "icon": "🧨",
		"desc": "5 с пули проходят постройки насквозь и рвут их вчетверо",
		"color": Color("#ffaa33"), "cooldown": 720, "duration": 300,
	},
	{
		"id": "silencer", "name": "Глушитель", "icon": "🔇",
		"desc": "6 с выстрелы не слышны ботам",
		"color": Color("#99a0aa"), "cooldown": 660, "duration": 360,
	},
	{
		"id": "smoke", "name": "Дымовая завеса", "icon": "🌫",
		"desc": "5 с боты не видят вас дальше 19 м",
		"color": Color("#cfd4da"), "cooldown": 720, "duration": 300,
	},
	{
		"id": "repair", "name": "Полевой ремонт", "icon": "🔧",
		"desc": "Чинит треть запаса прочности",
		"color": Color("#55dd77"), "cooldown": 900, "duration": 0,
	},
]

static var _by_id := {}

static func get_ability(id: String) -> Dictionary:
	if _by_id.is_empty():
		for a in LIST:
			_by_id[a["id"]] = a
	return _by_id.get(id, {})

static func icon_of(id: String) -> String:
	var a := get_ability(id)
	return String(a["icon"]) if not a.is_empty() else "✦"

static func name_of(id: String) -> String:
	var a := get_ability(id)
	return String(a["name"]) if not a.is_empty() else id
