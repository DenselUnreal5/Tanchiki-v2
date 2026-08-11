// ============================================================================
// config.js — все константы и настройки баланса в одном месте.
// Логика игры работает на фиксированном шаге 60 Гц, поэтому "60 тиков = 1 сек"
// здесь действительно верно (в старой версии шаг плавал и все таймеры
// в секундах врали примерно на 30%).
// ============================================================================

export const TICK_HZ = 60;
export const TICK_MS = 1000 / TICK_HZ;
/** Максимум логических шагов за один кадр — защита от «догоняющего» фриза. */
export const MAX_STEPS_PER_FRAME = 5;

// ---------------------------------------------------------------- карта
export const TILE = 32;
export const COLS = 120;
export const ROWS = 68;
export const MAP_W = COLS * TILE;
export const MAP_H = ROWS * TILE;

/** Типы тайлов. */
export const T = {
  EMPTY: 0,
  WALL: 1, // неразрушаемый бетон
  BRICK: 2, // разрушается пулями
  WATER: 3, // топит танк (кроме перка «Амфибия»)
  TREE: 4, // укрытие, сминается танком и сбивается пулей
  BASE_P: 5, // база команды игрока (CTF)
  BASE_E: 6, // база команды врага (CTF)
  SAND: 7, // песчаный берег вокруг воды (проходимый)
};

// ---------------------------------------------------------------- цвета
export const COLORS = {
  ground: '#3a3a2a',
  groundAlt: '#37372a',
  wall: '#555',
  wallTop: '#6a6a6a',
  wallEdge: '#3f3f3f',
  brick: '#b55',
  brickTop: '#c76b6b',
  brickEdge: '#8d4444',
  water: '#2b3a8f',
  waterLight: '#4455b5',
  sand: '#c9b878',
  sandLight: '#ddc98a',
  sandDark: '#a8975f',
  tree: '#2a6b3a',
  treeDark: '#1a4d2a',
  baseP: '#4466ff',
  baseE: '#ff4444',
  bullet: '#ffee55',
  bulletEnemy: '#ff8833',
  explosion: ['#ffee55', '#ff9933', '#ff4444', '#aa2222'],
  shield: '#33aaff',
  flagPlayer: '#4488ff',
  flagEnemy: '#ff4455',
};

/** Цвета команд/игроков для корпусов танков и HUD. */
export const TEAM_COLORS = {
  p1: { body: '#3f7d3f', bodyDark: '#2b5c2b', trim: '#8fd98f' },
  p2: { body: '#2f6a9c', bodyDark: '#204a6e', trim: '#8fc9ef' },
  p3: { body: '#9c5a2f', bodyDark: '#6e3f20', trim: '#e0b08f' },
  p4: { body: '#7a3f8c', bodyDark: '#542b63', trim: '#c79ad8' },
  p5: { body: '#3f8c8c', bodyDark: '#2b6262', trim: '#9ad8d8' },
  p6: { body: '#8c8c3f', bodyDark: '#62622b', trim: '#d8d89a' },
  enemy: { body: '#8c3a3a', bodyDark: '#642828', trim: '#e79a9a' },
  ally: { body: '#3f6a8c', bodyDark: '#2b4a64', trim: '#9ac4e0' },
  neutral: { body: '#7a6a3a', bodyDark: '#564a28', trim: '#d8c58f' },
  // Типы врагов — оттенки отличаются от обычного «enemy», чтобы на поле боя
  // было видно, с кем имеешь дело.
  scout: { body: '#9c6a2f', bodyDark: '#6e4a20', trim: '#e0b08f' },
  heavy: { body: '#6a3a8c', bodyDark: '#4a2864', trim: '#c79ad8' },
  sniper: { body: '#3a8c6a', bodyDark: '#28644a', trim: '#9ad8b0' },
  mortar: { body: '#8c5a2f', bodyDark: '#643e20', trim: '#e0c08f' },
  boss: { body: '#3a3a3a', bodyDark: '#1a1a1a', trim: '#e74c3c' },
};

/** Доступные игроку расцветки танка (ключи TEAM_COLORS). */
export const PLAYER_SKINS = [
  { key: 'p1', name: 'Зелёный', color: '#3f7d3f' },
  { key: 'p2', name: 'Синий', color: '#2f6a9c' },
  { key: 'p3', name: 'Оранжевый', color: '#9c5a2f' },
  { key: 'p4', name: 'Фиолетовый', color: '#7a3f8c' },
  { key: 'p5', name: 'Бирюзовый', color: '#3f8c8c' },
  { key: 'p6', name: 'Оливковый', color: '#8c8c3f' },
];

