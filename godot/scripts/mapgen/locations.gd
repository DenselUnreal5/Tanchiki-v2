# ============================================================================
# locations.gd — локации: город, пустошь, джунгли.
#
# Локация — это набор правил для того же самого конвейера генерации, а не
# отдельный генератор. Меняются четыре вещи: густота дорожной сети, состав
# районов, наличие реки и то, чем зарастают пустоты между застройкой.
# Тайлы при этом остаются прежними — и это не экономия, а условие: у песка,
# газона и асфальта уже есть разное сцепление (surfaces.gd), поэтому смена
# покрытия сразу меняет и то, как едет танк, а не только картинку.
#
# Каждая локация звучит по-своему: music — имя папки в res://music.
# ============================================================================
class_name Locations
extends RefCounted

const CITY := "city"
const DUST := "dust"
const JUNGLE := "jungle"

## Порядок в меню.
const ORDER := [CITY, DUST, JUNGLE]

## Поля локации:
##   block_min/max — шаг между улицами: чем больше, тем реже дороги
##   arterials     — бывают ли широкие магистрали
##   circles       — бывает ли кольцевая развязка
##   river         — множитель ширины реки, 0 — реки нет
##   districts     — веса районов при жеребьёвке опорных точек
##   cover         — чем зарастают пустоты: sand | tree | ничего
##   cover_chance  — доля пустых клеток, которые зарастают
##   ruin_chance   — доля тайлов застройки, выбитых из стен: руины
##   ground_tile   — чем застелена открытая земля кварталов (газон, песок)
##   yard_tile     — чем замощены дворы промзоны и площади
##   road_kind     — чем замощены дороги: asphalt | dirt | path
##   arterial_w    — ширина магистрали в тайлах
##   street_w      — ширина обычной улицы
##   street_w_wide — ширина широкой улицы (изредка вместо обычной)
##   link_chance   — доля перемычек между соседними параллельными улицами
##   weather       — какие погодные условия возможны (пусто — любые)
##   fog_tint      — цвет взвеси в воздухе: в пустоши это пыль, а не пар
##   dune_chance   — доля застройки, ставшая барханами (пустошь)
##   oases         — сколько озёр с зыбучими краями (пустошь)
##   ground        — цвет земли, по нему локация узнаётся с первого взгляда
static var LIST := {
	"city": {
		"id": "city", "name": "Город", "icon": "🏙", "music": "combat",
		"block_min": 9, "block_max": 14,
		"arterials": true, "circles": true, "river": 1.0,
		"districts": {"downtown": 3, "residential": 4, "industrial": 2, "park": 2},
		"cover": "", "cover_chance": 0.0, "ruin_chance": 0.0,
		"ground_tile": Cfg.T_GRASS, "yard_tile": Cfg.T_ROAD,
		"road_kind": "asphalt",
		"arterial_w": 3, "street_w": 2, "street_w_wide": 3,
		"link_chance": 0.55,
		"weather": ["clear", "rain", "fog", "storm", "snow"],
		"fog_tint": Color(0.86, 0.89, 0.94),
		"dune_chance": 0.0, "oases": 0,
		"ground": Color("#3a3a2a"), "ground_alt": Color("#37372a"),
	},
	# Пустошь: редкие дороги, промзона вместо жилья, песок вместо газона
	# и ни капли воды. Открытая карта — стреляют издалека, укрытий мало.
	"dust": {
		"id": "dust", "name": "Пустошь", "icon": "🏜", "music": "dust",
		"block_min": 16, "block_max": 24,
		"arterials": true, "circles": false, "river": 0.0,
		"districts": {"downtown": 1, "residential": 2, "industrial": 5, "park": 0},
		"cover": "sand", "cover_chance": 0.55,
		# Треть застройки выбита. Это не только вид: дыры в стенах открывают
		# простреливаемые насквозь линии, и пустошь начинает играть как
		# открытая карта, а не как город с другой палитрой.
		"ruin_chance": 0.34,
		# В пустоши не асфальтируют дворы: иначе замер связности показывал
		# на «пустоши» больше асфальта, чем в городе, — промзона заливала
		# кварталы дорогой, а промзона здесь основной район.
		"ground_tile": Cfg.T_SAND, "yard_tile": Cfg.T_SAND,
		# Асфальта в пустоши нет: только накатанная грунтовка.
		"road_kind": "dirt",
		"arterial_w": 3, "street_w": 2, "street_w_wide": 2,
		"link_chance": 0.65,
		# Снег и дождь в пустыне не идут. Остаётся ясная погода и пыльная
		# взвесь вместо тумана — она же и прячет, и слепит.
		"weather": ["clear", "fog"],
		"fog_tint": Color(0.85, 0.74, 0.50),
		# Большая часть застройки — не дома, а барханы: их можно переехать,
		# но медленно, поэтому они работают рельефом, а не стеной.
		"dune_chance": 0.62,
		# Оазисы: вода посреди песка, а по краям зыбучка. Единственная вода
		# на карте — и она же ловушка.
		"oases": 3,
		"ground": Color("#6b5c3c"), "ground_alt": Color("#655737"),
	},
	# Джунгли: магистралей нет вовсе, только узкие тропы, парк почти везде,
	# река шире городской. Тесная карта — бой в упор из-за деревьев.
	"jungle": {
		"id": "jungle", "name": "Джунгли", "icon": "🌴", "music": "jungle",
		"block_min": 14, "block_max": 22,
		"arterials": false, "circles": false, "river": 1.6,
		"districts": {"downtown": 1, "residential": 2, "industrial": 1, "park": 6},
		"cover": "tree", "cover_chance": 0.30, "ruin_chance": 0.16,
		"ground_tile": Cfg.T_GRASS, "yard_tile": Cfg.T_GRASS,
		# Тропа, набитая колёсами по грунту, — не проспект.
		"road_kind": "path",
		# Тропа в одну клетку: танк проходит (габарит 26 из 32), а карта
		# перестаёт выглядеть городом с зелёной палитрой.
		"arterial_w": 2, "street_w": 1, "street_w_wide": 2,
		"link_chance": 0.75,
		# В тропиках не бывает снега; всё остальное бывает, и чаще всего дождь.
		"weather": ["clear", "rain", "fog", "storm"],
		"fog_tint": Color(0.80, 0.88, 0.82),
		"dune_chance": 0.0, "oases": 0,
		"ground": Color("#2f3d24"), "ground_alt": Color("#2b3922"),
	},
}

