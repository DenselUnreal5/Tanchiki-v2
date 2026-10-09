class_name KillCam
extends RefCounted

var frames: Array = []
var meta := {}
var _since_record := 0

func record(world) -> void:
	_since_record += 1
	if _since_record < Cfg.KILLCAM_SAMPLE_EVERY:
		return
	_since_record = 0
	_push_frame(world)

func _push_frame(world) -> void:
	var tanks := PackedFloat32Array()
	for tank in world.tanks:
		if not tank.alive:
			continue
		_remember(tank)
		tanks.append(float(tank.id))
		tanks.append(tank.x)
		tanks.append(tank.y)
		tanks.append(tank.angle)
		tanks.append(tank.turret_angle)
		tanks.append(tank.hp / maxf(1.0, tank.max_hp))
	var bullets := PackedFloat32Array()
	for bullet in world.bullets:
		if not bullet.alive:
			continue
		bullets.append(bullet.x)
		bullets.append(bullet.y)
		bullets.append(1.0 if bullet.from_player else 0.0)
	frames.append({"tick": world.tick, "tanks": tanks, "bullets": bullets})
	while frames.size() > Cfg.KILLCAM_FRAMES:
		frames.pop_front()

func _remember(tank) -> void:
	if meta.has(tank.id):
		return
	meta[tank.id] = {
		"name": tank.name, "color_key": tank.color_key,
		"team": tank.team, "boss": tank.is_boss,
	}

func capture(world, victim, killer, source: String) -> Dictionary:
	_remember(victim)
	if killer != null:
		_remember(killer)
	_push_frame(world)
	_since_record = 0
	var killer_id: int = killer.id if killer != null and killer != victim else -1
	return {
		"frames": frames.duplicate(),
		"meta": meta.duplicate(true),
		"victim": victim.id,
		"killer": killer_id,
		"source": source,
		"victim_name": victim.name,
		"killer_name": killer.name if killer_id >= 0 else "",
		"death_pos": Vector2(victim.x, victim.y),
		"sample_every": Cfg.KILLCAM_SAMPLE_EVERY,
	}

static func tank_at(frame: Dictionary, tank_id: int) -> Dictionary:
	var arr: PackedFloat32Array = frame["tanks"]
	var i := 0
	while i + Cfg.KILLCAM_TANK_STRIDE <= arr.size():
		if int(arr[i]) == tank_id:
			return {"x": arr[i + 1], "y": arr[i + 2], "angle": arr[i + 3],
				"turret": arr[i + 4], "hp": arr[i + 5]}
		i += Cfg.KILLCAM_TANK_STRIDE
	return {}

static func source_label(source: String) -> String:
	match source:
		"bullet":
			return I18n.t("killcam.src.bullet", {}, "выстрел")
		"ram":
			return I18n.t("killcam.src.ram", {}, "таран")
		"mine":
			return I18n.t("killcam.src.mine", {}, "мина")
		"acid", "acid_stream":
			return I18n.t("killcam.src.acid", {}, "кислота")
		"lightning":
			return I18n.t("killcam.src.lightning", {}, "молния")
		"blast", "barrel_blast", "airstrike", "kamikaze":
			return I18n.t("killcam.src.blast", {}, "взрыв")
		"water":
			return I18n.t("killcam.src.water", {}, "вода")
	return I18n.t("killcam.src.other", {}, "урон")
