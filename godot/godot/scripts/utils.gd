# ============================================================================
# utils.gd — детерминированный ГПСЧ и мелкие математические помощники.
#
# Rng — порт mulberry32: один и тот же seed даёт одну и ту же карту, погоду
# и поведение ботов. Использовать вместо randf(), иначе теряется
# воспроизводимость уровней.
# ============================================================================
class_name Rng
extends RefCounted

const MASK := 0xFFFFFFFF

var state: int = 0

func _init(seed_value: int = 0) -> void:
	state = seed_value & MASK

static func imul(a: int, b: int) -> int:
	return (a * b) & MASK

## Следующее число в диапазоне [0, 1).
func nextf() -> float:
	state = (state + 0x6d2b79f5) & MASK
	var t: int = state
	t = imul(t ^ (t >> 15), 1 | t)
	t = ((t + imul(t ^ (t >> 7), 61 | t)) & MASK) ^ t
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0

func range_f(min_v: float, max_v: float) -> float:
	return min_v + nextf() * (max_v - min_v)

## Целое в [min_v, max_exclusive).
func range_i(min_v: int, max_exclusive: int) -> int:
	if max_exclusive <= min_v:
		return min_v
	return min_v + int(nextf() * float(max_exclusive - min_v))

func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[int(nextf() * arr.size()) % arr.size()]

## Тасование Фишера—Йетса. Возвращает новый массив.
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

# ---------------------------------------------------------------- общие функции

## Приводит угол к диапазону (-PI, PI].
static func normalize_angle(a: float) -> float:
	while a > PI:
		a -= TAU
	while a <= -PI:
		a += TAU
	return a

## Кратчайшая разница между углами.
static func angle_delta(from_a: float, to_a: float) -> float:
	return normalize_angle(to_a - from_a)

## Плавный поворот к целевому углу с ограничением скорости.
static func rotate_toward(current: float, target: float, max_step: float) -> float:
	var d := angle_delta(current, target)
	if absf(d) <= max_step:
		return normalize_angle(target)
	return normalize_angle(current + signf(d) * max_step)

## Детерминированный 0..1 из двух целых — для дождя/тумана без состояния.
static func hash01(i: int, salt: int) -> float:
	var a: int = (imul(i, 0x9e3779b1) + imul(salt, 0x2545f491)) & MASK
	a = imul(a ^ (a >> 15), 1 | a)
	a = (a ^ ((a + imul(a ^ (a >> 7), 61 | a)) & MASK)) & MASK
	return float((a ^ (a >> 14)) & MASK) / 4294967296.0

static func fract(v: float) -> float:
	return v - floorf(v)

## Форматирует число с разделителями разрядов.
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
