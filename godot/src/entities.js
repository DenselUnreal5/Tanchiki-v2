// ============================================================================
// entities.js — снаряды, мины, аптечки, флаги и частицы.
//
// Частицы теперь живут в пуле с жёстким лимитом: в старой версии каждый взрыв
// создавал 30–50 объектов без ограничения, и в замесе на 22 бота массив
// частиц раздувался до десятков тысяч, роняя частоту кадров.
// ============================================================================

import {
  TILE,
  T,
  COLORS,
  BULLET_SPEED,
  BULLET_LIFE,
  BULLET_DMG_MIN,
  BULLET_DMG_MAX,
  TANK_HIT_R,
  EXPLOSIVE_R,
  EXPLOSIVE_SPLASH,
  MINE_DMG,
  MINE_SPLASH_DMG,
  MINE_TRIGGER_R,
  MINE_SPLASH_R,
  PICKUP_RESPAWN,
  AIRSTRIKE_DMG,
  AIRSTRIKE_MAX_HP_FRACTION,
} from './config.js';
import { dist, dist2 } from './utils.js';

// ---------------------------------------------------------------------------
// Частицы
// ---------------------------------------------------------------------------

const MAX_PARTICLES = 1200;

export class ParticleSystem {
  constructor(max = MAX_PARTICLES) {
    this.max = max;
    this.x = new Float32Array(max);
    this.y = new Float32Array(max);
    this.vx = new Float32Array(max);
    this.vy = new Float32Array(max);
    this.size = new Float32Array(max);
    this.life = new Float32Array(max);
    this.maxLife = new Float32Array(max);
    this.color = new Array(max).fill('#fff');
    this.count = 0;
  }

  clear() {
    this.count = 0;
  }

  /** Добавляет частицу. При переполнении пула затирает самую старую. */
  spawn(x, y, color, size, life, rng = Math.random) {
    let i;
    if (this.count < this.max) {
      i = this.count++;
    } else {
      // Ищем самую «дожившую» частицу и переиспользуем её слот.
      let worst = 0;
      let worstLife = Infinity;
      for (let k = 0; k < this.max; k += 7) {
        if (this.life[k] < worstLife) {
          worstLife = this.life[k];
          worst = k;
        }
      }
      i = worst;
    }
    this.x[i] = x;
    this.y[i] = y;
    this.vx[i] = (rng() - 0.5) * 4;
    this.vy[i] = (rng() - 0.5) * 4;
    this.size[i] = size;
    this.life[i] = life;
    this.maxLife[i] = life;
    this.color[i] = color;
  }

  /** Взрыв: пачка частиц из палитры. */
  burst(x, y, colors, amount, sizeMin, sizeMax, lifeMin, lifeMax, rng = Math.random) {
    for (let i = 0; i < amount; i++) {
      this.spawn(
        x,
        y,
        colors[(rng() * colors.length) | 0],
        sizeMin + rng() * (sizeMax - sizeMin),
        lifeMin + rng() * (lifeMax - lifeMin),
        rng,
      );
    }
  }

  update() {
    let w = 0;
    for (let i = 0; i < this.count; i++) {
      const life = this.life[i] - 1;
      if (life <= 0) continue;
      // Компактизация на месте: живые частицы сдвигаются в начало массива.
      this.x[w] = this.x[i] + this.vx[i];
      this.y[w] = this.y[i] + this.vy[i];
      this.vx[w] = this.vx[i] * 0.95;
      this.vy[w] = this.vy[i] * 0.95;
      this.size[w] = this.size[i];
      this.life[w] = life;
      this.maxLife[w] = this.maxLife[i];
      this.color[w] = this.color[i];
      w++;
    }
    this.count = w;
  }
}

// ---------------------------------------------------------------------------
// Пуля
// ---------------------------------------------------------------------------

export class Bullet {
  /**
   * @param {import('./tank.js').Tank} owner
   */
  constructor(x, y, angle, owner, dmgScale = 1) {
    this.x = x;
    this.y = y;
    this.vx = Math.cos(angle) * BULLET_SPEED * owner.mods.bulletSpeedMult;
    this.vy = Math.sin(angle) * BULLET_SPEED * owner.mods.bulletSpeedMult;
    this.owner = owner;
    this.team = owner.team;
    this.alive = true;
    this.life = BULLET_LIFE;
    // Модификаторы владельца фиксируются в момент выстрела: если игрок
    // сменит перк, уже летящая пуля не должна менять свойства на лету.
    this.dmgScale = dmgScale * owner.mods.dmgMult;
    this.pierce = owner.flags.has('piercing') ? 1 : 0;
    this.explosive = owner.flags.has('explosive');
    this.keepBricks = owner.flags.has('keepBricks');
    this.fromPlayer = owner.owner !== null;
    /** Миномётный снаряд: летит по дуге и не задевает стены. */
    this.lobbed = false;
  }

