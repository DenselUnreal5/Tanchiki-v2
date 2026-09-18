# ============================================================================
# cosmetic_card.gd — одна карточка косметики (камуфляж/рисунок/гусеницы/
# башня) во вкладке «Гараж» Хаба. Раньше собиралась в ui_root.gd:
# _cosmetic_card() на каждый предмет заново; теперь сцена — размер иконки
# и ширина карточки редактируются в инспекторе.
#
# Одна кнопка на три состояния (как и раньше): «Купить · N 🪙» / «Надеть» /
# «Надето» (задизейблена) — какое из трёх решает hub.gd по Prof.*, карточка
# только показывает готовый текст и сообщает о нажатии.
#
# @tool: живой предпросмотр. Автозагрузки (Prof/I18n) не читаются —
# Hub передаёт уже готовые строки/числа/цвета.
# ============================================================================
@tool
class_name CosmeticCard
extends PanelContainer

signal action_pressed

@export var icon_size: Vector2 = Vector2(26, 26):
	set(v):
		icon_size = v
		if _icon != null:
			_icon.icon_size = v
@export var card_min_width: float = 258.0:
	set(v):
		card_min_width = v
		custom_minimum_size.x = v

@onready var _row: HBoxContainer = %Row
@onready var _icon: PerkIconView = %Icon
@onready var _info: VBoxContainer = %Info
@onready var _name_label: Label = %NameLabel
@onready var _state_label: Label = %StateLabel
@onready var _action_btn: Button = %ActionBtn

func _ready() -> void:
	custom_minimum_size.x = card_min_width
	_row.add_theme_constant_override("separation", 10)
	_info.add_theme_constant_override("separation", 3)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon.icon_size = icon_size
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_name_label.add_theme_font_override("font", Fonts.bold)
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color.WHITE)

	_state_label.add_theme_font_override("font", Fonts.regular)
	_state_label.add_theme_font_size_override("font_size", 9)
	_state_label.add_theme_color_override("font_color", Cfg.UI_MUTED)

	_style_button(_action_btn, UiKit.small(""))
	if not _action_btn.pressed.is_connected(_on_action_pressed):
		_action_btn.pressed.connect(_on_action_pressed)

	if Engine.is_editor_hint():
		set_data("cos_camo_forest", Cfg.UI_TEXT, "Лесной камуфляж", "Цена: 120 🪙",
			"Купить · 120 🪙", false, false, true, "cos_camo_forest")

func _on_action_pressed() -> void:
	action_pressed.emit()

## Донор стилбоксов/шрифта — переносит уже готовую разметку кнопки,
## собранной через UiKit.small(), на существующий узел сцены (тот же
## приём, что в main_menu.gd). Донор в дерево не добавляется.
func _style_button(target: Button, donor: Button) -> void:
	for prop in ["normal", "hover", "pressed", "disabled"]:
		var sb := donor.get_theme_stylebox(prop)
		if sb != null:
			target.add_theme_stylebox_override(prop, sb)
	target.add_theme_font_override("font", donor.get_theme_font("font"))
	target.add_theme_font_size_override("font_size", donor.get_theme_font_size("font_size"))
	for col in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		target.add_theme_color_override(col, donor.get_theme_color(col))
	donor.queue_free()

func set_data(perk_id: String, icon_color: Color, name_text: String, state_text: String,
		action_text: String, action_disabled: bool, equipped: bool, can_buy: bool,
		card_id: String) -> void:
	set_meta("card_id", card_id)
	var border := Cfg.UI_ACCENT_DIM if equipped else (Color(Cfg.UI_GOLD, 0.45) if can_buy else Cfg.UI_BORDER)
	add_theme_stylebox_override("panel", UiKit.card_style(border))

	_icon.perk_id = perk_id
	_icon.icon_color = icon_color
	_name_label.text = name_text
	_state_label.text = state_text

	_action_btn.text = action_text
	_action_btn.disabled = action_disabled
	_action_btn.set_meta("card_id", card_id)
