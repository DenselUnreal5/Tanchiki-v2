# ============================================================================
# game.gd — связывает всё вместе: цикл, состояния, события.
#
# Один явный конечный автомат состояний: МЕНЮ → ИГРА → (ПАУЗА | ВЫБОР ПЕРКА)
# → ИТОГИ. Логика мира идёт фиксированным шагом 60 Гц независимо от частоты
# кадров, отрисовка — каждый кадр.
# ============================================================================
extends Node

const S_MENU := "menu"
const S_PLAYING := "playing"
const S_PAUSED := "paused"
const S_PERK := "perk"
const S_GAMEOVER := "gameover"

var state := S_MENU

var world: World = null
var players: Array = []

## Накопитель времени для фиксированного шага.
var accumulator := 0.0
## Игрок, для которого сейчас открыт выбор перка.
var perk_player = null
## Суммарный урон за партию, для челленджа «Вампир».
var match_damage := 0.0

## Всплывающие числа урона: {x, y, text, color, life}.
var floaters: Array = []

var _root: Control
var _views_root: Control
var _views: Array = []     # [{container, viewport, view}]
var hud: Hud
var ui: UiRoot

func _ready() -> void:
	# Интерфейс рассчитан так, чтобы целиком помещаться без прокрутки;
	# меньше этого размера верстка начала бы налезать сама на себя.
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

	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	ui.show_menu()
	# Тема меню включится сама, как только соберётся в фоне.
	Mus.play_menu()

## Свёрнутое окно не должно означать проигранную партию.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == S_PLAYING:
		pause()

func _bind_ui() -> void:
	ui.start_requested.connect(start_match)
	ui.restart_requested.connect(start_match)
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

# ------------------------------------------------------------------ профиль
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

func _reset_progress() -> void:
	Prof.reset()
	ui.refresh_profile()
	ui.show_menu()

# ------------------------------------------------------------------ размеры
func _on_resize() -> void:
	_layout_viewports()
	if not players.is_empty():
		hud.layout(players)

## Раскладка областей просмотра: один экран или вертикальный сплит.
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

func _rebuild_views() -> void:
	for entry in _views:
		entry["container"].queue_free()
	_views.clear()
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
		view.floaters = floaters
		# Затенение у стен считается один раз на карту и переиспользуется.
		if Sets.fx_quality > PostFx.OFF:
			view.ao = AoLayer.new()
		vp.add_child(view)

		# Свечение источников — отдельным узлом поверх мира: режим смешивания
		# задаётся материалом всего узла, внутри одного _draw() его не сменить.
		var glow: GlowLayer = null
		if Sets.fx_quality > PostFx.OFF:
			glow = GlowLayer.new()
			glow.world = world
			glow.view = view
			glow.quality = Sets.fx_quality
			vp.add_child(glow)

		# Цветокоррекция вешается на контейнер: она обрабатывает готовую
		# картинку мира и не задевает HUD и меню, которые рисуются поверх.
		container.material = PostFx.make_material(Sets.fx_quality)

		_views.append({"container": container, "viewport": vp, "view": view, "glow": glow})
	_layout_viewports()

# ------------------------------------------------------------------ партия
func start_match() -> void:
	# Предыдущая партия могла остаться в памяти из-за циклических ссылок.
	if world != null:
		world.dispose()
		world = null

	var s := ui.settings
	var hotseat: bool = String(s["game_type"]) == "hotseat"

	players = [PlayerState.new(0, I18n.t("player1", {}, "Игрок 1"),
		String(s["color1"]), Ctl.MouseAimScheme.new(not hotseat))]
	if hotseat:
		players.append(PlayerState.new(1, I18n.t("player2", {}, "Игрок 2"),
			String(s["color2"]), Ctl.KeyboardAimScheme.new()))
	for p in players:
		p.reset_for_match()
		p.upgrade_mods = Prof.upgrade_mods()
		p.cosmetics = Prof.equipped_cosmetics()

	_layout_viewports()

	var level := LevelGen.generate(int(s["level"]), String(s["mode"]))
	world = World.new({
		"map": level["map"], "level": level, "mode": String(s["mode"]),
		"difficulty": String(s["difficulty"]), "players": players,
		"player_level": Prof.global_level,
	})
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

	# Стартовый выбор перка — по одному на игрока.
	state = S_PLAYING
	Mus.play_combat()
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

