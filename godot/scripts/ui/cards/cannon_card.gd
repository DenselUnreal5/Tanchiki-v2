@tool
class_name CannonCard
extends PanelContainer

signal action_pressed

@export var icon_size: Vector2 = Vector2(26, 26):
	set(v):
		icon_size = v
		if _icon != null:
			_icon.custom_minimum_size = v
@export var icon_font_size: int = 22:
	set(v):
		icon_font_size = v
		if _icon != null:
			_icon.add_theme_font_size_override("font_size", v)
@export var card_min_width: float = 258.0:
	set(v):
		card_min_width = v
		custom_minimum_size.x = v

@onready var _row: HBoxContainer = %Row
@onready var _icon: Label = %Icon
@onready var _info: VBoxContainer = %Info
@onready var _name_label: Label = %NameLabel
@onready var _state_label: Label = %StateLabel
@onready var _action_btn: Button = %ActionBtn

func _ready() -> void:
	custom_minimum_size.x = card_min_width
	_row.add_theme_constant_override("separation", 10)
	_info.add_theme_constant_override("separation", 3)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_icon.add_theme_font_override("font", Fonts.regular)
	_icon.add_theme_font_size_override("font_size", icon_font_size)
	_icon.custom_minimum_size = icon_size
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
		set_data("❄️", Cfg.UI_TEXT, "Ледяная пушка", "Цена: 400 🪙",
			"Купить · 400 🪙", false, false, true, "cannon_ice")

func _on_action_pressed() -> void:
	action_pressed.emit()

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

var _tex_view: PerkIconView

func _set_tex_icon(tex_id: String, color: Color) -> void:
	if tex_id == "":
		if _tex_view != null:
			_tex_view.visible = false
		return
	if _tex_view == null:
		_tex_view = PerkIconView.new()
		_icon.add_child(_tex_view)
		_tex_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex_view.visible = true
	_tex_view.perk_id = tex_id
	_tex_view.icon_color = color

func set_data(icon_text: String, icon_color: Color, name_text: String, state_text: String,
		action_text: String, action_disabled: bool, equipped: bool, can_buy: bool,
		card_id: String) -> void:
	set_meta("card_id", card_id)
	var border := Cfg.UI_ACCENT_DIM if equipped else (Color(Cfg.UI_GOLD, 0.45) if can_buy else Cfg.UI_BORDER)
	add_theme_stylebox_override("panel", UiKit.card_style(border))

	var has_tex := PerkIcons.texture_of(card_id) != null
	_icon.text = "" if has_tex else icon_text
	_icon.add_theme_color_override("font_color", icon_color)
	_set_tex_icon(card_id if has_tex else "", icon_color)
	_name_label.text = name_text
	_state_label.text = state_text

	_action_btn.text = action_text
	_action_btn.disabled = action_disabled
	_action_btn.set_meta("card_id", card_id)
