# ============================================================================
# ui_root.gd — экраны вне игрового процесса: меню, пауза, выбор перка,
# галерея перков, гараж, статистика, достижения, задания, итоги партии.
#
# Ui ничего не знает о правилах игры: он только показывает данные и сообщает
# о действиях пользователя сигналами.
# ============================================================================
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

## Сколько вариантов показывать при повышении уровня.
const PERK_CHOICES := 3

## Предел мёртвой зоны стика: половина хода. Выше — стик уже не отзывается.
const MAX_DEADZONE := 0.5

## Версия сборки. Источник один — project.godot, чтобы показанное на экране
## и записанное в свойствах .exe не разъезжались.
static func game_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))

var settings := {
	"game_type": "single", "mode": "ffa", "difficulty": "medium",
	"level": 1, "color1": "p1", "color2": "p2",
	# "auto" — погода, время суток и локация выбираются сами.
	"weather": "auto", "daytime": "auto", "location": "auto",
}

var menu_scene: MenuScene

## Ширины панелей меню: слева действия, справа настройки боя.
const MENU_PANEL_W := 400.0
const MENU_SETTINGS_W := 430.0

var _menu: Control
var _menu_panel: ThemedPanel
var _menu_title_box: VBoxContainer
var _menu_title: Label
var _menu_info: RichTextLabel
var _menu_settings: Control
var _menu_settings_panel: ThemedPanel
var _menu_settings_btn: Button
var _hints: RichTextLabel
var _lang_btn: Button

var _net: Control
var _net_body: VBoxContainer
var _net_sub: RichTextLabel
var _net_address := "127.0.0.1"
var _net_error := ""

var _settings: Control
var _settings_body: VBoxContainer
var _settings_sub: RichTextLabel

var _pause: Control
var _perk: Control
var _perk_body: VBoxContainer
var _gameover: Control
var _gameover_panel: ThemedPanel
var _gameover_title: Label
var _gameover_body: VBoxContainer

## Галерея перков, Гараж и Достижения объединены в одну вкладочную оболочку —
## см. _build_hub(). Раньше это были три раздельных оверлея.
var _hub: Control
var _hub_tabs_row: HBoxContainer
var _hub_sub: RichTextLabel
var _hub_body: VBoxContainer
var _hub_active_tab := "gallery"
var _gallery_selected_id := ""
## Узлы дерева и панель описания текущей вкладки галереи — храним, чтобы
## клик по перку (_select_gallery_perk) мог обновить только подсветку и
## описание, не пересобирая список: пересборка создаёт новый list_scroll
## и сбрасывает прокрутку на верх (см. _fill_gallery_tab).
var _gallery_nodes: Dictionary = {}
var _gallery_row: HBoxContainer
var _gallery_detail_panel: Control

var _stats: Control
var _stats_body: VBoxContainer
var _stats_sub: RichTextLabel
var _daily: Control
var _daily_body: VBoxContainer
var _daily_sub: RichTextLabel

var _confirm: ConfirmationDialog

var _last_gameover := {}

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

	_settings = _make_overlay(true)
	_settings_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	_settings_body = _overlay_body(_settings, "settings.title", "⚙ Настройки",
		_settings_sub, func(): close_settings(), 700)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func(): reset_progress_requested.emit())
	add_child(_confirm)

	I18n.language_changed.connect(_on_language_changed)

# ---------------------------------------------------------------- каркас
func _make_overlay(dim: bool) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if dim:
		root.add_child(UiKit.dimmer())
	add_child(root)
	return root

## Стандартная схема оверлея: заголовок, подзаголовок, тело, кнопка «Закрыть».
## Собирает строки настроек боя. Вынесено отдельно, потому что при смене
## языка их надо построить заново: подписи и варианты переводятся один раз
## при создании, а не на каждый кадр.
func _build_menu_settings() -> void:
	for c in _menu_settings.get_children():
		c.queue_free()
	var caption := UiKit.label(I18n.t("menu.selectMode", {}, "⚙️ Выбрать режим").to_upper(),
		12, Cfg.UI_ACCENT, true)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_settings.add_child(caption)

	_menu_settings.add_child(_make_group(I18n.t("menu.gametype", {}, "Тип игры"), "game_type", [
		["single", I18n.t("gametype.single", {}, "1 игрок")],
		["hotseat", I18n.t("gametype.hotseat", {}, "Горячий стул")],
	]))
	_menu_settings.add_child(_make_group(I18n.t("menu.mode", {}, "Режим"), "mode", [
		["ffa", I18n.t("mode.ffa", {}, "Каждый за себя")],
		["ctf", I18n.t("mode.ctf", {}, "Захват флага")],
		["koth", I18n.t("mode.koth", {}, "Царь горы")],
		["defense", I18n.t("mode.defense", {}, "Оборона")],
	]))
	_menu_settings.add_child(_make_group(I18n.t("menu.diff", {}, "Сложность"), "difficulty", [
		["easy", I18n.t("diff.easy", {}, "Легко")],
		["medium", I18n.t("diff.medium", {}, "Средне")],
		["hard", I18n.t("diff.hard", {}, "Сложно")],
	]))
	_menu_settings.add_child(_make_group(I18n.t("menu.level", {}, "Уровень"), "level", [
		[1, "1"], [2, "2"], [3, "3"], [4, "4"], [5, "5"], [-1, "?"],
	]))
	_menu_settings.add_child(_make_group(I18n.t("menu.location", {}, "Локация"), "location", [
		["auto", I18n.t("loc.auto", {}, "Жребий")],
		["city", I18n.t("loc.city", {}, "🏙 Город")],
		["dust", I18n.t("loc.dust", {}, "🏜 Пустошь")],
		["jungle", I18n.t("loc.jungle", {}, "🌴 Джунгли")],
	]))
	_menu_settings.add_child(_make_group(I18n.t("menu.weather", {}, "Погода"), "weather", [
		["auto", I18n.t("wx.auto", {}, "Своя")],
		["clear", I18n.t("wx.clear", {}, "☀ Ясно")],
		["rain", I18n.t("wx.rain", {}, "🌧 Дождь")],
		["fog", I18n.t("wx.fog", {}, "🌫 Туман")],
		["snow", I18n.t("wx.snow", {}, "❄ Снег")],
		["storm", I18n.t("wx.storm", {}, "⛈ Гроза")],
	]))
	_menu_settings.add_child(_make_group(I18n.t("menu.daytime", {}, "Время суток"), "daytime", [
		["auto", I18n.t("tod.auto", {}, "Цикл")],
		["day", I18n.t("tod.day", {}, "☀ День")],
		["dusk", I18n.t("tod.dusk", {}, "🌆 Закат")],
		["night", I18n.t("tod.night", {}, "🌙 Ночь")],
		["midnight", I18n.t("tod.midnight", {}, "🌑 Полночь")],
	]))
	_menu_settings.add_child(_make_color_group(I18n.t("menu.color1", {}, "Цвет танка 1"), "color1"))
	_menu_settings.add_child(_make_color_group(I18n.t("menu.color2", {}, "Цвет танка 2"), "color2"))


## @param title_key ключ перевода заголовка. Именно ключ, а не готовая
##        строка: заголовок и кнопка «Закрыть» собираются один раз при
##        запуске, и при смене языка их надо перевести заново.
func _overlay_body(root: Control, title_key: String, title_fallback: String,
		sub: Control, on_close: Callable, width: float = 760.0) -> VBoxContainer:
	var title_text := I18n.t(title_key, {}, title_fallback)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width, 0)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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

