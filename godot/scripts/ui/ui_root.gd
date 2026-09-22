class_name UiRoot
extends Control

signal start_requested
signal restart_requested
signal menu_requested
signal resume_requested
signal perk_chosen(player, perk_id)
signal reset_progress_requested
signal garage_changed
signal daily_reward_claimed(reward: int)
signal quit_requested

const PERK_CHOICES := 3

const MAX_DEADZONE := 0.5

static func game_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))

var settings := {
	"game_type": "single", "mode": "ffa", "difficulty": "medium",
	"level": -1,
	"weather": "auto", "daytime": "auto", "location": "auto",
}

var main_menu: MainMenu
var _menu: Control
var _menu_settings: Control
var _menu_settings_scroll: ScrollContainer
var _menu_settings_panel: ThemedPanel
var _menu_settings_btn: Button

var _net: Control
var _net_body: VBoxContainer
var _net_sub: RichTextLabel
var _net_error := ""
var _net_mode := ""
var _net_room_name := ""
var _net_search := ""

var _settings: Control
var _settings_body: VBoxContainer
var _settings_tabs_row: HBoxContainer
var _settings_active_tab := "general"
var _settings_key_status: Label

var _pause: Control
var _perk: Control
var _perk_body: VBoxContainer
var _gameover: Control
var _gameover_panel: ThemedPanel
var _gameover_title: Label
var _gameover_body: VBoxContainer

var hub: Hub
var _hub: Control
var _hub_active_tab: String:
	get: return hub.active_tab if hub != null else "gallery"

var _stats: Control
var _stats_body: VBoxContainer
var _stats_sub: RichTextLabel
var _daily: Control
var _daily_body: VBoxContainer
var _daily_sub: RichTextLabel

var _confirm: ConfirmationDialog

var _last_gameover := {}

var _nav_theme: Theme
var _pad_hints: Array = []
var _focus_stack: Array = []
var _menu_focus_cache := {}
var _menu_start_btn: Button
var _pause_resume_btn: Button
var _gameover_replay_btn: Button
var _perk_player = null
var _perk_pending_id := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_menu()
	_build_pause()
	_build_perk()
	_build_gameover()
	_build_hub()
	_stats = _make_overlay(true)
	_stats_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	_stats_body = _overlay_body(_stats, "stats.title", "📊 Статистика", _stats_sub,
		func(): close_stats(), 540)
	_daily = _make_overlay(true)
	_daily_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	_daily_body = _overlay_body(_daily, "daily.title", "📅 Ежедневные задания",
		_daily_sub, func(): close_daily())
	_net = _make_overlay(true)
	_net_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	_net_body = _overlay_body(_net, "net.title", "🌐 Сетевая игра",
		_net_sub, func(): close_net(), 620)

	_build_settings_shell()

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func(): reset_progress_requested.emit())
	add_child(_confirm)

	I18n.language_changed.connect(_on_language_changed)

	for ov in [_settings, _net, _stats, _daily, _hub]:
		if ov != null:
			ov.visibility_changed.connect(_on_menu_overlay_visibility.bind(ov))

	_nav_theme = Theme.new()
	theme = _nav_theme
	Sets.ui_input_mode_changed.connect(_apply_nav_mode)
	_apply_nav_mode(Sets.pad_ui)

func _make_overlay(dim: bool) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if dim:
		root.add_child(UiKit.dimmer())
	add_child(root)
	return root

func _pad_hint_strip(adjust: bool = false) -> RichTextLabel:
	var parts := [
		"‹A› " + I18n.t("nav.select", {}, "выбрать"),
		"‹B› " + I18n.t("nav.back", {}, "назад"),
		"‹✚› " + I18n.t("nav.move", {}, "перемещение"),
	]
	if adjust:
		parts.append("‹↔› " + I18n.t("nav.adjust", {}, "изменить"))
	var strip := UiKit.rich("[center]" + "   ".join(parts) + "[/center]", 9,
		Color(Cfg.UI_MUTED, 0.7))
	strip.visible = Sets.pad_ui
	_pad_hints.append(strip)
	return strip

func _apply_nav_mode(pad_ui: bool) -> void:
	if _nav_theme != null:
		_nav_theme.set_stylebox("focus", "Button",
			UiKit.focus_ring() if pad_ui else StyleBoxEmpty.new())
		_nav_theme.set_stylebox("focus", "HSlider",
			UiKit.focus_ring() if pad_ui else StyleBoxEmpty.new())
	for strip in _pad_hints:
		if is_instance_valid(strip):
			strip.visible = pad_ui

func _grab(ctrl) -> void:
	if is_instance_valid(ctrl):
		ctrl.grab_focus.call_deferred()

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

func _find_tab_button(row: Control, key: String) -> Control:
	for c in row.get_children():
		if c.has_meta("tab_key") and String(c.get_meta("tab_key")) == key:
			return c
	return null

func _push_focus() -> void:
	_focus_stack.append(get_viewport().gui_get_focus_owner())

func _pop_focus() -> void:
	if _focus_stack.is_empty():
		return
	var prev = _focus_stack.pop_back()
	if is_instance_valid(prev):
		_grab(prev)

func _set_menu_focusable(on: bool) -> void:
	if on:
		for id in _menu_focus_cache:
			var c = instance_from_id(id)
			if is_instance_valid(c):
				c.focus_mode = _menu_focus_cache[id]
		_menu_focus_cache.clear()
	elif _menu_focus_cache.is_empty() and _menu != null:
		_cache_focus_off(_menu)

func _any_menu_overlay_open() -> bool:
	for ov in [_settings, _net, _stats, _daily, _hub]:
		if ov != null and ov.visible:
			return true
	return false

func _on_menu_overlay_visibility(ov: Control) -> void:
	if ov.visible:
		_push_focus()
		_set_menu_focusable(false)
		var cb = ov.get_meta("close_button", null)
		_grab(cb if cb != null else _first_focusable(ov))
	else:
		_pop_focus()
		if not _any_menu_overlay_open():
			_set_menu_focusable(true)

func _cache_focus_off(node: Node) -> void:
	if node is Control and node.focus_mode != Control.FOCUS_NONE:
		_menu_focus_cache[node.get_instance_id()] = node.focus_mode
		node.focus_mode = Control.FOCUS_NONE
	for c in node.get_children():
		_cache_focus_off(c)


func handle_cancel() -> bool:
	if _perk != null and _perk.visible:
		perk_chosen.emit(_perk_player, "")
		return true
	if _settings != null and _settings.visible:
		close_settings()
		return true
	if _net != null and _net.visible:
		close_net()
		return true
	if _hub != null and _hub.visible:
		close_hub()
		return true
	if _stats != null and _stats.visible:
		close_stats()
		return true
	if _daily != null and _daily.visible:
		close_daily()
		return true
	if _pause != null and _pause.visible:
		resume_requested.emit()
		return true
	if _menu != null and _menu.visible and _menu_settings_panel != null \
			and _menu_settings_panel.visible:
		_menu_settings_panel.visible = false
		_refresh_mode_button()
		_layout_menu()
		_grab(_menu_settings_btn)
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("tab_next") or event.is_action_pressed("tab_prev")):
		return
	var dir := 1 if event.is_action_pressed("tab_next") else -1
	if _settings != null and _settings.visible:
		_switch_settings_tab(_neighbor_tab_key(_settings_tab_items(), _settings_active_tab, dir))
		get_viewport().set_input_as_handled()
	elif _hub != null and _hub.visible:
		hub.switch_tab(_neighbor_tab_key(hub.tab_items(), hub.active_tab, dir))
		get_viewport().set_input_as_handled()

func _neighbor_tab_key(items: Array, current: String, direction: int) -> String:
	var idx := 0
	for i in items.size():
		if String(items[i]["key"]) == current:
			idx = i
			break
	idx = (idx + direction + items.size()) % items.size()
	return String(items[idx]["key"])

const _NAV_REPEAT_DELAY := 0.35
const _NAV_REPEAT_INTERVAL := 0.1
var _nav_repeat_dir := ""
var _nav_repeat_t := 0.0

