extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
func _ready() -> void:
	for cls in TankClasses.LIST:
		var tank := Tank.new({"x": 0, "y": 0, "team": "player", "name": "", "color_key": "p1", "class_id": cls.id, "chassis": cls.chassis, "max_hp": 100, "speed": 0, "fire_rate": 30})
		var hull := TankSprites.hull_class(tank)
		for cannon in ["ice", "acid", "fire", "shock"]:
			tank.cannon_id = cannon
			var part := TankSprites.turret_part(tank, hull)
			if hull == "mortar":
				check(part == TankSprites.part(hull, "turret"), "mortar keeps native tube without colored front rectangle")
				check(not TankSprites.fitted_barrel(tank, hull), "mortar does not stretch elemental attachment")
				check(TankSprites.weapon_modules(tank, hull) != null, "mortar retains side modules")
				continue
			var tex: Image = part.tex.get_image()
			var paint: Image = part.paint.get_image()
			var tip := int(part.barrel_tip)
			var width := int(part.barrel_width)
			var left := 32 - width / 2
			var complete_cap := true
			for x in range(left - 1, left + width + 1):
				if tex.get_pixel(x, tip).a < 0.99 or paint.get_pixel(x, tip).a > 0.0: complete_cap = false
			check(complete_cap, "%s/%s: full-width muzzle cap with no cosmetic pipe protruding" % [cls.id, cannon])
			for y in tip:
				for x in range(22, 43): check(tex.get_pixel(x, y).a == 0.0, "nothing protrudes beyond muzzle cap")
			for skin in TankSkinArt.PALETTES:
				var painted: Image = TankSkinArt.texture(part, part.cache_key, skin).get_image()
				var hides_cap := false
				for x in range(left - 1, left + width + 1):
					if painted.get_pixel(x, tip).a > 0.0: hides_cap = true
				check(not hides_cap, "%s/%s/%s: skin does not replace functional muzzle" % [cls.id, cannon, skin])
	print("WEAPON MUZZLES: 6 classes x 4 cannons x 8 skins, failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
