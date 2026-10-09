extends Node

var failures := 0
var stat_counts := {}

func _ready() -> void:
	await get_tree().process_frame
	_check_week_keys()
	_check_monotonic_periods()
	_check_mutator_math()
	_check_ice_storm()
	_check_barrels()
	_check_defense_waves()
	_check_emp_overload()
	_check_cryo_shot()
	_check_stat_signals()
	Mutators.activate("")
	print("=== ПРОВЕРКА НЕДЕЛИ И МУТАТОРОВ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _unix(year: int, month: int, day: int) -> int:
	return int(Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day, "hour": 12, "minute": 0, "second": 0}))

func _check_week_keys() -> void:
	var cases := [
		[2026, 1, 1, "2026-W01"],
		[2025, 12, 29, "2026-W01"],
		[2025, 12, 28, "2025-W52"],
		[2026, 12, 31, "2026-W53"],
		[2027, 1, 3, "2026-W53"],
		[2027, 1, 4, "2027-W01"],
		[2026, 10, 9, "2026-W41"],
	]
	for c in cases:
		var got := GameClock.week_key(_unix(c[0], c[1], c[2]))
		_check(got == c[3], "%04d-%02d-%02d -> %s (ждали %s)" % [c[0], c[1], c[2], got, c[3]])
	var monday := GameClock.week_index(_unix(2026, 10, 5))
	var sunday := GameClock.week_index(_unix(2026, 10, 11))
	var next_monday := GameClock.week_index(_unix(2026, 10, 12))
	_check(monday == sunday and next_monday == monday + 1, "неделя идёт с понедельника по воскресенье")
	var left := GameClock.seconds_until_next_week()
	_check(left > 0 and left <= 7 * 86400, "до конца недели осталось %d с" % left)

func _check_monotonic_periods() -> void:
	var profile = load("res://scripts/profile.gd").new()
	profile._empty_stats()
	profile._empty_upgrades()
	profile.weekly = {"week": "2999-W10", "progress": {"kills": 7}, "claimed": true}
	profile.daily = {"date": "2999-01-01", "progress": {"kills": 3}, "claimed": ["kill_15"]}
	var wp: Dictionary = profile.get_weekly_progress()
	_check(bool(wp["claimed"]) and int(wp["current"]) == 7,
		"откат часов не сбрасывает недельный прогресс и награду")
	_check(String(profile.weekly["week"]) == "2999-W10", "ключ недели не уходит назад")
	var dp: Dictionary = profile.daily_progress("kill_15")
	_check(bool(dp["claimed"]) and int(dp["current"]) == 3, "откат часов не сбрасывает дневное задание")
	_check(profile.daily_key() == "2999-01-01", "ключ дня не уходит назад")
	_check(profile.weekly_challenge() == Weekly.challenge_for("2999-W10"),
		"испытание берётся по сохранённой неделе")
	profile.weekly = {"week": "2000-W10", "progress": {"kills": 7}, "claimed": true}
	profile.daily = {"date": "2000-01-01", "progress": {"kills": 3}, "claimed": ["kill_15"]}
	wp = profile.get_weekly_progress()
	_check(not bool(wp["claimed"]) and int(wp["current"]) == 0, "новая неделя сбрасывает прогресс")
	_check(profile.daily_key() == Daily.today_key(), "новый день сбрасывает задания")
	profile.free()

	var legacy = load("res://scripts/profile.gd").new()
	legacy._empty_stats()
	legacy._empty_upgrades()
	legacy._apply({"weekly": {"week": "2026-W51", "progress": {"kills": 9}, "claimed": true}})
	_check(String(legacy.weekly.get("week", "")) in ["", Weekly.week_key()] and int(legacy.weekly.get("progress", {}).get("kills", 0)) == 0,
		"старый формат ключа недели из сейва не блокирует новую неделю")
	legacy.get_weekly_progress()
	_check(String(legacy.weekly["week"]) == Weekly.week_key(), "после миграции неделя совпадает с текущей")
	legacy._apply({"weekly": {"week": "2999-W10", "progress": {"kills": 4}, "claimed": false, "scheme": GameClock.WEEK_SCHEME}})
	_check(String(legacy.weekly["week"]) == "2999-W10" and int(legacy.weekly["progress"]["kills"]) == 4,
		"сейв нового формата загружается как есть")
	legacy.free()

func _check_mutator_math() -> void:
	for id in Mutators.ALL:
		_check(not Weekly.get_challenge_by_mutator(id).is_empty(), "мутатор %s есть в недельных заданиях" % id)
	Mutators.activate("iron_ram")
	var mods := Perks.base_modifiers()
	Mutators.apply_mods(mods)
	_check(is_equal_approx(float(mods["ramMult"]), Cfg.MUT_IRON_RAM_MULT), "iron_ram: урон тарана ×%.2f" % mods["ramMult"])
	_check(is_equal_approx(Mutators.dash_distance(100.0), 100.0 * Cfg.MUT_IRON_DASH_MULT), "iron_ram: рывок длиннее")
	Mutators.activate("sniper_elite")
	mods = Perks.base_modifiers()
	Mutators.apply_mods(mods)
	_check(is_equal_approx(float(mods["bulletSpeedMult"]), Cfg.MUT_SNIPER_SPEED_MULT), "sniper_elite: снаряды быстрее")
	_check(is_equal_approx(float(mods["accuracyBonus"]), Cfg.MUT_SNIPER_ACCURACY), "sniper_elite: точность выше")
	Mutators.activate("bogus")
	_check(Mutators.active == "", "неизвестный мутатор не включается")
	Mutators.activate("")
	mods = Perks.base_modifiers()
	Mutators.apply_mods(mods)
	_check(is_equal_approx(float(mods["ramMult"]), 1.0) and Mutators.barrel_count(4) == 4 and Mutators.wave_size(5) == 5,
		"без мутатора ничего не меняется")

