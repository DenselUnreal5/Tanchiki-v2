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
		"dashCooldownMult": 1.0,
		"accuracyBonus": 0.0,
		"evasionChance": 0.0,
		"reflectFraction": 0.0,
		"pickupRadiusMult": 1.0,
		"pickupHealMult": 1.0,
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

		"burnDmgMult": 1.0,
		"burnDurationMult": 1.0,
		"firePatchRadiusMult": 1.0,
		"shockDmgMult": 1.0,
		"stunDurationMult": 1.0,
		"shockReloadMult": 1.0,
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
		"desc": "Стреляет залпом из двух параллельных снарядов по 60% урона каждый (суммарно ×1.2). Выше шанс попасть по прямой линии.", "category": "fire", "flags": ["doubleShot"],
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
		"desc": "Снаряд, попавший в танк, детонирует и наносит 50% урона по площади соседним целям. Работает только с обычной пушкой.", "category": "fire",
		"flags": ["explosive"],
	},
	{
		"id": "piercing", "name": "Пробивной выстрел", "icon": "🎯",
		"desc": "Бронебойные сердечники пробивают первую стену насквозь и поражают спрятавшихся за ней врагов.", "category": "fire", "flags": ["piercing"],
	},

	{
		"id": "heavy_armor", "name": "Усиленный корпус", "icon": "🛡",
		"desc": "Бронеплиты делают корпус танка прочнее на 50% (максимум HP +50%).", "category": "defense", "mods": {"maxHPMult": 1.5},
	},
	{
		"id": "regen", "name": "Регенерация", "icon": "❤",
		"desc": "Полевая ремонтная система восстанавливает броню прямо в бою (60 HP в минуту, по 1 HP в секунду).", "category": "defense",
		"mods": {"regenPerMinute": 60.0},
	},
	{
		"id": "reflect", "name": "Отражение", "icon": "🪞",
		"desc": "Реактивная защита: возвращает 45% полученного урона обратно атаковавшему вас противнику и оглушает его на 0.8 секунды.", "category": "defense",
		"mods": {"reflectFraction": 0.45},
	},
	{
		"id": "evasion", "name": "Уклонение", "icon": "💨",
		"desc": "Отточенные манёвры дают 15% шанс полностью избежать любого вражеского попадания.", "category": "defense",
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
		"desc": "Позволяет закладывать под себя противотанковые мины (до 3 штук на поле, живут 10 секунд). Враги подрываются при наезде.", "category": "special",
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
		"desc": "Удары молнии, которые вызвали вы, рикошетят в 3 ближайших вражеских танка, нанося им 50% урона.",
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
		"desc": "Высокоактивный химический состав: скорость разъедания брони кислотой увеличивается на 50%.",
		"category": "special", "flags": ["corrosiveAcid"],
		"mods": {"acidDmgMult": 1.5},
	},
	{
		"id": "acid_cloud", "name": "Едкое облако", "icon": "☁️",
		"desc": "При предельной концентрации реагента (5 слоёв) корпус цели распыляет токсичный пар, заражая соседнюю технику.",
		"category": "special", "flags": ["acidCloud"],
	},
	{
		"id": "corroding_armor", "name": "Разъедающая броня", "icon": "🦴",
		"desc": "Химическая деградация сплава: пока обшивка поражена кислотой, машина получает на 40% больше урона из всех источников.", "category": "special",
		"flags": ["corrodingArmor"],
	},

	{
		"id": "napalm", "name": "Напалм", "icon": "🔥",
		"desc": "Густая горючая смесь: подожжённые «Огнемётом» враги горят на 50% жарче (15 урона в секунду).",
		"category": "special", "flags": ["napalm"],
		"mods": {"burnDmgMult": 1.5},
	},
	{
		"id": "slow_burn", "name": "Долгое горение", "icon": "⏳",
		"desc": "Пламя «Огнемёта» не гаснет: горение врагов и огненные лужи держатся на 60% дольше.",
		"category": "special", "flags": ["slowBurn"],
		"mods": {"burnDurationMult": 1.6},
	},
	{
		"id": "fire_wall", "name": "Огненный вал", "icon": "🧱",
		"desc": "Широкий факел: лужи пламени на пути снарядов «Огнемёта» становятся на 50% шире и перекрывают проходы.",
		"category": "special", "flags": ["fireWall"],
		"mods": {"firePatchRadiusMult": 1.5},
	},
	{
		"id": "fireproof", "name": "Огнеупорный корпус", "icon": "🛡",
		"desc": "Термостойкая обшивка: ваш танк не загорается — ни от вражеского огня, ни от собственных луж пламени.",
		"category": "special", "flags": ["fireproof"],
	},
	{
		"id": "flashover", "name": "Вспышка", "icon": "💥",
		"desc": "Горящий враг при гибели взрывается огненным шаром: поджигает танки в радиусе 8 метров и оставляет кольцо пламени.",
		"category": "special", "flags": ["flashover"],
	},

	{
		"id": "high_voltage", "name": "Высокое напряжение", "icon": "⚡",
		"desc": "Усиленные катушки «Громовержца»: каждый заряд молнии бьёт на 60% сильнее (16 урона).",
		"category": "special", "flags": ["highVoltage"],
		"mods": {"shockDmgMult": 1.6},
	},
	{
		"id": "long_stun", "name": "Глубокий разряд", "icon": "💫",
		"desc": "Разряд «Громовержца» проникает глубже в электронику: оглушение длится на 50% дольше (1.5 секунды).",
		"category": "special", "flags": ["longStun"],
		"mods": {"stunDurationMult": 1.5},
	},
	{
		"id": "arc_chain", "name": "Цепной разряд", "icon": "🔗",
		"desc": "Молния «Громовержца» перескакивает с цели на 2 ближайших врага в радиусе 13 метров (50% урона и оглушение).",
		"category": "special", "flags": ["arcChain"],
	},
	{
		"id": "capacitor", "name": "Конденсатор", "icon": "🔋",
		"desc": "Быстрая зарядка батарей: перезарядка «Громовержца» быстрее на 25%.",
		"category": "special", "flags": ["capacitor"],
		"mods": {"shockReloadMult": 0.75},
	},
	{
		"id": "overload", "name": "Перегрузка", "icon": "☢",
		"desc": "Оглушённая техника беззащитна: пока враг оглушён, он получает на 30% больше урона из всех источников.",
		"category": "special", "flags": ["overload"],
	},

	{
		"id": "ram", "name": "Таран", "icon": "🚛",
		"desc": "Удваивает урон при столкновениях на скорости. Превращает массу танка в сокрушительное оружие.",
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
		"desc": "Особая ходовая часть не ломает деревья и кустарники при проезде: лес остаётся укрытием для засад.", "category": "challenge",
		"flags": ["forest"],
		"challenge": {"desc": "Проедь сквозь 5 деревьев", "stat": "treesDriven", "need": 5},
	},
	{
		"id": "magnet", "name": "Магнит", "icon": "🧲",
		"desc": "Встроенный манипулятор притягивает аптечки и ящики с оружием, удваивает радиус сбора и повышает лечение от аптечек на 20%.", "category": "challenge",
		"flags": ["magnet"],
		"mods": {"pickupRadiusMult": 2.0, "pickupHealMult": 1.2},
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
		"desc": "При уничтожении танка его боеукладка взрывается, нанося 130 сокрушительного урона в радиусе 8 метров.", "category": "challenge",
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
		"desc": "Вампиризм: 15% от нанесённого урона (Hard Cap: не более 12 HP в секунду) возвращается в виде ремонта вашего танка.", "category": "challenge",
		"mods": {"lifestealFraction": 0.15},
		"challenge": {"desc": "Нанеси 5000 урона за партию", "stat": "damageInGame", "need": 5000},
	},
]

