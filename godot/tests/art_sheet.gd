# ============================================================================
# art_sheet.gd — выгрузка каталога графики.
#
# В игре нет ни одной текстуры: тайлы, танки и эффекты рисуются примитивами
# в _draw(). Поэтому «посмотреть файлы ассетов» нельзя — вместо этого сцена
# прогоняет НАСТОЯЩИЙ рендерер (WorldView) по синтетическим кусочкам карты
# и по танкам каждого типа и сохраняет то, что он нарисовал.
#
# Запуск (с окном, не headless — иначе SubViewport отдаёт пустоту):
#   godot --path godot tests/art_sheet.tscn
#
# Результат: PNG плюс manifest.json в user://artsheet.
# ============================================================================
extends Node

const OUT := "user://artsheet/"

var world: World
var ps: PlayerState
var vp: SubViewport
var view: WorldView
var manifest: Array = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	print("OUT=", ProjectSettings.globalize_path(OUT))

	var level: Dictionary = LevelGen.generate(1, "ffa")
	ps = PlayerState.new(0, "P1", "p1", null)
	# puppet — мир без спавна: танки и предметы расставляем сами.
	world = World.new({
		"map": level["map"], "level": level, "mode": "ffa",
		"difficulty": "medium", "players": [ps], "puppet": true,
	})
	world.weather = WeatherSystem.new(0, {"condition": "clear", "phase": 0.25})

	vp = SubViewport.new()
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	await get_tree().process_frame

	await _tiles()
	await _tanks()
	await _scenes(level)

	var f := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("ГОТОВО: изображений ", manifest.size())
	get_tree().quit(0)

