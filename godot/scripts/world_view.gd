# ============================================================================
# world_view.gd — отрисовка мира для ОДНОГО игрока.
#
# Прямой порт render.js: то же immediate-mode рисование, только вместо
# Canvas2D — _draw(). Каждый игрок получает свой WorldView внутри своего
# SubViewport, поэтому разделённый экран работает без специальных случаев.
# ============================================================================
class_name WorldView
extends Node2D

var world: World = null
var player: PlayerState = null
## Всплывающие числа урона — общий список, живёт в Game.
var floaters: Array = []
## Смещение камеры этого кадра. Публично: слой свечения рисуется отдельным
## узлом и должен встать ровно поверх мира.
var view_off := Vector2.ZERO
## Затенение у стен; null — эффект выключен.
var ao: AoLayer = null
var _view := Rect2()

func _ready() -> void:
	# Тайлы, танки и частицы рисуются примитивами без текстур, поэтому
	# линейная фильтрация им безразлична — зато она мягко растягивает
	# карту затенения (пиксель на тайл) и сглаживает шрифт.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or player == null:
		return
	var size := player.viewport.size
	if size.x <= 0.0 or size.y <= 0.0:
		return

	# Тряска экрана — своя у каждого игрока.
	var shake := Vector2.ZERO
	if player.shake > 0.0:
		shake = Vector2((world.rng.nextf() - 0.5) * player.shake,
			(world.rng.nextf() - 0.5) * player.shake)

	# Сдвиг округляется до целых пикселей: при дробном смещении между
	# соседними тайлами появляются швы и по всей карте проступает сетка.
	view_off = (size * 0.5 - player.camera + shake).round()
	_view = Rect2(
		player.camera.x - size.x * 0.5 - Cfg.TILE,
		player.camera.y - size.y * 0.5 - Cfg.TILE,
		size.x + Cfg.TILE * 2.0,
		size.y + Cfg.TILE * 2.0)

	draw_set_transform(view_off)
	_draw_tiles()
	_draw_ao()
	_draw_pickups()
	_draw_weapon_pickups()
	_draw_perk_drops()
	_draw_flags()
	_draw_mines()
	_draw_debris()
	_draw_base()
	_draw_wrecks()
	_draw_tanks()
	_draw_bullets()
	_draw_particles()
	_draw_floaters()
	_draw_offscreen_markers(size)

	draw_set_transform(Vector2.ZERO)
	_draw_weather(size)

	if player.damage_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size),
			Color(1, 0, 0, (float(player.damage_flash) / 12.0) * 0.28))

	if player.tank != null and not player.tank.alive:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		var secs := int(ceil(float(player.tank.respawn_timer) / 60.0))
		var text := I18n.t("render.respawn", {"n": maxi(0, secs)},
			"Возрождение через %d..." % maxi(0, secs))
		_text_center(text, size * 0.5, 26, Color("#ff6666"), true)

## Затенение у стен и в углах — поверх тайлов, но под всем остальным.
func _draw_ao() -> void:
	if ao == null:
		return
	var tex := ao.texture(world.map)
	if tex != null:
		draw_texture_rect(tex, Rect2(0.0, 0.0, world.map.width, world.map.height), false)

# ---------------------------------------------------------------- помощники
func _in_view(x: float, y: float, margin: float) -> bool:
	return x >= _view.position.x - margin and x <= _view.end.x + margin \
		and y >= _view.position.y - margin and y <= _view.end.y + margin

func _rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)

func _text_center(text: String, pos: Vector2, size: int, color: Color, bold: bool = false) -> void:
	var font: Font = Fonts.bold if bold else Fonts.regular
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(pos.x - w * 0.5, pos.y + size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

# ------------------------------------------------------------------ погода
## Ночная тьма, туман, дождь и вспышки молний — в экранных координатах.
func _draw_weather(size: Vector2) -> void:
	var w := world.weather
	if w == null:
		return
	# Настройки могут приглушить погоду или выключить её совсем.
	var k := Sets.weather_scale()

	# --- ночная тьма: полупрозрачный слой по уровню освещения.
	var dark := (1.0 - w.light) * 0.55 if Sets.day_night else 0.0
	if dark > 0.01:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.039, 0.055, 0.133, dark))

	# --- туман: плавающие полупрозрачные пятна.
	if w.fog * k > 0.02:
		# Пятен тем больше, чем гуще туман: при полной густоте их четырнадцать,
		# и сквозь них дальний край экрана уже не читается — ровно так же,
		# как перестают видеть боты.
		var count := int(round(w.fog * k * 14.0))
		for i in count:
			var cx := Rng.hash01(i, 7) * size.x + sin(world.tick * 0.003 + i * 2.1) * 40.0
			var cy := Rng.hash01(i, 13) * size.y + cos(world.tick * 0.002 + i * 1.7) * 30.0
			var r := 90.0 + Rng.hash01(i, 29) * 130.0
			var fog_a := (0.02 + w.fog * 0.075) * k
			draw_circle(Vector2(cx, cy), r, Color(0.86, 0.89, 0.94, fog_a))
			draw_circle(Vector2(cx, cy), r * 0.6, Color(0.86, 0.89, 0.94, fog_a))

	# --- дождь: наклонные штрихи, падающие вниз.
	if w.rain * k > 0.03:
		var count := int(round(w.rain * k * 130.0))
		var col := Color(0.59, 0.71, 0.92, (0.15 + w.rain * 0.3) * k)
		for i in count:
			var x := Rng.hash01(i, 31) * size.x
			var speed := 6.0 + Rng.hash01(i, 41) * 6.0
			var y := Rng.fract(Rng.hash01(i, 43) + world.tick * 0.012 * speed) * (size.y + 40.0) - 20.0
			var length := 8.0 + Rng.hash01(i, 47) * 10.0
			draw_line(Vector2(x, y), Vector2(x - length * 0.4, y + length), col, 1.0)

	# --- снег: хлопья падают медленно и сносятся вбок.
	if w.snow * k > 0.03:
		# Белёсая пелена: снег не только сыплется, он ещё и лежит.
		draw_rect(Rect2(Vector2.ZERO, size),
			Color(0.88, 0.92, 0.97, w.snow * k * 0.10))
		var flakes := int(round(w.snow * k * 110.0))
		for i in flakes:
			var speed := 1.2 + Rng.hash01(i, 53) * 1.6
			var sx := Rng.hash01(i, 59) * size.x 				+ sin(world.tick * 0.008 + float(i)) * 26.0
			var sy := Rng.fract(Rng.hash01(i, 61) + world.tick * 0.0022 * speed) 				* (size.y + 30.0) - 15.0
			var r := 1.2 + Rng.hash01(i, 67) * 1.8
			draw_circle(Vector2(sx, sy), r,
				Color(1.0, 1.0, 1.0, (0.35 + w.snow * 0.4) * k))

	# --- вспышка молнии.
	if w.flash * k > 0.02:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.86, 0.92, 1.0, w.flash * k * 0.35))

