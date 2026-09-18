// ============================================================================
// map.js — тайловая карта и генерация уровней.
//
// Что исправлено против старой версии:
//  * карта хранится в типизированном массиве, а не в массиве массивов;
//  * добавлен проход, который гарантирует связность карты. Раньше генератор
//    мог запереть область стенами: бот с A* не находил путь и вставал
//    на месте, а спавн мог оказаться в изолированном кармане;
//  * генерация полностью детерминирована от seed (Math.random больше не
//    используется внутри генератора).
// ============================================================================

import { COLS, ROWS, TILE, MAP_W, MAP_H, T, MODES } from './config.js';
import { mulberry32, dist } from './utils.js';

/** Тайлы, сквозь которые не проехать. */
export function isSolidTile(tile) {
  return tile === T.WALL || tile === T.BRICK;
}

/** Тайлы, по которым бот согласен строить маршрут. */
export function isDrivableTile(tile) {
  return tile === T.EMPTY || tile === T.TREE || tile === T.BASE_P || tile === T.BASE_E || tile === T.SAND;
}

export class GameMap {
  constructor(cols = COLS, rows = ROWS) {
    this.cols = cols;
    this.rows = rows;
    this.tiles = new Uint8Array(cols * rows);
    /** Растёт при любом изменении тайла — по нему рендер понимает,
     *  что кэш миникарты пора перерисовать. */
    this.version = 0;
  }

  get width() {
    return this.cols * TILE;
  }

  get height() {
    return this.rows * TILE;
  }

  idx(row, col) {
    return row * this.cols + col;
  }

  inBounds(row, col) {
    return row >= 0 && row < this.rows && col >= 0 && col < this.cols;
  }

  get(row, col) {
    if (!this.inBounds(row, col)) return T.WALL; // за краем — стена
    return this.tiles[row * this.cols + col];
  }

  set(row, col, value) {
    if (!this.inBounds(row, col)) return;
    const i = row * this.cols + col;
    if (this.tiles[i] === value) return;
    this.tiles[i] = value;
    this.version++;
  }

  fill(value) {
    this.tiles.fill(value);
    this.version++;
  }

  colAt(x) {
    return Math.floor(x / TILE);
  }

  rowAt(y) {
    return Math.floor(y / TILE);
  }

  tileAtPixel(x, y) {
    return this.get(Math.floor(y / TILE), Math.floor(x / TILE));
  }

  isWaterAt(x, y) {
    return this.tileAtPixel(x, y) === T.WATER;
  }

