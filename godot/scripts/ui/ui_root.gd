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
const MENU_SETTINGS_W := 500.0

var _menu: Control
var _menu_panel: ThemedPanel
var _menu_title_box: VBoxContainer
var _menu_title: Label
var _menu_info: RichTextLabel
var _menu_settings: Control
var _menu_settings_panel: ThemedPanel
var _menu_settings_btn: Button

## Крутящаяся подсказка об интерфейсе внизу меню (см. MenuTips).
var _menu_tip: RichTextLabel
var _menu_tip_timer: Timer
var _menu_tip_order: Array = []
var _menu_tip_idx := 0

var _net: Control
var _net_body: VBoxContainer
var _net_sub: RichTextLabel
var _net_address := "127.0.0.1"
var _net_code := ""
var _net_error := ""

var _settings: Control
var _settings_body: VBoxContainer
var _settings_sub: RichTextLabel
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

## Навигация геймпадом/клавиатурой: тема с рамкой фокуса, подсказки по
## кнопкам и стек фокуса для возврата при закрытии оверлеев.
var _nav_theme: Theme
var _pad_hints: Array = []
var _focus_stack: Array = []
var _menu_focus_cache := {}
## Кнопки, на которые ставится фокус при открытии экрана.
var _menu_start_btn: Button
var _pause_resume_btn: Button
var _gameover_replay_btn: Button
## Игрок, которому сейчас показан выбор перка — для отмены по «назад».
var _perk_player = null

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

	# Тема на весь интерфейс несёт ровно одну запись — рамку фокуса кнопки.
	# Её мы и подменяем при смене режима навигации: кольцо для геймпада,
	# пусто для мыши. add_theme_stylebox_override у самих кнопок больше нет
	# (ui_kit.gd:_style_button), поэтому тема доходит до всех.
	_nav_theme = Theme.new()
	theme = _nav_theme
	Sets.ui_input_mode_changed.connect(_apply_nav_mode)
	_apply_nav_mode(Sets.pad_ui)

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

# =============================================== навигация геймпадом/клавой
## Подсказка по кнопкам геймпада внизу экрана. Видна только в режиме
## навигации (см. _apply_nav_mode). Каждая штука регистрируется в _pad_hints.
## adjust — показывать ли «‹↔› изменить» (для экранов с ползунками/списками).
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

## Смена режима навигации: кольцо фокуса и подсказки по кнопкам видны только
## когда последний ввод был не мышью.
func _apply_nav_mode(pad_ui: bool) -> void:
	if _nav_theme != null:
		_nav_theme.set_stylebox("focus", "Button",
			UiKit.focus_ring() if pad_ui else StyleBoxEmpty.new())
		# Слайдеры (громкость/деадзона/тряска и т.п.) — не Button, без этой
		# записи кольцо фокуса на них не рисуется вовсе, падает на
		# невзрачную рамку движка по умолчанию.
		_nav_theme.set_stylebox("focus", "HSlider",
			UiKit.focus_ring() if pad_ui else StyleBoxEmpty.new())
	for strip in _pad_hints:
		if is_instance_valid(strip):
			strip.visible = pad_ui

## Отложенный захват фокуса: большинство экранов сначала строят детей, потом
## ставят visible в том же кадре, а раскладка меню ещё и через call_deferred.
func _grab(ctrl) -> void:
	if is_instance_valid(ctrl):
		ctrl.grab_focus.call_deferred()

## Первый видимый фокусируемый Control в поддереве.
func _first_focusable(node: Node) -> Control:
	if node is Control and node.visible and node.focus_mode != Control.FOCUS_NONE:
		return node
	for c in node.get_children():
		var f := _first_focusable(c)
		if f != null:
			return f
	return null

## Ищет потомка с заданной meta-парой — восстановить фокус на ту же
## карточку после пересборки тела вкладки (см. _switch_hub_tab).
func _find_by_meta(node: Node, meta_key: String, value: String) -> Control:
	if node is Control and node.has_meta(meta_key) and String(node.get_meta(meta_key)) == value:
		return node
	for c in node.get_children():
		var f := _find_by_meta(c, meta_key, value)
		if f != null:
			return f
	return null

## Кнопка вкладки по её ключу (см. UiKit.plain_tabs: set_meta("tab_key", ...)) —
## искать по ключу, а не по тексту подписи, который зависит от языка.
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

## Пока открыт оверлей, вызванный из меню, кнопки меню за его подложкой не
## должны ловить фокус с крестовины (мышь-то ловит подложка, а фокус — нет).
func _set_menu_focusable(on: bool) -> void:
	if on:
		for id in _menu_focus_cache:
			var c = instance_from_id(id)
			if is_instance_valid(c):
				c.focus_mode = _menu_focus_cache[id]
		_menu_focus_cache.clear()
	elif _menu_focus_cache.is_empty() and _menu != null:
		# Уже отключено вложенным оверлеем — не перекэшировать (иначе в кэш
		# попадёт FOCUS_NONE и восстановить будет нечего).
		_cache_focus_off(_menu)

