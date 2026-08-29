# ============================================================================
# menu_scene.gd — анимированный фон главного меню.
#
# Ночное поле боя после штурма: разбитый город на горизонте, гряда холмов,
# танк на гребне, догорающие остовы, косой дождь и редкие молнии.
# Всё рисуется процедурно, без единого файла-ассета.
#
# Плавные засветки и небо сделаны градиентными текстурами (GradientTexture2D),
# а не кольцами из draw_circle: кольца давали видимые полосы на градиенте.
#
# Композиция смещена вправо: слева экран занимают панели меню.
# ============================================================================
class_name MenuScene
extends Control

const DROP_MAX := 260
const FLAME_MAX := 110
const SMOKE_MAX := 46
const EMBER_MAX := 130

static var FLAME_COLORS := [Color("#ffe066"), Color("#ffb020"), Color("#ff7a10"), Color("#ff4a08")]
static var EMBER_COLORS := [Color("#fff3c4"), Color("#ffcc55")]

# ---------------------------------------------------------------- палитра
static var SKY_TOP := Color("#05080d")
static var SKY_MID := Color("#0b1119")
static var SKY_HORIZON := Color("#1b2530")
static var CITY := Color("#0a0f15")
static var HILL_FAR := Color("#0d141a")
static var HILL_NEAR := Color("#101a16")
static var RIDGE := Color("#0b100e")
static var RIDGE_EDGE := Color("#2e4038")
static var GROUND := Color("#080b0a")

var time := 0

# Слои сцены, пересобираются при изменении размера окна.
var _drops: Array = []
var _skyline: Array = []
var _hill_far := PackedVector2Array()
var _hill_near := PackedVector2Array()
var _ridge := PackedVector2Array()
var _ridge_top := PackedVector2Array()
var _ridge_facets: Array = []
var _ridge_cracks: Array = []
## Пока геометрия не собрана (первый кадр), рисовать нечего.
var _built := false
var _craters: Array = []
var _wrecks: Array = []
var _fires: Array = []

# Частицы огня.
var _flames: Array = []
var _smoke: Array = []
var _embers: Array = []

# Молния: вспышка, обратный отсчёт и точки разряда.
var _flash := 0.0
var _flash_timer := 120.0
var _bolt := PackedVector2Array()
var _bolt_branch := PackedVector2Array()
var _bolt_life := 0

# Танк на гребне: периодический выстрел (отдача + вспышка в дуле).
var _shot_timer := 0
var _recoil := 0.0
var _muzzle := 0.0
var _tank_pos := Vector2.ZERO
var _tank_scale := 1.0

# Текстуры градиентов.
var _sky_tex: GradientTexture2D
var _glow_tex: GradientTexture2D
var _vignette_tex: GradientTexture2D

var _rng := RandomNumberGenerator.new()
var _last_size := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 20260828
	_build_textures()
	_flash_timer = randf_range(90.0, 200.0)

func _process(_delta: float) -> void:
	if size != _last_size:
		_last_size = size
		_rebuild()
	time += 1
	_update_rain()
	_update_fire()
	_update_lightning()
	_update_shot()
	queue_redraw()

# ---------------------------------------------------------------- текстуры
func _build_textures() -> void:
	# Небо: вертикальный градиент от почти чёрного к сизому у горизонта.
	var sky := Gradient.new()
	sky.offsets = PackedFloat32Array([0.0, 0.45, 0.78, 1.0])
	sky.colors = PackedColorArray([SKY_TOP, SKY_MID, SKY_HORIZON, Color("#243040")])
	_sky_tex = GradientTexture2D.new()
	_sky_tex.gradient = sky
	_sky_tex.width = 4
	_sky_tex.height = 256
	_sky_tex.fill_from = Vector2(0, 0)
	_sky_tex.fill_to = Vector2(0, 1)

	# Белая радиальная засветка: цвет задаётся модуляцией при отрисовке.
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	glow.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.32), Color(1, 1, 1, 0.0)])
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = glow
	_glow_tex.width = 128
	_glow_tex.height = 128
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)

	# Виньетка: прозрачный центр, затемнённые края.
	var vig := Gradient.new()
	vig.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vig.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.10), Color(0, 0, 0, 0.72)])
	_vignette_tex = GradientTexture2D.new()
	_vignette_tex.gradient = vig
	_vignette_tex.width = 256
	_vignette_tex.height = 256
	_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
	_vignette_tex.fill_from = Vector2(0.5, 0.5)
	_vignette_tex.fill_to = Vector2(1.0, 0.5)

