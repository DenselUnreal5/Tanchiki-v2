class_name TankSkinArt
extends RefCounted

## Native sprite-space cosmetics. Cached, clipped to the actual paint mask;
## the gun silhouette and the original mechanical shading remain intact.
const PALETTES := {
	"cyberpunk": [Color("#344454"), Color("#182c3a"), Color("#49d8db"), Color("#b0eef0")],
	"magma": [Color("#4b4039"), Color("#282b30"), Color("#dc6633"), Color("#f7be61")],
	"steampunk": [Color("#997047"), Color("#504337"), Color("#d2aa65"), Color("#ecce8c")],
	"void": [Color("#4b415f"), Color("#282c40"), Color("#9e84cb"), Color("#d7c4f2")],
	"dragon": [Color("#43715a"), Color("#2b433c"), Color("#b5a665"), Color("#e3d39a")],
	"toxic": [Color("#69714b"), Color("#323b35"), Color("#b6cc60"), Color("#e3e89b")],
	"golden_emperor": [Color("#c4a05e"), Color("#755b3b"), Color("#ebd399"), Color("#774860")],
	"arctic_frost": [Color("#a6bdc7"), Color("#5f7c91"), Color("#d8eced"), Color("#73b6c8")],
}
static var _cache: Dictionary = {}

static func texture(part: Dictionary, key: String, skin: String) -> Texture2D:
	if not PALETTES.has(skin) or part.is_empty(): return null
	var cache_key := key + ":" + skin
	if _cache.has(cache_key): return _cache[cache_key]
	var mask: Image = part.paint.get_image()
	if mask.is_compressed(): mask.decompress()
	var image := Image.create(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8)
	var palette: Array = PALETTES[skin]
	for y in mask.get_height():
		for x in mask.get_width():
			var source := mask.get_pixel(x, y)
			if source.a <= 0: continue
			var slot := _slot(skin, x, y)
			var col: Color = palette[slot]
			# Keep bevels, hatches and panel depth from the authored sprite.
			var shade := clampf(source.r * 1.6, 0.45, 1.15)
			image.set_pixel(x, y, Color(col.r * shade, col.g * shade, col.b * shade, source.a))
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cache[cache_key] = texture
	return texture

static func _slot(skin: String, x: int, y: int) -> int:
	match skin:
		"cyberpunk":
			if (x == 25 or x == 38) and y % 11 < 8: return 2
			if y % 13 == 0 and x % 9 < 5: return 3
			return 1 if (x / 5 + y / 7) % 4 == 0 else 0
		"magma":
			var crack := posmod(x + y / 3 + (y / 7) * 3, 13)
			if crack == 0: return 3
			if crack <= 2: return 2
			return 1 if (x / 5 + y / 5) % 3 == 0 else 0
		"steampunk":
			if x % 8 == 0 or y % 9 == 0: return 1
			if x % 8 == 2 and y % 9 == 2: return 3
			return 2 if x % 8 == 1 else 0
		"void":
			if Rng.hash01(x + y * 97, 311) > 0.97: return 3
			if (x + y / 2) % 15 < 2: return 2
			return 1 if (x / 7 + y / 5) % 3 == 0 else 0
		"dragon":
			var row := y / 5
			var col := posmod(x + (row % 2) * 3, 7)
			if y % 5 == 0 or (y % 5 < 3 and col == 0): return 1
			if y % 5 == 1 and col < 3: return 2
			return 0
		"toxic":
			if y > 35 and y < 42: return 2 if (x + y) % 8 < 4 else 1
			if x > 29 and x < 35 and y > 24 and y < 34: return 3 if y % 4 < 2 else 1
			return 1 if x % 11 == 0 else 0
		"golden_emperor":
			if x == 24 or x == 39 or y % 14 == 0: return 2
			if x >= 30 and x <= 33: return 3
			return 1 if x % 9 == 0 else 0
		"arctic_frost":
			if (x - y / 2) % 11 == 0: return 2
			if (x / 5 + y / 6) % 4 == 0: return 1
			return 3 if (x + y) % 17 < 2 else 0
	return 0

static func tracks(part: Dictionary, key: String, color: Color) -> Texture2D:
	var cache_key := key + ":tracks:" + color.to_html()
	if _cache.has(cache_key): return _cache[cache_key]
	var source: Image = part.tex.get_image()
	if source.is_compressed(): source.decompress()
	var image := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	var rect: Rect2i = part.rect
	var width := maxi(3, int(rect.size.x * 0.19))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x >= rect.position.x + width and x < rect.end.x - width: continue
			var original := source.get_pixel(x, y)
			if original.a <= 0.0: continue
			var shade := 0.5 if y % 4 == 0 else 0.9
			image.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, original.a * 0.8))
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cache[cache_key] = texture
	return texture
