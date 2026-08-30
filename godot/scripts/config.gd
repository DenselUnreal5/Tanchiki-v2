# ============================================================================
# config.gd — все константы и настройки баланса в одном месте.
# Логика игры работает на фиксированном шаге 60 Гц, поэтому «60 тиков = 1 сек»
# здесь действительно верно.
# ============================================================================
class_name Cfg
extends RefCounted

const TICK_HZ := 60
const TICK_SEC := 1.0 / 60.0
## Максимум логических шагов за один кадр — защита от «догоняющего» фриза.
const MAX_STEPS_PER_FRAME := 5

# ---------------------------------------------------------------- карта
const TILE := 32
const COLS := 120
const ROWS := 68
const MAP_W := COLS * TILE
const MAP_H := ROWS * TILE

## Карта «Захвата флага» намеренно втрое меньше общей: на полной команды
## разбредались и почти не встречались, а до чужого флага ехать было далеко.
const CTF_COLS := 64
const CTF_ROWS := 40

# Типы тайлов
const T_EMPTY := 0
const T_WALL := 1    # неразрушаемый бетон
const T_BRICK := 2   # разрушается пулями
const T_WATER := 3   # топит танк (кроме перка «Амфибия»)
const T_TREE := 4    # укрытие, сминается танком и сбивается пулей
const T_BASE_P := 5  # база команды игрока (CTF)
const T_BASE_E := 6  # база команды врага (CTF)
const T_SAND := 7    # песчаный берег вокруг воды (проходимый)
const T_ROAD := 8    # асфальт: улицы и проспекты, лучшее сцепление
const T_BRIDGE := 9  # мост через воду — единственный способ пересечь реку
const T_GRASS := 10  # газон городского парка

# ---------------------------------------------------------------- цвета
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
static var bridge := Color("#6a5c46")
static var bridge_dark := Color("#4a3f2f")
static var bridge_rail := Color("#a8977a")
static var grass := Color("#3d5c33")
static var grass_alt := Color("#456634")
static var grass_dark := Color("#2c4426")
static var sand := Color("#c9b878")
static var sand_light := Color("#ddc98a")
static var sand_dark := Color("#a8975f")
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

## Цвета команд/игроков для корпусов танков и HUD.
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
	# Типы врагов — оттенки отличаются от обычного «enemy».
	"scout": {"body": Color("#9c6a2f"), "dark": Color("#6e4a20"), "trim": Color("#e0b08f")},
	"heavy": {"body": Color("#6a3a8c"), "dark": Color("#4a2864"), "trim": Color("#c79ad8")},
	"sniper": {"body": Color("#3a8c6a"), "dark": Color("#28644a"), "trim": Color("#9ad8b0")},
	"mortar": {"body": Color("#8c5a2f"), "dark": Color("#643e20"), "trim": Color("#e0c08f")},
	"boss": {"body": Color("#3a3a3a"), "dark": Color("#1a1a1a"), "trim": Color("#e74c3c")},
}

## Доступные игроку расцветки танка (ключи TEAM_COLORS).
const PLAYER_SKINS := [
	{"key": "p1", "name": "Зелёный", "color": "#3f7d3f"},
	{"key": "p2", "name": "Синий", "color": "#2f6a9c"},
	{"key": "p3", "name": "Оранжевый", "color": "#9c5a2f"},
	{"key": "p4", "name": "Фиолетовый", "color": "#7a3f8c"},
	{"key": "p5", "name": "Бирюзовый", "color": "#3f8c8c"},
	{"key": "p6", "name": "Оливковый", "color": "#8c8c3f"},
]

# ---------------------------------------------------------------- палитра интерфейса
static var UI_BG := Color("#0a0a0a")
static var UI_PANEL := Color(0.031, 0.039, 0.031, 0.94)
static var UI_ACCENT := Color("#55cc55")
static var UI_ACCENT_DIM := Color("#2f6b2f")
static var UI_TEXT := Color("#d8d8d8")
static var UI_MUTED := Color("#7a7a7a")
static var UI_WARN := Color("#ffaa33")
static var UI_DANGER := Color("#cc4444")
static var UI_GOLD := Color("#ffee55")

# ---------------------------------------------------------------- физика
## Затухание скорости за тик. Предельная скорость = speed.
const FRICTION := 0.85
const ACCEL_FACTOR := 1.0 - FRICTION
## Замедление в воде (множитель к скорости за тик).
const WATER_DRAG := 0.6

const TANK_W := 24.0
const TANK_H := 28.0
## Радиус, в котором пуля считается попавшей в танк.
const TANK_HIT_R := 14.0
## Радиус контакта корпусов для тарана и расталкивания.
const TANK_BODY_R := 22.0

# ---------------------------------------------------------------- бой
const BULLET_SPEED := 3.25   # px/тик
const BULLET_LIFE := 160     # тиков
const BULLET_DMG_MIN := 20.0
const BULLET_DMG_MAX := 30.0

const SPAWN_PROTECT := 60    # 1 сек неуязвимости к боевому урону
const RESPAWN_DELAY := 120   # 2 сек до возрождения

const WATER_DMG := 5.0
const WATER_DMG_INTERVAL := 15

const RAM_MIN_SPEED := 0.5
const RAM_DMG_PER_SPEED := 8.0
const RAM_PUSH := 3.0