## Шапка хаба (вкладки + подзаголовок) больше не входит в scroll (см.
## _build_hub) — из общего бюджета высоты для неё нужно вычесть примерное
## место, иначе панель хаба вылезет за экран на ту же величину.
const HUB_HEADER_H := 90.0

## Общий бюджет высоты тела хаба (одинаковый на всех трёх вкладках, см.
## _resize_hub_scroll) — используется и для внешнего hub_scroll, и для
## внутреннего list_scroll галереи (_fill_gallery_tab), чтобы список перков
## занимал ровно ту же высоту, а не оставлял пустой промежуток перед «Закрыть».
func _hub_body_budget() -> float:
	var screen := get_viewport_rect().size
	return maxf(minf(screen.y * 0.86, 900.0) - HUB_HEADER_H, 200.0)

func _resize_overlays() -> void:
	var screen := get_viewport_rect().size
	for root in [_stats, _daily, _settings, _net, _gameover]:
		if root == null or not root.has_meta("scroll"):
			continue
		var scroll: ScrollContainer = root.get_meta("scroll")
		scroll.custom_minimum_size.y = minf(screen.y * 0.86, 900.0)
	_resize_hub_scroll()

## Высота тела хаба — фиксированный бюджет, ОДИНАКОВЫЙ для всех трёх
## вкладок (не зависит от содержимого конкретной вкладки): панель не должна
## менять размер и прыгать при переключении вкладок или выборе перка —
## только один и тот же прямоугольник, внутри которого короткие вкладки
## оставляют немного пустого места снизу списка, а длинные прокручиваются.
## Вызывается и при ресайзе окна, и после перестройки вкладки.
func _resize_hub_scroll() -> void:
	if _hub == null or not _hub.has_meta("scroll"):
		return
	var scroll: ScrollContainer = _hub.get_meta("scroll")
	scroll.custom_minimum_size.y = _hub_body_budget()

## Раскладка главного меню.
##
## Заголовок сверху по центру, слева панель действий, справа от неё —
## раскрывающиеся настройки боя. Прокрутки нет: обе панели по высоте
## считаются от содержимого и целиком помещаются в окно.
func _layout_menu() -> void:
	if _menu_panel == null:
		return
	var screen := get_viewport_rect().size
	var top := 128.0 if screen.y >= 640.0 else 92.0

	# Заголовок масштабируется вместе с шириной окна (как clamp() в CSS).
	if _menu_title != null:
		_menu_title.add_theme_font_size_override("font_size", clampi(int(screen.x * 0.042), 28, 54))
		_menu_title_box.offset_top = 18.0 if screen.y >= 640.0 else 8.0
		_menu_title_box.offset_bottom = _menu_title_box.offset_top + 110.0

	var left_h: float = _menu_panel.get_combined_minimum_size().y
	_menu_panel.size = Vector2(MENU_PANEL_W, left_h)
	_menu_panel.position = Vector2(26, _panel_y(screen, left_h, top))

	var set_h: float = _menu_settings_panel.get_combined_minimum_size().y
	_menu_settings_panel.size = Vector2(MENU_SETTINGS_W, set_h)
	var set_x := 26.0 + MENU_PANEL_W + 18.0
	# На узком окне настройки прижимаются к правому краю, чтобы не уехать за экран.
	if set_x + MENU_SETTINGS_W > screen.x - 16.0:
		set_x = maxf(16.0, screen.x - MENU_SETTINGS_W - 16.0)
	_menu_settings_panel.position = Vector2(set_x, _panel_y(screen, set_h, top))

## Вертикальное центрирование панели с учётом заголовка и краёв экрана.
func _panel_y(screen: Vector2, height: float, top: float) -> float:
	var centered := screen.y * 0.5 - height * 0.5 + 26.0
	return clampf(centered, top, maxf(top, screen.y - height - 16.0))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_overlays()
		_layout_menu()

# ================================================================== МЕНЮ
func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)

	# Анимированный фон: сетка, развёртка радара и настоящий танк игрока.
	menu_scene = MenuScene.new()
	menu_scene._settings = settings
	_menu.add_child(menu_scene)

	# ---- заголовок ----
	_menu_title_box = VBoxContainer.new()
	_menu_title_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_menu_title_box.offset_top = 18
	_menu_title_box.offset_bottom = 128
	_menu_title_box.add_theme_constant_override("separation", 2)
	_menu_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(_menu_title_box)

	_menu_title = UiKit.title("ТЯНЧИКИ", 46, Cfg.UI_TEXT)
	_menu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_title_box.add_child(_menu_title)
	var sub := UiKit.title("BATTLE TANKS", 12, Color(Cfg.UI_MUTED, 0.75))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_title_box.add_child(sub)

	# ---- левая панель: профиль, старт, разделы ----
	_menu_panel = UiKit.panel()
	_menu_panel.custom_minimum_size = Vector2(MENU_PANEL_W, 0)
	# Минимальный размер панели контейнер вычисляет отложенно, поэтому
	# позицию пересчитываем по сигналу, а не один раз при сборке.
	_menu_panel.minimum_size_changed.connect(_layout_menu)
	_menu.add_child(_menu_panel)

	var col := UiKit.vbox(12)
	_menu_panel.add_child(col)

	_menu_info = UiKit.rich("", 11, Cfg.UI_GOLD)
	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel",
		UiKit.flat(Color(1, 0.93, 0.33, 0.06), Cfg.RADIUS_MD, 1, Color(1, 0.93, 0.33, 0.18)))
	info_panel.add_child(_menu_info)
	col.add_child(info_panel)

	_menu_settings_btn = UiKit.secondary(I18n.t("menu.selectMode", {}, "⚙️ Выбрать режим"), 14)
	_menu_settings_btn.custom_minimum_size = Vector2(0, 42)
	_menu_settings_btn.pressed.connect(func():
		_menu_settings_panel.visible = not _menu_settings_panel.visible
		_refresh_mode_button()
		_layout_menu()
		_layout_menu.call_deferred())
	col.add_child(_menu_settings_btn)

	var start := UiKit.primary(I18n.t("menu.start", {}, "И Г Р А Т Ь"), 18)
	start.custom_minimum_size = Vector2(0, 50)
	start.pressed.connect(func(): start_requested.emit())
	col.add_child(start)

	_hints = UiKit.rich("", 10, Color(Cfg.UI_MUTED, 0.6))
	col.add_child(_hints)

	# Версия на виду. Без неё отчёт игрока не к чему привязать: «не работает»
	# без номера сборки не отличить от «не работало в прошлой».
	var ver := UiKit.label("v" + game_version(), 9, Color(Cfg.UI_MUTED, 0.55))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(ver)

	var footer := GridContainer.new()
	footer.columns = 2
	footer.add_theme_constant_override("h_separation", 8)
	footer.add_theme_constant_override("v_separation", 8)
	col.add_child(footer)

	var buttons := [
		[I18n.t("menu.garage", {}, "🔧 Гараж"), func(): open_garage()],
		[I18n.t("menu.gallery", {}, "Галерея перков"), func(): open_gallery()],
		[I18n.t("menu.achievements", {}, "🏅 Достижения"), func(): open_achievements()],
		[I18n.t("menu.daily", {}, "📅 Задания"), func(): open_daily()],
		[I18n.t("menu.stats", {}, "Статистика"), func(): open_stats()],
	]
	for b in buttons:
		var btn := UiKit.secondary(String(b[0]), 13)
		btn.custom_minimum_size = Vector2(0, 38)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(b[1])
		footer.add_child(btn)

	var net_btn := UiKit.secondary(I18n.t("menu.net", {}, "🌐 Сетевая игра"), 13)
	net_btn.custom_minimum_size = Vector2(0, 38)
	net_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	net_btn.pressed.connect(func(): open_net())
	footer.add_child(net_btn)

	var settings_btn := UiKit.secondary(I18n.t("menu.settings", {}, "⚙ Настройки"), 13)
	settings_btn.custom_minimum_size = Vector2(0, 38)
	settings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_btn.pressed.connect(func(): open_settings())
	footer.add_child(settings_btn)

	_lang_btn = UiKit.secondary("", 13)
	_lang_btn.custom_minimum_size = Vector2(0, 38)
	_lang_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lang_btn.pressed.connect(func(): I18n.toggle_lang())
	footer.add_child(_lang_btn)

	var quit_btn := UiKit.secondary(I18n.t("menu.quit", {}, "Выход"), 13)
	quit_btn.custom_minimum_size = Vector2(0, 38)
	quit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_btn.pressed.connect(func(): quit_requested.emit())
	footer.add_child(quit_btn)

	var reset_btn := UiKit.danger(I18n.t("menu.reset", {}, "Сбросить прогресс"), 12)
	reset_btn.custom_minimum_size = Vector2(0, 32)
	reset_btn.pressed.connect(func():
		_confirm.dialog_text = I18n.t("confirm.reset", {},
			"Сбросить весь прогресс профиля? Открытые перки будут потеряны.")
		_confirm.popup_centered())
	col.add_child(reset_btn)

	# ---- правая панель: настройки боя ----
	_menu_settings_panel = UiKit.panel()
	_menu_settings_panel.custom_minimum_size = Vector2(MENU_SETTINGS_W, 0)
	_menu_settings_panel.visible = false
	_menu_settings_panel.minimum_size_changed.connect(_layout_menu)
	_menu.add_child(_menu_settings_panel)

	_menu_settings = UiKit.vbox(11)
	_menu_settings_panel.add_child(_menu_settings)

	_build_menu_settings()

	_refresh_lang_btn()
	_refresh_hints()
	_refresh_mode_button()
	_layout_menu.call_deferred()

