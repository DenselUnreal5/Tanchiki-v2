# ============================================================================
# weather_check.gd — проверка, что погода влияет на игру, а не только на вид.
#
# Погоду легко нарисовать и забыть подключить: снег сыплется, а танк едет
# как по асфальту. Здесь каждое условие ставится принудительно, и сверяются
# те два числа, ради которых погода вообще существует в правилах —
# дальность зрения ботов и сцепление с грунтом.
# ============================================================================
extends Node

var game: Node
var failures := 0

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# ---- условия ---------------------------------------------------------
	print("условие      зрение ботов   сцепление")
	var base_sight := 0.0
	for id in ["clear", "rain", "fog", "snow", "storm"]:
		_start(id, "day")
		var w = game.world.weather
		var sight: float = BotBrain.sight_range(game.world)
		if id == "clear":
			base_sight = sight
		print("  %-10s %6.0f px      %.2f" % [id, sight, w.traction])
		_check(w.condition == id, "условие «%s» закреплено" % id)

	_start("fog", "day")
	_check(BotBrain.sight_range(game.world) < base_sight * 0.6,
		"в тумане боты видят меньше половины обычного")
	_start("snow", "day")
	_check(game.world.weather.traction < 0.85, "по снегу сцепление хуже")

	# ---- время суток -----------------------------------------------------
	print("время        свет   зрение ботов")
	for tod in ["day", "dusk", "night", "midnight"]:
		_start("clear", tod)
		var w = game.world.weather
		print("  %-10s %.2f   %6.0f px" % [tod, w.light, BotBrain.sight_range(game.world)])

	_start("clear", "day")
	var day_sight := BotBrain.sight_range(game.world)
	_start("clear", "midnight")
	var night_sight := BotBrain.sight_range(game.world)
	_check(night_sight < day_sight, "ночью боты видят меньше, чем днём (%.0f -> %.0f)"
		% [day_sight, night_sight])

	# Время должно стоять: выбранная ночь не превращается в рассвет.
	var w2 = game.world.weather
	var light_before: float = w2.light
	for i in 600:
		w2.update()
	_check(absf(w2.light - light_before) < 0.001, "выбранное время суток не уплывает")

	# ---- сцепление доходит до танка --------------------------------------
	_start("clear", "day")
	var tank: Tank = game.players[0].tank
	tank._update_surface(game.world)
	var dry := tank.surface_speed
	_start("snow", "day")
	tank = game.players[0].tank
	tank._update_surface(game.world)
	var slippery := tank.surface_speed
	_check(slippery < dry, "снег доходит до хода танка: %.2f -> %.2f" % [dry, slippery])

	# ---- гроза: разряд бьёт ровно на 90 ----------------------------------
	_start("storm", "night")
	# Бьём бота: у игрока броня из гаража режет любой входящий урон, и на
	# нём «ровно 90» не проверить. Первая версия теста этого не учла и
	# показала 61 — цифра верная, но проверяла она не то.
	var victim: Tank = null
	for t in game.world.tanks:
		if t.owner == null and t.perk_ids.is_empty():
			victim = t
			break
	if victim == null:
		_check(false, "бот для проверки молнии не нашёлся")
		return
	# Запас поднимаем выше урона: у бота его 80, и удар просто убивал —
	# разница по здоровью упиралась в ноль и ничего не доказывала.
	victim.max_hp = 300.0
	victim.hp = victim.max_hp
	victim.spawn_protect = 0
	var hp_before := victim.hp
	game.world.strike_lightning(victim.x + 8.0, victim.y + 8.0)
	_check(absf(hp_before - victim.hp - Cfg.LIGHTNING_DAMAGE) < 0.001,
		"прямое попадание молнии: %.0f -> %.0f (ровно %.0f)"
			% [hp_before, victim.hp, Cfg.LIGHTNING_DAMAGE])
	_check(game.world.scorches.size() > 0, "на земле остался след от удара")
	_check(game.world.bolts.size() > 0, "разряд появился в кадре")

	# Мимо — значит мимо: за радиусом поражения урона быть не должно.
	var hp2 := victim.hp
	game.world.strike_lightning(victim.x + Cfg.LIGHTNING_RADIUS * 3.0, victim.y)
	_check(absf(victim.hp - hp2) < 0.001, "удар в стороне не задевает танк")

	# ---- гроза глушит выстрел ------------------------------------------
	# Бот слышит чужой выстрел ближе в непогоду: та же дальность идёт и в
	# отметку на миникарте, поэтому проверяем именно её.
	print("условие      слышимость выстрела")
	game.ui.settings["location"] = "auto"
	_start("clear", "day")
	var clear_reach := _shot_reach()
	_start("storm", "day")
	var storm_reach := _shot_reach()
	print("  ясно       %6.0f м" % (clear_reach / 8.0))
	print("  гроза      %6.0f м" % (storm_reach / 8.0))
	_check(absf(clear_reach - Cfg.BOT_HEAR_RANGE) < 0.001,
		"в ясную погоду выстрел слышно на полную дальность (%.0f)" % Cfg.BOT_HEAR_RANGE)
	_check(storm_reach < clear_reach * 0.75, "гроза глушит выстрел: слышно заметно ближе")

	# ---- гроза валит деревья ------------------------------------------
	# Джунгли: карта, где деревьев вдоволь. Счётчик w._trees_felled считает
	# именно повал ветром — деревья мнут ещё и танки, по общему числу на
	# карте одно от другого не отделить.
	game.ui.settings["location"] = "jungle"
	_start("storm", "day")
	var w3 = game.world
	var trees0 := _count_trees(w3.map)
	for i in Cfg.STORM_FELL_EVERY * 3:
		if w3.finished_flag:
			break
		w3.step()
	print("джунгли, гроза: деревьев на карте %d, повалено ветром %d" % [trees0, w3._trees_felled])
	_check(w3._trees_felled > 0, "за грозу ветер повалил хотя бы одно дерево")

	# И обратное: без грозы счётчик повала не растёт (защита от кода,
	# который «валит» всегда, а не только в непогоду).
	_start("clear", "day")
	var w4 = game.world
	for i in Cfg.STORM_FELL_EVERY * 3:
		if w4.finished_flag:
			break
		w4.step()
	_check(w4._trees_felled == 0, "в ясную погоду ветер деревья не валит (счётчик %d)"
		% w4._trees_felled)

	# ---- потолок и воспроизводимость --------------------------------
	# Изолированно: только _update_treefall, без хода танков (они тоже мнут
	# деревья и своей случайностью забили бы проверку).
	_start("storm", "day")
	var sum_a := _fell_only(game.world)
	var capped := game.world._trees_felled
	_start("storm", "day")
	var sum_b := _fell_only(game.world)
	_check(capped == Cfg.STORM_FELL_MAX, "повал упирается в потолок %d за партию (получилось %d)"
		% [Cfg.STORM_FELL_MAX, capped])
	_check(sum_a == sum_b, "повал деревьев воспроизводится от seed: %08x == %08x"
		% [sum_a, sum_b])

	game.ui.settings["location"] = "auto"
	print("=== ПРОВЕРКА ПОГОДЫ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Дальность, с которой слышен выстрел бота без перков в текущей погоде.
func _shot_reach() -> float:
	var shooter: Tank = null
	for t in game.world.tanks:
		if t.owner == null and t.perk_ids.is_empty():
			shooter = t
			break
	if shooter == null:
		_check(false, "бот для проверки слышимости не нашёлся")
		return 0.0
	game.world.shot_pings.clear()
	game.world.notify_shot(shooter)
	if game.world.shot_pings.is_empty():
		_check(false, "выстрел не оставил отметки")
		return 0.0
	return float(game.world.shot_pings[-1]["reach"])

func _count_trees(map: GameMap) -> int:
	var n := 0
	for r in map.rows:
		for c in map.cols:
			if map.get_tile(r, c) == Cfg.T_TREE:
				n += 1
	return n

## Прогоняет только повал деревьев на свежих счётчиках и возвращает отпечаток
## карты. Ход танков не трогается — иначе разброс их случайности перекрыл бы
## то, что проверяется.
func _fell_only(w) -> int:
	w._trees_felled = 0
	w._tree_tiles = PackedInt32Array()
	w._tree_cache_tick = -100000
	w._storm_rng = Rng.new((int(w.level["seed"]) ^ 0x57012) & 0xFFFFFFFF)
	for i in Cfg.STORM_FELL_MAX + 20:
		w.tick = i * Cfg.STORM_FELL_EVERY
		w._update_treefall()
	return w.map.checksum()

func _start(weather: String, daytime: String) -> void:
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.ui.settings["weather"] = weather
	game.ui.settings["daytime"] = daytime
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
