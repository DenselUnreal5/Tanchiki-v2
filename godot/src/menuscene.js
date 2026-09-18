// ============================================================================
// menuscene.js — анимированный фон главного меню.
//
// Ночное поле боя под грозой: косой дождь, редкие молнии с вспышками, скала,
// на которой стоит танк, и обгоревшие остовы танков с тлеющим огнём.
// Всё рисуется процедурно в canvas, без ассетов.
// ============================================================================

const DROP_MAX = 220;       // потолок капель дождя
const FLAME_MAX = 90;       // потолок частиц огня
const SMOKE_MAX = 40;       // потолок частиц дыма

const FLAME_COLORS = ['#ffdd44', '#ffaa00', '#ff6600', '#ff3300'];
const EMBER_COLORS = ['#fff6cc', '#ffcc44'];

/** Случайное число между min и max. */
function rnd(min, max) {
  return min + Math.random() * (max - min);
}

export class MenuScene {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.w = 0;
    this.h = 0;
    this.time = 0;

    this.drops = [];
    this.flames = [];
    this.smoke = [];
    this.embers = [];

    // Молния: яркость вспышки, обратный отсчёт и точки разряда.
    this.flash = 0;
    this.flashTimer = rnd(60, 160);
    this.bolt = null;
    this.boltLife = 0;

    // Танк: периодический выстрел (отдача + вспышка в дуле).
    this.shotTimer = 0;
    this.recoil = 0;
    this.muzzle = 0;

