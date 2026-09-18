// ============================================================================
// input.js — клавиатура, мышь и схемы управления.
//
// Исправления против старой версии:
//  * Всё читается по e.code (физическая клавиша). Раньше часть кода читала
//    e.key, из-за чего при выключенном NumLock цифровой блок присылал
//    Home/ArrowUp/PageUp: прицеливание второго игрока полностью отваливалось,
//    а Numpad8/2/4/6 приходили как стрелки и вместо наводки двигали танк.
//    Раскладка (русская/английская) тоже больше не имеет значения.
//  * Наводка и выстрел у второго игрока разделены. Раньше нажатие клавиши
//    направления башни немедленно стреляло, прицелиться молча было нельзя.
//  * Зажатые клавиши сбрасываются не только на blur, но и при скрытии
//    вкладки и при потере фокуса окна.
// ============================================================================

/** Клавиши, у которых нужно подавить стандартное поведение браузера. */
const PREVENT_DEFAULT = new Set([
  'ArrowUp',
  'ArrowDown',
  'ArrowLeft',
  'ArrowRight',
  'Space',
  'Tab',
  'Slash',
  'Comma',
  'Period',
  'Numpad0',
  'Numpad1',
  'Numpad2',
  'Numpad3',
  'Numpad4',
  'Numpad5',
  'Numpad6',
  'Numpad7',
  'Numpad8',
  'Numpad9',
  'NumpadDecimal',
  'NumpadEnter',
  'NumpadAdd',
  'NumpadSubtract',
]);

export class Input {
  constructor(canvas) {
    this.canvas = canvas;
    /** @type {Set<string>} нажатые физические клавиши */
    this.down = new Set();
    this.mouse = { x: 0, y: 0, left: false, right: false, inside: false };
    /** @type {Map<string, Function[]>} */
    this.listeners = new Map();
    this.#bind();
  }

  on(event, fn) {
    if (!this.listeners.has(event)) this.listeners.set(event, []);
    this.listeners.get(event).push(fn);
    return this;
  }

  #emit(event, payload) {
    for (const fn of this.listeners.get(event) ?? []) {
      try {
        fn(payload);
      } catch (e) {
        console.error('[input] обработчик упал:', e);
      }
    }
  }

  isDown(code) {
    return this.down.has(code);
  }

  /** Любая из перечисленных клавиш нажата. */
  anyDown(codes) {
    for (const c of codes) if (this.down.has(c)) return true;
    return false;
  }

  clear() {
    this.down.clear();
    this.mouse.left = false;
    this.mouse.right = false;
  }

  #bind() {
    window.addEventListener('keydown', (e) => {
      if (PREVENT_DEFAULT.has(e.code) && !e.ctrlKey && !e.metaKey && !e.altKey) e.preventDefault();
      if (e.repeat) return;
      this.down.add(e.code);
      this.#emit('down', e.code);
    });

    window.addEventListener('keyup', (e) => {
      this.down.delete(e.code);
      this.#emit('up', e.code);
    });

    // Зажатые клавиши «залипают», если keyup ушёл в другое окно.
    const release = () => this.clear();
    window.addEventListener('blur', release);
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) release();
    });

    const updateMouse = (e) => {
      const rect = this.canvas.getBoundingClientRect();
      // Учитываем возможное несовпадение размера буфера канваса и CSS-размера.
      // Буфер увеличен на devicePixelRatio — делим обратно, чтобы координаты
      // мыши оставались в логических (CSS) пикселях.
      const dpr = window.devicePixelRatio || 1;
      const scaleX = (this.canvas.width / dpr) / rect.width;
      const scaleY = (this.canvas.height / dpr) / rect.height;
      this.mouse.x = (e.clientX - rect.left) * scaleX;
      this.mouse.y = (e.clientY - rect.top) * scaleY;
      this.mouse.inside =
        e.clientX >= rect.left &&
        e.clientX <= rect.right &&
        e.clientY >= rect.top &&
        e.clientY <= rect.bottom;
    };

    window.addEventListener('mousemove', updateMouse);
    window.addEventListener('mousedown', (e) => {
      updateMouse(e);
      if (e.button === 0) this.mouse.left = true;
      if (e.button === 2) this.mouse.right = true;
      this.#emit('mousedown', e.button);
    });
    window.addEventListener('mouseup', (e) => {
      if (e.button === 0) this.mouse.left = false;
      if (e.button === 2) this.mouse.right = false;
    });
    window.addEventListener('contextmenu', (e) => e.preventDefault());
  }
}

// ============================================================================
// Схемы управления
// ============================================================================

/**
 * @typedef {object} ControlScheme
 * @property {(tank: import('./tank.js').Tank, player: import('./player.js').Player, world: object) => void} apply
 * @property {string[]} hints подсказки для меню
 */

import { applyCommand } from './commands.js';

const CODES = {
  wasd: { up: 'KeyW', down: 'KeyS', left: 'KeyA', right: 'KeyD' },
  arrows: { up: 'ArrowUp', down: 'ArrowDown', left: 'ArrowLeft', right: 'ArrowRight' },
  numpadMove: { up: 'Numpad8', down: 'Numpad2', left: 'Numpad4', right: 'Numpad6' },
};

