extends Node

var game: Node
var failures := 0
var scanned := 0
var scanned_log := {}
var report := {}
var detail := {}

var LANGS := ["ru", "en", "fr", "es"]
var shots_dir := ""
const SCREENS := ["menu", "settings_general", "settings_sound", "settings_graphics", "settings_controls", "settings_access",
	"stats", "daily", "leaderboards", "gallery", "garage", "cosmetics", "bestiary", "achievements", "map_editor", "net",
	"perk", "hud", "pause", "controls", "gameover", "tutorial"]

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(30)
	var ui = game.ui
	var saved: String = I18n.lang
	var env_langs := OS.get_environment("LANG_FIT_LANGS")
	if env_langs != "":
		LANGS = Array(env_langs.split(","))
	shots_dir = OS.get_environment("LANG_FIT_SHOTS")
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	for code in LANGS:
		I18n.lang = code
		I18n.language_changed.emit()
		await _frames(6)
		report[code] = {}
		detail[code] = {}
		for screen in SCREENS:
			if ["perk", "hud", "pause", "controls", "gameover", "tutorial"].has(screen):
				continue
			ui.hide_all_overlays()
			await _frames(2)
			await _open(ui, screen)
			await _frames(10)
			var issues := _scan(get_tree().root, screen)
			scanned_log["%s/%s" % [code, screen]] = scanned
			if shots_dir != "":
				get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [shots_dir, code, screen])
			report[code][screen] = issues.size()
			detail[code][screen] = issues
		ui.hide_all_overlays()
		await _frames(2)
		await _match_flows(code)
	I18n.lang = saved
	I18n.language_changed.emit()
	_print()
	print("=== ПРОВЕРКА ВМЕЩАЕМОСТИ ТЕКСТА ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _record(code: String, screen: String) -> void:
	var issues := _scan(get_tree().root, screen)
	report[code][screen] = issues.size()
	detail[code][screen] = issues
	if shots_dir != "":
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [shots_dir, code, screen])

func _match_flows(code: String) -> void:
	var ui = game.ui
	ui.settings["mode"] = "ffa"
	ui.settings["game_type"] = "single"
	ui.settings["level"] = 1
	game.start_match()
	await _frames(10)
	_record(code, "perk")
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
		await _frames(2)
	await _frames(90)
	_record(code, "hud")
	game.pause()
	await _frames(8)
	_record(code, "pause")
	ui.open_controls()
	await _frames(8)
	_record(code, "controls")
	ui.hide_all_overlays()
	game.resume()
	await _frames(4)
	game.world._finish(game.players[0].name, 0, "player", "test")
	await _frames(20)
	_record(code, "gameover")
	game.to_menu()
	await _frames(10)
	ui.settings["mode"] = "tutorial"
	game.start_match()
	await _frames(90)
	_record(code, "tutorial")
	game.to_menu()
	await _frames(10)
	ui.settings["mode"] = "ffa"

func _open(ui, screen: String) -> void:
	match screen:
		"menu":
			ui.show_menu()
		"settings_general", "settings_sound", "settings_graphics", "settings_controls", "settings_access":
			ui._settings_active_tab = screen.replace("settings_", "")
			ui.open_settings()
		"stats":
			ui.open_stats()
		"daily":
			ui.open_daily()
		"leaderboards":
			ui.open_leaderboards()
		"gallery":
			ui.open_gallery()
		"garage":
			ui.open_garage()
		"cosmetics":
			ui.open_cosmetics()
		"bestiary":
			ui.open_bestiary()
		"achievements":
			ui.open_achievements()
		"map_editor":
			ui.open_map_editor()
		"net":
			ui.open_net()

func _under_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false

