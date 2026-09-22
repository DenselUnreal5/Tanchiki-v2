class_name Surfaces
extends RefCounted

static var ASPHALT := {
	"id": "asphalt", "speed": 1.12, "dust": Color("#4a4b50"), "tread": "tread_hard",
}
static var DIRT := {
	"id": "dirt", "speed": 1.0, "dust": Color("#6b6350"), "tread": "tread_soft",
}
static var GRASS := {
	"id": "grass", "speed": 0.92, "dust": Color("#4a6b3a"), "tread": "tread_soft",
}
static var SAND := {
	"id": "sand", "speed": 0.85, "dust": Color("#c9b878"), "tread": "tread_soft",
}
static var DUNE := {
	"id": "dune", "speed": 0.62, "dust": Color("#bfa967"), "tread": "tread_soft",
}
static var QUICKSAND := {
	"id": "quicksand", "speed": 0.34, "dust": Color("#7d6a45"), "tread": "tread_soft",
}
static var DIRT_ROAD := {
	"id": "dirt_road", "speed": 1.05, "dust": Color("#6a5a3c"), "tread": "tread_soft",
}
static var SAND_PATH := {
	"id": "sand_path", "speed": 0.95, "dust": Color("#b39a63"), "tread": "tread_soft",
}

static func of_tile(tile: int, road_kind: String = "asphalt") -> Dictionary:
	match tile:
		Cfg.T_ROAD, Cfg.T_BRIDGE:
			if road_kind == "asphalt":
				return ASPHALT
			if road_kind == "sand_path":
				return SAND_PATH
			return DIRT_ROAD
		Cfg.T_GRASS:
			return GRASS
		Cfg.T_SAND:
			return SAND
		Cfg.T_DUNE:
			return DUNE
		Cfg.T_QUICKSAND:
			return QUICKSAND
	return DIRT
