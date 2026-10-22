class_name Bestiary
extends RefCounted

# Descriptions are localized; numeric specifications come from live balance data.
const LIST: Array[Dictionary] = [
	{
		"id": "player_standard",
		"name": "Универсал · стандартная пушка",
		"category": "player",
		"category_name": "Орудия игрока",
		"is_player": true,
		"chassis": "standard",
		"color_key": "p1",
		"cannon_id": "standard",
		"role": "Прямой огонь",
		"desc": "Сбалансированное шасси со стандартным орудием. Подходит для знакомства с игрой и сборок без узкой специализации.",
		"abilities": [
			{
				"name": "Баллистическая стабилизация",
				"desc": "Стандартное орудие ускоряет снаряд на 15%."
			},
			{
				"name": "Гибкая сборка",
				"desc": "Орудие определяет тип выстрела; класс — прочность, подвижность и особенность танка."
			}
		],
		"tip": "Держите путь к отступлению и стреляйте между укрытиями. Класс и орудие можно менять отдельно в гараже."
	},
	{
		"id": "player_ice",
		"name": "Универсал · ледяная пушка",
		"category": "player",
		"category_name": "Орудия игрока",
		"is_player": true,
		"chassis": "standard",
		"color_key": "p5",
		"cannon_id": "ice",
		"role": "Контроль и таран",
		"desc": "Криогенный снаряд не наносит прямого урона. Он обездвиживает цель и подготавливает её к таранному удару.",
		"abilities": [
			{
				"name": "Заморозка",
				"desc": "Базовая длительность — 4 с. Движение и стрельба цели заблокированы; сопротивление контролю может сократить эффект."
			},
			{
				"name": "Хрупкая броня",
				"desc": "Таран уничтожает обычную замороженную цель. У боссов действуют ограничения урона."
			}
		],
		"tip": "Сначала заморозьте противника, затем сближайтесь для тарана. Следите за нагревом и оставляйте место для отхода."
	},
	{
		"id": "player_acid",
		"name": "Универсал · кислотная пушка",
		"category": "player",
		"category_name": "Орудия игрока",
		"is_player": true,
		"chassis": "standard",
		"color_key": "p12",
		"cannon_id": "acid",
		"role": "Урон со временем",
		"desc": "Снаряды наносят прямой урон и накладывают коррозию. Повторные попадания увеличивают число слоёв и обновляют эффект.",
		"abilities": [
			{
				"name": "Коррозия",
				"desc": "До 5 слоёв на 3 с. Новое попадание обновляет длительность; урон зависит от силы атаки."
			},
			{
				"name": "Частые выстрелы",
				"desc": "Базовый интервал выстрелов на 10% короче, чем у стандартной пушки; нагрев за выстрел ниже."
			}
		],
		"tip": "Попадайте сериями, чтобы накопить коррозию, затем уходите за укрытие, пока она продолжает наносить урон."
	},
	{
		"id": "player_fire",
		"name": "Универсал · огнемёт",
		"category": "player",
		"category_name": "Орудия игрока",
		"is_player": true,
		"chassis": "standard",
		"color_key": "p3",
		"cannon_id": "fire",
		"role": "Горение и опасная земля",
		"desc": "Сгустки пламени наносят ударный урон, поджигают цель и оставляют горящие пятна на земле.",
		"abilities": [
			{
				"name": "Горение",
				"desc": "До 3 уровней на 3 с. Горение наносит периодический урон и нагревает орудие жертвы."
			},
			{
				"name": "Огненные пятна",
				"desc": "Горящая земля поджигает проезжающую технику. Вода тушит горящий танк."
			}
		],
		"tip": "Перекрывайте проходы огнём. Повторные попадания усиливают горение; вода помогает противнику потушить пламя."
	},
	{
		"id": "player_shock",
		"name": "Универсал · Громовержец",
		"category": "player",
		"category_name": "Орудия игрока",
		"is_player": true,
		"chassis": "standard",
		"color_key": "p2",
		"cannon_id": "shock",
		"role": "Электрический контроль",
		"desc": "Быстрый электрический заряд наносит урон и на короткое время блокирует действия цели.",
		"abilities": [
			{
				"name": "Оглушение",
				"desc": "Базовая длительность — 1 с. Цель не может двигаться и стрелять."
			},
			{
				"name": "Защита от повторного контроля",
				"desc": "После попадания включается защита от повторного оглушения. Сопротивление контролю может сократить сам эффект."
			}
		],
		"tip": "Оглушайте цель перед атакой союзника. Не рассчитывайте на непрерывную цепь оглушений: у цели есть временная защита."
	},
	{
		"id": "grunt",
		"name": "Рядовой",
		"category": "enemy",
		"category_name": "Противники",
		"is_player": false,
		"chassis": "standard",
		"color_key": "enemy",
		"cannon_id": "standard",
		"role": "Линейный боец",
		"desc": "Преследует цель и ведёт прямой огонь. Опасен, когда несколько машин одновременно перекрывают пути отхода.",
		"abilities": [
			{
				"name": "Прямой огонь",
				"desc": "Обычные снаряды останавливаются препятствиями. Укрытия помогают разорвать линию огня."
			}
		],
		"tip": "Не стойте под перекрёстным огнём. Разделяйте группу укрытиями и уничтожайте машины по одной."
	},
	{
		"id": "scout",
		"name": "Разведчик",
		"category": "enemy",
		"category_name": "Противники",
		"is_player": false,
		"chassis": "light",
		"color_key": "scout",
		"cannon_id": "standard",
		"role": "Быстрый перехватчик",
		"desc": "Лёгкий быстрый противник. Стреляет чаще рядового, но отдельный снаряд наносит меньше урона.",
		"abilities": [
			{
				"name": "Подвижность",
				"desc": "Скорость выше базовой, прочность ниже. Частые попадания опасны, даже если отдельный выстрел слаб."
			}
		],
		"tip": "Прикрывайте фланги и стреляйте с упреждением. Не гонитесь за разведчиком через открытое пространство."
	},
	{
		"id": "heavy",
		"name": "Громила",
		"category": "enemy",
		"category_name": "Противники",
		"is_player": false,
		"chassis": "heavy",
		"color_key": "heavy",
		"cannon_id": "standard",
		"role": "Тяжёлый штурмовик",
		"desc": "Прочная медленная машина с мощными одиночными выстрелами и увеличенным интервалом между ними.",
		"abilities": [
			{
				"name": "Прочность и мощь",
				"desc": "Выдерживает больше попаданий, чем рядовой. За мощный выстрел платит подвижностью и скоростью перезарядки."
			}
		],
		"tip": "Уклонитесь от выстрела и атакуйте во время перезарядки. Держите дистанцию и избегайте тарана."
	},
	{
		"id": "sniper",
		"name": "Снайпер",
		"category": "enemy",
		"category_name": "Противники",
		"is_player": false,
		"chassis": "sniper",
		"color_key": "sniper",
		"cannon_id": "standard",
		"role": "Дальний огонь",
		"desc": "Держится вдали от цели. Его снаряды очень опасны, но пауза между выстрелами велика.",
		"abilities": [
			{
				"name": "Редкие мощные выстрелы",
				"desc": "Предпочитает дальнюю дистанцию. Долгая перезарядка создаёт окно для сближения."
			}
		],
		"tip": "Пересекайте линию огня рывком или через укрытие. Сближайтесь после его выстрела."
	},
	{
		"id": "mortar",
		"name": "Миномёт",
		"category": "enemy",
		"category_name": "Противники",
		"is_player": false,
		"chassis": "mortar",
		"color_key": "mortar",
		"cannon_id": "standard",
		"role": "Навесной огонь",
		"desc": "Запускает мины через стены. Взрыв накрывает площадь, поэтому обычное укрытие не гарантирует безопасность.",
		"abilities": [
			{
				"name": "Навесная траектория",
				"desc": "Мина перелетает стены и взрывается по площади. Время подлёта позволяет покинуть место падения."
			}
		],
		"tip": "Меняйте позицию после каждого залпа. Не прижимайтесь к союзникам и не оставайтесь за одной стеной."
	},
	{
		"id": "pyro",
		"name": "Огнемётчик",
		"category": "enemy",
		"category_name": "Противники",
		"is_player": false,
		"chassis": "heavy",
		"color_key": "pyro",
		"cannon_id": "fire",
		"role": "Огненный штурмовик",
		"desc": "Поджигает танки и землю на короткой дистанции. Повторные попадания усиливают горение и нагревают орудие цели.",
		"abilities": [
			{
				"name": "Горение",
				"desc": "До 3 уровней на 3 с. Горение наносит периодический урон и нагревает орудие жертвы."
			},
			{
				"name": "Огненные пятна",
				"desc": "Горящая земля поджигает проезжающую технику. Вода тушит горящий танк."
			}
		],
		"tip": "Держитесь вне короткой дистанции огня и объезжайте горящие пятна. Вода тушит пламя, но сама остаётся опасной."
	},
	{
		"id": "tesla",
		"name": "Громовержец",
		"category": "enemy",
		"category_name": "Противники",
		"is_player": false,
		"chassis": "standard",
		"color_key": "tesla",
		"cannon_id": "shock",
		"role": "Электрическая поддержка",
		"desc": "Стреляет быстрыми электрическими зарядами. Оглушение делает цель уязвимой для остальной группы.",
		"abilities": [
			{
				"name": "Оглушение",
				"desc": "Базовая длительность — 1 с. Цель не может двигаться и стрелять."
			},
			{
				"name": "Защита от повторного контроля",
				"desc": "После попадания включается защита от повторного оглушения. Сопротивление контролю может сократить сам эффект."
			}
		],
		"tip": "Прерывайте линию огня укрытиями и берегите рывок для заряда. Опаснее всего рядом с другими противниками."
	},
	{
		"id": "boss",
		"name": "Бронемонстр",
		"category": "boss",
		"category_name": "Боссы и клоны",
		"is_player": false,
		"chassis": "boss",
		"color_key": "boss",
		"cannon_id": "standard",
		"role": "Тяжёлый босс",
		"desc": "Ведёт огонь спаренным орудием и выпускает веерные залпы. При потере прочности переходит в более агрессивные фазы.",
		"abilities": [
			{
				"name": "Фазы боя",
				"desc": "При снижении прочности босс ускоряется и стреляет чаще. В последней фазе временно получает дополнительную защиту."
			},
			{
				"name": "Спаренное орудие",
				"desc": "Залп содержит два снаряда с пониженным уроном каждого. Значение в таблице указано за один снаряд."
			}
		],
		"tip": "Следите за подготовкой веерного залпа. Оставляйте пространство для манёвра, особенно ближе к концу боя."
	},
	{
		"id": "boss_rammer",
		"name": "Джаггернаут-Таран",
		"category": "boss",
		"category_name": "Боссы и клоны",
		"is_player": false,
		"chassis": "boss_rammer",
		"color_key": "boss_rammer",
		"cannon_id": "standard",
		"role": "Таранный босс",
		"desc": "Атакует разгонами, вращением и минами. Во время рывка и вращения получает на 35% меньше урона.",
		"abilities": [
			{
				"name": "Разгон и вращение",
				"desc": "Перед рывком предупреждает о направлении атаки. Вращение опасно вблизи и разбрасывает мины."
			},
			{
				"name": "Уязвимость после столкновения",
				"desc": "Столкновение со стеной временно оглушает босса и повышает получаемый им урон."
			}
		],
		"tip": "Уходите в сторону от линии разгона. Атакуйте после его столкновения со стеной и отойдите перед взрывом при гибели."
	},
	{
		"id": "boss_chimera",
		"name": "Фантом-Химера",
		"category": "boss",
		"category_name": "Боссы и клоны",
		"is_player": false,
		"chassis": "boss_chimera",
		"color_key": "boss_chimera",
		"cannon_id": "acid",
		"role": "Кислотный босс",
		"desc": "Выпускает непрерывную струю кислоты после подготовки. Использует маскировку, лужи и клонов, повторяющих её атаки.",
		"abilities": [
			{
				"name": "Струя и лужи",
				"desc": "Струя наносит непрерывный урон и накладывает коррозию. Лужи повреждают и замедляют танки."
			},
			{
				"name": "Маскировка и клоны",
				"desc": "Периодически скрывается и создаёт копии. Клоны повторяют фазы струйной атаки и исчезают при гибели оригинала."
			}
		],
		"tip": "Увидев подготовку струи, уходите в сторону или за прочную стену. Объезжайте лужи и ищите оригинал среди клонов."
	},
	{
		"id": "chimera_clone",
		"name": "Голографический клон",
		"category": "boss",
		"category_name": "Боссы и клоны",
		"is_player": false,
		"chassis": "boss_chimera",
		"color_key": "boss_chimera",
		"cannon_id": "acid",
		"role": "Копия Химеры",
		"desc": "Менее прочная копия Химеры. Повторяет подготовку и струйную атаку оригинала, но её прямой поток слабее.",
		"abilities": [
			{
				"name": "Синхронная атака",
				"desc": "Повторяет подготовку и направление потока оригинала. Поток также накладывает коррозию."
			},
			{
				"name": "Связь с оригиналом",
				"desc": "Имеет отдельный запас прочности. Исчезает сразу после уничтожения настоящей Химеры."
			}
		],
		"tip": "Клоны исчезают после гибели оригинала. Если можете безопасно атаковать настоящую Химеру, сосредоточьтесь на ней."
	}
]

