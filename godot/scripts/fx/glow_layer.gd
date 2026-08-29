# ============================================================================
# glow_layer.gd — свечение источников света, рисуется поверх мира с
# аддитивным смешиванием.
#
# Зачем отдельный узел: режим смешивания задаётся материалом всего
# CanvasItem, внутри одного _draw() его не переключить. Поэтому свечение
# живёт в собственном Node2D с BLEND_MODE_ADD поверх WorldView.
#
# Экранный bloom из post_fx размывает то, что уже нарисовано, и работает
# по всему кадру. Здесь наоборот — точечные ореолы там, где по смыслу есть
# источник света: трассеры, взрывы, огонь ракет, лежащее оружие. Это дёшево
# (десятки квадов) и даёт основную часть эффекта даже при выключенном bloom.
# ============================================================================
class_name GlowLayer
extends Node2D

## Каждая N-я частица получает ореол: на 1200 частиц квадов было бы слишком
## много, а на глаз разница незаметна.
const PARTICLE_STEP := 3

var world: World = null
var view: WorldView = null
## 0 — выключено, 1 — только крупные источники, 2 — всё.
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
	# Смещение камеры берём у WorldView: он рисуется первым в том же кадре,
	# и в нём уже учтена тряска экрана.
	var off := view.view_off
	draw_set_transform(off)

	# --- пули: короткий яркий трассер
	for b in world.bullets:
		if not b.alive:
			continue
		var color: Color = Cfg.bullet if b.from_player else Cfg.bullet_enemy
		_glow(Vector2(b.x, b.y), 26.0 if b.lobbed else 18.0, color, 0.45)

	# --- ракеты авиаудара
	for r in world.airstrikes:
		if r.alive:
			_glow(Vector2(r.x, r.y), 44.0, Color("#ff9a3c"), 0.7)

	# --- оружие на карте: пульсирующая метка видна издалека
	for p in world.weapon_pickups:
		if not p.active:
			continue
		var weapon := Weapons.get_weapon(p.weapon_id)
		if weapon.is_empty():
			continue
		var pulse := 0.35 + 0.2 * sin(world.tick * 0.12 + p.bob)
		_glow(Vector2(p.x, p.y), 40.0, weapon["color"], pulse)

	# --- выпавшие перки («Царь горы»)
	for d in world.perk_drops:
		if d.active:
			_glow(Vector2(d.x, d.y), 34.0, Color("#ff88ff"), 0.35)

	# --- горящие остовы
	for wreck in world.wrecks:
		var flicker: float = 0.6 + 0.4 * sin(world.tick * 0.2 + wreck.turret_angle)
		_glow(Vector2(wreck.x, wreck.y), 52.0 * wreck.scale,
			Color("#ff7a20"), 0.32 * wreck.fade * flicker)

	# --- ядро базы в «Обороне»
	if world.base != null:
		var ratio: float = float(world.base["hp"]) / float(world.base["max_hp"])
		var core := Color("#7abf6a") if ratio > 0.5 else (Color("#ddc255") if ratio > 0.25 else Color("#dd5555"))
		_glow(Vector2(world.base["x"], world.base["y"]), 70.0, core, 0.28)

	if quality < 2:
		return

	# --- искры взрывов и огня
	var ps := world.particles
	var i := 0
	while i < ps.count:
		var life_ratio := ps.life[i] / maxf(1.0, ps.max_life[i])
		var c: Color = ps.color[i]
		# Светятся только тёплые яркие частицы: дым и брызги воды не должны.
		if c.r + c.g > 1.1:
			_glow(Vector2(ps.px[i], ps.py[i]), 10.0 + ps.size[i] * 3.0, c, life_ratio * 0.35)
		i += PARTICLE_STEP

## Мягкий ореол заданного цвета и силы.
func _glow(pos: Vector2, radius: float, color: Color, strength: float) -> void:
	var c := color
	c.a = strength
	draw_texture_rect(_glow_tex,
		Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		false, c)
