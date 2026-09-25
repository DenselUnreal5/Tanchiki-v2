extends Node

const S_MENU := "menu"
const S_PLAYING := "playing"
const S_PAUSED := "paused"
const S_PERK := "perk"
const S_GAMEOVER := "gameover"

var state := S_MENU

var world: World = null
var players: Array = []

var accumulator := 0.0
var remote_players: Array = []
var _snap_tick := 0
var _sum_tick := 0
var _predict_buf: Array = []
var _last_reconciled_tick := -1
var net_desyncs := 0
var net_sums := 0
var net_last_mine := 0
var net_last_theirs := 0
var net_stale := false
var perk_player = null

var ui_rng := Rng.new(int(Time.get_ticks_usec()) & 0xFFFFFFFF)
var match_damage := 0.0

var floaters: Array = []

var _root: Control
var _loading: LoadingScreen = null
var _views_root: Control
var _views: Array = []
var _tile_cache: TileCache = null
var hud: Hud
var ui: UiRoot

func _ready() -> void:
	_sync_steam.call_deferred()

	get_window().min_size = Vector2i(1024, 640)

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_views_root = Control.new()
	_views_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_views_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_views_root)

	hud = Hud.new()
	_root.add_child(hud)
	hud.hide_hud()

	ui = UiRoot.new()
	_root.add_child(ui)

	_bind_ui()
	_bind_profile_events()
	_bind_net()

	var cli := Cli.parse()
	if bool(cli["server"]):
		_boot_dedicated_server(cli)
		return

	get_viewport().size_changed.connect(_on_resize)
	_on_resize()

	if get_tree().current_scene == self:
		var splash := Splash.new()
		_root.add_child(splash)
		await get_tree().create_timer(1.0).timeout
		splash.queue_free()

	ui.show_menu()
	Mus.play_menu()
	if String(cli["connect_host"]) != "":
		ui.open_net()
		Net.join_game(String(cli["connect_host"]), int(cli["connect_port"]))

func _boot_dedicated_server(cli: Dictionary) -> void:
	var port := int(cli["port"])
	var target := int(cli["players"])
	if String(cli["mode"]) != "":
		ui.settings["mode"] = String(cli["mode"])
	if String(cli["difficulty"]) != "":
		ui.settings["difficulty"] = String(cli["difficulty"])
	if int(cli["level"]) != Cli.UNSET_LEVEL:
		ui.settings["level"] = int(cli["level"])
	if String(cli["weather"]) != "":
		ui.settings["weather"] = String(cli["weather"])
	if String(cli["daytime"]) != "":
		ui.settings["daytime"] = String(cli["daytime"])
	if String(cli["location"]) != "":
		ui.settings["location"] = String(cli["location"])

	Net.my_name = I18n.t("net.dedicated.name", {}, "Выделенный сервер")

	if not Net.host_dedicated(port, target):
		push_error("[server] не удалось открыть порт %d" % port)
		get_tree().quit(1)
		return

	Net.countdown_changed.connect(func(seconds_left: int):
		if seconds_left == 0 and Net.role == "host":
			start_match())

	print("[server] слушаю порт %d, жду %d игроков (режим %s, сложность %s, уровень %s)"
		% [port, target, ui.settings["mode"], ui.settings["difficulty"], ui.settings["level"]])

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == S_PLAYING:
		pause()

func _bind_ui() -> void:
	ui.start_requested.connect(request_match)
	ui.restart_requested.connect(request_match)
	ui.menu_requested.connect(to_menu)
	ui.resume_requested.connect(resume)
	ui.perk_chosen.connect(_on_perk_chosen)
	ui.reset_progress_requested.connect(_reset_progress)
	ui.garage_changed.connect(func(): ui.refresh_profile())
	ui.quit_requested.connect(func(): get_tree().quit())
	ui.daily_reward_claimed.connect(func(reward: int):
		hud.add_feed(I18n.t("feed.dailyDone", {"n": reward},
			"Задание выполнено: +%d 🪙" % reward), Cfg.UI_GOLD)
		Sfx.play("pickup")
		ui.refresh_profile())