# ------------------------------------------------------------------ тайлы
func _draw_tiles() -> void:
	var map := world.map
	var c0 := maxi(0, int(floor(_view.position.x / Cfg.TILE)))
	var c1 := mini(map.cols - 1, int(ceil(_view.end.x / Cfg.TILE)))
	var r0 := maxi(0, int(floor(_view.position.y / Cfg.TILE)))
	var r1 := mini(map.rows - 1, int(ceil(_view.end.y / Cfg.TILE)))

	# Земля с лёгкой шахматкой, чтобы читалась сетка и масштаб.
	#
	# В снегопад она выбеливается. Первая попытка накрывала весь экран одним
	# полупрозрачным слоем — и вся сцена уходила в бурый: цветокоррекция
	# подхватывала осветление и грела его. Подкрашивать надо саму землю,
	# а не кадр: цвета считаются один раз на кадр, лишних вызовов рисования
	# не появляется вовсе.
	var snow_k := 0.0
	if world.weather != null:
		snow_k = clampf(world.weather.snow * Sets.weather_scale(), 0.0, 1.0) * 0.55
	var g0: Color = Cfg.ground.lerp(Cfg.snow_ground, snow_k)
	var g1: Color = Cfg.ground_alt.lerp(Cfg.snow_ground, snow_k)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			_rect(c * Cfg.TILE, r * Cfg.TILE, Cfg.TILE, Cfg.TILE,
				g0 if (r + c) % 2 == 0 else g1)

	var water_phase := float(world.tick % 120) / 120.0

	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var tile := map.get_tile(r, c)
			if tile == Cfg.T_EMPTY:
				continue
			var x := float(c * Cfg.TILE)
			var y := float(r * Cfg.TILE)
			match tile:
				Cfg.T_WALL:
					_rect(x, y, Cfg.TILE, Cfg.TILE, Cfg.wall)
					_rect(x, y, Cfg.TILE, 3, Cfg.wall_top)
					_rect(x, y, 3, Cfg.TILE, Cfg.wall_top)
					_rect(x, y + Cfg.TILE - 3, Cfg.TILE, 3, Cfg.wall_edge)
					_rect(x + Cfg.TILE - 3, y, 3, Cfg.TILE, Cfg.wall_edge)
				Cfg.T_BRICK:
					_draw_roof_tile(x, y, r, c)
				Cfg.T_WATER:
					_draw_water_tile(x, y, r, c, water_phase)
				Cfg.T_SAND:
					_draw_sand_tile(x, y, r, c)
				Cfg.T_ROAD:
					_draw_road_tile(x, y, r, c)
				Cfg.T_BRIDGE:
					_draw_bridge_tile(x, y, r, c)
				Cfg.T_GRASS:
					_draw_grass_tile(x, y, r, c)
				Cfg.T_TREE:
					_draw_tree_tile(x, y, r, c)
				Cfg.T_BASE_P:
					_draw_base_tile(x, y, true)
				Cfg.T_BASE_E:
					_draw_base_tile(x, y, false)

## Крыша многоэтажки — 5 детерминированных по (r, c) вариантов. Кирпич
## остаётся кирпичом в логике, меняется только вид.
func _draw_roof_tile(x: float, y: float, r: int, c: int) -> void:
	# Вариант крыши и материал постройки — одно и то же число: как здание
	# выглядит, так оно и держит удар.
	var variant := Materials.variant_at(r, c)
	match variant:
		0:
			_roof_concrete(x, y)
		1:
			_roof_gravel(x, y, r, c)
		2:
			_roof_ribbed(x, y)
		3:
			_roof_wood(x, y, r, c)
		_:
			_roof_panel(x, y)
	# Бортик по краю, чтобы крыша читалась как приподнятая.
	_rect(x, y, Cfg.TILE, 2, Color(0, 0, 0, 0.18))
	_rect(x, y, 2, Cfg.TILE, Color(0, 0, 0, 0.18))
	_rect(x, y + Cfg.TILE - 2, Cfg.TILE, 2, Color(1, 1, 1, 0.10))
	_rect(x + Cfg.TILE - 2, y, 2, Cfg.TILE, Color(1, 1, 1, 0.10))
	# Следы попаданий поверх крыши.
	var dmg := world.map.damage_ratio(r, c)
	if dmg > 0.06:
		_draw_damage(x, y, r, c, dmg, Materials.at(r, c))

## Серый бетон с полосами стяжки и трещинкой.
func _roof_concrete(x: float, y: float) -> void:
	_rect(x, y, Cfg.TILE, Cfg.TILE, Color("#8f8a84"))
	for i in 3:
		_rect(x, y + 5 + i * 10, Cfg.TILE, 1, Color("#7b766f"))
	_rect(x + 9, y, 2, Cfg.TILE, Color(0, 0, 0, 0.15))

## Гравийная кровля — крапинки по тёмно-серому.
func _roof_gravel(x: float, y: float, r: int, c: int) -> void:
	_rect(x, y, Cfg.TILE, Cfg.TILE, Color("#6f6b66"))
	for i in 10:
		var px := x + float((r * 31 + c * 17 + i * 13) % 27) + 2.0
		var py := y + float((r * 13 + c * 29 + i * 7) % 27) + 2.0
		_rect(px, py, 3, 3, Color("#7d7872") if i % 2 == 1 else Color("#5f5b56"))

## Профнастил — частые поперечные рёбра.
func _roof_ribbed(x: float, y: float) -> void:
	_rect(x, y, Cfg.TILE, Cfg.TILE, Color("#6e7b8a"))
	for i in 8:
		_rect(x, y + i * 4 + 1, Cfg.TILE, 2, Color("#5b6775"))
	for i in 8:
		_rect(x, y + i * 4, Cfg.TILE, 1, Color(1, 1, 1, 0.18))

## Деревянная постройка: доски с зазорами и сучками. Самая слабая цель
## на карте, поэтому и выглядеть должна соответствующе.
func _roof_wood(x: float, y: float, r: int, c: int) -> void:
	var mat := Materials.WOOD
	_rect(x, y, Cfg.TILE, Cfg.TILE, mat["base"])
	# Доски поперёк тайла, между ними тёмные щели.
	for i in 4:
		var py := y + i * 8.0
		_rect(x, py, Cfg.TILE, 7, mat["light"] if i % 2 == 0 else mat["base"])
		_rect(x, py + 7, Cfg.TILE, 1, mat["dark"])
	# Сучки и торцы гвоздей — детерминированы координатами.
	for i in 3:
		var px := x + float((r * 11 + c * 7 + i * 9) % 26) + 3.0
		var py2 := y + float((r * 5 + c * 13 + i * 7) % 26) + 3.0
		_rect(px, py2, 2, 2, mat["dark"])

## Панельная кровля с рулонным покрытием и парапетом.
func _roof_panel(x: float, y: float) -> void:
	_rect(x, y, Cfg.TILE, Cfg.TILE, Color("#9a948c"))
	_rect(x + 3, y + 3, Cfg.TILE - 6, Cfg.TILE - 6, Color("#b3aca2"))
	draw_rect(Rect2(x + 3, y + 3, Cfg.TILE - 6, Cfg.TILE - 6), Color("#7c766d"), false, 1.0)