// ---------------------------------------------------------------- физика
/** Затухание скорости за тик. Предельная скорость = maxSpeed. */
export const FRICTION = 0.85;
/** accel = maxSpeed * ACCEL_FACTOR, где ACCEL_FACTOR = 1 - FRICTION. */
export const ACCEL_FACTOR = 1 - FRICTION;
/** Замедление в воде (множитель к скорости за тик). */
export const WATER_DRAG = 0.6;

export const TANK_W = 24;
export const TANK_H = 28;
/** Радиус, в котором пуля считается попавшей в танк. */
export const TANK_HIT_R = 14;
/** Радиус контакта корпусов для тарана и расталкивания. */
export const TANK_BODY_R = 22;

// ---------------------------------------------------------------- бой
export const BULLET_SPEED = 3.25; // px/тик
export const BULLET_LIFE = 160; // тиков
export const BULLET_DMG_MIN = 20;
export const BULLET_DMG_MAX = 30;

export const SPAWN_PROTECT = 60; // 1 сек неуязвимости к боевому урону
export const RESPAWN_DELAY = 120; // 2 сек до возрождения

export const WATER_DMG = 5;
export const WATER_DMG_INTERVAL = 15; // тиков между тиками урона водой

export const RAM_MIN_SPEED = 0.5; // ниже этой скорости таран не срабатывает
export const RAM_DMG_PER_SPEED = 8;
export const RAM_PUSH = 3;

// ---------------------------------------------------------------- рывок (таран)
/** Дистанция рывка, px. */
export const DASH_DISTANCE = 100;
/** Множитель скорости во время рывка. */
export const DASH_SPEED_MULT = 1.5;
/** Кулдаун рывка, тиков. */
export const DASH_COOLDOWN = 120; // 2 сек

export const MINE_DMG = 40;
export const MINE_SPLASH_DMG = 20;
export const MINE_TRIGGER_R = 20;
export const MINE_SPLASH_R = 48;
export const MINE_LIFE = 600; // 10 сек
export const MINE_COOLDOWN = 60; // 1 сек между установками
export const MINE_MAX = 3; // одновременно на карте, на игрока

export const KAMIKAZE_DMG = 60;
export const KAMIKAZE_R = 64;

export const EXPLOSIVE_R = 32; // радиус урона по площади у «Взрывных пуль»
export const EXPLOSIVE_SPLASH = 0.5; // доля урона по соседним целям

export const SHIELD_HP = 30;
export const SHIELD_COOLDOWN = 30 * 60; // 30 сек
export const TURBO_DURATION = 180; // 3 сек
export const SHADOW_DURATION = 180; // 3 сек

// ---------------------------------------------------------------- аптечки
export const PICKUP_R = 20;
export const PICKUP_R_MAGNET = 40;
export const PICKUP_HEAL_FRACTION = 0.3; // от максимума HP
export const PICKUP_RESPAWN = 900; // 15 сек
export const PICKUP_MIN = 4;
export const PICKUP_MAX = 6;

// ---------------------------------------------------------------- бот
export const BOT_SIGHT = 500; // дистанция обнаружения по прямой видимости
export const BOT_COMBAT_RANGE = 450; // вход в состояние боя
export const BOT_FIRE_RANGE = 500;
export const BOT_KEEP_MIN = 80; // ближе — отступать
export const BOT_KEEP_MAX = 250; // дальше — сближаться
export const BOT_DODGE_LOOKAHEAD = 40; // радиус реакции на летящую пулю
export const BOT_PATH_REFRESH = 60; // тиков между перестройками пути
export const BOT_MAX_PERKS = 4;
export const BOT_PERK_CHANCE = 0.4; // шанс получить перк за убийство

// ---------------------------------------------------------------- прогресс
export const XP_PER_KILL = 100;
export const XP_PER_CAPTURE = 200;
export const SCORE_PER_KILL = 100;
export const SCORE_PER_CAPTURE = 500;
export const MAX_EQUIPPED_PERKS = 3;

/** Опыт до следующего уровня внутри партии. */
export const xpForSessionLevel = (lvl) => 300 + lvl * 200;
/** Опыт до следующего глобального (профильного) уровня. */
export const xpForGlobalLevel = (lvl) => 400 + lvl * 250;

