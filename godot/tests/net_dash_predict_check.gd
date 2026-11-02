extends Node

# Регрессионный тест сетевого предикта (фикс 01.11: рассинхрон клиента).
# Клиентский predict_move с реплеем неподтверждённых команд обязан сходиться
# с авторитетным world.step() после reconcile — в том числе во время рывка.
# Плюс проверка запасной точки спавна find_fallback_spot (не стена, не вода).
# Запуск: godot --headless --path . res://tests/net_dash_predict_check.tscn

var failures := 0

const LAG_TICKS := 5
const SNAP_EVERY := 25
const TICKS := 200
const POS_EPS := 0.5

class ScriptedScheme extends RefCounted:
	var cmd_of_tick: Callable

	func apply(tank: Tank, _player, world) -> void:
		Ctl.apply_command(tank, world, cmd_of_tick.call(world.tick))

func _ready() -> void:
	await get_tree().process_frame
	_check_dash_predict_parity()
	_check_fallback_spot()
	print("=== ПРОВЕРКА СЕТЕВОГО ПРЕДИКТА ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _script_cmd(tick: int) -> Dictionary:
	var cmd := {"mx": 0.0, "my": 1.0, "ax": 1.0, "ay": 0.0}
	if tick >= 60 and tick < 90:
		cmd["mx"] = 1.0
		cmd["my"] = 0.0
	if tick == 30 or tick == 170:
		cmd["dash"] = true
	return NetProtocol.canonical_command(cmd)

func _make_puppet_world(seed_value: int) -> World:
	var level := LevelGen.generate(1, "ffa", seed_value, "city")
	var scheme := ScriptedScheme.new()
	scheme.cmd_of_tick = _script_cmd
	var player := PlayerState.new(0, "Тест", "p1", scheme)
	player.reset_for_match()
	var world := World.new({
		"map": level["map"], "level": level, "mode": "ffa", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": seed_value, "puppet": true,
	})
	world._spawn_player_tank(player, "human_0")
	return world

func _snapshot(t: Tank) -> Dictionary:
	return {
		"x": t.x, "y": t.y, "vx": t.vx, "vy": t.vy,
		"body": t.body_angle, "turret": t.turret_angle,
		"dash": t.dash_range, "dash_dir": t.dash_dir, "dash_stall": t.dash_stall,
	}

func _restore(t: Tank, s: Dictionary) -> void:
	t.x = float(s["x"])
	t.y = float(s["y"])
	t.vx = float(s["vx"])
	t.vy = float(s["vy"])
	t.body_angle = float(s["body"])
	t.angle = t.body_angle
	t.turret_angle = float(s["turret"])
	t.dash_range = float(s["dash"])
	t.dash_stall = int(s["dash_stall"])
	t.dash_dir = s["dash_dir"] if t.dash_range > 0.0 else Vector2.ZERO

func _check_dash_predict_parity() -> void:
	var host := _make_puppet_world(9876)
	var client := _make_puppet_world(9876)
	var ht: Tank = host.players[0].tank
	var ct: Tank = client.players[0].tank
	_check(ht != null and ct != null, "танки созданы в обоих мирах")
	if ht == null or ct == null:
		host.dispose()
		client.dispose()
		return

	var host_hist: Array = []
	var cmd_hist: Array = []
	var worst := 0.0
	for i in TICKS:
		var cmd: Dictionary = _script_cmd(host.tick + 1)
		host.step()
		ct.predict_move(client, cmd)
		host_hist.append(_snapshot(ht))
		cmd_hist.append(cmd)
		if host.tick % SNAP_EVERY == 0 and host.tick > LAG_TICKS:
			var snap_i := host_hist.size() - 1 - LAG_TICKS
			_restore(ct, host_hist[snap_i])
			for j in range(snap_i + 1, cmd_hist.size()):
				ct.predict_move(client, cmd_hist[j])
			var dist := Vector2(ct.x - ht.x, ct.y - ht.y).length()
			worst = maxf(worst, dist)

	_check(ht.dash_cooldown > 0, "рывок на хосте реально сработал (кд %d)" % ht.dash_cooldown)
	_check(worst <= POS_EPS,
		"после reconcile+реплей клиент сходится с хостом (худшее расхождение %.3f px)" % worst)
	host.dispose()
	client.dispose()

func _check_fallback_spot() -> void:
	for loc in Locations.ORDER:
		for seed_value in [11, 22]:
			var lvl := LevelGen.generate(1, "ffa", seed_value, loc)
			var map: GameMap = lvl["map"]
			var spot := map.find_fallback_spot(30.0, 30.0)
			_check(not map.is_blocked_rect(spot.x, spot.y, 30.0, 30.0),
				"%s/seed %d: запасная клетка не в стене" % [loc, seed_value])
			_check(not map.is_water_at(spot.x, spot.y),
				"%s/seed %d: запасная клетка не в воде" % [loc, seed_value])

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)
