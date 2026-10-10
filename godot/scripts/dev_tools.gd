class_name DevTools
extends RefCounted

const MAX_LEVEL := 99

static func set_level(level: int) -> void:
	Prof.global_level = clampi(level, 1, MAX_LEVEL)
	Prof.global_xp = 0
	for lvl in Perks.UNLOCK_TABLE.keys():
		if Prof.global_level >= int(lvl):
			for id in Perks.UNLOCK_TABLE[lvl]:
				Prof.unlocked[id] = true
	Prof.save_profile()

static func add_money(delta: int) -> void:
	Prof.money = maxi(0, Prof.money + delta)
	Prof.save_profile()

static func set_money(value: int) -> void:
	Prof.money = maxi(0, value)
	Prof.save_profile()

static func perk_ids() -> Array:
	var out := []
	for p in Perks.all():
		out.append(String(p["id"]))
	return out

static func set_perk(id: String, on: bool, save: bool = true) -> void:
	if on:
		Prof.unlocked[id] = true
	else:
		Prof.unlocked.erase(id)
	if save:
		Prof.save_profile()

static func set_all_perks(on: bool) -> void:
	for id in perk_ids():
		set_perk(id, on, false)
	Prof.save_profile()

static func cosmetic_items() -> Array:
	var out := []
	for c in Cosmetics.all():
		if String(c["id"]) != "none":
			out.append(c)
	return out

static func is_cosmetic_owned(type: String, id: String) -> bool:
	return Prof.is_cosmetic_owned(type, id)

static func set_cosmetic(type: String, id: String, on: bool, save: bool = true) -> void:
	if id == "none":
		return
	var key := Prof._cos_key(type, id)
	if on:
		Prof.cosmetic_owned[key] = true
	else:
		Prof.cosmetic_owned.erase(key)
		if String(Prof.cosmetics.get(type, "none")) == id:
			Prof.cosmetics[type] = "none"
	if save:
		Prof.save_profile()

static func set_all_cosmetics(on: bool) -> void:
	for c in cosmetic_items():
		set_cosmetic(String(c["type"]), String(c["id"]), on, false)
	Prof.save_profile()

static func set_cannon(id: String, on: bool, save: bool = true) -> void:
	if id == "standard" or Cannons.get_cannon(id).is_empty():
		return
	if on:
		Prof.cannon_owned[id] = true
	else:
		Prof.cannon_owned.erase(id)
		if Prof.equipped_cannon == id:
			Prof.equipped_cannon = "standard"
	if save:
		Prof.save_profile()

static func set_class(id: String, on: bool, save: bool = true) -> void:
	if id == TankClasses.DEFAULT or not TankClasses.has(id):
		return
	if on:
		Prof.class_owned[id] = true
	else:
		Prof.class_owned.erase(id)
		if Prof.equipped_class == id:
			Prof.equipped_class = TankClasses.DEFAULT
	if save:
		Prof.save_profile()

static func set_all_tanks(on: bool) -> void:
	for c in Cannons.LIST:
		set_cannon(String(c["id"]), on, false)
	for id in TankClasses.ids():
		set_class(String(id), on, false)
	Prof.save_profile()
