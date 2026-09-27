class_name OrganicGen
extends RefCounted

## Клеточный автомат вместо уличной сетки: скальные гряды/заросли (T_WALL)
## и поляны/тропы (T_EMPTY) между ними. Классическое "сглаживающее" правило
## пещерной генерации (порог 5/3 с нейтральной зоной) — устоявшийся вариант,
## не осциллирует и даёт органичные бесформенные пятна вместо шума.
## T_EMPTY выбран для полян не случайно: это тот же тайл, что уже рисуется
## как "открытая земля" фоновым чекбордом (world_view.gd) и который уже
## подхватывает Locations.overgrow() (декор — деревья/песок по cover_chance
## локации) — дальнейший декор получаем бесплатно, без нового кода здесь.
## Связность гарантирует уже существующий GameMap.ensure_connectivity()
## (общий по is_drivable_tile, не завязан на дороги) — вызывается
## безусловно в конце LevelGen.generate(), доп. код тут не нужен.

const ITERATIONS := 5
const BIRTH_THRESHOLD := 5
const DEATH_THRESHOLD := 3

static func build(map: GameMap, rng: Rng, cols: int, rows: int, loc: Dictionary) -> void:
	var fill_prob: float = float(loc.get("organic_fill", 0.44))
	var grid := _seed(rng, cols, rows, fill_prob)
	for i in ITERATIONS:
		grid = _step(grid, cols, rows)
	for r in range(1, rows - 1):
		for c in range(1, cols - 1):
			map.set_tile(r, c, Cfg.T_WALL if grid[r * cols + c] == 1 else Cfg.T_EMPTY)

static func _seed(rng: Rng, cols: int, rows: int, fill_prob: float) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(cols * rows)
	for r in range(1, rows - 1):
		for c in range(1, cols - 1):
			grid[r * cols + c] = 1 if rng.nextf() < fill_prob else 0
	return grid

static func _step(grid: PackedByteArray, cols: int, rows: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(cols * rows)
	for r in range(1, rows - 1):
		for c in range(1, cols - 1):
			var n := _wall_neighbors(grid, cols, rows, r, c)
			var i := r * cols + c
			if n >= BIRTH_THRESHOLD:
				out[i] = 1
			elif n <= DEATH_THRESHOLD:
				out[i] = 0
			else:
				out[i] = grid[i]
	return out

## Рамка карты (за пределами [1,dim-2]) считается стеной — прижимает форму
## к границе и снижает число изолированных карманов у самого края.
static func _wall_neighbors(grid: PackedByteArray, cols: int, rows: int, r: int, c: int) -> int:
	var count := 0
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var nr := r + dr
			var nc := c + dc
			if nr <= 0 or nc <= 0 or nr >= rows - 1 or nc >= cols - 1:
				count += 1
				continue
			if grid[nr * cols + nc] == 1:
				count += 1
	return count
