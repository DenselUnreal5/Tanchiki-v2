class_name TankSprites
extends RefCounted

const DIR := "res://art/tanks/"
const PIVOT := Vector2(32.0, 32.0)
const PAINT_GAIN := 1.3

const BY_ENEMY := {
	"grunt": "private", "scout": "scout", "heavy": "bruiser", "sniper": "sniper",
	"mortar": "mortar", "pyro": "flamethrower", "tesla": "lightning",
}
const BY_CLASS := {
	"standard": "universal", "grunt": "private", "scout": "scout",
	"heavy": "bruiser", "sniper": "sniper", "mortar": "mortar",
}
const BY_COLOR := {
	"enemy": "private", "scout": "scout", "heavy": "bruiser", "sniper": "sniper",
	"mortar": "mortar", "pyro": "flamethrower", "tesla": "lightning",
}
const BY_CHASSIS := {
	"standard": "universal", "light": "scout", "heavy": "bruiser",
	"sniper": "sniper", "mortar": "mortar",
}
const BY_CANNON := {
	"fire": "flamethrower", "shock": "lightning", "acid": "acid",
}

static var _cache := {}

static func hull_class(tank) -> String:
	if not BY_CHASSIS.has(tank.chassis_id):
		return ""
	if not tank.enemy_type.is_empty():
		return String(BY_ENEMY.get(String(tank.enemy_type.get("id", "")), BY_CHASSIS[tank.chassis_id]))
	if tank.class_id != "standard" and BY_CLASS.has(tank.class_id):
		return String(BY_CLASS[tank.class_id])
	if BY_COLOR.has(tank.color_key):
		return String(BY_COLOR[tank.color_key])
	return String(BY_CHASSIS[tank.chassis_id])

static func turret_class(_tank, hull: String) -> String:
	return hull

# Native-space mount, muzzle and bore width for each class. Weapons adapt to
# the class turret, rather than replacing it with a different enemy's turret.
const GUN_FIT := {
	"universal": Vector3i(24, 7, 5), "private": Vector3i(24, 5, 5),
	"scout": Vector3i(24, 10, 3), "bruiser": Vector3i(20, 8, 8),
	"sniper": Vector3i(24, 1, 4), "mortar": Vector3i(20, 9, 9),
}

static func turret_part(tank, hull: String) -> Dictionary:
	var original := part(hull, "turret")
	if original.is_empty(): return original
	var cannon: String = tank.cannon_id
	if not tank.enemy_type.is_empty() or cannon in ["", "standard"] or not GUN_FIT.has(hull) or Cannons.get_cannon(cannon).is_empty(): return original
	var key := hull + "_turret:" + cannon
	if _cache.has(key): return _cache[key]
	var tex: Image = original.tex.get_image()
	var paint: Image = original.paint.get_image()
	if tex.is_compressed(): tex.decompress()
	if paint.is_compressed(): paint.decompress()
	tex = tex.duplicate()
	paint = paint.duplicate()
	var fit: Vector3i = GUN_FIT[hull]
	var root := fit.x
	var tip := fit.y
	var width := fit.z
	# Remove only the old barrel. Hatches, optics, antenna and turret armour stay.
	for y in root:
		for x in range(22, 43):
			tex.set_pixel(x, y, Color.TRANSPARENT)
			paint.set_pixel(x, y, Color.TRANSPARENT)
	var left := 32 - width / 2
	for y in range(tip, root):
		for x in range(left, left + width):
			var edge := x == left or x == left + width - 1
			_gun_pixel(tex, paint, x, y, Color("#303b43") if edge else Color("#839297"), not edge)
	var color: Color = Cannons.get_cannon(cannon).get("color", Color.WHITE)
	match cannon:
		"ice":
			for y in range(tip, root - 2):
				for x in range(left - 1, left + width + 1):
					_gun_pixel(tex, paint, x, y, Color("#c2e0e5") if (y - tip) % 4 == 0 else Color("#527f96"), false)
		"acid":
			for y in range(tip + 3, root - 2):
				for x in range(left, left + width):
					if x == left or x == left + width - 1: _gun_pixel(tex, paint, x, y, color.darkened(0.25), false)
			# The nozzle is the frontmost part: no paintable factory pipe
			# may extend ahead of it when a cosmetic skin is applied.
			for y in range(tip, tip + 2):
				for x in range(left - 1, left + width + 1):
					_gun_pixel(tex, paint, x, y, Color("#344039") if y == tip else color.darkened(0.25), false)
		"fire":
			for y in range(tip + 3, root - 2):
				for x in range(left, left + width):
					_gun_pixel(tex, paint, x, y, Color("#303137") if y % 4 < 2 else Color("#66523f"), false)
			for y in range(tip, tip + 3):
				for x in range(left - 1, left + width + 1):
					_gun_pixel(tex, paint, x, y, color.darkened(0.15) if y == tip + 1 else Color("#3e3430"), false)
		"shock":
			for y in range(tip, root - 2):
				for x in [left - 1, left + width]:
					_gun_pixel(tex, paint, x, y, Color("#649bb7") if y % 4 < 2 else Color("#304758"), false)
			for x in range(left - 1, left + width + 1):
				_gun_pixel(tex, paint, x, tip, Color("#e6cf78"), false)
	var mask := Image.create(tex.get_width(), tex.get_height(), false, Image.FORMAT_RGBA8)
	for y in tex.get_height():
		for x in tex.get_width():
			mask.set_pixel(x, y, Color(1, 1, 1, tex.get_pixel(x, y).a))
	var used := tex.get_used_rect()
	var info := {"tex": ImageTexture.create_from_image(tex), "paint": ImageTexture.create_from_image(paint),
		"mask": ImageTexture.create_from_image(mask), "rect": used,
		"center": Vector2(used.position) + Vector2(used.size) * 0.5, "cache_key": key,
		"barrel_tip": tip, "barrel_width": width, "barrel_root": root}
	_cache[key] = info
	return info

