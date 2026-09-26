class_name MapEditor
extends Control

signal close_requested
signal battle_requested(settings: Dictionary)

const BASE_TILE_PX := 14.0

const ARCHETYPES := [
	{"id": "auto", "name": "🎲 Авто", "desc": "Под стиль биома"},
	{"id": "avenues", "name": "🏙 Кварталы", "desc": "Проспекты и арки"},
	{"id": "plaza", "name": "🏛 Площадь", "desc": "Центральный монумент"},
	{"id": "river", "name": "🌊 Река", "desc": "Долина с мостами"},
	{"id": "fortress", "name": "🏰 Цитадель", "desc": "Укреплённый центр"},
	{"id": "labyrinths", "name": "🧩 Лабиринт", "desc": "Тактические укрытия"},
	{"id": "industrial", "name": "🏭 Промзона", "desc": "Контейнеры и ангары"},
]

const MODES := [
	{"id": "ffa", "name": "💥 Каждый за себя", "desc": "Классический бой до 40 фрагов"},
	{"id": "ctf", "name": "🚩 Захват флага", "desc": "1 нейтральный флаг, цель — 5 захватов"},
	{"id": "koth", "name": "👑 Царь горы", "desc": "Удержание центральной высоты"},
	{"id": "defense", "name": "🛡 Оборона", "desc": "Защита штаба от штурма"},
]

var current_location: String = "city"
var current_mode: String = "ctf"
var current_archetype: String = "auto"
var current_level: int = 1
var current_seed: int = 12345

var level_data: Dictionary = {}
var current_map: GameMap = null

# Canvas & Preview
var _canvas: _MapCanvas = null
var _info_label: Label = null
var _title_sub: Label = null

# UI Buttons & Inputs
var _loc_btn_group: ButtonGroup = ButtonGroup.new()
var _mode_btn_group: ButtonGroup = ButtonGroup.new()
var _arch_btn_group: ButtonGroup = ButtonGroup.new()
var _level_btn_group: ButtonGroup = ButtonGroup.new()

var _loc_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _arch_buttons: Dictionary = {}
var _level_buttons: Array[Button] = []

var _seed_input: LineEdit = null

# Stats
var _stat_size: Label = null
var _stat_walkable: Label = null
var _stat_buildings: Label = null
var _stat_bridges: Label = null
var _stat_roads: Label = null
var _stat_flags: Label = null

# Actions
var _btn_gen: Button = null
var _btn_battle: Button = null
var _btn_close: Button = null

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	if level_data.is_empty():
		randomize_seed()
		generate_map()

func open_with_settings(settings: Dictionary) -> void:
	var loc = String(settings.get("location", "city"))
	if loc == "auto" or not Locations.LIST.has(loc):
		loc = "city"
	current_location = loc

	var m = String(settings.get("mode", "ctf"))
	if m != "":
		current_mode = m

	var arch = String(settings.get("archetype", "auto"))
	current_archetype = arch

	var lvl = int(settings.get("level", 1))
	current_level = clampi(lvl if lvl > 0 else 1, 1, 5)

	if int(settings.get("seed", -1)) >= 0:
		current_seed = int(settings["seed"])
	else:
		randomize_seed()

	_sync_ui_state()
	generate_map()
	if _canvas != null:
		_canvas.reset_view.call_deferred()

func randomize_seed() -> void:
	current_seed = randi() & 0x7FFFFFFF
	if _seed_input != null:
		_seed_input.text = str(current_seed)

func generate_map() -> void:
	level_data = LevelGen.generate(current_level, current_mode, current_seed,
		current_location, current_archetype)
	current_map = level_data.get("map", null)
	_update_stats()
	_update_header()
	if _canvas != null:
		_canvas.current_map = current_map
		_canvas.level_data = level_data
		_canvas.queue_redraw()

func _update_header() -> void:
	if _title_sub == null:
		return
	var loc_info = Locations.get_location(current_location)
	var loc_name: String = loc_info.get("name", current_location)
	var mode_name := current_mode.to_upper()
	for m in MODES:
		if m["id"] == current_mode:
			mode_name = m["name"]
			break
	var arch_name := current_archetype
	for a in ARCHETYPES:
		if a["id"] == current_archetype:
			arch_name = a["name"]
			break
	_title_sub.text = "%s · %s · %s (Сид: %d)" % [loc_name, mode_name, arch_name, current_seed]

