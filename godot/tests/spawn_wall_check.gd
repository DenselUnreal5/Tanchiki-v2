extends Node

# Ищет танки, оказавшиеся внутри непроходимых блоков (стена, кирпич, саман):
# гоняет короткие матчи на всех локациях и после каждого кадра проверяет клетку под центром танка.
# Запуск: godot --headless --path . res://tests/spawn_wall_check.tscn

const FRAMES := 900
const MODES := ["ffa", "ctf", "defense"]
const SEEDS := [101, 202, 303]

var failures := 0
var game: Node

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	for loc in Locations.ORDER:
		for mode in MODES:
			for seed_value in SEEDS:
				await _run(loc, mode, seed_value)
	print("танков в стенах: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _run(loc: String, mode: String, seed_value: int) -> void:
	var s: Dictionary = game.ui.settings
	s["mode"] = mode
	s["game_type"] = "single"
	s["location"] = loc
	s["weather"] = "clear"
	s["daytime"] = "day"
	s["level"] = 3
	s["seed"] = seed_value
	s["difficulty"] = "medium"
	game.start_match()
	var seen := {}
	var found := 0
	for f in FRAMES:
		while game.state == "perk":
			game._on_perk_chosen(game.perk_player, "")
		if game.state == "paused":
			game.resume()
		var world = game.world
		if world == null:
			break
		for t in world.tanks:
			if not t.alive:
				continue
			var r: int = world.map.row_at(t.y)
			var c: int = world.map.col_at(t.x)
			var tile: int = world.map.get_tile(r, c)
			if not GameMap.is_solid_tile(tile):
				continue
			var key := "%s:%d" % [t.id, t.deaths]
			if seen.has(key):
				continue
			seen[key] = true
			found += 1
			print("  %-7s %-8s seed %d  кадр %4d  %-10s %-8s бот=%s  клетка (%d,%d) тип %d" % [
				loc, mode, seed_value, f, t.name, String(t.enemy_type.get("id", "-")),
				str(t.is_bot), r, c, tile])
		await get_tree().process_frame
	failures += found
	print("%-7s %-8s seed %d: %s" % [loc, mode, seed_value, "ОК" if found == 0 else "в стенах %d" % found])
	game.to_menu()
	await get_tree().process_frame
