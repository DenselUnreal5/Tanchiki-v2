class_name Weekly
extends RefCounted

static func week_key() -> String:
	var d := Time.get_datetime_dict_from_system(false)
	var unix := Time.get_unix_time_from_system()
	var week_num := int(unix / (7 * 86400))
	return "%04d-W%02d" % [d["year"], (week_num % 52) + 1]

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
		"desc": "Ликвидировать 20 врагов с дальней дистанции (от 40 метров)",
		"icon": "🎯",
		"counter": "long_kills",
		"need": 20,
		"reward": 300,
		"mutator": "sniper_elite",
		"mutator_desc": "Высокая точность и увеличенная скорость снарядов",
	},
]

static func current_challenge() -> Dictionary:
	var key := week_key()
	var sum := 0
	for i in key.length():
		sum += key.unicode_at(i)
	var idx := sum % CHALLENGES.size()
	return CHALLENGES[idx]

static func get_challenge(id: String) -> Dictionary:
	for ch in CHALLENGES:
		if ch["id"] == id:
			return ch
	return {}

static func time_until_next_week() -> Dictionary:
	var unix := Time.get_unix_time_from_system()
	var sec_in_week := 7 * 86400
	var elapsed: int = int(unix) % sec_in_week
	var remaining := sec_in_week - elapsed
	var days := int(remaining / 86400)
	var hours := int((remaining % 86400) / 3600)
	return {"days": days, "hours": hours, "total_seconds": remaining}
