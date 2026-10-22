extends Node

var failures := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _ready() -> void:
	for cls in TankSprites.BY_CHASSIS.values() + TankSprites.BY_CANNON.values() + TankSprites.BY_ENEMY.values():
		for kind in ["hull", "turret"]:
			var key := "%s_%s" % [cls, kind]
			_check(ResourceLoader.exists(TankSprites.DIR + key + ".png") and ResourceLoader.exists(TankSprites.DIR + key + "_paint.png"),
				"есть спрайт %s и маска краски" % key)
	for entry in TankClasses.LIST:
		var t := _tank(String(entry["chassis"]), "p1")
		t.class_id = String(entry["id"])
		_check(TankSprites.hull_class(t) == String(TankSprites.BY_CLASS.get(t.class_id, "")),
			"класс %s рисуется спрайтом %s" % [t.class_id, TankSprites.hull_class(t)])
	for id in TankSprites.BY_ENEMY:
		var t := _tank(String(EnemyTypes.get_type(id)["chassis"]), "enemy")
		t.enemy_type = EnemyTypes.get_type(id)
		_check(TankSprites.hull_class(t) == String(TankSprites.BY_ENEMY[id]), "враг %s рисуется спрайтом %s" % [id, TankSprites.hull_class(t)])
	for id in ["boss", "boss_rammer", "boss_chimera"]:
		var t := _tank(String(EnemyTypes.get_type(id)["chassis"]), "boss")
		t.enemy_type = EnemyTypes.get_type(id)
		_check(TankSprites.hull_class(t) == "", "босс %s остаётся в прежней отрисовке" % id)
	var gunner := _tank("standard", "p1")
	for cn in TankSprites.BY_CANNON:
		gunner.cannon_id = cn
		_check(TankSprites.turret_class(gunner, "universal") == "universal", "пушка %s сохраняет башню класса" % cn)
	gunner.cannon_id = "ice"
	_check(TankSprites.turret_class(gunner, "universal") == "universal", "ледяная пушка оставляет башню класса")
	print("=== ПРОВЕРКА СПРАЙТОВ ТАНКОВ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _tank(chassis: String, color: String) -> Tank:
	return Tank.new({"x": 0.0, "y": 0.0, "team": "player", "name": "", "color_key": color, "chassis": chassis,
		"max_hp": 100.0, "speed": 100.0, "fire_rate": 30})
