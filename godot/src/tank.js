// ============================================================================
// tank.js — танк: физика, стрельба, урон, перки.
//
// КЛЮЧЕВОЕ ОТЛИЧИЕ ОТ СТАРОЙ ВЕРСИИ.
// Раньше состояние игрока жило в глобальных переменных (shieldHP,
// regenTimer, mineCooldown, turboTimer, cleanKillStreak, playerPerks...).
// Второй игрок в «горячем стуле» создавался с isPlayer = true и начинал
// пользоваться теми же глобалами: перезарядки тикали дважды за кадр, попадание
// по P2 засвечивало экран P1, выстрелы P2 записывались в статистику P1,
// а убийство P2 всегда начисляло очки P1 — даже если стрелял бот.
//
// Здесь всё это — поля самого танка либо его владельца (Player).
// Число живых игроков перестаёт что-либо ломать.
// ============================================================================

import {
  TANK_W,
  TANK_H,
  TANK_BODY_R,
  FRICTION,
  ACCEL_FACTOR,
  WATER_DRAG,
  WATER_DMG,
  WATER_DMG_INTERVAL,
  RAM_MIN_SPEED,
  RAM_DMG_PER_SPEED,
  RAM_PUSH,
  DASH_DISTANCE,
  DASH_SPEED_MULT,
  DASH_COOLDOWN,
  SPAWN_PROTECT,
  SHIELD_HP,
  SHIELD_COOLDOWN,
  MINE_COOLDOWN,
  MINE_MAX,
  MINE_LIFE,
  KAMIKAZE_DMG,
  KAMIKAZE_R,
  COLORS,
  T,
  TICK_HZ,
} from './config.js';
import { computeModifiers, computeFlags, computeBotModifiers, computeBotFlags } from './perks.js';
import { dist, dist2, clamp, rotateToward } from './utils.js';
import { Bullet, Mine } from './entities.js';
import { getWeapon } from './weapons.js';

/** Урон, который спавн-защита НЕ блокирует. */
const ENVIRONMENTAL = new Set(['water']);

/**
 * Накладывает постоянные улучшения гаража на модификаторы.
 * regenPerMinute складывается (это «скорость», а не множитель),
 * остальное перемножается.
 */
function applyUpgradeMods(mods, upgradeMods) {
  const out = { ...mods };
  for (const key of Object.keys(upgradeMods)) {
    const value = upgradeMods[key];
    if (value === 0) continue;
    if (key === 'regenPerMinute') out.regenPerMinute += value;
    else out[key] *= value;
  }
  return out;
}

/** Скорость поворота башни у ботов, рад/тик. У игрока башня следует за мышью 1:1. */
const BOT_TURRET_SLEW = 0.12;
/** Скорость доворота корпуса, доля от разницы углов за тик. */
const BODY_TURN_RATE = 0.15;

let nextTankId = 1;

