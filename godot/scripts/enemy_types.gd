class_name EnemyTypes
extends RefCounted

const LIST := {
	"grunt": {
		"id": "grunt", "name": "Рядовой", "icon": "🪖",
		"hp_mult": 1.0, "speed_mult": 1.0, "fire_rate_mult": 1.0, "dmg_scale": 1.0,
		"accuracy_bonus": 0.0, "react_mult": 1.0,
		"fire_range": 500.0, "keep_min": 80.0, "keep_max": 250.0,
		"chassis": "standard", "role": "attacker", "color_key": "enemy",
		"weight": 50, "unlock_ramp": 1.0, "lobbed": false, "boss": false,
	},
	"scout": {
		"id": "scout", "name": "Разведчик", "icon": "🏃",
		"hp_mult": 0.75, "speed_mult": 1.3, "fire_rate_mult": 0.5, "dmg_scale": 0.5,
		"accuracy_bonus": -0.1, "react_mult": 0.9,
		"fire_range": 380.0, "keep_min": 60.0, "keep_max": 200.0,
		"chassis": "light", "role": "attacker", "color_key": "scout",
		"weight": 22, "unlock_ramp": 1.0, "lobbed": false, "boss": false,
	},
	"heavy": {
		"id": "heavy", "name": "Громила", "icon": "🛡️",
		"hp_mult": 2.2, "speed_mult": 0.8, "fire_rate_mult": 1.5, "dmg_scale": 1.35,
		"accuracy_bonus": 0.0, "react_mult": 1.1,
		"fire_range": 400.0, "keep_min": 120.0, "keep_max": 280.0,
		"chassis": "heavy", "role": "attacker", "color_key": "heavy",
		"weight": 16, "unlock_ramp": 1.08, "lobbed": false, "boss": false,
	},
	"sniper": {
		"id": "sniper", "name": "Снайпер", "icon": "🎯",
		"hp_mult": 0.9, "speed_mult": 1.0, "fire_rate_mult": 2.2, "dmg_scale": 2.5,
		"accuracy_bonus": 0.18, "react_mult": 1.3,
		"fire_range": 480.0, "keep_min": 300.0, "keep_max": 450.0,
		"chassis": "sniper", "role": "defender", "color_key": "sniper",
		"weight": 10, "unlock_ramp": 1.16, "lobbed": false, "boss": false,
	},
	"mortar": {
		"id": "mortar", "name": "Миномёт", "icon": "💣",
		"hp_mult": 1.1, "speed_mult": 0.85, "fire_rate_mult": 2.5, "dmg_scale": 1.2,
		"accuracy_bonus": 0.0, "react_mult": 1.2,
		"fire_range": 480.0, "keep_min": 320.0, "keep_max": 420.0,
		"chassis": "mortar", "role": "defender", "color_key": "mortar",
		"weight": 8, "unlock_ramp": 1.16, "lobbed": true, "boss": false,
	},
	"boss": {
		"id": "boss", "name": "Бронемонстр", "icon": "👹",
		"hp_mult": 5.0, "speed_mult": 0.75, "fire_rate_mult": 1.2, "dmg_scale": 1.15,
		"accuracy_bonus": 0.1, "react_mult": 1.0,
		"fire_range": 420.0, "keep_min": 100.0, "keep_max": 300.0,
		"chassis": "boss", "role": "attacker", "color_key": "boss",
		"weight": 3, "unlock_ramp": 1.24, "lobbed": false, "boss": true,
	},
	"boss_rammer": {
		"id": "boss_rammer", "name": "Джаггернаут-Таран", "icon": "🦏",
		"hp_mult": 30.0, "speed_mult": 0.85, "fire_rate_mult": 1.0, "dmg_scale": 1.25,
		"accuracy_bonus": 0.0, "react_mult": 1.0,
		"fire_range": 0.0, "keep_min": 0.0, "keep_max": 200.0,
		"chassis": "boss_rammer", "role": "rammer", "color_key": "boss_rammer",
		"weight": 3, "unlock_ramp": 1.24, "lobbed": false, "boss": true,
		"base_hp": Cfg.RAMMER_BOSS_BASE_HP,
	},
	"boss_chimera": {
		"id": "boss_chimera", "name": "Фантом-Химера", "icon": "🧪",
		"hp_mult": 20.0, "speed_mult": 1.25, "fire_rate_mult": 0.85, "dmg_scale": 1.35,
		"accuracy_bonus": 0.15, "react_mult": 0.8,
		"fire_range": 440.0, "keep_min": 140.0, "keep_max": 300.0,
		"chassis": "boss_chimera", "role": "phantom", "color_key": "boss_chimera",
		"weight": 3, "unlock_ramp": 1.24, "lobbed": false, "boss": true,
		"base_hp": Cfg.CHIMERA_BOSS_BASE_HP,
	},
}

const ORDER := ["grunt", "scout", "heavy", "sniper", "mortar", "boss", "boss_rammer", "boss_chimera"]

static func get_type(id: String) -> Dictionary:
	return LIST.get(id, {})

static func pick(ramp: float, rng: Rng, forced: String = "") -> Dictionary:
	if forced != "":
		return LIST.get(forced, LIST["grunt"])
	var pool := []
	for key in ORDER:
		var type: Dictionary = LIST[key]
		if float(type["unlock_ramp"]) > ramp:
			continue
		var ramp_weight := 0.35 if ramp < float(type["unlock_ramp"]) + 0.2 else 1.0
		var n := int(float(type["weight"]) * ramp_weight)
		for i in n:
			pool.append(type)
	if pool.is_empty():
		return LIST["grunt"]
	return pool[int(rng.nextf() * pool.size()) % pool.size()]
