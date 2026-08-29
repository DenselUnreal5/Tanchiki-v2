# ============================================================================
# daily.gd — ежедневные задания с наградой монетами.
#
# Прогресс сбрасывается в полночь. Задания сдвигаются по кругу: каждый день
# выбирается подмножество из общего списка.
#
# Прогресс пополняется вызовом Prof.bump_daily(counter, amount) из игровых
# событий. Ключи-счётчики: kills, wins, captures, coins, games, damage,
# medkits, streak.
# ============================================================================
class_name Daily
extends RefCounted

## Ключ текущего дня в формате YYYY-MM-DD (локальное время).
static func today_key() -> String:
	var d := Time.get_datetime_dict_from_system(false)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

const LIST := [
	{"id": "kill_15", "name": "Охота", "desc": "Убить 15 врагов", "icon": "🔫", "counter": "kills", "need": 15, "reward": 50},
	{"id": "win_2", "name": "Триумф", "desc": "Одержать 2 победы", "icon": "🏆", "counter": "wins", "need": 2, "reward": 45},
	{"id": "capture_2", "name": "Флаг в руки", "desc": "Захватить 2 флага", "icon": "🚩", "counter": "captures", "need": 2, "reward": 45},
	{"id": "coins_100", "name": "Казначей", "desc": "Заработать 100 монет", "icon": "💰", "counter": "coins", "need": 100, "reward": 55},
	{"id": "games_3", "name": "Трудоголик", "desc": "Сыграть 3 партии", "icon": "🎮", "counter": "games", "need": 3, "reward": 35},
	{"id": "damage_2000", "name": "Артиллерия", "desc": "Нанести 2000 урона", "icon": "💥", "counter": "damage", "need": 2000, "reward": 50},
	{"id": "medkits_5", "name": "Полевой врач", "desc": "Подобрать 5 аптечек", "icon": "🩹", "counter": "medkits", "need": 5, "reward": 40},
	{"id": "streak_5", "name": "Фортуна", "desc": "Серия 5 убийств без урона", "icon": "🍀", "counter": "streak", "need": 5, "reward": 60},
]

## Сколько заданий выдаётся в день.
const PER_DAY := 4

## Выбирает подмножество заданий дня по дате (детерминированно).
static func selection() -> Array:
	var key := today_key()
	var sum := 0
	for i in key.length():
		sum += key.unicode_at(i)
	var start := sum % LIST.size()
	var out := []
	for i in PER_DAY:
		out.append(LIST[(start + i) % LIST.size()])
	return out

static func get_quest(id: String) -> Dictionary:
	for q in LIST:
		if q["id"] == id:
			return q
	return {}