  update(world) {
    if (!this.alive) return;
    this.x += this.vx;
    this.y += this.vy;

    // Миномётный снаряд перелетает стены и кирпичи, взрывается о танк,
    // а при истечении жизни «приземляется» со взрывом.
    if (this.lobbed) {
      if (--this.life <= 0) {
        this.#explode(world, null, BULLET_DMG_MAX * this.dmgScale);
        this.alive = false;
        return;
      }
      if (this.x < 0 || this.x > world.map.width || this.y < 0 || this.y > world.map.height) {
        this.alive = false;
        return;
      }
      this.#hitTanks(world);
      return;
    }

    if (--this.life <= 0) {
      this.alive = false;
      return;
    }
    if (this.x < 0 || this.x > world.map.width || this.y < 0 || this.y > world.map.height) {
      this.alive = false;
      return;
    }
    if (this.#hitTiles(world)) return;
    this.#hitTanks(world);
  }

  /** @returns {boolean} true, если пуля прекратила существование */
  #hitTiles(world) {
    const map = world.map;
    const row = map.rowAt(this.y);
    const col = map.colAt(this.x);
    const tile = map.get(row, col);

    if (tile === T.WALL) {
      if (this.pierce > 0) {
        this.pierce--;
        return !this.#pierceThrough(world);
      }
      this.alive = false;
      world.particles.burst(this.x, this.y, ['#888', '#aaa'], 8, 2, 4, 10, 20, world.rng);
      return true;
    }

    if (tile === T.BRICK) {
      // «Толстая броня»: свои пули не ломают кирпич — плата за −20% урона.
      if (this.keepBricks) {
        this.alive = false;
        world.particles.burst(this.x, this.y, [COLORS.brick, COLORS.brickTop], 8, 2, 4, 10, 20, world.rng);
        return true;
      }
      map.set(row, col, T.EMPTY);
      world.onBrickDestroyed(this.owner);
      world.particles.burst(this.x, this.y, [COLORS.brick, COLORS.brickTop], 8, 2, 4, 10, 20, world.rng);
      if (this.pierce > 0) {
        this.pierce--;
        return !this.#pierceThrough(world);
      }
      this.alive = false;
      return true;
    }

    if (tile === T.TREE) {
      map.set(row, col, T.EMPTY);
      world.particles.burst(this.x, this.y, [COLORS.tree, COLORS.treeDark], 8, 2, 4, 10, 20, world.rng);
      // Дерево пулю не останавливает.
    }
    return false;
  }

  /**
   * Выводит пробивную пулю за пределы стены.
   * В старой версии счётчик пробития просто уменьшался, а пуля оставалась
   * внутри тайла стены и гибла на следующем тике — перк не работал.
   * @returns {boolean} удалось ли выйти на свободное место
   */
  #pierceThrough(world) {
    const map = world.map;
    const len = Math.hypot(this.vx, this.vy) || 1;
    const stepX = (this.vx / len) * 4;
    const stepY = (this.vy / len) * 4;
    // Максимум — две толщины тайла: сквозь более толстую кладку не пробиваем.
    const maxSteps = Math.ceil((TILE * 2) / 4);
    for (let i = 0; i < maxSteps; i++) {
      this.x += stepX;
      this.y += stepY;
      if (this.x < 0 || this.x > world.map.width || this.y < 0 || this.y > world.map.height) break;
      const tile = map.get(map.rowAt(this.y), map.colAt(this.x));
      if (tile !== T.WALL && tile !== T.BRICK) {
        world.particles.burst(this.x, this.y, ['#ffd', '#888'], 6, 2, 3, 8, 14, world.rng);
        return true;
      }
    }
    this.alive = false;
    return false;
  }

  /** @returns {boolean} попал ли снаряд в танк */
  #hitTanks(world) {
    const hitR2 = TANK_HIT_R * TANK_HIT_R;
    for (const tank of world.tanks) {
      if (tank === this.owner || !tank.alive) continue;
      if (!world.areHostile(this.owner, tank)) continue;
      if (dist2(this.x, this.y, tank.x, tank.y) > hitR2) continue;

      const amount =
        (BULLET_DMG_MIN + world.rng() * (BULLET_DMG_MAX - BULLET_DMG_MIN)) * this.dmgScale;
      world.dealDamage(tank, amount, this.owner, 'bullet');

      if (this.explosive) this.#explode(world, tank, amount);

      this.alive = false;
      world.particles.burst(this.x, this.y, ['#ff8833', '#ffee55'], 8, 2, 4, 10, 20, world.rng);
      return true;
    }
    return false;
  }

  #explode(world, directTarget, baseDamage) {
    const r2 = EXPLOSIVE_R * EXPLOSIVE_R;
    for (const other of world.tanks) {
      if (other === directTarget || other === this.owner || !other.alive) continue;
      if (!world.areHostile(this.owner, other)) continue;
      if (dist2(this.x, this.y, other.x, other.y) > r2) continue;
      world.dealDamage(other, baseDamage * EXPLOSIVE_SPLASH, this.owner, 'bullet');
    }
    // Снос кирпича в радиусе одного тайла.
    const map = world.map;
    const row = map.rowAt(this.y);
    const col = map.colAt(this.x);
    for (let dr = -1; dr <= 1; dr++) {
      for (let dc = -1; dc <= 1; dc++) {
        if (map.get(row + dr, col + dc) !== T.BRICK) continue;
        map.set(row + dr, col + dc, T.EMPTY);
        world.onBrickDestroyed(this.owner);
        world.particles.burst(
          (col + dc) * TILE + TILE / 2,
          (row + dr) * TILE + TILE / 2,
          [COLORS.brick, COLORS.brickTop],
          6,
          2,
          4,
          10,
          18,
          world.rng,
        );
      }
    }
    world.particles.burst(this.x, this.y, COLORS.explosion, 12, 2, 4, 10, 18, world.rng);
    world.addShake(8, this.x, this.y);
  }
}

