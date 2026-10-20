@tool
class_name UiIconArt
extends RefCounted

# Source artwork is preserved in atlases. No runtime recoloring or image cuts.
const SHEETS := {
	"perks_a": ["res://art/ui_icons/perks_a.png", 8, 5],
	"perks_b": ["res://art/ui_icons/perks_b.png", 8, 5],
	"achievements": ["res://art/ui_icons/achievements.png", 6, 6],
	"achievement_details": ["res://art/ui_icons/achievement_details.png", 3, 1],
	"equipment": ["res://art/ui_icons/equipment.png", 4, 3],
	"weapons": ["res://art/ui_icons/weapons.png", 3, 1],
	"upgrades": ["res://art/ui_icons/upgrades.png", 5, 2],
}
const ENTRIES := {
	"double_shot": ["perks_a", 0],
	"fan_shot": ["perks_a", 1],
	"rapid_fire": ["perks_a", 2],
	"quick_reload": ["perks_a", 3],
	"explosive": ["perks_a", 4],
	"piercing": ["perks_a", 5],
	"heavy_armor": ["perks_a", 6],
	"regen": ["perks_a", 7],
	"reflect": ["perks_a", 8],
	"evasion": ["perks_a", 9],
	"shield": ["perks_a", 10],
	"sprinter": ["perks_a", 11],
	"mines": ["perks_a", 12],
	"lightning_lord": ["perks_a", 13],
	"sky_strike": ["perks_a", 14],
	"chain_lightning": ["perks_a", 15],
	"deep_freeze": ["perks_a", 16],
	"frost_dash": ["perks_a", 17],
	"chilled_barrel": ["perks_a", 18],
	"corrosive_acid": ["perks_a", 19],
	"acid_cloud": ["perks_a", 20],
	"corroding_armor": ["perks_a", 21],
	"napalm": ["perks_a", 22],
	"slow_burn": ["perks_a", 23],
	"fire_wall": ["perks_a", 24],
	"fireproof": ["perks_a", 25],
	"flashover": ["perks_a", 26],
	"high_voltage": ["perks_a", 27],
	"long_stun": ["perks_a", 28],
	"arc_chain": ["perks_a", 29],
	"capacitor": ["perks_a", 30],
	"overload": ["perks_a", 31],
	"ram": ["perks_a", 32],
	"thick_armor": ["perks_a", 33],
	"amphibious": ["perks_a", 34],
	"forest": ["perks_a", 35],
	"magnet": ["perks_a", 36],
	"sniper": ["perks_a", 37],
	"berserk": ["perks_a", 38],
	"kamikaze": ["perks_a", 39],
	"turbo": ["perks_b", 0],
	"shadow": ["perks_b", 1],
	"vampire": ["perks_b", 2],
	"bot_boss_twin": ["perks_b", 3],
	"bot_boss_barrage": ["perks_b", 4],
	"siege": ["perks_b", 5],
	"nitro": ["perks_b", 6],
	"overdrive": ["perks_b", 7],
	"bulwark": ["perks_b", 8],
	"shockwave": ["perks_b", 9],
	"heat_sink": ["perks_b", 10],
	"thermal": ["perks_b", 11],
	"quick_vent": ["perks_b", 12],
	"heavy_shell": ["perks_b", 13],
	"light_shell": ["perks_b", 14],
	"road_king": ["perks_b", 15],
	"all_terrain": ["perks_b", 16],
	"lumberjack": ["perks_b", 17],
	"concrete_breaker": ["perks_b", 18],
	"can_opener": ["perks_b", 19],
	"scavenger": ["perks_b", 20],
	"keen_ear": ["perks_b", 21],
	"muffler": ["perks_b", 22],
	"predator": ["perks_b", 23],
	"coolant": ["perks_b", 24],
	"overclock": ["perks_b", 25],
	"grip": ["perks_b", 26],
	"breaker": ["perks_b", 27],
	"silencer": ["perks_b", 28],
	"smoke": ["perks_b", 29],
	"repair": ["perks_b", 30],
	"lightning": ["perks_b", 31],
	"stealth_hunter": ["perks_b", 32],
	"juggernaut": ["perks_b", 33],
	"ghost_sniper": ["perks_b", 34],
	"ice_hunter": ["perks_b", 35],
	"acid_hunter": ["perks_b", 36],
	"fire_hunter": ["perks_b", 37],
	"shock_hunter": ["perks_b", 38],
	"fortress": ["perks_a", 6],
	"gunner": ["perks_a", 2],
	"ach_first_blood": ["achievements", 0],
	"ach_kill_10": ["achievements", 1],
	"ach_kill_50": ["achievements", 2],
	"ach_kill_250": ["achievements", 3],
	"ach_ram_10": ["achievements", 4],
	"ach_ram_50": ["achievements", 5],
	"ach_bricks_100": ["achievements", 6],
	"ach_bricks_500": ["achievements", 7],
	"ach_medkits_25": ["achievements", 8],
	"ach_medkits_100": ["achievements", 9],
	"ach_wins_5": ["achievements", 10],
	"ach_wins_25": ["achievements", 11],
	"ach_games_10": ["achievements", 12],
	"ach_games_50": ["achievements", 13],
	"ach_long_20": ["achievement_details", 0],
	"ach_lowhp_10": ["achievements", 15],
	"ach_streak_10": ["achievement_details", 1],
	"ach_rapid_5": ["achievements", 17],
	"ach_bridge_defender": ["achievements", 18],
	"ach_demolition": ["achievements", 19],
	"ach_demolition_master": ["achievements", 20],
	"ach_eagle_ear": ["achievement_details", 2],
	"ach_ability_50": ["achievements", 22],
	"ach_ability_250": ["achievements", 23],
	"ach_damage_1000": ["achievements", 24],
	"ach_boss_1": ["achievements", 25],
	"ach_boss_10": ["achievements", 26],
	"ach_rank_sergeant": ["achievements", 27],
	"ach_rank_general": ["achievements", 28],
	"ach_money_5000": ["achievements", 29],
	"ach_money_20000": ["achievements", 30],
	"ach_defense_wave_10": ["achievements", 31],
	"ach_tutorial_master": ["achievements", 32],
	"upg_dmg": ["upgrades", 0],
	"upg_fire_rate": ["upgrades", 1],
	"upg_bullet_speed": ["upgrades", 2],
	"upg_max_hp": ["upgrades", 3],
	"upg_damage_taken": ["upgrades", 4],
	"upg_speed": ["upgrades", 5],
	"upg_ram": ["upgrades", 6],
	"upg_dash_cd": ["upgrades", 7],
	"upg_pickup_radius": ["upgrades", 8],
	"upg_regen": ["upgrades", 9],
	"fire_ring": ["perks_a", 24],
	"storm_pulse": ["perks_a", 27],
	"bot_rapid": ["perks_a", 2],
	"bot_speed": ["perks_a", 11],
	"bot_tough": ["perks_a", 6],
	"bot_double": ["perks_a", 0],
	"bot_nitro": ["perks_b", 6],
	"bot_wave": ["perks_b", 9],
	"bot_accurate": ["perks_a", 37],
	"bot_regen": ["perks_a", 7],
	"bot_heavy": ["perks_b", 13],
	"bot_evasion": ["perks_a", 9],
	"bot_lightning_lord": ["perks_a", 13],
	"bot_sky_strike": ["perks_a", 14],
	"bot_chain_lightning": ["perks_a", 15],
	"cannon_standard": ["equipment", 0],
	"cannon_ice": ["equipment", 1],
	"cannon_acid": ["equipment", 2],
	"cannon_fire": ["equipment", 3],
	"cannon_shock": ["equipment", 4],
	"class_standard": ["equipment", 5],
	"class_grunt": ["equipment", 6],
	"class_scout": ["equipment", 7],
	"class_heavy": ["equipment", 8, [0, 724, 400, 362]],
	"class_sniper": ["equipment", 9, [400, 724, 344, 362]],
	"class_mortar": ["equipment", 10, [744, 724, 344, 362]],
	"weapon_gatling": ["weapons", 0],
	"weapon_rockets": ["weapons", 1],
	"weapon_shotgun": ["weapons", 2],
}

