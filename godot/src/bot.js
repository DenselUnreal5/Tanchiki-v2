// ============================================================================
// bot.js — «мозг» бота: конечный автомат + A*.
//
// Сохранены все тактики оригинала: предсказание позиции цели, обнаружение по
// прямой видимости, уклонение от пуль, отход на низком HP, оценка угроз,
// удержание дистанции, сопровождение флагоносца, тактическое патрулирование,
// проверка численного перевеса, стрейф со случайной сменой направления.
//
// Исправлено:
//  * Флаги в CTF. Раньше бот рассматривал только флаги, которые видит по
//    прямой (`if (!hasLineOfSight(...)) continue`). На карте 120x68 это почти
//    никогда не выполняется, поэтому боты фактически не играли в режим.
//    Теперь цель выбирается по расстоянию, а дорогу ищет A*.
//  * Рассинхрон цели и дистанции. Оригинал выбирал цель как
//    `threat || nearest`, а в условие входа в бой подставлял `nearDist` —
//    дистанцию до `nearest`. Если угроза была, а `nearest` отсутствовал,
//    дистанция оставалась Infinity и бой не начинался.
//  * Реакция. Задержка реакции применялась только в состоянии combat,
//    в остальных бот стрелял мгновенно.
//  * Возврат своего сбитого флага — раньше не реализован вовсе.
// ============================================================================

import {
  TILE,
  BOT_SIGHT,
  BOT_COMBAT_RANGE,
  BOT_FIRE_RANGE,
  BOT_KEEP_MIN,
  BOT_KEEP_MAX,
  BOT_DODGE_LOOKAHEAD,
  BOT_PATH_REFRESH,
  BULLET_SPEED,
} from './config.js';
import { dist, dist2, clamp } from './utils.js';
import { findPath } from './pathfinding.js';

const STATE = {
  PATROL: 'patrol',
  COMBAT: 'combat',
  GO_FLAG: 'goFlag',
  RETURN_FLAG: 'returnFlag',
  ESCORT: 'escort',
  RECOVER_FLAG: 'recoverFlag',
};

export class BotBrain {
  constructor({
    accuracy = 0.75,
    reactTime = 20,
    role = 'attacker',
    rng = Math.random,
    fireRange = BOT_FIRE_RANGE,
    keepMin = BOT_KEEP_MIN,
    keepMax = BOT_KEEP_MAX,
    lobbed = false,
    survival = false,
  }) {
    this.baseAccuracy = accuracy;
    this.reactTime = reactTime;
    this.role = role;
    this.rng = rng;
    this.fireRange = fireRange;
    this.keepMin = keepMin;
    this.keepMax = keepMax;
    this.lobbed = lobbed;
    /** Царь горы: приоритет — пережить всех, а не набить фраги. */
    this.survival = survival;
    this.reset();
  }

  reset() {
    this.state = STATE.PATROL;
    this.target = null;
    this.destX = 0;
    this.destY = 0;
    this.stateTimer = 0;
    this.reactTimer = 0;
    this.strafeDir = this.rng() < 0.5 ? 1 : -1;
    this.strafeTimer = 0;
    this.dodgeTimer = 0;
    this.path = [];
    this.pathIdx = 0;
    this.pathTimer = 0;
    this.pathGoalX = 0;
    this.pathGoalY = 0;
    this.stuckTimer = 0;
    this.lastX = 0;
    this.lastY = 0;
    this.escapeCooldown = 0;
    this.escapeDir = this.rng() < 0.5 ? 1 : -1;
    this.dashTimer = 0;
  }

  get accuracy() {
    return clamp(this.baseAccuracy + (this.ownerMods?.accuracyBonus ?? 0), 0.1, 0.98);
  }

