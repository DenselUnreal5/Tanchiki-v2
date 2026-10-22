class_name Locations
extends RefCounted

const CITY := "city"
const GRASSLAND := "grassland"
const DUST := "dust"
const JUNGLE := "jungle"
const FROST := "frost"
const EXCLUSION := "exclusion"
const SHORE := "shore"

const ORDER := [CITY, GRASSLAND, DUST, JUNGLE, FROST, EXCLUSION, SHORE]

static var LIST := {
	"city": {
		"id": "city", "name": "Город", "icon": "🏙", "music": "combat",
		"terrain": "tiles",
		"block_min": 9, "block_max": 14,
		"arterials": true, "circles": true, "river": 1.0,
		"wave_streets": true,
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
	"grassland": {
		"id": "grassland", "name": "Равнина", "icon": "🌾", "music": "combat",
		"block_min": 10, "block_max": 16,
		"arterials": true, "circles": true, "river": 1.2,
		"terrain": "tiles",
		"tile_style": {
			"merge": 0.34, "ponds_small": 1, "ponds_large": 2, "rivers_small": 1, "rivers": 1,
			"house_share": 0.3, "grove_share": 0.35, "park_share": 0.25,
			"house_min": 1, "house_max": 4, "trees_min": 1, "trees_max": 4,
			"outskirt_tree": 0.2, "outskirt_house": 0.01,
		},
		"wave_streets": true,
		"districts": {"downtown": 2, "residential": 3, "industrial": 2, "park": 5},
		"cover": "tree", "cover_chance": 0.25, "ruin_chance": 0.05,
		"ground_tile": Cfg.T_GRASS, "yard_tile": Cfg.T_ROAD,
		"road_kind": "asphalt",
		"arterial_w": 3, "street_w": 2, "street_w_wide": 2,
		"link_chance": 0.60,
		"weather": ["clear", "rain", "fog", "storm"],
		"fog_tint": Color(0.85, 0.92, 0.88),
		"dune_chance": 0.0, "oases": 0,
		"ground": Color("#354a2a"), "ground_alt": Color("#324527"),
	},
	"dust": {
		"id": "dust", "name": "Пустошь", "icon": "🏜", "music": "dust",
		"block_min": 16, "block_max": 24,
		"arterials": false, "circles": false, "river": 0.0,
		"terrain": "tiles",
		"tile_style": {
			"merge": 0.3, "ponds_small": 1, "ponds_large": 2,
			"house_share": 0.45, "grove_share": 0.0, "park_share": 0.15,
			"house_min": 2, "house_max": 7, "trees_min": 0, "trees_max": 2,
			"outskirt_tree": 0.03, "outskirt_house": 0.01,
		},
		"districts": {"downtown": 1, "residential": 2, "industrial": 5, "park": 0},
		"cover": "sand", "cover_chance": 0.55,
		"ruin_chance": 0.34,
		"ground_tile": Cfg.T_SAND, "yard_tile": Cfg.T_SAND,
		"road_kind": "dirt",
		"arterial_w": 3, "street_w": 2, "street_w_wide": 2,
		"link_chance": 0.65,
		"weather": ["clear", "fog"],
		"fog_tint": Color(0.85, 0.74, 0.50),
		"dune_chance": 0.62,
		"oases": 3,
		"ground": Color("#6b5c3c"), "ground_alt": Color("#655737"),
	},
	"jungle": {
		"id": "jungle", "name": "Джунгли", "icon": "🌴", "music": "jungle",
		"block_min": 14, "block_max": 22,
		"arterials": false, "circles": false, "river": 1.6,
		"terrain": "tiles",
		"tile_style": {
			"merge": 0.32, "ponds_small": 1, "ponds_large": 3, "rivers_small": 1, "rivers": 2,
			"river_always": true,
			"house_share": 0.22, "grove_share": 0.5, "park_share": 0.18,
			"house_min": 1, "house_max": 4, "trees_min": 1, "trees_max": 4,
			"outskirt_tree": 0.45, "outskirt_house": 0.004,
		},
		"districts": {"downtown": 1, "residential": 2, "industrial": 1, "park": 6},
		"cover": "tree", "cover_chance": 0.30, "ruin_chance": 0.16,
		"ground_tile": Cfg.T_GRASS, "yard_tile": Cfg.T_GRASS,
		"road_kind": "asphalt",
		"arterial_w": 2, "street_w": 1, "street_w_wide": 2,
		"link_chance": 0.75,
		"weather": ["clear", "rain", "fog", "storm"],
		"fog_tint": Color(0.80, 0.88, 0.82),
		"dune_chance": 0.0, "oases": 0,
		"ground": Color("#2f3d24"), "ground_alt": Color("#2b3922"),
	},
	"frost": {
		"id": "frost", "name": "Зимний город", "icon": "❄", "music": "combat",
		"block_min": 9, "block_max": 14,
		"arterials": true, "circles": true, "river": 0.6,
		"terrain": "tiles",
		"tile_style": {
			"merge": 0.2, "ponds_small": 1, "ponds_large": 3,
			"house_share": 0.65, "grove_share": 0.1, "park_share": 0.2,
			"house_min": 3, "house_max": 10, "trees_min": 0, "trees_max": 2,
			"outskirt_tree": 0.05, "outskirt_house": 0.02,
		},
		"districts": {"downtown": 3, "residential": 4, "industrial": 2, "park": 2},
		"cover": "", "cover_chance": 0.0, "ruin_chance": 0.0,
		"ground_tile": Cfg.T_GRASS, "yard_tile": Cfg.T_ROAD,
		"road_kind": "asphalt",
		"arterial_w": 3, "street_w": 2, "street_w_wide": 3,
		"link_chance": 0.55,
		"weather": ["snow", "fog", "clear", "storm"],
		"fog_tint": Color(0.90, 0.93, 0.98),
		"dune_chance": 0.0, "oases": 0,
		"ground": Color("#44484f"), "ground_alt": Color("#40444b"),
	},
	"exclusion": {
		"id": "exclusion", "name": "Промзона", "icon": "☢", "music": "dust",
		"block_min": 13, "block_max": 20,
		"arterials": true, "circles": false, "river": 0.0,
		"terrain": "tiles",
		"tile_style": {
			"merge": 0.12, "ponds_small": 1, "ponds_large": 1,
			"house_share": 0.8, "grove_share": 0.05, "park_share": 0.05,
			"house_min": 5, "house_max": 12, "trees_min": 0, "trees_max": 1,
			"outskirt_tree": 0.02, "outskirt_house": 0.03,
		},
		"districts": {"downtown": 1, "residential": 1, "industrial": 5, "park": 1},
		"cover": "", "cover_chance": 0.0,
		"ruin_chance": 0.30,
		"ground_tile": Cfg.T_GRASS, "yard_tile": Cfg.T_GRASS,
		"road_kind": "asphalt",
		"arterial_w": 3, "street_w": 2, "street_w_wide": 2,
		"link_chance": 0.50,
		"weather": ["fog", "clear", "storm"],
		"fog_tint": Color(0.82, 0.85, 0.78),
		"dune_chance": 0.0, "oases": 0,
		"ground": Color("#4a4d42"), "ground_alt": Color("#464a3f"),
	},
	"shore": {
		"id": "shore", "name": "Побережье", "icon": "🌊", "music": "combat",
		"block_min": 9, "block_max": 14,
		"arterials": true, "circles": true, "river": 0.0,
		"terrain": "tiles",
		"tile_style": {
			"merge": 0.25, "ponds_small": 0, "ponds_large": 1,
			"house_share": 0.55, "grove_share": 0.1, "park_share": 0.25,
			"house_min": 2, "house_max": 7, "trees_min": 0, "trees_max": 3,
			"outskirt_tree": 0.08, "outskirt_house": 0.015,
		},
		"coast_frac_min": 0.30,
		"coast_frac_max": 0.38,
		"districts": {"downtown": 2, "residential": 4, "industrial": 3, "park": 2},
		"cover": "sand", "cover_chance": 0.20, "ruin_chance": 0.0,
		"ground_tile": Cfg.T_GRASS, "yard_tile": Cfg.T_ROAD,
		"road_kind": "asphalt",
		"arterial_w": 3, "street_w": 2, "street_w_wide": 3,
		"link_chance": 0.55,
		"weather": ["clear", "rain", "fog", "storm"],
		"fog_tint": Color(0.84, 0.90, 0.93),
		"dune_chance": 0.0, "oases": 1,
		"ground": Color("#3c4030"), "ground_alt": Color("#39402f"),
	},
}

static func road_kind_of(id: String) -> String:
	return String(get_location(id).get("road_kind", "asphalt"))

static func get_location(id: String) -> Dictionary:
	return LIST.get(id, LIST[CITY])

static func music_of(id: String) -> String:
	return String(get_location(id)["music"])

static func resolve(setting: String, rng: Rng) -> String:
	if LIST.has(setting):
		return setting
	return pick_random(rng)

static func pick_random(rng: Rng) -> String:
	return String(ORDER[int(rng.nextf() * float(ORDER.size())) % ORDER.size()])

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
			elif (t == Cfg.T_BRICK or t == Cfg.T_ADOBE) and dune > 0.0 and rng.nextf() < dune:
				map.set_tile(r, c, Cfg.T_DUNE)
			elif (t == Cfg.T_BRICK or t == Cfg.T_ADOBE) and ruin > 0.0 and rng.nextf() < ruin:
				map.set_tile(r, c, ground)

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