func _bind_profile_events() -> void:
	Prof.levelup.connect(func(levels: Array):
		var lvl: int = levels[levels.size() - 1]
		hud.add_feed(I18n.t("feed.profileLevel", {"n": lvl}, "Уровень профиля %d!" % lvl), Cfg.UI_GOLD)
		Sfx.play("levelup")
		ui.refresh_profile())

	Prof.unlock.connect(func(ids: Array, reason: String):
		var names := []
		for id in ids:
			var perk := Perks.get_perk(id)
			var label := I18n.t("feed.challengeDone", {}, "Челлендж выполнен") if reason == "challenge" \
				else I18n.t("feed.newPerk", {}, "Новый перк")
			hud.add_feed("%s: %s %s" % [label, Perks.perk_icon(id), I18n.dn(perk, "name", "perk")],
				Color("#ff66ff"))
			names.append(I18n.dn(perk, "name", "perk"))
		hud.banner(I18n.t("feed.perkUnlocked", {"names": ", ".join(names)},
			"Открыт перк: %s" % ", ".join(names)), Color("#ff88ff"))
		Sfx.play("unlock")
		ui.refresh_profile())

	Prof.achievement.connect(func(ids: Array, reward: int):
		var names := []
		for id in ids:
			var a := Achievements.get_achievement(id)
			names.append("%s %s" % [a.get("icon", ""), I18n.dn(a, "name", "ach")] if not a.is_empty() else id)
		hud.add_feed(I18n.t("feed.achievement", {"names": ", ".join(names)},
			"Достижение: %s" % ", ".join(names)), Cfg.UI_GOLD)
		hud.banner(I18n.t("feed.achievementReward", {"n": reward},
			"Достижение! +%d 🪙" % reward), Cfg.UI_GOLD)
		Sfx.play("unlock")
		ui.refresh_profile())

	Prof.rank_up.connect(func(ids: Array, reward: int):
		var names := []
		for id in ids:
			var r := Ranks.get_rank(id)
			names.append("%s %s" % [r.get("icon", ""), I18n.dn(r, "name", "rank")] if not r.is_empty() else id)
		hud.add_feed(I18n.t("feed.rankUp", {"names": ", ".join(names)},
			"Новое звание: %s" % ", ".join(names)), Cfg.UI_GOLD)
		if reward > 0:
			hud.banner(I18n.t("feed.rankReward", {"n": reward},
				"Новое звание! +%d 🪙" % reward), Cfg.UI_GOLD)
		Sfx.play("unlock")
		ui.refresh_profile())

func _reset_progress() -> void:
	Prof.reset()
	ui.refresh_profile()
	ui.show_menu()

func _on_resize() -> void:
	_layout_viewports()
	if not players.is_empty():
		hud.layout(players, world)

func _layout_viewports() -> void:
	var size := get_viewport().get_visible_rect().size
	if players.size() <= 1:
		if players.size() == 1:
			players[0].viewport = Rect2(Vector2.ZERO, size)
	else:
		var half := floorf(size.x / 2.0)
		players[0].viewport = Rect2(0, 0, half, size.y)
		players[1].viewport = Rect2(half, 0, size.x - half, size.y)
	for i in _views.size():
		if i >= players.size():
			continue
		var vp: Rect2 = players[i].viewport
		var entry: Dictionary = _views[i]
		var container: SubViewportContainer = entry["container"]
		container.position = vp.position
		container.size = vp.size
		(entry["viewport"] as SubViewport).size = Vector2i(maxi(1, int(vp.size.x)), maxi(1, int(vp.size.y)))

func _free_tile_cache() -> void:
	if _tile_cache != null:
		_tile_cache.queue_free()
		_tile_cache = null

func _rebuild_views() -> void:
	for entry in _views:
		entry["container"].queue_free()
	_views.clear()
	_free_tile_cache()
	# Один кэш тайлов на матч, общий для всех видов (в hot seat раньше
	# каждый вид запекал карту сам — вдвое больше работы на каждом
	# разрушении).
	if not players.is_empty():
		_tile_cache = TileCache.new()
		_tile_cache.world = world
		_tile_cache.players = players
		_views_root.add_child(_tile_cache)
	for player in players:
		var container := SubViewportContainer.new()
		container.stretch = false
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_views_root.add_child(container)

		var vp := SubViewport.new()
		vp.transparent_bg = false
		vp.handle_input_locally = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(vp)

		var bg := ColorRect.new()
		bg.color = Color("#0a0a0a")
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vp.add_child(bg)

		var view := WorldView.new()
		view.world = world
		view.player = player
		view.tile_cache = _tile_cache
		view.floaters = floaters
		if Sets.fx_quality > PostFx.OFF:
			view.ao = AoLayer.new()
		vp.add_child(view)

		var glow: GlowLayer = null
		if Sets.fx_quality > PostFx.OFF:
			glow = GlowLayer.new()
			glow.world = world
			glow.view = view
			glow.quality = Sets.fx_quality
			vp.add_child(glow)

		container.material = PostFx.make_material(Sets.fx_quality)

		_views.append({"container": container, "viewport": vp, "view": view, "glow": glow})
	_layout_viewports()

## Интерактивный старт партии (кнопки меню, «Ещё раз», старт по сети):
## сначала показываем экран загрузки, и только когда он реально
## отрисован — запускаем тяжёлый синхронный start_match(). Затем держим
## экран, пока WorldView не запечёт карту в кэш (первый полный проход
## _draw_tiles по всей карте) и не прогреются шейдеры пост-эффектов —
## именно на эти первые кадры приходился фриз при запуске карты.
## Тесты и выделенный сервер по-прежнему зовут start_match() напрямую.
const LOADING_MIN_MSEC := 450
const LOADING_MAX_WARM_FRAMES := 30

