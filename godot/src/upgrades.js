// ============================================================================
// upgrades.js — постоянные улучшения танка за валюту (Гараж).
//
// Улучшения живут в профиле и действуют на каждого живого игрока в партии
// (профиль общий на машину, как и опыт). Эффект задаётся так же, как у перков,
// — множителем модификатора: профильный бонус перемножается с бонусом перков
// в Tank.recompute().
//
// cost(level) — цена следующего уровня (level — уже купленный уровень).
// mult(level) — итоговый множитель на купленном уровне.
// ============================================================================

/** Категории улучшений — порядок разделов в Гараже. */
export const UPGRADE_CATEGORIES = [
  { id: 'fire', name: 'Огонь', color: '#ff8833' },
  { id: 'defense', name: 'Защита', color: '#44aaff' },
  { id: 'speed', name: 'Скорость', color: '#ffee55' },
  { id: 'utility', name: 'Полезное', color: '#55ff88' },
];

/** Рост цены за уровень: база * (level * шаг). */
const growing = (base, step) => (level) => Math.round(base + (level - 1) * step);

export const UPGRADES = [
  {
    id: 'dmg',
    name: 'Мощный ствол',
    icon: '💥',
    desc: 'Урон своих пуль',
    category: 'fire',
    modKey: 'dmgMult',
    maxLevel: 10,
    cost: growing(60, 25),
    mult: (level) => 1 + level * 0.06,
  },
  {
    id: 'fire_rate',
    name: 'Автоускоритель',
    icon: '⚡',
    desc: 'Перезарядка быстрее',
    category: 'fire',
    modKey: 'fireRateMult',
    maxLevel: 10,
    cost: growing(50, 20),
    mult: (level) => 1 - level * 0.03,
  },
  {
    id: 'bullet_speed',
    name: 'Тяжёлые снаряды',
    icon: '🚀',
    desc: 'Скорость полёта пуль',
    category: 'fire',
    modKey: 'bulletSpeedMult',
    maxLevel: 8,
    cost: growing(40, 15),
    mult: (level) => 1 + level * 0.05,
  },
  {
    id: 'max_hp',
    name: 'Усиленная броня',
    icon: '🛡',
    desc: 'Максимум HP',
    category: 'defense',
    modKey: 'maxHPMult',
    maxLevel: 10,
    cost: growing(55, 25),
    mult: (level) => 1 + level * 0.07,
  },
  {
    id: 'damage_taken',
    name: 'Композитная броня',
    icon: '🧱',
    desc: 'Получаемый урон меньше',
    category: 'defense',
    modKey: 'damageTakenMult',
    maxLevel: 8,
    cost: growing(70, 30),
    mult: (level) => 1 - level * 0.04,
  },
  {
    id: 'speed',
    name: 'Форсированный мотор',
    icon: '👟',
    desc: 'Предельная скорость',
    category: 'speed',
    modKey: 'speedMult',
    maxLevel: 10,
    cost: growing(45, 20),
    mult: (level) => 1 + level * 0.045,
  },
  {
    id: 'ram',
    name: 'Бронекаток',
    icon: '🚛',
    desc: 'Урон тараном',
    category: 'speed',
    modKey: 'ramMult',
    maxLevel: 8,
    cost: growing(50, 22),
    mult: (level) => 1 + level * 0.1,
  },
  {
    id: 'pickup_radius',
    name: 'Магнитный трал',
    icon: '🧲',
    desc: 'Радиус подбора аптечек',
    category: 'utility',
    modKey: 'pickupRadiusMult',
    maxLevel: 6,
    cost: growing(35, 15),
    mult: (level) => 1 + level * 0.15,
  },
  {
    id: 'regen',
    name: 'Ремонтный модуль',
    icon: '❤',
    desc: 'HP в минуту',
    category: 'utility',
    modKey: 'regenPerMinute',
    maxLevel: 6,
    cost: growing(55, 25),
    mult: (level) => level * 20, // 20/40/... HP в минуту
  },
];

/** Цена следующего уровня. */
export function upgradeCost(upgrade, level) {
  return upgrade.cost(level + 1);
}
