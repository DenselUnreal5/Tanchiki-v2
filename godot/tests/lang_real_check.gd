extends Node

var failures := 0

const CODES := ["fr", "es"]

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _placeholders(s: String) -> Array:
	var re := RegEx.new()
	re.compile("\\{[A-Za-z_0-9]+\\}|%[-0-9.]*[sdf]|%%")
	var out := []
	for m in re.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out

func _ready() -> void:
	await get_tree().process_frame
	var cyr := RegEx.new()
	cyr.compile("[А-Яа-яЁё]")
	var saved: String = I18n.lang
	for code in CODES:
		print("[%s]" % code)
		_check(I18n.is_available(code), "пакет «%s» найден в lang/" % code)
		if not I18n.is_available(code):
			continue
		var strings: Dictionary = I18n.packs[code]["strings"]
		var missing := []
		var extra := []
		for k in I18n.EN.keys():
			if not strings.has(k):
				missing.append(k)
		for k in strings.keys():
			if not I18n.EN.has(k):
				extra.append(k)
		_check(missing.is_empty(), "в пакете есть все ключи английского (не хватает %d %s)" % [missing.size(), str(missing.slice(0, 5))])
		_check(extra.is_empty(), "в пакете нет лишних ключей (лишних %d %s)" % [extra.size(), str(extra.slice(0, 5))])
		var bad_vars := []
		var bad_cyr := []
		var empty := []
		var untouched := 0
		var too_long := []
		for k in I18n.EN.keys():
			if not strings.has(k):
				continue
			var tv: String = String(strings[k])
			var ev: String = String(I18n.EN[k])
			if _placeholders(ev) != _placeholders(tv):
				bad_vars.append(k)
			if cyr.search(tv) != null and not String(k).begins_with("menu.lang."):
				bad_cyr.append(k)
			if tv.strip_edges() == "":
				empty.append(k)
			if tv == ev and ev.length() > 12 and not String(k).begins_with("menu.lang."):
				untouched += 1
			if ev.length() >= 4 and tv.length() > int(ev.length() * 1.6) + 12:
				too_long.append("%s %d→%d" % [k, ev.length(), tv.length()])
		_check(bad_vars.is_empty(), "переменные и форматы совпадают с английским (расхождений %d %s)" % [bad_vars.size(), str(bad_vars.slice(0, 5))])
		_check(bad_cyr.is_empty(), "в переводе нет кириллицы (%d %s)" % [bad_cyr.size(), str(bad_cyr.slice(0, 5))])
		_check(empty.is_empty(), "пустых строк нет")
		_check(untouched <= 15, "непереведённых длинных строк не больше 15 (их %d)" % untouched)
		print("  заметка: заметно длиннее английского (>1.6×): %d %s" % [too_long.size(), str(too_long.slice(0, 6))])
		I18n.lang = code
		_check(I18n.t("menu.start", {}, "ИГРАТЬ") == String(strings["menu.start"]), "язык переключается, строка из пакета")
		_check(I18n.dn({"id": "rapid_fire", "name": "Скорострельность"}, "name", "perk") == String(strings["perk.rapid_fire.name"]), "имя предмета из пакета")
		_check(I18n.bot_names().size() >= 20 and I18n.bot_names() != I18n.EN_BOT_NAMES, "у пакета свой список имён ботов")
		_check(I18n.lang_name(code) != code, "у пакета есть собственное название языка (%s)" % I18n.lang_name(code))
	I18n.lang = "fr"
	_check(I18n.plural(0, "a", "b", "c") == "a" and I18n.plural(1, "a", "b", "c") == "a" and I18n.plural(2, "a", "b", "c") == "c", "французское множественное число: 0 и 1 — единственное")
	I18n.lang = "es"
	_check(I18n.plural(1, "a", "b", "c") == "a" and I18n.plural(0, "a", "b", "c") == "c", "испанское множественное число")
	I18n.lang = saved
	print("=== ПРОВЕРКА НАСТОЯЩИХ ЯЗЫКОВЫХ ПАКЕТОВ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)