## Есть ли сейчас открытый оверлей, вызванный из меню.
func _any_menu_overlay_open() -> bool:
	for ov in [_settings, _net, _stats, _daily, _hub]:
		if ov != null and ov.visible:
			return true
	return false

## Открытие/закрытие оверлея из меню: подхват и возврат фокуса, глушение
## фокуса кнопок меню за подложкой. Централизованно через visibility_changed,
## чтобы не расставлять по десятку open_/close_ методов.
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

## Линкует ряд кнопок по горизонтали (left/right + next/prev), с переносом.
func _chain_horizontal(btns: Array, wrap: bool = true) -> void:
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

## Линкует ряды по вертикали (top/bottom). rows — Control'ы; для каждого
## берётся его meta("focus_row") либо первый фокусируемый потомок.
func _chain_vertical(rows: Array) -> void:
	var entries := []
	for row in rows:
		if not is_instance_valid(row):
			continue
		var e = row.get_meta("focus_row", null) if row.has_meta("focus_row") else null
		if e == null or not is_instance_valid(e):
			e = _first_focusable(row)
		if e != null:
			entries.append(e)
	for i in entries.size():
		var a: Control = entries[i]
		if i > 0:
			a.focus_neighbor_top = entries[i - 1].get_path()
		if i + 1 < entries.size():
			a.focus_neighbor_bottom = entries[i + 1].get_path()

## «Назад» (Esc / кнопка B): закрывает верхний открытый оверлей. Возвращает
## true, если что-то закрыл. Вызывается из game.gd:_unhandled_input и
## заменяет прежние ветки закрытия по Esc, которые жили там.
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
	# Раскрытая панель настроек боя в меню — сворачиваем.
	if _menu != null and _menu.visible and _menu_settings_panel != null \
			and _menu_settings_panel.visible:
		_menu_settings_panel.visible = false
		_refresh_mode_button()
		_layout_menu()
		_grab(_menu_settings_btn)
		return true
	# Голое главное меню и экран итогов — «назад» не делает ничего.
	return false

## L1/R1 геймпада переключают активную вкладку в открытых Настройках или
## Хабе (Галерея/Гараж/Достижения) — действия заводит settings.gd:
## _ensure_input_actions. В бою те же кнопки заняты рывком/авиаударом
## (сырой опрос в GamepadScheme, не через action) — конфликта нет, вкладки
## открываются только на паузе/в меню, где танк не тикает.
func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("tab_next") or event.is_action_pressed("tab_prev")):
		return
	var dir := 1 if event.is_action_pressed("tab_next") else -1
	if _settings != null and _settings.visible:
		_switch_settings_tab(_neighbor_tab_key(_settings_tab_items(), _settings_active_tab, dir))
		get_viewport().set_input_as_handled()
	elif _hub != null and _hub.visible:
		_switch_hub_tab(_neighbor_tab_key(_hub_tab_items(), _hub_active_tab, dir))
		get_viewport().set_input_as_handled()

## Соседний ключ вкладки по кругу: direction = 1 — следующая, -1 — предыдущая.
func _neighbor_tab_key(items: Array, current: String, direction: int) -> String:
	var idx := 0
	for i in items.size():
		if String(items[i]["key"]) == current:
			idx = i
			break
	idx = (idx + direction + items.size()) % items.size()
	return String(items[idx]["key"])

## Свой повтор ui_down/ui_up, пока направление удерживается: встроенный
## повтор Godot у аналогового стика (в отличие от эха клавиатуры на
## удержание клавиши) не настолько надёжен — зажатый стик мог не
## докручивать длинные списки (Настройки/Гараж/Достижения/Галерея) дальше
## первого шага. Только вертикаль: горизонталь занята слайдерами/
## choice_row («‹↔› изменить») и вводом текста, трогать её не нужно.
## Работает поверх обычной навигации, не вместо неё — первый переход
## фокуса как и раньше делает сам Godot по первому нажатию, задержка
## перед стартом повтора не даёт задвоить этот самый первый шаг.
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
		["frost", I18n.t("loc.frost", {}, "❄ Зима")],
		["exclusion", I18n.t("loc.exclusion", {}, "☢ Зона")],
		["shore", I18n.t("loc.shore", {}, "🌊 Берег")],
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
	_wire_menu_settings_nav.call_deferred()