  update(tank, world) {
    this.ownerMods = tank.mods;
    this.rng = world.rng;

    if (this.stateTimer > 0) this.stateTimer--;
    if (this.reactTimer > 0) this.reactTimer--;
    if (this.dodgeTimer > 0) this.dodgeTimer--;
    if (this.dashTimer > 0) this.dashTimer--;
    if (--this.strafeTimer <= 0) {
      this.strafeDir *= -1;
      this.strafeTimer = 20 + Math.floor(this.rng() * 40);
    }
    this.#trackStuck(tank);

    // ---- восприятие -------------------------------------------------------
    const visible = findVisibleEnemy(tank, world);
    const threat = findBestThreat(tank, world);
    const target = threat ?? visible.tank;
    const targetDist = target ? dist(tank.x, tank.y, target.x, target.y) : Infinity;
    const hasShot = target ? world.map.hasLineOfSight(tank.x, tank.y, target.x, target.y) : false;

    // ---- уклонение от летящей пули ---------------------------------------
    if (this.dodgeTimer <= 0) {
      const incoming = findIncomingBullet(tank, world, BOT_DODGE_LOOKAHEAD);
      if (incoming) {
        const bulletAngle = Math.atan2(incoming.vy, incoming.vx);
        const side = this.rng() < 0.5 ? 1 : -1;
        const dodgeAngle = bulletAngle + (Math.PI / 2) * side;
        this.#steer(tank, world, tank.x + Math.cos(dodgeAngle) * 60, tank.y + Math.sin(dodgeAngle) * 60);
        this.dodgeTimer = 15;
        // Уклоняясь, всё равно пытаемся отвечать — как в оригинале.
        this.#tryFire(tank, world, target, targetDist, hasShot);
        return;
      }
    }

    // ---- выбор состояния --------------------------------------------------
    this.#decide(tank, world, target, targetDist);

    // ---- исполнение -------------------------------------------------------
    switch (this.state) {
      case STATE.COMBAT:
        this.#doCombat(tank, world, target, targetDist, hasShot);
        break;
      case STATE.RETURN_FLAG:
      case STATE.GO_FLAG:
      case STATE.RECOVER_FLAG:
      case STATE.ESCORT:
      case STATE.PATROL:
      default:
        this.#moveToward(tank, world, this.destX, this.destY);
        this.#tryFire(tank, world, target, targetDist, hasShot);
        break;
    }
  }

  // ------------------------------------------------------------------ решения
  #decide(tank, world, target, targetDist) {
    // 1. Несём флаг — домой, это важнее любого боя.
    if (tank.carryingFlag) {
      const home = world.homeFor(tank.team);
      if (home) {
        this.state = STATE.RETURN_FLAG;
        this.destX = home.x;
        this.destY = home.y;
        return;
      }
    }

    // 2. Есть цель в радиусе боя — вступаем в бой.
    if (target && targetDist < BOT_COMBAT_RANGE) {
      if (this.state !== STATE.COMBAT) {
        this.state = STATE.COMBAT;
        // Задержка реакции: бот «замечает» противника не мгновенно.
        this.reactTimer = this.reactTime;
      }
      this.target = target;
      return;
    }

    // 2.5. «Оборона»: враги идут ломать базу.
    if (world.mode === 'defense' && world.base && tank.isBot) {
      const dBase = dist(tank.x, tank.y, world.base.x, world.base.y);
      if (dBase > 30) {
        this.state = STATE.PATROL;
        this.stateTimer = 60;
        this.destX = world.base.x;
        this.destY = world.base.y;
        return;
      }
    }

    // 3. Режим CTF: роли по флагам.
    if (world.mode === 'ctf' && this.#decideCtf(tank, world)) return;

    // 4. Иначе патруль.
    if (this.state !== STATE.PATROL || this.stateTimer <= 0) {
      this.state = STATE.PATROL;
      this.stateTimer = 60 + Math.floor(this.rng() * 120);
      const point = this.#pickPatrolPoint(tank, world);
      this.destX = point.x;
      this.destY = point.y;
    }
  }

