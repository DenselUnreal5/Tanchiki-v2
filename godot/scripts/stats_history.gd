class_name StatsHistory
extends RefCounted

const LIMIT := 60
const MODES := ["ffa", "ctf", "koth", "defense", "tutorial"]

static func clean(raw) -> Array:
	var out := []
	if not raw is Array: return out
	for row in raw.slice(maxi(0, raw.size() - LIMIT)):
		if not row is Dictionary or not MODES.has(row.get("mode", "")): continue
		var entry := {"mode": String(row.mode), "victory": bool(row.get("victory", false)),
			"date": clampi(_number(row.get("date", 0)), 0, 9999999999),
			"class": String(row.get("class", "standard")), "cannon": String(row.get("cannon", "standard"))}
		if not TankClasses.has(entry["class"]): entry["class"] = "standard"
		if Cannons.get_cannon(entry.cannon).is_empty(): entry.cannon = "standard"
		for field in ["kills", "deaths", "damage", "score", "seconds", "wave"]:
			entry[field] = clampi(_number(row.get(field, 0)), 0, 1000000000)
		out.append(entry)
	return out

static func _number(value) -> int:
	if value is int: return value
	if value is float: return int(clampf(value, -10000000000.0, 10000000000.0)) if is_finite(value) else 0
	if value is String and value.is_valid_int(): return value.to_int()
	return 0

static func from_player(world, player, victory: bool) -> Dictionary:
	return {"date": int(Time.get_unix_time_from_system()), "mode": world.mode,
		"victory": victory, "kills": player.kills, "deaths": player.deaths,
		"damage": int(round(player.damage_dealt)), "score": player.score,
		"seconds": world.tick / Cfg.TICK_HZ, "wave": world.wave,
		"class": player.equipped_class, "cannon": player.equipped_cannon}

static func filtered(history: Array, mode: String = "all", limit: int = LIMIT) -> Array:
	var out := []
	for row in history:
		if mode == "all" or row.mode == mode: out.append(row)
	return out.slice(maxi(0, out.size() - clampi(limit, 1, LIMIT)))
