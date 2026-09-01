# ============================================================================
# perk_dps.gd — замер огневых перков без участия «мозга».
#
# Боевой замер (perk_bench) гоняет партию, где за игрока играет бот. Для
# перков, меняющих реакцию мира на игрока, это честно. Для огневых — нет:
# у мозга зашиты дистанции удержания и дальность огня, он настроен на базовый
# танк и не подстраивается под перк. Любой перк, меняющий темп стрельбы или
# скорость снаряда, уводит танк от того, под что мозг настроен, и получает
# штраф, которого в руках человека не будет.
#
# Здесь мозга нет вовсе: танк стоит и жмёт на спуск каждый тик, а активную
# способность нажимает, как только она откатилась. Замеряется потолок —
# устойчивый темп огня и урон в секунду с учётом перегрева ствола.
#
# Запуск:
#   godot --headless --path godot tests/perk_dps.tscn
# ============================================================================
extends Node

const SECONDS := 60

## Перки, влияющие на ствол: нагрев, темп, снаряд.
const IDS := [
	"", "heat_sink", "thermal", "quick_vent", "light_shell", "heavy_shell",
	"coolant", "overclock", "rapid_fire", "quick_reload",
]

var game: Node
var rows := []

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	for id in IDS:
		rows.append(await _run(id))
	_report()
	get_tree().quit(0)

func _run(perk_id: String) -> Dictionary:
	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["difficulty"] = "medium"
	game.ui.settings["level"] = 1
	Prof.global_level = 5
	game.start_match({"rng_seed": 4242})
	var guard := 0
	while game.state == "perk" and guard < 40:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

	var world: World = game.world
	var player = game.players[0]
	# Массив перков переиспользуется: танк держит на него ссылку с рождения.
	player.perk_ids.clear()
	if perk_id != "":
		player.perk_ids.append(perk_id)
	var tank: Tank = player.tank
	tank.perk_ids = player.perk_ids
	tank.recompute()

	var ticks := SECONDS * 60
	for i in ticks:
		# Танк неуязвим и неподвижен: считается потолок темпа, а не выживание.
		tank.hp = tank.max_hp
		if tank.ability_id != "" and tank.ability_cd <= 0:
			tank.use_ability(world)
		tank.shoot(world)
		world.step()

	var rate := float(tank.shots_fired) / float(SECONDS)
	# Средний снаряд: урон пули берётся из диапазона равномерно, множители
	# перка и общий множитель игрока идут сверху.
	var avg_hit := (Cfg.BULLET_DMG_MIN + Cfg.BULLET_DMG_MAX) * 0.5 \
		* Cfg.PLAYER_DMG_MULT * float(tank.mods["dmgMult"])
	return {
		"id": perk_id, "rate": rate, "overheats": tank.overheats,
		"dps": rate * avg_hit, "bullet_speed": float(tank.mods["bulletSpeedMult"]),
	}

func _report() -> void:
	var base: Dictionary = rows[0]
	print("")
	print("=== ОГНЕВЫЕ ПЕРКИ: непрерывный огонь %d с ===" % SECONDS)
	print("предел без перегрева: %.2f выстр/с" % (60.0 / float(Cfg.PLAYER_FIRE_RATE)))
	print("контроль: %.2f выстр/с, перегревов %d, урона %.0f/с"
		% [base["rate"], base["overheats"], base["dps"]])
	print("")
	print("%-16s %9s %9s %9s %9s %9s" % [
		"перк", "выстр/с", "перегр", "урон/с", "Dурон/с", "скор.снар"])
	for r in rows:
		if r["id"] == "":
			continue
		print("%-16s %9.2f %9d %9.0f %+9.0f %9.2f" % [
			r["id"], r["rate"], r["overheats"], r["dps"],
			r["dps"] - float(base["dps"]), r["bullet_speed"]])
	print("")
	print("Замер детерминирован: одна карта, одна затравка, мозг не участвует.")