  /** @returns {boolean} взяла ли CTF-логика управление на себя */
  #decideCtf(tank, world) {
    // Свой флаг унесли или бросили — возвращаем (касание возвращает флаг).
    const ownFlag = world.flags.find((f) => f.team === tank.team && !f.atHome);
    if (ownFlag && !ownFlag.carried && (this.role === 'defender' || this.rng() < 0.3)) {
      this.state = STATE.RECOVER_FLAG;
      this.destX = ownFlag.x;
      this.destY = ownFlag.y;
      this.stateTimer = 60;
      return true;
    }

    // Союзник несёт флаг — сопровождаем.
    const ally = world.tanks.find(
      (t) => t.alive && t !== tank && t.team === tank.team && t.carryingFlag,
    );
    if (ally && (this.role === 'defender' || this.rng() < 0.5)) {
      const angle = this.rng() * Math.PI * 2;
      const radius = 60 + this.rng() * 40;
      this.state = STATE.ESCORT;
      this.destX = ally.x + Math.cos(angle) * radius;
      this.destY = ally.y + Math.sin(angle) * radius;
      this.stateTimer = 30;
      return true;
    }

    // Идём за флагом противника. Прямая видимость больше не требуется.
    let best = null;
    let bestDist = Infinity;
    for (const flag of world.flags) {
      if (flag.team === tank.team || flag.carried) continue;
      const d = dist(tank.x, tank.y, flag.x, flag.y);
      if (d < bestDist) {
        bestDist = d;
        best = flag;
      }
    }
    if (best) {
      this.state = STATE.GO_FLAG;
      this.destX = best.x;
      this.destY = best.y;
      this.stateTimer = 90;
      return true;
    }

