// ============================================================================
// src/net.js — онлайн-PvP клиент.
//
// Тонкий клиент: сервер крутит настоящий World, а здесь строится «зеркальный»
// мир — объект с теми же полями, которые читает Renderer и HUD, но заполненный
// из снапшотов. Локальная симуляция не запускается.
//
// Протокол см. в server/game.js.
// ============================================================================

import { GameMap } from './map.js';
import { WeatherSystem } from './weather.js';
import { ParticleSystem } from './entities.js';
import { MODES } from './config.js';
import { t } from './i18n.js';

/**
 * @param {object} opts
 * @param {(world: object, player: import('./player.js').Player) => void} opts.onReady
 * @param {(text: string, color: string) => void} opts.onFeed
 * @param {(result: object) => void} opts.onFinish
 * @param {(msg: string) => void} opts.onError
 */
export function connectOnline(url, opts) {
  return new OnlineMatch(url, opts);
}

export class OnlineMatch {
  constructor(url, { onReady, onFeed, onFinish, onError, onDamageNumber }) {
    this.url = url;
    this.onReady = onReady;
    this.onFeed = onFeed;
    this.onFinish = onFinish;
    this.onError = onError;
    this.onDamageNumber = onDamageNumber;

    /** Зеркальный мир. */
    this.world = null;
    /** Локальный игрок (viewport/camera/HUD). */
    this.player = null;
    this.ready = false;

    this.ws = new WebSocket(url);
    this.ws.onopen = () => this.#send({ t: 'hello', name: t('net.player', null, 'Игрок') });
    this.ws.onmessage = (e) => this.#handleMessage(e.data);
    this.ws.onerror = () => onError?.(t('net.lost', null, 'Соединение потеряно'));
    this.ws.onclose = () => {
      if (!this.ready) onError?.(t('net.unreachable', { url }, `Сервер недоступен: ${url}`));
    };
  }

  get connected() {
    return this.ws.readyState === WebSocket.OPEN;
  }

  #send(obj) {
    if (this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(obj));
  }

  /** Отправляет команду управления (собирается схемой локального игрока). */
  sendCommand(cmd) {
    this.#send({ t: 'cmd', ...cmd });
  }

  #handleMessage(text) {
    let msg;
    try {
      msg = JSON.parse(text);
    } catch {
      return;
    }
    switch (msg.t) {
      case 'init':
        this.#onInit(msg);
        break;
      case 'snap':
        if (this.world) this.#applySnapshot(msg);
        break;
      case 'feed':
        this.onFeed?.(msg.text, msg.color);
        break;
      case 'kill':
        this.onFeed?.(msg.text, msg.color);
        break;
      case 'damageNumber':
        this.onDamageNumber?.(msg);
        break;
      case 'finish':
        this.onFinish?.(msg.result);
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------- инициализация
  #onInit(msg) {
    this.world = buildMirrorWorld(msg);
    this.localIndex = msg.index;
    this.world.localIndex = msg.index;

    // Рендеру нужен player.tank и его owner. Ставим локальный танк сразу.
    const myTank = this.world.tanks.find((t) => t.ownerIndex === msg.index) ?? null;
    this.player = {
      index: msg.index,
      name: msg.myName ?? t('net.you', null, 'Вы'),
      tank: myTank,
    };
    this.ready = true;
    this.onReady?.(this.world, this.player);
  }

  // ---------------------------------------------------------------- снапшоты
  #applySnapshot(snap) {
    const w = this.world;
    w.tick = snap.tick;
    w.mode = snap.mode;
    w.teamScore = snap.teamScore ?? w.teamScore;
    w.result = snap.result ?? null;
    w.finished = !!snap.result;

    // Танки: переиспользуем зеркальные объекты по id, чтобы player.tank
    // и сравнения по ссылке в рендерере продолжали работать.
    const byId = new Map(w.tanks.map((t) => [t.id, t]));
    const tanks = [];
    for (const s of snap.tanks) {
      let t = byId.get(s.id);
      if (!t) {
        t = {
          id: s.id,
          width: 34,
          height: 34,
          isBot: s.isBot,
          owner: null,
          carryingFlag: false,
        };
      }
      applyTankSnapshot(t, s);
      tanks.push(t);
    }
    w.tanks = tanks;

    // Локальный танк.
    const myTank = tanks.find((t) => t.ownerIndex === this.localIndex) ?? null;
    if (myTank) {
      this.player.tank = myTank;
      // Статистика владельца на экран результатов.
      this.player.kills = myTank.kills;
      this.player.deaths = myTank.deaths;
      this.player.captures = myTank.captures ?? 0;
      this.player.score = myTank.score ?? 0;
      this.player.damageDealt = myTank.damageDealt ?? 0;
      this.player.sessionLevel = myTank.sessionLevel ?? 1;
      this.player.perkIds = myTank.perkIds ?? [];
    }

    w.bullets = snap.bullets.map((b) => ({ ...b }));
    w.mines = snap.mines.map((m) => ({ ...m }));
    w.pickups = snap.pickups.map((p) => ({ ...p }));
    w.weaponPickups = snap.weaponPickups.map((p) => ({ ...p }));
    w.perkDrops = snap.perkDrops.map((d) => ({ ...d }));
    w.flags = snap.flags.map((f) => ({ ...f }));
    w.airstrikes = (snap.airstrikes ?? []).map((r) => ({ ...r }));
    if (snap.base) {
      w.base = { ...w.base, ...snap.base };
    }

    // Погода: сервер шлёт текущее состояние, клиент просто подставляет.
    if (snap.weather) applyWeatherSnapshot(w.weather, snap.weather);
  }
}

