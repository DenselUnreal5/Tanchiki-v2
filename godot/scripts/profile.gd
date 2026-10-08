extends Node

const Weekly = preload("res://scripts/weekly.gd")

const SAVE_PATH := "user://profile.json"
const SCHEMA := 6

signal levelup(levels: Array)
signal unlock(ids: Array, reason: String)
signal achievement(ids: Array, reward: int)
signal daily_claimed(id: String, reward: int)
signal weekly_claimed(id: String, reward: int)
signal rank_up(ids: Array, reward: int)

const STAT_KEYS := [
	"ramKills",
	"bricksDestroyed",
	"waterEntries",
	"treesDriven",
	"healthPacksCollected",
	"gamesWon",
	"gamesPlayed",
	"timesDied",
	"totalKills",
	"rapidKills",
	"cleanStreak",
	"damageInGame",
	"longKills",
	"lowHpKills",
	"sniperKills",
	"bridgeKills",
	"concreteDestroyed",
	"abilityUses",
	"bossKills",
	"moneyEarned",
	"globalLevel",
	"defenseWaveReached",
	"tutorialCompleted",
]

const MAX_STATS := ["rapidKills", "cleanStreak", "damageInGame", "globalLevel", "defenseWaveReached", "tutorialCompleted"]

const STAT_LABELS := {
	"ramKills": "Убийства тараном",
	"bricksDestroyed": "Разрушено кирпичей",
	"waterEntries": "Входов в воду",
	"treesDriven": "Смято деревьев",
	"healthPacksCollected": "Подобрано аптечек",
	"gamesWon": "Побед",
	"gamesPlayed": "Партий сыграно",
	"timesDied": "Смертей",
	"totalKills": "Всего убийств",
	"rapidKills": "Лучшее: убийств за 10 сек",
	"cleanStreak": "Лучшая серия без урона",
	"damageInGame": "Лучший урон за партию",
	"longKills": "Убийства с 50 м",
	"lowHpKills": "Убийства при HP ≤ 40%",
	"sniperKills": "Убийства с 100 м",
	"bridgeKills": "Убийства на мосту",
	"concreteDestroyed": "Снесено бетона и железа",
	"abilityUses": "Способностей применено",
	"bossKills": "Убито боссов",
	"moneyEarned": "Заработано монет",
	"globalLevel": "Наивысший уровень",
	"defenseWaveReached": "Лучшая волна в «Обороне»",
	"tutorialCompleted": "Обучение пройдено",
}

var global_level := 1
var global_xp := 0
var unlocked := {}
var stats := {}
var money := 0
var upgrades := {}
var achievements := {}
var ranks_claimed := {}
var daily := {"date": "", "progress": {}, "claimed": []}
var weekly := {"week": "", "progress": {}, "claimed": false}
var local_leaderboards: Dictionary = {}
var cosmetic_owned := {}
var cosmetics := {"skin": "none", "camo": "none", "hull": "none", "track": "none", "turret": "none"}
var cannon_owned := {}
var equipped_cannon := "standard"
var equipped_color1 := "p1"
var equipped_color2 := "p2"
var bestiary_kills: Dictionary = {}

func _ready() -> void:
	_empty_stats()
	_empty_upgrades()
	daily = {"date": Daily.today_key(), "progress": {}, "claimed": []}
	weekly = {"week": Weekly.week_key(), "progress": {}, "claimed": false}
	load_profile()

func _empty_stats() -> void:
	stats = {}
	for k in STAT_KEYS:
		stats[k] = 0

func _empty_upgrades() -> void:
	upgrades = {}
	for u in Upgrades.LIST:
		upgrades[u["id"]] = 0

func load_profile() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var raw := f.get_as_text()
			f.close()
			var data = JSON.parse_string(raw)
			if data is Dictionary:
				_apply(data)
			else:
				push_warning("[profile] сохранение повреждено, начинаем заново")
	_sync_level_unlocks()

