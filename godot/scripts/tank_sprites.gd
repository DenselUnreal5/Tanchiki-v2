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

static func turret_class(tank, hull: String) -> String:
	if tank.enemy_type.is_empty() and BY_CANNON.has(tank.cannon_id):
		return String(BY_CANNON[tank.cannon_id])
	return hull

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
