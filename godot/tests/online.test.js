// ============================================================================
// online.test.js — сетевые проверки онлайн-PvP.
//
// Запуск: node tests/online.test.js
// Поднимает настоящий OnlineServer на случайном порту, подключает двух
// WebSocket-клиентов и проверяет init, снапшоты, применение команд, отказ
// третьему игроку и конец партии. Движок тестов тот же самописный, что и в
// smoke.test.js.
// ============================================================================

import assert from 'node:assert';
import { OnlineServer } from '../server/game.js';
import { MODES } from '../src/config.js';

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    failures.push({ name, e });
    console.log(`  ✗ ${name}`);
    console.log('    ' + String(e.message));
  }
}

async function testAsync(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    failures.push({ name, e });
    console.log(`  ✗ ${name}`);
    console.log('    ' + String(e.message));
  }
}

/** Подключает WebSocket-клиента и ждёт init (или err). */
function connect(url, name) {
  return new Promise((resolve) => {
    const ws = new WebSocket(url);
    const out = { ws, init: null, err: null, msgs: [], finish: null };
    ws.onopen = () => ws.send(JSON.stringify({ t: 'hello', name }));
    ws.onmessage = (e) => {
      const m = JSON.parse(e.data);
      out.msgs.push(m);
      if (m.t === 'init') {
        out.init = m;
        resolve(out);
      } else if (m.t === 'err') {
        out.err = m;
        resolve(out);
      } else if (m.t === 'finish') {
        out.finish = m.result;
      }
    };
    ws.onclose = () => resolve(out);
  });
}

async function main() {
  const srv = new OnlineServer(0);
  await new Promise((resolve) => srv.http.once('listening', resolve));
  const url = `ws://localhost:${srv.http.address().port}`;

  await testAsync('два клиента получают init с индексом и картой', async () => {
    const [c1, c2] = await Promise.all([connect(url, 'Алиса'), connect(url, 'Боб')]);
    assert.ok(c1.init, 'первый клиент не получил init');
    assert.ok(c2.init, 'второй клиент не получил init');
    assert.notEqual(c1.init.index, c2.init.index, 'индексы игроков совпали');
    assert.equal(c1.init.mode, 'ffa');
    assert.ok(c1.init.map.cols > 0 && c1.init.map.rows > 0, 'карта пустая');
    assert.equal(c1.init.map.tiles.length, c1.init.map.cols * c1.init.map.rows, 'плитки карты неполные');
    assert.equal(c1.init.seed, c2.init.seed, 'seed различается между клиентами');
    c1.ws.close();
    c2.ws.close();
  });

  await testAsync('снапшоты приходят и содержат двух танков без ботов', async () => {
    const [c1, c2] = await Promise.all([connect(url, 'Алиса'), connect(url, 'Боб')]);
    await new Promise((r) => setTimeout(r, 500));
    const snaps = c1.msgs.filter((m) => m.t === 'snap');
    assert.ok(snaps.length >= 2, 'снапшотов меньше двух');
    const s = snaps[snaps.length - 1];
    assert.equal(s.tanks.length, 2, 'ожидалось ровно 2 танка (noBots)');
    assert.ok(s.tanks.every((t) => t.hp > 0), 'у танка hp <= 0 на старте');
    assert.ok(s.weather && typeof s.weather.rain === 'number', 'нет погоды в снапшоте');
    c1.ws.close();
    c2.ws.close();
  });

  await testAsync('команда игрока применяется и двигает танк', async () => {
    const [c1, c2] = await Promise.all([connect(url, 'Алиса'), connect(url, 'Боб')]);
    await new Promise((r) => setTimeout(r, 200));
    const before = c1.msgs.filter((m) => m.t === 'snap').pop();
    const myBefore = before.tanks.find((t) => t.ownerIndex === c1.init.index);
    // Команда: движение вниз, 300 мс.
    const cmd = { t: 'cmd', mx: 0, my: 1, ax: 500, ay: 500, fire: false, mine: false, dash: false, airstrike: false };
    const mover = setInterval(() => {
      c1.ws.send(JSON.stringify(cmd));
      c2.ws.send(JSON.stringify({ ...cmd, my: -1 }));
    }, 20);
    await new Promise((r) => setTimeout(r, 400));
    clearInterval(mover);
    const after = c1.msgs.filter((m) => m.t === 'snap').pop();
    const myAfter = after.tanks.find((t) => t.ownerIndex === c1.init.index);
    assert.ok(
      Math.abs(myAfter.y - myBefore.y) > 1,
      `танк не сдвинулся по y: было ${myBefore.y}, стало ${myAfter.y}`,
    );
    c1.ws.close();
    c2.ws.close();
  });

  await testAsync('третий клиент получает отказ, когда сервер заполнен', async () => {
    const [c1, c2] = await Promise.all([connect(url, 'Алиса'), connect(url, 'Боб')]);
    const c3 = await connect(url, 'Входящий');
    assert.ok(c3.err, 'третий клиент не получил отказ');
    assert.match(c3.err.msg, /заполнен/);
    c1.ws.close();
    c3.ws.close();
    c2.ws.close();
  });

  await testAsync('finish приходит обоим, победа считается по своему индексу', async () => {
    const [c1, c2] = await Promise.all([connect(url, 'Алиса'), connect(url, 'Боб')]);
    await new Promise((r) => setTimeout(r, 400));
    const winner = srv.world.tanks.find((t) => t.owner?.index === c1.init.index);
    winner.kills = MODES.ffa.fragLimit;
    winner.owner.score = 500;
    await new Promise((r) => setTimeout(r, 400));
    assert.ok(srv.world.finished, 'сервер не завершил партию');
    assert.ok(c1.finish && c2.finish, 'finish не дошёл до клиентов');
    const win = (client) =>
      client.finish.winnerPlayerIndex !== null
        ? client.finish.winnerPlayerIndex === client.init.index
        : client.finish.victory;
    assert.equal(win(c1), true, 'победитель не видит победу');
    assert.equal(win(c2), false, 'проигравший видит победу');
    const last = c1.msgs.filter((m) => m.t === 'snap').pop();
    const me = last.tanks.find((t) => t.ownerIndex === c1.init.index);
    assert.equal(me.kills, MODES.ffa.fragLimit, 'статистика убийств не дошла в финальном снапшоте');
    assert.equal(me.score, 500, 'счёт не дошёл в финальном снапшоте');
    c1.ws.close();
    c2.ws.close();
  });

  srv.http.close();
  console.log('');
  console.log('────────────────────────────────────────────────────────────');
  if (failed > 0) {
    console.log(`Провалено ${failed} из ${passed + failed}`);
    for (const f of failures) {
      console.log(`✗ ${f.name}`);
      console.log('  ' + String(f.e?.message ?? f.e));
    }
    process.exit(1);
  } else {
    console.log(`Все проверки пройдены: ${passed}`);
  }
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
