# ============================================================================
# shot.gd — снимает экраны игры в user://shots/ для визуальной проверки.
#
# Запуск:
#   godot --path godot --resolution 1280x720 res://tests/shot.tscn
#
# В отличие от smoke.tscn здесь ничего не симулируется вручную: игра просто
# живёт своей жизнью несколько кадров, и кадр сохраняется в PNG.
# ============================================================================
extends Node

var game: Node

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	print("папка снимков: %s" % ProjectSettings.globalize_path("user://shots"))

	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(45)
	await _save("menu")

	# Меню с раскрытой панелью настроек.
	game.ui._menu_settings_panel.visible = true
	game.ui._refresh_mode_button()
	await _frames(12)
	await _save("menu_settings")

	# Гараж и галерея перков.
	game.ui.open_garage()
	await _frames(12)
	await _save("garage")
	game.ui.close_garage()

	game.ui.open_settings()
	await _frames(12)
	await _save("settings")
	game.ui.close_settings()

	game.ui.open_net()
	await _frames(10)
	await _save("net_lobby")
	game.ui.close_net()

	game.ui.open_gallery()
	await _frames(12)
	await _save("gallery")
	game.ui.close_gallery()

	# Постобработка: один и тот же бой без эффектов и с эффектами.
	Sets.fx_quality = PostFx.OFF
	await _match_shot("defense", "single", "fx_off")
	Sets.fx_quality = PostFx.HIGH
	await _match_shot("defense", "single", "fx_high")

	# Горящие остовы: подрываем ближайшие к камере танки и снимаем кадр,
	# пока обломки ещё горят.
	await _wreck_shot()

	# Прочность построек: рядом с камерой оставляем здания в разной стадии
	# разрушения и разносим несколько до обломков.
	await _damage_shot()

	# Витрина корпусов и камуфляжей: их не увидеть в обычном бою рядом.
	await _lineup_shot("chassis")
	await _lineup_shot("camo")

	# Активные способности: индикатор в HUD и карточка выбора перка.
	await _ability_shot()

	# Река и мосты: камеру ставим на переправу, иначе её можно не увидеть.
	await _bridge_shot()

	# Бой: обычный экран и разделённый.
	await _match_shot("ffa", "single", "ingame_ffa")
	await _match_shot("ctf", "single", "ingame_ctf")
	await _match_shot("ffa", "hotseat", "ingame_hotseat")
	await _match_shot("defense", "single", "ingame_defense")

	print("готово")
	get_tree().quit()

func _match_shot(mode: String, game_type: String, name: String) -> void:
	game.ui.settings["mode"] = mode
	game.ui.settings["game_type"] = game_type
	game.ui.settings["level"] = 1
	game.start_match()
	# Стартовый выбор перка закрываем — нужен вид самого боя.
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	await _frames(90)
	await _save(name)
	# Стоимость кадра: важнее всего на слабых видеокартах, ради них
	# и сделан переключатель качества.
	var t0 := Time.get_ticks_usec()
	await _frames(60)
	print("    кадр: %.2f мс (эффекты %d)"
		% [float(Time.get_ticks_usec() - t0) / 1000.0 / 60.0, Sets.fx_quality])
	game.to_menu()
	await _frames(5)

## Витрина: все силуэты корпусов или все камуфляжи в один ряд.
##
## В бою рядом их не поставить — типы врагов выпадают вразнобой, а камуфляж
## у игрока всегда один. Поэтому танки создаются вручную и расставляются
## на расчищенной площадке перед камерой.
func _lineup_shot(kind: String) -> void:
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	await _frames(6)

	var world = game.world
	var p = game.players[0]
	var map = world.map
	# Ставим витрину в середине карты и расчищаем под неё асфальт.
	var cx: float = map.width * 0.5
	var cy: float = map.height * 0.5
	var r0: int = map.row_at(cy) - 4
	var c0: int = map.col_at(cx) - 9
	for r in range(r0, r0 + 8):
		for c in range(c0, c0 + 18):
			map.set_tile(r, c, Cfg.T_ROAD)

	# Остальные танки убираем, чтобы не лезли в кадр.
	world.tanks = [p.tank]
	world.bullets.clear()
	p.tank.x = cx
	p.tank.y = cy + 90.0
	p.tank.alive = true

	var items := []
	if kind == "chassis":
		items = ["grunt", "scout", "heavy", "sniper", "mortar", "boss"]
	else:
		for c in Cosmetics.CAMOS:
			items.append(String(c["id"]))

	var step := 92.0
	var x0: float = cx - step * (float(items.size()) - 1.0) * 0.5
	for i in items.size():
		var t: Tank
		if kind == "chassis":
			var type: Dictionary = EnemyTypes.get_type(String(items[i]))
			t = Tank.new({
				"x": x0 + step * float(i), "y": cy - 20.0, "team": "show",
				"name": String(type["name"]), "owner": null, "max_hp": 100.0,
				"speed": 1.0, "fire_rate": 20, "color_key": String(type["color_key"]),
				"chassis": String(type.get("chassis", "standard")),
			})
		else:
			t = Tank.new({
				"x": x0 + step * float(i), "y": cy - 20.0, "team": "show",
				"name": Cosmetics.get_cosmetic("camo", String(items[i]))["name"],
				"owner": null, "max_hp": 100.0, "speed": 1.0, "fire_rate": 20,
				"color_key": "p1", "chassis": "standard",
			})
			t.cosmetics = {"camo": String(items[i]), "hull": "none",
				"track": "none", "turret": "none"}
		# Танки смотрят вправо: так виден ствол целиком, а полоска HP
		# над корпусом его не перекрывает.
		t.body_angle = 0.0
		t.angle = 0.0
		t.turret_angle = 0.0
		t.spawn_protect = 0
		world.tanks.append(t)

	p.update_camera()
	p.camera.y = cy
	await _frames(8)
	await _save("lineup_" + kind)
	game.to_menu()
	await _frames(5)

