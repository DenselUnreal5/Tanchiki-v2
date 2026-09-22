@tool
class_name UpgradeCard
extends PanelContainer

signal buy_pressed

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
@onready var _desc_label: Label = %DescLabel
@onready var _segs: HBoxContainer = %Segs
@onready var _max_wrap: FocusRingPanel = %MaxWrap
@onready var _max_label: Label = %MaxLabel
@onready var _buy_btn: Button = %BuyBtn

func _ready() -> void:
	custom_minimum_size.x = card_min_width
	_row.add_theme_constant_override("separation", 10)
	_info.add_theme_constant_override("separation", 3)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon.icon_size = icon_size
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_segs.add_theme_constant_override("separation", 2)

	_name_label.add_theme_font_override("font", Fonts.bold)
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color.WHITE)

	_desc_label.add_theme_font_override("font", Fonts.regular)
	_desc_label.add_theme_font_size_override("font_size", 9)
	_desc_label.add_theme_color_override("font_color", Cfg.UI_MUTED)

	_max_wrap.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_max_label.add_theme_font_override("font", Fonts.bold)
	_max_label.add_theme_font_size_override("font_size", 10)
	_max_label.add_theme_color_override("font_color", Cfg.UI_ACCENT)

	_style_button(_buy_btn, UiKit.small(""))
	if not _buy_btn.pressed.is_connected(_on_buy_pressed):
		_buy_btn.pressed.connect(_on_buy_pressed)

	if Engine.is_editor_hint():
		set_data("upg_dmg", "Мощный ствол", "Урон своих пуль", 3, 8, "Улучшить · 235 🪙",
			"МАКС", false, false, "upg_dmg")

func _on_buy_pressed() -> void:
	buy_pressed.emit()

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

func set_data(perk_id: String, name_text: String, desc_text: String,
		level: int, max_level: int, buy_text: String, max_text: String,
		maxed: bool, can_buy: bool, card_id: String) -> void:
	set_meta("card_id", card_id)
	var border := Cfg.UI_ACCENT_DIM if maxed else (Color(Cfg.UI_GOLD, 0.45) if can_buy else Cfg.UI_BORDER)
	add_theme_stylebox_override("panel", UiKit.card_style(border))

	_icon.perk_id = perk_id
	_icon.icon_color = Cfg.UI_TEXT
	_name_label.text = name_text
	_desc_label.text = desc_text

	for c in _segs.get_children():
		c.queue_free()
	for i in range(1, max_level + 1):
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(12, 4)
		seg.color = Cfg.UI_GOLD if i <= level else Cfg.UI_BORDER
		_segs.add_child(seg)

	_max_wrap.visible = maxed
	_buy_btn.visible = not maxed
	_max_wrap.set_meta("card_id", card_id)
	if maxed:
		_max_label.text = max_text
	else:
		_buy_btn.text = buy_text
		_buy_btn.disabled = not can_buy
		_buy_btn.set_meta("card_id", card_id)