func _apply(data: Dictionary) -> void:
	global_level = clampi(int(data.get("globalLevel", 1)), 1, 999)
	global_xp = maxi(0, int(data.get("globalXP", 0)))
	var known_perks := {}
	for p in Perks.all():
		known_perks[p["id"]] = true
	for id in data.get("unlocked", []):
		if known_perks.has(id):
			unlocked[id] = true
	var st = data.get("stats", {})
	if st is Dictionary:
		for k in STAT_KEYS:
			var v := int(st.get(k, 0))
			if v >= 0:
				stats[k] = v
	money = maxi(0, int(data.get("money", 0)))
	var ups = data.get("upgrades", {})
	if ups is Dictionary:
		for u in Upgrades.LIST:
			var lvl := clampi(int(ups.get(u["id"], 0)), 0, int(u["max_level"]))
			upgrades[u["id"]] = lvl
	var known_ach := {}
	for a in Achievements.LIST:
		known_ach[a["id"]] = true
	for id in data.get("achievements", []):
		if known_ach.has(id):
			achievements[id] = true
	var known_ranks := {}
	for r in Ranks.LIST:
		known_ranks[r["id"]] = true
	for id in data.get("ranksClaimed", []):
		if known_ranks.has(id):
			ranks_claimed[id] = true
	var d = data.get("daily", null)
	if d is Dictionary and d.has("date"):
		daily = {
			"date": String(d.get("date", "")),
			"progress": d.get("progress", {}) if d.get("progress", {}) is Dictionary else {},
			"claimed": d.get("claimed", []) if d.get("claimed", []) is Array else [],
		}
	var known_cos := {}
	for c in Cosmetics.all():
		known_cos["%s:%s" % [c["type"], c["id"]]] = true
	for key in data.get("cosmeticOwned", []):
		if known_cos.has(key):
			cosmetic_owned[key] = true
	var cos = data.get("cosmetics", {})
	if cos is Dictionary:
		for type in Cosmetics.TYPES:
			var id := String(cos.get(type, "none"))
			if is_cosmetic_owned(type, id):
				cosmetics[type] = id
	var c1 := String(data.get("equippedColor1", equipped_color1))
	if is_color_unlocked(c1):
		equipped_color1 = c1
	var c2 := String(data.get("equippedColor2", equipped_color2))
	if is_color_unlocked(c2):
		equipped_color2 = c2
	var known_cannons := {}
	for c in Cannons.LIST:
		known_cannons[c["id"]] = true
	for id in data.get("cannonOwned", []):
		if known_cannons.has(id):
			cannon_owned[id] = true
	var eq_cannon := String(data.get("equippedCannon", "standard"))
	if is_cannon_owned(eq_cannon):
		equipped_cannon = eq_cannon
	var bk = data.get("bestiaryKills", {})
	if bk is Dictionary:
		bestiary_kills = bk.duplicate()
	if int(bestiary_kills.get("boss", 0)) == 0 and int(stats.get("bossKills", 0)) > 0:
		bestiary_kills["boss"] = int(stats.get("bossKills", 0))
	if int(bestiary_kills.get("grunt", 0)) == 0 and int(stats.get("totalKills", 0)) > 0:
		bestiary_kills["grunt"] = 1
	var w = data.get("weekly", null)
	if w is Dictionary and w.has("week"):
		weekly = {
			"week": String(w.get("week", "")),
			"progress": w.get("progress", {}) if w.get("progress", {}) is Dictionary else {},
			"claimed": bool(w.get("claimed", false)),
		}
	var ll = data.get("localLeaderboards", null)
	if ll is Dictionary:
		local_leaderboards = ll.duplicate()
	_refresh_daily_if_stale()
	_refresh_weekly_if_stale()

