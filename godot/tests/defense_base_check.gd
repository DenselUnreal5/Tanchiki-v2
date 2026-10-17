extends Node

var failures := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	var player := PlayerState.new(0, "P", "p2", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, "defense", 5150, "city")
	var world := World.new({"map": level["map"], "level": level, "mode": "defense", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 5150})
	world._setup_wave(1)
	var max_hp: float = float(world.base["max_hp"])
	world.base["hp"] = max_hp * 0.5
	for t in world.tanks:
		if t.is_bot:
			t.alive = false
	world._update_defense()
	_check(world.wave_state == "delay", "волна отбита")
	_check(is_equal_approx(float(world.base["hp"]), max_hp * 0.65),
		"за победу база восстановила 15%% (%.0f из %.0f)" % [world.base["hp"], max_hp])
	var after_win: float = float(world.base["hp"])
	for i in 120:
		world._update_defense()
	_check(is_equal_approx(float(world.base["hp"]), after_win), "в паузе между волнами база не лечится")
	world._setup_wave(2)
	world.base["hp"] = max_hp * 0.95
	for t in world.tanks:
		if t.is_bot:
			t.alive = false
	world._update_defense()
	_check(is_equal_approx(float(world.base["hp"]), max_hp), "лечение не выходит за максимум прочности")
	world.dispose()
	print("=== ПРОВЕРКА БАЗЫ ОБОРОНЫ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)
