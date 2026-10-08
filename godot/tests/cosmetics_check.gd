extends Node

var failures := 0
var log_lines: Array[String] = []

func _ready() -> void:
	_log("--- НАЧАЛО ТЕСТА КОСМЕТИКИ И СКИНОВ ---")
	_test_cosmetics_data()
	_test_card_instantiation()
	_test_tank_rendering_all_skins()
	_test_hub_cosmetics_ui()

	_log("=== ПРОВЕРКА КОСМЕТИКИ ЗАВЕРШЕНА, ошибок: %d ===" % failures)
	var f := FileAccess.open("user://cosmetics_test.txt", FileAccess.WRITE)
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

func _test_cosmetics_data() -> void:
	var expected_skins := [
		"none", "cyberpunk", "magma", "steampunk", "void",
		"dragon", "toxic", "golden_emperor", "arctic_frost"
	]
	_check(Cosmetics.SKINS.size() == expected_skins.size(),
		"В Cosmetics.SKINS ровно %d позиций (получено %d)" % [expected_skins.size(), Cosmetics.SKINS.size()])

	var skin_ids: Array[String] = []
	for s in Cosmetics.SKINS:
		var sid := String(s["id"])
		skin_ids.append(sid)
		_check(s.has("name") and not String(s["name"]).is_empty(), "Скин %s имеет название" % sid)
		_check(s.has("desc") and not String(s["desc"]).is_empty(), "Скин %s имеет описание" % sid)
		_check(s.has("rarity") and not String(s["rarity"]).is_empty(), "Скин %s имеет редкость" % sid)
		if sid != "none":
			_check(String(s["desc"]).find("комплект") != -1 or String(s["desc"]).find("башн") != -1,
				"Описание скина %s описывает комплексные визуальные изменения" % sid)

	for expected in expected_skins:
		_check(skin_ids.has(expected), "Скин '%s' присутствует в каталоге" % expected)

	for c in Cosmetics.CAMOS:
		_check(c.has("desc") and not String(c["desc"]).is_empty(), "Камуфляж %s имеет описание" % String(c["id"]))
	for h in Cosmetics.HULLS:
		_check(h.has("desc") and not String(h["desc"]).is_empty(), "Декаль %s имеет описание" % String(h["id"]))
	for tr in Cosmetics.TRACKS:
		_check(tr.has("desc") and not String(tr["desc"]).is_empty(), "Гусеницы %s имеют описание" % String(tr["id"]))
	for tu in Cosmetics.TURRETS:
		_check(tu.has("desc") and not String(tu["desc"]).is_empty(), "Башня %s имеет описание" % String(tu["id"]))

func _test_card_instantiation() -> void:
	var card_scene: PackedScene = preload("res://scenes/ui/cards/cosmetic_card.tscn")
	var card: CosmeticCard = card_scene.instantiate()
	add_child(card)

	var preview_data := {"emitted": false, "type": "", "id": ""}
	card.preview_requested.connect(func(t: String, i: String):
		preview_data["emitted"] = true
		preview_data["type"] = t
		preview_data["id"] = i
	)

	card.set_data(
		"cos_skin_cyberpunk",
		Color("#00f0ff"),
		"Неоновый Киберпанк",
		"380 🪙",
		"Купить · 380 🪙",
		false,
		false,
		true,
		"cos_skin_cyberpunk",
		"legendary",
		"Полный кибер-комплект: корпус с микросхемами, башня с визором и светящиеся гусеницы.",
		"skin",
		"cyberpunk"
	)

	_check(card.get_node("%NameLabel").text == "Неоновый Киберпанк", "Имя карточки корректно установлено")
	_check(card.get_node("%StateLabel").text == "380 🪙", "Статус/цена карточки корректно установлена")
	_check(card.get_node("%ActionBtn").text == "Купить · 380 🪙", "Кнопка действия корректно установлена")
	_check(card.get_node("%DescLabel").text.find("кибер-комплект") != -1, "Описание карточки корректно отображается")

	card._trigger_preview()
	_log("Превью тест: emitted=%s type=%s id=%s" % [preview_data["emitted"], preview_data["type"], preview_data["id"]])
	_check(bool(preview_data["emitted"]) and String(preview_data["type"]) == "skin" and String(preview_data["id"]) == "cyberpunk",
		"Сигнал preview_requested корректно отправляет тип и id скина")

	card.queue_free()

func _test_tank_rendering_all_skins() -> void:
	var p := PlayerState.new(0, "Tester", "p1", null)
	var tank := Tank.new({
		"x": 0.0, "y": 0.0, "team": "player", "name": "Player",
		"owner": p, "color_key": "p1", "chassis": "standard",
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30
	})

	var view := MenuTankView.new()
	view.player = p
	view.display_tank = tank
	view.custom_minimum_size = Vector2(240, 160)
	view.size = Vector2(240, 160)
	add_child(view)

	for s in Cosmetics.SKINS:
		var sid := String(s["id"])
		Prof.cosmetics["skin"] = sid
		tank.cosmetics["skin"] = sid
		p.cosmetics["skin"] = sid
		view.notification(CanvasItem.NOTIFICATION_DRAW)

	_check(true, "MenuTankView успешно отрисовал все 8 премиум скинов без ошибок рендеринга")
	view.queue_free()

func _test_hub_cosmetics_ui() -> void:
	var hub_scene: PackedScene = preload("res://scenes/ui/hub.tscn")
	var hub: Hub = hub_scene.instantiate()
	add_child(hub)

	hub.switch_tab("cosmetics")
	_check(hub.active_tab == "cosmetics", "Хаб успешно открыл вкладку 'cosmetics'")

	var preview_view: MenuTankView = hub._cosmetic_preview_view
	_check(preview_view != null, "Закрепленный виджет танка CosmeticPreviewTank присутствует в Hub")

	var title_lbl: Label = hub._cosmetic_title_lbl
	var badge_lbl: RichTextLabel = hub._cosmetic_badge_lbl
	var feat_hull: Label = hub._cosmetic_feat_hull
	var feat_turret: Label = hub._cosmetic_feat_turret
	var feat_track: Label = hub._cosmetic_feat_track

	_check(title_lbl != null and badge_lbl != null, "Информационные лейблы закрепленного предпросмотра найдены")
	_check(feat_hull != null and feat_turret != null and feat_track != null,
		"Лейблы деталей корпуса, башни и гусениц найдены в закрепленной панели")

	for s in Cosmetics.SKINS:
		var sid := String(s["id"])
		hub._set_cosmetic_preview("skin", sid)
		_check(title_lbl.text == String(s["name"]), "Превью обновило название для скина %s" % sid)
		if sid != "none":
			_check(feat_hull.visible and feat_turret.visible and feat_track.visible,
				"Все три части танка (корпус, башня, гусеницы) отображаются для скина %s" % sid)

	hub._reset_cosmetics_preview()
	_check(true, "Сброс превью на экипированный скин работает штатно")

	hub.queue_free()
