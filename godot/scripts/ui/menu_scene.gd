# ============================================================================
# menu_scene.gd — фон главного меню.
#
# Плоский тёмно-серый холст: техническая сетка во весь экран (в духе
# тактической карты), настоящий танк игрока — тот же цвет и та же косметика
# (камуфляж, рисунок на корпусе, скины гусениц/башни), что экипированы в
# Гараже, отрисован тем же кодом, что и в бою (см. menu_tank_view.gd), —
# и развёртка радара во весь экран, вращающаяся вокруг танка. Танк живой:
# башня время от времени сама выбирает новое направление и изредка
# стреляет — отдача всем корпусом и вспышка на срезе.
#
# Никакой отдельной картинки-ассета: холст, сетка и развёртка по-прежнему
# рисуются процедурно, без кинематографичной сцены, которая раньше здесь
# была (город, огонь, дождь, молнии) — она визуально не сочеталась с
# плоскими панелями меню и остальным интерфейсом.
#
# Композиция смещена вправо: слева экран занимают панели меню.
# ============================================================================
class_name MenuScene
extends Control

const GRID_STEP := 64.0
## Развёртка радара — 3 полосы с затуханием по длине следа.
const SWEEP_TRAILS := 3
const SWEEP_SPEED := 0.006
## Скорость поворота башни к новой цели, рад/тик — то же по духу значение,
## что BOT_TURRET_SLEW у ботов (tank.gd), только медленнее: тут не бой,
## а фоновая анимация, дёргаться она не должна.
const TURRET_SLEW := 0.02

var time := 0

## Ссылка на тот же словарь, что UiRoot.settings (Dictionary — ссылочный
## тип в GDScript, отдельно подписываться на смену цвета не нужно).
## Ставит UiRoot сразу после создания сцены.
var _settings: Dictionary = {}

var _grid_lines_v: Array = []
var _grid_lines_h: Array = []
var _tank_center := Vector2.ZERO
var _tank_scale := 1.0
var _sweep_radius := 0.0
var _built := false

# Башня: медленно поворачивается к случайной цели и держит её, пока не
# истечёт _turret_hold — тогда выбирается новая. Отдельно от корпуса,
# как и у настоящих танков.
var _turret_angle := 0.0
var _turret_target := 0.0
var _turret_hold := 0
# Выстрел: отдача вдоль направления ствола (двигаем весь узел танка —
# на глаз неотличимо от отдачи одного ствола) и вспышка на срезе,
# затухают по тику, новый — через случайный интервал.
var _recoil := 0.0
var _muzzle := 0.0
var _shot_timer := 0

var _glow_tex: GradientTexture2D
var _last_size := Vector2.ZERO

## Настоящий танк для отрисовки и узел, который его рисует — см.
## menu_tank_view.gd: тот же код, что красит боевые танки.
var _display_tank: Tank
var _tank_view: MenuTankView

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_glow_texture()
	_shot_timer = int(randf_range(200.0, 340.0))
	_turret_hold = int(randf_range(90.0, 220.0))

	# Заглушка вместо живого игрока: MenuTankView._draw_tank() требует
	# ненулевой player (проверка союзности), но раз у самого player нет
	# своего tank, до world она не доходит — world можно не заводить вовсе.
	var stub_player := PlayerState.new(0, "", "p1", null)
	_display_tank = Tank.new({
		"x": 0.0, "y": 0.0, "team": "player", "name": "",
		"owner": stub_player, "color_key": "p1",
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30,
	})
	# Иначе кольцо неуязвимости спавна читало бы world.tick, а world нет.
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

# ---------------------------------------------------------------- сборка сцены
func _rebuild() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	# Сетка — во весь экран: и под панелями меню, которые её всё равно
	# закрывают собой (они непрозрачные), и в свободной правой части.
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

	# Танк — большой, обрезан правым/нижним краем экрана. Масштаб считан
	# от настоящих габаритов корпуса (24×28), а не от прежнего самодельного
	# силуэта — итоговый множитель заметно больше, чем был у водяного знака.
	_tank_center = Vector2(w * 0.88, h * 0.86)
	_tank_scale = clampf(h * 0.62 / 60.0, 1.2, 4.2)
	if _tank_view != null:
		_tank_view.scale = Vector2(_tank_scale, _tank_scale)

	# Развёртка крутится вокруг того же центра, что и танк — радар
	# «принадлежит» танку, а не отдельная деталь сама по себе. Радиус —
	# диагональ экрана: луч обязан доставать до любого угла, а танк стоит
	# не в центре, так что полдиагонали (как раньше) не всегда хватало.
	_sweep_radius = Vector2(w, h).length()

	_built = true

# ---------------------------------------------------------------- анимация
func _update_tank() -> void:
	_turret_hold -= 1
	if _turret_hold <= 0:
		_turret_target = randf_range(-PI, PI)
		_turret_hold = int(randf_range(90.0, 220.0))   # ~1.5–3.7 с между сменами
	_turret_angle = Rng.rotate_toward(_turret_angle, _turret_target, TURRET_SLEW)

	_shot_timer -= 1
	if _shot_timer > 0:
		_recoil = maxf(0.0, _recoil - 1.1)
		_muzzle = maxf(0.0, _muzzle - 0.10)
	else:
		_shot_timer = int(randf_range(200.0, 340.0))   # ~3.5–6 с между выстрелами
		_recoil = 10.0
		_muzzle = 1.0

	if _tank_view == null:
		return
	# Цвет и косметика — реальные, экипированные в Гараже. Гараж открывается
	# поверх этого же меню, поэтому читаем их каждый тик, а не только при
	# пересборке по ресайзу: перекраска видна сразу, без перезапуска экрана.
	_display_tank.color_key = String(_settings.get("color1", "p1"))
	_display_tank.cosmetics = Prof.equipped_cosmetics()
	_display_tank.turret_angle = _turret_angle
	_tank_view.muzzle = _muzzle
	var dir := Vector2(cos(_turret_angle), sin(_turret_angle))
	_tank_view.position = _tank_center - dir * _recoil * _tank_scale

# ================================================================ отрисовка
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
