class_name TankClasses
extends RefCounted

const DEFAULT := "standard"
const GUARD_HP_FRACTION := 0.4

const ADDITIVE_KEYS := ["accuracyBonus", "reflectFraction", "lifestealFraction", "regenPerMinute",
	"heatResumeAdd", "softGrip", "scavengeHeal", "turboOnKill"]

const LIST := [
	{
		"id": "standard", "name": "Универсал", "icon": "🛡️", "kills": 0, "price": 0,
		"desc": "Основная боевая машина: сбалансированная подвижность, броня и огневая мощь.",
		"trait": "Адаптация: +10% опыта матча, перки приходят чаще",
		"chassis": "standard", "hp_mult": 1.0, "speed_mult": 1.0, "fire_mult": 1.0, "dmg_mult": 1.0,
		"mods": {}, "lobbed": false, "xp_mult": 1.1,
	},
	{
		"id": "grunt", "name": "Рядовой", "icon": "🪖", "kills": 50, "price": 2000,
		"desc": "Выносливый пехотинец танковых войск: больше прочности ценой небольшой потери хода.",
		"trait": "Стойкость: аптечки лечат на 30% сильнее, ремонт 60 HP/мин, ниже 40% HP урон −15%",
		"chassis": "standard", "hp_mult": 1.15, "speed_mult": 0.95, "fire_mult": 1.0, "dmg_mult": 1.0,
		"mods": {"regenPerMinute": 60.0, "pickupHealMult": 1.3}, "lobbed": false, "guard_mult": 0.85,
	},
	{
		"id": "scout", "name": "Разведчик", "icon": "🏃", "kills": 60, "price": 3000,
		"desc": "Лёгкая быстрая машина: частые слабые выстрелы, высокая скорость, хрупкая броня.",
		"trait": "Призрачный ход: уклонение 15% (+10% в движении), рывок на 30% чаще, таран ×1.5, ускорение на 2 с после уничтожения врага",
		"chassis": "light", "hp_mult": 0.85, "speed_mult": 1.3, "fire_mult": 0.6, "dmg_mult": 0.6,
		"mods": {"evasionChance": 0.15, "heatPerShotMult": 0.6, "dashCooldownMult": 0.7, "ramMult": 1.5, "turboOnKill": 120.0},
		"lobbed": false, "move_evasion": 0.10,
	},
	{
		"id": "heavy", "name": "Громила", "icon": "🏋️", "kills": 75, "price": 4000,
		"desc": "Тяжёлый танк прорыва: вдвое прочнее, медленнее, редкие мощные выстрелы.",
		"trait": "Несокрушимый: не оглушается, заморозка действует вдвое короче, урон тарана ×3",
		"chassis": "heavy", "hp_mult": 2.0, "speed_mult": 0.8, "fire_mult": 1.4, "dmg_mult": 1.4,
		"mods": {"ramMult": 3.0, "heatPerShotMult": 1.4}, "lobbed": false, "stun_immune": true, "freeze_mult": 0.5,
	},
	{
		"id": "sniper", "name": "Снайпер", "icon": "🎯", "kills": 90, "price": 5000,
		"desc": "Дальнобойное орудие: редкие выстрелы двойной силы, очень быстрый снаряд.",
		"trait": "Засада: первый выстрел по неготовому врагу ×1.3, но выстрел слышно на 40% дальше",
		"chassis": "sniper", "hp_mult": 0.9, "speed_mult": 0.95, "fire_mult": 2.0, "dmg_mult": 2.0,
		"mods": {"ambushDmgMult": 1.3, "noiseMult": 1.4, "heatPerShotMult": 2.0}, "lobbed": false,
	},
	{
		"id": "mortar", "name": "Миномёт", "icon": "💣", "kills": 100, "price": 6000,
		"desc": "Осадная артиллерия: мины перелетают стены и падают на цель, взрываясь по площади.",
		"trait": "Навесной огонь: мина летит через стены к ближайшему врагу на линии прицела, здания разрушаются на 50% сильнее",
		"chassis": "mortar", "hp_mult": 1.1, "speed_mult": 0.85, "fire_mult": 2.2, "dmg_mult": 2.2,
		"mods": {"heatPerShotMult": 2.2, "buildingDmgMult": 1.5}, "lobbed": true,
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

static func xp_mult(id: String) -> float:
	return float(get_entry(id).get("xp_mult", 1.0))

static func guard_mult(id: String) -> float:
	return float(get_entry(id).get("guard_mult", 1.0))

static func move_evasion(id: String) -> float:
	return float(get_entry(id).get("move_evasion", 0.0))

static func stun_immune(id: String) -> bool:
	return bool(get_entry(id).get("stun_immune", false))

static func freeze_mult(id: String) -> float:
	return float(get_entry(id).get("freeze_mult", 1.0))

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

static func player_tank_opts(class_id: String, base_hp: float) -> Dictionary:
	var entry := get_entry(class_id)
	return {
		"max_hp": round(base_hp * float(entry["hp_mult"])),
		"speed": Cfg.PLAYER_SPEED * float(entry["speed_mult"]),
		"fire_rate": maxi(4, int(round(float(Cfg.PLAYER_FIRE_RATE) * float(entry["fire_mult"])))),
		"dmg_scale": Cfg.PLAYER_DMG_MULT * float(entry["dmg_mult"]),
		"class_id": String(entry["id"]),
		"chassis": String(entry["chassis"]),
	}

static func final_stats(class_id: String, upgrade_mods: Dictionary, base_hp: float) -> Dictionary:
	var opts := player_tank_opts(class_id, base_hp)
	opts.merge({"x": 0.0, "y": 0.0, "team": "player", "name": "",
		"owner": PlayerState.new(0, "", "p1", null), "upgrade_mods": upgrade_mods})
	var t := Tank.new(opts)
	var heat := Cfg.HEAT_PER_SHOT * float(t.mods["heatPerShotMult"])
	return {
		"hp": int(t.max_hp),
		"speed_pct": int(round(t.speed / Cfg.PLAYER_SPEED * 100.0)),
		"dmg": int(round((Cfg.BULLET_DMG_MIN + Cfg.BULLET_DMG_MAX) * 0.5 * t.dmg_scale * float(t.mods["dmgMult"]))),
		"reload": float(t.fire_rate) / float(Cfg.TICK_HZ),
		"overheat_shots": int(ceil(1.0 / heat)) if heat > 0.0 else 0,
		"fire_rate": t.fire_rate,
		"speed": t.speed,
	}

static func display_name(entry: Dictionary) -> String:
	return I18n.dn(entry, "name", "class")

static func trait_text(entry: Dictionary) -> String:
	return I18n.dn(entry, "trait", "class")