export class Tank {
  /**
   * @param {object} opts
   * @param {number} opts.x
   * @param {number} opts.y
   * @param {string} opts.team  команда; враждебность считается по несовпадению
   * @param {string} opts.name  отображаемое имя
   * @param {import('./player.js').Player|null} opts.owner  владелец-человек или null у бота
   * @param {number} opts.maxHP
   * @param {number} opts.speed  предельная скорость, px/тик
   * @param {number} opts.fireRate  тиков между выстрелами
   * @param {string} opts.colorKey  ключ палитры из TEAM_COLORS
   */
  constructor({ x, y, team, name, owner = null, maxHP, speed, fireRate, colorKey = 'enemy', upgradeMods = null, cosmetics = null, dmgScale = 1 }) {
    this.id = nextTankId++;
    this.x = x;
    this.y = y;
    this.vx = 0;
    this.vy = 0;
    this.spawnX = x;
    this.spawnY = y;

    this.team = team;
    this.name = name;
    this.owner = owner;
    this.isBot = owner === null;
    this.colorKey = colorKey;

    this.width = TANK_W;
    this.height = TANK_H;

    // Базовые характеристики — от них считаются итоговые с учётом перков.
    this.baseMaxHP = maxHP;
    this.baseSpeed = speed;
    this.baseFireRate = fireRate;

    /** Постоянные улучшения профиля (гараж). null у ботов. */
    this.upgradeMods = upgradeMods;

    /** Косметика {hull, track, turret} — null у ботов. */
    this.cosmetics = cosmetics;

    /** Множитель урона танка (типы врагов). У игроков всегда 1. */
    this.dmgScale = dmgScale;

    /** Тип врага (из enemyTypes.js). null у игроков. */
    this.enemyType = null;

    this.angle = owner ? -Math.PI / 2 : Math.PI / 2;
    this.bodyAngle = this.angle;
    this.turretAngle = this.angle;

    /** Перки танка. У игрока это ссылка на массив владельца. */
    this.perkIds = owner ? owner.perkIds : [];
    this.mods = computeModifiers([]);
    this.flags = new Set();

    this.maxHP = maxHP;
    this.hp = maxHP;
    this.speed = speed;
    this.fireRate = fireRate;

    this.alive = true;
    this.fireCooldown = 0;
    this.spawnProtect = SPAWN_PROTECT;
    this.respawnTimer = 0;

    // Состояние перков — теперь у каждого танка своё.
    this.shieldHP = 0;
    this.shieldCooldown = 0;
    this.regenAccum = 0;
    this.mineCooldown = 0;
    this.mines = 0;
    this.turboTimer = 0;
    this.shadowTimer = 0;
    this.dashRange = 0;

    this.inWater = false;
    this.waterTimer = 0;

    /** Временное оружие (power-up): id из weapons.js или null. */
    this.weapon = null;
    /** Оставшиеся тики действия оружия. */
    this.weaponTimer = 0;

    /** @type {import('./entities.js').Flag|null} */
    this.flag = null;
    /** @type {import('./bot.js').BotBrain|null} */
    this.brain = null;

    // Статистика за матч (для табло).
    this.kills = 0;
    this.deaths = 0;
    this.damageDealt = 0;

    /** Кто последним нанёс урон — для корректного начисления фрага. */
    this.lastAttacker = null;
    this.lastAttackerTick = -Infinity;

    this.recompute();
    this.hp = this.maxHP;
  }

  get isPlayerControlled() {
    return this.owner !== null;
  }

  get carryingFlag() {
    return this.flag !== null;
  }

  /**
   * Пересчитывает характеристики из базовых значений и текущих перков.
   * Вызывается при любом изменении набора перков. Именно это устраняет
   * «залипший» бонус HP от «Тяжёлой брони» при снятии перка.
   */
  recompute() {
    const hpRatio = this.maxHP > 0 ? this.hp / this.maxHP : 1;
    if (this.isBot) {
      this.mods = computeBotModifiers(this.perkIds);
      this.flags = computeBotFlags(this.perkIds);
    } else {
      this.mods = computeModifiers(this.perkIds);
      this.flags = computeFlags(this.perkIds);
    }
    // Постоянные улучшения из гаража перемножаются с бонусами перков.
    if (this.upgradeMods) this.mods = applyUpgradeMods(this.mods, this.upgradeMods);
    this.maxHP = Math.max(1, Math.round(this.baseMaxHP * this.mods.maxHPMult));
    this.speed = this.baseSpeed * this.mods.speedMult;
    this.fireRate = Math.max(4, Math.round(this.baseFireRate * this.mods.fireRateMult));
    // Сохраняем долю здоровья: рост максимума лечит пропорционально,
    // снижение не убивает мгновенно.
    this.hp = clamp(Math.round(this.maxHP * hpRatio), 1, this.maxHP);
    if (!this.flags.has('shield')) this.shieldHP = 0;
  }

