@tool
class_name Perks
extends RefCounted

static func base_modifiers() -> Dictionary:
	return {
		"maxHPMult": 1.0,
		"speedMult": 1.0,
		"fireRateMult": 1.0,
		"dmgMult": 1.0,
		"bulletSpeedMult": 1.0,
		"damageTakenMult": 1.0,
		"ramMult": 1.0,
		"accuracyBonus": 0.0,
		"evasionChance": 0.0,
		"reflectFraction": 0.0,
		"pickupRadiusMult": 1.0,
		"lifestealFraction": 0.0,
		"regenPerMinute": 0.0,
		"buildingDmgMult": 1.0,
		"turboOnKill": 0.0,
		"shadowOnKill": 0.0,

		"heatPerShotMult": 1.0,
		"heatCoolMult": 1.0,
		"heatResumeAdd": 0.0,

		"roadSpeedMult": 1.0,
		"softGrip": 0.0,

		"woodDmgMult": 1.0,
		"brickDmgMult": 1.0,
		"concreteDmgMult": 1.0,
		"metalDmgMult": 1.0,

		"hearingMult": 1.0,
		"noiseMult": 1.0,
		"ambushDmgMult": 1.0,
		"ambushDashTicks": 0.0,

		"scavengeHeal": 0.0,

		"freezeDurationMult": 1.0,
		"freezeDashTicks": 0.0,
		"iceHeatMult": 1.0,

		"acidDmgMult": 1.0,
	}

static var CATEGORIES := [
	{"id": "fire", "name": "Огонь", "color": Color("#e2803a")},
	{"id": "defense", "name": "Защита", "color": Color("#4d95c9")},
	{"id": "speed", "name": "Скорость", "color": Color("#dcd15a")},
	{"id": "special", "name": "Особые", "color": Color("#d966d9")},
	{"id": "challenge", "name": "Челленджи", "color": Color("#d95a63")},
]

