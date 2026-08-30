# ============================================================================
# audio.gd — процедурные звуковые эффекты, без файлов ассетов. Автозагрузка «Sfx».
#
# Каждый звук собран из нескольких слоёв (см. synth.gd) и существует в
# нескольких вариантах: сорок танков стреляют одновременно, и один и тот же
# буфер, воспроизведённый сорок раз, слышен как пулемёт, а не как бой.
#
# Голос — не просто плеер, а собственная шина с панорамой и фильтром.
# Это нужно ради главного: громкость и «плотность» выстрела зависят от
# расстояния до камеры. Далёкий выстрел тише И глуше — высокие частоты
# в воздухе теряются первыми, и ухо читает это как дистанцию куда лучше,
# чем одна только громкость.
# ============================================================================
extends Node

const MAX_VOICES := 16

## Ближе этого расстояния (в пикселях мира) звук играет в полную силу.
const NEAR_RANGE := 300.0
## Дальше этого не играет вовсе: экономит голоса и убирает кашу боя.
const HEAR_RANGE := 1800.0
## Срез фильтра на максимальной дистанции — «за холмом».
const FAR_CUTOFF := 1100.0

## Не более чем один звук данного типа за столько тиков.
const THROTTLE := {
	"shoot": 2,
	"shoot_heavy": 3,
	"hit": 2,
	"explosion": 3,
	"water": 10,
	"pickup": 0,
	"levelup": 0,
	"flag": 0,
	"unlock": 0,
	"airstrike": 0,
	"crack": 3,
	"crumble": 4,
	"clang": 3,
	# Ход по покрытию: звучит часто, поэтому троттлинг жёсткий.
	"tread_hard": 12,
	"tread_soft": 12,
	"steam": 20,
}

## Базовая громкость события. Выстрел и взрыв — громче всего остального,
## иначе бой не читается.
const LEVEL := {
	"shoot": -7.0,
	"shoot_heavy": -5.0,
	"hit": -11.0,
	"explosion": -4.0,
	"airstrike": -8.0,
	"crack": -10.0,
	"crumble": -9.0,
	"clang": -10.0,
	"tread_hard": -21.0,
	"tread_soft": -21.0,
	"steam": -13.0,
	"water": -12.0,
	"pickup": -9.0,
	"levelup": -8.0,
	"unlock": -8.0,
	"flag": -8.0,
}

## Разброс высоты тона. Мелодичные звуки интерфейса разброса не получают:
## «плывущий» уровень-ап слышится как поломка.
const PITCH_VARY := {
	"shoot": 0.07,
	"shoot_heavy": 0.05,
	"hit": 0.14,
	"explosion": 0.10,
	"crack": 0.16,
	"crumble": 0.12,
	"clang": 0.14,
	"tread_hard": 0.18,
	"tread_soft": 0.18,
	"water": 0.10,
}

var enabled := true
var tick := 0
var _last_played := {}
## type -> Array[AudioStreamWAV]: вариантов у звука может быть несколько.
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _voice_bus: PackedInt32Array = PackedInt32Array()
var _next_player := 0
var _rng := RandomNumberGenerator.new()
## Номер фоновой задачи синтеза: при выходе её надо дождаться, иначе она
## обращается к уже удалённой автозагрузке.
var _task := -1

## Камеры живых игроков. Громкость считается по ближайшей: в «горячем стуле»
## два экрана, и бой у чужого края карты не должен глушить свой.
var _listeners: PackedVector2Array = PackedVector2Array()
var _pan_half := 640.0
## Множитель дальности слышимости от перков игрока. Единица — как было.
var hear_scale := 1.0

func _ready() -> void:
	_rng.randomize()
	_ensure_buses()
	# Синтез идёт в фоне: полсекунды тишины в меню никто не заметит,
	# а полсекунды чёрного экрана на запуске — заметят все.
	_task = WorkerThreadPool.add_task(_build_async)
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SfxV%d" % i
		add_child(p)
		_players.append(p)

