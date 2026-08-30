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

var settings := {
	"game_type": "single", "mode": "ffa", "difficulty": "medium",
	"level": 1, "color1": "p1", "color2": "p2",
}

var menu_scene: MenuScene

## Ширины панелей меню: слева действия, справа настройки боя.
const MENU_PANEL_W := 400.0
const MENU_SETTINGS_W := 430.0

var _menu: Control
var _menu_panel: PanelContainer
var _menu_title_box: VBoxContainer
var _menu_title: Label
var _menu_info: RichTextLabel
var _menu_settings: Control
var _menu_settings_panel: PanelContainer
var _menu_settings_btn: Button
var _hints: RichTextLabel
var _lang_btn: Button

var _settings: Control
var _settings_body: VBoxContainer
var _settings_sub: RichTextLabel

var _pause: Control
var _perk: Control
var _perk_body: VBoxContainer
var _gameover: Control
var _gameover_panel: PanelContainer
var _gameover_title: Label
var _gameover_body: VBoxContainer

var _gallery: Control
var _gallery_body: VBoxContainer
var _gallery_sub: Label
var _garage: Control
var _garage_body: VBoxContainer
var _garage_sub: RichTextLabel
var _stats: Control
var _stats_body: VBoxContainer
var _stats_sub: RichTextLabel
var _achievements: Control
var _achievements_body: VBoxContainer
var _achievements_sub: RichTextLabel
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
	_gallery = _make_overlay(true)
	_gallery_sub = UiKit.subtitle("")
	_gallery_body = _overlay_body(_gallery, I18n.t("gallery.title", {}, "Галерея перков"), _gallery_sub,
		func(): close_gallery())
	_garage = _make_overlay(true)
	_garage_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	_garage_body = _overlay_body(_garage, I18n.t("garage.title", {}, "🔧 Гараж"), _garage_sub,
		func(): close_garage(), 880)
	_stats = _make_overlay(true)
	_stats_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	_stats_body = _overlay_body(_stats, I18n.t("stats.title", {}, "Статистика"), _stats_sub,
		func(): close_stats(), 540)
	_achievements = _make_overlay(true)
	_achievements_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	_achievements_body = _overlay_body(_achievements, I18n.t("achievements.title", {}, "🏅 Достижения"),
		_achievements_sub, func(): close_achievements())
	_daily = _make_overlay(true)
	_daily_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	_daily_body = _overlay_body(_daily, I18n.t("daily.title", {}, "📅 Ежедневные задания"),
		_daily_sub, func(): close_daily())
	_settings = _make_overlay(true)
	_settings_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	_settings_body = _overlay_body(_settings, I18n.t("settings.title", {}, "⚙ Настройки"),
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
func _overlay_body(root: Control, title_text: String, sub: Control,
		on_close: Callable, width: float = 760.0) -> VBoxContainer:
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
	root.set_meta("close_button", close)
	root.set_meta("scroll", scroll)
	return body

func _resize_overlays() -> void:
	var screen := get_viewport_rect().size
	for root in [_gallery, _garage, _stats, _achievements, _daily, _settings, _gameover]:
		if root == null or not root.has_meta("scroll"):
			continue
		var scroll: ScrollContainer = root.get_meta("scroll")
		scroll.custom_minimum_size.y = minf(screen.y * 0.86, 900.0)

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

	# Анимированный фон: гроза над разбитым полем боя.
	menu_scene = MenuScene.new()
	_menu.add_child(menu_scene)

	# ---- заголовок ----
	_menu_title_box = VBoxContainer.new()
	_menu_title_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_menu_title_box.offset_top = 18
	_menu_title_box.offset_bottom = 128
	_menu_title_box.add_theme_constant_override("separation", 2)
	_menu_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(_menu_title_box)

	_menu_title = UiKit.title("ТЯНЧИКИ", 46, Color("#eaffea"))
	_menu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_title_box.add_child(_menu_title)
	var sub := UiKit.title("BATTLE TANKS", 12, Color(0.78, 0.84, 0.78, 0.75))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_title_box.add_child(sub)

	# ---- левая панель: профиль, старт, разделы ----
	_menu_panel = _glass_panel()
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
		UiKit.flat(Color(1, 0.93, 0.33, 0.06), 10, 1, Color(1, 0.93, 0.33, 0.18)))
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

	_hints = UiKit.rich("", 10, Color(0.76, 0.80, 0.76, 0.6))
	col.add_child(_hints)

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
	_menu_settings_panel = _glass_panel()
	_menu_settings_panel.custom_minimum_size = Vector2(MENU_SETTINGS_W, 0)
	_menu_settings_panel.visible = false
	_menu_settings_panel.minimum_size_changed.connect(_layout_menu)
	_menu.add_child(_menu_settings_panel)

	_menu_settings = UiKit.vbox(11)
	_menu_settings_panel.add_child(_menu_settings)

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
	_menu_settings.add_child(_make_color_group(I18n.t("menu.color1", {}, "Цвет танка 1"), "color1"))
	_menu_settings.add_child(_make_color_group(I18n.t("menu.color2", {}, "Цвет танка 2"), "color2"))

	_refresh_lang_btn()
	_refresh_hints()
	_refresh_mode_button()
	_layout_menu.call_deferred()

