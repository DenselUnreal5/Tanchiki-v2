extends Node

var failures := 0
var stat_log := {}

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	var backup := FileAccess.get_file_as_bytes(Prof.SAVE_PATH)
	var had_file := FileAccess.file_exists(Prof.SAVE_PATH)
	_check_profile()
	_check_fire()
	_check_shock()
	_check_dodge()
	_check_burn_kill()
	if had_file:
		var f := FileAccess.open(Prof.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Prof.SAVE_PATH))
	Prof.load_profile()
	print("=== ПРОВЕРКА СПЕЦПУШЕК ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _arena() -> World:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, "ffa", 5151, "city")
	var world := World.new({
		"map": level["map"], "level": level, "mode": "ffa", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 5151,
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
	world.stat.connect(func(key: String, value: int, _mode: String):
		stat_log[key] = int(stat_log.get(key, 0)) + value)
	return world

func _spawn(world: World, type_id: String, x: float, y: float) -> Tank:
	var t: Tank = world._spawn_bot("enemy", "enemy", type_id)
	t.x = x
	t.y = y
	t.spawn_protect = 0
	t.brain = null
	return t

func _fire_at(world: World, shooter: Tank, target: Tank) -> Ent.Bullet:
	shooter.aim_at(target.x, target.y)
	shooter.fire_cooldown = 0
	var before := world.bullets.size()
	shooter.shoot(world)
	return world.bullets[before] if world.bullets.size() > before else null

func _fly(world: World, bullet, max_ticks: int = 200) -> void:
	for i in max_ticks:
		world.step()
		if bullet == null or not bullet.alive:
			return

func _check_profile() -> void:
	print("[1/5] Пушки и испытания")
	for id in ["fire", "shock"]:
		_check(Cannons.is_special(id) and not Cannons.challenge_of(id).is_empty(), "пушка «%s» есть и у неё есть испытание" % id)
		Prof.cannon_owned.erase(id)
		Prof.stats[String(Cannons.challenge_of(id)["stat"])] = 0
	if Prof.equipped_cannon == "fire" or Prof.equipped_cannon == "shock":
		Prof.equipped_cannon = "standard"
	_check(not Prof.is_cannon_unlocked("fire") and not Prof.is_cannon_unlocked("shock"), "без испытания пушки закрыты")
	Prof.money = 100000
	_check(String(Prof.buy_cannon("fire").get("reason", "")) == "locked", "закрытую пушку купить нельзя")
	_check(Prof.money == 100000, "монеты при отказе не списаны")
	_check(Prof.is_cannon_unlocked("ice"), "обычные пушки открыты для покупки без испытания")
	var announced := []
	var cb := func(ids: Array): announced.append_array(ids)
	Prof.cannon_unlocked.connect(cb)
	Prof.bump_stat("pyroBurnKills", 9)
	_check(announced.is_empty() and not Prof.is_cannon_unlocked("fire"), "9 из 10 — Огнемёт ещё закрыт")
	Prof.bump_stat("pyroBurnKills", 1)
	_check(announced == ["fire"] and Prof.is_cannon_unlocked("fire"), "10 из 10 — Огнемёт открыт, уведомление пришло")
	Prof.bump_stat("pyroBurnKills", 1)
	_check(announced.size() == 1, "уведомление не повторяется")
	Prof.bump_stat("lightningDodges", 10)
	_check(announced.has("shock") and Prof.is_cannon_unlocked("shock"), "10 уклонений от молний открывают Громовержца")
	Prof.cannon_unlocked.disconnect(cb)
	Prof.money = 1000
	_check(String(Prof.buy_cannon("fire").get("reason", "")) == "money", "без денег открытую пушку не купить")
	Prof.money = 2000
	_check(bool(Prof.buy_cannon("fire").get("ok", false)) and Prof.money == 500 and Prof.is_cannon_owned("fire"),
		"покупка Огнемёта списывает 1500 монет")
	_check(bool(Prof.equip_cannon("fire").get("ok", false)), "Огнемёт можно надеть")

func _check_fire() -> void:
	print("[2/5] Огнемёт у игрока")
	var world := _arena()
	var ptank: Tank = world.players[0].tank
	ptank.cannon_id = "fire"
	_check(ptank.shot_kind() == "fire", "танк игрока стреляет огнём")
	var target := _spawn(world, "grunt", 560.0, 400.0)
	var b := _fire_at(world, ptank, target)
	_check(b != null and b.cannon_kind == "fire" and b.life == Cfg.FIRE_BULLET_LIFE, "вылетел огненный снаряд")
	var reload := int(round(float(ptank.reload_ticks()) * 0.8))
	_check(ptank.fire_cooldown == maxi(4, reload), "перезарядка Огнемёта ×0.8")
	_fly(world, b)
	_check(target.burn_ticks > 0, "цель загорелась")
	_check(not world.fire_patches.is_empty(), "на пути снаряда горит земля")
	var impact: float = Cfg.FIRE_IMPACT_DMG * b.dmg_scale
	_check(target.max_hp - target.hp >= impact - 0.5, "попадание обжигает цель на %.1f урона (%.1f)" % [impact, target.max_hp - target.hp])
	_check(target.burn_stacks == 1 and is_equal_approx(target.burn_power, b.dmg_scale), "первое попадание — 1 уровень горения")
	for i in Cfg.BURN_STACK_MAX:
		target.hp = target.max_hp
		_fly(world, _fire_at(world, ptank, target))
	_check(target.burn_stacks == Cfg.BURN_STACK_MAX, "повторные попадания раздувают пламя до %d уровней (%d)" % [Cfg.BURN_STACK_MAX, target.burn_stacks])
	world.fire_patches.clear()
	target.hp = target.max_hp
	var hp0: float = target.hp
	for i in Cfg.TICK_HZ:
		target._update_burn(world)
	var stacked_dps := hp0 - target.hp
	_check(stacked_dps >= Cfg.BURN_DPS * Cfg.BURN_STACK_MAX * b.dmg_scale - 0.5, "на 3 уровнях горит на %.1f урона в секунду" % stacked_dps)

	var pyro := _spawn(world, "pyro", 300.0, 400.0)
	var victim := ptank
	victim.x = 300.0
	victim.y = 520.0
	victim.burn_ticks = 0
	victim.burn_stacks = 0
	victim.hp = victim.max_hp
	var eb := Ent.Bullet.new(victim.x, victim.y - 60.0, PI / 2.0, pyro, 1.0)
	eb.cannon_kind = "fire"
	world.bullets.append(eb)
	_fly(world, eb)
	_check(victim.burn_stacks == 1 and victim.hp == victim.max_hp, "Огнемётчик-враг по-прежнему только поджигает")
	victim.burn_ticks = 0
	ptank.weapon = "test_weapon"
	_check(ptank.shot_kind() == "", "с подобранным оружием стреляет оружие, а не пушка")
	ptank.weapon = ""

func _check_shock() -> void:
	print("[3/5] Громовержец у игрока")
	var world := _arena()
	var ptank: Tank = world.players[0].tank
	ptank.cannon_id = "shock"
	var target := _spawn(world, "grunt", 600.0, 400.0)
	target.hp = target.max_hp
	var hp_before: float = target.hp
	var b := _fire_at(world, ptank, target)
	_check(b != null and b.cannon_kind == "shock", "вылетел заряд молнии")
	_fly(world, b)
	_check(absf(hp_before - target.hp - Cfg.SHOCK_DMG) < 0.5, "молния нанесла 10 урона (%.1f)" % (hp_before - target.hp))
	_check(target.stun_ticks > 0, "цель оглушена")

func _dodge_pass(offset: float, dashing: bool, shooter_type: String = "grunt") -> Dictionary:
	var world := _arena()
	var ptank: Tank = world.players[0].tank
	ptank.hp = ptank.max_hp
	var shooter := _spawn(world, shooter_type, 200.0, 400.0 + offset)
	world.step()
	stat_log.clear()
	var b := Ent.Bullet.new(250.0, 400.0 + offset, 0.0, shooter, 1.0)
	if shooter_type == "tesla":
		b.cannon_kind = "shock"
	world.bullets.append(b)
	ptank.x = 400.0
	ptank.y = 400.0
	for i in 60:
		ptank.dash_invuln_ticks = 15 if dashing else 0
		b.update(world)
		if not b.alive:
			break
	return {"hit": not b.alive and b.x < 450.0, "hp_lost": ptank.max_hp - ptank.hp,
		"dodges": int(stat_log.get("lightningDodges", 0))}

func _check_dodge() -> void:
	print("[4/5] Уклонение")
	var probe := _arena()
	var r: float = probe.players[0].tank.hit_r
	var near := _dodge_pass(r + 10.0, true)
	_check(near["hit"] and near["hp_lost"] == 0.0, "снаряд рядом с танком в рывке засчитан как уклонение")
	var far := _dodge_pass(r + Cfg.DODGE_GRACE_R + 6.0, true)
	_check(not far["hit"], "снаряд дальше радиуса уклонения пролетает мимо")
	var calm := _dodge_pass(r + 10.0, false)
	_check(not calm["hit"] and calm["hp_lost"] == 0.0, "без рывка тот же снаряд пролетает мимо")
	var direct := _dodge_pass(0.0, false)
	_check(direct["hit"] and direct["hp_lost"] > 0.0, "без рывка прямое попадание наносит урон")
	var bolt := _dodge_pass(r + 10.0, true, "tesla")
	_check(bolt["hit"] and bolt["dodges"] == 1, "уклонение от молнии идёт в счёт испытания")
	var plain := _dodge_pass(r + 10.0, true)
	_check(plain["dodges"] == 0, "уклонение от обычного снаряда в испытание не идёт")

func _check_burn_kill() -> void:
	print("[5/5] Крещение огнём")
	var world := _arena()
	var ptank: Tank = world.players[0].tank
	var pyro := _spawn(world, "pyro", 600.0, 400.0)
	stat_log.clear()
	ptank.burn_ticks = 0
	world._kill_tank(pyro, ptank, "bullet")
	_check(int(stat_log.get("pyroBurnKills", 0)) == 0, "убийство Огнемётчика без огня не считается")
	var pyro2 := _spawn(world, "pyro", 600.0, 300.0)
	ptank.burn_ticks = 100
	world._kill_tank(pyro2, ptank, "bullet")
	_check(int(stat_log.get("pyroBurnKills", 0)) == 1, "убийство Огнемётчика, пока горишь, засчитано")
	var grunt := _spawn(world, "grunt", 600.0, 500.0)
	world._kill_tank(grunt, ptank, "bullet")
	_check(int(stat_log.get("pyroBurnKills", 0)) == 1, "другие танки в это испытание не идут")