## Раздельные шины, чтобы громкость эффектов и музыки регулировалась
## независимо от общей. Создаются кодом: в проекте нет файла раскладки шин,
## и заводить его ради этого незачем.
##
## У каждого голоса своя шина с панорамой и фильтром — иначе расстояние
## можно было бы передать только громкостью.
func _ensure_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		_add_bus(bus_name, "Master")
	_voice_bus.resize(MAX_VOICES)
	for i in MAX_VOICES:
		var idx := _add_bus("SfxV%d" % i, "SFX")
		_voice_bus[i] = idx
		if AudioServer.get_bus_effect_count(idx) == 0:
			AudioServer.add_bus_effect(idx, AudioEffectPanner.new(), 0)
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(idx, lp, 1)

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _add_bus(bus_name: String, send_to: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send_to)
	return idx

func set_enabled(on: bool) -> void:
	enabled = on

## Вызывается один раз за логический тик, чтобы работал троттлинг.
func advance() -> void:
	tick += 1

## Точки прослушивания и половина ширины экрана в мировых пикселях —
## по ней считается панорама.
func set_listeners(points: PackedVector2Array, pan_half: float) -> void:
	_listeners = points
	_pan_half = maxf(64.0, pan_half)

func clear_listeners() -> void:
	_listeners = PackedVector2Array()

# ------------------------------------------------------------------ проигрывание
## Без координат звук считается «своим» (интерфейс, события режима) и играет
## в полную силу по центру.
func play(type: String, x: float = INF, y: float = INF) -> void:
	if not enabled or not _streams.has(type):
		return
	var gap: int = THROTTLE.get(type, 0)
	if gap > 0 and _last_played.has(type) and tick - int(_last_played[type]) < gap:
		return

	var att := 0.0
	var pan := 0.0
	var cutoff := 20000.0
	if x != INF and not _listeners.is_empty():
		var best := _listeners[0]
		var best_d: float = best.distance_to(Vector2(x, y))
		for k in range(1, _listeners.size()):
			var d: float = _listeners[k].distance_to(Vector2(x, y))
			if d < best_d:
				best_d = d
				best = _listeners[k]
		var reach := HEAR_RANGE * hear_scale
		if best_d > reach:
			return
		# Спад громкости — обратная степенная кривая: у самого ствола звук
		# бьёт в полную силу и быстро проваливается на первых экранах.
		att = linear_to_db(1.0 / (1.0 + pow(best_d / NEAR_RANGE, 1.7)))
		var t: float = clampf(best_d / reach, 0.0, 1.0)
		cutoff = lerpf(20000.0, FAR_CUTOFF, t * t)
		pan = clampf((x - best.x) / _pan_half, -1.0, 1.0) * 0.8

	_last_played[type] = tick

	# Круговой пул голосов: самый старый прерывается.
	var i := _next_player
	_next_player = (_next_player + 1) % _players.size()
	var player := _players[i]
	var bus := _voice_bus[i]
	var panner: AudioEffectPanner = AudioServer.get_bus_effect(bus, 0)
	panner.pan = pan
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(bus, 1)
	lp.cutoff_hz = cutoff

	var variants: Array = _streams[type]
	player.stream = variants[_rng.randi() % variants.size()]
	var vary: float = float(PITCH_VARY.get(type, 0.0))
	player.pitch_scale = 1.0 + (_rng.randf() * 2.0 - 1.0) * vary
	player.volume_db = float(LEVEL.get(type, -8.0)) + att
	player.play()

# ---------------------------------------------------------------- генерация
func _build_async() -> void:
	var t0 := Time.get_ticks_msec()
	var built := {}
	_build_streams(built)
	_on_built.call_deferred(built, Time.get_ticks_msec() - t0)

## Готовый набор принимает основной поток: до этого момента play() просто
## ничего не находит и молча выходит.
func _on_built(built: Dictionary, ms: int) -> void:
	_streams = built
	print("[Sfx] звуки собраны за %d мс" % ms)

