class_name TerrainTextures
extends RefCounted

const DIR := "res://art/terrain/city/"
static var _cache := {}

static func _load_cached(file: String) -> Texture2D:
	if not _cache.has(file):
		_cache[file] = load(DIR + file)
	return _cache[file]

static func grass() -> Texture2D:
	return _load_cached("grass.png")

static func tree() -> Texture2D:
	return _load_cached("tree1.png")

static func bush() -> Texture2D:
	return _load_cached("bush1.png")

static func bridge(horizontal: bool) -> Texture2D:
	return _load_cached("bridge1.png") if horizontal else _load_cached("bridge2.png")

static func building(is_wood: bool) -> Texture2D:
	return _load_cached("woodenbuilding1.png") if is_wood else _load_cached("stonebuilding1.png")

static func road(index: int) -> Texture2D:
	if index == 7:
		return _load_cached("road16.png")
	return _load_cached("road%d.png" % index)

static func river(index: int) -> Texture2D:
	return _load_cached("river%d.png" % index)
