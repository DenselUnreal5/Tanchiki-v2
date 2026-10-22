extends "res://tests/reel.gd"

# Ролик билда «Владыка бури» для соцсетей: 16:9, с HUD, без надписей поверх.
# Запуск: godot --path . --write-movie <out.avi> res://tests/lightning_reel.tscn
# В лог печатается кадр начала ролика (REEL_START_FRAME) — до него идёт разгон, его обрезают.

const RW := 1920
const RH := 1080
const SHOW_FRAMES := 60 * 23
const VIEW := Vector2i(1280, 720)

func _ready() -> void:
	await _setup_wide()
	await _lightning_build()
	_teardown()

func _setup_wide() -> void:
	process_priority = 1000
	_had_profile = FileAccess.file_exists(PROFILE_PATH)
	if _had_profile:
		_profile_backup = FileAccess.get_file_as_bytes(PROFILE_PATH)
	Sets.display_mode = Sets.MODE_WINDOWED
	Sets.resolution = Vector2i(RW, RH)
	Sets.apply_video()
	var win := get_window()
	win.size = Vector2i(RW, RH)
	_original_lang = I18n.lang
	lang = "en"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			lang = a.substr(7)
	I18n.set_lang(lang)
	Sets.weather_effects = true
	Sets.weather_intensity = 1.0
	Sets.killcam = false
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	win.size = Vector2i(RW, RH)
	# Мир рисуется в базовом 1280×720 и растягивается — иначе на 1080p видно полкарты и танки мелкие.
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_size = VIEW
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_build_overlay()
	await _frames(3)

func _live() -> void:
	if game.world == null:
		return
	_skip_perks()
	for p in game.players:
		if p.tank != null:
			p.tank.alive = true
			p.tank.hp = p.tank.max_hp
		p.damage_flash = 0
	# Ботам перки не даём: иначе у них появляются свои молнии и огонь, и ролик теряет фокус на билде.
	for t in game.world.tanks:
		if t.is_bot and not t.perk_ids.is_empty():
			t.perk_ids.clear()
			t.recompute()
	_park_noisy_bots()
	game.hud.show_hud()

# Огнемётчики, миномёты, «Громовержцы» и боссы перетягивают внимание своими эффектами —
# в кадре оставляем только обычные танки, их уводим в дальний угол карты.
const CALM_TYPES := ["grunt", "scout", "heavy", "sniper"]

var _parked := {}

func _park_noisy_bots() -> void:
	var map = game.world.map
	var t0 = game.players[0].tank
	# Дальний от игрока угол карты, но только на свободных клетках — никаких танков внутри стен.
	var far_r: float = 2.0 if t0.y > map.rows * Cfg.TILE * 0.5 else map.rows - 8.0
	var far_c: float = 2.0 if t0.x > map.cols * Cfg.TILE * 0.5 else map.cols - 8.0
	var area := {"r0": far_r, "r1": far_r + 6.0, "c0": far_c, "c1": far_c + 6.0}
	for t in game.world.tanks:
		if not t.is_bot or not t.alive or CALM_TYPES.has(String(t.enemy_type.get("id", "grunt"))):
			continue
		if _parked.get(t.id, -1) == t.deaths:
			continue
		var spot: Vector2 = map.find_free_spot(game.world.rng, area, TankArt.MAX_COLLIDE_W, TankArt.MAX_COLLIDE_H)
		if spot != Vector2.INF:
			t.x = spot.x
			t.y = spot.y
		_parked[t.id] = t.deaths

# Подтягивает обычных ботов к игроку. В отличие от reel._pull_enemies ставит их
# только на свободные клетки рядом с нужной точкой, а не куда попало (в том числе в стены).
func _gather(count: int, radius: float) -> void:
	var map = game.world.map
	var t0 = game.players[0].tank
	var near := []
	for t in game.world.tanks:
		if t.is_bot and t.alive and t.team != t0.team and CALM_TYPES.has(String(t.enemy_type.get("id", "grunt"))):
			near.append([Vector2(t.x - t0.x, t.y - t0.y).length(), t])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(count, near.size()):
		var t = near[i][1]
		var ang := TAU * float(i) / float(maxi(1, count)) + 0.6
		var want := Vector2(t0.x + cos(ang) * radius, t0.y + sin(ang) * radius * 0.6)
		var r := want.y / Cfg.TILE
		var c := want.x / Cfg.TILE
		var spot: Vector2 = map.find_free_spot(game.world.rng, {"r0": r - 2.0, "r1": r + 2.0, "c0": c - 2.0, "c1": c + 2.0},
			TankArt.MAX_COLLIDE_W, TankArt.MAX_COLLIDE_H)
		if spot == Vector2.INF:
			continue
		t.x = spot.x
		t.y = spot.y
		t.spawn_protect = 0

func _lightning_build() -> void:
	await _start("ffa", "city", "clear", "dusk", 7202)
	game.hud.show_hud()
	var p = game.players[0]
	# Спавн бывает у края карты — тогда камера упирается в границу и бой уезжает к краю кадра.
	var map = game.world.map
	var mid: Vector2 = map.find_free_spot(game.world.rng, {"r0": map.rows * 0.4, "r1": map.rows * 0.6,
		"c0": map.cols * 0.4, "c1": map.cols * 0.6}, TankArt.MAX_COLLIDE_W, TankArt.MAX_COLLIDE_H)
	if mid != Vector2.INF:
		p.tank.x = mid.x
		p.tank.y = mid.y
	p.equip_perk("lightning_lord")
	p.equip_perk("sky_strike")
	for t in game.world.tanks:
		if t.is_bot:
			print("BOT ", t.name, " ", t.enemy_type.get("id", "?"))
	_gather(4, 260.0)
	for i in 90:
		_live()
		await _frames(1)

	print("REEL_START_FRAME=", Engine.get_frames_drawn())
	for i in 70:
		_live()
		await _frames(1)
	# Третий перк берётся «как в игре» — с сообщением в ленте и вызовом вечной грозы.
	game._on_perk_chosen(p, "chain_lightning")
	for i in SHOW_FRAMES - 70:
		_live()
		if i % 200 == 40:
			_gather(4, 230.0)
		await _frames(1)
	print("REEL_END_FRAME=", Engine.get_frames_drawn())
	await _end_match()