// ---------------------------------------------------------------- зеркальный мир
/**
 * Строит зеркальный мир по сообщению init. Содержит ровно те поля,
 * которые читают Renderer и HUD. Никакой симуляции.
 */
function buildMirrorWorld(msg) {
  const map = new GameMap(msg.map.cols, msg.map.rows);
  map.tiles = Uint8Array.from(msg.map.tiles);
  map.version = msg.map.version ?? 1;

  const weather = new WeatherSystem(msg.seed ?? 1);
  if (msg.weather) applyWeatherSnapshot(weather, msg.weather);

  const world = {
    map,
    tick: 0,
    mode: msg.mode,
    difficultyKey: msg.difficulty,
    teamScore: { player: 0, enemy: 0 },
    base: null,
    waveState: 'delay',
    wave: 0,
    airstrikeCooldown: 0,
    timeLimit: MODES.koth?.duration ?? 0,
    tanks: [],
    bullets: [],
    mines: [],
    pickups: [],
    weaponPickups: [],
    perkDrops: [],
    flags: [],
    airstrikes: [],
    particles: new ParticleSystem(),
    weather,
    result: null,
    finished: false,
    /** Минимальный RNG для тряски экрана (world.rng() в рендерере). */
    rng: Math.random,
    areHostile: (a, b) => !a || !b ? false : a.team !== b.team,
    progressFor: (player) => {
      if (msg.mode === 'ffa') return { current: player.kills, target: MODES.ffa.fragLimit };
      if (msg.mode === 'ctf') {
        const team = player.tank?.team ?? 'player';
        return { current: world.teamScore[team] ?? 0, target: MODES.ctf.capLimit };
      }
      return { current: 0, target: 1 };
    },
    scoreboard: () =>
      world.tanks
        .map((t) => ({
          name: t.name,
          kills: t.kills,
          deaths: t.deaths,
          team: t.team,
          colorKey: t.colorKey,
          isHuman: t.ownerIndex !== null,
          alive: t.alive,
          perks: t.perkIds?.slice() ?? [],
        }))
        .sort((a, b) => b.kills - a.kills || a.deaths - b.deaths),
  };

  // Локальный игрок создаётся game.js и передаётся через onReady.
  return world;
}

/** Копирует поля танка из снапшота в зеркальный объект. */
function applyTankSnapshot(t, s) {
  t.id = s.id;
  t.name = s.name;
  t.team = s.team;
  t.colorKey = s.colorKey;
  t.ownerIndex = s.ownerIndex ?? null;
  t.x = s.x;
  t.y = s.y;
  t.vx = s.vx;
  t.vy = s.vy;
  t.angle = s.angle;
  t.bodyAngle = s.bodyAngle;
  t.turretAngle = s.turretAngle;
  t.hp = s.hp;
  t.maxHP = s.maxHP;
  t.alive = s.alive;
  t.spawnProtect = s.spawnProtect;
  t.shieldHP = s.shieldHP;
  t.turboTimer = s.turboTimer;
  t.shadowTimer = s.shadowTimer ?? 0;
  t.weapon = s.weapon;
  t.weaponTimer = s.weaponTimer;
  t.perkIds = s.perkIds ?? [];
  t.cosmetics = s.cosmetics ?? null;
  t.kills = s.kills;
  t.deaths = s.deaths;
  t.captures = s.captures ?? 0;
  t.score = s.score ?? 0;
  t.damageDealt = s.damageDealt ?? 0;
  t.sessionLevel = s.sessionLevel ?? 1;
  t.flag = s.flag ? { team: s.flag.team } : null;
  t.carryingFlag = t.flag !== null;
  t.isPlayerControlled = s.ownerIndex !== null;
  t.isBot = !!s.isBot;
}

/** Копирует состояние погоды из снапшота. */
function applyWeatherSnapshot(weather, s) {
  weather.condition = s.condition;
  weather.rain = s.rain;
  weather.fog = s.fog;
  weather.flash = s.flash;
  weather.cycleTicks = s.cycleTicks;
}
