# ============================================================================
# splash.gd — экран логотипа при запуске.
#
# Показывается один раз, перед первым меню: пока Sfx/Mus достраивают звук
# в фоне (см. audio.gd/music.gd — они уже не блокируют старт сами по себе,
# но окно сплэша даёт этому времени пройти незаметно). Ничего не грузит и
# не ждёт сам — длительность держит вызывающий код (game.gd), сплэш только
# рисует. Логотипа отдельным файлом в проекте нет: используется тот же
# силуэт танка, что и icon.svg (он же иконка .exe), увеличенный.
# ============================================================================
class_name Splash
extends Control

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Cfg.UI_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := UiKit.vbox(16)
	center.add_child(col)

	var icon := TextureRect.new()
	icon.texture = load("res://icon.svg")
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.custom_minimum_size = Vector2(220, 220)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)

	var name_label := UiKit.label("Горячев Денис Викторович", 14, Cfg.UI_MUTED)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(name_label)

	# Лёгкое проявление — единственная анимация, никакой другой «кинематики».
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
