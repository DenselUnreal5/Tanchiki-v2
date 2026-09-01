# ============================================================================
# map_plan.gd — ПЛАН города. Ни одного тайла не красит.
#
# Генератор разделён на два этапа: сначала строится план — где проходят
# магистрали и улицы, где кварталы, какого района каждый квартал, где
# кольцевые развязки, — и только потом план красится в тайлы.
#
# Разделение не ради красоты. Раньше всё считалось и красилось вперемешку
# в одной функции на шестьсот строк, и любой вопрос вида «почему этот
# квартал промышленный» требовал читать её целиком. План — это данные,
# которые можно распечатать, посчитать и проверить тестом, не рисуя карту.
#
# Опорой служат референсы городских планов: там видно, что настоящий город
# это не равномерная решётка, а иерархия — две-три широкие магистрали,
# сетка обычных улиц между ними, кольцо на главном перекрёстке и районы,
# каждый со своим характером застройки.
# ============================================================================
class_name MapPlan
extends RefCounted

## Ранг улицы. Магистраль вдвое шире улицы и служит ориентиром: по ней
## видно, где ты находишься, не глядя на миникарту.
const RANK_ARTERIAL := 0
const RANK_STREET := 1

const ARTERIAL_W := 4
const STREET_W_NARROW := 2
const STREET_W_WIDE := 3

## Минимальное расстояние между магистралями, тайлов. Меньше — и они
## перестают читаться как главные.
const ARTERIAL_GAP := 26

## Районы. weight — доля при жеребьёвке опорных точек.
const DISTRICTS := {
	"downtown":    {"id": "downtown", "weight": 3},
	"residential": {"id": "residential", "weight": 4},
	"industrial":  {"id": "industrial", "weight": 2},
	"park":        {"id": "park", "weight": 2},
}

## Строит план города.
##
## @return {v, h, blocks, circles, seeds}
##   v, h    — улицы по осям: {pos, w, rank}
##   blocks  — кварталы: {r0, r1, c0, c1, district}
##   circles — кольцевые развязки: {r, c, radius}
##   seeds   — опорные точки районов: {r, c, type}
## @param loc правила локации (locations.gd): густота сетки, состав районов,
##        бывают ли магистрали и кольца
static func build(rng: Rng, cols: int, rows: int, loc: Dictionary) -> Dictionary:
	var bmin: int = int(loc.get("block_min", 9))
	var bmax: int = int(loc.get("block_max", 14))
	var arterials: bool = bool(loc.get("arterials", true))
	# Поперечные кварталы короче продольных: карта шире, чем выше, и при
	# одинаковом шаге сетка выходила бы вытянутой.
	var v := _axis(rng, cols, bmin, bmax, arterials)
	var h := _axis(rng, rows, maxi(4, bmin - 2), maxi(6, bmax - 3), arterials)
	var seeds := _district_seeds(rng, cols, rows, loc.get("districts", {}))
	var blocks := _blocks(v, h, cols, rows, seeds)
	var circles := _circles(rng, v, h) if bool(loc.get("circles", true)) else []
	return {"v": v, "h": h, "blocks": blocks, "circles": circles, "seeds": seeds}

# ------------------------------------------------------------------ улицы
## Раскладывает улицы вдоль одной оси и назначает им ранг.
##
## Сначала ставятся магистрали — по одной-две на ось, вдали друг от друга.
## Потом между ними обычные улицы, и те, что подошли к магистрали вплотную,
## отбрасываются: две дороги впритык читаются как одна широкая и сбивают
## ощущение иерархии.
##
## В джунглях магистралей не бывает вовсе: там только узкие тропы, и широкая
## четырёхполосная дорога посреди леса читалась бы как ошибка генерации.
static func _axis(rng: Rng, size: int, block_min: int, block_max: int,
		with_arterials: bool = true) -> Array:
	var out := []

	# Магистрали: одна почти всегда, вторая — если карта достаточно длинная.
	var arterials := []
	if with_arterials:
		var first := int(size * (0.28 + rng.nextf() * 0.16))
		arterials.append(first)
		if size >= ARTERIAL_GAP * 2 + 10:
			var second := int(size * (0.66 + rng.nextf() * 0.14))
			if absi(second - first) >= ARTERIAL_GAP:
				arterials.append(second)
	for pos in arterials:
		if pos > 2 and pos + ARTERIAL_W < size - 2:
			out.append({"pos": pos, "w": ARTERIAL_W, "rank": RANK_ARTERIAL})

	# Обычные улицы поверх той же оси.
	var p := 3 + int(rng.nextf() * 3.0)
	while p < size - 5:
		var w := STREET_W_WIDE if rng.nextf() < 0.22 else STREET_W_NARROW
		var clash := false
		for a in arterials:
			if absi(p - a) < ARTERIAL_W + 3:
				clash = true
				break
		if not clash:
			out.append({"pos": p, "w": w, "rank": RANK_STREET})
		p += w + block_min + int(rng.nextf() * float(block_max - block_min + 1))

	out.sort_custom(func(a, b): return int(a["pos"]) < int(b["pos"]))
	return out