func request_match(net_opts: Dictionary = {}) -> void:
	if _loading != null:
		return
	if DisplayServer.get_name() == "headless":
		start_match(net_opts)
		return

	var screen := LoadingScreen.new()
	_loading = screen
	_root.add_child(screen)
	screen.set_mode(String(net_opts.get("mode", ui.settings.get("mode", "ffa"))))
	var shown_at := Time.get_ticks_msec()

	# Клиент стартует сразу: хост уже шлёт спавны танков и дельты карты,
	# и пока world == null они бы терялись. Экран всё равно накроет
	# тяжёлые первые кадры отрисовки.
	if Net.role != "client":
		await get_tree().process_frame
		await get_tree().process_frame

	start_match(net_opts)

	if world != null:
		screen.set_location(String(world.level.get("location", "")))
	screen.set_stage(I18n.t("loading.gfx", {}, "Подготовка графики"), 0.8)

	var frames := 0
	while frames < LOADING_MAX_WARM_FRAMES and not _views_warm():
		frames += 1
		await get_tree().process_frame
	# Ещё пара кадров: кэш уже блитится, шейдеры пост-эффектов собраны.
	await get_tree().process_frame
	await get_tree().process_frame
	while Time.get_ticks_msec() - shown_at < LOADING_MIN_MSEC:
		await get_tree().process_frame

	if is_instance_valid(screen):
		screen.finish()
	_loading = null

func _views_warm() -> bool:
	for entry in _views:
		var view = entry["view"]
		if is_instance_valid(view) and not view.is_cache_warm():
			return false
	return true

func start_match(net_opts: Dictionary = {}) -> void:
	if world != null:
		world.dispose()
		world = null
	_predict_buf = []
	_last_reconciled_tick = -1

	var s := ui.settings
	var hotseat: bool = String(s["game_type"]) == "hotseat"
	var is_client := Net.role == "client"
	var seed_override := int(net_opts.get("net_seed", s.get("seed", -1)))
	if is_client:
		s["mode"] = String(net_opts.get("mode", s["mode"]))
		s["difficulty"] = String(net_opts.get("difficulty", s["difficulty"]))
		s["level"] = int(net_opts.get("level", s["level"]))
		s["weather"] = String(net_opts.get("weather", "auto"))
		s["daytime"] = String(net_opts.get("daytime", "auto"))
		s["location"] = String(net_opts.get("location", "auto"))

	remote_players = []
	var is_dedicated_host := Net.role == "host" and Net.dedicated
	players = []
	if not is_dedicated_host:
		var p1_dev := _connected_or_auto(Sets.p1_device)
		var p2_dev := _connected_or_auto(Sets.p2_device)
		if hotseat and p1_dev == Sets.DEV_AUTO and p2_dev == Sets.DEV_AUTO:
			var pads := Sets.pads()
			if pads.size() >= 1:
				p1_dev = "pad%d" % int(pads[0]["id"])
			if pads.size() >= 2:
				p2_dev = "pad%d" % int(pads[1]["id"])
		players = [PlayerState.new(0, I18n.t("player1", {}, "Игрок 1"),
			Prof.equipped_color1, _scheme_for(p1_dev, 0, hotseat))]
		if not hotseat and p1_dev == Sets.DEV_AUTO:
			players[0].enable_auto_device_switch(players[0].scheme, Ctl.GamepadScheme.new(0))
		if hotseat and not Net.is_online:
			players.append(PlayerState.new(1, I18n.t("player2", {}, "Игрок 2"),
				Prof.equipped_color2, _scheme_for(p2_dev, 1, hotseat)))
		if Net.is_online:
			players[0].peer_id = multiplayer.get_unique_id()
			players[0].name = String(Net.my_name)
	if Net.role == "host":
		for peer_id in Net.lobby.keys():
			if int(peer_id) == multiplayer.get_unique_id():
				continue
			var info: Dictionary = Net.lobby[peer_id]
			var rp := PlayerState.new(remote_players.size() + 1,
				String(info.get("name", "Игрок")), String(info.get("color_key", "p2")),
				Ctl.NetScheme.new(int(peer_id)))
			rp.peer_id = int(peer_id)
			rp.cosmetics = info.get("cosmetics", {})
			rp.equipped_cannon = String(info.get("cannon_id", "standard"))
			remote_players.append(rp)

	for p in players:
		p.reset_for_match()
		p.upgrade_mods = Prof.upgrade_mods()
		p.cosmetics = Prof.equipped_cosmetics()
		p.equipped_cannon = Prof.equipped_cannon
	for p in remote_players:
		p.reset_for_match()

	_layout_viewports()

	var loc_setting := String(s.get("location", "auto"))
	var match_location := loc_setting
	if is_client:
		match_location = String(net_opts.get("location", Locations.CITY))
	elif not Locations.LIST.has(loc_setting):
		match_location = Locations.pick_random(ui_rng)
	var level := LevelGen.generate(int(s["level"]), String(s["mode"]), seed_override,
		match_location, String(s.get("archetype", "auto")))
	if not is_client and int(s.get("seed", -1)) != -1:
		s["seed"] = -1
	Net.reset_tank_ids()
	if Net.role == "host":
		Net.begin_match()
	world = World.new({
		"map": level["map"], "level": level, "mode": String(s["mode"]),
		"difficulty": String(s["difficulty"]),
		"players": players + remote_players,
		"player_level": Prof.global_level,
		"puppet": is_client,
		"weather": String(s.get("weather", "auto")),
		"daytime": String(s.get("daytime", "auto")),
		"rng_seed": seed_override,
	})
	if is_client:
		for info in net_opts.get("net_roster", []):
			net_spawn_puppet(info)
	elif Net.role == "host":
		world.map.net_log_on = true
		Net.host_start_match({
			"mode": String(s["mode"]), "difficulty": String(s["difficulty"]),
			"level": int(s["level"]),
			"weather": String(s.get("weather", "auto")),
			"daytime": String(s.get("daytime", "auto")),
			"location": match_location,
		}, int(level["seed"]), world.roster())
	_bind_world_events(world)

	match_damage = 0.0
	accumulator = 0.0
	floaters.clear()

	_rebuild_views()
	hud.clear_feed()
	hud.build(players, world)
	hud.show_hud()

	var start_hint := ""
	match String(s["mode"]):
		"ffa":
			start_hint = I18n.t("feed.start.ffa", {}, "Каждый за себя: наберите фраги первым")
		"koth":
			start_hint = I18n.t("feed.start.koth", {}, "Царь горы: переживите всех на тонущей карте")
		"defense":
			start_hint = I18n.t("feed.start.defense", {}, "Оборона: удерживайте базу от волн врагов")
		_:
			start_hint = I18n.t("feed.start.ctf", {}, "Захват флага: везите чужие флаги на свою базу")
	hud.add_feed(start_hint, Color("#88ff88"))

	ui.hide_all_overlays()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	Prof.bump_stat("gamesPlayed", 1)

	for p in players:
		p.update_camera()

	state = S_PLAYING
	Mus.play_combat(String(world.level.get("location", Locations.CITY)))
	for p in players:
		p.pending_level_ups += 1
	_process_perk_queue()