func save_profile() -> void:
	var data := {
		"schema": SCHEMA,
		"globalLevel": global_level,
		"globalXP": global_xp,
		"unlocked": unlocked.keys(),
		"stats": stats,
		"money": money,
		"upgrades": upgrades,
		"achievements": achievements.keys(),
		"ranksClaimed": ranks_claimed.keys(),
		"daily": daily,
		"weekly": weekly,
		"localLeaderboards": local_leaderboards,
		"cosmeticOwned": cosmetic_owned.keys(),
		"cosmetics": cosmetics,
		"equippedColor1": equipped_color1,
		"equippedColor2": equipped_color2,
		"cannonOwned": cannon_owned.keys(),
		"equippedCannon": equipped_cannon,
		"bestiaryKills": bestiary_kills,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()

func reset() -> void:
	global_level = 1
	global_xp = 0
	unlocked.clear()
	_empty_stats()
	money = 0
	_empty_upgrades()
	achievements.clear()
	ranks_claimed.clear()
	daily = {"date": Daily.today_key(), "progress": {}, "claimed": []}
	cosmetic_owned.clear()
	cosmetics = {"skin": "none", "camo": "none", "hull": "none", "track": "none", "turret": "none"}
	equipped_color1 = "p1"
	equipped_color2 = "p2"
	cannon_owned.clear()
	equipped_cannon = "standard"
	bestiary_kills.clear()
	_sync_level_unlocks()
	save_profile()

func xp_to_next_level() -> int:
	return Cfg.xp_for_global_level(global_level)

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	global_xp += amount
	var levels := []
	var newly := []
	var guard := 0
	while global_xp >= xp_to_next_level() and guard < 500:
		guard += 1
		global_xp -= xp_to_next_level()
		global_level += 1
		levels.append(global_level)
		for id in Perks.UNLOCK_TABLE.get(global_level, []):
			if not unlocked.has(id):
				unlocked[id] = true
				newly.append(id)
	if not levels.is_empty():
		bump_stat("globalLevel", global_level)
		check_ranks()
		save_profile()
		levelup.emit(levels)
		if not newly.is_empty():
			unlock.emit(newly, "level")

func bump_stat(key: String, delta: int = 1) -> void:
	if not stats.has(key):
		return
	if MAX_STATS.has(key):
		stats[key] = maxi(int(stats[key]), delta)
	else:
		stats[key] = int(stats[key]) + delta
	check_challenges()
	check_achievements()

func check_achievements() -> Array:
	var newly := []
	for a in Achievements.LIST:
		if achievements.has(a["id"]):
			continue
		if int(stats.get(a["stat"], 0)) < int(a["need"]):
			continue
		achievements[a["id"]] = true
		newly.append(a["id"])
	if not newly.is_empty():
		var total := 0
		for id in newly:
			total += int(Achievements.get_achievement(id).get("reward", 0))
		money += total
		save_profile()
		for id in newly:
			SteamStats.unlock(String(id))
		achievement.emit(newly, total)
	return newly

func check_ranks() -> Array:
	var newly := []
	for r in Ranks.LIST:
		if ranks_claimed.has(r["id"]):
			continue
		if global_level < int(r["level"]):
			continue
		ranks_claimed[r["id"]] = true
		newly.append(r["id"])
	if not newly.is_empty():
		var total := 0
		for id in newly:
			total += int(Ranks.get_rank(id).get("reward", 0))
		money += total
		save_profile()
		rank_up.emit(newly, total)
	return newly

func check_challenges() -> Array:
	var newly := []
	for perk in Perks.all():
		if not perk.has("challenge") or unlocked.has(perk["id"]):
			continue
		var ch: Dictionary = perk["challenge"]
		if int(stats.get(ch["stat"], 0)) >= int(ch["need"]):
			unlocked[perk["id"]] = true
			newly.append(perk["id"])
	if not newly.is_empty():
		save_profile()
		unlock.emit(newly, "challenge")
	return newly

func _refresh_daily_if_stale() -> void:
	var today := Daily.today_key()
	if String(daily.get("date", "")) == today:
		return
	daily = {"date": today, "progress": {}, "claimed": []}

func daily_progress(id: String) -> Dictionary:
	_refresh_daily_if_stale()
	var q := Daily.get_quest(id)
	if q.is_empty():
		return {}
	var progress: Dictionary = daily["progress"]
	return {
		"current": mini(int(progress.get(q["counter"], 0)), int(q["need"])),
		"need": int(q["need"]),
		"claimed": (daily["claimed"] as Array).has(id),
		"reward": int(q["reward"]),
		"name": q["name"],
		"icon": q["icon"],
		"desc": q["desc"],
	}

func bump_daily(counter: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	_refresh_daily_if_stale()
	var progress: Dictionary = daily["progress"]
	progress[counter] = int(progress.get(counter, 0)) + amount
	save_profile()

func bump_daily_max(counter: String, value: int) -> void:
	if value <= 0:
		return
	_refresh_daily_if_stale()
	var progress: Dictionary = daily["progress"]
	if value > int(progress.get(counter, 0)):
		progress[counter] = value
		save_profile()

func claim_daily(id: String) -> Dictionary:
	_refresh_daily_if_stale()
	var q := Daily.get_quest(id)
	if q.is_empty():
		return {"ok": false, "reason": "unknown"}
	var claimed: Array = daily["claimed"]
	if claimed.has(id):
		return {"ok": false, "reason": "claimed"}
	var progress: Dictionary = daily["progress"]
	if int(progress.get(q["counter"], 0)) < int(q["need"]):
		return {"ok": false, "reason": "not_done"}
	claimed.append(id)
	money += int(q["reward"])
	save_profile()
	daily_claimed.emit(id, int(q["reward"]))
	return {"ok": true, "reward": int(q["reward"])}

func _refresh_weekly_if_stale() -> void:
	var cur_week := Weekly.week_key()
	if String(weekly.get("week", "")) == cur_week:
		return
	weekly = {"week": cur_week, "progress": {}, "claimed": false}

func get_weekly_progress() -> Dictionary:
	_refresh_weekly_if_stale()
	var ch := Weekly.current_challenge()
	var progress: Dictionary = weekly.get("progress", {})
	var current: int = int(progress.get(ch["counter"], 0))
	var need: int = int(ch["need"])
	return {
		"challenge": ch,
		"current": mini(current, need),
		"need": need,
		"done": current >= need,
		"claimed": bool(weekly.get("claimed", false)),
		"reward": int(ch["reward"]),
	}

func bump_weekly(counter: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	_refresh_weekly_if_stale()
	var progress: Dictionary = weekly.get("progress", {})
	var prev: int = int(progress.get(counter, 0))
	progress[counter] = prev + amount
	weekly["progress"] = progress
	save_profile()
	var ch := Weekly.current_challenge()
	if String(ch.get("counter", "")) == counter:
		var total: int = prev + amount
		SteamStats.push_weekly_score(total)
		record_local_leaderboard("weekly", "Игрок", total)

func claim_weekly() -> Dictionary:
	_refresh_weekly_if_stale()
	var ch := Weekly.current_challenge()
	if ch.is_empty():
		return {"ok": false, "reason": "unknown"}
	if bool(weekly.get("claimed", false)):
		return {"ok": false, "reason": "claimed"}
	var progress: Dictionary = weekly.get("progress", {})
	if int(progress.get(ch["counter"], 0)) < int(ch["need"]):
		return {"ok": false, "reason": "not_done"}
	weekly["claimed"] = true
	var rew := int(ch["reward"])
	money += rew
	save_profile()
	weekly_claimed.emit(String(ch["id"]), rew)
	return {"ok": true, "reward": rew}

func record_local_leaderboard(board_key: String, player_name: String, score: int) -> void:
	if score <= 0:
		return
	if not local_leaderboards.has(board_key):
		local_leaderboards[board_key] = []
	var list: Array = local_leaderboards[board_key]
	var found := false
	for entry in list:
		if entry.get("name") == player_name:
			if score > int(entry.get("score", 0)):
				entry["score"] = score
				entry["date"] = Daily.today_key()
			found = true
			break
	if not found:
		list.append({
			"name": player_name,
			"score": score,
			"date": Daily.today_key()
		})
	list.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	if list.size() > 10:
		list.resize(10)
	local_leaderboards[board_key] = list
	save_profile()

func get_local_leaderboard(board_key: String) -> Array:
	if not local_leaderboards.has(board_key) or (local_leaderboards[board_key] as Array).is_empty():
		_init_default_leaderboard(board_key)
	return local_leaderboards.get(board_key, [])

func _init_default_leaderboard(board_key: String) -> void:
	var defaults := []
	match board_key:
		"survival_waves", "defense":
			defaults = [
				{"name": "Генерал Броня", "score": 25, "date": "2026-10-01"},
				{"name": "Ветеран Цитадели", "score": 18, "date": "2026-10-02"},
				{"name": "Капитан Шторм", "score": 14, "date": "2026-10-03"},
				{"name": "Сержант Кремень", "score": 10, "date": "2026-10-04"},
				{"name": "Танкист-Защитник", "score": 7, "date": "2026-10-05"},
			]
		"survival_score":
			defaults = [
				{"name": "Ас Артиллерии", "score": 18500, "date": "2026-10-01"},
				{"name": "Охотник на Боссов", "score": 14200, "date": "2026-10-02"},
				{"name": "Тяжелый Рейдер", "score": 9800, "date": "2026-10-03"},
			]
		"weekly":
			defaults = [
				{"name": "Громовержец", "score": 45, "date": "2026-W41"},
				{"name": "Лидер Испытания", "score": 38, "date": "2026-W41"},
				{"name": "Стальной Чемпион", "score": 25, "date": "2026-W41"},
			]
		_:
			defaults = [
				{"name": "Абсолютный Чемпион", "score": 5000, "date": "2026-10-01"},
				{"name": "Мастер Дуэлей", "score": 3500, "date": "2026-10-02"},
				{"name": "Гладиатор Арены", "score": 2200, "date": "2026-10-03"},
			]
	local_leaderboards[board_key] = defaults

func _cos_key(type: String, id: String) -> String:
	return "%s:%s" % [type, id]

func is_cosmetic_owned(type: String, id: String) -> bool:
	if Cosmetics.get_cosmetic(type, id).is_empty():
		return false
	return id == "none" or cosmetic_owned.has(_cos_key(type, id))

func buy_cosmetic(type: String, id: String) -> Dictionary:
	var c := Cosmetics.get_cosmetic(type, id)
	if c.is_empty():
		return {"ok": false, "reason": "unknown"}
	if id == "none":
		return {"ok": false, "reason": "free"}
	if cosmetic_owned.has(_cos_key(type, id)):
		return {"ok": false, "reason": "owned"}
	if money < int(c["price"]):
		return {"ok": false, "reason": "money"}
	money -= int(c["price"])
	cosmetic_owned[_cos_key(type, id)] = true
	save_profile()
	return {"ok": true, "price": int(c["price"])}

func equip_cosmetic(type: String, id: String) -> Dictionary:
	if not is_cosmetic_owned(type, id):
		return {"ok": false, "reason": "not_owned"}
	cosmetics[type] = id
	save_profile()
	return {"ok": true}

func equipped_cosmetics() -> Dictionary:
	return cosmetics.duplicate()

func is_cannon_owned(id: String) -> bool:
	if Cannons.get_cannon(id).is_empty():
		return false
	return id == "standard" or cannon_owned.has(id)

func buy_cannon(id: String) -> Dictionary:
	var c := Cannons.get_cannon(id)
	if c.is_empty() or id == "standard":
		return {"ok": false, "reason": "unknown"}
	if cannon_owned.has(id):
		return {"ok": false, "reason": "owned"}
	if money < int(c["price"]):
		return {"ok": false, "reason": "money"}
	money -= int(c["price"])
	cannon_owned[id] = true
	save_profile()
	return {"ok": true, "price": int(c["price"])}

func equip_cannon(id: String) -> Dictionary:
	if not is_cannon_owned(id):
		return {"ok": false, "reason": "not_owned"}
	equipped_cannon = id
	save_profile()
	return {"ok": true}

func is_color_unlocked(key: String) -> bool:
	for skin in Cfg.PLAYER_SKINS:
		if String(skin["key"]) == key:
			return global_level >= int(skin.get("level", 1))
	return false

func set_equipped_color(slot: int, key: String) -> bool:
	if not is_color_unlocked(key):
		return false
	if slot == 0:
		equipped_color1 = key
	else:
		equipped_color2 = key
	save_profile()
	return true

func add_money(amount: int) -> int:
	if amount <= 0:
		return money
	money += amount
	bump_stat("moneyEarned", amount)
	save_profile()
	return money

func spend_money(amount: int) -> bool:
	if amount < 0 or money < amount:
		return false
	money -= amount
	return true

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

func upgrade_next_cost(id: String) -> int:
	var up := Upgrades.get_upgrade(id)
	if up.is_empty():
		return -1
	var level := upgrade_level(id)
	if level >= int(up["max_level"]):
		return -1
	return Upgrades.cost(up, level)

func buy_upgrade(id: String) -> Dictionary:
	var up := Upgrades.get_upgrade(id)
	if up.is_empty():
		return {"ok": false, "reason": "unknown"}
	var level := upgrade_level(id)
	if level >= int(up["max_level"]):
		return {"ok": false, "reason": "max"}
	var cost := Upgrades.cost(up, level)
	if not spend_money(cost):
		return {"ok": false, "reason": "money"}
	upgrades[id] = level + 1
	save_profile()
	return {"ok": true, "level": level + 1, "cost": cost}

func upgrade_mods() -> Dictionary:
	var m := {
		"maxHPMult": 1.0,
		"speedMult": 1.0,
		"fireRateMult": 1.0,
		"dmgMult": 1.0,
		"bulletSpeedMult": 1.0,
		"damageTakenMult": 1.0,
		"ramMult": 1.0,
		"pickupRadiusMult": 1.0,
		"regenPerMinute": 0.0,
	}
	for up in Upgrades.LIST:
		var level := upgrade_level(up["id"])
		if level <= 0:
			continue
		var value := Upgrades.mult(up, level)
		var key: String = up["mod_key"]
		if key == "regenPerMinute":
			m[key] = float(m[key]) + value
		else:
			m[key] = float(m[key]) * value
	return m

func is_unlocked(id: String) -> bool:
	return unlocked.has(id)

func available_perk_ids() -> Array:
	var out := []
	for p in Perks.all():
		if unlocked.has(p["id"]):
			out.append(p["id"])
	return out

func challenge_progress(perk_id: String) -> Dictionary:
	var perk := Perks.get_perk(perk_id)
	if perk.is_empty() or not perk.has("challenge"):
		return {}
	var ch: Dictionary = perk["challenge"]
	return {
		"current": mini(int(stats.get(ch["stat"], 0)), int(ch["need"])),
		"need": int(ch["need"]),
		"desc": String(ch["desc"]),
	}

func _sync_level_unlocks() -> void:
	for lvl in Perks.UNLOCK_TABLE.keys():
		if global_level >= int(lvl):
			for id in Perks.UNLOCK_TABLE[lvl]:
				unlocked[id] = true
	bump_stat("globalLevel", global_level)
	check_challenges()
	check_ranks()

func record_bestiary_kill(tank_id: String) -> void:
	if tank_id.is_empty():
		return
	var cur: int = int(bestiary_kills.get(tank_id, 0))
	bestiary_kills[tank_id] = cur + 1
	save_profile()

func get_bestiary_kills(tank_id: String) -> int:
	return int(bestiary_kills.get(tank_id, 0))

func is_bestiary_unlocked(tank_id: String) -> bool:
	if Bestiary.is_player_tank(tank_id):
		return true
	return get_bestiary_kills(tank_id) > 0