## Следы попаданий на постройке. Рисунок детерминирован координатами тайла,
## поэтому трещины не «дрожат» между кадрами, а растут по мере обстрела.
##
## У каждого материала свой характер повреждений: дерево трескается вдоль
## досок и теряет их целиком, металл сминается вмятинами, камень и бетон
## идут сеткой трещин и вываливаются кусками.
func _draw_damage(x: float, y: float, r: int, c: int, ratio: float, mat: Dictionary) -> void:
	var id := String(mat["id"])
	var seed_base := r * 92837111 + c * 689287499
	# Общее потемнение выбитой поверхности.
	draw_rect(Rect2(x, y, Cfg.TILE, Cfg.TILE), Color(0, 0, 0, 0.10 + 0.22 * ratio))

	if id == "wood":
		# Расщепление вдоль досок: доски лопаются одна за другой.
		var broken := int(ratio * 4.0)
		for i in broken:
			var py := y + float((i * 8) % 32) + 2.0
			_rect(x + 1, py, Cfg.TILE - 2, 3, Color(0.07, 0.05, 0.04, 0.85))
			_rect(x + 1 + Rng.hash01(seed_base + i, 5) * 12.0, py - 2, 4, 7,
				Color(0.05, 0.04, 0.03, 0.7))
		return

	if id == "metal":
		# Вмятины: металл гнётся, а не крошится.
		var dents := 1 + int(ratio * 3.0)
		for i in dents:
			var dx := x + 5.0 + Rng.hash01(seed_base + i, 11) * 20.0
			var dy := y + 5.0 + Rng.hash01(seed_base + i, 23) * 20.0
			var rr := 2.5 + ratio * 3.5
			draw_circle(Vector2(dx, dy), rr, Color(0, 0, 0, 0.35))
			draw_circle(Vector2(dx - 0.8, dy - 0.8), rr * 0.6, mat["light"])
		if ratio > 0.65:
			# Отогнутый лист у края.
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + Cfg.TILE - 10, y + 2), Vector2(x + Cfg.TILE - 2, y + 6),
				Vector2(x + Cfg.TILE - 6, y + 14),
			]), Color(0, 0, 0, 0.5))
		return

	# Камень и бетон: сетка трещин из одной точки, потом дыры.
	var cx := x + 8.0 + Rng.hash01(seed_base, 3) * 16.0
	var cy := y + 8.0 + Rng.hash01(seed_base, 7) * 16.0
	var cracks := 2 + int(ratio * 4.0)
	for i in cracks:
		var a := Rng.hash01(seed_base + i, 13) * TAU
		var len_px := (6.0 + ratio * 12.0) * (0.6 + Rng.hash01(seed_base + i, 17))
		draw_line(Vector2(cx, cy),
			Vector2(cx + cos(a) * len_px, cy + sin(a) * len_px),
			Color(0, 0, 0, 0.55), 1.0 + ratio)
	if ratio > 0.6:
		for i in 2:
			var hx := x + 6.0 + Rng.hash01(seed_base + i, 29) * 20.0
			var hy := y + 6.0 + Rng.hash01(seed_base + i, 31) * 20.0
			draw_circle(Vector2(hx, hy), 2.0 + ratio * 2.5, Color(0.03, 0.03, 0.03, 0.8))

## Обломки разрушенных построек: лежат на земле под танками.
func _draw_debris() -> void:
	for piece in world.debris:
		if not _in_view(piece.x, piece.y, 24):
			continue
		var a: float = piece.fade
		var pos := Vector2(piece.x, piece.y)
		draw_set_transform(view_off + pos, piece.angle)
		# Тень под куском отделяет его от земли.
		draw_rect(Rect2(-piece.w * 0.5 + 1.0, -piece.h * 0.5 + 1.5, piece.w, piece.h),
			Color(0, 0, 0, 0.35 * a))
		var c: Color = piece.color
		c.a = a
		draw_rect(Rect2(-piece.w * 0.5, -piece.h * 0.5, piece.w, piece.h), c)
	draw_set_transform(view_off)

## Песчаный берег: база с крапинками и светлой кромкой у воды.
## Знак работающей способности. Рисуется в системе координат танка, уже
## после корпуса и башни, поэтому ложится поверх.
func _draw_ability_state(tank: Tank) -> void:
	var ab := Abilities.get_ability(tank.ability_id)
	if ab.is_empty():
		return
	var col: Color = ab.get("color", Color.WHITE)
	var pulse := 0.55 + 0.25 * sin(float(world.tick) * 0.25)

	match tank.ability_id:
		"smoke":
			# Клубы вокруг корпуса: они и есть эффект — за ними танк
			# не видно ни игроку, ни боту.
			for i in 7:
				var a := float(i) / 7.0 * TAU + float(world.tick) * 0.02
				var r := 20.0 + 5.0 * sin(float(world.tick) * 0.08 + float(i))
				draw_circle(Vector2(cos(a) * r, sin(a) * r), 9.0,
					Color(0.82, 0.85, 0.88, 0.32))
		"silencer":
			# Глушитель на срезе ствола — виден и с чужого экрана.
			draw_set_transform(view_off + Vector2(tank.x, tank.y), tank.turret_angle)
			var shape := TankArt.chassis(tank.chassis_id)
			var tip: float = float(shape["turret_r"]) * 0.5 + float(shape["barrel_len"])
			_rect(tip - 9.0, -4.0, 11.0, 8.0, Color("#2a2e33"))
			_rect(tip - 9.0, -4.0, 11.0, 2.0, Color("#454b52"))
			draw_set_transform(view_off + Vector2(tank.x, tank.y))
		"breaker":
			# Раскалённая головка снаряда: кольцо у башни и искры.
			draw_arc(Vector2.ZERO, 15.0, 0, TAU, 20, Color(col.r, col.g, col.b, pulse), 2.0)
			for i in 3:
				var a := float(world.tick) * 0.15 + float(i) * TAU / 3.0
				draw_circle(Vector2(cos(a) * 15.0, sin(a) * 15.0), 1.8, col)
		"grip":
			# Искры из-под гусениц: сцепление держит на любом грунте.
			for i in 4:
				var a := tank.body_angle + PI + (float(i) - 1.5) * 0.5
				draw_circle(Vector2(cos(a) * 14.0, sin(a) * 14.0), 1.6,
					Color(0.75, 0.85, 1.0, 0.8))
		"overclock":
			# Разгон: пульсирующее красное кольцо, ствол и так раскалён жаром.
			draw_arc(Vector2.ZERO, 17.0, 0, TAU, 20,
				Color(1.0, 0.35, 0.15, pulse), 2.5)
		_:
			draw_arc(Vector2.ZERO, 17.0, 0, TAU, 20,
				Color(col.r, col.g, col.b, pulse * 0.8), 2.0)

## Насколько всё занесено снегом: 0 — чисто, 0.55 — полный снегопад.
func _snow_k() -> float:
	if world.weather == null:
		return 0.0
	return clampf(world.weather.snow * Sets.weather_scale(), 0.0, 1.0) * 0.55

## Асфальт и мост — одно покрытие для разметки: мост продолжает улицу,
## поэтому линии не должны обрываться перед въездом.
func _is_paved(r: int, c: int) -> bool:
	var t := world.map.get_tile(r, c)
	return t == Cfg.T_ROAD or t == Cfg.T_BRIDGE

## Асфальт: латаное полотно с трещинами, бордюром по краю проезжей части
## и осевой разметкой вдоль улицы.
func _draw_road_tile(x: float, y: float, r: int, c: int) -> void:
	# Асфальт в снег светлеет слабее газона: его чистят, да и лежит на нём
	# меньше.
	var k := _snow_k() * 0.6
	_rect(x, y, Cfg.TILE, Cfg.TILE,
		(Cfg.road if (r * 7 + c * 11) % 3 == 0 else Cfg.road_alt).lerp(Cfg.snow_ground, k))
	# Заплатки и трещины — детерминированы по клетке, поэтому не мерцают.
	for i in 3:
		var px := x + float((r * 17 + c * 5 + i * 9) % 25) + 3.0
		var py := y + float((r * 5 + c * 17 + i * 13) % 25) + 3.0
		_rect(px, py, 4, 2, Cfg.road_crack)

	var up := _is_paved(r - 1, c)
	var down := _is_paved(r + 1, c)
	var left := _is_paved(r, c - 1)
	var right := _is_paved(r, c + 1)
	# Перекрёсток и середина площади остаются пустым асфальтом.
	if up and down and left and right:
		return

	# Бордюр там, где проезжая часть кончается.
	if not up:
		_rect(x, y, Cfg.TILE, 2, Cfg.road_edge)
	if not down:
		_rect(x, y + Cfg.TILE - 2, Cfg.TILE, 2, Cfg.road_edge)
	if not left:
		_rect(x, y, 2, Cfg.TILE, Cfg.road_edge)
	if not right:
		_rect(x + Cfg.TILE - 2, y, 2, Cfg.TILE, Cfg.road_edge)

	# Осевая: только на улице шириной в две-три полосы. Ширину определяем
	# по соседям через одного — иначе разметка расползалась бы по площадям
	# и парковкам, где никакой оси нет.
	if up and down and not _is_paved(r, c - 2) and not _is_paved(r, c + 2):
		if left and right:
			# Проспект в три полосы: ось идёт по середине средней.
			_rect(x + Cfg.TILE * 0.5 - 1.0, y + 4, 2, 10, Cfg.road_line)
			_rect(x + Cfg.TILE * 0.5 - 1.0, y + 18, 2, 10, Cfg.road_line)
		elif left:
			# Улица в две полосы: ось — стык колонок.
			_rect(x, y + 4, 2, 10, Cfg.road_line)
			_rect(x, y + 18, 2, 10, Cfg.road_line)
	elif left and right and not _is_paved(r - 2, c) and not _is_paved(r + 2, c):
		if up and down:
			_rect(x + 4, y + Cfg.TILE * 0.5 - 1.0, 10, 2, Cfg.road_line)
			_rect(x + 18, y + Cfg.TILE * 0.5 - 1.0, 10, 2, Cfg.road_line)
		elif up:
			_rect(x + 4, y, 10, 2, Cfg.road_line)
			_rect(x + 18, y, 10, 2, Cfg.road_line)