func _process(delta: float) -> void:
	var dir := ""
	if Input.is_action_pressed("ui_down"):
		dir = "ui_down"
	elif Input.is_action_pressed("ui_up"):
		dir = "ui_up"
	if dir != _nav_repeat_dir:
		_nav_repeat_dir = dir
		_nav_repeat_t = _NAV_REPEAT_DELAY
	elif dir != "":
		_nav_repeat_t -= delta
		if _nav_repeat_t <= 0.0:
			_nav_repeat_t = _NAV_REPEAT_INTERVAL
			_advance_focus(dir)

func _advance_focus(dir: String) -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null:
		return
	var np: NodePath = owner.focus_neighbor_bottom if dir == "ui_down" else owner.focus_neighbor_top
	if np.is_empty():
		return
	var nxt := owner.get_node_or_null(np)
	if nxt != null:
		nxt.grab_focus()

func _overlay_body(root: Control, title_key: String, title_fallback: String,
		sub: Control, on_close: Callable, width: float = 760.0) -> VBoxContainer:
	var title_text := I18n.t(title_key, {}, title_fallback)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width, 0)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.follow_focus = true
	center.add_child(scroll)

	var panel := UiKit.panel()
	panel.custom_minimum_size = Vector2(width, 0)
	scroll.add_child(panel)

	var box := UiKit.vbox(10)
	panel.add_child(box)

	var title := UiKit.title(title_text, 24, Cfg.UI_TEXT)
	box.add_child(title)
	box.add_child(sub)

	var body := UiKit.vbox(8)
	box.add_child(body)

	box.add_child(_pad_hint_strip())

	var close := UiKit.secondary(I18n.t("btn.close", {}, "Закрыть"))
	close.pressed.connect(on_close)
	var wrap := CenterContainer.new()
	wrap.add_child(close)
	box.add_child(wrap)

	root.set_meta("title_label", title)
	root.set_meta("title_key", title_key)
	root.set_meta("title_fallback", title_fallback)
	root.set_meta("close_button", close)
	root.set_meta("scroll", scroll)
	return body

func _resize_overlays() -> void:
	var screen := get_viewport_rect().size
	for root in [_stats, _daily, _net, _gameover]:
		if root == null or not root.has_meta("scroll"):
			continue
		var scroll: ScrollContainer = root.get_meta("scroll")
		scroll.custom_minimum_size.y = minf(screen.y * 0.86, 900.0)
	_resize_settings_scroll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_overlays()
		_layout_menu()

func _build_menu() -> void:
	main_menu = preload("res://scenes/ui/main_menu.tscn").instantiate()
	main_menu.settings = settings
	add_child(main_menu)

	_menu = main_menu
	_menu_start_btn = main_menu.get_node("%StartBtn")
	_menu_settings_btn = main_menu.get_node("%ModeSummaryBtn")
	_menu_settings_panel = main_menu.get_node("%SettingsPanel")
	_menu_settings = main_menu.get_node("%SettingsBody")
	_menu_settings_scroll = main_menu.get_node("%SettingsScroll")

	main_menu.start_pressed.connect(func(): start_requested.emit())
	main_menu.nav_pressed.connect(_on_menu_nav)

func _on_menu_nav(id: String) -> void:
	match id:
		"garage": open_garage()
		"gallery": open_gallery()
		"achievements": open_achievements()
		"daily": open_daily()
		"stats": open_stats()
		"net": open_net()
		"settings": open_settings()
		"quit": quit_requested.emit()

func _layout_menu() -> void:
	if main_menu != null:
		main_menu.layout()

func _refresh_mode_button() -> void:
	if main_menu != null:
		main_menu.refresh_mode_summary()

func show_menu() -> void:
	hide_all_overlays()
	_menu.visible = true
	_layout_menu()
	_resize_overlays()
	refresh_profile()
	_focus_stack.clear()
	_set_menu_focusable(true)
	_grab(_menu_start_btn)

func refresh_profile() -> void:
	if main_menu != null:
		main_menu.refresh_profile()

func hide_all_overlays() -> void:
	for c in [_menu, _pause, _perk, _gameover, _hub, _stats, _daily, _settings, _net]:
		if c != null:
			c.visible = false

func _build_pause() -> void:
	_pause = _make_overlay(true)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)

	var panel := UiKit.panel()
	panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(panel)

	var box := UiKit.vbox(10)
	panel.add_child(box)
	box.add_child(UiKit.title(I18n.t("pause.title", {}, "ПАУЗА"), 24))

	var resume := UiKit.primary(I18n.t("pause.resume", {}, "Продолжить"), 15)
	resume.pressed.connect(func(): resume_requested.emit())
	box.add_child(resume)
	_pause_resume_btn = resume

	var gallery := UiKit.secondary(I18n.t("pause.gallery", {}, "Галерея перков"), 13)
	gallery.custom_minimum_size = Vector2(0, 38)
	gallery.pressed.connect(func(): open_gallery())
	box.add_child(gallery)

	var settings := UiKit.secondary(I18n.t("menu.settings", {}, "⚙ Настройки"), 13)
	settings.custom_minimum_size = Vector2(0, 38)
	settings.pressed.connect(func(): open_settings())
	box.add_child(settings)

	var to_menu := UiKit.secondary(I18n.t("pause.menu", {}, "Главное меню"), 13)
	to_menu.custom_minimum_size = Vector2(0, 38)
	to_menu.pressed.connect(func(): menu_requested.emit())
	box.add_child(to_menu)

	box.add_child(_pad_hint_strip())

func show_pause() -> void:
	_pause.visible = true
	_push_focus()
	_grab(_pause_resume_btn)

func hide_pause() -> void:
	_pause.visible = false
	_pop_focus()

func _build_perk() -> void:
	_perk = _make_overlay(true)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_perk.add_child(center)

	var panel := UiKit.panel(Cfg.UI_GOLD)
	panel.custom_minimum_size = Vector2(680, 0)
	center.add_child(panel)

	var box := UiKit.vbox(12)
	panel.add_child(box)
	box.add_child(UiKit.title(I18n.t("perk.title", {}, "УРОВЕНЬ ПОВЫШЕН"), 24, Cfg.UI_GOLD))

	_perk_body = UiKit.vbox(12)
	box.add_child(_perk_body)
	box.add_child(_pad_hint_strip())

var last_perk_choices: Array = []

