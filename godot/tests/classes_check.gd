extends Node

var failures := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	_check_catalog()
	_check_profile()
	_check_spawn()
	_check_tutorial()
	_check_respawn()
	_check_mortar()
	_check_perk_filter()
	_check_net_info()
	_check_parity()
	print("=== ПРОВЕРКА КЛАССОВ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _arena(class_id: String, mode: String = "ffa") -> World:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	player.equipped_class = class_id
	var level := LevelGen.generate(1, mode, 4242, "city")
	var world := World.new({
		"map": level["map"], "level": level, "mode": mode, "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 4242,
	})
	world.map.fill(Cfg.T_EMPTY)
	world.tanks = [player.tank]
	world.barrels.clear()
	world.pickups.clear()
	world.weapon_pickups.clear()
	world.power_generators.clear()
	var ptank: Tank = player.tank
	ptank.x = 400.0
	ptank.y = 400.0
	ptank.vx = 0.0
	ptank.vy = 0.0
	ptank.spawn_protect = 0
	return world

func _check_catalog() -> void:
	print("[1/9] Каталог")
	var kills := [0, 50, 60, 75, 90, 100]
	var prices := [0, 2000, 3000, 4000, 5000, 6000]
	_check(TankClasses.LIST.size() == kills.size(), "шесть классов")
	var seen := {}
	var base_mods := Perks.base_modifiers()
	for i in TankClasses.LIST.size():
		var e: Dictionary = TankClasses.LIST[i]
		var id := String(e["id"])
		_check(not seen.has(id), "id «%s» уникален" % id)
		seen[id] = true
		_check(int(e["kills"]) == kills[i], "«%s»: нужно уничтожений %d" % [id, kills[i]])
		_check(int(e["price"]) == prices[i], "«%s»: цена %d" % [id, prices[i]])
		_check(id == "standard" or Bestiary.get_entry(id).size() > 0, "«%s»: есть запись в бестиарии для подсчёта уничтожений" % id)
		_check(TankArt.CHASSIS.has(String(e["chassis"])), "«%s»: шасси «%s» существует" % [id, e["chassis"]])
		var keys_ok := true
		for k in (e["mods"] as Dictionary).keys():
			if not base_mods.has(k):
				keys_ok = false
		_check(keys_ok, "«%s»: ключи модов существуют в Perks.base_modifiers()" % id)
		_check(is_equal_approx(float(e["dmg_mult"]), float(e["fire_mult"])), "«%s»: урон и темп стрельбы растут вместе" % id)
		if float(e["fire_mult"]) > 1.0:
			_check(is_equal_approx(float(e["mods"].get("heatPerShotMult", 1.0)), float(e["fire_mult"])),
				"«%s»: нагрев за выстрел равен множителю темпа" % id)
	_check(not seen.has("boss") and not seen.has("pyro") and not seen.has("tesla"), "боссов и спецтанков в классах нет")
	_check(TankClasses.get_entry("нет такого")["id"] == "standard", "неизвестный id даёт Универсала")
	_check(TankClasses.kills_needed("sniper") == 90 and TankClasses.price("mortar") == 6000, "kills_needed и price")

func _check_profile() -> void:
	print("[2/9] Профиль: открытие по уничтожениям и покупка (свежий экземпляр)")
	var had_file := FileAccess.file_exists(Prof.SAVE_PATH)
	var saved_bytes := FileAccess.get_file_as_bytes(Prof.SAVE_PATH) if had_file else PackedByteArray()
	var prof = load("res://scripts/profile.gd").new()
	var announced := []
	prof.class_unlocked.connect(func(ids: Array): announced.append_array(ids))
	_check(prof.is_class_owned("standard") and prof.is_class_unlocked("standard"), "Универсал доступен всегда")
	_check(not prof.is_class_unlocked("grunt") and not prof.is_class_owned("grunt"), "Рядовой закрыт без уничтожений")
	prof.global_level = 30
	_check(not prof.is_class_unlocked("grunt"), "высокий уровень профиля класс не открывает")
	prof.money = 100000
	var res: Dictionary = prof.buy_class("grunt")
	_check(not bool(res["ok"]) and res["reason"] == "locked" and int(res["need"]) == 50, "купить закрытый класс нельзя")
	var unk: Dictionary = prof.equip_class("нет")
	_check(not bool(unk["ok"]) and unk["reason"] == "unknown", "неизвестный класс отклонён")
	_check(prof.equip_class("grunt")["reason"] == "not_owned", "некупленный класс не надеть")
	for i in 49:
		prof.bestiary_kills["grunt"] = int(prof.bestiary_kills.get("grunt", 0)) + 1
	_check(not prof.is_class_unlocked("grunt"), "49 уничтожений — ещё закрыт")
	prof.bestiary_kills["grunt"] = 49
	prof.record_bestiary_kill("grunt")
	_check(prof.is_class_unlocked("grunt"), "50 уничтожений открывают покупку")
	_check(announced == ["grunt"], "сигнал об открытии пришёл один раз")
	prof.money = 1999
	_check(prof.buy_class("grunt")["reason"] == "money", "без денег купить нельзя")
	prof.money = 5000
	_check(bool(prof.buy_class("grunt")["ok"]) and prof.money == 3000, "покупка списывает 2000")
	_check(prof.buy_class("grunt")["reason"] == "owned", "повторно не покупается")
	_check(bool(prof.equip_class("grunt")["ok"]) and prof.equipped_class == "grunt", "купленный класс надевается")
	prof.bestiary_kills["mortar"] = 99
	prof.record_bestiary_kill("mortar")
	_check(announced == ["grunt", "mortar"], "сигнал для миномёта на сотом уничтожении")
	prof.free()
	if had_file:
		var f := FileAccess.open(Prof.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(saved_bytes)
		f.close()
	elif FileAccess.file_exists(Prof.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Prof.SAVE_PATH))

func _check_spawn() -> void:
	print("[3/9] Появление танка каждого класса")
	var base: Tank = _arena("standard").players[0].tank
	for e in TankClasses.LIST:
		var id := String(e["id"])
		var t: Tank = _arena(id).players[0].tank
		_check(t.class_id == id, "«%s»: class_id" % id)
		_check(t.chassis_id == String(e["chassis"]), "«%s»: шасси" % id)
		_check(absf(t.max_hp - round(base.max_hp * float(e["hp_mult"]))) <= 1.0, "«%s»: HP ×%.2f" % [id, e["hp_mult"]])
		_check(absf(t.base_speed - base.base_speed * float(e["speed_mult"])) < 0.001, "«%s»: скорость ×%.2f" % [id, e["speed_mult"]])
		_check(t.enemy_type.is_empty() and not t.is_boss, "«%s»: enemy_type пуст, is_boss ложно" % id)
		_check(t.owner != null, "«%s»: танк под управлением игрока" % id)

func _check_tutorial() -> void:
	print("[4/9] Туториал всегда Универсал")
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	player.equipped_class = "mortar"
	var level := LevelGen.generate(1, "ffa", 4242, "city")
	World.new({
		"map": level["map"], "level": level, "mode": "tutorial", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 4242,
	})
	_check(player.tank != null and player.tank.class_id == "standard", "в туториале класс сброшен на Универсала")
	_check(player.tank != null and not player.tank.class_lobbed, "в туториале выстрел не навесной")

func _check_respawn() -> void:
	print("[5/9] Возрождение в FFA сохраняет класс")
	var world := _arena("heavy")
	var player: PlayerState = world.players[0]
	var tank: Tank = player.tank
	world.deal_damage(tank, tank.max_hp * 10.0, null, "test")
	_check(not tank.alive, "танк уничтожен")
	var guard := 0
	while not tank.alive and guard < 1200:
		guard += 1
		world.step()
	_check(tank.alive and player.tank == tank, "танк возродился")
	_check(tank.class_id == "heavy" and tank.chassis_id == "heavy", "после возрождения класс и шасси прежние")
	_check(is_equal_approx(tank.hp, tank.max_hp) and tank.max_hp > 150.0, "после возрождения HP класса восстановлено")

func _check_mortar() -> void:
	print("[6/9] Миномёт стреляет навесом")
	var world := _arena("mortar")
	var t: Tank = world.players[0].tank
	_check(t.class_lobbed, "class_lobbed включён")
	t.aim_at(t.x + 200.0, t.y)
	t.fire_cooldown = 0
	var before := world.bullets.size()
	t.shoot(world)
	_check(world.bullets.size() == before + 1 and world.bullets[before].lobbed, "выстрел создаёт навесную пулю")
	var other := _arena("standard")
	var o: Tank = other.players[0].tank
	o.aim_at(o.x + 200.0, o.y)
	o.fire_cooldown = 0
	var b0 := other.bullets.size()
	o.shoot(other)
	_check(other.bullets.size() > b0 and not other.bullets[b0].lobbed, "у Универсала пуля обычная")

func _check_perk_filter() -> void:
	print("[7/9] Фильтр перков по классу")
	_check(TankClasses.perk_allowed("fan_shot", "standard"), "Универсалу веер разрешён")
	_check(not TankClasses.perk_allowed("fan_shot", "mortar"), "Миномёту веер запрещён")
	_check(not TankClasses.perk_allowed("piercing", "mortar"), "Миномёту пробитие запрещено")
	_check(TankClasses.perk_allowed("rapid_fire", "mortar"), "обычный перк миномёту доступен")

func _check_net_info() -> void:
	print("[8/9] Сетевая информация")
	var world := _arena("scout")
	var info := World.tank_info(world.players[0].tank)
	_check(String(info.get("class", "")) == "scout", "tank_info содержит class")
	_check(String(info["chassis"]) == "light", "tank_info несёт шасси класса")

func _sustained(class_id: String) -> Dictionary:
	var world := _arena(class_id)
	var t: Tank = world.players[0].tank
	t.aim_at(t.x + 300.0, t.y)
	for i in 30 * 60:
		t.hp = t.max_hp
		t.shoot(world)
		world.bullets.clear()
		world.step()
	var per_shot: float = t.dmg_scale * float(t.mods["dmgMult"])
	return {"shots": t.shots_fired, "overheats": t.overheats, "dps": float(t.shots_fired) * per_shot / 30.0,
		"hp": t.max_hp, "speed": t.base_speed}

func _check_parity() -> void:
	print("[9/9] Паритет DPS за 30 с непрерывной стрельбы")
	var base := _sustained("standard")
	print("  standard: выстрелов %d, перегревов %d, урон/с %.2f" % [base["shots"], base["overheats"], base["dps"]])
	for e in TankClasses.LIST:
		var id := String(e["id"])
		if id == "standard":
			continue
		var r := _sustained(id)
		var ratio: float = float(r["dps"]) / maxf(0.001, float(base["dps"]))
		print("  %s: выстрелов %d, перегревов %d, урон/с %.2f (×%.2f), HP %d, скорость %.2f" % [
			id, r["shots"], r["overheats"], r["dps"], ratio, r["hp"], r["speed"]])
		_check(absf(ratio - 1.0) <= 0.12, "«%s»: устойчивый DPS в пределах ±12%% от Универсала" % id)