## Связывает переключатели панели настроек боя для навигации крестовиной:
## внутри группы — по горизонтали с переносом, между группами — по вертикали.
## Автопоиск соседа промахивается через HFlowContainer, поэтому вручную.
func _wire_menu_settings_nav() -> void:
	var groups := []
	for child in _menu_settings.get_children():
		if not (child is VBoxContainer):
			continue
		var flow: Control = null
		for gc in child.get_children():
			if gc is HFlowContainer:
				flow = gc
				break
		if flow == null or flow.get_child_count() == 0:
			continue
		var btns := []
		for b in flow.get_children():
			btns.append(b)
		_chain_horizontal(btns, true)
		child.set_meta("focus_row", btns[0])
		if is_instance_valid(_menu_settings_btn):
			btns[0].focus_neighbor_left = _menu_settings_btn.get_path()
		groups.append(child)
	_chain_vertical(groups)


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
	for root in [_stats, _daily, _net, _gameover]:
		if root == null or not root.has_meta("scroll"):
			continue
		var scroll: ScrollContainer = root.get_meta("scroll")
		scroll.custom_minimum_size.y = minf(screen.y * 0.86, 900.0)
	_resize_hub_scroll()
	_resize_settings_scroll()

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
	_menu_start_btn = start

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

	# Автопоиск соседа Godot промахивается через GridContainer — тот же баг,
	# что и у HFlowContainer в _wire_menu_settings_nav (обрывается после
	# одного шага: стрелками кажется, что зажатие клавиши «не держится»).
	# Прошиваем сетку явно: по строкам горизонтально, по столбцам вертикально.
	var footer_btns := footer.get_children()
	var footer_rows: Array = []
	var fi := 0
	while fi < footer_btns.size():
		var row: Array = footer_btns.slice(fi, mini(fi + footer.columns, footer_btns.size()))
		if row.size() > 1:
			_chain_horizontal(row, false)
		footer_rows.append(row)
		fi += footer.columns
	for col_i in footer.columns:
		var column: Array = []
		for row in footer_rows:
			if col_i < row.size():
				column.append(row[col_i])
		_chain_vertical(column)
	# Вход в сетку сверху и выход снизу — тоже детерминированные, а не
	# автоподбор через геометрию.
	if footer_rows.size() > 0:
		var first_row: Array = footer_rows[0]
		var last_row: Array = footer_rows[footer_rows.size() - 1]
		if is_instance_valid(_menu_start_btn):
			first_row[0].focus_neighbor_top = _menu_start_btn.get_path()
			_menu_start_btn.focus_neighbor_bottom = first_row[0].get_path()
		for b in last_row:
			b.focus_neighbor_bottom = reset_btn.get_path()
		reset_btn.focus_neighbor_top = last_row[0].get_path()

	# ---- правая панель: настройки боя ----
	_menu_settings_panel = UiKit.panel()
	_menu_settings_panel.custom_minimum_size = Vector2(MENU_SETTINGS_W, 0)
	_menu_settings_panel.visible = false
	_menu_settings_panel.minimum_size_changed.connect(_layout_menu)
	_menu.add_child(_menu_settings_panel)

	_menu_settings = UiKit.vbox(11)
	_menu_settings_panel.add_child(_menu_settings)

	_build_menu_settings()

	# ---- подсказка об интерфейсе внизу экрана ----
	# offset_right оставляет угол свободным от танка-декорации в menu_scene.
	var tip_wrap := Control.new()
	tip_wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tip_wrap.offset_left = 26.0
	tip_wrap.offset_right = -220.0
	tip_wrap.offset_top = -30.0
	tip_wrap.offset_bottom = -10.0
	tip_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(tip_wrap)

	_menu_tip = UiKit.rich("", 10, Color(Cfg.UI_MUTED, 0.6))
	_menu_tip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_wrap.add_child(_menu_tip)

	_menu_tip_order = range(MenuTips.LIST.size())
	_menu_tip_order.shuffle()
	_menu_tip_idx = 0
	_show_menu_tip(0)

	_menu_tip_timer = Timer.new()
	_menu_tip_timer.wait_time = 9.0
	_menu_tip_timer.one_shot = false
	_menu_tip_timer.timeout.connect(_advance_menu_tip)
	_menu.add_child(_menu_tip_timer)
	_menu_tip_timer.start()

	_refresh_mode_button()
	_layout_menu.call_deferred()

	_wire_menu_click_sfx(_menu)

## Звук клика на всех кнопках главного меню — один проход по дереву _menu
## (панель настроек боя тоже его ребёнок). Новые кнопки экрана получают звук
## сами, без правки каждого вызова UiKit.*. Меню пересобирается при смене
## темы, поэтому проход повторяется на свежих узлах.
func _wire_menu_click_sfx(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(Sfx.play_ui)
	for child in node.get_children():
		_wire_menu_click_sfx(child)

## Подсказка по индексу в перемешанном порядке (не в исходном списке —
## иначе одна и та же подсказка каждый раз шла бы первой).
func _show_menu_tip(order_idx: int) -> void:
	if _menu_tip == null or MenuTips.LIST.is_empty():
		return
	var entry: Array = MenuTips.LIST[_menu_tip_order[order_idx]]
	_menu_tip.text = "[center]" + I18n.t(String(entry[0]), {}, String(entry[1])) + "[/center]"

## Следующая подсказка с плавной сменой — тот же приём затухания, что и
## у баннера в hud.gd. Ранний выход, если меню сейчас не на экране (идёт
## бой или открыт оверлей поверх него) — незачем твинить невидимый текст.
func _advance_menu_tip() -> void:
	if _menu == null or not _menu.visible or _menu_tip == null:
		return
	_menu_tip_idx += 1
	if _menu_tip_idx >= _menu_tip_order.size():
		_menu_tip_idx = 0
		_menu_tip_order.shuffle()
	var idx := _menu_tip_idx
	var tw := create_tween()
	tw.tween_property(_menu_tip, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): _show_menu_tip(idx))
	tw.tween_property(_menu_tip, "modulate:a", 1.0, 0.35)

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
		btn.pressed.connect(func(): settings[key] = value)
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

