# ============================================================================
# synth.gd — синтез звука без файлов ассетов.
#
# Общий инструментарий для эффектов (audio.gd) и музыки (music.gd). Всё
# собирается сложением слоёв в буфер float, и только в конце сводится
# в 16-битный AudioStreamWAV с мягким ограничением.
#
# Слоями синтез сделан не ради красоты: одиночный осциллятор звучит как
# писк из телефона. Тяжёлый выстрел танка — это три разных звука, слышимых
# как один: щелчок дульного среза, тело выстрела и низкий гул, который и
# создаёт ощущение калибра.
# ============================================================================
class_name Synth
extends RefCounted

## 32 кГц вместо 44.1: половина времени сборки уходит на голый перебор
## сэмплов в GDScript, а материал здесь — удары и шум, у которых выше
## 16 кГц слушать нечего.
const RATE := 32000

# ------------------------------------------------------------------ буферы
static func buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(1, int(dur * float(RATE))))
	return b

## Подмешивает готовый буфер в другой начиная с позиции в секундах.
## Дешевле повторного синтеза: барабан считается один раз, а в петлю
## музыки попадает шестьдесят четыре раза.
static func mix(dst: PackedFloat32Array, src: PackedFloat32Array,
		at: float, gain: float = 1.0) -> void:
	var i0 := int(at * float(RATE))
	var n := src.size()
	var limit := dst.size()
	for i in n:
		var j := i0 + i
		if j < 0:
			continue
		if j >= limit:
			break
		dst[j] += src[i] * gain

## Форма волны берётся по номеру: сравнение строк внутри цикла на сотнях
## тысяч сэмплов стоит дороже самого синтеза.
const W_SINE := 0
const W_SQUARE := 1
const W_SAW := 2
const W_TRIANGLE := 3

static func kind_id(kind: String) -> int:
	match kind:
		"square":
			return W_SQUARE
		"saw":
			return W_SAW
		"triangle":
			return W_TRIANGLE
		_:
			return W_SINE

static func wave(kind: String, phase: float) -> float:
	var p := fposmod(phase, TAU)
	match kind_id(kind):
		W_SQUARE:
			return 1.0 if p < PI else -1.0
		W_SAW:
			return (p / PI) - 1.0
		W_TRIANGLE:
			return (2.0 / PI) * asin(sin(p))
		_:
			return sin(p)

# --------------------------------------------------------------- слои
#
# Внутренние циклы намеренно написаны «в лоб», без вызовов помощников:
# pow() и exp() на каждом сэмпле стоили 2.6 секунды на старте игры.
# Свип частоты и затухание — обе экспоненты, а экспонента считается
# умножением на постоянный шаг.

## Тон с экспоненциальным свипом частоты. Вибрато нужно свисту авиаудара.
static func add_tone(b: PackedFloat32Array, at: float, dur: float, kind: String,
		f0: float, f1: float, gain: float, decay: float,
		vib_hz: float = 0.0, vib: float = 0.0, attack: float = 0.002) -> void:
	var i0 := int(at * float(RATE))
	var n := maxi(1, int(dur * float(RATE)))
	var limit := b.size()
	var kid := kind_id(kind)

	var f: float = f0
	var f_step: float = pow(maxf(f1, 0.001) / maxf(f0, 0.001), 1.0 / float(n))
	var env: float = gain
	var env_step: float = exp(-decay / float(n))
	var na: float = maxf(1.0, attack * float(RATE))
	var phase := 0.0
	var inc_k: float = TAU / float(RATE)
	var vib_k: float = TAU * vib_hz / float(RATE)

	for i in n:
		var j := i0 + i
		if j >= limit:
			break
		var fi := f
		if vib > 0.0:
			fi *= 1.0 + vib * sin(vib_k * float(i))
		phase += inc_k * fi
		if phase >= TAU:
			phase -= TAU
		f *= f_step
		var a := env
		if float(i) < na:
			a *= float(i) / na
		env *= env_step
		if j < 0:
			continue
		match kid:
			W_SQUARE:
				b[j] += (a if phase < PI else -a)
			W_SAW:
				b[j] += ((phase / PI) - 1.0) * a
			W_TRIANGLE:
				b[j] += (2.0 / PI) * asin(sin(phase)) * a
			_:
				b[j] += sin(phase) * a

## Шум через однополюсный ФНЧ с плывущей частотой среза. Свип среза сверху
## вниз — это и есть «взрыв»: сначала треск, потом гул.
static func add_noise(b: PackedFloat32Array, at: float, dur: float,
		c0: float, c1: float, gain: float, decay: float, seed_value: int) -> void:
	var i0 := int(at * float(RATE))
	var n := maxi(1, int(dur * float(RATE)))
	var limit := b.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var alpha: float = clampf(c0 / float(RATE), 0.0005, 1.0)
	var a_end: float = clampf(c1 / float(RATE), 0.0005, 1.0)
	var a_step: float = pow(a_end / alpha, 1.0 / float(n))
	var env: float = gain
	var env_step: float = exp(-decay / float(n))
	var prev := 0.0

	for i in n:
		var j := i0 + i
		if j >= limit:
			break
		prev += alpha * (rng.randf_range(-1.0, 1.0) - prev)
		# Компенсация: ФНЧ съедает амплитуду тем сильнее, чем ниже срез.
		var out: float = prev * env * 0.52 / sqrt(alpha if alpha > 0.02 else 0.02)
		alpha *= a_step
		env *= env_step
		if j >= 0:
			b[j] += out

## Негармонические обертоны — металл. Чем выше обертон, тем быстрее он
## затухает: так звучит удар по железу, а не орган.
static func add_partials(b: PackedFloat32Array, at: float, dur: float,
		base: float, ratios: Array, gain: float, decay: float) -> void:
	for k in ratios.size():
		var r: float = float(ratios[k])
		add_tone(b, at, dur, "sine", base * r, base * r * 0.995,
			gain / (1.0 + float(k) * 0.7), decay * (1.0 + float(k) * 0.35))

## Несколько нот подряд одним слоем — арпеджио интерфейса.
static func add_steps(b: PackedFloat32Array, at: float, dur: float, kind: String,
		freqs: Array, gain: float, decay: float) -> void:
	var step: float = dur / float(maxi(1, freqs.size()))
	for k in freqs.size():
		add_tone(b, at + step * float(k), step * 1.6, kind,
			float(freqs[k]), float(freqs[k]), gain, decay)

# ------------------------------------------------------------------ сведение
## Мягкое ограничение вместо жёсткого обрезания: слои складываются и легко
## выходят за единицу, а tanh давит пики, не превращая их в квадрат.
static func to_stream(b: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		var v: float = tanh(b[i] * 1.1)
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = b.size()
	return st

## Пиковый уровень буфера — им проверяются звуки в тестах.
static func peak(b: PackedFloat32Array) -> float:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	return m