# ---------------------------------------------------------------- сборка сцены
func _rebuild() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	_rng.seed = 20260828

	# --- дождь
	var count: int = mini(DROP_MAX, int(w * h / 6500.0))
	_drops.clear()
	for i in count:
		_drops.append({
			"x": _rng.randf() * (w + 200.0) - 100.0,
			"y": _rng.randf() * h,
			"speed": _rng.randf_range(14.0, 30.0),
			"len": _rng.randf_range(10.0, 26.0),
			"alpha": _rng.randf_range(0.12, 0.42),
		})

	var horizon := h * 0.60

	# --- разбитый город на горизонте
	_skyline.clear()
	var x := -20.0
	while x < w + 40.0:
		var bw := _rng.randf_range(18.0, 54.0)
		var bh := _rng.randf_range(24.0, 96.0)
		# Часть зданий «сломана» — с уступом сверху.
		var broken := _rng.randf() < 0.45
		var windows := []
		var wy := horizon - bh + 8.0
		while wy < horizon - 8.0:
			var wx := x + 5.0
			while wx < x + bw - 7.0:
				if _rng.randf() < 0.14:
					windows.append(Vector2(wx, wy))
				wx += 8.0
			wy += 11.0
		_skyline.append({"x": x, "w": bw, "h": bh, "broken": broken, "windows": windows})
		x += bw + _rng.randf_range(2.0, 14.0)

	# --- дальняя и ближняя гряды холмов
	_hill_far = _make_hill(horizon + 6.0, 26.0, 150.0, h)
	_hill_near = _make_hill(horizon + 42.0, 34.0, 210.0, h)

	# --- гребень справа, на нём стоит танк
	var plateau_y := h * 0.545
	_ridge = PackedVector2Array([
		Vector2(w * 0.44, h + 4.0),
		Vector2(w * 0.47, h * 0.86),
		Vector2(w * 0.53, h * 0.72),
		Vector2(w * 0.585, h * 0.615),
		Vector2(w * 0.635, plateau_y + 4.0),
		Vector2(w * 0.66, plateau_y),
		Vector2(w * 0.90, plateau_y - 6.0),
		Vector2(w * 0.955, h * 0.60),
		Vector2(w + 4.0, h * 0.70),
		Vector2(w + 4.0, h + 4.0),
	])
	_ridge_top = PackedVector2Array([
		Vector2(w * 0.585, h * 0.615), Vector2(w * 0.635, plateau_y + 4.0),
		Vector2(w * 0.66, plateau_y), Vector2(w * 0.90, plateau_y - 6.0),
		Vector2(w * 0.955, h * 0.60),
	])
	# Рельеф гребня: светлая грань по склону к луне и тень у подножия,
	# иначе скала читается одним плоским пятном.
	_ridge_facets = [
		{"poly": PackedVector2Array([
			Vector2(w * 0.53, h * 0.72), Vector2(w * 0.585, h * 0.615),
			Vector2(w * 0.645, plateau_y + 2.0), Vector2(w * 0.63, h * 0.70),
			Vector2(w * 0.575, h * 0.88),
		]), "color": Color("#111a15")},
		{"poly": PackedVector2Array([
			Vector2(w * 0.44, h + 4.0), Vector2(w * 0.47, h * 0.86),
			Vector2(w + 4.0, h * 0.80), Vector2(w + 4.0, h + 4.0),
		]), "color": Color("#070b09")},
		{"poly": PackedVector2Array([
			Vector2(w * 0.90, plateau_y - 6.0), Vector2(w * 0.955, h * 0.60),
			Vector2(w * 0.94, h * 0.70), Vector2(w * 0.885, h * 0.62),
		]), "color": Color("#0f1613")},
	]
	_ridge_cracks = [
		[Vector2(w * 0.70, plateau_y + 10.0), Vector2(w * 0.685, h * 0.66), Vector2(w * 0.705, h * 0.78)],
		[Vector2(w * 0.83, plateau_y + 14.0), Vector2(w * 0.845, h * 0.70)],
	]

	_tank_pos = Vector2(w * 0.775, plateau_y - 4.0)
	_tank_scale = clampf(w / 1500.0, 0.62, 1.25)

	# --- воронки на переднем плане
	_craters.clear()
	for i in 5:
		_craters.append({
			"x": _rng.randf_range(w * 0.40, w),
			"y": _rng.randf_range(h * 0.88, h * 0.99),
			"r": _rng.randf_range(26.0, 70.0),
		})

	# --- остовы танков и очаги огня
	# Слева экран закрыт панелями меню, поэтому всё интересное — правее 0.45.
	_wrecks = [
		{"pos": Vector2(w * 0.50, h * 0.815), "scale": 1.15 * _tank_scale, "flip": false},
		{"pos": Vector2(w * 0.655, h * 0.905), "scale": 1.5 * _tank_scale, "flip": true},
		{"pos": Vector2(w * 0.905, h * 0.755), "scale": 0.8 * _tank_scale, "flip": false},
	]
	_fires = [
		{"pos": Vector2(w * 0.50, h * 0.80), "power": 1.0},
		{"pos": Vector2(w * 0.658, h * 0.885), "power": 1.35},
		{"pos": Vector2(w * 0.905, h * 0.74), "power": 0.7},
	]
	_flames.clear()
	_smoke.clear()
	_embers.clear()
	_built = true

