# ============================================================================
# weapons.gd — временное оружие с карты (power-up).
#
# Каждое оружие меняет поведение выстрела танка на ограниченное время.
# По истечении таймера танк возвращается к штатному пулемёту.
# ============================================================================
class_name Weapons
extends RefCounted

static var LIST := {
	"gatling": {
		"id": "gatling", "name": "Пулемёт", "icon": "🔥", "color": Color("#ffaa33"),
		"duration": 60 * 8,      # 8 секунд
		"cooldown_mult": 0.45,   # стреляет вдвое чаще
		"dmg_scale": 0.55,       # но каждая пуля слабее
		"spread": 0.06, "bullets": 1, "explosive": false,
	},
	"rockets": {
		"id": "rockets", "name": "Ракеты", "icon": "🚀", "color": Color("#ff5566"),
		"duration": 60 * 8,
		"cooldown_mult": 2.2,
		"dmg_scale": 1.9,
		"spread": 0.02, "bullets": 1, "explosive": true,
	},
	"shotgun": {
		"id": "shotgun", "name": "Дробовик", "icon": "💥", "color": Color("#ffcc44"),
		"duration": 60 * 6,
		"cooldown_mult": 2.0,
		"dmg_scale": 0.4,
		"spread": 0.22, "bullets": 6, "explosive": false,
	},
}

static func get_weapon(id: String) -> Dictionary:
	return LIST.get(id, {})

static func ids() -> Array:
	return LIST.keys()
