// ============================================================================
// weather.js — погода и атмосфера.
//
// WeatherSystem детерминирован по seed: одна и та же партия (один и тот же
// seed карты) показывает один и тот же сценарий погоды. Управляет циклом дня
// и ночи, условиями (ясно/дождь/туман/гроза) и вспышками молний. Чистая
// логика без канваса — отрисовка живёт в render.js.
// ============================================================================

import { clamp, lerp, mulberry32 } from './utils.js';

/** Полный цикл дня и ночи, тиков. */
export const DAY_CYCLE = 10 * 60 * 60; // 10 минут игры
/** Начальная фаза (в долях цикла) — игра начинается днём. */
export const DAY_START_PHASE = 0.18;

/** Доля цикла, соответствующая определённому времени суток. */
export const DAY_PHASES = {
  dawn: 0.0,
  day: 0.25,
  dusk: 0.5,
  night: 0.75,
};

/** Уровень освещения в момент каждой фазы (0 — темно, 1 — ярко). */
export const DAY_LIGHT = {
  dawn: 0.35,
  day: 1.0,
  dusk: 0.4,
  night: 0.18,
};

/** Минимальная и максимальная длительность погодного условия, тиков. */
export const WEATHER_MIN = 20 * 60; // 20 сек
export const WEATHER_MAX = 50 * 60; // 50 сек

/**
 * Погодные условия. rain/fog — целевая интенсивность (0..1), lightning —
 * шанс вспышки за тик в период грозы.
 */
export const WEATHER_TYPES = {
  clear: { id: 'clear', rain: 0, fog: 0, lightning: 0, weight: 3 },
  rain: { id: 'rain', rain: 1, fog: 0.15, lightning: 0, weight: 2 },
  fog: { id: 'fog', rain: 0, fog: 0.9, lightning: 0, weight: 2 },
  storm: { id: 'storm', rain: 1, fog: 0.4, lightning: 0.02, weight: 1 },
};

/** Скорость плавного перехода к целевой интенсивности за тик. */
export const WEATHER_SMOOTH = 0.002;

export class WeatherSystem {
  /**
   * @param {number} seed детерминирует весь сценарий погоды.
   */
  constructor(seed) {
    this.rng = mulberry32((seed ^ 0x9e3779b9) >>> 0);

    /** Время внутри цикла день/ночь, тиков. Игра начинается днём. */
    this.cycleTicks = Math.round(DAY_START_PHASE * DAY_CYCLE);
    /** Имя текущего условия: clear | rain | fog | storm. */
    this.condition = 'clear';
    /** Текущая (сглаженная) интенсивность дождя 0..1. */
    this.rain = 0;
    /** Текущая (сглаженная) плотность тумана 0..1. */
    this.fog = 0;
    /** Оставшиеся тики до смены погоды. */
    this.timer = this.#duration();
    /** Плавная вспышка молнии 0..1 (затухает каждый тик). */
    this.flash = 0;
  }

  /** Уровень освещения 0..1 на текущий момент дня. */
  get light() {
    const phase = this.phase;
    const keys = ['dawn', 'day', 'dusk', 'night', 'dawn'];
    for (let i = 0; i < keys.length - 1; i++) {
      const a = DAY_PHASES[keys[i]];
      const b = DAY_PHASES[keys[i + 1]];
      if (phase >= a && phase < b) {
        const t = (phase - a) / (b - a);
        return lerp(DAY_LIGHT[keys[i]], DAY_LIGHT[keys[i + 1]], t);
      }
    }
    return DAY_LIGHT.night;
  }

  /** Текущая фаза дня в долях цикла 0..1. */
  get phase() {
    return (this.cycleTicks % DAY_CYCLE) / DAY_CYCLE;
  }

  /** Короткое название времени суток для HUD/наград. */
  get timeName() {
    const p = this.phase;
    if (p < 0.125 || p >= 0.875) return 'ночь';
    if (p < 0.25) return 'рассвет';
    if (p < 0.5) return 'день';
    if (p < 0.75) return 'закат';
    return 'вечер';
  }

  /** Ключ времени суток для перевода (i18n). */
  get timeKey() {
    const p = this.phase;
    if (p < 0.125 || p >= 0.875) return 'night';
    if (p < 0.25) return 'dawn';
    if (p < 0.5) return 'day';
    if (p < 0.75) return 'dusk';
    return 'evening';
  }

  #duration() {
    const d = WEATHER_MIN + this.rng() * (WEATHER_MAX - WEATHER_MIN);
    return Math.round(d);
  }

  /** Выбирает следующее условие: никогда не то же самое, что сейчас. */
  #pickNext() {
    const others = Object.keys(WEATHER_TYPES).filter((k) => k !== this.condition);
    const total = others.reduce((s, k) => s + WEATHER_TYPES[k].weight, 0);
    let roll = this.rng() * total;
    for (const k of others) {
      roll -= WEATHER_TYPES[k].weight;
      if (roll <= 0) {
        this.condition = k;
        return;
      }
    }
    this.condition = others[others.length - 1];
  }

  /** Один тик погоды. */
  update() {
    this.cycleTicks++;

    // Смена условия по таймеру.
    if (--this.timer <= 0) {
      this.#pickNext();
      this.timer = this.#duration();
    }

    // Плавно стремимся к целевой интенсивности условия.
    const target = WEATHER_TYPES[this.condition];
    this.rain = clamp(this.rain + (target.rain - this.rain) * WEATHER_SMOOTH, 0, 1);
    this.fog = clamp(this.fog + (target.fog - this.fog) * WEATHER_SMOOTH, 0, 1);

    // Молнии только в грозу.
    this.flash *= 0.85;
    if (this.condition === 'storm' && this.flash < 0.2 && this.rng() < target.lightning) {
      this.flash = 1;
    }
  }

  /**
   * Принудительно ставит условие и его длительность. Используется тестами.
   * @param {string} id
   * @param {number} [ticks]
   */
  setCondition(id, ticks) {
    if (!WEATHER_TYPES[id]) return;
    this.condition = id;
    this.rain = WEATHER_TYPES[id].rain;
    this.fog = WEATHER_TYPES[id].fog;
    this.timer = ticks ?? this.#duration();
  }
}
