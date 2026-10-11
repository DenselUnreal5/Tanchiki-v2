extends Node

var failures := 0
var saved_bytes := PackedByteArray()
var had_file := false
var saved_level := 1
var saved_class := "standard"

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	had_file = FileAccess.file_exists(Prof.SAVE_PATH)
	if had_file:
		saved_bytes = FileAccess.get_file_as_bytes(Prof.SAVE_PATH)
	saved_level = Prof.global_level
	saved_class = Prof.equipped_class

	await _run()

	Prof.equipped_class = saved_class
	if had_file:
		var f := FileAccess.open(Prof.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(saved_bytes)
		f.close()
	elif FileAccess.file_exists(Prof.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Prof.SAVE_PATH))
	print("=== ПРОВЕРКА ГАРАЖА КЛАССОВ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _cards(hub: Node) -> Dictionary:
	var out := {}
	for e in TankClasses.LIST:
		var card = hub._find_by_meta(hub._body, "card_id", "class_" + String(e["id"]))
		if card != null:
			out[String(e["id"])] = card
	return out

func _run() -> void:
	var hub: Hub = preload("res://scenes/ui/hub.tscn").instantiate()
	add_child(hub)
	await get_tree().process_frame

	var saved_money := Prof.money
	var saved_kills: Dictionary = Prof.bestiary_kills.duplicate()
	var saved_owned: Dictionary = Prof.class_owned.duplicate()
	Prof.money = 3500
	Prof.bestiary_kills = {"grunt": 50, "scout": 60, "heavy": 20}
	Prof.class_owned = {"grunt": true}
	Prof.equipped_class = "standard"
	hub.switch_tab("garage")
	await get_tree().process_frame

	var cards := _cards(hub)
	_check(cards.size() == TankClasses.LIST.size(), "в Гараже карточки всех шести классов")

	var std_btn: Button = cards["standard"].get_node("%ActionBtn")
	var grunt_btn: Button = cards["grunt"].get_node("%ActionBtn")
	var scout_btn: Button = cards["scout"].get_node("%ActionBtn")
	var heavy_btn: Button = cards["heavy"].get_node("%ActionBtn")
	_check(std_btn.disabled, "Универсал надет, кнопка неактивна")
	_check(not grunt_btn.disabled and grunt_btn.text.find("Надеть") != -1, "купленный Рядовой доступен для надевания")
	_check(not scout_btn.disabled and scout_btn.text.find("3000") != -1, "Разведчик открыт: кнопка покупки за 3000 активна")
	_check(heavy_btn.disabled, "Громила закрыт, кнопка неактивна")
	var heavy_state: Label = cards["heavy"].get_node("%StateLabel")
	_check(heavy_state.text.find("20") != -1 and heavy_state.text.find("75") != -1, "у закрытого класса показан прогресс 20/75")
	var details_ok := true
	for cid in cards.keys():
		var fs := TankClasses.final_stats(String(cid), Prof.upgrade_mods(), float(Cfg.DIFFICULTY["medium"]["player_hp"]))
		var details: Label = cards[cid].get_node_or_null("Row/Info/DetailsLabel")
		if details == null or not details.visible or details.text.find("HP %d" % int(fs["hp"])) == -1 \
				or details.text.find("%d%%" % int(fs["speed_pct"])) == -1:
			details_ok = false
			print("    карточка %s: %s" % [cid, details.text if details != null else "нет строки"])
	_check(details_ok, "на всех карточках классов итоговые HP и ход с учётом апгрейдов")
	_check(cards["heavy"].tooltip_text.find("до перегрева") != -1, "в подсказке класса расшифровка характеристик")

	grunt_btn.pressed.emit()
	await get_tree().process_frame
	_check(Prof.equipped_class == "grunt", "нажатие на купленный класс надевает его")

	cards = _cards(hub)
	scout_btn = cards["scout"].get_node("%ActionBtn")
	scout_btn.pressed.emit()
	await get_tree().process_frame
	_check(Prof.is_class_owned("scout") and Prof.equipped_class == "scout" and Prof.money == 500,
		"покупка списывает 3000 и надевает класс")

	cards = _cards(hub)
	heavy_btn = cards["heavy"].get_node("%ActionBtn")
	heavy_btn.pressed.emit()
	_check(Prof.equipped_class == "scout" and not Prof.is_class_owned("heavy"), "закрытый класс нажатием не купить и не надеть")

	hub.switch_tab("cosmetics")
	await get_tree().process_frame
	var preview_tank: Tank = hub._cosmetic_preview_tank
	_check(preview_tank != null and preview_tank.chassis_id == "light", "превью ангара показывает шасси класса")

	hub.switch_tab("bestiary")
	hub._update_bestiary_detail("heavy")
	await get_tree().process_frame
	var found := false
	for c in hub._bestiary_detail_container.get_children():
		if c is Label and String(c.text).find("пилотировать") != -1 and String(c.text).find("20/75") != -1:
			found = true
	_check(found, "в бестиарии у Громилы строка с прогрессом 20/75")

	Prof.money = saved_money
	Prof.bestiary_kills = saved_kills
	Prof.class_owned = saved_owned
	hub.queue_free()
