# Одноразовая визуальная проверка: анимация воды/зыбучего песка всё ещё
# работает при развязанном от таймера перезапекании, и полный ребейк
# по-прежнему срабатывает на реальное изменение тайла (разрушение).
extends Node

func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.ui.settings["location"] = "dust"
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

	var world = game.world
	var map: GameMap = world.map
	var water_spot := Vector2i(-1, -1)
	for r in map.rows:
		for c in map.cols:
			if map.get_tile(r, c) == Cfg.T_WATER:
				water_spot = Vector2i(r, c)
				break
		if water_spot.x >= 0:
			break
	if water_spot.x < 0:
		print("вода на карте не найдена (сид без оазиса), выходим")
		get_tree().quit(1)
		return

	game.players[0].camera = Vector2(water_spot.y * Cfg.TILE, water_spot.x * Cfg.TILE)
	var vp: SubViewport = game._views[0]["viewport"]

	await get_tree().process_frame
	await get_tree().process_frame
	var img1 := vp.get_texture().get_image()
	img1.save_png("user://water_t0.png")

	for i in 90:
		world.step()
	await get_tree().process_frame
	await get_tree().process_frame
	var img2 := vp.get_texture().get_image()
	img2.save_png("user://water_t90.png")

	# Ломаем тайл рядом с камерой и проверяем, что полный ребейк подхватил
	# изменение (map.version реально бампается set_tile).
	var br := water_spot.x
	var bc := water_spot.y + 3
	if map.get_tile(br, bc) != Cfg.T_BRICK:
		for rr in range(maxi(1, br - 2), mini(map.rows - 2, br + 2)):
			for cc in range(maxi(1, bc - 2), mini(map.cols - 2, bc + 2)):
				if map.get_tile(rr, cc) == Cfg.T_BRICK:
					br = rr
					bc = cc
	var before_tile := map.get_tile(br, bc)
	map.set_tile(br, bc, Cfg.T_EMPTY)
	game.players[0].camera = Vector2(bc * Cfg.TILE, br * Cfg.TILE)
	await get_tree().process_frame
	await get_tree().process_frame
	var img3 := vp.get_texture().get_image()
	img3.save_png("user://after_destroy.png")

	print("тайл до/после разрушения: %d -> %d (изменился: %s)" % [
		before_tile, map.get_tile(br, bc), before_tile != map.get_tile(br, bc)])
	print("готово: ", ProjectSettings.globalize_path("user://"))
	get_tree().quit(0)
