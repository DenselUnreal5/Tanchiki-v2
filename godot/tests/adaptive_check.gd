extends Node

var failures := 0

func _ready() -> void:
	await get_tree().process_frame
	_check_controller()
	_check_clamps()
	_check_world_scaling()
	_check_disabled_online()
	print("=== ПРОВЕРКА АДАПТИВНОЙ СЛОЖНОСТИ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check_controller() -> void:
	var d := AdaptiveDifficulty.new()
	d.record_death()
	d.close_window()
	_check(d.level < 0.0, "смерть в окне облегчает игру (%.2f)" % d.level)
	var after_death := d.level
	d.record_kill()
	d.record_kill()
	d.record_damage(0.1)
	d.close_window()
	_check(d.level > after_death, "уверенная игра усложняет (%.2f -> %.2f)" % [after_death, d.level])
	d.level = 0.5
	d.record_damage(1.2)
	d.close_window()
	_check(d.level < 0.5, "тяжёлый урон без смертей слегка облегчает (%.2f)" % d.level)
	d.level = 0.5
	d.close_window()
	_check(d.level < 0.5 and d.level > 0.4, "спокойное окно возвращает к норме плавно (%.2f)" % d.level)
	var t := AdaptiveDifficulty.new()
	t.record_death()
	t.tick(Cfg.ADAPT_WINDOW_TICKS - 1)
	_check(t.windows_done == 0, "окно не закрывается раньше срока")
	t.tick(Cfg.ADAPT_WINDOW_TICKS)
	_check(t.windows_done == 1 and t.window_deaths == 0, "окно закрывается и сбрасывает счётчики")

func _check_clamps() -> void:
	var d := AdaptiveDifficulty.new()
	for i in 40:
		d.record_death()
		d.close_window()
	_check(is_equal_approx(d.level, -1.0), "уровень не уходит ниже -1")
	_check(is_equal_approx(d.hp_mult(), 1.0 - Cfg.ADAPT_HP), "минимум здоровья врагов %.2f" % d.hp_mult())
	_check(d.wave_size(10) == 8, "волна на минимуме: %d вместо 10" % d.wave_size(10))
	for i in 80:
		d.record_kill()
		d.record_kill()
		d.close_window()
	_check(is_equal_approx(d.level, 1.0), "уровень не поднимается выше 1")
	_check(is_equal_approx(d.hp_mult(), 1.0 + Cfg.ADAPT_HP), "максимум здоровья врагов %.2f" % d.hp_mult())
	_check(d.react_mult() < 1.0 and d.accuracy_bonus() > 0.0 and d.speed_mult() > 1.0, "на максимуме враги сильнее")

func _make_world(adaptive: bool, mode: String = "ffa") -> World:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, mode, 9876, "city")
	return World.new({
		"map": level["map"], "level": level, "mode": mode, "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 9876, "adaptive": adaptive,
	})

func _bot_hp(world: World) -> float:
	for t in world.tanks:
		if t.is_bot and not t.is_boss:
			return t.max_hp
	return 0.0

func _check_world_scaling() -> void:
	var plain := _make_world(false)
	var base_hp := _bot_hp(plain)
	_check(plain.director == null, "без флага директора нет")
	plain.dispose()
	var world := _make_world(true)
	_check(world.director != null, "с флагом директор создан")
	var start_hp := _bot_hp(world)
	_check(is_equal_approx(start_hp, base_hp), "на нулевом уровне враги как обычно (%.0f)" % start_hp)
	world.director.level = -1.0
	world._refresh_director()
	var easy_hp := _bot_hp(world)
	_check(easy_hp < base_hp, "облегчение режет здоровье живых врагов (%.0f -> %.0f)" % [base_hp, easy_hp])
	world.director.level = 1.0
	world._refresh_director()
	var hard_hp := _bot_hp(world)
	_check(hard_hp > base_hp, "усложнение поднимает здоровье живых врагов (%.0f -> %.0f)" % [base_hp, hard_hp])
	world.director.level = 0.0
	world._refresh_director()
	_check(absf(_bot_hp(world) - base_hp) <= 1.0, "возврат на ноль возвращает исходное здоровье")
	var ptank: Tank = world.players[0].tank
	ptank.spawn_protect = 0
	var before_damage := world.director.window_damage
	world.deal_damage(ptank, 10.0, null, "emp")
	_check(world.director.window_damage > before_damage, "урон по игроку учитывается директором")
	var killer: Tank = null
	for t in world.tanks:
		if t.is_bot and t.alive and t != ptank:
			killer = t
			break
	var deaths_before := world.director.window_deaths
	world.deal_damage(ptank, 9999.0, killer, "bullet")
	_check(world.director.window_deaths == deaths_before + 1, "смерть игрока учитывается директором")
	world.dispose()
	var defense_plain := _make_world(false, "defense")
	defense_plain._setup_wave(1)
	var base_size := defense_plain.defense_wave_size
	defense_plain.dispose()
	var defense := _make_world(true, "defense")
	defense.director.level = 1.0
	defense._setup_wave(1)
	_check(defense.defense_wave_size > base_size, "оборона: на максимуме волна больше (%d вместо %d)" % [defense.defense_wave_size, base_size])
	defense.dispose()

func _check_disabled_online() -> void:
	_check(Sets.adaptive_difficulty, "по умолчанию адаптивная сложность включена")

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