# ------------------------------------------------------------------ события мира
func _bind_world_events(w: World) -> void:
	w.feed.connect(func(text: String, color: Color): hud.add_feed(text, color))

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
			"%s: танк уничтожен" % player.name), Cfg.UI_DANGER))

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
	Mus.play_menu()
	if bool(result["victory"]):
		Prof.bump_stat("gamesWon", 1)
	Prof.bump_daily("games", 1)
	Prof.check_challenges()
	Prof.save_profile()
	hud.hide_hud()
	ui.refresh_profile()
	ui.show_game_over(result, world, players.size() > 1)

# ------------------------------------------------------------------ перки
## Показывает выбор перка следующему игроку в очереди, если он есть.
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
			Mus.set_paused(false)
			ui.hide_perk_select()
			accumulator = 0.0
		perk_player = null
		return
	state = S_PERK
	Mus.set_paused(true)
	perk_player = next
	var queue_left := -1
	for p in players:
		queue_left += p.pending_level_ups
	ui.show_perk_select(next, maxi(0, queue_left), world.rng if world != null else Rng.new(1))

func _on_perk_chosen(player, perk_id: String) -> void:
	if perk_id != "":
		player.equip_perk(perk_id)
		var perk := Perks.get_perk(perk_id)
		hud.add_feed(I18n.t("feed.perkTook",
			{"name": player.name, "icon": perk["icon"], "perk": I18n.dn(perk, "name", "perk")},
			"%s взял %s %s" % [player.name, perk["icon"], perk["name"]]), Cfg.UI_GOLD)
	player.pending_level_ups = maxi(0, player.pending_level_ups - 1)
	_process_perk_queue()

# ------------------------------------------------------------------ ввод
func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var key: int = key_event.keycode

	if key == KEY_ESCAPE:
		if ui.is_gallery_open or ui.is_garage_open or ui.is_stats_open \
				or ui.is_achievements_open or ui.is_daily_open:
			ui.close_gallery()
			ui.close_garage()
			ui.close_stats()
			ui.close_achievements()
			ui.close_daily()
			get_viewport().set_input_as_handled()
			return

	if key == KEY_P or key == KEY_ESCAPE:
		if state == S_PLAYING:
			pause()
		elif state == S_PAUSED:
			resume()
		get_viewport().set_input_as_handled()
		return

	if key == KEY_TAB and (state == S_PLAYING or state == S_PAUSED):
		hud.toggle_scoreboard(world)
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ цикл
func _process(delta: float) -> void:
	if state == S_MENU:
		return
	if world == null:
		return

	# Курсор мыши в координатах окна — схемы управления переводят его
	# в мировые координаты через личную область просмотра игрока.
	var mouse := get_viewport().get_mouse_position()
	for p in players:
		# Мышью целится только схема первого игрока.
		if p.scheme.has_method("read_command"):
			p.scheme.mouse = mouse

	if state == S_PLAYING:
		accumulator += minf(0.25, delta)
		var steps := 0
		while accumulator >= Cfg.TICK_SEC and steps < Cfg.MAX_STEPS_PER_FRAME:
			world.step()
			_update_floaters()
			accumulator -= Cfg.TICK_SEC
			steps += 1
			# Прерываем догон, если партия завершилась или открылся выбор перка.
			if world.finished_flag:
				break
			var pending := false
			for p in players:
				if p.pending_level_ups > 0:
					pending = true
					break
			if pending:
				break
		# Если накопилось слишком много — сбрасываем остаток, чтобы игра
		# не «догоняла» рывками после сворачивания окна.
		if accumulator > Cfg.TICK_SEC * Cfg.MAX_STEPS_PER_FRAME:
			accumulator = 0.0

		if not world.finished_flag:
			for p in players:
				if p.pending_level_ups > 0:
					_process_perk_queue()
					break

	_update_listeners()
	if state == S_PLAYING or state == S_PAUSED or state == S_PERK:
		hud.update_hud(world)
	_update_post_fx()

## Звук слышен «из камеры»: громкость, панорама и глухость далёких
## выстрелов считаются от этих точек. В «горячем стуле» их две.
func _update_listeners() -> void:
	var pts := PackedVector2Array()
	var half := 640.0
	for p in players:
		pts.append(Vector2(p.camera.x, p.camera.y))
		half = float(p.viewport.size.x) * 0.5
	Sfx.set_listeners(pts, half)

## Параметры постобработки ведёт погода: время суток, дождь, туман, молния.
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
