extends Node

var failures := 0

func _ready() -> void:
	var city_road_before := TerrainTextures.road(1, "city").get_image().get_data().duplicate()
	for loc in ["dust", "frost", "exclusion", "shore"]:
		_check(TerrainTextures.has_textures(loc), loc + ": textured rendering enabled")
		for file in TerrainTextures.BIOME_FILES:
			var texture := TerrainTextures._load_cached(loc, file)
			_check(texture is AtlasTexture, loc + "/" + file + ": own atlas region")
			if texture is AtlasTexture:
				_check(texture.region.position.y > 0 or loc == "frost", loc + ": correct biome row")
				_check(texture.get_image() != null, loc + "/" + file + ": readable pixels")
		for i in range(1, 19):
			_check_texture(TerrainTextures.road(i, loc), "%s/road%d" % [loc, i])
		for i in range(1, 12):
			_check_texture(TerrainTextures.river(i, loc), "%s/river%d" % [loc, i])
		for horizontal in [true, false]:
			_check_texture(TerrainTextures.bridge(horizontal, loc), loc + "/bridge")
		for variant in range(5):
			_check_texture(TerrainTextures.building_at(loc, variant, 0.2), loc + "/building")
		var ground := TerrainTextures.grass(loc).get_image()
		var sand := TerrainTextures.sand(loc).get_image()
		_check(ground.get_data() != sand.get_data(), loc + ": sand differs from ground")
		if loc != "dust":
			var road := TerrainTextures.road(1, loc).get_image()
			var city := TerrainTextures.road(1, "city").get_image()
			_check(road.get_data() != city.get_data(), loc + ": road verges adapted to biome")
			_check(road.get_size() == city.get_size(), loc + ": road geometry preserved")
			var sea := TerrainTextures.biome_water(loc, false, false, false, false).get_image()
			var bank := TerrainTextures.biome_water(loc, true, false, false, false).get_image()
			_check(sea.get_pixel(0, 0).b > sea.get_pixel(0, 0).r, loc + ": open water has no land corners")
			_check(bank.get_pixel(16, 0) != sea.get_pixel(16, 0), loc + ": bank beside land")
			_check(bank.get_pixel(16, 31) == sea.get_pixel(16, 31), loc + ": wet neighbour stays connected")
	_check(TerrainTextures.road(1, "city").get_image().get_data() == city_road_before,
		"shared city texture not mutated by biome generation")
	_check(TerrainTextures.tree_at("dust", 0.6) == TerrainTextures._load_cached("dust", "cactus_saguaro.png"),
		"dust: existing cactus variants retained")
	print("=== TERRAIN TEXTURES: failures: %d ===" % failures)
	get_tree().quit(1 if failures else 0)

func _check_texture(texture: Texture2D, label: String) -> void:
	_check(texture != null and texture.get_width() > 0 and texture.get_height() > 0, label)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