  /** Применяет ускорение по нормализованному направлению. */
  thrust(dx, dy) {
    if (dx === 0 && dy === 0) return;
    const len = Math.hypot(dx, dy);
    dx /= len;
    dy /= len;
    let mult = 1;
    if (this.turboTimer > 0) mult *= 1.5;
    const accel = this.speed * ACCEL_FACTOR * mult;
    this.vx += dx * accel;
    this.vy += dy * accel;
    this.angle = Math.atan2(dy, dx);
  }

  aimAt(x, y) {
    this.turretAngle = Math.atan2(y - this.y, x - this.x);
  }

  /** Плавный доворот башни — используется ботами. */
  slewTurretTo(target) {
    this.turretAngle = rotateToward(this.turretAngle, target, BOT_TURRET_SLEW);
  }

  get canFire() {
    return this.alive && this.fireCooldown <= 0;
  }

  // ------------------------------------------------------------------ шаг
  update(world) {
    if (!this.alive) return;

    if (this.spawnProtect > 0) this.spawnProtect--;
    if (this.fireCooldown > 0) this.fireCooldown--;
    if (this.mineCooldown > 0) this.mineCooldown--;
    if (this.shieldCooldown > 0) this.shieldCooldown--;
    if (this.turboTimer > 0) this.turboTimer--;
    if (this.shadowTimer > 0) this.shadowTimer--;
    if (this.dashCooldown > 0) this.dashCooldown--;
    if (this.weaponTimer > 0) {
      if (--this.weaponTimer <= 0) this.weapon = null;
    }

    this.#updateRegen();
    this.#updateShield(world);

    // Управление: человек через владельца, бот через свой «мозг».
    if (this.owner) this.owner.control(this, world);
    else if (this.brain) this.brain.update(this, world);

    // Рывок-таран: пока не проехали DASH_DISTANCE, скорость ×DASH_SPEED_MULT.
    if (this.dashRange > 0) {
      const boost = this.speed * DASH_SPEED_MULT;
      this.vx = Math.cos(this.angle) * boost;
      this.vy = Math.sin(this.angle) * boost;
    }

    const beforeMoveX = this.x;
    const beforeMoveY = this.y;
    this.#move(world);
    if (this.dashRange > 0) {
      this.dashRange -= Math.hypot(this.x - beforeMoveX, this.y - beforeMoveY);
      if (this.dashRange <= 0) this.dashRange = 0;
    }
    this.#checkWater(world);
    this.#tryRam(world);

    this.vx *= FRICTION;
    this.vy *= FRICTION;

    this.bodyAngle = rotateToward(
      this.bodyAngle,
      this.angle,
      Math.abs(this.angle - this.bodyAngle) * BODY_TURN_RATE + 0.02,
    );
  }

