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
const DAY_LIGHT := {"dawn": 0.35, "day": 1.0, "dusk": 0.4, "night": 0.14}

## Минимальная и максимальная длительность погодного условия, тиков.
const WEATHER_MIN := 20 * 60
const WEATHER_MAX := 50 * 60

## rain/fog/snow — целевая интенсивность (0..1), lightning — шанс вспышки
## за тик. Ещё два поля — то, ради чего погода вообще влияет на игру:
##   vision   — множитель дальности зрения ботов;
##   traction — множитель сцепления с грунтом (снег скользит).
const TYPES := {
	"clear": {"id": "clear", "rain": 0.0, "fog": 0.0, "snow": 0.0,
		"lightning": 0.0, "vision": 1.0, "traction": 1.0, "weight": 3},
	"rain": {"id": "rain", "rain": 1.0, "fog": 0.15, "snow": 0.0,
		"lightning": 0.0, "vision": 0.85, "traction": 0.94, "weight": 2},
	# Густой туман: видно на треть дальности, зато и вас не видят.
	"fog": {"id": "fog", "rain": 0.0, "fog": 1.0, "snow": 0.0,
		"lightning": 0.0, "vision": 0.42, "traction": 1.0, "weight": 2},
	"storm": {"id": "storm", "rain": 1.0, "fog": 0.45, "snow": 0.0,
		"lightning": 0.02, "vision": 0.60, "traction": 0.92, "weight": 1},
	# Снег: заносит обзор и, главное, скользит — по нему танк разгоняется
	# и тормозит заметно хуже.
	"snow": {"id": "snow", "rain": 0.0, "fog": 0.30, "snow": 1.0,
		"lightning": 0.0, "vision": 0.75, "traction": 0.80, "weight": 2},
}

## Скорость плавного перехода к целевой интенсивности за тик.
const SMOOTH := 0.002

var rng: Rng
var cycle_ticks := 0
var condition := "clear"
var rain := 0.0
var fog := 0.0
var snow := 0.0
var timer := 0
var flash := 0.0
## Погода закреплена игроком: смена условий не идёт.
var locked := false
## Время суток закреплено: цикл дня стоит. Иначе выбранная «ночь» через
## две минуты превращалась бы в рассвет, а игрок просил именно ночь.
var time_locked := false

## @param opts condition — закрепить условие, phase — закрепить время суток
func _init(seed_value: int, opts: Dictionary = {}) -> void:
	rng = Rng.new((seed_value ^ 0x9e3779b9) & 0xFFFFFFFF)
	cycle_ticks = int(round(DAY_START_PHASE * DAY_CYCLE))
	timer = _duration()

	var forced := String(opts.get("condition", ""))
	if TYPES.has(forced):
		locked = true
		condition = forced
		rain = float(TYPES[forced]["rain"])
		fog = float(TYPES[forced]["fog"])
		snow = float(TYPES[forced]["snow"])
	if opts.has("phase"):
		time_locked = true
		cycle_ticks = int(round(clampf(float(opts["phase"]), 0.0, 0.999) * DAY_CYCLE))

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
##
## Границы подогнаны под кривую освещения: самая тёмная точка цикла — 0.75,
## и раньше она называлась «вечер», а «ночью» звался уже подъём к рассвету.
## Снимок с выбранной ночью подписывался «закат» — это и вскрылось.
var time_name: String:
	get:
		match time_key:
			"dawn":
				return "рассвет"
			"day":
				return "день"
			"dusk":
				return "закат"
			"midnight":
				return "полночь"
			_:
				return "ночь"

## Ключ времени суток для перевода.
var time_key: String:
	get:
		var p := phase
		if p < 0.125:
			return "night"
		if p < 0.25:
			return "dawn"
		if p < 0.5:
			return "day"
		if p < 0.68:
			return "dusk"
		if p < 0.73:
			return "night"
		if p < 0.80:
			return "midnight"
		return "night"

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

## Множитель дальности зрения ботов. Ночь и туман перемножаются: в туманную
## ночь бот и правда почти слеп, и это честно — игрок в ней тоже почти слеп.
var vision_scale: float:
	get:
		var by_type: float = float(TYPES[condition].get("vision", 1.0))
		# Свет 1.0 днём и 0.18 ночью превращается в множитель 1.0 .. 0.55.
		var by_light: float = lerpf(0.55, 1.0, clampf(light, 0.0, 1.0))
		return clampf(by_type * by_light, 0.25, 1.0)

## Множитель сцепления с грунтом. Снег скользит, дождь — чуть-чуть.
var traction: float:
	get:
		return float(TYPES[condition].get("traction", 1.0))

## Один тик погоды.
func update() -> void:
	if not time_locked:
		cycle_ticks += 1

	if not locked:
		timer -= 1
		if timer <= 0:
			_pick_next()
			timer = _duration()

	# Плавно стремимся к целевой интенсивности условия.
	var target: Dictionary = TYPES[condition]
	rain = clampf(rain + (float(target["rain"]) - rain) * SMOOTH, 0.0, 1.0)
	fog = clampf(fog + (float(target["fog"]) - fog) * SMOOTH, 0.0, 1.0)
	snow = clampf(snow + (float(target["snow"]) - snow) * SMOOTH, 0.0, 1.0)

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
	snow = float(TYPES[id]["snow"])
	timer = ticks if ticks > 0 else _duration()