## Группа кнопок-переключателей с одним активным значением.
func _make_group(label_text: String, key: String, options: Array) -> VBoxContainer:
	var box := UiKit.vbox(6)
	var l := UiKit.label(label_text.to_upper(), 10, Cfg.UI_MUTED)
	box.add_child(l)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)

	var group := ButtonGroup.new()
	for opt in options:
		var value = opt[0]
		var btn := UiKit.toggle(String(opt[1]))
		btn.button_group = group
		btn.button_pressed = settings[key] == value
		btn.pressed.connect(func():
			settings[key] = value
			if key == "game_type":
				_refresh_hints())
		flow.add_child(btn)
	return box

func _make_color_group(label_text: String, key: String) -> VBoxContainer:
	var box := UiKit.vbox(6)
	box.add_child(UiKit.label(label_text.to_upper(), 10, Color(Cfg.UI_MUTED, 0.55)))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	var group := ButtonGroup.new()
	for skin in Cfg.PLAYER_SKINS:
		var btn := UiKit.toggle(String(skin["key"]).to_upper())
		btn.tooltip_text = I18n.t("skin." + String(skin["key"]), {}, String(skin["name"]))
		btn.button_group = group
		btn.button_pressed = settings[key] == skin["key"]
		var col := Color(String(skin["color"]))
		btn.add_theme_stylebox_override("normal", UiKit.flat(col.darkened(0.35), 999, 1, Color(1, 1, 1, 0.12)))
		btn.add_theme_stylebox_override("hover", UiKit.flat(col.darkened(0.15), 999, 1, Cfg.UI_ACCENT))
		btn.add_theme_stylebox_override("pressed", UiKit.flat(col, 999, 2, Color.WHITE))
		btn.add_theme_stylebox_override("hover_pressed", UiKit.flat(col, 999, 2, Color.WHITE))
		var value: String = skin["key"]
		btn.pressed.connect(func(): settings[key] = value)
		flow.add_child(btn)
	return box

func _refresh_mode_button() -> void:
	var caret := "▴" if _menu_settings_panel.visible else "▾"
	_menu_settings_btn.text = "%s  %s" % [I18n.t("menu.selectMode", {}, "⚙️ Выбрать режим"), caret]

## Подпись кнопки языка показывает целевой язык.
func _refresh_lang_btn() -> void:
	_lang_btn.text = I18n.t("menu.lang.ru", {}, "🌐 English") if I18n.lang == "ru" \
		else I18n.t("menu.lang.en", {}, "🌐 Русский")

## Подсказки по управлению зависят от выбранного типа игры.
func _refresh_hints() -> void:
	var move := I18n.t("hint.p1.move", {}, "движение")
	var fire := I18n.t("hint.p1.fire", {}, "выстрел")
	var mine := I18n.t("hint.p1.mine", {}, "мина")
	var rows := []
	# Подсказка обязана соответствовать выбранному устройству: игроку
	# с геймпадом бесполезно читать про WASD.
	rows.append(_hint_row(I18n.t("player1", {}, "Игрок 1"), Sets.p1_device, 0,
		move, fire, mine))
	if settings["game_type"] == "hotseat":
		rows.append(_hint_row(I18n.t("player2", {}, "Игрок 2"), Sets.p2_device, 1,
			move, fire, mine))
	rows.append("[P]/[Esc] %s · [Tab] %s" % [
		I18n.t("hint.pause", {}, "пауза"), I18n.t("hint.scoreboard", {}, "табло")])
	_hints.text = "[center]" + "\n".join(rows) + "[/center]"

## Строка подсказки под выбранное устройство игрока.
func _hint_row(who: String, device: String, index: int,
		move: String, fire: String, mine: String) -> String:
	if device.begins_with("pad"):
		return "[b]%s:[/b] [%s] %s · [%s] %s · [RT] %s · [LT] %s · [LB] %s" % [
			who,
			I18n.t("hint.pad.stickL", {}, "левый стик"), I18n.t("hint.pad.move", {}, "движение"),
			I18n.t("hint.pad.stickR", {}, "правый стик"), I18n.t("hint.pad.aim", {}, "прицел"),
			I18n.t("hint.pad.fire", {}, "выстрел"), I18n.t("hint.pad.mine", {}, "мина"),
			I18n.t("hint.pad.dash", {}, "рывок")]
	var keys_only := device == Sets.DEV_KEYS or (device == Sets.DEV_AUTO and index == 1)
	if keys_only:
		return "[b]%s:[/b] [↑][←][↓][→] %s · [<][>] %s · [Num 0] %s · [Num .] %s" % [
			who, move, I18n.t("hint.p2.turret", {}, "башня"), fire, mine]
	return "[b]%s:[/b] [W][A][S][D] %s · [%s] %s · [ЛКМ] %s · [E] %s · [Shift] %s" % [
		who, move,
		I18n.t("hint.p1.aim", {}, "мышь"), I18n.t("hint.p1.aim2", {}, "прицел"),
		fire, mine, I18n.t("hint.p1.dash", {}, "рывок")]

func show_menu() -> void:
	hide_all_overlays()
	_menu.visible = true
	_layout_menu()
	_resize_overlays()
	refresh_profile()
	_refresh_hints()

