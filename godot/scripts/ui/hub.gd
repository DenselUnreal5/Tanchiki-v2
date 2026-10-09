@tool
class_name Hub
extends Control

signal close_requested
signal garage_changed

const HUB_HEADER_H := 90.0
const _GALLERY_MAX_PER_COL := 3

const UpgradeCardScene := preload("res://scenes/ui/cards/upgrade_card.tscn")
const CosmeticCardScene := preload("res://scenes/ui/cards/cosmetic_card.tscn")
const CannonCardScene := preload("res://scenes/ui/cards/cannon_card.tscn")
const AchievementCardScene := preload("res://scenes/ui/cards/achievement_card.tscn")
const GalleryDetailScene := preload("res://scenes/ui/cards/gallery_detail.tscn")

var active_tab: String = "gallery"

func _tr(key: String, fallback: String, params: Dictionary = {}) -> String:
	return fallback if Engine.is_editor_hint() or I18n == null else I18n.t(key, params, fallback)

var _gallery_nodes: Dictionary = {}
var _gallery_row: HBoxContainer
var _gallery_detail_panel: Control
var _gallery_selected_id := ""

var garage_submode: String = "upgrades"
var _bestiary_selected_id := "player_standard"
var _bestiary_cards: Dictionary = {}
var _bestiary_detail_container: VBoxContainer = null

var _cosmetic_preview_tank: Tank = null
var _cosmetic_preview_view: MenuTankView = null
var _cosmetic_preview_type: String = "skin"
var _cosmetic_preview_id: String = ""
var _cosmetic_title_lbl: Label = null
var _cosmetic_badge_lbl: RichTextLabel = null
var _cosmetic_desc_lbl: Label = null
var _cosmetic_feat_hull: Label = null
var _cosmetic_feat_turret: Label = null
var _cosmetic_feat_track: Label = null
var _cosmetic_status_lbl: Label = null
var _cosmetic_action_btn: Button = null
var _cosmetic_reset_btn: Button = null
var _cosmetic_catalog_scroll: ScrollContainer = null

@onready var _panel: ThemedPanel = %HubPanel
@onready var _tabs_row: HBoxContainer = %HubTabsRow
@onready var _sub: RichTextLabel = %HubSub
@onready var _scroll: ScrollContainer = %HubScroll
@onready var _body: VBoxContainer = %HubBody
@onready var _close_btn: Button = %CloseBtn

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	%Dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	%Center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel.custom_minimum_size = Vector2(900, 0)
	_panel.seed_value = randi()

	_sub.add_theme_font_override("normal_font", Fonts.regular)
	_sub.add_theme_font_override("bold_font", Fonts.bold)
	_sub.add_theme_font_size_override("normal_font_size", 11)
	_sub.add_theme_font_size_override("bold_font_size", 11)
	_sub.add_theme_color_override("default_color", Cfg.UI_MUTED)

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_style_button(_close_btn, UiKit.secondary(""))
	_close_btn.text = _tr("btn.close", "Закрыть")
	if not _close_btn.pressed.is_connected(_on_close_pressed):
		_close_btn.pressed.connect(_on_close_pressed)
	set_meta("close_button", _close_btn)

	_rebuild_tabs()
	if Sets != null and Sets.has_signal("last_input_device_changed"):
		if not Sets.last_input_device_changed.is_connected(_on_input_device_changed):
			Sets.last_input_device_changed.connect(_on_input_device_changed)
	if Sets != null and Sets.has_signal("ui_input_mode_changed"):
		if not Sets.ui_input_mode_changed.is_connected(_on_input_device_changed):
			Sets.ui_input_mode_changed.connect(_on_input_device_changed)
	if Engine.is_editor_hint():
		_editor_preview_body()

func _on_input_device_changed(_arg = null) -> void:
	if is_inside_tree() and visible:
		_rebuild_tabs()

func _on_close_pressed() -> void:
	close_requested.emit()

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

func _first_focusable(node: Node) -> Control:
	if node is Control and node.visible and node.focus_mode != Control.FOCUS_NONE:
		return node
	for c in node.get_children():
		var f := _first_focusable(c)
		if f != null:
			return f
	return null

func _find_by_meta(node: Node, meta_key: String, value: String) -> Control:
	if node is Control and node.has_meta(meta_key) and String(node.get_meta(meta_key)) == value:
		return node
	for c in node.get_children():
		var f := _find_by_meta(c, meta_key, value)
		if f != null:
			return f
	return null

func _find_tab_button(key: String) -> Control:
	for c in _tabs_row.get_children():
		if c.has_meta("tab_key") and String(c.get_meta("tab_key")) == key:
			return c
	return null

func _grab(ctrl) -> void:
	if is_instance_valid(ctrl):
		ctrl.grab_focus.call_deferred()

func tab_items() -> Array:
	return [
		{"key": "garage", "label": _tr("menu.garage", "Гараж")},
		{"key": "bestiary", "label": _tr("menu.bestiary", "Справочник бронетехники")},
		{"key": "cosmetics", "label": _tr("menu.cosmetics", "Косметика")},
		{"key": "gallery", "label": _tr("menu.gallery", "Боевые перки")},
		{"key": "achievements", "label": _tr("menu.achievements", "Достижения")},
	]

func _rebuild_tabs() -> void:
	var idx := _tabs_row.get_index()
	var parent := _tabs_row.get_parent()
	var new_row := UiKit.plain_tabs(tab_items(), active_tab, func(key): switch_tab(key))

	var is_pad := Sets != null and (Sets.pad_ui or Sets.last_input_pad)
	var prev_hint := "[LB] ◀" if is_pad else "[Q] ◀"
	var next_hint := "▶ [RB]" if is_pad else "▶ [E]"

	var prev_btn := Button.new()
	prev_btn.text = prev_hint
	prev_btn.flat = true
	prev_btn.focus_mode = Control.FOCUS_NONE
	prev_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	prev_btn.add_theme_font_override("font", Fonts.bold)
	prev_btn.add_theme_font_size_override("font_size", 12)
	prev_btn.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 0.75))
	prev_btn.add_theme_color_override("font_hover_color", Cfg.UI_ACCENT)
	prev_btn.tooltip_text = _tr("hint.tab_prev", "Предыдущая вкладка (Q / LB)")
	prev_btn.pressed.connect(func(): cycle_tab(-1))
	new_row.add_child(prev_btn)
	new_row.move_child(prev_btn, 0)

	var next_btn := Button.new()
	next_btn.text = next_hint
	next_btn.flat = true
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	next_btn.add_theme_font_override("font", Fonts.bold)
	next_btn.add_theme_font_size_override("font_size", 12)
	next_btn.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 0.75))
	next_btn.add_theme_color_override("font_hover_color", Cfg.UI_ACCENT)
	next_btn.tooltip_text = _tr("hint.tab_next", "Следующая вкладка (E / RB)")
	next_btn.pressed.connect(func(): cycle_tab(1))
	new_row.add_child(next_btn)

	parent.add_child(new_row)
	parent.move_child(new_row, idx)
	_tabs_row.queue_free()
	_tabs_row = new_row

	var tab_btns: Array = []
	for c in _tabs_row.get_children():
		if c.has_meta("tab_key"):
			tab_btns.append(c)
	UiKit.chain_horizontal(tab_btns, true)

func cycle_tab(direction: int) -> void:
	var items := tab_items()
	if items.is_empty():
		return
	var idx := 0
	for i in items.size():
		if String(items[i]["key"]) == active_tab:
			idx = i
			break
	idx = (idx + direction + items.size()) % items.size()
	switch_tab(String(items[idx]["key"]))

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	var is_next: bool = bool(event.is_action_pressed("tab_next")) \
		or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_SHOULDER)
	var is_prev: bool = bool(event.is_action_pressed("tab_prev")) \
		or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_LEFT_SHOULDER)
	if is_next:
		cycle_tab(1)
		get_viewport().set_input_as_handled()
	elif is_prev:
		cycle_tab(-1)
		get_viewport().set_input_as_handled()

