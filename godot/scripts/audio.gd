# ============================================================================
# audio.gd — процедурные звуки, без файлов ассетов. Автозагрузка «Sfx».
#
# Буферы генерируются один раз при старте (тот же набор тонов и шумов, что и
# в веб-версии на Web Audio). Единый ограничитель голосов: 22 бота
# одновременно иначе перегружают микшер.
# ============================================================================
extends Node

const SAMPLE_RATE := 22050
const MAX_VOICES := 16

## Не более чем один звук данного типа за столько тиков.
const THROTTLE := {
	"shoot": 3,
	"hit": 3,
	"explosion": 4,
	"water": 10,
	"pickup": 0,
	"levelup": 0,
	"flag": 0,
	"unlock": 0,
	"airstrike": 0,
	# Звуки разрушения построек.
	"crack": 4,
	"crumble": 5,
	"clang": 4,
	# Ход по покрытию: звучит часто, поэтому троттлинг жёсткий.
	"tread_hard": 12,
	"tread_soft": 12,
}

var enabled := true
var tick := 0
var _last_played := {}
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0

func _ready() -> void:
	_ensure_buses()
	_build_streams()
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)

## Раздельные шины, чтобы громкость эффектов и музыки регулировалась
## независимо от общей. Создаются кодом: в проекте нет файла раскладки шин,
## и заводить его ради двух записей незачем.
##
## Музыки в игре пока нет — весь звук процедурный и состоит из эффектов.
## Шина всё равно заводится: ползунок в настройках уже подключён к ней,
## и добавленному позже треку не понадобится ничего менять.
func _ensure_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func set_enabled(on: bool) -> void:
	enabled = on

## Вызывается один раз за логический тик, чтобы работал троттлинг.
func advance() -> void:
	tick += 1

func play(type: String) -> void:
	if not enabled or not _streams.has(type):
		return
	var gap: int = THROTTLE.get(type, 0)
	if gap > 0 and _last_played.has(type) and tick - int(_last_played[type]) < gap:
		return
	_last_played[type] = tick
	# Круговой пул голосов: самый старый прерывается.
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[type]
	player.volume_db = -6.0
	player.play()

# ---------------------------------------------------------------- генерация
func _build_streams() -> void:
	_streams["shoot"] = _tone(0.08, "square", 760.0, 190.0, 0.11)
	_streams["hit"] = _tone(0.05, "sine", 300.0, 100.0, 0.09)
	_streams["pickup"] = _tone(0.12, "sine", 440.0, 880.0, 0.10)
	_streams["airstrike"] = _tone(0.9, "saw", 1200.0, 120.0, 0.16)
	_streams["levelup"] = _steps(0.36, "sine", [523.0, 659.0, 784.0], 0.13)
	_streams["unlock"] = _steps(0.4, "triangle", [660.0, 880.0, 1320.0], 0.12)
	_streams["flag"] = _steps(0.26, "triangle", [600.0, 800.0, 1000.0], 0.11)
	_streams["explosion"] = _noise(0.3, 900.0, 0.30)
	# Разрушение построек: сухой треск дерева, низкий гул камня,
	# звонкий удар по железу.
	_streams["crack"] = _noise(0.13, 2600.0, 0.22)
	_streams["crumble"] = _noise(0.28, 420.0, 0.28)
	_streams["clang"] = _tone(0.22, "triangle", 1500.0, 470.0, 0.11)
	# Трак по асфальту — сухой щелчок, по земле и траве — глухой шорох.
	_streams["tread_hard"] = _noise(0.07, 3000.0, 0.05)
	_streams["tread_soft"] = _noise(0.09, 700.0, 0.05)
	_streams["water"] = _noise(0.2, 1600.0, 0.16)

func _wave(kind: String, phase: float) -> float:
	var p := fposmod(phase, TAU)
	match kind:
		"square":
			return 1.0 if p < PI else -1.0
		"saw":
			return (p / PI) - 1.0
		"triangle":
			return (2.0 / PI) * asin(sin(p))
		_:
			return sin(p)

func _make_stream(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SAMPLE_RATE
	s.stereo = false
	s.data = data
	return s

func _put(data: PackedByteArray, value: float) -> void:
	var v := int(clampf(value, -1.0, 1.0) * 32767.0)
	data.append(v & 0xFF)
	data.append((v >> 8) & 0xFF)

## Тон с экспоненциальным свипом частоты и затуханием громкости.
func _tone(dur: float, kind: String, f0: float, f1: float, gain: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var data := PackedByteArray()
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = f0 * pow(f1 / f0, t)
		phase += TAU * f / SAMPLE_RATE
		var env: float = gain * pow(0.001 / maxf(gain, 0.0001), t)
		_put(data, _wave(kind, phase) * env)
	return _make_stream(data)

## Несколько нот подряд с общим затуханием.
func _steps(dur: float, kind: String, freqs: Array, gain: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var data := PackedByteArray()
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var idx := mini(freqs.size() - 1, int(t * freqs.size()))
		phase += TAU * float(freqs[idx]) / SAMPLE_RATE
		var env: float = gain * pow(0.001 / maxf(gain, 0.0001), t)
		_put(data, _wave(kind, phase) * env)
	return _make_stream(data)

## Шум с однополюсным ФНЧ — взрывы и всплески воды.
func _noise(dur: float, cutoff: float, gain: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var alpha: float = clampf(cutoff / float(SAMPLE_RATE), 0.0, 1.0)
	var prev := 0.0
	for i in n:
		var decay := 1.0 - float(i) / float(n)
		var white := rng.randf_range(-1.0, 1.0)
		prev = prev + alpha * (white - prev)
		_put(data, prev * decay * decay * gain * 3.0)
	return _make_stream(data)
