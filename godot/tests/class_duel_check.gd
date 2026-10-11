extends Node

var failures := 0

const ENEMIES := ["grunt", "scout", "heavy", "sniper", "mortar", "pyro", "tesla"]
const SEEDS := [101, 202, 303]
const DUEL_TICKS := 1800

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	_measure_ram()
	_measure_shell()
	_measure_duels()
	print("=== ЗАМЕРЫ КЛАССОВ ЗАВЕРШЕНЫ, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _arena(class_id: String, seed_value: int) -> World:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	player.equipped_class = class_id
	var level := LevelGen.generate(1, "ffa", seed_value, "city")
	var world := World.new({
		"map": level["map"], "level": level, "mode": "ffa", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": seed_value,
	})
	world.map.fill(Cfg.T_EMPTY)
	world.tanks = [player.tank]
	world.barrels.clear()
	world.pickups.clear()
	world.weapon_pickups.clear()
	world.power_generators.clear()
	var ptank: Tank = player.tank
	ptank.x = 400.0
	ptank.y = 400.0
	ptank.vx = 0.0
	ptank.vy = 0.0
	ptank.spawn_protect = 0
	return world

func _victim(world: World, type_id: String, x: float, y: float, keep_brain: bool) -> Tank:
	var t: Tank = world._spawn_bot("enemy", "enemy", type_id)
	t.x = x
	t.y = y
	t.spawn_protect = 0
	if not keep_brain:
		t.brain = null
	return t

func _measure_ram() -> void:
	print("[1/3] Таран: урон за 1 секунду непрерывного контакта по неподвижной цели")
	for id in TankClasses.ids():
		var world := _arena(id, 4242)
		var a: Tank = world.players[0].tank
		var v := _victim(world, "heavy", 460.0, 400.0, false)
		v.max_hp = 100000.0
		v.hp = 100000.0
		v.base_max_hp = 100000.0
		var contacts := 0
		for i in 60:
			var before := v.hp
			a.thrust(1.0, 0.0)
			world.step()
			if v.hp < before:
				contacts += 1
		var dealt := 100000.0 - v.hp
		print("  %-9s урон %.0f за 60 тиков, тиков с ударом %d, скорость %.2f" % [id, dealt, contacts, a.speed])
		_check(true, "«%s»: замер тарана выполнен" % id)

func _measure_shell() -> void:
	print("[2/3] Мина Миномёта: куда летит при цели в 200 пикселях")
	var world := _arena("mortar", 4242)
	var t: Tank = world.players[0].tank
	t.aim_at(t.x + 200.0, t.y)
	t.fire_cooldown = 0
	var before := world.bullets.size()
	t.shoot(world)
	if world.bullets.size() <= before:
		_check(false, "мина создана")
		return
	var b: Ent.Bullet = world.bullets[before]
	var last_x: float = b.x
	var ticks: int = 0
	while b.alive and ticks < 400:
		world.step()
		ticks += 1
		if b.alive:
			last_x = b.x
	print("  прицел на 200 px, мина прожила %d тиков и взорвалась около x=%.0f (дальность %.0f px)" % [ticks, last_x, last_x - t.x])
	_check(true, "замер мины выполнен")

func _duel(class_id: String, enemy_id: String, seed_value: int) -> Dictionary:
	var world := _arena(class_id, seed_value)
	var p: Tank = world.players[0].tank
	var e := _victim(world, enemy_id, 650.0, 400.0, true)
	for i in DUEL_TICKS:
		if not p.alive or not e.alive:
			break
		p.aim_at(e.x, e.y)
		p.shoot(world)
		world.step()
	var result := "ничья"
	if not e.alive and p.alive:
		result = "победа"
	elif not p.alive and e.alive:
		result = "поражение"
	elif not p.alive and not e.alive:
		result = "обоюдно"
	return {"result": result, "ticks": world.tick, "hp": p.hp / p.max_hp if p.max_hp > 0.0 else 0.0,
		"ehp": e.hp / e.max_hp if e.max_hp > 0.0 else 0.0}

func _measure_duels() -> void:
	print("[3/3] Дуэли в открытом поле: класс против одного врага (ничья после 30 с), %d сидов" % SEEDS.size())
	print("  победы / время убийства / остаток HP игрока")
	var totals := {}
	for id in TankClasses.ids():
		var cells := []
		var wins := 0
		var played := 0
		for en in ENEMIES:
			var w := 0
			var tsum := 0.0
			var hpsum := 0.0
			for s in SEEDS:
				var r := _duel(id, en, int(s))
				played += 1
				if r["result"] == "победа":
					w += 1
					tsum += float(r["ticks"]) / 60.0
				hpsum += float(r["hp"])
			wins += w
			cells.append("%s %d/%d %s %.0f%%" % [en, w, SEEDS.size(),
				("%.1fс" % (tsum / float(w))) if w > 0 else "—", hpsum / float(SEEDS.size()) * 100.0])
		totals[id] = [wins, played]
		print("  %-9s побед %d/%d | %s" % [id, wins, played, " | ".join(cells)])
	_check(totals.size() == TankClasses.LIST.size(), "дуэли проведены для всех классов")
