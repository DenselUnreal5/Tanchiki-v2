// ============================================================================
// profile.js — постоянный прогресс между партиями (localStorage).
//
// Профиль один на машину: в «горячем стуле» оба живых игрока пополняют его
// опыт и статистику челленджей. Внутрипартийные уровни и перки при этом
// у каждого игрока свои — они живут в Player, а не здесь.
// ============================================================================

import { PERKS, UNLOCK_TABLE, unlockLevelOf } from './perks.js';
import { UPGRADES, upgradeCost } from './upgrades.js';
import { ACHIEVEMENTS, getAchievement } from './achievements.js';
import { DAILY_QUESTS, todayKey } from './daily.js';
import { ALL_COSMETICS, getCosmetic, COSMETIC_TYPES } from './cosmetics.js';
import { xpForGlobalLevel } from './config.js';

const STORAGE_KEY = 'tanchiki_v2_profile';
const SCHEMA = 6;

/** Список отслеживаемых статистик. Порядок не важен, важны имена. */
export const STAT_KEYS = [
  'ramKills',
  'bricksDestroyed',
  'waterEntries',
  'treesDriven',
  'healthPacksCollected',
  'gamesWon',
  'gamesPlayed',
  'timesDied',
  'totalKills',
  'rapidKills', // лучший результат: убийств за 10 сек
  'cleanStreak', // лучшая серия убийств без урона
  'damageInGame', // лучший урон за одну партию
  'longKills', // убийства с дистанции ≥ 400 px
  'lowHpKills', // убийства при HP ≤ 40%
];

/** Статистики-рекорды: обновляются по максимуму, а не суммированием. */
const MAX_STATS = new Set(['rapidKills', 'cleanStreak', 'damageInGame']);

function emptyStats() {
  const s = {};
  for (const k of STAT_KEYS) s[k] = 0;
  return s;
}

function emptyUpgrades() {
  const u = {};
  for (const up of UPGRADES) u[up.id] = 0;
  return u;
}

export class Profile {
  constructor(storage = safeStorage()) {
    this.storage = storage;
    this.globalLevel = 1;
    this.globalXP = 0;
    /** @type {Set<string>} */
    this.unlocked = new Set();
    this.stats = emptyStats();
    /** Валюта (монеты) на улучшения танка. */
    this.money = 0;
    /** @type {Record<string, number>} уровни постоянных улучшений танка. */
    this.upgrades = emptyUpgrades();
    /** @type {Set<string>} открытые достижения. */
    this.achievements = new Set();
    /**
     * Ежедневные задания: прогресс и полученные награды за текущий день.
     * @type {{date: string, progress: Record<string, number>, claimed: string[]}}
     */
    this.daily = { date: todayKey(), progress: {}, claimed: [] };
    /** @type {Set<string>} купленная косметика (без «none» — он бесплатен). */
    this.cosmeticOwned = new Set();
    /** Экипированная косметика: {hull, track, turret}. */
    this.cosmetics = { hull: 'none', track: 'none', turret: 'none' };
    /** Слушатели событий: 'levelup' | 'unlock' | 'achievement' | 'daily'. */
    this.listeners = new Map();
    this.load();
  }

  on(event, fn) {
    if (!this.listeners.has(event)) this.listeners.set(event, []);
    this.listeners.get(event).push(fn);
    return this;
  }