    // Все чужие флаги уже несут — защищаем свою базу.
    const home = world.homeFor(tank.team);
    if (home) {
      this.state = STATE.PATROL;
      this.destX = home.x + (this.rng() - 0.5) * TILE * 8;
      this.destY = home.y + (this.rng() - 0.5) * TILE * 8;
      this.stateTimer = 60;
      return true;
    }
    return false;
  }

  /** Патрульная точка: своя база, центр карты или база противника. */
  #pickPatrolPoint(tank, world) {
    const map = world.map;
    const mw = map.width;
    const mh = map.height;
    const options = [];
    const own = world.homeFor(tank.team);
    if (own) options.push({ x: own.x, y: own.y, spread: 6 });
    options.push({ x: mw / 2, y: mh / 2, spread: 8 });
    const enemyHome = world.enemyHomeFor(tank.team);
    if (enemyHome) options.push({ x: enemyHome.x, y: enemyHome.y, spread: 8 });
    // В FFA баз нет — добавляем случайные точки по карте.
    if (options.length < 3) {
      options.push({ x: this.rng() * mw, y: this.rng() * mh, spread: 4 });
      options.push({ x: this.rng() * mw, y: this.rng() * mh, spread: 4 });
    }
    const pick = options[Math.floor(this.rng() * options.length)];

    for (let i = 0; i < 12; i++) {
      const x = clamp(pick.x + (this.rng() - 0.5) * TILE * pick.spread, TILE, mw - TILE);
      const y = clamp(pick.y + (this.rng() - 0.5) * TILE * pick.spread, TILE, mh - TILE);
      if (map.isDrivable(map.rowAt(y), map.colAt(x))) return { x, y };
    }
    return { x: clamp(pick.x, TILE, mw - TILE), y: clamp(pick.y, TILE, mh - TILE) };
  }

  // ------------------------------------------------------------------ бой
  #doCombat(tank, world, target, targetDist, hasShot) {
    if (!target || !target.alive) {
      this.state = STATE.PATROL;
      this.stateTimer = 0;
      return;
    }

    const predicted = predictPosition(tank, target);
    const aim = Math.atan2(predicted.y - tank.y, predicted.x - tank.x);
    this.#aim(tank, aim);
    tank.angle = aim;

    // Рывок уже летит — не рулим, чтобы не сбить курс, только стреляем.
    if (tank.dashRange > 0) {
      this.#tryFire(tank, world, target, targetDist, hasShot);
      return;
    }

    const hpRatio = tank.hp / tank.maxHP;
    const enemies = countNearby(world, tank, 400, true);
    const allies = countNearby(world, tank, 400, false);
    const outnumbered = enemies > allies + 1;
    // В режиме выживания уходим раньше и дальше: цена смерти здесь —
    // вылет из партии, а не просто штраф за смерть.
    const retreatHp = this.survival ? 0.55 : 0.3;
    const backDist = this.survival ? 200 : 150;

    if (hpRatio < retreatHp || outnumbered) {
      // Отход: держим цель в прицеле, но отъезжаем назад.
      const back = aim + Math.PI;
      const range = hpRatio < retreatHp ? backDist : 120;
      this.#steer(tank, world, tank.x + Math.cos(back) * range, tank.y + Math.sin(back) * range);
    } else if (this.#tryDash(tank, world, target, targetDist, hasShot)) {
      // Рывок-таран: бот сближается на высокой скорости, дальше разбираемся.
    } else if (targetDist > this.keepMax) {
      this.#moveToward(tank, world, target.x, target.y);
    } else if (targetDist < this.keepMin) {
      this.#steer(tank, world, tank.x - Math.cos(aim) * 120, tank.y - Math.sin(aim) * 120);
    } else {
      const strafe = aim + (Math.PI / 2) * this.strafeDir;
      const range = 60 + this.rng() * 60;
      this.#steer(tank, world, tank.x + Math.cos(strafe) * range, tank.y + Math.sin(strafe) * range);
    }

    this.#tryFire(tank, world, target, targetDist, hasShot);
  }

  /**
   * Рывок-таран: бот бросается на цель с повышенной скоростью, чтобы либо
   * догнать её, либо ударить корпусом. Не используем, если цель слишком далеко,
   * рядом есть стена на пути, или бот в воде/позади.
   * @returns {boolean} true, если рывок начат
   */
  #tryDash(tank, world, target, targetDist, hasShot) {
    if (tank.dashCooldown > 0 || tank.dashRange > 0) return false;
    if (this.dashTimer > 0) return false;
    if (!target || !target.alive || !hasShot) return false;
    // Не тараним из отхода и из воды.
    if (tank.inWater) return false;
    if (targetDist < 60 || targetDist > 320) return false;
    // Не тараним, если рядом уже много своих врагов впереди — может врезаться в толпу.
    if (this.survival && countNearby(world, tank, 120, true) > 0) return false;
    // Проверяем, что на пути рывка нет стены.
    const probe = 34;
    const px = tank.x + Math.cos(tank.angle) * probe;
    const py = tank.y + Math.sin(tank.angle) * probe;
    if (world.map.isBlockedRect(px, py, tank.width, tank.height)) return false;
    tank.dash();
    this.dashTimer = 90 + Math.floor(this.rng() * 60);
    return true;
  }
  #aim(tank, angle) {
    const spread = (1 - this.accuracy) * (this.rng() - 0.5) * 0.4;
    tank.slewTurretTo(angle + spread);
  }

  #tryFire(tank, world, target, targetDist, hasShot) {
    if (!target || !hasShot) return;
    if (targetDist > this.fireRange) return;
    if (this.reactTimer > 0 || !tank.canFire) return;

    const predicted = predictPosition(tank, target);
    const aim = Math.atan2(predicted.y - tank.y, predicted.x - tank.x);
    this.#aim(tank, aim);

    // Стреляем только если башня уже смотрит достаточно близко к цели —
    // иначе бот палит в стену рядом с собой.
    const off = Math.abs(Math.atan2(Math.sin(tank.turretAngle - aim), Math.cos(tank.turretAngle - aim)));
    const tolerance = 0.12 + (1 - this.accuracy) * 0.25;
    if (off > tolerance) return;

    // Миномёт стреляет по дуге — снаряд перелетает укрытия.
    if (this.lobbed) tank.shootLobbed(world);
    else tank.shoot(world);
  }

  // ------------------------------------------------------------------ движение
  #moveToward(tank, world, tx, ty) {
    const goalMoved = dist2(tx, ty, this.pathGoalX, this.pathGoalY) > 90 * 90;
    const needPath =
      this.path.length === 0 ||
      --this.pathTimer <= 0 ||
      goalMoved ||
      this.stuckTimer > 45 ||
      this.stuckTimer < 0;

    if (needPath) {
      this.path = findPath(world.map, tank.x, tank.y, tx, ty);
      this.pathIdx = 0;
      this.pathTimer = BOT_PATH_REFRESH + Math.floor(this.rng() * 40);
      this.pathGoalX = tx;
      this.pathGoalY = ty;
      this.stuckTimer = 0;
    }

    // Упирание. Не ждём 45 тиков: если бот долго не сдвигается к текущей
    // точке, считаем её застрявшей и пересчитываем путь. Дополнительно
    // «запинаем» поперёк — это вытаскивает из угла, куда таран по диагонали
    // загоняет прямоугольный корпус.
    if (this.stuckTimer > 20) {
      this.stuckTimer = -90; // принудительный пересчёт маршрута на следующем кадре
      this.pathTimer = 0;
      if (this.escapeCooldown <= 0) {
        this.escapeCooldown = 12;
        // Перпендикулярно к цели — вытаскивает прямоугольный корпус из угла,
        // куда его загнал диагональный таран в стену.
        const dx = tx - tank.x;
        const dy = ty - tank.y;
        const len = Math.hypot(dx, dy) || 1;
        tank.thrust((-dy / len) * this.escapeDir, (dx / len) * this.escapeDir);
        this.escapeDir *= -1; // чередуем сторону, чтобы не зациклиться в одну
      }
    }
    if (this.escapeCooldown > 0) this.escapeCooldown--;

    // Идём по путевым точкам, перескакивая уже пройденные.
    while (this.pathIdx < this.path.length) {
      const wp = this.path[this.pathIdx];
      if (dist2(tank.x, tank.y, wp.x, wp.y) < 20 * 20) this.pathIdx++;
      else break;
    }

    if (this.pathIdx < this.path.length) {
      const wp = this.path[this.pathIdx];
      this.#steer(tank, world, wp.x, wp.y);
    } else {
      this.#steer(tank, world, tx, ty);
    }
  }

  /**
   * Ускорение в сторону точки с локальным обходом стен.
   *
   * Сначала пробует направление строго на цель; если прямо перед башней —
   * стена или кирпич, выбирает ближайшее свободное направление (по часовой,
   * затем против). Так бот скользит вдоль стен и перестаёт упираться в них
   * при стрейфе/отходе/патруле. Это и есть основное «не врезайся в стену».
   *
   * В режиме выживания («Царь горы») отдельно избегаем воды: карту заливает,
   * и даже полоса воды на пути означает тихую гибель. Вода предпочтительнее
   * стены, но уступает суше.
   */
  #steer(tank, world, tx, ty) {
    const dx = tx - tank.x;
    const dy = ty - tank.y;
    if (dx * dx + dy * dy < 16) return;
    const desired = Math.atan2(dy, dx);
    const map = world.map;
    const probe = 18;
    const directions = [0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0];
    // Первый проход — свободное направление без воды (если выживаем).
    for (const off of directions) {
      const a = desired + off;
      const px = tank.x + Math.cos(a) * probe;
      const py = tank.y + Math.sin(a) * probe;
      if (map.isBlockedRect(px, py, tank.width, tank.height)) continue;
      if (this.survival && map.isWaterAt(px, py)) continue;
      tank.thrust(Math.cos(a), Math.sin(a));
      return;
    }
    // Вокруг всё глухо — не упорствуем, ждём пересчёта пути.
  }

  /** Замечает, что танк упёрся, чтобы перестроить маршрут. */
  #trackStuck(tank) {
    if (dist2(tank.x, tank.y, this.lastX, this.lastY) < 0.35) this.stuckTimer++;
    else this.stuckTimer = 0;
    this.lastX = tank.x;
    this.lastY = tank.y;
  }
}

