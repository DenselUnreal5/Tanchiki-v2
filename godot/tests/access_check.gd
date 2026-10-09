extends Node

var game: Node
var failures := 0

const DEUTAN := [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
const PROTAN := [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]
const TRITAN := [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for i in 30:
		await get_tree().process_frame
	var saved := [Sets.colorblind_mode, Sets.high_contrast, Sets.ui_scale, Sets.reduce_flashes]

	_check_palettes()
	_check_contrast()
	await _check_scale()
	_check_flashes()

	Sets.colorblind_mode = saved[0]
	Sets.high_contrast = saved[1]
	Sets.ui_scale = saved[2]
	Sets.reduce_flashes = saved[3]
	Sets.apply_look()
	print("=== ПРОВЕРКА ДОСТУПНОСТИ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _simulate(c: Color, matrix: Array) -> Vector3:
	var lin := c.srgb_to_linear()
	var v := Vector3(lin.r, lin.g, lin.b)
	return Vector3(
		v.dot(Vector3(matrix[0][0], matrix[0][1], matrix[0][2])),
		v.dot(Vector3(matrix[1][0], matrix[1][1], matrix[1][2])),
		v.dot(Vector3(matrix[2][0], matrix[2][1], matrix[2][2])))

func _separation(a: Color, b: Color, matrix: Array) -> float:
	return _simulate(a, matrix).distance_to(_simulate(b, matrix))

func _pair_report(label: String, matrix: Array, mode: int) -> void:
	Sets.colorblind_mode = 0
	Sets.high_contrast = false
	Sets.apply_look()
	var before := _separation(Cfg.team_palette("p1")["body"], Cfg.team_palette("enemy")["body"], matrix)
	var before_bullets := _separation(Cfg.bullet, Cfg.bullet_enemy, matrix)
	Sets.colorblind_mode = mode
	Sets.apply_look()
	var after := _separation(Cfg.team_palette("ally")["body"], Cfg.team_palette("enemy")["body"], matrix)
	var after_bullets := _separation(Cfg.bullet, Cfg.bullet_enemy, matrix)
	print("  %s: танки %.3f -> %.3f, снаряды %.3f -> %.3f" % [label, before, after, before_bullets, after_bullets])
	_check(after > before and after >= 0.05, "%s: свои и чужие танки различимее" % label)
	_check(after_bullets >= before_bullets * 0.9 and after_bullets >= 0.05, "%s: свои и чужие снаряды различимы" % label)

func _check_palettes() -> void:
	Sets.colorblind_mode = 0
	Sets.high_contrast = false
	Sets.apply_look()
	var base_enemy: Color = Cfg.team_palette("enemy")["body"]
	var base_bullet: Color = Cfg.bullet_enemy
	_pair_report("протанопия", PROTAN, 1)
	_pair_report("дейтеранопия", DEUTAN, 1)
	_pair_report("тританопия", TRITAN, 2)
	Sets.colorblind_mode = 1
	Sets.apply_look()
	_check(Cfg.team_palette("enemy")["body"] != base_enemy and Cfg.bullet_enemy != base_bullet,
		"режим красный/зелёный меняет цвета")
	Sets.colorblind_mode = 0
	Sets.apply_look()
	_check(Cfg.team_palette("enemy")["body"] == base_enemy and Cfg.bullet_enemy == base_bullet,
		"выключение режима возвращает исходные цвета")

func _luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b

func _ratio(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

func _check_contrast() -> void:
	for theme_name in Cfg.THEMES.keys():
		Sets.ui_theme = theme_name
		Sets.high_contrast = false
		Sets.colorblind_mode = 0
		Sets.apply_look()
		var normal := _ratio(Cfg.UI_TEXT, Cfg.UI_PANEL)
		var muted_normal := _ratio(Cfg.UI_MUTED, Cfg.UI_PANEL)
		Sets.high_contrast = true
		Sets.apply_look()
		var high := _ratio(Cfg.UI_TEXT, Cfg.UI_PANEL)
		var muted_high := _ratio(Cfg.UI_MUTED, Cfg.UI_PANEL)
		print("  %s: текст %.1f -> %.1f, приглушённый %.1f -> %.1f" % [theme_name, normal, high, muted_normal, muted_high])
		_check(high >= 7.0 and high >= normal, "%s: контраст текста не ниже 7:1 (%.1f)" % [theme_name, high])
		_check(muted_high >= 4.5 and muted_high >= muted_normal, "%s: приглушённый текст не ниже 4.5:1 (%.1f)" % [theme_name, muted_high])
		_check(is_equal_approx(Cfg.UI_PANEL_ALPHA, 1.0), "%s: панели непрозрачные" % theme_name)
	Sets.ui_theme = "military"
	Sets.high_contrast = false
	Sets.apply_look()

func _check_scale() -> void:
	var ui = game.ui
	var screen: Vector2 = game.get_viewport().get_visible_rect().size
	Sets.ui_scale = 1.0
	game._apply_ui_scale()
	_check(ui.size.is_equal_approx(screen) and ui.scale.is_equal_approx(Vector2.ONE), "масштаб 100%: интерфейс на весь экран")
	Sets.ui_scale = 1.5
	game._apply_ui_scale()
	for i in 4:
		await get_tree().process_frame
	var eff := UiKit.ui_scale()
	var cap := minf(screen.x / Cfg.UI_MIN_VIRTUAL.x, screen.y / Cfg.UI_MIN_VIRTUAL.y)
	_check(is_equal_approx(eff, clampf(minf(1.5, cap), 1.0, 1.5)), "масштаб 150%% ограничен размером окна: %.2f" % eff)
	_check(eff > 1.0 and ui.scale.is_equal_approx(Vector2(eff, eff)), "масштаб применён к интерфейсу")
	_check((ui.size * eff).is_equal_approx(screen), "виртуальный размер интерфейса %s покрывает экран" % str(ui.size))
	_check(ui.size.x >= Cfg.UI_MIN_VIRTUAL.x - 0.5 and ui.size.y >= Cfg.UI_MIN_VIRTUAL.y - 0.5,
		"виртуальный экран не меньше минимума меню")
	_check(game.hud.scale.is_equal_approx(Vector2(eff, eff)), "масштаб применён к боевой панели")
	ui.show_pause()
	for i in 4:
		await get_tree().process_frame
	var panel_rect := Rect2(ui._pause_resume_btn.get_global_rect())
	_check(Rect2(Vector2.ZERO, screen).encloses(panel_rect), "кнопки паузы целиком на экране при большом масштабе")
	ui.hide_pause()
	Sets.ui_scale = 0.8
	game._apply_ui_scale()
	_check((ui.size * 0.8).is_equal_approx(screen), "масштаб 80%: виртуальный размер больше экрана")
	Sets.ui_scale = 1.0
	game._apply_ui_scale()

func _check_flashes() -> void:
	Sets.reduce_flashes = false
	_check(is_equal_approx(Sets.flash_scale(), 1.0), "вспышки по умолчанию полные")
	Sets.reduce_flashes = true
	_check(is_equal_approx(Sets.flash_scale(), Cfg.REDUCED_FLASH_SCALE), "режим «меньше вспышек» ослабляет вспышки")
	Sets.reduce_flashes = false

func _check(ok: bool, what: String) -> bool:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
	return ok