func switch_tab(key: String, focus_id: String = "") -> void:
	if key == "encyclopedia":
		key = "bestiary"
	elif key == "perks" or key == "perk":
		key = "gallery"
	var same_tab: bool = (active_tab == key)
	var prev_scroll_v: int = _scroll.scroll_vertical if (same_tab and _scroll != null) else 0
	var prev_catalog_v: int = _cosmetic_catalog_scroll.scroll_vertical if (same_tab and _cosmetic_catalog_scroll != null and is_instance_valid(_cosmetic_catalog_scroll)) else 0

	active_tab = key
	_rebuild_tabs()
	_fill_tab(key)

	if same_tab:
		if prev_scroll_v > 0 and _scroll != null:
			_scroll.scroll_vertical = prev_scroll_v
			_scroll.set_deferred("scroll_vertical", prev_scroll_v)
		if prev_catalog_v > 0 and _cosmetic_catalog_scroll != null and is_instance_valid(_cosmetic_catalog_scroll):
			_cosmetic_catalog_scroll.scroll_vertical = prev_catalog_v
			_cosmetic_catalog_scroll.set_deferred("scroll_vertical", prev_catalog_v)

	if focus_id != "":
		var target := _find_by_meta(_body, "card_id", focus_id)
		if target != null:
			var act_btn: Control = target.get_node_or_null("%ActionBtn")
			if act_btn != null and act_btn.visible and act_btn.focus_mode != Control.FOCUS_NONE and not act_btn.disabled:
				_grab(act_btn)
			else:
				var btn := _first_focusable(target)
				_grab(btn if btn != null else target)
		else:
			_grab(_first_focusable(_body))
	else:
		_grab(_find_tab_button(key))

func _fill_tab(key: String) -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	match key:
		"garage": _fill_garage_tab()
		"bestiary": _fill_bestiary_tab()
		"cosmetics": _fill_cosmetics_tab()
		"gallery": _fill_gallery_tab()
		"achievements": _fill_achievements_tab()
	_resize_scroll()

func open_tab(key: String, focus_id: String = "") -> void:
	visible = true
	switch_tab(key, focus_id)

func open_encyclopedia(focus_id: String = "") -> void:
	open_tab("bestiary", focus_id)

func refresh_language() -> void:
	_close_btn.text = _tr("btn.close", "Закрыть")
	_rebuild_tabs()
	if visible:
		_fill_tab(active_tab)

func _body_budget() -> float:
	var screen := UiKit.virtual_screen(self)
	return maxf(minf(screen.y * 0.86, 900.0) - HUB_HEADER_H, 200.0)

func _resize_scroll() -> void:
	_scroll.custom_minimum_size.y = _body_budget()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_scroll()

func _fill_bestiary_tab() -> void:
	garage_submode = "encyclopedia"
	_fill_bestiary_view()

func _fill_bestiary_view() -> void:
	var all_entries: Array[Dictionary] = Bestiary.all()
	var unlocked_count := 0
	for entry in all_entries:
		if Prof.is_bestiary_unlocked(String(entry["id"])):
			unlocked_count += 1

	_sub.text = "[center]" + _tr("bestiary.sub",
		"База тактических данных техники · Рассекречено [b]%d[/b] из %d образцов" % [unlocked_count, all_entries.size()],
		{"unlocked": unlocked_count, "total": all_entries.size()}) + "[/center]"

	_bestiary_cards.clear()

	var row := UiKit.hbox(16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(row)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(340, _body_budget())
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	row.add_child(list_scroll)

	var list_vbox := UiKit.vbox(8)
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list_vbox)

	var categories: Array[Dictionary] = [
		{"id": "player", "title": _tr("bestiary.cat.player", "ТАНКИ ИГРОКА"), "color": Cfg.UI_ACCENT},
		{"id": "enemy", "title": _tr("bestiary.cat.enemy", "БОЕВАЯ ТЕХНИКА ПРОТИВНИКА"), "color": Color("#f59e0b")},
		{"id": "boss", "title": _tr("bestiary.cat.boss", "БОССЫ И ЭЛИТНЫЕ УГРОЗЫ"), "color": Color("#ef4444")},
	]

	var all_cards: Array = []

	for cat in categories:
		var cat_items: Array[Dictionary] = Bestiary.category_list(String(cat["id"]))
		if cat_items.is_empty():
			continue

		var header := UiKit.section(String(cat["title"]), cat["color"])
		list_vbox.add_child(header)

		for item in cat_items:
			var item_id := String(item["id"])
			var is_unlocked := Prof.is_bestiary_unlocked(item_id)
			var kills := Prof.get_bestiary_kills(item_id)
			var card_btn := _build_bestiary_item_card(item, is_unlocked, kills)
			list_vbox.add_child(card_btn)
			_bestiary_cards[item_id] = card_btn
			all_cards.append(card_btn)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.custom_minimum_size = Vector2(0, _body_budget())
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.follow_focus = true
	row.add_child(detail_scroll)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", UiKit.card_style(Cfg.UI_BORDER))
	detail_scroll.add_child(detail_panel)

	var detail_vbox := UiKit.vbox(10)
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(detail_vbox)
	_bestiary_detail_container = detail_vbox

	if _bestiary_selected_id == "" or Bestiary.get_entry(_bestiary_selected_id).is_empty():
		_bestiary_selected_id = "player_standard"

	_update_bestiary_detail(_bestiary_selected_id)
	_highlight_bestiary_card(_bestiary_selected_id)

	UiKit.chain_vertical(all_cards)
	if not all_cards.is_empty():
		var top_tab := _find_tab_button("garage")
		if top_tab != null:
			top_tab.focus_neighbor_bottom = all_cards[0].get_path()

	var back_btn := UiKit.secondary(_tr("garage.back_to_upgrades", "Вернуться к модернизации танка"), 12)
	back_btn.custom_minimum_size = Vector2(0, 38)
	back_btn.pressed.connect(func():
		garage_submode = "upgrades"
		_fill_tab("garage")
	)
	_body.add_child(back_btn)

func _build_bestiary_item_card(item: Dictionary, is_unlocked: bool, kills: int) -> Button:
	var item_id := String(item["id"])
	var card_btn := Button.new()
	card_btn.custom_minimum_size = Vector2(0, 48)
	card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_btn.focus_mode = Control.FOCUS_ALL
	card_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card_btn.set_meta("card_id", "bestiary_" + item_id)
	card_btn.set_meta("tank_id", item_id)

	var hbox := UiKit.hbox(10)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_btn.add_child(hbox)

	var text_vbox := UiKit.vbox(1)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(text_vbox)

	var title_str: String = Bestiary.text(item, "name") if is_unlocked else "???"
	var title_lbl := UiKit.label(title_str, 12, Cfg.UI_TEXT if is_unlocked else Cfg.UI_MUTED, true)
	text_vbox.add_child(title_lbl)

	var role_str: String = Bestiary.text(item, "role") if is_unlocked else _tr("bestiary.classified", "Засекреченный образец")
	var role_lbl := UiKit.label(role_str, 10, Cfg.UI_MUTED)
	text_vbox.add_child(role_lbl)

	var status_lbl := Label.new()
	status_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_lbl.add_theme_font_override("font", Fonts.bold)
	status_lbl.add_theme_font_size_override("font_size", 10)
	if bool(item.get("is_player", false)):
		status_lbl.text = _tr("bestiary.badge.player", "ИГРОК")
		status_lbl.add_theme_color_override("font_color", Cfg.UI_ACCENT)
	elif is_unlocked:
		status_lbl.text = "×%d" % kills
		status_lbl.add_theme_color_override("font_color", Cfg.UI_GOLD)
	else:
		status_lbl.text = _tr("bestiary.badge.locked", "ЗАКРЫТО")
		status_lbl.add_theme_color_override("font_color", Color(Cfg.UI_MUTED, 0.6))
	hbox.add_child(status_lbl)

	card_btn.pressed.connect(func(): _select_bestiary_tank(item_id))
	card_btn.focus_entered.connect(func(): _select_bestiary_tank(item_id))
	return card_btn