func _build_streams(_streams: Dictionary) -> void:
	# --- Выстрел танковой пушки. Не «пиу», а тяжёлый калибр: щелчок дульного
	# среза, тело выстрела, низкий гул и докатывающийся раскат.
	_streams["shoot"] = [_cannon(0), _cannon(1), _cannon(2)]
	# Спецоружие бьёт крупнее — тот же выстрел ниже и длиннее.
	_streams["shoot_heavy"] = [_cannon(3), _cannon(4)]
	_streams["explosion"] = [_explosion(0), _explosion(1), _explosion(2)]
	_streams["hit"] = [_hit(0), _hit(1), _hit(2)]
	_streams["airstrike"] = [_airstrike()]

	# --- разрушение построек
	_streams["crack"] = [_wood(0), _wood(1)]
	_streams["crumble"] = [_stone(0), _stone(1)]
	_streams["clang"] = [_metal(0), _metal(1)]

	# --- ход по покрытию
	_streams["tread_hard"] = [_tread(4200.0, 2200.0, 0.06, 41), _tread(3800.0, 1900.0, 0.06, 42)]
	_streams["tread_soft"] = [_tread(1300.0, 480.0, 0.09, 43), _tread(1100.0, 420.0, 0.09, 44)]
	_streams["water"] = [_splash(0), _splash(1)]
	# Сброс пара из перегретого ствола: шипение с падающим срезом.
	_streams["steam"] = [_steam()]

	# --- интерфейс и события
	_streams["pickup"] = [_pickup()]
	_streams["levelup"] = [_fanfare([523.25, 659.25, 783.99, 1046.5], 0.75)]
	_streams["unlock"] = [_fanfare([659.25, 830.61, 987.77, 1318.5], 0.85)]
	_streams["flag"] = [_horn()]

## Выстрел. Варианты 0–2 — обычная пушка, 3–4 — спецоружие покрупнее.
func _cannon(variant: int) -> AudioStreamWAV:
	var pitch: float = [1.06, 1.0, 0.94, 0.84, 0.79][variant]
	var heavy := variant >= 3
	var b := Synth.buf(0.75 if heavy else 0.62)
	var s := 900 + variant * 17

	# 1. Дульный щелчок. Без него выстрел звучит как «пуф» в подушку.
	Synth.add_noise(b, 0.0, 0.05, 11000.0 * pitch, 3000.0 * pitch, 0.50, 26.0, s)
	# 2. Тело выстрела: резкий свип шума сверху вниз.
	Synth.add_noise(b, 0.004, 0.34, 3200.0 * pitch, 240.0, 0.80, 8.0, s + 1)
	# 3. Низкий гул — именно он читается ухом как калибр.
	Synth.add_tone(b, 0.002, 0.48, "sine", 140.0 * pitch, 33.0, 0.95, 5.5)
	Synth.add_tone(b, 0.0, 0.30, "triangle", 230.0 * pitch, 72.0, 0.34, 9.0)
	# 4. Лязг затвора — отдельным слоем через сотую долю секунды.
	Synth.add_partials(b, 0.03, 0.16, 760.0 * pitch, [1.0, 2.3, 3.7], 0.09, 16.0)
	# 5. Раскат: докатывается уже после самого выстрела.
	Synth.add_noise(b, 0.06, 0.60 if heavy else 0.45, 560.0, 120.0, 0.28, 4.5, s + 2)
	return Synth.to_stream(b)

func _explosion(variant: int) -> AudioStreamWAV:
	var pitch: float = [1.0, 0.9, 1.1][variant]
	var s := 2100 + variant * 31
	var b := Synth.buf(0.9)
	Synth.add_noise(b, 0.0, 0.07, 12000.0, 4000.0, 0.45, 22.0, s)
	Synth.add_noise(b, 0.0, 0.62, 4200.0 * pitch, 190.0, 0.85, 6.0, s + 1)
	Synth.add_tone(b, 0.0, 0.60, "sine", 120.0 * pitch, 30.0, 0.90, 4.5)
	# Крошево: сыплется уже после вспышки.
	Synth.add_noise(b, 0.10, 0.55, 2600.0, 800.0, 0.20, 9.0, s + 2)
	return Synth.to_stream(b)

## Пуля по броне: короткий металлический цок, а не «бип».
func _hit(variant: int) -> AudioStreamWAV:
	var pitch: float = [1.0, 1.18, 0.86][variant]
	var b := Synth.buf(0.16)
	Synth.add_noise(b, 0.0, 0.03, 9000.0, 4000.0, 0.32, 40.0, 3300 + variant)
	Synth.add_partials(b, 0.0, 0.12, 1450.0 * pitch, [1.0, 2.76, 4.13], 0.28, 20.0)
	return Synth.to_stream(b)

## Авиаудар: падающий свист с вибрато, дальше своё дело делают взрывы.
func _airstrike() -> AudioStreamWAV:
	var b := Synth.buf(1.1)
	Synth.add_tone(b, 0.0, 1.0, "sine", 2100.0, 300.0, 0.32, 1.6, 7.0, 0.03)
	Synth.add_tone(b, 0.0, 1.0, "saw", 1050.0, 150.0, 0.10, 1.6, 7.0, 0.03)
	Synth.add_noise(b, 0.0, 1.0, 1400.0, 500.0, 0.12, 2.0, 5150)
	return Synth.to_stream(b)

