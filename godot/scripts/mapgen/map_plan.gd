class_name MapPlan
extends RefCounted

const RANK_ARTERIAL := 0
const RANK_STREET := 1

const ARTERIAL_W := 4
const STREET_W_NARROW := 2
const STREET_W_WIDE := 3

const ARTERIAL_GAP := 26
const MIN_WAVE_SEGMENT := 5

const DISTRICTS := {
	"downtown":     {"id": "downtown", "weight": 3},
	"residential":  {"id": "residential", "weight": 4},
	"industrial":   {"id": "industrial", "weight": 2},
	"park":         {"id": "park", "weight": 2},
	"adobe_village": {"id": "adobe_village", "weight": 0},
}

static func build(rng: Rng, cols: int, rows: int, loc: Dictionary) -> Dictionary:
	var bmin: int = int(loc.get("block_min", 9))
	var bmax: int = int(loc.get("block_max", 14))
	var arterials: bool = bool(loc.get("arterials", true))
	var v := _axis(rng, cols, bmin, bmax, arterials, loc)
	var h := _axis(rng, rows, maxi(4, bmin - 2), maxi(6, bmax - 3), arterials, loc)
	if bool(loc.get("wave_streets", false)):
		_apply_wave(rng, v, _crossing_marks(h, rows), loc)
		_apply_wave(rng, h, _crossing_marks(v, cols), loc)
	var seeds := _district_seeds(rng, cols, rows, loc.get("districts", {}))
	var blocks := _blocks(v, h, cols, rows, seeds)
	var circles := _circles(rng, v, h) if bool(loc.get("circles", true)) else []
	var links := _links(rng, v, h, cols, rows, loc)
	return {"v": v, "h": h, "blocks": blocks, "circles": circles,
		"seeds": seeds, "links": links}

## Позиции пересечений с перпендикулярной осью плюс границы карты — волна
## на каждой улице обязана быть ровно нулевой в этих точках, иначе
## перекрёстки/круги ломаются (см. wave_offset/_apply_wave).
static func _crossing_marks(other_axis: Array, size: int) -> Array:
	var marks := [1]
	for st in other_axis:
		marks.append(int(st["pos"]) + int(st["w"]) / 2)
	marks.append(size - 2)
	marks.sort()
	return marks

## Независимая полу-синусоида на каждом отрезке между соседними марками —
## sin(0)=sin(PI)=0, поэтому смещение всегда ровно нулевое на границах
## отрезка (на каждом перекрёстке и у стены карты). Амплитуда считается от
## длины конкретного отрезка, а не абсолютной константой, чтобы волна
## никогда не дотягивалась до соседней улицы.
static func _apply_wave(rng: Rng, streets: Array, marks: Array, loc: Dictionary) -> void:
	var amp_street: float = float(loc.get("street_wave_amp_max", 2.0))
	var amp_arterial: float = float(loc.get("arterial_wave_amp_max", 1.0))
	var wave_chance: float = float(loc.get("wave_chance", 0.6))
	for st in streets:
		var segs := []
		for i in range(marks.size() - 1):
			var t0: int = int(marks[i])
			var t1: int = int(marks[i + 1])
			var len_t := t1 - t0
			if len_t < MIN_WAVE_SEGMENT or rng.nextf() >= wave_chance:
				continue
			var amp_max: float = amp_arterial if int(st["rank"]) == RANK_ARTERIAL else amp_street
			var amp := clampi(int(float(len_t) * 0.22), 1, int(amp_max))
			var dir := 1 if rng.nextf() < 0.5 else -1
			segs.append({"t0": t0, "t1": t1, "amp": amp, "dir": dir})
		st["wave"] = segs

## Смещение волнистой улицы в точке t (0, если вне волнового сегмента или
## волна не включена для локации). Чистая функция — используется и при
## покраске (RoadNet), и при подгонке перемычек (_links) под тот же изгиб.
static func wave_offset(st: Dictionary, t: int) -> int:
	var segs: Array = st.get("wave", [])
	for seg in segs:
		var t0: int = int(seg["t0"])
		var t1: int = int(seg["t1"])
		if t < t0 or t > t1:
			continue
		var phase := PI * float(t - t0) / float(t1 - t0)
		return int(round(sin(phase) * float(seg["amp"]) * float(seg["dir"])))
	return 0

