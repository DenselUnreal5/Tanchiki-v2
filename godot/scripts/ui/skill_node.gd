@tool
class_name SkillNode
extends BaseButton

signal picked(id: String)

var perk_id := "":
	set(v):
		perk_id = v
		if _icon != null:
			_icon.perk_id = v
var locked := true
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var need_level := 0

@export var outer_size: Vector2 = Vector2(60, 60):
	set(v):
		outer_size = v
		custom_minimum_size = v
		queue_redraw()
@export var icon_size: Vector2 = Vector2(30, 30):
	set(v):
		icon_size = v
		if _icon != null:
			_icon.icon_size = v
		_layout_icon()

var _hovered := false

var _icon: PerkIconView

func _ui_theme() -> String:
	return "military" if Engine.is_editor_hint() else Sets.ui_theme

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; queue_redraw())
	custom_minimum_size = outer_size
	_icon = PerkIconView.new()
	_icon.icon_size = icon_size
	add_child(_icon)
	resized.connect(_layout_icon)
	pressed.connect(func(): picked.emit(perk_id))
	_layout_icon()
	refresh()

func _layout_icon() -> void:
	if _icon != null:
		_icon.position = size * 0.5 - _icon.size * 0.5

func refresh() -> void:
	if _icon == null:
		return
	_icon.perk_id = perk_id
	_icon.icon_color = Cfg.UI_TEXT if (selected or not locked) else Cfg.UI_MUTED
	modulate.a = 1.0 if not locked else 0.72
	queue_redraw()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	match _ui_theme():
		"noir": _draw_diamond()
		"scifi": _draw_tile()
		_: _draw_octagon()
	if locked and need_level > 0:
		_draw_badge()
	if has_focus() or _hovered:
		_draw_focus_ring()

func _draw_focus_ring() -> void:
	var w := 2.0 if has_focus() else 1.5
	var col := Cfg.UI_ACCENT if has_focus() else Color(Cfg.UI_ACCENT, 0.7)
	draw_rect(Rect2(-3, -3, size.x + 6, size.y + 6), col, false, w)

func _border_color() -> Color:
	if selected:
		return Cfg.UI_TEXT
	return Cfg.UI_ACCENT if not locked else Cfg.UI_BORDER

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out

func _scaled(pts: PackedVector2Array, k: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k)
	return out

func _draw_diamond() -> void:
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array([Vector2(w * 0.5, 2), Vector2(w - 2, h * 0.5), Vector2(w * 0.5, h - 2), Vector2(2, h * 0.5)])
	var border := _border_color()
	draw_colored_polygon(pts, Color(Cfg.UI_CARD, 0.75))
	draw_polyline(_closed(pts), border, 2.5, true)
	if selected:
		draw_polyline(_closed(_scaled(pts, 1.22)), Color(border, 0.5), 1.5, true)

func _draw_octagon() -> void:
	var w := size.x
	var h := size.y
	var cut_x := w * 0.28
	var cut_y := h * 0.28
	var pts := PackedVector2Array([
		Vector2(cut_x, 2), Vector2(w - cut_x, 2), Vector2(w - 2, cut_y), Vector2(w - 2, h - cut_y),
		Vector2(w - cut_x, h - 2), Vector2(cut_x, h - 2), Vector2(2, h - cut_y), Vector2(2, cut_y),
	])
	var border := _border_color()
	draw_colored_polygon(pts, Color(Cfg.UI_CARD, 0.82))
	draw_polyline(_closed(pts), border, 2.5, true)
	if selected:
		draw_polyline(_closed(_scaled(pts, 1.16)), Color(border, 0.6), 1.5, true)

func _draw_tile() -> void:
	var border := _border_color()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Cfg.UI_CARD, 0.8)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = border
	if not locked:
		sb.shadow_color = Color(Cfg.UI_ACCENT, 0.35)
		sb.shadow_size = 4
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	if selected:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color.TRANSPARENT
		glow.set_corner_radius_all(8)
		glow.set_border_width_all(1)
		glow.border_color = Color(border, 0.6)
		glow.shadow_color = Color(border, 0.5)
		glow.shadow_size = 8
		draw_style_box(glow, Rect2(-Vector2(3, 3), size + Vector2(6, 6)))

func _draw_badge() -> void:
	var c := Vector2(size.x - 5, size.y - 5)
	draw_circle(c, 8.0, Cfg.UI_TAG)
	draw_arc(c, 8.0, 0.0, TAU, 16, Cfg.UI_BG, 1.2, true)
	var txt := str(need_level)
	var f := Fonts.bold
	var fs := 9
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(f, c + Vector2(-w * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Cfg.UI_TAG_INK)
