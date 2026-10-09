extends Node

var game: Node
var failures := 0
var clips: Array = []

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for i in 30:
		await get_tree().process_frame
	_check_recorder()
	await _check_match_flow()
	print("=== ПРОВЕРКА КИЛЛКАМА ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _make_world(killcam: bool) -> World:
	var player := PlayerState.new(0, "Тест", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, "ffa", 5151, "city")
	return World.new({
		"map": level["map"], "level": level, "mode": "ffa", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": 5151, "killcam": killcam,
	})

func _check_recorder() -> void:
	var off := _make_world(false)
	_check(off.killcam == null, "без флага рекордера нет")
	off.dispose()

	var world := _make_world(true)
	_check(world.killcam != null, "с флагом рекордер создан")
	world.killcam_ready.connect(func(clip: Dictionary): clips.append(clip))
	for i in 400:
		world.step()
	var frames: Array = world.killcam.frames
	_check(frames.size() == Cfg.KILLCAM_FRAMES, "буфер держит %d кадров (%d)" % [Cfg.KILLCAM_FRAMES, frames.size()])
	var span := int(frames[frames.size() - 1]["tick"]) - int(frames[0]["tick"])
	_check(span >= 4 * Cfg.TICK_HZ, "буфер охватывает не меньше 4 секунд (%d тиков)" % span)

	var ptank: Tank = world.players[0].tank
	var killer: Tank = null
	for t in world.tanks:
		if t != ptank and t.alive:
			killer = t
			break
	ptank.spawn_protect = 0
	var death_x := ptank.x
	var death_y := ptank.y
	world.deal_damage(ptank, 99999.0, killer, "bullet")
	_check(clips.size() == 1, "смерть игрока выпускает один клип (%d)" % clips.size())
	if clips.is_empty():
		world.dispose()
		return
	var clip: Dictionary = clips[0]
	_check(int(clip["victim"]) == ptank.id and int(clip["killer"]) == killer.id, "клип знает жертву и убийцу")
	_check(String(clip["killer_name"]) == killer.name and String(clip["source"]) == "bullet", "клип хранит имя и источник урона")
	var last: Dictionary = (clip["frames"] as Array).back()
	var at_death := KillCam.tank_at(last, ptank.id)
	_check(not at_death.is_empty() and absf(float(at_death["x"]) - death_x) < 1.0 and absf(float(at_death["y"]) - death_y) < 1.0,
		"последний кадр содержит жертву на месте гибели")
	_check(not KillCam.tank_at(last, killer.id).is_empty(), "последний кадр содержит убийцу")

	clips.clear()
	world.deal_damage(killer, 99999.0, ptank, "bullet")
	_check(clips.is_empty(), "гибель бота клип не создаёт")
	world.dispose()

func _check_match_flow() -> void:
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	Sets.killcam = true
	game.start_match()
	for i in 6:
		await get_tree().process_frame
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")
	_check(game.world.killcam != null, "обычный матч включает рекордер")
	for i in 300:
		game.world.step()
	var ptank: Tank = game.players[0].tank
	ptank.spawn_protect = 0
	var killer: Tank = null
	for t in game.world.tanks:
		if t != ptank and t.alive:
			killer = t
			break
	game.world.deal_damage(ptank, 99999.0, killer, "bullet")
	await get_tree().process_frame
	var view: KillCamView = game.hud._killcam
	_check(view != null and view.running and view.visible, "повтор запущен в боевой панели")
	var frames_total := view.frame_count()
	_check(frames_total >= 2 and frames_total <= int(Cfg.KILLCAM_PLAY_SECONDS * 30.0) + 1,
		"проигрывается не больше %.0f секунд (%d кадров)" % [Cfg.KILLCAM_PLAY_SECONDS, frames_total])
	var screen: Vector2 = game.get_viewport().get_visible_rect().size
	_check(Rect2(Vector2.ZERO, screen).encloses(view.get_global_rect()), "окно повтора целиком на экране")
	var first_index := view.current_index()
	for i in 30:
		await get_tree().process_frame
	_check(view.running and view.current_index() > first_index, "кадры идут вперёд (%d -> %d)" % [first_index, view.current_index()])
	var guard_t := 0.0
	while view.running and guard_t < Cfg.KILLCAM_PLAY_SECONDS + Cfg.KILLCAM_HOLD_SECONDS + 2.0:
		await get_tree().process_frame
		guard_t += get_process_delta_time()
	_check(not view.running and not view.visible, "повтор сам закрывается по окончании")

	Sets.killcam = false
	game.start_match()
	for i in 4:
		await get_tree().process_frame
	_check(game.world.killcam == null, "при выключенной настройке рекордера нет")
	Sets.killcam = true

func _check(ok: bool, what: String) -> bool:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
	return ok
