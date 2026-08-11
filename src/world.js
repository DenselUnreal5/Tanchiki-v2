// ============================================================================
// world.js — состояние партии и правила режимов.
//
// World — единственный владелец игрового состояния. Он же отвечает за
// начисление урона и фрагов, поэтому больше нет ситуации из старой версии,
// где убийство второго игрока всегда записывалось первому — независимо от
// того, кто стрелял.
//
// Всё, что нужно показать на экране, World отдаёт событиями. Он ничего не
// знает про DOM.
// ============================================================================

import {
  TILE,
  COLORS,
  MODES,
  DIFFICULTY,
  PLAYER_SPEED,
  PLAYER_FIRE_RATE,
  TANK_W,
  TANK_H,
  RESPAWN_DELAY,
  PICKUP_MIN,
  PICKUP_MAX,
  PICKUP_R,
  PICKUP_HEAL_FRACTION,
  XP_PER_KILL,
  XP_PER_CAPTURE,
  SCORE_PER_KILL,
  SCORE_PER_CAPTURE,
  RAMP_INTERVAL,
  RAMP_STEP,
  RAMP_MAX,
  BOT_MAX_PERKS,
  BOT_PERK_CHANCE,
  MINE_SCATTER_FRACTION,
  SCATTER_MINE_LIFE,
  TICK_HZ,
  T,
  REWARD_KILL,
  REWARD_CAPTURE,
  REWARD_WIN,
  DEFENSE_FIRST_WAVE,
  DEFENSE_LEVEL_BONUS_CAP,
  DEFENSE_PLAYER_LEVEL_BONUS,
  DEFENSE_WAVE_CAP,
  DEFENSE_BOSS_WAVE,
  DEFENSE_RAMP_STEP,
  DEFENSE_PLAYER_HP_MULT,
  DEFENSE_ENEMY_ACCURACY_PENALTY,
  DEFENSE_BASE_REGEN_PER_TICK,
  AIRSTRIKE_DMG,
  AIRSTRIKE_MAX_HP_FRACTION,
  AIRSTRIKE_COOLDOWN,
} from './config.js';
import { Tank } from './tank.js';
import { BotBrain } from './bot.js';
import { ParticleSystem, Pickup, Flag, PerkPickup, Mine, WeaponPickup, StrikeRocket } from './entities.js';
import { BOT_PERKS, PERKS, isPerkAllowedInMode } from './perks.js';
import { pickEnemyType, getEnemyType } from './enemyTypes.js';
import { WEAPONS, getWeapon } from './weapons.js';
import { WeatherSystem } from './weather.js';
import { mulberry32, dist, dist2, pruneInPlace, choice } from './utils.js';

const BOT_NAMES = [
  'Рыжий', 'Серый', 'Чёрный', 'Белый', 'Тигр', 'Ястреб', 'Волк', 'Медведь',
  'Скорпион', 'Пантера', 'Сокол', 'Кобра', 'Шакал', 'Фантом', 'Рейдер',
  'Гром', 'Шторм', 'Клинок', 'Дикий', 'Капитан', 'Барс', 'Кремень',
];

/** Сколько тиков брошенный флаг лежит до автоматического возврата. */
const FLAG_RETURN_TIMEOUT = 15 * TICK_HZ;

export class World {
  /**
   * @param {object} opts
   * @param {import('./map.js').GameMap} opts.map
   * @param {object} opts.level результат generateLevel
   * @param {'ffa'|'ctf'} opts.mode
   * @param {'easy'|'medium'|'hard'} opts.difficulty
   * @param {import('./player.js').Player[]} opts.players
   * @param {import('./audio.js').Audio} opts.audio
   * @param {number} [opts.playerLevel] уровень профиля игрока (влияет на волны «Обороны»)
   * @param {boolean} [opts.noBots] не спавнить ботов вообще (онлайн-PvP)
   */
  constructor({ map, level, mode, difficulty, players, audio, playerLevel = 1, noBots = false }) {
    this.map = map;
    this.level = level;
    this.mode = mode;
    this.difficultyKey = difficulty;
    this.difficulty = DIFFICULTY[difficulty];
    this.players = players;
    this.audio = audio;
    this.playerLevel = playerLevel;
    this.noBots = noBots;
    for (const p of this.players) p.map = map;

    this.rng = mulberry32((Date.now() ^ (level.seed * 2654435761)) >>> 0);

    /** Погода и атмосфера — детерминированы по seed карты. */
    this.weather = new WeatherSystem(level.seed);

    /** @type {Tank[]} */
    this.tanks = [];
    /** @type {import('./entities.js').Bullet[]} */
    this.bullets = [];
    /** @type {import('./entities.js').Mine[]} */
    this.mines = [];
    /** @type {import('./entities.js').PerkPickup[]} выпавшие перки («Царь горы») */
    this.perkDrops = [];
    /** @type {Pickup[]} */
    this.pickups = [];
    /** @type {import('./entities.js').WeaponPickup[]} power-up оружия на карте */
    this.weaponPickups = [];
    /** @type {Flag[]} */
    this.flags = [];
    this.particles = new ParticleSystem();

    this.tick = 0;
    this.ramp = 1;
    this.rampTimer = 0;

    this.teamScore = { player: 0, enemy: 0 };
    this.finished = false;
    /** @type {{victory:boolean, reason:string}|null} */
    this.result = null;

    /** Накопленные за партию монеты (для итогового разбора наград). */
    this.matchRewards = { kills: 0, captures: 0, wins: 0 };

    /** Жив ли сейчас босс — одновременно босс один. */
    this.bossAlive = false;

    /** Оборона: база, номер волны и таймер до следующей волны. */
    this.base = null;
    this.wave = 0;
    this.waveState = 'delay'; // 'delay' — пауза, 'active' — враги на поле
    this.waveTimer = 0;

    /** Авиаудар («Оборона»): тиков до готовности, 0 — доступен. */
    this.airstrikeCooldown = 0;
    /** @type {import('./entities.js').StrikeRocket[]} */
    this.airstrikes = [];

    /** @type {Map<string, Function[]>} */
    this.listeners = new Map();
    this.usedNames = new Set();

    this.#spawnCombatants();
    this.#spawnPickups();
    this.#spawnWeaponPickups();
    this.#spawnFlags();
    if (mode === 'koth') this.#setupKoth();
    if (mode === 'defense') this.#setupDefense();
  }

