class_name CitadelArt
extends RefCounted

# Native world-pixel masonry: adjacent cells share courses and exterior edges.
# Geometry and collision tiles remain entirely owned by the map generator.
static var PALETTES := {
	"city": {"stone": Color("#73766a"), "light": Color("#949787"), "dark": Color("#424a40"),
		"joint": Color("#626759"), "paving": Color("#4d5146"), "soil": Color("#59633c"), "moss": Color("#586b39"),
		"water": Color("#204586"), "ripple": Color("#264e92"), "bank": Color("#1d772f")},
	"dust": {"stone": Color("#ac9466"), "light": Color("#c5ae7b"), "dark": Color("#6d6145"),
		"joint": Color("#95825a"), "paving": Color("#9a8b63"), "soil": Color("#aa9862"), "moss": Color("#817442"),
		"water": Color("#2b3a8f"), "ripple": Color("#3b4b9d"), "bank": Color("#aa9862")},
	"jungle": {"stone": Color("#68745b"), "light": Color("#899178"), "dark": Color("#394936"),
		"joint": Color("#57654b"), "paving": Color("#4d5941"), "soil": Color("#455733"), "moss": Color("#567635"),
		"water": Color("#2b3a8f"), "ripple": Color("#3b4b9d"), "bank": Color("#455733")},
	"frost": {"stone": Color("#858e8b"), "light": Color("#abb5ae"), "dark": Color("#4c5957"),
		"joint": Color("#74807b"), "paving": Color("#646f69"), "soil": Color("#899187"), "moss": Color("#667763"),
		"water": Color("#2b3a8f"), "ripple": Color("#3b4b9d"), "bank": Color("#899187")},
}

static func enabled(world: World) -> bool:
	if world == null: return false
	var rect = world.level.get("citadel", Rect2i())
	if rect is Rect2i and rect.has_area(): return true
	return String(world.level.get("archetype", "")) == "fortress" \
		and String(Locations.get_location(world.location).get("terrain", "")) != "tiles"

static func bounds(world: World) -> Rect2i:
	var rect = world.level.get("citadel", Rect2i())
	return rect if rect is Rect2i and rect.has_area() else central_rect(world.map)

static func central_rect(map: GameMap) -> Rect2i:
	var fw := mini(22, map.cols - 16)
	var fh := mini(18, map.rows - 14)
	if fw < 12 or fh < 10: return Rect2i()
	var half_w := fw / 2
	var half_h := fh / 2
	return Rect2i(map.cols / 2 - half_w, map.rows / 2 - half_h, half_w * 2 + 1, half_h * 2 + 1)

static func contains(world: World, r: int, c: int) -> bool:
	if not enabled(world): return false
	var point := Vector2i(c, r)
	var citadel = world.level.get("citadel", Rect2i())
	if citadel is Rect2i and citadel.has_area(): return citadel.has_point(point)
	var center := central_rect(world.map)
	if center.has_area() and center.grow(2).has_point(point): return true
	for row in [6, world.map.rows - 7]:
		for col in [6, world.map.cols - 7]:
			if Rect2i(col - 2, row - 2, 5, 5).has_point(point): return true
	return false

static func palette(location: String) -> Dictionary:
	if location in ["dust", "village"]: return PALETTES.dust
	if location in ["jungle", "grassland"]: return PALETTES.jungle
	return PALETTES.get(location, PALETTES.city)

static func _rect(canvas: CanvasItem, x: float, y: float, w: float, h: float, color: Color) -> void:
	canvas.draw_rect(Rect2(x, y, w, h), color)

static func draw_tile(canvas: CanvasItem, world: World, r: int, c: int) -> bool:
	if not contains(world, r, c): return false
	var tile := world.map.get_tile(r, c)
	var p := palette(world.location)
	var x := float(c * Cfg.TILE)
	var y := float(r * Cfg.TILE)
	if GameMap.is_solid_tile(tile):
		_wall(canvas, world.map, r, c, p, tile != Cfg.T_WALL)
	elif tile == Cfg.T_ROAD or (tile == Cfg.T_EMPTY and world.level.get("citadel", Rect2i()).has_area()):
		_paving(canvas, x, y, r, c, p)
	elif tile == Cfg.T_BRIDGE:
		_bridge(canvas, world.map, r, c, p)
	elif tile == Cfg.T_WATER:
		_water(canvas, world.map, r, c, p)
	else:
		return false
	return true

