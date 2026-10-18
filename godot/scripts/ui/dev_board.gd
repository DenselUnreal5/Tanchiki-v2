class_name DevBoard
extends Control

signal changed
signal closed

const TABS := [
	{"key": "profile", "label": "Профиль"},
	{"key": "perks", "label": "Перки"},
	{"key": "cosmetics", "label": "Косметика"},
	{"key": "tanks", "label": "Танки"},
]

const COSMETIC_TYPE_NAMES := {
	"skin": "Окраска",
	"camo": "Камуфляж",
	"hull": "Корпус",
	"track": "Гусеницы",
	"turret": "Башня",
}

var tab := "profile"
var _summary: Label
var _tabs_holder: CenterContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _close_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(UiKit.dimmer())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UiKit.panel(Cfg.UI_GOLD)
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)

	var box := UiKit.vbox(10)
	panel.add_child(box)

	var title := UiKit.title("ПАНЕЛЬ РАЗРАБОТЧИКА", 22, Cfg.UI_GOLD)
	box.add_child(title)
	_summary = UiKit.label("", 12, Cfg.UI_MUTED)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_summary)

	_tabs_holder = CenterContainer.new()
	box.add_child(_tabs_holder)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(700, 430)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	box.add_child(_scroll)

	_body = UiKit.vbox(6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	_close_btn = UiKit.secondary("Закрыть  [F10 / Esc]")
	_close_btn.pressed.connect(close_board)
	var wrap := CenterContainer.new()
	wrap.add_child(_close_btn)
	box.add_child(wrap)

func open_board() -> void:
	visible = true
	_render()
	_close_btn.grab_focus()

func close_board() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func toggle_board() -> void:
	if visible:
		close_board()
	else:
		open_board()

func switch_tab(key: String) -> void:
	tab = key
	_render()
	_scroll.scroll_vertical = 0

func _render() -> void:
	_update_summary()
	for c in _tabs_holder.get_children():
		c.queue_free()
	_tabs_holder.add_child(UiKit.plain_tabs(TABS, tab, switch_tab))
	for c in _body.get_children():
		c.queue_free()
	match tab:
		"profile":
			_fill_profile()
		"perks":
			_fill_perks()
		"cosmetics":
			_fill_cosmetics()
		"tanks":
			_fill_tanks()

func _update_summary() -> void:
	var cosmetics_owned := 0
	var cosmetics_total := DevTools.cosmetic_items().size()
	for c in DevTools.cosmetic_items():
		if DevTools.is_cosmetic_owned(String(c["type"]), String(c["id"])):
			cosmetics_owned += 1
	_summary.text = "Уровень %d  ·  %d 🪙  ·  перков %d/%d  ·  косметики %d/%d" % [
		Prof.global_level, Prof.money, Prof.unlocked.size(), Perks.all().size(),
		cosmetics_owned, cosmetics_total]

func _notify() -> void:
	_update_summary()
	changed.emit()

func _apply(action: Callable) -> void:
	action.call()
	changed.emit()
	_render()

func _buttons_row(caption: String, buttons: Array) -> HBoxContainer:
	var row := UiKit.hbox(8)
	var label := UiKit.label(caption, 13, Cfg.UI_TEXT, true)
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	for b in buttons:
		var btn := UiKit.small(String(b[0]))
		var action: Callable = b[1]
		btn.pressed.connect(func(): _apply(action))
		row.add_child(btn)
	return row

func _fill_profile() -> void:
	_body.add_child(UiKit.section("Уровень профиля", Cfg.UI_GOLD))
	_body.add_child(_buttons_row("Уровень: %d" % Prof.global_level, [
		["−1", func(): DevTools.set_level(Prof.global_level - 1)],
		["+1", func(): DevTools.set_level(Prof.global_level + 1)],
		["+5", func(): DevTools.set_level(Prof.global_level + 5)],
		["+10", func(): DevTools.set_level(Prof.global_level + 10)],
		["Макс (%d)" % DevTools.MAX_LEVEL, func(): DevTools.set_level(DevTools.MAX_LEVEL)],
		["Сброс (1)", func(): DevTools.set_level(1)],
	]))
	var hint := UiKit.label("Повышение уровня открывает перки по таблице уровней. Понижение перки не закрывает — для этого вкладка «Перки».", 11, Cfg.UI_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(hint)
	_body.add_child(UiKit.section("Монеты", Cfg.UI_GOLD))
	_body.add_child(_buttons_row("Монет: %d 🪙" % Prof.money, [
		["−1000", func(): DevTools.add_money(-1000)],
		["−100", func(): DevTools.add_money(-100)],
		["+100", func(): DevTools.add_money(100)],
		["+1000", func(): DevTools.add_money(1000)],
		["+10000", func(): DevTools.add_money(10000)],
		["Обнулить", func(): DevTools.set_money(0)],
	]))

func _all_row(on_all: Callable, off_all: Callable) -> HBoxContainer:
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var open_all := UiKit.button("Открыть всё", 12)
	open_all.pressed.connect(func(): _apply(on_all))
	row.add_child(open_all)
	var close_all := UiKit.danger("Закрыть всё", 12)
	close_all.pressed.connect(func(): _apply(off_all))
	row.add_child(close_all)
	return row

func _toggle_row(text: String, value: bool, on_change: Callable, icon_id: String = "") -> HBoxContainer:
	var row := UiKit.hbox(10)
	if icon_id != "":
		row.add_child(PerkIcons.make_view(icon_id, 36))
	var label := UiKit.label(text, 12, Cfg.UI_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	var btn := UiKit.toggle("", 12)
	btn.custom_minimum_size = Vector2(120, 24)
	btn.button_pressed = value
	btn.text = "Открыто" if value else "Закрыто"
	btn.toggled.connect(func(pressed: bool):
		btn.text = "Открыто" if pressed else "Закрыто"
		on_change.call(pressed)
		_notify())
	row.add_child(btn)
	return row

func _fill_perks() -> void:
	_body.add_child(_all_row(func(): DevTools.set_all_perks(true), func(): DevTools.set_all_perks(false)))
	for p in Perks.all():
		var id := String(p["id"])
		var text := I18n.dn(p, "name", "perk")
		_body.add_child(_toggle_row(text, Prof.is_unlocked(id), func(on: bool): DevTools.set_perk(id, on), id))

func _fill_cosmetics() -> void:
	_body.add_child(_all_row(func(): DevTools.set_all_cosmetics(true), func(): DevTools.set_all_cosmetics(false)))
	for type in Cosmetics.TYPES:
		_body.add_child(UiKit.section(String(COSMETIC_TYPE_NAMES.get(type, type)), Cfg.UI_GOLD))
		for c in Cosmetics.by_type(type):
			var id := String(c["id"])
			if id == "none":
				continue
			var text := "%s  %s  ·  %d 🪙" % [String(c.get("icon", "")), String(c["name"]), int(c.get("price", 0))]
			_body.add_child(_toggle_row(text, DevTools.is_cosmetic_owned(type, id),
				func(on: bool): DevTools.set_cosmetic(type, id, on)))

func _fill_tanks() -> void:
	_body.add_child(_all_row(func(): DevTools.set_all_tanks(true), func(): DevTools.set_all_tanks(false)))
	_body.add_child(UiKit.section("Классы танков", Cfg.UI_GOLD))
	for entry in TankClasses.LIST:
		var id := String(entry["id"])
		if id == TankClasses.DEFAULT:
			continue
		var text := "%s  ·  %d 🪙" % [TankClasses.display_name(entry), TankClasses.price(id)]
		_body.add_child(_toggle_row(text, Prof.is_class_owned(id), func(on: bool): DevTools.set_class(id, on), "class_" + id))
	_body.add_child(UiKit.section("Пушки", Cfg.UI_GOLD))
	for c in Cannons.LIST:
		var id := String(c["id"])
		if id == "standard":
			continue
		var text := "%s  ·  %d 🪙" % [String(c["name"]), int(c.get("price", 0))]
		_body.add_child(_toggle_row(text, Prof.is_cannon_owned(id), func(on: bool): DevTools.set_cannon(id, on), "cannon_" + id))
