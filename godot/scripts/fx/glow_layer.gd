class_name GlowLayer
extends Node2D

const PARTICLE_STEP := 3

var world: World = null
var view: WorldView = null
var quality := 2

var _glow_tex: GradientTexture2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_build_texture()

func _build_texture() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = grad
	_glow_tex.width = 64
	_glow_tex.height = 64
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or view == null or quality <= 0 or _glow_tex == null:
		return
	var off := view.view_off
	draw_set_transform(off)

	for b in world.bullets:
		if not b.alive or not view.in_view(b.x, b.y, 40.0):
			continue
		var cannon_color := Cannons.color_for_mode(b.cannon_kind)
		var color: Color = cannon_color if cannon_color.a > 0.0 \
			else (Cfg.bullet if b.from_player else Cfg.bullet_enemy)
		_glow(Vector2(b.x, b.y), 26.0 if b.lobbed else 18.0, color, 0.45)

	for r in world.airstrikes:
		if r.alive and view.in_view(r.x, r.y, 60.0):
			_glow(Vector2(r.x, r.y), 44.0, Color("#ff9a3c"), 0.7)

	for p in world.weapon_pickups:
		if not p.active or not view.in_view(p.x, p.y, 56.0):
			continue
		var weapon := Weapons.get_weapon(p.weapon_id)
		if weapon.is_empty():
			continue
		var pulse := 0.35 + 0.2 * sin(world.tick * 0.12 + p.bob)
		_glow(Vector2(p.x, p.y), 40.0, weapon["color"], pulse)

	for d in world.perk_drops:
		if d.active and view.in_view(d.x, d.y, 50.0):
			_glow(Vector2(d.x, d.y), 34.0, Color("#ff88ff"), 0.35)

	for wreck in world.wrecks:
		if not view.in_view(wreck.x, wreck.y, 70.0):
			continue
		var flicker: float = 0.6 + 0.4 * sin(world.tick * 0.2 + wreck.turret_angle)
		_glow(Vector2(wreck.x, wreck.y), 52.0 * wreck.scale,
			Color("#ff7a20"), 0.32 * wreck.fade * flicker)

	if world.base != null:
		var ratio: float = float(world.base["hp"]) / float(world.base["max_hp"])
		var core := Color("#7abf6a") if ratio > 0.5 else (Color("#ddc255") if ratio > 0.25 else Color("#dd5555"))
		_glow(Vector2(world.base["x"], world.base["y"]), 70.0, core, 0.28)

	if quality < 2:
		return

	var ps := world.particles
	var i := 0
	while i < ps.count:
		if not view.in_view(ps.px[i], ps.py[i], 30.0):
			i += PARTICLE_STEP
			continue
		var life_ratio := ps.life[i] / maxf(1.0, ps.max_life[i])
		var c: Color = ps.color[i]
		if c.r + c.g > 1.1:
			_glow(Vector2(ps.px[i], ps.py[i]), 10.0 + ps.size[i] * 3.0, c, life_ratio * 0.35)
		i += PARTICLE_STEP

func _glow(pos: Vector2, radius: float, color: Color, strength: float) -> void:
	var c := color
	c.a = strength
	draw_texture_rect(_glow_tex,
		Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		false, c)
