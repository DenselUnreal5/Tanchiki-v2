extends Node

class Sample extends WorldView:
	var case_name := "acid"
	var preview := false
	func _ready() -> void:
		pass
	func _draw() -> void:
		_view = Rect2(0, 0, 320, 220)
		view_off = Vector2.ZERO
		if preview:
			for r in 7:
				for c in 10:
					draw_texture_rect(TerrainTextures.grass("city"), Rect2(c * 32, r * 32, 32, 32), false)
			draw_rect(Rect2(0, 0, 320, 25), Color("#17231e", 0.9))
			draw_string(Fonts.bold, Vector2(10, 18), case_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e5e8d5"))
		if case_name == "acid":
			_draw_acid_pools()
		elif case_name in ["waves", "blast", "freeze", "synergy", "emp"]:
			_draw_shockwaves()
		elif case_name == "wreck":
			_draw_wrecks()
		elif case_name in ["artillery", "airstrike"]:
			_draw_bullets()
		elif case_name == "generator":
			_draw_power_generators()
		elif case_name == "lights":
			_lamps_ready = true
			_lamps = [Vector2(160, 110)]
			_draw_lamp_light(1.0)
			draw_texture_rect(PixelFx.glow_texture(), Rect2(120, 70, 80, 80), false, Color("#f2ce7c", 0.4))
		elif case_name == "scorches":
			_draw_scorches()
		else:
			var tank: Tank = world.tanks[0]
			if case_name in ["rammer", "spin"]:
				_draw_rammer_telegraph(tank)
				_draw_rammer_spin(tank)
				_draw_rammer_meltdowns()
			elif case_name == "chimera":
				_draw_chimera_telegraph(tank)
			elif case_name == "laser":
				_draw_aim_laser(tank)
				_draw_sniper_laser(tank)
			else:
				_draw_tank(tank)

var failures := 0
var sample: Sample
var viewport: SubViewport
var world: World
var tank: Tank
var gallery := Image.create(1280, 1540, false, Image.FORMAT_RGBA8)

func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("  ", "OK: " if ok else "FAIL: ", label)

func _capture() -> Image:
	sample.queue_redraw()
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _reset() -> void:
	tank.spawn_protect = 0
	tank.shield_hp = 0
	tank.turbo_timer = 0
	tank.dash_invuln_ticks = 0
	tank.ability_timer = 0
	tank.shadow_timer = 0
	tank.is_chimera_clone = false
	tank.is_chimera_boss = false
	tank.is_rammer_boss = false
	tank.sniper_laser_ticks = 0
	world.rammer_meltdowns.clear()
	world.airstrikes.clear()

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This visual check requires a graphics display")
		get_tree().quit(2)
		return
	var player := PlayerState.new(0, "FX", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, "ffa", 5151, "city")
	world = World.new({"map": level.map, "level": level, "mode": "ffa",
		"difficulty": "medium", "players": [player], "rng_seed": 5151})
	world.map.fill(Cfg.T_EMPTY)
	world.tanks = [player.tank]
	tank = player.tank
	tank.x = 160
	tank.y = 110
	tank.turret_angle = 0.2
	world.tick = 90
	world.acid_pools = [Ent.AcidPool.new(160, 110, 38, tank, 360)]
	world.wrecks = [Ent.Wreck.new(tank, world.rng)]
	world.scorches = [Vector2(160, 110)]
	world.power_generators = [Ent.PowerGenerator.new(160, 110)]
	var bullet := Ent.Bullet.new(160, 110, 0.2, tank)
	bullet.x = 160
	bullet.y = 110
	bullet.vx = 3
	bullet.vy = 1
	bullet.lobbed = true
	bullet.has_dest = true
	bullet.dest_x = 230
	bullet.dest_y = 110
	world.bullets = [bullet]
	world.tank_grid.rebuild(world.tanks)
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 220)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	sample = Sample.new()
	sample.world = world
	sample.player = player
	viewport.add_child(sample)
	var saved_quality := Sets.fx_quality
	var saved_flashes := Sets.reduce_flashes
	var cases := ["acid", "waves", "blast", "freeze", "synergy", "emp", "wreck", "shield", "turbo", "dash", "smoke", "overclock", "breaker", "grip", "boss_barrage", "rammer", "spin", "chimera", "artillery", "airstrike", "laser", "generator", "clone", "shadow", "lights", "scorches"]
	for index in cases.size():
		_reset()
		var kind: String = cases[index]
		sample.case_name = kind
		world.tick = 90
		world.shockwaves.clear()
		match kind:
			"waves": world.spawn_shockwave(160, 110, 80, "acid", Color("#93ad50"), 24); world.shockwaves[0].life = 18
			"blast", "freeze", "synergy", "emp":
				world.spawn_shockwave(160, 110, 80, kind, Color("#7ab4c7") if kind in ["freeze", "emp"] else Color("#d9a95c"), 24)
				world.shockwaves[0].life = 18
			"overclock", "breaker", "grip", "boss_barrage": tank.ability_id = kind; tank.ability_timer = 30
			"spin": tank.is_rammer_boss = true; tank.rammer_state = "spin"; tank.rammer_spin_ticks = 30
			"airstrike":
				var rocket := Ent.StrikeRocket.new(tank, tank, world)
				rocket.x = 160; rocket.y = 110; rocket.vx = 2; rocket.vy = 3
				world.airstrikes = [rocket]
			"shield": tank.shield_hp = 30; tank.spawn_protect = 40
			"turbo": tank.turbo_timer = 30
			"dash": tank.dash_invuln_ticks = 15; tank.dash_dir = Vector2.RIGHT
			"smoke": tank.ability_id = "smoke"; tank.ability_timer = 30
			"rammer":
				tank.is_rammer_boss = true
				tank.rammer_state = "telegraph"
				tank.rammer_telegraph_ticks = 15
				world.rammer_meltdowns = [{"x": 160.0, "y": 110.0, "ticks": 45, "max_ticks": 90}]
			"chimera":
				tank.is_chimera_boss = true
				tank.chimera_stream_warmup_ticks = 15
				tank.chimera_stream_target_point = Vector2(290, 170)
			"laser": tank.sniper_laser_ticks = 12
			"clone": tank.is_chimera_clone = true
			"shadow": tank.shadow_timer = 30
		Sets.fx_quality = 2
		Sets.reduce_flashes = false
		var state := world.rng.state
		var hp := tank.hp
		var pool_timer: int = world.acid_pools[0].timer
		var first := await _capture()
		_check(not first.is_invisible(), kind + ": visible")
		var repeat := await _capture()
		_check(first.get_data() == repeat.get_data(), kind + ": stable while paused")
		if "--capture-fx" in OS.get_cmdline_user_args():
			sample.preview = true
			var preview := await _capture()
			gallery.blit_rect(preview, Rect2i(0, 0, 320, 220), Vector2i((index % 4) * 320, (index / 4) * 220))
			sample.preview = false
		world.tick += 9
		if kind in ["acid", "wreck", "smoke", "dash", "clone", "shadow", "chimera", "rammer", "laser"]:
			# Dash is a directional cue; its lifetime, not world tick, controls fading.
			if kind == "dash": tank.dash_invuln_ticks = 7
			var animated := await _capture()
			_check(animated.get_data() != first.get_data(), kind + ": animates")
		Sets.fx_quality = 0
		Sets.reduce_flashes = true
		var low := await _capture()
		_check(not low.is_invisible(), kind + ": retains cue at low FX/reduced flashes")
		_check(world.rng.state == state and tank.hp == hp and world.acid_pools[0].timer == pool_timer, kind + ": drawing preserves simulation")
	world.acid_pools[0].timer = 0
	sample.case_name = "acid"
	_check((await _capture()).is_invisible(), "expired acid pool disappears")
	_check(AcidPoolFx._textures.size() == 4, "pool artwork cache stays bounded")
	Sets.fx_quality = saved_quality
	Sets.reduce_flashes = saved_flashes
	if "--capture-fx" in OS.get_cmdline_user_args(): gallery.save_png("user://combat_fx.png")
	world.dispose()
	print("=== COMBAT FX: failures: %d ===" % failures)
	get_tree().quit(1 if failures else 0)
