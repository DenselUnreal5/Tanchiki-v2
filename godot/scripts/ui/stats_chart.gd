class_name StatsChart
extends Control

var kind := "line"
var series: Array = []
var labels: Array = []
var empty_text := ""
var hover_index := -1

func _ready() -> void:
	if custom_minimum_size.y <= 0: custom_minimum_size.y = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hover_index = -1; queue_redraw())

func _plot() -> Rect2:
	return Rect2(44, 16, maxf(1, size.x - 60), maxf(1, size.y - 46))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var count := labels.size()
		hover_index = clampi(int(round((event.position.x - _plot().position.x) / _plot().size.x * maxi(0, count - 1))), 0, count - 1) if count > 0 else -1
		queue_redraw()

func _get_tooltip(at: Vector2) -> String:
	if kind == "line" and not labels.is_empty():
		var index := clampi(int(round((at.x - _plot().position.x) / _plot().size.x * maxi(0, labels.size() - 1))), 0, labels.size() - 1)
		var text := String(labels[index])
		for item in series:
			if index < item.values.size(): text += "\n%s: %s" % [item.name, item.values[index]]
		return text
	if kind in ["bars", "donut"]:
		var lines := []
		for item in series: lines.append("%s: %s" % [item.name, item.value])
		return "\n".join(lines)
	return empty_text

func _text(text: String, pos: Vector2, color: Color = Cfg.UI_MUTED, font_size: int = 11) -> void:
	draw_string(Fonts.regular, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _short(value: float) -> String:
	if value >= 1000000: return "%.1fM" % (value / 1000000)
	if value >= 10000: return "%.0fk" % (value / 1000)
	return str(int(value))

func _draw() -> void:
	if series.is_empty():
		_text(empty_text, Vector2(12, size.y * 0.5), Cfg.UI_MUTED, 12)
		return
	if kind == "donut":
		var total := 0.0
		for item in series: total += float(item.value)
		var center := Vector2(size.x * 0.5, 85)
		var radius := 58.0
		draw_arc(center, radius, 0, TAU, 80, Cfg.UI_BORDER, 16, true)
		var angle := -PI / 2
		for item in series:
			var end := angle + (float(item.value) / total * TAU if total > 0 else 0.0)
			if end > angle: draw_arc(center, radius, angle, end, 80, item.color, 16, true)
			angle = end
		var value := "%d%%" % int(round(float(series[0].value) / total * 100)) if total > 0 else "—"
		var width := Fonts.bold.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(Fonts.bold, center + Vector2(-width * 0.5, 9), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Cfg.UI_TEXT)
		for i in series.size():
			var p := Vector2(14, 170 + i * 22)
			draw_rect(Rect2(p + Vector2(0, -9), Vector2(8, 8)), series[i].color)
			_text("%s  %d" % [series[i].name, series[i].value], p + Vector2(15, 0))
		return
	if kind == "bars":
		var maximum := 1.0
		for item in series: maximum = maxf(maximum, float(item.value))
		for i in series.size():
			var item: Dictionary = series[i]
			var y := 20.0 + i * 30
			var label := String(item.name)
			while label.length() > 2 and Fonts.regular.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x > 140:
				label = label.substr(0, label.length() - 2) + "…"
			_text(label, Vector2(8, y + 10))
			var start := 160.0
			var width := maxf(8, size.x - start - 44)
			draw_rect(Rect2(start, y, width, 12), Cfg.UI_BORDER)
			draw_rect(Rect2(start, y, width * float(item.value) / maximum, 12), item.color)
			_text(_short(item.value), Vector2(start + width + 8, y + 11), Cfg.UI_TEXT)
		return
	var plot := _plot()
	var maximum := 1.0
	for item in series:
		for value in item.values: maximum = maxf(maximum, float(value))
	maximum = ceilf(maximum / 4.0) * 4.0
	for i in 5:
		var y := plot.end.y - i * plot.size.y / 4
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(Cfg.UI_BORDER, 0.65), 1)
		_text(_short(ceil(maximum * i / 4)), Vector2(2, y + 4))
	for item in series:
		var points := PackedVector2Array()
		for i in item.values.size():
			points.append(Vector2(plot.position.x + plot.size.x * i / maxi(1, item.values.size() - 1), plot.end.y - float(item.values[i]) / maximum * plot.size.y))
		if points.size() > 1: draw_polyline(points, item.color, 2, true)
		for i in points.size():
			draw_circle(points[i], 4 if i == hover_index else 2.5, item.color)
	if hover_index >= 0 and hover_index < labels.size():
		var x := plot.position.x + plot.size.x * hover_index / maxi(1, labels.size() - 1)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(Cfg.UI_TEXT, 0.3), 1)
	_text("1", plot.position + Vector2(0, plot.size.y + 20))
	_text(str(labels.size()), plot.end + Vector2(-12, 20))
