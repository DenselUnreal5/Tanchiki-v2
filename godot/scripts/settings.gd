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
	load_settings()
	# Видео применяем отложенно: окно на старте ещё не готово к смене режима.
	apply_video.call_deferred()
	apply_audio()

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
	display_mode = MODE_WINDOWED
	resolution = Vector2i(1280, 720)
	vsync = true
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
