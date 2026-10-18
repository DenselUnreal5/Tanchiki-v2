extends Node

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", message)

func _ready() -> void:
	var ids: Array[String] = []
	for list in [Perks.LIST, Perks.ACTIVE_LIST, Perks.EXTRA_LIST, Perks.EXTRA_ACTIVE, Perks.BOT_LIST, Perks.BUILDS]:
		for perk in list: ids.append(perk.id)
	for achievement in Achievements.LIST: ids.append("ach_" + achievement.id)
	for upgrade in Upgrades.LIST: ids.append("upg_" + upgrade.id)
	for cannon in Cannons.LIST: ids.append("cannon_" + cannon.id)
	for entry in TankClasses.LIST: ids.append("class_" + entry.id)
	for weapon in Weapons.LIST.values(): ids.append("weapon_" + weapon.id)
	for id in ids:
		var texture := PerkIcons.texture_of(id) as AtlasTexture
		if texture == null:
			check(false, id + ": generated artwork connected")
			continue
		var source := texture.atlas.get_image()
		if source.is_compressed(): source.decompress()
		var rect := Rect2i(texture.region)
		check(Rect2i(Vector2i.ZERO, source.get_size()).encloses(rect), id + ": atlas region in bounds")
		var colored := 0
		var transparent := 0
		for y in range(rect.position.y, rect.end.y, 3):
			for x in range(rect.position.x, rect.end.x, 3):
				var pixel := source.get_pixel(x, y)
				if pixel.a < 0.05: transparent += 1
				elif pixel.a > 0.5 and minf(pixel.r, minf(pixel.g, pixel.b)) < 0.7: colored += 1
		check(colored > 30 and transparent > 10, id + ": colored artwork and transparent background, no blank placeholder")
		check(texture == PerkIcons.texture_of(id), id + ": cached resource")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://art/ui_icons/manifest.json"))
	var mapping_matches: bool = manifest.size() == UiIconArt.ENTRIES.size()
	for id in UiIconArt.ENTRIES:
		var entry: Array = UiIconArt.ENTRIES[id]
		var documented: Array = manifest.get(id, ["missing", -1])
		mapping_matches = mapping_matches and documented[0] == entry[0] and int(documented[1]) == int(entry[1])
		if entry.size() > 2:
			mapping_matches = mapping_matches and documented.size() == entry.size()
			if documented.size() == entry.size():
				for i in 4: mapping_matches = mapping_matches and int(documented[2][i]) == int(entry[2][i])
	check(mapping_matches, "documented atlas mapping matches runtime mapping")
	check(UiIconArt.texture_of("unknown_future_perk") == null, "unknown icon retains fallback")
	check(UiIconArt.texture_of("bot_rapid").region == UiIconArt.texture_of("rapid_fire").region, "bot alias matches player perk")
	var up := load("res://scenes/ui/cards/upgrade_card.tscn").instantiate() as UpgradeCard
	add_child(up)
	up.set_data("upg_dmg", "Мощный ствол", "Урон своих пуль", 1, 10, "Улучшить", "МАКС", false, true, "upg_dmg")
	check(up.get_node("Row/Icon").icon_size == Vector2(40, 40), "garage artwork displayed at 40px")
	var ach := load("res://scenes/ui/cards/achievement_card.tscn").instantiate() as AchievementCard
	add_child(ach)
	ach.set_data("ach_first_blood", "Первая кровь", "Первое уничтожение", false, 20, 0, 1)
	check(ach.get_node("Box/Icon").icon_size == Vector2(48, 48) and ach.modulate.a > 0.5, "locked achievement remains recognizable at 48px")
	print("=== UI ICON ART: ids=%d failures=%d ===" % [ids.size(), failures])
	get_tree().quit(1 if failures else 0)
