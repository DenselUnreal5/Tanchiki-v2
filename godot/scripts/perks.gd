# ============================================================================
# perks.gd — описание перков.
#
# Числовые эффекты перков описаны декларативно и пересчитываются с нуля
# функцией compute_modifiers(): снятие перка честно возвращает характеристики.
# ============================================================================
class_name Perks
extends RefCounted

## Значения по умолчанию — «перков нет».
static func base_modifiers() -> Dictionary:
	return {
		"maxHPMult": 1.0,        # множитель максимума HP
		"speedMult": 1.0,        # множитель предельной скорости
		"fireRateMult": 1.0,     # множитель времени перезарядки (меньше — быстрее)
		"dmgMult": 1.0,          # множитель урона своих пуль
		"bulletSpeedMult": 1.0,  # множитель скорости своих пуль
		"damageTakenMult": 1.0,  # множитель получаемого урона
		"ramMult": 1.0,          # множитель урона тараном
		"accuracyBonus": 0.0,    # прибавка к точности (только боты)
		"evasionChance": 0.0,    # шанс полностью уклониться от урона
		"reflectFraction": 0.0,  # доля урона, возвращаемая атакующему
		"pickupRadiusMult": 1.0, # множитель радиуса подбора аптечек
		"lifestealFraction": 0.0,# доля нанесённого урона, идущая в лечение
		"regenPerMinute": 0.0,   # HP в минуту
		"buildingDmgMult": 1.0,  # множитель урона своих попаданий по постройкам
		"turboOnKill": 0.0,      # длительность ускорения после убийства, тиков
		"shadowOnKill": 0.0,     # длительность невидимости на миникарте, тиков
	}

## Категории перков. Порядок задаёт порядок разделов в галерее.
static var CATEGORIES := [
	{"id": "fire", "name": "Огонь", "color": Color("#ff8833")},
	{"id": "defense", "name": "Защита", "color": Color("#44aaff")},
	{"id": "speed", "name": "Скорость", "color": Color("#ffee55")},
	{"id": "special", "name": "Особые", "color": Color("#ff55ff")},
	{"id": "challenge", "name": "Челленджи", "color": Color("#ff4455")},
]

