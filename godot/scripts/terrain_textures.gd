class_name TerrainTextures
extends RefCounted

static var _cache := {}

## Each row contains ground, sand, tree, bush, masonry, timber, fort, warehouse.
## Atlas regions keep the original artwork intact and share one GPU texture.
const BIOME_ROWS := {"frost": 0, "exclusion": 1, "shore": 2, "dust": 3}
const BIOME_FILES := {
	"grass.png": 0, "sand.png": 1, "tree1.png": 2, "bush1.png": 3,
	"stonebuilding1.png": 4, "woodenbuilding1.png": 5,
	"citadel.png": 6, "house_warehouse.png": 7,
}
const BIOME_ATLAS := "res://art/terrain/biomes.png"
const DUST_GROUND := "res://art/terrain/dust/sand_ground.png"
const ADAPTED_BIOMES := ["dust", "frost", "exclusion", "shore"]

static func has_textures(loc: String) -> bool:
	return loc in ["city", "grassland", "jungle"] or BIOME_ROWS.has(loc)

static func _biome_region(loc: String, file: String) -> Texture2D:
	# All desert ground uses one surface, including underneath transparent props.
	if loc == "dust" and file in ["grass.png", "sand.png"]:
		return load(DUST_GROUND)
	if not BIOME_ROWS.has(loc) or not BIOME_FILES.has(file):
		return null
	var atlas: Texture2D = load(BIOME_ATLAS)
	var size := Vector2(atlas.get_width() / 8.0, atlas.get_height() / 4.0)
	var region := AtlasTexture.new()
	region.atlas = atlas
	region.region = Rect2(Vector2(float(BIOME_FILES[file]), float(BIOME_ROWS[loc])) * size, size)
	region.filter_clip = true
	return region

## Reuse the city's connected road/river shapes so junctions stay aligned.
## Only the green verges are replaced; asphalt, markings and bridge geometry
## remain readable. This is cached once per tile, not recomputed while drawing.
static func _biome_infrastructure(loc: String, file: String) -> Texture2D:
	var source := _load_cached("city", file)
	if source == null:
		return null
	var source_image := source.get_image()
	var ground := _load_cached(loc, "sand.png" if loc == "shore" else "grass.png").get_image()
	if source_image == null or ground == null:
		return source
	var img: Image = source_image.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var pixel := img.get_pixel(x, y)
			if pixel.g > pixel.r * 1.12 and pixel.g > pixel.b * 1.1:
				var gx := x * ground.get_width() / img.get_width()
				var gy := y * ground.get_height() / img.get_height()
				var replacement := ground.get_pixel(gx, gy)
				replacement.a = pixel.a
				img.set_pixel(x, y, replacement)
			elif loc == "frost" and file.begins_with("road"):
				# A light frost film leaves the dark carriageway and lines visible.
				img.set_pixel(x, y, pixel.lerp(Color(0.7, 0.78, 0.84, pixel.a), 0.2))
	return ImageTexture.create_from_image(img)

static func _load_cached(loc: String, file: String) -> Texture2D:
	var effective_loc := loc if has_textures(loc) else "city"
	var key := effective_loc + "/" + file
	if _cache.has(key):
		return _cache[key]
	var biome := _biome_region(effective_loc, file)
	if biome != null:
		_cache[key] = biome
		return biome
	if effective_loc in ADAPTED_BIOMES and (
			file.begins_with("road") or file.begins_with("river") or file.begins_with("bridge")):
		var infrastructure := _biome_infrastructure(effective_loc, file)
		_cache[key] = infrastructure
		return infrastructure

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

static func sand(loc: String = "city") -> Texture2D:
	return _load_cached(loc, "sand.png" if BIOME_ROWS.has(loc) else "grass.png")

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
		"frost", "exclusion", "shore":
			if variant == 2:
				return _load_cached(loc, "house_warehouse.png")
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
	if not has_textures(loc) or loc == "city" or loc in ADAPTED_BIOMES:
		return null
	var path := "res://art/terrain/%s/road7.png" % loc
	if not ResourceLoader.exists(path):
		return null
	return _load_cached(loc, "road7.png")

static func river(index: int, loc: String = "city") -> Texture2D:
	return _load_cached(loc, "river%d.png" % index)

## River sprites contain grassy corners even on the centre tile. Wide seas
## need water all the way to each wet neighbour, with banks only beside land.
static func biome_water(loc: String, up: bool, down: bool, left: bool, right: bool) -> Texture2D:
	var mask := int(up) | (int(down) << 1) | (int(left) << 2) | (int(right) << 3)
	var key := "%s/water/%d" % [loc, mask]
	if _cache.has(key):
		return _cache[key]
	var source := river(3, "city").get_image()
	var ground := sand(loc).get_image() if loc == "shore" else grass(loc).get_image()
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var tint := Color("#28667d")
	if loc == "frost":
		tint = Color("#41667e")
	elif loc == "exclusion":
		tint = Color("#405448")
	elif loc == "dust":
		tint = Color("#447b80")
	for y in 32:
		for x in 32:
			# Only sample the water in the middle of the old river sprite.
			var pixel := source.get_pixel(12 + x % 8, 12 + y % 8).lerp(tint, 0.65)
			var distance := 32
			if up:
				distance = mini(distance, y)
			if down:
				distance = mini(distance, 31 - y)
			if left:
				distance = mini(distance, x)
			if right:
				distance = mini(distance, 31 - x)
			if distance < 2:
				pixel = ground.get_pixel(x * ground.get_width() / 32, y * ground.get_height() / 32)
			elif distance < 4:
				pixel = pixel.lerp(Color("#a6c7bd"), 0.55 if distance == 2 else 0.25)
			image.set_pixel(x, y, pixel)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
