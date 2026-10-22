extends Node

var failures := 0
var game
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)

func frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	Prof.stats.merge({"gamesPlayed": 48, "gamesWon": 29, "totalKills": 728, "timesDied": 146, "damageInGame": 12450, "rapidKills": 8, "cleanStreak": 19, "defenseWaveReached": 24, "ramKills": 64, "longKills": 143, "lowHpKills": 38, "bossKills": 22, "bridgeKills": 17}, true)
	Prof.bestiary_kills = {"grunt": 280, "scout": 160, "heavy": 112, "sniper": 76, "mortar": 48, "boss": 22}
	Prof.match_history = []
	for i in 24:
		Prof.match_history.append({"date": 1792600000 + i * 1800, "mode": ["ffa", "ctf", "defense", "koth"][i % 4], "victory": i % 3 != 0, "kills": 7 + (i * 7) % 25, "deaths": (i * 3) % 7, "damage": 700 + (i * 317) % 4300, "score": i * 9, "seconds": 180 + i * 10, "wave": i % 12, "class": ["scout", "heavy", "sniper"][i % 3], "cannon": ["ice", "acid", "shock"][i % 3]})
	await frame()
	game.ui.open_stats()
	await frame()
	for language in ["ru", "en", "fr", "es"]:
		I18n.set_lang(language)
		await frame()
		for tab in 4:
			var dashboard: StatsDashboard = game.ui._stats_body.get_child(0)
			(dashboard.get_child(0) as TabBar).current_tab = tab
			await frame()
			check(dashboard.content.get_child_count() > 0, "%s tab %d has content" % [language, tab])
			get_viewport().get_texture().get_image().save_png("user://stats_%s_%d.png" % [language, tab])
	I18n.set_lang("en")
	await frame()
	var dashboard: StatsDashboard = game.ui._stats_body.get_child(0)
	dashboard.tab = 1
	dashboard.mode = "tutorial"
	dashboard.rebuild()
	await frame()
	var charts := dashboard.find_children("*", "StatsChart", true, false)
	check(charts.size() == 1 and charts[0].series.is_empty(), "empty mode filter displays empty chart")
	dashboard.mode = "all"
	dashboard.limit = 10
	dashboard.metric = "damage"
	dashboard.rebuild()
	await frame()
	charts = dashboard.find_children("*", "StatsChart", true, false)
	check(charts.size() == 1 and charts[0].labels.size() == 10 and charts[0].series.size() == 1, "history limit and damage metric affect plotted data")
	check(charts[0]._get_tooltip(Vector2(charts[0].size.x, 50)).contains("Damage"), "chart tooltip contains actual metric")
	dashboard.tab = 3
	dashboard.rebuild()
	await frame()
	var trees := dashboard.find_children("*", "Tree", true, false)
	check(trees.size() == 1, "all-counters table exists")
	if not trees.is_empty():
		trees[0].column_title_clicked.emit(1, MOUSE_BUTTON_LEFT)
		check(trees[0].get_root().get_first_child().get_text(1) == "12450", "numeric table sorting orders values numerically")
	Prof.match_history = []
	Prof._empty_stats()
	Prof.bestiary_kills = {}
	game.ui.open_stats()
	await frame()
	dashboard = game.ui._stats_body.get_child(0)
	(dashboard.get_child(0) as TabBar).current_tab = 1
	await frame()
	get_viewport().get_texture().get_image().save_png("user://stats_empty.png")
	check(game.ui.is_stats_open, "empty profile opens without division by zero")
	get_window().size = Vector2i(800, 600)
	await frame()
	await frame()
	var panel: Control = game.ui._stats.get_meta("content_panel")
	check(panel.size.x <= game.ui.size.x + 1, "dashboard fits narrow UI viewport")
	game.ui.close_stats()
	check(not game.ui.is_stats_open, "statistics overlay closes normally")
	print("=== STATS DASHBOARD: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