## Перки игрока. mods — числовые модификаторы, flags — поведенческие метки.
const LIST := [
	# ---------------------------------------------------------------- огонь
	{
		"id": "double_shot", "name": "Двойной выстрел", "icon": "🔫",
		"desc": "2 пули параллельно", "category": "fire", "flags": ["doubleShot"],
	},
	{
		"id": "fan_shot", "name": "Выстрел веером", "icon": "🌊",
		"desc": "3 пули веером, каждая 45% урона", "category": "fire", "flags": ["fanShot"],
	},
	{
		"id": "rapid_fire", "name": "Скорострельность", "icon": "⚡",
		"desc": "Перезарядка быстрее на 40%", "category": "fire",
		"mods": {"fireRateMult": 0.6},
	},
	{
		"id": "explosive", "name": "Взрывные пули", "icon": "💥",
		"desc": "Урон по площади 32 px и снос кирпича вокруг", "category": "fire",
		"flags": ["explosive"],
	},
	{
		"id": "piercing", "name": "Пробивной выстрел", "icon": "🎯",
		"desc": "Пуля пробивает одну стену", "category": "fire", "flags": ["piercing"],
	},

	# ---------------------------------------------------------------- защита
	{
		"id": "heavy_armor", "name": "Тяжёлая броня", "icon": "🛡",
		"desc": "Максимум HP +50%", "category": "defense", "mods": {"maxHPMult": 1.5},
	},
	{
		"id": "regen", "name": "Регенерация", "icon": "❤",
		"desc": "60 HP в минуту (1 HP/сек)", "category": "defense",
		"mods": {"regenPerMinute": 60.0},
	},
	{
		"id": "reflect", "name": "Отражение", "icon": "🪞",
		"desc": "20% полученного урона возвращается атакующему", "category": "defense",
		"mods": {"reflectFraction": 0.2},
	},
	{
		"id": "evasion", "name": "Уклонение", "icon": "💨",
		"desc": "15% шанс полностью избежать урона", "category": "defense",
		"mods": {"evasionChance": 0.15},
	},
	{
		"id": "shield", "name": "Энергощит", "icon": "🔵",
		"desc": "Щит на 30 HP, восстанавливается раз в 30 сек", "category": "defense",
		"flags": ["shield"],
	},

	# ---------------------------------------------------------------- скорость
	{
		"id": "sprinter", "name": "Спринтер", "icon": "👟",
		"desc": "Скорость +25%", "category": "speed", "mods": {"speedMult": 1.25},
	},
	{
		"id": "quick_reload", "name": "Быстрая перезарядка", "icon": "🔄",
		"desc": "Перезарядка быстрее на 30%", "category": "speed",
		"mods": {"fireRateMult": 0.7},
	},

	# ---------------------------------------------------------------- особые
	{
		"id": "mines", "name": "Миноукладчик", "icon": "💣",
		"desc": "До 3 мин на карте, ставятся клавишей мины", "category": "special",
		"flags": ["mines"],
	},

	# ------------------------------------------------------- челленджи
	{
		"id": "ram", "name": "Таран", "icon": "🚛",
		"desc": "Урон при столкновении x2", "category": "challenge",
		"mods": {"ramMult": 2.0},
		"challenge": {"desc": "Уничтожь 3 танка тараном", "stat": "ramKills", "need": 3},
	},
	{
		"id": "thick_armor", "name": "Толстая броня", "icon": "🧱",
		"desc": "Получаемый урон −20%, но ваши пули не ломают кирпич",
		"category": "challenge",
		"mods": {"damageTakenMult": 0.8}, "flags": ["keepBricks"],
		"challenge": {"desc": "Разбей 15 кирпичей", "stat": "bricksDestroyed", "need": 15},
	},
	{
		"id": "amphibious", "name": "Амфибия", "icon": "🐸",
		"desc": "В воде только замедление, без урона", "category": "challenge",
		"flags": ["amphibious"],
		"challenge": {"desc": "Войди в воду 5 раз", "stat": "waterEntries", "need": 5},
	},
	{
		"id": "forest", "name": "Лесной житель", "icon": "🌲",
		"desc": "Проезд через деревья, не уничтожая их", "category": "challenge",
		"flags": ["forest"],
		"challenge": {"desc": "Проедь через 5 деревьев", "stat": "treesDriven", "need": 5},
	},
	{
		"id": "magnet", "name": "Магнит", "icon": "🧲",
		"desc": "Радиус подбора аптечек x2", "category": "challenge",
		"mods": {"pickupRadiusMult": 2.0},
		"challenge": {"desc": "Собери 20 аптечек", "stat": "healthPacksCollected", "need": 20},
	},
	{
		"id": "sniper", "name": "Снайпер", "icon": "🔭",
		"desc": "Пули летят на 40% быстрее и наносят +15% урона", "category": "challenge",
		"mods": {"bulletSpeedMult": 1.4, "dmgMult": 1.15},
		"challenge": {"desc": "Убей 3 врагов с дистанции 400 px", "stat": "longKills", "need": 3},
	},
	{
		"id": "berserk", "name": "Берсерк", "icon": "😤",
		"desc": "Урон ×1.6, пока ваше HP ≤ 40%", "category": "challenge",
		"flags": ["berserk"],
		"challenge": {"desc": "Убей 5 врагов при HP ≤ 40%", "stat": "lowHpKills", "need": 5},
	},
	{
		"id": "kamikaze", "name": "Камикадзе", "icon": "💀",
		"desc": "При смерти взрыв на 64 px", "category": "challenge",
		"flags": ["kamikaze"],
		"challenge": {"desc": "Умри 10 раз", "stat": "timesDied", "need": 10},
	},
	{
		"id": "turbo", "name": "Турбо", "icon": "🚀",
		"desc": "Ускорение x1.5 на 3 сек после убийства", "category": "challenge",
		"mods": {"turboOnKill": 180.0},
		"challenge": {"desc": "Убей 5 врагов за 10 секунд", "stat": "rapidKills", "need": 5},
	},
	{
		"id": "shadow", "name": "Тень", "icon": "🌑",
		"desc": "Невидимость на миникарте 3 сек после убийства", "category": "challenge",
		"mods": {"shadowOnKill": 180.0},
		"challenge": {"desc": "3 убийства подряд без урона", "stat": "cleanStreak", "need": 3},
	},
	{
		"id": "vampire", "name": "Вампир", "icon": "🧛",
		"desc": "15% нанесённого урона возвращается как HP", "category": "challenge",
		"mods": {"lifestealFraction": 0.15},
		"challenge": {"desc": "Нанеси 5000 урона за партию", "stat": "damageInGame", "need": 5000},
	},
]