// ---------------------------------------------------------------------------
// Мина
// ---------------------------------------------------------------------------

export class Mine {
  /**
   * @param {import('./tank.js').Tank|null} owner null — «нейтральная» мина
   *   с карты «Царь горы»: она не принадлежит никому и бьёт всех одинаково.
   */
  constructor(x, y, owner, life) {
    this.x = x;
    this.y = y;
    this.owner = owner;
    this.team = owner ? owner.team : 'neutral';
    this.timer = life;
    this.alive = true;
    /** Пока хозяин не отъехал, мина не срабатывает на него самого. */
    this.armed = owner === null;
  }

  update(world) {
    if (--this.timer <= 0) {
      this.alive = false;
      return;
    }
    if (this.owner && !this.armed && dist(this.x, this.y, this.owner.x, this.owner.y) > MINE_TRIGGER_R + 8) {
      this.armed = true;
    }

    const triggerR2 = MINE_TRIGGER_R * MINE_TRIGGER_R;
    for (const tank of world.tanks) {
      if (!tank.alive) continue;
      if (tank === this.owner) continue;
      if (this.owner && !world.areHostile(this.owner, tank)) continue;
      if (dist2(this.x, this.y, tank.x, tank.y) > triggerR2) continue;
      this.#detonate(world, tank);
      return;
    }
  }

  #detonate(world, direct) {
    world.dealDamage(direct, MINE_DMG, this.owner, 'mine');
    const splashR2 = MINE_SPLASH_R * MINE_SPLASH_R;
    for (const tank of world.tanks) {
      if (tank === direct || tank === this.owner || !tank.alive) continue;
      if (this.owner && !world.areHostile(this.owner, tank)) continue;
      if (dist2(this.x, this.y, tank.x, tank.y) > splashR2) continue;
      world.dealDamage(tank, MINE_SPLASH_DMG, this.owner, 'mine');
    }
    world.particles.burst(this.x, this.y, COLORS.explosion, 25, 3, 7, 20, 35, world.rng);
    world.addShake(10, this.x, this.y);
    world.audio.play('explosion');
    this.alive = false;
  }
}

// ---------------------------------------------------------------------------
// Ракета авиаудара («Оборона»)
// ---------------------------------------------------------------------------

/**
 * Самонаводящаяся ракета супер-способности. Слетает с неба над картой и
 * пикирует на назначенную цель, игнорируя стены. Урон — фиксированный
 * AIRSTRIKE_DMG плюс доля от максимального HP цели.
 */
export class StrikeRocket {
  /**
   * @param {import('./tank.js').Tank} target
   * @param {import('./tank.js').Tank} owner атакующий (танк первого игрока)
   * @param {import('./world.js').World} world
   */
  constructor(target, owner, world) {
    this.x = target.x + (world.rng() - 0.5) * 300;
    this.y = -80;
    this.target = target;
    this.owner = owner;
    this.alive = true;
    this.speed = 16;
    this.vx = 0;
    this.vy = 1;
    this.trailTimer = 0;
  }