func _highlight_bestiary_card(selected_id: String) -> void:
	for id in _bestiary_cards:
		var btn: Button = _bestiary_cards[id]
		if not is_instance_valid(btn):
			continue
		var is_sel: bool = id == selected_id
		var normal := UiKit.flat(
			Color(0.18, 0.22, 0.14, 0.95) if is_sel else Color(0.10, 0.12, 0.10, 0.75),
			Cfg.RADIUS_SM,
			1.5 if is_sel else 1.0,
			Cfg.UI_ACCENT if is_sel else Color(Cfg.UI_BORDER, 0.4)
		)
		var hover := UiKit.flat(
			Color(0.22, 0.26, 0.17, 0.95) if is_sel else Color(0.14, 0.16, 0.12, 0.85),
			Cfg.RADIUS_SM,
			1.5,
			Cfg.UI_ACCENT
		)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		btn.add_theme_stylebox_override("focus", hover)

func _select_bestiary_tank(tank_id: String) -> void:
	_bestiary_selected_id = tank_id
	_highlight_bestiary_card(tank_id)
	_update_bestiary_detail(tank_id)

func _update_bestiary_detail(tank_id: String) -> void:
	if _bestiary_detail_container == null:
		return
	for c in _bestiary_detail_container.get_children():
		_bestiary_detail_container.remove_child(c)
		c.queue_free()

	var item: Dictionary = Bestiary.get_entry(tank_id)
	if item.is_empty():
		return

	var is_unlocked := Prof.is_bestiary_unlocked(tank_id)
	var kills := Prof.get_bestiary_kills(tank_id)

	# 1. Header (Category pill + Role, Title)
	var header_vbox := UiKit.vbox(3)
	header_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bestiary_detail_container.add_child(header_vbox)

	var sub_tag := Bestiary.category_text(item).to_upper()
	if is_unlocked:
		sub_tag += "  ·  " + Bestiary.text(item, "role").to_upper()
	var tag_lbl := UiKit.label(sub_tag, 10, Cfg.UI_ACCENT, true)
	header_vbox.add_child(tag_lbl)

	var title_text: String
	if is_unlocked:
		title_text = Bestiary.text(item, "name")
	else:
		title_text = _tr("bestiary.classified.title", "??? [ЗАСЕКРЕЧЕННЫЙ ОБРАЗЕЦ]")
	var title_lbl := UiKit.label(title_text, 18, Cfg.UI_TEXT if is_unlocked else Cfg.UI_MUTED, true)
	header_vbox.add_child(title_lbl)

	# 2. Big 2D Live Preview Box
	var preview_wrap := PanelContainer.new()
	preview_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_wrap.add_theme_stylebox_override("panel",
		UiKit.flat(Color(0.05, 0.06, 0.07, 0.95), Cfg.RADIUS_SM, 1, Color(Cfg.UI_BORDER, 0.5)))
	_bestiary_detail_container.add_child(preview_wrap)

	var center_box := CenterContainer.new()
	center_box.custom_minimum_size = Vector2(0, 110)
	preview_wrap.add_child(center_box)

	var stub_player := PlayerState.new(0, "", String(item.get("color_key", "p1")), null)
	var preview_tank := Tank.new({
		"x": 0.0, "y": 0.0, "team": "player" if bool(item.get("is_player", false)) else "enemy",
		"name": String(item.get("name", "")),
		"owner": stub_player,
		"color_key": String(item.get("color_key", "enemy")),
		"chassis": String(item.get("chassis", "standard")),
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30,
	})
	preview_tank.spawn_protect = 0
	preview_tank.cannon_id = String(item.get("cannon_id", "standard"))
	if tank_id == "chimera_clone":
		preview_tank.is_chimera_clone = true
	elif tank_id == "boss_chimera":
		preview_tank.is_chimera_boss = true
	elif tank_id == "boss_rammer":
		preview_tank.is_rammer_boss = true

	var tank_view := MenuTankView.new()
	tank_view.player = stub_player
	tank_view.display_tank = preview_tank
	tank_view.center_in_rect = true
	tank_view.auto_turret = true
	tank_view.is_locked = not is_unlocked
	tank_view.custom_minimum_size = Vector2(180, 100)
	center_box.add_child(tank_view)

	# 3. Status Pill / Combat Record
	var status_box := PanelContainer.new()
	status_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(item.get("is_player", false)):
		status_box.add_theme_stylebox_override("panel",
			UiKit.flat(Color(0.12, 0.18, 0.10, 0.85), Cfg.RADIUS_SM, 1, Color(Cfg.UI_ACCENT, 0.6)))
		var st_lbl := UiKit.label(_tr("bestiary.player_tank", "Доступен для управления в Гараже (Танк Игрока)"), 11, Cfg.UI_ACCENT, true)
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_box.add_child(st_lbl)
	elif is_unlocked:
		status_box.add_theme_stylebox_override("panel",
			UiKit.flat(Color(0.20, 0.18, 0.10, 0.85), Cfg.RADIUS_SM, 1, Color(Cfg.UI_GOLD, 0.6)))
		var st_lbl := UiKit.label(_tr("bestiary.kills", "Уничтожено в боевых действиях: %d раз(а)" % kills, {"n": kills}), 11, Cfg.UI_GOLD, true)
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_box.add_child(st_lbl)
	else:
		status_box.add_theme_stylebox_override("panel",
			UiKit.flat(Color(0.22, 0.10, 0.10, 0.85), Cfg.RADIUS_SM, 1, Color(Cfg.UI_DANGER, 0.6)))
		var st_lbl := UiKit.label(_tr("bestiary.condition", "УСЛОВИЕ РАССЕКРЕЧИВАНИЯ: Уничтожьте этот танк хотя бы 1 раз в бою"), 11, Color("#ffaaaa"), true)
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_box.add_child(st_lbl)
	_bestiary_detail_container.add_child(status_box)

	# 4. Tactical Characteristics (HP, Speed, Damage)
	_bestiary_detail_container.add_child(UiKit.section(_tr("bestiary.stats", "ТАКТИКО-ТЕХНИЧЕСКИЕ ХАРАКТЕРИСТИКИ"), Cfg.UI_ACCENT))
	var stats_box := PanelContainer.new()
	stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_box.add_theme_stylebox_override("panel",
		UiKit.flat(Color(0.08, 0.10, 0.08, 0.7), Cfg.RADIUS_SM, 1, Color(Cfg.UI_BORDER, 0.4)))
	_bestiary_detail_container.add_child(stats_box)

	var stats_vbox := UiKit.vbox(6)
	stats_box.add_child(stats_vbox)

	if is_unlocked:
		stats_vbox.add_child(_stat_row(_tr("bestiary.stat.hp", "Прочность корпуса:"), int(item.get("hp_rating", 3)), Bestiary.text(item, "hp_val")))
		stats_vbox.add_child(_stat_row(_tr("bestiary.stat.speed", "Подвижность / Ход:"), int(item.get("speed_rating", 3)), Bestiary.text(item, "speed_val")))
		stats_vbox.add_child(_stat_row(_tr("bestiary.stat.dmg", "Огневая мощь / Урон:"), int(item.get("dmg_rating", 3)), Bestiary.text(item, "dmg_val")))
	else:
		stats_vbox.add_child(_stat_row_masked(_tr("bestiary.stat.hp", "Прочность корпуса:")))
		stats_vbox.add_child(_stat_row_masked(_tr("bestiary.stat.speed", "Подвижность / Ход:")))
		stats_vbox.add_child(_stat_row_masked(_tr("bestiary.stat.dmg", "Огневая мощь / Урон:")))

	# 5. Tactical Profile / Lore
	_bestiary_detail_container.add_child(UiKit.section(_tr("bestiary.tactics", "ТАКТИЧЕСКИЙ ПРОФИЛЬ И ПРИМЕНЕНИЕ"), Cfg.UI_ACCENT))
	var desc_lbl: Label
	if is_unlocked:
		desc_lbl = UiKit.label(Bestiary.text(item, "desc"), 11, Cfg.UI_TEXT)
	else:
		desc_lbl = UiKit.label(_tr("bestiary.locked_desc", "Тактический профиль заблокирован. Технические спецификации, слабые места и алгоритмы боевого применения будут расшифрованы после первого уничтожения боевой единицы."), 11, Cfg.UI_MUTED)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bestiary_detail_container.add_child(desc_lbl)

	# 6. Abilities & Combat Features
	_bestiary_detail_container.add_child(UiKit.section(_tr("bestiary.abilities", "СПОСОБНОСТИ И БОЕВЫЕ МЕХАНИКИ"), Cfg.UI_ACCENT))
	if is_unlocked:
		var ab_list: Array = item.get("abilities", [])
		for ab_index in ab_list.size():
			var ab_panel := PanelContainer.new()
			ab_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ab_panel.add_theme_stylebox_override("panel",
				UiKit.flat(Color(0.10, 0.12, 0.09, 0.75), Cfg.RADIUS_SM, 1, Color(Cfg.UI_BORDER, 0.3)))
			_bestiary_detail_container.add_child(ab_panel)

			var ab_vbox := UiKit.vbox(2)
			ab_panel.add_child(ab_vbox)

			var ab_title := UiKit.label(Bestiary.ability_text(item, ab_index, "name"), 11, Cfg.UI_GOLD, true)
			ab_vbox.add_child(ab_title)

			var ab_desc := UiKit.label(Bestiary.ability_text(item, ab_index, "desc"), 10, Color(Cfg.UI_TEXT, 0.9))
			ab_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ab_vbox.add_child(ab_desc)
	else:
		var masked_card := PanelContainer.new()
		masked_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		masked_card.add_theme_stylebox_override("panel",
			UiKit.flat(Color(0.08, 0.08, 0.08, 0.6), Cfg.RADIUS_SM, 1, Color(Cfg.UI_BORDER, 0.2)))
		_bestiary_detail_container.add_child(masked_card)
		var m_lbl := UiKit.label(_tr("bestiary.systems_locked", "[СИСТЕМЫ ВООРУЖЕНИЯ И СПОСОБНОСТИ ЗАСЕКРЕЧЕНЫ]"), 11, Cfg.UI_MUTED)
		m_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		masked_card.add_child(m_lbl)

