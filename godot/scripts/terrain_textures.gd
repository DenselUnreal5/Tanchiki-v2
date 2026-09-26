class_name TerrainTextures
extends RefCounted

static var _cache := {}

static func has_textures(loc: String) -> bool:
	return loc == "city" or loc == "grassland"

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

	# Fallback to city
	if effective_loc != "city":
		return _load_cached("city", file)
	return null

static func grass(loc: String = "city") -> Texture2D:
	return _load_cached(loc, "grass.png")

static func tree(loc: String = "city") -> Texture2D:
	return _load_cached(loc, "tree1.png")

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

static func river(index: int, loc: String = "city") -> Texture2D:
	return _load_cached(loc, "river%d.png" % index)
