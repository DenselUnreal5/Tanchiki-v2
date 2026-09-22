class_name WeatherSystem
extends RefCounted

const DAY_CYCLE := 10 * 60 * 60
const DAY_START_PHASE := 0.18

const DAY_PHASES := {"dawn": 0.0, "day": 0.25, "dusk": 0.5, "night": 0.75}
const DAY_LIGHT := {"dawn": 0.35, "day": 1.0, "dusk": 0.4, "night": 0.14}

const WEATHER_MIN := 20 * 60
const WEATHER_MAX := 50 * 60

const TYPES := {
	"clear": {"id": "clear", "rain": 0.0, "fog": 0.0, "snow": 0.0,
		"lightning": 0.0, "vision": 1.0, "traction": 1.0, "noise": 1.0, "weight": 3},
	"rain": {"id": "rain", "rain": 1.0, "fog": 0.15, "snow": 0.0,
		"lightning": 0.0, "vision": 0.85, "traction": 0.94, "noise": 0.8, "weight": 2},
	"fog": {"id": "fog", "rain": 0.0, "fog": 1.0, "snow": 0.0,
		"lightning": 0.0, "vision": 0.42, "traction": 1.0, "noise": 1.0, "weight": 2},
	"storm": {"id": "storm", "rain": 1.0, "fog": 0.45, "snow": 0.0,
	"lightning": 0.004, "vision": 0.60, "traction": 0.92, "noise": 0.5,
	"fells_trees": true, "weight": 1},
	"snow": {"id": "snow", "rain": 0.0, "fog": 0.30, "snow": 1.0,
		"lightning": 0.0, "vision": 0.75, "traction": 0.80, "noise": 0.85, "weight": 2},
}

const SMOOTH := 0.002

var rng: Rng
var cycle_ticks := 0
var condition := "clear"
var rain := 0.0
var fog := 0.0
var snow := 0.0
var timer := 0
var flash := 0.0
var locked := false
var time_locked := false

var allowed: Array = []

func _init(seed_value: int, opts: Dictionary = {}) -> void:
	rng = Rng.new((seed_value ^ 0x9e3779b9) & 0xFFFFFFFF)
	cycle_ticks = int(round(DAY_START_PHASE * DAY_CYCLE))
	timer = _duration()

	allowed = opts.get("allowed", [])
	if not allowed.is_empty() and not allowed.has(condition):
		condition = String(allowed[0])

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

var phase: float:
	get: return float(cycle_ticks % DAY_CYCLE) / float(DAY_CYCLE)

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

func _pick_next() -> void:
	var others := []
	for k in TYPES.keys():
		if k == condition:
			continue
		if not allowed.is_empty() and not allowed.has(k):
			continue
		others.append(k)
	if others.is_empty():
		return
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

var vision_scale: float:
	get:
		var by_type: float = float(TYPES[condition].get("vision", 1.0))
		var by_light: float = lerpf(0.55, 1.0, clampf(light, 0.0, 1.0))
		return clampf(by_type * by_light, 0.25, 1.0)

var traction: float:
	get:
		return float(TYPES[condition].get("traction", 1.0))

var noise_scale: float:
	get:
		return float(TYPES[condition].get("noise", 1.0))

var fells_trees: bool:
	get:
		return bool(TYPES[condition].get("fells_trees", false))

func update() -> void:
	if not time_locked:
		cycle_ticks += 1

	if not locked:
		timer -= 1
		if timer <= 0:
			_pick_next()
			timer = _duration()

	var target: Dictionary = TYPES[condition]
	rain = clampf(rain + (float(target["rain"]) - rain) * SMOOTH, 0.0, 1.0)
	fog = clampf(fog + (float(target["fog"]) - fog) * SMOOTH, 0.0, 1.0)
	snow = clampf(snow + (float(target["snow"]) - snow) * SMOOTH, 0.0, 1.0)

	flash *= 0.85
	if condition == "storm" and flash < 0.2 and rng.nextf() < float(target["lightning"]):
		flash = 1.0

func set_condition(id: String, ticks: int = -1) -> void:
	if not TYPES.has(id):
		return
	condition = id
	rain = float(TYPES[id]["rain"])
	fog = float(TYPES[id]["fog"])
	snow = float(TYPES[id]["snow"])
	timer = ticks if ticks > 0 else _duration()