## Ломаная линия холма: слева направо со случайными неровностями.
func _make_hill(base_y: float, amp: float, step: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(-10.0, h + 4.0))
	var x := -10.0
	var i := 0
	while x < size.x + step:
		var y := base_y - sin(float(i) * 1.7) * amp * 0.5 - _rng.randf_range(0.0, amp)
		pts.append(Vector2(x, y))
		x += step
		i += 1
	pts.append(Vector2(size.x + 10.0, h + 4.0))
	return pts

# ---------------------------------------------------------------- анимация
func _update_rain() -> void:
	var tilt := 0.26  # ветер относит капли влево
	for d in _drops:
		d["x"] = float(d["x"]) - tilt * float(d["speed"])
		d["y"] = float(d["y"]) + float(d["speed"])
		if float(d["y"]) > size.y:
			d["y"] = -float(d["len"])
			d["x"] = _rng.randf() * (size.x + 200.0) - 100.0
		if float(d["x"]) < -110.0:
			d["x"] = size.x + 60.0

func _update_fire() -> void:
	for fire in _fires:
		var p: Vector2 = fire["pos"]
		var power: float = fire["power"]
		var n := 1 + int(power)
		for i in n:
			_spawn_flame(p.x, p.y, power)

	var kept := []
	for p in _flames:
		p["life"] = float(p["life"]) - 1.0
		if float(p["life"]) > 0.0:
			p["x"] = float(p["x"]) + float(p["vx"]) + sin(time * 0.14 + float(p["seed"])) * 0.35
			p["y"] = float(p["y"]) + float(p["vy"])
			p["vy"] = float(p["vy"]) * 0.985
			kept.append(p)
	_flames = kept

	var kept_e := []
	for p in _embers:
		p["life"] = float(p["life"]) - 1.0
		if float(p["life"]) > 0.0:
			p["x"] = float(p["x"]) + float(p["vx"]) - 0.35
			p["y"] = float(p["y"]) + float(p["vy"])
			p["vy"] = float(p["vy"]) * 0.975
			kept_e.append(p)
	_embers = kept_e

	var kept_s := []
	for p in _smoke:
		p["life"] = float(p["life"]) - 1.0
		if float(p["life"]) > 0.0:
			p["x"] = float(p["x"]) + float(p["vx"]) - 0.25
			p["y"] = float(p["y"]) + float(p["vy"])
			p["size"] = float(p["size"]) + 0.35
			kept_s.append(p)
	_smoke = kept_s

func _spawn_flame(x: float, y: float, power: float) -> void:
	if _flames.size() < FLAME_MAX:
		_flames.append({
			"x": x + _rng.randf_range(-7.0, 7.0) * power, "y": y,
			"vy": _rng.randf_range(-1.9, -0.8), "vx": _rng.randf_range(-0.4, 0.4),
			"size": _rng.randf_range(2.5, 6.0) * power,
			"life": _rng.randf_range(20.0, 44.0), "max_life": 44.0,
			"seed": _rng.randf() * 10.0,
			"color": FLAME_COLORS[_rng.randi() % FLAME_COLORS.size()],
		})
	if _rng.randf() < 0.35 and _embers.size() < EMBER_MAX:
		_embers.append({
			"x": x + _rng.randf_range(-10.0, 10.0), "y": y + _rng.randf_range(-6.0, 2.0),
			"vy": _rng.randf_range(-3.0, -1.4), "vx": _rng.randf_range(-0.8, 0.8),
			"size": _rng.randf_range(0.9, 2.0),
			"life": _rng.randf_range(24.0, 60.0), "max_life": 60.0,
			"color": EMBER_COLORS[_rng.randi() % EMBER_COLORS.size()],
		})
	if _rng.randf() < 0.10 and _smoke.size() < SMOKE_MAX:
		_smoke.append({
			"x": x + _rng.randf_range(-5.0, 5.0), "y": y - 12.0,
			"vy": _rng.randf_range(-1.1, -0.5), "vx": _rng.randf_range(-0.3, 0.3),
			"size": _rng.randf_range(6.0, 14.0) * power,
			"life": _rng.randf_range(70.0, 130.0), "max_life": 130.0,
		})