# ---------------------------------------------------------------- рывок (таран)
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

## Горящий остов на месте подбитого танка: сколько живёт и за сколько тиков
## гаснет в конце.
const WRECK_LIFE := 180
const WRECK_FADE := 45

const KAMIKAZE_DMG := 60.0
const KAMIKAZE_R := 64.0

## Урон постройкам от взрывной пули и от мины (в эпицентре).
const BLAST_TILE_DAMAGE := 70.0
const MINE_TILE_DAMAGE := 120.0

# ------------------------------------------------------- активные способности
## «Бастион»: множитель входящего урона на время действия.
const BULWARK_DAMAGE_MULT := 0.4
## «Ударная волна»: радиус, урон по танкам, урон по постройкам и отброс.
const SHOCKWAVE_R := 118.0
const SHOCKWAVE_DMG := 42.0
const SHOCKWAVE_TILE_DAMAGE := 150.0
const SHOCKWAVE_PUSH := 5.5
## «Форсаж»: множитель времени перезарядки, пока способность активна.
const OVERDRIVE_RELOAD_MULT := 0.5

const EXPLOSIVE_R := 32.0
const EXPLOSIVE_SPLASH := 0.5

const SHIELD_HP := 30.0
const SHIELD_COOLDOWN := 30 * 60
const TURBO_DURATION := 180
const SHADOW_DURATION := 180

# ---------------------------------------------------------------- аптечки
const PICKUP_R := 20.0
const PICKUP_R_MAGNET := 40.0
const PICKUP_HEAL_FRACTION := 0.3
const PICKUP_RESPAWN := 900
const PICKUP_MIN := 4
const PICKUP_MAX := 6

# ---------------------------------------------------------------- бот
const BOT_SIGHT := 500.0
const BOT_COMBAT_RANGE := 450.0
## В «Захвате флага» атакующие ввязываются в бой только вблизи: с общим
## радиусом 450 на компактной карте кто-то всегда был в поле зрения, бот
## навсегда оставался в боевом состоянии и за флагом не ехал вообще.
const BOT_CTF_ENGAGE_RANGE := 200.0
const BOT_FIRE_RANGE := 500.0
const BOT_KEEP_MIN := 80.0
const BOT_KEEP_MAX := 250.0
const BOT_DODGE_LOOKAHEAD := 40.0
const BOT_PATH_REFRESH := 60
const BOT_MAX_PERKS := 4
const BOT_PERK_CHANCE := 0.4

# ---------------------------------------------------------------- прогресс
const XP_PER_KILL := 100
const XP_PER_CAPTURE := 200
const SCORE_PER_KILL := 100
const SCORE_PER_CAPTURE := 500
const MAX_EQUIPPED_PERKS := 3

static func xp_for_session_level(lvl: int) -> int:
	return 300 + lvl * 200

static func xp_for_global_level(lvl: int) -> int:
	return 400 + lvl * 250

# ---------------------------------------------------------------- режимы
const MODES := {
	"ffa": {"id": "ffa", "name": "Каждый за себя", "frag_limit": 20},
	# cap_limit снижен с 5: флаги теперь стоят в спорной середине, каждый
	# захват даётся боем, и партия до пяти растягивалась на восемь минут.
	"ctf": {"id": "ctf", "name": "Захват флага", "cap_limit": 3, "flags_per_team": 2, "team_size": 4},
	"koth": {
		"id": "koth", "name": "Царь горы",
		"enemies": 40,
		"duration": 5 * 60 * 60,        # 5 минут — лимит партии
		"flood_duration": 2 * 60 * 60,  # 2 минуты — полное затопление карты
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
## Волны с гарантированным боссом: середина и финал.
const DEFENSE_BOSS_WAVES := [4, 7]
const DEFENSE_RAMP_STEP := 0.12
const DEFENSE_PLAYER_HP_MULT := 1.6
const DEFENSE_ENEMY_ACCURACY_PENALTY := 0.12
## База лечится в паузе между волнами, но уже не «до полной» за одну паузу.
const DEFENSE_BASE_REGEN_PER_TICK := 0.0006
## Если волну не зачистили за это время, следующая выходит всё равно —
## иначе осторожный игрок мог отстреливать врагов по одному сколько угодно.
const DEFENSE_WAVE_TIMEOUT := 50 * 60

## Авиаудар («Оборона», клавиша F).
const AIRSTRIKE_DMG := 70.0
const AIRSTRIKE_MAX_HP_FRACTION := 0.1
const AIRSTRIKE_COOLDOWN := 110 * 60

const MINE_SCATTER_FRACTION := 0.05
const SCATTER_MINE_LIFE := 6 * 60 * 60

# ---------------------------------------------------------------- валюта
const REWARD_KILL := 10
const REWARD_CAPTURE := 30
const REWARD_WIN := 50

## Сложность. enemies — число ботов в FFA. enemy_fire_rate — тиков между выстрелами.
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
const PLAYER_FIRE_RATE := 19

## Постепенное усиление ботов, чтобы затяжная партия не становилась скучной.
const RAMP_INTERVAL := 3600
const RAMP_STEP := 0.08
const RAMP_MAX := 1.8

static func team_palette(key: String) -> Dictionary:
	return TEAM_COLORS.get(key, TEAM_COLORS["neutral"])
