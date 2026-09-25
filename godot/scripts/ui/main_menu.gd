@tool
class_name MainMenu
extends Control

signal start_pressed
signal nav_pressed(id: String)

const LEFT_PANEL_W := 460.0
const SETTINGS_PANEL_W := 640.0

var settings: Dictionary = {}

var _tip_order: Array = []
var _tip_idx := 0

@onready var _bg: Control = %MenuSceneBg
@onready var _left_panel: ThemedPanel = %LeftPanel
@onready var _col: VBoxContainer = %Col
@onready var _title_box: VBoxContainer = %TitleBox
@onready var _hud_row: HBoxContainer = %HudRow
@onready var _chip_rank: Label = %ChipRank
@onready var _chip_level: Label = %ChipLevel
@onready var _chip_coins: Label = %ChipCoins
@onready var _chip_perks: Label = %ChipPerks
@onready var _mode_btn: Button = %ModeSummaryBtn
@onready var _start_btn: Button = %StartBtn
@onready var _version_pill: PanelContainer = %VersionPill
@onready var _version_label: Label = %VersionLabel
@onready var _nav_grid: GridContainer = %NavGrid
@onready var _tip_ticker: PanelContainer = %TipTicker
@onready var _tip_label: RichTextLabel = %TipLabel
@onready var _settings_panel: ThemedPanel = %SettingsPanel
@onready var _settings_scroll: ScrollContainer = %SettingsScroll
@onready var _settings_body: VBoxContainer = %SettingsBody

func _tr(key: String, fallback: String) -> String:
	return fallback if Engine.is_editor_hint() else I18n.t(key, {}, fallback)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if Engine.is_editor_hint() and settings.is_empty():
		settings = {
			"game_type": "single", "mode": "ffa", "difficulty": "medium",
			"weather": "auto", "daytime": "auto", "location": "auto",
		}
	_bg._settings = settings

	_col.add_theme_constant_override("separation", 10)
	_title_box.add_theme_constant_override("separation", 2)
	_hud_row.add_theme_constant_override("separation", 18)

	_style_chrome()
	_build_title()
	_build_hud_strip()
	_build_mode_and_start()
	_build_version_pill()
	_build_nav_grid()
	_build_settings_groups()
	_build_tip_ticker()
	refresh_profile()

	if not Engine.is_editor_hint():
		_wire_click_sfx(self)
	layout.call_deferred()

func _style_chrome() -> void:
	_left_panel.custom_minimum_size = Vector2(LEFT_PANEL_W, 0)
	_left_panel.border_color = Color.TRANSPARENT
	_left_panel.seed_value = randi()
	_settings_panel.custom_minimum_size = Vector2(SETTINGS_PANEL_W, 0)
	_settings_panel.seed_value = randi()
	_settings_panel.visible = false

	_hud_row.get_parent().add_theme_stylebox_override("panel", UiKit.card_style())
	_version_pill.add_theme_stylebox_override("panel",
		UiKit.flat(Color(Cfg.UI_BG, 0.5), Cfg.RADIUS_SM, 1, Cfg.UI_BORDER))
	_version_pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tip_ticker.add_theme_stylebox_override("panel",
		UiKit.flat(Color(Cfg.UI_BG, 0.45), Cfg.RADIUS_SM))

	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.follow_focus = true
	_settings_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_body.add_theme_constant_override("separation", 12)
	_nav_grid.columns = 2
	_nav_grid.add_theme_constant_override("h_separation", 8)
	_nav_grid.add_theme_constant_override("v_separation", 6)

