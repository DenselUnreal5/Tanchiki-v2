extends Node

const W := 540
const H := 960

class Pilot extends RefCounted:
	var rng := Rng.new(9)
	var wander := Vector2(1, 0)
	var stuck := 0
	var last := Vector2.ZERO
	var strafe := 1.0
	var tick := 0

	func hints() -> Array:
		return []

	func apply(tank: Tank, player, world) -> void:
		tick += 1
		var best = null
		var best_d := 520.0
		for t in world.tanks:
			if t == tank or not t.alive or t.team == tank.team:
				continue
			var d := Vector2(t.x - tank.x, t.y - tank.y).length()
			if d < best_d:
				best_d = d
				best = t
		var pos := Vector2(tank.x, tank.y)
		if pos.distance_to(last) < 0.25:
			stuck += 1
		else:
			stuck = 0
		last = pos
		if stuck > 25:
			stuck = 0
			strafe = -strafe
			var a := rng.nextf() * TAU
			wander = Vector2(cos(a), sin(a))
		if tick % 140 == 0:
			strafe = -strafe
		var move := wander
		if best != null:
			var to := Vector2(best.x - tank.x, best.y - tank.y).normalized()
			var side := Vector2(-to.y, to.x) * strafe
			move = (to * (1.0 if best_d > 210.0 else -0.2) + side * 0.8).normalized()
			tank.aim_at(best.x, best.y)
			tank.shoot(world)
		else:
			tank.aim_at(tank.x + wander.x * 100.0, tank.y + wander.y * 100.0)
			if tick % 20 == 0:
				tank.shoot(world)
		tank.thrust(move.x, move.y)
		if tick % 170 == 0:
			tank.dash(move)

const TEXT := {
	"en": {
		"hook1": "BATTLE CITY...", "hook2": "...BUT EVERYTHING EXPLODES",
		"storm": "STORMS THAT FIGHT BACK", "storm_sub": "Lightning hits tanks and walls",
		"base": "HOLD THE BASE", "base_sub": "Wave after wave of armor",
		"perks": "PICK PERKS. STACK BUILDS.",
		"runs": "ROGUELITE RUNS", "runs_sub": "Every match plays differently",
		"line1": "Destructible maps · Bosses", "line2": "Couch co-op · Online battles",
		"cta": "COMING TO STEAM", "follow": "Follow for devlogs",
	},
	"ru": {
		"hook1": "ТАНЧИКИ ИЗ ДЕТСТВА...", "hook2": "...НО ВЗРЫВАЕТСЯ ВСЁ",
		"storm": "ГРОЗА БЬЁТ В ОТВЕТ", "storm_sub": "Молнии попадают в танки и стены",
		"base": "УДЕРЖИ БАЗУ", "base_sub": "Волна за волной бронетехники",
		"perks": "ВЫБИРАЙ ПЕРКИ. СОБИРАЙ БИЛДЫ.",
		"runs": "КАЖДЫЙ БОЙ НОВЫЙ", "runs_sub": "Рогалик с разрушаемыми картами",
		"line1": "Разрушаемые карты · Боссы", "line2": "Кооп вдвоём · Онлайн-бои",
		"cta": "СКОРО В STEAM", "follow": "Подпишись на девлоги",
	},
}

var lang := "en"

func _t(key: String) -> String:
	return String(TEXT[lang][key])

var game: Node
var caption: Label
var sub: Label
var dim: ColorRect
var card: VBoxContainer
var overlay: CanvasLayer

