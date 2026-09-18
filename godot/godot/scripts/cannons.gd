# ============================================================================
# cannons.gd — сменные пушки, выбираемые в гараже за монеты.
#
# Как weapons.gd (подбираемое оружие), но выбор постоянный, а не временный
# подбор на карте: "standard" всегда доступна и ничего не меняет, "ice"/
# "acid" покупаются и полностью заменяют выстрел (см. Tank.shoot()) — так
# же, как это уже делает подобранное оружие, а не складываются с «Веером»/
# «Двойным стволом».
# ============================================================================
class_name Cannons
extends RefCounted

const LIST := [
	{
		"id": "standard", "name": "Стандартная пушка", "icon": "🔫",
		"desc": "Базовое орудие без особенностей.",
		"price": 0, "mode": "standard",
		"dmg_scale": 1.0, "cooldown_mult": 1.0, "heat_mult": 1.0,
	},
	{
		"id": "ice", "name": "Ледяная пушка", "icon": "❄️",
		"desc": "Не наносит урона, но замораживает цель на 4 секунды. Таран по замороженному танку убивает его мгновенно.",
		"price": 400, "mode": "freeze",
		"dmg_scale": 0.0, "cooldown_mult": 1.2, "heat_mult": 3.0,
		"color": Color("#7fdfff"),
	},
	{
		"id": "acid", "name": "Кислотная пушка", "icon": "🧪",
		"desc": "Каждое попадание накладывает стакающийся яд (до 5 стаков, 5 секунд).",
		"price": 450, "mode": "acid",
		"dmg_scale": 1.0, "cooldown_mult": 0.9, "heat_mult": 0.85,
		"color": Color("#9dff5c"),
	},
]

## Пусто, если id неизвестен — как у Cosmetics.get_cosmetic(). Profile.gd
## полагается именно на этот контракт (is_cannon_owned/buy_cannon отличают
## "неизвестная пушка" от "стандартная"); вызовы, которым нужен безопасный
## фолбэк на стандартную пушку (например Tank.shoot()), должны сами
## проверять cannon_id перед вызовом, а не полагаться на скрытый дефолт здесь.
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

## Акцентный цвет пушки по mode пули ("freeze"/"acid" — как хранится в
## Bullet.cannon_kind, это НЕ id пушки), либо прозрачный цвет, если для
## этого mode цвет не задан (обычный выстрел, mode == "").
static func color_for_mode(mode: String) -> Color:
	if mode == "":
		return Color(0, 0, 0, 0)
	for c in LIST:
		if String(c.get("mode", "")) == mode and c.has("color"):
			return c["color"]
	return Color(0, 0, 0, 0)