  #emit(event, payload) {
    const fns = this.listeners.get(event);
    if (!fns) return;
    for (const fn of fns) {
      try {
        fn(payload);
      } catch (e) {
        console.error('[profile] обработчик события упал:', e);
      }
    }
  }

  // -------------------------------------------------------------- хранилище
  load() {
    const raw = this.storage.get(STORAGE_KEY);
    if (raw) {
      try {
        const data = JSON.parse(raw);
        this.globalLevel = clampInt(data.globalLevel, 1, 999, 1);
        this.globalXP = clampInt(data.globalXP, 0, Number.MAX_SAFE_INTEGER, 0);
        if (Array.isArray(data.unlocked)) {
          const known = new Set(PERKS.map((p) => p.id));
          for (const id of data.unlocked) if (known.has(id)) this.unlocked.add(id);
        }
        if (data.stats && typeof data.stats === 'object') {
          for (const k of STAT_KEYS) {
            const v = Number(data.stats[k]);
            if (Number.isFinite(v) && v >= 0) this.stats[k] = v;
          }
        }
        this.money = clampInt(data.money, 0, Number.MAX_SAFE_INTEGER, 0);
        if (data.upgrades && typeof data.upgrades === 'object') {
          for (const up of UPGRADES) {
            const lvl = clampInt(data.upgrades[up.id], 0, up.maxLevel, 0);
            if (lvl > 0) this.upgrades[up.id] = lvl;
          }
        }
        if (Array.isArray(data.achievements)) {
          const known = new Set(ACHIEVEMENTS.map((a) => a.id));
          for (const id of data.achievements) if (known.has(id)) this.achievements.add(id);
        }
        if (data.daily && typeof data.daily === 'object' && data.daily.date) {
          this.daily = {
            date: String(data.daily.date),
            progress: data.daily.progress && typeof data.daily.progress === 'object' ? data.daily.progress : {},
            claimed: Array.isArray(data.daily.claimed) ? data.daily.claimed : [],
          };
        }
        if (Array.isArray(data.cosmeticOwned)) {
        const known = new Set(ALL_COSMETICS.map((c) => `${c.type}:${c.id}`));
        for (const key of data.cosmeticOwned) {
          if (typeof key === 'string' && known.has(key)) this.cosmeticOwned.add(key);
        }
        }
        if (data.cosmetics && typeof data.cosmetics === 'object') {
          for (const type of COSMETIC_TYPES) {
            const id = data.cosmetics[type];
            if (id && this.isCosmeticOwned(type, id)) this.cosmetics[type] = id;
          }
        }
        this.#refreshDailyIfStale();
      } catch {
        // Повреждённое сохранение не должно ломать запуск игры.
        console.warn('[profile] сохранение повреждено, начинаем заново');
      }
    }
    // Догоняем открытия, положенные по текущему уровню (например, после
    // изменения таблицы разблокировок в новой версии игры).
    this.#syncLevelUnlocks();
  }

  save() {
    this.storage.set(
      STORAGE_KEY,
      JSON.stringify({
        schema: SCHEMA,
        globalLevel: this.globalLevel,
        globalXP: this.globalXP,
        unlocked: [...this.unlocked],
        stats: this.stats,
        money: this.money,
        upgrades: this.upgrades,
        achievements: [...this.achievements],
        daily: this.daily,
        cosmeticOwned: [...this.cosmeticOwned],
        cosmetics: this.cosmetics,
      }),
    );
  }

  reset() {
    this.globalLevel = 1;
    this.globalXP = 0;
    this.unlocked.clear();
    this.stats = emptyStats();
    this.money = 0;
    this.upgrades = emptyUpgrades();
    this.achievements.clear();
    this.daily = { date: todayKey(), progress: {}, claimed: [] };
    this.cosmeticOwned.clear();
    this.cosmetics = { hull: 'none', track: 'none', turret: 'none' };
    this.#syncLevelUnlocks();
    this.save();
  }

  // -------------------------------------------------------------- опыт
  xpToNextLevel() {
    return xpForGlobalLevel(this.globalLevel);
  }

  /**
   * Начисляет глобальный опыт. Возвращает описание того, что изменилось,
   * и параллельно рассылает события — UI сам решает, что показывать.
   */
  addXP(amount) {
    if (!Number.isFinite(amount) || amount <= 0) return { levels: [], unlocked: [] };
    this.globalXP += Math.round(amount);
    const levels = [];
    const unlocked = [];
    // Ограничение на всякий случай: не крутить бесконечный цикл на кривых данных.
    let guard = 0;
    while (this.globalXP >= this.xpToNextLevel() && guard++ < 500) {
      this.globalXP -= this.xpToNextLevel();
      this.globalLevel++;
      levels.push(this.globalLevel);
      for (const id of UNLOCK_TABLE[this.globalLevel] ?? []) {
        if (!this.unlocked.has(id)) {
          this.unlocked.add(id);
          unlocked.push(id);
        }
      }
    }
    if (levels.length) {
      this.save();
      this.#emit('levelup', { levels, unlocked });
      if (unlocked.length) this.#emit('unlock', { ids: unlocked, reason: 'level' });
    }
    return { levels, unlocked };
  }

  // -------------------------------------------------------------- статистика
  /**
   * Изменяет статистику и сразу проверяет челленджи и достижения.
   * @returns {{perks: string[], achievements: string[]}} открытое именно сейчас
   */
  bumpStat(key, delta = 1) {
    if (!(key in this.stats)) return { perks: [], achievements: [] };
    if (MAX_STATS.has(key)) this.stats[key] = Math.max(this.stats[key], delta);
    else this.stats[key] += delta;
    return { perks: this.checkChallenges(), achievements: this.checkAchievements() };
  }

  /**
   * Проверяет все достижения и открывает выполненные, начисляя монеты.
   * @returns {string[]} id достижений, открывшихся именно сейчас
   */
  checkAchievements() {
    const newly = [];
    for (const a of ACHIEVEMENTS) {
      if (this.achievements.has(a.id)) continue;
      if ((this.stats[a.stat] ?? 0) < a.need) continue;
      this.achievements.add(a.id);
      newly.push(a.id);
    }
    if (newly.length) {
      const total = newly.reduce((sum, id) => sum + (getAchievement(id)?.reward ?? 0), 0);
      this.money += total;
      this.save();
      this.#emit('achievement', { ids: newly, reward: total });
    }
    return newly;
  }

  // -------------------------------------------------------------- ежедневные задания
  /** Если задание со вчера, сбрасываем прогресс и «открываем» новый день. */
  #refreshDailyIfStale() {
    const today = todayKey();
    if (this.daily.date === today) return;
    this.daily = { date: today, progress: {}, claimed: [] };
  }

  /** Прогресс задания: {current, need, claimed} либо null. */
  dailyProgress(id) {
    this.#refreshDailyIfStale();
    const q = DAILY_QUESTS.find((x) => x.id === id);
    if (!q) return null;
    return {
      current: Math.min(this.daily.progress[q.counter] ?? 0, q.need),
      need: q.need,
      claimed: this.daily.claimed.includes(id),
      reward: q.reward,
      name: q.name,
      icon: q.icon,
      desc: q.desc,
    };
  }

  /** Начисляет прогресс по счётчику всем заданиям дня. */
  bumpDaily(counter, amount = 1) {
    if (!Number.isFinite(amount) || amount <= 0) return;
    this.#refreshDailyIfStale();
    this.daily.progress[counter] = (this.daily.progress[counter] ?? 0) + Math.round(amount);
    this.save();
  }

  /** Прогресс по рекордному принципу (например, лучшая серия убийств). */
  bumpDailyMax(counter, value) {
    if (!Number.isFinite(value) || value <= 0) return;
    this.#refreshDailyIfStale();
    const cur = this.daily.progress[counter] ?? 0;
    if (value > cur) {
      this.daily.progress[counter] = Math.round(value);
      this.save();
    }
  }

  /** Забирает награду за выполненное задание. */
  claimDaily(id) {
    this.#refreshDailyIfStale();
    const q = DAILY_QUESTS.find((x) => x.id === id);
    if (!q) return { ok: false, reason: 'unknown' };
    if (this.daily.claimed.includes(id)) return { ok: false, reason: 'claimed' };
    const current = this.daily.progress[q.counter] ?? 0;
    if (current < q.need) return { ok: false, reason: 'not_done' };
    this.daily.claimed.push(id);
    this.money += q.reward;
    this.save();
    this.#emit('daily', { id, reward: q.reward });
    return { ok: true, reward: q.reward };
  }

  // -------------------------------------------------------------- косметика
  /** Ключ в cosmeticOwned: id может повторяться между типами, поэтому храним `тип:id`. */
  #cosKey(type, id) {
    return `${type}:${id}`;
  }

  /** Доступна ли косметика (куплена или «none»). */
  isCosmeticOwned(type, id) {
    const c = getCosmetic(type, id);
    if (!c) return false;
    return id === 'none' || this.cosmeticOwned.has(this.#cosKey(type, id));
  }

  /** Покупает косметику. Возвращает {ok, reason} | {ok, price}. */
  buyCosmetic(type, id) {
    const c = getCosmetic(type, id);
    if (!c) return { ok: false, reason: 'unknown' };
    if (id === 'none') return { ok: false, reason: 'free' };
    if (this.cosmeticOwned.has(this.#cosKey(type, id))) return { ok: false, reason: 'owned' };
    if (this.money < c.price) return { ok: false, reason: 'money' };
    this.money -= c.price;
    this.cosmeticOwned.add(this.#cosKey(type, id));
    this.save();
    return { ok: true, price: c.price };
  }

  /** Экипирует купленную косметику. Возвращает {ok, reason}. */
  equipCosmetic(type, id) {
    if (!this.isCosmeticOwned(type, id)) return { ok: false, reason: 'not_owned' };
    this.cosmetics[type] = id;
    this.save();
    return { ok: true };
  }

  /** Экипированный набор для применения к танкам игроков. */
  equippedCosmetics() {
    return { ...this.cosmetics };
  }

  /** Проверяет все челленджи и открывает выполненные. */
  checkChallenges() {
    const newly = [];
    for (const perk of PERKS) {
      if (!perk.challenge || this.unlocked.has(perk.id)) continue;
      if ((this.stats[perk.challenge.stat] ?? 0) >= perk.challenge.need) {
        this.unlocked.add(perk.id);
        newly.push(perk.id);
      }
    }
    if (newly.length) {
      this.save();
      this.#emit('unlock', { ids: newly, reason: 'challenge' });
    }
    return newly;
  }

  // -------------------------------------------------------------- валюта и улучшения
  /** Начисляет монеты и сохраняет. */
  addMoney(amount) {
    if (!Number.isFinite(amount) || amount <= 0) return 0;
    this.money += Math.round(amount);
    this.save();
    return this.money;
  }

  /** Пытается потратить монеты. Возвращает true, если хватило. */
  spendMoney(amount) {
    const cost = Math.round(amount);
    if (!Number.isFinite(cost) || cost < 0 || this.money < cost) return false;
    this.money -= cost;
    return true;
  }

  /** Уровень улучшения (0 — не куплено). */
  upgradeLevel(id) {
    return this.upgrades[id] ?? 0;
  }

  /** Цена следующего уровня улучшения или null, если оно максимально. */
  upgradeNextCost(id) {
    const up = UPGRADES.find((u) => u.id === id);
    if (!up) return null;
    const level = this.upgrades[id] ?? 0;
    if (level >= up.maxLevel) return null;
    return upgradeCost(up, level);
  }

  /** Покупает уровень улучшения. Возвращает {ok, reason}. */
  buyUpgrade(id) {
    const up = UPGRADES.find((u) => u.id === id);
    if (!up) return { ok: false, reason: 'unknown' };
    const level = this.upgrades[id] ?? 0;
    if (level >= up.maxLevel) return { ok: false, reason: 'max' };
    const cost = upgradeCost(up, level);
    if (!this.spendMoney(cost)) return { ok: false, reason: 'money' };
    this.upgrades[id] = level + 1;
    this.save();
    return { ok: true, level: level + 1, cost };
  }

  /**
   * Собирает модификаторы от всех купленных улучшений — их перемножает
   * Tank.recompute() с модификаторами перков.
   */
  upgradeMods() {
    const m = {
      maxHPMult: 1,
      speedMult: 1,
      fireRateMult: 1,
      dmgMult: 1,
      bulletSpeedMult: 1,
      damageTakenMult: 1,
      ramMult: 1,
      pickupRadiusMult: 1,
      regenPerMinute: 0,
    };
    for (const up of UPGRADES) {
      const level = this.upgrades[up.id] ?? 0;
      if (level <= 0) continue;
      const value = up.mult(level);
      if (up.modKey === 'regenPerMinute') m[up.modKey] += value;
      else m[up.modKey] *= value;
    }
    return m;
  }

  // -------------------------------------------------------------- перки
  isUnlocked(id) {
    return this.unlocked.has(id);
  }

  /** Перки, доступные для выбора при повышении уровня в партии. */
  availablePerkIds() {
    return PERKS.filter((p) => this.unlocked.has(p.id)).map((p) => p.id);
  }

  /** Прогресс по челленджу перка: {current, need} либо null. */
  challengeProgress(perkId) {
    const perk = PERKS.find((p) => p.id === perkId);
    if (!perk?.challenge) return null;
    return {
      current: Math.min(this.stats[perk.challenge.stat] ?? 0, perk.challenge.need),
      need: perk.challenge.need,
      desc: perk.challenge.desc,
    };
  }

  /** Открывает всё, что положено по текущему уровню. */
  #syncLevelUnlocks() {
    for (const [lvl, ids] of Object.entries(UNLOCK_TABLE)) {
      if (this.globalLevel >= Number(lvl)) for (const id of ids) this.unlocked.add(id);
    }
    this.checkChallenges();
  }

  /** Для галереи: на каком уровне откроется перк. */
  unlockLevelOf(perkId) {
    return unlockLevelOf(perkId);
  }
}

function clampInt(v, min, max, fallback) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.floor(n)));
}

/**
 * Обёртка над localStorage: в приватном режиме или при открытии файла
 * по file:// доступ может бросать исключение. Игра должна работать и без
 * сохранений, просто без прогресса.
 */
export function safeStorage() {
  let available = false;
  try {
    const probe = '__tanchiki_probe__';
    window.localStorage.setItem(probe, '1');
    window.localStorage.removeItem(probe);
    available = true;
  } catch {
    available = false;
  }
  const memory = new Map();
  return {
    available,
    get(key) {
      if (!available) return memory.get(key) ?? null;
      try {
        return window.localStorage.getItem(key);
      } catch {
        return null;
      }
    },
    set(key, value) {
      if (!available) {
        memory.set(key, value);
        return;
      }
      try {
        window.localStorage.setItem(key, value);
      } catch {
        /* переполнение квоты — прогресс просто не сохранится */
      }
    },
  };
}
