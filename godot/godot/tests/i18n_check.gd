# ============================================================================
# i18n_check.gd — полнота английского перевода.
#
# Пропущенный ключ ничем себя не выдаёт: I18n.t возвращает русский запасной
# текст, интерфейс собирается, ошибок в консоли нет. Игрок просто видит
# русскую надпись в английской игре. Ровно так и случилось с сетевым меню —
# двадцать одна строка и весь селектор локаций остались непереведёнными.
#
# Тест читает исходники, собирает все ключи, которые интерфейс запрашивает,
# и сверяет со словарём EN.
#
# Запуск:
#   godot --headless --path godot tests/i18n_check.tscn
# ============================================================================
extends Node

func _ready() -> void:
	var used := {}
	_scan("res://scripts", used)

	# Часть ключей собирается на лету: I18n.t("cat." + id). Регулярное
	# выражение видит только литеральный кусок, поэтому ключ, кончающийся
	# точкой, — это префикс, и он считается покрытым, если в словаре есть
	# хоть один ключ с таким началом.
	var prefixes := []
	var missing := []
	for key in used.keys():
		if key.ends_with("."):
			prefixes.append(key)
			var found := false
			for have in I18n.EN.keys():
				if String(have).begins_with(key):
					found = true
					break
			if not found:
				missing.append(key + "*")
		elif not I18n.EN.has(key):
			missing.append(key)
	missing.sort()

	print("ключей в интерфейсе: %d, в словаре EN: %d, без перевода: %d"
		% [used.size(), I18n.EN.size(), missing.size()])
	for k in missing:
		print("  БЕЗ ПЕРЕВОДА: %s   (%s)" % [k, used[k]])

	# Обратная проверка: ключи в словаре, которых больше никто не спрашивает.
	# Это не ошибка, но по ним видно, что интерфейс переименовали и забыли.
	var stale := []
	for key in I18n.EN.keys():
		if used.has(key):
			continue
		var by_prefix := false
		for p in prefixes:
			if String(key).begins_with(p):
				by_prefix = true
				break
		if not by_prefix:
			stale.append(key)
	if not stale.is_empty():
		print("не используются (%d): %s" % [stale.size(), str(stale.slice(0, 12))])

	print("=== ПРОВЕРКА ПЕРЕВОДА ЗАВЕРШЕНА, проблем: %d ===" % missing.size())
	get_tree().quit(1 if missing.size() > 0 else 0)

## Собирает ключи из всех вызовов I18n.t в дереве скриптов.
##
## Обход статическими вызовами, а не итератором DirAccess: ручная итерация
## с рекурсией внутри цикла зависала намертво, и тест приходилось снимать
## по таймауту.
func _scan(dir_path: String, out: Dictionary) -> void:
	var re := RegEx.new()
	# Шаблон нарочно без обратных слэшей: в строке GDScript \. и \s — это
	# недопустимые escape-последовательности, и файл не разбирается вовсе.
	# Точка и скобка взяты в классы символов, пробелы перечислены явно.
	re.compile('I18n[.]t[(][ \t\n]*"([^"]+)"')
	var stack := [dir_path]
	var guard := 0
	while not stack.is_empty() and guard < 500:
		guard += 1
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".gd"):
				continue
			var file := FileAccess.open(d + "/" + f, FileAccess.READ)
			if file == null:
				continue
			var text := file.get_as_text()
			file.close()
			for m in re.search_all(text):
				out[m.get_string(1)] = (d + "/" + f).replace("res://scripts/", "")
