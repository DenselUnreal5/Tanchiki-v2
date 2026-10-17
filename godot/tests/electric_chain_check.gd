extends Node

class ChainSample extends WorldView:
	func _ready() -> void:
		pass
	func _draw() -> void:
		_view = Rect2(0, 0, 320, 180)
		view_off = Vector2.ZERO
		_draw_electric_arcs()

var failures := 0
var sample: ChainSample
var viewport: SubViewport

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("  ", "OK: " if ok else "FAIL: ", label)

func _capture() -> Image:
	sample.queue_redraw()
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This visual check requires a graphics display")
		get_tree().quit(2)
		return
	var player := PlayerState.new(0, "Test", "p1", Ctl.KeyboardAimScheme.new())
	player.reset_for_match()
	var level := LevelGen.generate(1, "ffa", 5151, "city")
	var world := World.new({"map": level.map, "level": level, "mode": "ffa",
		"difficulty": "medium", "players": [player], "rng_seed": 5151})
	world.map.fill(Cfg.T_EMPTY)
	world.tanks = [player.tank]
	var attacker: Tank = player.tank
	attacker.x = 20
	attacker.y = 90
	attacker.spawn_protect = 0
	var target: Tank = world._spawn_bot("enemy", "enemy", "grunt")
	target.x = 160
	target.y = 90
	target.spawn_protect = 0
	target.brain = null
	var hp := target.hp
	world._chain_lightning(100, 90, attacker, {})
	_check(target.hp < hp and world.electric_arcs.size() == 1, "lightning damage creates a visible link")
	_check(world.electric_arcs[0].start == Vector2(100, 90) and world.electric_arcs[0].end == Vector2(160, 90), "link joins actual hit positions")
	world.electric_arcs.clear()
	var source: Tank = world._spawn_bot("enemy", "enemy", "grunt")
	source.x = 100
	source.y = 90
	source.spawn_protect = 0
	var hit := world.shock_arc(source, attacker, 1.0)
	_check(hit.has(target) and world.electric_arcs.size() == 1, "shock chain creates a link and still hits the target")
	var state := world.rng.state
	var points := ElectricGlow.link_points(Vector2(20, 30), Vector2(290, 140), 42)
	_check(points == ElectricGlow.link_points(Vector2(20, 30), Vector2(290, 140), 42), "paused geometry is deterministic")
	for p in points:
		_check(p == p.round(), "vertices follow pixel grid")
	_check(world.rng.state == state, "geometry preserves gameplay RNG")
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	sample = ChainSample.new()
	sample.world = world
	viewport.add_child(sample)
	world.electric_arcs.clear()
	world.add_electric_arc(Vector2(-30, 90), Vector2(350, 90))
	var saved_reduce := Sets.reduce_flashes
	Sets.reduce_flashes = false
	var first := await _capture()
	if "--capture-chain" in OS.get_cmdline_user_args():
		first.save_png("user://electric_chain.png")
	var repeat := await _capture()
	_check(first.get_data() == repeat.get_data(), "paused rendering stays stable")
	var blue := 0
	var yellow := 0
	for y in first.get_height():
		for x in first.get_width():
			var c := first.get_pixel(x, y)
			if c.a < 0.04: continue
			if c.b > c.r * 1.2 and c.b > c.g: blue += 1
			if c.r > 0.6 and c.g > 0.5 and c.b < c.r * 0.85: yellow += 1
	_check(blue > 0 and yellow > 0, "offscreen endpoints still draw blue halo and yellow core")
	Sets.reduce_flashes = true
	var reduced := await _capture()
	_check(reduced.get_data() != first.get_data() and not reduced.is_invisible(), "reduced flashes attenuate but retain combat link")
	_check(world.rng.state == state, "rendering preserves gameplay RNG")
	Sets.reduce_flashes = saved_reduce
	world.tick += 12
	world._expire_shot_effects()
	_check(world.electric_arcs.is_empty(), "link expires after 12 ticks")
	var expired := await _capture()
	_check(expired.is_invisible(), "expired link disappears")
	for i in 150:
		world.add_electric_arc(Vector2.ZERO, Vector2.ONE)
	_check(world.electric_arcs.size() == 128, "link count stays bounded")
	world.step_cosmetic()
	_check(world.electric_arcs.size() == 128, "cosmetic update retains fresh links")
	world.tick += 12
	world.step_cosmetic()
	_check(world.electric_arcs.is_empty(), "cosmetic update also expires links")
	world.add_electric_arc(Vector2.ZERO, Vector2.ONE)
	world.dispose()
	_check(world.electric_arcs.is_empty(), "cleanup removes links")
	print("=== ELECTRIC CHAIN: failures: %d ===" % failures)
	get_tree().quit(1 if failures else 0)
