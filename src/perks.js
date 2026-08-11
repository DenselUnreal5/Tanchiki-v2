// ============================================================================
// perks.js — описание перков.
//
// Главное отличие от старой версии: числовые эффекты перков описаны
// декларативно и пересчитываются с нуля функцией computeModifiers().
// Раньше «Тяжёлая броня» разово прибавляла maxHP прямо в объект танка, и при
// снятии перка бонус оставался навсегда. Теперь снятие перка честно
// возвращает характеристики обратно.
// ============================================================================

import { TURBO_DURATION, SHADOW_DURATION } from './config.js';

/** Значения по умолчанию — «перков нет». */
function baseModifiers() {
  return {
    maxHPMult: 1, // множитель максимума HP
    speedMult: 1, // множитель предельной скорости
    fireRateMult: 1, // множитель времени перезарядки (меньше — быстрее)
    dmgMult: 1, // множитель урона своих пуль
    bulletSpeedMult: 1, // множитель скорости своих пуль
    damageTakenMult: 1, // множитель получаемого урона
    ramMult: 1, // множитель урона тараном
    accuracyBonus: 0, // прибавка к точности (только боты)
    evasionChance: 0, // шанс полностью уклониться от урона
    reflectFraction: 0, // доля урона, возвращаемая атакующему
    pickupRadiusMult: 1, // множитель радиуса подбора аптечек
    lifestealFraction: 0, // доля нанесённого урона, идущая в лечение
    regenPerMinute: 0, // HP в минуту
    turboOnKill: 0, // длительность ускорения после убийства, тиков
    shadowOnKill: 0, // длительность невидимости на миникарте, тиков
  };
}

/**
 * Категории перков. Порядок задаёт порядок разделов в галерее.
 */
export const PERK_CATEGORIES = [
  { id: 'fire', name: 'Огонь', color: '#ff8833' },
  { id: 'defense', name: 'Защита', color: '#44aaff' },
  { id: 'speed', name: 'Скорость', color: '#ffee55' },
  { id: 'special', name: 'Особые', color: '#ff55ff' },
  { id: 'challenge', name: 'Челленджи', color: '#ff4455' },
];

/**
 * Перки игрока.
 *
 * mods  — числовые модификаторы (складываются/перемножаются в computeModifiers).
 * flags — поведенческие метки, которые читает игровая логика напрямую.
 */
