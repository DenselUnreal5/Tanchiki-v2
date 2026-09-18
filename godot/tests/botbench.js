// Отладка ботов: насколько часто и долго они «врезаются» в стены.
import { generateLevel } from '../src/map.js';
import { T } from '../src/config.js';
import { World } from '../src/world.js';
import { Player } from '../src/player.js';
import { TILE } from '../src/config.js';

const silentAudio = { play() {}, advance() {}, init() {}, setEnabled() {} };
const idleScheme = { apply() {}, get hints() { return []; } };

function makePlayers(count) {
  const players = [];
  for (let i = 0; i < count; i++) {
    players.push(new Player({ index: i, name: `Игрок ${i + 1}`, colorKey: i ? 'p2' : 'p1', scheme: idleScheme }));
    players[i].viewport = { x: 0, y: 0, w: 1280, h: 720 };
  }
  return players;
}

function bench(label, { mode = 'ffa', difficulty = 'medium', level = 1, playerCount = 1, ticks = 6000 }) {
  const lvl = generateLevel(level, mode);
  const players = makePlayers(playerCount);
  const world = new World({ map: lvl.map, level: lvl, mode, difficulty, players, audio: silentAudio });

  let noseWallTicks = 0; // нос в стену при попытке ехать
  let wedgeTicks = 0; // хочет ехать далеко, но почти не движется
  let maxContinuousWedge = 0;
  let continuous = 0;
  const lastPos = new Map();

  for (let tick = 0; tick < ticks; tick++) {
    world.step();
    for (const p of players) p.pendingLevelUps = 0;
    if (world.finished) break;

    for (const t of world.tanks) {
      if (!t.alive || t.isPlayerControlled) continue;
      const lp = lastPos.get(t.id) ?? { x: t.x, y: t.y };
      const moved = Math.hypot(t.x - lp.x, t.y - lp.y);
      lastPos.set(t.id, { x: t.x, y: t.y });

      const go = t.brain;
      const wantedX = go?.destX ?? t.x;
      const wantedY = go?.destY ?? t.y;
      const wantDist = Math.hypot(wantedX - t.x, wantedY - t.y);
      if (wantDist > 40 && moved < 0.12) {
        wedgeTicks++;
        continuous++;
        if (continuous > maxContinuousWedge) maxContinuousWedge = continuous;
      } else {
        continuous = 0;
      }

      // «Нос в стену»: прямо перед корпусом по направлению взгляда твёрдый тайл,
      // при этом бот пытается куда-то ехать и почти не движется.
      const nx = Math.round(t.x + Math.cos(t.bodyAngle) * 20);
      const ny = Math.round(t.y + Math.sin(t.bodyAngle) * 20);
      const front = lvl.map.get(lvl.map.rowAt(ny), lvl.map.colAt(nx));
      if ((front === T.WALL || front === T.BRICK) && wantDist > 30 && moved < 0.5) {
        noseWallTicks++;
      }
    }
  }

  const bots = world.tanks.filter((t) => t.isBot).length;
  const nosePct = ((noseWallTicks / (ticks * bots)) * 100).toFixed(1);
  console.log(
    `\n${label} (${bots} ботов): нос-в-стену ${noseWallTicks} тиков (${nosePct}% бот-времени), ` +
      `застрял ${wedgeTicks}, серия ${maxContinuousWedge}`,
  );
  return { noseWallTicks, nosePct, wedgeTicks, maxContinuousWedge, bots };
}

const results = [];
results.push(bench('FFA easy  lvl1', { mode: 'ffa', difficulty: 'easy', level: 1 }));
results.push(bench('FFA medium lvl2', { mode: 'ffa', difficulty: 'medium', level: 2 }));
results.push(bench('FFA hard  lvl3', { mode: 'ffa', difficulty: 'hard', level: 3 }));
results.push(bench('FFA hard  lvl5', { mode: 'ffa', difficulty: 'hard', level: 5 }));
results.push(bench('CTF medium lvl2', { mode: 'ctf', difficulty: 'medium', level: 2, playerCount: 1 }));

for (const r of results) console.log(`   → нос-в-стену ${r.nosePct}%`);

