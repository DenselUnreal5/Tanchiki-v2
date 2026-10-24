extends Node

# Deterministic training-room demonstrations, using the real Tank/World logic.
# --perk=<id> --frames=450 --dump=<json> ; record with --write-movie <out.avi>
const IDS := ["rapid_fire", "heavy_armor", "sprinter", "regen", "quick_vent"]
const WIDTH := 1080
const HEIGHT := 1920
var perk_id := "rapid_fire"
var frame := 0
var total_frames := 450
var lanes: Array = []
var canvas: CanvasItem
var dump_path := ""
var telemetry_path := ""
var telemetry: Array = []

class Controls extends RefCounted:
	var kind := ""
	var tick := 0
	func apply(tank: Tank, _player, world: World) -> void:
		if kind in ["rapid_fire", "regen"]:
			tank.aim_at(382, 80)
			if tick % 300 < 240: tank.shoot(world)
		elif kind == "sprinter":
			tank.aim_at(420, 80)
			if tank.x < 374: tank.thrust(1, 0)
		elif kind == "quick_vent":
			tank.aim_at(382, 80)
			if tank.shots_fired == 0 and not tank.overheated: tank.shoot(world)

class Lane extends WorldView:
	var actor: Tank
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		shot_fx = ShotFx.new()
		shot_fx.view = self
		add_child(shot_fx)
	func _draw() -> void:
		view_off = Vector2.ZERO
		_view = Rect2(0, 0, 448, 160)
		draw_set_transform(Vector2.ZERO)
		_draw_tiles()
		_draw_scorches()
		if (actor.owner.scheme as Controls).kind == "sprinter":
			for y in range(32, 128, 8):
				draw_rect(Rect2(374, y, 4, 8), Color("#d9dfd0") if y % 16 == 0 else Color("#1e2b32"))
		_draw_wrecks()
		_draw_tanks()
		_draw_bullets()
		_draw_particles()
		_draw_shockwaves()

class Chrome extends Node2D:
	var reel
	func _process(_delta: float) -> void: queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1080, 1920), Color("#0b1219"))
		for x in range(0, 1080, 48): draw_line(Vector2(x, 0), Vector2(x, 1920), Color(0.22, 0.40, 0.48, 0.08))
		for y in range(0, 1920, 48): draw_line(Vector2(0, y), Vector2(1080, y), Color(0.22, 0.40, 0.48, 0.08))
		var accent := Color("#c7df83")
		draw_line(Vector2(64, 156), Vector2(1016, 156), Color(accent, 0.5), 2)
		draw_style_box(UiKit.flat(Color("#172329"), 18, 2, Color(accent, 0.6)), Rect2(64, 208, 152, 152))
		var icon := UiIconArt.texture_of(reel.perk_id)
		draw_texture_rect(icon, Rect2(76, 220, 128, 128), false)
		draw_style_box(UiKit.flat(Color("#213225"), 14, 1, Color(accent, 0.4)), Rect2(64, 396, 952, 76))
		for i in 2:
			var y := 532 + i * 424
			draw_style_box(UiKit.flat(Color("#172329"), 16, 2, Color(accent if i == 1 else Color("#708491"), 0.7)), Rect2(54, y, 972, 400))
			var t: Tank = reel.lanes[i].actor
			var metric := ""
			if reel.perk_id in ["heavy_armor", "regen"]: metric = "%d / %d HP" % [maxi(0, int(t.hp)), int(t.max_hp)]
			elif reel.perk_id == "sprinter": metric = "%d%%" % int(round(t.speed / Cfg.PLAYER_SPEED * 100))
			else: metric = "%d" % t.shots_fired
			draw_string(Fonts.bold, Vector2(790, y + 44), metric, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color("#eff4e7"))
			if reel.perk_id in ["rapid_fire", "quick_vent"]:
				draw_rect(Rect2(90, y + 385, 900, 8), Color("#26333b"))
				draw_rect(Rect2(90, y + 385, 900 * t.heat, 8), Color("#f49561") if t.overheated else Color("#dfc77a"))
				if reel.perk_id == "quick_vent" and not t.overheated:
					draw_circle(Vector2(990, y + 27), 9, Color("#a8dd82"))
		# Progress remains inside the social-video safe area.
		draw_rect(Rect2(64, 1732, 952, 4), Color("#2b3943"))
		draw_rect(Rect2(64, 1732, 952 * float(reel.frame) / reel.total_frames, 4), accent)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perk="): perk_id = arg.substr(7)
		elif arg.begins_with("--frames="): total_frames = int(arg.substr(9))
		elif arg.begins_with("--dump="): dump_path = arg.substr(7)
		elif arg.begins_with("--telemetry="): telemetry_path = arg.substr(12)
	assert(IDS.has(perk_id))
	I18n.lang = "en"
	Sets.day_night = false
	Sets.weather_effects = false
	Sets.reduce_flashes = true
	Sets.fx_quality = 2
	var win := get_window()
	win.min_size = Vector2i(320, 320)
	win.size = Vector2i(WIDTH, HEIGHT)
	win.content_scale_size = Vector2i(WIDTH, HEIGHT)
	var chrome := Chrome.new()
	chrome.reel = self
	add_child(chrome)
	for i in 2:
		var map := GameMap.new(14, 5)
		map.fill(Cfg.T_GRASS)
		for c in map.cols:
			map.set_tile(0, c, Cfg.T_WALL)
			map.set_tile(4, c, Cfg.T_WALL)
		var controls := Controls.new()
		controls.kind = perk_id
		var p := PlayerState.new(i, "", "p1" if i == 0 else "p2", controls)
		if i == 1: p.perk_ids = [perk_id]
		var world := World.new({"map": map, "level": {"seed": 2026, "location": "city", "areas": {"any": {"r0":1,"r1":3,"c0":1,"c1":12}}}, "mode": "tutorial", "players": [], "puppet": true, "rng_seed": 9})
		var actor := Tank.new({"x": 72, "y": 80, "team": "player", "name": "", "owner": p,
			"color_key": p.color_key, "class_id": "standard", "chassis": "standard", "max_hp": 100,
			"speed": Cfg.PLAYER_SPEED, "fire_rate": Cfg.PLAYER_FIRE_RATE, "dmg_scale": Cfg.PLAYER_DMG_MULT})
		p.tank = actor
		actor.spawn_protect = 0
		actor.angle = 0
		actor.body_angle = 0
		actor.turret_angle = 0
		var target := Tank.new({"x": 382, "y": 80, "team": "enemy", "name": "", "color_key": "enemy", "max_hp": 10000, "speed": 0.0, "fire_rate": 60})
		target.spawn_protect = 0
		target.turret_angle = PI
		target.body_angle = PI
		if perk_id == "sprinter": target.x = 9999
		world.tanks = [actor, target]
		var lane := Lane.new()
		lane.actor = actor
		lane.player = p
		lane.world = world
		lane.position = Vector2(92, 594 + i * 424)
		lane.scale = Vector2.ONE * 2.0
		add_child(lane)
		lanes.append(lane)
		_reset(lane)
	if not dump_path.is_empty(): _dump()
	print("PERK MOVIE START ", perk_id, " level=", Perks.unlock_level_of(perk_id))