// ---------------------------------------------------------------------------
// Восприятие
// ---------------------------------------------------------------------------

/** Ближайший враг в пределах видимости и по прямой линии. */
export function findVisibleEnemy(tank, world) {
  let best = null;
  let bestDist = Infinity;
  const sight2 = BOT_SIGHT * BOT_SIGHT;
  for (const other of world.tanks) {
    if (other === tank || !other.alive) continue;
    if (!world.areHostile(tank, other)) continue;
    const d2 = dist2(tank.x, tank.y, other.x, other.y);
    if (d2 > sight2 || d2 >= bestDist) continue;
    if (!world.map.hasLineOfSight(tank.x, tank.y, other.x, other.y)) continue;
    bestDist = d2;
    best = other;
  }
  return { tank: best, dist: best ? Math.sqrt(bestDist) : Infinity };
}

/**
 * Оценка угроз: приоритет тем, кто ближе, слабее по HP и несёт наш флаг.
 * Возвращает танк или null.
 */
export function findBestThreat(tank, world) {
  let best = null;
  let bestScore = -Infinity;
  const sight2 = BOT_SIGHT * BOT_SIGHT;
  for (const other of world.tanks) {
    if (other === tank || !other.alive) continue;
    if (!world.areHostile(tank, other)) continue;
    const d2 = dist2(tank.x, tank.y, other.x, other.y);
    if (d2 > sight2) continue;
    if (!world.map.hasLineOfSight(tank.x, tank.y, other.x, other.y)) continue;

    const d = Math.sqrt(d2);
    let score = (BOT_SIGHT - d) / BOT_SIGHT; // ближе — важнее
    score += (1 - other.hp / other.maxHP) * 0.6; // добить раненого
    if (other.carryingFlag && other.team !== tank.team) score += 1.5; // остановить флагоносца
    if (other.isPlayerControlled) score += 0.25; // человек опаснее бота
    if (score > bestScore) {
      bestScore = score;
      best = other;
    }
  }
  return best;
}

