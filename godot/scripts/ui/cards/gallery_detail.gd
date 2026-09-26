@tool
class_name GalleryDetail
extends ThemedPanel

@export var icon_size: Vector2 = Vector2(80, 80):
	set(v):
		icon_size = v
		if _icon != null:
			_icon.icon_size = v
@export var panel_min_width: float = 240.0:
	set(v):
		panel_min_width = v
		custom_minimum_size.x = v

@onready var _box: VBoxContainer = %Box
@onready var _icon_center: CenterContainer = %IconCenter
@onready var _icon: PerkIconView = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _desc_label: Label = %DescLabel
@onready var _build_label: Label = %BuildLabel
@onready var _footer: VBoxContainer = %FooterWrap

func _ready() -> void:
	super._ready()
	seed_value = randi()
	custom_minimum_size.x = panel_min_width
	_box.add_theme_constant_override("separation", 6)
	_icon_center.custom_minimum_size = Vector2(0, 92)
	_icon.icon_size = icon_size
	_icon.rough = true

	_name_label.add_theme_font_override("font", Fonts.bold)
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.custom_minimum_size = Vector2(208, 0)

	_desc_label.add_theme_font_override("font", Fonts.regular)
	_desc_label.add_theme_font_size_override("font_size", 11)
	_desc_label.add_theme_color_override("font_color", Cfg.UI_MUTED)
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(208, 0)

	_build_label.add_theme_font_override("font", Fonts.bold)
	_build_label.add_theme_font_size_override("font_size", 10)
	_build_label.add_theme_color_override("font_color", Cfg.UI_ACCENT)
	_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_label.custom_minimum_size = Vector2(208, 0)
	_build_label.visible = false

	if Engine.is_editor_hint():
		set_perk("lightning_lord", "Повелитель молний",
			"Во время грозы молнии с небес с вероятностью 25% бьют в ближайший вражеский танк.",
			true, {}, "ОТКРЫТ", "", false,
			"⚡ ВЛАДЫКА БУРИ\nПовелитель молний + Небесный удар + Цепная молния\n" +
			"Вечная гроза над ареной, а шанс небесного удара возрастает до 75%")

func set_perk(perk_id: String, name_text: String, desc_text: String, unlocked: bool,
		challenge: Dictionary, unlock_label_text: String, task_label_text: String = "",
		is_active: bool = false, build_text: String = "", synergy_color: Color = Color.TRANSPARENT) -> void:
	_icon.perk_id = perk_id
	_icon.icon_color = Cfg.UI_TEXT if unlocked else Cfg.UI_MUTED
	_name_label.text = name_text
	_desc_label.text = desc_text
	_build_label.text = build_text
	_build_label.visible = build_text != ""
	if synergy_color != Color.TRANSPARENT:
		_build_label.add_theme_color_override("font_color", synergy_color)
	else:
		_build_label.add_theme_color_override("font_color", Cfg.UI_ACCENT)

	for c in _footer.get_children():
		c.queue_free()
	if unlocked:
		_footer.add_child(UiKit.unlock_button(unlock_label_text, "unlocked"))
	elif not challenge.is_empty():
		var task_label := UiKit.label(task_label_text, 10, Cfg.UI_WARN)
		task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		task_label.custom_minimum_size = Vector2(208, 0)
		_footer.add_child(task_label)
		var cur := int(challenge["current"])
		var need := int(challenge["need"])
		_footer.add_child(UiKit.progress_bar(float(cur) / float(maxi(need, 1)), 200, 5, Cfg.UI_WARN))
		var prog := UiKit.label("%d / %d" % [cur, need], 10, Cfg.UI_MUTED)
		prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_footer.add_child(prog)
	else:
		_footer.add_child(UiKit.unlock_button(unlock_label_text, "locked"))

	if synergy_color != Color.TRANSPARENT:
		border_color = Color(synergy_color, 0.8)
	else:
		border_color = Cfg.UI_WARN if is_active else Color.TRANSPARENT
	queue_redraw()
