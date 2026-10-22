extends Node

var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)

func _ready() -> void:
	for cls in TankClasses.LIST:
		var tank := Tank.new({"x": 0, "y": 0, "team": "player", "name": "", "color_key": "p1", "max_hp": 100.0, "speed": 2.0, "fire_rate": 30, "class_id": cls.id, "chassis": cls.chassis})
		var hull := TankSprites.hull_class(tank)
		var source := TankSprites.part(hull, "turret")
		var original: Image = source.tex.get_image()
		if original.is_compressed(): original.decompress()
		var before := hash(original.get_data())
		var parts := {}
		for cannon in Cannons.LIST:
			tank.cannon_id = cannon.id
			var state := [tank.width, tank.height, tank.hit_r, tank.muzzle_len, tank.hp, tank.mods.duplicate(true)]
			var part := TankSprites.turret_part(tank, hull)
			check(part == TankSprites.turret_part(tank, hull), "%s/%s: cached assembly" % [cls.id, cannon.id])
			check(TankSprites.turret_class(tank, hull) == hull, "%s/%s: native class turret" % [cls.id, cannon.id])
			if cannon.id == "standard":
				check(part == source, cls.id + ": factory gun remains available")
			else:
				var image: Image = part.tex.get_image()
				var root: int = part.barrel_root
				var body_rect := Rect2i(0, root, image.get_width(), image.get_height() - root)
				check(image.get_region(body_rect).get_data() == original.get_region(body_rect).get_data(), "%s/%s: original turret body, hatch and mount preserved" % [cls.id, cannon.id])
				check(part.barrel_width == TankSprites.GUN_FIT[hull].z and part.barrel_tip == TankSprites.GUN_FIT[hull].y, "%s/%s: class proportions" % [cls.id, cannon.id])
				parts[hash(image.get_data())] = true
				var k := tank.height / float((TankSprites.part(hull, "hull").rect as Rect2i).size.y)
				check(is_equal_approx(-TankSprites.barrel_tip_y(tank, hull) * k, tank.muzzle_len), "%s/%s: visible muzzle reaches projectile origin" % [cls.id, cannon.id])
				var modules := TankSprites.weapon_modules(tank, hull)
				check(modules != null and modules == TankSprites.weapon_modules(tank, hull), "%s/%s: functional modules cached" % [cls.id, cannon.id])
				for skin in TankSkinArt.PALETTES:
					check(TankSkinArt.texture(part, part.cache_key, skin) != null, "%s/%s/%s: skin fits weapon assembly" % [cls.id, cannon.id, skin])
			check(state == [tank.width, tank.height, tank.hit_r, tank.muzzle_len, tank.hp, tank.mods], "%s/%s: combat geometry and stats unchanged" % [cls.id, cannon.id])
		check(parts.size() == 4, cls.id + ": all four elemental guns are distinct")
		var after: Image = source.tex.get_image()
		if after.is_compressed(): after.decompress()
		check(hash(after.get_data()) == before, cls.id + ": source sprite remains untouched")
	check(TankSprites.GUN_FIT.scout.z < TankSprites.GUN_FIT.bruiser.z, "scout bore is narrower than heavy bore")
	check(TankSprites.GUN_FIT.sniper.x - TankSprites.GUN_FIT.sniper.y > TankSprites.GUN_FIT.mortar.x - TankSprites.GUN_FIT.mortar.y, "sniper barrel is longer than mortar tube")
	var bot := Tank.new({"x": 0, "y": 0, "team": "enemy", "name": "", "max_hp": 100.0, "speed": 2.0, "fire_rate": 30})
	bot.enemy_type = EnemyTypes.get_type("tesla")
	bot.cannon_id = "shock"
	check(TankSprites.turret_part(bot, "lightning") == TankSprites.part("lightning", "turret"), "enemy Tesla retains authored turret")
	print("=== CLASS GUNS: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
