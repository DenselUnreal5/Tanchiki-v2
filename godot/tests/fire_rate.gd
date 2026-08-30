# ============================================================================
# fire_rate.gd — замер темпа стрельбы игрока.
#
# Автопилот в дымовом тесте стреляет по цели, а не «зажимает гашетку»,
# поэтому перегрев у него почти не срабатывает и потолок темпа им не
# измерить. Здесь танк жмёт на спуск каждый тик — это и есть тот случай,
# ради которого перегрев вводился.
# ============================================================================
extends Node

const SECONDS := 60

func _ready() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

	var world = game.world
	var tank: Tank = game.players[0].tank
	# Танк стоит на месте и стреляет в одну сторону: замеряется темп,
	# а не умение попадать.
	var ticks := SECONDS * 60
	for i in ticks:
		tank.hp = tank.max_hp        # не даём себя убить: считаем только темп
		tank.shoot(world)
		world.step()

	var rate := float(tank.shots_fired) / float(SECONDS)
	print("непрерывная стрельба %d с: выстрелов %d, перегревов %d"
		% [SECONDS, tank.shots_fired, tank.overheats])
	print("устойчивый темп: %.2f выстрела/с (бот на средней сложности — %.2f)"
		% [rate, 60.0 / float(Cfg.DIFFICULTY["medium"]["enemy_fire_rate"])])
	print("предел без перегрева был бы %.2f/с" % (60.0 / float(Cfg.PLAYER_FIRE_RATE)))
	get_tree().quit()