## Мост: настил над водой с перилами по бокам. Перила ставятся только там,
## где рядом нет соседней секции, иначе они делили бы проезд пополам.
func _draw_bridge_tile(x: float, y: float, r: int, c: int) -> void:
	_rect(x, y, Cfg.TILE, Cfg.TILE, Cfg.bridge)

	var horizontal := _is_paved(r, c - 1) or _is_paved(r, c + 1)
	# Швы настила идут поперёк движения.
	for i in 4:
		var o := float(i * 8 + 1)
		if horizontal:
			_rect(x + o, y, 1, Cfg.TILE, Cfg.bridge_dark)
		else:
			_rect(x, y + o, Cfg.TILE, 1, Cfg.bridge_dark)

	if horizontal:
		if not _is_paved(r - 1, c):
			_rect(x, y, Cfg.TILE, 3, Cfg.bridge_rail)
			_rect(x, y + 3, Cfg.TILE, 1, Cfg.bridge_dark)
		if not _is_paved(r + 1, c):
			_rect(x, y + Cfg.TILE - 3, Cfg.TILE, 3, Cfg.bridge_rail)
			_rect(x, y + Cfg.TILE - 4, Cfg.TILE, 1, Cfg.bridge_dark)
	else:
		if not _is_paved(r, c - 1):
			_rect(x, y, 3, Cfg.TILE, Cfg.bridge_rail)
			_rect(x + 3, y, 1, Cfg.TILE, Cfg.bridge_dark)
		if not _is_paved(r, c + 1):
			_rect(x + Cfg.TILE - 3, y, 3, Cfg.TILE, Cfg.bridge_rail)
			_rect(x + Cfg.TILE - 4, y, 1, Cfg.TILE, Cfg.bridge_dark)

## Газон парка: трава с кустиками, по ней танк идёт чуть медленнее.
func _draw_grass_tile(x: float, y: float, r: int, c: int) -> void:
	var k := _snow_k()
	var base: Color = (Cfg.grass if (r + c) % 2 == 0 else Cfg.grass_alt) 		.lerp(Cfg.snow_ground, k)
	_rect(x, y, Cfg.TILE, Cfg.TILE, base)
	for i in 5:
		var px := x + float((r * 11 + c * 19 + i * 7) % 27) + 2.0
		var py := y + float((r * 19 + c * 11 + i * 5) % 25) + 3.0
		_rect(px, py, 2, 4, Cfg.grass_dark)

func _draw_sand_tile(x: float, y: float, r: int, c: int) -> void:
	_rect(x, y, Cfg.TILE, Cfg.TILE, Cfg.sand)
	for i in 6:
		var px := x + float((r * 13 + c * 7 + i * 5) % 26) + 3.0
		var py := y + float((r * 7 + c * 13 + i * 11) % 26) + 3.0
		_rect(px, py, 2, 2, Cfg.sand_dark)
	_rect(x, y, Cfg.TILE, 2, Cfg.sand_light)
	_rect(x, y, 2, Cfg.TILE, Cfg.sand_light)

func _draw_water_tile(x: float, y: float, r: int, c: int, phase: float) -> void:
	_rect(x, y, Cfg.TILE, Cfg.TILE, Cfg.water)
	# Две «волны», сдвинутые по фазе — дешёвая анимация без затрат.
	var wave := sin((r + c) * 0.7 + phase * TAU)
	var h := 2.0 + wave
	var col := Cfg.water_light
	col.a = 0.45
	_rect(x + 2, y + 8 + wave * 2.0, Cfg.TILE - 4, h, col)
	_rect(x + 4, y + 20 - wave * 2.0, Cfg.TILE - 10, h, col)

func _draw_tree_tile(x: float, y: float, r: int, c: int) -> void:
	draw_circle(Vector2(x + 16, y + 18), 13, Cfg.tree_dark)
	# Смещение кроны детерминировано координатами — картинка не «дрожит».
	var ox := float((r * 7 + c * 13) % 5) - 2.0
	var oy := float((r * 11 + c * 5) % 5) - 2.0
	draw_circle(Vector2(x + 16 + ox, y + 15 + oy), 10, Cfg.tree)

func _draw_base_tile(x: float, y: float, is_player: bool) -> void:
	var color := Cfg.base_p if is_player else Cfg.base_e
	var fill := color
	fill.a = 0.25
	_rect(x, y, Cfg.TILE, Cfg.TILE, fill)
	var pulse := 0.5 + 0.5 * sin(world.tick * 0.06)
	var stroke := color
	stroke.a = 0.5 + pulse * 0.5
	draw_rect(Rect2(x + 3, y + 3, Cfg.TILE - 6, Cfg.TILE - 6), stroke, false, 2.0)
	_text_center("⌂", Vector2(x + Cfg.TILE * 0.5, y + Cfg.TILE * 0.5), 14, color, true)

# ------------------------------------------------------------------ объекты
func _draw_pickups() -> void:
	for p in world.pickups:
		if not p.active or not _in_view(p.x, p.y, 20):
			continue
		var bob := sin(world.tick * 0.08 + p.bob) * 2.0
		var y: float = p.y + bob
		_rect(p.x - 8, y - 8, 16, 16, Color.WHITE)
		_rect(p.x - 6, y - 2, 12, 4, Color("#dd3333"))
		_rect(p.x - 2, y - 6, 4, 12, Color("#dd3333"))
		draw_arc(Vector2(p.x, y), 13, 0, TAU, 24, Color(1, 1, 1, 0.35), 1.0)

## Power-up оружия: цветной шестиугольник с иконкой.
func _draw_weapon_pickups() -> void:
	for p in world.weapon_pickups:
		if not p.active or not _in_view(p.x, p.y, 24):
			continue
		var weapon := Weapons.get_weapon(p.weapon_id)
		if weapon.is_empty():
			continue
		var bob := sin(world.tick * 0.09 + p.bob) * 2.5
		var y: float = p.y + bob

		# Пульсирующее кольцо — бросается в глаза.
		var pulse := 0.35 + 0.25 * sin(world.tick * 0.12)
		var glow: Color = weapon["color"]
		glow.a = pulse
		draw_circle(Vector2(p.x, y), 20, glow)

		# Шестиугольная «ячейка» оружия.
		var pts := PackedVector2Array()
		for i in 6:
			var a := (PI / 3.0) * i + PI / 6.0
			pts.append(Vector2(p.x + cos(a) * 15.0, y + sin(a) * 15.0))
		draw_colored_polygon(pts, Color(0.06, 0.08, 0.10, 0.92))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, weapon["color"], 2.0)

		_text_center(String(weapon["icon"]), Vector2(p.x, y), 13, Color.WHITE)