func _update_stats() -> void:
	if current_map == null:
		return
	var total_tiles := current_map.cols * current_map.rows
	var drivable := 0
	var buildings := 0
	var bridges := 0
	var roads := 0

	for r in current_map.rows:
		for c in current_map.cols:
			var t := current_map.get_tile(r, c)
			if GameMap.is_drivable_tile(t):
				drivable += 1
			if t == Cfg.T_WALL or t == Cfg.T_BRICK or t == Cfg.T_ADOBE:
				buildings += 1
			elif t == Cfg.T_BRIDGE:
				bridges += 1
			elif t == Cfg.T_ROAD:
				roads += 1

	var walk_pct := float(drivable) / float(maxi(1, total_tiles)) * 100.0
	var spots_cnt: int = level_data.get("flag_spots", {}).get("spots", []).size()
	if spots_cnt == 0:
		spots_cnt = level_data.get("flag_spots", {}).get("neutral", []).size()

	if _stat_size != null:
		_stat_size.text = "%d × %d клеток" % [current_map.cols, current_map.rows]
	if _stat_walkable != null:
		_stat_walkable.text = "%.1f%% (Связно 100%%)" % walk_pct
	if _stat_buildings != null:
		_stat_buildings.text = "%d клеток" % buildings
	if _stat_bridges != null:
		_stat_bridges.text = "%d переправ" % bridges
	if _stat_roads != null:
		_stat_roads.text = "%d (%d%% асфальт)" % [roads, int(float(roads) / float(maxi(1, drivable)) * 100.0)]
	if _stat_flags != null:
		if current_mode == "ctf":
			_stat_flags.text = "%d точек (по 1 флагу)" % spots_cnt
		elif current_mode == "koth":
			_stat_flags.text = "Центральная высота"
		elif current_mode == "defense":
			_stat_flags.text = "Штаб базы"
		else:
			_stat_flags.text = "Свободные спавны"

func _sync_ui_state() -> void:
	if _loc_buttons.has(current_location):
		_loc_buttons[current_location].button_pressed = true
	if _mode_buttons.has(current_mode):
		_mode_buttons[current_mode].button_pressed = true
	if _arch_buttons.has(current_archetype):
		_arch_buttons[current_archetype].button_pressed = true
	for i in _level_buttons.size():
		if i + 1 == current_level:
			_level_buttons[i].button_pressed = true
	if _seed_input != null:
		_seed_input.text = str(current_seed)

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# Dark Dimmer
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.04, 0.05, 0.05, 0.94)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)

	# Main Margin Layout
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(hbox)

	# Left Column: Map Canvas + Toolbar
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 8)
	hbox.add_child(left_col)

	_build_canvas_toolbar(left_col)
	_build_canvas_area(left_col)
	_build_canvas_footer(left_col)

	# Right Column: Themed Control Panel
	_build_control_panel(hbox)

func _build_canvas_toolbar(parent: Control) -> void:
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	parent.add_child(top_bar)

	var title_lbl := UiKit.title("ПРЕДПРОСМОТР КАРТЫ", 18, Cfg.UI_TEXT)
	top_bar.add_child(title_lbl)

	_title_sub = UiKit.label("", 11, Cfg.UI_MUTED)
	_title_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_sub.clip_text = true
	_title_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_bar.add_child(_title_sub)

	# Zoom controls
	var btn_zoom_out := UiKit.small(" ➖ ")
	btn_zoom_out.tooltip_text = "Уменьшить масштаб (Колёсико мыши вниз)"
	btn_zoom_out.pressed.connect(func(): if _canvas: _canvas.zoom_by(0.8))
	top_bar.add_child(btn_zoom_out)

	var btn_zoom_in := UiKit.small(" ➕ ")
	btn_zoom_in.tooltip_text = "Увеличить масштаб (Колёсико мыши вверх)"
	btn_zoom_in.pressed.connect(func(): if _canvas: _canvas.zoom_by(1.25))
	top_bar.add_child(btn_zoom_in)

	var btn_reset := UiKit.small(" ⛶ Центр ")
	btn_reset.tooltip_text = "Сбросить масштаб и отцентрировать карту"
	btn_reset.pressed.connect(func(): if _canvas: _canvas.reset_view())
	top_bar.add_child(btn_reset)

	var btn_tex := UiKit.small(" 🎨 Текстуры ")
	btn_tex.tooltip_text = "Переключить отображение текстур биома или схемы"
	btn_tex.pressed.connect(func():
		if _canvas:
			_canvas.show_textures = not _canvas.show_textures
			btn_tex.text = " 🎨 Текстуры " if _canvas.show_textures else " 📐 Схема "
			_canvas.queue_redraw()
	)
	top_bar.add_child(btn_tex)

func _build_canvas_area(parent: Control) -> void:
	var canvas_frame := PanelContainer.new()
	canvas_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_frame.add_theme_stylebox_override("panel",
		UiKit.flat(Color("#090b0c"), Cfg.RADIUS_MD, 2, Cfg.UI_BORDER))
	parent.add_child(canvas_frame)

	_canvas = _MapCanvas.new()
	_canvas.editor = self
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	canvas_frame.add_child(_canvas)

