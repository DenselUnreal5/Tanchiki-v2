class_name KeybindButton
extends Button

signal key_captured(keycode: int)

var normal_style: StyleBox
var listening_style: StyleBox

var listening := false:
	set(v):
		listening = v
		set_process_unhandled_input(v)
		if normal_style != null and listening_style != null:
			add_theme_stylebox_override("normal", listening_style if v else normal_style)
		_refresh_text()

var keycode: int = KEY_NONE:
	set(v):
		keycode = v
		_refresh_text()

func _ready() -> void:
	set_process_unhandled_input(false)
	pressed.connect(func(): listening = not listening)
	_refresh_text()

func _refresh_text() -> void:
	if listening:
		text = "…"
	elif keycode == KEY_NONE:
		text = "—"
	else:
		text = OS.get_keycode_string(keycode)

func _unhandled_input(event: InputEvent) -> void:
	if not listening:
		return
	if event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		listening = false
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key: int = (event as InputEventKey).physical_keycode
	listening = false
	if key == KEY_ESCAPE:
		return
	key_captured.emit(key)