## Выпавшие из убитых перки («Царь горы»).
func _draw_perk_drops() -> void:
	for drop in world.perk_drops:
		if not drop.active or not _in_view(drop.x, drop.y, 26):
			continue
		var bob := sin(world.tick * 0.07 + drop.bob) * 3.0
		var y: float = drop.y + bob
		draw_circle(Vector2(drop.x, y), 20, Color(1, 0.53, 1, 0.25))
		draw_circle(Vector2(drop.x, y), 15, Color(0.16, 0.06, 0.19, 0.85))
		draw_arc(Vector2(drop.x, y), 15, 0, TAU, 28, Color("#ff88ff"), 1.5)
		_text_center(Perks.perk_icon(drop.perk_id), Vector2(drop.x, y), 14, Color.WHITE)

func _draw_flags() -> void:
	for flag in world.flags:
		if not _in_view(flag.x, flag.y, 30):
			continue
		var color: Color = Cfg.flag_player if flag.team == "player" else Cfg.flag_enemy
		var carried: bool = flag.carried
		var lift := -18.0 if carried else sin(world.tick * 0.06) * 2.0

		# Домашняя метка, если флаг унесли.
		if not flag.at_home and _in_view(flag.home_x, flag.home_y, 30):
			var ghost := color
			ghost.a = 0.35
			draw_arc(Vector2(flag.home_x, flag.home_y), 16, 0, TAU, 24, ghost, 2.0)

		draw_line(Vector2(flag.x, flag.y + lift + 12), Vector2(flag.x, flag.y + lift - 14),
			Color("#dddddd"), 2.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(flag.x, flag.y + lift - 14),
			Vector2(flag.x + 16, flag.y + lift - 9),
			Vector2(flag.x, flag.y + lift - 4),
		]), color)

		if not carried and flag.return_timer > 0:
			_text_center("%d%s" % [int(ceil(float(flag.return_timer) / 60.0)), I18n.t("hud.sec", {}, "с")],
				Vector2(flag.x, flag.y + 24), 10, Color("#ffcc66"))

func _draw_mines() -> void:
	for mine in world.mines:
		if not _in_view(mine.x, mine.y, 30):
			continue
		draw_circle(Vector2(mine.x, mine.y), 6, Color("#666666"))
		var blink := (int(mine.timer / 20) % 2 == 0) if mine.timer > 120 else (int(mine.timer / 6) % 2 == 0)
		if blink:
			draw_circle(Vector2(mine.x, mine.y), 2.5,
				Color("#ff4444") if mine.armed else Color("#ffaa44"))
		if mine.timer < 180 or mine.timer > Cfg.MINE_LIFE - 60:
			draw_arc(Vector2(mine.x, mine.y), Cfg.MINE_TRIGGER_R, 0, TAU, 24,
				Color(1, 0.27, 0.27, 0.3), 1.0)

## База «Оборона»: кольцевая крепость с полоской прочности.
func _draw_base() -> void:
	var base = world.base
	if base == null or not _in_view(base["x"], base["y"], 80):
		return

	var pos := Vector2(base["x"], base["y"])
	var pulse := sin(world.tick * 0.05) * 3.0
	var ratio: float = float(base["hp"]) / float(base["max_hp"])

	# Платформа под крепостью.
	draw_circle(pos, 34, Color("#3a3a3a"))
	draw_arc(pos, 34, 0, TAU, 48, Color("#555555"), 2.0)

	# Кольцо-стена, пульсирует на повреждениях.
	var ring := Color("#6a9a5a") if ratio > 0.5 else (Color("#ccaa44") if ratio > 0.25 else Color("#cc4444"))
	draw_arc(pos, 24 + pulse, 0, TAU, 48, ring, 4.0)

	# Ядро.
	var core := Color("#7abf6a") if ratio > 0.5 else (Color("#ddc255") if ratio > 0.25 else Color("#dd5555"))
	draw_circle(pos, 14, core)
	_text_center("🏰", pos, 14, Color.WHITE)

	# Полоска прочности над крепостью.
	var w := 56.0
	var h := 6.0
	var bx := pos.x - w * 0.5
	var by := pos.y - 52.0
	_rect(bx - 1, by - 1, w + 2, h + 2, Color(0, 0, 0, 0.55))
	var bar := Color("#44cc44") if ratio > 0.5 else (Color("#cccc44") if ratio > 0.25 else Color("#cc4444"))
	_rect(bx, by, w * maxf(0.0, ratio), h, bar)

func _draw_bullets() -> void:
	for b in world.bullets:
		if not b.alive or not _in_view(b.x, b.y, 10):
			continue
		var pos := Vector2(b.x, b.y)
		if b.lobbed:
			# Миномётный снаряд: оранжевый огонёк с дымным хвостом.
			draw_line(pos - Vector2(b.vx, b.vy) * 3.0, pos, Color(0.67, 0.67, 0.67, 0.3), 3.0)
			draw_circle(pos, 4, Color("#ff9933"))
			draw_circle(pos, 1.8, Color("#ffe8a0"))
			continue
		var color: Color = Cfg.bullet if b.from_player else Cfg.bullet_enemy
		# Короткий след — читается направление полёта.
		var trail := color
		trail.a = 0.35
		draw_line(pos - Vector2(b.vx, b.vy) * 2.5, pos, trail, 2.0)
		draw_circle(pos, 3, color)
		draw_circle(pos, 1.4, Color.WHITE)

	# Ракеты авиаудара: огненная комета с хвостом.
	for r in world.airstrikes:
		if not r.alive or not _in_view(r.x, r.y, 12):
			continue
		var pos := Vector2(r.x, r.y)
		draw_line(pos - Vector2(r.vx, r.vy) * 4.0, pos, Color(1, 0.67, 0.27, 0.35), 4.0)
		draw_circle(pos, 5, Color("#ff8833"))
		draw_circle(pos, 2.2, Color("#fff6cc"))

func _draw_particles() -> void:
	var ps := world.particles
	for i in ps.count:
		var x := ps.px[i]
		var y := ps.py[i]
		if not _in_view(x, y, 10):
			continue
		var c: Color = ps.color[i]
		c.a = maxf(0.0, ps.life[i] / ps.max_life[i])
		var s := ps.size[i]
		_rect(x - s * 0.5, y - s * 0.5, s, s, c)

func _draw_floaters() -> void:
	for f in floaters:
		if not _in_view(f["x"], f["y"], 30):
			continue
		var alpha: float = minf(1.0, float(f["life"]) / 20.0)
		var shadow := Color(0, 0, 0, alpha)
		var c: Color = f["color"]
		c.a = alpha
		_text_center(f["text"], Vector2(f["x"] + 1, f["y"] + 1), 13, shadow, true)
		_text_center(f["text"], Vector2(f["x"], f["y"]), 13, c, true)

## Догорающие остовы подбитых танков: лежат на земле, поэтому рисуются
## до живых танков — те проезжают поверх.
func _draw_wrecks() -> void:
	for wreck in world.wrecks:
		if not _in_view(wreck.x, wreck.y, 40):
			continue
		_draw_wreck(wreck)