func _make_world(mode: String, mutator: String, seed_value: int = 4321) -> World:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, mode, seed_value, "city")
	return World.new({
		"map": level["map"], "level": level, "mode": mode, "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": seed_value, "mutator": mutator,
	})

func _check_ice_storm() -> void:
	var plain := _make_world("ffa", "")
	var plain_traction: float = plain.weather.traction
	var icy := _make_world("ffa", "ice_storm")
	_check(icy.weather.condition == "snow" and icy.weather.locked, "ice_storm: вечный снегопад")
	_check(icy.weather.traction < 0.8, "ice_storm: сцепление хуже снега (%.2f)" % icy.weather.traction)
	_check(plain_traction >= 0.8 or plain.weather.condition != "snow", "без мутатора сцепление обычное (%.2f)" % plain_traction)
	icy.dispose()
	plain.dispose()

func _check_barrels() -> void:
	var plain := _make_world("ffa", "")
	var base := plain.barrels.size()
	plain.dispose()
	var frenzy := _make_world("ffa", "explosive_frenzy")
	_check(base > 0 and frenzy.barrels.size() >= base * 2,
		"explosive_frenzy: бочек %d вместо %d" % [frenzy.barrels.size(), base])
	frenzy.dispose()

func _check_defense_waves() -> void:
	var plain := _make_world("defense", "")
	plain._setup_wave(1)
	var base := plain.defense_wave_size
	plain.dispose()
	var hard := _make_world("defense", "hardcore_waves")
	hard._setup_wave(1)
	_check(hard.defense_wave_size == int(ceil(float(base) * Cfg.MUT_WAVE_SIZE_MULT)),
		"hardcore_waves: волна %d вместо %d" % [hard.defense_wave_size, base])
	hard.dispose()

func _ticks_to_discharge(world: World) -> int:
	var gen = world.power_generators[0]
	var ptank: Tank = world.players[0].tank
	for t in world.tanks:
		if t != ptank:
			t.alive = false
	ptank.alive = true
	ptank.x = gen.x
	ptank.y = gen.y
	gen.cooldown = 0
	gen.capture_progress = 0.0
	var n := 0
	while gen.cooldown <= 0 and n < 600:
		gen.update(world)
		n += 1
	return n

func _check_emp_overload() -> void:
	var plain := _make_world("ffa", "")
	var slow := _ticks_to_discharge(plain)
	plain.dispose()
	var fast_world := _make_world("ffa", "emp_overload")
	var fast := _ticks_to_discharge(fast_world)
	var cooldown: int = fast_world.power_generators[0].cooldown
	_check(slow > 0 and slow < 600 and fast * 2 <= slow + 2 and fast * 2 >= slow - 2,
		"emp_overload: зарядка %d тиков вместо %d" % [fast, slow])
	_check(cooldown < 1200, "emp_overload: откат генератора короче (%d)" % cooldown)
	fast_world.dispose()

func _check_cryo_shot() -> void:
	var world := _make_world("ffa", "ice_storm")
	var shooter: Tank = world.players[0].tank
	var target: Tank = null
	for t in world.tanks:
		if t != shooter and t.alive:
			target = t
			break
	if target == null:
		_check(false, "цель для криовыстрела не найдена")
		world.dispose()
		return
	shooter.spawn_protect = 0
	target.spawn_protect = 0
	target.perk_ids = []
	target.recompute()
	target.freeze_ticks = 0
	target.cryo_immunity_ticks = 0
	var b = Ent.Bullet.new(target.x, target.y, 0.0, shooter, 1.0)
	world.bullets.append(b)
	world.step()
	_check(target.freeze_ticks > 0 or target.cryo_immunity_ticks > 0, "ice_storm: попадание замораживает цель")
	_check(target.cryo_immunity_ticks > 0, "ice_storm: после заморозки включается иммунитет")
	var frozen_left := target.freeze_ticks
	var b2 = Ent.Bullet.new(target.x, target.y, 0.0, shooter, 1.0)
	world.bullets.append(b2)
	world.step()
	_check(target.freeze_ticks <= frozen_left, "ice_storm: повторный выстрел не продлевает заморозку")
	world.dispose()

func _check_stat_signals() -> void:
	var world := _make_world("ffa", "")
	stat_counts.clear()
	world.stat.connect(func(key: String, value: int, _kind: String):
		stat_counts[key] = int(stat_counts.get(key, 0)) + value)
	var ptank: Tank = world.players[0].tank
	ptank.spawn_protect = 0
	var barrel := Ent.ExplosiveBarrel.new(ptank.x + 400.0, ptank.y + 400.0)
	barrel.hit(25.0, ptank, world)
	_check(int(stat_counts.get("barrelsExploded", 0)) == 1, "взрыв бочки игроком считается в статистике")
	var bot_barrel := Ent.ExplosiveBarrel.new(ptank.x + 500.0, ptank.y + 500.0)
	bot_barrel.hit(25.0, null, world)
	_check(int(stat_counts.get("barrelsExploded", 0)) == 1, "взрыв бочки без игрока не считается")
	var gen = world.power_generators[0]
	gen.discharge(world, ptank.team)
	_check(int(stat_counts.get("empDischarged", 0)) == 1, "разряд генератора игроком считается в статистике")
	world.dispose()

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
