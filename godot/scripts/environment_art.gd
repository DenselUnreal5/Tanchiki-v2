class_name EnvironmentArt
extends RefCounted

const ITEMS := {
	"military_props": [
		"fuel_barrel",
		"fuel_barrel_burning",
		"fuel_barrel_broken",
		"generator_idle",
		"generator_active",
		"generator_broken",
		"supply_crate",
		"sandbags",
		"concrete_barrier",
		"base_bunker",
		"tank_wreck",
		"lamp_post"
	],
	"desert_props": [
		"palm",
		"cactus",
		"dry_bush",
		"sandstone_rock",
		"adobe_house",
		"ruined_wall",
		"military_tent",
		"supply_crate",
		"fuel_barrel",
		"sandbags",
		"dead_tree",
		"scrub"
	],
	"jungle_props": [
		"broadleaf_tree",
		"palm",
		"dense_bush",
		"ferns",
		"moss_rock",
		"fallen_log",
		"tree_stump",
		"wooden_hut",
		"stone_ruin",
		"supply_crate",
		"sandbags",
		"fuel_barrel"
	]
}
static var _cache := {}

static func group_for(location: String) -> String:
	if location in ["dust", "village"]: return "desert_props"
	if location == "jungle": return "jungle_props"
	return "military_props"

static func texture(id: String, location: String = "city") -> Texture2D:
	var group := group_for(location)
	if not ITEMS[group].has(id): group = "military_props"
	if not ITEMS[group].has(id): return null
	var key := group + "/" + id
	if not _cache.has(key):
		_cache[key] = load("res://art/environment/%s/%s.tres" % [group, id])
	return _cache[key]
