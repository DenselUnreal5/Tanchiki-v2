class_name TouchControls
extends Control

signal pause_pressed

const STICK_RADIUS := 70.0
const KNOB_RADIUS := 26.0
const BUTTON_R := 34.0
const PAUSE_R := 22.0
const EDGE := 70.0

var scheme = null
var player = null
var show_airstrike := false

var _pointers := {}
var _was_active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func is_active() -> bool:
	return visible and scheme != null

func set_scheme(next_scheme, next_player, airstrike: bool) -> void:
	var active := next_scheme is Ctl.TouchScheme
	if not active and _was_active and scheme != null:
		scheme.release_all()
		_pointers.clear()
	scheme = next_scheme if active else null
	player = next_player
	show_airstrike = airstrike
	visible = active
	if active or _was_active != active:
		queue_redraw()
	_was_active = active

func button_defs() -> Array:
	var defs := [
		{"id": "dash", "label": I18n.t("touch.dash", {}, "РЫВОК"), "pos": Vector2(size.x - EDGE, size.y * 0.30)},
		{"id": "mine", "label": I18n.t("touch.mine", {}, "МИНА"), "pos": Vector2(size.x - EDGE, size.y * 0.42)},
		{"id": "ability", "label": I18n.t("touch.ability", {}, "СПОС."), "pos": Vector2(size.x - EDGE, size.y * 0.54)},
	]
	if show_airstrike:
		defs.append({"id": "airstrike", "label": I18n.t("touch.air", {}, "АВИА"),
			"pos": Vector2(size.x - EDGE, size.y * 0.66)})
	return defs

func pause_center() -> Vector2:
	return Vector2(size.x * 0.5, PAUSE_R + 12.0)

func _button_at(pos: Vector2) -> String:
	for d in button_defs():
		if pos.distance_to(d["pos"]) <= BUTTON_R * 1.15:
			return String(d["id"])
	return ""

func _set_button(id: String, down: bool) -> void:
	match id:
		"dash": scheme.dash = down
		"mine": scheme.mine = down
		"ability": scheme.ability = down
		"airstrike": scheme.airstrike = down

func begin(index: int, pos: Vector2) -> void:
	if scheme == null:
		return
	if pos.distance_to(pause_center()) <= PAUSE_R * 1.4:
		pause_pressed.emit()
		return
	var id := _button_at(pos)
	if id != "":
		_pointers[index] = {"role": "button", "id": id}
		_set_button(id, true)
	elif pos.x < size.x * 0.5:
		_pointers[index] = {"role": "move", "origin": pos, "pos": pos}
	else:
		_pointers[index] = {"role": "aim", "origin": pos, "pos": pos}
	queue_redraw()

func drag(index: int, pos: Vector2) -> void:
	if scheme == null or not _pointers.has(index):
		return
	var p: Dictionary = _pointers[index]
	if p["role"] == "button":
		return
	p["pos"] = pos
	var v: Vector2 = (pos - p["origin"]) / STICK_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	if p["role"] == "move":
		scheme.move = v
	else:
		scheme.aim = v
	queue_redraw()

func finish(index: int) -> void:
	if not _pointers.has(index):
		return
	var p: Dictionary = _pointers[index]
	_pointers.erase(index)
	if scheme != null:
		match p["role"]:
			"move": scheme.move = Vector2.ZERO
			"aim": scheme.aim = Vector2.ZERO
			"button": _set_button(String(p["id"]), false)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			begin(event.index, event.position)
		else:
			finish(event.index)
	elif event is InputEventScreenDrag:
		drag(event.index, event.position)

func _draw() -> void:
	if not is_active():
		return
	var ring := Color(Cfg.UI_ACCENT, 0.32)
	var fill := Color(Cfg.UI_ACCENT, 0.16)
	var strong := Color(Cfg.UI_ACCENT, 0.7)
	var idle_move := Vector2(150.0, size.y - 150.0)
	var idle_aim := Vector2(size.x - 230.0, size.y - 150.0)
	var drawn := {"move": false, "aim": false}
	for p in _pointers.values():
		if p["role"] == "button":
			continue
		drawn[p["role"]] = true
		var origin: Vector2 = p["origin"]
		var offset: Vector2 = (p["pos"] - origin).limit_length(STICK_RADIUS)
		draw_circle(origin, STICK_RADIUS, fill)
		draw_arc(origin, STICK_RADIUS, 0.0, TAU, 40, ring, 2.0)
		draw_circle(origin + offset, KNOB_RADIUS, strong)
	if not drawn["move"]:
		draw_arc(idle_move, STICK_RADIUS, 0.0, TAU, 40, ring, 2.0)
		draw_circle(idle_move, KNOB_RADIUS, fill)
	if not drawn["aim"]:
		draw_arc(idle_aim, STICK_RADIUS, 0.0, TAU, 40, ring, 2.0)
		draw_circle(idle_aim, KNOB_RADIUS, fill)

	var tank = player.tank if player != null else null
	for d in button_defs():
		var held := false
		for p in _pointers.values():
			if p["role"] == "button" and p["id"] == d["id"]:
				held = true
		var dim := 1.0
		if d["id"] == "ability" and (tank == null or tank.ability_id == "" or tank.ability_cd > 0):
			dim = 0.45
		draw_circle(d["pos"], BUTTON_R, Color(Cfg.UI_ACCENT, (0.5 if held else 0.2) * dim))
		draw_arc(d["pos"], BUTTON_R, 0.0, TAU, 32, Color(Cfg.UI_ACCENT, 0.8 * dim), 2.0)
		draw_string(ThemeDB.fallback_font, d["pos"] + Vector2(-BUTTON_R, 5.0), String(d["label"]),
			HORIZONTAL_ALIGNMENT_CENTER, BUTTON_R * 2.0, 11, Color(Cfg.UI_TEXT, dim))

	draw_circle(pause_center(), PAUSE_R, Color(Cfg.UI_ACCENT, 0.2))
	draw_arc(pause_center(), PAUSE_R, 0.0, TAU, 24, Color(Cfg.UI_ACCENT, 0.8), 2.0)
	var pc := pause_center()
	draw_rect(Rect2(pc + Vector2(-6.0, -7.0), Vector2(4.0, 14.0)), Cfg.UI_TEXT)
	draw_rect(Rect2(pc + Vector2(2.0, -7.0), Vector2(4.0, 14.0)), Cfg.UI_TEXT)