## Промежутки между улицами — это и есть кварталы.
static func gaps(streets: Array, size: int) -> Array:
	var out := []
	var prev := 1
	for st in streets:
		var pos: int = int(st["pos"])
		if pos - 1 >= prev:
			out.append([prev, pos - 1])
		prev = pos + int(st["w"])
	if size - 2 >= prev:
		out.append([prev, size - 2])
	return out

# ----------------------------------------------------------------- районы
## Опорные точки районов. Квартал получает тип ближайшей точки — это даёт
## связные зоны вместо чересполосицы, где склад стоит между парком и жильём.
##
## Веса приходят из локации: в пустоши почти всё промзона, в джунглях — парк.
static func _district_seeds(rng: Rng, cols: int, rows: int,
		weights: Dictionary = {}) -> Array:
	var count := 4 if cols < 80 else 6
	var mix := {}
	for k in DISTRICTS.keys():
		mix[k] = int(weights.get(k, DISTRICTS[k]["weight"]))
	var total := 0
	for k in mix.keys():
		total += int(mix[k])
	if total <= 0:
		mix = {"residential": 1}
		total = 1

	var out := []
	for i in count:
		var roll := rng.nextf() * float(total)
		var pick := "residential"
		for k in mix.keys():
			roll -= float(mix[k])
			if roll <= 0.0:
				pick = String(k)
				break
		out.append({
			"r": int(rng.nextf() * float(rows)),
			"c": int(rng.nextf() * float(cols)),
			"type": pick,
		})
	# Центр карты всегда самый плотный из доступных локации районов: там
	# сходятся все режимы, и застройка в середине даёт бой в упор, а не
	# перестрелку через пустырь. В джунглях «плотное» — это парк с деревьями.
	var core := "downtown"
	if int(mix.get("downtown", 0)) <= 0:
		core = "park" if int(mix.get("park", 0)) > 0 else "residential"
	out.append({"r": rows / 2, "c": cols / 2, "type": core})
	return out

static func _blocks(v: Array, h: Array, cols: int, rows: int, seeds: Array) -> Array:
	var out := []
	for rg in gaps(h, rows):
		for cg in gaps(v, cols):
			var r0: int = int(rg[0])
			var r1: int = int(rg[1])
			var c0: int = int(cg[0])
			var c1: int = int(cg[1])
			out.append({
				"r0": r0, "r1": r1, "c0": c0, "c1": c1,
				"district": district_at(seeds, (r0 + r1) / 2, (c0 + c1) / 2),
			})
	return out

## Ближайшая опорная точка и есть район этой клетки.
static func district_at(seeds: Array, r: int, c: int) -> String:
	var best := "residential"
	var best_d := 1 << 30
	for s in seeds:
		var dr: int = int(s["r"]) - r
		var dc: int = int(s["c"]) - c
		var d := dr * dr + dc * dc
		if d < best_d:
			best_d = d
			best = String(s["type"])
	return best

# ------------------------------------------------------------- развязки
## Кольцевая развязка ставится на пересечении магистралей — это главный
## ориентир карты. Если магистраль одна на ось, кольцо всё равно уместно:
## на референсах кольца стоят именно там, где сходятся крупные дороги.
static func _circles(rng: Rng, v: Array, h: Array) -> Array:
	var va := []
	var ha := []
	for st in v:
		if int(st["rank"]) == RANK_ARTERIAL:
			va.append(st)
	for st in h:
		if int(st["rank"]) == RANK_ARTERIAL:
			ha.append(st)
	if va.is_empty() or ha.is_empty():
		return []

	var out := []
	# Не больше одного кольца на карту: два одинаковых ориентира — это уже
	# ни одного.
	var vi: Dictionary = va[int(rng.nextf() * float(va.size())) % va.size()]
	var hi: Dictionary = ha[int(rng.nextf() * float(ha.size())) % ha.size()]
	out.append({
		"r": int(hi["pos"]) + ARTERIAL_W / 2,
		"c": int(vi["pos"]) + ARTERIAL_W / 2,
		"radius": 6,
	})
	return out