func _stat_row(title: String, stars: int, val_str: String) -> Control:
	var stat_line := UiKit.hbox(8)
	stat_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_lbl := UiKit.label(title, 11, Cfg.UI_MUTED)
	title_lbl.custom_minimum_size = Vector2(170, 0)
	stat_line.add_child(title_lbl)

	var stars_text := ""
	for i in 5:
		if i < stars:
			stars_text += "[color=#ffd700]★[/color]"
		else:
			stars_text += "[color=#4b533a]☆[/color]"
	var stars_rich := UiKit.rich(stars_text, 12)
	stars_rich.custom_minimum_size = Vector2(70, 0)
	stat_line.add_child(stars_rich)

	var val_lbl := UiKit.label(val_str, 11, Cfg.UI_TEXT, true)
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_line.add_child(val_lbl)
	return stat_line

func _stat_row_masked(title: String) -> Control:
	var stat_line := UiKit.hbox(8)
	stat_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_lbl := UiKit.label(title, 11, Cfg.UI_MUTED)
	title_lbl.custom_minimum_size = Vector2(170, 0)
	stat_line.add_child(title_lbl)

	var masked_lbl := UiKit.label(_tr("bestiary.classified_data", "[ДАННЫЕ ЗАСЕКРЕЧЕНЫ]"), 11, Color(Cfg.UI_MUTED, 0.6))
	masked_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_line.add_child(masked_lbl)
	return stat_line

func _fill_gallery_tab() -> void:
	_sub.text = _tr("gallery.sub",
		"Уровень профиля %d · открыто %d из %d" % [Prof.global_level, Prof.unlocked.size(), Perks.all().size()],
		{"lvl": Prof.global_level, "n": Prof.unlocked.size(), "total": Perks.all().size()})

	_gallery_nodes.clear()
	var row := UiKit.hbox(16)
	_gallery_row = row
	_body.add_child(row)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	list_scroll.custom_minimum_size = Vector2(0, _body_budget())
	row.add_child(list_scroll)

	var left_col := UiKit.vbox(16)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(left_col)

	if not Perks.BUILDS.is_empty():
		left_col.add_child(_build_builds_overview())

	var first_id := ""
	var _prev_band_last: SkillNode = null
	for cat in Perks.CATEGORIES:
		var perks := []
		for p in Perks.all():
			if p["category"] == cat["id"]:
				perks.append(p)
		if perks.is_empty():
			continue
		perks.sort_custom(func(a, b): return Perks.unlock_level_of(a["id"]) < Perks.unlock_level_of(b["id"]))
		if first_id == "":
			first_id = String(perks[0]["id"])

		var band := UiKit.vbox(8)
		band.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_col.add_child(band)

		var head := UiKit.section(_tr("cat." + String(cat["id"]), String(cat["name"])), cat["color"])
		band.add_child(head)

		var subcols := UiKit.hbox(14)
		subcols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		subcols.alignment = BoxContainer.ALIGNMENT_CENTER
		band.add_child(subcols)

		var num_cols := ceili(float(perks.size()) / float(_GALLERY_MAX_PER_COL))
		var rows := ceili(float(perks.size()) / float(num_cols))
		var columns: Array = []
		for c in num_cols:
			var sub := UiKit.vbox(8)
			sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sub.alignment = BoxContainer.ALIGNMENT_CENTER
			subcols.add_child(sub)
			var column: Array = []
			for r in rows:
				var idx := c * rows + r
				if idx >= perks.size():
					break
				if r > 0:
					sub.add_child(_gallery_spine())
				var node_wrap := CenterContainer.new()
				var node := _gallery_node(perks[idx])
				node_wrap.add_child(node)
				sub.add_child(node_wrap)
				column.append(node)
			columns.append(column)

		for column in columns:
			UiKit.chain_vertical(column)
		for c in columns.size() - 1:
			var a: Array = columns[c]
			var b: Array = columns[c + 1]
			for r in mini(a.size(), b.size()):
				a[r].focus_neighbor_right = b[r].get_path()
				b[r].focus_neighbor_left = a[r].get_path()
		if _prev_band_last != null and not columns.is_empty() and not columns[0].is_empty():
			var band_first: SkillNode = columns[0][0]
			_prev_band_last.focus_neighbor_bottom = band_first.get_path()
			band_first.focus_neighbor_top = _prev_band_last.get_path()
		if not columns.is_empty() and not columns.back().is_empty():
			_prev_band_last = columns.back().back()

	if _gallery_selected_id == "" or Perks.get_perk(_gallery_selected_id).is_empty():
		_gallery_selected_id = first_id

	_gallery_detail_panel = _build_gallery_detail(Perks.get_perk(_gallery_selected_id), row)

	if _gallery_nodes.has(first_id):
		var top_tab := _find_tab_button("gallery")
		if top_tab != null:
			top_tab.focus_neighbor_bottom = _gallery_nodes[first_id].get_path()

func _gallery_spine() -> Control:
	var wrap := CenterContainer.new()
	var line := ColorRect.new()
	line.color = Color(Cfg.UI_BORDER, 0.85)
	line.custom_minimum_size = Vector2(2, 14)
	wrap.add_child(line)
	return wrap

func _gallery_node(perk: Dictionary) -> Control:
	var id := String(perk["id"])
	var unlocked := Prof.is_unlocked(id)
	var node := SkillNode.new()
	node.perk_id = id
	node.locked = not unlocked
	node.selected = id == _gallery_selected_id
	if not perk.has("challenge"):
		node.need_level = Perks.unlock_level_of(id)
	var builds := Perks.builds_with_perk(id)
	if not builds.is_empty():
		var b: Dictionary = builds[0]
		node.synergy_color = b.get("color", Color.TRANSPARENT)
		node.synergy_build_name = String(b.get("name", ""))
	_gallery_nodes[id] = node
	node.picked.connect(func(picked_id: String): _select_gallery_perk(picked_id))
	return node

