# ============================================================================
# plugin.gd — регистрирует главный экран «Прогрессия перков» (рядом с
# «2D»/«3D»/«Script»/«AssetLib»). Вся логика — в progression_view.gd,
# этот файл только вставляет/убирает вкладку из редактора.
# ============================================================================
@tool
extends EditorPlugin

var _view: Control

func _enter_tree() -> void:
	_view = preload("res://addons/perk_progression_editor/progression_view.gd").new()
	EditorInterface.get_editor_main_screen().add_child(_view)
	_make_visible(false)

func _exit_tree() -> void:
	if is_instance_valid(_view):
		_view.queue_free()
	_view = null

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if is_instance_valid(_view):
		_view.visible = visible

func _get_plugin_name() -> String:
	return "Прогрессия перков"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Favorites", "EditorIcons")
