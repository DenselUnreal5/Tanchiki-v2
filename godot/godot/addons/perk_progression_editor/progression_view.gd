# ============================================================================
# progression_view.gd — вкладка «Прогрессия перков»: визуальный редактор
# Perks.UNLOCK_TABLE. Перетаскиванием переносишь карточку перка из одной
# колонки уровня в другую, «Сохранить» переписывает UNLOCK_TABLE в
# perks.gd (и только его — остальной файл не трогается).
#
# «Позиция» перка в игровой галерее — это не порядок в массивах
# LIST/EXTRA_LIST/..., а именно уровень открытия из UNLOCK_TABLE (см.
# ui_root.gd:_fill_gallery_tab, сортировка по Perks.unlock_level_of()).
# Поэтому редактор работает с уровнями, а не с порядком записей.
#
# Челлендж-перки (perk.has("challenge")) в UNLOCK_TABLE не участвуют —
# открываются заданием, не уровнем. Показаны отдельным нередактируемым
# рядом внизу, для справки.
# ============================================================================
@tool
extends Control

const PERKS_PATH := "res://scripts/perks.gd"
const MAX_LEVEL := 20

var _levels: Dictionary = {}    # int level -> Array[String] id перков
var _challenge_ids: Array = []  # String id — только для показа, без drag

var _dirty := false

var _status_label: Label
var _save_btn: Button
var _levels_row: HBoxContainer
var _challenge_row: HFlowContainer

# ------------------------------------------------------------ карточка перка
class PerkCard extends PanelContainer:
	var perk_id := ""
	var level := 0
	var draggable := false

	func _init() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.06)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		add_theme_stylebox_override("panel", sb)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if not draggable:
			return null
		var preview := Label.new()
		preview.text = perk_id
		preview.modulate = Color(1, 1, 1, 0.85)
		set_drag_preview(preview)
		return {"perk_id": perk_id, "from_level": level}

# --------------------------------------------------------- колонка уровня
class LevelColumn extends PanelContainer:
	var level := 0
	var host: Control
	var list: VBoxContainer

	func _init() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.03)
		sb.border_color = Color(1, 1, 1, 0.12)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		add_theme_stylebox_override("panel", sb)
		list = VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		add_child(list)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("perk_id") \
			and int(data.get("from_level", -1)) != level

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		host.move_perk(String(data["perk_id"]), int(data["from_level"]), level)

