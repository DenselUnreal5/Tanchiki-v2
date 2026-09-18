# ============================================================================
# version_check.gd — версия сборки задана и не разъехалась.
#
# Номер версии живёт в трёх местах: project.godot, свойства .exe и надпись
# в меню. Разойтись им нельзя: отчёт игрока привязывается к тому, что он
# видит на экране, а разбирается по тому, что записано в сборке.
#
# Запуск:
#   godot --headless --path godot tests/version_check.tscn
# ============================================================================
extends Node

var failures := 0

func _ready() -> void:
	var ver := String(ProjectSettings.get_setting("application/config/version", ""))
	print("версия в project.godot: «%s»" % ver)
	_check(ver != "", "версия задана")

	# Формат «числа через точку»: по нему сравнивают сборки между собой.
	var parts := ver.split(".")
	var numeric := parts.size() >= 2
	for p in parts:
		if not p.is_valid_int():
			numeric = false
	_check(numeric, "формат версии пригоден для сравнения (%s)" % ver)

	# То же число обязано попасть в свойства .exe.
	var cfg := ConfigFile.new()
	var err := cfg.load("res://export_presets.cfg")
	if err != OK:
		_check(false, "export_presets.cfg не читается")
	else:
		for section in cfg.get_sections():
			if not section.ends_with(".options"):
				continue
			if not cfg.has_section_key(section, "application/file_version"):
				continue
			var fv := String(cfg.get_value(section, "application/file_version", ""))
			_check(fv == ver,
				"%s: версия в сборке «%s» совпадает с project.godot" % [section, fv])

	print("=== ПРОВЕРКА ВЕРСИИ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