func _wood(variant: int) -> AudioStreamWAV:
	var b := Synth.buf(0.26)
	var s := 6100 + variant * 13
	Synth.add_noise(b, 0.0, 0.18, 7000.0, 1400.0, 0.55, 26.0, s)
	# Щепа: пара сухих щелчков вдогонку.
	Synth.add_partials(b, 0.04, 0.08, 900.0, [1.0, 1.9], 0.16, 30.0)
	Synth.add_partials(b, 0.09, 0.07, 1250.0, [1.0, 2.1], 0.12, 34.0)
	return Synth.to_stream(b)

func _stone(variant: int) -> AudioStreamWAV:
	var b := Synth.buf(0.6)
	var s := 7300 + variant * 19
	Synth.add_noise(b, 0.0, 0.45, 1500.0, 180.0, 0.70, 7.0, s)
	Synth.add_tone(b, 0.0, 0.35, "sine", 95.0, 42.0, 0.45, 8.0)
	Synth.add_noise(b, 0.10, 0.42, 3800.0, 1500.0, 0.16, 11.0, s + 1)
	return Synth.to_stream(b)

func _metal(variant: int) -> AudioStreamWAV:
	var b := Synth.buf(0.7)
	var pitch: float = 1.0 if variant == 0 else 0.87
	Synth.add_noise(b, 0.0, 0.03, 9000.0, 3500.0, 0.30, 45.0, 8400 + variant)
	# Негармонический набор: железо звенит «мимо» гармоник.
	Synth.add_partials(b, 0.0, 0.62, 610.0 * pitch,
		[1.0, 1.73, 2.41, 3.92, 5.17], 0.30, 4.0)
	return Synth.to_stream(b)

func _tread(c0: float, c1: float, dur: float, seed_value: int) -> AudioStreamWAV:
	var b := Synth.buf(dur)
	Synth.add_noise(b, 0.0, dur, c0, c1, 0.35, 30.0, seed_value)
	return Synth.to_stream(b)

func _splash(variant: int) -> AudioStreamWAV:
	var b := Synth.buf(0.45)
	Synth.add_noise(b, 0.0, 0.35, 6000.0, 700.0, 0.45, 9.0, 9600 + variant)
	Synth.add_tone(b, 0.02, 0.25, "sine", 520.0, 170.0, 0.22, 11.0)
	return Synth.to_stream(b)

## Пар: длинный шум с падающим срезом — «пш-ш-ш», а не щелчок.
func _steam() -> AudioStreamWAV:
	var b := Synth.buf(0.75)
	Synth.add_noise(b, 0.0, 0.70, 7000.0, 1400.0, 0.45, 3.2, 4242)
	Synth.add_noise(b, 0.0, 0.10, 9000.0, 5000.0, 0.25, 14.0, 4243)
	return Synth.to_stream(b)

func _pickup() -> AudioStreamWAV:
	var b := Synth.buf(0.34)
	Synth.add_steps(b, 0.0, 0.20, "sine", [660.0, 990.0], 0.32, 7.0)
	Synth.add_steps(b, 0.0, 0.20, "triangle", [1320.0, 1980.0], 0.10, 9.0)
	return Synth.to_stream(b)

## Мажорное арпеджио с обертоном на октаву — «колокольчик», а не писк.
func _fanfare(freqs: Array, dur: float) -> AudioStreamWAV:
	var b := Synth.buf(dur + 0.25)
	Synth.add_steps(b, 0.0, dur, "sine", freqs, 0.30, 5.0)
	var octave := []
	for f in freqs:
		octave.append(float(f) * 2.0)
	Synth.add_steps(b, 0.0, dur, "sine", octave, 0.10, 7.0)
	return Synth.to_stream(b)

## Флаг — сигнал горна: пила через мягкое затухание.
func _horn() -> AudioStreamWAV:
	var b := Synth.buf(0.6)
	Synth.add_steps(b, 0.0, 0.42, "saw", [440.0, 587.33], 0.16, 5.0)
	Synth.add_steps(b, 0.0, 0.42, "sine", [440.0, 587.33], 0.26, 5.0)
	return Synth.to_stream(b)
