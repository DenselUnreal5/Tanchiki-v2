extends Node

var failures := 0

const SHOTS := 16
const DISTANCES := [150.0, 250.0, 300.0, 400.0, 550.0]

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	print("Фантомный снайпер: средний урон выстрела по неподвижной цели (без засады)")
	var results := {}
	for d in DISTANCES:
		var plain := _avg_damage(d, [])
		var ghost := _avg_damage(d, ["sniper", "evasion", "keen_ear"])
		results[d] = ghost / maxf(0.01, plain)
		print("  %4.0f px: без перков %.1f | билд %.1f | ×%.2f" % [d, plain, ghost, results[d]])
	_check(Perks.is_build_complete("ghost_sniper", ["sniper", "evasion", "keen_ear"]), "три перка собирают билд")
	_check(float(results[250.0]) < 1.25, "ближе порога (%.0f px) только +10%% от перка «Снайпер» (×%.2f)" % [Cfg.GHOST_SNIPER_RANGE, results[250.0]])
	_check(float(results[300.0]) > 1.6, "с порога %.0f px критический урон +60%% (×%.2f)" % [Cfg.GHOST_SNIPER_RANGE, results[300.0]])
	_check(float(results[550.0]) > 1.6, "на дальней дистанции критический урон работает (×%.2f)" % results[550.0])
	print("=== ПРОВЕРКА ФАНТОМНОГО СНАЙПЕРА ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _avg_damage(distance: float, perks: Array) -> float:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, "ffa", 515, "city")
	var world := World.new({
		"map": level["map"], "level": level, "mode": "ffa", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 515,
	})
	world.map.fill(Cfg.T_EMPTY)
	world.tanks = [player.tank]
	world.barrels.clear()
	world.pickups.clear()
	world.weapon_pickups.clear()
	world.power_generators.clear()
	for id in perks:
		player.equip_perk(String(id))
	var p: Tank = player.tank
	p.x = 100.0
	p.y = 400.0
	p.spawn_protect = 0
	var v: Tank = world._spawn_bot("enemy", "enemy", "heavy")
	v.x = 100.0 + distance
	v.y = 400.0
	v.spawn_protect = 0
	v.brain = null
	v.base_max_hp = 1000000.0
	v.max_hp = 1000000.0
	v.hp = 1000000.0
	var total := 0.0
	var counted := 0
	for i in SHOTS:
		p.aim_at(v.x, v.y)
		p.heat = 0.0
		p.overheated = false
		p.fire_cooldown = 0
		var before := v.hp
		p.shoot(world)
		for t in 90:
			world.step()
			v.vx = 0.0
			v.vy = 0.0
			v.x = 100.0 + distance
			v.y = 400.0
		if i > 0:
			total += before - v.hp
			counted += 1
	return total / float(maxi(1, counted))
