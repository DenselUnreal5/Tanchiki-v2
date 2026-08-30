# ============================================================================
# music.gd — процедурный саундтрек боя. Автозагрузка «Mus».
#
# Ассетов в проекте нет, поэтому трек не проигрывается, а собирается: сначала
# синтезируются отдельные удары (бочка, малый, хэт, краш, басовая нота,
# аккорд), потом они раскладываются по сетке на 8 тактов, и получившийся
# буфер отдаётся движку как зацикленный AudioStreamWAV.
#
# Так сделано не из экономии, а ради ритма: собирать петлю плеерами из
# _process нельзя — кадр длится 16 мс, и барабаны бы «плыли». В готовом
# буфере каждый удар стоит на своём сэмпле.
#
# Музыка идёт по своей шине, и ползунок «Музыка» в настройках управляет
# только ей.
# ============================================================================
extends Node

const BPM := 152.0
const BARS := 8

## Шестнадцатые доли одного такта. Точка — пауза, x — удар.
## Ровная бочка на каждую долю плюс подтолкивающие шестнадцатые — самый
## прямой способ держать напор, не превращая петлю в кашу.
const P_KICK  := "x..xx...x..xx..."
const P_SNARE := "....x.......x..."
const P_HAT   := "x.x.x.x.x.x.x.x."
const P_BASS  := "x.xxx.xxx.xxx.xx"

## Ми минор: тоника, тоника, VI, IV — и то же с подъёмом во второй половине.
## Ноты берутся низко: агрессия в этом жанре живёт в нижней середине.
const ROOTS := [82.41, 82.41, 98.00, 73.42, 82.41, 82.41, 110.00, 65.41]

var _player: AudioStreamPlayer
var _loop: AudioStreamWAV
var _ducked := false
var _want_play := false

func _ready() -> void:
	_ensure_bus()
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.volume_db = 0.0
	add_child(_player)
	# Петля собирается в фоне: она длиннее секунды звука и заметно дольше
	# всех эффектов вместе взятых, а до первой партии всё равно не нужна.
	WorkerThreadPool.add_task(_build_async)

func _ensure_bus() -> void:
	if AudioServer.get_bus_index("Music") >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Music")
	AudioServer.set_bus_send(idx, "Master")

func _build_async() -> void:
	var t0 := Time.get_ticks_msec()
	var loop := _build_loop()
	# Готовый поток отдаём в основной поток: узлы трогать из задачи нельзя.
	_on_built.call_deferred(loop, Time.get_ticks_msec() - t0)

func _on_built(loop: AudioStreamWAV, ms: int) -> void:
	_loop = loop
	print("[Mus] петля собрана за %d мс" % ms)
	if _want_play:
		_start()

# ------------------------------------------------------------------ команды
func play_combat() -> void:
	_want_play = true
	if _loop != null:
		_start()

func stop() -> void:
	_want_play = false
	if _player != null:
		_player.stop()

## Приглушение на паузе и при выборе перка: трек продолжает идти, но уходит
## на задний план, иначе меню поверх боя невозможно слушать.
func set_ducked(on: bool) -> void:
	if _ducked == on:
		return
	_ducked = on
	if _player != null:
		_player.volume_db = -14.0 if on else 0.0

func _start() -> void:
	if _player.playing:
		return
	_player.stream = _loop
	_player.volume_db = -14.0 if _ducked else 0.0
	_player.play()