  /**
   * Проверяет прямоугольник (центр x,y) на столкновение со стенами.
   * Отступ в 2 px по каждой стороне — как в оригинале, чтобы танк не цеплялся
   * за углы при движении по коридорам.
   */
  isBlockedRect(x, y, w, h) {
    const hw = w / 2 - 2;
    const hh = h / 2 - 2;
    const c0 = Math.floor((x - hw) / TILE);
    const c1 = Math.floor((x + hw) / TILE);
    const r0 = Math.floor((y - hh) / TILE);
    const r1 = Math.floor((y + hh) / TILE);
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        if (!this.inBounds(r, c)) return true;
        if (isSolidTile(this.tiles[r * this.cols + c])) return true;
      }
    }
    return false;
  }

  isDrivable(row, col) {
    return this.inBounds(row, col) && isDrivableTile(this.tiles[row * this.cols + col]);
  }

  /**
   * Проверяет, что прямое движение из точки в точку не пересекает проезжаемые
   * границы, И при этом не «срезает» угол стены.
   *
   * В отличие от hasLineOfSight здесь перечисляются все клетки, которых
   * касается отрезок (включая клетку в вершине сетки — supercover). Обычный
   * DDA в такой ситуации учитывает только одну клетку и «прорезает» стену по
   * диагонали. Танк прямоугольный, в угол не влезает, поэтому маршрут должен
   * этого избегать. Требуется isDrivable (то есть без стены, кирпича и воды).
   */
  hasDrivableSegment(x1, y1, x2, y2) {
    const x0 = x1 / TILE;
    const y0 = y1 / TILE;
    const x1t = x2 / TILE;
    const y1t = y2 / TILE;

    let cx = Math.floor(x0);
    let cy = Math.floor(y0);
    const dx = x1t - x0;
    const dy = y1t - y0;
    const stepX = dx > 0 ? 1 : -1;
    const stepY = dy > 0 ? 1 : -1;
    const tDeltaX = dx !== 0 ? Math.abs(1 / dx) : Infinity;
    const tDeltaY = dy !== 0 ? Math.abs(1 / dy) : Infinity;
    let tMaxX = dx !== 0 ? Math.abs(((dx > 0 ? cx + 1 : cx) - x0) / dx) : Infinity;
    let tMaxY = dy !== 0 ? Math.abs(((dy > 0 ? cy + 1 : cy) - y0) / dy) : Infinity;
    const ex = Math.floor(x1t);
    const ey = Math.floor(y1t);

    let guard = 0;
    const maxSteps = this.cols + this.rows + 4;
    while (guard++ < maxSteps) {
      if (!this.isDrivable(cy, cx)) return false;
      if (cx === ex && cy === ey) return true;
      // Пересечение двух границ одновременно — линия проходит через вершину
      // сетки. Проверяем диагональную клетку вперёд, чтобы не прорезать угол.
      if (Math.abs(tMaxX - tMaxY) < 1e-9) {
        tMaxX += tDeltaX;
        tMaxY += tDeltaY;
        if (!this.isDrivable(cy + stepY, cx + stepX)) return false;
        cx += stepX;
        cy += stepY;
      } else if (tMaxX < tMaxY) {
        tMaxX += tDeltaX;
        cx += stepX;
      } else {
        tMaxY += tDeltaY;
        cy += stepY;
      }
      if (tMaxX > 1 && tMaxY > 1) return true;
    }
    return true;
  }

  /**
   * Есть ли прямая видимость между двумя точками (алгоритм DDA по сетке).
   * Стены и кирпич перекрывают обзор, деревья и вода — нет.
   */
  hasLineOfSight(x1, y1, x2, y2) {
    let col = Math.floor(x1 / TILE);
    let row = Math.floor(y1 / TILE);
    const endCol = Math.floor(x2 / TILE);
    const endRow = Math.floor(y2 / TILE);

    const dx = x2 - x1;
    const dy = y2 - y1;
    const stepC = dx > 0 ? 1 : -1;
    const stepR = dy > 0 ? 1 : -1;
    // Расстояния до следующей границы тайла, в параметре t от 0 до 1.
    const tDeltaC = dx !== 0 ? Math.abs(TILE / dx) : Infinity;
    const tDeltaR = dy !== 0 ? Math.abs(TILE / dy) : Infinity;
    let tMaxC =
      dx !== 0 ? Math.abs(((dx > 0 ? (col + 1) * TILE : col * TILE) - x1) / dx) : Infinity;
    let tMaxR =
      dy !== 0 ? Math.abs(((dy > 0 ? (row + 1) * TILE : row * TILE) - y1) / dy) : Infinity;

    let guard = 0;
    const maxSteps = this.cols + this.rows + 4;
    while (guard++ < maxSteps) {
      if (!this.inBounds(row, col)) return false;
      if (isSolidTile(this.tiles[row * this.cols + col])) return false;
      if (row === endRow && col === endCol) return true;
      if (tMaxC < tMaxR) {
        tMaxC += tDeltaC;
        col += stepC;
      } else {
        tMaxR += tDeltaR;
        row += stepR;
      }
      if (tMaxC > 1 && tMaxR > 1) return true; // дошли до конца отрезка
    }
    return true;
  }

  /**
   * Ищет свободную точку в прямоугольной зоне (в тайлах).
   * Зона с флагом `edge` ограничивает поиск периметром прямоугольника —
   * используется в «Обороне», чтобы враги выходили с краёв карты.
   * Возвращает {x, y} в пикселях либо null, если не нашлось.
   */
  findFreeSpot(rng, area, w, h, tries = 80, avoidWater = true) {
    const r0 = Math.ceil(area.r0);
    const r1 = Math.floor(area.r1);
    const c0 = Math.ceil(area.c0);
    const c1 = Math.floor(area.c1);
    for (let i = 0; i < tries; i++) {
      let c;
      let r;
      if (area.edge) {
        // Периметр: случайная из четырёх сторон.
        const side = Math.floor(rng() * 4);
        if (side === 0) { r = r0; c = c0 + rng() * (c1 - c0); }
        else if (side === 1) { r = r1; c = c0 + rng() * (c1 - c0); }
        else if (side === 2) { c = c0; r = r0 + rng() * (r1 - r0); }
        else { c = c1; r = r0 + rng() * (r1 - r0); }
      } else {
        c = c0 + rng() * (c1 - c0);
        r = r0 + rng() * (r1 - r0);
      }
      const x = c * TILE + TILE / 2;
      const y = r * TILE + TILE / 2;
      if (this.isBlockedRect(x, y, w, h)) continue;
      if (avoidWater && this.isWaterAt(x, y)) continue;
      return { x, y };
    }
    // Аварийный обход: линейный поиск по зоне, чтобы никогда не вернуть null
    // из-за неудачных случайных бросков.
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        if (area.edge && r !== r0 && r !== r1 && c !== c0 && c !== c1) continue;
        const x = c * TILE + TILE / 2;
        const y = r * TILE + TILE / 2;
        if (this.isBlockedRect(x, y, w, h)) continue;
        if (avoidWater && this.isWaterAt(x, y)) continue;
        return { x, y };
      }
    }
    return null;
  }

  /** Разметка связных проезжаемых областей. Возвращает {labels, regions}. */
  labelRegions() {
    const cols = this.cols;
    const rows = this.rows;
    const labels = new Int32Array(cols * rows).fill(-1);
    const regions = [];
    const queue = new Int32Array(cols * rows);
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const start = r * cols + c;
        if (labels[start] !== -1 || !isDrivableTile(this.tiles[start])) continue;
        const id = regions.length;
        let head = 0;
        let tail = 0;
        queue[tail++] = start;
        labels[start] = id;
        const cells = [];
        while (head < tail) {
          const cur = queue[head++];
          cells.push(cur);
          const cr = (cur / cols) | 0;
          const cc = cur % cols;
          for (let k = 0; k < 4; k++) {
            const nr = cr + (k === 0 ? -1 : k === 1 ? 1 : 0);
            const nc = cc + (k === 2 ? -1 : k === 3 ? 1 : 0);
            if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
            const ni = nr * cols + nc;
            if (labels[ni] !== -1 || !isDrivableTile(this.tiles[ni])) continue;
            labels[ni] = id;
            queue[tail++] = ni;
          }
        }
        regions.push(cells);
      }
    }
    return { labels, regions };
  }

  /**
   * Гарантирует, что вся проезжаемая площадь связна: прорубает коридоры
   * от каждой изолированной области к самой большой.
   */
  ensureConnectivity() {
    const { regions } = this.labelRegions();
    if (regions.length <= 1) return 0;
    const cols = this.cols;

    let biggest = 0;
    for (let i = 1; i < regions.length; i++) {
      if (regions[i].length > regions[biggest].length) biggest = i;
    }
    const mainCells = regions[biggest];
    let carved = 0;

    for (let i = 0; i < regions.length; i++) {
      if (i === biggest) continue;
      const cells = regions[i];
      // Берём центр области и ближайшую к нему клетку главной области.
      const from = cells[(cells.length / 2) | 0];
      const fr = (from / cols) | 0;
      const fc = from % cols;
      let best = mainCells[0];
      let bestD = Infinity;
      for (const cell of mainCells) {
        const cr = (cell / cols) | 0;
        const cc = cell % cols;
        const d = Math.abs(cr - fr) + Math.abs(cc - fc);
        if (d < bestD) {
          bestD = d;
          best = cell;
        }
      }
      carved += this.#carveCorridor(fr, fc, (best / cols) | 0, best % cols);
    }
    return carved;
  }

  /** Прорубает Г-образный коридор, не трогая внешнюю рамку карты. */
  #carveCorridor(r0, c0, r1, c1) {
    let carved = 0;
    const put = (r, c) => {
      if (r <= 0 || r >= this.rows - 1 || c <= 0 || c >= this.cols - 1) return;
      const i = r * this.cols + c;
      if (!isDrivableTile(this.tiles[i])) {
        this.tiles[i] = T.EMPTY;
        carved++;
      }
    };
    const stepC = c1 > c0 ? 1 : -1;
    for (let c = c0; c !== c1; c += stepC) put(r0, c);
    const stepR = r1 > r0 ? 1 : -1;
    for (let r = r0; r !== r1; r += stepR) put(r, c1);
    put(r1, c1);
    return carved;
  }
}

