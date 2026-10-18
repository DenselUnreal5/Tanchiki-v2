class_name TankBuildFx
extends RefCounted

const ACTIVATION_TICKS := 48

## Cosmetic state only: completion edges, never RNG, damage, mods or particles.
## Called by world updates, not by drawing (safe for multiple viewports).
static func completed(tank: Tank) -> Array:
	if not tank.build_fx_use_remote:
		return tank.completed_builds()
	var out := []
	for id in tank.build_fx_remote_ids:
		var build := Perks.get_build(String(id))
		if not build.is_empty() and not out.has(build): out.append(build)
	return out

static func has(tank: Tank, build_id: String) -> bool:
	return tank.build_fx_remote_ids.has(build_id) if tank.build_fx_use_remote else tank.has_build(build_id)

static func sync(tank: Tank, tick: int) -> void:
	if not tank.alive: return
	var complete := {}
	for build in completed(tank):
		var id: String = build.id
		complete[id] = true
		if not tank.build_fx_started.has(id): tank.build_fx_started[id] = tick
	for id in tank.build_fx_started.keys():
		if not complete.has(id): tank.build_fx_started.erase(id)

static func active(tank: Tank) -> Array:
	return completed(tank) if tank.alive else []

static func _point(local: Vector2, tank: Tank) -> Vector2:
	return local.rotated(tank.body_angle + PI / 2.0).round()

static func draw_underlay(canvas: CanvasItem, tank: Tank, tick: int, flash_scale: float, detail: int) -> void:
	var builds := active(tank)
	var hw := tank.width * 0.5
	var hh := tank.height * 0.5
	var radius := maxf(hw, hh) + 5
	# Overlapping builds remain legible without stacking opaque glow blankets.
	var strength := 1.0 / sqrt(float(maxi(builds.size(), 1)))
	for build in builds:
		var color: Color = build.color
		var pulse := 0.8 + 0.2 * sin(tick * 0.12 + tank.id)
		match String(build.id):
			"juggernaut":
				for side in [-1, 1]:
					var p := _point(Vector2(side * (hw + 3), hh * 0.3), tank)
					canvas.draw_rect(Rect2(p - Vector2(2, 5), Vector2(4, 10)), Color("#8f432f", 0.35 * strength))
			"fire_hunter":
				for side in [-1, 1]:
					var p := _point(Vector2(side * (hw + 4), hh * 0.55), tank)
					PixelFx.disk(canvas, p, 6, Color("#dc883d", 0.16 * pulse * flash_scale * strength), true)
			"stealth_hunter", "ghost_sniper":
				PixelFx.reticle(canvas, Vector2.ZERO, radius, Color(color, 0.20 * pulse * strength))
			"ice_hunter":
				PixelFx.ring(canvas, Vector2.ZERO, radius, 0.3, 1.2, 8, Color("#96cad0", 0.4 * strength), 1)
				PixelFx.ring(canvas, Vector2.ZERO, radius, PI + 0.3, PI + 1.2, 8, Color("#96cad0", 0.4 * strength), 1)
		if tank.build_fx_started.has(build.id):
			var age: int = tick - int(tank.build_fx_started[build.id])
			if age >= 0 and age < ACTIVATION_TICKS:
				var t := float(age) / ACTIVATION_TICKS
				var r := radius + 4 + floorf(t * 18)
				var alpha := (1.0 - t) * strength
				PixelFx.ring(canvas, Vector2.ZERO, r, 0, TAU, 32, Color(color, alpha * (0.25 + flash_scale * 0.4)), 2)
				if detail > 0:
					for i in 6:
						var angle := TAU * float(i) / 6.0 + t * 0.6
						var p := (Vector2(cos(angle), sin(angle)) * r).round()
						canvas.draw_rect(Rect2(p, Vector2(2, 2)), Color(color.lightened(0.25), alpha * flash_scale))

