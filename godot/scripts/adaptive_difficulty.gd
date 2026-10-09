class_name AdaptiveDifficulty
extends RefCounted

var level := 0.0
var window_kills := 0
var window_deaths := 0
var window_damage := 0.0
var windows_done := 0
var last_change := 0.0

func record_kill() -> void:
	window_kills += 1

func record_death() -> void:
	window_deaths += 1

func record_damage(fraction_of_max_hp: float) -> void:
	window_damage += maxf(0.0, fraction_of_max_hp)

func tick(world_tick: int) -> void:
	if world_tick <= 0 or world_tick % Cfg.ADAPT_WINDOW_TICKS != 0:
		return
	close_window()

func close_window() -> void:
	var before := level
	var delta := 0.0
	if window_deaths > 0:
		delta -= Cfg.ADAPT_STEP_DEATH * float(mini(window_deaths, 2))
	elif window_damage <= Cfg.ADAPT_EASY_DAMAGE and window_kills >= Cfg.ADAPT_EASY_KILLS:
		delta += Cfg.ADAPT_STEP_UP
	elif window_damage >= Cfg.ADAPT_HARD_DAMAGE:
		delta -= Cfg.ADAPT_STEP_DOWN
	else:
		delta = -signf(level) * minf(absf(level), Cfg.ADAPT_DRIFT)
	level = clampf(level + delta, -1.0, 1.0)
	last_change = level - before
	windows_done += 1
	window_kills = 0
	window_deaths = 0
	window_damage = 0.0

func hp_mult() -> float:
	return 1.0 + Cfg.ADAPT_HP * level

func accuracy_bonus() -> float:
	return Cfg.ADAPT_ACCURACY * level

func react_mult() -> float:
	return 1.0 - Cfg.ADAPT_REACT * level

func speed_mult() -> float:
	return 1.0 + Cfg.ADAPT_SPEED * level

func wave_size(base: int) -> int:
	return maxi(1, int(round(float(base) * (1.0 + Cfg.ADAPT_WAVE * level))))
