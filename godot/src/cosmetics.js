// ============================================================================
// cosmetics.js — косметика за монеты: рисунки корпуса, гусеницы и башни.
//
// Никакой механики не добавляет — только влияет на отрисовку танка
// (Renderr.#drawTank). «none» бесплатен и доступен всем; остальные покупаются
// в Гараже и экипируются. Косметика применяется к живым людям в партии:
// профиль один на машину, поэтому выбранный комплект общий для обоих игроков.
// ============================================================================

export const COSMETIC_TYPES = ['hull', 'track', 'turret'];

/** Рисунки корпуса. */
export const COSMETIC_HULLS = [
  { id: 'none', type: 'hull', name: 'Без рисунка', icon: '⬛', price: 0 },
  { id: 'stripes', type: 'hull', name: 'Камуфляж', icon: '🎨', price: 120 },
  { id: 'star', type: 'hull', name: 'Звезда', icon: '⭐', price: 150 },
  { id: 'flames', type: 'hull', name: 'Пламя', icon: '🔥', price: 200 },
  { id: 'cross', type: 'hull', name: 'Крест', icon: '✚', price: 100 },
  { id: 'chevrons', type: 'hull', name: 'Шевроны', icon: '🔺', price: 140 },
];

/** Гусеницы. */
export const COSMETIC_TRACKS = [
  { id: 'none', type: 'track', name: 'Стандартные', icon: '⬜', price: 0 },
  { id: 'gold', type: 'track', name: 'Золотые', icon: '✨', price: 180, color: '#d4af37' },
  { id: 'steel', type: 'track', name: 'Стальные', icon: '🪨', price: 100, color: '#9a9a9a' },
  { id: 'ruby', type: 'track', name: 'Рубиновые', icon: '🔴', price: 130, color: '#c0392b' },
];

/** Башни. */
export const COSMETIC_TURRETS = [
  { id: 'none', type: 'turret', name: 'Стандартная', icon: '🔘', price: 0 },
  { id: 'gold', type: 'turret', name: 'Золотая', icon: '👑', price: 160, color: '#d4af37' },
  { id: 'red', type: 'turret', name: 'Алая', icon: '🔴', price: 90, color: '#e05555' },
  { id: 'night', type: 'turret', name: 'Ночная', icon: '🌑', price: 140, color: '#11131a' },
];

/** Все косметические предметы одним списком. */
export const ALL_COSMETICS = [...COSMETIC_HULLS, ...COSMETIC_TRACKS, ...COSMETIC_TURRETS];

/** Список по типу. */
export const COSMETICS_BY_TYPE = {
  hull: COSMETIC_HULLS,
  track: COSMETIC_TRACKS,
  turret: COSMETIC_TURRETS,
};

/** Поиск по типу и id: id уникальны внутри типа, но могут повторяться между типами. */
export function getCosmetic(type, id) {
  return (COSMETICS_BY_TYPE[type] ?? []).find((c) => c.id === id) ?? null;
}
