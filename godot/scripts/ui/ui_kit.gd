# ============================================================================
# ui_kit.gd — оформление интерфейса.
#
# Повторяет style.css веб-версии: тёмная схема, зелёный акцент, скруглённые
# «пилюли»-кнопки, панели с полупрозрачным фоном и золотые акценты.
# ============================================================================
class_name UiKit
extends RefCounted

# ---------------------------------------------------------------- стили
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

static func panel_style(border_color: Color = Cfg.UI_ACCENT_DIM) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Cfg.UI_PANEL
	s.set_corner_radius_all(14)
	s.set_border_width_all(2)
	s.border_color = border_color
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 20
	s.content_margin_bottom = 20
	return s

static func card_style(border_color: Color = Color("#2e2e2e")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#151515")
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = border_color
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

# ---------------------------------------------------------------- надписи
static func label(text: String, font_size: int = 12, color: Color = Cfg.UI_TEXT,
		bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.bold if bold else Fonts.regular)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

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
	# Разрядка букв как letter-spacing в CSS: вставляем тонкие пробелы.
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

# ---------------------------------------------------------------- кнопки
static func _style_button(b: Button, normal: StyleBoxFlat, hover: StyleBoxFlat,
		pressed: StyleBoxFlat, font_size: int, color: Color) -> void:
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_font_override("font", Fonts.regular)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color("#dde8dd"))
	b.add_theme_color_override("font_pressed_color", Color("#eaffea"))
	b.add_theme_color_override("font_disabled_color", Color(color.r, color.g, color.b, 0.35))

## Главная зелёная кнопка (btn-primary / #btn-start).
static func primary(text: String, font_size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	var normal := flat(Color("#2f7329"), 12, 1, Cfg.UI_ACCENT)
	var hover := flat(Color("#3d8f36"), 12, 1, Cfg.UI_ACCENT)
	var pressed := flat(Color("#245c1f"), 12, 1, Cfg.UI_ACCENT)
	for s in [normal, hover, pressed]:
		s.content_margin_top = 12
		s.content_margin_bottom = 12
	_style_button(b, normal, hover, pressed, font_size, Color.WHITE)
	b.add_theme_font_override("font", Fonts.bold)
	return b

## Второстепенная «пилюля» (btn-secondary).
static func secondary(text: String, font_size: int = 12) -> Button:
	var b := Button.new()
	b.text = text
	var normal := flat(Color(0.094, 0.106, 0.094, 0.85), 999, 1, Color(1, 1, 1, 0.1))
	var hover := flat(Color(0.13, 0.15, 0.13, 0.9), 999, 1, Cfg.UI_ACCENT)
	var pressed := flat(Color(0.16, 0.2, 0.16, 0.95), 999, 1, Cfg.UI_ACCENT)
	_style_button(b, normal, hover, pressed, font_size, Color("#b3bcb3"))
	return b

## Опасное действие (btn-secondary.danger).
static func danger(text: String, font_size: int = 12) -> Button:
	var b := secondary(text, font_size)
	b.add_theme_stylebox_override("hover", flat(Color(0.16, 0.09, 0.09, 0.9), 999, 1, Cfg.UI_DANGER))
	b.add_theme_color_override("font_color", Color("#ffaaaa"))
	b.add_theme_color_override("font_hover_color", Color("#ffcccc"))
	return b

## Переключатель в группе (.toggle).
static func toggle(text: String, font_size: int = 12) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	var normal := flat(Color(0.086, 0.102, 0.086, 0.7), 999, 1, Color(1, 1, 1, 0.1))
	var hover := flat(Color(0.11, 0.14, 0.11, 0.8), 999, 1, Color(0.33, 0.8, 0.33, 0.6))
	var active := flat(Color("#2b6027"), 999, 1, Cfg.UI_ACCENT)
	_style_button(b, normal, hover, active, font_size, Color("#9aa59a"))
	b.add_theme_stylebox_override("pressed", active)
	b.add_theme_stylebox_override("hover_pressed", active)
	b.add_theme_color_override("font_pressed_color", Color("#eaffea"))
	b.add_theme_color_override("font_hover_pressed_color", Color("#eaffea"))
	return b

## Маленькая кнопка покупки (.btn-small).
static func small(text: String) -> Button:
	var b := Button.new()
	b.text = text
	var normal := flat(Color("#1f1f1f"), 6, 1, Color("#3a3a3a"))
	var hover := flat(Color("#282828"), 6, 1, Cfg.UI_GOLD)
	var pressed := flat(Color("#151515"), 6, 1, Cfg.UI_GOLD)
	for s in [normal, hover, pressed]:
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 6
		s.content_margin_bottom = 6
	_style_button(b, normal, hover, pressed, 10, Cfg.UI_GOLD)
	return b

# ---------------------------------------------------------------- контейнеры
static func panel(border_color: Color = Cfg.UI_ACCENT_DIM) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(border_color))
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

## Полоска прогресса (.gc-bar / .bar).
static func progress_bar(value: float, width: float, height: float,
		fill: Color, bg: Color = Color("#222222")) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(width, height)
	var back := ColorRect.new()
	back.color = bg
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(back)
	var front := ColorRect.new()
	front.color = fill
	front.position = Vector2.ZERO
	front.size = Vector2(width * clampf(value, 0.0, 1.0), height)
	wrap.add_child(front)
	return wrap

# ---------------------------------------------------------------- строки настроек
## Строка с ползунком: подпись слева, значение справа.
## on_change получает значение 0..1.
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
	return row

## Строка-выключатель: подпись и кнопка «Вкл/Выкл».
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
	return row

## Строка-переключатель из нескольких вариантов.
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
	return row

## Полупрозрачная затемняющая подложка оверлея (.overlay.dim).
static func dimmer() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, 0.82)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c