func show_perk_select(player, queue_left: int, rng: Rng) -> void:
	var available := []
	var equipped_cannon: String = String(player.tank.cannon_id) if player.tank != null else ""
	for id in Prof.available_perk_ids():
		if player.has_perk(id):
			continue
		if not Perks.is_perk_allowed_in_mode(id, String(settings["mode"])):
			continue
		if not Perks.is_perk_allowed_for_cannon(id, equipped_cannon):
			continue
		available.append(id)

	var guaranteed_id := ""
	var guaranteed_build := ""
	for build_id in player.build_pity.keys():
		if int(player.build_pity[build_id]) <= 0:
			continue
		var build := Perks.get_build(String(build_id))
		if build.is_empty():
			continue
		var missing := []
		for pid in (build["perks"] as Array):
			if available.has(pid):
				missing.append(pid)
		if not missing.is_empty():
			guaranteed_id = String(rng.pick(missing))
			guaranteed_build = String(build_id)
			break

	var pool := available.duplicate()
	if guaranteed_id != "":
		pool.erase(guaranteed_id)
	var slots := PERK_CHOICES - (1 if guaranteed_id != "" else 0)
	var choices := rng.shuffled(pool).slice(0, slots)
	if guaranteed_id != "":
		choices = rng.shuffled(choices + [guaranteed_id])
		player.build_pity[guaranteed_build] = int(player.build_pity[guaranteed_build]) - 1
		if int(player.build_pity[guaranteed_build]) <= 0:
			player.build_pity.erase(guaranteed_build)
	last_perk_choices = choices

	for c in _perk_body.get_children():
		c.queue_free()
	_perk_pending_id = ""

	var head := UiKit.vbox(3)
	var who := UiKit.label("%s — %s %d" % [player.name, I18n.t("perk.level", {}, "уровень"), player.session_level],
		15, Color.WHITE, true)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(who)
	var sub_text := "%s %d  ·  %s %d/%d" % [
		I18n.t("perk.profile", {}, "Профиль"), Prof.global_level,
		I18n.t("perk.equipped", {}, "экипировано"), player.perk_ids.size(), Cfg.MAX_EQUIPPED_PERKS]
	if queue_left > 0:
		sub_text += "  ·  " + I18n.t("perk.left", {"n": queue_left}, "ещё выборов: %d" % queue_left)
	head.add_child(UiKit.subtitle(sub_text))
	_perk_body.add_child(head)

	if choices.is_empty():
		var empty := UiKit.label(
			I18n.t("perk.empty.none", {}, "Пока нет открытых перков. Набирайте опыт профиля — они откроются.")
			if available.is_empty()
			else I18n.t("perk.empty.all", {}, "Все доступные перки уже экипированы."),
			12, Cfg.UI_MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(560, 0)
		_perk_body.add_child(empty)
	var first_card: Control = null
	var confirm_btn := UiKit.primary(I18n.t("perk.confirm.placeholder", {}, "Подтвердить выбор"), 14)
	confirm_btn.visible = false
	if not choices.is_empty():
		var card_buttons: Array = []
		var group := ButtonGroup.new()
		var grid := UiKit.hbox(12)
		grid.alignment = BoxContainer.ALIGNMENT_CENTER
		_perk_body.add_child(grid)
		for id in choices:
			var card := _perk_card(player, id) as Button
			card.toggle_mode = true
			card.button_group = group
			card.pressed.connect(func():
				_perk_pending_id = id
				var chosen := Perks.get_perk(id)
				confirm_btn.text = I18n.t("perk.confirm",
					{"name": I18n.dn(chosen, "name", "perk")},
					"Подтвердить: %s" % I18n.dn(chosen, "name", "perk"))
				confirm_btn.visible = true
				for c2 in card_buttons:
					c2.focus_neighbor_bottom = confirm_btn.get_path()
				confirm_btn.focus_neighbor_top = card_buttons[0].get_path()
				_grab(confirm_btn))
			if first_card == null:
				first_card = card
			card_buttons.append(card)
			grid.add_child(card)
		UiKit.chain_horizontal(card_buttons, true)
		var confirm_wrap := CenterContainer.new()
		confirm_wrap.add_child(confirm_btn)
		_perk_body.add_child(confirm_wrap)
	confirm_btn.pressed.connect(func(): perk_chosen.emit(player, _perk_pending_id))

	if not player.perk_ids.is_empty():
		var wrap := UiKit.vbox(8)
		var label := UiKit.label(I18n.t("perk.eq.label", {}, "Экипировано (нажмите, чтобы снять)"),
			10, Cfg.UI_MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wrap.add_child(label)
		var row := UiKit.hbox(8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for id in player.perk_ids.duplicate():
			var perk := Perks.get_perk(id)
			if perk.is_empty():
				continue
			var chip := UiKit.secondary("%s ✕" % I18n.dn(perk, "name", "perk"), 11)
			var chip_tex := PerkIcons.texture_of(id)
			if chip_tex != null:
				chip.icon = chip_tex
				chip.add_theme_constant_override("icon_max_width", 14)
			chip.pressed.connect(func():
				player.unequip_perk(id)
				show_perk_select(player, queue_left, rng))
			row.add_child(chip)
		wrap.add_child(row)
		_perk_body.add_child(wrap)

	var skip := UiKit.secondary(I18n.t("perk.skip", {}, "Продолжить без выбора"), 12)
	skip.pressed.connect(func(): perk_chosen.emit(player, ""))
	var skip_wrap := CenterContainer.new()
	skip_wrap.add_child(skip)
	_perk_body.add_child(skip_wrap)

	_perk_player = player
	_perk.visible = true
	_grab(first_card if first_card != null else skip)

func _perk_card(player, id: String) -> Control:
	var perk := Perks.get_perk(id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(190, 200)
	var normal := UiKit.flat(Color("#161616"), Cfg.RADIUS_MD, 2, Cfg.UI_BORDER)
	var hover := UiKit.flat(Color("#1c1c1c"), Cfg.RADIUS_MD, 2, Cfg.UI_GOLD)
	var selected := UiKit.flat(Color("#1c1c1c"), Cfg.RADIUS_MD, 3, Cfg.UI_WARN)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", selected)
	btn.add_theme_stylebox_override("hover_pressed", selected)

	var box := UiKit.vbox(4)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	var icon_wrap := CenterContainer.new()
	icon_wrap.custom_minimum_size = Vector2(0, 40)
	box.add_child(icon_wrap)
	var icon := PerkIconView.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.perk_id = id
	icon.icon_color = Cfg.UI_TEXT
	icon_wrap.add_child(icon)

	var name_label := UiKit.label(I18n.dn(perk, "name", "perk"), 12, Color.WHITE, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)

	if perk.has("active"):
		var key := "Q" if player.index == 0 else "Num -"
		var badge := UiKit.label(I18n.t("perk.active.badge", {"key": key},
			"АКТИВНАЯ · [%s]" % key), 9, Cfg.UI_GOLD, true)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(badge)

	var desc := UiKit.label(I18n.dn(perk, "desc", "perk"), 10, Cfg.UI_MUTED)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(170, 0)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(desc)
	return btn

func hide_perk_select() -> void:
	_perk.visible = false

func _build_hub() -> void:
	hub = preload("res://scenes/ui/hub.tscn").instantiate()
	add_child(hub)
	_hub = hub
	if not Engine.is_editor_hint():
		hub.visible = false
	hub.close_requested.connect(func(): close_hub())
	hub.garage_changed.connect(func(): garage_changed.emit())

func _open_hub_tab(key: String, focus_id: String = "") -> void:
	hub.open_tab(key, focus_id)

func close_hub() -> void:
	_hub.visible = false

func _refresh_hub_language() -> void:
	if hub != null:
		hub.refresh_language()

func open_gallery() -> void:
	_open_hub_tab("gallery")

func close_gallery() -> void:
	if _hub_active_tab == "gallery":
		close_hub()

var is_gallery_open: bool:
	get: return _hub != null and _hub.visible and _hub_active_tab == "gallery"


func open_garage(focus_id: String = "") -> void:
	_open_hub_tab("garage", focus_id)

func close_garage() -> void:
	if _hub_active_tab == "garage":
		close_hub()

var is_garage_open: bool:
	get: return _hub != null and _hub.visible and _hub_active_tab == "garage"


func open_stats() -> void:
	_stats_sub.text = "[center]" + I18n.t("stats.sub", {
		"lvl": Prof.global_level, "xp": Prof.global_xp, "need": Prof.xp_to_next_level(),
		"n": Prof.unlocked.size(), "total": Perks.all().size(), "money": Prof.money,
	}, "Уровень профиля [b]%d[/b] · %d / %d XP · перков %d/%d · монет [b]%d[/b] 🪙" % [
		Prof.global_level, Prof.global_xp, Prof.xp_to_next_level(),
		Prof.unlocked.size(), Perks.all().size(), Prof.money]) + "[/center]"

	for c in _stats_body.get_children():
		c.queue_free()

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 7)
	_stats_body.add_child(grid)

	for key in Prof.STAT_KEYS:
		var label_text := I18n.t("stat." + key, {}, String(Prof.STAT_LABELS.get(key, key)))
		var name_label := UiKit.label(label_text, 12, Cfg.UI_MUTED)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var value := UiKit.label(str(Prof.stats.get(key, 0)), 12, Color.WHITE, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)

	_stats.visible = true

func close_stats() -> void:
	_stats.visible = false

var is_stats_open: bool:
	get: return _stats != null and _stats.visible

func open_achievements() -> void:
	_open_hub_tab("achievements")

func close_achievements() -> void:
	if _hub_active_tab == "achievements":
		close_hub()

var is_achievements_open: bool:
	get: return _hub != null and _hub.visible and _hub_active_tab == "achievements"


func open_daily() -> void:
	var was_visible := _daily.visible
	var quests := Daily.selection()
	var done := 0
	for q in quests:
		if bool(Prof.daily_progress(String(q["id"]))["claimed"]):
			done += 1
	_daily_sub.text = "[center]" + I18n.t("daily.sub", {"done": done, "total": quests.size()},
		"Награды сбрасываются в полночь · выполнено [b]%d[/b] из %d" % [done, quests.size()]) + "[/center]"

	for c in _daily_body.get_children():
		_daily_body.remove_child(c)
		c.queue_free()

	for q in quests:
		var pr := Prof.daily_progress(String(q["id"]))
		var card := PanelContainer.new()
		var border := Cfg.UI_BORDER
		if bool(pr["claimed"]):
			border = Cfg.UI_ACCENT_DIM
		elif int(pr["current"]) >= int(pr["need"]):
			border = Color(Cfg.UI_ACCENT, 0.5)
		card.add_theme_stylebox_override("panel", UiKit.card_style(border))
		if bool(pr["claimed"]):
			card.modulate.a = 0.6

		var row := UiKit.hbox(10)
		card.add_child(row)
		row.add_child(UiKit.label(String(q["icon"]), 22))

		var info := UiKit.vbox(3)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiKit.label(I18n.dn(q, "name", "daily"), 11, Color.WHITE, true))
		info.add_child(UiKit.label(I18n.dn(q, "desc", "daily"), 9, Cfg.UI_MUTED))
		info.add_child(UiKit.label("%d / %d" % [pr["current"], pr["need"]], 9, Cfg.UI_MUTED))
		info.add_child(UiKit.progress_bar(float(pr["current"]) / float(pr["need"]), 300, 3, Cfg.UI_WARN))

		if bool(pr["claimed"]):
			row.add_child(UiKit.label(I18n.t("daily.claimed", {}, "Получено ✓"), 10, Cfg.UI_ACCENT, true))
		else:
			var claim := UiKit.small(I18n.t("daily.claim", {"reward": pr["reward"]},
				"Забрать · %d 🪙" % int(pr["reward"])))
			claim.disabled = int(pr["current"]) < int(pr["need"])
			var qid := String(q["id"])
			claim.pressed.connect(func():
				var res := Prof.claim_daily(qid)
				if bool(res["ok"]):
					daily_reward_claimed.emit(int(res["reward"]))
					open_daily())
			row.add_child(claim)
		_daily_body.add_child(card)

	_daily.visible = true
	if was_visible:
		_grab(_first_focusable(_daily_body))

func close_daily() -> void:
	_daily.visible = false

var is_daily_open: bool:
	get: return _daily != null and _daily.visible

func _build_gameover() -> void:
	_gameover = _make_overlay(true)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gameover.add_child(center)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 0)
	scroll.follow_focus = true
	center.add_child(scroll)
	_gameover.set_meta("scroll", scroll)

	_gameover_panel = UiKit.panel(Cfg.UI_DANGER)
	_gameover_panel.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(_gameover_panel)

	var box := UiKit.vbox(10)
	_gameover_panel.add_child(box)

	_gameover_title = UiKit.title(I18n.t("go.defeat", {}, "ПОРАЖЕНИЕ"), 26, Cfg.UI_DANGER)
	box.add_child(_gameover_title)

	_gameover_body = UiKit.vbox(8)
	box.add_child(_gameover_body)

	var actions := UiKit.hbox(10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	var replay := UiKit.primary(I18n.t("go.replay", {}, "Ещё раз"), 14)
	replay.pressed.connect(func(): restart_requested.emit())
	actions.add_child(replay)
	_gameover_replay_btn = replay
	var to_menu := UiKit.secondary(I18n.t("go.menu", {}, "В меню"), 13)
	to_menu.pressed.connect(func(): menu_requested.emit())
	actions.add_child(to_menu)
	box.add_child(_pad_hint_strip())

func show_game_over(result: Dictionary, world: World, hotseat: bool) -> void:
	_last_gameover = {"result": result, "world": world, "hotseat": hotseat}
	var win := bool(result["victory"])
	_gameover.visible = true
	_gameover_panel.border_color = Cfg.UI_ACCENT if win else Cfg.UI_DANGER
	_gameover_panel.queue_redraw()

	var winner_index := int(result["winner_player_index"])
	if hotseat and winner_index >= 0:
		var winner = world.players[winner_index] if winner_index < world.players.size() else null
		var wname: String = winner.name.to_upper() if winner != null else I18n.t("go.player", {}, "ИГРОК")
		_gameover_title.text = I18n.t("go.won", {"name": wname}, "ПОБЕДИЛ %s" % wname)
	else:
		_gameover_title.text = I18n.t("go.victory", {}, "ПОБЕДА!") if win else I18n.t("go.defeat", {}, "ПОРАЖЕНИЕ")
	_gameover_title.add_theme_color_override("font_color", Cfg.UI_ACCENT if win else Cfg.UI_DANGER)

	for c in _gameover_body.get_children():
		c.queue_free()

	var reason := UiKit.label(String(result["reason"]), 13, Cfg.UI_TEXT)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gameover_body.add_child(reason)

	var diff: Dictionary = Cfg.DIFFICULTY[world.difficulty_key]
	var mode_name := I18n.t("mode." + world.mode, {}, String(Cfg.MODES[world.mode]["name"]))
	var lvl_num := int(world.level["requested_level"])
	var lvl_text := I18n.t("go.randomLevel", {}, "случайный") if lvl_num < 0 else str(lvl_num)
	var meta := UiKit.label(I18n.t("go.meta",
		{"mode": mode_name, "diff": I18n.t("diff." + world.difficulty_key, {}, String(diff["name"])), "lvl": lvl_text},
		"%s · %s · уровень %s" % [mode_name, diff["name"], lvl_text]), 11, Cfg.UI_MUTED)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gameover_body.add_child(meta)

	var players_row := UiKit.hbox(12)
	players_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_gameover_body.add_child(players_row)
	for player in world.players:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(210, 0)
		card.add_theme_stylebox_override("panel", UiKit.card_style())
		var box := UiKit.vbox(2)
		card.add_child(box)
		box.add_child(UiKit.label(player.name, 13, Color.WHITE, true))
		box.add_child(UiKit.label("%s   %s" % [
			I18n.t("go.frags", {"n": player.kills}, "Фраги: %d" % player.kills),
			I18n.t("go.deaths", {"n": player.deaths}, "Смерти: %d" % player.deaths)], 11, Cfg.UI_MUTED))
		if world.mode == "ctf":
			box.add_child(UiKit.label(I18n.t("go.captures", {"n": player.captures},
				"Захваты флага: %d" % player.captures), 11, Cfg.UI_MUTED))
		box.add_child(UiKit.label(I18n.t("go.score", {"n": player.score},
			"Счёт: %d" % player.score), 11, Cfg.UI_MUTED))
		box.add_child(UiKit.label(I18n.t("go.damage", {"n": int(round(player.damage_dealt))},
			"Урона нанесено: %d" % int(round(player.damage_dealt))), 11, Cfg.UI_MUTED))
		box.add_child(UiKit.label(I18n.t("go.sessionLevel", {"n": player.session_level},
			"Уровень в партии: %d" % player.session_level), 11, Cfg.UI_MUTED))
		if player.perk_ids.is_empty():
			box.add_child(UiKit.label("—", 15, Cfg.UI_GOLD))
		else:
			var icons := HFlowContainer.new()
			icons.add_theme_constant_override("h_separation", 4)
			icons.add_theme_constant_override("v_separation", 4)
			for id in player.perk_ids:
				icons.add_child(PerkIcons.make_view(String(id), 20, Cfg.UI_GOLD))
			box.add_child(icons)
		players_row.add_child(card)

	var profile_line := UiKit.label(I18n.t("go.profile", {
		"lvl": Prof.global_level, "xp": Prof.global_xp, "need": Prof.xp_to_next_level(),
		"n": Prof.unlocked.size(), "total": Perks.all().size(),
	}, "Профиль: уровень %d, %d/%d XP, перков %d/%d" % [
		Prof.global_level, Prof.global_xp, Prof.xp_to_next_level(),
		Prof.unlocked.size(), Perks.all().size()]), 11, Cfg.UI_GOLD)
	profile_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gameover_body.add_child(profile_line)

	var rw: Dictionary = result["rewards"]
	var total: int = int(rw["kills"]) + int(rw["captures"]) + int(rw["wins"])
	var parts := []
	if int(rw["kills"]) > 0:
		parts.append(I18n.t("go.reward.kills", {"n": rw["kills"]}, "убийства %d" % int(rw["kills"])))
	if int(rw["captures"]) > 0:
		parts.append(I18n.t("go.reward.captures", {"n": rw["captures"]}, "флаги %d" % int(rw["captures"])))
	if int(rw["wins"]) > 0:
		parts.append(I18n.t("go.reward.wins", {"n": rw["wins"]}, "победа %d" % int(rw["wins"])))
	var reward_text := I18n.t("go.reward", {"total": total}, "Награда: +%d 🪙" % total)
	if not parts.is_empty():
		reward_text += " (" + " + ".join(parts) + ")"
	var reward_label := UiKit.label(reward_text, 13, Cfg.UI_GOLD)
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gameover_body.add_child(reward_label)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	_gameover_body.add_child(grid)
	for h in [I18n.t("go.table.rank", {}, "#"), I18n.t("go.table.tank", {}, "Танк"),
			I18n.t("go.table.kills", {}, "Фраги"), I18n.t("go.table.deaths", {}, "Смерти")]:
		grid.add_child(UiKit.label(String(h).to_upper(), 10, Cfg.UI_MUTED))
	var rows := world.scoreboard().slice(0, 8)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var color: Color = Cfg.UI_ACCENT if bool(r["is_human"]) else Cfg.UI_TEXT
		grid.add_child(UiKit.label(str(i + 1), 12, color))
		grid.add_child(UiKit.label(String(r["name"]), 12, color))
		grid.add_child(UiKit.label(str(r["kills"]), 12, color))
		grid.add_child(UiKit.label(str(r["deaths"]), 12, color))

	_grab(_gameover_replay_btn)

func hide_game_over() -> void:
	_gameover.visible = false

func _on_language_changed() -> void:
	for root in [_stats, _daily, _net, _gameover]:
		if root == null or not root.has_meta("title_key"):
			continue
		var label := root.get_meta("title_label") as Label
		if label != null:
			label.text = I18n.t(String(root.get_meta("title_key")), {},
				String(root.get_meta("title_fallback")))
		var btn := root.get_meta("close_button") as Button
		if btn != null:
			btn.text = I18n.t("btn.close", {}, "Закрыть")
	_refresh_hub_language()
	_refresh_settings_language()
	_refresh_screens()

func _refresh_screens() -> void:
	var was_menu := _menu.visible
	var settings_open := _menu_settings_panel.visible
	_menu.visible = false
	_menu.queue_free()
	_build_menu()
	move_child(_menu, 0)
	_menu_settings_panel.visible = settings_open
	_refresh_mode_button()
	_menu.visible = was_menu
	_layout_menu()
	_layout_menu.call_deferred()

	var pause_open := _pause.visible
	_pause.visible = false
	_pause.queue_free()
	_build_pause()
	_pause.visible = pause_open

	refresh_profile()
	if is_settings_open:
		open_settings()
	if is_stats_open:
		open_stats()
	if is_daily_open:
		open_daily()
	if _net != null and _net.visible:
		_refresh_net()
	if not _last_gameover.is_empty() and _gameover.visible:
		show_game_over(_last_gameover["result"], _last_gameover["world"], _last_gameover["hotseat"])

func _on_theme_changed() -> void:
	var hub_open := _hub.visible
	var hub_tab := _hub_active_tab
	_hub.visible = false
	_hub.queue_free()
	_build_hub()
	if hub_open:
		_open_hub_tab(hub_tab)
	_refresh_screens()

func _build_settings_shell() -> void:
	_settings = _make_overlay(true)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.add_child(center)

	var panel := UiKit.panel()
	panel.custom_minimum_size = Vector2(700, 0)
	center.add_child(panel)

	var box := UiKit.vbox(10)
	panel.add_child(box)

	_settings_tabs_row = HBoxContainer.new()
	box.add_child(_settings_tabs_row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)

	_settings_body = UiKit.vbox(8)
	_settings_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_settings_body)

	box.add_child(_pad_hint_strip())

	var close := UiKit.secondary(I18n.t("btn.close", {}, "Закрыть"))
	close.pressed.connect(func(): close_settings())
	var wrap := CenterContainer.new()
	wrap.add_child(close)
	box.add_child(wrap)

	_settings.set_meta("close_button", close)
	_settings.set_meta("scroll", scroll)

	_rebuild_settings_tabs()

func _settings_tab_items() -> Array:
	return [
		{"key": "general", "label": I18n.t("settings.tab.general", {}, "Общие")},
		{"key": "sound", "label": I18n.t("settings.tab.sound", {}, "Звук")},
		{"key": "graphics", "label": I18n.t("settings.tab.graphics", {}, "Графика")},
		{"key": "controls", "label": I18n.t("settings.tab.controls", {}, "Управление")},
	]

func _rebuild_settings_tabs() -> void:
	var idx := _settings_tabs_row.get_index()
	var parent := _settings_tabs_row.get_parent()
	var new_row := UiKit.plain_tabs(_settings_tab_items(), _settings_active_tab,
		func(key): _switch_settings_tab(key))
	parent.add_child(new_row)
	parent.move_child(new_row, idx)
	_settings_tabs_row.queue_free()
	_settings_tabs_row = new_row

func _switch_settings_tab(key: String) -> void:
	_settings_active_tab = key
	_rebuild_settings_tabs()
	_fill_settings_tab(key)
	_grab(_find_tab_button(_settings_tabs_row, key))

func _fill_settings_tab(key: String) -> void:
	for c in _settings_body.get_children():
		c.queue_free()
	match key:
		"general": _build_general_tab()
		"sound": _build_sound_tab()
		"graphics": _build_graphics_tab()
		"controls": _build_controls_tab()

	UiKit.chain_horizontal(_settings_tabs_row.get_children(), true)
	for row in _settings_body.get_children():
		if row.has_meta("focus_flow"):
			var flow: Control = row.get_meta("focus_flow")
			UiKit.chain_horizontal(flow.get_children(), true)
	UiKit.chain_vertical([_settings_tabs_row] + _settings_body.get_children())
	_resize_settings_scroll()

const _TABBED_SHELL_HEADER_H := 90.0

func _resize_settings_scroll() -> void:
	if _settings == null or not _settings.has_meta("scroll"):
		return
	var scroll: ScrollContainer = _settings.get_meta("scroll")
	var screen := get_viewport_rect().size
	scroll.custom_minimum_size.y = maxf(minf(screen.y * 0.86, 900.0) - _TABBED_SHELL_HEADER_H, 200.0)

func open_settings() -> void:
	var was_visible := _settings.visible
	_settings.visible = true
	_switch_settings_tab(_settings_active_tab)
	if was_visible:
		_grab(_first_focusable(_settings_body))

func _refresh_settings_language() -> void:
	if _settings == null:
		return
	var btn := _settings.get_meta("close_button") as Button
	if btn != null:
		btn.text = I18n.t("btn.close", {}, "Закрыть")

func _build_general_tab() -> void:
	var theme_keys := ["noir", "military", "scifi"]
	var theme_labels := [
		I18n.t("theme.noir", {}, "Нуар"),
		I18n.t("theme.military", {}, "Военное досье"),
		I18n.t("theme.scifi", {}, "Sci-Fi"),
	]
	var idx := maxi(0, theme_keys.find(Sets.ui_theme))
	_settings_body.add_child(UiKit.choice_row(
		I18n.t("set.theme", {}, "Тема интерфейса"), theme_labels, idx,
		func(v: int):
			Sets.ui_theme = theme_keys[v]
			Sets.save()
			Cfg.apply_theme(Sets.ui_theme)
			_on_theme_changed()))

	var lang_row := UiKit.hbox(8)
	var lang_label := UiKit.label(I18n.t("set.lang", {}, "Язык интерфейса"), 12, Cfg.UI_TEXT)
	lang_label.custom_minimum_size = Vector2(178, 0)
	lang_row.add_child(lang_label)
	var lang_btn := UiKit.secondary(
		I18n.t("menu.lang.ru", {}, "🌐 English") if I18n.lang == "ru"
			else I18n.t("menu.lang.en", {}, "🌐 Русский"), 13)
	lang_btn.pressed.connect(func(): I18n.toggle_lang())
	lang_row.add_child(lang_btn)
	_settings_body.add_child(lang_row)

	var reset := UiKit.danger(I18n.t("settings.reset", {}, "Сбросить настройки"), 12)
	reset.pressed.connect(func():
		Sets.reset()
		_switch_settings_tab("general"))
	var wrap := CenterContainer.new()
	wrap.add_child(reset)
	_settings_body.add_child(wrap)

	var reset_progress := UiKit.danger(I18n.t("menu.reset", {}, "Сбросить прогресс"), 12)
	reset_progress.pressed.connect(func():
		_confirm.dialog_text = I18n.t("confirm.reset", {},
			"Сбросить весь прогресс профиля? Открытые перки будут потеряны.")
		_confirm.popup_centered())
	var progress_wrap := CenterContainer.new()
	progress_wrap.add_child(reset_progress)
	_settings_body.add_child(progress_wrap)

func _build_graphics_tab() -> void:
	_settings_body.add_child(UiKit.section(I18n.t("set.screen", {}, "Экран"), Cfg.UI_MUTED))

	_settings_body.add_child(UiKit.choice_row(
		I18n.t("set.mode", {}, "Режим экрана"),
		[I18n.t("set.mode.window", {}, "Окно"),
			I18n.t("set.mode.full", {}, "Полный экран"),
			I18n.t("set.mode.borderless", {}, "Без рамки")],
		Sets.display_mode,
		func(v: int):
			Sets.display_mode = v
			Sets.apply_video()
			Sets.save()
			_switch_settings_tab.call_deferred("graphics")))

	var res_list := Sets.available_resolutions()
	var labels := []
	var current := 0
	for i in res_list.size():
		var r: Vector2i = res_list[i]
		labels.append("%d×%d" % [r.x, r.y])
		if r == Sets.resolution:
			current = i
	var res_row := UiKit.choice_row(I18n.t("set.resolution", {}, "Разрешение"),
		labels, current,
		func(v: int):
			Sets.resolution = res_list[v]
			Sets.apply_video()
			Sets.save())
	if Sets.display_mode != Sets.MODE_WINDOWED:
		res_row.modulate.a = 0.4
	_settings_body.add_child(res_row)

	_settings_body.add_child(UiKit.switch_row(
		I18n.t("set.vsync", {}, "Вертикальная синхронизация"), Sets.vsync,
		func(v: bool):
			Sets.vsync = v
			Sets.apply_video()
			Sets.save()))

	_settings_body.add_child(UiKit.section(I18n.t("set.fxsection", {}, "Эффекты"), Cfg.UI_MUTED))

	_settings_body.add_child(UiKit.choice_row(
		I18n.t("set.fx", {}, "Спецэффекты"),
		[I18n.t("fx.off", {}, "выкл"),
			I18n.t("fx.medium", {}, "средне"),
			I18n.t("fx.high", {}, "высоко")],
		Sets.fx_quality,
		func(v: int):
			Sets.fx_quality = v
			Sets.save()))
	_settings_body.add_child(UiKit.label(
		I18n.t("set.fx.hint", {}, "Цветокоррекция, свечение и затенение у стен. Применяется со следующей партии."),
		9, Cfg.UI_MUTED))

	_settings_body.add_child(UiKit.switch_row(
		I18n.t("set.weather", {}, "Погода (дождь, туман, гроза)"), Sets.weather_effects,
		func(v: bool):
			Sets.weather_effects = v
			Sets.save()))
	_settings_body.add_child(UiKit.slider_row(
		I18n.t("set.weather.power", {}, "Сила погоды"), Sets.weather_intensity,
		func(v: float):
			Sets.weather_intensity = v
			Sets.save()))
	_settings_body.add_child(UiKit.switch_row(
		I18n.t("set.daynight", {}, "Цикл дня и ночи"), Sets.day_night,
		func(v: bool):
			Sets.day_night = v
			Sets.save()))
	_settings_body.add_child(UiKit.switch_row(
		I18n.t("set.wrecks", {}, "Горящие остовы"), Sets.wrecks,
		func(v: bool):
			Sets.wrecks = v
			Sets.save()))
	_settings_body.add_child(UiKit.slider_row(
		I18n.t("set.shake", {}, "Тряска экрана"), Sets.screen_shake,
		func(v: float):
			Sets.screen_shake = v
			Sets.save()))

const _P1_KEY_ACTIONS := ["p1_up", "p1_down", "p1_left", "p1_right",
	"p1_fire", "p1_mine", "p1_dash", "p1_airstrike", "p1_ability"]
const _P2_KEY_ACTIONS := ["p2_up", "p2_down", "p2_left", "p2_right",
	"p2_turret_left", "p2_turret_right", "p2_fire", "p2_mine", "p2_dash", "p2_ability"]

func _key_action_label(action_id: String) -> String:
	match action_id:
		"p1_up", "p2_up": return I18n.t("key.up", {}, "Вперёд")
		"p1_down", "p2_down": return I18n.t("key.down", {}, "Назад")
		"p1_left", "p2_left": return I18n.t("key.left", {}, "Влево")
		"p1_right", "p2_right": return I18n.t("key.right", {}, "Вправо")
		"p1_fire", "p2_fire": return I18n.t("key.fire", {}, "Огонь")
		"p1_mine", "p2_mine": return I18n.t("key.mine", {}, "Мина")
		"p1_dash", "p2_dash": return I18n.t("key.dash", {}, "Рывок-таран")
		"p1_ability", "p2_ability": return I18n.t("key.ability", {}, "Способность перка")
		"p1_airstrike": return I18n.t("key.airstrike", {}, "Авиаудар")
		"p2_turret_left": return I18n.t("key.turretLeft", {}, "Башня влево")
		"p2_turret_right": return I18n.t("key.turretRight", {}, "Башня вправо")
	return action_id

func _assign_key(action_id: String, keycode: int) -> void:
	for other_id in Ctl.DEFAULT_KEYS.keys():
		if other_id == action_id:
			continue
		if Sets.key_for(other_id) == keycode:
			if is_instance_valid(_settings_key_status):
				_settings_key_status.text = I18n.t("set.key.conflict",
					{"key": OS.get_keycode_string(keycode), "action": _key_action_label(other_id)},
					"Клавиша «%s» уже занята: %s" % [OS.get_keycode_string(keycode), _key_action_label(other_id)])
			return
	Sets.set_key(action_id, keycode)
	_switch_settings_tab("controls")

func _build_controls_tab() -> void:
	var devices := [
		[Sets.DEV_AUTO, I18n.t("dev.auto", {}, "Авто")],
		[Sets.DEV_KBM, I18n.t("dev.kbm", {}, "Клавиатура и мышь")],
		[Sets.DEV_KEYS, I18n.t("dev.keys", {}, "Только клавиатура")],
	]
	for pad in Sets.pads():
		devices.append(["pad%d" % int(pad["id"]),
			"%s %d: %s" % [I18n.t("dev.pad", {}, "Геймпад"), int(pad["id"]) + 1,
				String(pad["name"])]])
	for cur in [Sets.p1_device, Sets.p2_device]:
		var known := false
		for d in devices:
			if String(d[0]) == cur:
				known = true
		if not known and String(cur).begins_with("pad"):
			devices.append([cur, "%s %d: %s" % [I18n.t("dev.pad", {}, "Геймпад"),
				int(String(cur).substr(3)) + 1, I18n.t("dev.pad.off", {}, "не подключён")]])
	var labels := []
	for d in devices:
		labels.append(String(d[1]))

	for who in [0, 1]:
		var current: String = Sets.p1_device if who == 0 else Sets.p2_device
		var idx := 0
		for i in devices.size():
			if String(devices[i][0]) == current:
				idx = i
		_settings_body.add_child(UiKit.choice_row(
			I18n.t("set.dev1", {}, "Игрок 1") if who == 0
				else I18n.t("set.dev2", {}, "Игрок 2"),
			labels, idx,
			func(v: int):
				var id: String = String(devices[v][0])
				if who == 0:
					Sets.p1_device = id
				else:
					Sets.p2_device = id
				Sets.save()))

	_settings_body.add_child(UiKit.section(I18n.t("set.keys.p1", {}, "Клавиши — Игрок 1"), Cfg.UI_MUTED))
	for action in _P1_KEY_ACTIONS:
		_settings_body.add_child(UiKit.keybind_row(_key_action_label(action), Sets.key_for(action),
			func(k: int): _assign_key(action, k)))

	_settings_body.add_child(UiKit.section(I18n.t("set.keys.p2", {}, "Клавиши — Игрок 2"), Cfg.UI_MUTED))
	for action in _P2_KEY_ACTIONS:
		_settings_body.add_child(UiKit.keybind_row(_key_action_label(action), Sets.key_for(action),
			func(k: int): _assign_key(action, k)))

	_settings_key_status = UiKit.label("", 10, Cfg.UI_WARN)
	_settings_body.add_child(_settings_key_status)

	var reset_keys := UiKit.danger(I18n.t("set.keys.reset", {}, "Сбросить клавиши"), 12)
	reset_keys.pressed.connect(func():
		Sets.custom_keys.clear()
		Sets.save()
		_switch_settings_tab("controls"))
	var reset_keys_wrap := CenterContainer.new()
	reset_keys_wrap.add_child(reset_keys)
	_settings_body.add_child(reset_keys_wrap)

	if Sets.pads().is_empty():
		_settings_body.add_child(UiKit.label(
			I18n.t("set.pad.none", {}, "Геймпад не найден. Подключите его и откройте настройки заново."),
			9, Cfg.UI_MUTED))
	else:
		_settings_body.add_child(_pad_hint_strip())
		_settings_body.add_child(UiKit.slider_row(
			I18n.t("set.pad.deadzone", {}, "Мёртвая зона стиков"),
			Sets.pad_deadzone / MAX_DEADZONE,
			func(v: float):
				Sets.pad_deadzone = v * MAX_DEADZONE
				Sets.save()))
		_settings_body.add_child(UiKit.label(
			I18n.t("set.pad.deadzone.hint", {}, "Ниже этого порога стик считается отпущенным. Слишком малая зона — танк едет сам."),
			9, Cfg.UI_MUTED))
		_settings_body.add_child(UiKit.switch_row(
			I18n.t("set.pad.vibration", {}, "Отдача геймпада"), Sets.pad_vibration,
			func(v: bool):
				Sets.pad_vibration = v
				Sets.save()))
		_settings_body.add_child(UiKit.switch_row(
			I18n.t("set.pad.aimassist", {}, "Автоприцел на геймпаде"), Sets.pad_aim_assist,
			func(v: bool):
				Sets.pad_aim_assist = v
				Sets.save()))
		_settings_body.add_child(UiKit.label(
			I18n.t("set.pad.aimassist.hint", {}, "Мягкая доводка прицела к ближайшему врагу, пока целишься правым стиком."),
			9, Cfg.UI_MUTED))

func _build_sound_tab() -> void:
	_settings_body.add_child(UiKit.slider_row(
		I18n.t("set.master", {}, "Общая громкость"), Sets.master_volume,
		func(v: float):
			Sets.master_volume = v
			Sets.apply_audio()
			Sets.save()))
	_settings_body.add_child(UiKit.slider_row(
		I18n.t("set.sfx", {}, "Звуковые эффекты"), Sets.sfx_volume,
		func(v: float):
			Sets.sfx_volume = v
			Sets.apply_audio()
			Sfx.play("pickup")
			Sets.save()))
	_settings_body.add_child(UiKit.slider_row(
		I18n.t("set.music", {}, "Музыка"), Sets.music_volume,
		func(v: float):
			Sets.music_volume = v
			Sets.apply_audio()
			Sets.save()))
	_settings_body.add_child(UiKit.label(
		I18n.t("set.music.hint", {}, "Боевой саундтрек игра собирает сама, как и остальной звук. Играет в бою и приглушается на паузе."),
		9, Cfg.UI_MUTED))

func close_settings() -> void:
	_settings.visible = false

var is_settings_open: bool:
	get: return _settings != null and _settings.visible

func open_net() -> void:
	if not Net.lobby_changed.is_connected(_refresh_net):
		Net.lobby_changed.connect(_refresh_net)
		Net.net_error.connect(_on_net_error)
		Net.countdown_changed.connect(_on_countdown_changed)
		Net.lobby_list_updated.connect(_refresh_net)
	_net.visible = true
	_refresh_net()

func close_net() -> void:
	_net.visible = false
	_net_mode = ""

var is_net_open: bool:
	get: return _net != null and _net.visible

func _on_net_error(text: String) -> void:
	_net_error = text
	_refresh_net()

func _on_countdown_changed(seconds_left: int) -> void:
	_refresh_net()
	if seconds_left == 0 and Net.role == "host":
		start_requested.emit()

func _refresh_net() -> void:
	if _net == null or not _net.visible:
		return
	_net_sub.text = "[center]" + I18n.t("net.sub", {},
		"Хост считает партию целиком, остальные шлют ввод и получают состояние") + "[/center]"
	for c in _net_body.get_children():
		c.queue_free()

	if _net_error != "":
		_net_body.add_child(UiKit.label(_net_error, 12, Cfg.UI_DANGER))

	if Net.role == "":
		_build_net_offline()
	else:
		_build_net_lobby()

func _build_net_offline() -> void:
	var steam_ok := NetTransport.SteamTransport.new().available()

	var name_row := UiKit.hbox(8)
	name_row.add_child(UiKit.label(I18n.t("net.name", {}, "Имя"), 12, Cfg.UI_TEXT))
	var name_edit := LineEdit.new()
	name_edit.text = Net.my_name
	name_edit.custom_minimum_size = Vector2(220, 30)
	name_edit.text_changed.connect(func(t: String): Net.my_name = t)
	name_row.add_child(name_edit)
	_net_body.add_child(name_row)

	if not Net.pending_invite.is_empty():
		var who := String(Net.pending_invite.get("name", ""))
		_net_body.add_child(UiKit.label(
			I18n.t("net.invite.incoming", {"name": who}, "%s зовёт в игру" % who),
			12, Cfg.UI_ACCENT))
		var accept_btn := UiKit.primary(I18n.t("net.invite.accept", {}, "Принять"), 13)
		accept_btn.disabled = Net.lobby_pending != ""
		accept_btn.pressed.connect(func():
			_net_error = ""
			Net.accept_pending_invite()
			_refresh_net())
		_net_body.add_child(accept_btn)

	if Net.lobby_pending != "":
		_net_body.add_child(UiKit.label(
			I18n.t("net.room.creating", {}, "Создаём…") if Net.lobby_pending == "host"
				else I18n.t("net.room.searching", {}, "Подключаемся…"), 11, Cfg.UI_MUTED))

	if not steam_ok:
		_net_body.add_child(UiKit.label(
			I18n.t("net.err.noSteam", {}, "Нужен клиент Steam — сетевая игра недоступна"),
			11, Cfg.UI_DANGER))
		return

	match _net_mode:
		"create":
			_build_net_create()
		"join":
			_build_net_join()
		_:
			_build_net_choice()

func _build_net_choice() -> void:
	var create_btn := UiKit.primary(I18n.t("net.create", {}, "Создать"), 15)
	create_btn.pressed.connect(func():
		_net_error = ""
		_net_room_name = ""
		_net_mode = "create"
		_refresh_net())
	_net_body.add_child(create_btn)

	var join_btn := UiKit.primary(I18n.t("net.join", {}, "Присоединиться"), 15)
	join_btn.pressed.connect(func():
		_net_error = ""
		_net_search = ""
		_net_mode = "join"
		Net.refresh_lobby_list()
		_refresh_net())
	_net_body.add_child(join_btn)

func _build_net_create() -> void:
	var back_btn := UiKit.small(I18n.t("net.back", {}, "Назад"))
	back_btn.pressed.connect(func():
		_net_mode = ""
		_refresh_net())
	_net_body.add_child(back_btn)

	var name_row := UiKit.hbox(8)
	name_row.add_child(UiKit.label(I18n.t("net.room.name", {}, "Название комнаты"), 12, Cfg.UI_TEXT))
	var room_edit := LineEdit.new()
	room_edit.text = _net_room_name
	room_edit.placeholder_text = I18n.t("net.room.placeholder", {}, "Например: Игра Дениса")
	room_edit.custom_minimum_size = Vector2(260, 30)
	room_edit.text_changed.connect(func(t: String): _net_room_name = t)
	name_row.add_child(room_edit)
	_net_body.add_child(name_row)

	var host_btn := UiKit.primary(I18n.t("net.create.confirm", {}, "Создать лобби"), 14)
	host_btn.disabled = Net.lobby_pending != ""
	host_btn.pressed.connect(func():
		_net_error = ""
		Net.host_lobby(_net_room_name)
		_refresh_net())
	_net_body.add_child(host_btn)

func _build_net_join() -> void:
	var back_btn := UiKit.small(I18n.t("net.back", {}, "Назад"))
	back_btn.pressed.connect(func():
		_net_mode = ""
		_refresh_net())
	_net_body.add_child(back_btn)

	var search_row := UiKit.hbox(8)
	search_row.add_child(UiKit.label(I18n.t("net.search", {}, "Поиск"), 12, Cfg.UI_TEXT))
	var search_edit := LineEdit.new()
	search_edit.text = _net_search
	search_edit.placeholder_text = I18n.t("net.search.placeholder", {}, "Имя игрока или комнаты")
	search_edit.custom_minimum_size = Vector2(260, 30)
	search_row.add_child(search_edit)
	_net_body.add_child(search_row)

	_net_body.add_child(UiKit.section(I18n.t("net.browser.title", {}, "Доступные лобби"), Cfg.UI_ACCENT))
	var refresh_btn := UiKit.small(I18n.t("net.browser.refresh", {}, "Обновить"))
	refresh_btn.pressed.connect(func():
		Net.refresh_lobby_list()
		_refresh_net())
	_net_body.add_child(refresh_btn)

	var list_box := UiKit.vbox(6)
	_net_body.add_child(list_box)

	var render_list := func():
		for c in list_box.get_children():
			c.queue_free()
		var q := _net_search.strip_edges().to_lower()
		var shown := 0
		for entry in Net.lobby_browser_results:
			var host_name := String(entry.get("host_name", ""))
			var room := String(entry.get("room_name", ""))
			if q != "" and host_name.to_lower().find(q) < 0 and room.to_lower().find(q) < 0:
				continue
			shown += 1
			var row := UiKit.hbox(8)
			var members := int(entry.get("members", 0))
			var max_members := int(entry.get("max_members", 0))
			row.add_child(UiKit.label(
				"%s · %s · %s" % [room, host_name,
					I18n.t("net.browser.players", {"n": members, "max": max_members}, "%d/%d" % [members, max_members])],
				11, Cfg.UI_TEXT))
			var lobby_id := int(entry.get("id", 0))
			var join_row_btn := UiKit.small(I18n.t("net.browser.join", {}, "Войти"))
			join_row_btn.disabled = Net.lobby_pending != ""
			join_row_btn.pressed.connect(func():
				_net_error = ""
				Net.join_lobby_id(lobby_id)
				_refresh_net())
			row.add_child(join_row_btn)
			list_box.add_child(row)
		if shown == 0:
			list_box.add_child(UiKit.label(I18n.t("net.browser.empty", {}, "Лобби не найдены"), 11, Cfg.UI_MUTED))

	search_edit.text_changed.connect(func(t: String):
		_net_search = t
		render_list.call())
	render_list.call()

func _build_net_lobby() -> void:
	var connecting := Net.role == "client" and Net.lobby.is_empty()
	var role_text := I18n.t("net.role.host", {}, "Вы хост")
	if connecting:
		role_text = I18n.t("net.role.connecting", {}, "Подключаемся к хосту…")
	elif Net.role != "host":
		role_text = I18n.t("net.role.client", {}, "Вы подключены")
	_net_body.add_child(UiKit.section(role_text, Cfg.UI_ACCENT))

	if Net.role == "host" and Net.lobby.size() < Net.MAX_LOBBY:
		if Net._steam_lobby_id != 0:
			_net_body.add_child(UiKit.label(
				"%s: %s" % [I18n.t("net.room.label", {}, "Комната"), Net.room_name],
				12, Cfg.UI_TEXT))
			var inv_btn := UiKit.primary(I18n.t("net.invite.friend", {}, "Пригласить друга"), 13)
			inv_btn.pressed.connect(func(): Net.invite_overlay())
			_net_body.add_child(inv_btn)
			var sid := NetTransport.SteamTransport.my_steam_id()
			if sid > 0:
				_net_body.add_child(UiKit.label(
					I18n.t("net.steam.mine", {}, "Ваш SteamID"), 11, Cfg.UI_MUTED))
				var sid_row := UiKit.hbox(8)
				var sid_edit := LineEdit.new()
				sid_edit.text = str(sid)
				sid_edit.editable = false
				sid_edit.custom_minimum_size = Vector2(220, 30)
				sid_row.add_child(sid_edit)
				_net_body.add_child(sid_row)
		else:
			_net_body.add_child(UiKit.label(
				I18n.t("net.host.hint", {}, "Порт 8124. В локальной сети остальным нужен ваш адрес, через интернет — проброс порта."),
				9, Cfg.UI_MUTED))

	if Net.lobby.is_empty():
		_net_body.add_child(UiKit.label(I18n.t("net.waiting", {}, "Соединение…"), 12, Cfg.UI_MUTED))
		if connecting:
			_net_body.add_child(UiKit.label(
				I18n.t("net.waiting.hint", {}, "Может занять несколько секунд. Если долго не проходит — сеть между компьютерами не пропускает игру, попробуйте «Отключиться» и другой способ."),
				9, Cfg.UI_MUTED))
	for peer_id in Net.lobby.keys():
		var info: Dictionary = Net.lobby[peer_id]
		var row := UiKit.hbox(8)
		var mark := "★" if int(peer_id) == 1 else "•"
		row.add_child(UiKit.label("%s %s" % [mark, String(info.get("name", I18n.t("net.player", {}, "Игрок")))],
			12, Cfg.UI_TEXT))
		var pal := Cfg.team_palette(String(info.get("color_key", "p1")))
		var chip := ColorRect.new()
		chip.color = pal["body"]
		chip.custom_minimum_size = Vector2(18, 14)
		row.add_child(chip)
		if int(peer_id) != 1:
			row.add_child(UiKit.label(
				"✓" if bool(info.get("ready", false)) else "…", 12,
				Cfg.UI_ACCENT if bool(info.get("ready", false)) else Cfg.UI_MUTED))
		_net_body.add_child(row)

	if Net.countdown_left >= 0:
		_net_body.add_child(UiKit.label(
			I18n.t("net.countdown.title", {}, "Матч начинается…"), 12, Cfg.UI_MUTED))
		var big := UiKit.label(str(Net.countdown_left), 48, Cfg.UI_TEXT, true)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_net_body.add_child(big)
		if Net.role == "host":
			var cancel_btn := UiKit.secondary(I18n.t("net.countdown.cancel", {}, "Отмена"), 12)
			cancel_btn.pressed.connect(func(): Net.host_cancel_countdown())
			_net_body.add_child(cancel_btn)
	elif Net.role == "host":
		var enough := Net.lobby.size() >= Net.MAX_LOBBY
		var ready := Net.all_guests_ready()
		var start_btn := UiKit.primary(I18n.t("net.start", {}, "Начать партию"), 13)
		start_btn.disabled = not enough or not ready
		start_btn.pressed.connect(func(): Net.host_begin_countdown())
		_net_body.add_child(start_btn)
		if not enough:
			_net_body.add_child(UiKit.label(
				I18n.t("net.wait.player", {}, "Ждём второго игрока…"), 9, Cfg.UI_MUTED))
		elif not ready:
			_net_body.add_child(UiKit.label(
				I18n.t("net.wait.ready", {}, "Ждём готовности игрока…"), 9, Cfg.UI_MUTED))
		else:
			_net_body.add_child(UiKit.label(
				I18n.t("net.start.hint", {}, "Режим, сложность и уровень берутся из вашего меню и объявляются всем."),
				9, Cfg.UI_MUTED))
	else:
		var me: Dictionary = Net.lobby.get(multiplayer.get_unique_id(), {})
		_net_body.add_child(UiKit.switch_row(
			I18n.t("net.ready", {}, "Готов"), bool(me.get("ready", false)),
			func(v: bool): Net.set_ready(v)))
		_net_body.add_child(UiKit.label(
			I18n.t("net.wait.host", {}, "Ждём, когда хост начнёт партию."), 11, Cfg.UI_MUTED))

	var leave_btn := UiKit.danger(I18n.t("net.leave", {}, "Отключиться"), 12)
	leave_btn.pressed.connect(func():
		Net.leave()
		_net_mode = ""
		_net_error = ""
		_refresh_net())
	_net_body.add_child(leave_btn)