  #updateRegen() {
    const perMinute = this.mods.regenPerMinute;
    if (perMinute <= 0 || this.hp >= this.maxHP) return;
    // Накопитель вместо счётчика тиков: корректно работает при любом
    // значении регенерации, в том числе дробном.
    this.regenAccum += perMinute / (TICK_HZ * 60);
    if (this.regenAccum >= 1) {
      const heal = Math.floor(this.regenAccum);
      this.regenAccum -= heal;
      this.hp = Math.min(this.maxHP, this.hp + heal);
    }
  }

  #updateShield(world) {
    if (!this.flags.has('shield')) return;
    if (this.shieldHP <= 0 && this.shieldCooldown <= 0) {
      this.shieldHP = SHIELD_HP;
      this.shieldCooldown = SHIELD_COOLDOWN;
      world.particles.burst(this.x, this.y, [COLORS.shield, '#88ddff'], 10, 2, 4, 12, 20, world.rng);
    }
  }

  /** Раздельное разрешение по осям — позволяет скользить вдоль стен. */
  #move(world) {
    const map = world.map;
    const nx = this.x + this.vx;
    const ny = this.y + this.vy;

    if (!map.isBlockedRect(nx, this.y, this.width, this.height)) {
      this.x = nx;
    } else {
      this.vx = 0;
    }
    if (!map.isBlockedRect(this.x, ny, this.width, this.height)) {
      this.y = ny;
    } else {
      this.vy = 0;
    }

    this.#crushTrees(world);

    this.x = clamp(this.x, this.width / 2 + 2, world.map.width - this.width / 2 - 2);
    this.y = clamp(this.y, this.height / 2 + 2, world.map.height - this.height / 2 - 2);
  }

  #crushTrees(world) {
    const map = world.map;
    const hw = this.width / 2;
    const hh = this.height / 2;
    const keep = this.flags.has('forest');
    let count = 0;
    for (let i = 0; i < 5; i++) {
      const px = i === 4 ? this.x : this.x + (i % 2 === 0 ? -hw : hw);
      const py = i === 4 ? this.y : this.y + (i < 2 ? -hh : hh);
      const row = map.rowAt(py);
      const col = map.colAt(px);
      if (map.get(row, col) !== T.TREE) continue;
      count++;
      if (keep) continue;
      map.set(row, col, T.EMPTY);
      world.particles.burst(
        col * 32 + 16,
        row * 32 + 16,
        [COLORS.tree, COLORS.treeDark],
        10,
        2,
        5,
        15,
        25,
        world.rng,
      );
    }
    if (count > 0 && this.owner) world.onTreesDriven(this, count);
  }

  #checkWater(world) {
    const inWater = world.map.isWaterAt(this.x, this.y);
    if (!inWater) {
      this.inWater = false;
      this.waterTimer = 0;
      return;
    }
    if (!this.inWater) {
      this.inWater = true;
      if (this.owner) world.onWaterEntered(this);
    }
    this.vx *= WATER_DRAG;
    this.vy *= WATER_DRAG;

    if (this.flags.has('amphibious')) {
      this.waterTimer = 0;
    } else if (++this.waterTimer >= WATER_DMG_INTERVAL) {
      this.waterTimer = 0;
      world.dealDamage(this, WATER_DMG, null, 'water');
      world.particles.burst(this.x, this.y, [COLORS.waterLight, '#88aaff'], 5, 2, 4, 12, 18, world.rng);
      if (this.owner) world.audio.play('water');
    }
    if (world.tick % 8 === 0) {
      world.particles.burst(this.x, this.y, [COLORS.waterLight], 1, 2, 2, 10, 10, world.rng);
    }
  }

  #tryRam(world) {
    const speed = Math.hypot(this.vx, this.vy);
    if (speed <= RAM_MIN_SPEED) return;
    const r2 = TANK_BODY_R * TANK_BODY_R;
    for (const other of world.tanks) {
      if (other === this || !other.alive) continue;
      if (!world.areHostile(this, other)) continue;
      if (dist2(this.x, this.y, other.x, other.y) > r2) continue;
      const damage = Math.floor(speed * RAM_DMG_PER_SPEED * this.mods.ramMult);
      if (damage <= 0) continue;
      // Начисление фрага и статистику тарана делает World по source === 'ram'.
      world.dealDamage(other, damage, this, 'ram');
      const pushAngle = Math.atan2(other.y - this.y, other.x - this.x);
      other.vx += Math.cos(pushAngle) * RAM_PUSH;
      other.vy += Math.sin(pushAngle) * RAM_PUSH;
    }
  }

  // ------------------------------------------------------------------ выстрел
  shoot(world) {
    if (!this.canFire) return false;
    this.fireCooldown = this.fireRate;

    const muzzleX = this.x + Math.cos(this.turretAngle) * 18;
    const muzzleY = this.y + Math.sin(this.turretAngle) * 18;
    const scale = this.dmgScale;

    // Временное оружие переопределяет выстрел.
    const weapon = this.weapon ? getWeapon(this.weapon) : null;
    if (weapon) {
      this.fireCooldown = Math.max(4, Math.round(this.fireRate * weapon.cooldownMult));
      const spreadStep = weapon.bullets > 1 ? weapon.spread : 0;
      for (let i = 0; i < weapon.bullets; i++) {
        const offset = weapon.bullets > 1 ? (i - (weapon.bullets - 1) / 2) * weapon.spread * 2 / (weapon.bullets - 1) : 0;
        const b = new Bullet(muzzleX, muzzleY, this.turretAngle + offset, this, weapon.dmgScale * scale);
        if (weapon.explosive) b.explosive = true;
        world.bullets.push(b);
      }
      world.particles.burst(muzzleX, muzzleY, [weapon.color, '#ffffff'], 6, 2, 4, 10, 12, world.rng);
      world.audio.play('shoot');
      return true;
    }

    if (this.flags.has('fanShot')) {
      for (let i = -1; i <= 1; i++) {
        world.bullets.push(new Bullet(muzzleX, muzzleY, this.turretAngle + i * 0.15, this, 0.45 * scale));
      }
    } else if (this.flags.has('doubleShot')) {
      const perp = this.turretAngle + Math.PI / 2;
      const ox = Math.cos(perp) * 6;
      const oy = Math.sin(perp) * 6;
      world.bullets.push(new Bullet(muzzleX + ox, muzzleY + oy, this.turretAngle, this, 1 * scale));
      world.bullets.push(new Bullet(muzzleX - ox, muzzleY - oy, this.turretAngle, this, 1 * scale));
    } else {
      world.bullets.push(new Bullet(muzzleX, muzzleY, this.turretAngle, this, 1 * scale));
    }

    world.particles.burst(muzzleX, muzzleY, ['#ffee55', '#ffffaa'], 5, 2, 4, 8, 8, world.rng);
    world.audio.play('shoot');
    return true;
  }

  /** Выстрел миномёта: снаряд летит по дуге над стенами. */
  shootLobbed(world) {
    if (!this.canFire) return false;
    this.fireCooldown = this.fireRate;

    const muzzleX = this.x + Math.cos(this.turretAngle) * 18;
    const muzzleY = this.y + Math.sin(this.turretAngle) * 18;
    const b = new Bullet(muzzleX, muzzleY, this.turretAngle, this, 1 * this.dmgScale);
    b.lobbed = true;
    b.explosive = true;
    world.bullets.push(b);

    world.particles.burst(muzzleX, muzzleY, ['#ff9933', '#ffcc66'], 6, 2, 4, 10, 12, world.rng);
    world.audio.play('shoot');
    return true;
  }

  /** Ставит мину. Лимит мин отсчитывается для каждого танка отдельно. */
  placeMine(world) {
    if (!this.flags.has('mines') || this.mineCooldown > 0) return false;
    const own = world.mines.reduce((n, m) => n + (m.owner === this ? 1 : 0), 0);
    if (own >= MINE_MAX) return false;
    world.mines.push(new Mine(this.x, this.y, this, MINE_LIFE));
    this.mineCooldown = MINE_COOLDOWN;
    return true;
  }

  /**
   * Рывок-таран: устремляет танк вперёд с повышенной скоростью на
   * DASH_DISTANCE. Скорость в момент активации задаётся мгновенно, дальше
   * каждый тик поддерживается в update(). Кулдаун не даёт спамить.
   * @returns {boolean} true, если рывок начался
   */
  dash() {
    if (!this.alive || this.dashCooldown > 0 || this.dashRange > 0) return false;
    this.dashCooldown = DASH_COOLDOWN;
    this.dashRange = DASH_DISTANCE;
    const boost = this.speed * DASH_SPEED_MULT;
    this.vx = Math.cos(this.angle) * boost;
    this.vy = Math.sin(this.angle) * boost;
    return true;
  }

  // ------------------------------------------------------------------ урон
  /**
   * Считает и применяет урон. Всё побочное (табло, статистика, тряска)
   * делает World — здесь только математика брони.
   * @returns {{applied:number, killed:boolean, evaded:boolean, reflected:number}}
   */
  takeDamage(world, amount, attacker, source) {
    const result = { applied: 0, killed: false, evaded: false, reflected: 0 };
    if (!this.alive) return result;
    if (this.spawnProtect > 0 && !ENVIRONMENTAL.has(source)) return result;

    if (this.mods.evasionChance > 0 && world.rng() < this.mods.evasionChance) {
      result.evaded = true;
      world.particles.burst(this.x, this.y, ['#00ffff', '#aaffff'], 5, 2, 3, 10, 14, world.rng);
      return result;
    }

    let dmg = amount * this.mods.damageTakenMult;

    if (this.shieldHP > 0) {
      const absorbed = Math.min(this.shieldHP, dmg);
      this.shieldHP -= absorbed;
      dmg -= absorbed;
      world.particles.burst(this.x, this.y, [COLORS.shield], 5, 2, 4, 12, 12, world.rng);
      if (dmg <= 0) return result;
    }

    if (this.mods.reflectFraction > 0 && attacker && attacker.alive && source !== 'reflect') {
      result.reflected = dmg * this.mods.reflectFraction;
    }

    this.hp -= dmg;
    result.applied = dmg;

    if (this.hp <= 0) {
      this.hp = 0;
      result.killed = true;
    }
    return result;
  }

  /** Вызывается World после смерти. Возвращает список побочных эффектов. */
  onDeath(world, killer) {
    this.alive = false;
    this.deaths++;
    this.vx = 0;
    this.vy = 0;
    this.shieldHP = 0;
    this.turboTimer = 0;
    this.shadowTimer = 0;
    this.dashRange = 0;

    world.particles.burst(this.x, this.y, COLORS.explosion, 30, 3, 8, 20, 40, world.rng);
    world.audio.play('explosion');
    world.addShake(6, this.x, this.y);

    if (this.flags.has('kamikaze')) {
      const r2 = KAMIKAZE_R * KAMIKAZE_R;
      for (const other of world.tanks) {
        if (other === this || !other.alive) continue;
        if (!world.areHostile(this, other)) continue;
        if (dist2(this.x, this.y, other.x, other.y) > r2) continue;
        world.dealDamage(other, KAMIKAZE_DMG, this, 'kamikaze');
      }
      world.particles.burst(this.x, this.y, COLORS.explosion, 40, 4, 8, 25, 45, world.rng);
      world.addShake(15, this.x, this.y);
    }
  }

  respawn(x, y) {
    this.x = x;
    this.y = y;
    this.vx = 0;
    this.vy = 0;
    this.alive = true;
    this.hp = this.maxHP;
    this.spawnProtect = SPAWN_PROTECT * 2;
    this.fireCooldown = 0;
    this.respawnTimer = 0;
    this.shieldHP = 0;
    this.shieldCooldown = 0;
    this.regenAccum = 0;
    this.waterTimer = 0;
    this.inWater = false;
    this.turboTimer = 0;
    this.shadowTimer = 0;
    this.dashRange = 0;
    this.dashCooldown = 0;
    this.weapon = null;
    this.weaponTimer = 0;
    this.lastAttacker = null;
    this.flag = null;
    if (this.brain) this.brain.reset();
  }

  /** Мягкое расталкивание, чтобы танки не слипались в одну точку. */
  separateFrom(other) {
    const d = dist(this.x, this.y, other.x, other.y);
    const minDist = TANK_BODY_R * 0.9;
    if (d >= minDist || d === 0) return;
    const push = ((minDist - d) / minDist) * 0.35;
    const nx = (this.x - other.x) / d;
    const ny = (this.y - other.y) / d;
    this.vx += nx * push;
    this.vy += ny * push;
    other.vx -= nx * push;
    other.vy -= ny * push;
  }
}