func _draw_wreck(wreck) -> void:
	var palette := Cfg.team_palette(wreck.color_key)
	var pos := Vector2(wreck.x, wreck.y)
	var a: float = wreck.fade          # 1 — только подбит, 0 — исчезает
	var s: float = wreck.scale
	var hw := Cfg.TANK_W * 0.5 * s
	var hh := Cfg.TANK_H * 0.5 * s

	# Копоть на земле под остовом.
	draw_set_transform(view_off + pos)
	_draw_ellipse(Vector2(0, 2), hw * 1.5, hh * 1.2, Color(0.03, 0.02, 0.02, 0.45 * a))

	# ---- корпус, лежит под тем же углом, что стоял танк
	draw_set_transform(view_off + pos, wreck.angle + PI / 2.0)
	var track := Color(0.10, 0.09, 0.09, a)
	_rect(-hw - 2.0 * s, -hh, 6.0 * s, hh * 2.0, track)
	_rect(hw - 4.0 * s, -hh, 6.0 * s, hh * 2.0, track)

	# Обгоревшая броня сохраняет оттенок команды, но почти чёрная.
	# Совсем чёрный корпус сливался с землёй, и остов читался только по огню.
	var burnt: Color = palette["dark"].darkened(0.5)
	burnt.a = a
	_rect(-hw + 3.0 * s, -hh + 2.0 * s, hw * 2.0 - 6.0 * s, hh * 2.0 - 4.0 * s, burnt)
	# Светлая кромка по верху отделяет силуэт от земли.
	var edge: Color = palette["body"].darkened(0.35)
	edge.a = a * 0.8
	_rect(-hw + 4.0 * s, -hh + 2.0 * s, hw * 2.0 - 8.0 * s, 2.0 * s, edge)
	# Пятна прогара.
	_rect(-hw + 5.0 * s, -hh + 5.0 * s, hw * 0.9, hh * 0.7, Color(0.06, 0.05, 0.05, a))
	_rect(hw * 0.1, hh * 0.1, hw * 0.7, hh * 0.6, Color(0.06, 0.05, 0.05, a))
	# Пробоина.
	draw_circle(Vector2(0, -2.0 * s), 4.5 * s, Color(0.02, 0.02, 0.02, a))

	# ---- сорванная башня рядом
	draw_set_transform(view_off + pos + wreck.turret_offset, wreck.turret_angle)
	draw_circle(Vector2.ZERO, 7.0 * s, Color(0.09, 0.08, 0.08, a))
	_rect(0, -2.0 * s, 18.0 * s, 4.0 * s, Color(0.07, 0.06, 0.06, a))

	# ---- пламя: три язычка с разной частотой мерцания
	draw_set_transform(view_off)
	for i in 3:
		var phase: float = world.tick * (0.22 + 0.05 * i) + wreck.turret_angle + i * 2.1
		var flicker := 0.55 + 0.45 * sin(phase)
		var r := (3.5 + 2.5 * flicker) * s
		var fx: float = wreck.x + cos(i * 2.4 + wreck.turret_angle) * 6.0 * s
		var fy: float = wreck.y + sin(i * 2.4 + wreck.turret_angle) * 5.0 * s - 2.0
		draw_circle(Vector2(fx, fy), r * 1.7, Color(1.0, 0.42, 0.10, 0.20 * a * flicker))
		draw_circle(Vector2(fx, fy), r, Color(1.0, 0.72, 0.24, 0.75 * a * flicker))
		draw_circle(Vector2(fx, fy), r * 0.45, Color(1.0, 0.94, 0.72, 0.85 * a * flicker))

# ------------------------------------------------------------------ танки
func _draw_tanks() -> void:
	for tank in world.tanks:
		if not tank.alive or not _in_view(tank.x, tank.y, 40):
			continue
		_draw_tank(tank)

