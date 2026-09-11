# ============================================================================
# cli.gd — разбор аргументов командной строки для двух режимов запуска:
# выделенный сервер (--server) и клиент, сразу подключающийся (--connect=).
#
# Читаем OS.get_cmdline_args() — это вся командная строка запуска, а не
# OS.get_cmdline_user_args() (только то, что после отдельного «--»): обычным
# флагам вида --server/--port=8124 отдельный «--» перед ними не нужен, так
# проще при запуске с ярлыка или из systemd-юнита.
#
# Значения режима/сложности/погоды/времени суток/локации сверяются со
# списком допустимых и при опечатке отбрасываются с предупреждением, а не
# летят как есть в ui.settings — иначе рассинхрон с Cfg.MODES/Cfg.DIFFICULTY
# уронил бы игру при первом же обращении к настройкам боя.
# ============================================================================
class_name Cli
extends RefCounted

## "Уровень не задан флагом" — отдельно от -1, который сам по себе означает
## «случайный уровень» (см. group-level в ui_root.gd) и обязан доходить как
## есть, а не молча теряться наравне с действительно отсутствующим флагом.
const UNSET_LEVEL := -999

const _VALID_WEATHER := ["auto", "clear", "rain", "fog", "snow", "storm"]
const _VALID_DAYTIME := ["auto", "day", "dusk", "night", "midnight"]
const _VALID_LOCATION := ["auto", "city", "dust", "jungle", "frost", "exclusion", "shore"]
const _VALID_LEVEL := [1, 2, 3, 4, 5, -1]

## Разбирает аргументы запуска в словарь с разумными дефолтами.
## Не заданный режим (ни --server, ни --connect=) — обычный запуск, ничего
## не меняется: вызывающая сторона просто проверяет out["server"] /
## out["connect_host"] != "".
static func parse(args: PackedStringArray = OS.get_cmdline_args()) -> Dictionary:
	var out := {
		"server": false,
		"port": 8124,
		"players": 2,
		"mode": "",
		"difficulty": "",
		"level": UNSET_LEVEL,
		"weather": "",
		"daytime": "",
		"location": "",
		"connect_host": "",
		"connect_port": 8124,
	}
	for a in args:
		if a == "--server":
			out["server"] = true
		elif a.begins_with("--port="):
			out["port"] = int(_value(a, "--port="))
		elif a.begins_with("--players="):
			out["players"] = int(_value(a, "--players="))
		elif a.begins_with("--mode="):
			out["mode"] = _pick("--mode", _value(a, "--mode="), Cfg.MODES.keys())
		elif a.begins_with("--difficulty="):
			out["difficulty"] = _pick("--difficulty", _value(a, "--difficulty="), Cfg.DIFFICULTY.keys())
		elif a.begins_with("--level="):
			var raw := _value(a, "--level=")
			var lvl := int(raw)
			if _VALID_LEVEL.has(lvl):
				out["level"] = lvl
			else:
				push_warning("[cli] непонятный --level «%s», использую уровень по умолчанию" % raw)
		elif a.begins_with("--weather="):
			out["weather"] = _pick("--weather", _value(a, "--weather="), _VALID_WEATHER)
		elif a.begins_with("--daytime="):
			out["daytime"] = _pick("--daytime", _value(a, "--daytime="), _VALID_DAYTIME)
		elif a.begins_with("--location="):
			out["location"] = _pick("--location", _value(a, "--location="), _VALID_LOCATION)
		elif a.begins_with("--connect="):
			_parse_connect(_value(a, "--connect="), out)
	return out

static func _value(a: String, prefix: String) -> String:
	return a.substr(prefix.length())

## Значение из allow-листа — как есть; иначе пустая строка (вызывающая
## сторона это читает как «флаг не задан» и оставляет дефолт настроек боя),
## с предупреждением в лог — опечатка в флаге не должна молча подменяться.
static func _pick(flag: String, value: String, allowed: Array) -> String:
	if allowed.has(value):
		return value
	push_warning("[cli] непонятный %s «%s», использую значение по умолчанию" % [flag, value])
	return ""

## "host:port" -> connect_host/connect_port; просто "host" оставляет порт
## дефолтным. IPv6 в скобочной нотации ([::1]:8124) не разбираем — для
## прямого подключения к своему серверу это не понадобилось.
static func _parse_connect(addr: String, out: Dictionary) -> void:
	var idx := addr.rfind(":")
	if idx > 0 and idx < addr.length() - 1 and addr.substr(idx + 1).is_valid_int():
		out["connect_host"] = addr.substr(0, idx)
		out["connect_port"] = int(addr.substr(idx + 1))
	else:
		out["connect_host"] = addr
