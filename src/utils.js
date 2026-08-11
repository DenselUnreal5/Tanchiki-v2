// ============================================================================
// utils.js — мелкие математические и общие помощники без побочных эффектов.
// ============================================================================

/** Быстрый детерминированный ГПСЧ. Один и тот же seed → одна и та же карта. */
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function dist(x1, y1, x2, y2) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  return Math.sqrt(dx * dx + dy * dy);
}

export function dist2(x1, y1, x2, y2) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  return dx * dx + dy * dy;
}

export function clamp(v, min, max) {
  return v < min ? min : v > max ? max : v;
}

export function lerp(a, b, t) {
  return a + (b - a) * t;
}

/** Приводит угол к диапазону (-PI, PI]. */
export function normalizeAngle(a) {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a <= -Math.PI) a += Math.PI * 2;
  return a;
}

/** Кратчайшая разница между углами, с учётом перехода через PI. */
export function angleDelta(from, to) {
  return normalizeAngle(to - from);
}

/** Плавный поворот к целевому углу с ограничением скорости. */
export function rotateToward(current, target, maxStep) {
  const d = angleDelta(current, target);
  if (Math.abs(d) <= maxStep) return normalizeAngle(target);
  return normalizeAngle(current + Math.sign(d) * maxStep);
}

export function randRange(rng, min, max) {
  return min + rng() * (max - min);
}

export function randInt(rng, min, maxExclusive) {
  return min + Math.floor(rng() * (maxExclusive - min));
}

export function choice(rng, arr) {
  return arr.length ? arr[Math.floor(rng() * arr.length)] : undefined;
}

/** Тасование Фишера—Йетса. Возвращает новый массив. */
export function shuffled(rng, arr) {
  const out = arr.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/**
 * Удаляет из массива элементы, не прошедшие проверку, изменяя массив на месте.
 * Быстрее, чем filter, и не создаёт мусор каждый тик.
 */
export function pruneInPlace(arr, keep) {
  let w = 0;
  for (let i = 0; i < arr.length; i++) {
    if (keep(arr[i])) arr[w++] = arr[i];
  }
  arr.length = w;
  return arr;
}

/** Форматирует число с разделителями разрядов. */
export function fmt(n) {
  return Math.round(n).toLocaleString('ru-RU');
}

/**
 * Автоопределение адреса онлайн-сервера.
 * На HTTPS-хостинге предполагается WebSocket-прокси на том же домене
 * (wss://host/ws). Локально (http) — ws://hostname:8123.
 */
export function defaultServerUrl() {
  if (typeof location === 'undefined') return 'ws://localhost:8123';
  const { protocol, host, hostname } = location;
  if (protocol === 'https:' || protocol === 'wss:') return `wss://${host}/ws`;
  return `ws://${hostname}:8123`;
}
