@tool
class_name Cfg
extends RefCounted

const TICK_HZ := 60
const TICK_SEC := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 5
const RECONCILE_MAX_REPLAY := 120

const TILE := 32
const COLS := 120
const ROWS := 68
const MAP_W := COLS * TILE
const MAP_H := ROWS * TILE

const CTF_COLS := 64
const CTF_ROWS := 40

const T_EMPTY := 0
const T_WALL := 1
const T_BRICK := 2
const T_WATER := 3
const T_TREE := 4
const T_BASE_P := 5
const T_BASE_E := 6
const T_SAND := 7
const T_ROAD := 8
const T_BRIDGE := 9
const T_GRASS := 10
const T_DUNE := 11
const T_QUICKSAND := 12
const T_ADOBE := 13

static var ground := Color("#3a3a2a")
static var ground_alt := Color("#37372a")
static var wall := Color("#555555")
static var wall_top := Color("#6a6a6a")
static var wall_edge := Color("#3f3f3f")
static var brick := Color("#bb5555")
static var brick_top := Color("#c76b6b")
static var brick_edge := Color("#8d4444")
static var water := Color("#2b3a8f")
static var water_light := Color("#4455b5")
static var road := Color("#2f3033")
static var road_alt := Color("#34353a")
static var road_line := Color("#c8c07a")
static var road_crack := Color("#232427")
static var road_edge := Color("#5c5d63")
static var snow_ground := Color("#9aa4b0")
static var lamp_post := Color("#3a3f45")
static var lamp_head := Color("#c9b071")
static var lamp_glow := Color(1.0, 0.86, 0.55)
static var bolt_core := Color(0.82, 0.96, 1.0)
static var bolt_glow := Color(0.35, 0.78, 1.0)
static var scorch := Color(0.06, 0.05, 0.05)
static var bridge := Color("#6a5c46")
static var bridge_dark := Color("#4a3f2f")
static var bridge_rail := Color("#a8977a")
static var grass := Color("#3d5c33")
static var grass_alt := Color("#456634")
static var grass_dark := Color("#2c4426")
static var sand := Color("#c9b878")
static var dune := Color("#bfa967")
static var dune_dark := Color("#93803f")
static var dune_light := Color("#e0cd92")
static var quicksand := Color("#7d6a45")
static var quicksand_dark := Color("#5d4e31")
static var quicksand_wet := Color("#96825a")
static var dirt_road := Color("#6a5a3c")
static var dirt_road_alt := Color("#63543a")
static var dirt_rut := Color("#4e4230")
static var path_road := Color("#5c5335")
static var path_road_alt := Color("#565030")
static var sand_light := Color("#ddc98a")
static var sand_dark := Color("#a8975f")
static var adobe := Color("#c9a56a")
static var adobe_dark := Color("#a3814f")
static var adobe_light := Color("#e0c088")
static var adobe_beam := Color("#5a4530")
static var sand_path_road := Color("#b39a63")
static var sand_path_road_alt := Color("#a88f57")
static var sand_path_rut := Color("#8c7548")
static var tree := Color("#2a6b3a")
static var tree_dark := Color("#1a4d2a")
static var base_p := Color("#4466ff")
static var base_e := Color("#ff4444")
static var bullet := Color("#ffee55")
static var bullet_enemy := Color("#ff8833")
static var shield := Color("#33aaff")
static var flag_player := Color("#4488ff")
static var flag_enemy := Color("#ff4455")
static var explosion: Array = [
	Color("#ffee55"), Color("#ff9933"), Color("#ff4444"), Color("#aa2222")
]

static var TEAM_COLORS := {
	"p1": {"body": Color("#3f7d3f"), "dark": Color("#2b5c2b"), "trim": Color("#8fd98f")},
	"p2": {"body": Color("#2f6a9c"), "dark": Color("#204a6e"), "trim": Color("#8fc9ef")},
	"p3": {"body": Color("#9c5a2f"), "dark": Color("#6e3f20"), "trim": Color("#e0b08f")},
	"p4": {"body": Color("#7a3f8c"), "dark": Color("#542b63"), "trim": Color("#c79ad8")},
	"p5": {"body": Color("#3f8c8c"), "dark": Color("#2b6262"), "trim": Color("#9ad8d8")},
	"p6": {"body": Color("#8c8c3f"), "dark": Color("#62622b"), "trim": Color("#d8d89a")},
	"enemy": {"body": Color("#8c3a3a"), "dark": Color("#642828"), "trim": Color("#e79a9a")},
	"ally": {"body": Color("#3f6a8c"), "dark": Color("#2b4a64"), "trim": Color("#9ac4e0")},
	"neutral": {"body": Color("#7a6a3a"), "dark": Color("#564a28"), "trim": Color("#d8c58f")},
	"scout": {"body": Color("#9c6a2f"), "dark": Color("#6e4a20"), "trim": Color("#e0b08f")},
	"heavy": {"body": Color("#6a3a8c"), "dark": Color("#4a2864"), "trim": Color("#c79ad8")},
	"sniper": {"body": Color("#3a8c6a"), "dark": Color("#28644a"), "trim": Color("#9ad8b0")},
	"mortar": {"body": Color("#8c5a2f"), "dark": Color("#643e20"), "trim": Color("#e0c08f")},
	"boss": {"body": Color("#3a3a3a"), "dark": Color("#1a1a1a"), "trim": Color("#e74c3c")},
}

