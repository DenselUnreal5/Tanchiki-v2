extends Node

func _ready() -> void:
	var used := {}
	_scan("res://scripts", used)

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

func _scan(dir_path: String, out: Dictionary) -> void:
	var re := RegEx.new()
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
