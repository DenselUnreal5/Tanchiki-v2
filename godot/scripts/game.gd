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
## Сетевые соперники: играют в том же мире, но экран на этой машине не делят.
var remote_players: Array = []
var _snap_tick := 0
var _sum_tick := 0
## Сколько раз карта клиента разошлась с хостовой за партию. Ноль — норма;
## всё остальное видно в тестах и в отладке.
var net_desyncs := 0
## Сколько сверок отпечатка вообще состоялось. Без этого счётчика ноль
## расхождений неотличим от «сверка ни разу не сработала».
var net_sums := 0
## Последняя пара отпечатков: свой и хостовый. По ней видно не только
## «разошлось или нет», но и на каком именно состоянии сверяли.
var net_last_mine := 0
var net_last_theirs := 0
## Сеть молчит дольше порога: HUD показывает это игроку.
var net_stale := false
## Игрок, для которого сейчас открыт выбор перка.
var perk_player = null

## Своя случайность для интерфейса — отдельно от мировой.
##
## Раньше тройка перков тасовалась генератором мира. Список доступных перков
## короче на один, когда перк уже взят, а тасовка вытягивает по одному числу
## на элемент — значит после первого же выбора вся партия шла по другой ветке
## случайности. Замер перков поймал это в лоб: перк, который на симуляцию
## влиять не может вовсе, «давал» +1.3 убийства в минуту.
var ui_rng := Rng.new(int(Time.get_ticks_usec()) & 0xFFFFFFFF)
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
	# Догоняем Steam тем, что игрок успел открыть без него: профиль — источник
	# правды, и достижения, полученные офлайн, обязаны появиться в Steam
	# задним числом. Отложено на кадр: автозагрузки должны завершить _ready.
	_sync_steam.call_deferred()

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
	_bind_net()

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
## @param net_opts настройки сетевой партии от хоста: seed карты и состав.
##        Пустой словарь — обычная локальная игра.
func start_match(net_opts: Dictionary = {}) -> void:
	# Предыдущая партия могла остаться в памяти из-за циклических ссылок.
	if world != null:
		world.dispose()
		world = null

	var s := ui.settings
	var hotseat: bool = String(s["game_type"]) == "hotseat"
	var is_client := Net.role == "client"
	var seed_override := int(net_opts.get("net_seed", -1))
	if is_client:
		# Клиент играет тем режимом, который объявил хост, а не тем,
		# что выбрано в его собственном меню.
		s["mode"] = String(net_opts.get("mode", s["mode"]))
		s["difficulty"] = String(net_opts.get("difficulty", s["difficulty"]))
		s["level"] = int(net_opts.get("level", s["level"]))
		s["weather"] = String(net_opts.get("weather", "auto"))
		s["daytime"] = String(net_opts.get("daytime", "auto"))
		s["location"] = String(net_opts.get("location", "auto"))

	# players — только местные игроки: по ним делится экран. Сетевые
	# соперники живут в remote_players и в мир попадают наравне, но своего
	# окна на этом компьютере не имеют.
	remote_players = []
	players = [PlayerState.new(0, I18n.t("player1", {}, "Игрок 1"),
		String(s["color1"]), _scheme_for(Sets.p1_device, 0, hotseat))]
	if hotseat and not Net.is_online:
		players.append(PlayerState.new(1, I18n.t("player2", {}, "Игрок 2"),
			String(s["color2"]), _scheme_for(Sets.p2_device, 1, hotseat)))
	if Net.is_online:
		players[0].peer_id = multiplayer.get_unique_id()
		players[0].name = String(Net.my_name)
	if Net.role == "host":
		# Каждому подключённому — свой игрок с сетевой схемой управления:
		# его ввод приходит пакетами, а не с этой клавиатуры.
		for peer_id in Net.lobby.keys():
			if int(peer_id) == multiplayer.get_unique_id():
				continue
			var info: Dictionary = Net.lobby[peer_id]
			var rp := PlayerState.new(remote_players.size() + 1,
				String(info.get("name", "Игрок")), String(info.get("color_key", "p2")),
				Ctl.NetScheme.new(int(peer_id)))
			rp.peer_id = int(peer_id)
			rp.cosmetics = info.get("cosmetics", {})
			remote_players.append(rp)

	for p in players:
		p.reset_for_match()
		p.upgrade_mods = Prof.upgrade_mods()
		p.cosmetics = Prof.equipped_cosmetics()
	for p in remote_players:
		p.reset_for_match()

	_layout_viewports()

	# Локация разыгрывается ЗДЕСЬ и уже готовой уходит и в генератор, и в сеть.
	# Тянуть жребий внутри генератора нельзя: карта уровня детерминирована,
	# и «случайная» локация выпадала бы на нём всегда одна и та же.
	var loc_setting := String(s.get("location", "auto"))
	var match_location := loc_setting
	if is_client:
		match_location = String(net_opts.get("location", Locations.CITY))
	elif not Locations.LIST.has(loc_setting):
		match_location = Locations.pick_random(ui_rng)
	var level := LevelGen.generate(int(s["level"]), String(s["mode"]), seed_override,
		match_location)
	Net.reset_tank_ids()
	world = World.new({
		"map": level["map"], "level": level, "mode": String(s["mode"]),
		"difficulty": String(s["difficulty"]),
		"players": players + remote_players,
		"player_level": Prof.global_level,
		"puppet": is_client,
		"weather": String(s.get("weather", "auto")),
		"daytime": String(s.get("daytime", "auto")),
		"rng_seed": int(net_opts.get("rng_seed", -1)),
	})
	if is_client:
		# Состав приходит от хоста: свои танки клиент не порождает.
		for info in net_opts.get("net_roster", []):
			net_spawn_puppet(info)
	elif Net.role == "host":
		# Журнал изменений карты нужен только хосту и только в партии.
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

	# Стартовый выбор перка — по одному на игрока.
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
	w.feed.connect(func(text: String, color: Color):
		hud.add_feed(text, color)
		if Net.role == "host":
			Net.host_event("feed", {"text": text, "color": color.to_html()}))

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
	if Net.role == "host":
		Net.host_event("finish", result)
	Mus.play_menu()
	if bool(result["victory"]):
		Prof.bump_stat("gamesWon", 1)
	Prof.bump_daily("games", 1)
	Prof.check_challenges()
	Prof.save_profile()
	# Итоги партии уходят в Steam: показатели — под достижения на стороне
	# Valve, лучший счёт — в общую таблицу.
	SteamStats.push_stats(Prof.stats)
	var best := 0
	for p in players:
		best = maxi(best, p.score)
	SteamStats.push_score(best)
	hud.hide_hud()
	ui.refresh_profile()
	ui.show_game_over(result, world, players.size() > 1)

