extends Node

var failures := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	var plain := _world({})
	var maxed := _world({"maxHPMult": 1.7, "damageTakenMult": 0.68, "regenPerMinute": 120.0})
	var p0: Tank = plain.players[0].tank
	var p1: Tank = maxed.players[0].tank
	_check(is_equal_approx(p0.enemy_threat_mult(), 1.0), "без апгрейдов урон врагов прежний")
	_check(is_equal_approx(p1.enemy_threat_mult(), 1.0 + (1.7 / 0.68 - 1.0) * Cfg.ENEMY_DMG_UPGRADE_SCALE),
		"с прокачанной бронёй враги бьют ×%.2f" % p1.enemy_threat_mult())
	_check(is_equal_approx(p0.upgrade_progress(), 0.0) and p1.upgrade_progress() > 0.2 and p1.upgrade_progress() < 0.5,
		"доля прокачки: новичок 0, три апгрейда на максимуме %.2f" % p1.upgrade_progress())
	var expected := p1.enemy_threat_mult(Cfg.mode_tune("ffa", "threat_scale", Cfg.ENEMY_DMG_UPGRADE_SCALE)) \
		* Cfg.mode_tune("ffa", "enemy_dmg", 1.0) \
		* (1.0 + p1.upgrade_progress() * Cfg.mode_tune("ffa", "progress_threat", 0.0))
	var bot0: Tank = plain._spawn_bot("enemy", "enemy", "grunt")
	var bot1: Tank = maxed._spawn_bot("enemy", "enemy", "grunt")
	var hit0 := plain.deal_damage(p0, 20.0, bot0, "bullet")
	var hit1 := maxed.deal_damage(p1, 20.0, bot1, "bullet")
	_check(is_equal_approx(hit0, 20.0), "новичок получает обычные 20 урона (%.1f)" % hit0)
	_check(is_equal_approx(hit1, 20.0 * 0.68 * expected), "прокачанный танк получает %.1f урона вместо %.1f" % [hit1, 20.0 * 0.68])
	_check(hit1 > hit0, "прокачанный танк теряет за попадание больше HP, чем без поправки")
	var burn := maxed.deal_damage(p1, 10.0, bot1, "fire")
	_check(is_equal_approx(burn, 10.0 * 0.68 * expected), "поправка действует и на огонь врагов")
	var other: Tank = maxed._spawn_bot("enemy", "enemy", "grunt")
	other.spawn_protect = 0
	var bot_vs_bot := maxed.deal_damage(other, 20.0, bot1, "bullet")
	_check(is_equal_approx(bot_vs_bot, 20.0) or bot_vs_bot == 0.0, "бот по боту бьёт без поправки")
	var rival := Tank.new({"x": p1.x + 50.0, "y": p1.y, "team": "enemy", "name": "P2", "owner": PlayerState.new(1, "P2", "p13", null),
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30})
	var pvp := maxed.deal_damage(p1, 20.0, rival, "bullet")
	_check(is_equal_approx(pvp, 20.0 * 0.68), "игрок по игроку бьёт без поправки (%.1f)" % pvp)
	var gunner := _world({"dmgMult": 1.6, "fireRateMult": 0.7})
	var g: Tank = gunner.players[0].tank
	var prey: Tank = gunner._spawn_bot("enemy", "enemy", "grunt")
	prey.spawn_protect = 0
	prey.hp = prey.max_hp
	var keep := Cfg.mode_tune("ffa", "offense_keep", 1.0)
	var offense := 1.6 / 0.7
	var dealt := gunner.deal_damage(prey, 20.0, g, "bullet")
	_check(is_equal_approx(dealt, 20.0 * (1.0 + (offense - 1.0) * keep) / offense),
		"в FFA прокачка урона по ботам учитывается на %.0f%% (%.1f из 20)" % [keep * 100.0, dealt])
	gunner.dispose()
	var koth := _world({}, "koth")
	var kp: Tank = koth.players[0].tank
	var kbot: Tank = null
	for t in koth.tanks:
		if t != kp:
			kbot = t
			break
	kp.spawn_protect = 0
	kp.hp = kp.max_hp
	var royale_hit := koth.deal_damage(kp, 20.0, kbot, "bullet")
	_check(is_equal_approx(royale_hit, 20.0 * Cfg.mode_tune("koth", "all_dmg", 1.0)), "в «Царе горы» урон снижен для всех (%.1f из 20)" % royale_hit)
	koth.dispose()
	var boss: Tank = plain._spawn_bot("enemy", "enemy", "boss")
	boss.brain = null
	boss.spawn_protect = 0
	p0.hp = p0.max_hp
	p0.boss_damage_grace_ticks = 0
	plain.deal_damage(p0, p0.max_hp * 0.3, boss, "bullet")
	_check(p0.boss_damage_grace_ticks > 0, "крупное попадание босса включает защиту от ваншота")
	var guarded := plain.deal_damage(p0, 10.0, boss, "bullet")
	_check(is_equal_approx(guarded, 10.0 * Cfg.BOSS_BURST_GRACE_REDUCTION), "сразу после него урон босса срезан (%.1f)" % guarded)
	for i in Cfg.BOSS_BURST_GRACE_TICKS + 2:
		p0.spawn_protect = 0
		plain.step()
	_check(p0.boss_damage_grace_ticks == 0, "защита от ваншота проходит через %d тиков" % Cfg.BOSS_BURST_GRACE_TICKS)
	p0.hp = p0.max_hp
	var later := plain.deal_damage(p0, 10.0, boss, "bullet")
	_check(is_equal_approx(later, 10.0), "после неё босс снова бьёт в полную силу (%.1f)" % later)
	plain.dispose()
	maxed.dispose()
	print("=== ПРОВЕРКА УРОНА ВРАГОВ ПО ПРОКАЧКЕ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _world(upgrades: Dictionary, mode: String = "ffa") -> World:
	var player := PlayerState.new(0, "P", "p2", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	player.equipped_class = TankClasses.DEFAULT
	player.equipped_cannon = "standard"
	player.upgrade_mods = upgrades
	var level := LevelGen.generate(1, mode, 4242, "city")
	var world := World.new({"map": level["map"], "level": level, "mode": mode, "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 4242})
	var p: Tank = player.tank
	p.spawn_protect = 0
	p.hp = p.max_hp
	return world
