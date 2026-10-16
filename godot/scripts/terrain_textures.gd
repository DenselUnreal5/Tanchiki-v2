class_name TerrainTextures
extends RefCounted

static var _cache := {}

static func has_textures(loc: String) -> bool:
	return loc == "city" or loc == "grassland" or loc == "jungle" or loc == "dust"

static func _load_cached(loc: String, file: String) -> Texture2D:
	var effective_loc := loc if has_textures(loc) else "city"
	var key := effective_loc + "/" + file
	if _cache.has(key):
		return _cache[key]

	var path := "res://art/terrain/%s/%s" % [effective_loc, file]
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			_cache[key] = res
			return res

	var global_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(global_path) or FileAccess.file_exists(path):
		var img := Image.load_from_file(global_path)
		if img != null and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_cache[key] = tex
			return tex

	if effective_loc != "city":
		return _load_cached("city", file)
	return null

static func grass(loc: String = "city") -> Texture2D:
	return _load_cached(loc, "grass.png")

static func tree(loc: String = "city") -> Texture2D:
	return _load_cached(loc, "tree1.png")

static func prop_hash(r: int, c: int) -> float:
	return Rng.hash01(r * 92821 + c * 68917, 4242)

static func tree_at(loc: String, h: float) -> Texture2D:
	match loc:
		"city":
			if h < 0.5:
				return tree(loc)
			return _load_cached(loc, "tree_broadleaf.png" if h < 0.8 else "tree_pine.png")
		"dust":
			if h < 0.5:
				return tree(loc)
			if h < 0.7:
				return _load_cached(loc, "cactus_saguaro.png")
			return _load_cached(loc, "cactus_barrel.png" if h < 0.85 else "cactus_cluster.png")
	return tree(loc)

static func building_at(loc: String, variant: int, h: float) -> Texture2D:
	match loc:
		"city":
			match variant:
				1:
					return _load_cached(loc, "house_apartment.png")
				2:
					return _load_cached(loc, "house_warehouse.png")
				3:
					if h < 0.5:
						return _load_cached(loc, "house_cottage.png")
				4:
					return _load_cached(loc, "house_concrete.png")
		"dust":
			if variant == 2:
				return _load_cached(loc, "oil_pumpjack.png" if h < 0.5 else "oil_derrick.png")
	return building(variant == 3, loc)

static func citadel(loc: String) -> Texture2D:
	return _load_cached(loc, "citadel.png")

static func bush(loc: String = "city") -> Texture2D:
	return _load_cached(loc, "bush1.png")

static func bridge(horizontal: bool, loc: String = "city") -> Texture2D:
	return _load_cached(loc, "bridge1.png" if horizontal else "bridge2.png")

static func building(is_wood: bool, loc: String = "city") -> Texture2D:
	return _load_cached(loc, "woodenbuilding1.png" if is_wood else "stonebuilding1.png")

static func road(index: int, loc: String = "city") -> Texture2D:
	if index == 7:
		return _load_cached(loc, "road16.png")
	return _load_cached(loc, "road%d.png" % index)

static func cross_arcs(loc: String) -> Texture2D:
	if not has_textures(loc) or loc == "city":
		return null
	var path := "res://art/terrain/%s/road7.png" % loc
	if not ResourceLoader.exists(path):
		return null
	return _load_cached(loc, "road7.png")

static func river(index: int, loc: String = "city") -> Texture2D:
	return _load_cached(loc, "river%d.png" % index)
