# ============================================================================
# perk_bench.gd — замер боевой ценности перков.
#
# perks_check отвечает на вопрос «перк вообще что-то делает?». Этот тест
# отвечает на другой: «а в бою от него есть толк?». Разница между ними —
# ровно разница между строкой в таблице и перком.
#
# Как считается. Одна и та же партия разыгрывается несколько раз: карта,
# расстановка и затравка мира заданы жёстко (rng_seed), меняется только
# набор перков у игрока. За танк играет обычный «мозг» бота — эталонный
# игрок средней руки, одинаковый во всех прогонах.
#
# Запуск:
#   godot --headless --path godot tests/perk_bench.tscn
# ============================================================================
extends Node

## Тиков на прогон: 60 секунд боя.
const TICKS := 3600
## Сколько разных стартов усредняем. Переопределяется PERK_BENCH_SEEDS —
## одним стартом удобно проверять сам тест, не дожидаясь получаса.
const SEEDS := 6

var seeds := SEEDS
var seed0 := 0
var out_path := ""
var ids: Array = IDS.duplicate()
## Уровень профиля на время замера. Профиль растёт от боя к бою, а вместе
## с ним и сила врагов: без заморозки поздние прогоны идут против других
## противников, и разница перков смешивается с разницей сложности.
const FROZEN_LEVEL := 5

## Замеряемый набор: двадцать перков второй волны плюс контроль без перков.
const IDS := [
	"",
	"heat_sink", "thermal", "quick_vent", "heavy_shell", "light_shell",
	"road_king", "all_terrain",
	"lumberjack", "concrete_breaker", "can_opener", "scavenger",
	"keen_ear", "muffler",
	"coolant", "overclock", "grip", "breaker", "silencer", "smoke", "repair",
]

## Схема управления «как бот». Активную способность жмёт сразу, как откатится.
class Autopilot:
	var brain: BotBrain

	func _init(rng: Rng) -> void:
		brain = BotBrain.new({"accuracy": 0.8, "react_time": 12, "rng": rng})

	func apply(tank: Tank, _player, world) -> void:
		brain.update(tank, world)
		if tank.ability_id != "" and tank.ability_cd <= 0:
			tank.use_ability(world)

var game: Node
var results := {}

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var env := OS.get_environment("PERK_BENCH_SEEDS")
	if env != "":
		seeds = maxi(1, int(env))
	# Замер режется на части и раскладывается по процессам: одно ядро считает
	# 21 набор по полчаса, четыре — за четверть этого.
	var env0 := OS.get_environment("PERK_BENCH_SEED0")
	if env0 != "":
		seed0 = int(env0)
	out_path = OS.get_environment("PERK_BENCH_OUT")
	# Список наборов можно подменить снаружи: «-» означает контроль без перков.
	# Нужно для диагностики — например, чтобы прогнать контроль дважды и
	# увидеть, не зависит ли исход от порядка прогонов.
	var env_ids := OS.get_environment("PERK_BENCH_IDS")
	if env_ids != "":
		ids = []
		for part in env_ids.split(","):
			ids.append("" if part == "-" else part)

	for id in ids:
		results[id] = []

	var t0 := Time.get_ticks_msec()
	for si in seeds:
		for id in ids:
			results[id].append(await _run(seed0 + si, id))
		print("...старт %d из %d готов (%.0f с)"
			% [si + 1, seeds, (Time.get_ticks_msec() - t0) / 1000.0])

	_report()
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"seed0": seed0, "seeds": seeds,
			"ticks": TICKS, "runs": results}))
		f.close()
		print("сырые числа: ", out_path)
	get_tree().quit(0)

# --------------------------------------------------------------------- прогон
func _run(seed_index: int, perk_id: String) -> Dictionary:
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["difficulty"] = "medium"
	game.ui.settings["level"] = 1 + seed_index % 5
	Prof.global_level = FROZEN_LEVEL
	game.start_match({"rng_seed": 7000 + seed_index})
	_dismiss_perks()

	var player = game.players[0]
	player.scheme = Autopilot.new(game.world.rng)
	# Массив перков переиспользуется, а не подменяется: танк держит на него
	# ссылку с момента рождения, и присваивание нового списка игроку оставило
	# бы танк с прежним — первый прогон этого теста выдал всем двадцати перкам
	# одинаковые цифры именно поэтому.
	player.perk_ids.clear()
	if perk_id != "":
		player.perk_ids.append(perk_id)
	if player.tank != null:
		player.tank.perk_ids = player.perk_ids
		player.tank.recompute()
		player.tank.hp = player.tank.max_hp
	_verify(player, perk_id)

	var world: World = game.world
	# Постройки считаем по сигналу: у игрока такого счётчика нет, а именно
	# он показывает, работают ли перки на материалы.
	var walls := {"n": 0}
	world.stat.connect(func(key: String, value: int, _kind: String):
		if key == "bricksDestroyed" or key == "concreteDestroyed":
			walls["n"] += value)

	var taken := 0.0
	var alive_ticks := 0
	var prev_hp: float = player.tank.hp if player.tank != null else 0.0
	var ticks := 0
	while ticks < TICKS and not world.finished_flag:
		world.step()
		ticks += 1
		var t: Tank = player.tank
		if t != null:
			if t.alive:
				alive_ticks += 1
				# Считаем только просадки: возрождение поднимает HP скачком,
				# и без этой проверки оно засчиталось бы как отрицательный урон.
				if t.hp < prev_hp:
					taken += prev_hp - t.hp
			prev_hp = t.hp
		var pending := false
		for p in game.players:
			if p.pending_level_ups > 0:
				pending = true
				break
		if pending:
			game._process_perk_queue()
			_dismiss_perks()
			# Уровень мог выдать перк — набор держим ровно тем, что замеряем.
			player.perk_ids.clear()
			if perk_id != "":
				player.perk_ids.append(perk_id)
			if player.tank != null:
				player.tank.perk_ids = player.perk_ids
				player.tank.recompute()

	var minutes := float(ticks) / 3600.0
	var tank: Tank = player.tank
	return {
		"kills": float(player.kills) / minutes,
		"deaths": float(player.deaths) / minutes,
		"dealt": player.damage_dealt / minutes,
		"taken": taken / minutes,
		"walls": float(walls["n"]) / minutes,
		"alive": float(alive_ticks) / float(maxi(1, ticks)),
		# Длительность партии обязана попасть в отчёт: показатели считаются
		# «в минуту», и если партия обрывается по лимиту фрагов на разной
		# секунде, то и знаменатель у прогонов разный.
		"ticks": float(ticks),
		"shots": (float(tank.shots_fired) / minutes) if tank != null else 0.0,
		"overheats": (float(tank.overheats) / minutes) if tank != null else 0.0,
	}

