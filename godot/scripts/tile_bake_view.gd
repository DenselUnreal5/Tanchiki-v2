class_name TileBakeView
extends WorldView

## Содержимое одного чанка кэша тайлов (см. TileCache), живёт в
## собственном маленьком SubViewport. Рисует тайлы r0..r1 × c0..c1 и
## кольцо соседних клеток вокруг: их тени, трещины (до ~20 px в любую
## сторону) и разметка заходят на клетки чанка, а всё лишнее обрезает
## граница вьюпорта.
## Порядок — как в полном проходе _draw_tiles: сначала вся земля, потом
## фонари, потом тайлы построчно.
## Без заданного прямоугольника (r1 < 0) рисует всю карту целиком, как
## раньше, — на случай, если его где-то используют напрямую.

var r0 := 0
var r1 := -1
var c0 := 0
var c1 := -1
## TileCache-владелец (без типа, чтобы не зацикливать class_name).
var cache = null

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func _process(_delta: float) -> void:
	pass

func _draw() -> void:
	if world == null:
		return
	if r1 < 0:
		draw_set_transform(Vector2.ZERO)
		_view = Rect2(0.0, 0.0, world.map.width, world.map.height)
		_draw_tiles()
		return
	var t0 := Time.get_ticks_usec()
	var map := world.map
	var er0 := maxi(0, r0 - 1)
	var er1 := mini(map.rows - 1, r1 + 1)
	var ec0 := maxi(0, c0 - 1)
	var ec1 := mini(map.cols - 1, c1 + 1)
	draw_set_transform(-Vector2(c0 * Cfg.TILE, r0 * Cfg.TILE))
	_view = Rect2(ec0 * Cfg.TILE, er0 * Cfg.TILE,
		(ec1 - ec0 + 1) * Cfg.TILE, (er1 - er0 + 1) * Cfg.TILE)
	# Земля и фонари не вылезают за свою клетку — их хватает в пределах
	# самого чанка; кольцо соседей нужно только тайлам.
	_draw_ground_range(r0, r1, c0, c1)
	_draw_lamp_posts_in(Rect2(c0 * Cfg.TILE, r0 * Cfg.TILE,
		(c1 - c0 + 1) * Cfg.TILE, (r1 - r0 + 1) * Cfg.TILE))
	_draw_tile_range(er0, er1, ec0, ec1)
	if cache != null:
		cache.report_cost(Time.get_ticks_usec() - t0)