func _select_gallery_perk(id: String) -> void:
	if id == _gallery_selected_id:
		return
	if _gallery_nodes.has(_gallery_selected_id):
		_gallery_nodes[_gallery_selected_id].selected = false
	_gallery_selected_id = id
	if _gallery_nodes.has(id):
		_gallery_nodes[id].selected = true
	if _gallery_row == null:
		return
	if _gallery_detail_panel != null:
		_gallery_detail_panel.queue_free()
	_gallery_detail_panel = _build_gallery_detail(Perks.get_perk(id), _gallery_row)
	_resize_scroll()

func _build_synergy_text(id: String) -> String:
	var builds := Perks.builds_with_perk(id)
	if builds.is_empty():
		return ""
	var b: Dictionary = builds[0]
	var member_names := []
	for pid in b["perks"]:
		member_names.append(I18n.dn(Perks.get_perk(String(pid)), "name", "perk"))
	return "%s\n%s\n%s" % [
		I18n.dn(b, "name", "build").to_upper(),
		" + ".join(member_names),
		I18n.dn(b, "bonus", "build"),
	]

func _build_builds_overview() -> Control:
	var section := UiKit.vbox(8)
	section.add_child(UiKit.section(_tr("gallery.builds", "Билды"), Cfg.UI_ACCENT))

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	section.add_child(flow)

	for b in Perks.BUILDS:
		var build_col: Color = b.get("color", Cfg.UI_ACCENT)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.card_style(Color(build_col, 0.7)))
		card.custom_minimum_size = Vector2(220, 0)
		flow.add_child(card)

		var box := UiKit.vbox(4)
		card.add_child(box)

		box.add_child(UiKit.label(I18n.dn(b, "name", "build").to_upper(), 11, build_col, true))

		var names_bbcode := []
		for pid in (b["perks"] as Array):
			var perk := Perks.get_perk(String(pid))
			var col := Cfg.UI_TEXT if Prof.is_unlocked(String(pid)) else Cfg.UI_MUTED
			names_bbcode.append("[color=#%s]%s[/color]" % [col.to_html(false), I18n.dn(perk, "name", "perk")])
		box.add_child(UiKit.rich(" + ".join(names_bbcode), 9, Cfg.UI_MUTED))

		var bonus_label := UiKit.label(I18n.dn(b, "bonus", "build"), 9, Cfg.UI_WARN)
		bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bonus_label.custom_minimum_size = Vector2(210, 0)
		box.add_child(bonus_label)

	return section

func _build_gallery_detail(perk: Dictionary, parent: Node) -> Control:
	var panel: GalleryDetail = GalleryDetailScene.instantiate()
	parent.add_child(panel)
	if perk.is_empty():
		return panel
	var id := String(perk["id"])
	var unlocked := Prof.is_unlocked(id)
	var is_active := perk.has("active")
	var name_text := I18n.dn(perk, "name", "perk")
	var desc_text := I18n.dn(perk, "desc", "perk")
	var build_text := _build_synergy_text(id)

	var builds := Perks.builds_with_perk(id)
	var syn_col := Color.TRANSPARENT
	if not builds.is_empty():
		syn_col = builds[0].get("color", Color.TRANSPARENT)

	if unlocked:
		panel.set_perk(id, name_text, desc_text, true, {}, _tr("gallery.open", "ОТКРЫТ"), "", is_active, build_text, syn_col)
	elif perk.has("challenge"):
		var pr := Prof.challenge_progress(id)
		var task := I18n.t("perk." + id + ".challenge", {}, String(pr["desc"]))
		panel.set_perk(id, name_text, desc_text, false, pr, "", task, is_active, build_text, syn_col)
	else:
		var lvl := Perks.unlock_level_of(id)
		panel.set_perk(id, name_text, desc_text, false, {},
			_tr("gallery.unlockAt", "Откроется на уровне профиля %d" % lvl, {"lvl": lvl}),
			"", is_active, build_text, syn_col)
	return panel

func _fill_garage_tab() -> void:
	_sub.text = "[center]" + _tr("garage.sub",
		"Монеты: [b]%d[/b] 🪙 · Улучшения танка действуют на обоих игроков в партии" % Prof.money,
		{"money": Prof.money}) + "[/center]"

	for cat in Upgrades.CATEGORIES:
		var ups := []
		for u in Upgrades.LIST:
			if u["category"] == cat["id"]:
				ups.append(u)
		if ups.is_empty():
			continue
		_body.add_child(UiKit.section(_tr("cat." + String(cat["id"]), String(cat["name"])), cat["color"]))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		_body.add_child(grid)
		for up in ups:
			_upgrade_card(up, grid)

	_body.add_child(UiKit.section(_tr("garage.cannons", "Пушки"), Cfg.UI_MUTED))
	var cannon_grid := HFlowContainer.new()
	cannon_grid.add_theme_constant_override("h_separation", 10)
	cannon_grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(cannon_grid)
	for c in Cannons.LIST:
		_cannon_card(c, cannon_grid)

