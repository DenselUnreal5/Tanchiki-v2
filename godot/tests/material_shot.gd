extends Node

var game: Node
const ARTIFACT_DIR := "c:/Users/Eskaro/.gemini/antigravity/brain/f8599ebc-e35b-4a32-98f2-37d024bc2379/"
const LOCAL_DIR := "c:/Users/Eskaro/Desktop/кто тут попка/neirogame/Tanchiki-v2/screenshots/"

func _ready() -> void:
	print("Запуск Material Shot...")
	DirAccess.make_dir_recursive_absolute(LOCAL_DIR)
	DirAccess.make_dir_recursive_absolute(ARTIFACT_DIR)

	Sets.ui_theme = "material"
	Cfg.apply_theme("material")

	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

	await _frames(30)
	await _save("menu_material")

	# Settings screen showing Material theme
	game.ui.open_settings()
	await _frames(15)
	await _save("settings_material")
	game.ui.close_settings()
	await _frames(8)

	# Garage Hub showing Material cards
	game.ui.open_garage()
	await _frames(15)
	await _save("garage_material")
	game.ui.close_garage()
	await _frames(8)

	# Gallery screen showing Material squircle skill nodes
	game.ui.open_gallery()
	await _frames(15)
	await _save("gallery_material")
	game.ui.close_gallery()
	await _frames(8)

	print("Все снимки успешно сохранены!")
	get_tree().quit(0)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		var path1 := ARTIFACT_DIR + file_name + ".png"
		var path2 := LOCAL_DIR + file_name + ".png"
		img.save_png(path1)
		img.save_png(path2)
		print("Снимок сохранён: ", file_name, ".png (", img.get_width(), "x", img.get_height(), ")")
