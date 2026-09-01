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
##   ground        — цвет земли, по нему локация узнаётся с первого взгляда
static var LIST := {
	"city": {
		"id": "city", "name": "Город", "icon": "🏙", "music": "combat",
		"block_min": 9, "block_max": 14,
		"arterials": true, "circles": true, "river": 1.0,
		"districts": {"downtown": 3, "residential": 4, "industrial": 2, "park": 2},
		"cover": "", "cover_chance": 0.0, "ruin_chance": 0.0,
		"ground_tile": Cfg.T_GRASS, "yard_tile": Cfg.T_ROAD,
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
		"ground": Color("#2f3d24"), "ground_alt": Color("#2b3922"),
	},
}

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
	if kind == "" and ruin <= 0.0:
		return
	var cover_tile := Cfg.T_SAND if kind == "sand" else Cfg.T_TREE
	var ground: int = int(loc.get("ground_tile", Cfg.T_GRASS))
	for r in range(1, map.rows - 1):
		for c in range(1, map.cols - 1):
			var t := map.get_tile(r, c)
			if t == Cfg.T_EMPTY and kind != "" and rng.nextf() < chance:
				map.set_tile(r, c, cover_tile)
			elif t == Cfg.T_BRICK and ruin > 0.0 and rng.nextf() < ruin:
				# Бетонный каркас не обрушаем: несущие колонны и должны
				# пережить дом, иначе руина перестаёт быть укрытием.
				map.set_tile(r, c, ground)