## Чем замощены дороги локации: asphalt | dirt | path.
static func road_kind_of(id: String) -> String:
	return String(get_location(id).get("road_kind", "asphalt"))

static func get_location(id: String) -> Dictionary:
	return LIST.get(id, LIST[CITY])

## Имя папки с музыкой этой локации.
static func music_of(id: String) -> String:
	return String(get_location(id)["music"])

## Локация по настройке меню. Готовый идентификатор возвращается как есть —
## и это важно: жребий тянуть тем же генератором, что и карту, нельзя.
## Карта уровня 1 детерминирована, поэтому «случайная» локация выпадала бы
## на нём всегда одна и та же. Жребий бросает вызывающий, своей случайностью,
## и передаёт сюда уже готовый ответ.
static func resolve(setting: String, rng: Rng) -> String:
	if LIST.has(setting):
		return setting
	return pick_random(rng)

## Жребий локации. Вызывается ДО генерации карты, чтобы не сдвигать её
## поток случайности, а в сетевой партии результат рассылается клиентам.
static func pick_random(rng: Rng) -> String:
	return String(ORDER[int(rng.nextf() * float(ORDER.size())) % ORDER.size()])

## Зарастание пустот и обрушение застройки. Последний этап рельефа: идёт по
## готовой карте и трогает только пустую землю и кирпич, поэтому не может ни
## разрезать дорогу, ни засыпать мост. Обрушение только открывает пространство,
## связность от него не страдает.
static func overgrow(map: GameMap, rng: Rng, loc: Dictionary) -> void:
	var kind := String(loc.get("cover", ""))
	var chance := float(loc.get("cover_chance", 0.0))
	var ruin := float(loc.get("ruin_chance", 0.0))
	var dune := float(loc.get("dune_chance", 0.0))
	if kind == "" and ruin <= 0.0 and dune <= 0.0:
		return
	var cover_tile := Cfg.T_SAND if kind == "sand" else Cfg.T_TREE
	var ground: int = int(loc.get("ground_tile", Cfg.T_GRASS))
	for r in range(1, map.rows - 1):
		for c in range(1, map.cols - 1):
			var t := map.get_tile(r, c)
			if t == Cfg.T_EMPTY and kind != "" and rng.nextf() < chance:
				map.set_tile(r, c, cover_tile)
			elif t == Cfg.T_BRICK and dune > 0.0 and rng.nextf() < dune:
				# Бархан вместо дома. Он проезжаемый, поэтому пустошь получает
				# рельеф, а не лабиринт: объехать быстрее, чем переползти,
				# и это решение принимает игрок, а не стена.
				map.set_tile(r, c, Cfg.T_DUNE)
			elif t == Cfg.T_BRICK and ruin > 0.0 and rng.nextf() < ruin:
				# Бетонный каркас не обрушаем: несущие колонны и должны
				# пережить дом, иначе руина перестаёт быть укрытием.
				map.set_tile(r, c, ground)

