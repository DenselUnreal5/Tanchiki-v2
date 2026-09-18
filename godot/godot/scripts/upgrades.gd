# ============================================================================
# upgrades.gd — постоянные улучшения танка за валюту (Гараж).
#
# Улучшения живут в профиле и действуют на каждого живого игрока в партии.
# Эффект задаётся так же, как у перков: профильный бонус перемножается
# с бонусом перков в Tank.recompute().
# ============================================================================
class_name Upgrades
extends RefCounted

## Категории улучшений — порядок разделов в Гараже.
static var CATEGORIES := [
	{"id": "fire", "name": "Огонь", "color": Color("#e2803a")},
	{"id": "defense", "name": "Защита", "color": Color("#4d95c9")},
	{"id": "speed", "name": "Скорость", "color": Color("#dcd15a")},
	{"id": "utility", "name": "Полезное", "color": Color("#5fbf83")},
]

## cost_base/cost_step — цена уровня: base + (level - 1) * step.
## mult_step — шаг эффекта, mult_mode: add (1 + lvl*step), sub (1 - lvl*step),
## flat (lvl*step).
const LIST := [
	{
		"id": "dmg", "name": "Мощный ствол", "icon": "💥", "desc": "Урон своих пуль",
		"category": "fire", "mod_key": "dmgMult", "max_level": 10,
		"cost_base": 60, "cost_step": 25, "mult_step": 0.06, "mult_mode": "add",
	},
	{
		"id": "fire_rate", "name": "Автоускоритель", "icon": "⚡", "desc": "Перезарядка быстрее",
		"category": "fire", "mod_key": "fireRateMult", "max_level": 10,
		"cost_base": 50, "cost_step": 20, "mult_step": 0.03, "mult_mode": "sub",
	},
	{
		"id": "bullet_speed", "name": "Тяжёлые снаряды", "icon": "🚀", "desc": "Скорость полёта пуль",
		"category": "fire", "mod_key": "bulletSpeedMult", "max_level": 8,
		"cost_base": 40, "cost_step": 15, "mult_step": 0.05, "mult_mode": "add",
	},
	{
		"id": "max_hp", "name": "Усиленная броня", "icon": "🛡", "desc": "Максимум HP",
		"category": "defense", "mod_key": "maxHPMult", "max_level": 10,
		"cost_base": 55, "cost_step": 25, "mult_step": 0.07, "mult_mode": "add",
	},
	{
		"id": "damage_taken", "name": "Композитная броня", "icon": "🧱", "desc": "Получаемый урон меньше",
		"category": "defense", "mod_key": "damageTakenMult", "max_level": 8,
		"cost_base": 70, "cost_step": 30, "mult_step": 0.04, "mult_mode": "sub",
	},
	{
		"id": "speed", "name": "Форсированный мотор", "icon": "👟", "desc": "Предельная скорость",
		"category": "speed", "mod_key": "speedMult", "max_level": 10,
		"cost_base": 45, "cost_step": 20, "mult_step": 0.045, "mult_mode": "add",
	},
	{
		"id": "ram", "name": "Бронекаток", "icon": "🚛", "desc": "Урон тараном",
		"category": "speed", "mod_key": "ramMult", "max_level": 8,
		"cost_base": 50, "cost_step": 22, "mult_step": 0.1, "mult_mode": "add",
	},
	{
		"id": "pickup_radius", "name": "Магнитный трал", "icon": "🧲", "desc": "Радиус подбора аптечек",
		"category": "utility", "mod_key": "pickupRadiusMult", "max_level": 6,
		"cost_base": 35, "cost_step": 15, "mult_step": 0.15, "mult_mode": "add",
	},
	{
		"id": "regen", "name": "Ремонтный модуль", "icon": "❤", "desc": "HP в минуту",
		"category": "utility", "mod_key": "regenPerMinute", "max_level": 6,
		"cost_base": 55, "cost_step": 25, "mult_step": 20.0, "mult_mode": "flat",
	},
]

static func get_upgrade(id: String) -> Dictionary:
	for u in LIST:
		if u["id"] == id:
			return u
	return {}

## Цена следующего уровня (level — уже купленный уровень).
static func cost(up: Dictionary, level: int) -> int:
	var next_level := level + 1
	return int(round(float(up["cost_base"]) + float(next_level - 1) * float(up["cost_step"])))

## Итоговый множитель (или прибавка) на купленном уровне.
static func mult(up: Dictionary, level: int) -> float:
	var step: float = float(up["mult_step"])
	match String(up["mult_mode"]):
		"add":
			return 1.0 + level * step
		"sub":
			return 1.0 - level * step
		_:
			return level * step
