# ============================================================================
# perk_icon_view.gd — рисует один значок из PerkIcons.ICONS. Один интерпретатор
# на все 49 перков: значок — просто данные, форма не зависит от темы
# интерфейса, меняется только icon_color (её выставляет вызывающий код по
# состоянию узла — открыт/закрыт/выбран — и по активной теме).
# ============================================================================
class_name PerkIconView
extends Control

var perk_id := "":
	set(v):
		perk_id = v
		queue_redraw()
var icon_color := Color.WHITE:
	set(v):
		icon_color = v
		queue_redraw()
## Цвет примитивов с "shade": true — внутренние прорези/швы/рёбра поверх
## основного силуэта (стиль "детальный милитари-пропс"). Полупрозрачный
## тёмный оверлей ложится одинаково на любой icon_color и любую тему, без
## завязки на конкретные цвета Cfg.
var shade_color := Color(0, 0, 0, 0.55):
	set(v):
		shade_color = v
		queue_redraw()
## Лёгкая потёртость поверх значка (мелкие тёмные крапинки) — под стиль
## референса «нарисовано грубой кистью». Включается только для крупного
## значка в детальной панели (см. _gallery_detail в ui_root.gd): на мелких
## узлах дерева (24px) те же крапинки просто мусорят силуэт, там она
## выключена.
var rough := false:
	set(v):
		rough = v
		queue_redraw()

## Общий фиксированный узор крапинок на все значки — не randi() в _draw(),
## а один раз посчитанный при первом использовании и переиспользуемый.
static var _grain: Array = []

static func _grain_spots() -> Array:
	if _grain.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 1337
		for i in 22:
			_grain.append({
				"c": Vector2(rng.randf_range(3.0, 61.0), rng.randf_range(3.0, 61.0)),
				"r": rng.randf_range(1.0, 3.0),
			})
	return _grain

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var ops: Array = PerkIcons.ICONS.get(perk_id, PerkIcons.ICONS["_default"])
	# Значки нарисованы на сетке 64×64 — растягиваем под фактический размер узла.
	draw_set_transform(Vector2.ZERO, 0.0, size / 64.0)
	for op in ops:
		_draw_op(op)
	if rough:
		for spot in _grain_spots():
			draw_circle(spot["c"], spot["r"], Color(0, 0, 0, 0.15))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_op(op: Dictionary) -> void:
	var col: Color = shade_color if bool(op.get("shade", false)) else icon_color
	match String(op["op"]):
		"poly":
			draw_colored_polygon(PackedVector2Array(op["pts"]), col)
		"line":
			draw_line(op["a"], op["b"], col, float(op.get("w", 4.0)), true)
		"circle":
			if bool(op.get("fill", true)):
				draw_circle(op["c"], float(op["r"]), col)
			else:
				draw_arc(op["c"], float(op["r"]), 0.0, TAU, 48, col, float(op.get("w", 4.0)), true)
		"rect":
			draw_colored_polygon(_rect_points(op["c"], op["size"], float(op.get("rot", 0.0))), col)
		"arc":
			draw_arc(op["c"], float(op["r"]), deg_to_rad(float(op["a0"])), deg_to_rad(float(op["a1"])),
				24, col, float(op.get("w", 4.0)), true)
		"ring":
			var base: Array = op["pts"]
			var n := int(op["n"])
			var c: Vector2 = op["c"]
			for i in n:
				var ang := TAU * float(i) / float(n)
				var pts := PackedVector2Array()
				for p in base:
					pts.append((p - c).rotated(ang) + c)
				draw_colored_polygon(pts, col)

func _rect_points(c: Vector2, sz: Vector2, rot_deg: float) -> PackedVector2Array:
	var hw := sz.x * 0.5
	var hh := sz.y * 0.5
	var rad := deg_to_rad(rot_deg)
	var pts := PackedVector2Array()
	for corner in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]:
		pts.append(corner.rotated(rad) + c)
	return pts
