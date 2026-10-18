extends Node

var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("OK: " if ok else "FAIL: ", message)

func _ready() -> void:
	var texture := TerrainTextures.wall() as CanvasTexture
	check(texture != null, "indestructible wall texture connected")
	if texture != null:
		check(texture == TerrainTextures.wall(), "wall texture reused from cache")
		check(texture.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "wall uses nearest filtering")
		var image := texture.diffuse_texture.get_image()
		if image.is_compressed(): image.decompress()
		check(image.get_size() == Vector2i(32, 32), "runtime tile matches native 32px game grid")
		var opaque := true
		var colors := {}
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				opaque = opaque and pixel.a > 0.99
				colors[pixel.to_rgba32()] = true
		check(opaque and colors.size() > 12, "opaque textured block without gaps or flat-color placeholder")
	var map := GameMap.new(5, 5)
	for r in 5:
		for c in 5:
			if r == 0 or c == 0 or r == 4 or c == 4: map.set_tile(r, c, Cfg.T_WALL)
	var version := map.version
	for source in ["bullet", "blast", "acid", "fire", "lightning"]:
		check(not map.apply_damage(0, 2, 1000000.0, source), source + ": perimeter remains indestructible")
	check(map.get_tile(0, 2) == Cfg.T_WALL and map.version == version and map.damage[2] == 0, "damage never changes wall or map state")
	check(not map.is_drivable(0, 2) and GameMap.is_solid_tile(Cfg.T_WALL), "wall remains an impassable solid")
	print("=== WALL TEXTURE: failures=%d ===" % failures)
	get_tree().quit(1 if failures else 0)