# ------------------------------------------------------------------ сборка
func _build_loop() -> AudioStreamWAV:
	var beat := 60.0 / BPM
	var six := beat * 0.25
	var bar := beat * 4.0
	var b := Synth.buf(bar * float(BARS))

	var kick := _kick()
	var snare := _snare()
	var hat := _hat(0.055, 0.30)
	var hat_open := _hat(0.20, 0.24)
	var crash := _crash()

	# Басовые ноты рендерятся по одной на высоту, а не на удар: в петле
	# их 128, и синтезировать каждую заново было бы вчетверо дольше.
	var bass_cache := {}
	for f in ROOTS:
		if not bass_cache.has(f):
			bass_cache[f] = _bass(float(f))

	for bar_i in BARS:
		var t0: float = bar * float(bar_i)
		var root: float = float(ROOTS[bar_i])

		for s in 16:
			var t: float = t0 + six * float(s)
			if P_KICK[s] == "x":
				Synth.mix(b, kick, t, 1.0)
			if P_SNARE[s] == "x":
				Synth.mix(b, snare, t, 0.85)
			if P_HAT[s] == "x":
				# Открытый хэт в конце такта — «вдох» перед следующим.
				if s == 14 and (bar_i == 3 or bar_i == 7):
					Synth.mix(b, hat_open, t, 0.5)
				else:
					Synth.mix(b, hat, t, 0.34 if s % 4 == 0 else 0.22)
			if P_BASS[s] == "x":
				Synth.mix(b, bass_cache[root], t, 0.62)

		# Аккорд на первую долю такта и краш в начале каждой половины.
		Synth.mix(b, _chord_cached(bass_cache, root), t0, 0.34)
		if bar_i == 0 or bar_i == 4:
			Synth.mix(b, crash, t0, 0.45)

	return Synth.to_stream(b, true)

## Аккорды кэшируются в том же словаре: ключ отличается знаком.
func _chord_cached(cache: Dictionary, root: float) -> PackedFloat32Array:
	var key := -root
	if not cache.has(key):
		cache[key] = _chord(root)
	return cache[key]

# ------------------------------------------------------------ инструменты
## Перегруз: то, что отличает агрессивный трек от вежливого. Считается один
## раз на инструмент, а не на удар.
func _drive(b: PackedFloat32Array, amount: float, out_gain: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] = tanh(b[i] * amount) * out_gain
	return b

func _kick() -> PackedFloat32Array:
	var b := Synth.buf(0.34)
	Synth.add_tone(b, 0.0, 0.30, "sine", 155.0, 41.0, 0.95, 9.0)
	Synth.add_noise(b, 0.0, 0.02, 6000.0, 2000.0, 0.30, 40.0, 101)
	return _drive(b, 2.2, 0.62)

func _snare() -> PackedFloat32Array:
	var b := Synth.buf(0.26)
	Synth.add_noise(b, 0.0, 0.22, 7500.0, 1200.0, 0.70, 15.0, 202)
	Synth.add_tone(b, 0.0, 0.12, "triangle", 215.0, 165.0, 0.35, 16.0)
	Synth.add_tone(b, 0.0, 0.12, "triangle", 330.0, 250.0, 0.20, 18.0)
	return _drive(b, 1.8, 0.58)

func _hat(dur: float, gain: float) -> PackedFloat32Array:
	var b := Synth.buf(dur)
	Synth.add_noise(b, 0.0, dur, 12000.0, 8000.0, gain, 26.0 if dur < 0.1 else 9.0, 303)
	return b

func _crash() -> PackedFloat32Array:
	var b := Synth.buf(1.3)
	Synth.add_noise(b, 0.0, 1.25, 12000.0, 2500.0, 0.55, 3.2, 404)
	return b

## Палм-мьют бас: короткая нота с резкой атакой и сильным перегрузом.
func _bass(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(0.18)
	Synth.add_tone(b, 0.0, 0.18, "saw", freq, freq * 0.985, 0.55, 7.0)
	Synth.add_tone(b, 0.0, 0.18, "square", freq * 0.5, freq * 0.5, 0.28, 8.0)
	Synth.add_tone(b, 0.0, 0.05, "square", freq * 2.0, freq * 1.9, 0.16, 24.0)
	return _drive(b, 3.2, 0.46)

## Квинт-аккорд: тоника, квинта, октава. Мажорной терции нет намеренно —
## она бы смягчила звучание.
func _chord(root: float) -> PackedFloat32Array:
	var b := Synth.buf(0.42)
	for r in [1.0, 1.5, 2.0]:
		Synth.add_tone(b, 0.0, 0.40, "saw", root * float(r), root * float(r) * 0.99,
			0.26, 5.0)
	return _drive(b, 2.4, 0.34)