func to_menu() -> void:
	state = S_MENU
	Mus.play_menu()
	Sfx.clear_listeners()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if world != null:
		world.dispose()
	world = null
	players = []
	perk_player = null
	for entry in _views:
		entry["container"].queue_free()
	_views.clear()
	_free_tile_cache()
	hud.hide_hud()
	hud.clear_feed()
	floaters.clear()
	ui.refresh_profile()
	ui.show_menu()

func pause() -> void:
	if state != S_PLAYING:
		return
	state = S_PAUSED
	Mus.set_ducked(true)
	ui.show_pause()

func resume() -> void:
	if state != S_PAUSED:
		return
	ui.hide_pause()
	ui.close_gallery()
	Mus.set_ducked(false)
	state = S_PLAYING
	accumulator = 0.0

func _bind_world_events(w: World) -> void:
	w.feed.connect(func(text: String, color: Color):
		hud.add_feed(text, color)
		if Net.role == "host":
			Net.host_event("feed", {"text": text, "color": color.to_html()}))

	w.wave_started.connect(func(n: int):
		hud.banner(I18n.t("hud.waveBanner", {"n": n}, "ВОЛНА %d" % n), Cfg.UI_GOLD, 90, 40)
		if Net.role == "host":
			Net.host_event("wave_started", {"n": n}))

	w.damage_number.connect(func(x: float, y: float, text: String, color: Color):
		if floaters.size() > 80:
			floaters.pop_front()
		floaters.append({"x": x, "y": y, "text": text, "color": color, "life": 45}))

	w.kill.connect(func(victim, killer, source: String, suicide: bool):
		if suicide or killer == null:
			hud.add_feed(I18n.t("feed.killSuicide", {"name": victim.name},
				"%s уничтожен" % victim.name), Color("#888888"))
			return
		var color := Color("#bbbbbb")
		if killer.owner != null:
			color = Color("#88ff88")
		elif victim.owner != null:
			color = Color("#ff6666")
		hud.add_feed("%s ▸ %s" % [killer.name, victim.name], color))

	w.player_died.connect(func(player):
		Prof.bump_stat("timesDied", 1)
		hud.add_feed(I18n.t("feed.youDied", {"name": player.name},
			"%s: танк уничтожен" % player.name), Cfg.UI_DANGER)
		Ctl.vibrate(player, 0.5, 1.0, 0.4))

	w.player_damage.connect(func(_player, amount: float):
		match_damage += amount
		Prof.bump_stat("damageInGame", int(round(match_damage)))
		Prof.bump_daily("damage", int(round(amount))))

	w.global_xp.connect(func(amount: int): Prof.add_xp(amount))

	w.reward.connect(func(kind: String, amount: int, who: String):
		Prof.add_money(amount)
		Prof.bump_daily("coins", amount)
		if kind == "kill":
			Prof.bump_daily("kills", 1)
		if kind == "capture":
			Prof.bump_daily("captures", 1)
		if kind == "win":
			Prof.bump_daily("wins", 1)
		hud.add_feed(I18n.t("feed.reward", {"n": amount, "label": _reward_label(kind, who)},
			"+%d 🪙 %s" % [amount, _reward_label(kind, who)]), Color("#ffd54a")))

	w.stat.connect(func(key: String, value: int, mode: String):
		Prof.bump_stat(key, value)
		if key == "totalKills":
			Prof.bump_daily("kills", 1)
		if key == "healthPacksCollected":
			Prof.bump_daily("medkits", 1)
		if key == "cleanStreak" and mode == "max":
			Prof.bump_daily_max("streak", value))

	w.bot_perk.connect(func(tank, perk: Dictionary):
		hud.add_feed(I18n.t("feed.botPerk",
			{"name": tank.name, "icon": perk["icon"], "perk": I18n.dn(perk, "name", "botperk")},
			"%s получил: %s %s" % [tank.name, perk["icon"], perk["name"]]), Color("#ffaa44")))

	w.session_level_up.connect(func(player, _levels: int):
		Sfx.play("levelup")
		hud.add_feed(I18n.t("feed.sessionLevel", {"name": player.name, "n": player.session_level},
			"%s: уровень %d!" % [player.name, player.session_level]), Cfg.UI_GOLD))

	w.flag_event.connect(func(type: String, _flag, tank):
		if type == "captured" and tank != null and tank.owner != null:
			hud.banner(I18n.t("feed.flagCaptured", {}, "Флаг захвачен!"), Cfg.UI_GOLD, 90))

	w.finished.connect(_on_finish)

