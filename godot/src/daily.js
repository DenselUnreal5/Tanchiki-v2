// ============================================================================
// daily.js — ежедневные задания с наградой монетами.
//
// Прогресс сбрасывается в полночь. Задания сдвигаются по кругу: каждый день
// выбирается подмножество из общего списка, чтобы не надоедать.
//
// Прогресс пополняется вызовом Profile.bumpDaily(key, amount) из игровых
// событий. Ключи-счётчики: kills, wins, captures, coins, games, damage.
// ============================================================================

/** Ключ текущего дня в формате YYYY-MM-DD (локальное время). */
export function todayKey(date = new Date()) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/**
 * id — уникальный ключ.
 * counter — ключ-счётчик (см. bumpDaily).
 * need — цель.
 * reward — монеты за выполнение.
 */
export const DAILY_QUESTS = [
  { id: 'kill_15', name: 'Охота', desc: 'Убить 15 врагов', icon: '🔫', counter: 'kills', need: 15, reward: 50 },
  { id: 'win_2', name: 'Триумф', desc: 'Одержать 2 победы', icon: '🏆', counter: 'wins', need: 2, reward: 45 },
  { id: 'capture_2', name: 'Флаг в руки', desc: 'Захватить 2 флага', icon: '🚩', counter: 'captures', need: 2, reward: 45 },
  { id: 'coins_100', name: 'Казначей', desc: 'Заработать 100 монет', icon: '💰', counter: 'coins', need: 100, reward: 55 },
  { id: 'games_3', name: 'Трудоголик', desc: 'Сыграть 3 партии', icon: '🎮', counter: 'games', need: 3, reward: 35 },
  { id: 'damage_2000', name: 'Артиллерия', desc: 'Нанести 2000 урона', icon: '💥', counter: 'damage', need: 2000, reward: 50 },
  { id: 'medkits_5', name: 'Полевой врач', desc: 'Подобрать 5 аптечек', icon: '🩹', counter: 'medkits', need: 5, reward: 40 },
  { id: 'streak_5', name: 'Фортуна', desc: 'Серия 5 убийств без урона', icon: '🍀', counter: 'streak', need: 5, reward: 60 },
];

/** Сколько заданий выдаётся в день. */
export const DAILY_PER_DAY = 4;

/** Выбирает подмножество заданий дня по дате (детерминированно). */
export function dailySelection(date = new Date()) {
  const key = todayKey(date);
  const sum = [...key].reduce((s, ch) => s + ch.charCodeAt(0), 0);
  const start = sum % DAILY_QUESTS.length;
  const out = [];
  for (let i = 0; i < DAILY_PER_DAY; i++) {
    out.push(DAILY_QUESTS[(start + i) % DAILY_QUESTS.length]);
  }
  return out;
}

export function getDaily(id) {
  return DAILY_QUESTS.find((q) => q.id === id) ?? null;
}