    this.resize(
      document.documentElement.clientWidth || window.innerWidth,
      document.documentElement.clientHeight || window.innerHeight,
    );
  }

  resize(w, h) {
    this.w = Math.max(320, w);
    this.h = Math.max(240, h);
    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = Math.round(this.w * dpr);
    this.canvas.height = Math.round(this.h * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.#fillRain();
  }

  #fillRain() {
    const count = Math.min(DROP_MAX, Math.round((this.w * this.h) / 9000));
    this.drops.length = 0;
    for (let i = 0; i < count; i++) {
      this.drops.push({
        x: Math.random() * this.w,
        y: Math.random() * this.h,
        speed: rnd(13, 26),
        len: rnd(12, 30),
      });
    }
  }

  update() {
    this.time++;
    this.#updateRain();
    this.#updateFlames();
    this.#updateLightning();
    this.#updateShot();
  }

  // ------------------------------------------------------------- дождь
  #updateRain() {
    const tilt = 0.22; // ветер относит капли влево
    for (const d of this.drops) {
      d.x -= tilt * d.speed;
      d.y += d.speed;
      if (d.y > this.h + d.len) {
        d.y = -d.len;
        d.x = Math.random() * this.w;
      }
      if (d.x < -d.len) d.x = this.w;
    }
  }

  // ------------------------------------------------------------- пламя
  #spawnFlame(x, y) {
    if (this.flames.length >= FLAME_MAX) return;
    this.flames.push({
      x: x + rnd(-6, 6),
      y,
      vy: rnd(-1.6, -0.7),
      vx: rnd(-0.5, 0.5),
      size: rnd(2, 5),
      life: rnd(20, 42),
      maxLife: 42,
      color: FLAME_COLORS[(Math.random() * FLAME_COLORS.length) | 0],
    });
    if (Math.random() < 0.4 && this.embers.length < 120) {
      this.embers.push({
        x: x + rnd(-8, 8),
        y: y + rnd(-4, 2),
        vy: rnd(-2.6, -1.4),
        vx: rnd(-1, 1),
        size: rnd(0.8, 1.8),
        life: rnd(16, 30),
        maxLife: 30,
        color: EMBER_COLORS[(Math.random() * EMBER_COLORS.length) | 0],
      });
    }
  }

  #updateFlames() {
    // Два очага огня — по одному на каждый горящий остов.
    const groundY = this.h * 0.72;
    this.#spawnFlame(this.w * 0.30, groundY - 26);
    this.#spawnFlame(this.w * 0.52, groundY - 20);
    this.#spawnFlame(this.w * 0.93, groundY - 30);
    this.#spawnFlame(this.w * 0.30, groundY - 40);
    this.#spawnFlame(this.w * 0.52, groundY - 34);

    let w = 0;
    for (const p of this.flames) {
      if (--p.life > 0) {
        p.x += p.vx + Math.sin(this.time * 0.3 + p.x) * 0.25;
        p.y += p.vy;
        p.vy *= 0.985;
        this.flames[w++] = p;
      }
    }
    this.flames.length = w;

    let ew = 0;
    for (const p of this.embers) {
      if (--p.life > 0) {
        p.x += p.vx;
        p.y += p.vy;
        p.vy *= 0.97;
        this.embers[ew++] = p;
      }
    }
    this.embers.length = ew;

    // Дым над огнём.
    if (this.smoke.length < SMOKE_MAX && Math.random() < 0.5) {
      this.smoke.push({
        x: this.w * 0.52 + rnd(-5, 5),
        y: groundY - 40,
        vy: rnd(-0.8, -0.4),
        vx: rnd(-0.2, 0.2),
        size: rnd(4, 9),
        life: rnd(50, 90),
        maxLife: 90,
      });
    }
    let sw = 0;
    for (const p of this.smoke) {
      if (--p.life > 0) {
        p.x += p.vx;
        p.y += p.vy;
        p.size += 0.12;
        this.smoke[sw++] = p;
      }
    }
    this.smoke.length = sw;
  }

  // ------------------------------------------------------------- молния
  #updateLightning() {
    if (--this.flashTimer > 0) return;
    this.flashTimer = Math.round(rnd(400, 820)); // 7–14 сек
    this.flash = 1;
    this.boltLife = 6;
    this.bolt = this.#makeBolt();
  }

  #makeBolt() {
    let x = this.w * rnd(0.35, 0.65);
    let y = 0;
    const targetY = this.h * rnd(0.32, 0.5);
    const points = [{ x, y }];
    let branch = null;
    while (y < targetY) {
      const step = rnd(24, 46);
      x += rnd(-26, 26);
      y += step;
      points.push({ x, y });
      // Иногда ответвление.
      if (!branch && Math.random() < 0.45) {
        branch = [{ x, y }];
        let bx = x;
        let by = y;
        const blen = rnd(30, 80);
        let travelled = 0;
        while (travelled < blen) {
          bx += rnd(-18, 10);
          by += rnd(10, 22);
          travelled += 20;
          branch.push({ x: bx, y: by });
        }
      }
    }
    return { points, branch };
  }

  // ------------------------------------------------------------- танк
  #updateShot() {
    if (--this.shotTimer > 0) {
      this.recoil = Math.max(0, this.recoil - 1.2);
      this.muzzle = Math.max(0, this.muzzle - 0.14);
      return;
    }
    this.shotTimer = Math.round(rnd(170, 260)); // ~3–4.5 сек
    this.recoil = 9;
    this.muzzle = 1;
  }

  // ================================================================ отрисовка
  draw() {
    const ctx = this.ctx;
    const { w, h } = this;
    this.#drawSky(ctx);
    this.#drawLightningBolt(ctx);
    this.#drawGround(ctx);
    this.#drawWrecks(ctx);
    this.#drawRock(ctx);
    this.#drawTank(ctx);
    this.#drawFire(ctx);
    this.#drawRain(ctx);
    this.#drawVignette(ctx);
    if (this.flash > 0) this.#drawFlash(ctx);
  }

  #drawSky(ctx) {
    const g = ctx.createLinearGradient(0, 0, 0, this.h);
    g.addColorStop(0, '#070d13');
    g.addColorStop(0.45, '#12181f');
    g.addColorStop(1, '#1c1e22');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, this.w, this.h);

    // Облака — тёмные размытые пятна.
    ctx.save();
    ctx.globalAlpha = 0.5;
    for (let i = 0; i < 7; i++) {
      const cx = ((i * 211 + 53) % this.w);
      const cy = this.h * (0.08 + ((i * 89) % 30) / 100);
      const r = this.w * rnd(0.1, 0.2);
      const cg = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
      cg.addColorStop(0, 'rgba(40,48,58,0.55)');
      cg.addColorStop(1, 'rgba(40,48,58,0)');
      ctx.fillStyle = cg;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  #drawLightningBolt(ctx) {
    if (!this.bolt || this.boltLife <= 0) return;
    const drawSeg = (points) => {
      ctx.beginPath();
      ctx.moveTo(points[0].x, points[0].y);
      for (let i = 1; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y);
      ctx.stroke();
    };
    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    // Широкое сияние.
    ctx.strokeStyle = 'rgba(140,170,255,0.30)';
    ctx.lineWidth = 9;
    drawSeg(this.bolt.points);
    if (this.bolt.branch) drawSeg(this.bolt.branch);
    // Тонкое ядро.
    ctx.strokeStyle = 'rgba(220,235,255,0.95)';
    ctx.lineWidth = 2.5;
    drawSeg(this.bolt.points);
    if (this.bolt.branch) drawSeg(this.bolt.branch);
    ctx.restore();
    this.boltLife--;
  }

  #drawGround(ctx) {
    const y = this.h * 0.72;
    ctx.fillStyle = '#14120f';
    ctx.beginPath();
    ctx.moveTo(0, y);
    // Рваный верхний край.
    for (let x = 0; x <= this.w; x += 60) {
      ctx.lineTo(x, y + 6 + Math.sin(x * 0.02) * 6 + ((x * 37) % 13));
    }
    ctx.lineTo(this.w, this.h);
    ctx.lineTo(0, this.h);
    ctx.closePath();
    ctx.fill();

    // Тёмный градиент к низу.
    const g = ctx.createLinearGradient(0, y, 0, this.h);
    g.addColorStop(0, 'rgba(0,0,0,0)');
    g.addColorStop(1, 'rgba(0,0,0,0.55)');
    ctx.fillStyle = g;
    ctx.fillRect(0, y, this.w, this.h - y);
  }

  #drawWreck(ctx) {
    // Обгоревший остов танка в профиль.
    ctx.fillStyle = '#0d0d0c';
    ctx.beginPath();
    ctx.moveTo(-44, 0);
    ctx.lineTo(-34, -10);
    ctx.lineTo(-26, -24); // снесённая башня
    ctx.lineTo(-8, -28);
    ctx.lineTo(10, -24);
    ctx.lineTo(20, -10);
    ctx.lineTo(30, -12);
    ctx.lineTo(38, -4);
    ctx.lineTo(30, 0);
    ctx.closePath();
    ctx.fill();

    // Обгоревший корпус светлее.
    ctx.fillStyle = '#1a1816';
    ctx.beginPath();
    ctx.moveTo(-34, -4);
    ctx.lineTo(-28, -16);
    ctx.lineTo(8, -22);
    ctx.lineTo(22, -8);
    ctx.lineTo(12, -4);
    ctx.closePath();
    ctx.fill();

    // Пробоина.
    ctx.fillStyle = '#080808';
    ctx.beginPath();
    ctx.arc(-2, -14, 4, 0, Math.PI * 2);
    ctx.fill();

    // Проржавевшие гусеницы.
    ctx.fillStyle = '#241d16';
    ctx.beginPath();
    ctx.roundRect(-40, -4, 76, 6, 3);
    ctx.fill();
  }

  #drawWrecks(ctx) {
    const y = this.h * 0.72;
    ctx.save();
    // Дальний остов, частично скрыт панелью меню.
    ctx.translate(this.w * 0.30, y - 8);
    ctx.scale(1.05, 1.05);
    this.#drawWreck(ctx);
    // Ближний остов справа.
    ctx.translate(this.w * 0.22, 14);
    ctx.scale(1.15, 1.15);
    this.#drawWreck(ctx);
    // Маленький остов у края.
    ctx.translate(this.w * 0.41, -6);
    ctx.scale(0.62, 0.62);
    this.#drawWreck(ctx);
    ctx.restore();
  }

  #drawRock(ctx) {
    const { w, h } = this;
    const bx = w * 0.60;
    const topY = h * 0.56;

    ctx.save();
    // Основание скалы.
    ctx.fillStyle = '#22262b';
    ctx.beginPath();
    ctx.moveTo(bx, h);
    ctx.lineTo(bx - 8, h * 0.72);
    ctx.lineTo(w * 0.58, h * 0.60);
    ctx.lineTo(w * 0.62, topY);          // плато для танка
    ctx.lineTo(w * 0.86, h * 0.57);
    ctx.lineTo(w * 0.97, h * 0.66);
    ctx.lineTo(w, h);
    ctx.closePath();
    ctx.fill();

    // Тени-трещины.
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath();
    ctx.moveTo(w * 0.60, h * 0.60);
    ctx.lineTo(w * 0.66, h * 0.68);
    ctx.lineTo(w * 0.62, h * 0.78);
    ctx.lineTo(w * 0.58, h * 0.72);
    ctx.closePath();
    ctx.fill();

    // Светлый гребень сверху.
    ctx.strokeStyle = 'rgba(150,165,180,0.35)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(w * 0.58, h * 0.60);
    ctx.lineTo(w * 0.62, topY);
    ctx.lineTo(w * 0.86, h * 0.57);
    ctx.stroke();

    // Блик на плато.
    ctx.fillStyle = 'rgba(120,135,150,0.18)';
    ctx.beginPath();
    ctx.roundRect(w * 0.63, topY - 3, w * 0.20, 6, 3);
    ctx.fill();

    // Валуны у подножия.
    ctx.fillStyle = '#1d2126';
    ctx.beginPath();
    ctx.arc(w * 0.88, h * 0.75, 16, Math.PI, 0);
    ctx.fill();
    ctx.fillStyle = '#262b31';
    ctx.beginPath();
    ctx.arc(w * 0.70, h * 0.77, 10, Math.PI, 0);
    ctx.fill();
    ctx.restore();
  }

  #drawTank(ctx) {
    const { w, h } = this;
    // Танк стоит на плато скалы.
    const cx = w * 0.745;
    const baseY = h * 0.56 + 3;
    const scale = Math.max(0.5, Math.min(1.3, w / 1600));

    ctx.save();
    ctx.translate(cx, baseY);
    ctx.scale(scale, scale);

    // Тень под танком.
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.beginPath();
    ctx.ellipse(0, 4, 48, 7, 0, 0, Math.PI * 2);
    ctx.fill();

    // Гусеницы.
    ctx.fillStyle = '#15191c';
    ctx.beginPath();
    ctx.roundRect(-46, -22, 92, 24, 10);
    ctx.fill();
    // Колёса.
    ctx.fillStyle = '#2c3237';
    for (let i = -34; i <= 34; i += 10) {
      ctx.beginPath();
      ctx.arc(i, -10, 4.5, 0, Math.PI * 2);
      ctx.fill();
    }
    // Траки.
    ctx.fillStyle = '#3a4147';
    ctx.fillRect(-44, -20, 88, 3);

    // Корпус.
    ctx.fillStyle = '#3d4a33';
    ctx.beginPath();
    ctx.roundRect(-42, -38, 84, 17, 5);
    ctx.fill();
    // Верхний бронелист.
    ctx.fillStyle = '#4a5a3d';
    ctx.beginPath();
    ctx.moveTo(-42, -38);
    ctx.lineTo(-42, -30);
    ctx.lineTo(42, -30);
    ctx.lineTo(42, -38);
    ctx.lineTo(34, -34);
    ctx.closePath();
    ctx.fill();
    // Люк/ящики на корпусе.
    ctx.fillStyle = '#333e2c';
    ctx.fillRect(14, -36, 12, 6);

    // Башня.
    const bob = Math.sin(this.time * 0.02) * 0.6;
    ctx.fillStyle = '#46543a';
    ctx.beginPath();
    ctx.roundRect(-18, -52 + bob, 36, 16, 9);
    ctx.fill();
    ctx.fillStyle = '#55654a';
    ctx.beginPath();
    ctx.arc(0, -44 + bob, 8, 0, Math.PI * 2);
    ctx.fill();
    // Командирский люк.
    ctx.fillStyle = '#2c3526';
    ctx.beginPath();
    ctx.arc(6, -46 + bob, 3, 0, Math.PI * 2);
    ctx.fill();

    // Ствол с отдачей.
    ctx.fillStyle = '#2e3a28';
    ctx.beginPath();
    ctx.roundRect(10 - this.recoil, -50 + bob, 44, 7, 3);
    ctx.fill();
    ctx.fillStyle = '#23301f';
    ctx.beginPath();
    ctx.roundRect(10 - this.recoil, -50 + bob, 44, 3, 3);
    ctx.fill();
    // Дульный тормоз.
    ctx.fillStyle = '#1d281a';
    ctx.fillRect(46 - this.recoil, -52 + bob, 8, 11);

    // Выхлопная труба сзади.
    ctx.fillStyle = '#2a3226';
    ctx.fillRect(-46, -20, 6, 8);

    // Вспышка выстрела.
    if (this.muzzle > 0) {
      const mx = 56 - this.recoil;
      const my = -47 + bob;
      ctx.save();
      ctx.globalAlpha = this.muzzle;
      const glow = ctx.createRadialGradient(mx, my, 0, mx, my, 26);
      glow.addColorStop(0, 'rgba(255,230,120,0.95)');
      glow.addColorStop(0.4, 'rgba(255,150,50,0.5)');
      glow.addColorStop(1, 'rgba(255,120,30,0)');
      ctx.fillStyle = glow;
      ctx.beginPath();
      ctx.arc(mx, my, 26, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }

    ctx.restore();
  }

  #drawFire(ctx) {
    const groundY = this.h * 0.72;
    ctx.save();

    // Дым.
    for (const p of this.smoke) {
      const a = Math.max(0, p.life / p.maxLife) * 0.16;
      ctx.globalAlpha = a;
      ctx.fillStyle = '#55555a';
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
    }

    // Огненные языки.
    for (const p of this.flames) {
      const a = Math.max(0, p.life / p.maxLife);
      ctx.globalAlpha = a;
      ctx.fillStyle = p.color;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
      // Тёплое свечение вокруг.
      if (p.life > p.maxLife * 0.5) {
        ctx.globalAlpha = a * 0.25;
        ctx.fillStyle = '#ff6600';
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size * 2.2, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    // Искры.
    for (const p of this.embers) {
      const a = Math.max(0, p.life / p.maxLife);
      ctx.globalAlpha = a;
      ctx.fillStyle = p.color;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
    }

    // Тёплый отсвет огня на земле.
    const glow = ctx.createRadialGradient(
      this.w * 0.52, groundY, 0,
      this.w * 0.52, groundY, this.w * 0.18,
    );
    glow.addColorStop(0, 'rgba(255,120,40,0.14)');
    glow.addColorStop(1, 'rgba(255,120,40,0)');
    ctx.globalAlpha = 1;
    ctx.fillStyle = glow;
    ctx.fillRect(0, groundY, this.w, this.h - groundY);

    ctx.restore();
  }

  #drawRain(ctx) {
    ctx.save();
    ctx.strokeStyle = 'rgba(160,185,220,0.30)';
    ctx.lineWidth = 1.1;
    ctx.lineCap = 'round';
    ctx.beginPath();
    for (const d of this.drops) {
      ctx.moveTo(d.x, d.y);
      ctx.lineTo(d.x - 0.22 * d.len, d.y + d.len);
    }
    ctx.stroke();
    ctx.restore();
  }

  #drawVignette(ctx) {
    const { w, h } = this;
    const g = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.35, w / 2, h / 2, Math.max(w, h) * 0.75);
    g.addColorStop(0, 'rgba(0,0,0,0)');
    g.addColorStop(1, 'rgba(0,0,0,0.55)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
  }

  #drawFlash(ctx) {
    ctx.fillStyle = `rgba(210,225,255,${(this.flash * 0.22).toFixed(3)})`;
    ctx.fillRect(0, 0, this.w, this.h);
    this.flash *= 0.82;
    if (this.flash < 0.02) this.flash = 0;
  }
}
