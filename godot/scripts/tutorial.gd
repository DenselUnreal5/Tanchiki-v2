class_name Tutorial
extends RefCounted

const TOTAL := 11
const DONE_PAUSE := 120
const FAIL_PAUSE := 90
const CHECKPOINT_R := 44.0
const DODGES_NEEDED := 3
const DODGE_GAP := 15
const BARREL_GRACE := 45
const MOVE_EPS := 0.3

const ST_PLAY := "play"
const ST_DONE := "done"
const ST_FAIL := "fail"
const ST_OVER := "over"

const TITLES := {
	1: "ДВИЖЕНИЕ",
	2: "СТРЕЛЬБА",
	3: "УКЛОНЕНИЕ",
	4: "ЩИТЫ",
	5: "ВЗРЫВНЫЕ БОЧКИ",
	6: "ВОДА И ЗЫБУЧИЕ ПЕСКИ",
	7: "МИНЫ",
	8: "ЛЕДЯНОЙ ТАНК",
	9: "КИСЛОТНЫЙ ТАНК",
	10: "БОЙ С БОТОМ",
	11: "БОЙ С БОССОМ",
}

const DESCS := {
	1: "Проведите танк через лабиринт до контрольной точки, используя [W] [A] [S] [D]",
	2: "Наведите башню мышью и уничтожьте танки-манекены [ЛКМ / Пробел]",
	3: "Турель стреляет по вам. Когда снаряд подлетает — рывок [Shift]: во время рывка танк неуязвим",
	4: "Заедьте в зону генератора и держитесь в ней, пока он не разрядится — генератор даст щит",
	5: "Танк спрятан за стеной, пули его не достанут. Взорвите обе бочки рядом с ним [ЛКМ] и держитесь подальше от взрыва",
	6: "Вода и зыбучие пески замедляют и ранят танк. Пересеките их и доберитесь до контрольной точки — рывок [Shift] помогает проскочить",
	7: "Подберите перк «Миноукладчик» и поставьте мину [E / ПКМ]",
	8: "Ледяной снаряд [ЛКМ] замораживает цель, но не ранит. Заморозьте манекен и разбейте его тараном",
	9: "Кислотные снаряды [ЛКМ] отравляют цель. Уничтожьте манекен ядом — таран не засчитывается",
	10: "Победите вражеский танк. Аптечки по краям восстановят броню",
	11: "Финал — бой с боссом. Победа необязательна: обучение завершится в любом случае",
}

const KEYS := {
	1: "[W] [A] [S] [D]",
	2: "[ЛКМ] / [Пробел]",
	3: "[Shift]",
	4: "Зона генератора",
	5: "[ЛКМ]",
	6: "[W] [A] [S] [D]",
	7: "[E] / [ПКМ]",
	8: "[ЛКМ] + таран",
	9: "[ЛКМ]",
	10: "БОЙ",
	11: "БОЙ",
}

var world
var stage := 0
var state := ST_PLAY
var pause_ticks := 0
var fail_reason := ""

var checkpoint := Vector2.INF
var targets: Array = []
var enemy = null
var barrels: Array = []
var generator = null
var perk_drop = null
var keys_used := {}
var dodges := 0
var last_dodge_tick := -100000
var was_frozen := false
var kill_sources := {}
var barrels_gone_ticks := 0

func _init(world_) -> void:
	world = world_

func start() -> void:
	begin_stage(1)

func player_tank():
	if world.players.is_empty():
		return null
	return world.players[0].tank

func begin_stage(n: int) -> void:
	stage = n
	state = ST_PLAY
	pause_ticks = 0
	fail_reason = ""
	checkpoint = Vector2.INF
	targets = []
	enemy = null
	barrels = []
	generator = null
	perk_drop = null
	keys_used = {"W": false, "A": false, "S": false, "D": false}
	dodges = 0
	last_dodge_tick = -100000
	was_frozen = false
	kill_sources = {}
	barrels_gone_ticks = 0
	_clear_arena()
	_apply_layout()
	_reset_player()
	_spawn_objects()
	world.feed.emit("ЗАДАНИЕ %d/%d: %s — %s" % [stage, TOTAL, TITLES[stage], DESCS[stage]], Color("#ffd700"))

