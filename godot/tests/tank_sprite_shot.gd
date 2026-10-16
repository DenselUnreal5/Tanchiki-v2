extends Node

const OUT := "user://tank_sprites/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var level: Dictionary = LevelGen.generate(1, "ffa", 777, "city")
	var ps := PlayerState.new(0, "P1", "p2", null)
	var world := World.new({
		"map": level["map"], "level": level, "mode": "ffa",
		"difficulty": "medium", "players": [ps], "puppet": true,
	})
	world.weather = WeatherSystem.new(0, {"condition": "clear", "phase": 0.25})
	var m := GameMap.new(40, 30)
	m.fill(Cfg.T_EMPTY)
	world.map = m
	ps.map = m
	world.tanks.clear()
	var x0 := 120.0
	var col := 0
	for cls in ["standard", "grunt", "scout", "heavy", "sniper", "mortar"]:
		var t := _tank(world, "player", "p2", String(TankClasses.get_entry(cls)["chassis"]), x0 + col * 70.0, 120.0)
		t.class_id = cls
		col += 1
	col = 0
	for id in ["grunt", "scout", "heavy", "sniper", "mortar", "pyro", "tesla", "boss"]:
		var t := world._spawn_bot("enemy", "enemy", id)
		t.x = x0 + col * 70.0
		t.y = 210.0
		t.body_angle = PI / 2.0
		t.turret_angle = PI / 2.0 + 0.4
		t.spawn_protect = 0
		col += 1
	col = 0
	for cn in ["ice", "acid", "fire", "shock"]:
		var t := _tank(world, "player", "p1", "standard", x0 + col * 70.0, 300.0)
		t.cannon_id = cn
		col += 1
	var skinned := _tank(world, "player", "p13", "standard", x0 + col * 70.0, 300.0)
	skinned.cosmetics = {"skin": "cyberpunk"}
	col += 1
	var camo := _tank(world, "player", "p1", "standard", x0 + col * 70.0, 300.0)
	camo.cosmetics = {"camo": "digital", "hull": "star", "turret": "gold"}
	col += 1
	var sil := _tank(world, "player", "silhouette", "standard", x0 + col * 70.0, 300.0)
	col = 0
	for st in ["burn", "freeze", "stun", "acid", "hurt"]:
		var t := _tank(world, "player", "p10", "standard", x0 + col * 70.0, 390.0)
		t.body_angle = 0.6 * col
		t.turret_angle = -0.8 * col
		match st:
			"burn": t.burn_ticks = 100; t.burn_stacks = 3
			"freeze": t.freeze_ticks = 100
			"stun": t.stun_ticks = 40
			"acid": t.acid_stacks = 4
			"hurt": t.hp = t.max_hp * 0.1; t.heat = 0.9
		col += 1
	for scale_v in [1.0, 2.0]:
		var vp := SubViewport.new()
		vp.size = Vector2i(int(720 * scale_v), int(450 * scale_v))
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var bg := ColorRect.new()
		bg.color = Color("#4a6b3a")
		bg.size = Vector2(vp.size)
		vp.add_child(bg)
		var view := WorldView.new()
		view.world = world
		view.player = ps
		view.scale = Vector2(scale_v, scale_v)
		vp.add_child(view)
		ps.viewport = Rect2(0, 0, 720, 450)
		ps.camera = Vector2(360, 225)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(OUT + "tanks_x%d.png" % int(scale_v))
		print("OUT=", ProjectSettings.globalize_path(OUT + "tanks_x%d.png" % int(scale_v)))
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for i in 8:
		await get_tree().process_frame
	for step in [["menu", ""], ["cosmetics", ""], ["bestiary", "pyro"]]:
		match String(step[0]):
			"cosmetics": game.ui.open_cosmetics()
			"bestiary": game.ui.open_bestiary(String(step[1]))
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT + "ui_%s.png" % step[0])
		print("OUT=", ProjectSettings.globalize_path(OUT + "ui_%s.png" % step[0]))
	get_tree().quit(0)

func _tank(world: World, team: String, color: String, chassis: String, x: float, y: float) -> Tank:
	var t := Tank.new({
		"x": x, "y": y, "team": team, "name": "", "color_key": color, "chassis": chassis,
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30,
	})
	t.spawn_protect = 0
	t.body_angle = -PI / 2.0
	t.turret_angle = -PI / 2.0 + 0.5
	world.tanks.append(t)
	return t