const BOT_LIST := [
	{"id": "bot_rapid", "icon": "⚡", "name": "Скорострельность", "desc": "Перезарядка ускорена на 30%", "mods": {"fireRateMult": 0.7}},
	{"id": "bot_speed", "icon": "👟", "name": "Форсаж", "desc": "Скорость движения увеличена на 30%", "mods": {"speedMult": 1.3}},
	{"id": "bot_tough", "icon": "🛡", "name": "Толстый корпус", "desc": "Корпус прочнее на 40%", "mods": {"maxHPMult": 1.4}},
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
		"desc": "Форсированная продувка: после перегрева танк готов стрелять снова примерно на треть быстрее обычного.", "category": "fire",
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
		"id": "road_king", "name": "Ходовая", "icon": "🛣",
		"desc": "Шоссейные траки и широкие гусеницы: +18% скорости по дорогам и мостам, без штрафа на траве, кустах и песке.", "category": "speed",
		"mods": {"roadSpeedMult": 1.18, "softGrip": 1.0},
	},
	{
		"id": "lumberjack", "name": "Сапёр", "icon": "🪓",
		"desc": "Снаряды прошивают деревянные постройки насквозь, наносят в 2.2 раза больше урона по бетону и в 2.5 раза по металлу.", "category": "fire",
		"flags": ["woodPierce"],
		"mods": {"concreteDmgMult": 2.2, "metalDmgMult": 2.5},
	},
	{
		"id": "scavenger", "name": "Мародёр", "icon": "🧰",
		"desc": "Утилизация обломков: каждая постройка, разрушенная вашим огнём, восстанавливает танку 3 HP.", "category": "special",
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
		"desc": "Активация: на 5 секунд шипы дают +12% к скорости на любой поверхности, включая лёд и грязь, без заносов.", "category": "speed",
		"active": "grip",
	},
	{
		"id": "breaker", "name": "Кумулятив", "icon": "🧨",
		"desc": "Активация: на 5 секунд снаряды пробивают разрушаемые стены насквозь и наносят постройкам четырёхкратный урон.",
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

const CANNON_INCOMPATIBLE := ["fan_shot", "double_shot", "explosive", "piercing", "sky_strike"]

const CANNON_REQUIRED := {
	"deep_freeze": "ice", "frost_dash": "ice", "chilled_barrel": "ice",
	"corrosive_acid": "acid", "acid_cloud": "acid", "corroding_armor": "acid",
	"napalm": "fire", "slow_burn": "fire", "fire_wall": "fire", "fireproof": "fire", "flashover": "fire",
	"high_voltage": "shock", "long_stun": "shock", "arc_chain": "shock", "capacitor": "shock", "overload": "shock",
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
	2: ["regen", "quick_vent"],
	3: ["evasion", "scavenger"],
	4: ["nitro", "shield"],
	5: ["double_shot"],
	6: ["thermal", "lumberjack"],
	7: ["quick_reload"],
	8: ["light_shell", "explosive"],
	9: ["siege", "grip"],
	10: ["mines", "piercing"],
	11: ["fan_shot", "smoke"],
	12: ["reflect", "silencer", "road_king"],
	13: ["bulwark", "breaker", "chilled_barrel"],
	14: ["heavy_shell", "keen_ear", "corrosive_acid"],
	15: ["muffler", "predator", "deep_freeze"],
	16: ["repair", "coolant", "frost_dash", "napalm", "high_voltage"],
	17: ["overdrive", "acid_cloud", "fireproof", "capacitor"],
	18: ["shockwave", "overclock", "corroding_armor", "slow_burn", "long_stun"],
	19: ["heat_sink", "lightning_lord", "fire_wall", "arc_chain"],
	20: ["sky_strike", "chain_lightning", "flashover", "overload"],
}

static func unlock_level_of(perk_id: String) -> int:
	for lvl in UNLOCK_TABLE.keys():
		if UNLOCK_TABLE[lvl].has(perk_id):
			return lvl
	return 0

const BUILDS := [
	{"id": "lightning", "name": "Владыка бури", "color": Color("#f59e0b"),
		"perks": ["lightning_lord", "sky_strike", "chain_lightning"],
		"bonus": "Над ареной разражается вечная гроза, а шанс удара небесной молнии возрастает втрое — с 25% до 40%, но бьёт только по врагам не дальше 60 метров."},
	{"id": "stealth_hunter", "name": "Лесной призрак", "color": Color("#10b981"),
		"perks": ["predator", "forest", "shadow"],
		"bonus": "Маскировка и лесные заросли делают танк неуловимым, а первый выстрел из засады наносит сокрушительный урон (×2.5). На свободных участках вырастают проходимые лесные заросли."},
	{"id": "juggernaut", "name": "Стальной таран", "color": Color("#ef4444"),
		"perks": ["ram", "thick_armor", "kamikaze"],
		"bonus": "Превращает танк в несокрушимый таран: уничтожение врага лобовым ударом вызывает мощную взрывную волну, калечащую и отбрасывающую соседние танки. Появляются полосы обломков: враги на 20% медленнее, владелец и союзники на 12% быстрее."},
	{"id": "ghost_sniper", "name": "Фантомный снайпер", "color": Color("#a855f7"),
		"perks": ["sniper", "evasion", "keen_ear"],
		"bonus": "Идеальная маскировка и прицельный огонь: попадания с дистанции более 35 метров гарантируют критический урон (+60%). На карте появляются участки тумана: дальние цели скрыты, ближе 140 пикселей танки видны."},
	{"id": "ice_hunter", "name": "Абсолютный ноль", "color": Color("#06b6d4"),
		"perks": ["deep_freeze", "frost_dash", "chilled_barrel"],
		"bonus": "Смертоносный холод: выстрелы «Ледяной пушки» мгновенно уничтожают противников с одного удара (не действует на боссов). На карте появляются ледяные участки, замедляющие врагов на 35%."},
	{"id": "acid_hunter", "name": "Чумной шквал", "color": Color("#84cc16"),
		"perks": ["corrosive_acid", "acid_cloud", "corroding_armor"],
		"active": "acid_bomb",
		"bonus": "Дарует способность «Кислотная бомба»: взрывной выброс химического аэрозоля покрывает всю вражескую технику поблизости сразу 3 слоями едкого нагара (перезарядка 10 сек). Кислота разъедает на 40% сильнее. На карте появляются кислотные лужи, а реки становятся кислотными: контакт с берегом разъедает врагов; мосты безопасны."},
	{"id": "fire_hunter", "name": "Инферно", "color": Color("#f97316"),
		"perks": ["napalm", "slow_burn", "flashover"],
		"active": "fire_ring",
		"bonus": "Дарует способность «Огненное кольцо»: танк окружает себя стеной пламени и мгновенно поджигает всех врагов в радиусе 11 метров (перезарядка 10 сек). Горение сильнее на 40%. На карте возникают очаги огня, поджигающие врагов."},
	{"id": "shock_hunter", "name": "Громовой молот", "color": Color("#facc15"),
		"perks": ["high_voltage", "arc_chain", "overload"],
		"active": "storm_pulse",
		"bonus": "Дарует способность «Электробуря»: разряд в радиусе 17 метров наносит 15 урона и оглушает всех врагов на 1.5 секунды, пробивая защиту от повторного стана (перезарядка 12 сек). Разряды «Громовержца» бьют на 40% сильнее, а оглушение длится на 20% дольше. Возникают электрические зоны, а реки электризуются: контакт с берегом бьёт врагов током; мосты безопасны."},
	{"id": "fortress", "name": "Несокрушимая крепость", "color": Color("#3b82f6"),
		"perks": ["heavy_armor", "regen", "shield"],
		"bonus": "Корпус превращается в крепость: получаемый урон снижен ещё на 15%, ремонт восстанавливает дополнительно 90 HP в минуту, а четверть полученного урона возвращается атакующему. Появляются ремонтные зоны: владелец и союзники восстанавливают 1 HP в секунду."},
	{"id": "gunner", "name": "Скорострел", "color": Color("#f43f5e"),
		"perks": ["rapid_fire", "thermal", "heat_sink"],
		"bonus": "Ствол почти не греется: нагрев за выстрел ниже ещё на 25%, а урон каждого выстрела выше на 15%. Появляются зоны охлаждения: владелец и союзники сбрасывают 5 единиц нагрева в секунду."},
]

static func apply_build_mods(mods: Dictionary, ids: Array) -> void:
	if ids == null or ids.is_empty():
		return
	if is_build_complete("fortress", ids):
		mods["damageTakenMult"] = float(mods["damageTakenMult"]) * 0.85
		mods["regenPerMinute"] = float(mods["regenPerMinute"]) + 90.0
		mods["reflectFraction"] = float(mods["reflectFraction"]) + 0.25
	if is_build_complete("gunner", ids):
		mods["heatPerShotMult"] = float(mods["heatPerShotMult"]) * 0.75
		mods["dmgMult"] = float(mods["dmgMult"]) * 1.15
	if is_build_complete("acid_hunter", ids):
		mods["acidDmgMult"] = float(mods.get("acidDmgMult", 1.0)) * 1.4
	if is_build_complete("fire_hunter", ids):
		mods["burnDmgMult"] = float(mods.get("burnDmgMult", 1.0)) * 1.4
	if is_build_complete("shock_hunter", ids):
		mods["shockDmgMult"] = float(mods.get("shockDmgMult", 1.0)) * 1.4
		mods["stunDurationMult"] = float(mods.get("stunDurationMult", 1.0)) * 1.2

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
				"damageTakenMult", "ramMult", "pickupRadiusMult", "pickupHealMult", "buildingDmgMult", \
				"heatPerShotMult", "heatCoolMult", "roadSpeedMult", \
				"woodDmgMult", "brickDmgMult", "concreteDmgMult", "metalDmgMult", \
				"hearingMult", "noiseMult", "ambushDmgMult", \
				"freezeDurationMult", "iceHeatMult", "acidDmgMult", "dashCooldownMult", \
				"burnDmgMult", "burnDurationMult", "firePatchRadiusMult", \
				"shockDmgMult", "stunDurationMult", "shockReloadMult":
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
