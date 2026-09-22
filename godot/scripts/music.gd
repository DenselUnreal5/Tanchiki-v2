extends Node

const COMBAT_BPM := 160.0
const COMBAT_BARS := 8

const P_KICK   := "x..xx...x..xx..."
const P_KICK2  := "x.xxx.x.x.xxx.x."
const P_SNARE  := "....x.......x..."
const P_HAT    := "x.x.x.x.x.x.x.x."
const P_CHUG   := "x.xxx.xxx.xxx.xx"
const P_CHORD  := "x.......x......."

const COMBAT_ROOTS := [82.41, 82.41, 98.00, 73.42, 82.41, 82.41, 110.00, 65.41]

const MENU_BPM := 72.0
const MENU_BARS := 12
const BELL_EVERY_BARS := 3

const MENU_CHORDS := [
	{"notes": [146.83, 220.00, 293.66], "pedal": 73.42, "top": 293.66},
	{"notes": [146.83, 174.61, 233.08], "pedal": 58.27, "top": 233.08},
	{"notes": [130.81, 174.61, 220.00], "pedal": 87.31, "top": 220.00},
	{"notes": [130.81, 196.00, 261.63], "pedal": 65.41, "top": 261.63},
]

const FADE := 0.7

var _combat: AudioStream
var _menu: AudioStream
var _extra := {}
var _from_files := {"menu": false, "combat": false}
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _current := ""
var _want := ""
var _paused := false
var _ducked := false
var _perk_ducked := false
var _fade: Tween
var _tasks: Array[int] = []

func _ready() -> void:
	_ensure_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_players.append(p)

	var themes := ["menu", "combat"]
	for key in Locations.ORDER:
		var name := Locations.music_of(key)
		if not themes.has(name):
			themes.append(name)
	for id in themes:
		var list := _scan_music("res://music/" + id)
		if list.is_empty():
			continue
		_from_files[id] = true
		if id == "menu":
			_menu = _playlist(list)
		elif id == "combat":
			_combat = _playlist(list)
		else:
			_extra[id] = _playlist(list)
		print("[Mus] тема «%s»: файлов %d" % [id, list.size()])

	if _menu == null:
		_tasks.append(WorkerThreadPool.add_task(_build_menu_async))
	if _combat == null:
		_tasks.append(WorkerThreadPool.add_task(_build_combat_async))

func _exit_tree() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()

func _scan_music(path: String) -> Array:
	var out := []
	var seen := {}
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for f in dir.get_files():
		var name := f
		if name.ends_with(".import"):
			name = name.trim_suffix(".import")
		if seen.has(name):
			continue
		var ext := name.get_extension().to_lower()
		if ext != "mp3" and ext != "ogg" and ext != "wav":
			continue
		seen[name] = true
		var stream = load(path + "/" + name)
		if stream != null:
			out.append(stream)
	return out

func _playlist(streams: Array) -> AudioStream:
	for st in streams:
		if st is AudioStreamMP3 or st is AudioStreamOggVorbis:
			st.loop = streams.size() == 1
	if streams.size() == 1:
		return streams[0]
	var pl := AudioStreamPlaylist.new()
	pl.stream_count = streams.size()
	for i in streams.size():
		pl.set_list_stream(i, streams[i])
	pl.loop = true
	pl.shuffle = true
	pl.fade_time = 1.0
	return pl

func _ensure_bus() -> void:
	_add_bus("Music", "Master")
	var hall := _add_bus("MusicHall", "Music")
	if AudioServer.get_bus_effect_count(hall) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.85
		rev.damping = 0.35
		rev.spread = 1.0
		rev.wet = 0.32
		rev.dry = 0.85
		rev.predelay_msec = 25.0
		AudioServer.add_bus_effect(hall, rev, 0)
		var cho := AudioEffectChorus.new()
		cho.voice_count = 2
		cho.wet = 0.18
		cho.dry = 0.9
		AudioServer.add_bus_effect(hall, cho, 1)

func _add_bus(bus_name: String, send_to: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send_to)
	return idx