func _update_lightning() -> void:
	_flash_timer -= 1.0
	if _flash_timer > 0.0:
		return
	_flash_timer = _rng.randf_range(320.0, 760.0)  # 5–13 сек
	_flash = 1.0
	_bolt_life = 7
	_make_bolt()

func _make_bolt() -> void:
	var x := size.x * _rng.randf_range(0.30, 0.85)
	var y := 0.0
	var target_y := size.y * _rng.randf_range(0.30, 0.48)
	_bolt = PackedVector2Array([Vector2(x, y)])
	_bolt_branch = PackedVector2Array()
	var has_branch := false
	while y < target_y:
		x += _rng.randf_range(-24.0, 24.0)
		y += _rng.randf_range(22.0, 44.0)
		_bolt.append(Vector2(x, y))
		if not has_branch and _rng.randf() < 0.5:
			has_branch = true
			var bx := x
			var by := y
			_bolt_branch = PackedVector2Array([Vector2(bx, by)])
			var travelled := 0.0
			var blen := _rng.randf_range(40.0, 90.0)
			while travelled < blen:
				bx += _rng.randf_range(-18.0, 8.0)
				by += _rng.randf_range(10.0, 22.0)
				travelled += 20.0
				_bolt_branch.append(Vector2(bx, by))

func _update_shot() -> void:
	_shot_timer -= 1
	if _shot_timer > 0:
		_recoil = maxf(0.0, _recoil - 1.1)
		_muzzle = maxf(0.0, _muzzle - 0.10)
		return
	_shot_timer = int(_rng.randf_range(200.0, 340.0))  # ~3.5–6 сек
	_recoil = 10.0
	_muzzle = 1.0

# ================================================================ отрисовка
func _draw() -> void:
	if not _built or _sky_tex == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_sky()
	_draw_bolt()
	_draw_city()
	_draw_hills()
	_draw_ridge()
	_draw_wrecks()
	_draw_tank()
	_draw_fire()
	_draw_rain()
	draw_texture_rect(_vignette_tex, Rect2(Vector2.ZERO, size), false)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.80, 0.87, 1.0, _flash * 0.20))
		_flash *= 0.84
		if _flash < 0.02:
			_flash = 0.0

## Мягкая радиальная засветка заданного цвета.
func _glow(center: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(_glow_tex,
		Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		false, color)

func _draw_sky() -> void:
	draw_texture_rect(_sky_tex, Rect2(Vector2.ZERO, size), false)
	# Луна за облаками — единственный холодный источник света.
	var moon := Vector2(size.x * 0.80, size.y * 0.16)
	_glow(moon, size.y * 0.34, Color(0.42, 0.55, 0.72, 0.16))
	_glow(moon, 26.0, Color(0.78, 0.86, 0.96, 0.30))
	# Рваные тучи — вытянутые тёмные пятна, слегка плывут.
	for i in 9:
		var t := time * 0.02
		var cx := fposmod(float(i) * size.x * 0.17 + t, size.x + 400.0) - 200.0
		var cy := size.y * (0.06 + float((i * 37) % 22) / 100.0)
		var r := size.x * (0.10 + float((i * 53) % 11) / 100.0)
		draw_texture_rect(_glow_tex,
			Rect2(Vector2(cx - r, cy - r * 0.42), Vector2(r * 2.0, r * 0.84)),
			false, Color(0.09, 0.12, 0.16, 0.55))

func _draw_bolt() -> void:
	if _bolt.size() < 2 or _bolt_life <= 0:
		return
	draw_polyline(_bolt, Color(0.55, 0.68, 1.0, 0.28), 10.0)
	draw_polyline(_bolt, Color(0.88, 0.94, 1.0, 0.95), 2.5)
	if _bolt_branch.size() > 1:
		draw_polyline(_bolt_branch, Color(0.55, 0.68, 1.0, 0.24), 7.0)
		draw_polyline(_bolt_branch, Color(0.88, 0.94, 1.0, 0.85), 1.8)
	_bolt_life -= 1

func _draw_city() -> void:
	var base := size.y * 0.60
	for b in _skyline:
		var x: float = b["x"]
		var bw: float = b["w"]
		var bh: float = b["h"]
		var top: float = base - bh
		if bool(b["broken"]):
			# Сломанный верх: уступ вместо ровной крыши.
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, base), Vector2(x, top + bh * 0.22),
				Vector2(x + bw * 0.45, top), Vector2(x + bw * 0.62, top + bh * 0.16),
				Vector2(x + bw, top + bh * 0.06), Vector2(x + bw, base),
			]), CITY)
		else:
			draw_rect(Rect2(x, top, bw, bh + 2.0), CITY)
		# Редкие горящие окна.
		for wpos in b["windows"]:
			draw_rect(Rect2(wpos, Vector2(2.0, 3.0)), Color(1.0, 0.72, 0.34, 0.5))