# ===========================================================================
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_from_perks()
	_refresh_columns()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	root.add_child(toolbar)

	var title := Label.new()
	title.text = "Прогрессия перков — перетащи карточку в другую колонку уровня"
	toolbar.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_status_label = Label.new()
	_status_label.modulate = Color(1, 1, 1, 0.6)
	toolbar.add_child(_status_label)

	var reload_btn := Button.new()
	reload_btn.text = "Обновить"
	reload_btn.tooltip_text = "Перечитать UNLOCK_TABLE из perks.gd, отменив несохранённые правки"
	reload_btn.pressed.connect(func():
		_load_from_perks()
		_refresh_columns())
	toolbar.add_child(reload_btn)

	_save_btn = Button.new()
	_save_btn.tooltip_text = "Переписать UNLOCK_TABLE в perks.gd.\n" \
		+ "Внимание: поясняющие комментарии между уровнями внутри таблицы " \
		+ "будут потеряны — после перестановки перков они всё равно теряют смысл."
	_save_btn.pressed.connect(_save_to_perks)
	toolbar.add_child(_save_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_levels_row = HBoxContainer.new()
	_levels_row.add_theme_constant_override("separation", 6)
	scroll.add_child(_levels_row)

	root.add_child(HSeparator.new())

	var challenge_header := Label.new()
	challenge_header.text = "Челленджи (открываются заданием, не уровнем — не перетаскиваются)"
	challenge_header.modulate = Color(1, 1, 1, 0.6)
	root.add_child(challenge_header)

	_challenge_row = HFlowContainer.new()
	_challenge_row.add_theme_constant_override("h_separation", 6)
	_challenge_row.add_theme_constant_override("v_separation", 6)
	root.add_child(_challenge_row)

	_update_save_button()

# ------------------------------------------------------------- данные
func _load_from_perks() -> void:
	_levels.clear()
	_challenge_ids.clear()

	var keys := {}
	for lvl in range(1, MAX_LEVEL + 1):
		keys[lvl] = true
	for lvl in Perks.UNLOCK_TABLE.keys():
		keys[int(lvl)] = true
	for lvl in keys.keys():
		_levels[int(lvl)] = []
	for lvl in Perks.UNLOCK_TABLE.keys():
		var ids: Array = Perks.UNLOCK_TABLE[lvl]
		for id in ids:
			_levels[int(lvl)].append(String(id))

	for perk in Perks.all():
		if perk.has("challenge"):
			_challenge_ids.append(String(perk["id"]))

	_dirty = false
	_update_save_button()
	if is_instance_valid(_status_label):
		_status_label.text = "Загружено из perks.gd"

func move_perk(id: String, from_level: int, to_level: int) -> void:
	if from_level == to_level:
		return
	if _levels.has(from_level):
		_levels[from_level].erase(id)
	if not _levels.has(to_level):
		_levels[to_level] = []
	if not _levels[to_level].has(id):
		_levels[to_level].append(id)
	_dirty = true
	_update_save_button()
	_status_label.text = "%s: уровень %d → %d (не сохранено)" % [id, from_level, to_level]
	_refresh_columns()

func _update_save_button() -> void:
	if not is_instance_valid(_save_btn):
		return
	_save_btn.text = "Сохранить*" if _dirty else "Сохранить"
	_save_btn.disabled = not _dirty

# --------------------------------------------------------------- отрисовка
func _refresh_columns() -> void:
	for c in _levels_row.get_children():
		c.queue_free()
	for c in _challenge_row.get_children():
		c.queue_free()

	var level_keys: Array = _levels.keys()
	level_keys.sort()
	for lvl in level_keys:
		_levels_row.add_child(_build_level_column(lvl))

	for id in _challenge_ids:
		_challenge_row.add_child(_build_card(id, 0, false))

func _build_level_column(lvl: int) -> Control:
	var col := LevelColumn.new()
	col.level = lvl
	col.host = self
	col.custom_minimum_size = Vector2(100, 0)

	var head := Label.new()
	head.text = "Ур. %d" % lvl
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.list.add_child(head)

	var ids: Array = _levels.get(lvl, [])
	for id in ids:
		col.list.add_child(_build_card(id, lvl, true))
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "—"
		empty.modulate = Color(1, 1, 1, 0.3)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.list.add_child(empty)
	return col

func _build_card(id: String, lvl: int, draggable: bool) -> Control:
	var perk: Dictionary = Perks.get_perk(id)
	var card := PerkCard.new()
	card.perk_id = id
	card.level = lvl
	card.draggable = draggable
	card.custom_minimum_size = Vector2(84, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var icon_center := CenterContainer.new()
	var icon := PerkIconView.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.perk_id = id
	icon.icon_color = Color(1, 1, 1, 0.9)
	icon_center.add_child(icon)
	box.add_child(icon_center)

	var name_label := Label.new()
	name_label.text = String(perk.get("name", id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 10)
	box.add_child(name_label)

	return card

# ------------------------------------------------------------- сохранение
func _save_to_perks() -> void:
	var f := FileAccess.open(PERKS_PATH, FileAccess.READ)
	if f == null:
		_status_label.text = "Ошибка: не удалось открыть perks.gd"
		return
	var text := f.get_as_text()
	f.close()

	var start_marker := "const UNLOCK_TABLE := {"
	var start := text.find(start_marker)
	if start < 0:
		_status_label.text = "Ошибка: не найден UNLOCK_TABLE в perks.gd"
		return
	var brace_start := start + start_marker.length() - 1
	var depth := 0
	var i := brace_start
	var end := -1
	while i < text.length():
		var ch := text[i]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				end = i
				break
		i += 1
	if end < 0:
		_status_label.text = "Ошибка: не найдена закрывающая скобка UNLOCK_TABLE"
		return

	var level_keys: Array = _levels.keys()
	level_keys.sort()
	var body := "{\n"
	var filled := 0
	for lvl in level_keys:
		var ids: Array = _levels[lvl]
		if ids.is_empty():
			continue
		filled += 1
		var quoted := PackedStringArray()
		for id in ids:
			quoted.append("\"%s\"" % id)
		body += "\t%d: [%s],\n" % [lvl, ", ".join(quoted)]
	body += "}"

	var new_text := text.substr(0, brace_start) + body + text.substr(end + 1)
	var out := FileAccess.open(PERKS_PATH, FileAccess.WRITE)
	if out == null:
		_status_label.text = "Ошибка: не удалось записать perks.gd"
		return
	out.store_string(new_text)
	out.close()

	_dirty = false
	_update_save_button()
	_status_label.text = "Сохранено: %d уровней с перками" % filled

	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.update_file(PERKS_PATH)