static var _cache: Dictionary = {}
static var _sources: Dictionary = {}

static func texture_of(id: String) -> Texture2D:
	if not ENTRIES.has(id):
		return null
	if not _cache.has(id):
		var entry: Array = ENTRIES[id]
		var sheet: Array = SHEETS[entry[0]]
		if not _sources.has(entry[0]):
			var loaded := load(String(sheet[0])) as Texture2D
			if loaded == null:
				return null
			_sources[entry[0]] = loaded
		var source: Texture2D = _sources[entry[0]]
		var columns: int = sheet[1]
		var rows: int = sheet[2]
		var index: int = entry[1]
		var col := index % columns
		var row := index / columns
		# Rounded shared boundaries handle generated sheets with odd dimensions.
		var start := Vector2(roundf(float(col) * source.get_width() / columns), roundf(float(row) * source.get_height() / rows))
		var end := Vector2(roundf(float(col + 1) * source.get_width() / columns), roundf(float(row + 1) * source.get_height() / rows))
		var region := AtlasTexture.new()
		region.atlas = source
		region.region = Rect2(start, end - start)
		if entry.size() > 2:
			var rect: Array = entry[2]
			region.region = Rect2(rect[0], rect[1], rect[2], rect[3])
			# Some wide tank silhouettes extend past an equal grid cell.
			# Their explicit regions keep the artwork intact; square padding
			# preserves proportions when the UI places them in an icon slot.
			var side := maxf(region.region.size.x, region.region.size.y)
			var extra := Vector2.ONE * side - region.region.size
			region.margin = Rect2(extra * 0.5, extra)
		region.filter_clip = true
		_cache[id] = region
	return _cache[id]
