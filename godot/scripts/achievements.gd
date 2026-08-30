# ============================================================================
# achievements.gd — постоянные достижения профиля с монетной наградой.
#
# От перков отличаются тем, что это не «способности», а вехи прогресса.
# Проверяются после каждой записи в статистику профиля.
# ============================================================================
class_name Achievements
extends RefCounted

## id — уникальный ключ, stat — ключ статистики, need — порог,
## reward — монеты, icon — эмодзи карточки.
const LIST := [
	{"id": "first_blood", "name": "Первая кровь", "desc": "Первое убийство", "icon": "🎯", "stat": "totalKills", "need": 1, "reward": 10},
	{"id": "kill_10", "name": "Ветеран", "desc": "10 убийств", "icon": "🔫", "stat": "totalKills", "need": 10, "reward": 25},
	{"id": "kill_50", "name": "Машина для убийств", "desc": "50 убийств", "icon": "💀", "stat": "totalKills", "need": 50, "reward": 50},
	{"id": "kill_250", "name": "Палач", "desc": "250 убийств", "icon": "🔥", "stat": "totalKills", "need": 250, "reward": 120},
	{"id": "ram_10", "name": "Тарановод", "desc": "10 убийств тараном", "icon": "🚛", "stat": "ramKills", "need": 10, "reward": 30},
	{"id": "ram_50", "name": "Бронированный таран", "desc": "50 убийств тараном", "icon": "💢", "stat": "ramKills", "need": 50, "reward": 80},
	{"id": "bricks_100", "name": "Разрушитель", "desc": "Снести 100 кирпичей", "icon": "🧱", "stat": "bricksDestroyed", "need": 100, "reward": 30},
	{"id": "bricks_500", "name": "Строительный магнат", "desc": "Снести 500 кирпичей", "icon": "🏚️", "stat": "bricksDestroyed", "need": 500, "reward": 90},
	{"id": "medkits_25", "name": "Санитар", "desc": "Подобрать 25 аптечек", "icon": "🩹", "stat": "healthPacksCollected", "need": 25, "reward": 30},
	{"id": "medkits_100", "name": "Медик полка", "desc": "Подобрать 100 аптечек", "icon": "⛑️", "stat": "healthPacksCollected", "need": 100, "reward": 90},
	{"id": "wins_5", "name": "Первая победа", "desc": "5 побед", "icon": "🏆", "stat": "gamesWon", "need": 5, "reward": 40},
	{"id": "wins_25", "name": "Чемпион", "desc": "25 побед", "icon": "👑", "stat": "gamesWon", "need": 25, "reward": 120},
	{"id": "games_10", "name": "Заядлый игрок", "desc": "Сыграть 10 партий", "icon": "🎮", "stat": "gamesPlayed", "need": 10, "reward": 30},
	{"id": "games_50", "name": "Легенда аркад", "desc": "Сыграть 50 партий", "icon": "🕹️", "stat": "gamesPlayed", "need": 50, "reward": 100},
	{"id": "long_20", "name": "Снайпер", "desc": "20 убийств с 400 px", "icon": "🔭", "stat": "longKills", "need": 20, "reward": 50},
	{"id": "lowhp_10", "name": "Берсерк", "desc": "10 убийств при HP ≤ 40%", "icon": "😤", "stat": "lowHpKills", "need": 10, "reward": 50},
	{"id": "streak_10", "name": "Неприкасаемый", "desc": "Серия из 10 убийств без урона", "icon": "✨", "stat": "cleanStreak", "need": 10, "reward": 80},
	{"id": "rapid_5", "name": "Шквал", "desc": "5 убийств за 10 секунд", "icon": "⚡", "stat": "rapidKills", "need": 5, "reward": 60},
	{"id": "bridge_defender", "name": "Защитник моста", "desc": "15 убийств на мосту", "icon": "🌉", "stat": "bridgeKills", "need": 15, "reward": 70},
	{"id": "demolition", "name": "Подрывник", "desc": "Снести 60 бетонных и железных построек", "icon": "🏗️", "stat": "concreteDestroyed", "need": 60, "reward": 70},
	{"id": "demolition_master", "name": "Мастер сноса", "desc": "Снести 250 бетонных и железных построек", "icon": "🧨", "stat": "concreteDestroyed", "need": 250, "reward": 140},
	{"id": "eagle_ear", "name": "Орлиный слух", "desc": "15 убийств с 800 px", "icon": "🦅", "stat": "sniperKills", "need": 15, "reward": 90},
	{"id": "ability_50", "name": "Козырь в рукаве", "desc": "50 раз применить способность", "icon": "✦", "stat": "abilityUses", "need": 50, "reward": 40},
	{"id": "ability_250", "name": "Мастер манёвра", "desc": "250 раз применить способность", "icon": "⚡", "stat": "abilityUses", "need": 250, "reward": 110},
	{"id": "damage_1000", "name": "Артобстрел", "desc": "1000 урона за одну партию", "icon": "💥", "stat": "damageInGame", "need": 1000, "reward": 60},
]

static func get_achievement(id: String) -> Dictionary:
	for a in LIST:
		if a["id"] == id:
			return a
	return {}
