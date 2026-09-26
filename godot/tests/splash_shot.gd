extends Node

var splash: Splash
const ARTIFACT_DIR := "c:/Users/Eskaro/.gemini/antigravity/brain/f8599ebc-e35b-4a32-98f2-37d024bc2379/"
const LOCAL_DIR := "c:/Users/Eskaro/Desktop/кто тут попка/neirogame/Tanchiki-v2/screenshots/"

func _ready() -> void:
	print("Запуск Splash Shot...")
	DirAccess.make_dir_recursive_absolute(LOCAL_DIR)
	DirAccess.make_dir_recursive_absolute(ARTIFACT_DIR)

	splash = Splash.new()
	add_child(splash)

	for i in 100:
		await get_tree().process_frame

	await _save("splash_iron_storm")
	print("Снимок заставки успешно сохранён!")
	get_tree().quit(0)

func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		var path1 := ARTIFACT_DIR + file_name + ".png"
		var path2 := LOCAL_DIR + file_name + ".png"
		img.save_png(path1)
		img.save_png(path2)
		print("Снимок сохранён: ", file_name, ".png (", img.get_width(), "x", img.get_height(), ")")