func _reward_label(kind: String, who: String) -> String:
	match kind:
		"kill":
			return I18n.t("reward.kill", {"name": who}, "за убийство (%s)" % who)
		"capture":
			return I18n.t("reward.capture", {"name": who}, "за захват флага (%s)" % who)
		"win":
			return I18n.t("reward.win", {}, "за победу")
	return I18n.t("reward.other", {}, "награда")

func _on_finish(result: Dictionary) -> void:
	state = S_GAMEOVER
	if Net.role == "host":
		Net.host_event("finish", result)
	Mus.play_menu()
	if bool(result["victory"]):
		Prof.bump_stat("gamesWon", 1)
	if world.mode == "defense":
		Prof.bump_stat("defenseWaveReached", world.wave)
	Prof.bump_daily("games", 1)
	Prof.check_challenges()
	Prof.save_profile()
	SteamStats.push_stats(Prof.stats)
	var best := 0
	for p in players:
		best = maxi(best, p.score)
	var board_score := world.wave if world.mode == "defense" else best
	SteamStats.push_score(board_score, world.mode)
	hud.hide_hud()
	ui.refresh_profile()
	ui.show_game_over(result, world, players.size() > 1)

func _sync_steam() -> void:
	if not SteamStats.ready():
		return
	var sent := SteamStats.push_all(Prof.achievements.keys())
	SteamStats.push_stats(Prof.stats)
	var steam: Object = Engine.get_singleton("Steam")
	if steam.has_signal("leaderboard_find_result") 			and not steam.is_connected("leaderboard_find_result", _on_leaderboard_found):
		steam.connect("leaderboard_find_result", _on_leaderboard_found)
	print("[Steam] достижений отправлено: %d из %d" % [sent, Prof.achievements.size()])

func _on_leaderboard_found(_handle, found: int) -> void:
	SteamStats.on_leaderboard_found(found != 0)

func _connected_or_auto(device: String) -> String:
	if not device.begins_with("pad"):
		return device
	var id := int(device.substr(3))
	for pad in Sets.pads():
		if int(pad["id"]) == id:
			return device
	push_warning("Геймпад %d из настроек не подключён — управление «Авто»" % (id + 1))
	return Sets.DEV_AUTO

