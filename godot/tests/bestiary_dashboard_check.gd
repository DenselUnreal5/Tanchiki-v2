extends Node

var failures := 0
var hub: Hub

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)

func frame() -> void:
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func visible_ids() -> Array:
	var out := []
	for id in hub._bestiary_cards:
		if hub._bestiary_cards[id].visible: out.append(id)
	return out

func capture(label: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://dossier_" + label + ".png")

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	Prof.bestiary_kills = {"grunt": 60, "scout": 15, "heavy": 8, "sniper": 4, "mortar": 2, "pyro": 3, "tesla": 1, "boss": 1}
	await frame()
	game.ui.open_bestiary()
	hub = game.ui._hub
	await frame()
	for language in ["ru", "en", "fr", "es"]:
		I18n.set_lang(language)
		await frame()
		for item in Bestiary.all():
			hub._select_bestiary_tank(item.id)
			await frame()
			var stats := hub._bestiary_detail_container.find_child("VehicleStats", true, false)
			check((stats != null) == Prof.is_bestiary_unlocked(item.id), "%s %s: specs follow unlock state" % [language, item.id])
			hub._bestiary_detail_scroll.scroll_vertical = 100
			hub._select_bestiary_tank("player_standard")
			check(hub._bestiary_detail_scroll.scroll_vertical == 0, "selection resets detail scroll")
		hub._select_bestiary_tank("heavy")
		await frame()
		capture(language)
	I18n.set_lang("ru")
	await frame()
	var filter: OptionButton = hub.find_child("VehicleFilter", true, false)
	filter.select(2)
	filter.item_selected.emit(2)
	check(visible_ids().size() == 5, "player filter has all five cannons")
	hub._bestiary_filter = 3
	hub._filter_bestiary()
	check(visible_ids().size() == 7, "enemy filter has seven units")
	hub._bestiary_filter = 1
	hub._filter_bestiary()
	for id in visible_ids(): check(Prof.is_bestiary_unlocked(id), "discovered filter: " + id)
	hub._bestiary_filter = 0
	hub._bestiary_query = "Химера"
	hub._filter_bestiary()
	check(visible_ids().is_empty(), "search does not reveal classified names")
	check(hub._bestiary_empty.visible, "empty search explains no matches")
	var search: LineEdit = hub.find_child("VehicleSearch", true, false)
	search.text = "Громила"
	search.text_changed.emit(search.text)
	check(visible_ids() == ["heavy"], "search finds translated name")
	hub._bestiary_query = "штурмовик"
	hub._filter_bestiary()
	check(visible_ids().has("heavy") and visible_ids().has("pyro"), "search finds translated role")
	hub._bestiary_query = ""
	hub._filter_bestiary()
	hub._select_bestiary_tank("boss_chimera")
	await frame()
	capture("locked")
	for id in ["boss_rammer", "boss_chimera", "chimera_clone"]: Prof.bestiary_kills[id] = 1
	for language in ["ru", "en", "fr", "es"]:
		I18n.set_lang(language)
		await frame()
		for id in ["boss_rammer", "boss_chimera", "chimera_clone"]:
			hub._select_bestiary_tank(id)
			await frame()
			check(hub._bestiary_detail_container.find_child("VehicleStats", true, false) != null, language + " unlocked boss renders: " + id)
	I18n.set_lang("ru")
	await frame()
	hub._select_bestiary_tank("player_fire")
	await frame()
	capture("fire")
	for language in ["ru", "fr", "es", "en"]:
		I18n.set_lang(language)
		await frame()
		get_window().size = Vector2i(800, 600)
		await frame()
		hub.refresh_language()
		await frame()
		check(hub._panel.size.x <= UiKit.virtual_screen(hub).x, language + " dossier fits 800x600")
		for card in hub._bestiary_cards.values():
			var padding: Control = card.get_child(0)
			check(card.size.y + 1 >= padding.get_combined_minimum_size().y, language + " card reserves translated text height")
		capture(language + "_narrow")
	game.ui.close_bestiary()
	check(not game.ui.is_bestiary_open, "close works")
	print("=== DOSSIER DASHBOARD: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
