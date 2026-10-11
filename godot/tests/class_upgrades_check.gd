extends Node

const RATIO_KEYS := ["dmgMult", "damageTakenMult", "ramMult", "bulletSpeedMult", "pickupRadiusMult", "dashCooldownMult", "heatPerShotMult"]

var game: Node
var failures := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	var backup := FileAccess.get_file_as_bytes(Prof.SAVE_PATH)
	var had_file := FileAccess.file_exists(Prof.SAVE_PATH)
	var saved_upgrades: Dictionary = Prof.upgrades.duplicate()
	var saved_class := Prof.equipped_class
	var saved_cannon := Prof.equipped_cannon
	var saved_owned: Dictionary = Prof.class_owned.duplicate()

	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	_check_upgrade_entry()
	for cid in TankClasses.ids():
		_check_class(String(cid))

	Prof.upgrades = saved_upgrades
	Prof.equipped_class = saved_class
	Prof.equipped_cannon = saved_cannon
	Prof.class_owned = saved_owned
	if had_file:
		var f := FileAccess.open(Prof.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Prof.SAVE_PATH))
	print("=== ПРОВЕРКА АПГРЕЙДОВ НА КЛАССАХ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check_upgrade_entry() -> void:
	print("[апгрейд] Манёвровые дюзы")
	var up := Upgrades.get_upgrade("dash_cd")
	_check(not up.is_empty() and String(up["category"]) == "speed", "апгрейд есть во вкладке «Скорость»")
	_check(is_equal_approx(Upgrades.mult(up, int(up["max_level"])), 0.52), "на максимуме откат рывка ×0.52")
	var missing := []
	for u in Upgrades.LIST:
		if PerkIcons.texture_of("upg_" + String(u["id"])) == null:
			missing.append(String(u["id"]))
	_check(missing.is_empty(), "у всех апгрейдов есть иконка %s" % ("" if missing.is_empty() else str(missing)))

func _set_upgrades(maxed: bool) -> void:
	for u in Upgrades.LIST:
		Prof.upgrades[u["id"]] = int(u["max_level"]) if maxed else 0

func _start(cid: String) -> Tank:
	Prof.class_owned[cid] = true
	Prof.equipped_class = cid
	Prof.equipped_cannon = "standard"
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["difficulty"] = "medium"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	var tank: Tank = game.players[0].tank
	tank.spawn_protect = 0
	return tank

func _snap(tank: Tank) -> Dictionary:
	var world = game.world
	tank.fire_cooldown = 0
	tank.overheated = false
	tank.heat = 0.0
	var before: int = world.bullets.size()
	tank.shoot(world)
	var shot_scale := -1.0
	if world.bullets.size() > before:
		shot_scale = float(world.bullets[before].dmg_scale)
	var s := {
		"max_hp": tank.max_hp, "speed": tank.speed, "fire_rate": tank.fire_rate,
		"base_fire_rate": tank.base_fire_rate, "dash_cd": tank.dash_cooldown_max(),
		"regen": float(tank.mods["regenPerMinute"]), "shot_scale": shot_scale,
	}
	for k in RATIO_KEYS:
		s[k] = float(tank.mods[k])
	tank.heat = 0.0
	tank.overheated = false
	var shots := 0
	while not tank.overheated and shots < 30:
		tank.fire_cooldown = 0
		tank.shoot(world)
		shots += 1
	s["shots_to_overheat"] = shots
	tank.heat = 0.0
	tank.overheated = false
	return s

func _check_class(cid: String) -> void:
	var entry := TankClasses.get_entry(cid)
	print("[класс] %s" % TankClasses.display_name(entry))
	_set_upgrades(false)
	var plain := _snap(_start(cid))
	_set_upgrades(true)
	var um := Prof.upgrade_mods()
	var tank := _start(cid)
	_check(tank.class_id == cid, "в бою надет класс %s" % cid)
	var fs := TankClasses.final_stats(cid, um, float(Cfg.DIFFICULTY["medium"]["player_hp"]))
	_check(int(fs["hp"]) == int(tank.max_hp) and int(fs["fire_rate"]) == tank.fire_rate \
		and is_equal_approx(float(fs["speed"]), tank.speed),
		"%s: цифры карточки гаража совпадают с танком в бою (HP %d, перезарядка %d, ход %.2f)" % [
			cid, fs["hp"], fs["fire_rate"], fs["speed"]])
	var up := _snap(tank)
	_compare(cid, plain, up, um, "в начале боя")
	_check(int(up["shots_to_overheat"]) > int(plain["shots_to_overheat"]),
		"%s: до перегрева выстрелов больше (%d → %d)" % [cid, plain["shots_to_overheat"], up["shots_to_overheat"]])

	tank.respawn(tank.x, tank.y)
	_compare(cid, plain, _snap(tank), um, "после возрождения")

	var player = game.players[0]
	player.perk_ids.append("regen")
	tank.recompute()
	var with_perk := _snap(tank)
	_check(is_equal_approx(with_perk["dmgMult"], up["dmgMult"]) and is_equal_approx(with_perk["speed"], up["speed"]),
		"%s: перк не сбрасывает апгрейды" % cid)

func _compare(cid: String, plain: Dictionary, up: Dictionary, um: Dictionary, when: String) -> void:
	var bad := []
	if absf(float(up["max_hp"]) / float(plain["max_hp"]) - float(um["maxHPMult"])) > 0.02:
		bad.append("HP %.0f→%.0f" % [plain["max_hp"], up["max_hp"]])
	if absf(float(up["speed"]) / float(plain["speed"]) - float(um["speedMult"])) > 0.001:
		bad.append("скорость %.2f→%.2f" % [plain["speed"], up["speed"]])
	var expect_fr := maxi(4, int(round(float(up["base_fire_rate"]) * float(um["fireRateMult"]))))
	if int(up["fire_rate"]) != expect_fr or int(up["fire_rate"]) >= int(plain["fire_rate"]):
		bad.append("перезарядка %d→%d (ждали %d)" % [plain["fire_rate"], up["fire_rate"], expect_fr])
	for k in RATIO_KEYS:
		if absf(float(up[k]) / float(plain[k]) - float(um[k])) > 0.001:
			bad.append("%s %.3f→%.3f" % [k, plain[k], up[k]])
	if absf(float(up["regen"]) - float(plain["regen"]) - float(um["regenPerMinute"])) > 0.01:
		bad.append("ремонт %.0f→%.0f" % [plain["regen"], up["regen"]])
	if absf(float(up["dash_cd"]) - round(float(plain["dash_cd"]) * float(um["dashCooldownMult"]))) > 1.0:
		bad.append("откат рывка %d→%d" % [plain["dash_cd"], up["dash_cd"]])
	if float(plain["shot_scale"]) <= 0.0 or absf(float(up["shot_scale"]) / float(plain["shot_scale"]) - float(um["dmgMult"])) > 0.001:
		bad.append("урон выстрела %.3f→%.3f" % [plain["shot_scale"], up["shot_scale"]])
	_check(bad.is_empty(), "%s %s: апгрейды действуют %s" % [cid, when, "" if bad.is_empty() else str(bad)])
