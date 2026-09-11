# ============================================================================
# cli_check.gd — разбор аргументов командной строки (Cli.parse), без сети.
#
# Запуск:
#   godot --headless --path godot tests/cli_check.tscn
# ============================================================================
extends Node

var failures := 0

func _ready() -> void:
	_check_defaults()
	_check_server_flags()
	_check_bad_values_fall_back()
	_check_connect()

	print("=== ПРОВЕРКА CLI ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Без флагов — обычный запуск: ни сервера, ни автоподключения.
func _check_defaults() -> void:
	var out := Cli.parse(PackedStringArray([]))
	_check(not bool(out["server"]), "без флагов: server=false")
	_check(String(out["connect_host"]) == "", "без флагов: connect_host пуст")
	_check(int(out["level"]) == Cli.UNSET_LEVEL, "без флагов: level не задан")
	_check(String(out["mode"]) == "", "без флагов: mode не задан")

func _check_server_flags() -> void:
	var out := Cli.parse(PackedStringArray([
		"--server", "--port=9000", "--players=3", "--mode=ctf",
		"--difficulty=hard", "--level=-1", "--weather=storm",
		"--daytime=night", "--location=jungle",
	]))
	_check(bool(out["server"]), "--server распознан")
	_check(int(out["port"]) == 9000, "--port=9000 разобран")
	_check(int(out["players"]) == 3, "--players=3 разобран")
	_check(String(out["mode"]) == "ctf", "--mode=ctf разобран")
	_check(String(out["difficulty"]) == "hard", "--difficulty=hard разобран")
	_check(int(out["level"]) == -1, "--level=-1 (случайный) доходит как есть")
	_check(String(out["weather"]) == "storm", "--weather=storm разобран")
	_check(String(out["daytime"]) == "night", "--daytime=night разобран")
	_check(String(out["location"]) == "jungle", "--location=jungle разобран")

## Опечатка в значении не должна ломать разбор — только сбрасывать на дефолт.
func _check_bad_values_fall_back() -> void:
	var out := Cli.parse(PackedStringArray([
		"--mode=zzz", "--difficulty=impossible", "--weather=meteor",
		"--daytime=whenever", "--location=mars", "--level=42",
	]))
	_check(String(out["mode"]) == "", "плохой --mode отброшен")
	_check(String(out["difficulty"]) == "", "плохая --difficulty отброшена")
	_check(String(out["weather"]) == "", "плохая --weather отброшена")
	_check(String(out["daytime"]) == "", "плохой --daytime отброшен")
	_check(String(out["location"]) == "", "плохая --location отброшена")
	_check(int(out["level"]) == Cli.UNSET_LEVEL, "недопустимый --level отброшен")

func _check_connect() -> void:
	var with_port := Cli.parse(PackedStringArray(["--connect=127.0.0.1:9001"]))
	_check(String(with_port["connect_host"]) == "127.0.0.1", "host из --connect с портом")
	_check(int(with_port["connect_port"]) == 9001, "порт из --connect")

	var without_port := Cli.parse(PackedStringArray(["--connect=127.0.0.1"]))
	_check(String(without_port["connect_host"]) == "127.0.0.1", "host из --connect без порта")
	_check(int(without_port["connect_port"]) == 8124, "порт по умолчанию, если не задан")

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