const LIST := [
	{
		"id": "double_shot", "name": "Двойной выстрел", "icon": "🔫",
		"desc": "Стреляет залпом из двух параллельных снарядов. Удваивает огневую мощь по прямой линии.", "category": "fire", "flags": ["doubleShot"],
	},
	{
		"id": "fan_shot", "name": "Выстрел веером", "icon": "🌊",
		"desc": "Выпускает веер из трёх снарядов (каждый наносит 45% урона). Накрывает широкую зону перед танком.", "category": "fire", "flags": ["fanShot"],
	},
	{
		"id": "rapid_fire", "name": "Скорострельность", "icon": "⚡",
		"desc": "Ускоряет перезарядку на 40% и снижает нагрев орудия при стрельбе на 30%.", "category": "fire",
		"mods": {"fireRateMult": 0.6, "heatPerShotMult": 0.7},
	},
	{
		"id": "quick_reload", "name": "Быстрая перезарядка", "icon": "🔄",
		"desc": "Перезарядка быстрее на 20%, а нагрев за выстрел снижен на 45%. Позволяет вести непрерывный подавляющий огонь.", "category": "fire",
		"mods": {"fireRateMult": 0.8, "heatPerShotMult": 0.55},
	},
	{
		"id": "explosive", "name": "Взрывные пули", "icon": "💥",
		"desc": "Снаряды детонируют при попадании, нанося урон по площади и мгновенно круша кирпичные стены.", "category": "fire",
		"flags": ["explosive"],
	},
	{
		"id": "piercing", "name": "Пробивной выстрел", "icon": "🎯",
		"desc": "Бронебойные сердечники пробивают первую стену насквозь и поражают спрятавшихся за ней врагов.", "category": "fire", "flags": ["piercing"],
	},

	{
		"id": "heavy_armor", "name": "Тяжёлая броня", "icon": "🛡",
		"desc": "Усиленный бронекорпус увеличивает максимальный запас прочности танка на 50%.", "category": "defense", "mods": {"maxHPMult": 1.5},
	},
	{
		"id": "regen", "name": "Регенерация", "icon": "❤",
		"desc": "Полевая ремонтная система восстанавливает броню прямо в бою (60 HP в минуту, по 1 HP в секунду).", "category": "defense",
		"mods": {"regenPerMinute": 60.0},
	},
	{
		"id": "reflect", "name": "Отражение", "icon": "🪞",
		"desc": "Реактивная защита: возвращает 20% полученного урона обратно атаковавшему вас противнику.", "category": "defense",
		"mods": {"reflectFraction": 0.2},
	},
	{
		"id": "evasion", "name": "Уклонение", "icon": "💨",
		"desc": "Отточенные манёвры дают 15% шанс полностью избежать урона от вражеского снаряда.", "category": "defense",
		"flags": ["evasion"],
		"mods": {"evasionChance": 0.15},
	},
	{
		"id": "shield", "name": "Энергощит", "icon": "🔵",
		"desc": "Персональный силовой барьер поглощает первые 30 урона и сам восстанавливается каждые 30 секунд.", "category": "defense",
		"flags": ["shield"],
	},

	{
		"id": "sprinter", "name": "Спринтер", "icon": "👟",
		"desc": "Форсированная трансмиссия увеличивает максимальную скорость движения танка на 25%.", "category": "speed", "mods": {"speedMult": 1.25},
	},

	{
		"id": "mines", "name": "Миноукладчик", "icon": "💣",
		"desc": "Позволяет сбрасывать противотанковые мины (до 3 штук на поле). Враги подрываются при наезде.", "category": "special",
		"flags": ["mines"],
	},
	{
		"id": "lightning_lord", "name": "Повелитель молний", "icon": "🌩",
		"desc": "Во время грозы с вероятностью 25% призывает небесную молнию по ближайшему вражескому танку.",
		"category": "special", "flags": ["lightningLord"],
	},
	{
		"id": "sky_strike", "name": "Небесный удар", "icon": "⚡",
		"desc": "Во время грозы каждые 12 секунд заряжает выстрел: попадание вызывает дополнительный удар молнии (90 урона).",
		"category": "special", "flags": ["skyStrike"],
	},
	{
		"id": "chain_lightning", "name": "Цепная молния", "icon": "🔗",
		"desc": "Любые удары молнии рикошетят в 3 ближайших вражеских танка, нанося им 50% урона.",
		"category": "special", "flags": ["chainLightning"],
	},

	{
		"id": "deep_freeze", "name": "Глубокая заморозка", "icon": "🧊",
		"desc": "Увеличивает длительность заморозки от «Ледяной пушки» на 50%. Враги дольше остаются неподвижными.",
		"category": "special", "flags": ["deepFreeze"],
		"mods": {"freezeDurationMult": 1.5},
	},
	{
		"id": "frost_dash", "name": "Ледяной рывок", "icon": "💨",
		"desc": "При заморозке противника танк получает ускорение на 1.5 секунды, позволяя мгновенно настичь и протаранить цель.",
		"category": "special", "flags": ["frostDash"],
		"mods": {"freezeDashTicks": 90.0},
	},
	{
		"id": "chilled_barrel", "name": "Охлаждённый ствол", "icon": "❄️",
		"desc": "Снижает нагрев «Ледяной пушки» на 35%, позволяя вести частый огонь без риска перегрева.",
		"category": "special", "flags": ["chilledBarrel"],
		"mods": {"iceHeatMult": 0.65},
	},

	{
		"id": "corrosive_acid", "name": "Едкая кислота", "icon": "🧪",
		"desc": "Усиливает токсичный состав: периодический урон от кислоты возрастает на 50%.",
		"category": "special", "flags": ["corrosiveAcid"],
		"mods": {"acidDmgMult": 1.5},
	},
	{
		"id": "acid_cloud", "name": "Едкое облако", "icon": "☁️",
		"desc": "Танк врага с максимальным отравлением (5 зарядов) выбрасывает ядовитые брызги, заражая соседей.",
		"category": "special", "flags": ["acidCloud"],
	},
	{
		"id": "corroding_armor", "name": "Разъедающая броня", "icon": "🦴",
		"desc": "Кислота истончает броню: пока враг отравлен, он получает на 40% больше урона из любых источников.", "category": "special",
		"flags": ["corrodingArmor"],
	},

	{
		"id": "ram", "name": "Таран", "icon": "🚛",
		"desc": "Удваивает урон при лобовых столкновениях. Превращает массу танка в сокрушительное оружие.",
		"category": "challenge",
		"flags": ["ram"],
		"mods": {"ramMult": 2.0},
		"challenge": {"desc": "Уничтожь 3 танка тараном", "stat": "ramKills", "need": 3},
	},
	{
		"id": "thick_armor", "name": "Толстая броня", "icon": "🧱",
		"desc": "Снижает весь получаемый урон на 20%, но ваши снаряды перестают ломать кирпич, сохраняя его как укрытие.",
		"category": "challenge",
		"mods": {"damageTakenMult": 0.8}, "flags": ["keepBricks", "thickArmor"],
		"challenge": {"desc": "Разрушь 15 кирпичных стен", "stat": "bricksDestroyed", "need": 15},
	},
	{
		"id": "amphibious", "name": "Амфибия", "icon": "🐸",
		"desc": "Герметичный корпус позволяет форсировать реки: вода больше не уничтожает танк, а лишь замедляет ход.", "category": "challenge",
		"flags": ["amphibious"],
		"challenge": {"desc": "Форсируй воду 5 раз", "stat": "waterEntries", "need": 5},
	},
	{
		"id": "forest", "name": "Лесной житель", "icon": "🌲",
		"desc": "Особая ходовая часть позволяет свободно проезжать сквозь деревья и кустарники, используя лес для засад.", "category": "challenge",
		"flags": ["forest"],
		"challenge": {"desc": "Проедь сквозь 5 деревьев", "stat": "treesDriven", "need": 5},
	},
	{
		"id": "magnet", "name": "Магнит", "icon": "🧲",
		"desc": "Встроенный манипулятор удваивает радиус автоматического подбора аптечек и ремонтных наборов.", "category": "challenge",
		"mods": {"pickupRadiusMult": 2.0},
		"challenge": {"desc": "Собери 20 аптечек", "stat": "healthPacksCollected", "need": 20},
	},
	{
		"id": "sniper", "name": "Снайпер", "icon": "🔭",
		"desc": "Нарезной дальнобойный ствол: снаряды летят на 25% быстрее и наносят на 10% больше урона.", "category": "challenge",
		"flags": ["sniper"],
		"mods": {"bulletSpeedMult": 1.25, "dmgMult": 1.1},
		"challenge": {"desc": "Уничтожь 3 врагов с дистанции от 50 метров", "stat": "longKills", "need": 3},
	},
	{
		"id": "berserk", "name": "Берсерк", "icon": "😤",
		"desc": "Когда запас прочности падает ниже 40%, ярость экипажа увеличивает урон всех орудий в 1.6 раза.", "category": "challenge",
		"flags": ["berserk"],
		"challenge": {"desc": "Уничтожь 5 врагов при прочности ≤ 40%", "stat": "lowHpKills", "need": 5},
	},
	{
		"id": "kamikaze", "name": "Камикадзе", "icon": "💀",
		"desc": "При уничтожении танка его боеукладка взрывается, разнося всё живое в радиусе 8 метров.", "category": "challenge",
		"flags": ["kamikaze"],
		"challenge": {"desc": "Погибни в бою 10 раз", "stat": "timesDied", "need": 10},
	},
	{
		"id": "turbo", "name": "Турбо", "icon": "🚀",
		"desc": "Каждое уничтожение врага даёт форсированный импульс ускорения (+50% к скорости) на 4 секунды.", "category": "challenge",
		"mods": {"turboOnKill": 240.0},
		"challenge": {"desc": "Уничтожь 5 врагов за 10 секунд", "stat": "rapidKills", "need": 5},
	},
	{
		"id": "shadow", "name": "Тень", "icon": "🌑",
		"desc": "После каждого фрага танк становится невидимым на 5 секунд: пропадает с экрана и миникарты. Время суммируется.", "category": "challenge",
		"flags": ["shadow"],
		"mods": {"shadowOnKill": Cfg.SHADOW_DURATION},
		"challenge": {"desc": "Уничтожь 3 врагов подряд, не получив урона", "stat": "cleanStreak", "need": 3},
	},
	{
		"id": "vampire", "name": "Вампир", "icon": "🧛",
		"desc": "Вампиризм: 15% от всего нанесённого врагам урона возвращается в виде ремонта вашего танка.", "category": "challenge",
		"mods": {"lifestealFraction": 0.15},
		"challenge": {"desc": "Нанеси 5000 урона за партию", "stat": "damageInGame", "need": 5000},
	},
]