## Разовая синхронизация со Steam при запуске.
##
## Отдаёт уже открытые достижения и накопленную статистику. Steam повторную
## выдачу игнорирует, поэтому вызов безопасен при каждом запуске.
func _sync_steam() -> void:
	if not SteamStats.ready():
		return
	var sent := SteamStats.push_all(Prof.achievements.keys())
	SteamStats.push_stats(Prof.stats)
	# Ответ на поиск таблицы приходит колбэком — подписываемся один раз.
	var steam: Object = Engine.get_singleton("Steam")
	if steam.has_signal("leaderboard_find_result") 			and not steam.is_connected("leaderboard_find_result", _on_leaderboard_found):
		steam.connect("leaderboard_find_result", _on_leaderboard_found)
	print("[Steam] достижений отправлено: %d из %d" % [sent, Prof.achievements.size()])

func _on_leaderboard_found(_handle, found: int) -> void:
	SteamStats.on_leaderboard_found(found != 0)

## Схема управления по настройке игрока.
##
## «auto» сохраняет прежнее поведение: первому — мышь с клавиатурой, второму
## клавиатура. Геймпад закрепляется за игроком по НОМЕРУ устройства, иначе
## в «горячем стуле» оба танка слушали бы один и тот же джойстик.
func _scheme_for(device: String, index: int, hotseat: bool):
	if device.begins_with("pad"):
		return Ctl.GamepadScheme.new(int(device.substr(3)))
	if device == Sets.DEV_KEYS:
		return Ctl.KeyboardAimScheme.new()
	if device == Sets.DEV_KBM:
		return Ctl.MouseAimScheme.new(not hotseat)
	return Ctl.MouseAimScheme.new(not hotseat) if index == 0 		else Ctl.KeyboardAimScheme.new()

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
		var perk := Perks.get_perk(perk_id)
		hud.add_feed(I18n.t("feed.perkTook",
			{"name": player.name, "icon": perk["icon"], "perk": I18n.dn(perk, "name", "perk")},
			"%s взял %s %s" % [player.name, perk["icon"], perk["name"]]), Cfg.UI_GOLD)
	# Клиент выбирает у себя, а танк живёт у хоста — отправляем выбор туда.
	if Net.role == "client":
		Net.send_perk(perk_id)
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

		_host_frame()

		if not world.finished_flag:
			for p in players:
				if p.pending_level_ups > 0:
					_process_perk_queue()
					break

	_update_listeners()
	if state == S_PLAYING or state == S_PAUSED or state == S_PERK:
		hud.update_hud(world)
	_update_post_fx()