/** Управление мышью: WASD + прицел мышью. Основная схема первого игрока. */
export class MouseAimScheme {
  /**
   * @param {Input} input
   * @param {boolean} allowArrows разрешить стрелки как дубль WASD (одиночная игра)
   */
  constructor(input, allowArrows = true) {
    this.input = input;
    this.allowArrows = allowArrows;
  }

  get hints() {
    return [
      '<kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> движение',
      '<kbd>мышь</kbd> прицел',
      '<kbd>ЛКМ</kbd> / <kbd>Space</kbd> выстрел',
      '<kbd>E</kbd> / <kbd>ПКМ</kbd> мина',
      '<kbd>Shift</kbd> рывок-таран',
      '<kbd>F</kbd> авиаудар (Оборона)',
    ];
  }

  apply(tank, player, world) {
    applyCommand(tank, world, this.readCommand(player));
  }

  /**
   * Собирает команду из текущего состояния ввода. Сеть шлёт именно её.
   * Прицел переводится через ЛИЧНУЮ область просмотра игрока: в «горячем
   * стуле» и онлайне у каждого своя камера.
   */
  readCommand(player) {
    const i = this.input;
    let mx = 0;
    let my = 0;
    if (i.isDown(CODES.wasd.up) || (this.allowArrows && i.isDown(CODES.arrows.up))) my -= 1;
    if (i.isDown(CODES.wasd.down) || (this.allowArrows && i.isDown(CODES.arrows.down))) my += 1;
    if (i.isDown(CODES.wasd.left) || (this.allowArrows && i.isDown(CODES.arrows.left))) mx -= 1;
    if (i.isDown(CODES.wasd.right) || (this.allowArrows && i.isDown(CODES.arrows.right))) mx += 1;

    const w = player.screenToWorld(i.mouse.x, i.mouse.y);
    return {
      mx,
      my,
      ax: w.x,
      ay: w.y,
      fire: i.mouse.left || i.isDown('Space'),
      mine: i.isDown('KeyE') || i.mouse.right,
      dash: i.isDown('ShiftLeft'),
      airstrike: i.isDown('KeyF'),
    };
  }
}

/**
 * Клавиатурная схема второго игрока («горячий стул»).
 *
 * Стрелки или Numpad 8/4/6/2 — движение. Башня по умолчанию доворачивается
 * в сторону движения, а если держать клавиши поворота (< >, Numpad 7/9),
 * она управляется вручную и сохраняет угол после отпускания.
 */
export class KeyboardAimScheme {
  constructor(input) {
    this.input = input;
    this.turretSlew = 0.07; // рад/тик при ручном повороте
    this.followSlew = 0.05; // рад/тик при доворотe за корпусом
  }

  get hints() {
    return [
      '<kbd>↑</kbd><kbd>←</kbd><kbd>↓</kbd><kbd>→</kbd> движение',
      '<kbd>&lt;</kbd><kbd>&gt;</kbd> поворот башни',
      '<kbd>Правый Shift</kbd> / <kbd>Num 0</kbd> выстрел',
      '<kbd>Num .</kbd> / <kbd>Правый Ctrl</kbd> мина',
      '<kbd>Левый Shift</kbd> рывок-таран',
    ];
  }

  apply(tank, player, world) {
    const i = this.input;
    let dx = 0;
    let dy = 0;
    if (i.isDown(CODES.arrows.up) || i.isDown(CODES.numpadMove.up)) dy -= 1;
    if (i.isDown(CODES.arrows.down) || i.isDown(CODES.numpadMove.down)) dy += 1;
    if (i.isDown(CODES.arrows.left) || i.isDown(CODES.numpadMove.left)) dx -= 1;
    if (i.isDown(CODES.arrows.right) || i.isDown(CODES.numpadMove.right)) dx += 1;
    const moving = dx !== 0 || dy !== 0;
    tank.thrust(dx, dy);

    const rotLeft = i.isDown('Comma') || i.isDown('Numpad7');
    const rotRight = i.isDown('Period') || i.isDown('Numpad9');

    if (rotLeft && !rotRight) {
      tank.turretAngle -= this.turretSlew;
    } else if (rotRight && !rotLeft) {
      tank.turretAngle += this.turretSlew;
    } else if (moving) {
      // Ручного поворота нет — башня плавно смотрит туда, куда едем.
      tank.turretAngle = approach(tank.turretAngle, tank.angle, this.followSlew);
    }

    if (i.anyDown(['ShiftRight', 'Numpad0', 'Numpad5', 'Slash', 'NumpadEnter', 'Enter'])) {
      tank.shoot(world);
    }
    if (i.anyDown(['NumpadDecimal', 'Delete', 'ControlRight'])) tank.placeMine(world);
    if (i.isDown('ShiftLeft')) tank.dash();
  }
}

/** Плавное приближение угла с учётом перехода через PI. */
function approach(current, target, step) {
  let d = target - current;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d <= -Math.PI) d += Math.PI * 2;
  if (Math.abs(d) <= step) return target;
  return current + Math.sign(d) * step;
}