# ------------------------------------------------------------------ съёмка
func _shot(id: String, size: Vector2i, group: String, title: String, note: String) -> void:
	vp.size = size
	ps.viewport = Rect2(0.0, 0.0, float(size.x), float(size.y))
	for ch in vp.get_children():
		vp.remove_child(ch)
		ch.queue_free()

	var bg := ColorRect.new()
	bg.color = Color("#0a0a0a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)

	view = WorldView.new()
	view.world = world
	view.player = ps
	vp.add_child(view)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(OUT + id + ".png")
	manifest.append({
		"id": id, "group": group, "title": title, "note": note,
		"w": size.x, "h": size.y,
	})

func _blank(n: int) -> GameMap:
	var m := GameMap.new(n, n)
	m.fill(Cfg.T_EMPTY)
	return m

func _box(m: GameMap, r0: int, r1: int, c0: int, c1: int, tile: int) -> void:
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			m.set_tile(r, c, tile)

## Ставит синтетическую карту и план города вместо настоящих.
func _use(m: GameMap, plan: Dictionary) -> void:
	world.map = m
	ps.map = m
	world.level = {"seed": 0, "plan": plan}
	ps.camera = Vector2(m.width * 0.5, m.height * 0.5)

const N := 9
const VIEW9 := Vector2i(N * 32, N * 32)

func _tiles() -> void:
	var m: GameMap
	var empty_plan := {"v": [], "h": []}

	m = _blank(N)
	_use(m, empty_plan)
	await _shot("tile_ground", VIEW9, "env", "Земля (T_EMPTY)",
		"Шахматка из двух оттенков — по ней читается сетка и масштаб")

	m = _blank(N)
	_box(m, 2, 6, 2, 6, Cfg.T_WALL)
	_use(m, empty_plan)
	await _shot("tile_wall", VIEW9, "env", "Бетон (T_WALL)",
		"Неразрушаемый. Светлая фаска сверху-слева, тёмная снизу-справа")

	m = _blank(N)
	_box(m, 2, 6, 2, 6, Cfg.T_BRICK)
	_use(m, empty_plan)
	await _shot("tile_brick", VIEW9, "env", "Здание (T_BRICK)",
		"Пять вариантов крыши по (строка, столбец). Разрушается")
	# Вид крыши и материал постройки — одно число. Чтобы каталог показал все
	# пять видов по отдельности, выгружаем карту вариантов: смещение камеры
	# на этом кадре нулевое, поэтому тайл (r, c) лежит по пикселям (c*32, r*32).
	var variants := []
	for r in range(2, 7):
		for c in range(2, 7):
			variants.append({"r": r, "c": c, "variant": Materials.variant_at(r, c)})
	manifest[manifest.size() - 1]["variants"] = variants

	m = _blank(N)
	_box(m, 0, N - 1, 2, 5, Cfg.T_ROAD)
	_use(m, {"v": [{"pos": 2, "w": 4, "rank": 0}], "h": []})
	await _shot("tile_road_arterial", VIEW9, "env", "Магистраль (T_ROAD, 4 полосы)",
		"Двойная сплошная по оси, бордюр по кромке")

	m = _blank(N)
	_box(m, 0, N - 1, 3, 4, Cfg.T_ROAD)
	_use(m, {"v": [{"pos": 3, "w": 2, "rank": 1}], "h": []})
	await _shot("tile_road_street", VIEW9, "env", "Улица (T_ROAD, 2 полосы)",
		"Прерывистая осевая")

	m = _blank(N)
	_box(m, 0, N - 1, 3, 4, Cfg.T_ROAD)
	_box(m, 3, 4, 0, N - 1, Cfg.T_ROAD)
	_use(m, {"v": [{"pos": 3, "w": 2, "rank": 1}], "h": [{"pos": 3, "w": 2, "rank": 1}]})
	await _shot("tile_road_junction", VIEW9, "env", "Перекрёсток и зебра",
		"Пешеходные полосы ставятся только на подходе к перекрёстку")

	m = _blank(N)
	_box(m, 0, N - 1, 2, 6, Cfg.T_WATER)
	_use(m, empty_plan)
	await _shot("tile_water", VIEW9, "env", "Вода (T_WATER)",
		"Топит танк. Анимированные блики")

	m = _blank(N)
	_box(m, 0, N - 1, 2, 6, Cfg.T_WATER)
	_box(m, 3, 4, 0, N - 1, Cfg.T_BRIDGE)
	_use(m, {"v": [], "h": [{"pos": 3, "w": 2, "rank": 1}]})
	await _shot("tile_bridge", VIEW9, "env", "Мост (T_BRIDGE)",
		"Настил с перилами. Не больше четырёх на карту")

	m = _blank(N)
	_box(m, 2, 6, 2, 6, Cfg.T_SAND)
	_use(m, empty_plan)
	await _shot("tile_sand", VIEW9, "env", "Песчаный берег (T_SAND)",
		"Кайма вокруг воды, проходимая")

	m = _blank(N)
	_box(m, 2, 6, 2, 6, Cfg.T_GRASS)
	_use(m, empty_plan)
	await _shot("tile_grass", VIEW9, "env", "Газон (T_GRASS)",
		"Городской парк и островки развязок")

	m = _blank(N)
	_box(m, 2, 6, 2, 6, Cfg.T_TREE)
	_use(m, empty_plan)
	await _shot("tile_tree", VIEW9, "env", "Дерево (T_TREE)",
		"Укрытие: сминается танком и сбивается пулей")

	m = _blank(N)
	_box(m, 2, 6, 2, 6, Cfg.T_ROAD)
	m.set_tile(4, 4, Cfg.T_BASE_P)
	_use(m, empty_plan)
	await _shot("tile_base_p", VIEW9, "env", "База своей команды (T_BASE_P)",
		"Один тайл, режим «Захват флага»")

	m = _blank(N)
	_box(m, 2, 6, 2, 6, Cfg.T_ROAD)
	m.set_tile(4, 4, Cfg.T_BASE_E)
	_use(m, empty_plan)
	await _shot("tile_base_e", VIEW9, "env", "База противника (T_BASE_E)",
		"Один тайл, режим «Захват флага»")

# ------------------------------------------------------------------- танки
const TANK_VIEW := Vector2i(160, 128)

func _tank_shot(id: String, group: String, title: String, note: String,
		chassis: String, color_key: String, cosmetics: Dictionary) -> void:
	var m := _blank(N)
	_use(m, {"v": [], "h": []})
	var centre := Vector2(m.width * 0.5, m.height * 0.5)
	ps.camera = centre
	var t := Tank.new({
		"x": centre.x, "y": centre.y, "team": "enemy", "name": "",
		"max_hp": 100.0, "speed": 2.0, "fire_rate": 30,
		"chassis": chassis, "color_key": color_key, "cosmetics": cosmetics,
	})
	# Стволом вправо: так виден и силуэт корпуса, и вылет ствола.
	t.angle = 0.0
	t.body_angle = 0.0
	t.turret_angle = 0.0
	# Кольцо неуязвимости после спавна для каталога — помеха: оно закрывает
	# корпус ровно тем, что к внешнему виду танка отношения не имеет.
	t.spawn_protect = 0
	world.tanks = [t]
	# Танк-«зритель»: у своего танка рендерер не рисует ни имени, ни полоски HP.
	ps.tank = t
	await _shot(id, TANK_VIEW, group, title, note)
	world.tanks = []
	ps.tank = null

func _tanks() -> void:
	for key in EnemyTypes.ORDER:
		var type: Dictionary = EnemyTypes.LIST[key]
		var shape: Dictionary = TankArt.chassis(String(type["chassis"]))
		await _tank_shot("tank_" + key, "tank",
			"%s (%s)" % [String(type["name"]), String(type["chassis"])],
			"корпус %.0fx%.0f px, ствол %.0f px, катков %d" % [
				float(shape["w"]), float(shape["h"]),
				float(shape["barrel_len"]), int(shape["wheels"])],
			String(type["chassis"]), String(type["color_key"]), {})

	for skin in Cfg.PLAYER_SKINS:
		await _tank_shot("skin_" + String(skin["key"]), "skin",
			String(skin["name"]), String(skin["color"]),
			"standard", String(skin["key"]), {})

	for camo in Cosmetics.CAMOS:
		await _tank_shot("camo_" + String(camo["id"]), "camo",
			String(camo["name"]), "цена %d" % int(camo["price"]),
			"standard", "p1", {"camo": String(camo["id"])})

	for hull in Cosmetics.HULLS:
		await _tank_shot("hull_" + String(hull["id"]), "hull",
			String(hull["name"]), "цена %d" % int(hull["price"]),
			"standard", "p1", {"hull": String(hull["id"])})

	for tr in Cosmetics.TRACKS:
		await _tank_shot("track_" + String(tr["id"]), "track",
			String(tr["name"]), "цена %d" % int(tr["price"]),
			"standard", "p1", {"track": String(tr["id"])})

	for tu in Cosmetics.TURRETS:
		await _tank_shot("turret_" + String(tu["id"]), "turret",
			String(tu["name"]), "цена %d" % int(tu["price"]),
			"standard", "p1", {"turret": String(tu["id"])})

# ------------------------------------------------------------------- сцены
const SCENE_VIEW := Vector2i(640, 400)

func _scenes(level: Dictionary) -> void:
	var real_map: GameMap = level["map"]
	world.map = real_map
	ps.map = real_map
	world.level = level
	world.tanks = []
	ps.tank = null

	# Точки съёмки выбираются не на глаз, а замером окна 19x11 тайлов:
	# «город» — где больше всего асфальта и застройки и нет воды,
	# «река» — где вода сходится с переправой.
	var city := _find_spot(real_map, false)
	var river := _find_spot(real_map, true)

	var conditions := [
		{"id": "clear", "phase": 0.25, "title": "Ясно, день"},
		{"id": "rain", "phase": 0.25, "title": "Дождь"},
		{"id": "fog", "phase": 0.25, "title": "Густой туман"},
		{"id": "snow", "phase": 0.25, "title": "Снег"},
		{"id": "storm", "phase": 0.25, "title": "Гроза"},
		{"id": "clear", "phase": 0.75, "title": "Ночь: фонари включаются сами"},
	]
	var i := 0
	for cond in conditions:
		ps.camera = city
		world.weather = WeatherSystem.new(0, {
			"condition": String(cond["id"]), "phase": float(cond["phase"]),
		})
		world.tick = 300
		await _shot("scene_%d_%s" % [i, String(cond["id"])], SCENE_VIEW,
			"scene", String(cond["title"]),
			"фрагмент карты 640x400 px = 20x12.5 тайлов")
		i += 1

	ps.camera = river
	world.weather = WeatherSystem.new(0, {"condition": "clear", "phase": 0.25})
	await _shot("scene_river", SCENE_VIEW, "scene", "Река, набережная и мост",
		"фрагмент карты 640x400 px = 20x12.5 тайлов")

	# Локации: одна и та же точка съёмки на каждой земле.
	for loc_id in Locations.ORDER:
		var lvl := LevelGen.generate(1, "ffa", -1, loc_id)
		var m: GameMap = lvl["map"]
		world.map = m
		ps.map = m
		world.level = lvl
		world.tanks = []
		ps.tank = null
		ps.camera = _find_spot(m, false)
		var loc := Locations.get_location(loc_id)
		await _shot("loc_" + loc_id, SCENE_VIEW, "scene",
			"%s %s" % [String(loc["icon"]), String(loc["name"])],
			"музыка: music/%s" % String(loc["music"]))

## Ищет окно карты с нужным содержимым. water — искать переправу через реку,
## иначе плотную застройку с улицами.
func _find_spot(m: GameMap, water_wanted: bool) -> Vector2:
	var best := Vector2(m.width * 0.5, m.height * 0.5)
	var best_score := -999999
	for r in range(7, m.rows - 7, 2):
		for c in range(11, m.cols - 11, 2):
			var road := 0
			var brick := 0
			var water := 0
			var bridge := 0
			for dr in range(-5, 6):
				for dc in range(-9, 10):
					var t := m.get_tile(r + dr, c + dc)
					if t == Cfg.T_ROAD:
						road += 1
					elif t == Cfg.T_BRIDGE:
						bridge += 1
					elif t == Cfg.T_BRICK or t == Cfg.T_WALL:
						brick += 1
					elif t == Cfg.T_WATER:
						water += 1
			var score := 0
			if water_wanted:
				score = mini(water, 60) + bridge * 3 + mini(road, 40) + mini(brick, 40)
				if bridge == 0:
					score -= 500
			else:
				score = mini(road, 90) + mini(brick, 90) - water * 4
			if score > best_score:
				best_score = score
				best = Vector2(c * Cfg.TILE, r * Cfg.TILE)
	return best