func _refresh_menu_info() -> void:
	var need := Prof.xp_to_next_level()
	var pct := minf(100.0, float(Prof.global_xp) / float(need) * 100.0)
	_menu_info.text = "[center]%s [b]%d[/b]  ·  %d / %d XP  ·  %s [b]%d[/b] из %d  ·  %s [b]%d 🪙[/b][/center]" % [
		I18n.t("menu.profile", {}, "Профиль: уровень"), Prof.global_level,
		Prof.global_xp, need,
		I18n.t("menu.perks", {}, "перков открыто"), Prof.unlocked.size(), Perks.all().size(),
		I18n.t("menu.coins", {}, "монет"), Prof.money]
	_menu_info.custom_minimum_size.y = 18.0 + pct * 0.0

func refresh_profile() -> void:
	_refresh_menu_info()

func hide_all_overlays() -> void:
	for c in [_menu, _pause, _perk, _gameover, _hub, _stats, _daily, _settings, _net]:
		if c != null:
			c.visible = false

# ================================================================== ПАУЗА
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

func show_pause() -> void:
	_pause.visible = true

func hide_pause() -> void:
	_pause.visible = false

# ============================================================ ВЫБОР ПЕРКА
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

## Показывает выбор перка для конкретного игрока.
## Последняя предложенная тройка перков — для тестов и отладки.
var last_perk_choices: Array = []

## Выбранный транспорт сетевой игры: steam | direct.
var _net_kind := "steam"

## Ставит выбранный транспорт в Net. Ошибку показываем в самом окне, а не
## всплывающим сообщением: игрок сейчас смотрит именно сюда.
func _apply_net_kind() -> void:
	var t: NetTransport = NetTransport.SteamTransport.new() if _net_kind == "steam" 		else NetTransport.EnetTransport.new(Net.PORT)
	if not t.available():
		_net_kind = "direct"
		t = NetTransport.EnetTransport.new(Net.PORT)
	Net.transport = t
	# Адрес от другого транспорта здесь бессмыслен: IP не SteamID и наоборот.
	# Проверка стоит здесь, а не только в обработчике переключателя, потому
	# что умолчание 127.0.0.1 висело бы в поле и при первом открытии окна.
	var looks_like_ip := _net_address.find(".") >= 0
	if _net_address != "" and looks_like_ip == (_net_kind == "steam"):
		_net_address = ""

func show_perk_select(player, queue_left: int, rng: Rng) -> void:
	# В режимах с запретами («Амфибия» в «Царе горы») такие перки не предлагаем:
	# иначе игрок получит перк, который просто не работает.
	var available := []
	for id in Prof.available_perk_ids():
		if player.has_perk(id):
			continue
		if not Perks.is_perk_allowed_in_mode(id, String(settings["mode"])):
			continue
		available.append(id)
	var choices := rng.shuffled(available).slice(0, PERK_CHOICES)
	# Предложенная тройка остаётся доступной снаружи: по ней тест снимков
	# ищет расклад с активным перком, не повторяя логику отбора у себя.
	last_perk_choices = choices

	for c in _perk_body.get_children():
		c.queue_free()

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
	else:
		var grid := UiKit.hbox(12)
		grid.alignment = BoxContainer.ALIGNMENT_CENTER
		_perk_body.add_child(grid)
		for id in choices:
			grid.add_child(_perk_card(player, id))

	# Экипированные — можно снять.
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
			var chip := UiKit.secondary("%s %s ✕" % [perk["icon"], I18n.dn(perk, "name", "perk")], 11)
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

	_perk.visible = true

func _perk_card(player, id: String) -> Control:
	var perk := Perks.get_perk(id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(170, 130)
	var normal := UiKit.flat(Color("#161616"), Cfg.RADIUS_MD, 2, Cfg.UI_BORDER)
	var hover := UiKit.flat(Color("#1c1c1c"), Cfg.RADIUS_MD, 2, Cfg.UI_GOLD)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(func(): perk_chosen.emit(player, id))

	var box := UiKit.vbox(4)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	var icon := UiKit.label(String(perk["icon"]), 28)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(icon)

	var name_label := UiKit.label(I18n.dn(perk, "name", "perk"), 12, Color.WHITE, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)

	# Активный перк надо отличать до выбора, а не после: остальные работают
	# сами, а этот бесполезен, если не знать клавишу.
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
	desc.custom_minimum_size = Vector2(150, 0)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(desc)
	return btn

func hide_perk_select() -> void:
	_perk.visible = false

# ============================================================ АРСЕНАЛ (вкладки)
## Галерея перков, Гараж и Достижения были тремя разными оверлеями — теперь
## это вкладки одной панели, оформленной по военно-технической рамке (см.
## план реформы интерфейса): верхняя строка вкладок, тело меняется по клику.
func _build_hub() -> void:
	_hub = _make_overlay(true)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hub.add_child(center)

	# Панель без общего скролла вокруг всего: вкладки и подзаголовок должны
	# остаться на месте, пока прокручивается только тело (см. _hub_scroll
	# ниже) — иначе при длинном содержимом (Гараж/Достижения) заголовок
	# уезжает вместе с ним.
	var panel := UiKit.panel()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)

	var box := UiKit.vbox(10)
	panel.add_child(box)

	_hub_tabs_row = HBoxContainer.new()
	box.add_child(_hub_tabs_row)

	_hub_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	box.add_child(_hub_sub)

	var hub_scroll := ScrollContainer.new()
	hub_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(hub_scroll)

	_hub_body = UiKit.vbox(8)
	_hub_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hub_scroll.add_child(_hub_body)

	var close := UiKit.secondary(I18n.t("btn.close", {}, "Закрыть"))
	close.pressed.connect(func(): close_hub())
	var wrap := CenterContainer.new()
	wrap.add_child(close)
	box.add_child(wrap)

	_hub.set_meta("close_button", close)
	_hub.set_meta("scroll", hub_scroll)

	_rebuild_hub_tabs()

## Подписи вкладок собираются заново при каждой перестройке: язык мог
## смениться, отдельно кэшировать их незачем.
func _hub_tab_items() -> Array:
	return [
		{"key": "gallery", "label": I18n.t("menu.gallery", {}, "Галерея перков")},
		{"key": "garage", "label": I18n.t("menu.garage", {}, "🔧 Гараж")},
		{"key": "achievements", "label": I18n.t("menu.achievements", {}, "🏅 Достижения")},
	]

func _rebuild_hub_tabs() -> void:
	var idx := _hub_tabs_row.get_index()
	var parent := _hub_tabs_row.get_parent()
	var new_row := UiKit.plain_tabs(_hub_tab_items(), _hub_active_tab,
		func(key): _switch_hub_tab(key))
	parent.add_child(new_row)
	parent.move_child(new_row, idx)
	_hub_tabs_row.queue_free()
	_hub_tabs_row = new_row

func _switch_hub_tab(key: String) -> void:
	_hub_active_tab = key
	_rebuild_hub_tabs()
	_fill_hub_tab(key)

func _fill_hub_tab(key: String) -> void:
	for c in _hub_body.get_children():
		c.queue_free()
	match key:
		"gallery": _fill_gallery_tab()
		"garage": _fill_garage_tab()
		"achievements": _fill_achievements_tab()
	_resize_hub_scroll()

func _open_hub_tab(key: String) -> void:
	_hub.visible = true
	_switch_hub_tab(key)

func close_hub() -> void:
	_hub.visible = false

## Перевод хаба на смену языка: заголовки вкладок и тело активной вкладки.
## Отдельно от общего цикла в _on_language_changed — у хаба нет единого
## title_key, три экрана внутри него переводятся вместе одним проходом.
func _refresh_hub_language() -> void:
	if _hub == null:
		return
	var btn := _hub.get_meta("close_button") as Button
	if btn != null:
		btn.text = I18n.t("btn.close", {}, "Закрыть")
	_rebuild_hub_tabs()
	if _hub.visible:
		_fill_hub_tab(_hub_active_tab)