func _fill_cosmetics_tab() -> void:
	_sub.text = "[center]" + _tr("cosmetics.sub",
		"Монеты: [b]%d[/b] 🪙 · Персонализируйте внешний вид вашего танка" % Prof.money,
		{"money": Prof.money}) + "[/center]"

	var budget := _body_budget()

	# Two-column container: Left = Pinned Live Tank Preview, Right = Scrollable Catalog
	var main_row := UiKit.hbox(14)
	main_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(main_row)

	# ============================================================
	# LEFT PANE: PINNED LIVE TANK PREVIEW (ALWAYS VISIBLE!)
	# ============================================================
	var preview_scroll := ScrollContainer.new()
	preview_scroll.custom_minimum_size = Vector2(310, budget)
	preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_row.add_child(preview_scroll)

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel",
		UiKit.flat(Color(0.06, 0.08, 0.10, 0.95), Cfg.RADIUS_MD, 1.5, Color(Cfg.UI_ACCENT, 0.45)))
	preview_scroll.add_child(preview_panel)

	var prev_vbox := UiKit.vbox(8)
	prev_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.add_child(prev_vbox)

	var title_lbl := UiKit.label(_tr("cosmetics.preview", "АНГАР · ЖИВОЙ ПРЕДПРОСМОТР").to_upper(), 10, Cfg.UI_ACCENT, true)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prev_vbox.add_child(title_lbl)

	# Frame for live MenuTankView
	var center_box := PanelContainer.new()
	center_box.custom_minimum_size = Vector2(0, 150)
	center_box.add_theme_stylebox_override("panel",
		UiKit.flat(Color(0.03, 0.04, 0.05, 0.90), Cfg.RADIUS_SM, 1.0, Color(Cfg.UI_BORDER, 0.5)))
	prev_vbox.add_child(center_box)

	var stub_player := PlayerState.new(0, "", Prof.equipped_color1, null)
	_cosmetic_preview_tank = Tank.new({
		"x": 0.0, "y": 0.0, "team": "player", "name": "",
		"owner": stub_player, "color_key": Prof.equipped_color1,
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30,
	})
	_cosmetic_preview_tank.spawn_protect = 0
	_cosmetic_preview_tank.cosmetics = Prof.equipped_cosmetics()
	_cosmetic_preview_tank.cannon_id = Prof.equipped_cannon

	_cosmetic_preview_view = MenuTankView.new()
	_cosmetic_preview_view.player = stub_player
	_cosmetic_preview_view.display_tank = _cosmetic_preview_tank
	_cosmetic_preview_view.center_in_rect = true
	_cosmetic_preview_view.auto_turret = true
	_cosmetic_preview_view.custom_minimum_size = Vector2(250, 140)
	center_box.add_child(_cosmetic_preview_view)

	# Info header: Item title and badge
	var info_box := UiKit.vbox(3)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_vbox.add_child(info_box)

	_cosmetic_title_lbl = UiKit.label(_tr("cos.default.name", "Стандартный"), 14, Color.WHITE, true)
	_cosmetic_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_box.add_child(_cosmetic_title_lbl)

	_cosmetic_badge_lbl = RichTextLabel.new()
	_cosmetic_badge_lbl.bbcode_enabled = true
	_cosmetic_badge_lbl.fit_content = true
	_cosmetic_badge_lbl.scroll_active = false
	_cosmetic_badge_lbl.add_theme_font_override("normal_font", Fonts.bold)
	_cosmetic_badge_lbl.add_theme_font_size_override("normal_font_size", 9)
	_cosmetic_badge_lbl.text = "[center][color=#94a3b8]" + _tr("cos.badge.base_set", "БАЗОВЫЙ КОМПЛЕКТ") + "[/color][/center]"
	info_box.add_child(_cosmetic_badge_lbl)

	_cosmetic_desc_lbl = UiKit.label(_tr("cos.default.desc", "Базовый заводской комплект брони, башни и гусениц."), 10, Color(Cfg.UI_TEXT, 0.85))
	_cosmetic_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cosmetic_desc_lbl.custom_minimum_size = Vector2(280, 42)
	prev_vbox.add_child(_cosmetic_desc_lbl)

	# Breakdown features box
	var feats_panel := PanelContainer.new()
	feats_panel.add_theme_stylebox_override("panel",
		UiKit.flat(Color(0.04, 0.05, 0.07, 0.80), Cfg.RADIUS_SM, 1.0, Color(Cfg.UI_BORDER, 0.4)))
	prev_vbox.add_child(feats_panel)

	var feats_vbox := UiKit.vbox(3)
	feats_panel.add_child(feats_vbox)

	_cosmetic_feat_hull = UiKit.label(_tr("cos.default.hull", "Корпус: Заводская броня"), 9, Color(Cfg.UI_TEXT, 0.9))
	_cosmetic_feat_turret = UiKit.label(_tr("cos.default.turret", "Башня: Стандартная нарезная"), 9, Color(Cfg.UI_TEXT, 0.9))
	_cosmetic_feat_track = UiKit.label(_tr("cos.default.track", "Гусеницы: Чугунные траки"), 9, Color(Cfg.UI_TEXT, 0.9))
	feats_vbox.add_child(_cosmetic_feat_hull)
	feats_vbox.add_child(_cosmetic_feat_turret)
	feats_vbox.add_child(_cosmetic_feat_track)

	# Status and Action Buttons
	_cosmetic_status_lbl = UiKit.label(_tr("cos.status.equipped", "ЭКИПИРОВАНО"), 11, Cfg.UI_ACCENT, true)
	_cosmetic_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prev_vbox.add_child(_cosmetic_status_lbl)

	_cosmetic_action_btn = UiKit.primary(_tr("cos.status.equipped", "ЭКИПИРОВАНО"), 12)
	_cosmetic_action_btn.custom_minimum_size = Vector2(0, 36)
	_cosmetic_action_btn.disabled = true
	prev_vbox.add_child(_cosmetic_action_btn)

	_cosmetic_reset_btn = UiKit.secondary(_tr("cos.reset", "Сбросить предпросмотр"), 10)
	_cosmetic_reset_btn.custom_minimum_size = Vector2(0, 28)
	_cosmetic_reset_btn.visible = false
	_cosmetic_reset_btn.pressed.connect(func(): _reset_cosmetics_preview())
	prev_vbox.add_child(_cosmetic_reset_btn)

	# ============================================================
	# RIGHT PANE: SCROLLABLE CATALOG WITH PERK-STYLE CARDS
	# ============================================================
	var catalog_scroll := ScrollContainer.new()
	catalog_scroll.custom_minimum_size = Vector2(550, budget)
	catalog_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	catalog_scroll.follow_focus = true
	_cosmetic_catalog_scroll = catalog_scroll
	main_row.add_child(catalog_scroll)

	var catalog_vbox := UiKit.vbox(10)
	catalog_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_scroll.add_child(catalog_vbox)

	# 1. Colors
	catalog_vbox.add_child(UiKit.section(_tr("garage.colors", "Расцветка корпуса"), Cfg.UI_ACCENT))
	catalog_vbox.add_child(_garage_color_row(_tr("menu.color1", "Основной цвет (Игрок 1)"), 0, Prof.equipped_color1, "cosmetics"))
	catalog_vbox.add_child(_garage_color_row(_tr("menu.color2", "Второй цвет (Игрок 2)"), 1, Prof.equipped_color2, "cosmetics"))

	# 2. Premium / Legendary Skins (Complete sets!)
	catalog_vbox.add_child(UiKit.section(_tr("cos.skin", "Премиальные и Легендарные скины (Корпус + Башня + Гусеницы)"), Color("#ffd700")))
	var skin_grid := HFlowContainer.new()
	skin_grid.add_theme_constant_override("h_separation", 10)
	skin_grid.add_theme_constant_override("v_separation", 10)
	catalog_vbox.add_child(skin_grid)
	for s in Cosmetics.SKINS:
		_cosmetic_card(s, "skin", skin_grid, "cosmetics")

	# 3. Individual Categories
	var type_names := {
		"camo": _tr("cos.type.camo", "Боевой камуфляж"),
		"hull": _tr("cos.type.hull", "Рисунки и декали на корпусе"),
		"track": _tr("cos.type.track", "Гусеницы"),
		"turret": _tr("cos.type.turret", "Башни")
	}
	for type in ["camo", "hull", "track", "turret"]:
		var section_title := String(type_names.get(type, type))
		catalog_vbox.add_child(UiKit.section(_tr("cos." + type, section_title), Cfg.UI_MUTED))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		catalog_vbox.add_child(grid)
		for c in Cosmetics.by_type(type):
			_cosmetic_card(c, type, grid, "cosmetics")

	# Initialize preview with currently equipped skin
	_reset_cosmetics_preview()