// ============================================================================
// Генерация уровня
// ============================================================================

/** Зоны спавна для командных режимов (в тайлах). */
const AREA_PLAYER = (cols, rows) => ({ r0: rows - 7, r1: rows - 3, c0: 2, c1: 8 });
const AREA_ENEMY = (cols, rows) => ({ r0: 2, r1: 6, c0: cols - 9, c1: cols - 3 });
const AREA_ANY = (cols, rows) => ({ r0: 3, r1: rows - 4, c0: 3, c1: cols - 4 });
/** В «Обороне» игроки возрождаются рядом с базой. */
const DEFENSE_PLAYER_AREA = (cols, rows) => ({
  r0: Math.floor(rows / 2) - 3,
  r1: Math.floor(rows / 2) + 3,
  c0: Math.floor(cols / 2) - 3,
  c1: Math.floor(cols / 2) + 3,
});
/**
 * В «Обороне» враги выходят с краёв карты, а не из ниоткуда у базы:
 * полоса по периметру в 4 тайла от рамки, чтобы у защитника было время
 * заметить и перехватить волну до того, как она доедет до центра.
 */
const DEFENSE_ENEMY_AREA = (cols, rows) => ({
  r0: 2,
  r1: rows - 3,
  c0: 2,
  c1: cols - 3,
  edge: true,
});

