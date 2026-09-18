# ============================================================================
# keybind_button.gd — кнопка-приёмник для переназначения клавиши. Обычная
# кнопка, пока не нажата; после клика ждёт следующую физическую клавишу
# (ловит её через _unhandled_input — независимо от того, в фокусе ли сама
# кнопка) и сообщает о ней сигналом. Esc или любая кнопка геймпада отменяют
# ожидание без изменений — геймпадом клавиатурную клавишу не назначить,
# но должна быть возможность выйти из режима ожидания, если чинишь клавиши
# игрока-2 (клавиатура) с геймпадом в руках, а не за той же клавиатурой:
# без этого кнопка так и осталась бы висеть в «…» навсегда, а геймпад со
# стороны выглядел бы так, будто перестал отвечать.
#
# Стилизуется снаружи (см. UiKit.keybind_row) — этот скрипт только про
# поведение, не про внешний вид, тем же приёмом, что PerkIconView/SkillNode
# не решают сами, какого они цвета.
# ============================================================================
class_name KeybindButton
extends Button

## Новая клавиша выбрана (отмена клавиатурой/геймпадом в захваченные не
## попадает).
signal key_captured(keycode: int)

## Стили на время ожидания клавиши — выставляются снаружи (UiKit.keybind_row)
## до первого использования; без них слушающее состояние просто не меняет
## фон, только подпись.
var normal_style: StyleBox
var listening_style: StyleBox

var listening := false:
	set(v):
		listening = v
		set_process_unhandled_input(v)
		if normal_style != null and listening_style != null:
			add_theme_stylebox_override("normal", listening_style if v else normal_style)
		_refresh_text()

## Физический keycode текущей привязки (Key.KEY_NONE — не задана).
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
	# Кнопка геймпада (любая) отменяет ожидание — назначить ею клавиатурную
	# клавишу нельзя, но должен быть выход, если рядом нет клавиатуры.
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
