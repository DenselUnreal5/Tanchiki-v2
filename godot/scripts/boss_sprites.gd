class_name BossSprites
extends RefCounted

# The authored atlas scenes define these pivots and relative module sizes.
# Keep collision sizes and attack origins in Tank; only fit the visual barrel.
const MODELS := {
	"boss": {"hull": preload("res://art/tanks/bosses/boss/hull.tres"),
		"turret": preload("res://art/tanks/bosses/boss/turret.tres"),
		"hull_offset": Vector2(-443, -466), "turret_offset": Vector2(-445, -550), "turret_scale": 0.72, "barrel_root": 300.0},
	"boss_rammer": {"hull": preload("res://art/tanks/bosses/boss_rammer/hull.tres"),
		"turret": preload("res://art/tanks/bosses/boss_rammer/turret.tres"),
		"hull_offset": Vector2(-475, -494), "turret_offset": Vector2(-455, -495), "turret_scale": 0.65, "barrel_root": 0.0},
	"boss_chimera": {"hull": preload("res://art/tanks/bosses/boss_chimera/hull.tres"),
		"turret": preload("res://art/tanks/bosses/boss_chimera/turret.tres"),
		"hull_offset": Vector2(-476, -438), "turret_offset": Vector2(-456, -568), "turret_scale": 0.85, "barrel_root": 310.0},
}
static var _cache := {}

static func has(tank: Tank) -> bool:
	return MODELS.has(tank.chassis_id)

static func model(id: String) -> Dictionary:
	if _cache.has(id): return _cache[id]
	if not MODELS.has(id): return {}
	var data: Dictionary = MODELS[id].duplicate()
	for part in ["hull", "turret"]:
		var source: Texture2D = data[part]
		var image := source.get_image()
		data[part + "_rect"] = image.get_used_rect()
		var texture := CanvasTexture.new()
		# CanvasTexture does not preserve AtlasTexture UV regions. Materialize
		# each half once, so the hull can never include the detached turret.
		data[part + "_source"] = source
		texture.diffuse_texture = ImageTexture.create_from_image(image)
		texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		data[part] = texture
	_cache[id] = data
	return data

static func scale_for(tank: Tank, data: Dictionary) -> float:
	return tank.height / float((data.hull_rect as Rect2i).size.y)