func _build_canvas_footer(parent: Control) -> void:
	var bot_bar := HBoxContainer.new()
	bot_bar.add_theme_constant_override("separation", 8)
	parent.add_child(bot_bar)

	_info_label = UiKit.label("Клетка: - | Тайл: -", 11, Cfg.UI_TEXT, true)
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.clip_text = true
	_info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bot_bar.add_child(_info_label)

	var hint := UiKit.label("🖱 Панорама: зажать ЛКМ · ⚙ Зум: колёсико · ⌨ Пробел: случайный сид", 11, Cfg.UI_MUTED)
	hint.clip_text = true
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bot_bar.add_child(hint)

func _build_control_panel(parent: Control) -> void:
	var panel := ThemedPanel.new()
	panel.custom_minimum_size = Vector2(350, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.seed_value = randi()
	# Override default ThemedPanel padding for a tighter, cleaner fit
	panel.add_theme_constant_override("margin_left", 14)
	panel.add_theme_constant_override("margin_right", 14)
	panel.add_theme_constant_override("margin_top", 12)
	panel.add_theme_constant_override("margin_bottom", 12)
	parent.add_child(panel)

	# Outer vertical layout holding: Fixed Header, Scrollable Options, Fixed Action Footer
	var panel_vbox := VBoxContainer.new()
	panel_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_vbox.add_theme_constant_override("separation", 8)
	panel.add_child(panel_vbox)

	# --- Pinned Header ---
	var hdr := UiKit.vbox(1)
	var t := UiKit.title("РЕДАКТОР КАРТ", 18, Cfg.UI_TEXT)
	hdr.add_child(t)
	var sub := UiKit.label("Генератор разнообразных тактических карт", 10, Cfg.UI_MUTED)
	hdr.add_child(sub)
	panel_vbox.add_child(hdr)

	panel_vbox.add_child(_make_divider())

	# --- Scrollable Middle Content ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_vbox.add_child(scroll)

	var vcol := VBoxContainer.new()
	vcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vcol.add_theme_constant_override("separation", 9)
	scroll.add_child(vcol)

	# Section 1: Biomes
	vcol.add_child(UiKit.label("ЛОКАЦИЯ И БИОМ", 11, Cfg.UI_ACCENT, true))
	var loc_grid := GridContainer.new()
	loc_grid.columns = 2
	loc_grid.add_theme_constant_override("h_separation", 5)
	loc_grid.add_theme_constant_override("v_separation", 5)
	vcol.add_child(loc_grid)

	_loc_buttons.clear()
	for loc_id in Locations.ORDER:
		var loc_info: Dictionary = Locations.get_location(loc_id)
		var loc_name: String = loc_info.get("name", loc_id)
		var loc_icon: String = loc_info.get("icon", "📍")
		var b := UiKit.toggle("%s %s" % [loc_icon, loc_name], 11)
		b.clip_text = true
		b.button_group = _loc_btn_group
		b.button_pressed = (loc_id == current_location)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			current_location = loc_id
			generate_map())
		loc_grid.add_child(b)
		_loc_buttons[loc_id] = b

	vcol.add_child(_make_divider())

	# Section 2: Mode
	vcol.add_child(UiKit.label("РЕЖИМ БОЯ", 11, Cfg.UI_ACCENT, true))
	var mode_grid := GridContainer.new()
	mode_grid.columns = 2
	mode_grid.add_theme_constant_override("h_separation", 5)
	mode_grid.add_theme_constant_override("v_separation", 5)
	vcol.add_child(mode_grid)

	_mode_buttons.clear()
	for m in MODES:
		var b := UiKit.toggle(m["name"], 11)
		b.clip_text = true
		b.tooltip_text = m["desc"]
		b.button_group = _mode_btn_group
		b.button_pressed = (m["id"] == current_mode)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mode_id: String = m["id"]
		b.pressed.connect(func():
			current_mode = mode_id
			generate_map()
			if _canvas: _canvas.reset_view.call_deferred())
		mode_grid.add_child(b)
		_mode_buttons[mode_id] = b

	vcol.add_child(_make_divider())

	# Section 3: Architectural Archetype
	vcol.add_child(UiKit.label("АРХИТЕКТУРА И СТИЛЬ КАРТЫ", 11, Cfg.UI_ACCENT, true))
	var arch_grid := GridContainer.new()
	arch_grid.columns = 2
	arch_grid.add_theme_constant_override("h_separation", 5)
	arch_grid.add_theme_constant_override("v_separation", 5)
	vcol.add_child(arch_grid)

	_arch_buttons.clear()
	for a in ARCHETYPES:
		var b := UiKit.toggle(a["name"], 11)
		b.clip_text = true
		b.tooltip_text = a["desc"]
		b.button_group = _arch_btn_group
		b.button_pressed = (a["id"] == current_archetype)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var arch_id: String = a["id"]
		b.pressed.connect(func():
			current_archetype = arch_id
			generate_map())
		arch_grid.add_child(b)
		_arch_buttons[arch_id] = b

	vcol.add_child(_make_divider())

	# Section 4: Seed & Level
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	vcol.add_child(seed_row)

	var seed_col := VBoxContainer.new()
	seed_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_col.add_child(UiKit.label("СИД (SEED)", 10, Cfg.UI_MUTED, true))

	var seed_input_row := HBoxContainer.new()
	seed_input_row.add_theme_constant_override("separation", 4)
	seed_col.add_child(seed_input_row)

	_seed_input = LineEdit.new()
	_seed_input.text = str(current_seed)
	_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_input.add_theme_font_override("font", Fonts.regular)
	_seed_input.add_theme_font_size_override("font_size", 11)
	_seed_input.text_submitted.connect(func(text: String):
		if text.is_valid_int():
			current_seed = text.to_int()
			generate_map())
	seed_input_row.add_child(_seed_input)

	var btn_dice := UiKit.small("🎲")
	btn_dice.tooltip_text = "Случайный сид"
	btn_dice.pressed.connect(func():
		randomize_seed()
		generate_map())
	seed_input_row.add_child(btn_dice)
	seed_row.add_child(seed_col)

	# Level (1-5)
	var lvl_col := VBoxContainer.new()
	lvl_col.add_child(UiKit.label("УРОВЕНЬ", 10, Cfg.UI_MUTED, true))
	var lvl_row := HBoxContainer.new()
	lvl_row.add_theme_constant_override("separation", 3)
	lvl_col.add_child(lvl_row)

	_level_buttons.clear()
	for l in range(1, 6):
		var lb := UiKit.toggle(str(l), 11)
		lb.custom_minimum_size = Vector2(26, 26)
		lb.button_group = _level_btn_group
		lb.button_pressed = (l == current_level)
		lb.pressed.connect(func():
			current_level = l
			generate_map())
		lvl_row.add_child(lb)
		_level_buttons.append(lb)
	seed_row.add_child(lvl_col)

	vcol.add_child(_make_divider())

	# Section 5: Stats Card
	vcol.add_child(UiKit.label("ТАКТИЧЕСКИЙ АНАЛИЗ КАРТЫ", 11, Cfg.UI_GOLD, true))
	var stats_card := PanelContainer.new()
	stats_card.add_theme_stylebox_override("panel", UiKit.card_style())
	vcol.add_child(stats_card)

	var sgrid := GridContainer.new()
	sgrid.columns = 2
	sgrid.add_theme_constant_override("h_separation", 10)
	sgrid.add_theme_constant_override("v_separation", 4)
	stats_card.add_child(sgrid)

	_stat_size = _add_stat_row(sgrid, "📐 Размеры:", "-")
	_stat_walkable = _add_stat_row(sgrid, "🚶 Проходимость:", "-")
	_stat_buildings = _add_stat_row(sgrid, "🏢 Зданий/стен:", "-")
	_stat_bridges = _add_stat_row(sgrid, "🌉 Переправ:", "-")
	_stat_roads = _add_stat_row(sgrid, "🛣 Дорог:", "-")
	_stat_flags = _add_stat_row(sgrid, "🎯 Точек целей:", "-")

	# --- Pinned Footer Action Bar (Always Visible!) ---
	var footer_box := UiKit.vbox(6)
	panel_vbox.add_child(footer_box)

	footer_box.add_child(_make_divider())

	_btn_battle = UiKit.primary("⚔ В БОЙ НА ЭТОЙ КАРТЕ!", 14)
	_btn_battle.custom_minimum_size = Vector2(0, 40)
	_btn_battle.pressed.connect(_on_battle_pressed)
	footer_box.add_child(_btn_battle)

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 6)
	footer_box.add_child(act_row)

	_btn_gen = UiKit.secondary("🎲 Случайно (Space)", 11)
	_btn_gen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_gen.custom_minimum_size = Vector2(0, 32)
	_btn_gen.pressed.connect(func():
		randomize_seed()
		generate_map())
	act_row.add_child(_btn_gen)

	_btn_close = UiKit.secondary("✖ В меню (Esc)", 11)
	_btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_close.custom_minimum_size = Vector2(0, 32)
	_btn_close.pressed.connect(func(): close_requested.emit())
	act_row.add_child(_btn_close)

