class_name Weekly
extends RefCounted

static func week_key() -> String:
	return GameClock.week_key()

const CHALLENGES := [
	{
		"id": "w_ice_storm",
		"name": "Ледяной шторм",
		"desc": "Уничтожить 35 танков в скользких зимних условиях",
		"icon": "❄️",
		"counter": "kills",
		"need": 35,
		"reward": 300,
		"mutator": "ice_storm",
		"mutator_desc": "Повышенное скольжение и крио-снаряды",
	},
	{
		"id": "w_explosive_madness",
		"name": "Взрывная лихорадка",
		"desc": "Подорвать 15 взрывных бочек и нанести урон взрывами",
		"icon": "💣",
		"counter": "barrels_exploded",
		"need": 15,
		"reward": 300,
		"mutator": "explosive_frenzy",
		"mutator_desc": "Удвоенное число взрывных бочек на арене",
	},
	{
		"id": "w_emp_overload",
		"name": "ЭМИ-перегрузка",
		"desc": "Разрядить генераторы поля 8 раз и оглушить противников",
		"icon": "⚡",
		"counter": "emp_discharged",
		"need": 8,
		"reward": 300,
		"mutator": "emp_overload",
		"mutator_desc": "Ускоренная зарядка генераторов поля",
	},
	{
		"id": "w_iron_ram",
		"name": "Стальной таран",
		"desc": "Совершить 12 сокрушительных таранов на тяжелой машине",
		"icon": "🛡️",
		"counter": "ram_kills",
		"need": 12,
		"reward": 300,
		"mutator": "iron_ram",
		"mutator_desc": "Увеличенный урон и дальность рывка",
	},
	{
		"id": "w_survival_endurance",
		"name": "Осада Цитадели",
		"desc": "Выдержать не менее 12 волн в режиме «Оборона»",
		"icon": "🏰",
		"counter": "defense_wave",
		"need": 12,
		"reward": 350,
		"mutator": "hardcore_waves",
		"mutator_desc": "Особо плотные волны бронетехники",
	},
	{
		"id": "w_sniper_elite",
		"name": "Снайперская дуэль",
		"desc": "Ликвидировать 20 врагов с дальней дистанции (от 50 метров)",
		"icon": "🎯",
		"counter": "long_kills",
		"need": 20,
		"reward": 300,
		"mutator": "sniper_elite",
		"mutator_desc": "Высокая точность и увеличенная скорость снарядов",
	},
]

static func challenge_for(key: String) -> Dictionary:
	var sum := 0
	for i in key.length():
		sum += key.unicode_at(i)
	return CHALLENGES[sum % CHALLENGES.size()]

static func current_challenge() -> Dictionary:
	return challenge_for(week_key())

static func get_challenge_by_mutator(mutator_id: String) -> Dictionary:
	for ch in CHALLENGES:
		if ch["mutator"] == mutator_id:
			return ch
	return {}

static func get_challenge(id: String) -> Dictionary:
	for ch in CHALLENGES:
		if ch["id"] == id:
			return ch
	return {}

static func time_until_next_week() -> Dictionary:
	var remaining := GameClock.seconds_until_next_week()
	var days := int(remaining / 86400)
	var hours := int((remaining % 86400) / 3600)
	return {"days": days, "hours": hours, "total_seconds": remaining}
