extends Node

class Sample extends WorldView:
	var tank: Tank
	var effect_only := true
	func _ready() -> void:
		pass
	func _draw() -> void:
		_view = Rect2(0, 0, 176, 176)
		view_off = Vector2.ZERO
		if effect_only:
			draw_set_transform(Vector2(88, 88))
			TankBuildFx.draw_underlay(self, tank, world.tick, Sets.flash_scale(), Sets.fx_quality)
			TankBuildFx.draw(self, tank, world.tick, Sets.flash_scale(), Sets.fx_quality)
		else:
			_draw_tanks()

var failures := 0
var viewport: SubViewport
var sample: Sample

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)

func capture(tick: int) -> Image:
	sample.world.tick = tick
	sample.queue_redraw()
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("tank_build_visual_check requires a graphics display")
		get_tree().quit(2)
		return
	var map := GameMap.new(8, 8)
	map.fill(Cfg.T_GRASS)
	var world := World.new({"map": map, "level": {"seed": 42}, "mode": "ffa", "difficulty": "medium", "players": [], "puppet": true})
	var tank := Tank.new({"x": 88, "y": 88, "team": "enemy", "name": "", "max_hp": 100.0, "speed": 2.0, "fire_rate": 30})
	tank.spawn_protect = 0
	tank.body_angle = -PI / 2
	world.tanks = [tank]
	viewport = SubViewport.new()
	viewport.size = Vector2i(176, 176)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	sample = Sample.new()
	sample.world = world
	sample.tank = tank
	viewport.add_child(sample)
	var quality := Sets.fx_quality
	var reduced := Sets.reduce_flashes
	Sets.fx_quality = 2
	Sets.reduce_flashes = false
	var empty := await capture(120)
	var images := []
	for build in Perks.BUILDS:
		tank.perk_ids = build.perks.duplicate()
		tank.build_fx_started.clear()
		TankBuildFx.sync(tank, 0)
		var rng_before := world.rng.state
		var timers := [tank.hp, tank.burn_ticks, tank.stun_ticks, tank.acid_stacks]
		var started := tank.build_fx_started.duplicate()
		var first := await capture(120)
		check(first.get_data() != empty.get_data(), build.id + ": persistent effect visible after celebration expires")
		var animated := await capture(128)
		check(first.get_data() != animated.get_data(), build.id + ": effect animates")
		var repeat := await capture(120)
		check(first.get_data() == repeat.get_data(), build.id + ": paused frame is stable")
		for previous: Image in images: check(first.get_data() != previous.get_data(), build.id + ": distinct build appearance")
		images.append(first)
		Sets.fx_quality = 0
		Sets.reduce_flashes = true
		var low := await capture(120)
		check(not low.is_invisible(), build.id + ": signal remains on low FX/reduced flashes")
		Sets.fx_quality = 2
		Sets.reduce_flashes = false
		var burst := await capture(12)
		check(burst.get_data() != first.get_data(), build.id + ": completing build adds a temporary celebration")
		check(world.rng.state == rng_before and timers == [tank.hp, tank.burn_ticks, tank.stun_ticks, tank.acid_stacks]
			and started == tank.build_fx_started, build.id + ": drawing preserves RNG, health, statuses and completion time")
		tank.perk_ids.pop_back()
		check((await capture(120)).is_invisible(), build.id + ": incomplete build disappears immediately")
		tank.perk_ids = build.perks.duplicate()
		tank.alive = false
		check((await capture(120)).is_invisible(), build.id + ": no effects on dead tanks")
		tank.alive = true
	# Test the actual WorldView visibility gate, rather than only a drawing helper.
	sample.effect_only = false
	tank.perk_ids = Perks.get_build("stealth_hunter").perks.duplicate()
	var observer := PlayerState.new(0, "Observer", "p1", null)
	observer.tank = Tank.new({"x": -400, "y": -400, "team": "player", "name": "Observer", "max_hp": 100.0, "speed": 2.0, "fire_rate": 30})
	sample.player = observer
	check((await capture(120)).is_invisible(), "hidden enemy build cannot reveal its tank")
	tank.perk_ids.clear()
	tank.build_fx_use_remote = true
	tank.build_fx_remote_ids = ["stealth_hunter"]
	check((await capture(120)).is_invisible(), "remote build cosmetics preserve forest stealth without granting local perks")
	observer.tank.x = 80
	observer.tank.y = 80
	check(not (await capture(120)).is_invisible(), "nearby revealed tank and its build render normally")
	sample.player = null
	tank.build_fx_use_remote = false
	tank.build_fx_remote_ids.clear()
	tank.perk_ids.clear()
	var base_hull := await capture(120)
	tank.perk_ids = Perks.get_build("shock_hunter").perks.duplicate()
	tank.build_fx_started.clear()
	TankBuildFx.sync(tank, 0)
	var build_hull := await capture(120)
	var flank := Rect2i(58, 70, 18, 36)
	check(base_hull.get_region(flank).get_data() != build_hull.get_region(flank).get_data(),
		"actual WorldView draws build arcs beside the hull, independently of overhead perk icons")
	tank.perk_ids.clear()
	for build in Perks.BUILDS:
		for id in build.perks:
			if not tank.perk_ids.has(id): tank.perk_ids.append(id)
	TankBuildFx.sync(tank, 0)
	var combined := await capture(120)
	check(not combined.is_invisible(), "multiple completed builds coexist with readable hull")
	tank.burn_ticks = 90
	tank.acid_stacks = 3
	tank.stun_ticks = 40
	check((await capture(120)).get_data() != combined.get_data(), "negative status effects remain layered above build effects")
	Sets.fx_quality = quality
	Sets.reduce_flashes = reduced
	world.dispose()
	print("=== TANK BUILD VISUALS: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