func _add_stat_row(parent: Control, title: String, def_val: String) -> Label:
	var l_title := UiKit.label(title, 10, Cfg.UI_MUTED)
	parent.add_child(l_title)
	var l_val := UiKit.label(def_val, 10, Color.WHITE, true)
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_val.clip_text = true
	parent.add_child(l_val)
	return l_val

func _make_divider() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(Cfg.UI_BORDER, 0.4)
	rect.custom_minimum_size = Vector2(0, 1)
	return rect

func _on_battle_pressed() -> void:
	var match_settings := {
		"location": current_location,
		"mode": current_mode,
		"archetype": current_archetype,
		"level": current_level,
		"seed": current_seed,
	}
	battle_requested.emit(match_settings)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_requested.emit()
			get_viewport().set_input_as_handled()
		elif (event.keycode == KEY_SPACE or event.keycode == KEY_R) and not (_seed_input != null and _seed_input.has_focus()):
			randomize_seed()
			generate_map()
			get_viewport().set_input_as_handled()
		elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not (_seed_input != null and _seed_input.has_focus()):
			_on_battle_pressed()
			get_viewport().set_input_as_handled()

func set_hover_info(r: int, c: int) -> void:
	if _info_label == null:
		return
	if current_map == null or not current_map.in_bounds(r, c):
		_info_label.text = "Клетка: - | Тайл: -"
		return
	var t := current_map.get_tile(r, c)
	var tile_name := "Пустота"
	var passable := GameMap.is_drivable_tile(t)
	match t:
		Cfg.T_WALL: tile_name = "Бетонная стена (непробиваемо)"
		Cfg.T_BRICK: tile_name = "Кирпичная стена (разрушаемо)"
		Cfg.T_ADOBE: tile_name = "Глинобитная стена"
		Cfg.T_WATER: tile_name = "Водная преграда"
		Cfg.T_BRIDGE: tile_name = "Мост / переправа"
		Cfg.T_ROAD: tile_name = "Асфальт / шоссе"
		Cfg.T_SAND: tile_name = "Песчаный грунт"
		Cfg.T_DUNE: tile_name = "Бархан"
		Cfg.T_QUICKSAND: tile_name = "Зыбучий песок"
		Cfg.T_GRASS: tile_name = "Трава / газон"
		Cfg.T_TREE: tile_name = "Лесной массив"
		Cfg.T_BASE_P: tile_name = "База синих (Игрок)"
		Cfg.T_BASE_E: tile_name = "База красных (Враг)"

	_info_label.text = "Клетка: (%d, %d) | %s | %s" % [
		c, r, tile_name,
		"🟢 Проходимо" if passable else "🔴 Препятствие"
	]


