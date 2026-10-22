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
const ADAPTED_BIOMES := ["dust", "frost", "exclusion", "shore"]

static func has_textures(loc: String) -> bool:
	return loc in ["city", "grassland", "jungle"] or BIOME_ROWS.has(loc)

static func _biome_region(loc: String, file: String) -> Texture2D:
	# All desert ground uses one surface, including underneath transparent props.
	if loc == "dust" and file in ["grass.png", "sand.png"]:
		return _desert_ground()
	if not BIOME_ROWS.has(loc) or not BIOME_FILES.has(file):
		return null
	var atlas: Texture2D = load(BIOME_ATLAS)
	var size := Vector2(atlas.get_width() / 8.0, atlas.get_height() / 4.0)
	var region := AtlasTexture.new()
	region.atlas = atlas
	region.region = Rect2(Vector2(float(BIOME_FILES[file]), float(BIOME_ROWS[loc])) * size, size)
	region.filter_clip = true
	return region

## Native 32px terrain: a small shared palette keeps sand crisp at game scale.
static func _desert_ground() -> Texture2D:
	const key := "dust/pixel_ground"
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var palette := [Color("#bca06a"), Color("#c6aa72"), Color("#cfb57c"), Color("#d7be87")]
	for y in 32:
		for x in 32:
			var grain := Rng.hash01(x + y * 32, 813)
			var ripple := (y + int(2.0 * sin(float(x) * TAU / 32.0))) % 12
			var index := 1 if grain < 0.7 else 2
			if ripple == 0 and grain < 0.4:
				index = 0
			elif grain > 0.96:
				index = 3
			image.set_pixel(x, y, palette[index])
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func quicksand() -> Texture2D:
	const key := "dust/quicksand"
	if _cache.has(key):
		return _cache[key]
	var image := _desert_ground().get_image().duplicate() as Image
	for y in 32:
		for x in 32:
			var color := image.get_pixel(x, y).lerp(Color("#79633f"), 0.63)
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

## Reuse the city's connected road/river shapes so junctions stay aligned.
## Green verges follow the biome. Desert roads replace asphalt and markings
## with compacted sand while preserving the connected shapes. This is cached once per tile, not recomputed while drawing.
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
			elif loc == "dust" and file.begins_with("road"):
				var gx := x * ground.get_width() / img.get_width()
				var gy := y * ground.get_height() / img.get_height()
				var sand_pixel := ground.get_pixel(gx, gy)
				# Road geometry comes from the source; its paint is deliberately ignored.
				var rut := (file == "road1.png" and gy in [9, 22]) or (file == "road2.png" and gx in [9, 22])
				var shade := 0.18 if rut else 0.09
				if (gx + gy * 3) % 7 == 0:
					shade += 0.025
				img.set_pixel(x, y, sand_pixel.darkened(shade))
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

## Shared indestructible wall material across every biome and the map editor.
static func wall() -> Texture2D:
	const key := "_indestructible_wall"
	if _cache.has(key):
		return _cache[key]
	var path := "res://art/terrain/indestructible_wall.png"
	if not ResourceLoader.exists(path):
		return null
	var source := load(path) as Texture2D
	if source == null:
		return null
	var texture := CanvasTexture.new()
	texture.diffuse_texture = source
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cache[key] = texture
	return texture

static func grass(loc: String = "city") -> Texture2D:
	return _load_cached(loc, "grass.png")

static func sand(loc: String = "city") -> Texture2D:
	return _load_cached(loc, "sand.png" if BIOME_ROWS.has(loc) else "grass.png")

## Neighbour masks also support roads wider than one tile without grid seams.
static func desert_road(up: bool, down: bool, left: bool, right: bool) -> Texture2D:
	var mask := int(up) | (int(down) << 1) | (int(left) << 2) | (int(right) << 3)
	var key := "dust/sand_road/%d" % mask
	if _cache.has(key):
		return _cache[key]
	var image := _desert_ground().get_image().duplicate() as Image
	for y in 32:
		for x in 32:
			var edge := (not up and y < 2) or (not down and y > 29) or (not left and x < 2) or (not right and x > 29)
			if edge:
				continue
			var rut := false
			if up and down:
				rut = (not left and x in [6, 8]) or (not right and x in [23, 25])
			if left and right:
				rut = rut or (not up and y in [6, 8]) or (not down and y in [23, 25])
			var shade := 0.18 if rut and (x + y) % 7 != 0 else 0.10
			image.set_pixel(x, y, image.get_pixel(x, y).darkened(shade))
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

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

static func road_shape(up: bool, down: bool, left: bool, right: bool) -> int:
	if up and down and left and right:
		return 16
	if down and left and right:
		return 8
	if up and down and right:
		return 9
	if up and down and left:
		return 10
	if up and left and right:
		return 11
	if right and down and not up and not left:
		return 12
	if left and down and not up and not right:
		return 13
	if up and right and not down and not left:
		return 14
	if up and left and not down and not right:
		return 15
	if up or down:
		return 2
	return 1

static func river_shape(up: bool, down: bool, left: bool, right: bool) -> int:
	if not up and not down and not left and not right:
		return 3
	if up and not down and not left and not right:
		return 4
	if down and not up and not left and not right:
		return 7
	if left and not up and not down and not right:
		return 5
	if right and not up and not down and not left:
		return 6
	if up and left and not down and not right:
		return 8
	if up and right and not down and not left:
		return 9
	if down and left and not up and not right:
		return 10
	if down and right and not up and not left:
		return 11
	if up and down and not left and not right:
		return 1
	if left and right and not up and not down:
		return 2
	var wet_h := not left or not right
	var wet_v := not up or not down
	if wet_h and not wet_v:
		return 1
	if wet_v and not wet_h:
		return 2
	return 3

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
