// ============================================================================
// audio.js — процедурные звуки на Web Audio API, без файлов ассетов.
// Отличия от старой версии: единый ограничитель голосов (иначе 22 бота
// одновременно перегружали микшер) и корректное освобождение узлов.
// ============================================================================

/** Не более чем один звук данного типа за столько тиков. */
const THROTTLE = {
  shoot: 3,
  hit: 3,
  explosion: 4,
  water: 10,
  pickup: 0,
  levelup: 0,
  flag: 0,
  unlock: 0,
  airstrike: 0,
};

export class Audio {
  constructor() {
    this.ctx = null;
    this.enabled = true;
    this.master = null;
    /** @type {Map<string, number>} последний тик воспроизведения по типу */
    this.lastPlayed = new Map();
    this.tick = 0;
    this.voices = 0;
    this.maxVoices = 16;
    this.#bindUnlock();
  }

  /**
   * Первое взаимодействие с игрой (клик, клавиша, касание) создаёт контекст.
   * Без этого Chrome/Edge держат AudioContext в состоянии 'suspended' до жеста
   * пользователя, и игра первое время молчит.
   */
  #bindUnlock() {
    const unlock = () => {
      this.init();
      window.removeEventListener('pointerdown', unlock);
      window.removeEventListener('keydown', unlock);
      window.removeEventListener('touchstart', unlock);
    };
    window.addEventListener('pointerdown', unlock);
    window.addEventListener('keydown', unlock);
    window.addEventListener('touchstart', unlock);
  }

  /** Должно вызываться из обработчика пользовательского ввода. */
  init() {
    if (!this.ctx) {
      const Ctor = window.AudioContext || window.webkitAudioContext;
      if (!Ctor) return false;
      try {
        this.ctx = new Ctor();
        this.master = this.ctx.createGain();
        this.master.gain.value = 0.55;
        this.master.connect(this.ctx.destination);
      } catch {
        this.ctx = null;
        return false;
      }
    }
    if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
    return true;
  }

  setEnabled(on) {
    this.enabled = on;
    if (this.master) this.master.gain.value = on ? 0.55 : 0;
  }

  /** Вызывается один раз за логический тик, чтобы работал троттлинг. */
  advance() {
    this.tick++;
  }

  play(type) {
    if (!this.enabled || !this.ctx || this.voices >= this.maxVoices) return;
    const gap = THROTTLE[type] ?? 0;
    if (gap > 0) {
      const last = this.lastPlayed.get(type);
      if (last !== undefined && this.tick - last < gap) return;
    }
    this.lastPlayed.set(type, this.tick);

    try {
      if (type === 'explosion' || type === 'water') this.#noise(type);
      else this.#tone(type);
    } catch {
      /* звук не критичен для игры */
    }
  }

  #track(node, stopAt) {
    this.voices++;
    const release = () => {
      this.voices = Math.max(0, this.voices - 1);
      try {
        node.disconnect();
      } catch {
        /* уже отключён */
      }
    };
    node.onended = release;
    // Страховка: если onended не придёт, освободим голос по таймеру.
    setTimeout(release, Math.max(50, (stopAt - this.ctx.currentTime) * 1000 + 120));
  }

  #noise(type) {
    const ctx = this.ctx;
    const now = ctx.currentTime;
    const dur = type === 'explosion' ? 0.3 : 0.2;
    const len = Math.floor(ctx.sampleRate * dur);
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < len; i++) {
      const decay = 1 - i / len;
      data[i] = (Math.random() * 2 - 1) * decay * decay;
    }
    const src = ctx.createBufferSource();
    src.buffer = buf;
    const g = ctx.createGain();
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = type === 'explosion' ? 900 : 1600;
    src.connect(lp);
    lp.connect(g);
    g.connect(this.master);
    g.gain.setValueAtTime(type === 'explosion' ? 0.3 : 0.16, now);
    g.gain.exponentialRampToValueAtTime(0.001, now + dur);
    src.start(now);
    src.stop(now + dur);
    this.#track(src, now + dur);
  }

  #tone(type) {
    const ctx = this.ctx;
    const now = ctx.currentTime;
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.connect(g);
    g.connect(this.master);
    let stop = now + 0.1;

    switch (type) {
      case 'shoot':
        osc.type = 'square';
        osc.frequency.setValueAtTime(760, now);
        osc.frequency.exponentialRampToValueAtTime(190, now + 0.08);
        g.gain.setValueAtTime(0.11, now);
        g.gain.exponentialRampToValueAtTime(0.001, now + 0.08);
        stop = now + 0.08;
        break;
      case 'hit':
        osc.type = 'sine';
        osc.frequency.setValueAtTime(300, now);
        osc.frequency.exponentialRampToValueAtTime(100, now + 0.05);
        g.gain.setValueAtTime(0.09, now);
        g.gain.exponentialRampToValueAtTime(0.001, now + 0.05);
        stop = now + 0.05;
        break;
      case 'levelup':
        osc.type = 'sine';
        osc.frequency.setValueAtTime(523, now);
        osc.frequency.setValueAtTime(659, now + 0.1);
        osc.frequency.setValueAtTime(784, now + 0.2);
        g.gain.setValueAtTime(0.13, now);
        g.gain.exponentialRampToValueAtTime(0.001, now + 0.36);
        stop = now + 0.36;
        break;
      case 'unlock':
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(660, now);
        osc.frequency.setValueAtTime(880, now + 0.09);
        osc.frequency.setValueAtTime(1320, now + 0.18);
        g.gain.setValueAtTime(0.12, now);
        g.gain.exponentialRampToValueAtTime(0.001, now + 0.4);
        stop = now + 0.4;
        break;
      case 'pickup':
        osc.type = 'sine';
        osc.frequency.setValueAtTime(440, now);
        osc.frequency.exponentialRampToValueAtTime(880, now + 0.12);
        g.gain.setValueAtTime(0.1, now);
        g.gain.exponentialRampToValueAtTime(0.001, now + 0.12);
        stop = now + 0.12;
        break;
      case 'flag':
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(600, now);
        osc.frequency.setValueAtTime(800, now + 0.07);
        osc.frequency.setValueAtTime(1000, now + 0.14);
        g.gain.setValueAtTime(0.11, now);
        g.gain.exponentialRampToValueAtTime(0.001, now + 0.26);
        stop = now + 0.26;
        break;
      case 'airstrike':
        osc.type = 'sawtooth';
        osc.frequency.setValueAtTime(1200, now);
        osc.frequency.exponentialRampToValueAtTime(120, now + 0.9);
        g.gain.setValueAtTime(0.16, now);
        g.gain.exponentialRampToValueAtTime(0.001, now + 0.9);
        stop = now + 0.9;
        break;
      default:
        return;
    }
    osc.start(now);
    osc.stop(stop);
    this.#track(osc, stop);
  }
}