const PLAYER_SKINS := [
	{"key": "p1", "name": "Зелёный", "color": "#3f7d3f", "level": 1},
	{"key": "p2", "name": "Синий", "color": "#2f6a9c", "level": 1},
	{"key": "p3", "name": "Оранжевый", "color": "#9c5a2f", "level": 5},
	{"key": "p4", "name": "Фиолетовый", "color": "#7a3f8c", "level": 10},
	{"key": "p5", "name": "Бирюзовый", "color": "#3f8c8c", "level": 20},
	{"key": "p6", "name": "Оливковый", "color": "#8c8c3f", "level": 30},
]

static var UI_BG := Color("#0d0f08")
static var UI_PANEL := Color("#262c17")
static var UI_PANEL_ALPHA := 0.96
static var UI_CARD := Color("#303619")
static var UI_BORDER := Color("#767c54")
static var UI_ACCENT := Color("#a8c065")
static var UI_ACCENT_DIM := Color("#465a2e")
static var UI_TEXT := Color("#f3f5e4")
static var UI_MUTED := Color("#9a9c7c")
static var UI_WARN := Color("#e2a747")
static var UI_DANGER := Color("#c05a44")
static var UI_GOLD := Color("#dcc178")
static var UI_TAG := Color("#d4d0b4")
static var UI_TAG_INK := Color("#1a1c0e")

static var THEMES := {
	"noir": {
		"bg": Color("#0c0b07"), "panel": Color("#231f15"), "panel_alpha": 0.95,
		"card": Color("#2c2718"), "border": Color("#6e6650"),
		"accent": Color("#a8c084"), "accent_dim": Color("#4a5c38"),
		"text": Color("#f4efe2"), "muted": Color("#9d9478"),
		"warn": Color("#d4a860"), "danger": Color("#b56652"), "gold": Color("#d9c495"),
		"tag": Color("#d9c495"), "tag_ink": Color("#231f15"),
	},
	"military": {
		"bg": Color("#0d0f08"), "panel": Color("#262c17"), "panel_alpha": 0.96,
		"card": Color("#303619"), "border": Color("#767c54"),
		"accent": Color("#a8c065"), "accent_dim": Color("#465a2e"),
		"text": Color("#f3f5e4"), "muted": Color("#9a9c7c"),
		"warn": Color("#e2a747"), "danger": Color("#c05a44"), "gold": Color("#dcc178"),
		"tag": Color("#d4d0b4"), "tag_ink": Color("#1a1c0e"),
	},
	"scifi": {
		"bg": Color("#060a0c"), "panel": Color("#122228"), "panel_alpha": 0.94,
		"card": Color("#183036"), "border": Color("#3a827a"),
		"accent": Color("#4ff2d2"), "accent_dim": Color("#1e6a5f"),
		"text": Color("#eafffa"), "muted": Color("#82a8a4"),
		"warn": Color("#eeb75c"), "danger": Color("#ea6a5e"), "gold": Color("#a2f0dc"),
		"tag": Color("#1a4038"), "tag_ink": Color("#a2f0dc"),
	},
}

static func apply_theme(name: String) -> void:
	var t: Dictionary = THEMES.get(name, THEMES["military"])
	UI_BG = t["bg"]
	UI_PANEL = t["panel"]
	UI_PANEL_ALPHA = t["panel_alpha"]
	UI_CARD = t["card"]
	UI_BORDER = t["border"]
	UI_ACCENT = t["accent"]
	UI_ACCENT_DIM = t["accent_dim"]
	UI_TEXT = t["text"]
	UI_MUTED = t["muted"]
	UI_WARN = t["warn"]
	UI_DANGER = t["danger"]
	UI_GOLD = t["gold"]
	UI_TAG = t["tag"]
	UI_TAG_INK = t["tag_ink"]

static var RADIUS_SM := 6.0
static var RADIUS_MD := 10.0
static var RADIUS_LG := 16.0
static var RADIUS_PILL := 999.0

const FRICTION := 0.85
const ACCEL_FACTOR := 1.0 - FRICTION
const WATER_DRAG := 0.6

