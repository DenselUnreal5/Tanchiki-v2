extends Node

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
	_run()
	if had_file:
		var f := FileAccess.open(Prof.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Prof.SAVE_PATH))
	Prof.load_profile()
	print("=== ПРОВЕРКА ПАНЕЛИ РАЗРАБОТЧИКА ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _run() -> void:
	print("[1/5] Уровень")
	DevTools.set_all_perks(false)
	DevTools.set_level(5)
	_check(Prof.global_level == 5 and Prof.global_xp == 0, "уровень выставлен в 5")
	var expected := []
	for lvl in Perks.UNLOCK_TABLE.keys():
		if int(lvl) <= 5:
			expected.append_array(Perks.UNLOCK_TABLE[lvl])
	var all_open := true
	for id in expected:
		if not Prof.is_unlocked(id):
			all_open = false
	_check(all_open, "открылись перки уровней 1–5")
	DevTools.set_level(1000)
	_check(Prof.global_level == DevTools.MAX_LEVEL, "уровень не выше максимума (%d)" % DevTools.MAX_LEVEL)
	DevTools.set_level(-3)
	_check(Prof.global_level == 1, "уровень не ниже 1")

	print("[2/5] Монеты")
	DevTools.set_money(500)
	DevTools.add_money(1000)
	_check(Prof.money == 1500, "монеты добавляются (%d)" % Prof.money)
	DevTools.add_money(-100000)
	_check(Prof.money == 0, "монеты не уходят в минус")

	print("[3/5] Перки")
	DevTools.set_all_perks(true)
	_check(Prof.available_perk_ids().size() == Perks.all().size(), "«открыть всё» открывает все перки")
	DevTools.set_perk("sniper", false)
	_check(not Prof.is_unlocked("sniper"), "отдельный перк закрывается")
	DevTools.set_all_perks(false)
	_check(Prof.unlocked.is_empty(), "«закрыть всё» закрывает все перки")

	print("[4/5] Косметика")
	DevTools.set_all_cosmetics(true)
	var owned := 0
	for c in DevTools.cosmetic_items():
		if Prof.is_cosmetic_owned(String(c["type"]), String(c["id"])):
			owned += 1
	_check(owned == DevTools.cosmetic_items().size(), "вся косметика открыта (%d)" % owned)
	var item: Dictionary = DevTools.cosmetic_items()[0]
	var type := String(item["type"])
	var id := String(item["id"])
	Prof.equip_cosmetic(type, id)
	DevTools.set_cosmetic(type, id, false)
	_check(not Prof.is_cosmetic_owned(type, id) and String(Prof.cosmetics[type]) == "none",
		"закрытая надетая косметика снимается")
	DevTools.set_all_cosmetics(false)
	_check(Prof.cosmetic_owned.is_empty(), "«закрыть всё» убирает всю косметику")

	print("[5/5] Танки")
	DevTools.set_all_tanks(true)
	var classes_ok := true
	for cid in TankClasses.ids():
		if not Prof.is_class_owned(String(cid)):
			classes_ok = false
	var cannons_ok := true
	for c in Cannons.LIST:
		if not Prof.is_cannon_owned(String(c["id"])):
			cannons_ok = false
	_check(classes_ok and cannons_ok, "все классы танков и пушки открыты")
	Prof.equip_class("heavy")
	Prof.equip_cannon("ice")
	DevTools.set_class("heavy", false)
	DevTools.set_cannon("ice", false)
	_check(Prof.equipped_class == TankClasses.DEFAULT and Prof.equipped_cannon == "standard",
		"закрытые надетые класс и пушка сменяются на стандартные")
	DevTools.set_all_tanks(false)
	_check(Prof.is_class_owned(TankClasses.DEFAULT) and Prof.is_cannon_owned("standard"),
		"стандартный класс и пушка остаются доступными")

	var board := DevBoard.new()
	add_child(board)
	for key in ["profile", "perks", "cosmetics", "tanks"]:
		board.open_board()
		board.switch_tab(key)
	_check(board.visible, "панель открывается и переключает вкладки")
	board.close_board()
	_check(not board.visible, "панель закрывается")
	board.queue_free()