func _ready() -> void:
	Sets.display_mode = Sets.MODE_WINDOWED
	Sets.resolution = Vector2i(W, H)
	Sets.apply_video()
	var win := get_window()
	win.size = Vector2i(W, H)
	win.content_scale_size = Vector2i(W, H)
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var original_lang := I18n.lang
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			lang = a.substr(7)
	if not TEXT.has(lang):
		lang = "en"
	I18n.set_lang(lang)
	Sets.weather_effects = true
	Sets.weather_intensity = 1.0
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	win.min_size = Vector2i(320, 320)
	win.size = Vector2i(W, H)
	_build_overlay()
	await _frames(3)

	await _city_chaos()
	await _storm()
	await _defense()
	await _perks()
	await _end_card()

	I18n.set_lang(original_lang)
	get_tree().quit()

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	overlay = layer
	dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	caption = _big_label(46)
	caption.position = Vector2(20, 120)
	layer.add_child(caption)
	sub = _big_label(26)
	sub.position = Vector2(20, 250)
	sub.add_theme_color_override("font_color", Color("#ffd54a"))
	layer.add_child(sub)
	card = VBoxContainer.new()
	card.position = Vector2(0, 300)
	card.size = Vector2(W, 400)
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.visible = false
	layer.add_child(card)

func _big_label(size: int) -> Label:
	var l := Label.new()
	l.size = Vector2(W - 40, 120)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", Fonts.bold)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 12)
	l.pivot_offset = l.size / 2.0
	return l

func _say(text: String, small: String = "") -> void:
	caption.text = text
	sub.text = small
	for l in [caption, sub]:
		l.scale = Vector2(1.35, 1.35)
		l.modulate.a = 0.0
		var tw := create_tween().set_parallel()
		tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(l, "modulate:a", 1.0, 0.12)

func _start(mode: String, location: String, weather: String, daytime: String, seed_value: int) -> void:
	var s: Dictionary = game.ui.settings
	s["mode"] = mode
	s["game_type"] = "single"
	s["location"] = location
	s["weather"] = weather
	s["daytime"] = daytime
	s["level"] = 2
	s["seed"] = seed_value
	s["difficulty"] = "medium"
	caption.text = ""
	sub.text = ""
	game.start_match()
	_skip_perks()
	var p = game.players[0]
	p._auto_pad_scheme = null
	p._auto_kbm_scheme = null
	p._auto_touch_scheme = null
	p.scheme = Pilot.new()
	game.hud.hide_hud()

func _skip_perks() -> void:
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

func _end_match() -> void:
	game.to_menu()
	await _frames(1)

func _pin_overlay() -> void:
	overlay.offset = Vector2.ZERO
	overlay.scale = Vector2.ONE
	overlay.rotation = 0.0
	caption.position = Vector2(20, 120)
	sub.position = Vector2(20, 250)

func _keep_alive() -> void:
	if game.world == null:
		return
	_skip_perks()
	for p in game.players:
		if p.tank != null:
			p.tank.alive = true
			p.tank.hp = maxf(p.tank.hp, p.tank.max_hp * 0.6)
		p.damage_flash = 0
	game.hud.hide_hud()

func _pull_enemies(count: int, radius: float) -> void:
	var t0 = game.players[0].tank
	var near := []
	for t in game.world.tanks:
		if t.is_bot and t.alive and t.team != t0.team:
			near.append([Vector2(t.x - t0.x, t.y - t0.y).length(), t])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(count, near.size()):
		var t = near[i][1]
		var ang := TAU * float(i) / float(maxi(1, count)) + 0.6
		t.x = t0.x + cos(ang) * radius * 0.7
		t.y = t0.y + sin(ang) * radius
		t.spawn_protect = 0

func _blast_bricks(radius_tiles: int, every: int) -> void:
	var world = game.world
	var t0 = game.players[0].tank
	var map = world.map
	var cr: int = map.row_at(t0.y)
	var cc: int = map.col_at(t0.x)
	var n := 0
	for dr in range(-radius_tiles * 2, radius_tiles * 2 + 1):
		for dc in range(-radius_tiles, radius_tiles + 1):
			var r := cr + dr
			var c := cc + dc
			if map.get_tile(r, c) != Cfg.T_BRICK:
				continue
			n += 1
			if n % every != 0:
				continue
			var mat := Materials.at(r, c)
			world.hit_building(r, c, float(mat["hp"]) * 1.6, "blast",
				c * Cfg.TILE + 16.0, r * Cfg.TILE + 16.0, null)
			return

