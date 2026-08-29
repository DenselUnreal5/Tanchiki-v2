# ============================================================================
# materials.gd — материалы построек: прочность, сопротивление и обломки.
#
# Раньше любой разрушаемый тайл ломался с одного попадания. Теперь у каждого
# здания есть материал, и он определяет сразу три вещи:
#   * сколько урона выдержит постройка;
#   * насколько ей вредны пули и насколько — взрывы (у металла и бетона
#     это разные числа, поэтому против брони выгоднее взрывчатка);
#   * как она разваливается — щепки, кирпичное крошево, бетонные плиты
#     или рваные листы железа с искрами.
#
# Материал не хранится в карте: он выводится из тех же координат, что и
# вариант крыши в отрисовке. Поэтому вид постройки честно говорит игроку
# о её прочности — профнастил и выглядит железным, и держит как железный.
# ============================================================================
class_name Materials
extends RefCounted

## Пуля наносит 20–30 урона, поэтому «прочность» удобно читать в попаданиях.
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
	# Пули железу почти не вредят, зато взрыв рвёт его лучше бетона:
	# против профнастила выгоднее взрывчатка, а не расстрел в упор.
	"hp": 110.0, "bullet": 0.5, "blast": 1.35,
	"base": Color("#6e7b8a"), "dark": Color("#47525d"), "light": Color("#93a2b0"),
	"dust": Color("#7d8894"),
	"pieces": 7, "piece_w": Vector2(9.0, 16.0), "piece_h": Vector2(2.0, 3.0),
	"speed": Vector2(1.4, 3.0), "spin": 0.3, "life": Vector2(100.0, 160.0),
	"sound": "clang", "shake": 5.0, "sparks": 7,
}

## Вариант крыши (0..4) → материал. Порядок совпадает с отрисовкой
## в world_view.gd: бетон, кирпич/гравий, профнастил, дерево, панель.
static var BY_VARIANT := [CONCRETE, BRICK, METAL, WOOD, CONCRETE]

## Вариант постройки по координатам тайла. Тот же хеш, что и в отрисовке,
## поэтому вид и прочность всегда совпадают.
static func variant_at(r: int, c: int) -> int:
	return int(Rng.hash01(r * 73856093 + c, 1337) * 5.0)

static func at(r: int, c: int) -> Dictionary:
	return BY_VARIANT[variant_at(r, c) % BY_VARIANT.size()]

## Множитель урона по источнику: 'blast' — взрывы и мины, остальное — пули.
static func resist(mat: Dictionary, source: String) -> float:
	return float(mat["blast"]) if source == "blast" else float(mat["bullet"])
