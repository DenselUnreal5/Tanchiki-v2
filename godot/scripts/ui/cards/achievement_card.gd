# ============================================================================
# achievement_card.gd — одна карточка вкладки «Достижения» в Хабе. Раньше
# собиралась целиком в ui_root.gd:_fill_achievements_tab() на каждое
# достижение заново; теперь это сцена — размер иконки и ширина карточки
# редактируются в инспекторе, а Hub только вызывает set_data() с уже
# готовыми (переведёнными) данными.
#
# Карточка не кликабельна — FocusRingPanel нужна только чтобы геймпад/
# клавиатура вообще могли до неё дотянуться фокусом (обычный PanelContainer
# фокус не ловит).
#
# @tool: живой предпросмотр в редакторе. Ни один автозагрузочный класс
# (I18n/Prof) здесь не читается — Hub передаёт уже готовые строки/числа,
# поэтому предпросмотр не нуждается ни в каких обходах автозагрузок.
# ============================================================================
@tool
class_name AchievementCard
extends FocusRingPanel

@export var icon_size: Vector2 = Vector2(28, 28):
	set(v):
		icon_size = v
		if _icon != null:
			_icon.icon_size = v
@export var card_min_width: float = 168.0:
	set(v):
		card_min_width = v
		custom_minimum_size.x = v

@onready var _box: VBoxContainer = %Box
@onready var _icon: PerkIconView = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _desc_label: Label = %DescLabel
@onready var _reward_badge: Label = %RewardBadge
@onready var _prog_label: Label = %ProgLabel
@onready var _prog_bar_wrap: Control = %ProgBarWrap

func _ready() -> void:
	custom_minimum_size.x = card_min_width
	_box.add_theme_constant_override("separation", 3)
	_icon.icon_size = icon_size
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	_name_label.add_theme_font_override("font", Fonts.bold)
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_desc_label.add_theme_font_override("font", Fonts.regular)
	_desc_label.add_theme_font_size_override("font_size", 9)
	_desc_label.add_theme_color_override("font_color", Cfg.UI_MUTED)
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(148, 0)

	_reward_badge.add_theme_font_override("font", Fonts.bold)
	_reward_badge.add_theme_font_size_override("font_size", 9)
	_reward_badge.add_theme_color_override("font_color", Cfg.UI_GOLD)
	_reward_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_prog_label.add_theme_font_override("font", Fonts.regular)
	_prog_label.add_theme_font_size_override("font_size", 9)
	_prog_label.add_theme_color_override("font_color", Cfg.UI_MUTED)
	_prog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if Engine.is_editor_hint():
		set_data("ach_boss_1", "Убийца боссов", "Убить первого босса", false, 60, 3, 10)

## perk_id — тот же ключ, что раньше собирался как "ach_"+a["id"] в
## ui_root.gd; name_text/desc_text — уже переведённые строки (I18n.dn
## остаётся в hub.gd, карточка автозагрузок не касается).
func set_data(perk_id: String, name_text: String, desc_text: String,
		done: bool, reward: int, cur: int, need: int) -> void:
	add_theme_stylebox_override("panel",
		UiKit.card_style(Cfg.UI_ACCENT_DIM if done else Cfg.UI_BORDER))
	modulate.a = 1.0 if done else 0.65

	_icon.perk_id = perk_id
	_icon.icon_color = Cfg.UI_TEXT
	_name_label.text = name_text
	_desc_label.text = desc_text

	_reward_badge.visible = done
	_prog_label.visible = not done
	_prog_bar_wrap.visible = not done
	if done:
		_reward_badge.text = "%d 🪙" % reward
	else:
		_prog_label.text = "%d / %d" % [mini(cur, need), need]
		for c in _prog_bar_wrap.get_children():
			c.queue_free()
		var bar := UiKit.progress_bar(float(cur) / float(maxi(need, 1)), 148, 3, Cfg.UI_WARN)
		_prog_bar_wrap.add_child(bar)
