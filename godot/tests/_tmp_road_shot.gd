extends Node

func _ready() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(10)
	game.ui.settings["location"] = "city"
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = -1
	game.start_match()
	var guard := 0
	while game.state == game.S_PERK and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	await _frames(20)

	var world = game.world
	var plan: Dictionary = world.level["plan"]
	var p = game.players[0]

	var found_v := false
	for st in plan["v"]:
		if int(st["w"]) >= 2:
			var r := world.map.rows / 2
			var c := int(st["pos"]) + MapPlan.wave_offset(st, r) + int(st["w"]) / 2
			p.tank.x = float(c) * Cfg.TILE + Cfg.TILE * 0.5
			p.tank.y = float(r) * Cfg.TILE + Cfg.TILE * 0.5
			p.update_camera()
			await _frames(10)
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://shots/wide_v.png")
			found_v = true
			break
	print("wide_v найден: ", found_v)

	var found_h := false
	for st in plan["h"]:
		if int(st["w"]) >= 2:
			var c2 := world.map.cols / 2
			var r2 := int(st["pos"]) + MapPlan.wave_offset(st, c2) + int(st["w"]) / 2
			p.tank.x = float(c2) * Cfg.TILE + Cfg.TILE * 0.5
			p.tank.y = float(r2) * Cfg.TILE + Cfg.TILE * 0.5
			p.update_camera()
			await _frames(10)
			var img2 := get_viewport().get_texture().get_image()
			img2.save_png("user://shots/wide_h.png")
			found_h = true
			break
	print("wide_h найден: ", found_h)

	if not plan["v"].is_empty() and not plan["h"].is_empty():
		var jr := int(plan["h"][0]["pos"])
		var jc := int(plan["v"][0]["pos"])
		p.tank.x = float(jc) * Cfg.TILE + Cfg.TILE * 0.5
		p.tank.y = float(jr) * Cfg.TILE + Cfg.TILE * 0.5
		p.update_camera()
		await _frames(10)
		var img3 := get_viewport().get_texture().get_image()
		img3.save_png("user://shots/junction.png")

	print("готово")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
