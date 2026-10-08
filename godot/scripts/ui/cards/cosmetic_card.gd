@tool
class_name CosmeticCard
extends PanelContainer

signal action_pressed
signal preview_requested(type: String, id: String)

@export var icon_size: Vector2 = Vector2(30, 30):
	set(v):
		icon_size = v
		if _icon != null:
			_icon.icon_size = v
@export var card_min_width: float = 252.0:
	set(v):
		card_min_width = v
		custom_minimum_size.x = v

@onready var _card_box: VBoxContainer = %CardBox
@onready var _header_row: HBoxContainer = %HeaderRow
@onready var _icon_wrap: PanelContainer = %IconWrap
@onready var _icon: PerkIconView = %Icon
@onready var _header_info: VBoxContainer = %HeaderInfo
@onready var _name_label: Label = %NameLabel
@onready var _badge_label: RichTextLabel = %BadgeLabel
@onready var _desc_label: Label = %DescLabel
@onready var _footer_row: HBoxContainer = %FooterRow
@onready var _state_label: Label = %StateLabel
@onready var _action_btn: Button = %ActionBtn

var _cosmetic_type: String = ""
var _cosmetic_id: String = ""
var _is_equipped: bool = false
var _rarity: String = ""
var _border_color: Color = Cfg.UI_BORDER

func _ready() -> void:
	custom_minimum_size.x = card_min_width
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_PASS

	_card_box.add_theme_constant_override("separation", 6)
	_header_row.add_theme_constant_override("separation", 8)
	_header_info.add_theme_constant_override("separation", 2)
	_header_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_icon_wrap.custom_minimum_size = Vector2(38, 38)
	_icon_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.icon_size = icon_size
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	_name_label.add_theme_font_override("font", Fonts.bold)
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color.WHITE)

	_badge_label.add_theme_font_override("normal_font", Fonts.bold)
	_badge_label.add_theme_font_size_override("normal_font_size", 9)
	_badge_label.fit_content = true
	_badge_label.scroll_active = false
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_desc_label.add_theme_font_override("font", Fonts.regular)
	_desc_label.add_theme_font_size_override("font_size", 10)
	_desc_label.add_theme_color_override("font_color", Color(Cfg.UI_TEXT, 0.82))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(card_min_width - 24.0, 36.0)
	_desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_footer_row.add_theme_constant_override("separation", 6)
	_footer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_state_label.add_theme_font_override("font", Fonts.bold)
	_state_label.add_theme_font_size_override("font_size", 10)
	_state_label.add_theme_color_override("font_color", Cfg.UI_GOLD)
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_style_button(_action_btn, UiKit.small(""))
	if not _action_btn.pressed.is_connected(_on_action_pressed):
		_action_btn.pressed.connect(_on_action_pressed)

	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(_on_focus_entered)
	gui_input.connect(_on_gui_input)

	if Engine.is_editor_hint():
		set_data("cos_skin_cyberpunk", Color("#00f0ff"), "Неоновый Киберпанк", "380 🪙",
			"Купить · 380 🪙", false, false, true, "cos_skin_cyberpunk", "legendary",
			"Полный кибер-комплект: корпус с микросхемами, башня с визором и светящиеся гусеницы.", "skin", "cyberpunk")

func _on_action_pressed() -> void:
	action_pressed.emit()

func _on_mouse_entered() -> void:
	_trigger_preview()

func _on_focus_entered() -> void:
	_trigger_preview()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_trigger_preview()

func _trigger_preview() -> void:
	if _cosmetic_type != "" and _cosmetic_id != "":
		preview_requested.emit(_cosmetic_type, _cosmetic_id)

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
		card_id: String, rarity: String = "", desc_text: String = "",
		cos_type: String = "", cos_id: String = "") -> void:
	set_meta("card_id", card_id)
	_cosmetic_type = cos_type
	_cosmetic_id = cos_id
	_is_equipped = equipped
	_rarity = rarity

	var border := Cfg.UI_ACCENT if equipped else (
		Color("#ffd700", 0.90) if rarity == "legendary" else (
			Color("#c084fc", 0.85) if rarity == "epic" else (
				Color("#60a5fa", 0.80) if rarity == "rare" else (
					Color(Cfg.UI_GOLD, 0.45) if can_buy else Cfg.UI_BORDER
				)
			)
		)
	)
	_border_color = border

	# Rich card stylebox with margin padding
	var bg_col := Color(0.12, 0.14, 0.18, 0.96) if equipped else Color(0.08, 0.09, 0.11, 0.92)
	var card_sb := UiKit.flat(bg_col, Cfg.RADIUS_SM, 2.0 if equipped else 1.2, border)
	card_sb.content_margin_left = 10
	card_sb.content_margin_right = 10
	card_sb.content_margin_top = 8
	card_sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", card_sb)

	# Icon wrap box
	var icon_bg := UiKit.flat(Color(0.05, 0.06, 0.08, 0.95), Cfg.RADIUS_SM, 1.0, border * 0.7)
	icon_bg.content_margin_left = 4
	icon_bg.content_margin_right = 4
	icon_bg.content_margin_top = 4
	icon_bg.content_margin_bottom = 4
	_icon_wrap.add_theme_stylebox_override("panel", icon_bg)

	_icon.perk_id = perk_id
	_icon.icon_color = icon_color

	_name_label.text = name_text

	var badge_bbcode := ""
	if cos_type == "skin":
		if rarity == "legendary":
			badge_bbcode = "[color=#ffd700]ЛЕГЕНДАРНЫЙ · ПОЛНЫЙ КОМПЛЕКТ[/color]"
		elif rarity == "epic":
			badge_bbcode = "[color=#c084fc]ЭПИЧЕСКИЙ · ПОЛНЫЙ КОМПЛЕКТ[/color]"
		elif rarity == "rare":
			badge_bbcode = "[color=#60a5fa]РЕДКИЙ · ПОЛНЫЙ КОМПЛЕКТ[/color]"
		else:
			badge_bbcode = "[color=#94a3b8]БАЗОВЫЙ КОМПЛЕКТ[/color]"
	else:
		if rarity == "legendary":
			badge_bbcode = "[color=#ffd700]ЛЕГЕНДАРНЫЙ[/color]"
		elif rarity == "epic":
			badge_bbcode = "[color=#c084fc]ЭПИЧЕСКИЙ[/color]"
		elif rarity == "rare":
			badge_bbcode = "[color=#60a5fa]РЕДКИЙ[/color]"
		else:
			match cos_type:
				"camo": badge_bbcode = "[color=#94a3b8]КАМУФЛЯЖ[/color]"
				"hull": badge_bbcode = "[color=#94a3b8]ДЕКАЛЬ КОРПУСА[/color]"
				"track": badge_bbcode = "[color=#94a3b8]ГУСЕНИЦЫ[/color]"
				"turret": badge_bbcode = "[color=#94a3b8]БАШНЯ[/color]"
				_: badge_bbcode = "[color=#94a3b8]КОСМЕТИКА[/color]"

	_badge_label.text = badge_bbcode

	_desc_label.text = desc_text

	_state_label.text = state_text
	if equipped:
		_state_label.add_theme_color_override("font_color", Cfg.UI_ACCENT)
	elif can_buy:
		_state_label.add_theme_color_override("font_color", Cfg.UI_GOLD)
	else:
		_state_label.add_theme_color_override("font_color", Cfg.UI_MUTED)

	_action_btn.text = action_text
	_action_btn.disabled = action_disabled
	_action_btn.set_meta("card_id", card_id)
