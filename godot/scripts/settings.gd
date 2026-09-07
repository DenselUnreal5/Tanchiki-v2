# ============================================================================
# settings.gd — настройки игры. Автозагрузка «Sets».
#
# Отделены от профиля намеренно: profile.json — это прогресс (уровни, монеты,
# достижения), и сбрасывать вместе с ним громкость и разрешение неправильно.
# Настройки лежат в user://settings.cfg и переживают сброс прогресса.
# ============================================================================
extends Node

const SAVE_PATH := "user://settings.cfg"

## Сообщает интерфейсу и миру, что настройки изменились.
signal changed

# ---------------------------------------------------------------- звук
## Громкости 0..1. Ноль — тишина (шина глушится, а не выкручивается в -80 дБ).
var master_volume := 0.9
var sfx_volume := 0.85
var music_volume := 0.6

# ---------------------------------------------------------------- графика
## Постобработка: 0 — выкл, 1 — градация и виньетка, 2 — плюс свечение.
var fx_quality := 2
## Погодные эффекты (дождь, туман, вспышки молний) поверх мира.
var weather_effects := true
## Их сила, 0..1 — на слабых машинах дождь можно приглушить, не выключая.
var weather_intensity := 1.0
## Цикл дня и ночи: затемнение экрана и ночная тонировка.
var day_night := true
## Тряска экрана от взрывов, 0..1.
var screen_shake := 1.0
## Горящие остовы подбитых танков.
var wrecks := true

# ------------------------------------------------------------- управление
## Устройство игрока: auto | kbm | keys | pad0…pad3.
##
## «auto» — то, что было всегда: первому игроку мышь с клавиатурой, второму
## клавиатура. Как только выбран геймпад, он закрепляется за игроком по
## номеру устройства, иначе в «горячем стуле» оба игрока получали бы ввод
## с одного и того же джойстика.
const DEV_AUTO := "auto"
const DEV_KBM := "kbm"
const DEV_KEYS := "keys"

var p1_device := DEV_AUTO
var p2_device := DEV_AUTO

## Мёртвая зона стиков. В покое стики почти всегда отдают не ноль, и без
## неё танк медленно уезжает сам.
var pad_deadzone := 0.22
## Отдача геймпада на попаданиях и взрывах.
var pad_vibration := true
## Автоприцел геймпада: мягкая доводка к ближайшему врагу, пока игрок целится
## правым стиком. См. input_schemes.gd:GamepadScheme.
var pad_aim_assist := true

## Свои клавиши игроков 1 и 2 — только отличия от Ctl.DEFAULT_KEYS
## (input_schemes.gd), action_id -> физический keycode. Отсутствующий в
## словаре action берёт значение по умолчанию — см. key_for().
var custom_keys: Dictionary = {}

## Действующая клавиша действия (своя, если назначена, иначе дефолт).
func key_for(action: String) -> int:
	if custom_keys.has(action):
		return int(custom_keys[action])
	return int(Ctl.DEFAULT_KEYS.get(action, -1))

func set_key(action: String, keycode: int) -> void:
	custom_keys[action] = keycode
	save()

# ---------------------------------------------------------------- интерфейс
## Визуальная тема интерфейса: noir | military | scifi. См. Cfg.THEMES.
var ui_theme := "military"

## Подключённые геймпады: [{id, name}]. Спрашивается интерфейсом настроек.
func pads() -> Array:
	var out := []
	for id in Input.get_connected_joypads():
		out.append({"id": id, "name": Input.get_joy_name(id)})
	return out

# ---------------------------------------------------------------- видео
const MODE_WINDOWED := 0
const MODE_FULLSCREEN := 1
const MODE_BORDERLESS := 2

var display_mode := MODE_WINDOWED
var resolution := Vector2i(1280, 720)
var vsync := true