func _build_title() -> void:
	for c in _title_box.get_children():
		c.queue_free()
	var title := UiKit.title("ТЯНЧИКИ", 36, Cfg.UI_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_box.add_child(title)
	var sub := UiKit.title("BATTLE TANKS", 12, Color(Cfg.UI_MUTED, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_box.add_child(sub)
	var rule := ColorRect.new()
	rule.color = Color(Cfg.UI_ACCENT, 0.5)
	rule.custom_minimum_size = Vector2(0, 2)
	_title_box.add_child(rule)

func _build_hud_strip() -> void:
	_chip_rank.add_theme_font_override("font", Fonts.regular)
	_chip_rank.add_theme_font_size_override("font_size", 12)
	_chip_rank.add_theme_color_override("font_color", Cfg.UI_TEXT)
	_chip_level.add_theme_font_override("font", Fonts.regular)
	_chip_level.add_theme_font_size_override("font_size", 12)
	_chip_level.add_theme_color_override("font_color", Cfg.UI_TEXT)
	_chip_coins.add_theme_font_override("font", Fonts.bold)
	_chip_coins.add_theme_font_size_override("font_size", 12)
	_chip_coins.add_theme_color_override("font_color", Cfg.UI_GOLD)
	_chip_perks.add_theme_font_override("font", Fonts.regular)
	_chip_perks.add_theme_font_size_override("font_size", 12)
	_chip_perks.add_theme_color_override("font_color", Cfg.UI_MUTED)

func _build_mode_and_start() -> void:
	_style_button(_mode_btn, UiKit.secondary("", 14))
	_mode_btn.custom_minimum_size = Vector2(0, 42)
	if not _mode_btn.pressed.is_connected(_on_mode_pressed):
		_mode_btn.pressed.connect(_on_mode_pressed)

	_style_button(_start_btn, UiKit.primary("", 18))
	_start_btn.text = _tr("menu.start", "И Г Р А Т Ь")
	_start_btn.custom_minimum_size = Vector2(0, 50)
	if not _start_btn.pressed.is_connected(_on_start_pressed):
		_start_btn.pressed.connect(_on_start_pressed)
	refresh_mode_summary()

func _on_mode_pressed() -> void:
	_settings_panel.visible = not _settings_panel.visible
	refresh_mode_summary()
	layout()
	layout.call_deferred()

func _on_start_pressed() -> void:
	start_pressed.emit()

func _build_version_pill() -> void:
	_version_label.text = "v" + UiRoot.game_version()
	_version_label.add_theme_font_override("font", Fonts.regular)
	_version_label.add_theme_font_size_override("font_size", 9)
	_version_label.add_theme_color_override("font_color", Color(Cfg.UI_MUTED, 0.7))

func _style_button(target: Button, donor: Button) -> void:
	for prop in ["normal", "hover", "pressed", "disabled"]:
		var sb := donor.get_theme_stylebox(prop)
		if sb != null:
			target.add_theme_stylebox_override(prop, sb)
	target.add_theme_font_override("font", donor.get_theme_font("font"))
	target.add_theme_font_size_override("font_size", donor.get_theme_font_size("font_size"))
	for col in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		target.add_theme_color_override(col, donor.get_theme_color(col))
	donor.queue_free()

func refresh_mode_summary() -> void:
	var caret := "▴" if _settings_panel.visible else "▾"
	var mode_label := _option_label("mode", settings.get("mode", "ffa"))
	var type_label := _option_label("game_type", settings.get("game_type", "single"))
	_mode_btn.text = "%s · %s  %s" % [mode_label, type_label, caret]

func _option_label(key: String, value) -> String:
	var opts: Array = _settings_options().get(key, [])
	for opt in opts:
		if opt[0] == value:
			return String(opt[1])
	return String(value)

func _build_nav_grid() -> void:
	for c in _nav_grid.get_children():
		c.queue_free()
	var dest := [
		["garage", "🔧", _tr("menu.tile.garage", "Гараж")],
		["gallery", "✨", _tr("menu.gallery", "Галерея")],
		["achievements", "🏅", _tr("menu.tile.achievements", "Достижения")],
		["daily", "📅", _tr("menu.tile.daily", "Задания")],
		["stats", "📊", _tr("menu.stats", "Статистика")],
		["net", "🌐", _tr("menu.tile.net", "Сетевая игра")],
		["map_editor", "🗺", _tr("menu.tile.map_editor", "Редактор карт")],
		["settings", "⚙", _tr("menu.tile.settings", "Настройки")],
		["quick_play", "🎲", _tr("menu.tile.quick", "Быстрый бой")],
		["quit", "✖", _tr("menu.quit", "Выход")],
	]
	var tiles: Array = []
	for d in dest:
		var id: String = d[0]
		var tile := UiKit.secondary("%s\n%s" % [d[1], d[2]], 12)
		tile.custom_minimum_size = Vector2(0, 44)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.pressed.connect(func(): nav_pressed.emit(id))
		_nav_grid.add_child(tile)
		tiles.append(tile)

	var rows: Array = []
	var i := 0
	while i < tiles.size():
		var row: Array = tiles.slice(i, mini(i + _nav_grid.columns, tiles.size()))
		if row.size() > 1:
			UiKit.chain_horizontal(row, false)
		rows.append(row)
		i += _nav_grid.columns
	for col_i in _nav_grid.columns:
		var column: Array = []
		for row in rows:
			if col_i < row.size():
				column.append(row[col_i])
		UiKit.chain_vertical(column)
	if rows.size() > 0:
		var first_row: Array = rows[0]
		first_row[0].focus_neighbor_top = _start_btn.get_path()
		_start_btn.focus_neighbor_bottom = first_row[0].get_path()

func _build_tip_ticker() -> void:
	_tip_order = range(MenuTips.LIST.size())
	_tip_order.shuffle()
	_tip_idx = 0
	_show_tip(0)
	var timer := Timer.new()
	timer.wait_time = 9.0
	timer.one_shot = false
	timer.timeout.connect(_advance_tip)
	add_child(timer)
	timer.start()

func _show_tip(order_idx: int) -> void:
	if MenuTips.LIST.is_empty():
		return
	var entry: Array = MenuTips.LIST[_tip_order[order_idx]]
	_tip_label.text = "[center]" + _tr(String(entry[0]), String(entry[1])) + "[/center]"

func _advance_tip() -> void:
	if not visible:
		return
	_tip_idx += 1
	if _tip_idx >= _tip_order.size():
		_tip_idx = 0
		_tip_order.shuffle()
	var idx := _tip_idx
	var tw := create_tween()
	tw.tween_property(_tip_label, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): _show_tip(idx))
	tw.tween_property(_tip_label, "modulate:a", 1.0, 0.35)

func _settings_options() -> Dictionary:
	return {
		"game_type": [
			["single", _tr("gametype.single", "1 игрок")],
			["hotseat", _tr("gametype.hotseat", "Горячий стул")],
		],
		"mode": [
			["ffa", _tr("mode.ffa", "Каждый за себя")],
			["ctf", _tr("mode.ctf", "Захват флага")],
			["koth", _tr("mode.koth", "Царь горы")],
			["defense", _tr("mode.defense", "Оборона")],
		],
		"difficulty": [
			["easy", _tr("diff.easy", "Легко")],
			["medium", _tr("diff.medium", "Средне")],
			["hard", _tr("diff.hard", "Сложно")],
		],
		"location": [
			["auto", _tr("loc.auto", "Жребий")],
			["city", _tr("loc.city", "🏙 Город")],
			["dust", _tr("loc.dust", "🏜 Пустошь")],
			["jungle", _tr("loc.jungle", "🌴 Джунгли")],
			["frost", _tr("loc.frost", "❄ Зима")],
			["exclusion", _tr("loc.exclusion", "☢ Зона")],
			["shore", _tr("loc.shore", "🌊 Берег")],
		],
		"weather": [
			["auto", _tr("wx.auto", "Своя")],
			["clear", _tr("wx.clear", "☀ Ясно")],
			["rain", _tr("wx.rain", "🌧 Дождь")],
			["fog", _tr("wx.fog", "🌫 Туман")],
			["snow", _tr("wx.snow", "❄ Снег")],
			["storm", _tr("wx.storm", "⛈ Гроза")],
		],
		"daytime": [
			["auto", _tr("tod.auto", "Цикл")],
			["day", _tr("tod.day", "☀ День")],
			["dusk", _tr("tod.dusk", "🌆 Закат")],
			["night", _tr("tod.night", "🌙 Ночь")],
			["midnight", _tr("tod.midnight", "🌑 Полночь")],
		],
	}

const _GROUP_LABELS := {
	"game_type": "menu.gametype", "mode": "menu.mode", "difficulty": "menu.diff",
	"location": "menu.location", "weather": "menu.weather",
	"daytime": "menu.daytime",
}
const _GROUP_FALLBACKS := {
	"game_type": "Тип игры", "mode": "Режим", "difficulty": "Сложность",
	"location": "Локация", "weather": "Погода",
	"daytime": "Время суток",
}
const _GROUP_ORDER := ["game_type", "mode", "difficulty", "location", "weather", "daytime"]

func _build_settings_groups() -> void:
	for c in _settings_body.get_children():
		c.queue_free()
	var opts := _settings_options()
	for key in _GROUP_ORDER:
		_settings_body.add_child(_make_group(
			_tr(String(_GROUP_LABELS[key]), String(_GROUP_FALLBACKS[key])), key, opts[key]))
	_wire_settings_nav.call_deferred()

func _make_group(label_text: String, key: String, options: Array) -> HBoxContainer:
	var row := UiKit.hbox(10)
	var l := UiKit.label(label_text.to_upper(), 10, Cfg.UI_MUTED)
	l.custom_minimum_size = Vector2(112, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(l)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(flow)

	var group := ButtonGroup.new()
	for opt in options:
		var value = opt[0]
		var btn := UiKit.toggle(String(opt[1]))
		btn.button_group = group
		btn.button_pressed = settings[key] == value
		btn.pressed.connect(func():
			settings[key] = value
			refresh_mode_summary())
		flow.add_child(btn)
	return row

func _wire_settings_nav() -> void:
	var groups := []
	for child in _settings_body.get_children():
		if not (child is HBoxContainer):
			continue
		var flow: Control = null
		for gc in child.get_children():
			if gc is HFlowContainer:
				flow = gc
				break
		if flow == null or flow.get_child_count() == 0:
			continue
		var btns := []
		for b in flow.get_children():
			btns.append(b)
		UiKit.chain_horizontal(btns, true)
		child.set_meta("focus_row", btns[0])
		btns[0].focus_neighbor_left = _mode_btn.get_path()
		groups.append(child)
	UiKit.chain_vertical(groups)

func _settings_budget(top: float, screen_h: float) -> float:
	return maxf(screen_h - top - 32.0, 200.0)

func _panel_y(screen: Vector2, height: float, top: float) -> float:
	var centered := screen.y * 0.5 - height * 0.5 + 26.0
	return clampf(centered, top, maxf(top, screen.y - height - 16.0))

func layout() -> void:
	if _left_panel == null:
		return
	var screen := get_viewport_rect().size
	var top := 100.0 if screen.y >= 640.0 else 64.0

	var left_h: float = _left_panel.get_combined_minimum_size().y
	_left_panel.size = Vector2(LEFT_PANEL_W, left_h)
	_left_panel.position = Vector2(26, _panel_y(screen, left_h, top))

	var set_natural: float = _settings_body.get_combined_minimum_size().y
	_settings_scroll.custom_minimum_size.y = minf(set_natural, _settings_budget(top, screen.y))
	var set_h: float = _settings_panel.get_combined_minimum_size().y
	_settings_panel.size = Vector2(SETTINGS_PANEL_W, set_h)
	var set_x := 26.0 + LEFT_PANEL_W + 18.0
	if set_x + SETTINGS_PANEL_W > screen.x - 16.0:
		set_x = maxf(16.0, screen.x - SETTINGS_PANEL_W - 16.0)
	_settings_panel.position = Vector2(set_x, _panel_y(screen, set_h, top))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		layout()

func refresh_profile() -> void:
	if Engine.is_editor_hint():
		_chip_rank.text = "🎖 Рядовой"
		_chip_level.text = "Ур. 1  ·  0/100 XP"
		_chip_coins.text = "0 🪙"
		_chip_perks.text = "перков 0/0"
		return
	var need := Prof.xp_to_next_level()
	var rank := Ranks.for_level(Prof.global_level)
	_chip_rank.text = "%s %s" % [String(rank.get("icon", "")), I18n.dn(rank, "name", "rank")]
	_chip_level.text = "%s %d  ·  %d/%d XP" % [
		_tr("menu.lvl", "Ур."), Prof.global_level, Prof.global_xp, need]
	_chip_coins.text = "%d 🪙" % Prof.money
	_chip_perks.text = "%s %d/%d" % [
		_tr("menu.perks", "перков"), Prof.unlocked.size(), Perks.all().size()]

func _wire_click_sfx(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(Sfx.play_ui)
	for child in node.get_children():
		_wire_click_sfx(child)