  // ------------------------------------------------------------------ события
  on(event, fn) {
    if (!this.listeners.has(event)) this.listeners.set(event, []);
    this.listeners.get(event).push(fn);
    return this;
  }

  emit(event, payload) {
    for (const fn of this.listeners.get(event) ?? []) {
      try {
        fn(payload);
      } catch (e) {
        console.error(`[world] обработчик "${event}" упал:`, e);
      }
    }
  }

  // ------------------------------------------------------------------ команды
  /** Враждебность определяется только несовпадением команд. */
  areHostile(a, b) {
    if (!a || !b) return false;
    return a.team !== b.team;
  }

  homeFor(team) {
    if (this.mode !== 'ctf') return null;
    return team === 'player' ? this.level.homes.player : this.level.homes.enemy;
  }

  enemyHomeFor(team) {
    if (this.mode !== 'ctf') return null;
    return team === 'player' ? this.level.homes.enemy : this.level.homes.player;
  }

  /** Зона респауна для команды. */
  areaFor(team) {
    if (this.mode === 'ctf') return team === 'player' ? this.level.areas.player : this.level.areas.enemy;
    if (this.mode === 'defense' && team === 'player') return this.level.areas.player;
    return this.level.areas.any;
  }

  // ------------------------------------------------------------------ создание
  #uniqueBotName(type = null) {
    const free = BOT_NAMES.filter((n) => !this.usedNames.has(n));
    const name = free.length ? choice(this.rng, free) : `Бот-${this.usedNames.size + 1}`;
    this.usedNames.add(name);
    return type?.boss ? `«${name}»` : name;
  }

  #freeSpot(team, w = TANK_W, h = TANK_H) {
    const spot = this.map.findFreeSpot(this.rng, this.areaFor(team), w, h);
    // findFreeSpot имеет линейный резервный поиск, но подстрахуемся центром карты.
    return spot ?? this.map.findFreeSpot(this.rng, this.level.areas.any, w, h) ?? { x: TILE * 4, y: TILE * 4 };
  }

  #spawnCombatants() {
    const diff = this.difficulty;
    const isCtf = this.mode === 'ctf';
    const isDefense = this.mode === 'defense';

    // ---- люди -----------------------------------------------------------
    this.players.forEach((player, i) => {      // В FFA у каждого своя команда, в CTF первый игрок ведёт «player»,
      // второй — «enemy». В «Обороне» все люди на одной стороне.
      const team = isCtf
        ? (i === 0 ? 'player' : 'enemy')
        : isDefense
          ? 'player'
          : `human_${i}`;
      const spot = this.#freeSpot(team);
      const tank = new Tank({
        x: spot.x,
        y: spot.y,
        team,
        name: player.name,
        owner: player,
        // В «Обороне» игрок один против орды — запас прочности выше.
        maxHP: isDefense ? Math.round(diff.playerHP * DEFENSE_PLAYER_HP_MULT) : diff.playerHP,
        speed: PLAYER_SPEED,
        fireRate: PLAYER_FIRE_RATE,
        colorKey: player.colorKey,
        upgradeMods: player.upgradeMods ?? null,
        cosmetics: player.cosmetics ?? null,
      });
      player.tank = tank;
      this.tanks.push(tank);
    });

    // ---- боты -----------------------------------------------------------
    // Онлайн-PvP — без ботов: только люди.
    if (this.noBots) return;

    if (isCtf) {
      const size = MODES.ctf.teamSize;
      // Команда игрока получает на одного бота меньше за каждого живого
      // человека в ней, чтобы составы были равными.
      const humansPlayer = this.players.filter((_, i) => i === 0).length;
      const humansEnemy = this.players.length - humansPlayer;
      this.#spawnBotTeam('player', Math.max(0, size - humansPlayer), 'ally');
      this.#spawnBotTeam('enemy', Math.max(0, size - humansEnemy), 'enemy');
    } else if (this.mode === 'koth') {
      // «Царь горы»: ровно столько врагов, сколько задано в режиме.
      for (let i = 0; i < MODES.koth.enemies; i++) {
        this.#spawnBot(`bot_${i}`, 'enemy');
      }
    } else if (this.mode === 'defense') {
      // «Оборона»: враги приходят волнами, спавним первую сразу.
      this.#setupWave(1);
    } else {
      for (let i = 0; i < diff.enemies; i++) {
        this.#spawnBot(`bot_${i}`, 'enemy');
      }
    }
  }

  #spawnBotTeam(team, count, colorKey) {
    // Союзники в CTF — только рядовые: сбалансированная помощь людям.
    const forced = team === 'player' ? 'grunt' : null;
    for (let i = 0; i < count; i++) this.#spawnBot(team, colorKey, forced);
  }

  /**
   * Создаёт вражеского бота. Тип выбирается по рампе сложности; характеристики
   * танка и параметры «мозга» берутся из типа.
   */
  #spawnBot(team, colorKey, forcedType = null) {
    const diff = this.difficulty;
    let type = pickEnemyType(this.ramp, this.rng, forcedType);
    // Босс на поле боя только один: пока жив — не спавним второго.
    if (type.boss && this.bossAlive) type = getEnemyType('grunt');
    const spot = this.#freeSpot(team);
    const tank = new Tank({
      x: spot.x,
      y: spot.y,
      team,
      name: this.#uniqueBotName(type),
      owner: null,
      maxHP: Math.round(diff.enemyHP * type.hpMult * this.ramp),
      speed: diff.enemySpeed * type.speedMult,
      fireRate: Math.max(4, Math.round(diff.enemyFireRate * type.fireRateMult)),
      colorKey: type.colorKey,
      dmgScale: type.dmgScale,
    });
    tank.enemyType = type;
    if (type.boss) this.bossAlive = true;
    // В «Обороне» враги метят чуть хуже: их много, и перекрёстный огонь
    // из всех стволов убивал защитника ещё до подхода к базе.
    const accBonus = type.accuracyBonus - (this.mode === 'defense' ? DEFENSE_ENEMY_ACCURACY_PENALTY : 0);
    tank.brain = new BotBrain({
      accuracy: Math.min(0.98, diff.enemyAccuracy + accBonus),
      reactTime: Math.round(diff.enemyReactTime * type.reactMult),
      role: type.role,
      fireRange: type.fireRange,
      keepMin: type.keepMin,
      keepMax: type.keepMax,
      lobbed: type.lobbed,
      survival: this.mode === 'koth',
      rng: this.rng,
    });
    if (type.boss) {
      this.particles.burst(tank.x, tank.y, ['#e74c3c', '#ffaa33'], 24, 3, 6, 20, 30, this.rng);
      this.emit('feed', {
        text: `${type.icon} ${tank.name} — БОСС на поле боя!`,
        color: '#e74c3c',
      });
    }
    this.tanks.push(tank);
    return tank;
  }

  #spawnPickups() {
    const count = PICKUP_MIN + Math.floor(this.rng() * (PICKUP_MAX - PICKUP_MIN + 1));
    for (let i = 0; i < count; i++) {
      const spot = this.map.findFreeSpot(this.rng, this.level.areas.any, 16, 16);
      if (spot) this.pickups.push(new Pickup(spot.x, spot.y));
    }
  }

  /** Разбрасывает power-up оружия — по одному каждого типа. */
  #spawnWeaponPickups() {
    for (const id of Object.keys(WEAPONS)) {
      const spot = this.map.findFreeSpot(this.rng, this.level.areas.any, 16, 16);
      if (spot) this.weaponPickups.push(new WeaponPickup(spot.x, spot.y, id));
    }
  }

  #spawnFlags() {
    if (this.mode !== 'ctf') return;
    for (const s of this.level.flagSpots.enemy) this.flags.push(new Flag(s.x, s.y, 'enemy'));
    for (const s of this.level.flagSpots.player) this.flags.push(new Flag(s.x, s.y, 'player'));
  }

  // ------------------------------------------------------- «Оборона»
  /** Подготовка режима: база в центре карты и первая волна. */
  #setupDefense() {
    const home = this.level.homes.player;
    this.base = {
      x: home.x,
      y: home.y,
      maxHP: MODES.defense.baseHP,
      hp: MODES.defense.baseHP,
      radius: MODES.defense.baseRadius,
    };
    // Первая волна выходит через startDelay после старта.
    this.wave = 0;
    this.waveState = 'delay';
    this.waveTimer = MODES.defense.startDelay;
  }

  /**
   * Запускает волну: спавнит врагов и переводит режим в активное состояние.
   * Первая волна — ровно DEFENSE_FIRST_WAVE, каждая следующая — столько же
   * плюс уровень игрока (профиль, не глобальный счётчик). На последней волне
   * гарантированно выходит босс.
   * @param {number} n номер волны (1-based)
   */
  #setupWave(n) {
    this.wave = n;
    this.waveState = 'active';
    const base = DEFENSE_FIRST_WAVE;
    // Рост волн: первая — ровно base, дальше base + вклад уровня игрока
    // (с капом) + небольшой рост от номера волны. Без капа ветеранов
    // заваливало ордой начиная со второй волны.
    const levelBonus = DEFENSE_PLAYER_LEVEL_BONUS
      ? Math.min(DEFENSE_LEVEL_BONUS_CAP, Math.max(0, this.playerLevel - 1))
      : 0;
    const waveGrowth = n === 1 ? 0 : Math.floor((n - 1) / 2);
    const size = Math.min(DEFENSE_WAVE_CAP, base + levelBonus + waveGrowth);
    // Волна сложнее — типы врагов становятся злее.
    this.ramp = Math.min(RAMP_MAX, 1 + (n - 1) * DEFENSE_RAMP_STEP);
    for (let i = 0; i < size; i++) {
      // Вся волна — одна команда «enemy»: враги воюют только с защитниками,
      // а не друг с другом. Раньше у каждого бота была своя уникальная команда
      // (wave{n}_{i}), из-за чего areHostile считала их врагами между собой.
      this.#spawnBot('enemy', 'enemy');
    }
    if (n === DEFENSE_BOSS_WAVE) this.#spawnBoss();
    this.emit('feed', {
      text: `🌊 Волна ${n} из ${MODES.defense.waves}: ${size} врагов`,
      color: '#ff8833',
    });
  }

  /** Гарантированный босс: даже если с ранних волн жив ещё один. */
  #spawnBoss() {
    this.bossAlive = false;
    const tank = this.#spawnBot('enemy', 'enemy', 'boss');
    this.bossAlive = true;
    return tank;
  }

  /** Каждый тик «Оборона»: урон базе и контроль волн. */
  #updateDefense() {
    if (this.finished || !this.base) return;

    // Враги рядом с базой ломают её.
    if (this.base.hp > 0) {
      let attackers = 0;
      for (const tank of this.tanks) {
        if (!tank.alive || !tank.isBot) continue;
        const d2 = dist2(tank.x, tank.y, this.base.x, this.base.y);
        const r = this.base.radius;
        if (d2 <= r * r) attackers++;
      }
      if (attackers > 0) {
        this.base.hp = Math.max(0, this.base.hp - attackers * MODES.defense.baseDPS);
      }
    }

    // Режим проигран — база уничтожена.
    if (this.base.hp <= 0) {
      this.#finish({
        winnerName: 'Орда',
        winnerPlayerIndex: null,
        reason: 'База уничтожена — оборона пала',
      });
      return;
    }

    // В паузе — база лечится (пока её никто не бьёт), потом ждём следующую волну.
    if (this.waveState === 'delay') {
      if (this.#aliveEnemyCount() === 0 && this.base.hp < this.base.maxHP) {
        this.base.hp = Math.min(
          this.base.maxHP,
          this.base.hp + this.base.maxHP * DEFENSE_BASE_REGEN_PER_TICK,
        );
      }
      if (--this.waveTimer <= 0) this.#setupWave(this.wave + 1);
      return;
    }

    // В активной фазе: когда все враги волны мертвы — короткая пауза,
    // а после последней волны — победа.
    if (this.#aliveEnemyCount() === 0) {
      if (this.wave >= MODES.defense.waves) {
        this.#finish({
          winnerName: 'Защитники',
          winnerPlayerIndex: this.players[0]?.index ?? 0,
          winnerTeam: 'player',
          reason: `Все ${MODES.defense.waves} волн отбиты — оборона устояла`,
        });
      } else {
        this.waveState = 'delay';
        this.waveTimer = MODES.defense.waveDelay;
      }
    }
  }

  #aliveEnemyCount() {
    let n = 0;
    for (const tank of this.tanks) {
      if (tank.alive && tank.isBot) n++;
    }
    return n;
  }

  // ------------------------------------------------------------- авиаудар
  /**
   * Супер-способность «Обороны»: на каждого живого врага с неба летит
   * самонаводящаяся ракета (70 + 10% от максимального HP). Только первый
   * игрок, только в этом режиме, перезарядка AIRSTRIKE_COOLDOWN.
   * @param {import('./player.js').Player} player кто вызывает
   * @returns {boolean} удалось ли вызвать
   */
  triggerAirstrike(player) {
    if (this.mode !== 'defense' || this.finished || this.airstrikeCooldown > 0) return false;
    if (!player || player.index !== 0 || !player.tank?.alive) return false;
    const enemies = this.tanks.filter(
      (t) => t.alive && t.isBot && this.areHostile(player.tank, t),
    );
    if (enemies.length === 0) return false;
    for (const target of enemies) {
      this.airstrikes.push(new StrikeRocket(target, player.tank, this));
    }
    this.airstrikeCooldown = AIRSTRIKE_COOLDOWN;
    this.audio.play('airstrike');
    this.emit('feed', { text: `✈ Авиаудар по ${enemies.length} целям!`, color: '#ffaa33' });
    return true;
  }

  #updateAirstrike() {
    for (const r of this.airstrikes) r.update(this);
    pruneInPlace(this.airstrikes, (r) => r.alive);
    if (this.airstrikeCooldown > 0) this.airstrikeCooldown--;
  }

  // ------------------------------------------------------- «Царь горы»
  /** Подготовка режима: мины и карта затопления. */
  #setupKoth() {
    this.timeLimit = MODES.koth.duration;
    // Затопление идёт быстрее лимита партии: floodDuration определяет, за
    // сколько карта полностью уходит под воду.
    this.floodDuration = MODES.koth.floodDuration;
    this.#scatterMines();
    // Дистанция до ближайшего края карты в тайлах — по ней идёт затопление.
    const cols = this.map.cols;
    const rows = this.map.rows;
    this.floodTiles = [];
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const tile = this.map.get(r, c);
        if (tile === T.WALL) continue; // бетон не тонет
        const depth = Math.min(r, rows - 1 - r, c, cols - 1 - c);
        this.floodTiles.push({ r, c, depth });
      }
    }
    this.floodTiles.sort((a, b) => a.depth - b.depth);
    this.floodIdx = 0;
    this.maxFloodDepth = Math.floor(Math.min(rows, cols) / 2);
    this.floodLevel = 0;
  }

  /** Мины на 5% пустой площади карты, подальше от точек спавна. */
  #scatterMines() {
    const cols = this.map.cols;
    const rows = this.map.rows;
    const empty = [];
    for (let r = 2; r < rows - 2; r++) {
      for (let c = 2; c < cols - 2; c++) {
        if (this.map.get(r, c) === T.EMPTY) empty.push([r, c]);
      }
    }
    const count = Math.max(1, Math.floor(empty.length * MINE_SCATTER_FRACTION));
    // Частичный Фишер-Йетс: первые count позиций — случайные.
    for (let i = 0; i < count; i++) {
      const j = Math.floor(this.rng() * empty.length);
      [empty[i], empty[j]] = [empty[j], empty[i]];
    }
    let placed = 0;
    for (let i = 0; i < empty.length && placed < count; i++) {
      const [r, c] = empty[i];
      const x = c * TILE + TILE / 2;
      const y = r * TILE + TILE / 2;
      // Не класть мины впритык к танкам — чтобы не взрываться на респауне.
      let nearTank = false;
      for (const t of this.tanks) {
        if (t.alive && dist(t.x, t.y, x, y) < TILE * 2) {
          nearTank = true;
          break;
        }
      }
      if (nearTank) continue;
      this.mines.push(new Mine(x, y, null, SCATTER_MINE_LIFE));
      placed++;
    }
  }

  /** Медленно заливает карту водой от краёв к центру. */
  #updateFlood() {
    this.floodLevel = (this.tick / this.floodDuration) * this.maxFloodDepth;
    while (this.floodIdx < this.floodTiles.length) {
      const tile = this.floodTiles[this.floodIdx];
      if (tile.depth > this.floodLevel) break;
      if (this.map.get(tile.r, tile.c) !== T.WATER) this.map.set(tile.r, tile.c, T.WATER);
      this.floodIdx++;
    }
  }

  /** Обновляет выпавшие перки и проверяет их подбор. */
  #updatePerkDrops() {
    for (const drop of this.perkDrops) {
      drop.update();
      if (!drop.active) continue;
      for (const tank of this.tanks) {
        if (!tank.alive) continue;
        if (dist(tank.x, tank.y, drop.x, drop.y) > 26) continue;
        const perk = PERKS.find((p) => p.id === drop.perkId);
        if (!perk) continue;
        if (tank.owner) {
          tank.owner.equipPerk(drop.perkId);
          this.audio.play('pickup');
          this.emit('damageNumber', { x: tank.x, y: tank.y - 26, text: perk.icon, color: '#ff88ff' });
          this.emit('feed', { text: `${tank.name} подобрал перк ${perk.icon} ${perk.name}`, color: '#ff88ff' });
        } else {
          // Бот тоже подбирает, пока не упрётся в лимит перков.
          if (tank.perkIds.length < BOT_MAX_PERKS && !tank.perkIds.includes(drop.perkId)) {
            tank.perkIds.push(drop.perkId);
            tank.recompute();
            this.emit('feed', { text: `${tank.name} подобрал перк ${perk.icon} ${perk.name}`, color: '#ffaa44' });
          }
        }
        drop.active = false;
        break;
      }
    }
    pruneInPlace(this.perkDrops, (d) => d.active);
  }

  // ------------------------------------------------------------------ шаг
  step() {
    if (this.finished) return;
    this.tick++;
    this.audio.advance();
    this.weather.update();
    if (this.mode === 'koth') this.#updateFlood();

    for (const tank of this.tanks) tank.update(this);
    this.#separateTanks();

    for (const b of this.bullets) b.update(this);
    pruneInPlace(this.bullets, (b) => b.alive);

    for (const m of this.mines) m.update(this);
    pruneInPlace(this.mines, (m) => m.alive);

    if (this.mode === 'defense') this.#updateAirstrike();

    this.particles.update();

    if (this.mode === 'ctf') this.#updateFlags();
    this.#updatePickups();
    this.#updateWeaponPickups();
    if (this.mode === 'koth') this.#updatePerkDrops();
    if (this.mode === 'defense') this.#updateDefense();
    this.#updateRespawns();
    this.#updateRamp();

    for (const p of this.players) {
      p.tick();
      p.updateCamera();
    }

    if (!this.finished) this.#checkVictory();
  }

  /** Мягкое расталкивание: без него боты слипаются в кучу в узких проходах. */
  #separateTanks() {
    const list = this.tanks;
    for (let i = 0; i < list.length; i++) {
      const a = list[i];
      if (!a.alive) continue;
      for (let j = i + 1; j < list.length; j++) {
        const b = list[j];
        if (!b.alive) continue;
        if (dist2(a.x, a.y, b.x, b.y) > 32 * 32) continue;
        a.separateFrom(b);
      }
    }
  }

  #updateRamp() {
    if (++this.rampTimer < RAMP_INTERVAL) return;
    this.rampTimer = 0;
    if (this.ramp >= RAMP_MAX) return;
    this.ramp = Math.min(RAMP_MAX, this.ramp + RAMP_STEP);
    for (const tank of this.tanks) {
      if (!tank.isBot) continue;
      // Меняем БАЗОВУЮ характеристику и пересчитываем — иначе бонус затёрся бы
      // при следующем пересчёте перков. Множитель типа врага сохраняется.
      const hpMult = tank.enemyType?.hpMult ?? 1;
      tank.baseMaxHP = Math.round(this.difficulty.enemyHP * hpMult * this.ramp);
      tank.recompute();
    }
    this.emit('feed', { text: 'Враги стали сильнее!', color: '#ff8833' });
  }

  // ------------------------------------------------------------------ урон
  /**
   * Единая точка нанесения урона. Здесь же — вся атрибуция.
   * @param {Tank} target
   * @param {number} amount
   * @param {Tank|null} attacker
   * @param {'bullet'|'ram'|'mine'|'water'|'kamikaze'|'reflect'|'airstrike'} source
   */
  dealDamage(target, amount, attacker, source) {
    if (!target.alive || amount <= 0) return 0;
    // «Берсерк»: пока HP атакующего ≤ 40%, его урон увеличен.
    if (attacker && attacker.alive && attacker.flags.has('berserk')) {
      const ratio = attacker.maxHP > 0 ? attacker.hp / attacker.maxHP : 0;
      if (ratio <= 0.4) amount *= 1.6;
    }
    const res = target.takeDamage(this, amount, attacker, source);
    if (res.evaded || res.applied <= 0) return 0;

    target.lastAttacker = attacker;
    target.lastAttackerTick = this.tick;

    // Обратный урон от «Отражения» — до проверки смерти, чтобы взаимное
    // уничтожение работало предсказуемо.
    if (res.reflected > 0 && attacker && attacker.alive) {
      this.dealDamage(attacker, res.reflected, target, 'reflect');
    }

    // Учёт нанесённого урона и вампиризм.
    if (attacker) {
      attacker.damageDealt += res.applied;
      if (attacker.owner) {
        attacker.owner.damageDealt += res.applied;
        this.emit('playerDamage', { player: attacker.owner, amount: res.applied });
      }
      if (attacker.mods.lifestealFraction > 0 && attacker.alive) {
        const heal = Math.floor(res.applied * attacker.mods.lifestealFraction);
        if (heal > 0) attacker.hp = Math.min(attacker.maxHP, attacker.hp + heal);
      }
    }

    // Обратная связь: цифры урона и вспышка только у пострадавшего игрока.
    this.emit('damageNumber', {
      x: target.x,
      y: target.y - 20,
      text: `-${Math.round(res.applied)}`,
      color: target.owner ? '#ff4444' : '#ffee55',
    });
    if (target.owner) {
      target.owner.damageFlash = 12;
      target.owner.shake = Math.max(target.owner.shake, 5);
      target.owner.cleanStreak = 0;
      this.audio.play('hit');
    }

    if (res.killed) this.#killTank(target, attacker, source);
    return res.applied;
  }

  #killTank(victim, killer, source) {
    victim.onDeath(this, killer);
    victim.respawnTimer = RESPAWN_DELAY;

    // Босс убит — можно снова спавнить нового.
    if (victim.enemyType?.boss) this.bossAlive = false;

    // «Царь горы»: убитый роняет случайный перк.
    if (this.mode === 'koth') this.#dropPerk(victim);

    // Флаг выпадает на месте гибели.
    if (victim.flag) {
      const flag = victim.flag;
      victim.flag = null;
      flag.drop(victim.x, victim.y, FLAG_RETURN_TIMEOUT);
      this.emit('flag', { type: 'dropped', flag, tank: victim });
    }

    // ---- начисление фрага ----------------------------------------------
    const suicide = !killer || killer === victim;
    if (!suicide && this.areHostile(killer, victim)) {
      killer.kills++;
      if (killer.owner) this.#creditPlayerKill(killer.owner, victim, source);
      else if (killer.isBot) this.#maybeGiveBotPerk(killer);
    }

    if (victim.owner) {
      victim.owner.deaths++;
      victim.owner.cleanStreak = 0;
      this.emit('playerDied', { player: victim.owner, killer });
    }

    this.emit('kill', {
      victim,
      killer: suicide ? null : killer,
      source,
      suicide,
    });
  }

  #creditPlayerKill(player, victim, source) {
    player.kills++;
    player.score += SCORE_PER_KILL;
    this.matchRewards.kills += REWARD_KILL;
    this.emit('reward', { kind: 'kill', amount: REWARD_KILL, name: player.name });

    const levels = player.addXP(XP_PER_KILL);
    if (levels > 0) this.emit('sessionLevelUp', { player, levels });
    this.emit('globalXP', { amount: XP_PER_KILL, player });

    // Бонус за босса: щедрый куш в монетах и XP.
    if (victim.enemyType?.boss) {
      const bossReward = REWARD_KILL * 5;
      this.matchRewards.kills += bossReward;
      this.emit('reward', { kind: 'boss', amount: bossReward, name: player.name });
      this.emit('globalXP', { amount: XP_PER_KILL * 3, player });
      player.score += SCORE_PER_KILL * 3;
      this.emit('feed', {
        text: `${player.name} уничтожил БОССА! +${bossReward} 🪙`,
        color: '#e74c3c',
      });
    }

    // Челлендж «убей 5 врагов за 10 секунд».
    player.killTicks.push(this.tick);
    const cutoff = this.tick - 10 * TICK_HZ;
    while (player.killTicks.length && player.killTicks[0] < cutoff) player.killTicks.shift();
    this.emit('stat', { key: 'rapidKills', value: player.killTicks.length, mode: 'max' });

    // Серия без полученного урона.
    player.cleanStreak++;
    this.emit('stat', { key: 'cleanStreak', value: player.cleanStreak, mode: 'max' });
    this.emit('stat', { key: 'totalKills', value: 1, mode: 'add' });

    if (source === 'ram') this.emit('stat', { key: 'ramKills', value: 1, mode: 'add' });

    // Челленджи «Снайпер» и «Берсерк».
    const killerTank = player.tank;
    if (killerTank) {
      const killDist = dist(killerTank.x, killerTank.y, victim.x, victim.y);
      if (killDist >= 400) this.emit('stat', { key: 'longKills', value: 1, mode: 'add' });
      if (killerTank.maxHP > 0 && killerTank.hp / killerTank.maxHP <= 0.4) {
        this.emit('stat', { key: 'lowHpKills', value: 1, mode: 'add' });
      }
    }

    // Перки «Турбо» и «Тень» — теперь на конкретном танке, а не в глобалах.
    const tank = player.tank;
    if (tank) {
      if (tank.mods.turboOnKill > 0) tank.turboTimer = tank.mods.turboOnKill;
      if (tank.mods.shadowOnKill > 0) tank.shadowTimer = tank.mods.shadowOnKill;
    }
  }

  #maybeGiveBotPerk(bot) {
    if (bot.perkIds.length >= BOT_MAX_PERKS) return;
    if (this.rng() >= BOT_PERK_CHANCE) return;
    const available = BOT_PERKS.filter((p) => !bot.perkIds.includes(p.id));
    if (!available.length) return;
    const perk = choice(this.rng, available);
    bot.perkIds.push(perk.id);
    bot.recompute();
    this.particles.burst(bot.x, bot.y - 20, ['#ffee55', '#ffffaa'], 8, 2, 4, 15, 20, this.rng);
    this.emit('botPerk', { tank: bot, perk });
  }

  /** Роняет перк на месте гибели — только перки, разрешённые в режиме. */
  #dropPerk(victim) {
    const allowed = PERKS.filter((p) => isPerkAllowedInMode(p.id, this.mode));
    if (!allowed.length) return;
    const perk = choice(this.rng, allowed);
    this.perkDrops.push(new PerkPickup(victim.x, victim.y, perk.id));
    this.particles.burst(victim.x, victim.y, ['#ff88ff', '#ffffff'], 8, 2, 4, 12, 18, this.rng);
  }

  // ------------------------------------------------------------- крючки из entities
  onBrickDestroyed(owner) {
    if (owner?.owner) this.emit('stat', { key: 'bricksDestroyed', value: 1, mode: 'add' });
  }

  onTreesDriven(tank, count) {
    if (tank.owner) this.emit('stat', { key: 'treesDriven', value: count, mode: 'add' });
  }

  onWaterEntered(tank) {
    if (tank.owner) this.emit('stat', { key: 'waterEntries', value: 1, mode: 'add' });
  }

  /** Тряска добавляется каждому игроку, который видит точку взрыва. */
  addShake(amount, x, y) {
    for (const p of this.players) {
      if (x === undefined || dist(p.camera.x, p.camera.y, x, y) < 700) {
        p.shake = Math.max(p.shake, amount);
      }
    }
  }

  // ------------------------------------------------------------------ аптечки
  #updatePickups() {
    // В «Царе горы» аптечки подбирают и боты, в остальных режимах — только люди.
    const candidates = [];
    for (const player of this.players) {
      if (player.tank?.alive) candidates.push(player.tank);
    }
    if (this.mode === 'koth') {
      for (const tank of this.tanks) {
        if (tank.isBot && tank.alive) candidates.push(tank);
      }
    }

    for (const pickup of this.pickups) {
      if (!pickup.active) {
        if (--pickup.respawnTimer <= 0) {
          const spot = this.map.findFreeSpot(this.rng, this.level.areas.any, 16, 16);
          if (spot) {
            pickup.x = spot.x;
            pickup.y = spot.y;
          }
          pickup.active = true;
        }
        continue;
      }
      for (const tank of candidates) {
        const radius = tank.owner ? tank.owner.pickupRadius : PICKUP_R;
        if (dist(tank.x, tank.y, pickup.x, pickup.y) > radius) continue;
        const heal = Math.max(1, Math.floor(tank.maxHP * PICKUP_HEAL_FRACTION));
        const before = tank.hp;
        tank.hp = Math.min(tank.maxHP, tank.hp + heal);
        const gained = Math.round(tank.hp - before);
        pickup.consume();
        this.audio.play('pickup');
        this.emit('damageNumber', { x: tank.x, y: tank.y - 24, text: `+${gained}`, color: '#44ff44' });
        if (tank.owner) {
          this.emit('feed', { text: `${tank.owner.name}: аптечка +${gained} HP`, color: '#44ff44' });
          this.emit('stat', { key: 'healthPacksCollected', value: 1, mode: 'add' });
        } else {
          this.emit('feed', { text: `${tank.name}: аптечка +${gained} HP`, color: '#44ff44' });
        }
        break;
      }
    }
  }

  // ------------------------------------------------------------------ power-up оружия
  /** Обновляет оружие на карте: подбор людьми, таймеры исчезновения. */
  #updateWeaponPickups() {
    for (const pickup of this.weaponPickups) {
      if (!pickup.active) continue;
      pickup.update();
      if (!pickup.active) continue;
      for (const tank of this.tanks) {
        if (!tank.alive || !tank.owner) continue;
        const radius = tank.owner.pickupRadius || PICKUP_R;
        if (dist(tank.x, tank.y, pickup.x, pickup.y) > radius) continue;
        const weapon = getWeapon(pickup.weaponId);
        if (!weapon) continue;
        tank.weapon = weapon.id;
        tank.weaponTimer = weapon.duration;
        pickup.active = false;
        this.audio.play('pickup');
        this.particles.burst(tank.x, tank.y, [weapon.color, '#ffffff'], 10, 2, 4, 14, 22, this.rng);
        this.emit('damageNumber', { x: tank.x, y: tank.y - 26, text: `${weapon.icon} ${weapon.name}!`, color: weapon.color });
        this.emit('feed', { text: `${tank.owner.name}: ${weapon.icon} ${weapon.name}!`, color: weapon.color });
        break;
      }
    }
    pruneInPlace(this.weaponPickups, (p) => p.active);
  }

  // ------------------------------------------------------------------ флаги
  #updateFlags() {
    // 1. Подбор и возврат при касании.
    for (const flag of this.flags) {
      if (flag.carried) continue;
      for (const tank of this.tanks) {
        if (!tank.alive) continue;
        if (dist(tank.x, tank.y, flag.x, flag.y) > 24) continue;

        if (flag.team === tank.team) {
          // Свой флаг: если он не дома — возвращаем касанием.
          if (!flag.atHome) {
            flag.returnHome();
            this.audio.play('flag');
            this.emit('flag', { type: 'returned', flag, tank });
            this.emit('feed', {
              text: `${tank.name} вернул свой флаг`,
              color: flag.team === 'player' ? COLORS.flagPlayer : COLORS.flagEnemy,
            });
          }
        } else if (!tank.carryingFlag) {
          flag.pickUp(tank);
          tank.flag = flag;
          this.audio.play('flag');
          this.emit('flag', { type: 'taken', flag, tank });
          this.emit('feed', {
            text: `${tank.name} забрал флаг`,
            color: tank.owner ? '#ffee55' : '#ff8833',
          });
        }
        break;
      }
    }

    // 2. Флаг едет вместе с носителем.
    for (const flag of this.flags) {
      if (flag.carrier) {
        if (!flag.carrier.alive) {
          // Страховка: носитель умер вне #killTank.
          const carrier = flag.carrier;
          carrier.flag = null;
          flag.drop(carrier.x, carrier.y, FLAG_RETURN_TIMEOUT);
          continue;
        }
        flag.x = flag.carrier.x;
        flag.y = flag.carrier.y;
      } else if (flag.state === 'dropped') {
        // Брошенный флаг сам возвращается домой по таймеру.
        if (--flag.returnTimer <= 0) {
          flag.returnHome();
          this.emit('flag', { type: 'returned', flag, tank: null });
        }
      }
    }

    // 3. Захват: носитель доехал до своей базы.
    for (const flag of this.flags) {
      const carrier = flag.carrier;
      if (!carrier || !carrier.alive) continue;
      const home = this.homeFor(carrier.team);
      if (!home || dist(carrier.x, carrier.y, home.x, home.y) > 40) continue;

      const team = carrier.team;
      this.teamScore[team] = (this.teamScore[team] ?? 0) + 1;
      carrier.flag = null;
      flag.returnHome();

      if (carrier.owner) {
        const player = carrier.owner;
        player.captures++;
        player.score += SCORE_PER_CAPTURE;
        const levels = player.addXP(XP_PER_CAPTURE);
        if (levels > 0) this.emit('sessionLevelUp', { player, levels });
        this.emit('globalXP', { amount: XP_PER_CAPTURE, player });
        this.matchRewards.captures += REWARD_CAPTURE;
        this.emit('reward', { kind: 'capture', amount: REWARD_CAPTURE, name: player.name });
      }

      this.audio.play('flag');
      this.particles.burst(
        home.x,
        home.y,
        ['#ffee55', '#44ff44', '#4488ff', '#ff44ff'],
        50,
        3,
        7,
        30,
        60,
        this.rng,
      );
      this.emit('flag', { type: 'captured', flag, tank: carrier });
      this.emit('feed', {
        text: `${carrier.name} захватил флаг! ${this.teamScore.player}:${this.teamScore.enemy}`,
        color: '#ffee55',
      });
      break; // за тик засчитываем один захват — иначе можно «сдвоить» победу
    }
  }

  // ------------------------------------------------------------------ респаун
  #updateRespawns() {
    // «Царь горы»: без возрождения — побеждает последний выживший.
    if (this.mode === 'koth') return;
    for (const tank of this.tanks) {
      if (tank.alive) continue;
      // «Оборона»: враги волн не возрождаются, люди — да.
      if (this.mode === 'defense' && tank.isBot) continue;
      if (--tank.respawnTimer > 0) continue;
      const spot = this.#freeSpot(tank.team);
      tank.respawn(spot.x, spot.y);
      if (tank.enemyType?.boss) this.bossAlive = true;
      if (tank.owner) {
        tank.owner.updateCamera();
        this.emit('respawn', { player: tank.owner });
      }
    }
  }

  // ------------------------------------------------------------------ победа
  #checkVictory() {
    // «Оборона»: победу и поражение считает #updateDefense.
    if (this.mode === 'defense') return;

    // «Царь горы»: побеждает последний выживший. Время истекло — сильнейший.
    if (this.mode === 'koth') {
      const alive = [];
      for (const t of this.tanks) if (t.alive) alive.push(t);

      // Игроков-людей больше нет — партия окончена (поражение).
      const humansLeft = this.players.some((p) => p.tank?.alive);
      if (!humansLeft) {
        this.#finish({
          winnerName: alive.length ? alive[0].name : 'Никто',
          winnerPlayerIndex: null,
          reason: 'Все игроки уничтожены',
        });
        return;
      }

      if (alive.length === 1) {
        const winner = alive[0];
        this.#finish({
          winnerName: winner.name,
          winnerPlayerIndex: winner.owner ? winner.owner.index : null,
          reason: `${winner.name} остался последним`,
        });
        return;
      }

      // Тайм-аут: доели — побеждает тот, кто нанёс больше урона.
      if (this.tick >= this.timeLimit) {
        let best = alive[0];
        for (const t of alive) if (t.damageDealt > best.damageDealt) best = t;
        this.#finish({
          winnerName: best.name,
          winnerPlayerIndex: best.owner ? best.owner.index : null,
          reason: 'Время вышло — побеждает сильнейший',
        });
      }
      return;
    }

    if (this.mode === 'ffa') {
      const limit = MODES.ffa.fragLimit;
      let leader = null;
      for (const tank of this.tanks) {
        if (tank.kills >= limit && (!leader || tank.kills > leader.kills)) leader = tank;
      }
      if (!leader) return;
      this.#finish({
        winnerName: leader.name,
        winnerPlayerIndex: leader.owner ? leader.owner.index : null,
        reason: `${leader.name} первым набрал ${leader.kills} фрагов`,
      });
      return;
    }

    const limit = MODES.ctf.capLimit;
    const team = this.teamScore.player >= limit ? 'player' : this.teamScore.enemy >= limit ? 'enemy' : null;
    if (!team) return;
    const winnerHuman = this.players.find((p) => p.tank?.team === team);
    this.#finish({
      winnerName: team === 'player' ? 'Команда «Свои»' : 'Команда «Враги»',
      winnerPlayerIndex: winnerHuman ? winnerHuman.index : null,
      winnerTeam: team,
      reason: `${team === 'player' ? 'Свои' : 'Враги'} захватили ${limit} флагов`,
    });
  }

  /**
   * Завершает партию.
   * victory считается от лица первого игрока, но в результате есть и явный
   * победитель — «горячему стулу» нужно показывать, кто именно выиграл.
   */
  #finish({ winnerName, winnerPlayerIndex, winnerTeam = null, reason }) {
    this.finished = true;
    const victory = winnerPlayerIndex === 0;
    if (victory) {
      this.matchRewards.wins += REWARD_WIN;
      this.emit('reward', { kind: 'win', amount: REWARD_WIN, name: winnerName });
    }
    this.result = {
      victory,
      winnerName,
      winnerPlayerIndex,
      winnerTeam,
      reason,
      rewards: { ...this.matchRewards },
    };
    this.emit('finish', this.result);
  }

  // ------------------------------------------------------------------ табло
  /** Данные для таблицы результатов, отсортированные по фрагам. */
  scoreboard() {
    const rows = this.tanks.map((tank) => ({
      name: tank.name,
      kills: tank.kills,
      deaths: tank.deaths,
      team: tank.team,
      colorKey: tank.colorKey,
      isHuman: tank.owner !== null,
      alive: tank.alive,
      perks: tank.perkIds.slice(),
    }));
    rows.sort((a, b) => b.kills - a.kills || a.deaths - b.deaths);
    return rows;
  }

  aliveEnemiesFor(team) {
    let n = 0;
    for (const t of this.tanks) if (t.alive && t.team !== team) n++;
    return n;
  }

  /** Множитель прогресса режима (для полосок в HUD). */
  progressFor(player) {
    if (this.mode === 'koth') {
      const alive = this.tanks.reduce((n, t) => n + (t.alive ? 1 : 0), 0);
      return { current: alive, target: 1, total: this.tanks.length };
    }
    if (this.mode === 'defense') {
      const left = this.#aliveEnemyCount();
      return { current: left, target: 0, total: MODES.defense.waves, wave: this.wave };
    }
    if (this.mode === 'ffa') {
      return { current: player.kills, target: MODES.ffa.fragLimit };
    }
    const team = player.tank?.team ?? 'player';
    return { current: this.teamScore[team] ?? 0, target: MODES.ctf.capLimit };
  }
}