func _scan(root: Node, screen: String) -> Array:
	var out := []
	scanned = 0
	var cyr := RegEx.new()
	cyr.compile("[А-Яа-яЁё]")
	var vp := get_viewport().get_visible_rect().size
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Control) or not (n as Control).is_visible_in_tree():
			continue
		var ctl := n as Control
		var rect := ctl.get_global_rect()
		var text := ""
		var kind := ""
		if ctl is Label:
			text = (ctl as Label).text
			kind = "label"
		elif ctl is Button:
			text = (ctl as Button).text
			kind = "button"
		elif ctl is RichTextLabel:
			text = (ctl as RichTextLabel).get_parsed_text()
			kind = "rich"
		if text.strip_edges() == "":
			continue
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			continue
		scanned += 1
		var font: Font = ctl.get_theme_font("font")
		var fs: int = ctl.get_theme_font_size("font_size")
		var problem := ""
		if I18n.lang != "ru" and text != "Русский" and cyr.search(text) != null:
			problem = "кириллица в нерусском интерфейсе"
		if problem == "" and ctl is Label:
			var lab := ctl as Label
			if lab.autowrap_mode == TextServer.AUTOWRAP_OFF:
				var need := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if (lab.clip_text or lab.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING) and need > lab.size.x + 1.0:
					problem = "обрезан по ширине (%d > %d)" % [need, lab.size.x]
			else:
				if lab.get_minimum_size().y > lab.size.y + 2.0 and lab.get_line_count() > lab.get_visible_line_count():
					problem = "обрезан по высоте"
		elif ctl is Button:
			var btn := ctl as Button
			if btn.clip_text:
				var needb := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if needb > btn.size.x - 6.0:
					problem = "кнопка обрезана (%d > %d)" % [needb, btn.size.x]
		if problem == "":
			var mn := ctl.get_combined_minimum_size()
			if mn.x > ctl.size.x + 2.0 or mn.y > ctl.size.y + 2.0:
				problem = "меньше своего минимума (%dx%d < %dx%d)" % [ctl.size.x, ctl.size.y, mn.x, mn.y]
		var par := ctl.get_parent()
		if problem == "" and par is Control and (par as Control).is_visible_in_tree() and not (par is ScrollContainer):
			var pr := (par as Control).get_global_rect()
			if pr.size.x > 4.0 and (rect.end.x > pr.end.x + 3.0 or rect.end.y > pr.end.y + 3.0):
				problem = "выступает за родителя (%d > %d)" % [rect.end.x, pr.end.x]
		if problem == "" and not _under_scroll(ctl):
			if rect.end.x > vp.x + 2.0 or rect.end.y > vp.y + 2.0 or rect.position.x < -2.0:
				problem = "выходит за экран (%d..%d)" % [rect.position.x, rect.end.x]
		if problem != "":
			out.append("%s «%s» %s" % [kind, text.substr(0, 38).replace("\n", " "), problem])
	return out

func _print() -> void:
	print("Проверено элементов с текстом: ", str(scanned_log.size()) + " экранов")
	print("Подозрительные места по экранам (ru / en / fr / es):")
	for screen in SCREENS:
		var row := []
		for code in LANGS:
			row.append(str(report[code][screen]))
		print("  %-18s %s" % [screen, " / ".join(row)])
	var leaks := {}
	for code in LANGS:
		if code == "ru" or not detail.has(code):
			continue
		for screen in SCREENS:
			for s in detail[code].get(screen, []):
				if String(s).contains("кириллица"):
					leaks["%s/%s: %s" % [code, screen, s]] = true
	for l in leaks.keys():
		print("   УТЕЧКА РУССКОГО: ", l)
	if not leaks.is_empty():
		failures += 1
		print("  ОШИБКА: русский текст в нерусском интерфейсе: %d мест" % leaks.size())
	for code in ["fr", "es"]:
		if not report.has(code) or not report.has("en"):
			continue
		var extra := 0
		for screen in SCREENS:
			var diff: int = int(report[code][screen]) - int(report["en"][screen])
			if diff > 0:
				extra += diff
				var seen_en := {}
				for s in detail["en"][screen]:
					seen_en[s] = true
				for s in detail[code][screen]:
					if not seen_en.has(s):
						print("   [%s %s] %s" % [code, screen, s])
		print("  лишних относительно английского в %s: %d" % [code, extra])
		if extra > 12:
			failures += 1
			print("  ОШИБКА: слишком много мест, где текст %s не помещается" % code)