func _build_menu_async() -> void:
	var t0 := Time.get_ticks_msec()
	var loop := _build_menu()
	_on_built.call_deferred("menu", loop, Time.get_ticks_msec() - t0)

func _build_combat_async() -> void:
	var t0 := Time.get_ticks_msec()
	var loop := _build_combat()
	_on_built.call_deferred("combat", loop, Time.get_ticks_msec() - t0)

func _on_built(id: String, loop: AudioStream, ms: int) -> void:
	if id == "menu":
		_menu = loop
	else:
		_combat = loop
	print("[Mus] тема «%s» собрана за %d мс" % [id, ms])
	if _want == id and _current != id:
		_switch(id)

func play_menu() -> void:
	_request("menu")

func play_combat(location: String = "") -> void:
	var theme := "combat"
	if location != "":
		var want := Locations.music_of(location)
		if _extra.has(want) or want == "combat":
			theme = want
	_request(theme)

func stop() -> void:
	_want = ""
	_current = ""
	if _fade != null and _fade.is_valid():
		_fade.kill()
	for p in _players:
		p.stop()
		p.volume_db = -60.0

const PERK_DUCK_DB := -3.1
const MENU_DUCK_DB := -14.0

func set_paused(on: bool) -> void:
	if _paused == on:
		return
	_paused = on
	for p in _players:
		p.stream_paused = on

func set_ducked(on: bool) -> void:
	if _ducked == on:
		return
	_ducked = on
	_apply_volume()

func set_perk_ducked(on: bool) -> void:
	if _perk_ducked == on:
		return
	_perk_ducked = on
	_apply_volume()

func _apply_volume() -> void:
	var db := _target_db()
	for bus in ["Music", "MusicHall"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, db)

func _target_db() -> float:
	var db := 0.0
	if _ducked:
		db = minf(db, MENU_DUCK_DB)
	if _perk_ducked:
		db = minf(db, PERK_DUCK_DB)
	return db

func _request(id: String) -> void:
	_want = id
	if _current == id:
		return
	var loop := _stream_of(id)
	if loop == null:
		return
	_switch(id)

func _stream_of(id: String) -> AudioStream:
	if id == "menu":
		return _menu
	if _extra.has(id):
		return _extra[id]
	return _combat

func _switch(id: String) -> void:
	var loop := _stream_of(id)
	if loop == null:
		return
	_current = id
	var from := _players[_active]
	_active = 1 - _active
	var to := _players[_active]

	to.bus = "Music" if _from_files.get(id, false) else "MusicHall"
	to.stream = loop
	to.stream_paused = _paused
	to.volume_db = -60.0
	to.play()

	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(to, "volume_db", 0.0, FADE)
	if from.playing:
		_fade.tween_property(from, "volume_db", -60.0, FADE)
		_fade.chain().tween_callback(from.stop)

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
		if bar_i == 3 or bar_i == 7:
			for k in 4:
				Synth.mix(b, tom, t0 + bar - six * float(4 - k), 0.6 + 0.1 * float(k))

	return Synth.to_stream(b, true)

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
			choir[top * 0.75] = _choir_note(top * 0.75)
		var ped := float(chord["pedal"])
		if not pedal.has(ped):
			pedal[ped] = _pedal_note(ped, bar)
			brass[ped] = _brass_note(ped * 2.0)

	var timp := _timpani()
	var bell := _bell(73.42)

	for bar_i in MENU_BARS:
		var t0: float = bar * float(bar_i)
		var chord: Dictionary = MENU_CHORDS[bar_i % MENU_CHORDS.size()]
		var ped := float(chord["pedal"])
		var top := float(chord["top"])

		Synth.mix(b, pedal[ped], t0, 0.55)
		for f in chord["notes"]:
			Synth.mix(b, strings[float(f)], t0, 0.42)

		for f in chord["notes"]:
			Synth.mix(b, strings[float(f)], t0 + bar * 0.5, 0.30)

		if bar_i >= 3:
			Synth.mix(b, timp, t0, 0.7)
			Synth.mix(b, timp, t0 + beat * 3.0, 0.4)

		if bar_i >= 4 and bar_i % 2 == 0:
			Synth.mix(b, brass[ped], t0 + beat * 2.0, 0.42)

		if bar_i >= 6:
			Synth.mix(b, choir[top], t0, 0.5)
			Synth.mix(b, choir[top * 0.75], t0, 0.38)

		if bar_i % BELL_EVERY_BARS == 0:
			Synth.mix(b, bell, t0, 0.85)

	Synth.normalize(b, 0.72)
	return Synth.to_stream(b, true, 1.7)

