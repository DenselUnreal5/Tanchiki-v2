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

static func card_style(border_color: Color = Cfg.UI_BORDER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Cfg.UI_CARD
	s.set_corner_radius_all(int(Cfg.RADIUS_MD))
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

## Подпись с иконкой-эмодзи впереди. Правило размера одно и без исключений:
## иконка всегда того же кегля, что и текст рядом — отдельной шкалы размеров
## для иконок нет и не нужно, только это наследование.
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
static func _style_button(b: Button, normal: StyleBox, hover: StyleBox,
		pressed: StyleBox, font_size: int, color: Color) -> void:
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

## Форма кнопок по теме — обычные Button/StyleBoxFlat, не свой _draw() (как
## у ThemedPanel/SkillNode), поэтому разница между темами — в геометрии
## (радиус, толщина рамки), а не в произвольной форме. Раньше все три темы
## получали одну и ту же перекрашенную «пилюлю» — снаружи это читалось как
## «сменили только палитру», хотя дерево умений и панели были другими.
## Нуар — мягкая пилюля (рваная бумага, мягкие формы), военное досье —
## почти прямой срез с толстой рамкой (штампованный металл), sci-fi —
## небольшое скругление, тоньше и светлее.
static func _chrome_radius() -> float:
	match Sets.ui_theme:
		"military": return 3.0
		"scifi": return 8.0
		_: return 999.0

static func _chrome_border_w() -> float:
	return 2.0 if Sets.ui_theme == "military" else 1.0

## Главная зелёная кнопка (btn-primary / #btn-start).
static func primary(text: String, font_size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	var r := 4.0 if Sets.ui_theme == "military" else 12.0
	var normal := flat(Color("#2f7329"), r, 1, Cfg.UI_ACCENT)
	var hover := flat(Color("#3d8f36"), r, 1, Cfg.UI_ACCENT)
	var pressed := flat(Color("#245c1f"), r, 1, Cfg.UI_ACCENT)
	for s in [normal, hover, pressed]:
		s.content_margin_top = 12
		s.content_margin_bottom = 12
	_style_button(b, normal, hover, pressed, font_size, Color.WHITE)
	b.add_theme_font_override("font", Fonts.bold)
	return b

## Второстепенная кнопка (btn-secondary) — навигация/хром.
static func secondary(text: String, font_size: int = 12) -> Button:
	var b := Button.new()
	b.text = text
	var r := _chrome_radius()
	var bw := _chrome_border_w()
	var normal := flat(Color(0.086, 0.098, 0.09, 0.85), r, bw, Color(1, 1, 1, 0.16))
	var hover := flat(Color(0.13, 0.15, 0.11, 0.9), r, bw, Cfg.UI_ACCENT)
	var pressed := flat(Color(0.16, 0.19, 0.13, 0.95), r, bw, Cfg.UI_ACCENT)
	_style_button(b, normal, hover, pressed, font_size, Color("#c7cbb8"))
	return b

## Опасное действие (btn-secondary.danger).
static func danger(text: String, font_size: int = 12) -> Button:
	var b := secondary(text, font_size)
	b.add_theme_stylebox_override("hover", flat(Color(0.16, 0.09, 0.09, 0.9), _chrome_radius(), _chrome_border_w(), Cfg.UI_DANGER))
	b.add_theme_color_override("font_color", Color("#ffaaaa"))
	b.add_theme_color_override("font_hover_color", Color("#ffcccc"))
	return b

## Переключатель в группе (.toggle).
static func toggle(text: String, font_size: int = 12) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
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
## Панель с фоном текущей темы (рваная бумага / клёпаный металл / скошенное
## стекло, см. themed_panel.gd) — основной строительный блок почти всех
## экранов вне HUD. border_color по умолчанию — Color.TRANSPARENT, что
## значит «рамка текущей темы» (Cfg.UI_BORDER); передавать другой цвет
## нужно только для семантических рамок (победа/поражение/награда).
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

## Полоска прогресса (.gc-bar / .bar).
static func progress_bar(value: float, width: float, height: float,
		fill: Color, bg: Color = Color("#222222")) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(width, height)
	var back := ColorRect.new()
	back.color = bg
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(back)
	# Анкерами, а не пиксельным size: контейнер (wrap) нередко растягивается
	# шире переданного width (например VBoxContainer с EXPAND_FILL в карточке
	# задания) — back это отражает через PRESET_FULL_RECT, а фиксированный
	# по ширине front тогда не дотягивался бы до края даже при value = 1.0.
	var front := ColorRect.new()
	front.color = fill
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	front.anchor_right = clampf(value, 0.0, 1.0)
	front.offset_right = 0.0
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

# ---------------------------------------------------------------- вкладки и статус
## Полоска вкладок сверху экрана: активная — жирным и цветом акцента,
## остальные — приглушённым текстом. Без фона/пилюль — читается как заголовки
## разделов, а не как отдельные кнопки (так у всех трёх тем сразу, только
## меняется акцентный цвет). items — массив {"key": String, "label": String}.
static func plain_tabs(items: Array, active_key: String, on_change: Callable) -> HBoxContainer:
	var row := hbox(28)
	for item in items:
		var key: String = item["key"]
		var on := key == active_key
		var btn := Button.new()
		btn.text = String(item["label"]).to_upper()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		_style_button(btn, empty, empty, empty, 13, Cfg.UI_ACCENT if on else Cfg.UI_MUTED)
		btn.add_theme_font_override("font", Fonts.bold if on else Fonts.regular)
		btn.pressed.connect(func(): on_change.call(key))
		row.add_child(btn)
	return row

## Состояние узла дерева умений — не кнопка покупки, а честная сводка
## состояния: прогресс здесь всегда только по уровню профиля/задаче,
## купить перк за деньги нельзя (в отличие от прототипа-референса).
## Военное досье рисует её полоской-жетоном (UI_TAG), остальные темы — как
## обычную приглушённую/акцентную кнопку-статус.
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
	var style := flat(bg, Cfg.RADIUS_SM, 1, Cfg.UI_BORDER if state == "locked" else Color.TRANSPARENT)
	_style_button(b, style, style, style, 12, color)
	b.add_theme_font_override("font", Fonts.bold)
	return b

## Полоска прогресса с тонкой рамкой — общий стиль баров HUD (HP/нагрев/
## опыт/кулдаун). Ничего «тематического» тяжелее рамки — полоски видны
## постоянно во время боя и должны оставаться простыми и читаемыми при
## любой активной теме.
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
