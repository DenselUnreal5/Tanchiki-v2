extends Node

var failures := 0
var checked := 0
var missing: Array = []

func _need(key: String, ru: String) -> void:
	if ru == "":
		return
	checked += 1
	if not I18n.EN.has(key):
		missing.append(key)

func _entry(list, ns: String, fields: Array) -> void:
	var items: Array = list.values() if list is Dictionary else list
	for e in items:
		if not (e is Dictionary):
			continue
		for f in fields:
			_need("%s.%s.%s" % [ns, String(e.get("id", "")), String(f)], String(e.get(f, "")))

func _ready() -> void:
	_entry(Perks.all(), "perk", ["name", "desc"])
	_entry(Perks.BOT_LIST, "botperk", ["name"])
	_entry(Perks.BUILDS, "build", ["name", "bonus"])
	_entry(Abilities.LIST, "ability", ["name", "desc"])
	_entry(Upgrades.LIST, "upg", ["name", "desc"])
	_entry(Cannons.LIST, "cannon", ["name", "desc"])
	_entry(Weapons.LIST, "weapon", ["name"])
	_entry(TankClasses.LIST, "class", ["name", "desc", "trait"])
	_entry(Achievements.LIST, "ach", ["name", "desc"])
	_entry(Daily.LIST, "daily", ["name", "desc"])
	_entry(Weekly.CHALLENGES, "weekly", ["name", "desc", "mutator_desc"])
	_entry(Ranks.LIST, "rank", ["name"])
	_entry(EnemyTypes.LIST, "enemy", ["name"])
	_entry(Cosmetics.SKINS, "cos.skin", ["name", "desc"])
	_entry(Cosmetics.CAMOS, "cos.camo", ["name", "desc"])
	_entry(Cosmetics.HULLS, "cos.hull", ["name", "desc"])
	_entry(Cosmetics.TRACKS, "cos.track", ["name", "desc"])
	_entry(Cosmetics.TURRETS, "cos.turret", ["name", "desc"])
	for loc_id in Locations.ORDER:
		_need("loc." + String(loc_id), String(Locations.get_location(loc_id).get("name", "")))
	for tip in MenuTips.LIST:
		_need(String(tip[0]), String(tip[1]))
	for key in Prof.STAT_LABELS.keys():
		_need("stat." + String(key), String(Prof.STAT_LABELS[key]))
	for e in Bestiary.LIST:
		var id := String(e["id"])
		for f in ["name", "role", "hp_val", "speed_val", "dmg_val", "desc"]:
			_need("bestiary.%s.%s" % [id, f], String(e.get(f, "")))
		var abilities: Array = e.get("abilities", [])
		for i in abilities.size():
			_need("bestiary.%s.ab%d.name" % [id, i], String(abilities[i].get("name", "")))
			_need("bestiary.%s.ab%d.desc" % [id, i], String(abilities[i].get("desc", "")))
	for cannon in Cannons.LIST:
		if cannon.has("challenge"):
			_need("cannon.%s.challenge" % cannon["id"], String(cannon["challenge"].get("desc", "")))
	for p in Perks.all():
		if p.has("challenge"):
			_need("perk.%s.challenge" % p["id"], String(p["challenge"].get("desc", "")))
	missing.sort()
	print("полей данных проверено: %d, без английского ключа: %d" % [checked, missing.size()])
	for k in missing:
		print("  БЕЗ КЛЮЧА: ", k)
	print("=== ПРОВЕРКА ДАННЫХ ПЕРЕВОДА ЗАВЕРШЕНА, проблем: %d ===" % missing.size())
	get_tree().quit(1 if missing.size() > 0 else 0)