static func _gun_pixel(tex: Image, paint: Image, x: int, y: int, color: Color, paintable: bool) -> void:
	tex.set_pixel(x, y, color)
	paint.set_pixel(x, y, Color(0.65, 0.65, 0.65, 1) if paintable else Color.TRANSPARENT)

static func part(cls: String, kind: String) -> Dictionary:
	var key := cls + "_" + kind
	if _cache.has(key):
		return _cache[key]
	var info := {}
	var tex: Texture2D = load(DIR + key + ".png")
	var paint: Texture2D = load(DIR + key + "_paint.png")
	if tex != null and paint != null:
		var img := tex.get_image()
		if img == null or img.is_empty():
			_cache[key] = info
			return info
		if img.is_compressed():
			img.decompress()
		var used := img.get_used_rect()
		var mask_img := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var a := img.get_pixel(x, y).a
				if a > 0.0:
					mask_img.set_pixel(x, y, Color(1, 1, 1, a))
		info = {
			"tex": tex, "paint": paint, "mask": ImageTexture.create_from_image(mask_img),
			"rect": used, "center": Vector2(used.position) + Vector2(used.size) * 0.5,
		}
	_cache[key] = info
	return info

static func paint_modulate(color: Color, alpha: float = 1.0) -> Color:
	return Color(color.r * PAINT_GAIN, color.g * PAINT_GAIN, color.b * PAINT_GAIN, alpha)

# Separate, unpainted functional hardware stays legible under every cosmetic.
# It does not alter the authored turret body or the cosmetic paint mask.
static func weapon_modules(tank, hull: String) -> Texture2D:
	if not tank.enemy_type.is_empty() or not GUN_FIT.has(hull) or not tank.cannon_id in ["ice", "acid", "fire", "shock"]: return null
	var key := "modules:" + hull + ":" + String(tank.cannon_id)
	if _cache.has(key): return _cache[key]
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var narrow := hull in ["scout", "sniper"]
	var spread := 7 if narrow else 9
	var top := 28 if hull != "bruiser" and hull != "mortar" else 26
	var color: Color = Cannons.get_cannon(tank.cannon_id).get("color", Color.WHITE)
	for side in [-1, 1]:
		var cx: int = 32 + int(side) * spread
		for y in range(top, top + 10):
			for x in range(cx - 2, cx + 3):
				var edge: bool = x == cx - 2 or x == cx + 2 or y == top or y == top + 9
				var fill := Color("#26333d") if edge else color.darkened(0.15)
				match tank.cannon_id:
					"ice":
						if not edge: fill = Color("#c4f1fa") if y % 3 == 0 else Color("#3d9dbb")
					"acid":
						if not edge: fill = Color("#ddf98b") if x == cx - 1 else Color("#72bd30")
					"fire":
						if not edge: fill = Color("#cd5637") if y % 4 < 3 else Color("#4e3331")
					"shock":
						if not edge: fill = Color("#ffdb62") if y % 3 == 0 else Color("#3d8fc7")
				image.set_pixel(x, y, fill)
		# Hose/connector leads toward the breech without covering the hatch.
		for x in range(mini(cx, 32 + side * 4), maxi(cx, 32 + side * 4) + 1):
			image.set_pixel(x, top + 1, Color("#556774"))
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cache[key] = texture
	return texture

static func fitted_barrel(tank, hull: String) -> bool:
	return tank.enemy_type.is_empty() and GUN_FIT.has(hull) and tank.cannon_id in ["ice", "acid", "fire", "shock"]

static func barrel_tip_y(tank, hull: String) -> float:
	var body := part(hull, "hull")
	var scale: float = tank.height / float((body.rect as Rect2i).size.y)
	return -tank.muzzle_len / scale
