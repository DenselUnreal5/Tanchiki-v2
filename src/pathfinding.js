// ============================================================================
// pathfinding.js — A* по тайловой сетке.
//
// Реализация переиспользует буферы между вызовами: до 22 ботов ищут путь
// каждые ~60 тиков, и аллокация Map/Set на каждый вызов заметно нагружала GC.
// Есть жёсткий лимит раскрытых узлов, чтобы одиночный безнадёжный запрос
// не съедал кадр.
// ============================================================================

import { COLS, ROWS, TILE } from './config.js';

const SQRT2 = Math.SQRT2;
/** Максимум раскрытых узлов на один запрос. */
const NODE_BUDGET = 4000;

/** Минимальная бинарная куча по f-оценке. */
class MinHeap {
  constructor(capacity) {
    this.items = new Int32Array(capacity);
    this.keys = new Float64Array(capacity);
    this.size = 0;
  }

  clear() {
    this.size = 0;
  }

  push(item, key) {
    if (this.size >= this.items.length) return; // переполнение — запрос всё равно оборвётся по бюджету
    let i = this.size++;
    this.items[i] = item;
    this.keys[i] = key;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (this.keys[parent] <= this.keys[i]) break;
      this.#swap(i, parent);
      i = parent;
    }
  }

  pop() {
    const top = this.items[0];
    this.size--;
    if (this.size > 0) {
      this.items[0] = this.items[this.size];
      this.keys[0] = this.keys[this.size];
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let smallest = i;
        if (l < this.size && this.keys[l] < this.keys[smallest]) smallest = l;
        if (r < this.size && this.keys[r] < this.keys[smallest]) smallest = r;
        if (smallest === i) break;
        this.#swap(i, smallest);
        i = smallest;
      }
    }
    return top;
  }

  #swap(a, b) {
    const ti = this.items[a];
    this.items[a] = this.items[b];
    this.items[b] = ti;
    const tk = this.keys[a];
    this.keys[a] = this.keys[b];
    this.keys[b] = tk;
  }
}

const CELLS = ROWS * COLS;
const gScore = new Float64Array(CELLS);
const cameFrom = new Int32Array(CELLS);
const visitGen = new Int32Array(CELLS); // «поколение» посещения вместо очистки массивов
const closed = new Uint8Array(CELLS);
const heap = new MinHeap(CELLS);
let generation = 0;

/**
 * Ищет маршрут по проезжаемым тайлам.
 * @returns {{x:number,y:number}[]} путевые точки в пикселях (без стартовой)
 */
export function findPath(map, startX, startY, endX, endY) {
  const cols = map.cols;
  const startCol = Math.floor(startX / TILE);
  const startRow = Math.floor(startY / TILE);
  let endCol = Math.floor(endX / TILE);
  let endRow = Math.floor(endY / TILE);

  if (!map.inBounds(startRow, startCol)) return [];

  // Если цель в стене или воде — берём ближайший проезжаемый тайл рядом.
  if (!map.isDrivable(endRow, endCol)) {
    const alt = nearestDrivable(map, endRow, endCol, 6);
    if (!alt) return [];
    endRow = alt.row;
    endCol = alt.col;
  }

  const start = startRow * cols + startCol;
  const goal = endRow * cols + endCol;
  if (start === goal) return [];

  const gen = ++generation;
  heap.clear();
  gScore[start] = 0;
  cameFrom[start] = -1;
  visitGen[start] = gen;
  closed[start] = 0;
  heap.push(start, heuristic(startRow, startCol, endRow, endCol));

  let expanded = 0;
  let bestNode = start;
  let bestH = heuristic(startRow, startCol, endRow, endCol);

  while (heap.size > 0) {
    const current = heap.pop();
    if (closed[current] === 1 && visitGen[current] === gen) continue;
    closed[current] = 1;
    visitGen[current] = gen;

    if (current === goal) return reconstruct(map, current, gen);
    if (++expanded > NODE_BUDGET) break;

    const cr = (current / cols) | 0;
    const cc = current % cols;
    const h = heuristic(cr, cc, endRow, endCol);
    if (h < bestH) {
      bestH = h;
      bestNode = current;
    }

    for (let dr = -1; dr <= 1; dr++) {
      for (let dc = -1; dc <= 1; dc++) {
        if (dr === 0 && dc === 0) continue;
        const nr = cr + dr;
        const nc = cc + dc;
        if (!map.isDrivable(nr, nc)) continue;
        // По диагонали нельзя «срезать» угол между двумя стенами.
        if (dr !== 0 && dc !== 0) {
          if (!map.isDrivable(cr + dr, cc) || !map.isDrivable(cr, cc + dc)) continue;
        }
        const next = nr * cols + nc;
        if (visitGen[next] === gen && closed[next] === 1) continue;
        const step = dr !== 0 && dc !== 0 ? SQRT2 : 1;
        const tentative = gScore[current] + step;
        const seen = visitGen[next] === gen;
        if (seen && tentative >= gScore[next]) continue;
        visitGen[next] = gen;
        closed[next] = 0;
        gScore[next] = tentative;
        cameFrom[next] = current;
        heap.push(next, tentative + heuristic(nr, nc, endRow, endCol));
      }
    }
  }

  // Полного пути нет — идём хотя бы в сторону цели, до ближайшего найденного узла.
  if (bestNode !== start) return reconstruct(map, bestNode, gen);
  return [];
}

function heuristic(r1, c1, r2, c2) {
  const dr = Math.abs(r1 - r2);
  const dc = Math.abs(c1 - c2);
  // Восьминаправленная (октильная) метрика — согласована с ценой шага.
  return (dr + dc) + (SQRT2 - 2) * Math.min(dr, dc);
}

function reconstruct(map, node, gen) {
  const raw = [];
  let cur = node;
  let guard = 0;
  while (cur !== -1 && guard++ < CELLS) {
    raw.push(cur);
    if (visitGen[cur] !== gen) break;
    cur = cameFrom[cur];
  }
  raw.reverse();
  // Первый элемент — стартовый тайл, он не нужен.
  const cells = raw.slice(1);
  return smooth(map, cells);
}

/**
 * Убирает лишние точки: если из точки A видно точку C по чистой прямой
 * (без прорезания углов), промежуточная B не нужна. Используется именно
 * corner-safe проверка, потому что бот едет прямо к путевой точке, и если та
 * окажется у стены «наискосок» — он упрётся в угол и будет толкаться в стену.
 */
function smooth(map, cells) {
  const cols = map.cols;
  const points = cells.map((cell) => ({
    x: (cell % cols) * TILE + TILE / 2,
    y: (((cell / cols) | 0) * TILE) + TILE / 2,
  }));
  if (points.length <= 2) return points;

  const out = [];
  let anchor = 0;
  while (anchor < points.length - 1) {
    let furthest = anchor + 1;
    for (let j = points.length - 1; j > anchor + 1; j--) {
      if (map.hasDrivableSegment(points[anchor].x, points[anchor].y, points[j].x, points[j].y)) {
        furthest = j;
        break;
      }
    }
    out.push(points[furthest]);
    anchor = furthest;
  }
  return out;
}

/** Поиск ближайшего проезжаемого тайла в радиусе. */
function nearestDrivable(map, row, col, radius) {
  for (let rad = 1; rad <= radius; rad++) {
    for (let dr = -rad; dr <= rad; dr++) {
      for (let dc = -rad; dc <= rad; dc++) {
        if (Math.max(Math.abs(dr), Math.abs(dc)) !== rad) continue;
        if (map.isDrivable(row + dr, col + dc)) return { row: row + dr, col: col + dc };
      }
    }
  }
  return null;
}
