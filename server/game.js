// ============================================================================
// server/game.js — игровой сервер для онлайн-PvP.
//
// Крутит «настоящий» World на Node (он не использует DOM), применяет команды
// двух игроков и рассылает снапшоты. Клиент — тонкий: только ввод и отрисовка.
//
// Протокол (JSON-строки):
//   клиент → сервер
//     {t:'cmd', mx, my, ax, ay, fire, mine, dash, airstrike}
//     {t:'hello', name}
//   сервер → клиент
//     {t:'init', index, mode, difficulty, level, seed, map:{...}} — начало
//     {t:'snap', ...полное состояние}                     — каждые 3 тика
//     {t:'feed', text, color}                              — события ленты
//     {t:'finish', result}                                 — конец партии
//     {t:'err', msg}
// ============================================================================

import { createServer } from 'node:http';
import { attachWebSocket } from './ws.js';
import { World } from '../src/world.js';
import { Player } from '../src/player.js';
import { applyCommand } from '../src/commands.js';
import { generateLevel } from '../src/map.js';

const PORT = Number(process.env.PORT || 8123);
const TICK_MS = 1000 / 60;
const SNAP_EVERY = 3; // ~20 Гц

/** Заглушка звука — сервер ничего не проигрывает. */
const silentAudio = {
  play() {},
  advance() {},
};

/** Схема игрока на сервере: применяет последнюю пришедшую команду. */
class ServerScheme {
  constructor() {
    this.cmd = null;
  }
  apply(tank, player, world) {
    if (this.cmd) {
      applyCommand(tank, world, this.cmd);
      this.cmd = null;
    }
  }
}

export class OnlineServer {
  constructor(port = PORT) {
    this.port = port;
    /** @type {import('./ws.js').Connection[]} */
    this.clients = [];
    this.world = null;
    this.tickTimer = null;
    this.snapAccum = 0;
    this.http = createServer((req, res) => {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Танчики онлайн-сервер: порт ' + this.port);
    });
    this.http.listen(this.port, () => {
      console.log(`[server] онлайн-сервер слушает ws://localhost:${this.port}`);
    });
    attachWebSocket(this.http, (conn) => this.#onConnection(conn));
  }

  #onConnection(conn) {
    console.log('[server] клиент подключился');
    conn.onclose = () => this.#onDisconnect(conn);
    conn.onmessage = (text) => {
      try {
        const msg = JSON.parse(text);
        if (msg.t === 'cmd') this.#onCommand(conn, msg);
        if (msg.t === 'hello') this.#onHello(conn, msg);
      } catch (e) {
        console.error('[server] битое сообщение:', e.message);
      }
    };
  }