func _clear_arena() -> void:
	var keep := []
	for t in world.tanks:
		if t.owner != null:
			keep.append(t)
	world.tanks = keep
	world.bullets.clear()
	world.mines.clear()
	world.barrels.clear()
	world.power_generators.clear()
	world.perk_drops.clear()
	world.pickups.clear()
	world.weapon_pickups.clear()
	world.acid_pools.clear()
	world.wrecks.clear()
	world.airstrikes.clear()
	world.rammer_meltdowns.clear()
	world.boss_alive = false

func _apply_layout() -> void:
	var rows: Array = TutorialLayouts.layout(stage)
	var map: GameMap = world.map
	map.fill(Cfg.T_EMPTY)
	for r in mini(rows.size(), map.rows):
		var line: String = rows[r]
		for c in mini(line.length(), map.cols):
			var tile := TutorialLayouts.tile_for(line[c])
			if tile != Cfg.T_EMPTY:
				map.set_tile(r, c, tile)

func _reset_player() -> void:
	var player = world.players[0]
	var tank = player.tank
	if tank == null:
		return
	var spot: Vector2 = TutorialLayouts.markers(stage, "P")[0]
	tank.respawn(spot.x, spot.y)
	var cannon := "standard"
	var chassis := "standard"
	var color := "p1"
	if stage == 8:
		cannon = "ice"
		chassis = "light"
		color = "p5"
	elif stage == 9:
		cannon = "acid"
		chassis = "heavy"
		color = "p12"
	player.perk_ids.clear()
	player.equipped_cannon = cannon
	player.color_key = color
	tank.cannon_id = cannon
	tank.set_chassis(chassis)
	tank.color_key = color
	tank.ability_id = ""
	tank.mine_cooldown = 0
	tank.recompute()
	tank.hp = tank.max_hp
	tank.angle = -PI * 0.5
	tank.body_angle = -PI * 0.5
	tank.turret_angle = -PI * 0.5
	player.update_camera()

func _spawn_objects() -> void:
	var xs := TutorialLayouts.markers(stage, "X")
	if not xs.is_empty():
		checkpoint = xs[0]
	for pos in TutorialLayouts.markers(stage, "H"):
		world.pickups.append(Ent.Pickup.new(pos.x, pos.y, "health", world.rng))
	for pos in TutorialLayouts.markers(stage, "O"):
		var b := Ent.ExplosiveBarrel.new(pos.x, pos.y)
		world.barrels.append(b)
		barrels.append(b)
	for pos in TutorialLayouts.markers(stage, "G"):
		generator = Ent.PowerGenerator.new(pos.x, pos.y)
		world.power_generators.append(generator)
	for pos in TutorialLayouts.markers(stage, "M"):
		perk_drop = Ent.PerkPickup.new(pos.x, pos.y, "mines", world.rng)
		perk_drop.life = 1 << 30
		world.perk_drops.append(perk_drop)
	for pos in TutorialLayouts.markers(stage, "T"):
		match stage:
			5:
				targets.append(_spawn_dummy(pos, "Танк в укрытии", 50.0, "standard", "enemy"))
			8:
				targets.append(_spawn_dummy(pos, "Манекен", 60.0, "light", "target"))
			9:
				targets.append(_spawn_dummy(pos, "Тяжёлый манекен", 90.0, "heavy", "target"))
			_:
				targets.append(_spawn_dummy(pos, "Манекен", 40.0, "standard", "target"))
	for pos in TutorialLayouts.markers(stage, "E"):
		if stage == 3:
			enemy = _spawn_turret(pos)
		else:
			enemy = _spawn_enemy("grunt", pos)
	for pos in TutorialLayouts.markers(stage, "K"):
		enemy = _spawn_enemy("boss", pos)

