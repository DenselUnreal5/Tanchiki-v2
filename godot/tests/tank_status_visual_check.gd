extends Node

class StatusSample extends Node2D:
	var tank: Tank
	var tick := 0
	var detail := 2
	var flash_scale := 1.0

	func _draw() -> void:
		TankStatusFx.draw_underlay(self, tank, tick, detail)
		TankStatusFx.draw(self, tank, tick, flash_scale, detail)

var failures := 0
var sample: StatusSample
var viewport: SubViewport

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("tank_status_visual_check requires a graphics display (X11/Xvfb)")
		get_tree().quit(2)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	sample = StatusSample.new()
	sample.position = Vector2(64, 64)
	sample.tank = Tank.new({"x": 64, "y": 64, "team": "player", "max_hp": 100.0,
		"color_key": "p1", "name": "", "speed": 0.0, "fire_rate": 30})
	sample.tank.body_angle = -PI / 2.0
	viewport.add_child(sample)
	var empty := await _capture(0, 60)
	var images := []
	for flags in [TankStatusFx.BURN, TankStatusFx.ACID, TankStatusFx.SHOCK]:
		var first := await _capture(flags, 60)
		var next := await _capture(flags, 68)
		var repeat := await _capture(flags, 60)
		_check(first.get_data() != empty.get_data(), "status %d draws particles, not just a hull tint" % flags)
		_check(first.get_data() != next.get_data(), "status %d animates" % flags)
		_check(first.get_data() == repeat.get_data(), "status %d is stable when paused" % flags)
		images.append(first)
		var expired := await _capture(0, 60)
		_check(expired.get_data() == empty.get_data(), "status %d disappears immediately on expiry" % flags)
	var mixed := await _capture(7, 60)
	for image: Image in images:
		_check(mixed.get_data() != image.get_data(), "simultaneous statuses retain distinct layers")
	await _capture(TankStatusFx.BURN, 60)
	sample.tank.burn_stacks = 1
	await _frame()
	var light_burn := viewport.get_texture().get_image()
	sample.tank.burn_stacks = 3
	await _frame()
	_check(viewport.get_texture().get_image().get_data() != light_burn.get_data(), "burn stacks increase visible flame intensity")
	await _capture(TankStatusFx.ACID, 60)
	sample.tank.acid_stacks = 1
	await _frame()
	var light_acid := viewport.get_texture().get_image()
	sample.tank.acid_stacks = Cfg.ACID_STACK_MAX
	await _frame()
	_check(viewport.get_texture().get_image().get_data() != light_acid.get_data(), "acid stacks increase visible coating")
	await _capture(7, 60)
	var before := [sample.tank.burn_ticks, sample.tank.burn_stacks, sample.tank.acid_stacks,
		sample.tank.acid_ticks_left, sample.tank.stun_ticks, sample.tank.hp]
	await _frame()
	_check(before == [sample.tank.burn_ticks, sample.tank.burn_stacks, sample.tank.acid_stacks,
		sample.tank.acid_ticks_left, sample.tank.stun_ticks, sample.tank.hp],
		"rendering does not mutate status timers or health")
	sample.detail = 0
	var low := await _capture(7, 60)
	_check(low.get_data() != empty.get_data(), "combat status cues remain visible at low FX quality")
	sample.detail = 2
	sample.flash_scale = 0.2
	var reduced := await _capture(TankStatusFx.SHOCK, 60)
	_check(reduced.get_data() != images[2].get_data(), "reduced flashes attenuate electric glow")
	sample.tank.alive = false
	await _frame()
	_check(viewport.get_texture().get_image().get_data() == empty.get_data(), "no status effects on dead tanks")
	sample.tank.alive = true
	sample.tank.body_angle = PI / 2.0
	var rotated := await _capture(TankStatusFx.ACID, 60)
	_check(rotated.get_data() != images[1].get_data(), "armor coating follows hull rotation")
	print("=== TANK STATUS VISUALS: failures: %d ===" % failures)
	get_tree().quit(1 if failures else 0)

func _capture(flags: int, tick: int) -> Image:
	sample.tank.burn_ticks = 120 if flags & TankStatusFx.BURN else 0
	sample.tank.burn_stacks = 2
	sample.tank.acid_stacks = 3 if flags & TankStatusFx.ACID else 0
	sample.tank.acid_ticks_left = 180
	sample.tank.stun_ticks = 60 if flags & TankStatusFx.SHOCK else 0
	sample.tick = tick
	await _frame()
	return viewport.get_texture().get_image()

func _frame() -> void:
	sample.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