  #onHello(conn, msg) {
    if (this.clients.length >= 2) {
      this.#send(conn, { t: 'err', msg: 'Сервер уже заполнен (2/2)' });
      conn.close();
      return;
    }
    conn.name = String(msg.name ?? `Игрок ${this.clients.length + 1}`).slice(0, 20);
    conn.scheme = new ServerScheme();
    this.clients.push(conn);
    console.log(`[server] ${conn.name} в лобби (${this.clients.length}/2)`);
    if (this.clients.length === 2) this.#startMatch();
  }

  #onCommand(conn, msg) {
    if (!conn.scheme || this.world?.finished) return;
    conn.scheme.cmd = {
      mx: clampNum(msg.mx),
      my: clampNum(msg.my),
      ax: clampNum(msg.ax),
      ay: clampNum(msg.ay),
      fire: !!msg.fire,
      mine: !!msg.mine,
      dash: !!msg.dash,
      airstrike: !!msg.airstrike,
    };
  }

  #onDisconnect(conn) {
    const i = this.clients.indexOf(conn);
    if (i !== -1) this.clients.splice(i, 1);
    console.log('[server] клиент отключился, в лобби осталось', this.clients.length);
    if (this.world && !this.world.finished) {
      // Один из игроков ушёл — партию заканчиваем.
      this.#finishDueToDisconnect(conn);
    }
  }

  #finishDueToDisconnect(leaver) {
    const winner = this.clients.find((c) => c !== leaver);
    const leaverTank = leaver?.tank;
    const result = {
      victory: false,
      winnerName: winner?.name ?? 'Никто',
      winnerPlayerIndex: winner ? this.#playerIndex(winner) : null,
      winnerTeam: null,
      reason: 'Противник вышел из игры',
      rewards: { kills: 0, captures: 0, wins: 0 },
      disconnected: true,
    };
    void leaverTank;
    for (const c of this.clients) this.#send(c, { t: 'finish', result });
  }

  #playerIndex(conn) {
    return this.clients.indexOf(conn);
  }

  #startMatch() {
    const mode = 'ffa';
    const difficulty = 'medium';
    const levelNum = 1 + Math.floor(Math.random() * 3); // 1..3, детерминированная карта
    const level = generateLevel(levelNum, mode);

    const players = this.clients.map((conn, i) => {
      const p = new Player({
        index: i,
        name: conn.name,
        colorKey: i === 0 ? 'p1' : 'p2',
        scheme: conn.scheme,
      });
      conn.tank = null;
      return p;
    });

    this.world = new World({
      map: level.map,
      level,
      mode,
      difficulty,
      players,
      audio: silentAudio,
      playerLevel: 1,
      noBots: true,
    });

    // Каждому игроку — его танк, чтобы отправлять init и снапшот.
    players.forEach((p, i) => {
      this.clients[i].tank = p.tank;
    });

    // Отправляем карту + индекс один раз.
    players.forEach((p, i) => {
      this.#send(this.clients[i], {
        t: 'init',
        index: i,
        mode,
        difficulty,
        level: levelNum,
        map: serializeMap(level.map),
        seed: level.seed,
        weather: serializeWeather(this.world.weather),
        myName: p.name,
      });
    });

    // События мира пересылаем клиентам: лента, убийства, всплывающие цифры.
    this.world.on('feed', ({ text, color }) => this.#broadcast({ t: 'feed', text, color }));
    this.world.on('kill', ({ victim, killer, suicide }) => {
      this.#broadcast({
        t: 'kill',
        text: suicide || !killer ? `${victim.name} уничтожен` : `${killer.name} ▸ ${victim.name}`,
        color: killer?.owner ? '#88ff88' : '#ff6666',
      });
    });
    this.world.on('damageNumber', ({ x, y, text, color }) =>
      this.#broadcast({ t: 'damageNumber', x, y, text, color }),
    );

    console.log('[server] матч начался:', players.map((p) => p.name).join(' vs '));
    this.snapAccum = 0;
    this.tickTimer = setInterval(() => this.#tick(), TICK_MS);
  }

  #tick() {
    if (!this.world || this.world.finished) {
      if (this.tickTimer) {
        clearInterval(this.tickTimer);
        this.tickTimer = null;
      }
      return;
    }
    this.world.step();
    // Если партия завершилась — шлём финальный снапшот (актуальная статистика),
    // затем finish, не дожидаясь регулярного снапшота.
    if (this.world.finished) {
      const snap = this.#buildSnapshot();
      for (const c of this.clients) this.#send(c, snap);
      this.#sendFinish();
      return;
    }
    if (++this.snapAccum >= SNAP_EVERY) {
      this.snapAccum = 0;
      const snap = this.#buildSnapshot();
      for (const c of this.clients) this.#send(c, snap);
    }
  }

  #buildSnapshot() {
    const w = this.world;
    return {
      t: 'snap',
      tick: w.tick,
      mode: w.mode,
      teamScore: w.teamScore,
      tanks: w.tanks.map((t) => ({
        id: t.id,
        name: t.name,
        team: t.team,
        colorKey: t.colorKey,
        ownerIndex: t.owner ? this.clients.findIndex((c) => c.tank === t) : null,
        x: round1(t.x),
        y: round1(t.y),
        vx: round2(t.vx),
        vy: round2(t.vy),
        angle: round3(t.angle),
        bodyAngle: round3(t.bodyAngle),
        turretAngle: round3(t.turretAngle),
        hp: Math.round(t.hp),
        maxHP: Math.round(t.maxHP),
        alive: t.alive,
        spawnProtect: t.spawnProtect,
        shieldHP: t.shieldHP,
        turboTimer: t.turboTimer,
        weapon: t.weapon,
        weaponTimer: t.weaponTimer,
        perkIds: t.perkIds.slice(),
        cosmetics: t.cosmetics,
        kills: t.kills,
        deaths: t.deaths,
        flag: t.flag ? { team: t.flag.team } : null,
        isBot: t.isBot,
        // Статистика владельца для экрана результатов.
        captures: t.owner?.captures ?? 0,
        score: t.owner?.score ?? 0,
        damageDealt: round1(t.owner?.damageDealt ?? t.damageDealt ?? 0),
        sessionLevel: t.owner?.sessionLevel ?? 1,
      })),
      bullets: w.bullets.map((b) => ({
        x: round1(b.x),
        y: round1(b.y),
        vx: round2(b.vx),
        vy: round2(b.vy),
        alive: b.alive,
        lobbed: b.lobbed,
        fromPlayer: b.fromPlayer,
      })),
      mines: w.mines.map((m) => ({ x: round1(m.x), y: round1(m.y), timer: m.timer, armed: m.armed })),
      pickups: w.pickups.map((p) => ({ x: p.x, y: p.y, active: p.active, bob: p.bob })),
      weaponPickups: w.weaponPickups.map((p) => ({
        x: p.x,
        y: p.y,
        active: p.active,
        bob: p.bob,
        weaponId: p.weaponId,
      })),
      perkDrops: w.perkDrops.map((d) => ({ x: d.x, y: d.y, active: d.active, bob: d.bob, perkId: d.perkId })),
      flags: w.flags.map((f) => ({
        x: f.x,
        y: f.y,
        team: f.team,
        carried: f.carried,
        atHome: f.atHome,
        homeX: f.homeX,
        homeY: f.homeY,
        returnTimer: f.returnTimer,
      })),
      base: w.base ? { x: w.base.x, y: w.base.y, hp: Math.round(w.base.hp), maxHP: w.base.maxHP } : null,
      airstrikes: (w.airstrikes ?? []).map((r) => ({ x: r.x, y: r.y, vx: r.vx, vy: r.vy, alive: r.alive })),
      weather: serializeWeather(w.weather),
      result: w.finished ? w.result : null,
    };
  }

  #sendFinish() {
    for (const c of this.clients) this.#send(c, { t: 'finish', result: this.world.result });
    if (this.tickTimer) {
      clearInterval(this.tickTimer);
      this.tickTimer = null;
    }
  }

  #broadcast(obj) {
    for (const c of this.clients) this.#send(c, obj);
  }

  #send(conn, obj) {
    try {
      conn.send(JSON.stringify(obj));
    } catch (e) {
      console.error('[server] не смог отправить:', e.message);
    }
  }
}

/** Сериализуем карту один раз — клиент строит свою по ней (без DOM-копий). */
function serializeMap(map) {
  return {
    cols: map.cols,
    rows: map.rows,
    tiles: Array.from(map.tiles),
    width: map.width,
    height: map.height,
    version: map.version,
  };
}

/** Погода детерминирована по seed, но шлём текущее состояние для синхрона. */
function serializeWeather(w) {
  return {
    condition: w.condition,
    rain: w.rain,
    fog: w.fog,
    flash: w.flash,
    cycleTicks: w.cycleTicks,
  };
}

function clampNum(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.max(-1e4, Math.min(1e4, n));
}
function round1(v) {
  return Math.round(v * 10) / 10;
}
function round2(v) {
  return Math.round(v * 100) / 100;
}
function round3(v) {
  return Math.round(v * 1000) / 1000;
}

// `node server/game.js` — запуск.
if (import.meta.url === `file://${process.argv[1]}`.replace(/\\/g, '/')) {
  new OnlineServer();
}
