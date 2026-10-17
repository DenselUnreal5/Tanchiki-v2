extends Node

class WeatherSample extends WorldView:
	func _ready() -> void:
		pass

	func _draw() -> void:
		_view = Rect2(0, 0, 512, 320)
		view_off = Vector2.ZERO
		for r in 10:
			for c in 16:
				draw_texture_rect(TerrainTextures.grass("city"), Rect2(c * 32, r * 32, 32, 32), false)
		for r in 10:
			draw_texture_rect(TerrainTextures.road(2), Rect2(224, r * 32, 32, 32), false)
		_draw_weather(Vector2(512, 320))
		_draw_bolts()

var failures := 0
var sample: WeatherSample
var viewport: SubViewport

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("weather_visual_check requires a graphics display, e.g. X11/Xvfb")
		get_tree().quit(2)
		return
	var saved := [Sets.weather_effects, Sets.weather_intensity, Sets.day_night, Sets.reduce_flashes]
	Sets.weather_effects = true
	Sets.weather_intensity = 1.0
	Sets.day_night = false
	Sets.reduce_flashes = false
	var level := LevelGen.generate(1, "ffa", 42, "city")
	var map := GameMap.new(16, 10)
	map.fill(Cfg.T_GRASS)
	level["map"] = map
	var world := World.new({"map": map, "level": level, "mode": "ffa",
		"difficulty": "medium", "players": [], "puppet": true})
	viewport = SubViewport.new()
	viewport.size = Vector2i(512, 320)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	sample = WeatherSample.new()
	sample.world = world
	viewport.add_child(sample)
	var fog := WeatherVisuals.fog_texture().diffuse_texture as NoiseTexture2D
	for i in 120:
		if fog.get_image() != null:
			break
		await get_tree().process_frame
	_check(fog.get_image() != null, "shared fog artwork generated")
	var baseline := await _capture("clear", 900)
	var rng_before := world.rng.state
	for condition in ["fog", "rain", "snow", "storm"]:
		var first := await _capture(condition, 900)
		var second := await _capture(condition, 1020)
		_check(first.get_data() != baseline.get_data(), condition + ": visible effect")
		_check(first.get_data() != second.get_data(), condition + ": animated effect")
		var repeat := await _capture(condition, 900)
		_check(first.get_data() == repeat.get_data(), condition + ": deterministic at a fixed tick")
	Sets.weather_effects = false
	var disabled := await _capture("storm", 900)
	_check(disabled.get_data() == baseline.get_data(), "weather toggle removes decorative weather")
	Sets.weather_effects = true
	Sets.weather_intensity = 0.0
	var zero := await _capture("snow", 900)
	_check(zero.get_data() == baseline.get_data(), "zero intensity removes snow and haze")
	Sets.weather_intensity = 1.0
	var normal := await _capture("clear", 900, 1.0)
	Sets.reduce_flashes = true
	var reduced := await _capture("clear", 900, 1.0)
	_check(_brightness(reduced) < _brightness(normal), "reduced flashes lower sky flash brightness")
	Sets.weather_effects = false
	world.bolts.append({"x": 280.0, "y": 240.0, "life": 14, "seed": 77})
	var bolt := await _capture("clear", 900)
	_check(bolt.get_data() != baseline.get_data(), "damaging lightning remains visible with weather disabled")
	Sets.reduce_flashes = false
	var full_bolt := await _capture("clear", 900)
	_check(_has_electric_color(full_bolt, baseline, true), "storm bolt has a blue halo")
	_check(_has_electric_color(full_bolt, baseline, false), "storm bolt has a yellow center")
	_check(world.rng.state == rng_before, "drawing does not advance simulation RNG")
	var points := WeatherVisuals.bolt_points(Vector2(40, 10), Vector2(200, 240), 77)
	for point in points:
		_check(fmod(point.x, 2.0) == 0.0 and fmod(point.y, 2.0) == 0.0, "bolt follows the pixel grid")
	Sets.weather_effects = saved[0]
	Sets.weather_intensity = saved[1]
	Sets.day_night = saved[2]
	Sets.reduce_flashes = saved[3]
	print("=== WEATHER VISUALS: failures: %d ===" % failures)
	get_tree().quit(1 if failures else 0)

func _capture(condition: String, tick: int, flash: float = 0.0) -> Image:
	sample.world.weather = WeatherSystem.new(7, {"condition": condition, "phase": 0.25})
	sample.world.weather.flash = flash
	sample.world.tick = tick
	sample.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _brightness(image: Image) -> float:
	var sum := 0.0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var color := image.get_pixel(x, y)
			sum += color.r + color.g + color.b
	return sum

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _has_electric_color(image: Image, baseline: Image, blue: bool) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			var original := baseline.get_pixel(x, y)
			if Vector3(color.r - original.r, color.g - original.g, color.b - original.b).length() < 0.05:
				continue
			if blue and color.b > color.r * 1.2 and color.b > color.g * 1.05:
				return true
			if not blue and color.r > 0.6 and color.g > 0.5 and color.b < color.r * 0.8 and color.r > color.g * 0.9:
				return true
	return false