func _reset(lane: Lane) -> void:
	var t := lane.actor
	t.alive = true
	t.hp = t.max_hp
	t.x = 72
	t.y = 80
	t.vx = 0
	t.vy = 0
	t.heat = 0
	t.overheated = false
	t.fire_cooldown = 0
	t.shots_fired = 0
	t.regen_accum = 0
	lane.world.bullets.clear()
	lane.world.wrecks.clear()
	if perk_id == "regen": t.hp = 50
	if perk_id == "quick_vent":
		t.heat = 1.0
		t.overheated = true

func _process(_delta: float) -> void:
	if lanes.is_empty(): return
	for step in 2:
		var tick := frame * 2 + step
		for lane in lanes:
			if perk_id in ["sprinter", "quick_vent"] and tick > 0 and tick % 300 == 0: _reset(lane)
			if perk_id == "heavy_armor" and tick > 0 and tick % 420 == 0: _reset(lane)
			(lane.actor.owner.scheme as Controls).tick = tick
			var target: Tank = lane.world.tanks[1]
			if perk_id == "heavy_armor" and lane.actor.alive:
				target.aim_at(lane.actor.x, lane.actor.y)
				target.shoot(lane.world)
			lane.world.step()
			lane.world.perk_drops.clear()
			lane.queue_redraw()
	var values := []
	for lane in lanes:
		var t: Tank = lane.actor
		values.append({"hp": t.hp, "max_hp": t.max_hp, "heat": t.heat, "overheated": t.overheated, "shots": t.shots_fired, "x": t.x})
	telemetry.append({"frame": frame, "lanes": values})
	frame += 1
	if frame % 60 == 0: print("PERK MOVIE FRAME ", perk_id, " ", frame, "/", total_frames)
	if frame >= total_frames:
		if not telemetry_path.is_empty():
			var file := FileAccess.open(telemetry_path, FileAccess.WRITE)
			file.store_string(JSON.stringify(telemetry))
		get_tree().quit()

func _dump() -> void:
	var data := []
	for id in IDS:
		var perk := Perks.get_perk(id)
		var item := {"id": id, "level": Perks.unlock_level_of(id), "mods": perk.get("mods", {}), "texts": {}}
		for language in ["ru", "en", "fr", "es"]:
			I18n.lang = language
			item.texts[language] = {"name": I18n.dn(perk, "name", "perk"), "description": I18n.dn(perk, "desc", "perk")}
		data.append(item)
	I18n.lang = "en"
	var file := FileAccess.open(dump_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
