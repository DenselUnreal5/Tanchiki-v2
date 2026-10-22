class_name StatsDashboard
extends VBoxContainer

var tab := 0
var mode := "all"
var limit := 30
var metric := "kills"
var content: VBoxContainer

func _t(key: String, fallback: String) -> String:
	return I18n.t("stats.ui." + key, {}, fallback)

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var tabs := TabBar.new()
	for text in [_t("overview", "Обзор"), _t("battles", "Матчи"), _t("enemies", "Противники"), _t("all", "Все показатели")]: tabs.add_tab(text)
	tabs.add_theme_font_override("font", Fonts.bold)
	tabs.add_theme_font_size_override("font_size", 14)
	tabs.tab_changed.connect(func(index: int): tab = index; rebuild())
	add_child(tabs)
	content = UiKit.vbox(14)
	add_child(content)
	rebuild()

func rebuild() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	match tab:
		0: _overview()
		1: _battles()
		2: _enemies()
		3: _all_stats()

func _panel(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiKit.card_style())
	parent.add_child(panel)
	var box := UiKit.vbox(10)
	panel.add_child(box)
	box.add_child(UiKit.label(title, 14, Cfg.UI_TEXT, true))
	return box

func _note(parent: Node, text: String) -> void:
	var label := UiKit.label(text, 11, Cfg.UI_MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _card(parent: Node, title: String, value: String, color: Color) -> void:
	var box := _panel(parent, title)
	box.add_child(UiKit.label(value, 26, color, true))

func _overview() -> void:
	var stats: Dictionary = Prof.stats
	var cards := GridContainer.new()
	cards.columns = 4
	cards.add_theme_constant_override("h_separation", 10)
	content.add_child(cards)
	_card(cards, _t("starts", "Выходов в бой"), str(stats.get("gamesPlayed", 0)), Cfg.UI_ACCENT)
	_card(cards, _t("wins", "Побед"), str(stats.get("gamesWon", 0)), Color("#72c9a3"))
	_card(cards, _t("kills", "Уничтожений"), str(stats.get("totalKills", 0)), Color("#e8bc72"))
	var deaths := int(stats.get("timesDied", 0))
	_card(cards, "K/D", "%.2f" % (float(stats.get("totalKills", 0)) / deaths) if deaths > 0 else "—", Color("#79bddd"))
	var xp := ProgressBar.new()
	xp.max_value = maxi(1, Prof.xp_to_next_level())
	xp.value = Prof.global_xp
	xp.show_percentage = false
	xp.custom_minimum_size.y = 10
	xp.tooltip_text = "%d / %d XP" % [Prof.global_xp, Prof.xp_to_next_level()]
	content.add_child(xp)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 12)
	content.add_child(grid)
	var results := _panel(grid, _t("results", "Результаты завершённых матчей"))
	var donut := StatsChart.new()
	donut.kind = "donut"
	var wins := 0
	for row in Prof.match_history:
		if row.victory: wins += 1
	donut.series = [{"name": _t("win", "Победа"), "value": wins, "color": Color("#72c9a3")}, {"name": _t("loss", "Поражение"), "value": Prof.match_history.size() - wins, "color": Color("#c7807a")}]
	results.add_child(donut)
	_note(results, _t("history_scope", "Последние 60 завершённых матчей. Старые общие счётчики сохранены."))
	var records := _panel(grid, _t("records", "Личные рекорды"))
	for key in ["damageInGame", "cleanStreak", "rapidKills", "defenseWaveReached"]:
		var line := HBoxContainer.new()
		var label := UiKit.label(I18n.t("stat." + key, {}, Prof.STAT_LABELS[key]), 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(label)
		line.add_child(UiKit.label(str(stats.get(key, 0)), 18, Cfg.UI_ACCENT, true))
		records.add_child(line)
	var combat := _panel(content, _t("combat", "Особые уничтожения"))
	var bars := StatsChart.new()
	bars.kind = "bars"
	bars.custom_minimum_size.y = 160
	for key in ["ramKills", "longKills", "lowHpKills", "bossKills", "bridgeKills"]:
		bars.series.append({"name": I18n.t("stat." + key, {}, Prof.STAT_LABELS[key]), "value": int(stats.get(key, 0)), "color": Cfg.UI_ACCENT})
	combat.add_child(bars)
	_note(combat, _t("overlap", "Категории могут пересекаться: например, уничтожение босса тараном учитывается в обеих."))

func _battles() -> void:
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 12)
	content.add_child(filters)
	var modes := OptionButton.new()
	modes.add_item(_t("all_modes", "Все режимы"))
	for id in StatsHistory.MODES: modes.add_item(_mode_name(id))
	modes.select(0 if mode == "all" else StatsHistory.MODES.find(mode) + 1)
	modes.item_selected.connect(func(index: int): mode = "all" if index == 0 else StatsHistory.MODES[index - 1]; rebuild())
	filters.add_child(modes)
	var count := OptionButton.new()
	for n in [10, 30, 60]: count.add_item(str(n) + " · " + _t("battles", "Матчи"))
	count.select([10, 30, 60].find(limit))
	count.item_selected.connect(func(index: int): limit = [10, 30, 60][index]; rebuild())
	filters.add_child(count)
	var metrics := OptionButton.new()
	metrics.add_item(_t("kd_chart", "Уничтожения / смерти"))
	metrics.add_item(_t("damage", "Нанесённый урон"))
	metrics.select(0 if metric == "kills" else 1)
	metrics.item_selected.connect(func(index: int): metric = "kills" if index == 0 else "damage"; rebuild())
	filters.add_child(metrics)
	var history := StatsHistory.filtered(Prof.match_history, mode, limit)
	var box := _panel(content, _t("trend", "Динамика результатов"))
	var chart := StatsChart.new()
	chart.empty_text = _t("empty", "Завершите матч — здесь появятся ваши результаты.")
	var kills := []
	var deaths := []
	for i in history.size():
		var row: Dictionary = history[i]
		chart.labels.append("#%d · %s · %s" % [i + 1, _date(row.date), _mode_name(row.mode)])
		kills.append(int(row.get(metric, 0)))
		deaths.append(int(row.deaths))
	if not history.is_empty():
		chart.series.append({"name": _t("kills", "Уничтожений") if metric == "kills" else _t("damage", "Нанесённый урон"), "values": kills, "color": Color("#72c9a3")})
		if metric == "kills": chart.series.append({"name": _t("deaths", "Смертей"), "values": deaths, "color": Color("#c7807a")})
	box.add_child(chart)
	_note(box, _t("chart_hint", "Зелёная линия — уничтожения/урон, красная — смерти. Наведите курсор на точку для подробностей."))
	var rows := []
	for row in history:
		var class_name_text := TankClasses.display_name(TankClasses.get_entry(row["class"]))
		rows.append({"values": [_date(row.date), _mode_name(row.mode), _t("win", "Победа") if row.victory else _t("loss", "Поражение"), "%d / %d" % [row.kills, row.deaths], row.damage, class_name_text],
			"sort": [row.date, row.mode, int(row.victory), float(row.kills) / maxi(1, int(row.deaths)), row.damage, class_name_text],
			"color": Color("#72c9a3") if row.victory else Color("#c7807a"),
			"tip": "%s · %d:%02d · %s: %d" % [I18n.dn(Cannons.get_cannon(row.cannon), "name", "cannon"), int(row.seconds) / 60, int(row.seconds) % 60, _t("score", "Счёт"), row.score]})
	rows.reverse()
	_table(content, [_t("date", "Дата"), _t("mode", "Режим"), _t("result", "Итог"), "K / D", _t("damage_short", "Урон"), _t("class", "Класс")], rows)
	_note(content, _t("table_hint", "Нажмите на заголовок столбца для сортировки. История сохраняется между запусками."))