/**
 * @param {number|'random'} levelNum 1..5 либо 'random'
 * @param {'ffa'|'ctf'} mode
 * @returns {{map: GameMap, seed: number, areas: object, homes: object, flagSpots: object}}
 */
export function generateLevel(levelNum, mode) {
  const seed =
    levelNum === 'random' ? (Math.random() * 0xffffffff) >>> 0 : ((levelNum - 1) * 7777 + 42) >>> 0;
  const rng = mulberry32(seed);
  // В «Обороне» карта в два раза меньше обычной — база в центре, держать её проще.
  const cols = mode === 'defense' ? Math.floor(COLS / 2) : COLS;
  const rows = mode === 'defense' ? Math.floor(ROWS / 2) : ROWS;
  const map = new GameMap(cols, rows);
  map.fill(T.EMPTY);

  // -------------------------------------------------------------- рамка
  for (let r = 0; r < rows; r++) {
    map.set(r, 0, T.WALL);
    map.set(r, cols - 1, T.WALL);
  }
  for (let c = 0; c < cols; c++) {
    map.set(0, c, T.WALL);
    map.set(rows - 1, c, T.WALL);
  }

  // -------------------------------------------------------------- стены
  const spacing = 4 + Math.floor(rng() * 3);
  for (let r = 2; r < rows - 2; r += spacing) {
    for (let c = 2; c < cols - 2; c += spacing) {
      if (rng() >= 0.7) continue;
      map.set(r, c, T.WALL);
      if (rng() < 0.5 && c + 1 < cols - 1) map.set(r, c + 1, T.WALL);
      if (rng() < 0.5 && r + 1 < rows - 1) map.set(r + 1, c, T.WALL);
    }
  }

  // -------------------------------------------------------------- кирпич
  const brickDensity = 0.06 + rng() * 0.06;
  for (let r = 2; r < rows - 2; r++) {
    for (let c = 2; c < cols - 2; c++) {
      if (map.get(r, c) !== T.EMPTY || rng() >= brickDensity) continue;
      map.set(r, c, T.BRICK);
      if (rng() < 0.3 && map.get(r, c + 1) === T.EMPTY) map.set(r, c + 1, T.BRICK);
    }
  }

  // -------------------------------------------------------------- вода
  const waterPatches = 10 + Math.floor(rng() * 10);
  for (let i = 0; i < waterPatches; i++) {
    const wr = 3 + Math.floor(rng() * (rows - 8));
    const wc = 3 + Math.floor(rng() * (cols - 8));
    const size = 2 + Math.floor(rng() * 4);
    for (let dr = 0; dr < size; dr++) {
      for (let dc = 0; dc < size; dc++) {
        const r = wr + dr;
        const c = wc + dc;
        if (r > 0 && r < rows - 1 && c > 0 && c < cols - 1 && map.get(r, c) === T.EMPTY) {
          map.set(r, c, T.WATER);
        }
      }
    }
  }

  // ------------------------------------------------------- песчаный берег
  // Каждая клетка воды получает песок по периметру — берег «обводит» озеро.
  for (let r = 1; r < rows - 1; r++) {
    for (let c = 1; c < cols - 1; c++) {
      if (map.get(r, c) !== T.WATER) continue;
      for (let dr = -1; dr <= 1; dr++) {
        for (let dc = -1; dc <= 1; dc++) {
          if (dr === 0 && dc === 0) continue;
          if (map.get(r + dr, c + dc) === T.EMPTY) map.set(r + dr, c + dc, T.SAND);
        }
      }
    }
  }

  // -------------------------------------------------------------- деревья
  for (let r = 2; r < rows - 2; r++) {
    for (let c = 2; c < cols - 2; c++) {
      if (map.get(r, c) === T.EMPTY && rng() < 0.04) map.set(r, c, T.TREE);
    }
  }

  // -------------------------------------------------- расчистка зон спавна
  const clearRadius = 5;
  const spawnCenters = [
    [4, 4],
    [4, cols - 5],
    [rows - 5, 4],
    [rows - 5, cols - 5],
    [4, (cols / 2) | 0],
    [rows - 5, (cols / 2) | 0],
    [(rows / 2) | 0, 4],
    [(rows / 2) | 0, cols - 5],
  ];
  for (const [sr, sc] of spawnCenters) {
    for (let dr = -clearRadius; dr <= clearRadius; dr++) {
      for (let dc = -clearRadius; dc <= clearRadius; dc++) {
        const r = sr + dr;
        const c = sc + dc;
        if (r > 0 && r < rows - 1 && c > 0 && c < cols - 1) map.set(r, c, T.EMPTY);
      }
    }
  }

  const homes = { player: null, enemy: null };
  const flagSpots = { player: [], enemy: [] };

  // -------------------------------------------------------------- CTF
  if (mode === 'ctf') {
    map.set(rows - 2, 2, T.BASE_P);
    map.set(1, cols - 3, T.BASE_E);
    homes.player = { x: 2 * TILE + TILE / 2, y: (rows - 2) * TILE + TILE / 2 };
    homes.enemy = { x: (cols - 3) * TILE + TILE / 2, y: 1 * TILE + TILE / 2 };

    // Продольные коридоры вдоль обеих баз, чтобы дом всегда был достижим.
    for (let c = 1; c < cols - 1; c++) {
      if (map.get(rows - 3, c) !== T.WALL) map.set(rows - 3, c, T.EMPTY);
      if (map.get(rows - 2, c) !== T.WALL && map.get(rows - 2, c) !== T.BASE_P) {
        map.set(rows - 2, c, T.EMPTY);
      }
      if (map.get(2, c) !== T.WALL) map.set(2, c, T.EMPTY);
      if (map.get(1, c) !== T.WALL && map.get(1, c) !== T.BASE_E) map.set(1, c, T.EMPTY);
    }

    const perTeam = MODES.ctf.flagsPerTeam;
    flagSpots.enemy = pickFlagSpots(map, rng, perTeam, 2, ((rows / 2) | 0) - 2);
    flagSpots.player = pickFlagSpots(map, rng, perTeam, ((rows / 2) | 0) + 2, rows - 4);
  }

  // -------------------------------------------------------------- Оборона
  // База — центр карты, вокруг неё расчищаем площадку для обороны.
  if (mode === 'defense') {
    const cr = Math.floor(rows / 2);
    const cc = Math.floor(cols / 2);
    for (let dr = -4; dr <= 4; dr++) {
      for (let dc = -4; dc <= 4; dc++) {
        const r = cr + dr;
        const c = cc + dc;
        if (r > 0 && r < rows - 1 && c > 0 && c < cols - 1) map.set(r, c, T.EMPTY);
      }
    }
    homes.player = { x: cc * TILE + TILE / 2, y: cr * TILE + TILE / 2 };
  }

  // Связность прорубается ПОСЛЕ всех правок рельефа, но ДО валидации спавнов.
  map.ensureConnectivity();

  return {
    map,
    seed,
    mode,
    requestedLevel: levelNum,
    homes,
    flagSpots,
    areas: {
      player: mode === 'ctf' ? AREA_PLAYER(cols, rows) : mode === 'defense' ? DEFENSE_PLAYER_AREA(cols, rows) : AREA_ANY(cols, rows),
      enemy: mode === 'ctf' ? AREA_ENEMY(cols, rows) : mode === 'defense' ? DEFENSE_ENEMY_AREA(cols, rows) : AREA_ANY(cols, rows),
      any: AREA_ANY(cols, rows),
    },
  };
}

