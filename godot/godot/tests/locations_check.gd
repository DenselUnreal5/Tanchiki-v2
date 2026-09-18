# ============================================================================
# locations_check.gd — проверка описаний локаций.
#
# Локация — это только данные (locations.gd): набор правил для общего
# конвейера генерации. Ошибка в этих данных ничем себя не выдаёт до самой
# партии — карта соберётся, но погода уйдёт в несуществующее условие, музыка
# не найдёт папку, а район с нулевым весом не выпадет ни разу.
#
# Тест проходит по каждой записи Locations.ORDER и сверяет: музыкальная папка
# есть на диске; каждое погодное условие известно WeatherSystem; тайлы земли
# и дворов проезжаемы; веса районов ссылаются на существующие районы и в
# сумме больше нуля; палитра и цвет взвеси заданы.
#
# Полноту карт (связность, переправы, проходимость) считает map_check —
# он и так идёт по Locations.ORDER, поэтому новые локации попадают под него
# автоматически.
#
# Запуск:
#   godot --headless --path godot res://tests/locations_check.tscn
# ============================================================================
extends Node

var failures := 0

func _ready() -> void:
	await get_tree().process_frame

	print("локация    районы                          погода                     дорога")
	for id in Locations.ORDER:
		_check(Locations.LIST.has(id), "%s: есть запись в LIST" % id)
		if not Locations.LIST.has(id):
			continue
		var loc: Dictionary = Locations.LIST[id]
		_check(String(loc.get("id", "")) == id, "%s: поле id совпадает с ключом" % id)

		# --- музыка ---
		var music := String(loc.get("music", ""))
		_check(music != "", "%s: задана папка музыки" % id)
		_check(DirAccess.dir_exists_absolute("res://music/" + music),
			"%s: папка музыки res://music/%s есть на диске" % [id, music])

		# --- погода ---
		var wx: Array = loc.get("weather", [])
		_check(not wx.is_empty(), "%s: список погоды не пуст" % id)
		for w in wx:
			_check(WeatherSystem.TYPES.has(w),
				"%s: условие «%s» известно WeatherSystem" % [id, w])

		# --- тайлы покрытия ---
		var gt: int = int(loc.get("ground_tile", -1))
		var yt: int = int(loc.get("yard_tile", -1))
		_check(GameMap.is_drivable_tile(gt), "%s: ground_tile проезжаем" % id)
		_check(GameMap.is_drivable_tile(yt), "%s: yard_tile проезжаем" % id)

		# --- районы ---
		var districts: Dictionary = loc.get("districts", {})
		var sum := 0
		for k in districts.keys():
			_check(MapPlan.DISTRICTS.has(k),
				"%s: район «%s» есть в MapPlan.DISTRICTS" % [id, k])
			sum += int(districts[k])
		_check(sum > 0, "%s: сумма весов районов больше нуля" % id)

		# --- палитра и прочее ---
		_check(loc.has("fog_tint"), "%s: задан цвет взвеси" % id)
		_check(loc.has("ground") and loc.has("ground_alt"), "%s: задан цвет земли" % id)
		_check(int(loc.get("block_min", 0)) <= int(loc.get("block_max", 0)),
			"%s: block_min <= block_max" % id)
		_check(float(loc.get("river", 0.0)) >= 0.0, "%s: river >= 0" % id)
		_check(int(loc.get("oases", 0)) >= 0, "%s: oases >= 0" % id)

		# --- строка таблицы ---
		var dstr := ""
		for k in districts.keys():
			dstr += "%s%d " % [String(k).substr(0, 4), int(districts[k])]
		print("  %-9s %-31s %-26s %s" % [
			id, dstr.strip_edges(), str(wx), String(loc.get("road_kind", "?"))])

	# resolve() должен возвращать явный id как есть, а «auto»/мусор — жребием.
	var rng := Rng.new(1)
	for id in Locations.ORDER:
		_check(Locations.resolve(id, rng) == id, "resolve(«%s») возвращает его же" % id)
	_check(Locations.LIST.has(Locations.resolve("auto", rng)),
		"resolve(«auto») даёт существующую локацию")

	print("проблем: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  ПРОВАЛ: %s" % what)
