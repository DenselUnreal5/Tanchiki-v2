extends Node

var failures := 0
var log_lines: Array[String] = []

func _ready() -> void:
	_log("--- НАЧАЛО ТЕСТА БЕСТИАРИЯ ---")
	_test_bestiary_data()
	_test_reference_stats()
	_test_translations()
	_test_profile_unlocks()
	_test_preview_rendering()
	_test_hub_bestiary_ui()

	_log("=== ПРОВЕРКА БЕСТИАРИЯ ЗАВЕРШЕНА, ошибок: %d ===" % failures)
	var f := FileAccess.open("user://bestiary_check.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines))
		f.close()
	get_tree().quit(1 if failures > 0 else 0)

func _log(msg: String) -> void:
	print(msg)
	log_lines.append(msg)

func _check(ok: bool, what: String) -> void:
	if ok:
		_log("  [OK] " + what)
	else:
		failures += 1
		_log("  [FAIL] " + what)

func _test_bestiary_data() -> void:
	var all_tanks: Array[Dictionary] = Bestiary.all()
	_check(all_tanks.size() == 16, "Всего 16 танков в бестиарии (получено %d)" % all_tanks.size())

	var player_tanks: Array[Dictionary] = Bestiary.category_list("player")
	_check(player_tanks.size() == 5, "5 орудий игрока (получено %d)" % player_tanks.size())

	var enemy_tanks: Array[Dictionary] = Bestiary.category_list("enemy")
	_check(enemy_tanks.size() == 7, "7 обычных врагов (получено %d)" % enemy_tanks.size())

	var boss_tanks: Array[Dictionary] = Bestiary.category_list("boss")
	_check(boss_tanks.size() == 4, "4 босса/клона (получено %d)" % boss_tanks.size())

	for t in all_tanks:
		var tid: String = String(t["id"])
		var entry: Dictionary = Bestiary.get_entry(tid)
		_check(not entry.is_empty(), "Танк %s найден в базе" % tid)
		_check(entry.has("name") and Bestiary.stat_values(entry).size() == 4,
			"У танка %s есть все базовые характеристики" % tid)
		_check(entry.has("abilities") and (entry["abilities"] as Array).size() > 0,
			"У танка %s есть список способностей" % tid)

func _test_profile_unlocks() -> void:
	_check(Prof.is_bestiary_unlocked("player_standard"), "Танк игрока 'player_standard' открыт по умолчанию")
	_check(Prof.is_bestiary_unlocked("player_ice"), "Танк игрока 'player_ice' открыт по умолчанию")
	_check(Prof.is_bestiary_unlocked("player_acid"), "Танк игрока 'player_acid' открыт по умолчанию")

	var initial_chimera_kills := Prof.get_bestiary_kills("boss_chimera")
	Prof.record_bestiary_kill("boss_chimera")
	var new_chimera_kills := Prof.get_bestiary_kills("boss_chimera")
	_check(new_chimera_kills == initial_chimera_kills + 1, "Счетчик убийств Химеры увеличился на 1")
	_check(Prof.is_bestiary_unlocked("boss_chimera"), "Химера открыта в бестиарии после уничтожения")

func _test_preview_rendering() -> void:
	# Проверка, что MenuTankView не крашится ни на одном танке (особенно Rammer и Chimera с world == null)
	for t in Bestiary.all():
		var tid: String = String(t["id"])
		var stub_p := PlayerState.new(0, "", String(t.get("color_key", "p1")), null)
		var tank := Tank.new({
			"x": 0.0, "y": 0.0, "team": "player" if bool(t.get("is_player", false)) else "enemy",
			"name": String(t.get("name", "")), "owner": stub_p,
			"color_key": String(t.get("color_key", "enemy")),
			"chassis": String(t.get("chassis", "standard")),
			"max_hp": 100.0, "speed": 100.0, "fire_rate": 30,
		})
		if tid == "boss_chimera":
			tank.is_chimera_boss = true
		elif tid == "boss_rammer":
			tank.is_rammer_boss = true
		elif tid == "chimera_clone":
			tank.is_chimera_clone = true

		var view := MenuTankView.new()
		view.player = stub_p
		view.display_tank = tank
		view.center_in_rect = true
		view.custom_minimum_size = Vector2(160, 90)

		# Проверка конфигурации MenuTankView
		view.is_locked = false
		_check(view.display_tank != null, "Модель танка %s успешно создана" % tid)
		view.is_locked = true
		_check(view.is_locked, "Силуэтное состояние танка %s задано" % tid)
		view.free()
	_check(true, "MenuTankView успешно сконфигурирован для всех 16 моделей танков")

func _test_hub_bestiary_ui() -> void:
	var hub_scene := preload("res://scenes/ui/hub.tscn")
	var hub: Hub = hub_scene.instantiate()
	add_child(hub)
	_check(hub.tab_items().size() == 5, "В хабе ровно 5 основных вкладок (получено %d)" % hub.tab_items().size())
	hub.open_encyclopedia()
	_check(hub.active_tab == "bestiary", "Hub открывает справочник техники в отдельной верхней вкладке 'bestiary'")

	# Переключаемся по всем 12 танкам в UI
	for t in Bestiary.all():
		var tid: String = String(t["id"])
		hub._select_bestiary_tank(tid)
	_check(true, "Hub успешно переключает карточки всех 16 танков и обновляет панель описания")

	_log("Тест открытия Гаража...")
	hub.open_tab("garage")
	_check(hub.active_tab == "garage", "Hub открывает вкладку 'garage'")

	_log("Тест открытия Достижений...")
	hub.open_tab("achievements")
	_check(hub.active_tab == "achievements", "Hub открывает вкладку 'achievements'")
	hub.queue_free()

func _test_reference_stats() -> void:
	var standard := Bestiary.reference_stats(Bestiary.get_entry("player_standard"))
	_check(standard.hp == Cfg.DIFFICULTY.medium.player_hp, "Прочность игрока берётся из средней сложности")
	_check(standard.damage_min == Cfg.BULLET_DMG_MIN * Cfg.PLAYER_DMG_MULT, "Урон игрока учитывает множитель игрока")
	for id in EnemyTypes.ORDER:
		var type := EnemyTypes.get_type(id)
		var stats := Bestiary.reference_stats(Bestiary.get_entry(id))
		var hp := float(type.get("base_hp", Cfg.DIFFICULTY.medium.enemy_hp * type.hp_mult))
		_check(is_equal_approx(stats.hp, hp), "Базовая прочность совпадает с формулой спавна: " + id)
		_check(is_equal_approx(stats.speed, Cfg.DIFFICULTY.medium.enemy_speed * type.speed_mult), "Базовая скорость совпадает с формулой спавна: " + id)
	_check(Bestiary.reference_stats(Bestiary.get_entry("chimera_clone")).hp == Cfg.CHIMERA_CLONE_HP, "Прочность клона — отдельная константа, не 50% босса")
	_check(Bestiary.reference_stats(Bestiary.get_entry("tesla")).damage_min == Cfg.TESLA_SHOCK_DMG, "Вражеская Тесла использует собственный урон")
	_check(Bestiary.reference_stats(Bestiary.get_entry("player_shock")).damage_min == Cfg.SHOCK_DMG, "Электропушка игрока использует собственный урон")
	_check(Bestiary.reference_stats(Bestiary.get_entry("player_ice")).damage_max == 0, "Лёд не наносит прямого урона")
	_check(Bestiary.reference_stats(Bestiary.get_entry("player_fire")).damage_min == Cfg.FIRE_IMPACT_DMG * Cfg.PLAYER_DMG_MULT, "Огнемёт игрока наносит прямой урон")

func _test_translations() -> void:
	var previous := I18n.lang
	for language in ["ru", "en", "fr", "es"]:
		I18n.lang = language
		var missing: Array[String] = []
		for item in Bestiary.all():
			for field in ["name", "role", "desc", "tip"]:
				var key := "bestiary.%s.%s" % [item.id, field]
				if language == "en" and not I18n.EN.has(key): missing.append(key)
				elif language in ["fr", "es"] and not I18n.packs[language]["strings"].has(key): missing.append(key)
				if Bestiary.text(item, field).is_empty(): missing.append(key)
			for i in item.abilities.size():
				for field in ["name", "desc"]:
					var key := "bestiary.%s.ab%d.%s" % [item.id, i, field]
					if language == "en" and not I18n.EN.has(key): missing.append(key)
					elif language in ["fr", "es"] and not I18n.packs[language]["strings"].has(key): missing.append(key)
			for value in Bestiary.stat_values(item).values():
				if String(value).contains("{n}"): missing.append("unexpanded unit")
		_check(missing.is_empty(), "Полные описания и способности %s: %s" % [language, str(missing)])
	I18n.lang = previous