# ------------------------------------------------------------ ГАЛЕРЕЯ ПЕРКОВ
func open_gallery() -> void:
	_open_hub_tab("gallery")

func close_gallery() -> void:
	if _hub_active_tab == "gallery":
		close_hub()

var is_gallery_open: bool:
	get: return _hub != null and _hub.visible and _hub_active_tab == "gallery"

## Дерево умений: колонка на категорию (см. Perks.CATEGORIES), узлы сверху
## вниз в порядке открытия по уровню профиля (Perks.unlock_level_of) —
## настоящих рёбер-предпосылок между отдельными перками в данных нет,
## только уровень открытия, поэтому колонка — прямая линейная цепочка,
## а не граф. Категория с более чем тремя перками не растягивается в одну
## длинную колонку, а делится на две узкие рядом (первая половина по
## уровню открытия — в левую, вторая — в правую).
const _GALLERY_MAX_PER_COL := 3

func _fill_gallery_tab() -> void:
	_hub_sub.text = I18n.t("gallery.sub",
		{"lvl": Prof.global_level, "n": Prof.unlocked.size(), "total": Perks.all().size()},
		"Уровень профиля %d · открыто %d из %d" % [Prof.global_level, Prof.unlocked.size(), Perks.all().size()])

	_gallery_nodes.clear()
	var row := UiKit.hbox(16)
	_gallery_row = row
	_hub_body.add_child(row)

	# Список перков — в своём ScrollContainer с ограниченной высотой, а не
	# в общем скролле всего хаба: у категории «Огонь» одной 17 перков,
	# и если бы список и панель описания прокручивались вместе, при
	# просмотре нижних категорий панель описания уезжала бы за край экрана
	# вместе со списком. Так список гуляет сам по себе, а описание справа
	# остаётся на месте и читается при любой прокрутке.
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Та же высота, что и у тела хаба целиком (_hub_body_budget) — иначе
	# список перков (короче панели описания) оставляет пустой промежуток
	# перед кнопкой «Закрыть», а высота вкладки не совпадает с Гаражом/
	# Достижениями.
	list_scroll.custom_minimum_size = Vector2(0, _hub_body_budget())
	row.add_child(list_scroll)

	var left_col := UiKit.vbox(16)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(left_col)

	var first_id := ""
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
		left_col.add_child(band)

		var head := UiKit.section(I18n.t("cat." + String(cat["id"]), {}, String(cat["name"])), cat["color"])
		band.add_child(head)

		var subcols := UiKit.hbox(14)
		band.add_child(subcols)

		var num_cols := ceili(float(perks.size()) / float(_GALLERY_MAX_PER_COL))
		var rows := ceili(float(perks.size()) / float(num_cols))
		for c in num_cols:
			var sub := UiKit.vbox(8)
			subcols.add_child(sub)
			for r in rows:
				var idx := c * rows + r
				if idx >= perks.size():
					break
				if r > 0:
					sub.add_child(_gallery_spine())
				sub.add_child(_gallery_node(perks[idx]))

	if _gallery_selected_id == "" or Perks.get_perk(_gallery_selected_id).is_empty():
		_gallery_selected_id = first_id

	_gallery_detail_panel = _gallery_detail(Perks.get_perk(_gallery_selected_id))
	row.add_child(_gallery_detail_panel)

## Прямая вертикальная связь между двумя узлами одной колонки.
func _gallery_spine() -> Control:
	var wrap := CenterContainer.new()
	var line := ColorRect.new()
	line.color = Color(Cfg.UI_BORDER, 0.85)
	line.custom_minimum_size = Vector2(2, 14)
	wrap.add_child(line)
	return wrap

## Узел дерева — форма зависит от активной темы (см. skill_node.gd), значок
## общий для всех тем (см. perk_icons.gd). Полное описание живёт в панели
## справа (_gallery_detail), сам узел показывает только иконку.
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

## Выбор перка без пересборки списка: полная пересборка (_fill_hub_tab)
## создаёт новый list_scroll и сбрасывает прокрутку на верх (см.
## _fill_gallery_tab) — при простом клике по перку список не должен
## прыгать, меняются только подсветка узла и панель описания справа.
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
	_gallery_detail_panel = _gallery_detail(Perks.get_perk(id))
	_gallery_row.add_child(_gallery_detail_panel)
	_resize_hub_scroll()

