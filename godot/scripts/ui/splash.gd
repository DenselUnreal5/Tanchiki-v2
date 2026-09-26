class_name Splash
extends Control

## Современная кинематографичная заставка игры.
## Отображает высокодетализированный герб с бронетанковой эмблемой,
## неоновые тактические интерфейсы, анимированные частицы, лазерный блик,
## статусную строку калибровки систем и информацию об авторе.
## Любая клавиша или клик мыши мгновенно пропускает заставку.

signal finished

const TOTAL_DURATION := 2.5
const NUM_PARTICLES := 35

var _time := 0.0
var _progress := 0.0
var _shockwave_r := 0.0
var _shockwave_alpha := 0.0
var _flare_alpha := 0.0
var _flare_x := 0.0

var _fading_out := false
var _main_tween: Tween = null
var _particles: Array = []

var _emblem_holder: Control
var _emblem: TextureRect
var _author_box: VBoxContainer
var _title_box: VBoxContainer
var _bar_holder: VBoxContainer
var _status_label: Label
var _bar_draw: Control
var _skip_hint: Label

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

func _ready() -> void:
	grab_focus()
	_init_particles()
	_build_ui()
	_start_intro_animation()

func _unhandled_input(event: InputEvent) -> void:
	if _fading_out:
		return
	if event is InputEventKey and event.pressed:
		_skip()
	elif event is InputEventMouseButton and event.pressed:
		_skip()
	elif event is InputEventJoypadButton and event.pressed:
		_skip()

func _gui_input(event: InputEvent) -> void:
	if _fading_out:
		return
	if event is InputEventMouseButton and event.pressed:
		_skip()