func _draw_tank(tank: Tank) -> void:
	var palette := Cfg.team_palette(tank.color_key)
	var shape := TankArt.chassis(tank.chassis_id)
	var is_viewer := player.tank == tank
	var is_ally := player.tank != null and not world.are_hostile(player.tank, tank) and not is_viewer
	var pos := Vector2(tank.x, tank.y)
	var hw := tank.width * 0.5
	var hh := tank.height * 0.5

	# Тень под корпусом — отделяет танк от земли.
	draw_set_transform(view_off + pos)
	_draw_ellipse(Vector2(2, 4), hw * 1.05, hh / 1.2, Color(0, 0, 0, 0.25))

	# ---- ходовая --------------------------------------------------------
	draw_set_transform(view_off + pos, tank.body_angle + PI / 2.0)
	var track_id := String(tank.cosmetics.get("track", "none"))
	var track_fill := Cosmetics.color_of("track", track_id, Color("#2a2a2a"))
	var track_tread := Cosmetics.color_of("track", track_id, Color("#4a4a4a"))
	var tw := float(shape["track_w"])
	# Катки и траки рисуются прямоугольниками, а не кругами: на танке
	# высотой 28 px разницы не видно, а draw_circle — полигон, и на
	# разделённом экране полсотни танков это стоило 9 мс на кадр.
	var wheel_col := Color(0, 0, 0, 0.45)
	var wheels := int(shape["wheels"])
	var wheel_r := tw * 0.30
	for side in [-1.0, 1.0]:
		var tx: float = side * hw - tw * 0.5
		_rect(tx, -hh, tw, tank.height, track_fill)
		for k in wheels:
			var wy := -hh + tank.height * (float(k) + 0.5) / float(wheels)
			_rect(tx + tw * 0.5 - wheel_r, wy - wheel_r, wheel_r * 2.0, wheel_r * 2.0, wheel_col)
		# Ведущее и направляющее колесо крупнее катков.
		_rect(tx + 0.5, -hh + 0.5, tw - 1.0, tw * 0.8, wheel_col)
		_rect(tx + 0.5, hh - tw * 0.8 - 0.5, tw - 1.0, tw * 0.8, wheel_col)
	# Траки «прокручиваются» вместе с движением.
	var tread_shift := float(int((tank.x + tank.y) / 4.0) % 8)
	var ty := -hh + tread_shift
	while ty < hh:
		_rect(-hw - tw * 0.5, ty, tw, 2, track_tread)
		_rect(hw - tw * 0.5, ty, tw, 2, track_tread)
		ty += 8.0

	# ---- корпус ---------------------------------------------------------
	# Лоб со скосом: у разведчика он длинный и острый, у громилы почти
	# плоский. Форма читается даже когда цвет не виден.
	var nose := tank.height * float(shape["nose"])
	# Лоб не просто скошен, а сужен: разведчик получается клиновидным,
	# громила — почти прямоугольным. Это и есть главный признак роли.
	var nose_hw: float = (hw - 1.0) * (1.0 - float(shape["nose"]) * 0.9)
	var body := PackedVector2Array([
		Vector2(-hw + 1.0, -hh + nose),
		Vector2(-nose_hw, -hh),
		Vector2(nose_hw, -hh),
		Vector2(hw - 1.0, -hh + nose),
		Vector2(hw - 1.0, hh - 2.0),
		Vector2(hw - 4.0, hh),
		Vector2(-hw + 4.0, hh),
		Vector2(-hw + 1.0, hh - 2.0),
	])
	draw_colored_polygon(body, palette["body"])

	# Камуфляж ложится под наклейки и обрезается по габаритам корпуса.
	_draw_camo(tank, hw, hh, palette)

	# Моторный отсек сзади и светлая полоса по лбу — объём без источника света.
	_rect(-hw + 3.0, hh - 8.0, tank.width - 6.0, 6.0, palette["dark"])
	_rect(-hw + 4.5, hh - 6.5, tank.width - 9.0, 1.2, Color(0, 0, 0, 0.35))
	_rect(-hw + 5.0, -hh + nose + 1.0, tank.width - 10.0, 2.5, palette["trim"])

	# Накладная броня у тяжёлых корпусов — с заклёпками.
	if bool(shape["plates"]):
		for side in [-1.0, 1.0]:
			var px: float = side * (hw - 3.5) - 1.5
			_rect(px, -hh + nose, 3.0, tank.height - nose - 4.0, palette["dark"])
			for k in 3:
				_rect(px + 0.8, -hh + nose + 3.5 + float(k) * 6.0, 1.6, 1.6,
					Color(1, 1, 1, 0.35))

	# Предупреждающие полосы босса.
	if bool(shape["stripes"]):
		for k in 3:
			_rect(-hw + 4.0 + float(k) * 7.0, -hh + nose, 3.0, tank.height - nose - 5.0,
				Color(0.95, 0.75, 0.1, 0.75))

	# Рисунок корпуса (косметика-наклейка).
	_draw_hull_pattern(tank, hw, hh)

	# Кромки: светлая по левому борту, тёмная по правому. Свет считается
	# один на всю карту, поэтому танки затенены согласованно друг с другом.
	var light := PI * 0.75 - tank.body_angle
	var lit := Color(1, 1, 1, 0.13)
	var shade := Color(0, 0, 0, 0.22)
	_rect(-hw + 1.0, -hh + nose, 1.5, tank.height - nose - 2.0,
		lit if cos(light) < 0.0 else shade)
	_rect(hw - 2.5, -hh + nose, 1.5, tank.height - nose - 2.0,
		shade if cos(light) < 0.0 else lit)

	# Копоть по мере потери прочности: подбитый танк видно до полоски HP.
	var wear := 1.0 - clampf(tank.hp / tank.max_hp, 0.0, 1.0)
	if wear > 0.35:
		var soot := Color(0.05, 0.04, 0.03, (wear - 0.35) * 0.7)
		_rect(-hw + 3.0, -hh + nose, tank.width - 6.0, tank.height - nose - 4.0, soot)

	# ---- башня ----------------------------------------------------------
	var turret_id := String(tank.cosmetics.get("turret", "none"))
	var has_turret_color := turret_id != "" and turret_id != "none"
	var barrel_base := Cosmetics.color_of("turret", turret_id, Color("#4d545c"))
	var barrel_dark := Cosmetics.color_of("turret", turret_id, Color("#2b3036"))
	var tr := float(shape["turret_r"])
	var bl := float(shape["barrel_len"])
	var bw := float(shape["barrel_w"])

	draw_set_transform(view_off + pos, tank.turret_angle)
	# Ствол считается от края башни, поэтому вылет виден целиком: у снайпера
	# он вдвое длиннее обычного, у миномёта — короткий и вдвое толще.
	var b0 := tr * 0.5
	var b1 := b0 + bl
	match String(shape["muzzle"]):
		"twin":
			# Спаренная установка: два ствола вместо одного — силуэт босса
			# ни с чем не спутать.
			for off in [-4.5, 4.5]:
				_rect(b0, off - bw * 0.5, bl, bw, barrel_base)
				_rect(b1 - 4.0, off - bw * 0.5 - 1.0, 5.0, bw + 2.0, barrel_dark)
		"tube":
			# Миномёт: короткая толстая труба с раструбом.
			_rect(b0, -bw * 0.5, bl, bw, barrel_base)
			_rect(b1 - 3.0, -bw * 0.5 - 2.0, 5.0, bw + 4.0, barrel_dark)
		"brake":
			_rect(b0, -bw * 0.5, bl, bw, barrel_base)
			# Дульный тормоз: две «щеки» у среза.
			_rect(b1 - 8.0, -bw * 0.5 - 1.8, 3.0, bw + 3.6, barrel_dark)
			_rect(b1 - 3.5, -bw * 0.5 - 1.8, 3.5, bw + 3.6, barrel_dark)
		_:
			_rect(b0, -bw * 0.5, bl, bw, barrel_base)
			_rect(b1 - 4.0, -bw * 0.5 - 1.0, 5.0, bw + 2.0, barrel_dark)
	# Раскалённый ствол: по нему видно, сколько ещё можно стрелять, не
	# отводя глаз на полоску в углу экрана.
	if tank.heat > 0.25:
		var glow := Color(1.0, 0.35, 0.1, minf(0.85, (tank.heat - 0.25) * 1.1))
		if tank.overheated:
			glow = Color(1.0, 0.75, 0.45, 0.75 + 0.2 * sin(world.tick * 0.4))
		_rect(b1 - 9.0, -bw * 0.5 - 0.5, 9.0, bw + 1.0, glow)

	# Блик по верхней кромке ствола: без него ствол сливается в плоскую полосу.
	if String(shape["muzzle"]) != "twin":
		_rect(b0, -bw * 0.5, b1 - b0 - 3.0, 1.0, Color(1, 1, 1, 0.18))
	# Маска ствола — утолщение у башни.
	_rect(b0 - 1.0, -bw * 0.5 - 2.0, 4.5, bw + 4.0, barrel_dark)

	draw_set_transform(view_off + pos)
	var turret_dark: Color = Cosmetics.color_of("turret", turret_id, palette["dark"]) 		if has_turret_color else palette["dark"]
	var turret_body: Color = Cosmetics.color_of("turret", turret_id, palette["body"]) 		if has_turret_color else palette["body"]
	draw_circle(Vector2.ZERO, tr, turret_dark)
	draw_circle(Vector2.ZERO, tr - 2.0, turret_body)
	# Люк командира со смещением — башня перестаёт быть плоским кругом.
	if tr >= 7.5:
		draw_circle(Vector2(-tr * 0.25, -tr * 0.25), tr * 0.30, Color(0, 0, 0, 0.30))
		draw_arc(Vector2.ZERO, tr - 1.0, PI * 0.7, PI * 1.55, 10, Color(1, 1, 1, 0.16), 1.5)

	# Прицел снайпера и антенна — мелкие приметы роли.
	draw_set_transform(view_off + pos, tank.turret_angle)
	if bool(shape["scope"]):
		_rect(tr * 0.2, -tr - 2.5, 5.0, 3.0, Color("#1a1a1a"))
		draw_circle(Vector2(tr * 0.2 + 5.0, -tr - 1.0), 1.2, Color(0.6, 0.9, 1.0, 0.9))
	draw_set_transform(view_off + pos, tank.body_angle + PI / 2.0)
	if bool(shape["antenna"]):
		draw_line(Vector2(hw - 5.0, hh - 4.0), Vector2(hw - 7.0, hh - 14.0),
			Color(0.1, 0.1, 0.1, 0.85), 1.0)

	draw_set_transform(view_off + pos)

	# ---- состояние активной способности ---------------------------------
	# У каждой длящейся способности свой знак: без него игрок видит только
	# полоску кулдауна в углу и не понимает, работает ли перк прямо сейчас.
	if tank.ability_timer > 0:
		_draw_ability_state(tank)

	# ---- индикаторы -----------------------------------------------------
	if tank.spawn_protect > 0:
		draw_arc(Vector2.ZERO, 20, 0, TAU, 32,
			Color(1, 1, 1, 0.4 + 0.3 * sin(world.tick * 0.3)), 2.0)
	if tank.shield_hp > 0.0:
		var sh := Cfg.shield
		sh.a = 0.55
		draw_arc(Vector2.ZERO, 18, 0, TAU, 32, sh, 2.0)
	if tank.turbo_timer > 0:
		for k in 3:
			var a := tank.body_angle + PI + (k - 1) * 0.3
			draw_circle(Vector2(cos(a) * 20.0, sin(a) * 20.0), 3, Color(1, 0.67, 0.2, 0.5))

	# Активное оружие — щиток над танком с иконкой и кольцом-таймером.
	if tank.weapon != "" and tank.weapon_timer > 0:
		var weapon := Weapons.get_weapon(tank.weapon)
		if not weapon.is_empty():
			var frac := maxf(0.0, float(tank.weapon_timer) / float(weapon["duration"]))
			draw_circle(Vector2(0, -20), 10, Color(0.06, 0.08, 0.10, 0.9))
			draw_arc(Vector2(0, -20), 10, 0, TAU, 24, weapon["color"], 1.5)
			var ring: Color = weapon["color"]
			ring.a = 0.8
			draw_arc(Vector2(0, -20), 13, -PI / 2.0, -PI / 2.0 + frac * TAU, 32, ring, 2.0)
			_text_center(String(weapon["icon"]), Vector2(0, -20), 10, Color.WHITE)

	# Маркер «это ты» — важно в разделённом экране.
	if is_viewer:
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, -26), Vector2(-5, -34), Vector2(5, -34)]), palette["trim"])

	# ---- полоска HP и подпись (без поворота) ----------------------------
	draw_set_transform(view_off)
	var bar_w := 26.0
	var ratio := maxf(0.0, tank.hp / tank.max_hp)
	if ratio < 1.0 or not is_viewer:
		_rect(tank.x - bar_w * 0.5, tank.y - 22, bar_w, 4, Color(0, 0, 0, 0.6))
		var bar := Color("#44cc44") if ratio > 0.5 else (Color("#cccc44") if ratio > 0.25 else Color("#cc4444"))
		_rect(tank.x - bar_w * 0.5, tank.y - 22, bar_w * ratio, 4, bar)
	if tank.shield_hp > 0.0:
		_rect(tank.x - bar_w * 0.5, tank.y - 26, bar_w * minf(1.0, tank.shield_hp / 30.0), 2, Cfg.shield)

	if not is_viewer:
		var name_color := Color("#88ccff") if is_ally else (Color("#ffee55") if tank.is_player_controlled else Color("#ffaaaa"))
		_text_center(tank.name, Vector2(tank.x, tank.y - 32), 10, name_color)
		# Перки бота видно над именем — понятно, почему он вдруг стал опасным.
		if not tank.perk_ids.is_empty():
			var icons := ""
			for id in tank.perk_ids:
				icons += Perks.any_perk_icon(id)
			_text_center(icons, Vector2(tank.x, tank.y - 43), 9, Color("#ffcc66"))

	if tank.carrying_flag:
		_text_center("⚑", Vector2(tank.x + 16, tank.y - 16), 14, Color("#ffee55"))