## Правая панель: выбранный узел целиком — иконка, название, описание и
## честное состояние (открыт / прогресс задачи / нужный уровень профиля).
## Купить перк за деньги нельзя (в отличие от прообраза-референса) —
## поэтому кнопка тут читается как индикатор состояния, а не CTA.
func _gallery_detail(perk: Dictionary) -> Control:
	var panel := UiKit.panel()
	panel.custom_minimum_size = Vector2(240, 0)
	if perk.is_empty():
		return panel
	var id := String(perk["id"])
	var unlocked := Prof.is_unlocked(id)

	var box := UiKit.vbox(6)
	panel.add_child(box)

	var icon_center := CenterContainer.new()
	icon_center.custom_minimum_size = Vector2(0, 92)
	var icon := PerkIconView.new()
	icon.custom_minimum_size = Vector2(80, 80)
	icon.perk_id = id
	icon.icon_color = Cfg.UI_TEXT if unlocked else Cfg.UI_MUTED
	icon.rough = true
	icon_center.add_child(icon)
	box.add_child(icon_center)
	var name_label := UiKit.label(I18n.dn(perk, "name", "perk"), 15, Color.WHITE, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(208, 0)
	box.add_child(name_label)
	var desc := UiKit.label(I18n.dn(perk, "desc", "perk"), 11, Cfg.UI_MUTED)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(208, 0)
	box.add_child(desc)

	box.add_child(HSeparator.new())

	if unlocked:
		box.add_child(UiKit.unlock_button(I18n.t("gallery.open", {}, "ОТКРЫТ"), "unlocked"))
	elif perk.has("challenge"):
		var pr := Prof.challenge_progress(id)
		var task := I18n.t("perk." + id + ".challenge", {}, String(pr["desc"]))
		var task_label := UiKit.label(task, 10, Cfg.UI_WARN)
		task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		task_label.custom_minimum_size = Vector2(208, 0)
		box.add_child(task_label)
		box.add_child(UiKit.progress_bar(float(pr["current"]) / float(pr["need"]), 200, 5, Cfg.UI_WARN))
		var prog := UiKit.label("%d / %d" % [pr["current"], pr["need"]], 10, Cfg.UI_MUTED)
		prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(prog)
	else:
		var lvl := Perks.unlock_level_of(id)
		box.add_child(UiKit.unlock_button(
			I18n.t("gallery.unlockAt", {"lvl": lvl}, "Откроется на уровне профиля %d" % lvl), "locked"))

	return panel

# ================================================================== ГАРАЖ
func open_garage() -> void:
	_open_hub_tab("garage")

func close_garage() -> void:
	if _hub_active_tab == "garage":
		close_hub()

var is_garage_open: bool:
	get: return _hub != null and _hub.visible and _hub_active_tab == "garage"

func _fill_garage_tab() -> void:
	_hub_sub.text = "[center]" + I18n.t("garage.sub", {"money": Prof.money},
		"Монеты: [b]%d[/b] 🪙 · Улучшения танка действуют на обоих игроков в партии" % Prof.money) + "[/center]"

	for cat in Upgrades.CATEGORIES:
		var ups := []
		for u in Upgrades.LIST:
			if u["category"] == cat["id"]:
				ups.append(u)
		if ups.is_empty():
			continue
		_hub_body.add_child(UiKit.section(I18n.t("cat." + String(cat["id"]), {}, String(cat["name"])), cat["color"]))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for up in ups:
			grid.add_child(_upgrade_card(up))
		_hub_body.add_child(grid)

	# ---- косметика ----
	_hub_body.add_child(UiKit.section(I18n.t("garage.cosmetics", {}, "Косметика"), Cfg.UI_MUTED))
	var type_names := {"camo": "Камуфляж", "hull": "Рисунок", "track": "Гусеницы", "turret": "Башня"}
	for type in Cosmetics.TYPES:
		var t2 := UiKit.label(I18n.t("cos." + type, {}, String(type_names[type])).to_upper(),
			11, Cfg.UI_MUTED, true)
		_hub_body.add_child(t2)
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for c in Cosmetics.by_type(type):
			grid.add_child(_cosmetic_card(c, type))
		_hub_body.add_child(grid)

func _upgrade_card(up: Dictionary) -> Control:
	var level := Prof.upgrade_level(String(up["id"]))
	var maxed := level >= int(up["max_level"])
	var cost := -1 if maxed else Upgrades.cost(up, level)
	var can_buy := not maxed and Prof.money >= cost

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(258, 0)
	var border := Cfg.UI_ACCENT_DIM if maxed else (Color(Cfg.UI_GOLD, 0.45) if can_buy else Cfg.UI_BORDER)
	card.add_theme_stylebox_override("panel", UiKit.card_style(border))

	var row := UiKit.hbox(10)
	card.add_child(row)
	var icon := PerkIconView.new()
	icon.perk_id = "upg_" + String(up["id"])
	icon.icon_color = Cfg.UI_TEXT
	icon.custom_minimum_size = Vector2(26, 26)
	row.add_child(icon)

	var info := UiKit.vbox(3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UiKit.label(I18n.dn(up, "name", "upg"), 11, Color.WHITE, true))
	info.add_child(UiKit.label(I18n.dn(up, "desc", "upg"), 9, Cfg.UI_MUTED))

	# Полоска прогресса улучшения: заполненные сегменты = уровень.
	var segs := UiKit.hbox(2)
	for i in range(1, int(up["max_level"]) + 1):
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(12, 4)
		seg.color = Cfg.UI_GOLD if i <= level else Cfg.UI_BORDER
		segs.add_child(seg)
	info.add_child(segs)

	if maxed:
		row.add_child(UiKit.label(I18n.t("upg.max", {}, "МАКС"), 10, Cfg.UI_ACCENT, true))
	else:
		var buy := UiKit.small(I18n.t("upg.buy", {"price": cost}, "Улучшить · %d 🪙" % cost))
		buy.disabled = not can_buy
		buy.pressed.connect(func():
			if Prof.buy_upgrade(String(up["id"]))["ok"]:
				garage_changed.emit()
				open_garage())
		row.add_child(buy)
	return card

func _cosmetic_card(c: Dictionary, type: String) -> Control:
	var owned := Prof.is_cosmetic_owned(type, String(c["id"]))
	var equipped := String(Prof.cosmetics[type]) == String(c["id"])
	var can_buy := not owned and Prof.money >= int(c["price"])

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(258, 0)
	var border := Cfg.UI_ACCENT_DIM if equipped else (Color(Cfg.UI_GOLD, 0.45) if can_buy else Cfg.UI_BORDER)
	card.add_theme_stylebox_override("panel", UiKit.card_style(border))

	var row := UiKit.hbox(10)
	card.add_child(row)
	var icon := PerkIconView.new()
	icon.perk_id = "cos_%s_%s" % [type, String(c["id"])]
	icon.icon_color = c.get("color", c.get("a", Cfg.UI_TEXT))
	icon.custom_minimum_size = Vector2(26, 26)
	row.add_child(icon)

	var info := UiKit.vbox(3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UiKit.label(I18n.dn(c, "name", "cos." + type), 11, Color.WHITE, true))
	var state := ""
	if owned:
		state = I18n.t("cos.equipped", {}, "Надето") if equipped else I18n.t("cos.owned", {}, "Куплено")
	else:
		state = I18n.t("cos.price", {"price": c["price"]}, "Цена: %d 🪙" % int(c["price"]))
	info.add_child(UiKit.label(state, 9, Cfg.UI_MUTED))

	if owned:
		var equip := UiKit.small(I18n.t("cos.equipped", {}, "Надето") if equipped
			else I18n.t("cos.equip", {}, "Надеть"))
		equip.disabled = equipped
		equip.pressed.connect(func():
			if Prof.equip_cosmetic(type, String(c["id"]))["ok"]:
				garage_changed.emit()
				open_garage())
		row.add_child(equip)
	else:
		var buy := UiKit.small(I18n.t("cos.buy", {"price": c["price"]}, "Купить · %d 🪙" % int(c["price"])))
		buy.disabled = not can_buy
		buy.pressed.connect(func():
			if Prof.buy_cosmetic(type, String(c["id"]))["ok"]:
				garage_changed.emit()
				open_garage())
		row.add_child(buy)
	return card

# ================================================================ СТАТИСТИКА
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

# ================================================================ ДОСТИЖЕНИЯ
func open_achievements() -> void:
	_open_hub_tab("achievements")

func close_achievements() -> void:
	if _hub_active_tab == "achievements":
		close_hub()

var is_achievements_open: bool:
	get: return _hub != null and _hub.visible and _hub_active_tab == "achievements"

func _fill_achievements_tab() -> void:
	var unlocked := []
	var total_reward := 0
	for a in Achievements.LIST:
		if Prof.achievements.has(a["id"]):
			unlocked.append(a)
			total_reward += int(a["reward"])
	_hub_sub.text = "[center]" + I18n.t("achievements.sub",
		{"n": unlocked.size(), "total": Achievements.LIST.size(), "reward": total_reward},
		"Открыто [b]%d[/b] из %d · награда всего [b]%d 🪙[/b]" % [
			unlocked.size(), Achievements.LIST.size(), total_reward]) + "[/center]"

	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_hub_body.add_child(grid)

	for a in Achievements.LIST:
		var done := Prof.achievements.has(a["id"])
		var cur := int(Prof.stats.get(a["stat"], 0))
		var need := int(a["need"])
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(168, 0)
		card.add_theme_stylebox_override("panel",
			UiKit.card_style(Cfg.UI_ACCENT_DIM if done else Cfg.UI_BORDER))
		if not done:
			card.modulate.a = 0.65
		var box := UiKit.vbox(3)
		card.add_child(box)
		var icon := PerkIconView.new()
		icon.perk_id = "ach_" + String(a["id"])
		icon.icon_color = Cfg.UI_TEXT
		icon.custom_minimum_size = Vector2(28, 28)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		var name_label := UiKit.label(I18n.dn(a, "name", "ach"), 11, Color.WHITE, true)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(name_label)
		var desc := UiKit.label(I18n.dn(a, "desc", "ach"), 9, Cfg.UI_MUTED)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(148, 0)
		box.add_child(desc)
		if done:
			var badge := UiKit.label("%d 🪙" % int(a["reward"]), 9, Cfg.UI_GOLD, true)
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(badge)
		else:
			var prog := UiKit.label("%d / %d" % [mini(cur, need), need], 9, Cfg.UI_MUTED)
			prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(prog)
			box.add_child(UiKit.progress_bar(float(cur) / float(need), 148, 3, Cfg.UI_WARN))
		grid.add_child(card)

# ============================================================ ЕЖЕДНЕВНЫЕ
func open_daily() -> void:
	var quests := Daily.selection()
	var done := 0
	for q in quests:
		if bool(Prof.daily_progress(String(q["id"]))["claimed"]):
			done += 1
	_daily_sub.text = "[center]" + I18n.t("daily.sub", {"done": done, "total": quests.size()},
		"Награды сбрасываются в полночь · выполнено [b]%d[/b] из %d" % [done, quests.size()]) + "[/center]"

	for c in _daily_body.get_children():
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

func close_daily() -> void:
	_daily.visible = false

var is_daily_open: bool:
	get: return _daily != null and _daily.visible

# ================================================================== ИТОГИ
func _build_gameover() -> void:
	_gameover = _make_overlay(true)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gameover.add_child(center)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 0)
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
	var to_menu := UiKit.secondary(I18n.t("go.menu", {}, "В меню"), 13)
	to_menu.pressed.connect(func(): menu_requested.emit())
	actions.add_child(to_menu)

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
		var icons := ""
		for id in player.perk_ids:
			icons += Perks.perk_icon(id) + " "
		box.add_child(UiKit.label(icons if icons != "" else "—", 15, Cfg.UI_GOLD))
		players_row.add_child(card)

	var profile_line := UiKit.label(I18n.t("go.profile", {
		"lvl": Prof.global_level, "xp": Prof.global_xp, "need": Prof.xp_to_next_level(),
		"n": Prof.unlocked.size(), "total": Perks.all().size(),
	}, "Профиль: уровень %d, %d/%d XP, перков %d/%d" % [
		Prof.global_level, Prof.global_xp, Prof.xp_to_next_level(),
		Prof.unlocked.size(), Perks.all().size()]), 11, Cfg.UI_GOLD)
	profile_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gameover_body.add_child(profile_line)

	# Награда за партию.
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

	# Итоговая таблица.
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