func _init_particles() -> void:
	var vp_sz := get_viewport_rect().size
	if vp_sz.x <= 0:
		vp_sz = Vector2(1280, 720)
	for i in NUM_PARTICLES:
		var col := Color("#f59e0b") if randf() < 0.65 else Color("#38bdf8")
		_particles.append({
			"x": randf() * vp_sz.x,
			"y": randf() * vp_sz.y,
			"speed": randf_range(25.0, 70.0),
			"size": randf_range(1.5, 3.5),
			"color": col,
			"alpha": randf_range(0.25, 0.75),
			"phase": randf_range(0.0, TAU),
		})

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var main_col := UiKit.vbox(12)
	main_col.alignment = BoxContainer.ALIGNMENT_CENTER
	main_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(main_col)

	# --- 1. Автор / Продюсер ---
	_author_box = UiKit.vbox(2)
	_author_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_author_box.modulate.a = 0.0
	main_col.add_child(_author_box)

	var pres_label := UiKit.label("П Р Е Д С Т А В Л Я Е Т", 10, Color("#64748b"), true)
	pres_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_author_box.add_child(pres_label)

	var name_label := UiKit.label("—  ДЕНИС ГОРЯЧЕВ  —", 13, Color("#cbd5e1"), true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_author_box.add_child(name_label)

	# --- 2. Эмблема Танка ---
	_emblem_holder = Control.new()
	_emblem_holder.custom_minimum_size = Vector2(210, 210)
	_emblem_holder.pivot_offset = Vector2(105, 105)
	_emblem_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_emblem_holder.modulate.a = 0.0
	main_col.add_child(_emblem_holder)

	_emblem = TextureRect.new()
	_emblem.texture = load("res://icon.svg")
	_emblem.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_emblem.custom_minimum_size = Vector2(210, 210)
	_emblem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_emblem_holder.add_child(_emblem)

	# --- 3. Название игры ---
	_title_box = UiKit.vbox(2)
	_title_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_box.modulate.a = 0.0
	main_col.add_child(_title_box)

	var title_lbl := UiKit.title("Т Я Н Ч И К И", 44, Color("#ffffff"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_box.add_child(title_lbl)

	var sub_lbl := UiKit.label("B A T T L E   T A N K S", 14, Color("#f59e0b"), true)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_box.add_child(sub_lbl)

	var tag_lbl := UiKit.label("TACTICAL TOP-DOWN ARMORED WARFARE", 10, Color("#64748b"))
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_box.add_child(tag_lbl)

	# Отступ
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	main_col.add_child(spacer)

	# --- 4. Прогресс-бар калибровки систем ---
	_bar_holder = UiKit.vbox(6)
	_bar_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar_holder.modulate.a = 0.0
	main_col.add_child(_bar_holder)

	_bar_draw = Control.new()
	_bar_draw.custom_minimum_size = Vector2(320, 6)
	_bar_draw.draw.connect(_on_bar_draw)
	_bar_holder.add_child(_bar_draw)

	_status_label = UiKit.label("ИНИЦИАЛИЗАЦИЯ БОЕВОГО ЯДРА...", 11, Color("#94a3b8"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_holder.add_child(_status_label)

	# --- 5. Подсказка о пропуске внизу ---
	_skip_hint = UiKit.label("[ НАЖМИТЕ ЛЮБУЮ КЛАВИШУ ДЛЯ ВХОДА ]", 11, Color("#475569"))
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -340
	_skip_hint.offset_top = -42
	_skip_hint.offset_right = -32
	_skip_hint.offset_bottom = -20
	add_child(_skip_hint)

func _start_intro_animation() -> void:
	modulate.a = 0.0
	_main_tween = create_tween()
	_main_tween.set_parallel(true)

	# 1. Плавный общий fade-in
	_main_tween.tween_property(self, "modulate:a", 1.0, 0.35)

	# 2. Появление строки создателя
	_main_tween.tween_property(_author_box, "modulate:a", 1.0, 0.45).set_delay(0.1)

	# 3. Эмблема: мощное пружинящее увеличение + проявление
	_emblem_holder.scale = Vector2(0.65, 0.65)
	_main_tween.tween_property(_emblem_holder, "scale", Vector2(1.04, 1.04), 0.65) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.25)
	_main_tween.tween_property(_emblem_holder, "modulate:a", 1.0, 0.45).set_delay(0.25)

	# 4. Ударная волна и горизонтальный блик
	_main_tween.tween_property(self, "_shockwave_r", 280.0, 0.75) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.4)
	_main_tween.tween_property(self, "_shockwave_alpha", 0.85, 0.1).set_delay(0.4)
	_main_tween.tween_property(self, "_shockwave_alpha", 0.0, 0.65).set_delay(0.5)

	# Световой горизонтальный лазерный скан
	_main_tween.tween_property(self, "_flare_alpha", 1.0, 0.2).set_delay(0.45)
	_main_tween.tween_property(self, "_flare_alpha", 0.0, 0.5).set_delay(0.65)
	_main_tween.tween_property(self, "_flare_x", 1.0, 0.8).set_delay(0.4)

	# Звук подтверждения активации
	_main_tween.tween_callback(_play_activation_sound).set_delay(0.4)

	# 5. Возврат масштаба эмблемы в 1.0
	_main_tween.tween_property(_emblem_holder, "scale", Vector2(1.0, 1.0), 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(0.9)

	# 6. Проявление названия игры
	_main_tween.tween_property(_title_box, "modulate:a", 1.0, 0.5).set_delay(0.65)

	# 7. Проявление строки прогресса
	_main_tween.tween_property(_bar_holder, "modulate:a", 1.0, 0.4).set_delay(0.75)

	# 8. Прогресс калибровки систем (0.0 -> 1.0)
	_main_tween.tween_method(_set_progress, 0.0, 1.0, 1.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.75)

	# 9. Финальный переход в меню
	_main_tween.chain().tween_interval(0.45)
	_main_tween.chain().tween_callback(_finish_naturally)

func _play_activation_sound() -> void:
	var sfx_node: Node = get_node_or_null("/root/Sfx")
	if sfx_node != null:
		if sfx_node.has_method("play_ui"):
			sfx_node.call("play_ui")
		elif sfx_node.has_method("play"):
			sfx_node.call("play", "unlock")

func _set_progress(val: float) -> void:
	_progress = clampf(val, 0.0, 1.0)
	if _bar_draw != null and is_instance_valid(_bar_draw):
		_bar_draw.queue_redraw()

	if _status_label != null and is_instance_valid(_status_label):
		if _progress < 0.35:
			_status_label.text = "ИНИЦИАЛИЗАЦИЯ БОЕВОГО ЯДРА..."
			_status_label.add_theme_color_override("font_color", Color("#94a3b8"))
		elif _progress < 0.70:
			_status_label.text = "КАЛИБРОВКА ОРУДИЙНЫХ СИСТЕМ..."
			_status_label.add_theme_color_override("font_color", Color("#cbd5e1"))
		elif _progress < 0.96:
			_status_label.text = "ЗАГРУЗКА ТАКТИЧЕСКИХ ПРОТОКОЛОВ..."
			_status_label.add_theme_color_override("font_color", Color("#f59e0b"))
		else:
			_status_label.text = "БОЕВЫЕ СИСТЕМЫ ГОТОВЫ  [ 100% ]"
			_status_label.add_theme_color_override("font_color", Color("#4ade80"))

func _skip() -> void:
	if _fading_out:
		return
	_fading_out = true
	if _main_tween != null and _main_tween.is_valid():
		_main_tween.kill()

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func():
		finished.emit()
	)

func _finish_naturally() -> void:
	if _fading_out:
		return
	_fading_out = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func():
		finished.emit()
	)

func _process(delta: float) -> void:
	_time += delta

	# Движение частиц вверх с синусоидальным дрейфом
	var sz := size
	if sz.x <= 0:
		sz = get_viewport_rect().size
	for p in _particles:
		p.y -= float(p.speed) * delta
		p.x += sin(_time * 1.5 + float(p.phase)) * 0.45
		if p.y < -10.0:
			p.y = sz.y + 10.0
			p.x = randf() * sz.x

	# Пульсация подсказки о пропуске
	if _skip_hint != null and is_instance_valid(_skip_hint):
		var pulse := 0.45 + 0.35 * sin(_time * 4.0)
		_skip_hint.modulate.a = pulse

	# Небольшое плавное дыхание эмблемы после раскрытия
	if _emblem_holder != null and is_instance_valid(_emblem_holder) and not _fading_out:
		if _time > 1.2:
			var breathe := 1.0 + 0.015 * sin((_time - 1.2) * 2.5)
			_emblem_holder.scale = Vector2(breathe, breathe)

	queue_redraw()

func _on_bar_draw() -> void:
	if _bar_draw == null:
		return
	var b_sz := _bar_draw.size
	# Фоновая подложка
	_bar_draw.draw_rect(Rect2(Vector2.ZERO, b_sz), Color("#0a0f1d"))
	_bar_draw.draw_rect(Rect2(Vector2.ZERO, b_sz), Color("#1e293b"), false, 1.0)

	# Заполнение
	var fill_w := b_sz.x * _progress
	if fill_w > 0:
		var fill_color := Color("#f59e0b") if _progress < 0.96 else Color("#4ade80")
		_bar_draw.draw_rect(Rect2(Vector2.ZERO, Vector2(fill_w, b_sz.y)), fill_color)

		# Свечение ведущего края
		var tip_x := fill_w
		_bar_draw.draw_line(Vector2(tip_x, -1), Vector2(tip_x, b_sz.y + 1), Color("#ffffff", 0.9), 2.0)
		_bar_draw.draw_circle(Vector2(tip_x, b_sz.y * 0.5), 3.0, Color("#38bdf8", 0.8))

func _draw() -> void:
	var sz := size
	if sz.x <= 0 or sz.y <= 0:
		sz = get_viewport_rect().size

	# 1. Глубокий кинематографичный космический фон
	draw_rect(Rect2(Vector2.ZERO, sz), Color("#060911"))

	# 2. Мягкое радиальное свечение в центре
	var center := sz * 0.5
	var r_outer := minf(sz.x, sz.y) * 0.55
	draw_circle(center, r_outer, Color("#0d1527", 0.5))
	draw_circle(center, r_outer * 0.65, Color("#131d33", 0.4))
	var halo_alpha := 0.08 * (0.8 + 0.2 * sin(_time * 2.5))
	draw_circle(center, 140.0, Color("#f59e0b", halo_alpha))

	# 3. Тактическая сетка с мягкими линиями
	var grid_step := 64.0
	var grid_col := Color("#38bdf8", 0.035)
	var x := fmod(0.0, grid_step)
	while x < sz.x:
		draw_line(Vector2(x, 0), Vector2(x, sz.y), grid_col, 1.0)
		x += grid_step

	var y := fmod(0.0, grid_step)
	while y < sz.y:
		draw_line(Vector2(0, y), Vector2(sz.x, y), grid_col, 1.0)
		y += grid_step

	# Тактические перекрестия на пересечениях сетки
	var cross_col := Color("#38bdf8", 0.08)
	var cx := grid_step * 2.0
	while cx < sz.x - grid_step:
		var cy := grid_step * 2.0
		while cy < sz.y - grid_step:
			draw_line(Vector2(cx - 3, cy), Vector2(cx + 3, cy), cross_col, 1.0)
			draw_line(Vector2(cx, cy - 3), Vector2(cx, cy + 3), cross_col, 1.0)
			cy += grid_step * 3.0
		cx += grid_step * 3.0

	# 4. Летающие микро-частицы / пылинки
	for p in _particles:
		var p_pos := Vector2(float(p.x), float(p.y))
		var p_col: Color = p.color
		var a: float = float(p.alpha) * (0.6 + 0.4 * sin(_time * 3.0 + float(p.phase)))
		p_col.a = a
		draw_circle(p_pos, float(p.size), p_col)

	# 5. Ударная волна от появления логотипа
	if _shockwave_alpha > 0.01:
		var shock_c := Color("#f59e0b", _shockwave_alpha)
		draw_arc(center, _shockwave_r, 0, TAU, 64, shock_c, 2.5)
		var inner_c := Color("#38bdf8", _shockwave_alpha * 0.6)
		draw_arc(center, maxf(1.0, _shockwave_r - 12.0), 0, TAU, 64, inner_c, 1.5)

	# 6. Горизонтальный анаморфный лазерный блик (flare)
	if _flare_alpha > 0.01:
		var beam_y := center.y - 10.0
		var sweep_pos_x := sz.x * _flare_x

		# Тонкий луч через весь экран
		draw_line(Vector2(0, beam_y), Vector2(sz.x, beam_y),
			Color("#38bdf8", _flare_alpha * 0.35), 6.0)
		draw_line(Vector2(0, beam_y), Vector2(sz.x, beam_y),
			Color("#ffffff", _flare_alpha * 0.85), 1.5)

		# Центральная вспышка
		draw_circle(Vector2(sweep_pos_x, beam_y), 42.0 * _flare_alpha, Color("#38bdf8", _flare_alpha * 0.3))
		draw_circle(Vector2(sweep_pos_x, beam_y), 18.0 * _flare_alpha, Color("#ffffff", _flare_alpha * 0.95))

	# 7. Тактические угловые скобы HUD
	_draw_hud_corners(sz)

func _draw_hud_corners(sz: Vector2) -> void:
	var m := 24.0
	var blen := 28.0
	var b_col := Color("#38bdf8", 0.45)
	var t_col := Color("#64748b", 0.65)

	var font: Font = get_theme_default_font()
	var fonts_node: Node = get_node_or_null("/root/Fonts")
	if fonts_node != null and "regular" in fonts_node and fonts_node.regular != null:
		font = fonts_node.regular

	# Верх-лево
	draw_line(Vector2(m, m), Vector2(m + blen, m), b_col, 2.0)
	draw_line(Vector2(m, m), Vector2(m, m + blen), b_col, 2.0)
	if font != null:
		draw_string(font, Vector2(m + 10, m + 22),
			"[ PROTOCOL // ARMORED COMBAT v0.9.22 ]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, t_col)

	# Верх-право
	draw_line(Vector2(sz.x - m, m), Vector2(sz.x - m - blen, m), b_col, 2.0)
	draw_line(Vector2(sz.x - m, m), Vector2(sz.x - m, m + blen), b_col, 2.0)
	if font != null:
		draw_string(font, Vector2(sz.x - m - 200, m + 22),
			"[ SYS.DIAGNOSTICS // ONLINE ]", HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, t_col)

	# Низ-лево
	draw_line(Vector2(m, sz.y - m), Vector2(m + blen, sz.y - m), b_col, 2.0)
	draw_line(Vector2(m, sz.y - m), Vector2(m, sz.y - m - blen), b_col, 2.0)
	if font != null:
		draw_string(font, Vector2(m + 10, sz.y - m - 10),
			"[ TARGET MATRIX: ENGAGED // LAT 59.93° N ]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, t_col)

	# Низ-право
	draw_line(Vector2(sz.x - m, sz.y - m), Vector2(sz.x - m - blen, sz.y - m), b_col, 2.0)
	draw_line(Vector2(sz.x - m, sz.y - m), Vector2(sz.x - m, sz.y - m - blen), b_col, 2.0)