## Полупрозрачная «стеклянная» панель меню.
func _glass_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.043, 0.055, 0.043, 0.86)
	st.set_corner_radius_all(18)
	st.set_border_width_all(1)
	st.border_color = Color(0.33, 0.8, 0.33, 0.22)
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 18
	st.content_margin_left = 20
	st.content_margin_right = 20
	st.content_margin_top = 18
	st.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", st)
	return panel

## Группа кнопок-переключателей с одним активным значением.
func _make_group(label_text: String, key: String, options: Array) -> VBoxContainer:
	var box := UiKit.vbox(6)
	var l := UiKit.label(label_text.to_upper(), 10, Color(0.73, 0.80, 0.73, 0.55))
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
	box.add_child(UiKit.label(label_text.to_upper(), 10, Color(0.73, 0.80, 0.73, 0.55)))
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
	rows.append("[b]%s:[/b] [W][A][S][D] %s · [%s] %s · [ЛКМ] %s · [E] %s · [Shift] %s" % [
		I18n.t("player1", {}, "Игрок 1"), move,
		I18n.t("hint.p1.aim", {}, "мышь"), I18n.t("hint.p1.aim2", {}, "прицел"),
		fire, mine, I18n.t("hint.p1.dash", {}, "рывок")])
	if settings["game_type"] == "hotseat":
		rows.append("[b]%s:[/b] [↑][←][↓][→] %s · [<][>] %s · [Num 0] %s · [Num .] %s" % [
			I18n.t("player2", {}, "Игрок 2"), move,
			I18n.t("hint.p2.turret", {}, "башня"), fire, mine])
	rows.append("[P]/[Esc] %s · [Tab] %s" % [
		I18n.t("hint.pause", {}, "пауза"), I18n.t("hint.scoreboard", {}, "табло")])
	_hints.text = "[center]" + "\n".join(rows) + "[/center]"

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
	for c in [_menu, _pause, _perk, _gameover, _gallery, _garage, _stats,
			_achievements, _daily, _settings]:
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
	var normal := UiKit.flat(Color("#161616"), 10, 2, Color("#333333"))
	var hover := UiKit.flat(Color("#1c1c1c"), 10, 2, Cfg.UI_GOLD)
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

	var desc := UiKit.label(I18n.dn(perk, "desc", "perk"), 10, Color("#8a8a8a"))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(150, 0)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(desc)
	return btn

func hide_perk_select() -> void:
	_perk.visible = false