# ============================================================== сетевая игра
func _bind_net() -> void:
	Net.bind_game(self)
	Net.match_starting.connect(func(settings: Dictionary): start_match(settings))
	Net.disconnected.connect(func():
		if state != S_MENU:
			to_menu())

## Кадр клиента: своя симуляция не считается вовсе. Идут только частицы,
## погода и обломки, а положение всего живого приходит от хоста.
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
			Net.send_command(p.scheme.read_command(p))
	if accumulator > Cfg.TICK_SEC * Cfg.MAX_STEPS_PER_FRAME:
		accumulator = 0.0
	_apply_net_state()
	_check_net_alive()
	for p in players:
		p.update_camera()

## Сколько молчит сеть, прежде чем предупредить игрока и прежде чем
## признать партию потерянной. Первый порог — четыре пропущенных снапшота
## подряд, второй — заведомо не джиттер, а обрыв.
const NET_WARN_MSEC := 700
const NET_DEAD_MSEC := 8000

## Клиент не считает мир сам, поэтому молчащая сеть выглядит как застывшая
## картинка без единой ошибки в консоли. Это худший вид поломки: игра цела,
## но не играет. Здесь она называет вещи своими именами.
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

## Хвост кадра хоста: разослать изменения карты и снапшот.
func _host_frame() -> void:
	if Net.role != "host" or world == null:
		return
	Net.host_map_delta(world.map.take_net_log())
	# Уровень сетевому игроку начисляет мир у хоста, а выбирает перк он сам:
	# зовём его экран, ответ придёт обратно как выбор.
	for rp in remote_players:
		while rp.pending_level_ups > 0:
			rp.pending_level_ups -= 1
			Net.host_event_to(int(rp.peer_id), "perk", {})
	# Раз в пять секунд — отпечаток карты. Это дёшево и ловит потерю
	# надёжного пакета, после которой у клиента осталась бы стена там,
	# где её снесли ещё в прошлой атаке.
	if world.tick - _sum_tick >= 300:
		_sum_tick = world.tick
		Net.host_event("mapsum", {"h": world.map.checksum()})

	if world.tick - _snap_tick < Net.SNAP_EVERY:
		return
	_snap_tick = world.tick
	Net.host_broadcast(world.tick, world.tanks, world.bullets, _net_extra())

## Мелочь режима, без которой HUD клиента врёт: счёт, флаги, аптечки, база.
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

