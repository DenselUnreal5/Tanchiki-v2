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

		# --- ствол: нагрев и сброс (см. Cfg.HEAT_*)
		"heatPerShotMult": 1.0,  # множитель нагрева за выстрел
		"heatCoolMult": 1.0,     # множитель скорости остывания
		"heatResumeAdd": 0.0,    # прибавка к порогу возобновления огня

		# --- покрытие под гусеницами (см. surfaces.gd)
		"roadSpeedMult": 1.0,    # множитель хода по асфальту и мосту
		"softGrip": 0.0,         # доля отыгранного штрафа за траву и песок

		# --- материалы построек (см. materials.gd)
		"woodDmgMult": 1.0,
		"brickDmgMult": 1.0,
		"concreteDmgMult": 1.0,
		"metalDmgMult": 1.0,

		# --- слышимость (см. audio.gd)
		"hearingMult": 1.0,      # насколько дальше слышны чужие выстрелы
		"noiseMult": 1.0,        # насколько далеко ваш выстрел слышат боты
		"ambushDmgMult": 1.0,    # множитель урона по тому, кто вас ещё не нашёл

		"scavengeHeal": 0.0,     # лечение за снесённую поблизости постройку
	}

## Категории перков. Порядок задаёт порядок разделов в галерее.
static var CATEGORIES := [
	{"id": "fire", "name": "Огонь", "color": Color("#e2803a")},
	{"id": "defense", "name": "Защита", "color": Color("#4d95c9")},
	{"id": "speed", "name": "Скорость", "color": Color("#dcd15a")},
	{"id": "special", "name": "Особые", "color": Color("#d966d9")},
	{"id": "challenge", "name": "Челленджи", "color": Color("#d95a63")},
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
		"desc": "Перезарядка быстрее на 40%, ствол греется меньше", "category": "fire",
		# Один лишь темп перезарядки ничего не давал: устойчивый огонь упирается
		# не в неё, а в нагрев ствола. Замер непрерывной стрельбы показал +4
		# урона в секунду при обещанных +40% скорострельности — перк снимал
		# ограничение, которое и так не было узким местом.
		"mods": {"fireRateMult": 0.6, "heatPerShotMult": 0.7},
	},
	{
		"id": "explosive", "name": "Взрывные пули", "icon": "💥",
		# Дистанции в описаниях — в метрах, 8 px движка = 1 м на глаз игрока.
		"desc": "Урон по площади 4 м и снос кирпича вокруг", "category": "fire",
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
		"desc": "Перезарядка быстрее на 30%, ствол греется меньше", "category": "speed",
		# То же, что и у «Скорострельности»: замер давал −1 урона в секунду.
		"mods": {"fireRateMult": 0.7, "heatPerShotMult": 0.8},
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
		"challenge": {"desc": "Убей 3 врагов с дистанции 50 м", "stat": "longKills", "need": 3},
	},
	{
		"id": "berserk", "name": "Берсерк", "icon": "😤",
		"desc": "Урон ×1.6, пока ваше HP ≤ 40%", "category": "challenge",
		"flags": ["berserk"],
		"challenge": {"desc": "Убей 5 врагов при HP ≤ 40%", "stat": "lowHpKills", "need": 5},
	},
	{
		"id": "kamikaze", "name": "Камикадзе", "icon": "💀",
		"desc": "При смерти взрыв на 8 м", "category": "challenge",
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
		for p in EXTRA_LIST:
			_by_id[p["id"]] = p
		for p in EXTRA_ACTIVE:
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
		_all = LIST + ACTIVE_LIST + EXTRA_LIST + EXTRA_ACTIVE
	return _all

## Двадцать перков второй волны. Разнесены по тем механикам, которые в игре
## уже есть: нагрев ствола, покрытие под гусеницами, материалы построек и
## слышимость. Числа без механики — это не перк, а строка в таблице.
const EXTRA_LIST := [
	# ------------------------------------------------------------ ствол
	{
		"id": "heat_sink", "name": "Радиатор", "icon": "❄",
		"desc": "Ствол остывает в 1.6 раза быстрее", "category": "fire",
		"mods": {"heatCoolMult": 1.6},
	},
	{
		"id": "thermal", "name": "Термостойкость", "icon": "🌡",
		"desc": "Нагрев за выстрел на четверть меньше", "category": "fire",
		"mods": {"heatPerShotMult": 0.75},
	},
	{
		"id": "quick_vent", "name": "Быстрый сброс", "icon": "💨",
		"desc": "После перегрева огонь возобновляется вдвое раньше", "category": "fire",
		"mods": {"heatResumeAdd": 0.25},
	},
	{
		"id": "heavy_shell", "name": "Тяжёлый снаряд", "icon": "🏋",
		"desc": "Урон +25%, но снаряд летит медленнее", "category": "fire",
		"mods": {"dmgMult": 1.25, "bulletSpeedMult": 0.85},
	},
	{
		"id": "light_shell", "name": "Лёгкий снаряд", "icon": "🪶",
		"desc": "Снаряд быстрее на треть, ствол греется меньше", "category": "fire",
		"mods": {"bulletSpeedMult": 1.3, "heatPerShotMult": 0.8},
	},
	# ---------------------------------------------------------- покрытие
	{
		"id": "road_king", "name": "Асфальтоукладчик", "icon": "🛣",
		"desc": "По асфальту и мостам ход быстрее на 18%", "category": "speed",
		"mods": {"roadSpeedMult": 1.18},
	},
	{
		"id": "all_terrain", "name": "Вездеход", "icon": "🌾",
		"desc": "Трава и песок больше не тормозят", "category": "speed",
		"mods": {"softGrip": 1.0},
	},
	# --------------------------------------------------------- материалы
	{
		"id": "lumberjack", "name": "Лесоруб", "icon": "🪓",
		"desc": "Снаряд прошивает деревянные постройки насквозь", "category": "fire",
		# Было «урон по дереву ×2.5». Это не работало и не могло: пуля игрока
		# наносит постройке 37.5, дерево держит 30 HP при сопротивлении пуле
		# ×1.15 — то есть 43 урона по 30, один выстрел в любом случае. Замер
		# подтвердил: партия с перком проходила побитово как без него, 8 из 8.
		# Теперь перк даёт то, чего множитель дать не мог, — линию огня.
		"flags": ["woodPierce"],
	},
	{
		"id": "concrete_breaker", "name": "Бетонолом", "icon": "🧱",
		"desc": "Урон по бетону ×2.2", "category": "fire",
		"mods": {"concreteDmgMult": 2.2},
	},
	{
		"id": "can_opener", "name": "Консервный нож", "icon": "🔩",
		"desc": "Урон по железу ×2.5 — иначе пули его почти не берут", "category": "fire",
		"mods": {"metalDmgMult": 2.5},
	},
	{
		"id": "scavenger", "name": "Мародёр", "icon": "🧰",
		"desc": "Каждая снесённая рядом постройка чинит на 3 HP", "category": "special",
		"mods": {"scavengeHeal": 3.0},
	},
	# -------------------------------------------------------- слышимость
	{
		"id": "keen_ear", "name": "Острый слух", "icon": "👂",
		"desc": "Дальние выстрелы слышны и отмечаются на миникарте", "category": "special",
		"mods": {"hearingMult": 1.7},
	},
	{
		"id": "muffler", "name": "Глушение", "icon": "🤫",
		"desc": "Выстрелы слышны вдвое ближе, урон по незаметившим +50%",
		"category": "special",
		# Одна тишина была чистым минусом: боты не сбегаются, целей меньше,
		# замер показал −1.0 убийства и −217 урона в минуту при том, что
		# полученный урон не падал. Тишина должна возвращаться засадой.
		"mods": {"noiseMult": 0.5, "ambushDmgMult": 1.5},
	},
]

## Перки с активной способностью. Активный перк отличается тем, что его надо
## нажать вовремя: это единственная механика в игре, где решает момент.
const EXTRA_ACTIVE := [
	{
		"id": "coolant", "name": "Продувка ствола", "icon": "🧊",
		"desc": "Мгновенно сбрасывает весь жар", "category": "fire",
		"active": "coolant",
	},
	{
		"id": "overclock", "name": "Разгон", "icon": "⚙",
		"desc": "2.5 с двойной темп стрельбы, ствол не греется",
		"category": "fire", "active": "overclock",
	},
	{
		"id": "grip", "name": "Шипы", "icon": "🕸",
		"desc": "5 с любое покрытие держит как асфальт", "category": "speed",
		"active": "grip",
	},
	{
		"id": "breaker", "name": "Кумулятив", "icon": "🧨",
		"desc": "5 с пули проходят постройки насквозь и рвут их вчетверо",
		"category": "fire", "active": "breaker",
	},
	{
		"id": "silencer", "name": "Глушитель", "icon": "🔇",
		"desc": "6 с ваши выстрелы боты не слышат вовсе", "category": "special",
		"active": "silencer",
	},
	{
		"id": "smoke", "name": "Дымовая завеса", "icon": "🌫",
		"desc": "5 с боты не видят вас дальше 19 м", "category": "defense",
		"active": "smoke",
	},
	{
		"id": "repair", "name": "Полевой ремонт", "icon": "🔧",
		"desc": "Мгновенно чинит на треть запаса", "category": "defense",
		"active": "repair",
	},
]

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
## Открытие перков по уровню профиля, 1..20.
##
## Порядок не по вкусу, а по трём правилам, и каждое проверяется замером
## (tests/perk_dps.gd — устойчивый урон, tests/perk_bench.gd — бой):
##
##   1. Сначала то, что работает само. Уровни 1..3 — постоянные прибавки
##      к характеристикам: их не надо вовремя нажимать и под них не надо
##      менять поведение.
##   2. Активные способности — с четвёртого уровня и порознь. Это
##      единственная механика, где решает момент, и вываливать её в первый
##      же выбор незачем.
##   3. Сильное и требующее знания карты — в конце. На двадцатом уровне
##      стоят перки с наибольшим замеренным вкладом: «Радиатор» даёт +40
##      урона в секунду при непрерывном огне, «Разгон» — +28.
##
## Прежняя таблица ужимала те же 38 перков в двенадцать уровней по три-четыре
## за раз. К восьмому уровню игрок получал доступ почти ко всему сразу, и
## дальше прогрессия ничего не открывала.
const UNLOCK_TABLE := {
	# --- постоянные прибавки: учат характеристикам
	1: ["rapid_fire", "heavy_armor", "sprinter"],
	2: ["regen", "quick_reload"],
	3: ["double_shot", "evasion"],
	# --- первая активная способность
	4: ["nitro", "shield"],
	# --- покрытие под гусеницами и нагрев ствола: механики города
	5: ["fan_shot", "road_king"],
	6: ["reflect", "thermal"],
	7: ["explosive", "all_terrain"],
	8: ["overdrive", "quick_vent"],
	9: ["piercing", "scavenger"],
	10: ["bulwark", "light_shell"],
	# --- материалы построек: работают, когда игрок уже читает застройку
	11: ["mines", "concrete_breaker"],
	12: ["repair", "heavy_shell"],
	13: ["siege", "grip"],
	14: ["coolant", "can_opener"],
	15: ["lumberjack", "smoke"],
	# --- слышимость и скрытность: требуют понимания поведения ботов
	16: ["keen_ear", "silencer"],
	17: ["muffler", "breaker"],
	# --- вершина: наибольший замеренный вклад
	18: ["shockwave"],
	19: ["heat_sink"],
	20: ["overclock"],
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
				"damageTakenMult", "ramMult", "pickupRadiusMult", "buildingDmgMult", 				"heatPerShotMult", "heatCoolMult", "roadSpeedMult", 				"woodDmgMult", "brickDmgMult", "concreteDmgMult", "metalDmgMult", 				"hearingMult", "noiseMult", "ambushDmgMult":
					m[key] = float(m[key]) * v
				"accuracyBonus", "reflectFraction", "lifestealFraction", "regenPerMinute", 				"heatResumeAdd", "softGrip", "scavengeHeal":
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
