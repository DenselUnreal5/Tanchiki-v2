class_name Materials
extends RefCounted

static var WOOD := {
	"id": "wood", "name": "дерево",
	"hp": 30.0, "bullet": 1.15, "blast": 1.6,
	"base": Color("#8a6a3f"), "dark": Color("#5f472a"), "light": Color("#a98c62"),
	"dust": Color("#c9a877"),
	"pieces": 9, "piece_w": Vector2(7.0, 15.0), "piece_h": Vector2(2.0, 3.5),
	"speed": Vector2(1.6, 3.4), "spin": 0.26, "life": Vector2(90.0, 150.0),
	"sound": "crack", "shake": 3.0, "sparks": 0,
}
static var BRICK := {
	"id": "brick", "name": "кирпич",
	"hp": 75.0, "bullet": 1.0, "blast": 1.2,
	"base": Color("#8a5a4a"), "dark": Color("#5e3a30"), "light": Color("#a97a66"),
	"dust": Color("#b08878"),
	"pieces": 11, "piece_w": Vector2(4.0, 7.0), "piece_h": Vector2(4.0, 7.0),
	"speed": Vector2(1.2, 2.8), "spin": 0.18, "life": Vector2(80.0, 140.0),
	"sound": "crumble", "shake": 4.0, "sparks": 0,
}
static var CONCRETE := {
	"id": "concrete", "name": "бетон",
	"hp": 160.0, "bullet": 1.0, "blast": 0.8,
	"base": Color("#8f8a84"), "dark": Color("#5d5952"), "light": Color("#b3aca2"),
	"dust": Color("#9a958e"),
	"pieces": 8, "piece_w": Vector2(6.0, 11.0), "piece_h": Vector2(6.0, 10.0),
	"speed": Vector2(0.7, 1.9), "spin": 0.09, "life": Vector2(120.0, 190.0),
	"sound": "crumble", "shake": 8.0, "sparks": 0,
}
static var METAL := {
	"id": "metal", "name": "металл",
	"hp": 110.0, "bullet": 0.5, "blast": 1.35,
	"base": Color("#6e7b8a"), "dark": Color("#47525d"), "light": Color("#93a2b0"),
	"dust": Color("#7d8894"),
	"pieces": 7, "piece_w": Vector2(9.0, 16.0), "piece_h": Vector2(2.0, 3.0),
	"speed": Vector2(1.4, 3.0), "spin": 0.3, "life": Vector2(100.0, 160.0),
	"sound": "clang", "shake": 5.0, "sparks": 7,
}
static var ADOBE := {
	"id": "adobe", "name": "саман",
	"hp": 55.0, "bullet": 1.05, "blast": 1.3,
	"base": Color("#c9a56a"), "dark": Color("#a3814f"), "light": Color("#e0c088"),
	"dust": Color("#cbb083"),
	"pieces": 10, "piece_w": Vector2(5.0, 8.0), "piece_h": Vector2(4.0, 7.0),
	"speed": Vector2(1.3, 2.9), "spin": 0.2, "life": Vector2(85.0, 145.0),
	"sound": "crumble", "shake": 4.0, "sparks": 0,
}

static var BY_VARIANT := [CONCRETE, BRICK, METAL, WOOD, CONCRETE]

static func variant_at(r: int, c: int) -> int:
	return int(Rng.hash01(r * 73856093 + c, 1337) * 5.0)

static func at(r: int, c: int, tile: int = Cfg.T_BRICK) -> Dictionary:
	if tile == Cfg.T_ADOBE:
		return ADOBE
	return BY_VARIANT[variant_at(r, c) % BY_VARIANT.size()]

static func resist(mat: Dictionary, source: String) -> float:
	return float(mat["blast"]) if source == "blast" else float(mat["bullet"])