# ================================================================== ГАЛЕРЕЯ
func open_gallery() -> void:
	_gallery_sub.text = I18n.t("gallery.sub",
		{"lvl": Prof.global_level, "n": Prof.unlocked.size(), "total": Perks.all().size()},
		"Уровень профиля %d · открыто %d из %d" % [Prof.global_level, Prof.unlocked.size(), Perks.all().size()])

	for c in _gallery_body.get_children():
		c.queue_free()

	for cat in Perks.CATEGORIES:
		var perks := []
		for p in Perks.all():
			if p["category"] == cat["id"]:
				perks.append(p)
		if perks.is_empty():
			continue
		_gallery_body.add_child(UiKit.section(I18n.t("cat." + String(cat["id"]), {}, String(cat["name"])), cat["color"]))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for perk in perks:
			grid.add_child(_gallery_card(perk))
		_gallery_body.add_child(grid)

	_gallery.visible = true

func _gallery_card(perk: Dictionary) -> Control:
	var unlocked := Prof.is_unlocked(String(perk["id"]))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(168, 0)
	card.add_theme_stylebox_override("panel",
		UiKit.card_style(Cfg.UI_ACCENT_DIM if unlocked else Color("#2e2e2e")))
	if not unlocked:
		card.modulate.a = 0.65

	var box := UiKit.vbox(3)
	card.add_child(box)

	if unlocked:
		var badge := UiKit.label(I18n.t("gallery.open", {}, "Открыт"), 8, Color("#eaffea"), true)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(badge)

	var icon := UiKit.label(String(perk["icon"]), 24)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(icon)
	var name_label := UiKit.label(I18n.dn(perk, "name", "perk"), 11, Color.WHITE, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	var desc := UiKit.label(I18n.dn(perk, "desc", "perk"), 9, Color("#7d7d7d"))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(148, 0)
	box.add_child(desc)

	if not unlocked:
		if perk.has("challenge"):
			var pr := Prof.challenge_progress(String(perk["id"]))
			var task := I18n.t("perk." + String(perk["id"]) + ".challenge", {}, String(pr["desc"]))
			var task_label := UiKit.label(task, 9, Cfg.UI_WARN)
			task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			task_label.custom_minimum_size = Vector2(148, 0)
			box.add_child(task_label)
			var prog := UiKit.label("%d / %d" % [pr["current"], pr["need"]], 9, Cfg.UI_MUTED)
			prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(prog)
			box.add_child(UiKit.progress_bar(float(pr["current"]) / float(pr["need"]), 148, 3, Cfg.UI_WARN))
		else:
			var lvl := Perks.unlock_level_of(String(perk["id"]))
			var l := UiKit.label(I18n.t("gallery.unlockAt", {"lvl": lvl},
				"Откроется на уровне профиля %d" % lvl), 9, Cfg.UI_WARN)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(148, 0)
			box.add_child(l)
	return card

func close_gallery() -> void:
	_gallery.visible = false

var is_gallery_open: bool:
	get: return _gallery != null and _gallery.visible

# ================================================================== ГАРАЖ
func open_garage() -> void:
	_garage_sub.text = "[center]" + I18n.t("garage.sub", {"money": Prof.money},
		"Монеты: [b]%d[/b] 🪙 · Улучшения танка действуют на обоих игроков в партии" % Prof.money) + "[/center]"

	for c in _garage_body.get_children():
		c.queue_free()

	for cat in Upgrades.CATEGORIES:
		var ups := []
		for u in Upgrades.LIST:
			if u["category"] == cat["id"]:
				ups.append(u)
		if ups.is_empty():
			continue
		_garage_body.add_child(UiKit.section(I18n.t("cat." + String(cat["id"]), {}, String(cat["name"])), cat["color"]))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for up in ups:
			grid.add_child(_upgrade_card(up))
		_garage_body.add_child(grid)

	# ---- косметика ----
	_garage_body.add_child(UiKit.section(I18n.t("garage.cosmetics", {}, "Косметика"), Color("#ff88dd")))
	var type_names := {"camo": "Камуфляж", "hull": "Рисунок", "track": "Гусеницы", "turret": "Башня"}
	for type in Cosmetics.TYPES:
		var t2 := UiKit.label(I18n.t("cos." + type, {}, String(type_names[type])).to_upper(),
			11, Color("#ff88dd"), true)
		_garage_body.add_child(t2)
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for c in Cosmetics.by_type(type):
			grid.add_child(_cosmetic_card(c, type))
		_garage_body.add_child(grid)

	_garage.visible = true

func _upgrade_card(up: Dictionary) -> Control:
	var level := Prof.upgrade_level(String(up["id"]))
	var maxed := level >= int(up["max_level"])
	var cost := -1 if maxed else Upgrades.cost(up, level)
	var can_buy := not maxed and Prof.money >= cost

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(258, 0)
	var border := Cfg.UI_ACCENT_DIM if maxed else (Color(1, 0.84, 0.29, 0.45) if can_buy else Color("#2e2e2e"))
	card.add_theme_stylebox_override("panel", UiKit.card_style(border))

	var row := UiKit.hbox(10)
	card.add_child(row)
	row.add_child(UiKit.label(String(up["icon"]), 22))

	var info := UiKit.vbox(3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UiKit.label(I18n.dn(up, "name", "upg"), 11, Color.WHITE, true))
	info.add_child(UiKit.label(I18n.dn(up, "desc", "upg"), 9, Color("#7d7d7d")))

	# Полоска прогресса улучшения: заполненные сегменты = уровень.
	var segs := UiKit.hbox(2)
	for i in range(1, int(up["max_level"]) + 1):
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(12, 4)
		seg.color = Cfg.UI_GOLD if i <= level else Color("#262626")
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
	var border := Cfg.UI_ACCENT_DIM if equipped else (Color(1, 0.84, 0.29, 0.45) if can_buy else Color("#2e2e2e"))
	card.add_theme_stylebox_override("panel", UiKit.card_style(border))

	var row := UiKit.hbox(10)
	card.add_child(row)
	row.add_child(UiKit.label(String(c["icon"]), 22))

	var info := UiKit.vbox(3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UiKit.label(I18n.dn(c, "name", "cos." + type), 11, Color.WHITE, true))
	var state := ""
	if owned:
		state = I18n.t("cos.equipped", {}, "Надето") if equipped else I18n.t("cos.owned", {}, "Куплено")
	else:
		state = I18n.t("cos.price", {"price": c["price"]}, "Цена: %d 🪙" % int(c["price"]))
	info.add_child(UiKit.label(state, 9, Color("#7d7d7d")))

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

func close_garage() -> void:
	_garage.visible = false

var is_garage_open: bool:
	get: return _garage != null and _garage.visible

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
		var name_label := UiKit.label(label_text, 12, Color("#a8a8a8"))
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
	var unlocked := []
	var total_reward := 0
	for a in Achievements.LIST:
		if Prof.achievements.has(a["id"]):
			unlocked.append(a)
			total_reward += int(a["reward"])
	_achievements_sub.text = "[center]" + I18n.t("achievements.sub",
		{"n": unlocked.size(), "total": Achievements.LIST.size(), "reward": total_reward},
		"Открыто [b]%d[/b] из %d · награда всего [b]%d 🪙[/b]" % [
			unlocked.size(), Achievements.LIST.size(), total_reward]) + "[/center]"

	for c in _achievements_body.get_children():
		c.queue_free()

	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_achievements_body.add_child(grid)

	for a in Achievements.LIST:
		var done := Prof.achievements.has(a["id"])
		var cur := int(Prof.stats.get(a["stat"], 0))
		var need := int(a["need"])
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(168, 0)
		card.add_theme_stylebox_override("panel",
			UiKit.card_style(Cfg.UI_ACCENT_DIM if done else Color("#2e2e2e")))
		if not done:
			card.modulate.a = 0.65
		var box := UiKit.vbox(3)
		card.add_child(box)
		var icon := UiKit.label(String(a["icon"]), 24)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(icon)
		var name_label := UiKit.label(I18n.dn(a, "name", "ach"), 11, Color.WHITE, true)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(name_label)
		var desc := UiKit.label(I18n.dn(a, "desc", "ach"), 9, Color("#7d7d7d"))
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

	_achievements.visible = true

func close_achievements() -> void:
	_achievements.visible = false

var is_achievements_open: bool:
	get: return _achievements != null and _achievements.visible

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
		var border := Color("#2e2e2e")
		if bool(pr["claimed"]):
			border = Cfg.UI_ACCENT_DIM
		elif int(pr["current"]) >= int(pr["need"]):
			border = Color(0.33, 0.8, 0.33, 0.5)
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
		info.add_child(UiKit.label(I18n.dn(q, "desc", "daily"), 9, Color("#7d7d7d")))
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
	_gameover_panel.add_theme_stylebox_override("panel",
		UiKit.panel_style(Cfg.UI_ACCENT if win else Cfg.UI_DANGER))

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

	var reason := UiKit.label(String(result["reason"]), 13, Color("#cccccc"))
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
			I18n.t("go.deaths", {"n": player.deaths}, "Смерти: %d" % player.deaths)], 11, Color("#b0b0b0")))
		if world.mode == "ctf":
			box.add_child(UiKit.label(I18n.t("go.captures", {"n": player.captures},
				"Захваты флага: %d" % player.captures), 11, Color("#b0b0b0")))
		box.add_child(UiKit.label(I18n.t("go.score", {"n": player.score},
			"Счёт: %d" % player.score), 11, Color("#b0b0b0")))
		box.add_child(UiKit.label(I18n.t("go.damage", {"n": int(round(player.damage_dealt))},
			"Урона нанесено: %d" % int(round(player.damage_dealt))), 11, Color("#b0b0b0")))
		box.add_child(UiKit.label(I18n.t("go.sessionLevel", {"n": player.session_level},
			"Уровень в партии: %d" % player.session_level), 11, Color("#b0b0b0")))
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
		var color: Color = Color("#eaffea") if bool(r["is_human"]) else Cfg.UI_TEXT
		grid.add_child(UiKit.label(str(i + 1), 12, color))
		grid.add_child(UiKit.label(String(r["name"]), 12, color))
		grid.add_child(UiKit.label(str(r["kills"]), 12, color))
		grid.add_child(UiKit.label(str(r["deaths"]), 12, color))

