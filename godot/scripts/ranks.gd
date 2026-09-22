@tool
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

static func for_level(level: int) -> Dictionary:
	var current: Dictionary = LIST[0]
	for r in LIST:
		if level < int(r["level"]):
			break
		current = r
	return current
