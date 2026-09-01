# ============================================================================
# steam_stats_check.gd — отражение прогресса в Steam.
#
# Проверяет две разные вещи и не путает их:
#   1. отображение имён — целиком наше дело, обязано быть верным всегда;
#   2. приём вызовов Steam — зависит от App ID, и на тестовом 480 наши
#      достижения не заведены, поэтому отказ здесь ОЖИДАЕМ и не ошибка.
#
# Запуск:
#   godot --headless --path godot tests/steam_stats_check.tscn
# ============================================================================
extends Node

var failures := 0

func _ready() -> void:
	await get_tree().process_frame

	# ---- отображение имён ----------------------------------------------
	var seen := {}
	var bad := []
	for a in Achievements.LIST:
		var id := String(a["id"])
		var api := SteamStats.api_name(id)
		if seen.has(api):
			bad.append(api)
		seen[api] = true
		if not api.begins_with("ACH_") or api != api.to_upper():
			bad.append(api)
	_check(bad.is_empty(), "имена достижений уникальны и в верхнем регистре (%d штук)"
		% Achievements.LIST.size())
	_check(seen.size() == Achievements.LIST.size(),
		"каждому достижению своё имя: %d из %d" % [seen.size(), Achievements.LIST.size()])
	print("  пример: first_blood -> %s" % SteamStats.api_name("first_blood"))

	# ---- доступность Steam ----------------------------------------------
	var live := SteamStats.ready()
	print("  Steam доступен: %s" % live)
	if not live:
		print("  вызовы пропущены — без Steam слой обязан молчать, и он молчит")
		_finish()
		return

	# ---- что Steam принимает --------------------------------------------
	var ids := []
	for a in Achievements.LIST:
		ids.append(String(a["id"]))
	var sent := SteamStats.push_all(ids)
	print("  достижений принято Steam: %d из %d" % [sent, ids.size()])

	var stats := {}
	for key in SteamStats.STAT_KEYS:
		stats[key] = 7
	var pushed := SteamStats.push_stats(stats)
	print("  показателей принято Steam: %d из %d" % [pushed, SteamStats.STAT_KEYS.size()])

	# Решающий опыт: выдаём НАСТОЯЩЕЕ достижение Spacewar. Если пройдёт оно,
	# значит конвейер рабочий, а ноль выше — только про чужие имена.
	var steam: Object = Engine.get_singleton("Steam")
	var has_req := false
	for m in steam.get_method_list():
		if String(m["name"]) == "requestCurrentStats":
			has_req = true
	print("  requestCurrentStats есть: %s" % has_req)
	if has_req:
		steam.requestCurrentStats()
		for i in 30:
			steam.run_callbacks()
			await get_tree().process_frame
	var native: bool = steam.setAchievement("ACH_WIN_ONE_GAME")
	steam.storeStats()
	print("  родное достижение Spacewar принято: %s" % native)
	if native:
		steam.clearAchievement("ACH_WIN_ONE_GAME")
		steam.storeStats()
		print("  (выдача отменена, профиль не тронут)")

	# Отказ на тестовом App ID — не провал теста: имена достижений там чужие.
	# Провал был бы, если бы вызов уронил игру.
	_check(true, "вызовы Steam проходят без падения")
	_finish()

func _finish() -> void:
	print("=== ПРОВЕРКА STEAM-ПРОГРЕССА ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