func hide_game_over() -> void:
	_gameover.visible = false

# ---------------------------------------------------------------- язык
func _on_language_changed() -> void:
	# Полная пересборка меню — самый надёжный способ применить перевод
	# ко всем подписям сразу.
	var was_menu := _menu.visible
	var settings_open := _menu_settings_panel.visible
	_menu.queue_free()
	_build_menu()
	# Новое меню должно остаться под оверлеями.
	move_child(_menu, 0)
	_menu_settings_panel.visible = settings_open
	_refresh_mode_button()
	_menu.visible = was_menu
	refresh_profile()
	if is_settings_open:
		open_settings()
	if is_gallery_open:
		open_gallery()
	if is_garage_open:
		open_garage()
	if is_stats_open:
		open_stats()
	if is_achievements_open:
		open_achievements()
	if is_daily_open:
		open_daily()
	if not _last_gameover.is_empty() and _gameover.visible:
		show_game_over(_last_gameover["result"], _last_gameover["world"], _last_gameover["hotseat"])

# ================================================================ НАСТРОЙКИ
## Собирает экран настроек заново при каждом открытии: значения берутся
## прямо из Sets, поэтому экран всегда показывает текущее состояние.
func open_settings() -> void:
	_settings_sub.text = "[center]" + I18n.t("settings.sub", {},
		"Сохраняются в user://settings.cfg и переживают сброс прогресса") + "[/center]"

	for c in _settings_body.get_children():
		c.queue_free()

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

func _build_video_section() -> void:
	_settings_body.add_child(UiKit.section(I18n.t("set.video", {}, "Видео"), Color("#44aaff")))

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
	_settings_body.add_child(UiKit.section(I18n.t("set.graphics", {}, "Графика"), Color("#ff8833")))

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
	_settings_body.add_child(UiKit.section(I18n.t("set.audio", {}, "Звук"), Color("#55ff88")))

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
