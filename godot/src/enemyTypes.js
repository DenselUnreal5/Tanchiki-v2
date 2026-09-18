// ============================================================================
// enemyTypes.js — типы врагов-ботов и мини-босс.
//
// Тип влияет на характеристики танка (HP/скорость/скорострельность), на урон
// и на поведение «мозга» (дальность боя, дистанцию удержания, точность).
// Выбор типа при спавне идёт по весам, а сложные типы открываются по мере
// роста «рампы» сложности — чтобы затяжная партия не превращалась в полк
// снайперов. Босс редок, огромен по запасу прочности и щедро платит.
// ============================================================================

export const ENEMY_TYPES = {
  grunt: {
    id: 'grunt', name: 'Рядовой', icon: '🪖',
    hpMult: 1, speedMult: 1, fireRateMult: 1, dmgScale: 1, accuracyBonus: 0, reactMult: 1,
    fireRange: 500, keepMin: 80, keepMax: 250, role: 'attacker', colorKey: 'enemy',
    weight: 50, unlockRamp: 1, lobbed: false, boss: false,
  },
  scout: {
    id: 'scout', name: 'Разведчик', icon: '🏃',
    hpMult: 0.75, speedMult: 1.3, fireRateMult: 0.5, dmgScale: 0.5, accuracyBonus: -0.1, reactMult: 0.9,
    fireRange: 380, keepMin: 60, keepMax: 200, role: 'attacker', colorKey: 'scout',
    weight: 22, unlockRamp: 1, lobbed: false, boss: false,
  },
  heavy: {
    id: 'heavy', name: 'Громила', icon: '🛡️',
    hpMult: 2.2, speedMult: 0.8, fireRateMult: 1.5, dmgScale: 1.35, accuracyBonus: 0, reactMult: 1.1,
    fireRange: 400, keepMin: 120, keepMax: 280, role: 'attacker', colorKey: 'heavy',
    weight: 16, unlockRamp: 1.08, lobbed: false, boss: false,
  },
  sniper: {
    id: 'sniper', name: 'Снайпер', icon: '🎯',
    hpMult: 0.9, speedMult: 1, fireRateMult: 2.2, dmgScale: 2.5, accuracyBonus: 0.18, reactMult: 1.3,
    fireRange: 650, keepMin: 300, keepMax: 450, role: 'defender', colorKey: 'sniper',
    weight: 10, unlockRamp: 1.16, lobbed: false, boss: false,
  },
  mortar: {
    id: 'mortar', name: 'Миномёт', icon: '💣',
    hpMult: 1.1, speedMult: 0.85, fireRateMult: 2.5, dmgScale: 1.2, accuracyBonus: 0, reactMult: 1.2,
    fireRange: 600, keepMin: 320, keepMax: 420, role: 'defender', colorKey: 'mortar',
    weight: 8, unlockRamp: 1.16, lobbed: true, boss: false,
  },
  boss: {
    id: 'boss', name: 'Бронемонстр', icon: '👹',
    hpMult: 5, speedMult: 0.75, fireRateMult: 1.2, dmgScale: 1.6, accuracyBonus: 0.1, reactMult: 1,
    fireRange: 420, keepMin: 100, keepMax: 300, role: 'attacker', colorKey: 'boss',
    weight: 3, unlockRamp: 1.24, lobbed: false, boss: true,
  },
};

/** Порядок и лейблы типов для отчётов/интерфейса. */
export const ENEMY_TYPE_ORDER = ['grunt', 'scout', 'heavy', 'sniper', 'mortar', 'boss'];

export function getEnemyType(id) {
  return ENEMY_TYPES[id] ?? null;
}

/**
 * Случайный тип с учётом рампы сложности. Тяжёлые/дальнобойные типы открываются
 * позже, босс — редко и только на поздней рампе.
 * @param {number} ramp текущий множитель сложности (1..RAMP_MAX)
 * @param {() => number} rng
 * @param {string} [forced] принудительный тип (например 'ally' для союзников)
 */
export function pickEnemyType(ramp, rng = Math.random, forced = null) {
  if (forced) return ENEMY_TYPES[forced] ?? ENEMY_TYPES.grunt;
  const pool = [];
  for (const type of Object.values(ENEMY_TYPES)) {
    if (type.unlockRamp > ramp) continue;
    // На старте рампы вес тяжёлых типов почти нулевой — они раскрываются позже.
    const rampWeight = ramp < type.unlockRamp + 0.2 ? 0.35 : 1;
    for (let i = 0; i < type.weight * rampWeight; i++) pool.push(type);
  }
  return pool[Math.floor(rng() * pool.length)] ?? ENEMY_TYPES.grunt;
}