## Разрешения, которые предлагаем в меню. Ниже 1024×640 интерфейс уже
## не помещается без прокрутки, поэтому список начинается с него.
const RESOLUTIONS := [
	Vector2i(1024, 640),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

func _ready() -> void:
	_ensure_input_actions()
	load_settings()
	Cfg.apply_theme(ui_theme)
	# Видео применяем отложенно: окно на старте ещё не готово к смене режима.
	apply_video.call_deferred()
	apply_audio()

# ---------------------------------------------------------- действия ввода
## Регистрируем действия геймпада кодом, а не в project.godot: ручная правка
## сериализованных InputEvent хрупка и зависит от версии движка. `ui_up/
## down/left/right` не трогаем — у них уже полный набор по умолчанию
## (крестовина, левый стик, перенос фокуса). `ui_accept`, вопреки видимости,
## кнопки геймпада по умолчанию НЕ получает (только Enter/Space с
## клавиатуры) — навигация фокусом работала, а подтверждение геймпадом
## нет; добавляем кнопку A явно, тем же приёмом, что и ui_cancel ниже.
func _ensure_input_actions() -> void:
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
		_bind_key("pause", KEY_P)
		_bind_key("pause", KEY_ESCAPE)
		_bind_pad("pause", JOY_BUTTON_START)
	if not InputMap.has_action("scoreboard"):
		InputMap.add_action("scoreboard")
		_bind_key("scoreboard", KEY_TAB)
		_bind_pad("scoreboard", JOY_BUTTON_BACK)
	# `ui_cancel` уже есть (Esc) — добавляем к нему кнопку B, не пересобирая.
	if not _action_has_pad("ui_cancel", JOY_BUTTON_B):
		_bind_pad("ui_cancel", JOY_BUTTON_B)
	# `ui_accept` уже есть (Enter/Space) — по умолчанию без геймпада вовсе,
	# добавляем кнопку A, иначе фокус двигается, а подтвердить нечем.
	if not _action_has_pad("ui_accept", JOY_BUTTON_A):
		_bind_pad("ui_accept", JOY_BUTTON_A)

func _bind_key(action: StringName, keycode: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	InputMap.action_add_event(action, e)

func _bind_pad(action: StringName, button: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)

func _action_has_pad(action: StringName, button: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == button:
			return true
	return false

# ------------------------------------------------------- режим навигации
## Последний ввод был не мышью (геймпад или клавиатура) — тогда интерфейс
## рисует рамку фокуса и подсказки по кнопкам. Не сохраняется: на старте
## всегда мышиный режим, поэтому снимки меню и headless-тесты не меняются.
var pad_ui := false
signal ui_input_mode_changed(pad_ui: bool)

## Клавиши, по которым включаем режим навигации: только те, которыми и
## ходят по интерфейсу. Случайная буква (или WASD в бою) режим не трогает.
const _NAV_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB,
	KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_set_pad_ui(true)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_set_pad_ui(true)
	elif event is InputEventKey and event.pressed and event.keycode in _NAV_KEYS:
		_set_pad_ui(true)
	elif event is InputEventMouseButton and event.pressed:
		_set_pad_ui(false)
	elif event is InputEventMouseMotion and event.relative != Vector2.ZERO:
		_set_pad_ui(false)

func _set_pad_ui(v: bool) -> void:
	if v == pad_ui:
		return
	pad_ui = v
	# Возврат к мыши: снимаем фокус, чтобы случайный Space/A не нажал
	# невидимый элемент.
	if not v:
		var vp := get_viewport()
		if vp != null:
			var f := vp.gui_get_focus_owner()
			if f != null:
				f.release_focus()
	ui_input_mode_changed.emit(v)

# ---------------------------------------------------------------- хранилище
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)

	fx_quality = clampi(int(cfg.get_value("video", "fx_quality", fx_quality)), 0, 2)
	weather_effects = bool(cfg.get_value("video", "weather", weather_effects))
	weather_intensity = clampf(float(cfg.get_value("video", "weather_intensity", weather_intensity)), 0.0, 1.0)
	day_night = bool(cfg.get_value("video", "day_night", day_night))
	screen_shake = clampf(float(cfg.get_value("video", "shake", screen_shake)), 0.0, 1.0)
	wrecks = bool(cfg.get_value("video", "wrecks", wrecks))

	display_mode = clampi(int(cfg.get_value("window", "mode", display_mode)), 0, 2)
	var res = cfg.get_value("window", "resolution", resolution)
	if res is Vector2i:
		resolution = res
	vsync = bool(cfg.get_value("window", "vsync", vsync))
	p1_device = String(cfg.get_value("input", "p1_device", p1_device))
	p2_device = String(cfg.get_value("input", "p2_device", p2_device))
	pad_deadzone = clampf(float(cfg.get_value("input", "pad_deadzone", pad_deadzone)), 0.0, 0.6)
	pad_vibration = bool(cfg.get_value("input", "pad_vibration", pad_vibration))
	pad_aim_assist = bool(cfg.get_value("input", "pad_aim_assist", pad_aim_assist))
	var keys = cfg.get_value("input", "custom_keys", {})
	custom_keys = keys if keys is Dictionary else {}
	ui_theme = String(cfg.get_value("ui", "theme", ui_theme))
	if not Cfg.THEMES.has(ui_theme):
		ui_theme = "military"

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("video", "fx_quality", fx_quality)
	cfg.set_value("video", "weather", weather_effects)
	cfg.set_value("video", "weather_intensity", weather_intensity)
	cfg.set_value("video", "day_night", day_night)
	cfg.set_value("video", "shake", screen_shake)
	cfg.set_value("video", "wrecks", wrecks)
	cfg.set_value("window", "mode", display_mode)
	cfg.set_value("window", "resolution", resolution)
	cfg.set_value("window", "vsync", vsync)
	cfg.set_value("input", "p1_device", p1_device)
	cfg.set_value("input", "p2_device", p2_device)
	cfg.set_value("input", "pad_deadzone", pad_deadzone)
	cfg.set_value("input", "pad_vibration", pad_vibration)
	cfg.set_value("input", "pad_aim_assist", pad_aim_assist)
	cfg.set_value("input", "custom_keys", custom_keys)
	cfg.set_value("ui", "theme", ui_theme)
	cfg.save(SAVE_PATH)
	changed.emit()

## Возвращает всё к заводским значениям.
func reset() -> void:
	master_volume = 0.9
	sfx_volume = 0.85
	music_volume = 0.6
	fx_quality = 2
	weather_effects = true
	weather_intensity = 1.0
	day_night = true
	screen_shake = 1.0
	wrecks = true
	p1_device = DEV_AUTO
	p2_device = DEV_AUTO
	pad_deadzone = 0.22
	pad_vibration = true
	pad_aim_assist = true
	custom_keys = {}
	display_mode = MODE_WINDOWED
	resolution = Vector2i(1280, 720)
	vsync = true
	ui_theme = "military"
	Cfg.apply_theme(ui_theme)
	apply_audio()
	apply_video()
	save()

# ---------------------------------------------------------------- применение
func apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Music", music_volume)

func _set_bus(bus_name: String, volume: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	# Полная тишина через mute: linear_to_db(0) даёт -inf и в разных
	# драйверах ведёт себя по-разному.
	AudioServer.set_bus_mute(idx, volume <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.001)))

func apply_video() -> void:
	var win := get_window()
	if win == null:
		return
	match display_mode:
		MODE_FULLSCREEN:
			win.mode = Window.MODE_FULLSCREEN
		MODE_BORDERLESS:
			win.mode = Window.MODE_WINDOWED
			win.borderless = true
			win.size = DisplayServer.screen_get_size()
			win.position = Vector2i.ZERO
		_:
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
			win.size = resolution
			# Центрируем: после смены размера окно иначе уезжает за край.
			var screen := DisplayServer.screen_get_size()
			win.position = (screen - resolution) / 2
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

## Разрешения, которые влезают в текущий экран.
func available_resolutions() -> Array:
	var screen := DisplayServer.screen_get_size()
	var out := []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			out.append(r)
	if out.is_empty():
		out.append(RESOLUTIONS[0])
	return out

## Множитель силы погоды с учётом общего выключателя.
func weather_scale() -> float:
	return weather_intensity if weather_effects else 0.0
