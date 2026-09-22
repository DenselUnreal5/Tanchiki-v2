class_name TankArt
extends RefCounted

static var CHASSIS := {
	"standard": {
		"w": 24.0, "h": 28.0, "track_w": 6.0, "wheels": 4, "nose": 0.22,
		"turret_r": 7.5, "barrel_len": 24.0, "barrel_w": 5.0, "muzzle": "plain",
		"plates": false, "antenna": false, "scope": false, "stripes": false,
	},
	"light": {
		"w": 21.0, "h": 25.0, "track_w": 5.0, "wheels": 3, "nose": 0.34,
		"turret_r": 6.0, "barrel_len": 21.0, "barrel_w": 4.0, "muzzle": "plain",
		"plates": false, "antenna": true, "scope": false, "stripes": false,
	},
	"heavy": {
		"w": 29.0, "h": 30.0, "track_w": 8.0, "wheels": 5, "nose": 0.12,
		"turret_r": 9.5, "barrel_len": 23.0, "barrel_w": 7.5, "muzzle": "brake",
		"plates": true, "antenna": false, "scope": false, "stripes": false,
	},
	"sniper": {
		"w": 23.0, "h": 29.0, "track_w": 5.5, "wheels": 4, "nose": 0.26,
		"turret_r": 7.0, "barrel_len": 36.0, "barrel_w": 4.0, "muzzle": "brake",
		"plates": false, "antenna": false, "scope": true, "stripes": false,
	},
	"mortar": {
		"w": 25.0, "h": 27.0, "track_w": 6.5, "wheels": 4, "nose": 0.10,
		"turret_r": 8.5, "barrel_len": 14.0, "barrel_w": 10.0, "muzzle": "tube",
		"plates": false, "antenna": true, "scope": false, "stripes": false,
	},
	"boss": {
		"w": 34.0, "h": 36.0, "track_w": 9.0, "wheels": 5, "nose": 0.16,
		"turret_r": 11.5, "barrel_len": 30.0, "barrel_w": 6.0, "muzzle": "twin",
		"plates": true, "antenna": true, "scope": false, "stripes": true,
	},
}

const MAX_COLLIDE_W := 26.0
const MAX_COLLIDE_H := 30.0

static func chassis(id: String) -> Dictionary:
	return CHASSIS.get(id, CHASSIS["standard"])

static func muzzle_len(shape: Dictionary) -> float:
	var tip: float = float(shape["turret_r"]) * 0.5 + float(shape["barrel_len"]) * 0.85
	return minf(tip, float(shape["h"]) * 0.5 + 6.0)

static func hit_radius(w: float, h: float) -> float:
	return (w + h) * 0.25 + 1.0