func hide_game_over() -> void:
	_gameover.visible = false

# ---------------------------------------------------------------- язык
func _on_language_changed() -> void:
	# Заголовки окон и кнопка «Закрыть» живут вне меню: они собираются один
	# раз в _ready и пересборкой меню не затрагиваются. Поэтому в английской
	# игре над сетевым окном оставалась надпись «Сетевая игра».
	for root in [_stats, _daily, _settings, _net, _gameover]:
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
	_refresh_screens()

## Общая пересборка после смены языка или темы интерфейса. Главное меню и
## пауза строятся заново — их кнопки несут цвет, запечённый в StyleBox при
## постройке, одной перерисовки мало; окна вроде настроек/статистики просто
## переоткрываются — они и так собирают тело с нуля при каждом открытии.
func _refresh_screens() -> void:
	var was_menu := _menu.visible
	var settings_open := _menu_settings_panel.visible
	# queue_free() освобождает узел только в конце кадра — до этого старое
	# меню остаётся в дереве. move_child(_menu, 0) ниже кладёт НОВОЕ меню
	# на дно z-порядка (как и задумано, чтобы оверлеи были поверх), но это
	# заодно поднимает ещё живое старое меню НАД новым: на один кадр экран
	# рисует старое (сейчас будет удалено) меню поверх нового, а клик может
	# попасть между ними — по кнопке, которой уже фактически нет. Прячем
	# старое сразу, а не ждём его освобождения.
	_menu.visible = false
	_menu.queue_free()
	_build_menu()
	# Новое меню должно остаться под оверлеями.
	move_child(_menu, 0)
	_menu_settings_panel.visible = settings_open
	_refresh_mode_button()
	_menu.visible = was_menu
	# Позиция левой панели меню считается от get_combined_minimum_size(),
	# который обновляется отложенно через сигнал minimum_size_changed —
	# раскладываем сразу, иначе кнопки на кадр-другой остаются на (0, 0)
	# и не попадают под клик.
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
	# Сетевого окна в этом списке не было — оно единственное оставалось
	# на прежнем языке/теме до закрытия и повторного открытия.
	if _net != null and _net.visible:
		_refresh_net()
	if not _last_gameover.is_empty() and _gameover.visible:
		show_game_over(_last_gameover["result"], _last_gameover["world"], _last_gameover["hotseat"])

## Смена темы интерфейса вживую (см. Sets.ui_theme / Cfg.apply_theme) —
## галерея/гараж/достижения пересобираются полностью (форма узлов дерева
## умений зависит от темы), остальные экраны — через общий _refresh_screens().
func _on_theme_changed() -> void:
	var hub_open := _hub.visible
	var hub_tab := _hub_active_tab
	_hub.visible = false
	_hub.queue_free()
	_hub_active_tab = hub_tab
	_build_hub()
	if hub_open:
		_open_hub_tab(hub_tab)
	_refresh_screens()

# ================================================================ НАСТРОЙКИ
## Собирает экран настроек заново при каждом открытии: значения берутся
## прямо из Sets, поэтому экран всегда показывает текущее состояние.
func open_settings() -> void:
	_settings_sub.text = "[center]" + I18n.t("settings.sub", {},
		"Сохраняются в user://settings.cfg и переживают сброс прогресса") + "[/center]"

	for c in _settings_body.get_children():
		c.queue_free()

	_build_interface_section()
	_build_video_section()
	_build_graphics_section()
	_build_audio_section()

	var reset := UiKit.danger(I18n.t("settings.reset", {}, "Сбросить настройки"), 12)
	reset.pressed.connect(func():
		Sets.reset()
		open_settings())
	var wrap := CenterContainer.new()
	wrap.add_child(reset)
	_settings_body.add_child(wrap)

	_settings.visible = true

## Тема интерфейса переключается вживую и сразу сохраняется — как и все
## остальные настройки здесь (см. README «каждое изменение применяется
## сразу»). Смена формы узлов дерева умений и панелей происходит через
## _on_theme_changed(), которая пересобирает открытые экраны.
func _build_interface_section() -> void:
	_settings_body.add_child(UiKit.section(I18n.t("set.interface", {}, "Интерфейс"), Cfg.UI_MUTED))
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

func _build_video_section() -> void:
	_settings_body.add_child(UiKit.section(I18n.t("set.video", {}, "Видео"), Cfg.UI_MUTED))

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
			# Список разрешений имеет смысл только в оконном режиме.
			open_settings.call_deferred()))

	# Разрешение применимо только в окне: в полноэкранных режимах его
	# задаёт сам монитор.
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

func _build_graphics_section() -> void:
	# ---- управление -----------------------------------------------------
	_settings_body.add_child(UiKit.section(
		I18n.t("set.input", {}, "Управление"), Cfg.UI_MUTED))

	var devices := [
		[Sets.DEV_AUTO, I18n.t("dev.auto", {}, "Как обычно")],
		[Sets.DEV_KBM, I18n.t("dev.kbm", {}, "Клавиатура и мышь")],
		[Sets.DEV_KEYS, I18n.t("dev.keys", {}, "Только клавиатура")],
	]
	for pad in Sets.pads():
		devices.append(["pad%d" % int(pad["id"]),
			"%s %d: %s" % [I18n.t("dev.pad", {}, "Геймпад"), int(pad["id"]) + 1,
				String(pad["name"])]])
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
				Sets.save()
				_refresh_hints()))

	if Sets.pads().is_empty():
		_settings_body.add_child(UiKit.label(
			I18n.t("set.pad.none", {}, "Геймпад не найден. Подключите его и откройте настройки заново."),
			9, Cfg.UI_MUTED))
	else:
		# Ползунок ходит 0..1, а мёртвая зона выше половины хода бессмысленна:
		# стик перестал бы отзываться вовсе. Поэтому шкала сжата вдвое.
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

	_settings_body.add_child(UiKit.section(I18n.t("set.graphics", {}, "Графика"), Cfg.UI_MUTED))

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

