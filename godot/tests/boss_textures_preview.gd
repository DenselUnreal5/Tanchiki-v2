extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene = load("res://art/tanks/bosses/bosses_preview.tscn").instantiate()
	root.add_child(scene)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("res://../screenshots/boss_textures_preview.png")
	print("Boss preview capture: ", err)
	quit(0 if err == OK else 1)