func _spawn_dummy(pos: Vector2, label: String, hp: float, chassis: String, color: String) -> Tank:
	var t := Tank.new({
		"x": pos.x, "y": pos.y, "team": "target", "name": label, "owner": null,
		"max_hp": hp, "speed": 0.0, "fire_rate": 99999,
		"color_key": color, "chassis": chassis, "dmg_scale": 0.0,
	})
	t.net_id = Net.next_tank_id()
	t.spawn_protect = 0
	t.angle = PI * 0.5
	t.body_angle = PI * 0.5
	t.turret_angle = PI * 0.5
	world.tanks.append(t)
	world.particles.burst(pos.x, pos.y, [Color("#eab308"), Color.WHITE], 10, 2, 4, 10, 20, world.rng)
	return t

func _spawn_turret(pos: Vector2) -> Tank:
	var t := Tank.new({
		"x": pos.x, "y": pos.y, "team": "enemy", "name": "Учебная турель", "owner": null,
		"max_hp": 99999.0, "speed": 0.0, "fire_rate": 100,
		"color_key": "enemy", "chassis": "heavy", "dmg_scale": 0.4,
	})
	t.net_id = Net.next_tank_id()
	t.spawn_protect = 0
	t.brain = BotBrain.new({
		"accuracy": 0.9, "react_time": 20, "role": "defender",
		"fire_range": 560.0, "keep_min": 0.0, "keep_max": 9999.0,
		"lobbed": false, "rng": world.rng,
	})
	world.tanks.append(t)
	return t

func _spawn_enemy(type_id: String, pos: Vector2) -> Tank:
	var t: Tank = world._spawn_bot("enemy", "enemy", type_id)
	t.x = pos.x
	t.y = pos.y
	t.spawn_x = pos.x
	t.spawn_y = pos.y
	t.angle = PI * 0.5
	t.body_angle = PI * 0.5
	t.turret_angle = PI * 0.5
	return t

func update() -> void:
	if state == ST_OVER or world.finished_flag:
		return
	if state == ST_DONE or state == ST_FAIL:
		pause_ticks -= 1
		if pause_ticks <= 0:
			begin_stage(stage + 1 if state == ST_DONE else stage)
		return
	var tank = player_tank()
	if tank == null:
		return
	if not tank.alive:
		if stage == TOTAL:
			_finish_course(false)
		else:
			_fail("Танк уничтожен")
		return
	_track(tank)
	match _verdict(tank):
		1:
			if stage == TOTAL:
				_finish_course(true)
			else:
				_succeed(tank)
		-1:
			_fail(fail_reason)

func _track(tank) -> void:
	if tank.vy < -MOVE_EPS:
		keys_used["W"] = true
	if tank.vy > MOVE_EPS:
		keys_used["S"] = true
	if tank.vx < -MOVE_EPS:
		keys_used["A"] = true
	if tank.vx > MOVE_EPS:
		keys_used["D"] = true
	if stage == 8 and not targets.is_empty() and targets[0].alive and targets[0].freeze_ticks > 0:
		was_frozen = true

func _all_keys_used() -> bool:
	for k in keys_used:
		if not bool(keys_used[k]):
			return false
	return true

func _at_checkpoint(tank) -> bool:
	return checkpoint != Vector2.INF and Vector2(tank.x, tank.y).distance_to(checkpoint) < CHECKPOINT_R

func _alive_count(list: Array) -> int:
	var n := 0
	for e in list:
		if e != null and e.alive:
			n += 1
	return n

func _verdict(tank) -> int:
	match stage:
		1:
			return 1 if _at_checkpoint(tank) and _all_keys_used() else 0
		2:
			return 1 if _alive_count(targets) == 0 else 0
		3:
			return 1 if dodges >= DODGES_NEEDED else 0
		4:
			return 1 if generator != null and generator.captured_team == tank.team else 0
		5:
			if _alive_count(targets) == 0:
				return 1
			if _alive_count(barrels) == 0:
				barrels_gone_ticks += 1
				if barrels_gone_ticks > BARREL_GRACE:
					fail_reason = "Бочки взорваны, а танк уцелел"
					return -1
			return 0
		6:
			return 1 if _at_checkpoint(tank) else 0
		7:
			return 1 if tank.flags.has("mines") and _player_mine_placed(tank) else 0
		8:
			if _alive_count(targets) > 0:
				return 0
			if was_frozen:
				return 1
			fail_reason = "Манекен уничтожен без заморозки"
			return -1
		9:
			if _alive_count(targets) > 0:
				return 0
			if String(kill_sources.get(targets[0], "")) == "acid":
				return 1
			fail_reason = "Манекен уничтожен не ядом"
			return -1
		10, 11:
			return 1 if enemy != null and not enemy.alive else 0
	return 0