## Раскладывает присланное состояние по объектам мира. Танки уже созданы
## заранее по составу, поэтому здесь только координаты и здоровье.
func _apply_net_state() -> void:
	var st := Net.render_state()
	if st.is_empty() or world == null:
		return
	var seen := {}
	var live := []
	for t in world.tanks:
		var info = st["tanks"].get(t.net_id)
		if info == null:
			continue
		seen[t.net_id] = true
		t.x = float(info["x"])
		t.y = float(info["y"])
		t.body_angle = float(info["body"])
		t.angle = t.body_angle
		t.turret_angle = float(info["turret"])
		t.hp = float(info["hp"])
		t.shield_hp = float(info["shield"])
		var flags := int(info["flags"])
		t.alive = (flags & 1) != 0
		# Таймеры не тикают у клиента, поэтому держим их взведёнными,
		# пока хост сообщает, что эффект активен: отрисовке нужен сам факт.
		t.turbo_timer = 2 if (flags & 2) != 0 else 0
		t.spawn_protect = 2 if (flags & 4) != 0 else 0
		t.shadow_timer = 2 if (flags & 16) != 0 else 0
		t.ability_timer = 2 if (flags & 32) != 0 else 0
		live.append(t)
	world.tanks = live

	# Пули пересобираются каждый кадр: их номера по сети не гоняются,
	# а связывать их между пакетами ради экономии — сложность без выигрыша.
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
		fl.at_home = bool(f[3])
		world.flags.append(fl)
	world.pickups.clear()
	for p in extra.get("pickups", []):
		world.pickups.append(Ent.Pickup.new(float(p[0]), float(p[1])))
	world.weapon_pickups.clear()
	for w in extra.get("weapons", []):
		world.weapon_pickups.append(Ent.WeaponPickup.new(float(w[0]), float(w[1]), String(w[2])))
	if extra.has("score"):
		world.team_score = extra["score"]
	if extra.has("wave"):
		world.wave = int(extra["wave"])
	if extra.has("base") and world.base != null:
		world.base["hp"] = float(extra["base"][0])

## Создаёт у клиента танк-марионетку по описанию от хоста.
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
	# Свой танк цепляется к местному игроку: иначе не будет ни камеры,
	# ни HUD, ни прицеливания.
	if int(info["owner_peer"]) == multiplayer.get_unique_id() and not players.is_empty():
		tank.owner = players[0]
		players[0].tank = tank
	world.tanks.append(tank)

func net_apply_map_delta(delta: Array) -> void:
	if world == null:
		return
	var map := world.map
	for entry in delta:
		var i := int(entry[0])
		map.tiles[i] = int(entry[1])
		map.damage[i] = int(entry[2])
	map.version += 1

func net_apply_event(kind: String, args: Dictionary) -> void:
	match kind:
		"feed":
			hud.add_feed(String(args.get("text", "")), Color(args.get("color", "#ffffff")))
		"mapsum":
			# Расхождение чиним не «подкруткой», а запросом карты целиком:
			# знать, какие именно тайлы разошлись, клиент не может.
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

## Игрок отключился посреди партии. Без уборки его танк оставался
## в мире с последней командой в руках: ехал в стену до конца партии,
## занимал место в счёте и продолжал получать уровни.
func net_peer_left(peer_id: int) -> void:
	for i in range(remote_players.size() - 1, -1, -1):
		var rp = remote_players[i]
		if int(rp.peer_id) != peer_id:
			continue
		if rp.tank != null:
			# Танк убирается из мира целиком, а не просто помечается мёртвым.
			# Мёртвый корпус остаётся в списке, и его продолжает расталкивать
			# физика: замер показал, что за две секунды он уезжал на 40 px
			# сам по себе. Клиенты уберут его следом — снапшот его больше
			# не содержит, а лишние танки клиент вычищает сам.
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

## Перк, выбранный сетевым игроком: экран у него, танк — здесь.
func net_apply_perk(peer_id: int, perk_id: String) -> void:
	if perk_id == "":
		return
	for rp in remote_players:
		if int(rp.peer_id) != peer_id:
			continue
		if rp.equip_perk(perk_id) and rp.tank != null:
			rp.tank.perk_ids = rp.perk_ids
			rp.tank.recompute()
		return

## Звук слышен «из камеры»: громкость, панорама и глухость далёких
## выстрелов считаются от этих точек. В «горячем стуле» их две.
func _update_listeners() -> void:
	var pts := PackedVector2Array()
	var half := 640.0
	for p in players:
		pts.append(Vector2(p.camera.x, p.camera.y))
		half = float(p.viewport.size.x) * 0.5
	Sfx.set_listeners(pts, half)
	# «Острый слух» слышит дальше: дальность берётся у местного игрока,
	# потому что слушает именно он.
	var t0 = players[0].tank if not players.is_empty() else null
	Sfx.hear_scale = float(t0.mods["hearingMult"]) if t0 != null else 1.0

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
