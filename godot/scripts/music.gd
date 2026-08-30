# ============================================================================
# music.gd — процедурный саундтрек. Автозагрузка «Mus».
#
# Ассетов в проекте нет, поэтому оба трека не проигрываются, а собираются:
# сначала синтезируются отдельные ноты и удары, потом раскладываются по сетке,
# и получившийся буфер отдаётся движку как зацикленный AudioStreamWAV.
#
# Так сделано не из экономии, а ради ритма: собирать петлю плеерами из
# _process нельзя — кадр длится 16 мс, и барабаны бы «плыли». В готовом
# буфере каждый удар стоит на своём сэмпле.
#
# Треков два, и они противоположны по характеру:
#   * меню — ре минор, 76 ударов, струнные, хор и литавры: медленно и крупно;
#   * бой   — ми минор, 160 ударов, перегруженная гитара и тяжёлые барабаны.
#
# Главная хитрость сборки — кэш нот. Синтез стоит около микросекунды на
# сэмпл, а подмешивание готового буфера — в тридцать раз дешевле. Поэтому
# каждая нота считается один раз, а в петлю попадает столько раз, сколько
# нужно: прогрессия из четырёх аккордов даёт всего восемь уникальных нот.
# ============================================================================
extends Node

# ------------------------------------------------------------------ бой
const COMBAT_BPM := 160.0
const COMBAT_BARS := 8

## Шестнадцатые доли такта. Точка — пауза, x — удар.
const P_KICK   := "x..xx...x..xx..."
const P_KICK2  := "x.xxx.x.x.xxx.x."   # вторая половина петли: сдвоенная бочка
const P_SNARE  := "....x.......x..."
const P_HAT    := "x.x.x.x.x.x.x.x."
## Гитарный чух: галоп из шестнадцатых, костяк всего трека.
const P_CHUG   := "x.xxx.xxx.xxx.xx"
## Аккорд на сильную долю — то, что слышно поверх галопа.
const P_CHORD  := "x.......x......."

## Ми минор: тоника, тоника, VI, IV — и подъём во второй половине.
const COMBAT_ROOTS := [82.41, 82.41, 98.00, 73.42, 82.41, 82.41, 110.00, 65.41]

# ----------------------------------------------------------------- меню
const MENU_BPM := 76.0
const MENU_BARS := 8

## Ре минор: Dm — Bb — F — C, дважды. Аккорды подобраны так, чтобы делить
## между собой ноты: восемь уникальных высот на всю тему вместо тринадцати.
const MENU_CHORDS := [
	{"notes": [146.83, 220.00, 293.66], "pedal": 73.42, "top": 293.66},  # Dm
	{"notes": [146.83, 174.61, 233.08], "pedal": 58.27, "top": 233.08},  # Bb
	{"notes": [130.81, 174.61, 220.00], "pedal": 87.31, "top": 220.00},  # F
	{"notes": [130.81, 196.00, 261.63], "pedal": 65.41, "top": 261.63},  # C
]

## Скорость перехода между темами, секунд.
const FADE := 0.7

var _combat: AudioStreamWAV
var _menu: AudioStreamWAV
## Два плеера ради кроссфейда: обрыв темы на входе в бой слышен как сбой.
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _current := ""
var _want := ""
var _paused := false
var _ducked := false
var _fade: Tween

func _ready() -> void:
	_ensure_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_players.append(p)
	# Две независимые задачи: на многоядерной машине темы собираются
	# параллельно, а до первой партии боевая всё равно не нужна.
	WorkerThreadPool.add_task(_build_menu_async)
	WorkerThreadPool.add_task(_build_combat_async)

func _ensure_bus() -> void:
	if AudioServer.get_bus_index("Music") >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Music")
	AudioServer.set_bus_send(idx, "Master")

func _build_menu_async() -> void:
	var t0 := Time.get_ticks_msec()
	var loop := _build_menu()
	_on_built.call_deferred("menu", loop, Time.get_ticks_msec() - t0)

func _build_combat_async() -> void:
	var t0 := Time.get_ticks_msec()
	var loop := _build_combat()
	_on_built.call_deferred("combat", loop, Time.get_ticks_msec() - t0)

func _on_built(id: String, loop: AudioStreamWAV, ms: int) -> void:
	if id == "menu":
		_menu = loop
	else:
		_combat = loop
	print("[Mus] тема «%s» собрана за %d мс" % [id, ms])
	# Тему могли попросить, пока она собиралась.
	if _want == id and _current != id:
		_switch(id)

