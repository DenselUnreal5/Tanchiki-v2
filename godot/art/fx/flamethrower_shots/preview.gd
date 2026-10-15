extends Node2D

# Replay one-shot animations only in this preview scene.
func _ready() -> void:
	for child in get_children():
		if child is AnimatedSprite2D:
			child.animation_finished.connect(child.play)
			child.play()
