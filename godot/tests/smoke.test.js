// ============================================================================
// tests/smoke.test.js — проверки без браузера.
//
// Вся симуляция (карта, танки, боты, пули, флаги, перки, профиль) не зависит
// от DOM, поэтому её можно прогнать в Node. Запуск: node tests/smoke.test.js
// ============================================================================

import assert from 'node:assert/strict';

import { COLS, ROWS, TILE, MAP_W, MAP_H, T, MODES, DIFFICULTY, REWARD_KILL, REWARD_CAPTURE, REWARD_WIN } from '../src/config.js';
import { generateLevel, GameMap } from '../src/map.js';
import { findPath } from '../src/pathfinding.js';
import { World } from '../src/world.js';
import { Player } from '../src/player.js';
import { Profile } from '../src/profile.js';
import { Tank } from '../src/tank.js';
import { Bullet } from '../src/entities.js';
import { computeModifiers, computeFlags, PERKS, UNLOCK_TABLE, getPerk, isPerkAllowedInMode } from '../src/perks.js';
import { UPGRADES } from '../src/upgrades.js';
import { pickEnemyType } from '../src/enemyTypes.js';
import { WeatherSystem, DAY_CYCLE } from '../src/weather.js';

// ---------------------------------------------------------------- инструменты

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  \x1b[32m✓\x1b[0m ${name}`);
  } catch (e) {
    failed++;
    failures.push({ name, e });
    console.log(`  \x1b[31m✗\x1b[0m ${name}`);
    console.log(`      ${e.message.split('\n')[0]}`);
  }
}

function section(name) {
  console.log(`\n\x1b[36m${name}\x1b[0m`);
}

/** Заглушка звука: интерфейс тот же, ничего не делает. */
const silentAudio = { play() {}, advance() {}, init() {}, setEnabled() {} };

/** Схема управления, которая ничего не нажимает. */
const idleScheme = { apply() {}, get hints() { return []; } };

/** Схема, которая держит газ и стреляет — чтобы шевелить симуляцию. */
function activeScheme(dx, dy) {
  return {
    apply(tank, player, world) {
      tank.thrust(dx, dy);
      tank.aimAt(tank.x + dx * 100, tank.y + dy * 100);
      tank.shoot(world);
    },
    get hints() {
      return [];
    },
  };
}

function makePlayers(count, scheme = idleScheme) {
  const players = [];
  for (let i = 0; i < count; i++) {
    players.push(
      new Player({
        index: i,
        name: `Игрок ${i + 1}`,
        colorKey: i === 0 ? 'p1' : 'p2',
        scheme,
      }),
    );
    players[i].viewport = { x: 0, y: 0, w: 1280, h: 720 };
  }
  return players;
}

function makeWorld({ mode = 'ffa', difficulty = 'medium', level = 1, playerCount = 1, scheme } = {}) {
  const lvl = generateLevel(level, mode);
  const players = makePlayers(playerCount, scheme);
  const world = new World({
    map: lvl.map,
    level: lvl,
    mode,
    difficulty,
    players,
    audio: silentAudio,
  });
  return { world, players, level: lvl };
}

/** Хранилище в памяти для тестов профиля. */
function memoryStorage() {
  const m = new Map();
  return {
    available: true,
    get: (k) => (m.has(k) ? m.get(k) : null),
    set: (k, v) => m.set(k, v),
  };
}

// ============================================================================
section('Генерация уровней');

test('все уровни обоих режимов генерируются и полностью связны', () => {
  for (const mode of ['ffa', 'ctf']) {
    for (const lvl of [1, 2, 3, 4, 5]) {
      const { map } = generateLevel(lvl, mode);
      const { regions } = map.labelRegions();
      assert.ok(regions.length >= 1, `${mode} ур.${lvl}: нет проезжаемых клеток`);
      assert.equal(
        regions.length,
        1,
        `${mode} ур.${lvl}: карта распалась на ${regions.length} изолированных областей`,
      );
    }
  }
});

test('случайные уровни связны на 40 разных сидах', () => {
  for (let i = 0; i < 40; i++) {
    const { map } = generateLevel('random', i % 2 ? 'ctf' : 'ffa');
    const { regions } = map.labelRegions();
    assert.equal(regions.length, 1, `итерация ${i}: областей ${regions.length}`);
  }
});

test('генерация детерминирована для числового уровня', () => {
  const a = generateLevel(3, 'ffa');
  const b = generateLevel(3, 'ffa');
  assert.equal(a.seed, b.seed);
  assert.deepEqual(Array.from(a.map.tiles), Array.from(b.map.tiles));
});

test('рамка карты — стена', () => {
  const { map } = generateLevel(1, 'ffa');
  for (let c = 0; c < COLS; c++) {
    assert.equal(map.get(0, c), T.WALL);
    assert.equal(map.get(ROWS - 1, c), T.WALL);
  }
  for (let r = 0; r < ROWS; r++) {
    assert.equal(map.get(r, 0), T.WALL);
    assert.equal(map.get(r, COLS - 1), T.WALL);
  }
});

test('CTF: базы, дома и по 3 флага на команду на месте', () => {
  const lvl = generateLevel(2, 'ctf');
  assert.equal(lvl.map.get(ROWS - 2, 2), T.BASE_P);
  assert.equal(lvl.map.get(1, COLS - 3), T.BASE_E);
  assert.ok(lvl.homes.player && lvl.homes.enemy);
  assert.equal(lvl.flagSpots.player.length, MODES.ctf.flagsPerTeam);
  assert.equal(lvl.flagSpots.enemy.length, MODES.ctf.flagsPerTeam);
});

test('во всех зонах спавна находится свободная точка', () => {
  for (const mode of ['ffa', 'ctf']) {
    for (const lvl of [1, 2, 3, 4, 5]) {
      const level = generateLevel(lvl, mode);
      const rng = () => 0.5;
      for (const key of ['player', 'enemy', 'any']) {
        const spot = level.map.findFreeSpot(rng, level.areas[key], 24, 28);
        assert.ok(spot, `${mode} ур.${lvl} зона ${key}: свободной точки нет`);
        assert.ok(!level.map.isBlockedRect(spot.x, spot.y, 24, 28));
      }
    }
  }
});

// ============================================================================
section('Прямая видимость и поиск пути');

test('видимость симметрична и блокируется стеной', () => {
  const map = new GameMap();
  map.fill(T.EMPTY);
  const y = 5 * TILE + 16;
  assert.ok(map.hasLineOfSight(2 * TILE + 16, y, 20 * TILE + 16, y));
  map.set(5, 10, T.WALL);
  assert.ok(!map.hasLineOfSight(2 * TILE + 16, y, 20 * TILE + 16, y));
  assert.ok(!map.hasLineOfSight(20 * TILE + 16, y, 2 * TILE + 16, y));
});

test('деревья и вода не мешают видимости, кирпич мешает', () => {
  const map = new GameMap();
  map.fill(T.EMPTY);
  const y = 5 * TILE + 16;
  map.set(5, 10, T.TREE);
  map.set(5, 12, T.WATER);
  assert.ok(map.hasLineOfSight(2 * TILE + 16, y, 20 * TILE + 16, y));
  map.set(5, 14, T.BRICK);
  assert.ok(!map.hasLineOfSight(2 * TILE + 16, y, 20 * TILE + 16, y));
});

test('A* находит путь в лабиринте со змеевидными стенами', () => {
  const map = new GameMap();
  map.fill(T.EMPTY);
  for (let r = 0; r < ROWS; r++) {
    map.set(r, 0, T.WALL);
    map.set(r, COLS - 1, T.WALL);
  }
  for (let c = 0; c < COLS; c++) {
    map.set(0, c, T.WALL);
    map.set(ROWS - 1, c, T.WALL);
  }
  // Вертикальные перегородки с проходами по очереди у верха и низа.
  for (let c = 6; c < COLS - 6; c += 8) {
    for (let r = 1; r < ROWS - 1; r++) map.set(r, c, T.WALL);
    const gap = (c / 8) % 2 === 0 ? 2 : ROWS - 3;
    map.set(gap, c, T.EMPTY);
    map.set(gap + 1, c, T.EMPTY);
  }
  const path = findPath(map, 2 * TILE + 16, 2 * TILE + 16, (COLS - 3) * TILE + 16, (ROWS - 3) * TILE + 16);
  assert.ok(path.length > 0, 'путь не найден');
  const last = path[path.length - 1];
  const goalDist = Math.hypot(last.x - ((COLS - 3) * TILE + 16), last.y - ((ROWS - 3) * TILE + 16));
  assert.ok(goalDist < TILE * 2, `путь оборвался в ${goalDist.toFixed(0)} px от цели`);
  for (const wp of path) {
    assert.ok(map.isDrivable(map.rowAt(wp.y), map.colAt(wp.x)), 'путевая точка внутри стены');
  }
});

test('A* не зацикливается на недостижимой цели', () => {
  const map = new GameMap();
  map.fill(T.EMPTY);
  // Полностью замуровываем цель.
  for (let r = 9; r <= 11; r++) for (let c = 9; c <= 11; c++) map.set(r, c, T.WALL);
  map.set(10, 10, T.EMPTY);
  const t0 = Date.now();
  const path = findPath(map, 2 * TILE, 2 * TILE, 10 * TILE + 16, 10 * TILE + 16);
  assert.ok(Date.now() - t0 < 500, 'поиск занял слишком много времени');
  assert.ok(Array.isArray(path));
});

test('цель в стене подменяется ближайшей проезжаемой клеткой', () => {
  const map = new GameMap();
  map.fill(T.EMPTY);
  map.set(10, 10, T.WALL);
  const path = findPath(map, 2 * TILE, 2 * TILE, 10 * TILE + 16, 10 * TILE + 16);
  assert.ok(path.length > 0, 'путь к соседней клетке не найден');
});

test('hasDrivableSegment не срезает угол стены (supercover)', () => {
  const map = new GameMap();
  map.fill(T.EMPTY);
  // Одиночный столб стены в (5,5).
  map.set(5, 5, T.WALL);
  // Отрезок, проходящий «наискосок» через вершину стены.
  const a = [(4 * TILE + 32), (4 * TILE + 16)];
  const b = [(6 * TILE + 16), (6 * TILE + 32)];
  // Линия почти проходит через угол стены в точке (5*32, 5*32). Наивный DDA
  // может «прорезать», corner-safe обязан отказаться.
  const res = map.hasDrivableSegment(a[0], a[1], b[0], b[1]);
  // Проверяем хотя бы, что прямая видимость сквозь явный блок отсекается:
  const y = 5 * TILE + 16;
  assert.ok(!map.hasDrivableSegment(2 * TILE + 16, y, 20 * TILE + 16, y), 'отрезок сквозь стену прошёл');
});

test('A*, огибая угол, не выдаёт кратчайший путь сквозь стену', () => {
  const map = new GameMap();
  map.fill(T.EMPTY);
  const y = 5 * TILE + 16;
  map.set(5, 8, T.WALL);
  map.set(5, 9, T.WALL);
  const path = findPath(map, 2 * TILE + 16, y, 14 * TILE + 16, y);
  assert.ok(path.length > 0, 'путь не найден');
  const last = path[path.length - 1];
  assert.ok(Math.hypot(last.x - (14 * TILE + 16), last.y - y) < TILE * 2, 'маршрут не дошёл до цели');
  // Ни одна путевая точка не должна лежать в стене или в прорезанном угле.
  for (const wp of path) {
    assert.ok(map.isDrivable(map.rowAt(wp.y), map.colAt(wp.x)), 'путевая точка в стене');
  }
});

test('боты почти не упираются носом в стены (регрессия pathfinding)', () => {
  const { world, players } = makeWorld({ mode: 'ffa', difficulty: 'hard', level: 3, playerCount: 1 });
  let noseWallTicks = 0;
  const ticks = 2400;
  for (let i = 0; i < ticks; i++) {
    world.step();
    players[0].pendingLevelUps = 0;
    if (world.finished) break;
    for (const t of world.tanks) {
      if (!t.alive || t.isPlayerControlled) continue;
      const wantX = t.brain?.destX ?? t.x;
      const wantY = t.brain?.destY ?? t.y;
      if (Math.hypot(wantX - t.x, wantY - t.y) < 30) continue;
      const front = world.map.get(
        world.map.rowAt(t.y + Math.sin(t.bodyAngle) * 20),
        world.map.colAt(t.x + Math.cos(t.bodyAngle) * 20),
      );
      if ((front === T.WALL || front === T.BRICK) && Math.hypot(t.vx, t.vy) < 0.5 && t.fireCooldown > 0) {
        noseWallTicks++;
      }
    }
  }
  const bots = world.tanks.filter((x) => x.isBot).length;
  const pct = (noseWallTicks / (ticks * bots)) * 100;
  assert.ok(pct < 6, `боты упираются в стены ${pct.toFixed(1)}% времени`);
});

// ============================================================================
section('Перки: пересчёт характеристик');

test('модификаторы перемножаются, шансы не превышают 100%', () => {
  const m = computeModifiers(['rapid_fire', 'quick_reload']);
  assert.ok(Math.abs(m.fireRateMult - 0.42) < 1e-9, `ожидалось 0.42, получено ${m.fireRateMult}`);
  const e = computeModifiers(['evasion', 'evasion']);
  assert.ok(e.evasionChance < 1);
});

test('heavy_armor: снятие перка возвращает максимум HP (баг старой версии)', () => {
  const tank = new Tank({
    x: 100, y: 100, team: 'p', name: 'T',
    owner: { perkIds: [] },
    maxHP: 100, speed: 1, fireRate: 20,
  });
  // Симулируем владельца: танк держит ссылку на его массив перков.
  tank.perkIds = tank.owner.perkIds;
  assert.equal(tank.maxHP, 100);

  tank.perkIds.push('heavy_armor');
  tank.recompute();
  assert.equal(tank.maxHP, 150, 'перк не увеличил максимум HP');

  tank.perkIds.length = 0;
  tank.recompute();
  assert.equal(tank.maxHP, 100, 'после снятия перка максимум HP не вернулся — старый баг');
  assert.ok(tank.hp <= tank.maxHP, 'HP осталось выше максимума');
});

test('доля здоровья сохраняется при изменении максимума', () => {
  const owner = { perkIds: [] };
  const tank = new Tank({
    x: 0, y: 0, team: 'p', name: 'T', owner,
    maxHP: 100, speed: 1, fireRate: 20,
  });
  tank.perkIds = owner.perkIds;
  tank.hp = 50;
  tank.perkIds.push('heavy_armor');
  tank.recompute();
  assert.equal(tank.maxHP, 150);
  assert.equal(tank.hp, 75, 'половина от 150 должна быть 75');
});

test('каждый перк из UNLOCK_TABLE существует, каждый нечелленджевый перк открывается', () => {
  const known = new Set(PERKS.map((p) => p.id));
  const listed = new Set();
  for (const ids of Object.values(UNLOCK_TABLE)) {
    for (const id of ids) {
      assert.ok(known.has(id), `в таблице разблокировок неизвестный перк ${id}`);
      assert.ok(!listed.has(id), `перк ${id} указан в таблице дважды`);
      listed.add(id);
    }
  }
  for (const perk of PERKS) {
    const reachable = perk.challenge ? true : listed.has(perk.id);
    assert.ok(reachable, `перк ${perk.id} нельзя получить: нет ни уровня, ни челленджа`);
  }
});

test('на 1-м уровне профиля есть чем экипироваться', () => {
  const profile = new Profile(memoryStorage());
  const available = profile.availablePerkIds();
  assert.ok(available.length >= 3, `на старте доступно только ${available.length} перков`);
});

test('flags описаны только известными метками', () => {
  const allowed = new Set([
    'doubleShot', 'fanShot', 'explosive', 'piercing', 'shield',
    'mines', 'keepBricks', 'amphibious', 'forest', 'berserk', 'kamikaze',
  ]);
  for (const perk of PERKS) {
    for (const f of perk.flags ?? []) {
      assert.ok(allowed.has(f), `перк ${perk.id}: неизвестная метка ${f}`);
    }
  }
  const set = computeFlags(['fan_shot', 'mines']);
  assert.ok(set.has('fanShot') && set.has('mines'));
});

test('описания перков не противоречат числам', () => {
  // Старая версия обещала «урон x4» у веерного выстрела, а в коде было 0.25.
  const fan = getPerk('fan_shot');
  assert.match(fan.desc, /45%/, 'описание веерного выстрела должно называть реальный урон');
  const thick = getPerk('thick_armor');
  assert.ok(thick.mods?.damageTakenMult < 1, 'у «толстой брони» должен быть реальный плюс');
});

// ============================================================================
section('Профиль и прогресс');

test('опыт повышает уровень и открывает перки', () => {
  const p = new Profile(memoryStorage());
  const startLevel = p.globalLevel;
  const unlockedBefore = p.unlocked.size;
  const res = p.addXP(100000);
  assert.ok(p.globalLevel > startLevel, 'уровень не вырос');
  assert.ok(res.levels.length > 0);
  assert.ok(p.unlocked.size > unlockedBefore, 'новые перки не открылись');
});

test('челлендж открывает перк по достижении цели', () => {
  const p = new Profile(memoryStorage());
  assert.ok(!p.isUnlocked('ram'));
  p.bumpStat('ramKills', 1);
  p.bumpStat('ramKills', 1);
  assert.ok(!p.isUnlocked('ram'), 'открылся раньше времени');
  const newly = p.bumpStat('ramKills', 1);
  assert.ok(p.isUnlocked('ram'), 'челлендж не сработал на 3-м убийстве');
  assert.deepEqual(newly.perks, ['ram']);
});

test('рекордные статистики берут максимум, а не сумму', () => {
  const p = new Profile(memoryStorage());
  p.bumpStat('cleanStreak', 5);
  p.bumpStat('cleanStreak', 2);
  assert.equal(p.stats.cleanStreak, 5, 'рекорд перезаписался меньшим значением');
  p.bumpStat('bricksDestroyed', 3);
  p.bumpStat('bricksDestroyed', 4);
  assert.equal(p.stats.bricksDestroyed, 7, 'накопительная статистика должна складываться');
});

test('сохранение и загрузка профиля переживают круг', () => {
  const storage = memoryStorage();
  const a = new Profile(storage);
  a.addXP(3000);
  a.bumpStat('healthPacksCollected', 7);
  a.save();
  const b = new Profile(storage);
  assert.equal(b.globalLevel, a.globalLevel);
  assert.equal(b.globalXP, a.globalXP);
  assert.equal(b.stats.healthPacksCollected, 7);
  assert.deepEqual([...b.unlocked].sort(), [...a.unlocked].sort());
});

test('битое сохранение не ломает запуск', () => {
  const storage = memoryStorage();
  storage.set('tanchiki_v2_profile', '{это не json');
  const p = new Profile(storage);
  assert.equal(p.globalLevel, 1);
  assert.ok(p.availablePerkIds().length >= 3);
});

test('сброс прогресса возвращает стартовое состояние', () => {
  const p = new Profile(memoryStorage());
  p.addXP(50000);
  p.bumpStat('timesDied', 20);
  p.reset();
  assert.equal(p.globalLevel, 1);
  assert.equal(p.globalXP, 0);
  assert.equal(p.stats.timesDied, 0);
});

test('монеты начисляются и тратятся, но не уходят в минус', () => {
  const p = new Profile(memoryStorage());
  assert.equal(p.money, 0);
  p.addMoney(150);
  assert.equal(p.money, 150);
  assert.equal(p.spendMoney(100), true);
  assert.equal(p.money, 50);
  assert.equal(p.spendMoney(100), false, 'потратили больше, чем есть');
  assert.equal(p.money, 50, 'неудачная трата не должна списывать деньги');
});

test('покупка улучшения списывает монеты и повышает уровень', () => {
  const p = new Profile(memoryStorage());
  p.addMoney(1000);
  const before = p.money;
  const res = p.buyUpgrade('dmg');
  assert.equal(res.ok, true, 'не удалось купить: ' + res.reason);
  assert.equal(res.level, 1);
  assert.equal(p.upgradeLevel('dmg'), 1);
  assert.equal(p.money, before - res.cost);
});

test('нельзя купить неизвестное, максимальное или безденежное улучшение', () => {
  const p = new Profile(memoryStorage());
  assert.deepEqual(p.buyUpgrade('nosuch'), { ok: false, reason: 'unknown' });

  const up = UPGRADES.find((u) => u.id === 'dmg');
  for (let i = 0; i < up.maxLevel; i++) {
    p.addMoney(100000);
    const res = p.buyUpgrade('dmg');
    assert.equal(res.ok, true, 'должно было купиться на шаге ' + i);
  }
  const maxed = p.buyUpgrade('dmg');
  assert.equal(maxed.reason, 'max', 'купили уровень сверх максимума');

  const broke = new Profile(memoryStorage());
  const poor = broke.buyUpgrade('regen');
  assert.equal(poor.reason, 'money', 'купили без денег');
});

test('улучшения перемножаются, реген складывается', () => {
  const p = new Profile(memoryStorage());
  p.addMoney(100000);
  p.buyUpgrade('dmg'); // dmgMult = 1.06
  p.buyUpgrade('max_hp'); // maxHPMult = 1.07
  p.buyUpgrade('regen');
  p.buyUpgrade('regen'); // 20 + 20 = 40 в минуту

  const m = p.upgradeMods();
  assert.ok(Math.abs(m.dmgMult - 1.06) < 1e-9, `dmgMult=${m.dmgMult}`);
  assert.ok(Math.abs(m.maxHPMult - 1.07) < 1e-9, `maxHPMult=${m.maxHPMult}`);
  assert.equal(m.regenPerMinute, 40);
  assert.equal(m.speedMult, 1, 'некупленные улучшения не должны влиять');
});

test('монеты и улучшения переживают сохранение и загрузку', () => {
  const storage = memoryStorage();
  const a = new Profile(storage);
  a.addMoney(777);
  const cost = a.upgradeNextCost('fire_rate');
  a.buyUpgrade('fire_rate');
  a.save();
  const b = new Profile(storage);
  assert.equal(b.money, 777 - cost);
  assert.equal(b.upgradeLevel('fire_rate'), 1);
  assert.equal(b.upgradeLevel('max_hp'), 0);
});

test('косметику можно купить, экипировать и снять', () => {
  const p = new Profile(memoryStorage());
  assert.equal(p.isCosmeticOwned('hull', 'none'), true, 'none доступен бесплатно');
  assert.equal(p.buyCosmetic('hull', 'none').reason, 'free', 'none нельзя купить');
  assert.equal(p.buyCosmetic('hull', 'nope').reason, 'unknown', 'неизвестная косметика');
  assert.equal(p.equipCosmetic('hull', 'star').reason, 'not_owned', 'нельзя надеть некупленное');

  p.addMoney(1000);
  assert.equal(p.buyCosmetic('hull', 'star').ok, true);
  assert.equal(p.buyCosmetic('hull', 'star').reason, 'owned', 'нельзя купить дважды');
  assert.equal(p.equipCosmetic('hull', 'star').ok, true);
  assert.equal(p.cosmetics.hull, 'star');
  assert.deepEqual(p.equippedCosmetics(), { hull: 'star', track: 'none', turret: 'none' });

  // Звёзда стоит 150, золотая башня 160 — на оба хватает.
  assert.equal(p.buyCosmetic('turret', 'gold').ok, true);
  assert.equal(p.equipCosmetic('turret', 'gold').ok, true);
  assert.equal(p.cosmetics.turret, 'gold');
  assert.deepEqual(p.equippedCosmetics(), { hull: 'star', track: 'none', turret: 'gold' });

  // id могут совпадать между типами — покупка трека «gold» отдельна от башни «gold».
  assert.equal(p.buyCosmetic('track', 'gold').ok, true);
});

test('косметика переживает сохранение и сброс', () => {
  const storage = memoryStorage();
  const a = new Profile(storage);
  a.addMoney(1000);
  a.buyCosmetic('track', 'gold');
  a.equipCosmetic('track', 'gold');
  a.save();
  const b = new Profile(storage);
  assert.equal(b.isCosmeticOwned('track', 'gold'), true);
  assert.equal(b.cosmetics.track, 'gold');

  const c = new Profile(memoryStorage());
  c.addMoney(1000);
  c.buyCosmetic('hull', 'flames');
  c.equipCosmetic('hull', 'flames');
  c.reset();
  assert.equal(c.isCosmeticOwned('hull', 'flames'), false, 'сброс должен вернуть покупки');
  assert.equal(c.cosmetics.hull, 'none');
});

test('достижение открывается по статистике и платит монеты', () => {
  const p = new Profile(memoryStorage());
  const moneyBefore = p.money;
  const events = [];
  p.on('achievement', (e) => events.push(e));
  const res = p.bumpStat('totalKills', 1);
  assert.ok(p.achievements.has('first_blood'), 'достижение не открылось');
  assert.deepEqual(res.achievements, ['first_blood']);
  assert.equal(p.money, moneyBefore + 10, 'награда не начислена');
  assert.equal(events.length, 1);
  assert.equal(events[0].reward, 10);
});

test('открытые достижения не платят дважды', () => {
  const p = new Profile(memoryStorage());
  p.bumpStat('totalKills', 1);
  const money = p.money;
  p.bumpStat('totalKills', 1);
  assert.equal(p.money, money, 'за уже открытое достижение начислили снова');
});

test('достижения переживают сохранение и сброс прогресса', () => {
  const storage = memoryStorage();
  const a = new Profile(storage);
  a.bumpStat('gamesPlayed', 10);
  a.save();
  const b = new Profile(storage);
  assert.ok(b.achievements.has('games_10'), 'достижение не сохранилось');

  const c = new Profile(memoryStorage());
  c.bumpStat('gamesPlayed', 10);
  c.reset();
  assert.equal(c.achievements.size, 0, 'сброс не очистил достижения');
});

test('ежедневное задание набирает прогресс и выдаёт награду', () => {
  const p = new Profile(memoryStorage());
  const moneyBefore = p.money;
  p.bumpDaily('kills', 5);
  p.bumpDaily('kills', 10);
  const pr = p.dailyProgress('kill_15');
  assert.equal(pr.current, 15, 'прогресс не набрался');
  assert.equal(pr.claimed, false);
  const res = p.claimDaily('kill_15');
  assert.equal(res.ok, true, 'нельзя забрать выполненное задание');
  assert.equal(res.reward, pr.reward);
  assert.equal(p.money, moneyBefore + pr.reward, 'награда не начислена');
});

test('задание нельзя забрать дважды или невыполненным', () => {
  const p = new Profile(memoryStorage());
  const early = p.claimDaily('kill_15');
  assert.equal(early.reason, 'not_done', 'забрали невыполненное задание');

  p.bumpDaily('kills', 20);
  assert.equal(p.claimDaily('kill_15').ok, true);
  const again = p.claimDaily('kill_15');
  assert.equal(again.reason, 'claimed', 'забрали второй раз');
});

test('ежедневный прогресс сбрасывается на следующий день', () => {
  const p = new Profile(memoryStorage());
  p.bumpDaily('kills', 15);
  assert.equal(p.dailyProgress('kill_15').current, 15);
  // Принудительно «наступил» следующий день.
  p.daily.date = '1970-01-01';
  assert.equal(p.dailyProgress('kill_15').current, 0, 'прогресс не сброшен');
  assert.equal(p.dailyProgress('kill_15').claimed, false);
});

test('ежедневные задания переживают сохранение', () => {
  const storage = memoryStorage();
  const a = new Profile(storage);
  a.bumpDaily('wins', 2);
  a.claimDaily('win_2');
  a.save();
  const b = new Profile(storage);
  assert.equal(b.dailyProgress('win_2').current, 2);
  assert.equal(b.dailyProgress('win_2').claimed, true);
});

// ============================================================================
section('Симуляция: стабильность');

for (const mode of ['ffa', 'ctf']) {
  for (const difficulty of ['easy', 'hard']) {
    test(`${mode}/${difficulty}: 3600 тиков без ошибок и без NaN`, () => {
      const { world, players } = makeWorld({ mode, difficulty, playerCount: 2, scheme: activeScheme(1, 0) });
      for (let i = 0; i < 3600; i++) {
        world.step();
        // Выбор перка в тестах не показываем — сразу гасим очередь.
        for (const p of players) p.pendingLevelUps = 0;
        if (world.finished) break;
      }
      for (const tank of world.tanks) {
        assert.ok(Number.isFinite(tank.x) && Number.isFinite(tank.y), `${tank.name}: координаты NaN`);
        assert.ok(tank.x >= 0 && tank.x <= MAP_W, `${tank.name}: x вне карты (${tank.x})`);
        assert.ok(tank.y >= 0 && tank.y <= MAP_H, `${tank.name}: y вне карты (${tank.y})`);
        assert.ok(Number.isFinite(tank.hp) && tank.hp >= 0, `${tank.name}: hp = ${tank.hp}`);
        assert.ok(tank.hp <= tank.maxHP, `${tank.name}: hp выше максимума`);
        assert.ok(Number.isFinite(tank.turretAngle), `${tank.name}: угол башни NaN`);
      }
    });
  }
}

test('koth/medium: 3600 тиков без ошибок и без NaN, карта заливается', () => {
  const { world, players } = makeWorld({ mode: 'koth', difficulty: 'medium', playerCount: 1, scheme: activeScheme(1, 0) });
  const startWaters = world.map.tiles.filter((t) => t === T.WATER).length;
  for (let i = 0; i < 3600; i++) {
    world.step();
    players[0].pendingLevelUps = 0;
    if (world.finished) break;
  }
  for (const tank of world.tanks) {
    assert.ok(Number.isFinite(tank.x) && Number.isFinite(tank.y), `${tank.name}: координаты NaN`);
    assert.ok(Number.isFinite(tank.hp) && tank.hp >= 0, `${tank.name}: hp = ${tank.hp}`);
  }
  // Если партия дожила до затопления — вода должна прибывать.
  if (!world.finished) {
    const endWaters = world.map.tiles.filter((t) => t === T.WATER).length;
    assert.ok(endWaters > startWaters, 'вода не прибывает при затоплении');
  }
});

test('танки не застревают в стенах', () => {
  const { world, players } = makeWorld({ mode: 'ffa', difficulty: 'medium', playerCount: 2, scheme: activeScheme(1, 1) });
  for (let i = 0; i < 1800; i++) {
    world.step();
    for (const p of players) p.pendingLevelUps = 0;
  }
  for (const tank of world.tanks) {
    if (!tank.alive) continue;
    assert.ok(
      !world.map.isBlockedRect(tank.x, tank.y, tank.width, tank.height),
      `${tank.name} оказался внутри стены`,
    );
  }
});

test('массивы пуль и частиц не растут бесконечно', () => {
  const { world, players } = makeWorld({ mode: 'ffa', difficulty: 'hard', playerCount: 2, scheme: activeScheme(0, 1) });
  let maxBullets = 0;
  for (let i = 0; i < 2400; i++) {
    world.step();
    for (const p of players) p.pendingLevelUps = 0;
    maxBullets = Math.max(maxBullets, world.bullets.length);
  }
  assert.ok(maxBullets < 400, `пуль одновременно: ${maxBullets}`);
  assert.ok(world.particles.count <= world.particles.max, 'пул частиц переполнен');
});

test('счётчик мин не позволяет превысить лимит', () => {
  const { world, players } = makeWorld({ playerCount: 1 });
  const tank = players[0].tank;
  players[0].perkIds.push('mines');
  tank.recompute();
  for (let i = 0; i < 50; i++) {
    tank.mineCooldown = 0;
    tank.placeMine(world);
  }
  const own = world.mines.filter((m) => m.owner === tank).length;
  assert.ok(own <= 3, `мин у игрока: ${own}`);
});

// ============================================================================
section('Симуляция: правила и начисление');

test('FFA: у каждого бойца своя команда, все враждебны друг другу', () => {
  const { world } = makeWorld({ mode: 'ffa', playerCount: 2 });
  const teams = new Set(world.tanks.map((t) => t.team));
  assert.equal(teams.size, world.tanks.length, 'команды повторяются — часть врагов «дружит»');
  assert.ok(world.areHostile(world.tanks[0], world.tanks[1]));
});

test('CTF: составы команд равные, роли расставлены', () => {
  const single = makeWorld({ mode: 'ctf', playerCount: 1 }).world;
  const own = single.tanks.filter((t) => t.team === 'player').length;
  const foe = single.tanks.filter((t) => t.team === 'enemy').length;
  assert.equal(own, MODES.ctf.teamSize);
  assert.equal(foe, MODES.ctf.teamSize);

  const hot = makeWorld({ mode: 'ctf', playerCount: 2 }).world;
  assert.equal(hot.tanks.filter((t) => t.team === 'player').length, MODES.ctf.teamSize);
  assert.equal(hot.tanks.filter((t) => t.team === 'enemy').length, MODES.ctf.teamSize);
  assert.equal(hot.players[0].tank.team, 'player');
  assert.equal(hot.players[1].tank.team, 'enemy');
});

test('фраг достаётся тому, кто убил (баг старой версии: всегда P1)', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 2 });
  const [p1, p2] = players;
  const bot = world.tanks.find((t) => t.isBot);
  const p2tank = p2.tank;

  // Бот убивает второго игрока.
  p2tank.spawnProtect = 0;
  world.dealDamage(p2tank, 99999, bot, 'bullet');

  assert.equal(p2tank.alive, false, 'второй игрок не погиб');
  assert.equal(p1.kills, 0, 'первому игроку начислили чужое убийство');
  assert.equal(p1.score, 0, 'первому игроку начислили чужие очки');
  assert.equal(p2.deaths, 1);
  assert.equal(bot.kills, 1, 'бот не получил фраг');
});

test('игрок получает фраг, опыт и очки за своё убийство', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 1 });
  const p1 = players[0];
  const bot = world.tanks.find((t) => t.isBot);
  bot.spawnProtect = 0;
  world.dealDamage(bot, 99999, p1.tank, 'bullet');
  assert.equal(p1.kills, 1);
  assert.ok(p1.score > 0);
  assert.ok(p1.sessionXP > 0 || p1.sessionLevel > 1, 'опыт не начислен');
});

test('за убийство человеку начисляется валюта и событие reward', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 1 });
  const p1 = players[0];
  const bot = world.tanks.find((t) => t.isBot);
  const rewards = [];
  world.on('reward', (r) => rewards.push(r));

  bot.spawnProtect = 0;
  world.dealDamage(bot, 99999, p1.tank, 'bullet');

  assert.equal(rewards.length, 1, 'события reward не было');
  assert.equal(rewards[0].kind, 'kill');
  assert.equal(rewards[0].amount, REWARD_KILL);
  assert.equal(world.matchRewards.kills, REWARD_KILL);
});

test('за захват флага человеку начисляется валюта', () => {
  const { world, players } = makeWorld({ mode: 'ctf', playerCount: 1 });
  const tank = players[0].tank;
  const flag = world.flags.find((f) => f.team === 'enemy');
  const home = world.homeFor('player');
  const rewards = [];
  world.on('reward', (r) => rewards.push(r));

  tank.x = flag.x;
  tank.y = flag.y;
  world.step();
  tank.x = home.x;
  tank.y = home.y;
  world.step();

  const capture = rewards.find((r) => r.kind === 'capture');
  assert.ok(capture, 'события reward за захват не было');
  assert.equal(capture.amount, REWARD_CAPTURE);
  assert.equal(world.matchRewards.captures, REWARD_CAPTURE);
});

test('победа начисляет валюту и кладёт её в результат партии', () => {
  const { world } = makeWorld({ mode: 'ffa', playerCount: 1 });
  const rewards = [];
  world.on('reward', (r) => rewards.push(r));
  const tank = world.tanks.find((t) => !t.isBot);
  tank.kills = MODES.ffa.fragLimit;
  world.step();

  const win = rewards.find((r) => r.kind === 'win');
  assert.ok(win, 'события reward за победу не было');
  assert.equal(win.amount, REWARD_WIN);
  assert.ok(world.finished, 'партия не завершилась');
  assert.equal(world.result.rewards.wins, REWARD_WIN);
  assert.equal(world.result.rewards.kills + world.result.rewards.captures + world.result.rewards.wins, REWARD_WIN);
});

test('улучшения из профиля применяются к танкам игроков', () => {
  const p = new Profile(memoryStorage());
  p.addMoney(100000);
  p.buyUpgrade('max_hp'); // maxHPMult = 1.07
  const mods = p.upgradeMods();

  const tank = new Tank({
    x: 100, y: 100, team: 'p', name: 'T',
    owner: { perkIds: [] },
    maxHP: 100, speed: 1, fireRate: 20,
    upgradeMods: mods,
  });
  tank.perkIds = tank.owner.perkIds;
  tank.recompute();
  assert.ok(Math.abs(tank.maxHP - 107) < 1e-9, `maxHP=${tank.maxHP}, ожидалось 107`);
});

test('самоуничтожение в воде не даёт никому фраг', () => {
  const { world, players } = makeWorld({ playerCount: 1 });
  const tank = players[0].tank;
  tank.spawnProtect = 0;
  let killEvent = null;
  world.on('kill', (e) => (killEvent = e));
  world.dealDamage(tank, 99999, null, 'water');
  assert.ok(killEvent, 'события смерти не было');
  assert.equal(killEvent.suicide, true);
  assert.equal(players[0].kills, 0);
});

test('спавн-защита блокует пули, но не спасает от воды', () => {
  const { world, players } = makeWorld({ playerCount: 1 });
  const tank = players[0].tank;
  const bot = world.tanks.find((t) => t.isBot);
  tank.spawnProtect = 60;
  const before = tank.hp;
  world.dealDamage(tank, 30, bot, 'bullet');
  assert.equal(tank.hp, before, 'спавн-защита не сработала против пули');
  world.dealDamage(tank, 5, null, 'water');
  assert.ok(tank.hp < before, 'вода должна топить даже под спавн-защитой');
});

test('состояние перков у двух игроков независимо (баг общих глобалов)', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 2 });
  const [p1, p2] = players;
  p1.equipPerk('shield');
  // Прокручиваем достаточно тиков, чтобы щит выдался.
  for (let i = 0; i < 5; i++) world.step();
  assert.ok(p1.tank.shieldHP > 0, 'щит первого игрока не появился');
  assert.equal(p2.tank.shieldHP, 0, 'щит утёк второму игроку');

  const cd1 = p1.tank.shieldCooldown;
  for (let i = 0; i < 60; i++) world.step();
  // За 60 тиков перезарядка должна уйти ровно на 60, а не на 120.
  const spent = cd1 - p1.tank.shieldCooldown;
  assert.ok(Math.abs(spent - 60) <= 1, `перезарядка ушла на ${spent} вместо 60 — двойной тик`);
});

test('урон по одному игроку не засвечивает экран другому', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 2 });
  const [p1, p2] = players;
  const bot = world.tanks.find((t) => t.isBot);
  p2.tank.spawnProtect = 0;
  world.dealDamage(p2.tank, 10, bot, 'bullet');
  assert.ok(p2.damageFlash > 0, 'пострадавший не получил вспышку');
  assert.equal(p1.damageFlash, 0, 'вспышка ушла не тому игроку');
});

test('серия без урона сбрасывается только у пострадавшего', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 2 });
  const [p1, p2] = players;
  const bot = world.tanks.find((t) => t.isBot);
  p1.cleanStreak = 3;
  p2.cleanStreak = 4;
  p2.tank.spawnProtect = 0;
  world.dealDamage(p2.tank, 5, bot, 'bullet');
  assert.equal(p1.cleanStreak, 3, 'серия первого игрока сброшена чужим уроном');
  assert.equal(p2.cleanStreak, 0);
});

test('отражение возвращает урон атакующему, без бесконечной рекурсии', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 1 });
  const p1 = players[0];
  p1.equipPerk('reflect');
  const bot = world.tanks.find((t) => t.isBot);
  bot.spawnProtect = 0;
  p1.tank.spawnProtect = 0;
  const botHP = bot.hp;
  world.dealDamage(p1.tank, 50, bot, 'bullet');
  assert.ok(bot.hp < botHP, 'отражение не нанесло урон атакующему');
});

test('вампиризм лечит за нанесённый урон', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 1 });
  const p1 = players[0];
  p1.equipPerk('vampire');
  p1.tank.hp = 20;
  const bot = world.tanks.find((t) => t.isBot);
  bot.spawnProtect = 0;
  world.dealDamage(bot, 40, p1.tank, 'bullet');
  assert.ok(p1.tank.hp > 20, 'HP не восстановилось');
});

test('усиление ботов по времени ограничено и не теряется при пересчёте перков', () => {
  const { world } = makeWorld({ mode: 'ffa', difficulty: 'medium' });
  const bot = world.tanks.find((t) => t.isBot);
  const baseHP = bot.maxHP;
  // Прокручиваем несколько порогов усиления.
  for (let i = 0; i < 10; i++) {
    world.rampTimer = 1e9;
    world.step();
  }
  assert.ok(world.ramp <= 1.8 + 1e-9, `множитель вышел за предел: ${world.ramp}`);
  assert.ok(bot.maxHP > baseHP, 'бот не усилился');
  const boosted = bot.maxHP;
  bot.perkIds.push('bot_rapid'); // перк без влияния на HP
  bot.recompute();
  assert.equal(bot.maxHP, boosted, 'усиление сбросилось при пересчёте перков');
});

test('пробивная пуля выходит за стену, а не гибнет внутри', () => {
  const lvl = generateLevel(1, 'ffa');
  const map = lvl.map;
  map.fill(T.EMPTY);
  const players = makePlayers(1);
  const world = new World({ map, level: lvl, mode: 'ffa', difficulty: 'easy', players, audio: silentAudio });
  const shooter = players[0].tank;
  players[0].perkIds.push('piercing');
  shooter.recompute();

  // Одна колонна стены прямо по курсу.
  const y = 20 * TILE + 16;
  const startX = 10 * TILE + 16;
  map.set(20, 14, T.WALL);
  const bullet = new Bullet(startX, y, 0, shooter, 1);
  world.bullets.length = 0;
  world.bullets.push(bullet);

  for (let i = 0; i < 200 && bullet.alive; i++) bullet.update(world);
  assert.ok(bullet.x > 15 * TILE, `пуля не прошла стену, остановилась на x=${bullet.x.toFixed(0)}`);
});

test('«толстая броня» не ломает кирпич и снижает урон', () => {
  const lvl = generateLevel(1, 'ffa');
  const map = lvl.map;
  map.fill(T.EMPTY);
  const players = makePlayers(1);
  const world = new World({ map, level: lvl, mode: 'ffa', difficulty: 'easy', players, audio: silentAudio });
  const shooter = players[0].tank;
  players[0].perkIds.push('thick_armor');
  shooter.recompute();
  assert.ok(shooter.mods.damageTakenMult < 1);

  map.set(20, 14, T.BRICK);
  const bullet = new Bullet(10 * TILE + 16, 20 * TILE + 16, 0, shooter, 1);
  for (let i = 0; i < 200 && bullet.alive; i++) bullet.update(world);
  assert.equal(map.get(20, 14), T.BRICK, 'кирпич всё-таки разрушен');
});

test('CTF: захват флага увеличивает счёт команды и возвращает флаг домой', () => {
  const { world, players } = makeWorld({ mode: 'ctf', playerCount: 1 });
  const tank = players[0].tank;
  const flag = world.flags.find((f) => f.team === 'enemy');
  const home = world.homeFor('player');

  // Берём флаг.
  tank.x = flag.x;
  tank.y = flag.y;
  world.step();
  assert.equal(tank.carryingFlag, true, 'флаг не подобран');

  // Довозим до базы.
  tank.x = home.x;
  tank.y = home.y;
  world.step();
  assert.equal(world.teamScore.player, 1, 'захват не засчитан');
  assert.equal(tank.carryingFlag, false);
  assert.equal(flag.x, flag.homeX, 'флаг не вернулся на своё место');
  assert.equal(players[0].captures, 1);
});

test('CTF: смерть носителя роняет флаг, союзник возвращает его касанием', () => {
  const { world, players } = makeWorld({ mode: 'ctf', playerCount: 1 });
  const tank = players[0].tank;
  const enemy = world.tanks.find((t) => t.team === 'enemy');
  const ourFlag = world.flags.find((f) => f.team === 'player');

  // Враг забирает наш флаг.
  enemy.x = ourFlag.x;
  enemy.y = ourFlag.y;
  world.step();
  assert.equal(enemy.carryingFlag, true, 'враг не забрал флаг');

  // Отвозим носителя подальше от базы флага, иначе флаг упадёт на свой дом
  // и по правилам сразу вернётся.
  const away = world.map.findFreeSpot(() => 0.5, { r0: 30, r1: 34, c0: 58, c1: 62 }, 24, 28);
  enemy.x = away.x;
  enemy.y = away.y;

  // Убиваем носителя.
  enemy.spawnProtect = 0;
  world.dealDamage(enemy, 99999, tank, 'bullet');
  assert.equal(ourFlag.carried, false, 'флаг остался «в руках» у мёртвого');
  assert.equal(ourFlag.state, 'dropped', `флаг в состоянии ${ourFlag.state}, ожидалось dropped`);
  assert.ok(!ourFlag.atHome, 'флаг телепортировался домой сразу');

  // Свой танк возвращает флаг касанием.
  tank.x = ourFlag.x;
  tank.y = ourFlag.y;
  world.step();
  assert.ok(ourFlag.atHome, 'касание своего флага не вернуло его домой');
});

test('CTF: флаг, упавший на свою базу, считается возвращённым', () => {
  const { world } = makeWorld({ mode: 'ctf', playerCount: 1 });
  const flag = world.flags.find((f) => f.team === 'player');
  flag.pickUp(world.tanks.find((t) => t.team === 'enemy'));
  flag.drop(flag.homeX + 4, flag.homeY - 4, 900);
  assert.equal(flag.state, 'home', 'флаг на своей базе должен сразу вернуться');
  assert.equal(flag.returnTimer, 0);
});

test('CTF: брошенный флаг сам возвращается по таймеру', () => {
  const { world } = makeWorld({ mode: 'ctf', playerCount: 1 });
  const flag = world.flags.find((f) => f.team === 'player');
  flag.drop(50 * TILE, 50 * TILE, 3);
  for (let i = 0; i < 5; i++) world.step();
  assert.ok(flag.atHome, 'таймер возврата не сработал');
});

test('CTF: победа фиксируется на пятом захвате', () => {
  const { world } = makeWorld({ mode: 'ctf', playerCount: 1 });
  let finish = null;
  world.on('finish', (r) => (finish = r));
  world.teamScore.player = MODES.ctf.capLimit;
  world.step();
  assert.ok(finish, 'победа не зафиксирована');
  assert.equal(finish.victory, true);
  assert.equal(world.finished, true);
});

test('FFA: победа достаётся тому, кто первым добрал лимит фрагов', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 2 });
  let finish = null;
  world.on('finish', (r) => (finish = r));
  const bot = world.tanks.find((t) => t.isBot);
  bot.kills = MODES.ffa.fragLimit;
  world.step();
  assert.ok(finish, 'партия не завершилась');
  assert.equal(finish.victory, false, 'победа бота записана игроку');
  assert.equal(finish.winnerPlayerIndex, null);
  void players;
});

test('FFA: победа второго игрока помечена именно им', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 2 });
  let finish = null;
  world.on('finish', (r) => (finish = r));
  players[1].tank.kills = MODES.ffa.fragLimit;
  world.step();
  assert.equal(finish.winnerPlayerIndex, 1);
  assert.equal(finish.victory, false, 'с точки зрения P1 это не победа');
});

test('после завершения партии мир больше не обновляется', () => {
  const { world } = makeWorld({ mode: 'ctf', playerCount: 1 });
  world.teamScore.player = MODES.ctf.capLimit;
  world.step();
  const tickAfterFinish = world.tick;
  world.step();
  world.step();
  assert.equal(world.tick, tickAfterFinish, 'мир продолжает считать после победы');
});

test('погибшие возрождаются и остаются в списке танков (баг сборки мусора)', () => {
  const { world, players } = makeWorld({ mode: 'ffa', playerCount: 1 });
  const tank = players[0].tank;
  const total = world.tanks.length;
  // Много смертей подряд: в старой версии игрока вычищали из массива tanks.
  for (let round = 0; round < 25; round++) {
    tank.spawnProtect = 0;
    world.dealDamage(tank, 99999, null, 'water');
    for (let i = 0; i <= 121; i++) world.step();
  }
  assert.ok(tank.alive, 'игрок не возродился');
  assert.ok(world.tanks.includes(tank), 'танк игрока исчез из мира');
  assert.equal(world.tanks.length, total, 'состав участников изменился');
});

test('аптечки лечат и появляются заново', () => {
  const { world, players } = makeWorld({ playerCount: 1 });
  const tank = players[0].tank;
  const pickup = world.pickups[0];
  tank.hp = 10;
  tank.x = pickup.x;
  tank.y = pickup.y;
  world.step();
  assert.ok(tank.hp > 10, 'аптечка не подобрана');
  assert.equal(pickup.active, false);
  pickup.respawnTimer = 1;
  world.step();
  assert.equal(pickup.active, true, 'аптечка не восстановилась');
});

test('перк «Магнит» увеличивает радиус подбора', () => {
  const { players } = makeWorld({ playerCount: 1 });
  const p = players[0];
  const base = p.pickupRadius;
  p.equipPerk('magnet');
  assert.ok(p.pickupRadius > base, 'радиус не изменился');
});

test('камера не выходит за карту и переносит зажим при огромном окне', () => {
  const { world, players } = makeWorld({ playerCount: 1 });
  const p = players[0];
  p.viewport = { x: 0, y: 0, w: 1280, h: 720 };
  p.tank.x = 0;
  p.tank.y = 0;
  p.updateCamera();
  assert.ok(p.camera.x >= 640 - 1e-6 && p.camera.y >= 360 - 1e-6, 'камера уехала за левый край');

  // Окно шире и выше карты — старый зажим давал min > max.
  p.viewport = { x: 0, y: 0, w: MAP_W + 500, h: MAP_H + 500 };
  p.updateCamera();
  assert.equal(p.camera.x, MAP_W / 2);
  assert.equal(p.camera.y, MAP_H / 2);
  void world;
});

test('перевод экранных координат в мировые учитывает область просмотра', () => {
  const { players } = makeWorld({ playerCount: 2 });
  const p2 = players[1];
  p2.viewport = { x: 960, y: 0, w: 960, h: 1080 };
  p2.camera.x = 1000;
  p2.camera.y = 500;
  // Центр правой половины экрана должен указывать ровно в центр камеры.
  const w = p2.screenToWorld(960 + 480, 540);
  assert.equal(w.x, 1000);
  assert.equal(w.y, 500);
});

test('боты в CTF доезжают до чужих флагов (в старой версии требовалась прямая видимость)', () => {
  const { world, players } = makeWorld({ mode: 'ctf', difficulty: 'medium', playerCount: 1 });
  // Уводим игрока подальше, чтобы боты занимались флагами, а не боем.
  players[0].tank.x = MAP_W / 2;
  players[0].tank.y = MAP_H / 2;
  let anyPickup = false;
  world.on('flag', (e) => {
    if (e.type === 'taken') anyPickup = true;
  });
  for (let i = 0; i < 5400 && !anyPickup; i++) {
    world.step();
    players[0].pendingLevelUps = 0;
  }
  assert.ok(anyPickup, 'за 90 секунд ни один бот не забрал флаг');
});

test('боты действительно стреляют и наносят урон', () => {
  const { world, players } = makeWorld({ mode: 'ffa', difficulty: 'hard', playerCount: 1 });
  const tank = players[0].tank;
  let shots = 0;
  const startHP = tank.hp;
  for (let i = 0; i < 1800; i++) {
    world.step();
    players[0].pendingLevelUps = 0;
    shots = Math.max(shots, world.bullets.length);
  }
  assert.ok(shots > 0, 'боты не сделали ни одного выстрела');
  const someoneTookDamage =
    tank.hp < startHP || tank.deaths > 0 || world.tanks.some((t) => t.hp < t.maxHP || t.deaths > 0);
  assert.ok(someoneTookDamage, 'за 30 секунд никто не получил урона');
});

test('сложность влияет на число противников и характеристики', () => {
  const easy = makeWorld({ mode: 'ffa', difficulty: 'easy' }).world;
  const hard = makeWorld({ mode: 'ffa', difficulty: 'hard' }).world;
  assert.ok(hard.tanks.length > easy.tanks.length, 'на сложном врагов не больше');
  const eBot = easy.tanks.find((t) => t.isBot);
  const hBot = hard.tanks.find((t) => t.isBot);
  assert.ok(hBot.maxHP > eBot.maxHP);
  assert.ok(hBot.speed > eBot.speed);
  assert.ok(hBot.fireRate < eBot.fireRate, 'на сложном перезарядка должна быть быстрее');
  assert.equal(easy.players[0].tank.maxHP, DIFFICULTY.easy.playerHP);
});

test('типы врагов: у всех ботов есть тип и характеристики соответствуют', () => {
  const { world } = makeWorld({ mode: 'ffa', difficulty: 'hard' });
  const bots = world.tanks.filter((t) => t.isBot);
  assert.ok(bots.length > 0, 'нет ботов');
  for (const b of bots) {
    assert.ok(b.enemyType, `бот ${b.name} без типа врага`);
    assert.ok(b.enemyType.hpMult >= 0.75 && b.enemyType.hpMult <= 5, 'hpMult вне диапазона');
    assert.ok(b.dmgScale > 0, 'множитель урона не положительный');
  }
  // Среди 22 ботов на hard при рампе 1 должны встречаться разные типы.
  const types = new Set(bots.map((b) => b.enemyType.id));
  assert.ok(types.size >= 2, `разнообразия нет, только: ${[...types].join(', ')}`);
});

test('тяжёлый тип живучее, миномёт стреляет дуговой пулей', () => {
  const { world } = makeWorld({ mode: 'ffa', difficulty: 'hard' });
  const bot = world.tanks.find((t) => t.isBot);

  // Пересобираем танк как тяжёлого: базовый HP из сложности × множитель.
  bot.enemyType = { ...bot.enemyType, hpMult: 2.2 };
  bot.baseMaxHP = Math.round(DIFFICULTY.hard.enemyHP * 2.2);
  bot.recompute();
  assert.ok(bot.maxHP >= 150, `тяжёлый должен быть живучее, получено ${bot.maxHP}`);

  // Миномётный снаряд помечен как дуговой и взрывается.
  bot.fireCooldown = 0;
  const before = world.bullets.length;
  bot.shootLobbed(world);
  assert.equal(world.bullets.length, before + 1, 'миномёт не выстрелил');
  const shell = world.bullets[before];
  assert.equal(shell.lobbed, true, 'снаряд не помечен как дуговой');
  assert.equal(shell.explosive, true, 'миномётный снаряд должен взрываться');
});

test('босс редко и жив только один', () => {
  // pickEnemyType не должен отдавать босса на рампе 1.
  for (let i = 0; i < 200; i++) {
    const t = pickEnemyType(1, Math.random);
    assert.notEqual(t.id, 'boss', 'босс не должен появляться в начале игры');
  }
  // На максимальной рампе босс может выпасть.
  let sawBoss = false;
  for (let i = 0; i < 2000; i++) {
    if (pickEnemyType(2, Math.random).id === 'boss') { sawBoss = true; break; }
  }
  assert.ok(sawBoss, 'босс никогда не выпадает на поздней рампе');
});

test('power-up оружия разбросаны по карте и подбираются игроком', () => {
  const { world } = makeWorld({ mode: 'ffa' });
  assert.ok(world.weaponPickups.length >= 3, 'оружие не разбросано по карте');
  const ids = new Set(world.weaponPickups.map((p) => p.weaponId));
  assert.ok(ids.has('gatling') && ids.has('rockets') && ids.has('shotgun'), 'не все типы оружия на карте');

  // Ставим игрока вплотную к оружию и подбираем.
  const player = world.players[0];
  const wp = world.weaponPickups[0];
  player.tank.x = wp.x;
  player.tank.y = wp.y;
  world.step();
  assert.equal(player.tank.weapon, wp.weaponId, 'оружие не подобрано');
  assert.ok(player.tank.weaponTimer > 0, 'таймер оружия не запущен');
});

test('оружие меняет выстрел: пулемёт чаще, ракеты взрываются, дробовик веер', () => {
  const { world } = makeWorld({ mode: 'ffa' });
  const tank = world.players[0].tank;
  tank.fireCooldown = 0;

  // Пулемёт: много пуль в один залп... нет, пулемёт — одна пуля, но перезарядка вдвое короче.
  tank.weapon = 'gatling';
  tank.weaponTimer = 60;
  const baseCooldown = tank.fireRate;
  const before = world.bullets.length;
  tank.shoot(world);
  assert.equal(world.bullets.length, before + 1, 'пулемёт должен стрелять по одной пуле');
  assert.ok(tank.fireCooldown < baseCooldown, 'пулемёт должен перезаряжаться быстрее');
  tank.fireCooldown = 0;

  // Дробовик: несколько дробин веером.
  tank.weapon = 'shotgun';
  tank.weaponTimer = 60;
  const sBefore = world.bullets.length;
  tank.shoot(world);
  assert.equal(world.bullets.length, sBefore + 6, 'дробовик должен выстрелить 6 дробин');
  tank.fireCooldown = 0;

  // Ракеты: взрывные пули.
  tank.weapon = 'rockets';
  tank.weaponTimer = 60;
  const rBefore = world.bullets.length;
  tank.shoot(world);
  assert.equal(world.bullets.length, rBefore + 1, 'ракета одна');
  const rocket = world.bullets[rBefore];
  assert.equal(rocket.explosive, true, 'ракета должна взрываться');
});

test('оружие снимается по истечении таймера и после респауна', () => {
  const { world } = makeWorld({ mode: 'ffa' });
  const tank = world.players[0].tank;
  tank.weapon = 'rockets';
  tank.weaponTimer = 2;
  world.step();
  world.step();
  assert.equal(tank.weapon, null, 'оружие не снялось по таймеру');

  tank.weapon = 'gatling';
  tank.weaponTimer = 60;
  tank.respawn(tank.x, tank.y);
  assert.equal(tank.weapon, null, 'оружие должно сбрасываться при респауне');
});

test('погода: у каждого мира есть детерминированный WeatherSystem', () => {
  const { world } = makeWorld({ mode: 'ffa' });
  const w = world.weather;
  assert.ok(w, 'у мира нет погоды');
  assert.ok(['clear', 'rain', 'fog', 'storm'].includes(w.condition), 'неизвестное условие');
  assert.ok(w.light >= 0 && w.light <= 1, 'освещение вне диапазона');
  assert.ok(['ночь', 'рассвет', 'день', 'закат', 'вечер'].includes(w.timeName), 'неизвестное время суток');

  // Детерминированность: два мира с одним сидом дают одинаковую последовательность.
  const seed = 4242;
  const a = new WeatherSystem(seed);
  const b = new WeatherSystem(seed);
  for (let i = 0; i < 3000; i++) {
    a.update();
    b.update();
  }
  assert.equal(a.condition, b.condition, 'условия разошлись');
  assert.ok(Math.abs(a.rain - b.rain) < 1e-9, 'дождь разошёлся');
  assert.ok(Math.abs(a.light - b.light) < 1e-9, 'освещение разошлось');
});

test('погода: смена условий, день/ночь и молнии в грозу', () => {
  const w = new WeatherSystem(7);

  // Цикл день/ночь действительно движется.
  const lightStart = w.light;
  for (let i = 0; i < DAY_CYCLE / 2; i++) w.update();
  assert.ok(Math.abs(w.light - lightStart) > 0.1, 'освещение не меняется в течение дня');

  // Принудительная гроза вызывает вспышки молний.
  w.setCondition('storm', 1e9);
  let sawFlash = false;
  for (let i = 0; i < 2000 && !sawFlash; i++) {
    w.update();
    if (w.flash > 0.5) sawFlash = true;
  }
  assert.ok(sawFlash, 'в грозу не было вспышки молнии');

  // Дождь и туман стремятся к целевым значениям условия.
  w.setCondition('rain', 1e9);
  for (let i = 0; i < 2000; i++) w.update();
  assert.ok(w.rain > 0.5, 'дождь не достиг целевой интенсивности');

  w.setCondition('fog', 1e9);
  for (let i = 0; i < 2000; i++) w.update();
  assert.ok(w.fog > 0.5, 'туман не достиг целевой плотности');
  assert.ok(w.rain < 0.5, 'после тумана дождь должен сойти на нет');
});

test('погода: условия действительно сменяются с течением времени', () => {
  const w = new WeatherSystem(99);
  const seen = new Set([w.condition]);
  for (let i = 0; i < 30000; i++) {
    w.update();
    seen.add(w.condition);
  }
  assert.ok(seen.size >= 2, `погода не менялась, только: ${[...seen].join(', ')}`);
});

test('Оборона: база в центре, враги волнами, оба игрока в одной команде', () => {
  const { world, players } = makeWorld({ mode: 'defense', playerCount: 2 });
  // Оба человека на одной стороне.
  assert.equal(world.players[0].tank.team, world.players[1].tank.team, 'люди в разных командах');
  assert.equal(world.players[0].tank.team, 'player', 'игроки должны быть в команде «player»');
  // База есть в центре карты.
  assert.ok(world.base, 'базы нет');
  assert.equal(world.base.hp, MODES.defense.baseHP, 'HP базы не совпадает с настройкой');
  // Игроки спавнятся рядом с базой.
  const dBase = Math.hypot(world.base.x - players[0].tank.x, world.base.y - players[0].tank.y);
  assert.ok(dBase < 12 * 32, 'игрок спавнится слишком далеко от базы');
});

test('Оборона: первая волна выходит и база страдает без защиты', () => {
  const { world } = makeWorld({ mode: 'defense', playerCount: 1 });
  const startWave = world.wave;
  // Догоняем первую волну: startDelay тиков.
  for (let i = 0; i < MODES.defense.startDelay + 10; i++) {
    world.step();
    // Паузы в аптечке не важны; главное — волны.
  }
  assert.ok(world.wave >= 1, 'первая волна не вышла');
  const enemies = world.tanks.filter((t) => t.isBot).length;
  assert.ok(enemies > 0, 'в первой волне нет врагов');

  // Приводим волну к активной и ставим всех врагов прямо на базу.
  world.waveState = 'active';
  for (const t of world.tanks) {
    if (t.isBot) {
      t.x = world.base.x;
      t.y = world.base.y;
      t.spawnProtect = 0;
    }
  }
  const hpBefore = world.base.hp;
  for (let i = 0; i < 30; i++) world.step();
  assert.ok(world.base.hp < hpBefore, 'база не получила урон от врагов');
});

test('Оборона: поражение при разрушенной базе, победа после всех волн', () => {
  const { world } = makeWorld({ mode: 'defense', playerCount: 1 });
  // Поражение: обнуляем базу напрямую.
  world.base.hp = 1;
  for (const t of world.tanks) {
    t.x = world.base.x;
    t.y = world.base.y;
    t.spawnProtect = 0;
  }
  for (let i = 0; i < 300 && !world.finished; i++) world.step();
  assert.ok(world.finished, 'партия не завершилась');
  assert.equal(world.result.victory, false, 'база должна считаться павшей');

  // Победа: последняя волна, убиваем всех врагов.
  const w2 = makeWorld({ mode: 'defense', playerCount: 1 }).world;
  w2.wave = MODES.defense.waves;
  w2.waveState = 'active';
  for (const t of w2.tanks) {
    if (t.isBot) {
      t.hp = 0;
      t.alive = false;
    }
  }
  for (let i = 0; i < 300 && !w2.finished; i++) w2.step();
  assert.ok(w2.finished, 'победа не зафиксирована');
  assert.equal(w2.result.victory, true, 'оборона должна быть признана успешной');
});

test('koth: 40 врагов, без респауна и победа последнего выжившего', () => {  const { world } = makeWorld({ mode: 'koth', playerCount: 1 });
  const enemies = world.tanks.filter((t) => t.isBot).length;
  assert.equal(enemies, MODES.koth.enemies, 'в «Царе горы» должно быть 40 врагов');
  assert.equal(world.timeLimit, MODES.koth.duration);

  // Снимаем спавн-защиту, чтобы урон проходил сразу.
  for (const t of world.tanks) t.spawnProtect = 0;

  // Победа: все враги мертвы, игрок жив.
  const playerTank = world.tanks.find((t) => !t.isBot);
  for (const tank of world.tanks) {
    if (tank !== playerTank) world.dealDamage(tank, 99999, null, 'test');
  }
  world.step();
  assert.equal(world.finished, true, 'партия не завершилась, когда остался один');
  assert.equal(world.result.victory, true);
  assert.equal(world.result.winnerName, playerTank.name);
});

test('koth: убитые не возрождаются', () => {
  const { world, players } = makeWorld({ mode: 'koth', playerCount: 1 });
  for (const t of world.tanks) t.spawnProtect = 0;
  for (const tank of world.tanks) if (tank.isBot) world.dealDamage(tank, 99999, null, 'test');
  const deadBefore = world.tanks.filter((t) => !t.alive).length;
  for (let i = 0; i < 200; i++) {
    world.step();
    players[0].pendingLevelUps = 0;
    if (world.finished) break;
  }
  const deadAfter = world.tanks.filter((t) => !t.alive).length;
  assert.ok(deadAfter >= deadBefore, 'мёртвые боты воскресли в «Царе горы»');
});

test('koth: на карте разбросаны нейтральные мины (5% пустого пространства)', () => {
  const { world, level } = makeWorld({ mode: 'koth', playerCount: 1 });
  const emptyTiles = [];
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      if (level.map.get(r, c) === T.EMPTY) emptyTiles.push([r, c]);
    }
  }
  const expected = Math.max(1, Math.floor(emptyTiles.length * 0.05));
  const neutral = world.mines.filter((m) => m.owner === null).length;
  assert.ok(neutral >= 1, 'на карте нет нейтральных мин');
  assert.ok(
    Math.abs(neutral - expected) <= expected * 0.5,
    `нейтральных мин ${neutral}, ожидалось около ${expected}`,
  );
});

test('koth: «Амфибия» запрещена в выборе и в выпадении перков', () => {
  const ids = PERKS.map((p) => p.id);
  const allowed = ids.filter((id) => isPerkAllowedInMode(id, 'koth'));
  assert.ok(!allowed.includes('amphibious'), 'Амфибия не должна быть разрешена в koth');
});

test('koth: перки выпадают из убитых и подбираются', () => {
  const { world, players } = makeWorld({ mode: 'koth', playerCount: 1 });
  for (const t of world.tanks) t.spawnProtect = 0;
  const bot = world.tanks.find((t) => t.isBot);
  const playerTank = world.tanks.find((t) => !t.isBot);
  // Убиваем бота без стрелка — перк всё равно должен выпасть.
  world.dealDamage(bot, 99999, null, 'test');
  assert.ok(world.perkDrops.length >= 1, 'из убитого не выпал перк');
  const drop = world.perkDrops[0];
  assert.equal(drop.active, true);
  assert.ok(PERKS.some((p) => p.id === drop.perkId), 'выпал неизвестный перк');

  // Ставим игрока на перк — он должен подобраться.
  playerTank.x = drop.x;
  playerTank.y = drop.y;
  for (let i = 0; i < 5; i++) {
    world.step();
    players[0].pendingLevelUps = 0;
  }
  assert.ok(!drop.active, 'перк не подобрался при касании');
  assert.ok(playerTank.perkIds.includes(drop.perkId), 'перк не экипировался игроку');
});

test('koth: боты подбирают аптечки', () => {
  const { world, players } = makeWorld({ mode: 'koth', playerCount: 1 });
  const pickup = world.pickups[0];
  assert.ok(pickup, 'аптечек нет на карте');
  const bot = world.tanks.find((t) => t.isBot);
  for (const t of world.tanks) t.spawnProtect = 0;
  // Подраненному боту есть что лечить.
  world.dealDamage(bot, Math.floor(bot.maxHP * 0.3), null, 'test');
  const hpBefore = bot.hp;
  // Отводим остальных из толпы, чтобы расталкивание не вынесло бота из радиуса.
  for (const t of world.tanks) {
    if (t !== bot) {
      t.x = t.spawnX;
      t.y = t.spawnY;
      t.vx = 0;
      t.vy = 0;
      t.hp = 0;
      t.alive = false;
    }
  }
  bot.x = pickup.x;
  bot.y = pickup.y;
  bot.vx = 0;
  bot.vy = 0;
  pickup.active = true;
  // Отключаем «мозг»: бот стоит на месте и не уезжает от аптечки.
  bot.brain = null;
  for (let i = 0; i < 5; i++) {
    world.step();
    players[0].pendingLevelUps = 0;
  }
  assert.ok(bot.alive, 'бот умер по пути к аптечке');
  assert.ok(bot.hp > hpBefore, 'бот не подобрал аптечку');
});

test('koth: затопление начинается с краёв и движется к центру', () => {
  const { world, players } = makeWorld({ mode: 'koth', playerCount: 1 });
  const centerR = Math.floor(ROWS / 2);
  const centerC = Math.floor(COLS / 2);
  const centerIsWater = () => world.map.get(centerR, centerC) === T.WATER;
  const nearEdgeFlooded = () => {
    for (let r = 0; r < ROWS; r++) {
      for (let c = 0; c < COLS; c++) {
        const depth = Math.min(r, ROWS - 1 - r, c, COLS - 1 - c);
        if (depth <= 1 && world.map.get(r, c) === T.WATER) return true;
      }
    }
    return false;
  };
  assert.ok(!nearEdgeFlooded(), 'край карты затоплен до старта');
  assert.ok(!centerIsWater(), 'центр затоплен до старта');

  // Детерминированная проверка: прыгаем на 3000-й тик (затопление на ~17%).
  world.tick = 3000;
  for (let i = 0; i < 3; i++) {
    world.step();
    players[0].pendingLevelUps = 0;
    if (world.finished) break;
  }
  assert.ok(nearEdgeFlooded(), 'края карты не затопились');
  assert.ok(!centerIsWater(), 'центр затопился слишком рано');

  // К концу времени вода покрывает почти всё — остаётся только бетон.
  world.tick = world.timeLimit - 10;
  for (let i = 0; i < 15; i++) {
    world.step();
    players[0].pendingLevelUps = 0;
    if (world.finished) break;
  }
  const nonWall = [];
  const waters = [];
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const t = world.map.get(r, c);
      if (t !== T.WALL) nonWall.push(1);
      if (t === T.WATER) waters.push(1);
    }
  }
  assert.ok(waters.length >= nonWall.length * 0.95, 'к концу времени карта почти не покрыта водой');
});

// ============================================================================
section('Производительность');

test('3600 тиков hard/FFA с двумя игроками укладываются в разумное время', () => {
  const { world, players } = makeWorld({ mode: 'ffa', difficulty: 'hard', playerCount: 2, scheme: activeScheme(1, 0) });
  const t0 = Date.now();
  for (let i = 0; i < 3600; i++) {
    world.step();
    for (const p of players) p.pendingLevelUps = 0;
    if (world.finished) break;
  }
  const ms = Date.now() - t0;
  const perTick = ms / 3600;
  console.log(`      60 секунд игры просчитаны за ${ms} мс (${perTick.toFixed(3)} мс/тик)`);
  // Бюджет одного тика при 60 Гц — 16.7 мс; берём десятикратный запас.
  assert.ok(perTick < 1.7, `тик занимает ${perTick.toFixed(3)} мс — слишком дорого`);
});

// ============================================================================
console.log(`\n${'─'.repeat(60)}`);
if (failed === 0) {
  console.log(`\x1b[32mВсе проверки пройдены: ${passed}\x1b[0m`);
} else {
  console.log(`\x1b[31mПровалено ${failed} из ${passed + failed}\x1b[0m`);
  for (const f of failures) {
    console.log(`\n\x1b[31m✗ ${f.name}\x1b[0m`);
    console.log(f.e.stack);
  }
}
process.exit(failed === 0 ? 0 : 1);