static func _axis(rng: Rng, size: int, block_min: int, block_max: int,
		with_arterials: bool = true, loc: Dictionary = {}) -> Array:
	var out := []
	var art_w: int = int(loc.get("arterial_w", ARTERIAL_W))
	var w_narrow: int = int(loc.get("street_w", STREET_W_NARROW))
	var w_wide: int = int(loc.get("street_w_wide", STREET_W_WIDE))

	var arterials := []
	if with_arterials:
		var first := int(size * (0.28 + rng.nextf() * 0.16))
		arterials.append(first)
		if size >= ARTERIAL_GAP * 2 + 10:
			var second := int(size * (0.66 + rng.nextf() * 0.14))
			if absi(second - first) >= ARTERIAL_GAP:
				arterials.append(second)
	for pos in arterials:
		if pos > 2 and pos + art_w < size - 2:
			out.append({"pos": pos, "w": art_w, "rank": RANK_ARTERIAL})

	var p := 3 + int(rng.nextf() * 3.0)
	while p < size - 5:
		var w := w_wide if rng.nextf() < 0.22 else w_narrow
		var clash := false
		for a in arterials:
			if absi(p - a) < art_w + 3:
				clash = true
				break
		if not clash:
			out.append({"pos": p, "w": w, "rank": RANK_STREET})
		p += w + block_min + int(rng.nextf() * float(block_max - block_min + 1))

	out.sort_custom(func(a, b): return int(a["pos"]) < int(b["pos"]))
	return out

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
	var vi: Dictionary = va[int(rng.nextf() * float(va.size())) % va.size()]
	var hi: Dictionary = ha[int(rng.nextf() * float(ha.size())) % ha.size()]
	out.append({
		"r": int(hi["pos"]) + ARTERIAL_W / 2,
		"c": int(vi["pos"]) + ARTERIAL_W / 2,
		"radius": 6,
	})
	return out

static func _links(rng: Rng, v: Array, h: Array, cols: int, rows: int,
		loc: Dictionary) -> Array:
	var out := []
	var chance := float(loc.get("link_chance", 0.0))
	if chance <= 0.0:
		return out
	var w: int = maxi(1, int(loc.get("street_w", STREET_W_NARROW)))

	var row_gaps := gaps(h, rows)
	for i in range(v.size() - 1):
		var a: Dictionary = v[i]
		var b: Dictionary = v[i + 1]
		var c0: int = int(a["pos"]) + int(a["w"])
		var c1: int = int(b["pos"]) - 1
		if c1 - c0 < 3:
			continue
		for g in row_gaps:
			if rng.nextf() >= chance:
				continue
			var r0: int = int(g[0])
			var r1: int = int(g[1])
			if r1 - r0 < w + 2:
				continue
			var rr: int = r0 + 1 + int(rng.nextf() * float(r1 - r0 - w))
			var wc0: int = c0 + wave_offset(a, rr)
			var wc1: int = c1 + wave_offset(b, rr)
			out.append({"r0": rr, "r1": rr + w - 1, "c0": wc0, "c1": wc1})

	var col_gaps := gaps(v, cols)
	for i in range(h.size() - 1):
		var a: Dictionary = h[i]
		var b: Dictionary = h[i + 1]
		var r0: int = int(a["pos"]) + int(a["w"])
		var r1: int = int(b["pos"]) - 1
		if r1 - r0 < 3:
			continue
		for g in col_gaps:
			if rng.nextf() >= chance:
				continue
			var c0: int = int(g[0])
			var c1: int = int(g[1])
			if c1 - c0 < w + 2:
				continue
			var cc: int = c0 + 1 + int(rng.nextf() * float(c1 - c0 - w))
			var wr0: int = r0 + wave_offset(a, cc)
			var wr1: int = r1 + wave_offset(b, cc)
			out.append({"r0": wr0, "r1": wr1, "c0": cc, "c1": cc + w - 1})

	return out