## Перк обязан доехать до танка. Молчаливая потеря набора превращает замер
## в двадцать одинаковых строк — и выглядит это как «перки ничего не решают».
func _verify(player, perk_id: String) -> void:
	if perk_id == "":
		return
	var tank: Tank = player.tank
	if tank == null:
		return
	if not tank.perk_ids.has(perk_id):
		push_error("перк %s не попал в танк" % perk_id)
		return
	var perk := Perks.get_perk(perk_id)
	if perk.has("active"):
		if tank.ability_id != String(perk["active"]):
			push_error("способность %s не встала в слот" % perk_id)
		return
	var base := Perks.base_modifiers()
	var changed := false
	for key in perk.get("mods", {}).keys():
		if not is_equal_approx(float(tank.mods[key]), float(base[key])):
			changed = true
	if not changed:
		push_error("перк %s не изменил ни одного модификатора" % perk_id)

func _dismiss_perks() -> void:
	var guard := 0
	while game.state == "perk" and guard < 40:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

# ---------------------------------------------------------------------- отчёт
func _avg(rows: Array, key: String) -> float:
	var s := 0.0
	for r in rows:
		s += float(r[key])
	return s / float(maxi(1, rows.size()))

func _sd(rows: Array, key: String) -> float:
	var m := _avg(rows, key)
	var s := 0.0
	for r in rows:
		s += pow(float(r[key]) - m, 2.0)
	return sqrt(s / float(maxi(1, rows.size())))

## Парная разница: перк минус контроль на ТОМ ЖЕ старте. Разброс между
## картами куда больше разницы от перка, и без спаривания она в нём тонет.
func _paired(id: String, key: String) -> Array:
	var base: Array = results[""]
	var rows: Array = results[id]
	var out := []
	for i in mini(base.size(), rows.size()):
		out.append(float(rows[i][key]) - float(base[i][key]))
	return out

func _mean(v: Array) -> float:
	var s := 0.0
	for x in v:
		s += float(x)
	return s / float(maxi(1, v.size()))

func _sem(v: Array) -> float:
	if v.size() < 2:
		return 0.0
	var m := _mean(v)
	var s := 0.0
	for x in v:
		s += pow(float(x) - m, 2.0)
	return sqrt(s / float(v.size() - 1)) / sqrt(float(v.size()))

func _report() -> void:
	var base: Array = results[""]
	var bk := _avg(base, "kills")
	var bd := _avg(base, "dealt")
	var bt := _avg(base, "taken")
	var bw := _avg(base, "walls")

	print("")
	print("=== ЗАМЕР ПЕРКОВ: %d стартов по %d тиков ===" % [seeds, TICKS])
	print("контроль: убийств/мин %.2f, урона/мин %.0f, получено/мин %.0f, построек/мин %.1f"
		% [bk, bd, bt, bw])
	print("")
	print("%-18s %14s %14s %14s %8s %7s" % [
		"перк", "убийств", "урон", "получено", "постр", "оценка"])

	var scored := []
	for id in ids:
		if id == "":
			continue
		var dk := _paired(id, "kills")
		var dd := _paired(id, "dealt")
		var dt := _paired(id, "taken")
		var dw := _paired(id, "walls")
		# Оценка в долях от контроля: разные величины иначе не складываются.
		var score := 0.0
		score += _mean(dk) / maxf(0.01, bk) * 50.0
		score += _mean(dd) / maxf(1.0, bd) * 30.0
		score -= _mean(dt) / maxf(1.0, bt) * 20.0
		scored.append({
			"id": id, "score": score,
			"k": _mean(dk), "ks": _sem(dk),
			"d": _mean(dd), "ds": _sem(dd),
			"t": _mean(dt), "ts": _sem(dt),
			"w": _mean(dw),
		})

	scored.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	for e in scored:
		print("%-18s %+7.2f±%-5.2f %+7.0f±%-5.0f %+7.0f±%-5.0f %+7.1f %7.1f" % [
			e["id"], e["k"], e["ks"], e["d"], e["ds"], e["t"], e["ts"],
			e["w"], e["score"]])
	print("")
	print("± — стандартная ошибка среднего по стартам. Если разница меньше")
	print("своей ошибки, перк от контроля неотличим и в тир-лист идёт по низу.")