func show_menu() -> void:
	hide_all_overlays()
	_menu.visible = true
	_layout_menu()
	_resize_overlays()
	refresh_profile()
	_focus_stack.clear()
	_set_menu_focusable(true)
	_grab(_menu_start_btn)

func _refresh_menu_info() -> void:
	var need := Prof.xp_to_next_level()
	var pct := minf(100.0, float(Prof.global_xp) / float(need) * 100.0)
	var rank := Ranks.for_level(Prof.global_level)
	_menu_info.text = "[center]%s %s  ·  %s [b]%d[/b]  ·  %d / %d XP  ·  %s [b]%d[/b] из %d  ·  %s [b]%d 🪙[/b][/center]" % [
		String(rank.get("icon", "")), I18n.dn(rank, "name", "rank"),
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
	box.add_child(_pad_hint_strip())

## Показывает выбор перка для конкретного игрока.
## Последняя предложенная тройка перков — для тестов и отладки.
var last_perk_choices: Array = []

## Выбранный транспорт сетевой игры: steam | direct.
var _net_kind := "steam"
## Свёрнут ли блок «Другие способы подключения» (прямой адрес/SteamID/LAN) на
## экране до подключения — по умолчанию свёрнут, обычному игроку туда лезть
## незачем: единственная кнопка «Создать игру» уже покрывает основной путь.
var _net_advanced_open := false

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
	var first_card: Control = null
	if not choices.is_empty():
		var grid := UiKit.hbox(12)
		grid.alignment = BoxContainer.ALIGNMENT_CENTER
		_perk_body.add_child(grid)
		for id in choices:
			var card := _perk_card(player, id)
			if first_card == null:
				first_card = card
			grid.add_child(card)

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

	_perk_player = player
	_perk.visible = true
	_grab(first_card if first_card != null else skip)

func _perk_card(player, id: String) -> Control:
	var perk := Perks.get_perk(id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(170, 130)
	var normal := UiKit.flat(Color("#161616"), Cfg.RADIUS_MD, 2, Cfg.UI_BORDER)
	var hover := UiKit.flat(Color("#1c1c1c"), Cfg.RADIUS_MD, 2, Cfg.UI_GOLD)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	# Рамка фокуса — от темы UiRoot (кольцо в режиме навигации, пусто в мыши).
	btn.pressed.connect(func(): perk_chosen.emit(player, id))

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
	hub_scroll.follow_focus = true
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
	# Кнопки вкладок теперь фокусируемы (см. UiKit.plain_tabs) — свяжем их
	# по горизонтали, иначе геймпад/клавиатура не смогут переключить вкладку.
	_chain_horizontal(_hub_tabs_row.get_children(), true)

## focus_id — id карточки (см. _find_by_meta/"card_id"), на которую нужно
## вернуть фокус после пересборки, вместо вкладки: используется, когда
## вызов пришёл не от клика по вкладке, а от обновления её же содержимого
## (например покупка улучшения в гараже — фокус должен остаться на той же
## карточке, а не улететь на саму вкладку).
func _switch_hub_tab(key: String, focus_id: String = "") -> void:
	_hub_active_tab = key
	_rebuild_hub_tabs()
	_fill_hub_tab(key)
	if focus_id != "":
		var target := _find_by_meta(_hub_body, "card_id", focus_id)
		_grab(target if target != null else _first_focusable(_hub_body))
	else:
		# Кнопка вкладки, державшая фокус, была пересобрана (queue_free) —
		# без этого фокус геймпадом/клавиатурой улетал в никуда (баг: после
		# смены вкладки не попасть ни в неё, ни дальше в тело).
		_grab(_find_tab_button(_hub_tabs_row, key))

func _fill_hub_tab(key: String) -> void:
	# remove_child() ДО queue_free(): само удаление из дерева отложено
	# только у free(), а _hub_body.get_children() без remove_child() ещё
	# секунду держит вперемешку и старых, и новых детей — из-за этого
	# поиск по meta (_find_by_meta/_first_focusable) мог найти старую,
	# уже обречённую кнопку с тем же card_id вместо только что созданной,
	# и фокус пропадал через кадр, когда её реально удаляли.
	for c in _hub_body.get_children():
		_hub_body.remove_child(c)
		c.queue_free()
	match key:
		"gallery": _fill_gallery_tab()
		"garage": _fill_garage_tab()
		"achievements": _fill_achievements_tab()
	_resize_hub_scroll()

func _open_hub_tab(key: String, focus_id: String = "") -> void:
	_hub.visible = true
	_switch_hub_tab(key, focus_id)

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
	list_scroll.follow_focus = true
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
	# Соседи по фокусу связываются явно (см. ниже) — хаб раньше целиком
	# полагался на автоматический геометрический подбор Godot'ом, а узлы
	# перков и вовсе были недостижимы фокусом (skill_node.gd: FOCUS_NONE).
	# _prev_band_last — нижний узел предыдущей категории, чтобы «вниз» из
	# последней строки можно было уйти в следующую категорию, а не упереться.
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

		var head := UiKit.section(I18n.t("cat." + String(cat["id"]), {}, String(cat["name"])), cat["color"])
		band.add_child(head)

		# Колонки распределены по всей ширине списка (до панели описания
		# справа), а не сжаты к левому краю — иначе при малом числе колонок
		# в категории остаётся пустая полоса перед описанием перка.
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

		# Вертикально — внутри каждого столбца (_chain_vertical принимает сам
		# SkillNode как «строку»: _first_focusable возвращает узел напрямую,
		# раз он и есть фокусируемый контрол).
		for column in columns:
			_chain_vertical(column)
		# Горизонтально — между соседними столбцами на совпадающих строках.
		for c in columns.size() - 1:
			var a: Array = columns[c]
			var b: Array = columns[c + 1]
			for r in mini(a.size(), b.size()):
				a[r].focus_neighbor_right = b[r].get_path()
				b[r].focus_neighbor_left = a[r].get_path()
		# Между категориями — одна связь вниз из прошлой в первый узел этой.
		if _prev_band_last != null and not columns.is_empty() and not columns[0].is_empty():
			var band_first: SkillNode = columns[0][0]
			_prev_band_last.focus_neighbor_bottom = band_first.get_path()
			band_first.focus_neighbor_top = _prev_band_last.get_path()
		if not columns.is_empty() and not columns.back().is_empty():
			_prev_band_last = columns.back().back()

	if _gallery_selected_id == "" or Perks.get_perk(_gallery_selected_id).is_empty():
		_gallery_selected_id = first_id

	_gallery_detail_panel = _gallery_detail(Perks.get_perk(_gallery_selected_id))
	row.add_child(_gallery_detail_panel)

	# Вкладки хаба → первый перк: от вкладок «вниз» сразу попадаешь в список,
	# тем же приёмом, каким это уже сделано для Настроек.
	if _gallery_nodes.has(first_id):
		var top_tab := _find_tab_button(_hub_tabs_row, "gallery")
		if top_tab != null:
			top_tab.focus_neighbor_bottom = _gallery_nodes[first_id].get_path()

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
func open_garage(focus_id: String = "") -> void:
	_open_hub_tab("garage", focus_id)

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
		# Тот же card_id, что и у кнопки «Улучшить» ниже — иначе после
		# покупки ПОСЛЕДНЕГО уровня _find_by_meta (_switch_hub_tab) не
		# находит ничего с этим id, фокус срывается на первую карточку
		# всего экрана вместо того, чтобы остаться на месте.
		var max_wrap := FocusRingPanel.new()
		max_wrap.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		max_wrap.set_meta("card_id", "upg_" + String(up["id"]))
		max_wrap.add_child(UiKit.label(I18n.t("upg.max", {}, "МАКС"), 10, Cfg.UI_ACCENT, true))
		row.add_child(max_wrap)
	else:
		var buy := UiKit.small(I18n.t("upg.buy", {"price": cost}, "Улучшить · %d 🪙" % cost))
		buy.disabled = not can_buy
		# card_id — чтобы после покупки (тело вкладки пересобирается целиком)
		# фокус вернулся на эту же карточку, а не улетел на вкладку «Гараж»
		# (см. _switch_hub_tab/_find_by_meta).
		var card_id := "upg_" + String(up["id"])
		buy.set_meta("card_id", card_id)
		buy.pressed.connect(func():
			if Prof.buy_upgrade(String(up["id"]))["ok"]:
				garage_changed.emit()
				open_garage(card_id))
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

	# card_id — общий для кнопок «Купить»/«Надеть» одного предмета, чтобы
	# после покупки (кнопка меняется на «Надеть») фокус нашёл её преемницу
	# с тем же id, а не улетел на вкладку «Гараж» (см. _switch_hub_tab/
	# _find_by_meta).
	var card_id := "cos_%s_%s" % [type, String(c["id"])]
	if owned:
		var equip := UiKit.small(I18n.t("cos.equipped", {}, "Надето") if equipped
			else I18n.t("cos.equip", {}, "Надеть"))
		equip.disabled = equipped
		equip.set_meta("card_id", card_id)
		equip.pressed.connect(func():
			if Prof.equip_cosmetic(type, String(c["id"]))["ok"]:
				garage_changed.emit()
				open_garage(card_id))
		row.add_child(equip)
	else:
		var buy := UiKit.small(I18n.t("cos.buy", {"price": c["price"]}, "Купить · %d 🪙" % int(c["price"])))
		buy.disabled = not can_buy
		buy.set_meta("card_id", card_id)
		buy.pressed.connect(func():
			if Prof.buy_cosmetic(type, String(c["id"]))["ok"]:
				garage_changed.emit()
				open_garage(card_id))
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

	# Карточки — FocusRingPanel, а не голый PanelContainer: иначе они вообще
	# недостижимы фокусом геймпада/клавиатуры (см. комментарий у прошивки
	# соседей ниже).
	var cards: Array = []
	for a in Achievements.LIST:
		var done := Prof.achievements.has(a["id"])
		var cur := int(Prof.stats.get(a["stat"], 0))
		var need := int(a["need"])
		var card := FocusRingPanel.new()
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
		cards.append(card)

	# Автопоиск соседа промахивается через HFlowContainer с переменным
	# переносом строк (тот же баг, что и у панели настроек боя, см.
	# _wire_menu_settings_nav) — прошиваем одним кольцом по кругу, чтобы
	# каждая карточка была достижима стиком/клавиатурой без обрывов.
	_chain_horizontal(cards, true)
	if not cards.is_empty():
		var top_tab := _find_tab_button(_hub_tabs_row, "achievements")
		if top_tab != null:
			top_tab.focus_neighbor_bottom = cards[0].get_path()

# ============================================================ ЕЖЕДНЕВНЫЕ
func open_daily() -> void:
	# Пересборка на лету (кнопка «Забрать» тоже вызывает open_daily() —
	# см. ниже) сносит и пересоздаёт весь список карточек, включая ту,
	# что держала фокус — без восстановления геймпад/клавиатура упирались
	# в невалидного владельца фокуса и не могли сдвинуться к следующей
	# награде (тот же приём, что и в open_settings()).
	var was_visible := _daily.visible
	var quests := Daily.selection()
	var done := 0
	for q in quests:
		if bool(Prof.daily_progress(String(q["id"]))["claimed"]):
			done += 1
	_daily_sub.text = "[center]" + I18n.t("daily.sub", {"done": done, "total": quests.size()},
		"Награды сбрасываются в полночь · выполнено [b]%d[/b] из %d" % [done, quests.size()]) + "[/center]"

	# remove_child() ДО queue_free() — см. тот же приём и его причину в
	# _fill_hub_tab(): без него _first_focusable() мог поймать старую,
	# уже обречённую карточку вместо новой, и фокус пропадал через кадр.
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

# ================================================================== ИТОГИ
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

	_grab(_gameover_replay_btn)

func hide_game_over() -> void:
	_gameover.visible = false

# ---------------------------------------------------------------- язык
func _on_language_changed() -> void:
	# Заголовки окон и кнопка «Закрыть» живут вне меню: они собираются один
	# раз в _ready и пересборкой меню не затрагиваются. Поэтому в английской
	# игре над сетевым окном оставалась надпись «Сетевая игра».
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
## Настройки — та же вкладочная оболочка, что и у хаба (Галерея перков/
## Гараж/Достижения, см. _build_hub): ряд вкладок и подзаголовок остаются
## на месте, меняется только тело вкладки в своём скролле. Раньше это был
## один длинный список из пяти секций подряд — четыре вкладки читаются
## заметно легче.
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

	_settings_sub = UiKit.rich("", 11, Cfg.UI_MUTED)
	box.add_child(_settings_sub)

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

## Подписи вкладок собираются заново при каждой перестройке — язык мог
## смениться, отдельно кэшировать их незачем (см. _hub_tab_items).
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
	# Та же причина, что у _switch_hub_tab: кнопка вкладки была пересобрана,
	# фокус без этого пропадал — до самих настроек было не добраться.
	_grab(_find_tab_button(_settings_tabs_row, key))

## Собирает выбранную вкладку заново при каждом переключении: значения
## берутся прямо из Sets, поэтому вкладка всегда показывает текущее
## состояние.
func _fill_settings_tab(key: String) -> void:
	for c in _settings_body.get_children():
		c.queue_free()
	match key:
		"general": _build_general_tab()
		"sound": _build_sound_tab()
		"graphics": _build_graphics_tab()
		"controls": _build_controls_tab()

	# Ряды настроек связываем по вертикали: каждая строка выставляет
	# meta("focus_row") на свой элемент (choice_row/slider_row/switch_row).
	# Внутри choice_row варианты — по горизонтали с переносом. Ряд вкладок
	# сверху — первое звено цепочки: с него «вниз» ведёт в тело вкладки,
	# а свои кнопки внутри ряда линкуются по горизонтали, иначе геймпад/
	# клавиатура не могут переключить вкладку вовсе (FOCUS_NONE раньше).
	_chain_horizontal(_settings_tabs_row.get_children(), true)
	for row in _settings_body.get_children():
		if row.has_meta("focus_flow"):
			var flow: Control = row.get_meta("focus_flow")
			_chain_horizontal(flow.get_children(), true)
	_chain_vertical([_settings_tabs_row] + _settings_body.get_children())
	_resize_settings_scroll()

## Тот же бюджет высоты, что и у тела хаба (см. _hub_body_budget) — форма
## оболочки идентична (ряд вкладок + подзаголовок сверху, тело в скролле).
func _resize_settings_scroll() -> void:
	if _settings == null or not _settings.has_meta("scroll"):
		return
	var scroll: ScrollContainer = _settings.get_meta("scroll")
	scroll.custom_minimum_size.y = _hub_body_budget()

func open_settings() -> void:
	_settings_sub.text = "[center]" + I18n.t("settings.sub", {},
		"Сохраняются в user://settings.cfg и переживают сброс прогресса") + "[/center]"

	var was_visible := _settings.visible
	_settings.visible = true
	_switch_settings_tab(_settings_active_tab)
	# Пересборка на лету (смена темы/режима экрана/языка дёргает
	# open_settings заново) — фокус улетел, вернём на первую строку.
	if was_visible:
		_grab(_first_focusable(_settings_body))

## Перевод настроек на смену языка: кнопка «Закрыть» и подзаголовок живут
## вне переоткрытия вкладки (создаются один раз в _build_settings_shell),
## поэтому переводятся отдельно — тот же приём, что и у хаба
## (_refresh_hub_language).
func _refresh_settings_language() -> void:
	if _settings == null:
		return
	var btn := _settings.get_meta("close_button") as Button
	if btn != null:
		btn.text = I18n.t("btn.close", {}, "Закрыть")

## Тема интерфейса переключается вживую и сразу сохраняется — как и все
## остальные настройки здесь (см. README «каждое изменение применяется
## сразу»). Смена формы узлов дерева умений и панелей происходит через
## _on_theme_changed(), которая пересобирает открытые экраны.
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

	# Кнопка-тумблер, а не выбор: подпись сама показывает целевой язык,
	# на который переключит клик. Тело вкладки и так пересобирается целиком
	# при каждой смене языка (_on_language_changed -> _refresh_screens ->
	# open_settings), отдельно обновлять подпись не нужно.
	var lang_row := UiKit.hbox(8)
	lang_row.add_child(UiKit.label(I18n.t("set.lang", {}, "Язык интерфейса"), 12, Cfg.UI_TEXT))
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

## Экран и графические эффекты вместе — обе прежние секции («Видео» и
## «Графика») про то, как выглядит игра. Два под-заголовка внутри вкладки
## сохраняют границу между ними.
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
			# Список разрешений имеет смысл только в оконном режиме.
			_switch_settings_tab.call_deferred("graphics")))

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