func _enemies() -> void:
	var rows := []
	var total := 0
	for id in Prof.bestiary_kills: total += maxi(0, int(Prof.bestiary_kills[id]))
	var bars := StatsChart.new()
	bars.kind = "bars"
	for id in Prof.bestiary_kills:
		var count := maxi(0, int(Prof.bestiary_kills[id]))
		if count == 0: continue
		var enemy := EnemyTypes.get_type(id)
		var name_text := I18n.dn(enemy, "name", "enemy") if not enemy.is_empty() else String(id)
		rows.append({"values": [name_text, count, "%.1f%%" % (count * 100.0 / maxi(1, total))], "sort": [name_text, count, count]})
	rows.sort_custom(func(a, b): return a.sort[1] > b.sort[1])
	for row in rows.slice(0, 5): bars.series.append({"name": row.values[0], "value": row.values[1], "color": Color("#79bddd")})
	bars.empty_text = _t("no_enemies", "Уничтоженные противники появятся здесь после первых боёв.")
	bars.custom_minimum_size.y = 170
	_panel(content, _t("enemy_top", "Чаще всего уничтожены")).add_child(bars)
	_table(content, [_t("enemy", "Противник"), _t("kills", "Уничтожений"), _t("share", "Доля")], rows)

func _all_stats() -> void:
	var rows := []
	for key in Prof.STAT_KEYS:
		rows.append({"values": [I18n.t("stat." + key, {}, Prof.STAT_LABELS.get(key, key)), int(Prof.stats.get(key, 0)), _t("record", "Рекорд") if Prof.MAX_STATS.has(key) else _t("total", "Всего")], "sort": [I18n.t("stat." + key, {}, key), int(Prof.stats.get(key, 0)), int(Prof.MAX_STATS.has(key))]})
	_table(content, [_t("metric", "Показатель"), _t("value", "Значение"), _t("type", "Тип")], rows, 430)