const BOT_LIST := [
	{"id": "bot_rapid", "icon": "⚡", "name": "Скорострельность", "desc": "Перезарядка ускорена на 30%", "mods": {"fireRateMult": 0.7}},
	{"id": "bot_speed", "icon": "👟", "name": "Форсаж", "desc": "Скорость движения увеличена на 30%", "mods": {"speedMult": 1.3}},
	{"id": "bot_tough", "icon": "🛡", "name": "Толстая броня", "desc": "Запас прочности увеличен на 40%", "mods": {"maxHPMult": 1.4}},
	{"id": "bot_double", "icon": "🔫", "name": "Двойной выстрел", "desc": "Стреляет двумя параллельными снарядами", "flags": ["doubleShot"]},
	{"id": "bot_nitro", "icon": "🚀", "name": "Нитро", "desc": "Периодический рывок скорости для сближения", "active": "nitro"},
	{"id": "bot_wave", "icon": "💠", "name": "Ударная волна", "desc": "Круговой импульс, отбрасывающий врагов в упор", "active": "shockwave"},
	{"id": "bot_accurate", "icon": "🎯", "name": "Снайпер", "desc": "Точность наведения увеличена на 15%", "mods": {"accuracyBonus": 0.15}},
	{"id": "bot_regen", "icon": "❤", "name": "Регенерация", "desc": "Постоянный ремонт: 60 HP в минуту", "mods": {"regenPerMinute": 60.0}},
	{"id": "bot_heavy", "icon": "💥", "name": "Тяжёлые пули", "desc": "Урон орудия увеличен на 25%", "mods": {"dmgMult": 1.25}},
	{"id": "bot_evasion", "icon": "💨", "name": "Уклонение", "desc": "15% шанс полностью избежать попадания", "mods": {"evasionChance": 0.15}},
	{"id": "bot_lightning_lord", "icon": "🌩", "name": "Повелитель молний",
		"desc": "В грозу с вероятностью 25% призывает молнию по врагу", "flags": ["lightningLord"]},
	{"id": "bot_sky_strike", "icon": "⚡", "name": "Небесный удар",
		"desc": "В грозу выстрелы периодически бьют дополнительной молнией", "flags": ["skyStrike"]},
	{"id": "bot_chain_lightning", "icon": "🔗", "name": "Цепная молния",
		"desc": "Удары молнии перескакивают по цепочке на соседние танки", "flags": ["chainLightning"]},
	{"id": "bot_boss_twin", "icon": "🔫", "name": "Спаренная установка",
		"desc": "Оба ствола стреляют синхронным залпом", "flags": ["doubleShot"], "boss_only": true},
	{"id": "bot_boss_barrage", "icon": "💢", "name": "Шквальный залп",
		"desc": "Мощный залп веером снарядов по широкому фронту", "active": "boss_barrage", "boss_only": true},
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

static func any_perk_icon(id: String) -> String:
	_index()
	if _by_id.has(id):
		return _by_id[id]["icon"]
	if _bot_by_id.has(id):
		return _bot_by_id[id]["icon"]
	return "⭐"

const ACTIVE_LIST := [
	{
		"id": "siege", "name": "Осадные снаряды", "icon": "🏗",
		"desc": "Усиленный боезапас: урон по любым зданиям и стенам увеличен в 2.2 раза.", "category": "fire",
		"mods": {"buildingDmgMult": 2.2},
	},
	{
		"id": "nitro", "name": "Нитро", "icon": "🚀",
		"desc": "Активация: мгновенный рывок скорости на 2.5 секунды для тарана или быстрого отрыва.", "category": "speed",
		"active": "nitro",
	},
	{
		"id": "overdrive", "name": "Форсаж", "icon": "🔥",
		"desc": "Активация: предельный режим механизмов — удваивает темп стрельбы на 4 секунды.", "category": "fire",
		"active": "overdrive",
	},
	{
		"id": "bulwark", "name": "Бастион", "icon": "🛡",
		"desc": "Активация: включает осадную защиту на 3 секунды, поглощая 60% любого входящего урона.", "category": "defense",
		"active": "bulwark",
	},
	{
		"id": "shockwave", "name": "Ударная волна", "icon": "💠",
		"desc": "Активация: порождает мощный круговой импульс, который ломает стены и раскидывает врагов.", "category": "special",
		"active": "shockwave",
	},
]

static var _all := []

static func all() -> Array:
	if _all.is_empty():
		_all = LIST + ACTIVE_LIST + EXTRA_LIST + EXTRA_ACTIVE
	return _all

const EXTRA_LIST := [
	{
		"id": "heat_sink", "name": "Радиатор", "icon": "❄",
		"desc": "Продвинутая система теплоотвода: ствол орудия остывает в 1.6 раза быстрее.", "category": "fire",
		"mods": {"heatCoolMult": 1.6},
	},
	{
		"id": "thermal", "name": "Термостойкость", "icon": "🌡",
		"desc": "Огнеупорный сплав: снижает нагрев орудия при каждом выстреле на 25%.", "category": "fire",
		"mods": {"heatPerShotMult": 0.75},
	},
	{
		"id": "quick_vent", "name": "Быстрый сброс", "icon": "💨",
		"desc": "Форсированная продувка: после перегрева танк готов стрелять снова вдвое быстрее обычного.", "category": "fire",
		"mods": {"heatResumeAdd": 0.25},
	},
	{
		"id": "heavy_shell", "name": "Тяжёлый снаряд", "icon": "🏋",
		"desc": "Утяжелённый калибр: снаряды бьют на 25% сильнее, но летят на 15% медленнее.", "category": "fire",
		"mods": {"dmgMult": 1.25, "bulletSpeedMult": 0.85},
	},
	{
		"id": "light_shell", "name": "Лёгкий снаряд", "icon": "🪶",
		"desc": "Облегчённый калибр: снаряды летят на 30% быстрее, а нагрев орудия снижен на 20%.", "category": "fire",
		"mods": {"bulletSpeedMult": 1.3, "heatPerShotMult": 0.8},
	},
	{
		"id": "road_king", "name": "Асфальтоукладчик", "icon": "🛣",
		"desc": "Шоссейные траки: увеличивают скорость движения по дорогам, мостам и асфальту на 18%.", "category": "speed",
		"mods": {"roadSpeedMult": 1.18},
	},
	{
		"id": "all_terrain", "name": "Вездеход", "icon": "🌾",
		"desc": "Широкие гусеницы: движение по высокой траве, кустам и песку без штрафа к скорости.", "category": "speed",
		"mods": {"softGrip": 1.0},
	},
	{
		"id": "lumberjack", "name": "Лесоруб", "icon": "🪓",
		"desc": "Снаряды прошивают деревянные постройки и заборы насквозь, не теряя убойной силы.", "category": "fire",
		"flags": ["woodPierce"],
	},
	{
		"id": "concrete_breaker", "name": "Бетонолом", "icon": "🧱",
		"desc": "Кумулятивные наконечники: наносят в 2.2 раза больше урона по бетонным ДОТам и стенам.", "category": "fire",
		"mods": {"concreteDmgMult": 2.2},
	},
	{
		"id": "can_opener", "name": "Консервный нож", "icon": "🔩",
		"desc": "Бронебойные сердечники: наносят в 2.5 раза больше урона по металлическим преградам.", "category": "fire",
		"mods": {"metalDmgMult": 2.5},
	},
	{
		"id": "scavenger", "name": "Мародёр", "icon": "🧰",
		"desc": "Утилизация обломков: разрушение любых построек поблизости восстанавливает танку 3 HP.", "category": "special",
		"mods": {"scavengeHeal": 3.0},
	},
	{
		"id": "keen_ear", "name": "Острый слух", "icon": "👂",
		"desc": "Акустический пеленгатор: слышит далёкие выстрелы, помечает врагов на миникарте и обнаруживает невидимок.", "category": "special",
		"flags": ["keenEar"],
		"mods": {"hearingMult": 1.7},
	},
	{
		"id": "muffler", "name": "Глушение", "icon": "🤫",
		"desc": "Пламегаситель и глушитель: звук выстрелов тише в 2 раза, а атака из засады наносит +50% урона.", "category": "special",
		"mods": {"noiseMult": 0.5, "ambushDmgMult": 1.5},
	},
	{
		"id": "predator", "name": "Хищник", "icon": "🐆",
		"desc": "Внезапная атака из засады или невидимости даёт 2 секунды форсированного ускорения.", "category": "special",
		"flags": ["predator"],
		"mods": {"ambushDashTicks": 120.0},
	},
]

const EXTRA_ACTIVE := [
	{
		"id": "coolant", "name": "Продувка ствола", "icon": "🧊",
		"desc": "Активация: мгновенно охлаждает раскалённое орудие до нормальной температуры.", "category": "fire",
		"active": "coolant",
	},
	{
		"id": "overclock", "name": "Разгон", "icon": "⚙",
		"desc": "Активация: на 2.5 секунды удваивает темп стрельбы и полностью отключает нагрев орудия.",
		"category": "fire", "active": "overclock",
	},
	{
		"id": "grip", "name": "Шипы", "icon": "🕸",
		"desc": "Активация: на 5 секунд даёт идеальное сцепление на льду, в грязи и воде без заносов.", "category": "speed",
		"active": "grip",
	},
	{
		"id": "breaker", "name": "Кумулятив", "icon": "🧨",
		"desc": "Активация: на 5 секунд снаряды пробивают любые стены насквозь с четырёхкратным уроном.",
		"category": "fire", "active": "breaker",
	},
	{
		"id": "silencer", "name": "Глушитель", "icon": "🔇",
		"desc": "Активация: 6 секунд полной тишины — боты не слышат стрельбы, а выстрелы бьют как из засады (+50%).", "category": "special",
		"active": "silencer",
	},
	{
		"id": "smoke", "name": "Дымовая завеса", "icon": "🌫",
		"desc": "Активация: плотная дымовая завеса на 5 секунд скрывает танк, сбивая прицел всем врагам.", "category": "defense",
		"active": "smoke",
	},
	{
		"id": "repair", "name": "Полевой ремонт", "icon": "🔧",
		"desc": "Активация: экстренный ремкомплект, мгновенно восстанавливающий 33% максимальной прочности танка.", "category": "defense",
		"active": "repair",
	},
]

static func active_ability_of(perk_ids: Array, bot: bool = false) -> String:
	if perk_ids == null:
		return ""
	if not bot:
		for b in BUILDS:
			if String(b.get("active", "")) == "":
				continue
			var complete := true
			for pid in (b["perks"] as Array):
				if not perk_ids.has(pid):
					complete = false
					break
			if complete:
				return String(b["active"])
	for id in perk_ids:
		var perk: Dictionary = get_bot_perk(String(id)) if bot else get_perk(String(id))
		if perk.has("active"):
			return String(perk["active"])
	return ""

static func is_active_perk(id: String) -> bool:
	return get_perk(id).has("active")

const MODE_BANNED := {"koth": ["amphibious"]}

static func is_perk_allowed_in_mode(id: String, mode: String) -> bool:
	var banned: Array = MODE_BANNED.get(mode, [])
	return not banned.has(id)

const CANNON_INCOMPATIBLE := ["fan_shot", "double_shot"]

const CANNON_REQUIRED := {
	"deep_freeze": "ice", "frost_dash": "ice", "chilled_barrel": "ice",
	"corrosive_acid": "acid", "acid_cloud": "acid", "corroding_armor": "acid",
}

static func is_perk_allowed_for_cannon(id: String, cannon_id: String) -> bool:
	var effective_cannon: String = cannon_id if cannon_id != "" else "standard"
	if effective_cannon != "standard" and CANNON_INCOMPATIBLE.has(id):
		return false
	var required: String = CANNON_REQUIRED.get(id, "")
	return required == "" or required == effective_cannon

static func filter_perks_for_mode(ids: Array, mode: String) -> Array:
	var out := []
	for id in ids:
		if is_perk_allowed_in_mode(id, mode):
			out.append(id)
	return out

const UNLOCK_TABLE := {
	1: ["rapid_fire", "heavy_armor", "sprinter"],
	2: ["regen", "quick_reload"],
	3: ["double_shot", "evasion"],
	4: ["nitro", "shield"],
	5: ["fan_shot", "road_king"],
	6: ["reflect", "thermal"],
	7: ["explosive", "all_terrain"],
	8: ["overdrive", "quick_vent"],
	9: ["piercing", "scavenger"],
	10: ["bulwark", "light_shell"],
	11: ["mines", "concrete_breaker"],
	12: ["repair", "heavy_shell"],
	13: ["siege", "grip"],
	14: ["coolant", "can_opener"],
	15: ["lumberjack", "smoke"],
	16: ["keen_ear", "silencer"],
	17: ["muffler", "breaker", "predator"],
	18: ["shockwave", "deep_freeze", "frost_dash", "chilled_barrel"],
	19: ["heat_sink", "lightning_lord", "sky_strike",
		"corrosive_acid", "acid_cloud", "corroding_armor"],
	20: ["overclock", "chain_lightning"],
}

static func unlock_level_of(perk_id: String) -> int:
	for lvl in UNLOCK_TABLE.keys():
		if UNLOCK_TABLE[lvl].has(perk_id):
			return lvl
	return 0

const BUILDS := [
	{"id": "lightning", "name": "Владыка бури", "color": Color("#f59e0b"),
		"perks": ["lightning_lord", "sky_strike", "chain_lightning"],
		"bonus": "Над ареной разражается вечная гроза, а шанс удара небесной молнии возрастает втрое — с 25% до 75%."},
	{"id": "stealth_hunter", "name": "Лесной призрак", "color": Color("#10b981"),
		"perks": ["predator", "forest", "shadow"],
		"bonus": "Маскировка и лесные заросли делают танк неуловимым, а первый выстрел из засады наносит сокрушительный урон (×2.5)."},
	{"id": "juggernaut", "name": "Стальной таран", "color": Color("#ef4444"),
		"perks": ["ram", "thick_armor", "kamikaze"],
		"bonus": "Превращает танк в несокрушимый таран: уничтожение врага лобовым ударом вызывает мощную взрывную волну, калечащую и отбрасывающую соседние танки."},
	{"id": "ghost_sniper", "name": "Фантомный снайпер", "color": Color("#a855f7"),
		"perks": ["sniper", "evasion", "keen_ear"],
		"bonus": "Идеальная маскировка и прицельный огонь: попадания с дистанции более 50 метров гарантируют критический урон (+60%)."},
	{"id": "ice_hunter", "name": "Абсолютный ноль", "color": Color("#06b6d4"),
		"perks": ["deep_freeze", "frost_dash", "chilled_barrel"],
		"bonus": "Смертоносный холод: выстрелы «Ледяной пушки» мгновенно уничтожают противников с одного удара (не действует на боссов)."},
	{"id": "acid_hunter", "name": "Чумной шквал", "color": Color("#84cc16"),
		"perks": ["corrosive_acid", "acid_cloud", "corroding_armor"],
		"active": "acid_bomb",
		"bonus": "Дарует способность «Кислотная бомба»: мощный выброс ядовитого аэрозоля заражает всех врагов вокруг сразу 3 слоями кислоты (перезарядка 10 сек)."},
]

static func builds_with_perk(perk_id: String) -> Array:
	var out := []
	for b in BUILDS:
		if (b["perks"] as Array).has(perk_id):
			out.append(b)
	return out

static func get_build(build_id: String) -> Dictionary:
	for b in BUILDS:
		if b["id"] == build_id:
			return b
	return {}

static func is_build_complete(build_id: String, ids: Array) -> bool:
	if ids == null or ids.is_empty():
		return false
	var b := get_build(build_id)
	if b.is_empty():
		return false
	for pid in (b["perks"] as Array):
		if not ids.has(pid):
			return false
	return true

static func completed_builds(ids: Array) -> Array:
	var out := []
	if ids == null or ids.is_empty():
		return out
	for b in BUILDS:
		var ok := true
		for pid in (b["perks"] as Array):
			if not ids.has(pid):
				ok = false
				break
		if ok:
			out.append(b)
	return out

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
				"damageTakenMult", "ramMult", "pickupRadiusMult", "buildingDmgMult", 				"heatPerShotMult", "heatCoolMult", "roadSpeedMult", 				"woodDmgMult", "brickDmgMult", "concreteDmgMult", "metalDmgMult", 				"hearingMult", "noiseMult", "ambushDmgMult", 				"freezeDurationMult", "iceHeatMult", "acidDmgMult":
					m[key] = float(m[key]) * v
				"accuracyBonus", "reflectFraction", "lifestealFraction", "regenPerMinute", 				"heatResumeAdd", "softGrip", "scavengeHeal":
					m[key] = float(m[key]) + v
				"evasionChance":
					evasion_miss *= (1.0 - v)
				"turboOnKill", "shadowOnKill", "ambushDashTicks", "freezeDashTicks":
					m[key] = maxf(float(m[key]), v)
	m["evasionChance"] = 1.0 - evasion_miss
	return m

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