# ------------------------------------------------------------------ команды
func play_menu() -> void:
	_request("menu")

func play_combat() -> void:
	_request("combat")

func stop() -> void:
	_want = ""
	_current = ""
	if _fade != null and _fade.is_valid():
		_fade.kill()
	for p in _players:
		p.stop()
		p.volume_db = -60.0

## Пауза музыки на экране выбора перка. Не приглушение, а именно остановка:
## выбор перка — это пауза боя, и тишина в этот момент отделяет его от
## стрельбы куда лучше, чем тот же трек потише.
func set_paused(on: bool) -> void:
	if _paused == on:
		return
	_paused = on
	for p in _players:
		p.stream_paused = on

## Приглушение — для меню паузы, где игрок может задержаться надолго
## и трек лучше оставить фоном.
func set_ducked(on: bool) -> void:
	if _ducked == on:
		return
	_ducked = on
	var p := _players[_active]
	if p.playing:
		p.volume_db = _target_db()

func _target_db() -> float:
	return -14.0 if _ducked else 0.0

func _request(id: String) -> void:
	_want = id
	if _current == id:
		return
	var loop: AudioStreamWAV = _menu if id == "menu" else _combat
	if loop == null:
		return  # ещё собирается — включим в _on_built
	_switch(id)

## Кроссфейд: новая тема поднимается на втором плеере, старая уходит.
func _switch(id: String) -> void:
	var loop: AudioStreamWAV = _menu if id == "menu" else _combat
	if loop == null:
		return
	_current = id
	var from := _players[_active]
	_active = 1 - _active
	var to := _players[_active]

	to.stream = loop
	to.stream_paused = _paused
	to.volume_db = -60.0
	to.play()

	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(to, "volume_db", _target_db(), FADE)
	if from.playing:
		_fade.tween_property(from, "volume_db", -60.0, FADE)
		_fade.chain().tween_callback(from.stop)

# =========================================================== боевая тема
func _build_combat() -> AudioStreamWAV:
	var beat := 60.0 / COMBAT_BPM
	var six := beat * 0.25
	var bar := beat * 4.0
	var b := Synth.buf(bar * float(COMBAT_BARS))

	var kick := _kick()
	var snare := _snare()
	var hat := _hat(0.05, 0.30)
	var hat_open := _hat(0.20, 0.24)
	var crash := _crash()
	var tom := _tom()

	# Гитара и бас кэшируются по высоте: в петле их под две сотни ударов.
	var chug := {}
	var power := {}
	var bass := {}
	for f in COMBAT_ROOTS:
		var key := float(f)
		if not chug.has(key):
			chug[key] = _guitar_chug(key)
			power[key] = _guitar_power(key)
			bass[key] = _bass(key)

	for bar_i in COMBAT_BARS:
		var t0: float = bar * float(bar_i)
		var root: float = float(COMBAT_ROOTS[bar_i])
		# Во второй половине петли бочка удваивается — трек прибавляет,
		# а не повторяет сам себя восемь тактов подряд.
		var kick_pattern: String = P_KICK2 if bar_i >= 4 else P_KICK

		for s in 16:
			var t: float = t0 + six * float(s)
			if kick_pattern[s] == "x":
				Synth.mix(b, kick, t, 1.0)
			if P_SNARE[s] == "x":
				Synth.mix(b, snare, t, 0.9)
			if P_HAT[s] == "x":
				if s == 14 and (bar_i == 3 or bar_i == 7):
					Synth.mix(b, hat_open, t, 0.5)
				else:
					Synth.mix(b, hat, t, 0.32 if s % 4 == 0 else 0.20)
			if P_CHUG[s] == "x":
				Synth.mix(b, chug[root], t, 0.85)
				Synth.mix(b, bass[root], t, 0.5)
			if P_CHORD[s] == "x":
				Synth.mix(b, power[root], t, 0.5)

		if bar_i == 0 or bar_i == 4:
			Synth.mix(b, crash, t0, 0.5)
		# Сбивка по томам в конце каждой четвёрки тактов.
		if bar_i == 3 or bar_i == 7:
			for k in 4:
				Synth.mix(b, tom, t0 + bar - six * float(4 - k), 0.6 + 0.1 * float(k))

	return Synth.to_stream(b, true)