func _scheme_for(device: String, index: int, hotseat: bool):
	if device.begins_with("pad"):
		return Ctl.GamepadScheme.new(int(device.substr(3)))
	if device == Sets.DEV_KEYS:
		return Ctl.KeyboardAimScheme.new()
	if device == Sets.DEV_KBM:
		return Ctl.MouseAimScheme.new(not hotseat)
	return Ctl.MouseAimScheme.new(not hotseat) if index == 0 		else Ctl.KeyboardAimScheme.new()

func _process_perk_queue() -> void:
	if state == S_GAMEOVER or state == S_MENU:
		return
	var next = null
	for p in players:
		if p.pending_level_ups > 0:
			next = p
			break
	if next == null:
		if state == S_PERK:
			state = S_PLAYING
			Mus.set_perk_ducked(false)
			ui.hide_perk_select()
			accumulator = 0.0
		perk_player = null
		return
	state = S_PERK
	Mus.set_perk_ducked(true)
	perk_player = next
	var queue_left := -1
	for p in players:
		queue_left += p.pending_level_ups
	ui.show_perk_select(next, maxi(0, queue_left), ui_rng)

func _on_perk_chosen(player, perk_id: String) -> void:
	if perk_id != "":
		player.equip_perk(perk_id)
		if world != null:
			world.maybe_summon_storm(player)
		var perk := Perks.get_perk(perk_id)
		hud.add_feed(I18n.t("feed.perkTook",
			{"name": player.name, "icon": perk["icon"], "perk": I18n.dn(perk, "name", "perk")},
			"%s взял %s %s" % [player.name, perk["icon"], perk["name"]]), Cfg.UI_GOLD)
	if Net.role == "client":
		Net.send_perk(perk_id)
	player.pending_level_ups = maxi(0, player.pending_level_ups - 1)
	_process_perk_queue()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if ui.handle_cancel():
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("pause"):
		if state == S_PLAYING:
			pause()
		elif state == S_PAUSED:
			resume()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("scoreboard") and (state == S_PLAYING or state == S_PAUSED):
		hud.toggle_scoreboard(world)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if state == S_MENU:
		return
	if world == null:
		return

	var mouse := get_viewport().get_mouse_position()
	for p in players:
		if "mouse" in p.scheme:
			p.scheme.mouse = mouse
		if "world" in p.scheme:
			p.scheme.world = world

	if state == S_PLAYING and Net.role == "client":
		_client_frame(delta)
	elif state == S_PLAYING:
		accumulator += minf(0.25, delta)
		var steps := 0
		while accumulator >= Cfg.TICK_SEC and steps < Cfg.MAX_STEPS_PER_FRAME:
			world.step()
			_update_floaters()
			accumulator -= Cfg.TICK_SEC
			steps += 1
			if world.finished_flag:
				break
			var pending := false
			for p in players:
				if p.pending_level_ups > 0:
					pending = true
					break
			if pending:
				break
		if accumulator > Cfg.TICK_SEC * Cfg.MAX_STEPS_PER_FRAME:
			accumulator = 0.0

		_host_frame()

		if not world.finished_flag:
			for p in players:
				if p.pending_level_ups > 0:
					_process_perk_queue()
					break

	_update_listeners()
	_update_engines()
	if state == S_PLAYING or state == S_PAUSED or state == S_PERK:
		hud.update_hud(world)
	_update_post_fx()

func _bind_net() -> void:
	Net.bind_game(self)
	Net.match_starting.connect(func(settings: Dictionary): request_match(settings))
	Net.disconnected.connect(func():
		if state != S_MENU:
			to_menu())
	Net.lobby_entered.connect(func():
		if state == S_MENU:
			ui.open_net())

func _client_frame(delta: float) -> void:
	accumulator += minf(0.25, delta)
	var steps := 0
	while accumulator >= Cfg.TICK_SEC and steps < Cfg.MAX_STEPS_PER_FRAME:
		world.step_cosmetic()
		_update_floaters()
		accumulator -= Cfg.TICK_SEC
		steps += 1
		var p = players[0]
		if p.scheme.has_method("read_command"):
			var cmd: Dictionary = p.scheme.read_command(p)
			Net.send_command(cmd)
			if p.tank != null:
				p.tank.predict_move(world, cmd)
				_predict_buf.append({"tick": world.tick, "cmd": cmd})
				if _predict_buf.size() > 480:
					_predict_buf = _predict_buf.slice(_predict_buf.size() - 480)
	if accumulator > Cfg.TICK_SEC * Cfg.MAX_STEPS_PER_FRAME:
		accumulator = 0.0
	_reconcile_local_tank()
	_apply_net_state()
	_check_net_alive()
	for p in players:
		p.update_camera()

const NET_WARN_MSEC := 700
const NET_DEAD_MSEC := 8000

