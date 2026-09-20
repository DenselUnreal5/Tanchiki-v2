# ============================================================================
# hub.gd — Хаб: Галерея перков / Гараж / Достижения, три вкладки одного
# оверлея. Раньше строился целиком в ui_root.gd (_build_hub() и все
# _fill_*_tab()); теперь оболочка — сцена (scenes/ui/hub.tscn), а содержимое
# вкладок по-прежнему строится кодом (число карточек зависит от Prof/
# Upgrades/Achievements/Perks — статично не авторится), но каждая отдельная
# карточка — сама сцена (scenes/ui/cards/*.tscn) с редактируемым в
# инспекторе размером иконки, вместо литералов Vector2(26,26) и т.п.
#
# UiRoot остаётся диспетчером экранов (видимость, стек фокуса, L1/R1) —
# Hub сообщает о закрытии сигналом close_requested и не знает о других
# оверлеях игры.
#
# @tool: живой предпросмотр оболочки в редакторе — без реального Prof
# показывает по одному статичному образцу каждой карточки (см. низ файла).
# Настоящая работа с иконками делается на самих файлах карточек
# (upgrade_card.tscn и т.д.), которые полностью живые и Prof не читают.
# ============================================================================
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

## Автозагрузка без @tool: в редакторе — заглушка. Хаб не пишет I18n.lang
## напрямую (это уже читает сам I18n.t()/dn() через fallback), обёртка
## нужна только там, где вызов идёт вне set_data()-цепочек, во время
## первичной сборки оболочки.
func _tr(key: String, fallback: String, params: Dictionary = {}) -> String:
	return fallback if Engine.is_editor_hint() else I18n.t(key, params, fallback)

var _gallery_nodes: Dictionary = {}
var _gallery_row: HBoxContainer
var _gallery_detail_panel: Control
var _gallery_selected_id := ""

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
	if Engine.is_editor_hint():
		_editor_preview_body()

func _on_close_pressed() -> void:
	close_requested.emit()

## Донор стилбоксов/шрифта — тот же приём, что в main_menu.gd/карточках.
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

# ------------------------------------------------------------ фокус-хелперы
## Первый видимый фокусируемый Control в поддереве (копия UiRoot._first_
## focusable — самодостаточность Hub важнее переиспользования пары строк).
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

# ---------------------------------------------------------------- вкладки
func tab_items() -> Array:
	return [
		{"key": "gallery", "label": _tr("menu.gallery", "Галерея перков")},
		{"key": "garage", "label": _tr("menu.garage", "🔧 Гараж")},
		{"key": "achievements", "label": _tr("menu.achievements", "🏅 Достижения")},
	]

func _rebuild_tabs() -> void:
	var idx := _tabs_row.get_index()
	var parent := _tabs_row.get_parent()
	var new_row := UiKit.plain_tabs(tab_items(), active_tab, func(key): switch_tab(key))
	parent.add_child(new_row)
	parent.move_child(new_row, idx)
	_tabs_row.queue_free()
	_tabs_row = new_row
	UiKit.chain_horizontal(_tabs_row.get_children(), true)

## focus_id — id карточки (meta "card_id"), на которую нужно вернуть фокус
## после пересборки, вместо вкладки — используется, когда вызов пришёл не
## от клика по вкладке, а от обновления её же содержимого (покупка в
## гараже — фокус должен остаться на той же карточке).
func switch_tab(key: String, focus_id: String = "") -> void:
	active_tab = key
	_rebuild_tabs()
	_fill_tab(key)
	if focus_id != "":
		var target := _find_by_meta(_body, "card_id", focus_id)
		_grab(target if target != null else _first_focusable(_body))
	else:
		_grab(_find_tab_button(key))

func _fill_tab(key: String) -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	match key:
		"gallery": _fill_gallery_tab()
		"garage": _fill_garage_tab()
		"achievements": _fill_achievements_tab()
	_resize_scroll()

func open_tab(key: String, focus_id: String = "") -> void:
	visible = true
	switch_tab(key, focus_id)

func refresh_language() -> void:
	_close_btn.text = _tr("btn.close", "Закрыть")
	_rebuild_tabs()
	if visible:
		_fill_tab(active_tab)

# ---------------------------------------------------------------- раскладка
func _body_budget() -> float:
	var screen := get_viewport_rect().size
	return maxf(minf(screen.y * 0.86, 900.0) - HUB_HEADER_H, 200.0)

func _resize_scroll() -> void:
	_scroll.custom_minimum_size.y = _body_budget()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_scroll()

# ------------------------------------------------------------ ГАЛЕРЕЯ ПЕРКОВ
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