func _player_mine_placed(tank) -> bool:
	for m in world.mines:
		if m.owner == tank:
			return true
	return false

func _succeed(tank) -> void:
	state = ST_DONE
	pause_ticks = DONE_PAUSE
	_disarm_enemies()
	Sfx.play("pickup")
	world.spawn_shockwave(tank.x, tank.y, 60.0, "dash", Color("#86efac"), 16)
	world.particles.burst(tank.x, tank.y, [Color("#86efac"), Color.WHITE], 20, 2, 5, 14, 28, world.rng)
	world.feed.emit("✔ Задание %d выполнено!" % stage, Color("#86efac"))

func _fail(reason: String) -> void:
	state = ST_FAIL
	fail_reason = reason
	pause_ticks = FAIL_PAUSE
	_disarm_enemies()
	world.feed.emit("✖ %s — задание начнётся заново" % reason, Color("#f87171"))

func _disarm_enemies() -> void:
	for t in world.tanks:
		if t.owner == null:
			t.brain = null

func _finish_course(boss_defeated: bool) -> void:
	state = ST_OVER
	Prof.bump_stat("tutorialCompleted", 1)
	var player = world.players[0]
	var reason := "Курс молодого бойца пройден! Босс повержен." if boss_defeated \
		else "Курс молодого бойца пройден! Босс оказался сильнее, но обучение завершено."
	world.feed.emit("🏆 " + reason, Color("#ffd700"))
	world._finish(player.name, 0, "player", reason)

func on_damage_evaded(target, source: String) -> void:
	if state != ST_PLAY or stage != 3 or target == null or target.owner == null:
		return
	if source != "bullet" or target.dash_invuln_ticks <= 0:
		return
	if world.tick - last_dodge_tick <= DODGE_GAP:
		return
	last_dodge_tick = world.tick
	dodges += 1
	Sfx.play("dash", target.x, target.y)
	world.damage_number.emit(target.x, target.y - 30, "УКЛОНЕНИЕ %d/%d" % [mini(dodges, DODGES_NEEDED), DODGES_NEEDED], Color("#38bdf8"))

func on_tank_killed(victim, source: String) -> void:
	kill_sources[victim] = source

