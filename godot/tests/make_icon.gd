# ============================================================================
# make_icon.gd — растрирование icon.svg в PNG для сборки .ico.
#
# Иконка .exe обязана быть растровой и многоразмерной: Windows берёт из файла
# тот размер, который ей нужен, а не масштабирует один. Здесь каждый размер
# растрируется из ВЕКТОРА отдельно — так мелкие остаются чёткими, а не
# получаются мылом из уменьшенного большого.
#
# Запуск:
#   godot --headless --path godot tests/make_icon.tscn
# ============================================================================
extends Node

const SIZES := [16, 24, 32, 48, 64, 128, 256]
const OUT := "user://icon_png/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	print("OUT=", ProjectSettings.globalize_path(OUT))
	var f := FileAccess.open("res://icon.svg", FileAccess.READ)
	var svg := f.get_as_text()
	f.close()

	for size in SIZES:
		var img := Image.new()
		# Исходник нарисован в 128 px, поэтому масштаб — отношение к нему.
		var err := img.load_svg_from_string(svg, float(size) / 128.0)
		if err != OK or img.get_width() != size:
			# Округление масштаба иногда даёт пиксель мимо: доводим точно.
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		img.save_png(OUT + "icon_%d.png" % size)
		print("  %d×%d готов" % [size, size])
	get_tree().quit(0)