/** Разбрасывает точки флагов в горизонтальной полосе, не ближе 6 тайлов друг к другу. */
function pickFlagSpots(map, rng, count, rowFrom, rowTo) {
  const spots = [];
  const minGap = TILE * 6;
  const cols = map.cols;
  const rows = map.rows;
  for (let attempt = 0; attempt < 300 && spots.length < count; attempt++) {
    const c = 5 + Math.floor(rng() * (cols - 10));
    const r = rowFrom + Math.floor(rng() * Math.max(1, rowTo - rowFrom));
    const tile = map.get(r, c);
    if (tile !== T.EMPTY && tile !== T.TREE) continue;
    const x = c * TILE + TILE / 2;
    const y = r * TILE + TILE / 2;
    if (spots.some((s) => dist(s.x, s.y, x, y) < minGap)) continue;
    map.set(r, c, T.EMPTY);
    spots.push({ x, y });
  }
  // Гарантированный запасной вариант: раскладываем по центру полосы.
  let fallbackCol = ((cols / 2) | 0) - count * 3;
  while (spots.length < count) {
    const r = Math.max(1, Math.min(rows - 2, ((rowFrom + rowTo) / 2) | 0));
    const c = Math.max(1, Math.min(cols - 2, fallbackCol));
    map.set(r, c, T.EMPTY);
    spots.push({ x: c * TILE + TILE / 2, y: r * TILE + TILE / 2 });
    fallbackCol += 4;
  }
  return spots;
}

export { MAP_W, MAP_H };