func _check_net_alive() -> void:
	if Net.role != "client":
		return
	var st := Net.stats()
	var stale := int(st["stale_msec"])
	net_stale = stale > NET_WARN_MSEC
	if stale > NET_DEAD_MSEC:
		hud.add_feed(I18n.t("net.dead", {}, "Хост не отвечает — выходим в меню"),
			Cfg.UI_DANGER)
		Net.leave(false)
		to_menu()

func _host_frame() -> void:
	if Net.role != "host" or world == null:
		return
	Net.host_map_delta(world.map.take_net_log())
	for rp in remote_players:
		while rp.pending_level_ups > 0:
			rp.pending_level_ups -= 1
			Net.host_event_to(int(rp.peer_id), "perk", {})
	if world.tick - _sum_tick >= 300:
		_sum_tick = world.tick
		Net.host_event("mapsum", {"h": world.map.checksum()})

	if world.tick - _snap_tick < Net.SNAP_EVERY:
		return
	_snap_tick = world.tick
	Net.host_broadcast(world.tick, world.tanks, world.bullets, _net_extra())

func _net_extra() -> Dictionary:
	var flags := []
	for f in world.flags:
		flags.append([f.x, f.y, 0 if f.team == "player" else 1, f.at_home])
	var picks := []
	for p in world.pickups:
		picks.append([p.x, p.y])
	var weapons := []
	for w in world.weapon_pickups:
		weapons.append([w.x, w.y, w.weapon_id])
	var out := {
		"flags": flags, "pickups": picks, "weapons": weapons,
		"score": world.team_score, "wave": world.wave,
	}
	if world.base != null:
		out["base"] = [world.base["hp"], world.base["max_hp"]]
	return out

func _reconcile_local_tank() -> void:
	if players.is_empty():
		return
	var p = players[0]
	if p.tank == null or p.tank.net_id == 0:
		return
	var auth := Net.latest_snapshot_tank(p.tank.net_id)
	if auth.is_empty():
		return
	var t: int = int(auth["tick"])
	if t <= _last_reconciled_tick:
		return
	_last_reconciled_tick = t

	var tank: Tank = p.tank
	tank.x = float(auth["x"])
	tank.y = float(auth["y"])
	tank.body_angle = float(auth["body"])
	tank.angle = tank.body_angle
	tank.turret_angle = float(auth["turret"])
	tank.vx = 0.0
	tank.vy = 0.0

	var replay: Array = []
	for entry in _predict_buf:
		if int(entry["tick"]) > t:
			replay.append(entry)
	if replay.size() > Cfg.RECONCILE_MAX_REPLAY:
		replay = replay.slice(replay.size() - Cfg.RECONCILE_MAX_REPLAY)
	for entry in replay:
		tank.predict_move(world, entry["cmd"])
	_predict_buf = replay

func _apply_net_state() -> void:
	var st := Net.render_state()
	if st.is_empty() or world == null:
		return
	var local_tank = players[0].tank if not players.is_empty() else null
	var seen := {}
	var live := []
	for t in world.tanks:
		var info = st["tanks"].get(t.net_id)
		if info == null:
			continue
		seen[t.net_id] = true
		if t != local_tank:
			t.x = float(info["x"])
			t.y = float(info["y"])
			t.body_angle = float(info["body"])
			t.angle = t.body_angle
			t.turret_angle = float(info["turret"])
		t.hp = float(info["hp"])
		t.shield_hp = float(info["shield"])
		var flags := int(info["flags"])
		t.alive = (flags & 1) != 0
		t.turbo_timer = 2 if (flags & 2) != 0 else 0
		t.spawn_protect = 2 if (flags & 4) != 0 else 0
		t.shadow_timer = 2 if (flags & 16) != 0 else 0
		t.ability_timer = 2 if (flags & 32) != 0 else 0
		live.append(t)
	world.tanks = live

	world.bullets.clear()
	for b in st["bullets"]:
		var pb = Ent.Bullet.new(float(b["x"]), float(b["y"]), 0.0, null)
		pb.vx = float(b["vx"])
		pb.vy = float(b["vy"])
		pb.from_player = bool(b["player"])
		world.bullets.append(pb)

	_apply_net_extra(st.get("extra", {}))

func _apply_net_extra(extra: Dictionary) -> void:
	if extra.is_empty():
		return
	world.flags.clear()
	for f in extra.get("flags", []):
		var fl = Ent.Flag.new(float(f[0]), float(f[1]), "player" if int(f[2]) == 0 else "enemy")
		fl.state = "home" if bool(f[3]) else "dropped"
		world.flags.append(fl)
	world.pickups.clear()
	for p in extra.get("pickups", []):
		world.pickups.append(Ent.Pickup.new(float(p[0]), float(p[1]), "health", world.rng))
	world.weapon_pickups.clear()
	for w in extra.get("weapons", []):
		world.weapon_pickups.append(Ent.WeaponPickup.new(float(w[0]), float(w[1]), String(w[2]), world.rng))
	if extra.has("score"):
		world.team_score = extra["score"]
	if extra.has("wave"):
		world.wave = int(extra["wave"])
	if extra.has("base") and world.base != null:
		world.base["hp"] = float(extra["base"][0])