func _drive(b: PackedFloat32Array, amount: float, out_gain: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] = Synth._fast_tanh(b[i] * amount) * out_gain
	return b

func _kick() -> PackedFloat32Array:
	var b := Synth.buf(0.36)
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

func _guitar_chug(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(0.15)
	Synth.add_tone(b, 0.0, 0.15, "saw", freq, freq * 0.99, 0.60, 9.0)
	Synth.add_tone(b, 0.0, 0.15, "square", freq * 1.005, freq, 0.35, 10.0)
	Synth.add_noise(b, 0.0, 0.02, 5000.0, 1800.0, 0.22, 45.0, 606)
	return _drive(b, 4.5, 0.42)

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

func _strings_note(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(1.9)
	Synth.add_tone(b, 0.0, 1.9, "triangle", freq, freq, 0.50, 1.0, 4.6, 0.004, 0.30)
	Synth.add_tone(b, 0.0, 1.9, "saw", freq * 1.005, freq * 1.005, 0.16, 1.4, 4.0, 0.004, 0.36)
	return b

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

func _pedal_note(freq: float, dur: float) -> PackedFloat32Array:
	var b := Synth.buf(dur)
	Synth.add_tone(b, 0.0, dur, "triangle", freq, freq, 0.60, 0.7, 0.0, 0.0, 0.5)
	return b

func _brass_note(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(1.0)
	Synth.add_tone(b, 0.0, 1.0, "saw", freq, freq * 0.998, 0.42, 2.6, 4.5, 0.003, 0.06)
	Synth.add_tone(b, 0.0, 1.0, "square", freq * 1.5, freq * 1.5, 0.14, 3.2, 4.5, 0.003, 0.08)
	return _drive(b, 1.9, 0.5)

func _bell(freq: float) -> PackedFloat32Array:
	var b := Synth.buf(5.2)

	for p in [
		[0.5, 0.60, 0.5],
		[1.0, 0.90, 0.9],
		[1.2, 0.50, 1.4],
		[1.5, 0.34, 1.7],
		[2.0, 0.34, 2.1],
		[3.0, 0.20, 3.0],
	]:
		var f: float = freq * float(p[0])
		Synth.add_tone(b, 0.0, 5.2, "sine", f, f * 0.997, float(p[1]) * 0.5, float(p[2]))

	for p in [
		[4.0, 0.16, 3.2], [5.33, 0.13, 3.8], [6.0, 0.11, 4.2],
		[8.0, 0.08, 5.0], [10.7, 0.06, 5.6], [13.3, 0.04, 6.4],
	]:
		var f: float = freq * float(p[0])
		Synth.add_tone(b, 0.0, 1.1, "sine", f, f * 0.996, float(p[1]) * 0.5, float(p[2]))

	Synth.add_noise(b, 0.0, 0.09, 9000.0, 1200.0, 0.34, 22.0, 909)
	return b

func _timpani() -> PackedFloat32Array:
	var b := Synth.buf(0.9)
	Synth.add_tone(b, 0.0, 0.85, "sine", 105.0, 62.0, 0.9, 5.0)
	Synth.add_tone(b, 0.0, 0.40, "sine", 158.0, 96.0, 0.30, 7.0)
	Synth.add_noise(b, 0.0, 0.05, 3000.0, 900.0, 0.22, 26.0, 808)
	return _drive(b, 1.7, 0.62)