export const PERKS = [
  // ---------------------------------------------------------------- огонь
  {
    id: 'double_shot',
    name: 'Двойной выстрел',
    icon: '🔫',
    desc: '2 пули параллельно',
    category: 'fire',
    flags: ['doubleShot'],
  },
  {
    id: 'fan_shot',
    name: 'Выстрел веером',
    icon: '🌊',
    desc: '3 пули веером, каждая 45% урона',
    category: 'fire',
    flags: ['fanShot'],
  },
  {
    id: 'rapid_fire',
    name: 'Скорострельность',
    icon: '⚡',
    desc: 'Перезарядка быстрее на 40%',
    category: 'fire',
    mods: { fireRateMult: 0.6 },
  },
  {
    id: 'explosive',
    name: 'Взрывные пули',
    icon: '💥',
    desc: 'Урон по площади 32 px и снос кирпича вокруг',
    category: 'fire',
    flags: ['explosive'],
  },
  {
    id: 'piercing',
    name: 'Пробивной выстрел',
    icon: '🎯',
    desc: 'Пуля пробивает одну стену',
    category: 'fire',
    flags: ['piercing'],
  },

  // ---------------------------------------------------------------- защита
  {
    id: 'heavy_armor',
    name: 'Тяжёлая броня',
    icon: '🛡',
    desc: 'Максимум HP +50%',
    category: 'defense',
    mods: { maxHPMult: 1.5 },
  },
  {
    id: 'regen',
    name: 'Регенерация',
    icon: '❤',
    desc: '60 HP в минуту (1 HP/сек)',
    category: 'defense',
    mods: { regenPerMinute: 60 },
  },
  {
    id: 'reflect',
    name: 'Отражение',
    icon: '🪞',
    desc: '20% полученного урона возвращается атакующему',
    category: 'defense',
    mods: { reflectFraction: 0.2 },
  },
  {
    id: 'evasion',
    name: 'Уклонение',
    icon: '💨',
    desc: '15% шанс полностью избежать урона',
    category: 'defense',
    mods: { evasionChance: 0.15 },
  },
  {
    id: 'shield',
    name: 'Энергощит',
    icon: '🔵',
    desc: 'Щит на 30 HP, восстанавливается раз в 30 сек',
    category: 'defense',
    flags: ['shield'],
  },

  // ---------------------------------------------------------------- скорость
  {
    id: 'sprinter',
    name: 'Спринтер',
    icon: '👟',
    desc: 'Скорость +25%',
    category: 'speed',
    mods: { speedMult: 1.25 },
  },
  {
    id: 'quick_reload',
    name: 'Быстрая перезарядка',
    icon: '🔄',
    desc: 'Перезарядка быстрее на 30%',
    category: 'speed',
    mods: { fireRateMult: 0.7 },
  },

  // ---------------------------------------------------------------- особые
  {
    id: 'mines',
    name: 'Миноукладчик',
    icon: '💣',
    desc: 'До 3 мин на карте, ставятся клавишей мины',
    category: 'special',
    flags: ['mines'],
  },

  // ------------------------------------------------------- челленджи
  {
    id: 'ram',
    name: 'Таран',
    icon: '🚛',
    desc: 'Урон при столкновении x2',
    category: 'challenge',
    mods: { ramMult: 2 },
    challenge: { desc: 'Уничтожь 3 танка тараном', stat: 'ramKills', need: 3 },
  },
  {
    id: 'thick_armor',
    name: 'Толстая броня',
    icon: '🧱',
    // В старой версии этот перк был чистым минусом: пули игрока перестают
    // ломать кирпич — и никакого плюса. Добавлен реальный компромисс.
    desc: 'Получаемый урон −20%, но ваши пули не ломают кирпич',
    category: 'challenge',
    mods: { damageTakenMult: 0.8 },
    flags: ['keepBricks'],
    challenge: { desc: 'Разбей 15 кирпичей', stat: 'bricksDestroyed', need: 15 },
  },
  {
    id: 'amphibious',
    name: 'Амфибия',
    icon: '🐸',
    desc: 'В воде только замедление, без урона',
    category: 'challenge',
    flags: ['amphibious'],
    challenge: { desc: 'Войди в воду 5 раз', stat: 'waterEntries', need: 5 },
  },
  {
    id: 'forest',
    name: 'Лесной житель',
    icon: '🌲',
    desc: 'Проезд через деревья, не уничтожая их',
    category: 'challenge',
    flags: ['forest'],
    challenge: { desc: 'Проедь через 5 деревьев', stat: 'treesDriven', need: 5 },
  },
  {
    id: 'magnet',
    name: 'Магнит',
    icon: '🧲',
    desc: 'Радиус подбора аптечек x2',
    category: 'challenge',
    mods: { pickupRadiusMult: 2 },
    challenge: { desc: 'Собери 20 аптечек', stat: 'healthPacksCollected', need: 20 },
  },
  {
    id: 'sniper',
    name: 'Снайпер',
    icon: '🔭',
    desc: 'Пули летят на 40% быстрее и наносят +15% урона',
    category: 'challenge',
    mods: { bulletSpeedMult: 1.4, dmgMult: 1.15 },
    challenge: { desc: 'Убей 3 врагов с дистанции 400 px', stat: 'longKills', need: 3 },
  },
  {
    id: 'berserk',
    name: 'Берсерк',
    icon: '😤',
    desc: 'Урон ×1.6, пока ваше HP ≤ 40%',
    category: 'challenge',
    flags: ['berserk'],
    challenge: { desc: 'Убей 5 врагов при HP ≤ 40%', stat: 'lowHpKills', need: 5 },
  },
  {
    id: 'kamikaze',
    name: 'Камикадзе',
    icon: '💀',
    desc: 'При смерти взрыв на 64 px',
    category: 'challenge',
    flags: ['kamikaze'],
    challenge: { desc: 'Умри 10 раз', stat: 'timesDied', need: 10 },
  },
  {
    id: 'turbo',
    name: 'Турбо',
    icon: '🚀',
    desc: 'Ускорение x1.5 на 3 сек после убийства',
    category: 'challenge',
    mods: { turboOnKill: TURBO_DURATION },
    challenge: { desc: 'Убей 5 врагов за 10 секунд', stat: 'rapidKills', need: 5 },
  },
  {
    id: 'shadow',
    name: 'Тень',
    icon: '🌑',
    desc: 'Невидимость на миникарте 3 сек после убийства',
    category: 'challenge',
    mods: { shadowOnKill: SHADOW_DURATION },
    challenge: { desc: '3 убийства подряд без урона', stat: 'cleanStreak', need: 3 },
  },
  {
    id: 'vampire',
    name: 'Вампир',
    icon: '🧛',
    desc: '15% нанесённого урона возвращается как HP',
    category: 'challenge',
    mods: { lifestealFraction: 0.15 },
    challenge: { desc: 'Нанеси 5000 урона за партию', stat: 'damageInGame', need: 5000 },
  },
];