static func all() -> Array[Dictionary]:
	return LIST

static func text(entry: Dictionary, field: String) -> String:
	if field in ["hp_val", "speed_val", "dmg_val", "reload_val"]:
		return stat_values(entry).get(field, "—")
	return I18n.dn(entry, field, "bestiary")

static func category_text(entry: Dictionary) -> String:
	return I18n.lookup("bestiary.cat.%s" % String(entry.get("category", "")),
		String(entry.get("category_name", "")))

static func ability_text(entry: Dictionary, index: int, field: String) -> String:
	var abilities: Array = entry.get("abilities", [])
	if index < 0 or index >= abilities.size():
		return ""
	var ru := String((abilities[index] as Dictionary).get(field, ""))
	return I18n.lookup("bestiary.%s.ab%d.%s" % [String(entry.get("id", "")), index, field], ru)

static func get_entry(id: String) -> Dictionary:
	for item in LIST:
		if String(item.get("id", "")) == id:
			return item
	return {}

static func is_player_tank(id: String) -> bool:
	var entry := get_entry(id)
	return bool(entry.get("is_player", false))

static func category_list(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in LIST:
		if String(item.get("category", "")) == category:
			out.append(item)
	return out

# Reference only: Medium, neutral mode, ramp 1, no upgrades/director/team scaling.
# Keep random bullet rolls as a range instead of implying a fixed damage value.
static func reference_stats(entry: Dictionary) -> Dictionary:
	var id := String(entry.get("id", ""))
	var diff: Dictionary = Cfg.DIFFICULTY["medium"]
	if bool(entry.get("is_player", false)):
		var cannon := Cannons.get_cannon(String(entry.get("cannon_id", "standard")))
		var scale := Cfg.PLAYER_DMG_MULT * float(cannon.get("dmg_scale", 1.0))
		var damage_min := Cfg.BULLET_DMG_MIN * scale
		var damage_max := Cfg.BULLET_DMG_MAX * scale
		var mode := String(cannon.get("mode", "standard"))
		if mode == "shock":
			damage_min = Cfg.SHOCK_DMG
			damage_max = damage_min
		elif mode == "fire":
			damage_min = Cfg.FIRE_IMPACT_DMG * Cfg.PLAYER_DMG_MULT
			damage_max = damage_min
		return {"hp": float(diff["player_hp"]), "speed": Cfg.PLAYER_SPEED,
			"damage_min": damage_min, "damage_max": damage_max,
			"reload": float(maxi(4, int(round(Cfg.PLAYER_FIRE_RATE * float(cannon.get("cooldown_mult", 1.0)))))) / Cfg.TICK_HZ,
			"kind": mode}
	var clone := id == "chimera_clone"
	var type := EnemyTypes.get_type("boss_chimera" if clone else id)
	if type.is_empty(): return {}
	var hp := float(type.get("base_hp", float(diff["enemy_hp"]) * float(type["hp_mult"])))
	var scale := float(type["dmg_scale"])
	var damage_min := Cfg.BULLET_DMG_MIN * scale
	var damage_max := Cfg.BULLET_DMG_MAX * scale
	var kind := String(type.get("shot", "standard"))
	if id == "boss":
		damage_min *= 0.6 # doubleShot in Tank.shoot(), per shell
		damage_max *= 0.6
	elif id == "tesla":
		damage_min = Cfg.TESLA_SHOCK_DMG
		damage_max = damage_min
	elif id == "boss_rammer": kind = "ram"
	elif id == "boss_chimera" or clone: kind = "stream"
	var speed := float(diff["enemy_speed"]) * float(type["speed_mult"])
	if clone:
		hp = Cfg.CHIMERA_CLONE_HP
		speed *= 1.05
	return {"hp": hp, "speed": speed, "damage_min": damage_min, "damage_max": damage_max,
		"reload": float(maxi(4, int(round(float(diff["enemy_fire_rate"]) * float(type["fire_rate_mult"])))))/Cfg.TICK_HZ,
		"kind": kind}

static func stat_values(entry: Dictionary) -> Dictionary:
	var s := reference_stats(entry)
	if s.is_empty(): return {}
	var kind := String(s.kind)
	var damage := _number(float(s.damage_min))
	if float(s.damage_min) != float(s.damage_max): damage += "–" + _number(float(s.damage_max))
	if kind == "freeze": damage = I18n.t("bestiary.damage.none", {}, "0 · контроль")
	elif kind == "ram": damage = I18n.t("bestiary.damage.ram", {}, "Таран и мины")
	elif kind == "stream": damage = I18n.t("bestiary.damage.stream", {}, "Кислотная струя")
	elif kind == "fire" and not bool(entry.get("is_player", false)):
		damage = I18n.t("bestiary.damage.burn", {}, "Горение")
	return {"hp_val": _number(float(s.hp)) + " HP", "dmg_val": damage,
		"speed_val": I18n.t("bestiary.unit.speed", {"n": _number(float(s.speed) * Cfg.TICK_HZ / Cfg.TILE)}, "{n} кл/с"),
		"reload_val": "—" if kind in ["ram", "stream"] else I18n.t("bestiary.unit.time", {"n": _number(float(s.reload), 2)}, "{n} с")}

static func _number(value: float, decimals: int = 1) -> String:
	var result := ("%." + str(decimals) + "f") % value
	while result.contains(".") and result.ends_with("0"): result = result.left(-1)
	if result.ends_with("."): result = result.left(-1)
	if I18n.lang in ["ru", "fr", "es"]: result = result.replace(".", ",")
	return result