## Снимки активной способности: индикатор в HUD во время действия и экран
## выбора перка с активными карточками.
func _ability_shot() -> void:
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	await _frames(10)

	var p = game.players[0]
	p.perk_ids.append("nitro")
	p.tank.recompute()
	p.tank.use_ability(game.world)
	await _frames(6)
	await _save("ability_hud")

	# Ищем расклад, где в тройке есть активный перк: подменять игроку весь
	# набор нельзя — строка «экипировано» раздувается и ломает вёрстку,
	# то есть снимок показал бы не экран игры, а артефакт теста.
	var found := false
	for attempt in 80:
		game.ui.show_perk_select(p, 0, Rng.new(attempt))
		for id in game.ui.last_perk_choices:
			if Perks.is_active_perk(String(id)):
				found = true
				break
		if found:
			print("  выбор перка: расклад %d, карточки %s"
				% [attempt, str(game.ui.last_perk_choices)])
			break
	if not found:
		print("  ОШИБКА: активный перк не выпал ни в одном раскладе")
	await _frames(12)
	await _save("perk_select")
	game.ui.hide_perk_select()

	game.to_menu()
	await _frames(5)

## Снимок переправы: игрок телепортируется на ближайший к центру мост.
func _bridge_shot() -> void:
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	await _frames(10)

	var map = game.world.map
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for r in map.rows:
		for c in map.cols:
			if map.get_tile(r, c) != Cfg.T_BRIDGE:
				continue
			var d: int = absi(r - map.rows / 2) + absi(c - map.cols / 2)
			if d < best_d:
				best_d = d
				best = Vector2i(r, c)
	if best.x < 0:
		print("  мостов на карте нет — снимок пропущен")
		game.to_menu()
		await _frames(5)
		return
	print("  мост: строка %d, колонка %d" % [best.x, best.y])

	var p = game.players[0]
	p.tank.x = best.y * Cfg.TILE + Cfg.TILE * 0.5
	p.tank.y = best.x * Cfg.TILE + Cfg.TILE * 0.5
	p.tank.vx = 0.0
	p.tank.vy = 0.0
	p.update_camera()
	await _frames(20)
	await _save("bridge")
	game.to_menu()
	await _frames(5)

## Снимок с повреждёнными и разрушенными постройками.
func _damage_shot() -> void:
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	await _frames(20)

	var world = game.world
	var cam = game.players[0].camera
	var map = world.map
	var cr: int = map.row_at(cam.y)
	var cc: int = map.col_at(cam.x)

	# Собираем постройки вокруг камеры и портим их по нарастающей:
	# часть остаётся с трещинами, часть разносим в обломки.
	var found := []
	for dr in range(-9, 10):
		for dc in range(-16, 17):
			if map.get_tile(cr + dr, cc + dc) == Cfg.T_BRICK:
				found.append(Vector2i(cr + dr, cc + dc))
	var stages := [0.35, 0.6, 0.85, 1.4]
	for i in found.size():
		var t: Vector2i = found[i]
		var mat := Materials.at(t.x, t.y)
		var k: float = stages[i % stages.size()]
		world.hit_building(t.x, t.y, float(mat["hp"]) * k, "blast",
			t.y * Cfg.TILE + 16.0, t.x * Cfg.TILE + 16.0, null)

	await _frames(12)
	await _save("damage")
	game.to_menu()
	await _frames(5)

## Снимок с догорающими остовами.
func _wreck_shot() -> void:
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	await _frames(30)

	# Ближайшие боты переставляются вплотную к камере и подрываются:
	# иначе остовы оказываются за кадром и снимок бесполезен.
	var world = game.world
	var cam = game.players[0].camera
	var near := []
	for t in world.tanks:
		if t.is_bot and t.alive:
			near.append([Vector2(t.x - cam.x, t.y - cam.y).length(), t])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var spots := [Vector2(-150, -60), Vector2(120, 90), Vector2(-40, 130)]
	for i in mini(3, near.size()):
		var t = near[i][1]
		t.x = cam.x + spots[i].x
		t.y = cam.y + spots[i].y
		t.spawn_protect = 0
		world.deal_damage(t, 9999.0, null, "bullet")

	await _frames(25)
	await _save("wrecks")
	game.to_menu()
	await _frames(5)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _save(name: String) -> void:
	# Ждём обычных кадров и берём последний отрисованный: продолжать корутину
	# внутри frame_post_draw нельзя — следующий await из неё уже не проснётся.
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots/%s.png" % name)
	print("  снимок: %s.png (%dx%d)" % [name, img.get_width(), img.get_height()])
