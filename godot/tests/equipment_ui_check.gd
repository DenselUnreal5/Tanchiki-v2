extends Node

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", message)

func _frames(count: int = 4) -> void:
	for i in count: await get_tree().process_frame

func _collect(node: Node, type_name: String) -> Array:
	var out := []
	if (type_name == "card" and node is CannonCard) or (type_name == "icon" and node is PerkIconView):
		out.append(node)
	for child in node.get_children(): out.append_array(_collect(child, type_name))
	return out

func _ready() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames()
	game.ui.open_garage()
	await _frames()
	var hub: Hub = game.ui.hub
	var cards := {}
	for card in _collect(hub, "card"): cards[String(card.get_meta("card_id"))] = card
	for list in [Cannons.LIST, TankClasses.LIST]:
		var prefix := "cannon_" if list == Cannons.LIST else "class_"
		for entry in list:
			var id: String = prefix + entry.id
			check(cards.has(id), id + ": actual garage card exists")
			if not cards.has(id): continue
			var card: CannonCard = cards[id]
			var icon := card.get_node("Row/Icon") as PerkIconView
			check(icon != null and icon.perk_id == id and PerkIcons.texture_of(id) is AtlasTexture,
				id + ": garage renders artwork instead of an emoji Label")
			for locked in [false, true]:
				card.set_data(String(entry.icon), Cfg.UI_MUTED if locked else Color.WHITE,
					entry.name, "state", "action", locked, false, false, id)
				check(icon.perk_id == id and icon.icon_size == Vector2(48, 48), id + ": artwork persists in locked/unlocked states")
	game.ui.open_gallery()
	await _frames()
	check(hub._gallery_nodes.size() == Perks.all().size(), "all player perks appear in the gallery")
	var top := INF
	for perk in Perks.all():
		var node: SkillNode = hub._gallery_nodes[perk.id]
		var icons := _collect(node, "icon")
		check(icons.size() == 1 and icons[0].perk_id == perk.id and icons[0].icon_size == Vector2(40, 40)
			and PerkIcons.texture_of(perk.id) is AtlasTexture, perk.id + ": actual gallery node uses new artwork")
		top = minf(top, node.get_global_rect().position.y)
	check(top < hub.get_global_rect().position.y + 180, "perk icons are visible immediately, above build descriptions")
	game.ui.close_gallery()
	game.ui.toggle_dev_board()
	var board: DevBoard = game.ui._dev_board
	for tab in ["tanks", "perks"]:
		board.switch_tab(tab)
		await _frames()
		var icons := _collect(board._body, "icon")
		var expected := 9 if tab == "tanks" else Perks.all().size()
		check(icons.size() == expected, tab + ": developer panel uses artwork for every item")
		for icon in icons:
			check(PerkIcons.texture_of(icon.perk_id) is AtlasTexture, icon.perk_id + ": developer artwork connected")
	print("=== EQUIPMENT UI: failures=%d ===" % failures)
	game.queue_free()
	await _frames(1)
	get_tree().quit(1 if failures else 0)
