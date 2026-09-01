# ============================================================================
# profile.gd — постоянный прогресс между партиями (user://profile.json).
# Автозагрузка «Prof».
#
# Профиль один на машину: в «горячем стуле» оба живых игрока пополняют его
# опыт и статистику челленджей. Внутрипартийные уровни и перки при этом
# у каждого игрока свои — они живут в PlayerState, а не здесь.
# ============================================================================
extends Node

const SAVE_PATH := "user://profile.json"
const SCHEMA := 6

signal levelup(levels: Array)
signal unlock(ids: Array, reason: String)
signal achievement(ids: Array, reward: int)
signal daily_claimed(id: String, reward: int)

## Список отслеживаемых статистик.
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
	"rapidKills",     # лучший результат: убийств за 10 сек
	"cleanStreak",    # лучшая серия убийств без урона
	"damageInGame",   # лучший урон за одну партию
	"longKills",      # убийства с дистанции ≥ 400 px
	"lowHpKills",     # убийства при HP ≤ 40%
	"sniperKills",    # убийства с дистанции ≥ 800 px
	"bridgeKills",    # убийства, сделанные стоя на мосту
	"concreteDestroyed",  # снесённые бетонные и железные постройки
	"abilityUses",    # срабатывания активной способности
]

## Статистики-рекорды: обновляются по максимуму, а не суммированием.
const MAX_STATS := ["rapidKills", "cleanStreak", "damageInGame"]

## Названия статистик для экрана «Статистика».
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
	"longKills": "Убийства с 400 px",
	"lowHpKills": "Убийства при HP ≤ 40%",
	"sniperKills": "Убийства с 800 px",
	"bridgeKills": "Убийства на мосту",
	"concreteDestroyed": "Снесено бетона и железа",
	"abilityUses": "Способностей применено",
}

var global_level := 1
var global_xp := 0
var unlocked := {}          # Set<String> открытых перков
var stats := {}
var money := 0
var upgrades := {}          # id -> уровень
var achievements := {}      # Set<String>
var daily := {"date": "", "progress": {}, "claimed": []}
var cosmetic_owned := {}    # Set<"тип:id">
var cosmetics := {"camo": "none", "hull": "none", "track": "none", "turret": "none"}

func _ready() -> void:
	_empty_stats()
	_empty_upgrades()
	daily = {"date": Daily.today_key(), "progress": {}, "claimed": []}
	load_profile()

func _empty_stats() -> void:
	stats = {}
	for k in STAT_KEYS:
		stats[k] = 0

func _empty_upgrades() -> void:
	upgrades = {}
	for u in Upgrades.LIST:
		upgrades[u["id"]] = 0

# -------------------------------------------------------------- хранилище
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
	# Догоняем открытия, положенные по текущему уровню.
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
	_refresh_daily_if_stale()

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
		"daily": daily,
		"cosmeticOwned": cosmetic_owned.keys(),
		"cosmetics": cosmetics,
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
	daily = {"date": Daily.today_key(), "progress": {}, "claimed": []}
	cosmetic_owned.clear()
	cosmetics = {"camo": "none", "hull": "none", "track": "none", "turret": "none"}
	_sync_level_unlocks()
	save_profile()

# -------------------------------------------------------------- опыт
func xp_to_next_level() -> int:
	return Cfg.xp_for_global_level(global_level)

## Начисляет глобальный опыт и рассылает события об уровнях и открытиях.
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
		save_profile()
		levelup.emit(levels)
		if not newly.is_empty():
			unlock.emit(newly, "level")

# -------------------------------------------------------------- статистика
## Изменяет статистику и сразу проверяет челленджи и достижения.
func bump_stat(key: String, delta: int = 1) -> void:
	if not stats.has(key):
		return
	if MAX_STATS.has(key):
		stats[key] = maxi(int(stats[key]), delta)
	else:
		stats[key] = int(stats[key]) + delta
	check_challenges()
	check_achievements()

## Проверяет все достижения и открывает выполненные, начисляя монеты.
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
		# Отражаем наружу: в профиле Steam достижение должно появиться тогда
		# же, когда в игре. Прогресс при этом остаётся своим — profile.json.
		for id in newly:
			SteamStats.unlock(String(id))
		achievement.emit(newly, total)
	return newly

## Проверяет все челленджи и открывает выполненные.
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

# -------------------------------------------------------------- ежедневные задания
func _refresh_daily_if_stale() -> void:
	var today := Daily.today_key()
	if String(daily.get("date", "")) == today:
		return
	daily = {"date": today, "progress": {}, "claimed": []}

## Прогресс задания: {current, need, claimed, reward, name, icon, desc}.
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

## Начисляет прогресс по счётчику всем заданиям дня.
func bump_daily(counter: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	_refresh_daily_if_stale()
	var progress: Dictionary = daily["progress"]
	progress[counter] = int(progress.get(counter, 0)) + amount
	save_profile()

## Прогресс по рекордному принципу (например, лучшая серия убийств).
func bump_daily_max(counter: String, value: int) -> void:
	if value <= 0:
		return
	_refresh_daily_if_stale()
	var progress: Dictionary = daily["progress"]
	if value > int(progress.get(counter, 0)):
		progress[counter] = value
		save_profile()

## Забирает награду за выполненное задание.
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

# -------------------------------------------------------------- косметика
func _cos_key(type: String, id: String) -> String:
	return "%s:%s" % [type, id]

## Доступна ли косметика (куплена или «none»).
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

## Экипированный набор для применения к танкам игроков.
func equipped_cosmetics() -> Dictionary:
	return cosmetics.duplicate()

# -------------------------------------------------------------- валюта и улучшения
func add_money(amount: int) -> int:
	if amount <= 0:
		return money
	money += amount
	save_profile()
	return money

func spend_money(amount: int) -> bool:
	if amount < 0 or money < amount:
		return false
	money -= amount
	return true

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

## Цена следующего уровня улучшения или -1, если оно максимально.
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

## Собирает модификаторы от всех купленных улучшений — их перемножает
## Tank.recompute() с модификаторами перков.
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

# -------------------------------------------------------------- перки
func is_unlocked(id: String) -> bool:
	return unlocked.has(id)

## Перки, доступные для выбора при повышении уровня в партии.
func available_perk_ids() -> Array:
	var out := []
	for p in Perks.all():
		if unlocked.has(p["id"]):
			out.append(p["id"])
	return out

## Прогресс по челленджу перка: {current, need, desc} либо пустой словарь.
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

## Открывает всё, что положено по текущему уровню.
func _sync_level_unlocks() -> void:
	for lvl in Perks.UNLOCK_TABLE.keys():
		if global_level >= int(lvl):
			for id in Perks.UNLOCK_TABLE[lvl]:
				unlocked[id] = true
	check_challenges()