func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)

## Рисунок на корпусе (косметика). Вызывается в повёрнутом контексте корпуса.
## Камуфляж — базовая окраска корпуса под наклейками.
##
## Пятна рисуются в системе координат корпуса, а не карты: иначе камуфляж
## «плыл» бы по броне при движении. Цвета смешиваются с командным, а не
## заменяют его — в командных режимах свои должны оставаться узнаваемыми.
func _draw_camo(tank: Tank, hw: float, hh: float, palette: Dictionary) -> void:
	var id := String(tank.cosmetics.get("camo", "none"))
	if id == "" or id == "none":
		return
	var camo := Cosmetics.get_cosmetic("camo", id)
	if camo.is_empty() or not camo.has("a"):
		return
	var base: Color = palette["body"]
	# Немного командного цвета подмешивается в оба пятна: камуфляж должен
	# перекрашивать танк, но не превращать его в чужой силуэт.
	var a: Color = Color(camo["a"]).lerp(base, 0.16)
	var b: Color = Color(camo["b"]).lerp(base, 0.16)
	var x0 := -hw + 2.0
	var x1 := hw - 2.0
	var y0 := -hh + 2.0
	var y1 := hh - 2.0

	match id:
		"digital", "winter", "urban":
			# Пиксельные пятна: размер блока отличает «цифру» от городского.
			var cell := 3.0 if id == "digital" else (4.5 if id == "winter" else 5.5)
			var row := 0
			var y := y0
			while y < y1:
				var col := 0
				var x := x0
				while x < x1:
					var q := Rng.hash01(row * 73856093 + col * 19349663, 4242)
					if q < 0.42:
						_rect(x, y, minf(cell, x1 - x), minf(cell, y1 - y), a)
					elif q < 0.74:
						_rect(x, y, minf(cell, x1 - x), minf(cell, y1 - y), b)
					col += 1
					x += cell
				row += 1
				y += cell
		"tiger":
			# Полосы поперёк корпуса, каждая со своим изломом.
			var k := 0
			var y2 := y0
			while y2 < y1:
				var wob := (Rng.hash01(k, 77) - 0.5) * 5.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(x0, y2), Vector2(x1, y2 + wob),
					Vector2(x1, y2 + wob + 3.2), Vector2(x0, y2 + 3.2),
				]), b if k % 2 == 0 else a)
				k += 1
				y2 += 5.0
		"splinter":
			# Угловатые осколки: по три на борт, зеркально.
			for i in 3:
				var yy := y0 + (y1 - y0) * (float(i) + 0.15) / 3.0
				var h2 := (y1 - y0) / 3.4
				draw_colored_polygon(PackedVector2Array([
					Vector2(x0, yy), Vector2(x0 + hw * 0.9, yy + h2 * 0.35),
					Vector2(x0 + hw * 0.5, yy + h2), Vector2(x0, yy + h2 * 0.75),
				]), a if i % 2 == 0 else b)
				draw_colored_polygon(PackedVector2Array([
					Vector2(x1, yy + h2 * 0.5), Vector2(x1 - hw * 0.85, yy + h2 * 0.15),
					Vector2(x1 - hw * 0.45, yy + h2 * 0.95), Vector2(x1, yy + h2 * 1.1),
				]), b if i % 2 == 0 else a)
		"desert":
			# Мягкие кляксы: округлая форма отличает пустынный от цифрового.
			for i in 13:
				var px := x0 + (x1 - x0) * Rng.hash01(i, 11)
				var py := y0 + (y1 - y0) * Rng.hash01(i, 23)
				var r := 2.4 + Rng.hash01(i, 31) * 3.0
				draw_circle(Vector2(clampf(px, x0 + r, x1 - r), clampf(py, y0 + r, y1 - r)),
					r, a if i % 2 == 0 else b)

func _draw_hull_pattern(tank: Tank, hw: float, hh: float) -> void:
	var id := String(tank.cosmetics.get("hull", "none"))
	if id == "" or id == "none":
		return
	var a := 0.8
	match id:
		"stripes":
			var x := -hw + 4.0
			while x < hw - 4.0:
				if int((x + tank.x) / 6.0) % 2 == 0:
					_rect(x, -hh + 2, 3, tank.height - 4, Color(1, 1, 1, a))
				x += 6.0
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := 7.0 if i % 2 == 0 else 3.0
				var ang := -PI / 2.0 + (float(i) * PI) / 5.0
				pts.append(Vector2(cos(ang) * r, sin(ang) * r))
			draw_colored_polygon(pts, Color(1, 0.93, 0.33, a))
		"flames":
			for i in 3:
				var y := -hh + 6.0 + i * 6.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(-hw + 4, y), Vector2(-hw + 8, y - 7),
					Vector2(-hw + 12, y), Vector2(-hw + 8, y + 4),
				]), Color(1, 0.47, 0.2, a))
		"cross":
			_rect(-2, -hh + 4, 4, tank.height - 8, Color(1, 1, 1, a))
			_rect(-hw + 4, -2, tank.width - 8, 4, Color(1, 1, 1, a))
		"chevrons":
			for i in 2:
				var y := -hh + 6.0 + i * 8.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(-hw + 4, y), Vector2(0, y - 5),
					Vector2(hw - 4, y), Vector2(0, y + 2),
				]), Color(0.53, 0.8, 1.0, a))

## Стрелки к важным целям за пределами экрана.
func _draw_offscreen_markers(size: Vector2) -> void:
	if world.mode != "ctf" or player.tank == null:
		return
	var cam := player.camera
	var half_w := size.x * 0.5 - 40.0
	var half_h := size.y * 0.5 - 40.0

	for flag in world.flags:
		var relevant: bool = flag.team != player.tank.team or not flag.at_home
		if not relevant:
			continue
		var dx: float = flag.x - cam.x
		var dy: float = flag.y - cam.y
		if absf(dx) < half_w and absf(dy) < half_h:
			continue
		var angle := atan2(dy, dx)
		var radius := minf(half_w, half_h) * 0.95
		var c := cam + Vector2(cos(angle), sin(angle)) * radius
		var color: Color = Cfg.flag_player if flag.team == "player" else Cfg.flag_enemy
		color.a = 0.8
		draw_set_transform(view_off + c, angle)
		draw_colored_polygon(PackedVector2Array([
			Vector2(10, 0), Vector2(-6, -6), Vector2(-6, 6)]), color)
	draw_set_transform(view_off)
