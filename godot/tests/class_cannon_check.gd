extends Node

var failures := 0

const CANNONS := ["standard", "ice", "fire", "shock", "acid"]
const SECONDS := 30

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	var table := {}
	print("Непрерывный огонь %d с по неподвижной цели: выстрелов / перегревов / урон цели / время эффекта цели (%%)" % SECONDS)
	for cannon in CANNONS:
		var base := {}
		for cid in TankClasses.ids():
			var r := _run(String(cid), String(cannon))
			table[cannon + "/" + String(cid)] = r
			if cid == "standard":
				base = r
			print("  %-8s %-9s выстрелов %3d | перегревов %d (в перегреве %2.0f%%) | урон %5.0f | эффект %3.0f%% | наложений ×%.2f" % [
				cannon, cid, r["shots"], r["overheats"], r["hot"] * 100.0, r["damage"], r["uptime"] * 100.0,
				float(r["applications"]) / maxf(1.0, float(base["applications"]))])
	for cannon in ["ice", "fire", "shock", "acid"]:
		var base: Dictionary = table[cannon + "/standard"]
		for cid in TankClasses.ids():
			var r: Dictionary = table[cannon + "/" + String(cid)]
			if r.get("lobbed", false):
				var mortar_std: Dictionary = table["standard/mortar"]
				_check(absi(int(r["shots"]) - int(mortar_std["shots"])) <= 2,
					"%s на Миномёте: выстрелов %d, как со стандартной пушкой (%d), пушка не даёт обойти нагрев" % [cannon, r["shots"], mortar_std["shots"]])
				continue
			var ratio := float(r["applications"]) / maxf(1.0, float(base["applications"]))
			_check(ratio <= 1.15 and ratio >= 0.85,
				"%s на классе «%s»: частота наложения эффекта %.2f от Универсала (допуск ±15%%)" % [cannon, cid, ratio])
			var shots_ratio := float(r["shots"]) / maxf(1.0, float(base["shots"]))
			_check(shots_ratio <= 1.15 and shots_ratio >= 0.85,
				"%s на классе «%s»: выстрелов %.2f от Универсала (допуск ±15%%)" % [cannon, cid, shots_ratio])
	print("=== ПРОВЕРКА КЛАССОВ СО СПЕЦПУШКАМИ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _run(class_id: String, cannon: String) -> Dictionary:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	player.equipped_class = class_id
	player.equipped_cannon = cannon
	var level := LevelGen.generate(1, "ffa", 777, "city")
	var world := World.new({
		"map": level["map"], "level": level, "mode": "ffa", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 777,
	})
	world.map.fill(Cfg.T_EMPTY)
	world.tanks = [player.tank]
	world.barrels.clear()
	world.pickups.clear()
	world.weapon_pickups.clear()
	world.power_generators.clear()
	var p: Tank = player.tank
	p.x = 400.0
	p.y = 400.0
	p.spawn_protect = 0
	var v: Tank = world._spawn_bot("enemy", "enemy", "heavy")
	v.x = 600.0
	v.y = 400.0
	v.spawn_protect = 0
	v.brain = null
	v.base_max_hp = 1000000.0
	v.max_hp = 1000000.0
	v.hp = 1000000.0
	var active_ticks := 0
	var applications := 0
	var overheated_ticks := 0
	var prev_freeze := 0
	var prev_stun := 0
	var prev_burn := 0
	var prev_acid := 0
	for i in SECONDS * 60:
		p.hp = p.max_hp
		p.aim_at(v.x, v.y)
		p.shoot(world)
		world.step()
		v.vx = 0.0
		v.vy = 0.0
		if v.freeze_ticks > 0 or v.stun_ticks > 0 or v.burn_ticks > 0 or v.acid_stacks > 0:
			active_ticks += 1
		if p.overheated:
			overheated_ticks += 1
		if v.freeze_ticks > prev_freeze or v.stun_ticks > prev_stun or v.burn_ticks > prev_burn or v.acid_stacks > prev_acid:
			applications += 1
		prev_freeze = v.freeze_ticks
		prev_stun = v.stun_ticks
		prev_burn = v.burn_ticks
		prev_acid = v.acid_stacks
	if cannon == "standard":
		applications = p.shots_fired
	return {"shots": p.shots_fired, "overheats": p.overheats, "damage": 1000000.0 - v.hp,
		"uptime": float(active_ticks) / float(SECONDS * 60), "applications": applications,
		"hot": float(overheated_ticks) / float(SECONDS * 60),
		"lobbed": TankClasses.is_lobbed(class_id)}
