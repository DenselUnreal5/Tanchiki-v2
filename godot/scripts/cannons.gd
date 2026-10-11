@tool
class_name Cannons
extends RefCounted

const LIST := [
	{
		"id": "standard", "name": "Стандартная пушка", "icon": "🔫",
		"desc": "Базовое нарезное орудие. Пассивный бонус: баллистическая стабилизация даёт +15% к скорости полёта снаряда.",
		"price": 0, "mode": "standard",
		"dmg_scale": 1.0, "cooldown_mult": 1.0, "heat_mult": 1.0, "bullet_speed_mult": 1.15,
	},
	{
		"id": "ice", "name": "Ледяная пушка", "icon": "❄️",
		"desc": "Криогенные снаряды лишают цель подвижности на 4 секунды. Скованная ледяным панцирем броня становится хрупкой и мгновенно раскалывается от таранного удара.",
		"price": 400, "mode": "freeze",
		"dmg_scale": 0.0, "cooldown_mult": 1.2, "heat_mult": 2.15,
		"color": Color("#7fdfff"),
	},
	{
		"id": "acid", "name": "Кислотная пушка", "icon": "🧪",
		"desc": "Снаряды распыляют агрессивный химикат, разъедающий обшивку (до 5 слоёв коррозии на 3 секунды). Урон возрастает с каждым новым попаданием.",
		"price": 450, "mode": "acid",
		"dmg_scale": 1.0, "cooldown_mult": 0.9, "heat_mult": 0.85,
		"color": Color("#9dff5c"),
	},
	{
		"id": "fire", "name": "Огнемёт", "icon": "🔥",
		"desc": "Сгусток пламени поджигает землю на всём пути полёта и саму цель: горящий танк получает 10 урона в секунду, а его ствол быстрее перегревается. Вода тушит огонь.",
		"price": 1500, "mode": "fire", "special": true,
		"dmg_scale": 0.0, "cooldown_mult": 0.8, "heat_mult": 1.2,
		"color": Color("#f97316"),
		"challenge": {"stat": "pyroBurnKills", "need": 10, "desc": "Уничтожьте 10 Огнемётчиков, пока ваш танк горит"},
	},
	{
		"id": "shock", "name": "Громовержец", "icon": "⚡",
		"desc": "Стремительный заряд молнии наносит 10 урона и оглушает цель на 1 секунду. После оглушения цель ненадолго получает защиту от повторного стана.",
		"price": 1800, "mode": "shock", "special": true,
		"dmg_scale": 1.0, "cooldown_mult": 1.6, "heat_mult": 1.5,
		"color": Color("#facc15"),
		"challenge": {"stat": "lightningDodges", "need": 10, "desc": "Уклонитесь рывком (Shift) от 10 молний"},
	},
]

static func get_cannon(id: String) -> Dictionary:
	for c in LIST:
		if c["id"] == id:
			return c
	return {}

static func ids() -> Array:
	var out := []
	for c in LIST:
		out.append(c["id"])
	return out

static func is_special(id: String) -> bool:
	return bool(get_cannon(id).get("special", false))

static func challenge_of(id: String) -> Dictionary:
	return get_cannon(id).get("challenge", {})

static func color_for_mode(mode: String) -> Color:
	if mode == "":
		return Color(0, 0, 0, 0)
	for c in LIST:
		if String(c.get("mode", "")) == mode and c.has("color"):
			return c["color"]
	return Color(0, 0, 0, 0)