func _set_cosmetic_preview(type: String, id: String) -> void:
	if _cosmetic_preview_tank == null:
		return
	_cosmetic_preview_type = type
	_cosmetic_preview_id = id

	var temp_cosmetics := Prof.equipped_cosmetics()
	if type == "skin":
		temp_cosmetics["skin"] = id
		if id != "none":
			temp_cosmetics["track"] = "none"
			temp_cosmetics["turret"] = "none"
	else:
		temp_cosmetics[type] = id
	_cosmetic_preview_tank.cosmetics = temp_cosmetics

	var item := Cosmetics.get_cosmetic(type, id)
	if item.is_empty():
		return

	var name_str := I18n.dn(item, "name", "cos." + type)
	var rarity_str := String(item.get("rarity", ""))
	var desc_str := String(item.get("desc", ""))
	var price_val := int(item.get("price", 0))
	var owned := Prof.is_cosmetic_owned(type, id)
	var equipped := String(Prof.cosmetics.get(type, "none")) == id
	var can_buy := not owned and Prof.money >= price_val

	if _cosmetic_title_lbl != null:
		_cosmetic_title_lbl.text = name_str

	if _cosmetic_badge_lbl != null:
		var badge := ""
		if type == "skin":
			if rarity_str == "legendary":
				badge = "[center][color=#ffd700]" + _tr("cos.badge.legendary_set", "ЛЕГЕНДАРНЫЙ · ПОЛНЫЙ КОМПЛЕКТ") + "[/color][/center]"
			elif rarity_str == "epic":
				badge = "[center][color=#c084fc]" + _tr("cos.badge.epic_set", "ЭПИЧЕСКИЙ · ПОЛНЫЙ КОМПЛЕКТ") + "[/color][/center]"
			elif rarity_str == "rare":
				badge = "[center][color=#60a5fa]" + _tr("cos.badge.rare_set", "РЕДКИЙ · ПОЛНЫЙ КОМПЛЕКТ") + "[/color][/center]"
			else:
				badge = "[center][color=#94a3b8]" + _tr("cos.badge.base_set", "БАЗОВЫЙ КОМПЛЕКТ") + "[/color][/center]"
		else:
			if rarity_str == "legendary":
				badge = "[center][color=#ffd700]" + _tr("cos.badge.legendary", "ЛЕГЕНДАРНЫЙ") + "[/color][/center]"
			elif rarity_str == "epic":
				badge = "[center][color=#c084fc]" + _tr("cos.badge.epic", "ЭПИЧЕСКИЙ") + "[/color][/center]"
			elif rarity_str == "rare":
				badge = "[center][color=#60a5fa]" + _tr("cos.badge.rare", "РЕДКИЙ") + "[/color][/center]"
			else:
				match type:
					"camo": badge = "[center][color=#94a3b8]" + _tr("cos.badge.camo", "КАМУФЛЯЖ") + "[/color][/center]"
					"hull": badge = "[center][color=#94a3b8]" + _tr("cos.badge.hull", "ДЕКАЛЬ КОРПУСА") + "[/color][/center]"
					"track": badge = "[center][color=#94a3b8]" + _tr("cos.badge.track", "ГУСЕНИЦЫ") + "[/color][/center]"
					"turret": badge = "[center][color=#94a3b8]" + _tr("cos.badge.turret", "БАШНЯ") + "[/color][/center]"
					_: badge = "[center][color=#94a3b8]" + _tr("cos.badge.cosmetic", "КОСМЕТИКА") + "[/color][/center]"
		_cosmetic_badge_lbl.text = badge

	if _cosmetic_desc_lbl != null:
		_cosmetic_desc_lbl.text = desc_str

	if _cosmetic_feat_hull != null and _cosmetic_feat_turret != null and _cosmetic_feat_track != null:
		if type == "skin":
			_cosmetic_feat_hull.visible = true
			_cosmetic_feat_turret.visible = true
			_cosmetic_feat_track.visible = true
			match id:
				"cyberpunk":
					_cosmetic_feat_hull.text = _tr("cos.feat.cyberpunk.hull", "Корпус: неон, микросхемы и сканер")
					_cosmetic_feat_turret.text = _tr("cos.feat.cyberpunk.turret", "Башня: кибер-визор и энерго-ствол")
					_cosmetic_feat_track.text = _tr("cos.feat.cyberpunk.track", "Гусеницы: неоновые светящиеся траки")
				"magma":
					_cosmetic_feat_hull.text = _tr("cos.feat.magma.hull", "Корпус: базальт с огненными разломами")
					_cosmetic_feat_turret.text = _tr("cos.feat.magma.turret", "Башня: вулканическое жерло и лава")
					_cosmetic_feat_track.text = _tr("cos.feat.magma.track", "Гусеницы: раскаленные огненные траки")
				"steampunk":
					_cosmetic_feat_hull.text = _tr("cos.feat.steampunk.hull", "Корпус: кованая латунь и шестерни")
					_cosmetic_feat_turret.text = _tr("cos.feat.steampunk.turret", "Башня: купол с манометром и нарезка")
					_cosmetic_feat_track.text = _tr("cos.feat.steampunk.track", "Гусеницы: тяжелая кованая бронза")
				"void":
					_cosmetic_feat_hull.text = _tr("cos.feat.void.hull", "Корпус: темная материя и созвездия")
					_cosmetic_feat_turret.text = _tr("cos.feat.void.turret", "Башня: сингулярность с аккрецией")
					_cosmetic_feat_track.text = _tr("cos.feat.void.track", "Гусеницы: звездная аметистовая пыль")
				"dragon":
					_cosmetic_feat_hull.text = _tr("cos.feat.dragon.hull", "Корпус: изумрудная чешуя и хребет")
					_cosmetic_feat_turret.text = _tr("cos.feat.dragon.turret", "Башня: рога дракона и рубиновое око")
					_cosmetic_feat_track.text = _tr("cos.feat.dragon.track", "Гусеницы: когтистые шипы и чешуя")
				"toxic":
					_cosmetic_feat_hull.text = _tr("cos.feat.toxic.hull", "Корпус: биозащита и знак опасности")
					_cosmetic_feat_turret.text = _tr("cos.feat.toxic.turret", "Башня: колба бурлящего токсина")
					_cosmetic_feat_track.text = _tr("cos.feat.toxic.track", "Гусеницы: защитные хим-траки")
				"golden_emperor":
					_cosmetic_feat_hull.text = _tr("cos.feat.golden_emperor.hull", "Корпус: зеркальное 24К золото и пурпур")
					_cosmetic_feat_turret.text = _tr("cos.feat.golden_emperor.turret", "Башня: царская корона с рубином")
					_cosmetic_feat_track.text = _tr("cos.feat.golden_emperor.track", "Гусеницы: сплошные золотые звенья")
				"arctic_frost":
					_cosmetic_feat_hull.text = _tr("cos.feat.arctic_frost.hull", "Корпус: реликтовый лед и кристаллы")
					_cosmetic_feat_turret.text = _tr("cos.feat.arctic_frost.turret", "Башня: морозная звезда и иней")
					_cosmetic_feat_track.text = _tr("cos.feat.arctic_frost.track", "Гусеницы: заснеженная мерзлота")
				_:
					_cosmetic_feat_hull.text = _tr("cos.feat.default.hull", "Корпус: заводская бронеплита")
					_cosmetic_feat_turret.text = _tr("cos.feat.default.turret", "Башня: стандартная нарезная")
					_cosmetic_feat_track.text = _tr("cos.feat.default.track", "Гусеницы: стальные траки")
		else:
			_cosmetic_feat_hull.visible = type == "hull" or type == "camo"
			_cosmetic_feat_turret.visible = type == "turret"
			_cosmetic_feat_track.visible = type == "track"
			if type == "hull": _cosmetic_feat_hull.text = _tr("cos.feat.art", "Рисунок: %s" % name_str, {"name": name_str})
			elif type == "camo": _cosmetic_feat_hull.text = _tr("cos.feat.camo", "Камуфляж: %s" % name_str, {"name": name_str})
			elif type == "turret": _cosmetic_feat_turret.text = _tr("cos.feat.turret", "Башня: %s" % name_str, {"name": name_str})
			elif type == "track": _cosmetic_feat_track.text = _tr("cos.feat.track", "Гусеницы: %s" % name_str, {"name": name_str})

	if _cosmetic_status_lbl != null:
		if equipped:
			_cosmetic_status_lbl.text = _tr("cos.status.equipped", "ЭКИПИРОВАНО")
			_cosmetic_status_lbl.add_theme_color_override("font_color", Cfg.UI_ACCENT)
		elif owned:
			_cosmetic_status_lbl.text = _tr("cos.status.owned", "В ВАШЕЙ КОЛЛЕКЦИИ")
			_cosmetic_status_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
		else:
			_cosmetic_status_lbl.text = _tr("cos.status.price", "ЦЕНА: %d 🪙" % price_val, {"price": price_val})
			_cosmetic_status_lbl.add_theme_color_override("font_color", Cfg.UI_GOLD if can_buy else Cfg.UI_MUTED)

	if _cosmetic_action_btn != null:
		for conn in _cosmetic_action_btn.pressed.get_connections():
			_cosmetic_action_btn.pressed.disconnect(conn["callable"])

		if equipped:
			_cosmetic_action_btn.text = _tr("cos.status.equipped", "ЭКИПИРОВАНО")
			_cosmetic_action_btn.disabled = true
		elif owned:
			_cosmetic_action_btn.text = _tr("cos.action.equip", "НАДЕТЬ")
			_cosmetic_action_btn.disabled = false
			_cosmetic_action_btn.pressed.connect(func():
				if Prof.equip_cosmetic(type, id)["ok"]:
					garage_changed.emit()
					switch_tab("cosmetics", "cos_%s_%s" % [type, id])
			)
		else:
			_cosmetic_action_btn.text = _tr("cos.action.buy", "КУПИТЬ · %d 🪙" % price_val, {"price": price_val})
			_cosmetic_action_btn.disabled = not can_buy
			_cosmetic_action_btn.pressed.connect(func():
				if Prof.buy_cosmetic(type, id)["ok"]:
					Prof.equip_cosmetic(type, id)
					garage_changed.emit()
					switch_tab("cosmetics", "cos_%s_%s" % [type, id])
			)

	if _cosmetic_reset_btn != null:
		_cosmetic_reset_btn.visible = not equipped

func _reset_cosmetics_preview() -> void:
	var cur_skin: String = String(Prof.cosmetics.get("skin", "none"))
	_set_cosmetic_preview("skin", cur_skin)

