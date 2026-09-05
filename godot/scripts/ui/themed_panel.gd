# ============================================================================
# themed_panel.gd — панель-контейнер, которая рисует себя по активной теме
# (Sets.ui_theme): рваная бумага (нуар), клёпаный металл (военное досье),
# скошенное стекло со свечением (sci-fi). Заменяет UiKit.panel() везде, где
# нужен фон под текущую тему — дочерние узлы добавляются как обычно, отступы
# держит MarginContainer.
# ============================================================================
class_name ThemedPanel
extends MarginContainer

## Разный seed на разных панелях — иначе рваный край нуара у всех окон
## получался бы одинаковым «зубцом». Стабилен между перерисовками одной
## и той же панели (важно: не randi() внутри _draw()).
var seed_value: int = 0
## Color.TRANSPARENT — использовать Cfg.UI_BORDER текущей темы.
var border_color: Color = Color.TRANSPARENT
## Военное досье: полоса-штамп по верхнему краю (используется в шапках).
var stripe_top: bool = false

var _jag: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	add_theme_constant_override("margin_left", 22)
	add_theme_constant_override("margin_right", 22)
	add_theme_constant_override("margin_top", 18)
	add_theme_constant_override("margin_bottom", 18)
	resized.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	if Sets.ui_theme == "noir":
		_jag = _jagged_outline(size, 5.0, 4)
	queue_redraw()

func _border() -> Color:
	return Cfg.UI_BORDER if border_color == Color.TRANSPARENT else border_color

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	match Sets.ui_theme:
		"noir": _draw_noir()
		"scifi": _draw_scifi()
		_: _draw_military()

# ---------------------------------------------------------------- нуар
## Рваный контур рисуется только контуром (draw_polyline), не заливкой
## многоугольника: полилинии рисуют соединённые отрезки как есть, им
## всё равно, пересекает ли ломаная сама себя. Заливка — обычный прямой
## прямоугольник (draw_rect), ему тоже всё равно. Раньше заливка шла тем
## же самопересекающимся контуром через draw_colored_polygon(), а Godot
## триангулирует только простые (без самопересечений) многоугольники —
## при случайном зубце с нужным сочетанием (seed, size) контур регулярно
## получался непростым, и триангуляция падала с "Invalid polygon data"
## каждый кадр, пока панель была на экране. Так эффект того же вида
## («рваный край») достигается без риска сломанной отрисовки.
func _jagged_outline(sz: Vector2, jag: float, segs: int) -> PackedVector2Array:
	var w := sz.x
	var h := sz.y
	if w < 8.0 or h < 8.0 or segs < 1:
		return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h), Vector2(0, 0)])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := PackedVector2Array()
	for i in range(segs + 1):
		pts.append(Vector2(float(i) / segs * w, rng.randf_range(-jag, jag)))
	for i in range(1, segs + 1):
		pts.append(Vector2(w + rng.randf_range(-jag, jag), float(i) / segs * h))
	for i in range(1, segs + 1):
		pts.append(Vector2(w - float(i) / segs * w, h + rng.randf_range(-jag, jag)))
	for i in range(1, segs + 1):
		pts.append(Vector2(rng.randf_range(-jag, jag), h - float(i) / segs * h))
	pts.append(pts[0])
	return pts

func _draw_noir() -> void:
	draw_rect(Rect2(Vector2(3, 4), size), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Cfg.UI_PANEL, Cfg.UI_PANEL_ALPHA))
	if _jag.size() >= 3:
		draw_polyline(_jag, _border(), 1.6, true)

# ---------------------------------------------------------------- военное досье
func _draw_military() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Cfg.UI_PANEL, Cfg.UI_PANEL_ALPHA))
	draw_rect(Rect2(Vector2(1.5, 1.5), size - Vector2(3, 3)), _border(), false, 3.0)
	for c in [Vector2(11, 11), Vector2(size.x - 11, 11), Vector2(11, size.y - 11), Vector2(size.x - 11, size.y - 11)]:
		draw_circle(c, 4.0, Cfg.UI_TAG)
		draw_arc(c, 4.0, 0.0, TAU, 12, Color(Cfg.UI_BG, 0.8), 1.2, true)
	if stripe_top:
		var y := 0.0
		var stripe_w := 16.0
		while y < size.x + size.y:
			var x0 := clampf(y, 0.0, size.x)
			var x1 := clampf(y - 8.0, 0.0, size.x)
			if x1 < x0:
				draw_colored_polygon(PackedVector2Array([
					Vector2(x1, 0), Vector2(x0, 0), Vector2(x0, 4), Vector2(x1, 4)]),
					Color(Cfg.UI_WARN, 0.5))
			y += stripe_w

# ---------------------------------------------------------------- sci-fi
func _draw_scifi() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Cfg.UI_PANEL, Cfg.UI_PANEL_ALPHA)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = _border()
	sb.shadow_color = Color(Cfg.UI_ACCENT, 0.18)
	sb.shadow_size = 10
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), Color(Cfg.UI_ACCENT, 0.16), false, 1.0)
	for c in [Vector2(12, 12), Vector2(size.x - 12, 12), Vector2(12, size.y - 12), Vector2(size.x - 12, size.y - 12)]:
		draw_circle(c, 3.5, Cfg.UI_ACCENT)
		draw_circle(c, 1.6, Cfg.UI_BG)
