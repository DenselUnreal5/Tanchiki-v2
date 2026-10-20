extends Node

const TICKS := 3600
const DEFAULT_SEEDS := 4

const LOADOUTS := [
	{"id": "control", "cannon": "standard", "perks": []},
	{"id": "fire_stack", "cannon": "standard", "perks": ["rapid_fire", "quick_reload", "thermal"]},
	{"id": "tank_stack", "cannon": "standard", "perks": ["heavy_armor", "thick_armor", "evasion"]},
	{"id": "speed_ram", "cannon": "standard", "perks": ["sprinter", "ram", "turbo"]},
	{"id": "lightning", "cannon": "standard", "perks": ["lightning_lord", "sky_strike", "chain_lightning"], "build": true},
	{"id": "stealth_hunter", "cannon": "standard", "perks": ["predator", "forest", "shadow"], "build": true},
	{"id": "juggernaut", "cannon": "standard", "perks": ["ram", "thick_armor", "kamikaze"], "build": true},
	{"id": "ghost_sniper", "cannon": "standard", "perks": ["sniper", "evasion", "keen_ear"], "build": true},
	{"id": "fortress", "cannon": "standard", "perks": ["heavy_armor", "regen", "shield"], "build": true},
	{"id": "gunner", "cannon": "standard", "perks": ["rapid_fire", "thermal", "heat_sink"], "build": true},
	{"id": "fire_stack4", "cannon": "standard", "perks": ["rapid_fire", "quick_reload", "thermal", "heavy_shell"]},
	{"id": "lightning_plus", "cannon": "standard", "perks": ["lightning_lord", "sky_strike", "chain_lightning", "heavy_armor"], "build": true},
	{"id": "fortress_plus", "cannon": "standard", "perks": ["heavy_armor", "regen", "shield", "rapid_fire"], "build": true},
	{"id": "control_ice", "cannon": "ice", "perks": []},
	{"id": "ice_hunter", "cannon": "ice", "perks": ["deep_freeze", "frost_dash", "chilled_barrel"], "build": true},
	{"id": "control_acid", "cannon": "acid", "perks": []},
	{"id": "acid_hunter", "cannon": "acid", "perks": ["corrosive_acid", "acid_cloud", "corroding_armor"], "build": true},
	{"id": "control_fire", "cannon": "fire", "perks": []},
	{"id": "fire_hunter", "cannon": "fire", "perks": ["napalm", "slow_burn", "flashover"], "build": true},
	{"id": "control_shock", "cannon": "shock", "perks": []},
	{"id": "shock_hunter", "cannon": "shock", "perks": ["high_voltage", "arc_chain", "overload"], "build": true},
]

class Autopilot:
	var brain: BotBrain

	func _init(rng: Rng) -> void:
		brain = BotBrain.new({"accuracy": 0.8, "react_time": 12, "rng": rng})

	func apply(tank: Tank, _player, world) -> void:
		brain.update(tank, world)
		if tank.ability_id != "" and tank.ability_cd <= 0:
			tank.use_ability(world)

var seeds := DEFAULT_SEEDS
var out_path := ""
var only: Array = []

func _ready() -> void:
	var env := OS.get_environment("BUILD_BENCH_SEEDS")
	if env != "":
		seeds = maxi(1, int(env))
	out_path = OS.get_environment("BUILD_BENCH_OUT")
	var env_only := OS.get_environment("BUILD_BENCH_IDS")
	if env_only != "":
		only = env_only.split(",")

	var lines: Array[String] = []
	var results := {}
	var t0 := Time.get_ticks_msec()
	for entry in LOADOUTS:
		if not only.is_empty() and not only.has(String(entry["id"])):
			continue
		var kills := 0.0
		var deaths := 0.0
		var dealt := 0.0
		for s in seeds:
			var r := _run(entry, 1000 + s * 77)
			kills += float(r["kills"])
			deaths += float(r["deaths"])
			dealt += float(r["dealt"])
		var n := float(seeds)
		results[String(entry["id"])] = {"kills": kills / n, "deaths": deaths / n, "dealt": dealt / n}
		lines.append("%-16s убийств %5.1f | смертей %4.1f | урона %6.0f" % [
			entry["id"], kills / n, deaths / n, dealt / n])
		print(lines[-1])
	lines.append("")
	lines.append("Относительно контроля с той же пушкой (убийства / урон):")
	for entry in LOADOUTS:
		var id := String(entry["id"])
		if not results.has(id):
			continue
		var control_id := "control" if String(entry["cannon"]) == "standard" else "control_" + String(entry["cannon"])
		if not results.has(control_id) or id == control_id:
			continue
		var base: Dictionary = results[control_id]
		lines.append("  %-16s убийства ×%.2f | урон ×%.2f | смертей %+.1f" % [
			id, float(results[id]["kills"]) / maxf(0.1, float(base["kills"])),
			float(results[id]["dealt"]) / maxf(1.0, float(base["dealt"])),
			float(results[id]["deaths"]) - float(base["deaths"])])
	for l in lines:
		if l.begins_with("  ") or l.begins_with("Относит"):
			print(l)
	print("всего %.0f с" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(lines))
			f.close()
	get_tree().quit(0)

func _run(entry: Dictionary, seed_value: int) -> Dictionary:
	var rng := Rng.new(seed_value)
	var player := PlayerState.new(0, "Тест", "p1", Autopilot.new(rng))
	player.reset_for_match()
	player.equipped_cannon = String(entry["cannon"])
	var level := LevelGen.generate(1, "ffa", seed_value, "city")
	var world := World.new({
		"map": level["map"], "level": level, "mode": "ffa", "difficulty": "medium",
		"players": [player], "player_level": 1, "rng_seed": seed_value,
	})
	for id in entry["perks"]:
		player.equip_perk(String(id))
	world.check_player_synergies(player)
	world.maybe_summon_storm(player)
	for i in TICKS:
		world.step()
	var result := {"kills": player.kills, "deaths": player.deaths, "dealt": player.damage_dealt}
	world.dispose()
	return result