func _date(timestamp: int) -> String:
	if timestamp <= 0: return "—"
	var offset := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_datetime_string_from_unix_time(timestamp + offset).replace("T", " ").substr(0, 16)

func _mode_name(id: String) -> String:
	return I18n.t("mode." + id, {}, String(Cfg.MODES.get(id, {"name": "Обучение"}).get("name", id)))

func _table(parent: Node, headers: Array, rows: Array, height: float = 260) -> void:
	var tree := Tree.new()
	tree.hide_root = true
	tree.columns = headers.size()
	tree.column_titles_visible = true
	tree.custom_minimum_size = Vector2(0, height)
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.add_theme_font_override("font", Fonts.regular)
	tree.add_theme_font_override("title_button_font", Fonts.bold)
	tree.add_theme_font_size_override("font_size", 12)
	tree.add_theme_stylebox_override("panel", UiKit.flat(Cfg.UI_CARD, 6, 1, Cfg.UI_BORDER))
	for i in headers.size():
		tree.set_column_title(i, headers[i])
		tree.set_column_expand(i, true)
		tree.set_column_custom_minimum_width(i, 65 if headers.size() > 3 else 100)
	tree.set_meta("ascending", true)
	tree.column_title_clicked.connect(func(column: int, _button: int):
		var ascending := not bool(tree.get_meta("ascending"))
		tree.set_meta("ascending", ascending)
		rows.sort_custom(func(a, b): return a.sort[column] < b.sort[column] if ascending else a.sort[column] > b.sort[column])
		_fill_table(tree, rows))
	parent.add_child(tree)
	_fill_table(tree, rows)

func _fill_table(tree: Tree, rows: Array) -> void:
	tree.clear()
	var root := tree.create_item()
	for row in rows:
		var item := tree.create_item(root)
		for i in row.values.size():
			item.set_text(i, str(row.values[i]))
			item.set_tooltip_text(i, String(row.get("tip", "")))
			if i == 2 and row.has("color"): item.set_custom_color(i, row.color)