func _draw_hills() -> void:
	draw_colored_polygon(_hill_far, HILL_FAR)
	# Дымка над дальним планом.
	_glow(Vector2(size.x * 0.6, size.y * 0.615), size.x * 0.5,
		Color(0.35, 0.42, 0.5, 0.10))
	draw_colored_polygon(_hill_near, HILL_NEAR)

func _draw_ridge() -> void:
	draw_colored_polygon(_ridge, RIDGE)
	for facet in _ridge_facets:
		draw_colored_polygon(facet["poly"], facet["color"])
	for crack in _ridge_cracks:
		draw_polyline(PackedVector2Array(crack), Color(0, 0, 0, 0.45), 2.0)
	# Подсвеченная кромка гребня — отделяет силуэт от неба.
	draw_polyline(_ridge_top, RIDGE_EDGE, 2.0)
	# Земля переднего плана с воронками.
	draw_rect(Rect2(0, size.y * 0.965, size.x, size.y * 0.05), GROUND)
	for c in _craters:
		draw_colored_polygon(
			_ellipse(Vector2(c["x"], c["y"]), float(c["r"]), float(c["r"]) * 0.34),
			Color(0.02, 0.03, 0.03, 0.85))

func _ellipse(center: Vector2, rx: float, ry: float, segments: int = 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

## Обгоревшие остовы танков в профиль.
func _draw_wrecks() -> void:
	for wreck in _wrecks:
		var o: Vector2 = wreck["pos"]
		var s: float = wreck["scale"]
		var dir := -1.0 if bool(wreck["flip"]) else 1.0
		var p := func(px: float, py: float) -> Vector2:
			return o + Vector2(px * dir, py) * s

		# Корпус с оторванной башней.
		draw_colored_polygon(PackedVector2Array([
			p.call(-42, 0), p.call(-36, -12), p.call(-16, -18),
			p.call(6, -20), p.call(24, -12), p.call(34, -4), p.call(30, 0),
		]), Color("#0b0d0c"))
		# Свёрнутая набок башня рядом.
		draw_colored_polygon(PackedVector2Array([
			p.call(-56, 0), p.call(-52, -9), p.call(-40, -11), p.call(-36, -2),
		]), Color("#0e100e"))
		# Ствол торчит из земли.
		draw_line(p.call(-52, -8), p.call(-70, -20), Color("#12140f"), 3.0 * s)
		# Тлеющий разлом в корпусе.
		draw_colored_polygon(PackedVector2Array([
			p.call(-6, -16), p.call(6, -17), p.call(10, -9), p.call(-4, -8),
		]), Color(0.55, 0.20, 0.05, 0.75))
		# Сползшая гусеница.
		draw_rect(Rect2(p.call(-40, -4), Vector2(70, 5) * s), Color("#151713"))

func _draw_tank() -> void:
	var o := _tank_pos
	var s := _tank_scale
	var p := func(px: float, py: float) -> Vector2:
		return o + Vector2(px, py) * s
	var r := func(px: float, py: float, pw: float, ph: float) -> Rect2:
		return Rect2(o + Vector2(px, py) * s, Vector2(pw, ph) * s)

	# Тень на камне.
	draw_colored_polygon(_ellipse(o + Vector2(0, 4) * s, 54 * s, 7 * s), Color(0, 0, 0, 0.5))

	# Гусеницы и катки.
	draw_rect(r.call(-48, -22, 96, 24), Color("#12161a"))
	var i := -36.0
	while i <= 36.0:
		draw_circle(p.call(i, -10), 5.0 * s, Color("#222a2e"))
		i += 10.0
	draw_rect(r.call(-46, -21, 92, 3), Color("#2b343a"))

	# Корпус.
	draw_colored_polygon(PackedVector2Array([
		p.call(-44, -21), p.call(-44, -36), p.call(-30, -40),
		p.call(34, -40), p.call(46, -32), p.call(46, -21),
	]), Color("#2f3a28"))
	# Верхний бронелист ловит свет луны.
	draw_colored_polygon(PackedVector2Array([
		p.call(-30, -40), p.call(34, -40), p.call(34, -37), p.call(-30, -37),
	]), Color("#4a5a3d"))
	# Ящики на надгусеничной полке.
	draw_rect(r.call(12, -38, 14, 6), Color("#26301f"))

	# Башня.
	var bob := sin(time * 0.018) * 0.7
	draw_colored_polygon(PackedVector2Array([
		p.call(-18, -40 + bob), p.call(-14, -54 + bob), p.call(12, -54 + bob),
		p.call(20, -46 + bob), p.call(20, -40 + bob),
	]), Color("#39472f"))
	draw_circle(p.call(2, -55 + bob), 3.5 * s, Color("#222b1c"))  # командирский люк

	# Ствол с отдачей и дульным тормозом.
	draw_rect(r.call(18 - _recoil, -50 + bob, 46, 6), Color("#293321"))
	draw_rect(r.call(18 - _recoil, -50 + bob, 46, 2), Color("#3d4a33"))
	draw_rect(r.call(60 - _recoil, -52 + bob, 9, 10), Color("#1d2618"))

	# Антенна.
	draw_line(p.call(-16, -54 + bob), p.call(-22, -78 + bob), Color("#1b2318"), 1.5 * s)

	# Вспышка выстрела.
	if _muzzle > 0.0:
		var m: Vector2 = p.call(72 - _recoil, -47 + bob)
		_glow(m, 46.0 * s, Color(1.0, 0.80, 0.35, _muzzle * 0.85))
		_glow(m, 16.0 * s, Color(1.0, 0.95, 0.75, _muzzle))

func _draw_fire() -> void:
	# Тёплые ореолы вокруг очагов — рисуются под частицами.
	for fire in _fires:
		var p: Vector2 = fire["pos"]
		var power: float = fire["power"]
		var pulse := 0.85 + 0.15 * sin(time * 0.12 + p.x)
		_glow(p, 120.0 * power * pulse, Color(1.0, 0.45, 0.12, 0.16))
		_glow(p, 46.0 * power * pulse, Color(1.0, 0.62, 0.22, 0.22))
		# Отсвет на земле вокруг очага.
		draw_texture_rect(_glow_tex,
			Rect2(p + Vector2(-95.0 * power, -14.0 * power),
				Vector2(190.0 * power, 46.0 * power)),
			false, Color(1.0, 0.42, 0.10, 0.13))

	for p in _smoke:
		var a: float = maxf(0.0, float(p["life"]) / float(p["max_life"]))
		draw_circle(Vector2(p["x"], p["y"]), float(p["size"]), Color(0.22, 0.21, 0.22, a * 0.20))

	for p in _flames:
		var a: float = maxf(0.0, float(p["life"]) / float(p["max_life"]))
		var c: Color = p["color"]
		c.a = a * 0.95
		draw_circle(Vector2(p["x"], p["y"]), float(p["size"]) * (0.4 + a * 0.6), c)

	for p in _embers:
		var a: float = maxf(0.0, float(p["life"]) / float(p["max_life"]))
		var c: Color = p["color"]
		c.a = a
		draw_circle(Vector2(p["x"], p["y"]), float(p["size"]), c)

func _draw_rain() -> void:
	for d in _drops:
		var x := float(d["x"])
		var y := float(d["y"])
		var l := float(d["len"])
		draw_line(Vector2(x, y), Vector2(x - 0.26 * l, y + l),
			Color(0.62, 0.72, 0.88, float(d["alpha"])), 1.0)
