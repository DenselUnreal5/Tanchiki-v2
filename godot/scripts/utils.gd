class_name Rng
extends RefCounted

const MASK := 0xFFFFFFFF

var state: int = 0

func _init(seed_value: int = 0) -> void:
	state = seed_value & MASK

static func imul(a: int, b: int) -> int:
	return (a * b) & MASK

func nextf() -> float:
	state = (state + 0x6d2b79f5) & MASK
	var t: int = state
	t = imul(t ^ (t >> 15), 1 | t)
	t = ((t + imul(t ^ (t >> 7), 61 | t)) & MASK) ^ t
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0

func range_f(min_v: float, max_v: float) -> float:
	return min_v + nextf() * (max_v - min_v)

func range_i(min_v: int, max_exclusive: int) -> int:
	if max_exclusive <= min_v:
		return min_v
	return min_v + int(nextf() * float(max_exclusive - min_v))

func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[int(nextf() * arr.size()) % arr.size()]

func shuffled(arr: Array) -> Array:
	var out := arr.duplicate()
	var i := out.size() - 1
	while i > 0:
		var j := int(nextf() * float(i + 1))
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
		i -= 1
	return out


static func normalize_angle(a: float) -> float:
	while a > PI:
		a -= TAU
	while a <= -PI:
		a += TAU
	return a

static func angle_delta(from_a: float, to_a: float) -> float:
	return normalize_angle(to_a - from_a)

static func rotate_toward(current: float, target: float, max_step: float) -> float:
	var d := angle_delta(current, target)
	if absf(d) <= max_step:
		return normalize_angle(target)
	return normalize_angle(current + signf(d) * max_step)

static func hash01(i: int, salt: int) -> float:
	var a: int = (imul(i, 0x9e3779b1) + imul(salt, 0x2545f491)) & MASK
	a = imul(a ^ (a >> 15), 1 | a)
	a = (a ^ ((a + imul(a ^ (a >> 7), 61 | a)) & MASK)) & MASK
	return float((a ^ (a >> 14)) & MASK) / 4294967296.0

static func fract(v: float) -> float:
	return v - floorf(v)

static func fmt(n: float) -> String:
	var s := str(int(round(n)))
	var neg := s.begins_with("-")
	if neg:
		s = s.substr(1)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = " " + out
	return ("-" if neg else "") + out
