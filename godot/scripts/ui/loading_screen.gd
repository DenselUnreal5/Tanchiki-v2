class_name LoadingScreen
extends Control

## Экран загрузки карты. Появляется мгновенно (без fade-in), чтобы уже
## в первом же кадре закрыть меню до того, как главный поток уйдёт в
## тяжёлую генерацию карты. Пока идёт генерация, кадр "замерзает" на
## этом экране — это нормально; после генерации полоска и точки снова
## оживают, пока WorldView запекает тайлы в кэш и компилируются шейдеры.
## Весь ввод, пока экран на месте, глотается — чтобы вслепую не нажать
## кнопку в меню или карточку перка под ним.

signal finished

const BAR_W := 420.0
const BAR_H := 8.0
const FADE_OUT_SEC := 0.25

var _title: Label
var _sub: Label
var _status: Label
var _tip: Label
var _bar: Dictionary
var _status_text := ""
var _mode_text := ""
var _loc_text := ""
var _progress := 0.0
var _shown_progress := 0.0
var _anim_t := 0.0
var _closing := false

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

	var bg := ColorRect.new()
	bg.color = Cfg.UI_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := UiKit.vbox(14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	_title = UiKit.title(I18n.t("loading.title", {}, "Загрузка").to_upper(), 30, Cfg.UI_TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_sub = UiKit.label("", 15, Cfg.UI_ACCENT, true)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	col.add_child(spacer)

	_bar = UiKit.rounded_bar(BAR_W, BAR_H, Cfg.UI_ACCENT)
	var bar_wrap: Control = _bar["wrap"]
	bar_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(bar_wrap)

	_status = UiKit.label("", 13, Cfg.UI_MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(BAR_W, 0)
	col.add_child(_status)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 28)
	col.add_child(spacer2)

	_tip = UiKit.label(_random_tip(), 13, Cfg.UI_MUTED)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(560, 0)
	col.add_child(_tip)

	set_stage(I18n.t("loading.map", {}, "Генерация карты"), 0.15)

func _ready() -> void:
	grab_focus()

## Название режима — сразу при показе экрана (оно известно заранее).
func set_mode(mode: String) -> void:
	var fallback := mode
	if Cfg.MODES.has(mode):
		fallback = String(Cfg.MODES[mode].get("name", mode))
	_mode_text = I18n.t("mode." + mode, {}, fallback)
	_refresh_sub()

## Локация становится известна только после генерации (при "auto" её
## выбирает сам start_match), поэтому дописывается вторым шагом.
func set_location(loc_id: String) -> void:
	if loc_id == "":
		return
	var loc := Locations.get_location(loc_id)
	var fallback := loc_id
	if not loc.is_empty():
		fallback = ("%s %s" % [String(loc.get("icon", "")), String(loc.get("name", loc_id))]).strip_edges()
	_loc_text = I18n.t("loc." + loc_id, {}, fallback)
	_refresh_sub()

func set_stage(text: String, progress: float) -> void:
	_status_text = text
	_progress = clampf(maxf(progress, _progress), 0.0, 1.0)
	_update_status_label()

## Добиваем полоску до конца, плавно гасим экран и удаляем его.
func finish() -> void:
	if _closing:
		return
	_closing = true
	set_stage(I18n.t("loading.ready", {}, "Готово"), 1.0)
	_shown_progress = 1.0
	_apply_bar()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_OUT_SEC)
	tw.finished.connect(func():
		finished.emit()
		queue_free())

func _process(delta: float) -> void:
	_anim_t += delta
	# Полоска догоняет целевой прогресс плавно, а не рывками.
	_shown_progress = move_toward(_shown_progress, _progress, delta * 1.6)
	_apply_bar()
	_update_status_label()

func _input(event: InputEvent) -> void:
	# Пока грузимся — никакого ввода ни в меню, ни в выбор перка под нами.
	if event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventJoypadButton or event is InputEventJoypadMotion \
			or event is InputEventScreenTouch or event is InputEventAction:
		get_viewport().set_input_as_handled()

func _apply_bar() -> void:
	if _bar.is_empty():
		return
	var fill: ColorRect = _bar["fill"]
	fill.size = Vector2(BAR_W * _shown_progress, BAR_H)

func _update_status_label() -> void:
	if _status == null:
		return
	if _closing:
		_status.text = _status_text
		return
	var dots := int(_anim_t * 3.0) % 4
	_status.text = _status_text + ".".repeat(dots) + " ".repeat(3 - dots)

func _refresh_sub() -> void:
	var parts: Array = []
	if _mode_text != "":
		parts.append(_mode_text)
	if _loc_text != "":
		parts.append(_loc_text)
	_sub.text = "  ·  ".join(parts)

static func _random_tip() -> String:
	if MenuTips.LIST.is_empty():
		return ""
	var entry: Array = MenuTips.LIST[randi() % MenuTips.LIST.size()]
	return I18n.t(String(entry[0]), {}, String(entry[1]))
