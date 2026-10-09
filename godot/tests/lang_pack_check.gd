extends Node

var failures := 0

func _ready() -> void:
	await get_tree().process_frame
	var saved_lang: String = I18n.lang
	DirAccess.make_dir_recursive_absolute("user://lang")
	var path := "user://lang/zz_check.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"name": "Тестовый язык",
		"strings": {
			"pause.title": "PAUZA-ZZ",
			"killcam.title": "Replay-ZZ {name} {src}",
			"perk.double_shot.name": "Dvoynoy-ZZ",
		},
	}))
	f.close()
	var broken := FileAccess.open("user://lang/zz_broken.json", FileAccess.WRITE)
	broken.store_string("{not json")
	broken.close()

	I18n.reload_packs()
	_check(I18n.is_available("zz_check"), "пакет из user://lang найден")
	_check(not I18n.is_available("zz_broken"), "повреждённый пакет пропущен")
	var names := []
	for entry in I18n.available_languages():
		names.append(String(entry["code"]))
	_check(names.slice(0, 2) == ["ru", "en"] and names.has("zz_check"), "список языков: %s" % str(names))
	_check(I18n.lang_name("zz_check") == "Тестовый язык", "название языка берётся из пакета")

	I18n.lang = "zz_check"
	_check(I18n.t("pause.title", {}, "ПАУЗА") == "PAUZA-ZZ", "строка из пакета")
	_check(I18n.t("killcam.title", {"name": "Bot", "src": "x"}, "RU") == "Replay-ZZ Bot x", "подстановки работают в пакете")
	_check(I18n.t("pause.resume", {}, "Продолжить") == "Resume", "нет в пакете: берётся английский")
	_check(I18n.t("no.such.key", {}, "Запасной") == "Запасной", "нет нигде: берётся запасной текст")
	_check(I18n.dn({"id": "double_shot", "name": "Двойной выстрел"}, "name", "perk") == "Dvoynoy-ZZ", "имя предмета из пакета")
	_check(I18n.dn({"id": "rapid_fire", "name": "Скорострельность"}, "name", "perk") != "Скорострельность", "имя предмета: запасной английский")
	_check(I18n.plural(1, "one", "few", "many") == "one" and I18n.plural(2, "one", "few", "many") == "many",
		"множественное число по английскому правилу")
	_check(I18n.bot_names().size() > 0, "боты получают английские имена")

	I18n.lang = "ru"
	_check(I18n.t("pause.title", {}, "ПАУЗА") == "ПАУЗА", "русский всегда берёт запасной текст")
	I18n.lang = "en"
	_check(I18n.t("pause.title", {}, "ПАУЗА") == "PAUSE", "английский берёт словарь EN")

	I18n.set_lang("zz_check")
	_check(I18n.lang == "zz_check", "set_lang принимает язык пакета")
	I18n.toggle_lang()
	_check(I18n.lang != "zz_check", "toggle_lang идёт по кругу")
	I18n.set_lang("unknown_code")
	_check(I18n.lang == "ru", "неизвестный язык откатывается на русский")

	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://lang/zz_broken.json")
	I18n.reload_packs()
	_check(not I18n.is_available("zz_check"), "после удаления пакет исчезает")
	I18n.set_lang(saved_lang)
	print("=== ПРОВЕРКА ЯЗЫКОВЫХ ПАКЕТОВ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(ok: bool, what: String) -> bool:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
	return ok
