// ============================================================================
// render.js — отрисовка мира.
//
// Каждый игрок рисуется в собственную область просмотра со своей камерой,
// поэтому разделённый экран работает без специальных случаев. Кэш миникарты
// перерисовывается только когда карта действительно изменилась.
// ============================================================================

import {
  TILE,
  COLS,
  ROWS,
  T,
  COLORS,
  TEAM_COLORS,
  MINE_LIFE,
  MINE_TRIGGER_R,
} from './config.js';
import { perkIcon } from './perks.js';
import { COSMETIC_TRACKS, COSMETIC_TURRETS } from './cosmetics.js';
import { getWeapon } from './weapons.js';
import { t } from './i18n.js';

/** Детерминированный 0..1 из двух целых — для дождя/тумана без состояния. */
function hash01(i, salt) {
  let a = (Math.imul(i, 0x9e3779b1) + Math.imul(salt, 0x2545f491)) >>> 0;
  a = Math.imul(a ^ (a >>> 15), 1 | a);
  a = a ^ (a + Math.imul(a ^ (a >>> 7), 61 | a));
  a = (a ^ (a >>> 14)) >>> 0;
  return a / 4294967296;
}

function fract(v) {
  return v - Math.floor(v);
}

export class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');

    /** Кэш статичной части миникарты, один на всех игроков. */
    this.mapCache = document.createElement('canvas');
    this.mapCache.width = COLS;
    this.mapCache.height = ROWS;
    this.mapCacheCtx = this.mapCache.getContext('2d');
    this.mapCacheVersion = -1;

    /** Всплывающие числа урона: {x, y, text, color, life, maxLife}. */
    this.floaters = [];
  }

  addFloater(x, y, text, color) {
    if (this.floaters.length > 80) this.floaters.shift();
    this.floaters.push({ x, y, text, color, life: 45, maxLife: 45 });
  }

  clearFloaters() {
    this.floaters.length = 0;
  }

  updateFloaters() {
    let w = 0;
    for (const f of this.floaters) {
      f.life--;
      f.y -= 0.6;
      if (f.life > 0) this.floaters[w++] = f;
    }
    this.floaters.length = w;
  }

  resize(width, height) {
    const dpr = window.devicePixelRatio || 1;
    this.width = width;
    this.height = height;
    this.dpr = dpr;
    this.canvas.width = Math.round(width * dpr);
    this.canvas.height = Math.round(height * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  /**
   * Рисует кадр целиком.
   * @param {import('./world.js').World} world
   */
  draw(world) {
    const ctx = this.ctx;
    ctx.fillStyle = '#0a0a0a';
    ctx.fillRect(0, 0, this.width, this.height);

    for (const player of world.players) {
      this.#drawViewport(world, player);
    }

    if (world.players.length > 1) this.#drawSplitDivider(world);
  }

  #drawSplitDivider(world) {
    const ctx = this.ctx;
    const first = world.players[0].viewport;
    // Только разделительная линия: имена игроков рисует HUD, дублировать
    // их на канвасе не нужно.
    ctx.save();
    ctx.fillStyle = '#4a4a4a';
    ctx.fillRect(first.x + first.w - 1, 0, 2, this.height);
    ctx.restore();
  }

  #drawViewport(world, player) {
    const ctx = this.ctx;
    const vp = player.viewport;
    if (vp.w <= 0 || vp.h <= 0) return;

    ctx.save();
    ctx.beginPath();
    ctx.rect(vp.x, vp.y, vp.w, vp.h);
    ctx.clip();

    // Тряска экрана — своя у каждого игрока.
    let shakeX = 0;
    let shakeY = 0;
    if (player.shake > 0) {
      shakeX = (world.rng() - 0.5) * player.shake;
      shakeY = (world.rng() - 0.5) * player.shake;
    }

    // Переход из мировых координат в экранные для этой области.
    // Сдвиг округляется до целых пикселей: при дробном translate между
    // соседними тайлами появляются швы от сглаживания, и по всей карте
    // проступает сетка.
    const originX = Math.round(vp.x + vp.w / 2 - player.camera.x + shakeX);
    const originY = Math.round(vp.y + vp.h / 2 - player.camera.y + shakeY);
    ctx.translate(originX, originY);

    const view = {
      x0: player.camera.x - vp.w / 2 - TILE,
      y0: player.camera.y - vp.h / 2 - TILE,
      x1: player.camera.x + vp.w / 2 + TILE,
      y1: player.camera.y + vp.h / 2 + TILE,
    };

    this.#drawTiles(ctx, world, view);
    this.#drawPickups(ctx, world, view);
    this.#drawWeaponPickups(ctx, world, view);
    this.#drawPerkDrops(ctx, world, view);
    this.#drawFlags(ctx, world, view);
    this.#drawMines(ctx, world, view);
    this.#drawBase(ctx, world, view);
    this.#drawTanks(ctx, world, player, view);
    this.#drawBullets(ctx, world, view);
    this.#drawParticles(ctx, world, view);
    this.#drawFloaters(ctx, view);
    this.#drawOffscreenMarkers(ctx, world, player, vp);

    ctx.restore();

    this.#drawWeather(ctx, world, player, vp);

    if (player.damageFlash > 0) {
      ctx.save();
      ctx.globalAlpha = (player.damageFlash / 12) * 0.28;
      ctx.fillStyle = '#ff0000';
      ctx.fillRect(vp.x, vp.y, vp.w, vp.h);
      ctx.restore();
    }

    if (player.tank && !player.tank.alive) {
      ctx.save();
      ctx.fillStyle = 'rgba(0,0,0,0.45)';
      ctx.fillRect(vp.x, vp.y, vp.w, vp.h);
      ctx.fillStyle = '#ff6666';
      ctx.font = 'bold 26px "Segoe UI", Arial, sans-serif';
      ctx.textAlign = 'center';
      const secs = Math.ceil(player.tank.respawnTimer / 60);
      ctx.fillText(
        t('render.respawn', { n: Math.max(0, secs) }, `Возрождение через ${Math.max(0, secs)}...`),
        vp.x + vp.w / 2,
        vp.y + vp.h / 2,
      );
      ctx.restore();
    }
  }

  // ------------------------------------------------------------------ погода
  /**
   * Рисует атмосферу поверх мира: ночная тьма, туман, дождь, вспышки молний.
   * Работает в экранных координатах области просмотра.
   */
  #drawWeather(ctx, world, player, vp) {
    const weather = world.weather;
    if (!weather) return;

    // --- ночная тьма: полупрозрачный затемняющий слой по уровню освещения.
    const dark = (1 - weather.light) * 0.55;
    if (dark > 0.01) {
      ctx.fillStyle = `rgba(10, 14, 34, ${dark.toFixed(3)})`;
      ctx.fillRect(vp.x, vp.y, vp.w, vp.h);
    }

    // --- туман: плавающие полупрозрачные пятна, ближе к игроку плотнее.
    if (weather.fog > 0.02) {
      const count = Math.round(weather.fog * 9);
      for (let i = 0; i < count; i++) {
        const cx = vp.x + hash01(i, 7) * vp.w + Math.sin(world.tick * 0.003 + i * 2.1) * 40;
        const cy = vp.y + hash01(i, 13) * vp.h + Math.cos(world.tick * 0.002 + i * 1.7) * 30;
        const r = 90 + hash01(i, 29) * 130;
        const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
        g.addColorStop(0, `rgba(220, 228, 240, ${(0.05 + weather.fog * 0.1).toFixed(3)})`);
        g.addColorStop(1, 'rgba(220, 228, 240, 0)');
        ctx.fillStyle = g;
        ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
      }
    }

    // --- дождь: наклонные штрихи, падающие вниз.
    if (weather.rain > 0.03) {
      const count = Math.round(weather.rain * 130);
      ctx.strokeStyle = `rgba(150, 180, 235, ${(0.15 + weather.rain * 0.3).toFixed(3)})`;
      ctx.lineWidth = 1;
      ctx.beginPath();
      for (let i = 0; i < count; i++) {
        const seedX = hash01(i, 31) * vp.w;
        const speed = 6 + hash01(i, 41) * 6;
        const y = fract(hash01(i, 43) + world.tick * 0.012 * speed) * (vp.h + 40) - 20;
        const x = vp.x + seedX;
        const len = 8 + hash01(i, 47) * 10;
        ctx.moveTo(x, vp.y + y);
        ctx.lineTo(x - len * 0.4, vp.y + y + len);
      }
      ctx.stroke();
    }

    // --- вспышка молнии: короткая яркая заливка.
    if (weather.flash > 0.02) {
      ctx.fillStyle = `rgba(220, 235, 255, ${(weather.flash * 0.35).toFixed(3)})`;
      ctx.fillRect(vp.x, vp.y, vp.w, vp.h);
    }
  }

  // ------------------------------------------------------------------ тайлы
  #drawTiles(ctx, world, view) {
    const map = world.map;
    const c0 = Math.max(0, Math.floor(view.x0 / TILE));
    const c1 = Math.min(map.cols - 1, Math.ceil(view.x1 / TILE));
    const r0 = Math.max(0, Math.floor(view.y0 / TILE));
    const r1 = Math.min(map.rows - 1, Math.ceil(view.y1 / TILE));

    // Земля с лёгкой шахматкой, чтобы читалась сетка и масштаб.
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        ctx.fillStyle = (r + c) % 2 === 0 ? COLORS.ground : COLORS.groundAlt;
        ctx.fillRect(c * TILE, r * TILE, TILE, TILE);
      }
    }

    const waterPhase = (world.tick % 120) / 120;

    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        const tile = map.get(r, c);
        if (tile === T.EMPTY) continue;
        const x = c * TILE;
        const y = r * TILE;
        switch (tile) {
          case T.WALL:
            ctx.fillStyle = COLORS.wall;
            ctx.fillRect(x, y, TILE, TILE);
            ctx.fillStyle = COLORS.wallTop;
            ctx.fillRect(x, y, TILE, 3);
            ctx.fillRect(x, y, 3, TILE);
            ctx.fillStyle = COLORS.wallEdge;
            ctx.fillRect(x, y + TILE - 3, TILE, 3);
            ctx.fillRect(x + TILE - 3, y, 3, TILE);
            break;
          case T.BRICK:
            this.#drawRoofTile(ctx, x, y, r, c);
            break;
          case T.WATER:
            this.#drawWaterTile(ctx, x, y, r, c, waterPhase);
            break;
          case T.SAND:
            this.#drawSandTile(ctx, x, y, r, c);
            break;
          case T.TREE:
            this.#drawTreeTile(ctx, x, y, r, c);
            break;
          case T.BASE_P:
          case T.BASE_E:
            this.#drawBaseTile(ctx, x, y, tile === T.BASE_P, world.tick);
            break;
          default:
            break;
        }
      }
    }
  }

  #drawBrickTile(ctx, x, y) {
    ctx.fillStyle = COLORS.brick;
    ctx.fillRect(x, y, TILE, TILE);
    ctx.fillStyle = COLORS.brickEdge;
    // Кладка: два ряда со смещением.
    for (let i = 0; i < 4; i++) {
      const by = y + i * 8;
      ctx.fillRect(x, by + 7, TILE, 1);
      const offset = i % 2 === 0 ? 0 : 8;
      ctx.fillRect(x + offset, by, 1, 7);
      ctx.fillRect(x + offset + 16, by, 1, 7);
    }
    ctx.fillStyle = COLORS.brickTop;
    ctx.fillRect(x, y, TILE, 2);
  }

  /**
   * Крыша многоэтажки — 5 детерминированных по (r, c) вариантов. Кирпич
   * остаётся кирпичом в логике (разрушается пулями, проезжаемость та же),
   * меняется только вид: теперь это плоские крыши панельных домов.
   */
  #drawRoofTile(ctx, x, y, r, c) {
    const variant = Math.floor(hash01(r * 73856093 + c, 1337) * 5);
    switch (variant) {
      case 0:
        this.#roofConcrete(ctx, x, y);
        break;
      case 1:
        this.#roofGravel(ctx, x, y, r, c);
        break;
      case 2:
        this.#roofRibbed(ctx, x, y);
        break;
      case 3:
        this.#roofPatchwork(ctx, x, y, r, c);
        break;
      default:
        this.#roofPanel(ctx, x, y);
        break;
    }
    // Бортик по краю, чтобы крыша читалась как приподнятая.
    ctx.fillStyle = 'rgba(0,0,0,0.18)';
    ctx.fillRect(x, y, TILE, 2);
    ctx.fillRect(x, y, 2, TILE);
    ctx.fillStyle = 'rgba(255,255,255,0.10)';
    ctx.fillRect(x, y + TILE - 2, TILE, 2);
    ctx.fillRect(x + TILE - 2, y, 2, TILE);
  }

  /** Серый бетон с полосами стяжки и трещинкой. */
  #roofConcrete(ctx, x, y) {
    ctx.fillStyle = '#8f8a84';
    ctx.fillRect(x, y, TILE, TILE);
    ctx.fillStyle = '#7b766f';
    for (let i = 0; i < 3; i++) {
      ctx.fillRect(x, y + 5 + i * 10, TILE, 1);
    }
    ctx.fillStyle = 'rgba(0,0,0,0.15)';
    ctx.fillRect(x + 9, y, 2, TILE);
  }

  /** Гравийная кровля — крапинки по тёмно-серому. */
  #roofGravel(ctx, x, y, r, c) {
    ctx.fillStyle = '#6f6b66';
    ctx.fillRect(x, y, TILE, TILE);
    for (let i = 0; i < 10; i++) {
      const px = x + ((r * 31 + c * 17 + i * 13) % 27) + 2;
      const py = y + ((r * 13 + c * 29 + i * 7) % 27) + 2;
      ctx.fillStyle = i % 2 ? '#7d7872' : '#5f5b56';
      ctx.fillRect(px, py, 3, 3);
    }
  }

  /** Профнастил — частые поперечные рёбра. */
  #roofRibbed(ctx, x, y) {
    ctx.fillStyle = '#6e7b8a';
    ctx.fillRect(x, y, TILE, TILE);
    ctx.fillStyle = '#5b6775';
    for (let i = 0; i < 8; i++) {
      ctx.fillRect(x, y + i * 4 + 1, TILE, 2);
    }
    ctx.fillStyle = 'rgba(255,255,255,0.18)';
    for (let i = 0; i < 8; i++) {
      ctx.fillRect(x, y + i * 4, TILE, 1);
    }
  }

  /** Лоскутное перекрытие разных участков ремонта. */
  #roofPatchwork(ctx, x, y, r, c) {
    ctx.fillStyle = '#8a8278';
    ctx.fillRect(x, y, TILE, TILE);
    const n = 3;
    for (let i = 0; i < n; i++) {
      const px = x + ((r * 7 + c * 11 + i * 5) % 20) + 2;
      const py = y + ((r * 5 + c * 7 + i * 9) % 20) + 2;
      ctx.fillStyle = i % 2 ? '#777065' : '#9c948a';
      ctx.fillRect(px, py, 8, 8);
      ctx.strokeStyle = 'rgba(0,0,0,0.2)';
      ctx.strokeRect(px, py, 8, 8);
    }
  }

  /** Панельная кровля с рулонным покрытием и парапетом. */
  #roofPanel(ctx, x, y) {
    ctx.fillStyle = '#9a948c';
    ctx.fillRect(x, y, TILE, TILE);
    ctx.fillStyle = '#b3aca2';
    ctx.fillRect(x + 3, y + 3, TILE - 6, TILE - 6);
    ctx.strokeStyle = '#7c766d';
    ctx.strokeRect(x + 3, y + 3, TILE - 6, TILE - 6);
  }

  /** Песчаный берег: база с крапинками и светлой кромкой у воды. */
  #drawSandTile(ctx, x, y, r, c) {
    ctx.fillStyle = COLORS.sand;
    ctx.fillRect(x, y, TILE, TILE);
    ctx.fillStyle = COLORS.sandDark;
    for (let i = 0; i < 6; i++) {
      const px = x + ((r * 13 + c * 7 + i * 5) % 26) + 3;
      const py = y + ((r * 7 + c * 13 + i * 11) % 26) + 3;
      ctx.fillRect(px, py, 2, 2);
    }
    ctx.fillStyle = COLORS.sandLight;
    ctx.fillRect(x, y, TILE, 2);
    ctx.fillRect(x, y, 2, TILE);
  }

  #drawWaterTile(ctx, x, y, r, c, phase) {
    ctx.fillStyle = COLORS.water;
    ctx.fillRect(x, y, TILE, TILE);
    ctx.fillStyle = COLORS.waterLight;
    // Две «волны», сдвинутые по фазе — дешёвая анимация без затрат.
    const wave = Math.sin((r + c) * 0.7 + phase * Math.PI * 2);
    const h = 2 + wave;
    ctx.globalAlpha = 0.45;
    ctx.fillRect(x + 2, y + 8 + wave * 2, TILE - 4, h);
    ctx.fillRect(x + 4, y + 20 - wave * 2, TILE - 10, h);
    ctx.globalAlpha = 1;
  }

  #drawTreeTile(ctx, x, y, r, c) {
    ctx.fillStyle = COLORS.treeDark;
    ctx.beginPath();
    ctx.arc(x + 16, y + 18, 13, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = COLORS.tree;
    // Смещение кроны детерминировано координатами — картинка не «дрожит».
    const ox = ((r * 7 + c * 13) % 5) - 2;
    const oy = ((r * 11 + c * 5) % 5) - 2;
    ctx.beginPath();
    ctx.arc(x + 16 + ox, y + 15 + oy, 10, 0, Math.PI * 2);
    ctx.fill();
  }

  #drawBaseTile(ctx, x, y, isPlayer, tick) {
    const color = isPlayer ? COLORS.baseP : COLORS.baseE;
    ctx.fillStyle = color;
    ctx.globalAlpha = 0.25;
    ctx.fillRect(x, y, TILE, TILE);
    ctx.globalAlpha = 1;
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    const pulse = 0.5 + 0.5 * Math.sin(tick * 0.06);
    ctx.globalAlpha = 0.5 + pulse * 0.5;
    ctx.strokeRect(x + 3, y + 3, TILE - 6, TILE - 6);
    ctx.globalAlpha = 1;
    ctx.fillStyle = color;
    ctx.font = 'bold 14px "Segoe UI", Arial, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('⌂', x + TILE / 2, y + TILE / 2);
  }

  // ------------------------------------------------------------------ объекты
  #drawPickups(ctx, world, view) {
    for (const p of world.pickups) {
      if (!p.active || !inView(p.x, p.y, view, 20)) continue;
      const bob = Math.sin(world.tick * 0.08 + p.bob) * 2;
      const y = p.y + bob;
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(p.x - 8, y - 8, 16, 16);
      ctx.fillStyle = '#dd3333';
      ctx.fillRect(p.x - 6, y - 2, 12, 4);
      ctx.fillRect(p.x - 2, y - 6, 4, 12);
      ctx.strokeStyle = 'rgba(255,255,255,0.35)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.arc(p.x, y, 13, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  /** Power-up оружия: цветной шестиугольник с иконкой. */
  #drawWeaponPickups(ctx, world, view) {
    for (const p of world.weaponPickups) {
      if (!p.active || !inView(p.x, p.y, view, 24)) continue;
      const weapon = getWeapon(p.weaponId);
      if (!weapon) continue;
      const bob = Math.sin(world.tick * 0.09 + p.bob) * 2.5;
      const y = p.y + bob;

      // Пульсирующее кольцо — бросается в глаза.
      const pulse = 0.35 + 0.25 * Math.sin(world.tick * 0.12);
      ctx.globalAlpha = pulse;
      ctx.fillStyle = weapon.color;
      ctx.beginPath();
      ctx.arc(p.x, y, 20, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;

      // Шестиугольная «ячейка» оружия.
      ctx.fillStyle = 'rgba(16,20,26,0.92)';
      ctx.strokeStyle = weapon.color;
      ctx.lineWidth = 2;
      ctx.beginPath();
      for (let i = 0; i < 6; i++) {
        const a = (Math.PI / 3) * i + Math.PI / 6;
        const rx = p.x + Math.cos(a) * 15;
        const ry = y + Math.sin(a) * 15;
        if (i === 0) ctx.moveTo(rx, ry);
        else ctx.lineTo(rx, ry);
      }
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = '#ffffff';
      ctx.font = '13px "Segoe UI", Arial, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(weapon.icon, p.x, y + 1);
    }
  }

  /** Выпавшие из убитых перки («Царь горы»). */
  #drawPerkDrops(ctx, world, view) {
    for (const drop of world.perkDrops) {
      if (!drop.active || !inView(drop.x, drop.y, view, 26)) continue;
      const bob = Math.sin(world.tick * 0.07 + drop.bob) * 3;
      const y = drop.y + bob;

      ctx.globalAlpha = 0.25;
      ctx.fillStyle = '#ff88ff';
      ctx.beginPath();
      ctx.arc(drop.x, y, 20, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;

      ctx.fillStyle = 'rgba(40,16,48,0.85)';
      ctx.beginPath();
      ctx.arc(drop.x, y, 15, 0, Math.PI * 2);
      ctx.fill();

      ctx.strokeStyle = '#ff88ff';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(drop.x, y, 15, 0, Math.PI * 2);
      ctx.stroke();

      ctx.fillStyle = '#ffffff';
      ctx.font = '14px "Segoe UI", Arial, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(perkIcon(drop.perkId), drop.x, y + 0.5);
      ctx.textBaseline = 'alphabetic';
    }
  }

  #drawFlags(ctx, world, view) {
    for (const flag of world.flags) {
      if (!inView(flag.x, flag.y, view, 30)) continue;
      const color = flag.team === 'player' ? COLORS.flagPlayer : COLORS.flagEnemy;
      const carried = flag.carried;
      const lift = carried ? -18 : Math.sin(world.tick * 0.06) * 2;

      // Домашняя метка, если флаг унесли.
      if (!flag.atHome && inView(flag.homeX, flag.homeY, view, 30)) {
        ctx.globalAlpha = 0.35;
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.setLineDash([4, 4]);
        ctx.beginPath();
        ctx.arc(flag.homeX, flag.homeY, 16, 0, Math.PI * 2);
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.globalAlpha = 1;
      }

      ctx.strokeStyle = '#dddddd';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(flag.x, flag.y + lift + 12);
      ctx.lineTo(flag.x, flag.y + lift - 14);
      ctx.stroke();
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.moveTo(flag.x, flag.y + lift - 14);
      ctx.lineTo(flag.x + 16, flag.y + lift - 9);
      ctx.lineTo(flag.x, flag.y + lift - 4);
      ctx.closePath();
      ctx.fill();

      if (!carried && flag.returnTimer > 0) {
        ctx.fillStyle = 'rgba(255,255,255,0.8)';
        ctx.font = '10px "Segoe UI", Arial, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillStyle = '#ffcc66';
        ctx.fillText(`${Math.ceil(flag.returnTimer / 60)}${t('hud.sec', null, 'с')}`, flag.x, flag.y + 24);
      }
    }
  }

  #drawMines(ctx, world, view) {
    for (const mine of world.mines) {
      if (!inView(mine.x, mine.y, view, 30)) continue;
      ctx.fillStyle = '#666666';
      ctx.beginPath();
      ctx.arc(mine.x, mine.y, 6, 0, Math.PI * 2);
      ctx.fill();
      const blink = mine.timer > 120 ? Math.floor(mine.timer / 20) % 2 === 0 : Math.floor(mine.timer / 6) % 2 === 0;
      if (blink) {
        ctx.fillStyle = mine.armed ? '#ff4444' : '#ffaa44';
        ctx.beginPath();
        ctx.arc(mine.x, mine.y, 2.5, 0, Math.PI * 2);
        ctx.fill();
      }
      if (mine.timer < 180 || mine.timer > MINE_LIFE - 60) {
        ctx.globalAlpha = 0.3;
        ctx.strokeStyle = '#ff4444';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(mine.x, mine.y, MINE_TRIGGER_R, 0, Math.PI * 2);
        ctx.stroke();
        ctx.globalAlpha = 1;
      }
    }
  }

  /** База «Оборона»: кольцевая крепость с полоской прочности. */
  #drawBase(ctx, world, view) {
    const base = world.base;
    if (!base) return;
    if (!inView(base.x, base.y, view, 80)) return;

    const pulse = Math.sin(world.tick * 0.05) * 3;
    const ratio = base.hp / base.maxHP;

    // Платформа под крепостью.
    ctx.fillStyle = '#3a3a3a';
    ctx.beginPath();
    ctx.arc(base.x, base.y, 34, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#555';
    ctx.lineWidth = 2;
    ctx.stroke();

    // Кольцо-стена, пульсирует на повреждениях.
    ctx.strokeStyle = ratio > 0.5 ? '#6a9a5a' : ratio > 0.25 ? '#ccaa44' : '#cc4444';
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(base.x, base.y, 24 + pulse, 0, Math.PI * 2);
    ctx.stroke();

    // Ядро.
    ctx.fillStyle = ratio > 0.5 ? '#7abf6a' : ratio > 0.25 ? '#ddc255' : '#dd5555';
    ctx.beginPath();
    ctx.arc(base.x, base.y, 14, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.font = '14px "Segoe UI", Arial, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('🏰', base.x, base.y + 1);

    // Полоска прочности над крепостью.
    const w = 56;
    const h = 6;
    const bx = base.x - w / 2;
    const by = base.y - 52;
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.fillRect(bx - 1, by - 1, w + 2, h + 2);
    ctx.fillStyle = ratio > 0.5 ? '#44cc44' : ratio > 0.25 ? '#cccc44' : '#cc4444';
    ctx.fillRect(bx, by, w * Math.max(0, ratio), h);
  }

  #drawBullets(ctx, world, view) {
    for (const b of world.bullets) {
      if (!b.alive || !inView(b.x, b.y, view, 10)) continue;
      if (b.lobbed) {
        // Миномётный снаряд: оранжевый огонёк с дымным хвостом.
        ctx.fillStyle = '#ff9933';
        ctx.beginPath();
        ctx.arc(b.x, b.y, 4, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = '#ffe8a0';
        ctx.beginPath();
        ctx.arc(b.x, b.y, 1.8, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 0.3;
        ctx.strokeStyle = '#aaaaaa';
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.moveTo(b.x - b.vx * 3, b.y - b.vy * 3);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
        ctx.globalAlpha = 1;
        continue;
      }
      const color = b.fromPlayer ? COLORS.bullet : COLORS.bulletEnemy;
      // Короткий след — читается направление полёта.
      ctx.strokeStyle = color;
      ctx.globalAlpha = 0.35;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(b.x - b.vx * 2.5, b.y - b.vy * 2.5);
      ctx.lineTo(b.x, b.y);
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(b.x, b.y, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#ffffff';
      ctx.beginPath();
      ctx.arc(b.x, b.y, 1.4, 0, Math.PI * 2);
      ctx.fill();
    }

    // Ракеты авиаудара: огненная комета с хвостом по направлению полёта.
    for (const r of world.airstrikes ?? []) {
      if (!r.alive || !inView(r.x, r.y, view, 12)) continue;
      ctx.strokeStyle = '#ffaa44';
      ctx.globalAlpha = 0.35;
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.moveTo(r.x - r.vx * 4, r.y - r.vy * 4);
      ctx.lineTo(r.x, r.y);
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = '#ff8833';
      ctx.beginPath();
      ctx.arc(r.x, r.y, 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#fff6cc';
      ctx.beginPath();
      ctx.arc(r.x, r.y, 2.2, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  #drawParticles(ctx, world, view) {
    const ps = world.particles;
    for (let i = 0; i < ps.count; i++) {
      const x = ps.x[i];
      const y = ps.y[i];
      if (!inView(x, y, view, 10)) continue;
      ctx.globalAlpha = Math.max(0, ps.life[i] / ps.maxLife[i]);
      ctx.fillStyle = ps.color[i];
      const s = ps.size[i];
      ctx.fillRect(x - s / 2, y - s / 2, s, s);
    }
    ctx.globalAlpha = 1;
  }

  #drawFloaters(ctx, view) {
    ctx.font = 'bold 13px "Segoe UI", Arial, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (const f of this.floaters) {
      if (!inView(f.x, f.y, view, 30)) continue;
      ctx.globalAlpha = Math.min(1, f.life / 20);
      ctx.fillStyle = '#000000';
      ctx.fillText(f.text, f.x + 1, f.y + 1);
      ctx.fillStyle = f.color;
      ctx.fillText(f.text, f.x, f.y);
    }
    ctx.globalAlpha = 1;
  }

  // ------------------------------------------------------------------ танки
  #drawTanks(ctx, world, viewer, view) {
    for (const tank of world.tanks) {
      if (!tank.alive || !inView(tank.x, tank.y, view, 40)) continue;
      this.#drawTank(ctx, world, tank, viewer);
    }
  }

  #drawTank(ctx, world, tank, viewer) {
    const palette = TEAM_COLORS[tank.colorKey] ?? TEAM_COLORS.neutral;
    const isViewer = viewer.tank === tank;
    const isAlly = viewer.tank && !world.areHostile(viewer.tank, tank) && !isViewer;

    ctx.save();
    ctx.translate(tank.x, tank.y);

    // Тень под корпусом — отделяет танк от земли.
    ctx.globalAlpha = 0.25;
    ctx.fillStyle = '#000000';
    ctx.beginPath();
    ctx.ellipse(2, 4, tank.width / 2, tank.height / 2.4, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;

    // ---- корпус ---------------------------------------------------------
    ctx.save();
    ctx.rotate(tank.bodyAngle + Math.PI / 2);
    const hw = tank.width / 2;
    const hh = tank.height / 2;

    // Гусеницы. Цвет можно менять косметикой.
    const trackColor = tank.cosmetics?.track;
    const trackC = trackColor && trackColor !== 'none' ? COSMETIC_TRACKS.find((c) => c.id === trackColor)?.color : null;
    const trackFill = trackC ?? '#2a2a2a';
    const trackTread = trackC ?? '#444444';
    ctx.fillStyle = trackFill;
    ctx.fillRect(-hw - 2, -hh, 6, tank.height);
    ctx.fillRect(hw - 4, -hh, 6, tank.height);
    ctx.fillStyle = trackTread;
    // Траки «прокручиваются» вместе с движением.
    const treadShift = Math.floor((tank.x + tank.y) / 4) % 6;
    for (let i = -hh + treadShift; i < hh; i += 6) {
      ctx.fillRect(-hw - 2, i, 6, 2);
      ctx.fillRect(hw - 4, i, 6, 2);
    }

    // Основной корпус.
    ctx.fillStyle = palette.body;
    ctx.fillRect(-hw + 3, -hh + 2, tank.width - 6, tank.height - 4);
    ctx.fillStyle = palette.bodyDark;
    ctx.fillRect(-hw + 3, hh - 8, tank.width - 6, 6);
    ctx.fillStyle = palette.trim;
    ctx.fillRect(-hw + 5, -hh + 4, tank.width - 10, 3);

    // Рисунок корпуса (косметика).
    this.#drawHullPattern(ctx, tank, hw, hh);

    ctx.restore();

    // ---- башня ----------------------------------------------------------
    const turretC = tank.cosmetics?.turret;
    const turretColor = turretC && turretC !== 'none' ? COSMETIC_TURRETS.find((c) => c.id === turretC)?.color : null;
    const barrelBase = turretColor ?? '#222222';
    const barrelDark = turretColor ?? '#3a3a3a';
    ctx.save();
    ctx.rotate(tank.turretAngle);
    ctx.fillStyle = barrelBase;
    ctx.fillRect(0, -2.5, 22, 5);
    ctx.fillStyle = barrelDark;
    ctx.fillRect(18, -3.5, 5, 7);
    ctx.restore();

    ctx.fillStyle = turretColor ?? palette.bodyDark;
    ctx.beginPath();
    ctx.arc(0, 0, 8.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = turretColor ?? palette.body;
    ctx.beginPath();
    ctx.arc(0, 0, 6.5, 0, Math.PI * 2);
    ctx.fill();

    // ---- индикаторы -----------------------------------------------------
    if (tank.spawnProtect > 0) {
      ctx.globalAlpha = 0.4 + 0.3 * Math.sin(world.tick * 0.3);
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(0, 0, 20, 0, Math.PI * 2);
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
    if (tank.shieldHP > 0) {
      ctx.globalAlpha = 0.55;
      ctx.strokeStyle = COLORS.shield;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(0, 0, 18, 0, Math.PI * 2);
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
    if (tank.turboTimer > 0) {
      ctx.globalAlpha = 0.5;
      ctx.fillStyle = '#ffaa33';
      for (let i = 0; i < 3; i++) {
        const a = tank.bodyAngle + Math.PI + (i - 1) * 0.3;
        ctx.beginPath();
        ctx.arc(Math.cos(a) * 20, Math.sin(a) * 20, 3, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    }

    // Активное оружие — оранжевый щиток над танком с иконкой.
    if (tank.weapon && tank.weaponTimer > 0) {
      const weapon = getWeapon(tank.weapon);
      const frac = Math.max(0, tank.weaponTimer / weapon.duration);
      ctx.fillStyle = 'rgba(16,20,26,0.9)';
      ctx.strokeStyle = weapon.color;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(0, -20, 10, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      // Кольцо-таймер вокруг значка.
      ctx.strokeStyle = weapon.color;
      ctx.lineWidth = 2;
      ctx.globalAlpha = 0.8;
      ctx.beginPath();
      ctx.arc(0, -20, 13, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2);
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = '#ffffff';
      ctx.font = '10px "Segoe UI", Arial, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(weapon.icon, 0, -20);
    }

    // Маркер «это ты» — важно в разделённом экране.
    if (isViewer) {
      ctx.fillStyle = palette.trim;
      ctx.beginPath();
      ctx.moveTo(0, -26);
      ctx.lineTo(-5, -34);
      ctx.lineTo(5, -34);
      ctx.closePath();
      ctx.fill();
    }

    ctx.restore();

    // ---- полоска HP и подпись (без поворота) ----------------------------
    const barW = 26;
    const ratio = Math.max(0, tank.hp / tank.maxHP);
    if (ratio < 1 || !isViewer) {
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      ctx.fillRect(tank.x - barW / 2, tank.y - 22, barW, 4);
      ctx.fillStyle = ratio > 0.5 ? '#44cc44' : ratio > 0.25 ? '#cccc44' : '#cc4444';
      ctx.fillRect(tank.x - barW / 2, tank.y - 22, barW * ratio, 4);
    }
    if (tank.shieldHP > 0) {
      ctx.fillStyle = COLORS.shield;
      ctx.fillRect(tank.x - barW / 2, tank.y - 26, barW * Math.min(1, tank.shieldHP / 30), 2);
    }

    if (!isViewer) {
      ctx.font = '10px "Segoe UI", Arial, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'bottom';
      ctx.fillStyle = isAlly ? '#88ccff' : tank.isPlayerControlled ? '#ffee55' : '#ffaaaa';
      ctx.fillText(tank.name, tank.x, tank.y - 27);
      // Перки бота видно над именем — понятно, почему он вдруг стал опасным.
      if (tank.perkIds.length) {
        ctx.font = '9px "Segoe UI", Arial, sans-serif';
        ctx.fillStyle = '#ffcc66';
        ctx.fillText(tank.perkIds.map(botIcon).join(''), tank.x, tank.y - 38);
      }
    }

    if (tank.carryingFlag) {
      ctx.font = '14px "Segoe UI", Arial, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = '#ffee55';
      ctx.fillText('⚑', tank.x + 16, tank.y - 16);
    }
  }

  /** Рисунок на корпусе (косметика). Вызывается в повёрнутом контексте корпуса. */
  #drawHullPattern(ctx, tank, hw, hh) {
    const id = tank.cosmetics?.hull;
    if (!id || id === 'none') return;
    ctx.save();
    ctx.globalAlpha = 0.8;

    if (id === 'stripes') {
      ctx.fillStyle = '#ffffff';
      for (let x = -hw + 4; x < hw - 4; x += 6) {
        if (((x + tank.x) / 6 | 0) % 2 === 0) ctx.fillRect(x, -hh + 2, 3, tank.height - 4);
      }
    } else if (id === 'star') {
      ctx.fillStyle = '#ffee55';
      ctx.beginPath();
      for (let i = 0; i < 10; i++) {
        const r = i % 2 === 0 ? 7 : 3;
        const a = -Math.PI / 2 + (i * Math.PI) / 5;
        ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r);
      }
      ctx.closePath();
      ctx.fill();
    } else if (id === 'flames') {
      ctx.fillStyle = '#ff7733';
      for (let i = 0; i < 3; i++) {
        const y = -hh + 6 + i * 6;
        ctx.beginPath();
        ctx.moveTo(-hw + 4, y);
        ctx.quadraticCurveTo(-hw + 8, y - 10, -hw + 12, y);
        ctx.quadraticCurveTo(-hw + 8, y + 5, -hw + 4, y);
        ctx.fill();
      }
    } else if (id === 'cross') {
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(-2, -hh + 4, 4, tank.height - 8);
      ctx.fillRect(-hw + 4, -2, tank.width - 8, 4);
    } else if (id === 'chevrons') {
      ctx.fillStyle = '#88ccff';
      for (let i = 0; i < 2; i++) {
        const y = -hh + 6 + i * 8;
        ctx.beginPath();
        ctx.moveTo(-hw + 4, y);
        ctx.lineTo(0, y - 5);
        ctx.lineTo(hw - 4, y);
        ctx.lineTo(0, y + 2);
        ctx.closePath();
        ctx.fill();
      }
    }

    ctx.restore();
  }

  /** Стрелки к важным целям за пределами экрана. */
  #drawOffscreenMarkers(ctx, world, player, vp) {
    if (world.mode !== 'ctf' || !player.tank) return;
    const cam = player.camera;
    const halfW = vp.w / 2 - 40;
    const halfH = vp.h / 2 - 40;

    for (const flag of world.flags) {
      const relevant = flag.team !== player.tank.team || !flag.atHome;
      if (!relevant) continue;
      const dx = flag.x - cam.x;
      const dy = flag.y - cam.y;
      if (Math.abs(dx) < halfW && Math.abs(dy) < halfH) continue;
      const angle = Math.atan2(dy, dx);
      const cx = cam.x + Math.cos(angle) * Math.min(halfW, halfH) * 0.95;
      const cy = cam.y + Math.sin(angle) * Math.min(halfW, halfH) * 0.95;
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(angle);
      ctx.fillStyle = flag.team === 'player' ? COLORS.flagPlayer : COLORS.flagEnemy;
      ctx.globalAlpha = 0.8;
      ctx.beginPath();
      ctx.moveTo(10, 0);
      ctx.lineTo(-6, -6);
      ctx.lineTo(-6, 6);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
    }
  }

  // ------------------------------------------------------------------ миникарта
  /**
   * Рисует миникарту в указанный канвас. В разделённом экране у каждого
   * игрока своя миникарта со своим обзором.
   * @param {HTMLCanvasElement} canvas
   * @param {import('./world.js').World} world
   * @param {import('./player.js').Player} player чей обзор показывать
   */
  drawMinimap(canvas, world, player) {
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;

    if (this.mapCacheVersion !== world.map.version) {
      this.#renderMapCache(world.map);
      this.mapCacheVersion = world.map.version;
    }

    ctx.fillStyle = '#0a0a0a';
    ctx.fillRect(0, 0, w, h);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(this.mapCache, 0, 0, w, h);

    const sx = w / world.map.width;
    const sy = h / world.map.height;

    // Аптечки.
    ctx.fillStyle = '#ffffff';
    for (const p of world.pickups) {
      if (p.active) ctx.fillRect(p.x * sx - 1, p.y * sy - 1, 2, 2);
    }

    // Флаги.
    for (const flag of world.flags) {
      ctx.fillStyle = flag.team === 'player' ? COLORS.flagPlayer : COLORS.flagEnemy;
      ctx.fillRect(flag.x * sx - 2, flag.y * sy - 2, 4, 4);
    }

    const viewerTank = player.tank;

    for (const tank of world.tanks) {
      if (!tank.alive) continue;
      const isViewer = tank === viewerTank;
      const hostile = viewerTank ? world.areHostile(viewerTank, tank) : true;

      // «Тень» скрывает танк с чужой миникарты.
      if (!isViewer && tank.shadowTimer > 0 && hostile) continue;

      // Врагов видно только по прямой видимости.
      if (hostile && viewerTank) {
        if (!world.map.hasLineOfSight(viewerTank.x, viewerTank.y, tank.x, tank.y)) continue;
      }

      const palette = TEAM_COLORS[tank.colorKey] ?? TEAM_COLORS.neutral;
      ctx.fillStyle = isViewer ? '#ffffff' : palette.body;
      const size = isViewer || tank.isPlayerControlled ? 4 : 3;
      ctx.fillRect(tank.x * sx - size / 2, tank.y * sy - size / 2, size, size);
    }

    // Рамка области просмотра.
    const vp = player.viewport;
    ctx.strokeStyle = 'rgba(120,220,120,0.7)';
    ctx.lineWidth = 1;
    ctx.strokeRect(
      (player.camera.x - vp.w / 2) * sx,
      (player.camera.y - vp.h / 2) * sy,
      vp.w * sx,
      vp.h * sy,
    );
  }

  #renderMapCache(map) {
    if (this.mapCache.width !== map.cols || this.mapCache.height !== map.rows) {
      this.mapCache.width = map.cols;
      this.mapCache.height = map.rows;
    }
    const ctx = this.mapCacheCtx;
    ctx.fillStyle = '#20201a';
    ctx.fillRect(0, 0, map.cols, map.rows);
    for (let r = 0; r < map.rows; r++) {
      for (let c = 0; c < map.cols; c++) {
        const tile = map.get(r, c);
        if (tile === T.EMPTY) continue;
        switch (tile) {
          case T.WALL:
            ctx.fillStyle = '#707070';
            break;
          case T.BRICK:
            ctx.fillStyle = '#8a8278';
            break;
          case T.WATER:
            ctx.fillStyle = '#2b3a8f';
            break;
          case T.SAND:
            ctx.fillStyle = '#c9b878';
            break;
          case T.TREE:
            ctx.fillStyle = '#245a33';
            break;
          case T.BASE_P:
            ctx.fillStyle = COLORS.baseP;
            break;
          case T.BASE_E:
            ctx.fillStyle = COLORS.baseE;
            break;
          default:
            continue;
        }
        ctx.fillRect(c, r, 1, 1);
      }
    }
  }
}

function inView(x, y, view, margin) {
  return x >= view.x0 - margin && x <= view.x1 + margin && y >= view.y0 - margin && y <= view.y1 + margin;
}

/** Короткая иконка перка бота для подписи над танком. */
function botIcon(id) {
  switch (id) {
    case 'bot_rapid':
      return '⚡';
    case 'bot_speed':
      return '👟';
    case 'bot_tough':
      return '🛡';
    case 'bot_double':
      return '🔫';
    case 'bot_accurate':
      return '🎯';
    case 'bot_regen':
      return '❤';
    case 'bot_heavy':
      return '💥';
    case 'bot_evasion':
      return '💨';
    default:
      return '';
  }
}
