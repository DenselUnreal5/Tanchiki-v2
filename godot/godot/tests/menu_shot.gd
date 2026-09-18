# ============================================================================
# menu_shot.gd — снимок меню на выбранном языке.
#
# Полнота словаря (i18n_check) доказывает, что ключи есть, но не то, что
# игрок увидит английский текст: строку могли собрать мимо переводчика.
# Здесь снимается то, что реально нарисовано.
#
# Запуск (с окном, не headless):
#   godot --path godot tests/menu_shot.tscn
# ============================================================================
extends Node

const OUT := "user://menu_shot/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	print("OUT=", ProjectSettings.globalize_path(OUT))
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for i in 8:
		await get_tree().process_frame

	# Само меню, без окон поверх: на нём видно версию сборки.
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "menu_plain.png")
	print("снято: menu_plain.png")

	for lang in ["en", "ru"]:
		I18n.set_lang(lang)
		var ui = game.ui
		ui.open_net()
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(OUT + "net_" + lang + ".png")
		print("снято: net_%s.png" % lang)
		ui.close_net()
		for i in 4:
			await get_tree().process_frame

	get_tree().quit(0)
