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
	_carve_trails(grid, rng, cols, rows)
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
static func _carve_trails(grid: PackedByteArray, rng: Rng, cols: int, rows: int) -> void:
	var count := 3 + int(rng.nextf() * 3.0)
	for i in count:
		var horizontal := rng.nextf() < 0.5
		var x: float
		var y: float
		var tx: float
		var ty: float
		if horizontal:
			y = 2.0 + rng.nextf() * float(rows - 4)
			x = 1.0
			ty = 2.0 + rng.nextf() * float(rows - 4)
			tx = float(cols - 2)
		else:
			x = 2.0 + rng.nextf() * float(cols - 4)
			y = 1.0
			tx = 2.0 + rng.nextf() * float(cols - 4)
			ty = float(rows - 2)
		_walk_trail(grid, rng, cols, rows, x, y, tx, ty)

static func _walk_trail(grid: PackedByteArray, rng: Rng, cols: int, rows: int,
		x0: float, y0: float, x1: float, y1: float) -> void:
	var x := x0
	var y := y0
	var steps := int(float(cols + rows) * 0.6)
	for i in steps:
		var dx := x1 - x
		var dy := y1 - y
		var dist := sqrt(dx * dx + dy * dy)
		if dist < 1.5:
			break
		var step_x := dx / dist + (rng.nextf() - 0.5) * 0.9
		var step_y := dy / dist + (rng.nextf() - 0.5) * 0.9
		x = clampf(x + step_x, 2.0, float(cols - 3))
		y = clampf(y + step_y, 2.0, float(rows - 3))
		_clear_disc(grid, cols, rows, x, y, 1.4)

static func _clear_disc(grid: PackedByteArray, cols: int, rows: int,
		cx: float, cy: float, radius: float) -> void:
	var box := int(ceil(radius)) + 1
	var icx := int(round(cx))
	var icy := int(round(cy))
	for dr in range(-box, box + 1):
		for dc in range(-box, box + 1):
			var r := icy + dr
			var c := icx + dc
			if r <= 0 or c <= 0 or r >= rows - 1 or c >= cols - 1:
				continue
			if sqrt(float(dr * dr + dc * dc)) <= radius:
				grid[r * cols + c] = 0

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
