class_name VehiclePreview
extends Control

# A real Control reserves space in containers; MenuTankView itself is a Node2D.
var view: MenuTankView
var compact := false
var accent := Color("#81b76d")

func setup(entry: Dictionary, unlocked: bool, small: bool = false) -> void:
	compact = small
	custom_minimum_size = Vector2(48, 48) if compact else Vector2(0, 132)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var id := String(entry.get("id", ""))
	var player := bool(entry.get("is_player", false))
	accent = Cfg.UI_ACCENT if player else (Cfg.UI_DANGER if entry.get("category") == "boss" else Cfg.UI_GOLD)
	var stub := PlayerState.new(0, "", String(entry.get("color_key", "p1")), null)
	var tank := Tank.new({"x": 0.0, "y": 0.0, "owner": stub if player else null,
		"team": "player" if player else "enemy", "name": "",
		"color_key": String(entry.get("color_key", "enemy")),
		"chassis": String(entry.get("chassis", "standard")),
		"max_hp": 100.0, "speed": 0.0, "fire_rate": 30})
	tank.spawn_protect = 0
	tank.cannon_id = String(entry.get("cannon_id", "standard"))
	if not player: tank.enemy_type = EnemyTypes.get_type(id)
	tank.is_chimera_clone = id == "chimera_clone"
	tank.is_chimera_boss = id == "boss_chimera"
	tank.is_rammer_boss = id == "boss_rammer"
	view = MenuTankView.new()
	view.player = stub
	view.display_tank = tank
	view.auto_turret = not compact and unlocked
	view.is_locked = not unlocked
	add_child(view)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if view == null: return
	var zoom := 1.0 if compact else 2.7
	if view.display_tank.is_rammer_boss or view.display_tank.is_chimera_boss or view.display_tank.is_chimera_clone:
		zoom *= 0.7
	view.scale = Vector2.ONE * zoom
	view.position = (size * 0.5).round()
	queue_redraw()

func _draw() -> void:
	if compact: return
	draw_style_box(UiKit.flat(Color("#101714"), 6, 1, Color(accent, 0.25)), Rect2(Vector2.ZERO, size))
	for x in range(16, int(size.x), 24):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(accent, 0.06))
	for y in range(12, int(size.y), 24):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(accent, 0.06))
	var center := size * 0.5
	draw_arc(center, 52, 0, TAU, 48, Color(accent, 0.18), 1.0)
	for sign_x in [-1, 1]:
		for sign_y in [-1, 1]:
			var point := center + Vector2(sign_x * 66, sign_y * 54)
			draw_line(point, point - Vector2(sign_x * 12, 0), Color(accent, 0.6), 2)
			draw_line(point, point - Vector2(0, sign_y * 12), Color(accent, 0.6), 2)