func task_info() -> Dictionary:
	var info := {
		"stage": stage, "total": TOTAL,
		"title": "ЗАДАНИЕ %d/%d: %s" % [stage, TOTAL, TITLES.get(stage, "")],
		"desc": String(DESCS.get(stage, "")),
		"keys": String(KEYS.get(stage, "")),
		"progress_text": "", "progress": 0.0, "done": false,
	}
	match state:
		ST_DONE:
			info["title"] = "✔ ЗАДАНИЕ %d ВЫПОЛНЕНО" % stage
			info["progress_text"] = "Следующее задание через %d…" % _seconds_left()
			info["progress"] = 1.0
			return info
		ST_FAIL:
			info["title"] = "✖ ЗАДАНИЕ %d НЕ ВЫПОЛНЕНО" % stage
			info["desc"] = fail_reason
			info["progress_text"] = "Перезапуск через %d…" % _seconds_left()
			return info
		ST_OVER:
			info["title"] = "ОБУЧЕНИЕ ЗАВЕРШЕНО"
			info["desc"] = "Курс молодого бойца пройден!"
			info["progress"] = 1.0
			info["done"] = true
			return info
	var tank = player_tank()
	match stage:
		1:
			var parts := []
			for k in ["W", "A", "S", "D"]:
				parts.append("%s %s" % [k, "✔" if bool(keys_used[k]) else "—"])
			info["progress_text"] = "   ".join(parts) + "   ·   до точки: %d м" % _meters_to_checkpoint(tank)
		2:
			info["progress_text"] = "Уничтожено манекенов: %d / %d" % [targets.size() - _alive_count(targets), targets.size()]
		3:
			info["progress_text"] = "Уклонений: %d / %d" % [mini(dodges, DODGES_NEEDED), DODGES_NEEDED]
		4:
			var charge := 0
			if generator != null:
				charge = 100 if generator.captured_team != "" else int(generator.capture_progress * 100.0)
			info["progress_text"] = "Заряд генератора: %d%%" % charge
		5:
			info["progress_text"] = "Бочек взорвано: %d / %d   ·   танк: %s" % [
				barrels.size() - _alive_count(barrels), barrels.size(), _hp_text(targets[0] if not targets.is_empty() else null)]
		6:
			info["progress_text"] = "До точки: %d м" % _meters_to_checkpoint(tank)
		7:
			var has_perk: bool = tank != null and tank.flags.has("mines")
			info["progress_text"] = "Перк: %s   ·   Мина: %s" % [
				"✔" if has_perk else "—", "✔" if tank != null and _player_mine_placed(tank) else "—"]
		8:
			info["progress_text"] = "Заморожен: %s   ·   манекен: %s" % [
				"✔" if was_frozen else "—", _hp_text(targets[0] if not targets.is_empty() else null)]
		9:
			var dummy = targets[0] if not targets.is_empty() else null
			var stacks: int = dummy.acid_stacks if dummy != null and dummy.alive else 0
			info["progress_text"] = "Слоёв яда: %d / %d   ·   манекен: %s" % [stacks, Cfg.ACID_STACK_MAX, _hp_text(dummy)]
		10:
			info["progress_text"] = "Противник: %s" % _hp_text(enemy)
		11:
			info["progress_text"] = "Босс: %s" % _hp_text(enemy)
	return info

func _seconds_left() -> int:
	return maxi(1, int(ceil(float(pause_ticks) / 60.0)))

func _meters_to_checkpoint(tank) -> int:
	if tank == null or checkpoint == Vector2.INF:
		return 0
	return int(Vector2(tank.x, tank.y).distance_to(checkpoint) / float(Cfg.TILE))

func _hp_text(t) -> String:
	if t == null or not t.alive:
		return "уничтожен"
	return "%d / %d HP" % [int(ceil(t.hp)), int(t.max_hp)]

func highlights() -> Array:
	var out := []
	if state != ST_PLAY:
		return out
	match stage:
		1, 6:
			if checkpoint != Vector2.INF:
				out.append({"pos": checkpoint, "label": "КОНТРОЛЬНАЯ ТОЧКА", "color": Color("#38bdf8"), "point": true})
		2:
			_add_alive(out, targets, "МАНЕКЕН", Color("#fde047"))
		3:
			_add_alive(out, [enemy], "ТУРЕЛЬ", Color("#f87171"))
		4:
			if generator != null:
				out.append({"pos": Vector2(generator.x, generator.y), "label": "ГЕНЕРАТОР ЩИТА", "color": Color("#34d399"), "point": true})
		5:
			_add_alive(out, barrels, "ВЗРЫВНАЯ БОЧКА", Color("#f97316"))
			_add_alive(out, targets, "ЦЕЛЬ", Color("#f87171"))
		7:
			if perk_drop != null and perk_drop.active:
				out.append({"pos": Vector2(perk_drop.x, perk_drop.y), "label": "ПЕРК «МИНОУКЛАДЧИК»", "color": Color("#ff88ff"), "point": false})
		8:
			_add_alive(out, targets, "ЦЕЛЬ (ЗАМОРОЗКА)", Color("#7fdfff"))
		9:
			_add_alive(out, targets, "ЦЕЛЬ (ЯД)", Color("#84cc16"))
		10:
			_add_alive(out, [enemy], "ПРОТИВНИК", Color("#f43f5e"))
		11:
			_add_alive(out, [enemy], "БОСС", Color("#e74c3c"))
	return out

func _add_alive(out: Array, list: Array, label: String, color: Color) -> void:
	for e in list:
		if e != null and e.alive:
			out.append({"pos": Vector2(e.x, e.y), "label": label, "color": color, "point": false})