const TANK_W := 24.0
const TANK_H := 28.0
const TANK_HIT_R := 14.0
const TANK_BODY_R := 22.0

const BULLET_SPEED := 3.25
const BULLET_LIFE := 160
const BULLET_DMG_MIN := 20.0
const BULLET_DMG_MAX := 30.0

const SPAWN_PROTECT := 60
const RESPAWN_DELAY := 120

const WATER_DMG := 5.0
const WATER_DMG_INTERVAL := 15
const QUICKSAND_DMG := 3.0
const QUICKSAND_DMG_INTERVAL := 12

const RAM_MIN_SPEED := 0.5
const RAM_DMG_PER_SPEED := 8.0
const RAM_PUSH := 3.0

const DASH_DISTANCE := 100.0
const DASH_SPEED_MULT := 1.5
const DASH_COOLDOWN := 120

const MINE_DMG := 40.0
const MINE_SPLASH_DMG := 20.0
const MINE_TRIGGER_R := 20.0
const MINE_SPLASH_R := 48.0
const MINE_LIFE := 600
const MINE_COOLDOWN := 60
const MINE_MAX := 3

const WRECK_LIFE := 180
const WRECK_FADE := 45

const KAMIKAZE_DMG := 60.0
const KAMIKAZE_R := 64.0

const BLAST_TILE_DAMAGE := 70.0
const MINE_TILE_DAMAGE := 120.0

const LIGHTNING_DAMAGE := 90.0
const LIGHTNING_RADIUS := 34.0
const LIGHTNING_EVERY := 90
const LIGHTNING_CHANCE := 0.55
const LIGHTNING_LORD_CHANCE := 0.25
const LIGHTNING_LORD_SYNERGY_CHANCE := 0.75

const SKY_STRIKE_COOLDOWN := 720

const CHAIN_LIGHTNING_RADIUS := 140.0
const CHAIN_LIGHTNING_MAX_TARGETS := 3
const CHAIN_LIGHTNING_DMG_MULT := 0.5

const BUILD_PITY_WINDOW := 2
const MAX_SCORCH := 40

const STORM_FELL_EVERY := 150
const STORM_FELL_MAX := 60

const BULWARK_DAMAGE_MULT := 0.4
const SHOCKWAVE_R := 118.0
const SHOCKWAVE_DMG := 42.0
const SHOCKWAVE_TILE_DAMAGE := 150.0
const SHOCKWAVE_PUSH := 5.5
const JUGGERNAUT_SHOCK_R := 90.0
const JUGGERNAUT_SHOCK_DMG := 12.0
const JUGGERNAUT_SHOCK_PUSH := 4.0
const OVERDRIVE_RELOAD_MULT := 0.5

const BOSS_PHASE2_HP := 0.5
const BOSS_PHASE3_HP := 0.2
const BOSS_PHASE2_SPEED_MULT := 1.25
const BOSS_PHASE2_FIRE_RATE_MULT := 0.85
const BOSS_PHASE3_SPEED_MULT := 1.45
const BOSS_PHASE3_FIRE_RATE_MULT := 0.7
const BOSS_PHASE3_SHIELD_TICKS := 180
const BOSS_PHASE3_SHIELD_MULT := 0.35
const BOSS_BARRAGE_WINDUP := 50
const BOSS_BARRAGE_COOLDOWN := 540
const BOSS_BARRAGE_BULLETS := 5
const BOSS_BARRAGE_SPREAD := 0.5
const BOSS_BARRAGE_DMG_SCALE := 0.7
const BOSS_HP_PER_EXTRA_PLAYER := 0.35
const BOSS_DMG_PER_EXTRA_PLAYER := 0.10
const BOSS_HP_PER_WAVE := 0.15
const BOSS_DMG_PER_WAVE := 0.05
const BOSS_HP_MULT_CAP := 4.0
const BOSS_DMG_MULT_CAP := 2.0

const EXPLOSIVE_R := 32.0
const EXPLOSIVE_SPLASH := 0.5

const SHIELD_HP := 30.0
const SHIELD_COOLDOWN := 30 * 60
const TURBO_DURATION := 180
const SHADOW_DURATION := 300

const PICKUP_R := 20.0
const PICKUP_HEAL_FRACTION := 0.3
const PICKUP_RESPAWN := 900
const PICKUP_MIN := 4
const PICKUP_MAX := 6

const BOT_SIGHT := 500.0
const BOT_COMBAT_RANGE := 450.0
const BOT_CTF_ENGAGE_RANGE := 200.0
const BOT_FIRE_RANGE := 500.0
const BOT_KEEP_MIN := 80.0
const BOT_KEEP_MAX := 250.0
const BOT_DODGE_LOOKAHEAD := 40.0
const BOT_PATH_REFRESH := 60
const BOT_MAX_PERKS := 4
const BOT_PERK_CHANCE := 0.4

