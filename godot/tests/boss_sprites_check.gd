extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)
func _ready() -> void:
	for id in ["boss", "boss_rammer", "boss_chimera"]:
		var type := EnemyTypes.get_type(id)
		var tank := Tank.new({"x": 0, "y": 0, "name": "", "team": "enemy", "chassis": type.chassis, "max_hp": 100, "speed": 1.0, "fire_rate": 30})
		var before := [tank.width, tank.height, tank.col_w, tank.col_h, tank.hit_r, tank.muzzle_len, tank.hp]
		check(BossSprites.has(tank), id + ": dedicated texture renderer selected")
		var data := BossSprites.model(id)
		check(data == BossSprites.model(id), id + ": atlas metadata cached")
		check((data.hull_source as Texture2D).resource_path.contains("/" + id + "/hull.tres"), id + ": original authored hull atlas")
		check((data.turret_source as Texture2D).resource_path.contains("/" + id + "/turret.tres"), id + ": original authored turret atlas")
		check(data.hull.get_width() == 887 and data.hull.get_height() == 887 and data.turret.get_width() == 887, id + ": isolated atlas halves, no detached duplicate")
		check(data.hull.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, id + ": sharp sampling in every location")
		check(is_equal_approx(BossSprites.scale_for(tank, data) * float(data.hull_rect.size.y), tank.height), id + ": hull fits existing height")
		check(before == [tank.width, tank.height, tank.col_w, tank.col_h, tank.hit_r, tank.muzzle_len, tank.hp], id + ": combat geometry and health unchanged")
		if id == "boss_rammer": check(data.barrel_root == 0.0, "rammer has fixed module and no fake gun")
	var clone := Tank.new({"x": 0, "y": 0, "name": "", "team": "enemy", "chassis": "boss_chimera", "max_hp": 220, "speed": 1.0, "fire_rate": 30})
	clone.is_chimera_clone = true
	check(BossSprites.has(clone), "holographic clone uses Chimera atlas")
	print("=== BOSS SPRITES: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