# ============================================================ тема меню
func _build_menu() -> AudioStreamWAV:
	var beat := 60.0 / MENU_BPM
	var bar := beat * 4.0
	var b := Synth.buf(bar * float(MENU_BARS))

	var strings := {}
	var choir := {}
	var pedal := {}
	var brass := {}
	for chord in MENU_CHORDS:
		for f in chord["notes"]:
			var key := float(f)
			if not strings.has(key):
				strings[key] = _strings_note(key)
		var top := float(chord["top"])
		if not choir.has(top):
			choir[top] = _choir_note(top)
			# Хор поёт в терцию сам с собой: одна нота звучит одиноко,
			# две — уже хором.
			choir[top * 0.75] = _choir_note(top * 0.75)
		var ped := float(chord["pedal"])
		if not pedal.has(ped):
			pedal[ped] = _pedal_note(ped, bar)
			brass[ped] = _brass_note(ped * 2.0)

	var timp := _timpani()
	var crash := _crash()

	for bar_i in MENU_BARS:
		var t0: float = bar * float(bar_i)
		var chord: Dictionary = MENU_CHORDS[bar_i % MENU_CHORDS.size()]
		var ped := float(chord["pedal"])
		var top := float(chord["top"])

		# Струнные и педаль держат всю тему.
		Synth.mix(b, pedal[ped], t0, 0.55)
		for f in chord["notes"]:
			Synth.mix(b, strings[float(f)], t0, 0.42)

		# Вторая половина такта — повторная атака струнных: без неё
		# длинная нота успевает затухнуть и тема провисает.
		for f in chord["notes"]:
			Synth.mix(b, strings[float(f)], t0 + bar * 0.5, 0.30)

		# Литавры на сильную долю: с третьего такта, когда тема набрала вес.
		if bar_i >= 2:
			Synth.mix(b, timp, t0, 0.7)
			Synth.mix(b, timp, t0 + beat * 3.0, 0.4)

		# Медь отвечает струнным на третьей доле.
		if bar_i >= 2:
			Synth.mix(b, brass[ped], t0 + beat * 2.0, 0.42)

		# Хор вступает во второй половине темы — это её кульминация.
		if bar_i >= 4:
			Synth.mix(b, choir[top], t0, 0.5)
			Synth.mix(b, choir[top * 0.75], t0, 0.38)
		if bar_i == 4:
			Synth.mix(b, crash, t0, 0.35)

	return Synth.to_stream(b, true)

# ------------------------------------------------------------ инструменты
## Перегруз: то, что отличает агрессивный трек от вежливого. Считается один
## раз на инструмент, а не на удар.
func _drive(b: PackedFloat32Array, amount: float, out_gain: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] = tanh(b[i] * amount) * out_gain
	return b

func _kick() -> PackedFloat32Array:
	var b := Synth.buf(0.36)
	# Два слоя тела: короткий щелчок сверху и длинный низ — так бочка
	# слышна и на ноутбучных динамиках, и в наушниках.
	Synth.add_tone(b, 0.0, 0.32, "sine", 165.0, 40.0, 0.95, 9.0)
	Synth.add_tone(b, 0.0, 0.10, "sine", 420.0, 120.0, 0.35, 22.0)
	Synth.add_noise(b, 0.0, 0.02, 6500.0, 2200.0, 0.32, 40.0, 101)
	return _drive(b, 2.4, 0.66)

func _snare() -> PackedFloat32Array:
	var b := Synth.buf(0.30)
	Synth.add_noise(b, 0.0, 0.26, 8000.0, 1100.0, 0.75, 13.0, 202)
	Synth.add_tone(b, 0.0, 0.14, "triangle", 215.0, 165.0, 0.40, 15.0)
	Synth.add_tone(b, 0.0, 0.14, "triangle", 330.0, 250.0, 0.22, 17.0)
	return _drive(b, 2.0, 0.62)

func _tom() -> PackedFloat32Array:
	var b := Synth.buf(0.26)
	Synth.add_tone(b, 0.0, 0.24, "sine", 220.0, 90.0, 0.8, 11.0)
	Synth.add_noise(b, 0.0, 0.03, 4000.0, 1500.0, 0.18, 34.0, 505)
	return _drive(b, 1.8, 0.6)

func _hat(dur: float, gain: float) -> PackedFloat32Array:
	var b := Synth.buf(dur)
	Synth.add_noise(b, 0.0, dur, 12000.0, 8000.0, gain, 26.0 if dur < 0.1 else 9.0, 303)
	return b

func _crash() -> PackedFloat32Array:
	var b := Synth.buf(1.3)
	Synth.add_noise(b, 0.0, 1.25, 12000.0, 2500.0, 0.55, 3.2, 404)
	return b