## Собирает GalleryDetail для перка — пустой (не выбрано) или с данными,
## переведёнными здесь и переданными как готовые строки (см. gallery_
## detail.gd:set_perk).
## parent — куда добавить панель ДО заполнения данными: set_perk() трогает
## @onready-поля (%Icon и т.д.), которые Godot проставляет только в _ready(),
## а _ready() узла срабатывает лишь при входе в дерево (add_child), не при
## самом instantiate() — тот же порядок нужен и во всех *_card() ниже.
## Тематический билд (Perks.BUILDS) для перка — например «Грозовой билд»:
## Повелитель молний + Небесный удар + Цепная молния вместе утраивают шанс
## удара молнии (см. world.gd::_update_lightning_lord). Раньше эта синергия
## нигде не объяснялась игроку — только жила в коде. Пустая строка, если
## перк ни в какой билд не входит.
func _build_synergy_text(id: String) -> String:
	var builds := Perks.builds_with_perk(id)
	if builds.is_empty():
		return ""
	var b: Dictionary = builds[0]
	var member_names := []
	for pid in b["perks"]:
		member_names.append(I18n.dn(Perks.get_perk(String(pid)), "name", "perk"))
	return "⚡ %s\n%s\n%s" % [
		I18n.dn(b, "name", "build").to_upper(),
		" + ".join(member_names),
		I18n.dn(b, "bonus", "build"),
	]

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
	if unlocked:
		panel.set_perk(id, name_text, desc_text, true, {}, _tr("gallery.open", "ОТКРЫТ"), "", is_active, build_text)
	elif perk.has("challenge"):
		var pr := Prof.challenge_progress(id)
		var task := I18n.t("perk." + id + ".challenge", {}, String(pr["desc"]))
		panel.set_perk(id, name_text, desc_text, false, pr, "", task, is_active, build_text)
	else:
		var lvl := Perks.unlock_level_of(id)
		panel.set_perk(id, name_text, desc_text, false, {},
			_tr("gallery.unlockAt", "Откроется на уровне профиля %d" % lvl, {"lvl": lvl}),
			"", is_active, build_text)
	return panel

# ------------------------------------------------------------------ ГАРАЖ
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
		# grid — в дерево ДО заполнения карточками: set_data() внутри
		# _upgrade_card() трогает @onready-поля, которые заведёт только
		# _ready() карточки, а он сработает лишь когда карточка реально
		# войдёт в SceneTree — то есть уже после того, как в неё войдёт grid.
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

	_body.add_child(UiKit.section(_tr("garage.colors", "Цвет танка"), Cfg.UI_MUTED))
	_body.add_child(_garage_color_row(_tr("menu.color1", "Цвет танка 1"), 0, Prof.equipped_color1))
	_body.add_child(_garage_color_row(_tr("menu.color2", "Цвет танка 2"), 1, Prof.equipped_color2))

	_body.add_child(UiKit.section(_tr("garage.cosmetics", "Косметика"), Cfg.UI_MUTED))
	var type_names := {"camo": "Камуфляж", "hull": "Рисунок", "track": "Гусеницы", "turret": "Башня"}
	for type in Cosmetics.TYPES:
		var t2 := UiKit.label(_tr("cos." + type, String(type_names[type])).to_upper(), 11, Cfg.UI_MUTED, true)
		_body.add_child(t2)
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		_body.add_child(grid)
		for c in Cosmetics.by_type(type):
			_cosmetic_card(c, type, grid)

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

func _cosmetic_card(c: Dictionary, type: String, parent: Node) -> Control:
	var id := String(c["id"])
	var owned := Prof.is_cosmetic_owned(type, id)
	var equipped := String(Prof.cosmetics[type]) == id
	var can_buy := not owned and Prof.money >= int(c["price"])
	var card_id := "cos_%s_%s" % [type, id]

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

	var card: CosmeticCard = CosmeticCardScene.instantiate()
	parent.add_child(card)
	card.set_data("cos_%s_%s" % [type, id], c.get("color", c.get("a", Cfg.UI_TEXT)),
		I18n.dn(c, "name", "cos." + type), state, action_text, action_disabled, equipped, can_buy, card_id)
	card.action_pressed.connect(func():
		var ok: bool = Prof.equip_cosmetic(type, id)["ok"] if owned else Prof.buy_cosmetic(type, id)["ok"]
		if ok:
			garage_changed.emit()
			switch_tab("garage", card_id))
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
		var ok: bool = Prof.equip_cannon(id)["ok"] if owned else Prof.buy_cannon(id)["ok"]
		if ok:
			garage_changed.emit()
			switch_tab("garage", card_id))
	return card

func _garage_color_row(label_text: String, slot: int, equipped_key: String) -> Control:
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
				switch_tab("garage", card_id))
		flow.add_child(btn)
	return box

# -------------------------------------------------------------- ДОСТИЖЕНИЯ
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

# ---------------------------------------------------------- предпросмотр
## В редакторе Prof/Achievements-данных для настоящего состояния профиля
## нет — вместо попытки подделать Prof показываем по одному статичному
## образцу каждой карточки, только чтобы оболочка не выглядела пустой.
## Карточка сама заполняет себя образцом в своём _ready() под
## Engine.is_editor_hint() — здесь достаточно её просто добавить в дерево
## (set_data() до add_child() обращался бы к ещё не готовым @onready-полям).
## Точная настройка размера иконок — на самих файлах карточек, они живые.
func _editor_preview_body() -> void:
	_body.add_child(UpgradeCardScene.instantiate())