## Оазисы пустоши: озерцо, обведённое зыбучим песком.
##
## Единственная вода на карте — и она же ловушка: доехать до неё хочется,
## а край затягивает. Дороги, мосты и бетон не трогаются, иначе озеро
## разрезало бы улицу и появилось бы посреди дома.
static func carve_oases(map: GameMap, rng: Rng, loc: Dictionary) -> void:
	var count := int(loc.get("oases", 0))
	if count <= 0:
		return
	var placed := 0
	var attempt := 0
	while placed < count and attempt < 400:
		attempt += 1
		var r := 6 + int(rng.nextf() * float(maxi(1, map.rows - 12)))
		var c := 6 + int(rng.nextf() * float(maxi(1, map.cols - 12)))
		# Радиус меньше трёх даёт не озеро, а крест из пяти клеток.
		var radius := 3 + int(rng.nextf() * 2.0)
		if not _oasis_fits(map, r, c, radius + 1):
			continue
		for dr in range(-radius - 1, radius + 2):
			for dc in range(-radius - 1, radius + 2):
				var rr := r + dr
				var cc := c + dc
				if rr < 1 or cc < 1 or rr >= map.rows - 1 or cc >= map.cols - 1:
					continue
				var d := sqrt(float(dr * dr + dc * dc))
				if d <= float(radius):
					map.set_tile(rr, cc, Cfg.T_WATER)
				elif d <= float(radius) + 1.4:
					map.set_tile(rr, cc, Cfg.T_QUICKSAND)
		placed += 1

## Оазису нужно место под самим пятном: поперёк улицы озеро выглядит ошибкой
## генерации, а вода на дороге ещё и разрезала бы сеть. Руины топить можно —
## затопленная развалина смотрится естественно.
##
## Первая версия требовала чистого КВАДРАТА с запасом в две клетки вокруг.
## Когда радиус подняли с 2–3 до 3–4, такого места на карте не находилось ни
## разу за 400 попыток и оазисов выходило ноль. Замер поймал это сразу: вода
## и зыбучка исчезли с карты целиком.
static func _oasis_fits(map: GameMap, r: int, c: int, reach: int) -> bool:
	for dr in range(-reach, reach + 1):
		for dc in range(-reach, reach + 1):
			if dr * dr + dc * dc > reach * reach:
				continue
			var t := map.get_tile(r + dr, c + dc)
			if t == Cfg.T_ROAD or t == Cfg.T_BRIDGE or t == Cfg.T_WALL \
					or t == Cfg.T_WATER:
				return false
	return true
