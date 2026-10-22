extends Node

var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)

func _ready() -> void:
	check(StatsHistory.clean(null).is_empty() and StatsHistory.clean([null, 1, {}, {"mode": "bad"}]).is_empty(), "missing/malformed history is safely empty")
	var rows := []
	for i in 75: rows.append({"mode": "ffa" if i % 2 else "ctf", "kills": i, "deaths": i % 5, "damage": i * 10})
	var clean := StatsHistory.clean(rows)
	check(clean.size() == 60 and clean[0].kills == 15 and clean[-1].kills == 74, "only newest sixty results are retained in chronological order")
	var filtered := StatsHistory.filtered(clean, "ffa", 10)
	check(filtered.size() == 10 and filtered[0].kills == 55 and filtered[-1].kills == 73, "mode and count filters select the correct recent matches")
	var sanitized: Dictionary = StatsHistory.clean([{"mode": "ffa", "kills": -12, "damage": -5, "class": "unknown", "cannon": "unknown"}])[0]
	check(sanitized.kills == 0 and sanitized.damage == 0 and sanitized["class"] == "standard" and sanitized.cannon == "standard", "invalid counters and equipment are sanitized")
	var damaged: Dictionary = StatsHistory.clean([{"mode": "ffa", "kills": {}, "date": [], "damage": "150"}])[0]
	check(damaged.kills == 0 and damaged.date == 0 and damaged.damage == 150, "damaged numeric fields cannot crash profile loading")
	var profile = load("res://scripts/profile.gd").new()
	profile._empty_stats()
	profile._empty_upgrades()
	profile._apply({"schema": 6, "stats": {"totalKills": 321, "gamesWon": 12}})
	check(profile.match_history.is_empty() and profile.stats.totalKills == 321 and profile.stats.gamesWon == 12, "legacy profile retains all-time counters without invented match history")
	profile.free()
	Prof.match_history = []
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var player := PlayerState.new(0, "History", "p1", null)
	player.kills = 9
	player.deaths = 2
	player.damage_dealt = 345.6
	player.equipped_class = "scout"
	player.equipped_cannon = "ice"
	var map := GameMap.new(8, 8)
	map.fill(Cfg.T_GRASS)
	var world := World.new({"map": map, "level": {"seed": 42}, "mode": "ffa", "difficulty": "medium", "players": [player], "puppet": true})
	world.tick = 7200
	game.world = world
	game.players = [player]
	game._record_match_history({"victory": true})
	game._record_match_history({"victory": true})
	check(Prof.match_history.size() == 1, "finish callback records a match exactly once")
	var entry: Dictionary = Prof.match_history[0]
	check(entry.kills == 9 and entry.deaths == 2 and entry.damage == 346 and entry.seconds == 120 and entry["class"] == "scout" and entry.cannon == "ice" and entry.victory, "history uses actual player results, duration and equipped loadout")
	var disk = JSON.parse_string(FileAccess.get_file_as_string(Prof.SAVE_PATH))
	check(disk.schema == 7 and disk.matchHistory.size() == 1 and disk.matchHistory[0].kills == 9, "result survives profile JSON serialization")
	var restored = load("res://scripts/profile.gd").new()
	restored._empty_stats()
	restored._empty_upgrades()
	restored._apply(disk)
	check(restored.match_history == Prof.match_history, "history is restored on reload")
	restored.free()
	var role := Net.role
	Net.role = "client"
	game._history_recorded = false
	game._record_match_history({"victory": false})
	check(Prof.match_history.size() == 1, "client does not save incomplete non-authoritative damage totals")
	player.tank = Tank.new({"x": 64, "y": 64, "team": "player", "name": "Client", "max_hp": 100.0, "speed": 2.0, "fire_rate": 30, "net_id": 21})
	world.tanks = [player.tank]
	game._record_match_history({"stats_history": {"21": {"mode": "ctf", "victory": true, "kills": 17, "damage": 920}}})
	check(Prof.match_history.size() == 2 and Prof.match_history[-1].kills == 17 and Prof.match_history[-1].damage == 920, "client records authoritative host finish totals for its own tank")
	var other := PlayerState.new(1, "Opponent", "p2", null)
	other.kills = 4
	other.tank = Tank.new({"x": 96, "y": 96, "team": "enemy", "name": "Opponent", "max_hp": 100.0, "speed": 2.0, "fire_rate": 30, "net_id": 22})
	world.tanks.append(other.tank)
	game.players = [player, other]
	var host_rows: Dictionary = game._finish_history_rows({"winner_player_index": 1})
	check(not host_rows["21"].victory and host_rows["22"].victory and host_rows["22"].kills == 4, "host prepares per-player FFA results with correct winner and totals")
	world.mode = "ctf"
	host_rows = game._finish_history_rows({"winner_team": "enemy"})
	check(not host_rows["21"].victory and host_rows["22"].victory, "CTF history victory follows the player's team")
	world.mode = "defense"
	host_rows = game._finish_history_rows({"victory": true})
	check(host_rows["21"].victory and host_rows["22"].victory, "cooperative defense preserves shared victory")
	Net.role = role
	world.dispose()
	game.world = null
	game.players = []
	game.queue_free()
	Prof.reset()
	check(Prof.match_history.is_empty(), "profile reset clears match history")
	print("=== STATS HISTORY: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
