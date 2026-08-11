// ============================================================================
// player.js — управляемый человеком игрок.
//
// Здесь живёт всё, что раньше было глобальными переменными: набор перков,
// внутрипартийный уровень и опыт, счёт, серии убийств, камера. Благодаря
// этому второй игрок в «горячем стуле» полностью независим от первого.
// ============================================================================

import {
  MAX_EQUIPPED_PERKS,
  xpForSessionLevel,
  MAP_W,
  MAP_H,
  PICKUP_R,
  PICKUP_R_MAGNET,
} from './config.js';
import { clamp } from './utils.js';

export class Player {
  /**
   * @param {object} opts
   * @param {number} opts.index 0 или 1
   * @param {string} opts.name
   * @param {string} opts.colorKey ключ палитры TEAM_COLORS
   * @param {import('./input.js').ControlScheme} opts.scheme схема управления
   */
  constructor({ index, name, colorKey, scheme }) {
    this.index = index;
    this.name = name;
    this.colorKey = colorKey;
    this.scheme = scheme;

    /** @type {import('./tank.js').Tank|null} */
    this.tank = null;

    /** Постоянные улучшения профиля (гараж), применяются к танку при спавне. */
    this.upgradeMods = null;

    /** Экипированная косметика: {hull, track, turret} или null. */
    this.cosmetics = null;

    /** Экипированные перки. Танк держит ссылку на этот же массив. */
    this.perkIds = [];

    this.sessionXP = 0;
    this.sessionLevel = 1;
    /** Сколько раз ещё нужно показать выбор перка. */
    this.pendingLevelUps = 0;

    this.score = 0;
    this.kills = 0;
    this.deaths = 0;
    this.captures = 0;
    this.damageDealt = 0;

    /** Метки времени убийств для челленджа «5 убийств за 10 секунд». */
    this.killTicks = [];
    /** Серия убийств без полученного урона. */
    this.cleanStreak = 0;

    this.camera = { x: 0, y: 0 };
    this.viewport = { x: 0, y: 0, w: 0, h: 0 };

    /** Ссылка на карту мира — камере нужны её размеры. Ставится World. */
    this.map = null;

    /** Таймер вспышки при получении урона, тиков. */
    this.damageFlash = 0;
    /** Тряска экрана только для этого игрока. */
    this.shake = 0;
  }

  // ------------------------------------------------------------------ перки
  hasPerk(id) {
    return this.perkIds.includes(id);
  }

  /**
   * Экипирует перк. При переполнении вытесняет самый старый.
   * После изменения обязателен пересчёт характеристик танка.
   */
  equipPerk(id) {
    if (this.hasPerk(id)) return false;
    this.perkIds.push(id);
    while (this.perkIds.length > MAX_EQUIPPED_PERKS) this.perkIds.shift();
    this.tank?.recompute();
    return true;
  }

  unequipPerk(id) {
    const i = this.perkIds.indexOf(id);
    if (i === -1) return false;
    this.perkIds.splice(i, 1);
    this.tank?.recompute();
    return true;
  }

  /** Сбрасывает всё, что относится к одной партии. */
  resetForMatch() {
    this.perkIds.length = 0;
    this.upgradeMods = null;
    this.sessionXP = 0;
    this.sessionLevel = 1;
    this.pendingLevelUps = 0;
    this.score = 0;
    this.kills = 0;
    this.deaths = 0;
    this.captures = 0;
    this.damageDealt = 0;
    this.killTicks.length = 0;
    this.cleanStreak = 0;
    this.damageFlash = 0;
    this.shake = 0;
    this.tank = null;
  }

  // ------------------------------------------------------------------ опыт
  xpToNextLevel() {
    return xpForSessionLevel(this.sessionLevel);
  }

  /** @returns {number} сколько уровней получено */
  addXP(amount) {
    if (amount <= 0) return 0;
    this.sessionXP += amount;
    let gained = 0;
    let guard = 0;
    while (this.sessionXP >= this.xpToNextLevel() && guard++ < 100) {
      this.sessionXP -= this.xpToNextLevel();
      this.sessionLevel++;
      this.pendingLevelUps++;
      gained++;
    }
    return gained;
  }

  // ------------------------------------------------------------------ ввод
  /** Вызывается танком каждый тик. */
  control(tank, world) {
    this.scheme.apply(tank, this, world);
  }

  /** Радиус подбора аптечек с учётом перка «Магнит». */
  get pickupRadius() {
    const mult = this.tank ? this.tank.mods.pickupRadiusMult : 1;
    return mult > 1 ? PICKUP_R_MAGNET : PICKUP_R;
  }

  // ------------------------------------------------------------------ камера
  /**
   * Держит камеру на танке, аккуратно обрабатывая случай, когда карта меньше
   * области просмотра. В старой версии зажим `Math.max(w/2, Math.min(MAP_W - w/2, x))`
   * при широком окне давал min > max и уводил камеру за край карты.
   */
  updateCamera() {
    const { w, h } = this.viewport;
    const mapW = this.map ? this.map.width : MAP_W;
    const mapH = this.map ? this.map.height : MAP_H;
    if (this.tank && this.tank.alive) {
      this.camera.x = this.tank.x;
      this.camera.y = this.tank.y;
    } else if (this.tank) {
      // Танк мёртв — камера остаётся на месте гибели.
      this.camera.x = this.tank.x;
      this.camera.y = this.tank.y;
    }
    this.camera.x = mapW <= w ? mapW / 2 : clamp(this.camera.x, w / 2, mapW - w / 2);
    this.camera.y = mapH <= h ? mapH / 2 : clamp(this.camera.y, h / 2, mapH - h / 2);
  }

  /** Переводит точку экрана в мировые координаты для этого игрока. */
  screenToWorld(screenX, screenY) {
    const { x, y, w, h } = this.viewport;
    return {
      x: screenX - x - w / 2 + this.camera.x,
      y: screenY - y - h / 2 + this.camera.y,
    };
  }

  /** Попадает ли точка экрана в область просмотра этого игрока. */
  containsScreenPoint(screenX, screenY) {
    const { x, y, w, h } = this.viewport;
    return screenX >= x && screenX <= x + w && screenY >= y && screenY <= y + h;
  }

  tick() {
    if (this.damageFlash > 0) this.damageFlash--;
    if (this.shake > 0) this.shake--;
  }
}
