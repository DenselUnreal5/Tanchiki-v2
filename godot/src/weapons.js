// ============================================================================
// weapons.js — временное оружие с карты (power-up).
//
// Каждое оружие меняет поведение выстрела танка на ограниченное время.
// Действует на конкретный танк (this.weapon / this.weaponTimer у Tank),
// в бою отображается в HUD. Оружие не влияет на баланс навсегда — по истечении
// таймера танк возвращается к штатному пулемёту.
// ============================================================================

export const WEAPONS = {
  gatling: {
    id: 'gatling',
    name: 'Пулемёт',
    icon: '🔥',
    color: '#ffaa33',
    duration: 60 * 8, // 8 секунд
    cooldownMult: 0.45, // стреляет вдвое чаще
    dmgScale: 0.55, // но каждая пуля слабее
    spread: 0.06,
    bullets: 1,
  },
  rockets: {
    id: 'rockets',
    name: 'Ракеты',
    icon: '🚀',
    color: '#ff5566',
    duration: 60 * 8,
    cooldownMult: 2.2, // реже
    dmgScale: 1.9,
    spread: 0.02,
    bullets: 1,
    explosive: true,
  },
  shotgun: {
    id: 'shotgun',
    name: 'Дробовик',
    icon: '💥',
    color: '#ffcc44',
    duration: 60 * 6,
    cooldownMult: 2.0,
    dmgScale: 0.4,
    spread: 0.22,
    bullets: 6,
  },
};

export function getWeapon(id) {
  return WEAPONS[id] ?? null;
}