func net_spawn_puppet(info: Dictionary) -> void:
	if world == null:
		return
	for t in world.tanks:
		if t.net_id == int(info["id"]):
			return
	var tank := Tank.new({
		"x": 0.0, "y": 0.0, "team": String(info["team"]), "name": String(info["name"]),
		"owner": null, "max_hp": float(info["max_hp"]), "speed": float(info["speed"]),
		"fire_rate": int(info["fire_rate"]), "color_key": String(info["color_key"]),
		"chassis": String(info["chassis"]),
		"net_id": int(info["id"]), "owner_peer": int(info["owner_peer"]),
	})
	tank.cosmetics = info.get("cosmetics", {})
	tank.cannon_id = String(info.get("cannon_id", "standard"))
	if int(info["owner_peer"]) == multiplayer.get_unique_id() and not players.is_empty():
		tank.owner = players[0]
		players[0].tank = tank
	world.tanks.append(tank)

func net_apply_map_delta(delta: Array) -> void:
	if world == null:
		return
	var map := world.map
	for entry in delta:
		map.apply_net_cell(int(entry[0]), int(entry[1]), int(entry[2]))
	map.version += 1

func net_apply_event(kind: String, args: Dictionary) -> void:
	match kind:
		"feed":
			hud.add_feed(String(args.get("text", "")), Color(args.get("color", "#ffffff")))
		"wave_started":
			var n := int(args.get("n", 0))
			hud.banner(I18n.t("hud.waveBanner", {"n": n}, "ВОЛНА %d" % n), Cfg.UI_GOLD, 90, 40)
		"mapsum":
			if world == null:
				return
			net_sums += 1
			var mine := world.map.checksum()
			var theirs := int(args.get("h", 0))
			net_last_mine = mine
			net_last_theirs = theirs
			if mine != theirs:
				net_desyncs += 1
				print("[Net] карта разошлась: у меня %08x, у хоста %08x" % [mine, theirs])
				Net.request_map_resync()
		"perk":
			if not players.is_empty():
				players[0].pending_level_ups += 1
				_process_perk_queue()
		"finish":
			if state != S_GAMEOVER:
				_on_finish(args)

func net_peer_left(peer_id: int) -> void:
	for i in range(remote_players.size() - 1, -1, -1):
		var rp = remote_players[i]
		if int(rp.peer_id) != peer_id:
			continue
		if rp.tank != null:
			rp.tank.alive = false
			rp.tank.owner = null
			if world != null:
				world.tanks.erase(rp.tank)
		hud.add_feed(I18n.t("net.left", {"name": rp.name},
			"%s покинул бой" % rp.name), Cfg.UI_WARN)
		if world != null:
			world.players.erase(rp)
		remote_players.remove_at(i)
	return

func net_apply_perk(peer_id: int, perk_id: String) -> void:
	if perk_id == "":
		return
	for rp in remote_players:
		if int(rp.peer_id) != peer_id:
			continue
		if rp.equip_perk(perk_id):
			if world != null:
				world.maybe_summon_storm(rp)
			if rp.tank != null:
				rp.tank.perk_ids = rp.perk_ids
				rp.tank.recompute()
		return

func _update_listeners() -> void:
	var pts := PackedVector2Array()
	var half := 640.0
	for p in players:
		pts.append(Vector2(p.camera.x, p.camera.y))
		half = float(p.viewport.size.x) * 0.5
	Sfx.set_listeners(pts, half)
	var t0 = players[0].tank if not players.is_empty() else null
	Sfx.hear_scale = float(t0.mods["hearingMult"]) if t0 != null else 1.0

func _update_engines() -> void:
	var rigs: Array = []
	if state == S_PLAYING:
		for p in players:
			if p.tank == null:
				continue
			var t = p.tank
			rigs.append([t.x, t.y, sqrt(t.vx * t.vx + t.vy * t.vy)])
	Sfx.update_engines(rigs)

func _update_post_fx() -> void:
	if Sets.fx_quality <= PostFx.OFF:
		return
	for i in _views.size():
		if i >= players.size():
			continue
		var mat: ShaderMaterial = _views[i]["container"].material
		PostFx.update(mat, world, players[i], players[i].viewport.size, Sets.fx_quality)

func _update_floaters() -> void:
	var kept := []
	for f in floaters:
		f["life"] = int(f["life"]) - 1
		f["y"] = float(f["y"]) - 0.6
		if int(f["life"]) > 0:
			kept.append(f)
	floaters.assign(kept)