func _build_audio_section() -> void:
	_settings_body.add_child(UiKit.section(I18n.t("set.audio", {}, "Звук"), Cfg.UI_MUTED))

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
			# Пример звука сразу после отпускания — иначе громкость
			# приходится подбирать вслепую.
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

# ============================================================ сетевая игра
## Экран собирается заново при каждом изменении лобби: состояние соединения
## меняется редко, а держать ссылки на полтора десятка узлов ради этого
## дороже, чем пересобрать десяток строк.
func open_net() -> void:
	if not Net.lobby_changed.is_connected(_refresh_net):
		Net.lobby_changed.connect(_refresh_net)
		Net.net_error.connect(_on_net_error)
		Net.countdown_changed.connect(_on_countdown_changed)
	_net.visible = true
	_refresh_net()

func close_net() -> void:
	_net.visible = false

var is_net_open: bool:
	get: return _net != null and _net.visible

func _on_net_error(text: String) -> void:
	_net_error = text
	_refresh_net()

## Хост и клиент видят одни и те же секунды — рассылает их Net. Ноль это
## именно тот момент, когда партия обязана начаться, и запускает её только
## хост: у клиента она начнётся сама, когда придёт _rpc_match_start.
##
## Проверка на ноль не зависит от того, открыт ли ещё экран лобби: если
## игрок вернулся в меню, не нажимая «Отключиться», отсчёт всё равно должен
## доиграть до конца, а не зависнуть в фоне навсегда.
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
	# Выбор транспорта. Steam ведёт соединение через релей Valve, поэтому
	# проброс портов не нужен; прямой адрес остаётся для локальной сети.
	var steam_ok := NetTransport.SteamTransport.new().available()
	if not steam_ok and _net_kind == "steam":
		_net_kind = "direct"
	var kinds := [
		["steam", I18n.t("net.kind.steam", {}, "Через Steam")],
		["direct", I18n.t("net.kind.direct", {}, "Прямой адрес")],
	]
	var labels := []
	for k in kinds:
		labels.append(String(k[1]))
	var idx := 0 if _net_kind == "steam" else 1
	_net_body.add_child(UiKit.choice_row(
		I18n.t("net.kind", {}, "Соединение"), labels, idx,
		func(v: int):
			_net_kind = String(kinds[v][0])
			# Адрес от другого транспорта здесь бессмыслен: IP не SteamID
			# и наоборот. Чистим, чтобы игрок не подключался к мусору.
			_apply_net_kind()
			_refresh_net()))
	if not steam_ok:
		_net_body.add_child(UiKit.label(
			I18n.t("net.steam.off", {}, "Steam недоступен в этой сборке — работает только прямой адрес."),
			9, Cfg.UI_MUTED))
	_apply_net_kind()

	_net_body.add_child(UiKit.section(I18n.t("net.new", {}, "Своя игра"), Cfg.UI_MUTED))

	var name_row := UiKit.hbox(8)
	name_row.add_child(UiKit.label(I18n.t("net.name", {}, "Имя"), 12, Cfg.UI_TEXT))
	var name_edit := LineEdit.new()
	name_edit.text = Net.my_name
	name_edit.custom_minimum_size = Vector2(220, 30)
	name_edit.text_changed.connect(func(t: String): Net.my_name = t)
	name_row.add_child(name_edit)
	_net_body.add_child(name_row)

	var host_btn := UiKit.primary(I18n.t("net.host", {}, "Создать игру"), 13)
	host_btn.pressed.connect(func():
		_net_error = ""
		Net.host_game()
		_refresh_net())
	_net_body.add_child(host_btn)
	if _net_kind == "steam":
		var sid := NetTransport.SteamTransport.my_steam_id()
		_net_body.add_child(UiKit.label(
			I18n.t("net.steam.hint", {}, "Соединение идёт через серверы Valve — проброс портов не нужен."),
			9, Cfg.UI_MUTED))
		if sid > 0:
			var id_row := UiKit.hbox(8)
			id_row.add_child(UiKit.label(I18n.t("net.steam.mine", {}, "Ваш SteamID"),
				12, Cfg.UI_TEXT))
			var id_edit := LineEdit.new()
			id_edit.text = str(sid)
			id_edit.editable = false
			id_edit.custom_minimum_size = Vector2(220, 30)
			id_row.add_child(id_edit)
			_net_body.add_child(id_row)
			_net_body.add_child(UiKit.label(
				I18n.t("net.steam.share", {}, "Передайте его тем, кто подключается."),
				9, Cfg.UI_MUTED))
	else:
		_net_body.add_child(UiKit.label(
			I18n.t("net.host.hint", {}, "Порт 8124. В локальной сети остальным нужен ваш адрес, через интернет — проброс порта."),
			9, Cfg.UI_MUTED))

	_net_body.add_child(UiKit.section(I18n.t("net.join.title", {}, "Подключиться"), Cfg.UI_MUTED))
	var addr_row := UiKit.hbox(8)
	addr_row.add_child(UiKit.label(
		I18n.t("net.steam.id", {}, "SteamID хоста") if _net_kind == "steam"
			else I18n.t("net.address", {}, "Адрес"), 12, Cfg.UI_TEXT))
	var addr_edit := LineEdit.new()
	addr_edit.text = _net_address
	addr_edit.custom_minimum_size = Vector2(220, 30)
	addr_edit.text_changed.connect(func(t: String): _net_address = t)
	addr_row.add_child(addr_edit)
	_net_body.add_child(addr_row)

	var join_btn := UiKit.secondary(I18n.t("net.join", {}, "Подключиться"), 13)
	join_btn.pressed.connect(func():
		_net_error = ""
		Net.join_game(_net_address)
		_refresh_net())
	_net_body.add_child(join_btn)

func _build_net_lobby() -> void:
	var role_text := I18n.t("net.role.host", {}, "Вы хост")
	if Net.role != "host":
		role_text = I18n.t("net.role.client", {}, "Вы подключены")
	_net_body.add_child(UiKit.section(role_text, Cfg.UI_ACCENT))

	if Net.lobby.is_empty():
		_net_body.add_child(UiKit.label(I18n.t("net.waiting", {}, "Соединение…"), 12, Cfg.UI_MUTED))
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
		_net_body.add_child(row)

	# Идёт отсчёт — вместо кнопок старта список игроков дополняет большая
	# цифра. Число, а не фраза с числом: «5 секунд»/«2 секунды» требует
	# согласования по-русски, а голая цифра понятна без него на любом языке.
	# «Отключиться» ниже остаётся доступной и здесь — передумать можно
	# в любой момент, а не только пока отсчёт не начался.
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
		var start_btn := UiKit.primary(I18n.t("net.start", {}, "Начать партию"), 13)
		start_btn.pressed.connect(func(): Net.host_begin_countdown())
		_net_body.add_child(start_btn)
		_net_body.add_child(UiKit.label(
			I18n.t("net.start.hint", {}, "Режим, сложность и уровень берутся из вашего меню и объявляются всем."),
			9, Cfg.UI_MUTED))
	else:
		_net_body.add_child(UiKit.label(
			I18n.t("net.wait.host", {}, "Ждём, когда хост начнёт партию."), 11, Cfg.UI_MUTED))

	var leave_btn := UiKit.danger(I18n.t("net.leave", {}, "Отключиться"), 12)
	leave_btn.pressed.connect(func():
		Net.leave()
		_net_error = ""
		_refresh_net())
	_net_body.add_child(leave_btn)