func _city_chaos() -> void:
	await _start("ffa", "city", "clear", "day", 7101)
	_pull_enemies(4, 230.0)
	_say(_t("hook1"))
	for i in 60:
		_keep_alive()
		if i % 6 == 0:
			_blast_bricks(5, 3 + i % 4)
		await _frames(1)
	_say(_t("hook2"))
	for i in 90:
		_keep_alive()
		if i % 4 == 0:
			_blast_bricks(6, 2 + i % 5)
		if i == 30:
			_pull_enemies(3, 200.0)
		await _frames(1)
	await _end_match()

func _storm() -> void:
	await _start("ffa", "city", "storm", "night", 7202)
	_pull_enemies(4, 240.0)
	_say(_t("storm"), _t("storm_sub"))
	for i in 150:
		_keep_alive()
		if i % 9 == 2:
			var t = game.players[0].tank
			var a := float(i) * 1.7
			game.world.strike_lightning(t.x + cos(a) * 150.0, t.y + sin(a) * 220.0)
		await _frames(1)
	await _end_match()

func _defense() -> void:
	await _start("defense", "dust", "clear", "dusk", 7303)
	game.world.wave_timer = 1
	await _frames(3)
	_pull_enemies(7, 260.0)
	_say(_t("base"), _t("base_sub"))
	for i in 165:
		_keep_alive()
		if i == 60:
			_pull_enemies(6, 240.0)
		if i == 100:
			game.world.trigger_airstrike(game.players[0])
		await _frames(1)
	await _end_match()

func _perks() -> void:
	await _start("ffa", "jungle", "rain", "day", 7404)
	_pull_enemies(3, 230.0)
	await _frames(20)
	var p = game.players[0]
	var k := float(W) / 1000.0
	game.ui.scale = Vector2(k, k)
	game.ui.size = Vector2(W, H) / k
	game.ui.show_perk_select(p, 0, Rng.new(11))
	_say(_t("perks"))
	for i in 75:
		await _frames(1)
	game.ui.hide_perk_select()
	game._apply_ui_scale()
	p.perk_ids.append("nitro")
	p.tank.recompute()
	_say(_t("runs"), _t("runs_sub"))
	for i in 75:
		_keep_alive()
		await _frames(1)
	await _end_match()

func _end_card() -> void:
	await _start("ffa", "frost", "snow", "day", 7505)
	_pull_enemies(3, 230.0)
	caption.text = ""
	sub.text = ""
	var tw := create_tween()
	tw.tween_property(dim, "color:a", 0.78, 0.4)
	card.visible = true
	for c in card.get_children():
		c.queue_free()
	var title := _big_label(64)
	title.text = "IRON STORM"
	title.custom_minimum_size = Vector2(W, 90)
	card.add_child(title)
	var tag := _big_label(24)
	tag.text = "BATTLE TANKS"
	tag.add_theme_color_override("font_color", Color("#9fe3c7"))
	tag.custom_minimum_size = Vector2(W, 40)
	card.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	card.add_child(gap)
	for line in [_t("line1"), _t("line2")]:
		var l := _big_label(26)
		l.text = line
		l.custom_minimum_size = Vector2(W, 44)
		card.add_child(l)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 40)
	card.add_child(gap2)
	var cta := _big_label(34)
	cta.text = _t("cta")
	cta.add_theme_color_override("font_color", Color("#ffd54a"))
	cta.custom_minimum_size = Vector2(W, 56)
	card.add_child(cta)
	var follow := _big_label(24)
	follow.text = _t("follow")
	follow.custom_minimum_size = Vector2(W, 40)
	card.add_child(follow)
	for i in 120:
		_keep_alive()
		await _frames(1)
	await _end_match()

func _frames(n: int) -> void:
	for i in n:
		_pin_overlay()
		await get_tree().process_frame
