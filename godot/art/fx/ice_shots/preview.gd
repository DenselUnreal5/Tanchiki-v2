extends Node2D

# Replay one-shot effects only in the preview.
func _ready() -> void:
	for child in get_children():
		if child is AnimatedSprite2D:
			child.animation_finished.connect(child.play)
			child.play()
