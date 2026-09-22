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
		var err := img.load_svg_from_string(svg, float(size) / 128.0)
		if err != OK or img.get_width() != size:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		img.save_png(OUT + "icon_%d.png" % size)
		print("  %d×%d готов" % [size, size])
	get_tree().quit(0)
