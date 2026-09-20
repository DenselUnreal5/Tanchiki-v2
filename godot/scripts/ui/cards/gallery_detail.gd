# ============================================================================
# gallery_detail.gd — правая панель вкладки «Галерея перков» в Хабе:
# крупная иконка + название/описание + подвал (открыт / прогресс задания /
# «откроется на уровне N»). Раньше собиралась в ui_root.gd:_gallery_detail()
# заново при каждом клике по перку (см. _select_gallery_perk — частичная
# пересборка только этой панели, не всей вкладки); теперь сцена — крупный
# размер иконки редактируется в инспекторе.
#
# В отличие от карточек Гаража/Достижений это ЕДИНСТВЕННЫЙ экземпляр на
# вкладку (не по счётчику данных), поэтому получила полноценную сцену, а не
# только шаблон под instantiate() N раз.
#
# Подвал (unlock-кнопка / прогресс задания) — три взаимоисключающих
# состояния с разным набором дочерних виджетов (единственная кнопка,
# либо кнопка+полоска+подпись) — как и сегменты в upgrade_card.gd, это не
# фиксированная структура, поэтому строится кодом в set_perk() через
# UiKit.unlock_button()/progress_bar(), а не как узлы сцены.
#
# @tool: живой предпросмотр. Автозагрузки (Prof/I18n) не читаются —
# Hub передаёт уже готовые строки/числа/флаги.
# ============================================================================
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
			"Во время грозы — 25% шанс, что молния ударит по ближайшему вражескому танку",
			true, {}, "ОТКРЫТ", "", false,
			"⚡ ГРОЗОВОЙ БИЛД\nПовелитель молний + Небесный удар + Цепная молния\n" +
			"Все три перка сразу: шанс «Повелителя молний» растёт с 25% до 75%")

## unlocked — уже открыт (footer: одна кнопка "ОТКРЫТ"). challenge —
## непустой словарь {"desc","current","need"} для перка-испытания в
## процессе (footer: подпись задания + полоска + "N / M"); пустой словарь —
## перк не challenge. unlock_level — для остальных locked-перков (footer:
## "Откроется на уровне профиля N"). Тексты (task/unlock label) уже
## переведены вызывающим кодом (hub.gd), карточка сама I18n не читает.
## is_active — перк-способность по кнопке (perk.has("active")), а не
## пассивный бонус: подсвечиваем золотой рамкой панели независимо от
## unlocked/challenge/locked — это свойство самого перка, не его статуса.
## build_text — готовый (переведённый вызывающим кодом) блок про тематический
## билд (Perks.BUILDS), если перк — часть одного; пустая строка — перк ни в
## каком билде не участвует, блок скрыт.
func set_perk(perk_id: String, name_text: String, desc_text: String, unlocked: bool,
		challenge: Dictionary, unlock_label_text: String, task_label_text: String = "",
		is_active: bool = false, build_text: String = "") -> void:
	_icon.perk_id = perk_id
	_icon.icon_color = Cfg.UI_TEXT if unlocked else Cfg.UI_MUTED
	_name_label.text = name_text
	_desc_label.text = desc_text
	_build_label.text = build_text
	_build_label.visible = build_text != ""

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

	# UI_GOLD в теме Sci-Fi — мятно-бирюзовый (#a2f0dc), не жёлтый: рамка
	# сливалась бы с остальным интерфейсом именно в этой теме. UI_WARN во
	# всех трёх темах — стабильно жёлто-янтарный, это и даёт настоящий
	# жёлтый цвет, а не «золотой» по названию слота.
	border_color = Cfg.UI_WARN if is_active else Color.TRANSPARENT
	queue_redraw()