  update(world) {
    if (!this.alive) return;
    const t = this.target;
    if (!t || !t.alive) {
      this.alive = false;
      world.particles.burst(this.x, this.y, ['#ff9933', '#888888'], 6, 2, 3, 8, 14, world.rng);
      return;
    }
    const dx = t.x - this.x;
    const dy = t.y - this.y;
    const len = Math.hypot(dx, dy);
    if (len < 26) {
      const dmg = AIRSTRIKE_DMG + Math.round(t.maxHP * AIRSTRIKE_MAX_HP_FRACTION);
      world.dealDamage(t, dmg, this.owner, 'airstrike');
      world.particles.burst(this.x, this.y, COLORS.explosion, 16, 2, 5, 12, 24, world.rng);
      world.addShake(8, this.x, this.y);
      world.audio.play('explosion');
      this.alive = false;
      return;
    }
    this.vx = (dx / len) * this.speed;
    this.vy = (dy / len) * this.speed;
    this.x += this.vx;
    this.y += this.vy;
    if (++this.trailTimer % 2 === 0) {
      world.particles.spawn(this.x - this.vx * 2, this.y - this.vy * 2, '#ffcc44', 2.5, 12, world.rng);
    }
  }
}

// ---------------------------------------------------------------------------
// Аптечка
// ---------------------------------------------------------------------------

export class Pickup {
  constructor(x, y, type = 'health') {
    this.x = x;
    this.y = y;
    this.type = type;
    this.active = true;
    this.respawnTimer = 0;
    this.bob = Math.random() * Math.PI * 2;
  }

  consume() {
    this.active = false;
    this.respawnTimer = PICKUP_RESPAWN;
  }
}

// ---------------------------------------------------------------------------
// Выпавший перк («Царь горы»)
// ---------------------------------------------------------------------------

/** Время, которое выпавший перк лежит на земле до исчезновения, тиков. */
export const PERK_DROP_LIFE = 60 * 60; // 60 сек

export class PerkPickup {
  /** @param {string} perkId */
  constructor(x, y, perkId) {
    this.x = x;
    this.y = y;
    this.perkId = perkId;
    this.active = true;
    this.life = PERK_DROP_LIFE;
    this.bob = Math.random() * Math.PI * 2;
  }

  update() {
    if (this.active && --this.life <= 0) this.active = false;
  }
}

// ---------------------------------------------------------------------------
// Power-up оружия
// ---------------------------------------------------------------------------

/** Время, которое оружие лежит на карте до исчезновения, тиков. */
export const WEAPON_PICKUP_LIFE = 60 * 25; // 25 секунд

export class WeaponPickup {
  /** @param {string} weaponId id из weapons.js */
  constructor(x, y, weaponId) {
    this.x = x;
    this.y = y;
    this.weaponId = weaponId;
    this.active = true;
    this.life = WEAPON_PICKUP_LIFE;
    this.bob = Math.random() * Math.PI * 2;
  }

  update() {
    if (this.active && --this.life <= 0) this.active = false;
  }
}

// ---------------------------------------------------------------------------
// Флаг (CTF)
// ---------------------------------------------------------------------------

export class Flag {
  /** @param {'player'|'enemy'} team команда-владелец флага */
  constructor(x, y, team) {
    this.homeX = x;
    this.homeY = y;
    this.x = x;
    this.y = y;
    this.team = team;
    /**
     * Состояние хранится явно, а не выводится из координат: флаг, брошенный
     * ровно на своей базе, иначе одновременно считался бы и «дома»,
     * и «брошенным с таймером возврата».
     * @type {'home'|'carried'|'dropped'}
     */
    this.state = 'home';
    /** @type {import('./tank.js').Tank|null} */
    this.carrier = null;
    /** Тиков до автоматического возврата брошенного флага. */
    this.returnTimer = 0;
  }

  get carried() {
    return this.state === 'carried';
  }

  get atHome() {
    return this.state === 'home';
  }

  pickUp(tank) {
    this.carrier = tank;
    this.state = 'carried';
    this.returnTimer = 0;
  }

  returnHome() {
    this.x = this.homeX;
    this.y = this.homeY;
    this.carrier = null;
    this.state = 'home';
    this.returnTimer = 0;
  }

  /** Бросает флаг. Упавший на свою базу считается сразу возвращённым. */
  drop(x, y, timeout) {
    this.carrier = null;
    if (dist(x, y, this.homeX, this.homeY) < 32) {
      this.returnHome();
      return;
    }
    this.x = x;
    this.y = y;
    this.state = 'dropped';
    this.returnTimer = timeout;
  }
}
