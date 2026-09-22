class_name TileBakeView
extends WorldView

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func _process(_delta: float) -> void:
	pass

func _draw() -> void:
	if world == null:
		return
	_view = Rect2(0.0, 0.0, world.map.width, world.map.height)
	draw_set_transform(Vector2.ZERO)
	_draw_tiles()