func _upgrade_card(up: Dictionary, parent: Node) -> Control:
	var id := String(up["id"])
	var level := Prof.upgrade_level(id)
	var maxed := level >= int(up["max_level"])
	var cost := -1 if maxed else Upgrades.cost(up, level)
	var can_buy := not maxed and Prof.money >= cost
	var card_id := "upg_" + id

	var card: UpgradeCard = UpgradeCardScene.instantiate()
	parent.add_child(card)
	card.set_data("upg_" + id, I18n.dn(up, "name", "upg"), I18n.dn(up, "desc", "upg"),
		level, int(up["max_level"]),
		_tr("upg.buy", "Улучшить · %d 🪙" % cost, {"price": cost}), _tr("upg.max", "МАКС"), maxed, can_buy, card_id)
	card.buy_pressed.connect(func():
		if Prof.buy_upgrade(id)["ok"]:
			garage_changed.emit()
			switch_tab("garage", card_id))
	return card

func _cosmetic_card(c: Dictionary, type: String, parent: Node, tab_key: String = "cosmetics") -> Control:
	var id := String(c["id"])
	var owned := Prof.is_cosmetic_owned(type, id)
	var equipped := String(Prof.cosmetics.get(type, "none")) == id
	var can_buy := not owned and Prof.money >= int(c["price"])
	var card_id := "cos_%s_%s" % [type, id]

	var state := ""
	var action_text := ""
	var action_disabled := false
	if equipped:
		state = _tr("cos.equipped", "Надето")
		action_text = _tr("cos.equipped", "Надето")
		action_disabled = true
	elif owned:
		state = _tr("cos.owned", "В ангаре")
		action_text = _tr("cos.equip", "Надеть")
		action_disabled = false
	else:
		state = "%d 🪙" % int(c["price"])
		action_text = _tr("cos.buy", "Купить · %d 🪙" % int(c["price"]), {"price": c["price"]})
		action_disabled = not can_buy

	var rarity: String = String(c.get("rarity", ""))
	var desc_text: String = String(c.get("desc", ""))

	var card: CosmeticCard = CosmeticCardScene.instantiate()
	parent.add_child(card)
	card.set_data("cos_%s_%s" % [type, id], c.get("color", c.get("a", Cfg.UI_TEXT)),
		I18n.dn(c, "name", "cos." + type), state, action_text, action_disabled, equipped, can_buy, card_id,
		rarity, desc_text, type, id)
	card.preview_requested.connect(func(ptype, pid):
		_set_cosmetic_preview(ptype, pid)
	)
	card.action_pressed.connect(func():
		var ok := false
		if not owned:
			var buy_res := Prof.buy_cosmetic(type, id)
			if buy_res.get("ok", false):
				ok = true
				Prof.equip_cosmetic(type, id)
		else:
			ok = Prof.equip_cosmetic(type, id).get("ok", false)
		if ok:
			garage_changed.emit()
			_set_cosmetic_preview(type, id)
			switch_tab(tab_key, card_id))
	return card

func _cannon_card(c: Dictionary, parent: Node) -> Control:
	var id := String(c["id"])
	var owned := Prof.is_cannon_owned(id)
	var equipped := Prof.equipped_cannon == id
	var can_buy := not owned and Prof.money >= int(c["price"])
	var card_id := "cannon_" + id

	var state := ""
	var action_text := ""
	var action_disabled := false
	if owned:
		state = _tr("cos.equipped", "Надето") if equipped else _tr("cos.owned", "Куплено")
		action_text = _tr("cos.equipped", "Надето") if equipped else _tr("cos.equip", "Надеть")
		action_disabled = equipped
	else:
		state = _tr("cos.price", "Цена: %d 🪙" % int(c["price"]), {"price": c["price"]})
		action_text = _tr("cos.buy", "Купить · %d 🪙" % int(c["price"]), {"price": c["price"]})
		action_disabled = not can_buy

	var card: CannonCard = CannonCardScene.instantiate()
	parent.add_child(card)
	card.set_data(String(c["icon"]), c.get("color", Cfg.UI_TEXT), I18n.dn(c, "name", "cannon"),
		state, action_text, action_disabled, equipped, can_buy, card_id)
	card.action_pressed.connect(func():
		var ok := false
		if not owned:
			var buy_res := Prof.buy_cannon(id)
			if buy_res.get("ok", false):
				ok = true
				Prof.equip_cannon(id)
		else:
			ok = Prof.equip_cannon(id).get("ok", false)
		if ok:
			garage_changed.emit()
			switch_tab("garage", card_id))
	return card

func _garage_color_row(label_text: String, slot: int, equipped_key: String, tab_key: String = "cosmetics") -> Control:
	var box := UiKit.vbox(6)
	box.add_child(UiKit.label(label_text.to_upper(), 10, Color(Cfg.UI_MUTED, 0.55)))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	var group := ButtonGroup.new()
	for skin in Cfg.PLAYER_SKINS:
		var key: String = skin["key"]
		var unlocked := Prof.is_color_unlocked(key)
		var lvl := int(skin.get("level", 1))
		var btn := UiKit.toggle(String(key).to_upper() if unlocked else str(lvl))
		btn.tooltip_text = _tr("skin." + key, String(skin["name"])) if unlocked \
			else _tr("gallery.unlockAt", "Откроется на уровне профиля %d" % lvl, {"lvl": lvl})
		btn.button_group = group
		btn.button_pressed = equipped_key == key
		btn.disabled = not unlocked
		var col := Color(String(skin["color"]))
		if unlocked:
			btn.add_theme_stylebox_override("normal", UiKit.flat(col.darkened(0.35), 999, 1, Color(1, 1, 1, 0.12)))
			btn.add_theme_stylebox_override("hover", UiKit.flat(col.darkened(0.15), 999, 1, Cfg.UI_ACCENT))
			btn.add_theme_stylebox_override("pressed", UiKit.flat(col, 999, 2, Color.WHITE))
			btn.add_theme_stylebox_override("hover_pressed", UiKit.flat(col, 999, 2, Color.WHITE))
		else:
			var muted := col.darkened(0.6)
			muted.a = 0.5
			btn.add_theme_stylebox_override("normal", UiKit.flat(muted, 999, 1, Color(1, 1, 1, 0.08)))
			btn.add_theme_stylebox_override("disabled", UiKit.flat(muted, 999, 1, Color(1, 1, 1, 0.08)))
		var card_id := "color%d_%s" % [slot, key]
		btn.set_meta("card_id", card_id)
		btn.pressed.connect(func():
			if Prof.set_equipped_color(slot, key):
				garage_changed.emit()
				switch_tab(tab_key, card_id))
		flow.add_child(btn)
	return box

func _fill_achievements_tab() -> void:
	var unlocked := []
	var total_reward := 0
	for a in Achievements.LIST:
		if Prof.achievements.has(a["id"]):
			unlocked.append(a)
			total_reward += int(a["reward"])
	_sub.text = "[center]" + _tr("achievements.sub",
		"Открыто [b]%d[/b] из %d · награда всего [b]%d 🪙[/b]" % [
			unlocked.size(), Achievements.LIST.size(), total_reward],
		{"n": unlocked.size(), "total": Achievements.LIST.size(), "reward": total_reward}) + "[/center]"

	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)

	var cards: Array = []
	for a in Achievements.LIST:
		var done := Prof.achievements.has(a["id"])
		var cur := int(Prof.stats.get(a["stat"], 0))
		var need := int(a["need"])
		var card: AchievementCard = AchievementCardScene.instantiate()
		grid.add_child(card)
		card.set_data("ach_" + String(a["id"]), I18n.dn(a, "name", "ach"), I18n.dn(a, "desc", "ach"),
			done, int(a["reward"]), cur, need)
		cards.append(card)

	UiKit.chain_horizontal(cards, true)
	if not cards.is_empty():
		var top_tab := _find_tab_button("achievements")
		if top_tab != null:
			top_tab.focus_neighbor_bottom = cards[0].get_path()

func _editor_preview_body() -> void:
	_body.add_child(UpgradeCardScene.instantiate())