static func _wall(canvas: CanvasItem, map: GameMap, r: int, c: int, p: Dictionary, roof: bool) -> void:
	var x := float(c * Cfg.TILE)
	var y := float(r * Cfg.TILE)
	var stone: Color = p.stone
	if roof: stone = stone.darkened(0.08)
	_rect(canvas, x, y, 32, 32, stone)
	# Eight-pixel courses continue across tile and chunk boundaries.
	for course in 4:
		var cy := y + course * 8
		_rect(canvas, x, cy, 32, 1, p.joint)
		var offset := 8 if (r * 4 + course) % 2 == 0 else 0
		for joint in 2:
			_rect(canvas, x + offset + joint * 16, cy + 1, 1, 7, p.joint)
		if (r * 13 + c * 7 + course) % 5 == 0:
			_rect(canvas, x + offset + 3, cy + 3, 5, 1, stone.lightened(0.045))
	var up := not GameMap.is_solid_tile(map.get_tile(r - 1, c))
	var down := not GameMap.is_solid_tile(map.get_tile(r + 1, c))
	var left := not GameMap.is_solid_tile(map.get_tile(r, c - 1))
	var right := not GameMap.is_solid_tile(map.get_tile(r, c + 1))
	if up:
		_rect(canvas, x, y, 32, 1, p.dark)
		_rect(canvas, x, y + 1, 32, 2, p.light)
	if left:
		_rect(canvas, x, y, 1, 32, p.dark)
		_rect(canvas, x + 1, y + 2, 2, 28, p.light)
	if right: _rect(canvas, x + 29, y, 3, 32, p.dark)
	if down:
		_rect(canvas, x, y + 28, 32, 4, p.dark)
		_rect(canvas, x + 1, y + 27, 30, 1, p.joint)
		if map.get_tile(r + 1, c) != Cfg.T_WATER:
			_rect(canvas, x, y + 32, 32, 2, Color(0.07, 0.09, 0.06, 0.25))
	# Small irregular weathering ties masonry to the local ground palette.
	var chip := float((r * 19 + c * 11) % 22 + 5)
	if down:
		_rect(canvas, x + chip, y + 30, 4, 2, p.soil)
		_rect(canvas, x + chip - 2, y + 28, 2, 2, p.moss)
	if left and (r + c) % 3 == 0:
		_rect(canvas, x + 1, y + chip, 3, 3, p.moss)
	if roof and (r + c) % 2 == 0:
		_rect(canvas, x + 11, y + 12, 10, 8, p.dark)
		for line in 3:
			_rect(canvas, x + 12, y + 13 + line * 2, 8, 1, p.joint)

static func _paving(canvas: CanvasItem, x: float, y: float, r: int, c: int, p: Dictionary) -> void:
	var base: Color = p.paving
	_rect(canvas, x, y, 32, 32, base)
	for course in 2:
		_rect(canvas, x, y + course * 16, 32, 1, base.darkened(0.10))
		var offset := 8 if (r + course) % 2 == 0 else 0
		for joint in 2:
			_rect(canvas, x + offset + joint * 16, y + course * 16, 1, 16, base.darkened(0.10))
	var px := float((r * 17 + c * 7) % 23 + 3)
	var py := float((r * 7 + c * 13) % 23 + 3)
	_rect(canvas, x + px, y + py, 3, 1, base.lightened(0.06))
	if (r + c) % 4 == 0:
		_rect(canvas, x + px, y + 16, 3, 2, p.moss)

static func _water(canvas: CanvasItem, map: GameMap, r: int, c: int, p: Dictionary) -> void:
	var x := float(c * 32)
	var y := float(r * 32)
	_rect(canvas, x, y, 32, 32, p.water)
	var shift := float((r * 7 + c * 5) % 12)
	_rect(canvas, x + shift, y + 9, 10, 1, p.ripple)
	_rect(canvas, x + 17 - shift, y + 24, 8, 1, p.ripple)
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var neighbor := map.get_tile(r + d.y, c + d.x)
		if neighbor == Cfg.T_WATER or neighbor == Cfg.T_BRIDGE: continue
		var bank: Color = (p.stone as Color).darkened(0.15) if GameMap.is_solid_tile(neighbor) else p.bank
		if d.y < 0: _rect(canvas, x, y, 32, 2, bank)
		elif d.y > 0: _rect(canvas, x, y + 30, 32, 2, bank)
		elif d.x < 0: _rect(canvas, x, y, 2, 32, bank)
		else: _rect(canvas, x + 30, y, 2, 32, bank)

static func _bridge(canvas: CanvasItem, map: GameMap, r: int, c: int, p: Dictionary) -> void:
	var x := float(c * 32)
	var y := float(r * 32)
	var horizontal := _paved(map.get_tile(r, c - 1)) or _paved(map.get_tile(r, c + 1))
	var wood: Color = (p.paving as Color).lerp(Color("#8b7450"), 0.45)
	_rect(canvas, x, y, 32, 32, wood)
	for plank in 4:
		if horizontal: _rect(canvas, x + plank * 8, y, 1, 32, wood.darkened(0.24))
		else: _rect(canvas, x, y + plank * 8, 32, 1, wood.darkened(0.24))
	if horizontal:
		if map.get_tile(r - 1, c) != Cfg.T_BRIDGE: _rect(canvas, x, y, 32, 2, p.dark)
		if map.get_tile(r + 1, c) != Cfg.T_BRIDGE: _rect(canvas, x, y + 30, 32, 2, p.dark)
	else:
		if map.get_tile(r, c - 1) != Cfg.T_BRIDGE: _rect(canvas, x, y, 2, 32, p.dark)
		if map.get_tile(r, c + 1) != Cfg.T_BRIDGE: _rect(canvas, x + 30, y, 2, 32, p.dark)

static func _paved(tile: int) -> bool:
	return tile == Cfg.T_ROAD or tile == Cfg.T_BRIDGE
