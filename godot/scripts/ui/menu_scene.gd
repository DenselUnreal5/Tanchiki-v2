@tool
class_name MenuScene
extends Control

const GRID_STEP := 64.0
const SWEEP_TRAILS := 3
const SWEEP_SPEED := 0.006
const TURRET_SLEW := 0.02

var time := 0

var _settings: Dictionary = {}

var _grid_lines_v: Array = []
var _grid_lines_h: Array = []
var _tank_center := Vector2.ZERO
var _tank_scale := 1.0
var _sweep_radius := 0.0
var _built := false

var _turret_angle := 0.0
var _turret_target := 0.0
var _turret_hold := 0
var _recoil := 0.0
var _muzzle := 0.0
var _shot_timer := 0

var _glow_tex: GradientTexture2D
var _last_size := Vector2.ZERO

var _display_tank: Tank
var _tank_view: MenuTankView

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_glow_texture()
	_shot_timer = int(randf_range(200.0, 340.0))
	_turret_hold = int(randf_range(90.0, 220.0))

	if Engine.is_editor_hint():
		return

	var stub_player := PlayerState.new(0, "", "p1", null)
	_display_tank = Tank.new({
		"x": 0.0, "y": 0.0, "team": "player", "name": "",
		"owner": stub_player, "color_key": "p1",
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30,
	})
	_display_tank.spawn_protect = 0

	_tank_view = MenuTankView.new()
	_tank_view.player = stub_player
	_tank_view.glow_tex = _glow_tex
	_tank_view.display_tank = _display_tank
	add_child(_tank_view)

func _process(_delta: float) -> void:
	if size != _last_size:
		_last_size = size
		_rebuild()
	time += 1
	if not Engine.is_editor_hint():
		_update_tank()
	queue_redraw()

func _build_glow_texture() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g
	_glow_tex.width = 128
	_glow_tex.height = 128
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)

func _rebuild() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	_grid_lines_v.clear()
	var x := 0.0
	while x <= w:
		_grid_lines_v.append(x)
		x += GRID_STEP
	_grid_lines_h.clear()
	var y := 0.0
	while y <= h:
		_grid_lines_h.append(y)
		y += GRID_STEP

	_tank_center = Vector2(w * 0.88, h * 0.86)
	_tank_scale = clampf(h * 0.62 / 60.0, 1.2, 4.2)
	if _tank_view != null:
		_tank_view.scale = Vector2(_tank_scale, _tank_scale)

	_sweep_radius = Vector2(w, h).length()

	_built = true

func _update_tank() -> void:
	_turret_hold -= 1
	if _turret_hold <= 0:
		_turret_target = randf_range(-PI, PI)
		_turret_hold = int(randf_range(90.0, 220.0))
	_turret_angle = Rng.rotate_toward(_turret_angle, _turret_target, TURRET_SLEW)

	_shot_timer -= 1
	if _shot_timer > 0:
		_recoil = maxf(0.0, _recoil - 1.1)
		_muzzle = maxf(0.0, _muzzle - 0.10)
	else:
		_shot_timer = int(randf_range(200.0, 340.0))
		_recoil = 10.0
		_muzzle = 1.0

	if _tank_view == null:
		return
	_display_tank.color_key = Prof.equipped_color1
	_display_tank.cosmetics = Prof.equipped_cosmetics()
	_display_tank.turret_angle = _turret_angle
	_tank_view.muzzle = _muzzle
	var dir := Vector2(cos(_turret_angle), sin(_turret_angle))
	_tank_view.position = _tank_center - dir * _recoil * _tank_scale

func _draw() -> void:
	if not _built or size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Cfg.UI_BG)
	_draw_glow()
	_draw_sweep()
	_draw_grid()

func _draw_glow() -> void:
	var r := size.y * 0.55
	draw_texture_rect(_glow_tex,
		Rect2(_tank_center - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
		false, Color(Cfg.UI_ACCENT_DIM, 0.10))

func _draw_grid() -> void:
	var col := Color(Cfg.UI_BORDER, 0.28)
	for x in _grid_lines_v:
		draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
	for y in _grid_lines_h:
		draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0)

func _draw_sweep() -> void:
	var base_angle := float(time) * SWEEP_SPEED
	for i in SWEEP_TRAILS:
		var angle := base_angle - float(i) * 0.10
		var alpha := 0.16 * (1.0 - float(i) / float(SWEEP_TRAILS))
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(_tank_center, _tank_center + dir * _sweep_radius,
			Color(Cfg.UI_ACCENT, alpha), 1.5)