const PERK_BY_ID = new Map(PERKS.map((p) => [p.id, p]));

export function getPerk(id) {
  return PERK_BY_ID.get(id);
}

/**
 * Перки, запрещённые в конкретном режиме. В «Царе горы» нет «Амфибии»:
 * вся соль режима — тонущая карта, и прятаться от неё нельзя.
 */
const MODE_BANNED = { koth: new Set(['amphibious']) };

/** Возвращает id перков, допустимых в данном режиме. */
export function filterPerksForMode(ids, mode) {
  const banned = MODE_BANNED[mode];
  if (!banned) return ids;
  return ids.filter((id) => !banned.has(id));
}

/** Можно ли этот перк в этом режиме. */
export function isPerkAllowedInMode(id, mode) {
  return !(MODE_BANNED[mode]?.has(id) ?? false);
}

export function perkIcon(id) {
  return PERK_BY_ID.get(id)?.icon ?? '⭐';
}

export function perkName(id) {
  return PERK_BY_ID.get(id)?.name ?? id;
}

/**
 * Перки, открываемые за глобальные уровни профиля.
 *
 * В старой версии таблица начиналась со 2-го уровня, но при выборе перка код
 * всё равно предлагал ВСЕ нечелленджевые перки. То есть галерея обещала
 * «откроется на 5 уровне», а взять перк можно было сразу — таблица ни на что
 * не влияла. Здесь на 1-м уровне выдаются три стартовых перка, дальше
 * открытие реально работает.
 */
export const UNLOCK_TABLE = {
  1: ['rapid_fire', 'heavy_armor', 'sprinter'],
  2: ['double_shot', 'regen'],
  3: ['quick_reload', 'evasion'],
  4: ['fan_shot', 'reflect'],
  5: ['explosive', 'shield'],
  6: ['piercing'],
  7: ['mines'],
};

/** На каком глобальном уровне открывается перк (или null для челленджей). */
export function unlockLevelOf(perkId) {
  for (const [lvl, ids] of Object.entries(UNLOCK_TABLE)) {
    if (ids.includes(perkId)) return Number(lvl);
  }
  return null;
}

/**
 * Собирает итоговые модификаторы из набора перков.
 * Множители перемножаются, прибавки складываются, шансы объединяются
 * вероятностно (1 - произведение промахов), чтобы никогда не превысить 100%.
 */