## Перки ботов — та же схема модификаторов.
const BOT_LIST := [
	{"id": "bot_rapid", "icon": "⚡", "name": "Скорострельность", "desc": "Перезарядка x0.7", "mods": {"fireRateMult": 0.7}},
	{"id": "bot_speed", "icon": "👟", "name": "Ноги", "desc": "Скорость x1.3", "mods": {"speedMult": 1.3}},
	{"id": "bot_tough", "icon": "🛡", "name": "Толстая броня", "desc": "Максимум HP +40%", "mods": {"maxHPMult": 1.4}},
	{"id": "bot_double", "icon": "🔫", "name": "Двойной выстрел", "desc": "2 пули параллельно", "flags": ["doubleShot"]},
	{"id": "bot_nitro", "icon": "🚀", "name": "Нитро", "desc": "Рывок скорости по кулдауну", "active": "nitro"},
	{"id": "bot_wave", "icon": "💠", "name": "Ударная волна", "desc": "Взрыв вокруг себя в упор", "active": "shockwave"},
	{"id": "bot_accurate", "icon": "🎯", "name": "Снайпер", "desc": "Точность +15%", "mods": {"accuracyBonus": 0.15}},
	{"id": "bot_regen", "icon": "❤", "name": "Регенерация", "desc": "60 HP в минуту", "mods": {"regenPerMinute": 60.0}},
	{"id": "bot_heavy", "icon": "💥", "name": "Тяжёлые пули", "desc": "Урон +25%", "mods": {"dmgMult": 1.25}},
	{"id": "bot_evasion", "icon": "💨", "name": "Уклонение", "desc": "15% шанс уклонения", "mods": {"evasionChance": 0.15}},
]

static var _by_id := {}
static var _bot_by_id := {}

static func _index() -> void:
	if _by_id.is_empty():
		for p in LIST:
			_by_id[p["id"]] = p
		for p in ACTIVE_LIST:
			_by_id[p["id"]] = p
	if _bot_by_id.is_empty():
		for p in BOT_LIST:
			_bot_by_id[p["id"]] = p

static func get_perk(id: String) -> Dictionary:
	_index()
	return _by_id.get(id, {})

static func get_bot_perk(id: String) -> Dictionary:
	_index()
	return _bot_by_id.get(id, {})

static func perk_icon(id: String) -> String:
	_index()
	if _by_id.has(id):
		return _by_id[id]["icon"]
	return "⭐"

static func perk_name(id: String) -> String:
	_index()
	if _by_id.has(id):
		return _by_id[id]["name"]
	return id

## Иконка перка любого вида — игрока или бота.
static func any_perk_icon(id: String) -> String:
	_index()
	if _by_id.has(id):
		return _by_id[id]["icon"]
	if _bot_by_id.has(id):
		return _bot_by_id[id]["icon"]
	return "⭐"

## Перки с активной способностью и осадный пассив. Вынесены отдельным
## списком только для читаемости — в индекс они попадают наравне с LIST.
const ACTIVE_LIST := [
	{
		"id": "siege", "name": "Осадные снаряды", "icon": "🏗",
		"desc": "Урон по постройкам x2.2", "category": "fire",
		"mods": {"buildingDmgMult": 2.2},
	},
	{
		"id": "nitro", "name": "Нитро", "icon": "🚀",
		"desc": "рывок скорости на 2.5 с", "category": "speed",
		"active": "nitro",
	},
	{
		"id": "overdrive", "name": "Форсаж", "icon": "🔥",
		"desc": "4 с двойной скорострельности", "category": "fire",
		"active": "overdrive",
	},
	{
		"id": "bulwark", "name": "Бастион", "icon": "🛡",
		"desc": "3 с урон по вам снижен на 60%", "category": "defense",
		"active": "bulwark",
	},
	{
		"id": "shockwave", "name": "Ударная волна", "icon": "💠",
		"desc": "взрыв вокруг танка, сносит постройки", "category": "special",
		"active": "shockwave",
	},
]

