extends Node

const LIMITS := {"ffa": 3 * 60 * 60, "defense": 9 * 60 * 60, "koth": 6 * 60 * 60, "ctf": 6 * 60 * 60}

class Autopilot:
	var brain: BotBrain

	func _init(rng: Rng, survival: bool) -> void:
		brain = BotBrain.new({"accuracy": 0.8, "react_time": 12, "rng": rng, "survival": survival})

	func apply(tank: Tank, player, world) -> void:
		var leash: bool = world.mode == "defense" and world.base != null \
			and Vector2(float(world.base["x"]) - tank.x, float(world.base["y"]) - tank.y).length() > 280.0
		if leash:
			brain._move_toward(tank, world, float(world.base["x"]), float(world.base["y"]))
			var threat = BotBrain.find_best_threat(tank, world)
			if threat != null:
				tank.aim_at(threat.x, threat.y)
				tank.shoot(world)
		else:
			brain.update(tank, world)
		if tank.ability_id != "" and tank.ability_cd <= 0:
			tank.use_ability(world)
		if world.mode == "defense" and world.airstrike_cooldown <= 0:
			world.trigger_airstrike(player)

var game: Node
var opts := {
	"modes": ["ffa", "defense", "koth", "ctf"],
	"diffs": ["easy", "medium", "hard"],
	"profiles": ["novice", "veteran"],
	"classes": ["standard"],
	"seeds": [11, 22],
}
var type_stats := {}

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).split("=", true, 1)
		if kv.size() != 2:
			continue
		var vals := Array(kv[1].split(","))
		if kv[0] == "seeds":
			var nums := []
			for v in vals:
				nums.append(int(v))
			opts["seeds"] = nums
		else:
			opts[kv[0]] = vals

func _ready() -> void:
	_parse_args()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var saved := {
		"upgrades": Prof.upgrades.duplicate(true), "class": Prof.equipped_class,
		"cannon": Prof.equipped_cannon, "level": Prof.global_level,
		"mutator": Sets.weekly_mutator,
	}
	Sets.weekly_mutator = false
	print("BAL|mode|diff|profile|class|seed|result|ticks|p_kills|p_deaths|p_dmg|bot_avg_kills|bot_avg_deaths|rank|extra")
	for mode in opts["modes"]:
		for diff in opts["diffs"]:
			for prof in opts["profiles"]:
				for cls in opts["classes"]:
					for s in opts["seeds"]:
						_set_profile(String(prof), String(cls))
						_run(String(mode), String(diff), String(prof), String(cls), int(s))
	for key in type_stats.keys():
		var ts: Dictionary = type_stats[key]
		print("TYPE|%s|n=%d|kills=%.2f|deaths=%.2f|dmg=%.0f" % [key, ts["n"], float(ts["kills"]) / ts["n"], float(ts["deaths"]) / ts["n"], float(ts["dmg"]) / ts["n"]])
	Prof.upgrades = saved["upgrades"]
	Prof.equipped_class = saved["class"]
	Prof.equipped_cannon = saved["cannon"]
	Prof.global_level = saved["level"]
	Sets.weekly_mutator = saved["mutator"]
	print("=== БАЛАНС-СИМУЛЯЦИЯ ЗАВЕРШЕНА ===")
	get_tree().quit(0)

func _set_profile(prof: String, cls: String) -> void:
	var ups := {}
	if prof == "veteran":
		for up in Upgrades.LIST:
			ups[String(up["id"])] = int(up["max_level"])
	Prof.upgrades = ups
	Prof.equipped_class = cls
	Prof.equipped_cannon = "standard"
	Prof.global_level = 30 if prof == "veteran" else 6

func _run(mode: String, diff: String, prof: String, cls: String, seed_value: int) -> void:
	game.ui.settings["mode"] = mode
	game.ui.settings["game_type"] = "single"
	game.ui.settings["difficulty"] = diff
	game.ui.settings["level"] = 1
	game.ui.settings["seed"] = seed_value
	game.ui.settings["location"] = "city"
	game.start_match()
	_dismiss()
	var world: World = game.world
	var p = game.players[0]
	p._auto_pad_scheme = null
	p._auto_touch_scheme = null
	p.scheme = Autopilot.new(world.rng, mode == "koth")
	var causes := {}
	world.kill.connect(func(victim, killer, source: String, _suicide: bool):
		if victim == p.tank:
			var who := "none"
			if killer != null:
				who = String(killer.enemy_type.get("id", "bot")) if not killer.enemy_type.is_empty() else "player"
			var key := "%s:%s" % [source, who]
			causes[key] = int(causes.get(key, 0)) + 1)
	var limit: int = int(LIMITS.get(mode, 10800))
	var ticks := 0
	var place := 0
	while ticks < limit and not world.finished_flag:
		world.step()
		ticks += 1
		if mode == "koth" and place == 0 and p.tank != null and not p.tank.alive:
			for t in world.tanks:
				if t.alive:
					place += 1
			place += 1
		if ticks % 30 == 0:
			game._update_floaters()
		var pending := false
		for pl in game.players:
			if pl.pending_level_ups > 0:
				pending = true
		if pending:
			game._process_perk_queue()
			_dismiss()
	var pt: Tank = p.tank
	var bots := 0
	var bot_k := 0
	var bot_d := 0
	var rank := 1
	for t in world.tanks:
		if t == pt:
			continue
		if t.is_bot:
			bots += 1
			bot_k += t.kills
			bot_d += t.deaths
			var tid := String(t.enemy_type.get("id", "bot")) if not t.enemy_type.is_empty() else "bot"
			var key := "%s|%s|%s" % [mode, diff, tid]
			if not type_stats.has(key):
				type_stats[key] = {"n": 0, "kills": 0, "deaths": 0, "dmg": 0.0}
			type_stats[key]["n"] += 1
			type_stats[key]["kills"] += t.kills
			type_stats[key]["deaths"] += t.deaths
			type_stats[key]["dmg"] += t.damage_dealt
		if t.kills > pt.kills:
			rank += 1
	var result := "timeout"
	if world.finished_flag:
		result = "win" if bool(world.result.get("victory", false)) else "lose"
	var extra := ""
	match mode:
		"defense":
			extra = "wave=%d base=%d" % [world.wave, int(world.base["hp"]) if world.base != null else 0]
		"ctf":
			extra = "score=%d:%d" % [world.team_score["player"], world.team_score["enemy"]]
		"koth":
			extra = "place=%d/%d" % [place if place > 0 else 1, world.tanks.size()]
	var cause_list := []
	for k in causes.keys():
		cause_list.append("%s=%d" % [k, causes[k]])
	extra += " died_by=" + ",".join(cause_list)
	print("BAL|%s|%s|%s|%s|%d|%s|%d|%d|%d|%.0f|%.2f|%.2f|%d/%d|%s" % [
		mode, diff, prof, cls, seed_value, result, ticks, pt.kills, pt.deaths, pt.damage_dealt,
		float(bot_k) / maxf(1.0, float(bots)), float(bot_d) / maxf(1.0, float(bots)), rank, bots + 1, extra])

func _dismiss() -> void:
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		var choices: Array = game.ui.last_perk_choices
		game._on_perk_chosen(game.perk_player, String(choices[0]) if not choices.is_empty() else "")
