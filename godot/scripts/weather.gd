# ============================================================================
# weather.gd — погода и атмосфера.
#
# Детерминирована по seed: одна и та же партия показывает один и тот же
# сценарий погоды. Управляет циклом дня и ночи, условиями (ясно/дождь/туман/
# гроза) и вспышками молний. Чистая логика — отрисовка живёт в рендерере.
# ============================================================================
class_name WeatherSystem
extends RefCounted

## Полный цикл дня и ночи, тиков (10 минут игры).
const DAY_CYCLE := 10 * 60 * 60
## Начальная фаза (в долях цикла) — игра начинается днём.
const DAY_START_PHASE := 0.18

## Доля цикла, соответствующая определённому времени суток.
const DAY_PHASES := {"dawn": 0.0, "day": 0.25, "dusk": 0.5, "night": 0.75}
## Уровень освещения в момент каждой фазы (0 — темно, 1 — ярко).
const DAY_LIGHT := {"dawn": 0.35, "day": 1.0, "dusk": 0.4, "night": 0.18}

## Минимальная и максимальная длительность погодного условия, тиков.
const WEATHER_MIN := 20 * 60
const WEATHER_MAX := 50 * 60

## rain/fog — целевая интенсивность (0..1), lightning — шанс вспышки за тик.
const TYPES := {
	"clear": {"id": "clear", "rain": 0.0, "fog": 0.0, "lightning": 0.0, "weight": 3},
	"rain": {"id": "rain", "rain": 1.0, "fog": 0.15, "lightning": 0.0, "weight": 2},
	"fog": {"id": "fog", "rain": 0.0, "fog": 0.9, "lightning": 0.0, "weight": 2},
	"storm": {"id": "storm", "rain": 1.0, "fog": 0.4, "lightning": 0.02, "weight": 1},
}

## Скорость плавного перехода к целевой интенсивности за тик.
const SMOOTH := 0.002

var rng: Rng
var cycle_ticks := 0
var condition := "clear"
var rain := 0.0
var fog := 0.0
var timer := 0
var flash := 0.0

func _init(seed_value: int) -> void:
	rng = Rng.new((seed_value ^ 0x9e3779b9) & 0xFFFFFFFF)
	cycle_ticks = int(round(DAY_START_PHASE * DAY_CYCLE))
	timer = _duration()

## Текущая фаза дня в долях цикла 0..1.
var phase: float:
	get: return float(cycle_ticks % DAY_CYCLE) / float(DAY_CYCLE)

## Уровень освещения 0..1 на текущий момент дня.
var light: float:
	get:
		var p := phase
		var keys := ["dawn", "day", "dusk", "night", "dawn"]
		for i in range(keys.size() - 1):
			var a: float = DAY_PHASES[keys[i]]
			var b: float = DAY_PHASES[keys[i + 1]] if i + 1 < 4 else 1.0
			if p >= a and p < b:
				var t := (p - a) / (b - a)
				return lerpf(DAY_LIGHT[keys[i]], DAY_LIGHT[keys[i + 1]], t)
		return DAY_LIGHT["night"]

## Короткое название времени суток для HUD.
var time_name: String:
	get:
		var p := phase
		if p < 0.125 or p >= 0.875:
			return "ночь"
		if p < 0.25:
			return "рассвет"
		if p < 0.5:
			return "день"
		if p < 0.75:
			return "закат"
		return "вечер"

## Ключ времени суток для перевода.
var time_key: String:
	get:
		var p := phase
		if p < 0.125 or p >= 0.875:
			return "night"
		if p < 0.25:
			return "dawn"
		if p < 0.5:
			return "day"
		if p < 0.75:
			return "dusk"
		return "evening"

func _duration() -> int:
	return int(round(WEATHER_MIN + rng.nextf() * float(WEATHER_MAX - WEATHER_MIN)))

## Выбирает следующее условие: никогда не то же самое, что сейчас.
func _pick_next() -> void:
	var others := []
	for k in TYPES.keys():
		if k != condition:
			others.append(k)
	var total := 0.0
	for k in others:
		total += float(TYPES[k]["weight"])
	var roll := rng.nextf() * total
	for k in others:
		roll -= float(TYPES[k]["weight"])
		if roll <= 0.0:
			condition = k
			return
	condition = others[others.size() - 1]

## Один тик погоды.
func update() -> void:
	cycle_ticks += 1

	timer -= 1
	if timer <= 0:
		_pick_next()
		timer = _duration()

	# Плавно стремимся к целевой интенсивности условия.
	var target: Dictionary = TYPES[condition]
	rain = clampf(rain + (float(target["rain"]) - rain) * SMOOTH, 0.0, 1.0)
	fog = clampf(fog + (float(target["fog"]) - fog) * SMOOTH, 0.0, 1.0)

	# Молнии только в грозу.
	flash *= 0.85
	if condition == "storm" and flash < 0.2 and rng.nextf() < float(target["lightning"]):
		flash = 1.0

## Принудительно ставит условие и его длительность.
func set_condition(id: String, ticks: int = -1) -> void:
	if not TYPES.has(id):
		return
	condition = id
	rain = float(TYPES[id]["rain"])
	fog = float(TYPES[id]["fog"])
	timer = ticks if ticks > 0 else _duration()