/** Ближайшая пуля, которая по курсу попадёт в танк. */
export function findIncomingBullet(tank, world, radius) {
  let best = null;
  let bestT = Infinity;
  for (const b of world.bullets) {
    if (!b.alive) continue;
    if (!world.areHostile(b.owner, tank)) continue;
    // Время сближения по прямой (проекция на направление пули).
    const dx = tank.x - b.x;
    const dy = tank.y - b.y;
    const speed2 = b.vx * b.vx + b.vy * b.vy;
    if (speed2 === 0) continue;
    const t = (dx * b.vx + dy * b.vy) / speed2;
    if (t < 0 || t > 40) continue; // позади или слишком далеко по времени
    const closestX = b.x + b.vx * t;
    const closestY = b.y + b.vy * t;
    if (dist(closestX, closestY, tank.x, tank.y) > radius) continue;
    if (t < bestT) {
      bestT = t;
      best = b;
    }
  }
  return best;
}

/** Сколько врагов (или союзников) рядом. */
export function countNearby(world, tank, radius, hostile) {
  const r2 = radius * radius;
  let n = 0;
  for (const other of world.tanks) {
    if (other === tank || !other.alive) continue;
    const isHostile = world.areHostile(tank, other);
    if (isHostile !== hostile) continue;
    if (dist2(tank.x, tank.y, other.x, other.y) <= r2) n++;
  }
  return n;
}

/** Куда стрелять с опережением, чтобы попасть в движущуюся цель. */
export function predictPosition(shooter, target) {
  const d = dist(shooter.x, shooter.y, target.x, target.y);
  const flightTicks = d / BULLET_SPEED;
  // Скорость цели за тик уже учитывает трение, поэтому берём её как есть,
  // но ограничиваем горизонт предсказания, чтобы не уводить прицел в стену.
  const horizon = Math.min(flightTicks, 40);
  return {
    x: target.x + target.vx * horizon,
    y: target.y + target.vy * horizon,
  };
}