## Полный список перков игрока. ACTIVE_LIST живёт отдельно только ради
## читаемости файла, но галерея, гараж и выдача уровней должны видеть все.
static var _all := []

static func all() -> Array:
	if _all.is_empty():
		_all = LIST + ACTIVE_LIST
	return _all

## Способность из набора перков: берётся первая найденная. Двух активных
## одновременно не бывает — иначе понадобилась бы вторая клавиша, и выбор
## перестал бы быть выбором.
static func active_ability_of(perk_ids: Array, bot: bool = false) -> String:
	if perk_ids == null:
		return ""
	for id in perk_ids:
		var perk: Dictionary = get_bot_perk(String(id)) if bot else get_perk(String(id))
		if perk.has("active"):
			return String(perk["active"])
	return ""

static func is_active_perk(id: String) -> bool:
	return get_perk(id).has("active")

## Перки, запрещённые в конкретном режиме. В «Царе горы» нет «Амфибии»:
## вся соль режима — тонущая карта, и прятаться от неё нельзя.
const MODE_BANNED := {"koth": ["amphibious"]}

static func is_perk_allowed_in_mode(id: String, mode: String) -> bool:
	var banned: Array = MODE_BANNED.get(mode, [])
	return not banned.has(id)

static func filter_perks_for_mode(ids: Array, mode: String) -> Array:
	var out := []
	for id in ids:
		if is_perk_allowed_in_mode(id, mode):
			out.append(id)
	return out

## Перки, открываемые за глобальные уровни профиля.
const UNLOCK_TABLE := {
	1: ["rapid_fire", "heavy_armor", "sprinter"],
	2: ["double_shot", "regen", "nitro"],
	3: ["quick_reload", "evasion", "siege"],
	4: ["fan_shot", "reflect"],
	5: ["explosive", "shield", "overdrive"],
	6: ["piercing", "bulwark"],
	7: ["mines", "shockwave"],
}

## На каком глобальном уровне открывается перк (или 0 для челленджей).
static func unlock_level_of(perk_id: String) -> int:
	for lvl in UNLOCK_TABLE.keys():
		if UNLOCK_TABLE[lvl].has(perk_id):
			return lvl
	return 0

## Собирает итоговые модификаторы из набора перков.
## Множители перемножаются, прибавки складываются, шансы объединяются
## вероятностно (1 - произведение промахов), чтобы не превысить 100%.
static func compute_modifiers(perk_ids: Array, bot: bool = false) -> Dictionary:
	var m := base_modifiers()
	if perk_ids == null or perk_ids.is_empty():
		return m
	var evasion_miss := 1.0
	for id in perk_ids:
		var perk: Dictionary = get_bot_perk(id) if bot else get_perk(id)
		if perk.is_empty() or not perk.has("mods"):
			continue
		var mods: Dictionary = perk["mods"]
		for key in mods.keys():
			var v: float = float(mods[key])
			match key:
				"maxHPMult", "speedMult", "fireRateMult", "dmgMult", "bulletSpeedMult", \
				"damageTakenMult", "ramMult", "pickupRadiusMult", "buildingDmgMult":
					m[key] = float(m[key]) * v
				"accuracyBonus", "reflectFraction", "lifestealFraction", "regenPerMinute":
					m[key] = float(m[key]) + v
				"evasionChance":
					evasion_miss *= (1.0 - v)
				"turboOnKill", "shadowOnKill":
					m[key] = maxf(float(m[key]), v)
	m["evasionChance"] = 1.0 - evasion_miss
	return m

## Собирает множество поведенческих меток из набора перков.
static func compute_flags(perk_ids: Array, bot: bool = false) -> Dictionary:
	var set := {}
	if perk_ids == null:
		return set
	for id in perk_ids:
		var perk: Dictionary = get_bot_perk(id) if bot else get_perk(id)
		if perk.is_empty() or not perk.has("flags"):
			continue
		for f in perk["flags"]:
			set[f] = true
	return set