static func draw(canvas: CanvasItem, tank: Tank, tick: int, flash_scale: float, detail: int) -> void:
	var builds := active(tank)
	var hw := tank.width * 0.5
	var hh := tank.height * 0.5
	var strength := 1.0 / sqrt(float(maxi(builds.size(), 1)))
	for build in builds:
		var phase := posmod(tick + tank.id * 13, 48)
		var color: Color = build.color
		var alpha := (0.65 + 0.15 * sin(tick * 0.16)) * strength
		match String(build.id):
			"lightning":
				var cloud := _point(Vector2(0, hh + 6), tank)
				canvas.draw_rect(Rect2(cloud - Vector2(6, 2), Vector2(12, 5)), Color("#34454f", 0.85 * strength))
				canvas.draw_rect(Rect2(cloud - Vector2(3, 4), Vector2(6, 3)), Color("#627786", 0.85 * strength))
				var end := cloud + Vector2(phase / 12 - 2, 9)
				var points := PackedVector2Array([cloud, cloud + Vector2(-3, 4), cloud + Vector2(2, 4), end])
				ElectricGlow.draw_path(canvas, points, alpha, flash_scale, true)
			"stealth_hunter":
				for i in (4 if detail > 0 else 2):
					var p := _point(Vector2((-1 if i % 2 == 0 else 1) * (hw + 4), hh * 0.7 - posmod(phase + i * 13, 40) * 0.5), tank)
					canvas.draw_rect(Rect2(p, Vector2(3, 2)), Color("#609c66", alpha))
					canvas.draw_rect(Rect2(p + Vector2(1, -1), Vector2(1, 1)), Color("#b4c894", alpha))
			"juggernaut":
				for side in [-1, 1]:
					var p := _point(Vector2(side * (hw + 2), -hh * 0.65), tank)
					canvas.draw_rect(Rect2(p - Vector2(2, 4), Vector2(4, 8)), Color("#713c32", 0.9 * strength))
					canvas.draw_rect(Rect2(p - Vector2(2, 4), Vector2(4, 2)), Color("#dba66b", alpha))
				if detail > 0:
					var p := _point(Vector2(sin(phase * 0.3) * hw, -hh - 4 - phase % 8), tank)
					canvas.draw_rect(Rect2(p, Vector2(2, 2)), Color("#efb366", alpha))
			"ghost_sniper":
				var tip := (Vector2(cos(tank.turret_angle), sin(tank.turret_angle)) * (tank.muzzle_len + 5)).round()
				PixelFx.reticle(canvas, tip, 4 + phase / 16, Color("#bca0df", alpha))
				if detail > 0:
					var p := _point(Vector2(-hw - 3, hh + phase / 8), tank)
					PixelFx.line(canvas, p, p + Vector2(3, 0), Color("#8972b5", alpha * 0.7), 2)
			"ice_hunter":
				for i in (4 if detail > 0 else 2):
					var side := -1 if i % 2 == 0 else 1
					var p := _point(Vector2(side * (hw + 3), (-0.55 + (i / 2) * 1.1) * hh), tank)
					var size := 3 + posmod(phase + i * 9, 24) / 12
					PixelFx.polygon(canvas, PackedVector2Array([p + Vector2(0, -size), p + Vector2(2, 0), p + Vector2(0, 3), p + Vector2(-2, 0)]), Color("#7bbac9", alpha))
					PixelFx.line(canvas, p + Vector2(0, -size), p, Color("#e2efdf", alpha), 1)
			"acid_hunter":
				for i in (4 if detail > 0 else 2):
					var age := posmod(phase + i * 11, 40)
					var p := _point(Vector2((-1 if i % 2 == 0 else 1) * (hw + 3), hh * 0.6), tank)
					p += Vector2(sin(age * 0.25 + i) * 2, -floorf(age * 0.35))
					var fade := (1.0 - age / 40.0) * strength
					canvas.draw_rect(Rect2(p.round(), Vector2(3, 3)), Color("#76994c", fade * 0.8))
					canvas.draw_rect(Rect2(p.round(), Vector2.ONE), Color("#c7d57c", fade))
			"fire_hunter":
				for side in [-1, 1]:
					var p := _point(Vector2(side * (hw + 3), hh * 0.8), tank)
					PixelFx.flame(canvas, p, 2, tick + side * 7, 0.85 * strength)
				if detail > 0:
					var p := _point(Vector2(sin(phase * 0.25) * (hw + 6), -hh - phase / 6), tank)
					canvas.draw_rect(Rect2(p, Vector2.ONE * 2), Color("#e9b86c", alpha))
			"shock_hunter":
				for side in [-1, 1]:
					var start := _point(Vector2(side * (hw + 4), -hh * 0.6), tank)
					var end := _point(Vector2(side * (hw + 4), hh * 0.6), tank)
					ElectricGlow.draw_path(canvas, ElectricGlow.link_points(start, end, tank.id + phase / 4 + side * 71), alpha, flash_scale, true)
					if detail > 0: ElectricGlow.draw_spark(canvas, start, 2, alpha, flash_scale)
	# One compact side badge avoids the HP bars and overhead perk list.
	# Cycling avoids overlapping badges for simultaneous completed builds.
	for i in builds.size():
		var build: Dictionary = builds[i]
		if not tank.build_fx_started.has(build.id): continue
		var age: int = tick - int(tank.build_fx_started[build.id])
		if age < 0 or age >= ACTIVATION_TICKS or (tick / 12) % builds.size() != i: continue
		var icon := PerkIcons.texture_of(String(build.id))
		if icon != null:
			canvas.draw_texture_rect(icon, Rect2(Vector2(-hw - 24, -8 - age / 8), Vector2(16, 16)), false, Color(1, 1, 1, (1.0 - float(age) / ACTIVATION_TICKS) * (0.55 + flash_scale * 0.45)))