## Действия вкладки «Управление» в порядке отображения — см. Ctl.DEFAULT_KEYS.
const _P1_KEY_ACTIONS := ["p1_up", "p1_down", "p1_left", "p1_right",
	"p1_fire", "p1_mine", "p1_dash", "p1_airstrike", "p1_ability"]
const _P2_KEY_ACTIONS := ["p2_up", "p2_down", "p2_left", "p2_right",
	"p2_turret_left", "p2_turret_right", "p2_fire", "p2_mine", "p2_dash", "p2_ability"]

## Подпись действия — общий словарь понятий: «вперёд»/«огонь»/... читаются
## одной строкой у обоих игроков, различаются только сами клавиши.
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

## Общий обработчик всех keybind_row на вкладке «Управление»: клавиша,
## уже занятая другим действием (любого игрока), не применяется — только
## показывает предупреждение, старая привязка не трогается.
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
		# Подсказка по кнопкам геймпада — раньше висела ещё и строкой под
		# «Играть» на главном экране, убрал оттуда: тут, в настройках
		# геймпада, ей самое место, а не на первом же экране игры.
		_settings_body.add_child(_pad_hint_strip())
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
	var steam_ok := NetTransport.SteamTransport.new().available()

	# Имя игрока — общее для обоих путей подключения.
	var name_row := UiKit.hbox(8)
	name_row.add_child(UiKit.label(I18n.t("net.name", {}, "Имя"), 12, Cfg.UI_TEXT))
	var name_edit := LineEdit.new()
	name_edit.text = Net.my_name
	name_edit.custom_minimum_size = Vector2(220, 30)
	name_edit.text_changed.connect(func(t: String): Net.my_name = t)
	name_row.add_child(name_edit)
	_net_body.add_child(name_row)

	# Входящее приглашение — показываем первым, оно самое срочное.
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
			I18n.t("net.code.creating", {}, "Создаём лобби…") if Net.lobby_pending == "host"
				else I18n.t("net.code.searching", {}, "Подключаемся…"), 11, Cfg.UI_MUTED))

	# --- Основной путь: одна кнопка «Создать игру» (Steam, лобби+код разом) ---
	# Раньше здесь было два разных способа хостинга (пригласить через оверлей
	# Steam / создать по коду) — объединены в Net.host_lobby(): лобби теперь
	# всегда публичное и с кодом, поэтому «Пригласить друга» в лобби всегда
	# рабочая, а код — всегда под рукой как запасной путь.
	var create_btn := UiKit.primary(I18n.t("net.invite.create", {}, "Создать игру"), 13)
	create_btn.disabled = not steam_ok or Net.lobby_pending != ""
	create_btn.pressed.connect(func():
		_net_error = ""
		Net.host_lobby()
		_refresh_net())
	_net_body.add_child(create_btn)
	_net_body.add_child(UiKit.label(
		I18n.t("net.invite.createHint", {},
			"Друга позовёте кнопкой в лобби или через «Join Game» в списке друзей Steam."),
		9, Cfg.UI_MUTED))
	if not steam_ok:
		_net_body.add_child(UiKit.label(
			I18n.t("net.err.noSteamInvite", {}, "Для игры через Steam нужен Steam — ниже прямое подключение."),
			9, Cfg.UI_MUTED))

	# --- Присоединиться по коду от друга ---
	var code_row := UiKit.hbox(8)
	code_row.add_child(UiKit.label(I18n.t("net.code.enter", {}, "Код"), 12, Cfg.UI_TEXT))
	var code_edit := LineEdit.new()
	code_edit.max_length = 4
	code_edit.text = _net_code
	code_edit.placeholder_text = "0000"
	code_edit.custom_minimum_size = Vector2(120, 30)
	code_edit.text_changed.connect(func(t: String):
		var digits := ""
		for c in t:
			if c >= "0" and c <= "9":
				digits += c
		_net_code = digits
		if digits != t:
			code_edit.text = digits
			code_edit.caret_column = digits.length())
	code_row.add_child(code_edit)
	var join_code_btn := UiKit.secondary(I18n.t("net.code.join", {}, "Войти"), 13)
	join_code_btn.disabled = not steam_ok or Net.lobby_pending != ""
	join_code_btn.pressed.connect(func():
		_net_error = ""
		Net.join_by_code(_net_code)
		_refresh_net())
	code_row.add_child(join_code_btn)
	_net_body.add_child(code_row)

	# --- Другие способы: прямой адрес или SteamID (локальная сеть / без Steam) ---
	# Свёрнуто по умолчанию — обычному игроку сюда лезть незачем, единственная
	# кнопка выше уже покрывает основной путь. Раскрывашка — обычная кнопка:
	# отдельного виджета «аккордеон» в UiKit нет и городить его ради одного
	# места не стоит.
	var adv_toggle := UiKit.secondary(
		("▾ " if _net_advanced_open else "▸ ") + I18n.t("net.advanced", {}, "Другие способы подключения"), 12)
	adv_toggle.pressed.connect(func():
		_net_advanced_open = not _net_advanced_open
		_refresh_net())
	_net_body.add_child(adv_toggle)

	if not _net_advanced_open:
		return

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
			_apply_net_kind()
			_refresh_net()))
	_apply_net_kind()

	var host_btn := UiKit.secondary(I18n.t("net.host", {}, "Создать напрямую"), 13)
	host_btn.pressed.connect(func():
		_net_error = ""
		Net.host_game()
		_refresh_net())
	_net_body.add_child(host_btn)
	if _net_kind == "steam":
		var sid := NetTransport.SteamTransport.my_steam_id()
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
	else:
		_net_body.add_child(UiKit.label(
			I18n.t("net.host.hint", {}, "Порт 8124. В локальной сети остальным нужен ваш адрес, через интернет — проброс порта."),
			9, Cfg.UI_MUTED))

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

	# Как позвать второго. «Пригласить друга» реально работает только у
	# Steam-лобби (Net.host_lobby() всегда его ставит) — хост, зашедший через
	# «Создать напрямую» (прямой адрес/SteamID, без матчмейкинга Steam),
	# никакого Steam-лобби не получает, кнопка приглашения там ничего не
	# сделала бы. Ему вместо неё показываем то же самое напоминание об
	# адресе/SteamID, что было на экране до подключения.
	if Net.role == "host" and Net.lobby.size() < Net.MAX_LOBBY:
		if Net._steam_lobby_id != 0:
			var inv_btn := UiKit.primary(I18n.t("net.invite.friend", {}, "Пригласить друга"), 13)
			inv_btn.pressed.connect(func(): Net.invite_overlay())
			_net_body.add_child(inv_btn)
			_net_body.add_child(UiKit.label(
				I18n.t("net.code.label", {}, "или назовите код второму игроку"), 11, Cfg.UI_MUTED))
			var code_big := UiKit.label(Net.lobby_code, 40, Cfg.UI_ACCENT, true)
			code_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			code_big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_net_body.add_child(code_big)
		elif _net_kind == "steam":
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
		# Готовность показываем только для гостей: у хоста своя кнопка старта.
		if int(peer_id) != 1:
			row.add_child(UiKit.label(
				"✓" if bool(info.get("ready", false)) else "…", 12,
				Cfg.UI_ACCENT if bool(info.get("ready", false)) else Cfg.UI_MUTED))
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
		_net_error = ""
		_refresh_net())
	_net_body.add_child(leave_btn)
