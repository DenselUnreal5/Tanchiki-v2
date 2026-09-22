extends Node

const SAVE_PATH := "user://settings.cfg"

signal changed

var master_volume := 0.9
var sfx_volume := 0.85
var music_volume := 0.6

var fx_quality := 2
var weather_effects := true
var weather_intensity := 1.0
var day_night := true
var screen_shake := 1.0
var wrecks := true

const DEV_AUTO := "auto"
const DEV_KBM := "kbm"
const DEV_KEYS := "keys"

var p1_device := DEV_AUTO
var p2_device := DEV_AUTO

var pad_deadzone := 0.22
var pad_vibration := true
var pad_aim_assist := true

var custom_keys: Dictionary = {}

func key_for(action: String) -> int:
	if custom_keys.has(action):
		return int(custom_keys[action])
	return int(Ctl.DEFAULT_KEYS.get(action, -1))

func set_key(action: String, keycode: int) -> void:
	custom_keys[action] = keycode
	save()

var ui_theme := "military"

func pads() -> Array:
	var out := []
	for id in Input.get_connected_joypads():
		out.append({"id": id, "name": Input.get_joy_name(id)})
	return out

const MODE_WINDOWED := 0
const MODE_FULLSCREEN := 1
const MODE_BORDERLESS := 2

var display_mode := MODE_WINDOWED
var resolution := Vector2i(1280, 720)
var vsync := true

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
	apply_video.call_deferred()
	apply_audio()

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
	if not _action_has_pad("ui_cancel", JOY_BUTTON_B):
		_bind_pad("ui_cancel", JOY_BUTTON_B)
	if not _action_has_pad("ui_accept", JOY_BUTTON_A):
		_bind_pad("ui_accept", JOY_BUTTON_A)
	if not InputMap.has_action("tab_prev"):
		InputMap.add_action("tab_prev")
		_bind_pad("tab_prev", JOY_BUTTON_LEFT_SHOULDER)
	if not InputMap.has_action("tab_next"):
		InputMap.add_action("tab_next")
		_bind_pad("tab_next", JOY_BUTTON_RIGHT_SHOULDER)

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

var pad_ui := false
signal ui_input_mode_changed(pad_ui: bool)

const _NAV_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB,
	KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]

var last_input_pad := false
var last_pad_device := 0
signal last_input_device_changed(pad: bool)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_set_pad_ui(true)
		last_pad_device = event.device
		_set_last_input_pad(true)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_set_pad_ui(true)
		last_pad_device = event.device
		_set_last_input_pad(true)
	elif event is InputEventKey and event.pressed:
		_set_last_input_pad(false)
		if event.keycode in _NAV_KEYS:
			_set_pad_ui(true)
	elif event is InputEventMouseButton and event.pressed:
		_set_pad_ui(false)
		_set_last_input_pad(false)
	elif event is InputEventMouseMotion and event.relative != Vector2.ZERO:
		_set_pad_ui(false)
		_set_last_input_pad(false)

func _set_pad_ui(v: bool) -> void:
	if v == pad_ui:
		return
	pad_ui = v
	if not v:
		var vp := get_viewport()
		if vp != null:
			var f := vp.gui_get_focus_owner()
			if f != null:
				f.release_focus()
	ui_input_mode_changed.emit(v)

func _set_last_input_pad(v: bool) -> void:
	if v == last_input_pad:
		return
	last_input_pad = v
	last_input_device_changed.emit(v)

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

func apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Music", music_volume)

func _set_bus(bus_name: String, volume: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
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
			var screen := DisplayServer.screen_get_size()
			win.position = (screen - resolution) / 2
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

func available_resolutions() -> Array:
	var screen := DisplayServer.screen_get_size()
	var out := []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			out.append(r)
	if out.is_empty():
		out.append(RESOLUTIONS[0])
	return out

func weather_scale() -> float:
	return weather_intensity if weather_effects else 0.0
