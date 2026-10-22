extends Node

var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", label)

func _ready() -> void:
	var saved := [Prof.equipped_class, Prof.equipped_cannon]
	var menu := MenuScene.new()
	add_child(menu)
	menu.set_process(false)
	for cls in TankClasses.LIST:
		for cannon in Cannons.LIST:
			Prof.equipped_class = cls.id
			Prof.equipped_cannon = cannon.id
			menu._update_tank()
			check(menu._display_tank.class_id == cls.id and menu._display_tank.cannon_id == cannon.id and menu._display_tank.chassis_id == cls.chassis, "menu follows %s / %s without reopening" % [cls.id, cannon.id])
	Prof.equipped_class = saved[0]
	Prof.equipped_cannon = saved[1]
	menu._update_tank()
	menu.queue_free()
	for cls in ["universal", "private", "scout", "bruiser", "sniper", "mortar", "acid", "flamethrower", "lightning"]:
		for kind in ["hull", "turret"]:
			var part := TankSprites.part(cls, kind)
			var mask: Image = part.paint.get_image()
			if mask.is_compressed(): mask.decompress()
			var fingerprints := {}
			for skin in TankSkinArt.PALETTES:
				var texture := TankSkinArt.texture(part, cls + "_" + kind, skin) as CanvasTexture
				check(texture != null and texture == TankSkinArt.texture(part, cls + "_" + kind, skin), "%s/%s/%s: cached native skin" % [cls, kind, skin])
				var image := texture.diffuse_texture.get_image()
				var clipped := true
				for y in mask.get_height():
					for x in mask.get_width():
						if image.get_pixel(x, y).a > mask.get_pixel(x, y).a + 0.01: clipped = false
				check(clipped, "%s/%s/%s: respects sprite mask" % [cls, kind, skin])
				fingerprints[hash(image.get_data())] = true
			check(fingerprints.size() == TankSkinArt.PALETTES.size(), "%s/%s: every skin has distinct artwork" % [cls, kind])
	check(TankSkinArt.texture(TankSprites.part("universal", "hull"), "universal_hull", "none") == null, "factory appearance remains available")
	print("=== TANK SKINS: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