const XP_PER_KILL := 100
const XP_PER_CAPTURE := 200
const SCORE_PER_KILL := 100
const SCORE_PER_CAPTURE := 500
const MAX_EQUIPPED_PERKS := 3

static func xp_for_session_level(lvl: int) -> int:
	return 300 + lvl * 200

static func xp_for_global_level(lvl: int) -> int:
	return 400 + lvl * 250

const MODES := {
	"ffa": {"id": "ffa", "name": "Каждый за себя", "frag_limit": 20},
	"ctf": {"id": "ctf", "name": "Захват флага", "cap_limit": 3, "flags_per_team": 2, "team_size": 4},
	"koth": {
		"id": "koth", "name": "Царь горы",
		"enemies": 40,
		"duration": 5 * 60 * 60,
		"flood_duration": 2 * 60 * 60,
	},
	"defense": {
		"id": "defense", "name": "Оборона",
		"waves": 7,
		"base_hp": 1000.0,
		"start_delay": 3 * 60,
		"wave_delay": 4 * 60,
		"base_dps": 0.18,
		"base_radius": 72.0,
	},
}

const DEFENSE_FIRST_WAVE := 5
const DEFENSE_LEVEL_BONUS_CAP := 1
const DEFENSE_PLAYER_LEVEL_BONUS := true
const DEFENSE_WAVE_CAP := 30
const DEFENSE_BOSS_WAVES := [4, 7]
const DEFENSE_ENDLESS_BOSS_EVERY := 3
const DEFENSE_RAMP_STEP := 0.12
const DEFENSE_PLAYER_HP_MULT := 1.6
const DEFENSE_ENEMY_ACCURACY_PENALTY := 0.12
const DEFENSE_ACCURACY_PENALTY_MAX := 0.30
const DEFENSE_BASE_REGEN_PER_TICK := 0.0006
const DEFENSE_WAVE_TIMEOUT := 50 * 60

const AIRSTRIKE_DMG := 70.0
const AIRSTRIKE_MAX_HP_FRACTION := 0.1
const AIRSTRIKE_COOLDOWN := 110 * 60

const MINE_SCATTER_FRACTION := 0.05
const SCATTER_MINE_LIFE := 6 * 60 * 60

const REWARD_KILL := 10
const REWARD_CAPTURE := 30
const REWARD_WIN := 50

const DIFFICULTY := {
	"easy": {
		"name": "Легко", "enemies": 8, "enemy_hp": 60.0, "enemy_speed": 0.88,
		"enemy_fire_rate": 69, "enemy_accuracy": 0.6, "enemy_react_time": 30, "player_hp": 150.0,
	},
	"medium": {
		"name": "Средне", "enemies": 14, "enemy_hp": 80.0, "enemy_speed": 1.18,
		"enemy_fire_rate": 46, "enemy_accuracy": 0.75, "enemy_react_time": 20, "player_hp": 100.0,
	},
	"hard": {
		"name": "Сложно", "enemies": 22, "enemy_hp": 100.0, "enemy_speed": 1.47,
		"enemy_fire_rate": 31, "enemy_accuracy": 0.9, "enemy_react_time": 10, "player_hp": 80.0,
	},
}

const PLAYER_SPEED := 1.3
const PLAYER_FIRE_RATE := 27

const PLAYER_DMG_MULT := 1.5

const REPAIR_FRACTION := 0.33
const BREAKER_BUILDING_MULT := 4.0
const BOT_HEAR_RANGE := 520.0
const SMOKE_VISION := 150.0

const HEAT_PER_SHOT := 0.20
const HEAT_COOL := 0.0040
const HEAT_RESUME := 0.30

const AMBUSH_UNAWARE_TICKS := 180

const STEALTH_HUNTER_CRIT_MULT := 2.5

const GHOST_SNIPER_RANGE := 400.0
const GHOST_SNIPER_CRIT_MULT := 1.6

const KEEN_EAR_STEALTH_RANGE := 260.0

const ICE_FREEZE_TICKS := 240

const FROZEN_BOSS_RAM_FRACTION := 0.5

const ACID_STACK_MAX := 5
const ACID_DURATION_TICKS := 300
const ACID_TICK_INTERVAL := 30
const ACID_DMG_PER_STACK_TICK := 6.0

const ACID_CLOUD_RADIUS := 80.0
const CORRODING_ARMOR_MULT := 1.4
const ACID_BOMB_STACKS := 3
const ACID_BOMB_COOLDOWN := 900

const RAMP_INTERVAL := 3600
const RAMP_STEP := 0.08
const RAMP_MAX := 1.8

static func team_palette(key: String) -> Dictionary:
	return TEAM_COLORS.get(key, TEAM_COLORS["neutral"])
