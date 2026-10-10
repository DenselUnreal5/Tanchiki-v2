class_name TankClasses
extends RefCounted

const DEFAULT := "standard"

const ADDITIVE_KEYS := ["accuracyBonus", "reflectFraction", "lifestealFraction", "regenPerMinute",
	"heatResumeAdd", "softGrip", "scavengeHeal"]

const LIST := [
	{
		"id": "standard", "name": "Универсал", "icon": "🛡️", "kills": 0, "price": 0,
		"desc": "Основная боевая машина: сбалансированная подвижность, броня и огневая мощь.",
		"trait": "",
		"chassis": "standard", "hp_mult": 1.0, "speed_mult": 1.0, "fire_mult": 1.0, "dmg_mult": 1.0,
		"mods": {}, "lobbed": false,
	},
	{
		"id": "grunt", "name": "Рядовой", "icon": "🪖", "kills": 50, "price": 2000,
		"desc": "Выносливый пехотинец танковых войск: больше прочности ценой небольшой потери хода.",
		"trait": "Выучка: ремонт +30 HP в минуту",
		"chassis": "standard", "hp_mult": 1.15, "speed_mult": 0.95, "fire_mult": 1.0, "dmg_mult": 1.0,
		"mods": {"regenPerMinute": 30.0}, "lobbed": false,
	},
	{
		"id": "scout", "name": "Разведчик", "icon": "🏃", "kills": 60, "price": 3000,
		"desc": "Лёгкая быстрая машина: частые слабые выстрелы, высокая скорость, хрупкая броня.",
		"trait": "Лёгкий ход: 10% шанс уклониться от попадания",
		"chassis": "light", "hp_mult": 0.75, "speed_mult": 1.3, "fire_mult": 0.6, "dmg_mult": 0.6,
		"mods": {"evasionChance": 0.10, "heatPerShotMult": 0.6}, "lobbed": false,
	},
	{
		"id": "heavy", "name": "Громила", "icon": "🏋️", "kills": 75, "price": 4000,
		"desc": "Тяжёлый танк прорыва: вдвое прочнее, медленнее, редкие мощные выстрелы.",
		"trait": "Бронелоб: урон тарана ×1.5",
		"chassis": "heavy", "hp_mult": 2.0, "speed_mult": 0.8, "fire_mult": 1.4, "dmg_mult": 1.4,
		"mods": {"ramMult": 1.5, "heatPerShotMult": 1.4}, "lobbed": false,
	},
	{
		"id": "sniper", "name": "Снайпер", "icon": "🎯", "kills": 90, "price": 5000,
		"desc": "Дальнобойное орудие: редкие выстрелы двойной силы, очень быстрый снаряд.",
		"trait": "Засада: первый выстрел по неготовому врагу ×1.5",
		"chassis": "sniper", "hp_mult": 0.9, "speed_mult": 0.95, "fire_mult": 2.0, "dmg_mult": 2.0,
		"mods": {"ambushDmgMult": 1.5, "heatPerShotMult": 2.0}, "lobbed": false,
	},
	{
		"id": "mortar", "name": "Миномёт", "icon": "💣", "kills": 100, "price": 6000,
		"desc": "Осадная артиллерия: навесные мины перелетают стены и взрываются на цели.",
		"trait": "Навесной выстрел через стены и укрытия",
		"chassis": "mortar", "hp_mult": 1.1, "speed_mult": 0.85, "fire_mult": 2.2, "dmg_mult": 2.2,
		"mods": {"heatPerShotMult": 2.2}, "lobbed": true,
	},
]

const LOBBED_BLOCKED_PERKS := ["fan_shot", "double_shot", "explosive", "piercing", "sky_strike"]

static var _by_id := {}

static func _index() -> void:
	if not _by_id.is_empty():
		return
	for entry in LIST:
		_by_id[entry["id"]] = entry

static func get_entry(id: String) -> Dictionary:
	_index()
	return _by_id.get(id, _by_id[DEFAULT])

static func has(id: String) -> bool:
	_index()
	return _by_id.has(id)

static func ids() -> Array:
	var out := []
	for entry in LIST:
		out.append(String(entry["id"]))
	return out

static func kills_needed(id: String) -> int:
	return int(get_entry(id)["kills"])

static func price(id: String) -> int:
	return int(get_entry(id)["price"])

static func apply_mods(mods: Dictionary, class_id: String) -> void:
	var entry := get_entry(class_id)
	var extra: Dictionary = entry["mods"]
	for key in extra.keys():
		var v := float(extra[key])
		if key == "evasionChance":
			mods[key] = 1.0 - (1.0 - float(mods.get(key, 0.0))) * (1.0 - v)
		elif ADDITIVE_KEYS.has(key):
			mods[key] = float(mods.get(key, 0.0)) + v
		else:
			mods[key] = float(mods.get(key, 1.0)) * v

static func is_lobbed(class_id: String) -> bool:
	return bool(get_entry(class_id)["lobbed"])

static func perk_allowed(perk_id: String, class_id: String) -> bool:
	if not is_lobbed(class_id):
		return true
	if LOBBED_BLOCKED_PERKS.has(perk_id):
		return false
	return not Perks.CANNON_REQUIRED.has(perk_id)

static func display_name(entry: Dictionary) -> String:
	return I18n.dn(entry, "name", "class")

static func trait_text(entry: Dictionary) -> String:
	return I18n.dn(entry, "trait", "class")