export function computeModifiers(perkIds, source = PERK_BY_ID) {
  const m = baseModifiers();
  if (!perkIds || perkIds.length === 0) return m;

  let evasionMiss = 1;
  for (const id of perkIds) {
    const perk = source.get ? source.get(id) : source[id];
    if (!perk || !perk.mods) continue;
    const mods = perk.mods;
    if (mods.maxHPMult !== undefined) m.maxHPMult *= mods.maxHPMult;
    if (mods.speedMult !== undefined) m.speedMult *= mods.speedMult;
    if (mods.fireRateMult !== undefined) m.fireRateMult *= mods.fireRateMult;
    if (mods.dmgMult !== undefined) m.dmgMult *= mods.dmgMult;
    if (mods.bulletSpeedMult !== undefined) m.bulletSpeedMult *= mods.bulletSpeedMult;
    if (mods.damageTakenMult !== undefined) m.damageTakenMult *= mods.damageTakenMult;
    if (mods.ramMult !== undefined) m.ramMult *= mods.ramMult;
    if (mods.pickupRadiusMult !== undefined) m.pickupRadiusMult *= mods.pickupRadiusMult;
    if (mods.accuracyBonus !== undefined) m.accuracyBonus += mods.accuracyBonus;
    if (mods.reflectFraction !== undefined) m.reflectFraction += mods.reflectFraction;
    if (mods.lifestealFraction !== undefined) m.lifestealFraction += mods.lifestealFraction;
    if (mods.regenPerMinute !== undefined) m.regenPerMinute += mods.regenPerMinute;
    if (mods.evasionChance !== undefined) evasionMiss *= 1 - mods.evasionChance;
    if (mods.turboOnKill !== undefined) m.turboOnKill = Math.max(m.turboOnKill, mods.turboOnKill);
    if (mods.shadowOnKill !== undefined) m.shadowOnKill = Math.max(m.shadowOnKill, mods.shadowOnKill);
  }
  m.evasionChance = 1 - evasionMiss;
  return m;
}

/** Собирает множество поведенческих меток из набора перков. */
export function computeFlags(perkIds, source = PERK_BY_ID) {
  const set = new Set();
  if (!perkIds) return set;
  for (const id of perkIds) {
    const perk = source.get ? source.get(id) : source[id];
    if (!perk || !perk.flags) continue;
    for (const f of perk.flags) set.add(f);
  }
  return set;
}

// ============================================================================
// Перки ботов — та же схема модификаторов, чтобы пересчёт работал одинаково.
// ============================================================================

export const BOT_PERKS = [
  { id: 'bot_rapid', icon: '⚡', name: 'Скорострельность', desc: 'Перезарядка x0.7', mods: { fireRateMult: 0.7 } },
  { id: 'bot_speed', icon: '👟', name: 'Ноги', desc: 'Скорость x1.3', mods: { speedMult: 1.3 } },
  { id: 'bot_tough', icon: '🛡', name: 'Толстая броня', desc: 'Максимум HP +40%', mods: { maxHPMult: 1.4 } },
  { id: 'bot_double', icon: '🔫', name: 'Двойной выстрел', desc: '2 пули параллельно', flags: ['doubleShot'] },
  { id: 'bot_accurate', icon: '🎯', name: 'Снайпер', desc: 'Точность +15%', mods: { accuracyBonus: 0.15 } },
  { id: 'bot_regen', icon: '❤', name: 'Регенерация', desc: '60 HP в минуту', mods: { regenPerMinute: 60 } },
  { id: 'bot_heavy', icon: '💥', name: 'Тяжёлые пули', desc: 'Урон +25%', mods: { dmgMult: 1.25 } },
  { id: 'bot_evasion', icon: '💨', name: 'Уклонение', desc: '15% шанс уклонения', mods: { evasionChance: 0.15 } },
];

const BOT_PERK_BY_ID = new Map(BOT_PERKS.map((p) => [p.id, p]));

export function getBotPerk(id) {
  return BOT_PERK_BY_ID.get(id);
}

export function computeBotModifiers(perkIds) {
  return computeModifiers(perkIds, BOT_PERK_BY_ID);
}

export function computeBotFlags(perkIds) {
  return computeFlags(perkIds, BOT_PERK_BY_ID);
}

/** Иконка перка любого вида — игрока или бота. */
export function anyPerkIcon(id) {
  return PERK_BY_ID.get(id)?.icon ?? BOT_PERK_BY_ID.get(id)?.icon ?? '⭐';
}