## Гитарный чух: заглушенная ладонью нота. Короткая, злая, с сильным
## перегрузом — на ней держится весь галоп.
func _guitar_chug(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(0.15)
	Synth.add_tone(b, 0.0, 0.15, "saw", freq, freq * 0.99, 0.60, 9.0)
	Synth.add_tone(b, 0.0, 0.15, "square", freq * 1.005, freq, 0.35, 10.0)
	# Призвук медиатора: без него чух звучит как синтезаторный бас.
	Synth.add_noise(b, 0.0, 0.02, 5000.0, 1800.0, 0.22, 45.0, 606)
	return _drive(b, 4.5, 0.42)

## Квинт-аккорд с перегрузом: тоника, квинта, октава. Терции нет намеренно —
## она бы смягчила звучание, а трек должен быть злым.
func _guitar_power(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(0.55)
	for r in [1.0, 1.5, 2.0]:
		Synth.add_tone(b, 0.0, 0.55, "saw", freq * float(r), freq * float(r) * 0.995,
			0.30, 4.0)
	Synth.add_noise(b, 0.0, 0.025, 6000.0, 2000.0, 0.18, 40.0, 707)
	return _drive(b, 5.0, 0.34)

func _bass(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(0.18)
	Synth.add_tone(b, 0.0, 0.18, "square", freq * 0.5, freq * 0.5, 0.55, 8.0)
	return _drive(b, 2.6, 0.40)

## Струнная секция: два расстроенных голоса. Расстройка и медленная атака —
## всё, что отличает секцию от одинокого осциллятора.
func _strings_note(freq: float) -> PackedFloat32Array:
	# 1.9 с, а не полный такт: нота всё равно перекрывается следующей атакой,
	# а синтез стоит ровно пропорционально длине.
	var b := Synth.buf(1.9)
	Synth.add_tone(b, 0.0, 1.9, "triangle", freq, freq, 0.50, 1.0, 4.6, 0.004, 0.30)
	Synth.add_tone(b, 0.0, 1.9, "saw", freq * 1.005, freq * 1.005, 0.16, 1.4, 4.0, 0.004, 0.36)
	return b

## Хор на «а». Гласная — это два бугра в спектре (форманты), поэтому
## гармоники взвешены по близости к 750 и 1150 Гц: без этого получается
## орган, а не голоса.
func _choir_note(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(1.9)
	for h in [1, 2, 3, 4]:
		var fh := freq * float(h)
		var g := _formant_gain(fh)
		if g < 0.05:
			continue
		Synth.add_tone(b, 0.0, 1.9, "sine", fh, fh * 1.002, g * 0.6, 0.9, 5.4, 0.007, 0.42)
	return b

func _formant_gain(f: float) -> float:
	var a := exp(-pow((f - 750.0) / 430.0, 2.0))
	var c := exp(-pow((f - 1150.0) / 520.0, 2.0))
	return a * 0.9 + c * 0.55 + 0.10

## Органная педаль в басу — фундамент, на котором держится вся тема.
func _pedal_note(freq: float, dur: float) -> PackedFloat32Array:
	# Одна волна вместо двух: октавный призвук всё равно перекрыт струнными,
	# а педаль длиной в такт — самый дорогой буфер темы.
	var b := Synth.buf(dur)
	Synth.add_tone(b, 0.0, dur, "triangle", freq, freq, 0.60, 0.7, 0.0, 0.0, 0.5)
	return b

## Медь: быстрая атака, лёгкий перегруз, яркий верх.
func _brass_note(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(1.0)
	Synth.add_tone(b, 0.0, 1.0, "saw", freq, freq * 0.998, 0.42, 2.6, 4.5, 0.003, 0.06)
	Synth.add_tone(b, 0.0, 1.0, "square", freq * 1.5, freq * 1.5, 0.14, 3.2, 4.5, 0.003, 0.08)
	return _drive(b, 1.9, 0.5)

## Литавра: низкий удар с быстрым падением высоты.
func _timpani() -> PackedFloat32Array:
	var b := Synth.buf(0.9)
	Synth.add_tone(b, 0.0, 0.85, "sine", 105.0, 62.0, 0.9, 5.0)
	Synth.add_tone(b, 0.0, 0.40, "sine", 158.0, 96.0, 0.30, 7.0)
	Synth.add_noise(b, 0.0, 0.05, 3000.0, 900.0, 0.22, 26.0, 808)
	return _drive(b, 1.7, 0.62)