// ---------------------------------------------------------------- режимы
export const MODES = {
  ffa: { id: 'ffa', name: 'Каждый за себя', fragLimit: 20 },
  ctf: { id: 'ctf', name: 'Захват флага', capLimit: 5, flagsPerTeam: 3, teamSize: 4 },
  koth: {
    id: 'koth',
    name: 'Царь горы',
    enemies: 40,
    duration: 5 * 60 * TICK_HZ, // 5 минут — лимит партии
    floodDuration: 2 * 60 * TICK_HZ, // 2 минуты — полное затопление карты
  },
  defense: {
    id: 'defense',
    name: 'Оборона',
    waves: 5,
    baseHP: 1000,
    startDelay: 4 * TICK_HZ, // 4 сек до первой волны
    waveDelay: 5 * TICK_HZ, // 5 сек между волнами
    baseDPS: 0.15, // урон базе за тик от врага рядом с ней (9 HP/сек на врага)
    baseRadius: 64, // враг в этом радиусе начинает ломать базу
  },
};

/** «Оборона»: численность первой волны. */
export const DEFENSE_FIRST_WAVE = 5;
/** Вклад уровня игрока в размер волны — кап, чтобы ветеранов не задавило ордой. */
export const DEFENSE_LEVEL_BONUS_CAP = 1;
/** Каждая следующая волна: DEFENSE_FIRST_WAVE + вклад уровня + рост по волнам. */
export const DEFENSE_PLAYER_LEVEL_BONUS = true;
/** Потолок численности одной волны. */
export const DEFENSE_WAVE_CAP = 30;
/** Номер волны, на которой гарантированно появляется босс. */
export const DEFENSE_BOSS_WAVE = 5;
/** Подъём сложности за волну (типы врагов становятся злее). */
export const DEFENSE_RAMP_STEP = 0.08;
/** «Оборона»: запас прочности игрока (он один против орды). */
export const DEFENSE_PLAYER_HP_MULT = 2;
/** «Оборона»: штраф к точности врагов (перекрёстный огонь слишком карал). */
export const DEFENSE_ENEMY_ACCURACY_PENALTY = 0.2;
/** «Оборона»: доля HP базы, восстанавливаемая за тик в паузе между волнами. */
export const DEFENSE_BASE_REGEN_PER_TICK = 0.002;

/** Авиаудар («Оборона», клавиша F): база урона и доля от максимального HP. */
export const AIRSTRIKE_DMG = 70;
export const AIRSTRIKE_MAX_HP_FRACTION = 0.1;
/** Перезарядка авиаудара, тиков (90 секунд). */
export const AIRSTRIKE_COOLDOWN = 90 * TICK_HZ;

/** Доля пустых тайлов карты, занятых минами в «Царе горы». */
export const MINE_SCATTER_FRACTION = 0.05;
/** Время жизни рассыпанных по карте мин, тиков (больше, чем длительность). */
export const SCATTER_MINE_LIFE = 6 * 60 * TICK_HZ;

// ---------------------------------------------------------------- валюта
/** Монеты за убийство врага (когда убийца — человек). */
export const REWARD_KILL = 10;
/** Монеты за захват флага в CTF. */
export const REWARD_CAPTURE = 30;
/** Монеты за победу в партии (когда выиграл игрок). */
export const REWARD_WIN = 50;

/**
 * Сложность. enemies — число ботов в FFA, teamSize в CTF берётся из MODES.
 * fireRate — тиков между выстрелами.
 */
export const DIFFICULTY = {
  easy: {
    name: 'Легко',
    enemies: 8,
    enemyHP: 60,
    enemySpeed: 0.88,
    enemyFireRate: 69,
    enemyAccuracy: 0.6,
    enemyReactTime: 30,
    playerHP: 150,
  },
  medium: {
    name: 'Средне',
    enemies: 14,
    enemyHP: 80,
    enemySpeed: 1.18,
    enemyFireRate: 46,
    enemyAccuracy: 0.75,
    enemyReactTime: 20,
    playerHP: 100,
  },
  hard: {
    name: 'Сложно',
    enemies: 22,
    enemyHP: 100,
    enemySpeed: 1.47,
    enemyFireRate: 31,
    enemyAccuracy: 0.9,
    enemyReactTime: 10,
    playerHP: 80,
  },
};

export const PLAYER_SPEED = 1.3; // px/тик
export const PLAYER_FIRE_RATE = 19; // тиков

/** Постепенное усиление ботов, чтобы затяжная партия не становилась скучной. */
export const RAMP_INTERVAL = 3600; // раз в 60 сек
export const RAMP_STEP = 0.08;
export const RAMP_MAX = 1.8; // жёсткий предел, в старой версии его не было
