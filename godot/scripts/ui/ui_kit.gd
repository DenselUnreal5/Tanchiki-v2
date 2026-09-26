@tool
class_name UiKit
extends RefCounted

static func flat(bg: Color, radius: float = 8.0, border: float = 0.0,
		border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(int(radius))
	if border > 0.0:
		s.set_border_width_all(int(border))
		s.border_color = border_color
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

static func focus_ring() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.set_border_width_all(2)
	s.border_color = Cfg.UI_ACCENT
	s.set_corner_radius_all(int(_chrome_radius()))
	s.set_expand_margin_all(3.0 if _ui_theme() == "material" else 2.0)
	return s

static func card_style(border_color: Color = Cfg.UI_BORDER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Cfg.UI_CARD
	if _ui_theme() == "material":
		s.set_corner_radius_all(16)
		s.set_border_width_all(1)
		s.border_color = border_color
		s.shadow_color = Color(0, 0, 0, 0.28)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 3)
	else:
		s.set_corner_radius_all(int(Cfg.RADIUS_MD))
		s.set_border_width_all(1)
		s.border_color = border_color
	var pad := 12 if _ui_theme() == "material" else 10
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

static func label(text: String, font_size: int = 12, color: Color = Cfg.UI_TEXT,
		bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.bold if bold else Fonts.regular)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

static func icon_label(icon: String, text: String, font_size: int = 12,
		color: Color = Cfg.UI_TEXT, bold: bool = false) -> Label:
	return label("%s %s" % [icon, text], font_size, color, bold)

static func rich(text: String, font_size: int = 12, color: Color = Cfg.UI_TEXT) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.add_theme_font_override("normal_font", Fonts.regular)
	r.add_theme_font_override("bold_font", Fonts.bold)
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_font_size_override("bold_font_size", font_size)
	r.add_theme_color_override("default_color", color)
	return r

static func title(text: String, font_size: int = 26, color: Color = Cfg.UI_TEXT) -> Label:
	var spaced := ""
	for i in text.length():
		spaced += text[i]
		if i < text.length() - 1:
			spaced += " "
	var l := label(spaced, font_size, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func subtitle(text: String) -> Label:
	var l := label(text, 11, Cfg.UI_MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func _style_button(b: Button, normal: StyleBox, hover: StyleBox,
		pressed: StyleBox, font_size: int, color: Color) -> void:
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_font_override("font", Fonts.regular)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color("#dde8dd"))
	b.add_theme_color_override("font_pressed_color", Color("#eaffea"))
	b.add_theme_color_override("font_disabled_color", Color(color.r, color.g, color.b, 0.35))

static func _ui_theme() -> String:
	return "military" if Engine.is_editor_hint() else Sets.ui_theme

static func _chrome_radius() -> float:
	match _ui_theme():
		"military": return 3.0
		"scifi": return 8.0
		"material": return 20.0
		_: return 999.0

static func _chrome_border_w() -> float:
	match _ui_theme():
		"military": return 2.0
		"scifi": return 1.0
		"material": return 1.0
		_: return 1.0

static func primary(text: String, font_size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	if _ui_theme() == "material":
		var r := 999.0
		var normal := flat(Cfg.UI_ACCENT, r, 0)
		var hover := flat(Cfg.UI_ACCENT.lightened(0.12), r, 0)
		var pressed := flat(Cfg.UI_ACCENT.darkened(0.12), r, 0)
		for s in [normal, hover, pressed]:
			s.content_margin_top = 12
			s.content_margin_bottom = 12
			s.content_margin_left = 24
			s.content_margin_right = 24
		_style_button(b, normal, hover, pressed, font_size, Color("#042f4c"))
		b.add_theme_color_override("font_hover_color", Color("#022238"))
		b.add_theme_color_override("font_pressed_color", Color("#011828"))
		b.add_theme_font_override("font", Fonts.bold)
		return b
	var r := 4.0 if _ui_theme() == "military" else 12.0
	var normal := flat(Color("#2f7329"), r, 1, Cfg.UI_ACCENT)
	var hover := flat(Color("#3d8f36"), r, 1, Cfg.UI_ACCENT)
	var pressed := flat(Color("#245c1f"), r, 1, Cfg.UI_ACCENT)
	for s in [normal, hover, pressed]:
		s.content_margin_top = 12
		s.content_margin_bottom = 12
	_style_button(b, normal, hover, pressed, font_size, Color.WHITE)
	b.add_theme_font_override("font", Fonts.bold)
	return b

static func secondary(text: String, font_size: int = 12) -> Button:
	var b := Button.new()
	b.text = text
	if _ui_theme() == "material":
		var normal := flat(Cfg.UI_CARD, 999.0, 1, Cfg.UI_BORDER)
		var hover := flat(Cfg.UI_CARD.lightened(0.12), 999.0, 1, Cfg.UI_ACCENT)
		var pressed := flat(Cfg.UI_ACCENT_DIM, 999.0, 1, Cfg.UI_ACCENT)
		_style_button(b, normal, hover, pressed, font_size, Cfg.UI_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Cfg.UI_ACCENT)
		return b
	var r := _chrome_radius()
	var bw := _chrome_border_w()
	var normal := flat(Color(0.086, 0.098, 0.09, 0.85), r, bw, Color(1, 1, 1, 0.16))
	var hover := flat(Color(0.13, 0.15, 0.11, 0.9), r, bw, Cfg.UI_ACCENT)
	var pressed := flat(Color(0.16, 0.19, 0.13, 0.95), r, bw, Cfg.UI_ACCENT)
	_style_button(b, normal, hover, pressed, font_size, Color("#c7cbb8"))
	return b

static func danger(text: String, font_size: int = 12) -> Button:
	var b := secondary(text, font_size)
	if _ui_theme() == "material":
		b.add_theme_stylebox_override("normal", flat(Color(0.25, 0.08, 0.08, 0.7), 999.0, 1, Color(Cfg.UI_DANGER, 0.4)))
		b.add_theme_stylebox_override("hover", flat(Color(0.35, 0.1, 0.1, 0.9), 999.0, 1, Cfg.UI_DANGER))
		b.add_theme_stylebox_override("pressed", flat(Color(0.42, 0.12, 0.12, 0.95), 999.0, 1, Cfg.UI_DANGER))
		b.add_theme_color_override("font_color", Cfg.UI_DANGER)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		return b
	b.add_theme_stylebox_override("hover", flat(Color(0.16, 0.09, 0.09, 0.9), _chrome_radius(), _chrome_border_w(), Cfg.UI_DANGER))
	b.add_theme_color_override("font_color", Color("#ffaaaa"))
	b.add_theme_color_override("font_hover_color", Color("#ffcccc"))
	return b

static func toggle(text: String, font_size: int = 12) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	if _ui_theme() == "material":
		var normal := flat(Cfg.UI_CARD, 999.0, 1, Cfg.UI_BORDER)
		var hover := flat(Cfg.UI_CARD.lightened(0.08), 999.0, 1, Cfg.UI_ACCENT)
		var active := flat(Cfg.UI_ACCENT_DIM, 999.0, 0, Color.TRANSPARENT)
		_style_button(b, normal, hover, active, font_size, Cfg.UI_MUTED)
		b.add_theme_stylebox_override("pressed", active)
		b.add_theme_stylebox_override("hover_pressed", active)
		b.add_theme_color_override("font_hover_color", Cfg.UI_TEXT)
		b.add_theme_color_override("font_pressed_color", Cfg.UI_ACCENT)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		return b
	var r := _chrome_radius()
	var bw := _chrome_border_w()
	var normal := flat(Color(0.086, 0.102, 0.086, 0.7), r, bw, Color(1, 1, 1, 0.16))
	var hover := flat(Color(0.11, 0.14, 0.11, 0.8), r, bw, Color(Cfg.UI_ACCENT, 0.6))
	var active := flat(Color(Cfg.UI_ACCENT_DIM, 0.85), r, bw, Cfg.UI_ACCENT)
	_style_button(b, normal, hover, active, font_size, Color("#a8b09a"))
	b.add_theme_stylebox_override("pressed", active)
	b.add_theme_stylebox_override("hover_pressed", active)
	b.add_theme_color_override("font_pressed_color", Color("#eaffea"))
	b.add_theme_color_override("font_hover_pressed_color", Color("#eaffea"))
	return b

static func small(text: String) -> Button:
	var b := Button.new()
	b.text = text
	var is_mat := _ui_theme() == "material"
	var r := 999.0 if is_mat else 6.0
	var normal := flat(Cfg.UI_CARD if is_mat else Color("#1f1f1f"), r, 1, Cfg.UI_BORDER if is_mat else Color("#3a3a3a"))
	var hover := flat(Cfg.UI_CARD.lightened(0.1) if is_mat else Color("#282828"), r, 1, Cfg.UI_GOLD)
	var pressed := flat(Cfg.UI_ACCENT_DIM if is_mat else Color("#151515"), r, 1, Cfg.UI_GOLD)
	for s in [normal, hover, pressed]:
		s.content_margin_left = 12 if is_mat else 10
		s.content_margin_right = 12 if is_mat else 10
		s.content_margin_top = 6
		s.content_margin_bottom = 6
	_style_button(b, normal, hover, pressed, 10, Cfg.UI_GOLD)
	return b

static func panel(border_color: Color = Color.TRANSPARENT, stripe_top: bool = false) -> ThemedPanel:
	var p := ThemedPanel.new()
	p.border_color = border_color
	p.stripe_top = stripe_top
	p.seed_value = randi()
	return p

static func vbox(separation: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v

static func hbox(separation: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h

static func section(text: String, color: Color) -> Label:
	var l := label(text.to_upper(), 12, color, true)
	l.add_theme_constant_override("line_spacing", 6)
	return l

static func progress_bar(value: float, width: float, height: float,
		fill: Color, bg: Color = Color("#222222")) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(width, height)
	if _ui_theme() == "material":
		var back := Panel.new()
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.add_theme_stylebox_override("panel", flat(bg, height * 0.5))
		wrap.add_child(back)
		var front := Panel.new()
		front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		front.anchor_right = clampf(value, 0.0, 1.0)
		front.offset_right = 0.0
		front.add_theme_stylebox_override("panel", flat(fill, height * 0.5))
		wrap.add_child(front)
		return wrap
	var back := ColorRect.new()
	back.color = bg
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(back)
	var front := ColorRect.new()
	front.color = fill
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	front.anchor_right = clampf(value, 0.0, 1.0)
	front.offset_right = 0.0
	wrap.add_child(front)
	return wrap

static func slider_row(label_text: String, value: float, on_change: Callable,
		suffix: String = "%") -> Control:
	var row := hbox(12)
	row.custom_minimum_size = Vector2(0, 30)

	var name_label := label(label_text, 12, Cfg.UI_TEXT)
	name_label.custom_minimum_size = Vector2(178, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(200, 22)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _ui_theme() == "material":
		slider.add_theme_stylebox_override("slider", flat(Cfg.UI_BORDER, 999.0))
		slider.add_theme_stylebox_override("grabber_area", flat(Cfg.UI_ACCENT, 999.0))
		slider.add_theme_stylebox_override("grabber_area_highlight", flat(Cfg.UI_ACCENT.lightened(0.15), 999.0))
	else:
		slider.add_theme_stylebox_override("slider", flat(Color(0, 0, 0, 0.55), 4))
		slider.add_theme_stylebox_override("grabber_area", flat(Cfg.UI_ACCENT_DIM, 4))
		slider.add_theme_stylebox_override("grabber_area_highlight", flat(Cfg.UI_ACCENT, 4))
	row.add_child(slider)

	var value_label := label("", 11, Cfg.UI_GOLD)
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%d%s" % [round(value * 100.0), suffix]
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float):
		value_label.text = "%d%s" % [round(v * 100.0), suffix]
		on_change.call(v))
	row.set_meta("focus_row", slider)
	return row

static func switch_row(label_text: String, value: bool, on_change: Callable) -> Control:
	var row := hbox(12)
	row.custom_minimum_size = Vector2(0, 30)

	var name_label := label(label_text, 12, Cfg.UI_TEXT)
	name_label.custom_minimum_size = Vector2(178, 0)
	row.add_child(name_label)

	var btn := toggle("", 12)
	btn.custom_minimum_size = Vector2(110, 26)
	btn.button_pressed = value
	btn.text = I18n.t("opt.on", {}, "Включено") if value else I18n.t("opt.off", {}, "Выключено")
	btn.toggled.connect(func(pressed: bool):
		btn.text = I18n.t("opt.on", {}, "Включено") if pressed else I18n.t("opt.off", {}, "Выключено")
		on_change.call(pressed))
	row.add_child(btn)
	row.set_meta("focus_row", btn)
	return row

static func choice_row(label_text: String, options: Array, index: int,
		on_change: Callable) -> Control:
	var row := hbox(12)
	row.custom_minimum_size = Vector2(0, 30)

	var name_label := label(label_text, 12, Cfg.UI_TEXT)
	name_label.custom_minimum_size = Vector2(178, 0)
	row.add_child(name_label)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(flow)

	var group := ButtonGroup.new()
	for i in options.size():
		var btn := toggle(String(options[i]), 11)
		btn.button_group = group
		btn.button_pressed = i == index
		var value := i
		btn.pressed.connect(func(): on_change.call(value))
		flow.add_child(btn)
	if flow.get_child_count() > 0:
		row.set_meta("focus_row", flow.get_child(mini(index, flow.get_child_count() - 1)))
	row.set_meta("focus_flow", flow)
	return row

static func keybind_row(label_text: String, keycode: int, on_change: Callable) -> Control:
	var row := hbox(12)
	row.custom_minimum_size = Vector2(0, 30)

	var name_label := label(label_text, 12, Cfg.UI_TEXT)
	name_label.custom_minimum_size = Vector2(178, 0)
	row.add_child(name_label)

	var btn := KeybindButton.new()
	btn.custom_minimum_size = Vector2(110, 26)
	var is_mat := _ui_theme() == "material"
	var r := _chrome_radius()
	var bw := _chrome_border_w()
	var normal := flat(Cfg.UI_CARD if is_mat else Color(0.086, 0.102, 0.086, 0.7), r, bw, Cfg.UI_BORDER if is_mat else Color(1, 1, 1, 0.16))
	var hover := flat(Cfg.UI_CARD.lightened(0.1) if is_mat else Color(0.11, 0.14, 0.11, 0.8), r, bw, Cfg.UI_ACCENT if is_mat else Color(Cfg.UI_ACCENT, 0.6))
	var listening_style := flat(Cfg.UI_ACCENT_DIM, r, bw, Cfg.UI_ACCENT)
	_style_button(btn, normal, hover, normal, 12, Cfg.UI_TEXT if is_mat else Color("#a8b09a"))
	btn.normal_style = normal
	btn.listening_style = listening_style
	btn.keycode = keycode
	btn.key_captured.connect(func(k: int): on_change.call(k))
	row.add_child(btn)
	row.set_meta("focus_row", btn)
	return row

static func dimmer() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, 0.82)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c

static func plain_tabs(items: Array, active_key: String, on_change: Callable) -> HBoxContainer:
	var row := hbox(28)
	for item in items:
		var key: String = item["key"]
		var on := key == active_key
		var btn := Button.new()
		btn.text = String(item["label"]).to_upper()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.set_meta("tab_key", key)
		if _ui_theme() == "material" and on:
			var active_sb := StyleBoxFlat.new()
			active_sb.bg_color = Color.TRANSPARENT
			active_sb.border_color = Cfg.UI_ACCENT
			active_sb.set_border_width(SIDE_BOTTOM, 3)
			active_sb.content_margin_bottom = 6
			_style_button(btn, active_sb, active_sb, active_sb, 13, Cfg.UI_ACCENT)
		else:
			var empty := StyleBoxEmpty.new()
			_style_button(btn, empty, empty, empty, 13, Cfg.UI_ACCENT if on else Cfg.UI_MUTED)
		btn.add_theme_font_override("font", Fonts.bold if on else Fonts.regular)
		btn.pressed.connect(func(): on_change.call(key))
		row.add_child(btn)
	return row

static func unlock_button(text: String, state: String) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = state == "locked"
	b.mouse_filter = Control.MOUSE_FILTER_STOP if state != "locked" else Control.MOUSE_FILTER_IGNORE
	var color := Cfg.UI_MUTED
	var bg := Color(Cfg.UI_BG, 0.6)
	if state == "unlocked" or state == "equipped":
		color = Cfg.UI_TAG_INK
		bg = Cfg.UI_TAG
	var r := 999.0 if _ui_theme() == "material" else Cfg.RADIUS_SM
	var style := flat(bg, r, 1, Cfg.UI_BORDER if state == "locked" else Color.TRANSPARENT)
	_style_button(b, style, style, style, 12, color)
	b.add_theme_font_override("font", Fonts.bold)
	return b

static func first_focusable(node: Node) -> Control:
	if node is Control and node.visible and node.focus_mode != Control.FOCUS_NONE:
		return node
	for c in node.get_children():
		var f := first_focusable(c)
		if f != null:
			return f
	return null

static func chain_horizontal(btns: Array, wrap: bool = true) -> void:
	var n := btns.size()
	for i in n:
		var b: Control = btns[i]
		if not is_instance_valid(b):
			continue
		var l: int = (i - 1 + n) % n if wrap else maxi(0, i - 1)
		var r: int = (i + 1) % n if wrap else mini(n - 1, i + 1)
		if is_instance_valid(btns[l]):
			b.focus_neighbor_left = btns[l].get_path()
			b.focus_previous = btns[l].get_path()
		if is_instance_valid(btns[r]):
			b.focus_neighbor_right = btns[r].get_path()
			b.focus_next = btns[r].get_path()

static func chain_vertical(rows: Array) -> void:
	var entries := []
	for row in rows:
		if not is_instance_valid(row):
			continue
		var e = row.get_meta("focus_row", null) if row.has_meta("focus_row") else null
		if e == null or not is_instance_valid(e):
			e = first_focusable(row)
		if e != null:
			entries.append(e)
	for i in entries.size():
		var a: Control = entries[i]
		if i > 0:
			a.focus_neighbor_top = entries[i - 1].get_path()
		if i + 1 < entries.size():
			a.focus_neighbor_bottom = entries[i + 1].get_path()

static func rounded_bar(width: float, height: float, fill: Color,
		border_color: Color = Color.TRANSPARENT) -> Dictionary:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(width, height)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.6)
	back.size = Vector2(width, height)
	wrap.add_child(back)
	var front := ColorRect.new()
	front.color = fill
	front.size = Vector2(0, height)
	wrap.add_child(front)
	var border := PanelContainer.new()
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bc := Cfg.UI_BORDER if border_color == Color.TRANSPARENT else border_color
	border.add_theme_stylebox_override("panel", flat(Color.TRANSPARENT, 2, 1, Color(bc, 0.8)))
	wrap.add_child(border)
	return {"wrap": wrap, "bg": back, "fill": front}