# Inner Class for Interactive Map Rendering
class _MapCanvas extends Control:
	var editor: MapEditor = null
	var current_map: GameMap = null
	var level_data: Dictionary = {}

	var zoom: float = 1.0
	var pan_offset: Vector2 = Vector2.ZERO
	var _dragging: bool = false
	var _drag_start: Vector2 = Vector2.ZERO
	var _hover_cell: Vector2i = Vector2i(-1, -1)
	var show_textures: bool = true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		resized.connect(queue_redraw)

	func reset_view() -> void:
		if current_map == null or size.x <= 0 or size.y <= 0:
			return
		var map_w: float = current_map.cols * MapEditor.BASE_TILE_PX
		var map_h: float = current_map.rows * MapEditor.BASE_TILE_PX
		var fit_x := (size.x - 30.0) / map_w
		var fit_y := (size.y - 30.0) / map_h
		zoom = clampf(minf(fit_x, fit_y), 0.35, 2.5)
		pan_offset = (size - Vector2(map_w, map_h) * zoom) * 0.5
		queue_redraw()

	func zoom_by(factor: float) -> void:
		_zoom_at(size * 0.5, factor)

	func _zoom_at(center: Vector2, factor: float) -> void:
		var old_zoom := zoom
		zoom = clampf(zoom * factor, 0.25, 3.5)
		var actual_factor := zoom / old_zoom
		pan_offset = center - (center - pan_offset) * actual_factor
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_zoom_at(event.position, 1.15)
				accept_event()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_zoom_at(event.position, 1.0 / 1.15)
				accept_event()
			elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_dragging = true
					_drag_start = event.position
				else:
					_dragging = false
				accept_event()
		elif event is InputEventMouseMotion:
			if _dragging:
				pan_offset += event.relative
				queue_redraw()
			_update_hover(event.position)

	func _update_hover(m_pos: Vector2) -> void:
		if current_map == null:
			return
		var tile_sz := MapEditor.BASE_TILE_PX * zoom
		var local := m_pos - pan_offset
		var c := int(floor(local.x / tile_sz))
		var r := int(floor(local.y / tile_sz))
		if current_map.in_bounds(r, c):
			if _hover_cell != Vector2i(c, r):
				_hover_cell = Vector2i(c, r)
				if editor != null:
					editor.set_hover_info(r, c)
				queue_redraw()
		else:
			if _hover_cell != Vector2i(-1, -1):
				_hover_cell = Vector2i(-1, -1)
				if editor != null:
					editor.set_hover_info(-1, -1)
				queue_redraw()

	func _draw() -> void:
		# Canvas background
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0a0c0e"))

		if current_map == null:
			draw_string(Fonts.bold, size * 0.5 - Vector2(100, 0), "Карта не сгенерирована",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Cfg.UI_MUTED)
			return

		var loc_id: String = editor.current_location if editor != null else Locations.CITY
		var use_textures: bool = show_textures and TerrainTextures.has_textures(loc_id)
		var loc_info: Dictionary = Locations.get_location(loc_id)
		var ground_col: Color = Color(loc_info.get("ground", "#3a3a2a"))
		var ground_alt: Color = Color(loc_info.get("ground_alt", "#37372a"))

		var tile_sz := MapEditor.BASE_TILE_PX * zoom
		var map_w := float(current_map.cols) * tile_sz
		var map_h := float(current_map.rows) * tile_sz

		# Map Ground Background & Shadow
		draw_rect(Rect2(pan_offset + Vector2(4, 6), Vector2(map_w, map_h)), Color(0, 0, 0, 0.45))
		if not use_textures:
			draw_rect(Rect2(pan_offset, Vector2(map_w, map_h)), ground_col)

		# Visible bounds check (frustum culling)
		var r_min := maxi(0, int(floor((-pan_offset.y) / tile_sz)))
		var r_max := mini(current_map.rows - 1, int(ceil((size.y - pan_offset.y) / tile_sz)))
		var c_min := maxi(0, int(floor((-pan_offset.x) / tile_sz)))
		var c_max := mini(current_map.cols - 1, int(ceil((size.x - pan_offset.x) / tile_sz)))

		# 1. Ground Checkerboard & Natural Variations or Ground Textures
		var grass_tex: Texture2D = TerrainTextures.grass(loc_id) if use_textures else null
		for r in range(r_min, r_max + 1):
			for c in range(c_min, c_max + 1):
				var p := pan_offset + Vector2(c, r) * tile_sz
				var rect := Rect2(p, Vector2(tile_sz, tile_sz))
				if grass_tex != null:
					draw_texture_rect(grass_tex, rect, false)
				elif (r + c) % 2 == 1:
					draw_rect(rect, ground_alt)

		# 2. Tiles Layer
		for r in range(r_min, r_max + 1):
			for c in range(c_min, c_max + 1):
				var t := current_map.get_tile(r, c)
				var p := pan_offset + Vector2(c, r) * tile_sz
				var rect := Rect2(p, Vector2(tile_sz, tile_sz))

				match t:
					Cfg.T_ROAD:
						if use_textures:
							var up := _is_paved(r - 1, c)
							var down := _is_paved(r + 1, c)
							var left := _is_paved(r, c - 1)
							var right := _is_paved(r, c + 1)
							var idx := _road_index(r, c, up, down, left, right)
							var rtex := TerrainTextures.road(idx, loc_id)
							if rtex != null:
								draw_texture_rect(rtex, rect, false)
							else:
								_draw_road(rect, loc_id)
						else:
							_draw_road(rect, loc_id)
					Cfg.T_WATER:
						if use_textures:
							var up := _is_not_water(r - 1, c)
							var down := _is_not_water(r + 1, c)
							var left := _is_not_water(r, c - 1)
							var right := _is_not_water(r, c + 1)
							var idx := _river_index(up, down, left, right)
							var wtex := TerrainTextures.river(idx, loc_id)
							if wtex != null:
								draw_texture_rect(wtex, rect, false)
							else:
								_draw_water(rect)
						else:
							_draw_water(rect)
					Cfg.T_BRIDGE:
						if use_textures:
							var horiz := _is_paved(r, c - 1) or _is_paved(r, c + 1)
							var btex := TerrainTextures.bridge(horiz, loc_id)
							if btex != null:
								draw_texture_rect(btex, rect, false)
							else:
								_draw_bridge(rect)
						else:
							_draw_bridge(rect)
					Cfg.T_SAND, Cfg.T_DUNE:
						draw_rect(rect, Color("#c9b878"))
					Cfg.T_QUICKSAND:
						draw_rect(rect, Color("#7d6a45"))
					Cfg.T_GRASS:
						if use_textures:
							if grass_tex != null:
								draw_texture_rect(grass_tex, rect, false)
							if (r * 74351 + c * 5911) % 7 == 0:
								var bs := tile_sz * 0.65
								var b_rect := Rect2(rect.position + Vector2((tile_sz - bs) * 0.5, (tile_sz - bs) * 0.5), Vector2(bs, bs))
								var btex := TerrainTextures.bush(loc_id)
								if btex != null:
									draw_texture_rect(btex, b_rect, false)
						else:
							draw_rect(rect, Color("#3d5c33"))
					Cfg.T_WALL:
						_draw_wall(rect)
					Cfg.T_BRICK, Cfg.T_ADOBE:
						if use_textures:
							var variant := Materials.variant_at(r, c)
							var bldg := TerrainTextures.building(variant == 3, loc_id)
							if bldg != null:
								draw_texture_rect(bldg, rect, false)
							else:
								_draw_brick(rect)
						else:
							_draw_brick(rect)
					Cfg.T_TREE:
						if use_textures:
							if grass_tex != null:
								draw_texture_rect(grass_tex, rect, false)
							var ttex := TerrainTextures.tree(loc_id)
							if ttex != null:
								draw_texture_rect(ttex, rect, false)
							else:
								_draw_tree(rect)
						else:
							_draw_tree(rect)
					Cfg.T_BASE_P:
						_draw_base(rect, Color("#3498db"), "P")
					Cfg.T_BASE_E:
						_draw_base(rect, Color("#e74c3c"), "E")

		# 3. Map Outer Border
		draw_rect(Rect2(pan_offset, Vector2(map_w, map_h)), Color(Cfg.UI_ACCENT, 0.45), false, 1.5)

		# 4. Tactical Overlays (Bases, Flag spots, Hill)
		_draw_tactical_overlays(tile_sz)

		# 5. Hover Cell Indicator
		if _hover_cell != Vector2i(-1, -1) and current_map.in_bounds(_hover_cell.y, _hover_cell.x):
			var hp := pan_offset + Vector2(_hover_cell.x, _hover_cell.y) * tile_sz
			draw_rect(Rect2(hp, Vector2(tile_sz, tile_sz)), Color(1.0, 1.0, 1.0, 0.8), false, 2.0)

	func _is_paved(r: int, c: int) -> bool:
		if current_map == null or not current_map.in_bounds(r, c):
			return false
		var t := current_map.get_tile(r, c)
		return t == Cfg.T_ROAD or t == Cfg.T_BRIDGE

	func _is_not_water(r: int, c: int) -> bool:
		if current_map == null or not current_map.in_bounds(r, c):
			return false
		return current_map.get_tile(r, c) != Cfg.T_WATER

	func _road_index(r: int, c: int, up: bool, down: bool, left: bool, right: bool) -> int:
		var n := (1 if up else 0) + (1 if down else 0) + (1 if left else 0) + (1 if right else 0)
		if n >= 3:
			if up and down and left and right:
				return 7
			if up and down and left:
				return 10
			if up and down and right:
				return 11
			if left and right and up:
				return 8
			if left and right and down:
				return 9
		if n == 2:
			if left and right:
				return 1
			if up and down:
				return 2
			if up and left:
				return 14
			if up and right:
				return 15
			if down and left:
				return 12
			if down and right:
				return 13
		if up or down:
			return 2
		if left or right:
			return 1
		return 1

	func _river_index(up: bool, down: bool, left: bool, right: bool) -> int:
		if not up and not down and not left and not right:
			return 3
		if up and not down and not left and not right:
			return 4
		if down and not up and not left and not right:
			return 7
		if left and not up and not down and not right:
			return 5
		if right and not up and not down and not left:
			return 6
		if up and left and not down and not right:
			return 8
		if up and right and not down and not left:
			return 9
		if down and left and not up and not right:
			return 10
		if down and right and not up and not left:
			return 11
		if up and down and not left and not right:
			return 1
		if left and right and not up and not down:
			return 2
		return 3

	func _draw_road(rect: Rect2, loc_id: String) -> void:
		var road_color := Color("#2c2d30")
		if loc_id == Locations.DUST:
			road_color = Color("#594833")
		elif loc_id == Locations.JUNGLE:
			road_color = Color("#4a523a")
		draw_rect(rect, road_color)
		if rect.size.x >= 8.0:
			draw_rect(rect, Color(1, 1, 1, 0.08), false, 1.0)

	func _draw_water(rect: Rect2) -> void:
		draw_rect(rect, Color("#225588"))
		if rect.size.x >= 6.0:
			# Water ripple line
			var y_mid := rect.position.y + rect.size.y * 0.5
			draw_line(Vector2(rect.position.x + 2, y_mid),
				Vector2(rect.position.x + rect.size.x - 2, y_mid),
				Color("#3f88c5", 0.5), 1.0)

	func _draw_bridge(rect: Rect2) -> void:
		draw_rect(rect, Color("#7a5a3a"))
		if rect.size.x >= 6.0:
			# Planks
			draw_line(Vector2(rect.position.x, rect.position.y),
				Vector2(rect.position.x + rect.size.x, rect.position.y), Color("#4a3725"), 1.0)
			draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y),
				Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), Color("#4a3725"), 1.0)

	func _draw_wall(rect: Rect2) -> void:
		draw_rect(rect, Color("#555a60"))
		# 3D bevel
		if rect.size.x >= 4.0:
			draw_line(rect.position, Vector2(rect.position.x + rect.size.x, rect.position.y), Color("#888f98"), 1.0)
			draw_line(rect.position, Vector2(rect.position.x, rect.position.y + rect.size.y), Color("#888f98"), 1.0)
			draw_line(Vector2(rect.position.x + rect.size.x, rect.position.y),
				Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), Color("#303337"), 1.0)
			draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y),
				Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), Color("#303337"), 1.0)

	func _draw_brick(rect: Rect2) -> void:
		draw_rect(rect, Color("#9e4a3b"))
		if rect.size.x >= 6.0:
			# Mortar lines
			var mid_y := rect.position.y + rect.size.y * 0.5
			draw_line(Vector2(rect.position.x, mid_y),
				Vector2(rect.position.x + rect.size.x, mid_y), Color("#6d3226"), 1.0)

	func _draw_tree(rect: Rect2) -> void:
		var center := rect.position + rect.size * 0.5
		var radius := rect.size.x * 0.45
		draw_circle(center + Vector2(1, 1), radius, Color(0, 0, 0, 0.3))
		draw_circle(center, radius, Color("#2d6a35"))
		if radius >= 4.0:
			draw_circle(center - Vector2(1, 1), radius * 0.4, Color("#428c4c"))

	func _draw_base(rect: Rect2, col: Color, label: String) -> void:
		draw_rect(rect, col)
		draw_rect(rect, Color.WHITE, false, 1.5)
		if rect.size.x >= 10.0:
			draw_string(Fonts.bold, rect.position + Vector2(rect.size.x * 0.25, rect.size.y * 0.75),
				label, HORIZONTAL_ALIGNMENT_CENTER, -1, int(rect.size.y * 0.6), Color.WHITE)

	func _draw_tactical_overlays(tile_sz: float) -> void:
		if level_data.is_empty():
			return

		var homes: Dictionary = level_data.get("homes", {})
		var flag_spots: Dictionary = level_data.get("flag_spots", {})

		# Home Bases Glow & Ring
		for team in ["player", "enemy"]:
			if homes.has(team):
				var hp: Vector2 = homes[team]
				var world_to_map := Vector2(hp.x / float(Cfg.TILE), hp.y / float(Cfg.TILE))
				var p := pan_offset + world_to_map * tile_sz
				var col: Color = Color("#3498db") if team == "player" else Color("#e74c3c")
				draw_circle(p, tile_sz * 1.2, Color(col.r, col.g, col.b, 0.25))
				draw_arc(p, tile_sz * 1.2, 0.0, TAU, 24, col, 2.0)
				var tag := "🛡 БАЗА [СИНИЕ]" if team == "player" else "💀 БАЗА [КРАСНЫЕ]"
				draw_string(Fonts.bold, p + Vector2(-30, -tile_sz * 1.4), tag,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 10, col)

		# CTF Neutral Flag Spot Candidates (Sequential single flag spawn points!)
		var spots: Array = flag_spots.get("spots", [])
		if spots.is_empty():
			spots = flag_spots.get("neutral", [])

		for i in spots.size():
			var sp: Vector2 = spots[i]
			var map_pos := Vector2(sp.x / float(Cfg.TILE), sp.y / float(Cfg.TILE))
			var p := pan_offset + map_pos * tile_sz
			var gold := Color("#ffd700")

			if i == 0:
				# Initial flag spawn: Radiant beacon
				draw_circle(p, tile_sz * 1.5, Color(1.0, 0.84, 0.0, 0.35))
				draw_arc(p, tile_sz * 1.5, 0.0, TAU, 24, gold, 2.5)
				draw_circle(p, tile_sz * 0.45, gold)
				draw_string(Fonts.bold, p + Vector2(-32, -tile_sz * 1.7), "🚩 1-й ФЛАГ",
					HORIZONTAL_ALIGNMENT_CENTER, -1, 11, gold)
			else:
				# Next sequential flag spawn spots
				draw_arc(p, tile_sz * 0.9, 0.0, TAU, 16, Color(gold, 0.75), 1.5)
				draw_circle(p, tile_sz * 0.25, Color(gold, 0.9))
				if tile_sz >= 8.0:
					draw_string(Fonts.bold, p + Vector2(-4, 3), "#%d" % (i + 1),
						HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)

		# KotH Hill
		if editor != null and editor.current_mode == "koth":
			var mid_c := current_map.cols / 2
			var mid_r := current_map.rows / 2
			var hill_sz := 8
			var hp := pan_offset + Vector2(mid_c - hill_sz / 2, mid_r - hill_sz / 2) * tile_sz
			var h_rect := Rect2(hp, Vector2(hill_sz, hill_sz) * tile_sz)
			draw_rect(h_rect, Color(1.0, 0.7, 0.0, 0.2))
			draw_rect(h_rect, Color("#ffaa00"), false, 2.0)
			draw_string(Fonts.bold, h_rect.position + Vector2(h_rect.size.x * 0.5 - 35, h_rect.size.y * 0.5 + 4),
				"👑 ГОРА", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color("#ffdd44"))
