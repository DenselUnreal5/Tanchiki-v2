# ============================================================================
# ranks.gd — воинские звания за уровень профиля.
#
# У перков и улучшений Гаража есть потолок: всё открывается к 20 уровню
# профиля (Perks.UNLOCK_TABLE), а сам профиль тем временем растёт до 999
# (Profile.global_level, config.gd). Без этого файла всё, что происходит
# после двадцатого уровня, — просто цифра, которая крутится в никуда.
#
# Звание — не бонус танку, никаких mod_key тут нет: это видимая метка того,
# что происходило после «контента», плюс разовая монетная награда за
# каждую новую ступень, чтобы это было заметно, а не только строчкой на
# экране профиля. «Сержант» намеренно совпадает с 20 уровнем — как раз
# тем местом, где заканчиваются перки.
# ============================================================================
class_name Ranks
extends RefCounted

const LIST := [
	{"id": "recruit", "name": "Новобранец", "icon": "🌱", "level": 1, "reward": 0},
	{"id": "private", "name": "Рядовой", "icon": "🪖", "level": 5, "reward": 20},
	{"id": "corporal", "name": "Ефрейтор", "icon": "🎖", "level": 10, "reward": 30},
	{"id": "sergeant", "name": "Сержант", "icon": "🎗", "level": 20, "reward": 50},
	{"id": "master_sergeant", "name": "Старшина", "icon": "⭐", "level": 30, "reward": 80},
	{"id": "lieutenant", "name": "Лейтенант", "icon": "🌟", "level": 45, "reward": 120},
	{"id": "captain", "name": "Капитан", "icon": "🏅", "level": 60, "reward": 160},
	{"id": "major", "name": "Майор", "icon": "🥉", "level": 80, "reward": 200},
	{"id": "colonel", "name": "Полковник", "icon": "🥈", "level": 100, "reward": 260},
	{"id": "general", "name": "Генерал", "icon": "🥇", "level": 130, "reward": 320},
	{"id": "marshal", "name": "Маршал", "icon": "👑", "level": 170, "reward": 400},
	{"id": "legend", "name": "Легенда фронта", "icon": "💠", "level": 220, "reward": 500},
	{"id": "immortal", "name": "Бессмертный", "icon": "♾", "level": 300, "reward": 650},
]

static func get_rank(id: String) -> Dictionary:
	for r in LIST:
		if r["id"] == id:
			return r
	return {}

## Текущее звание — последнее, до которого игрок дорос. LIST идёт по
## возрастанию уровня, поэтому достаточно остановиться на первом, до
## которого уровень не дотягивает.
static func for_level(level: int) -> Dictionary:
	var current: Dictionary = LIST[0]
	for r in LIST:
		if level < int(r["level"]):
			break
		current = r
	return current
