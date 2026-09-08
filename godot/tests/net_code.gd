# ============================================================================
# net_code.gd — лобби: код, готовность гостей, разбор ссылки «Join Game».
#
# Путь через Steam (createLobby/requestLobbyList/приглашения) headless не
# проверить — нужен запущенный клиент Steam. Здесь только та логика, что от
# Steam не зависит.
#
# Запуск:
#   godot --headless --path godot tests/net_code.tscn
# ============================================================================
extends Node

var failures := 0

func _ready() -> void:
	_check_is_code()
	_check_gen_code()
	_check_guests_ready()
	_check_connect_lobby()

	print("=== ПРОВЕРКА КОДА ЛОББИ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Формат кода: ровно четыре десятичные цифры.
func _check_is_code() -> void:
	for good in ["1000", "9999", "1234", "0000"]:
		_check(Net.is_code(good), "«%s» — годный код" % good)
	for bad in ["", "12", "12345", "12a4", "abcd", " 123", "1 23"]:
		_check(not Net.is_code(bad), "«%s» — негодный код" % bad)

## Генератор всегда даёт четыре цифры в диапазоне 1000–9999.
func _check_gen_code() -> void:
	var ok := true
	var lo := 9999
	var hi := 1000
	for i in range(2000):
		var code: String = Net._gen_code()
		if not Net.is_code(code):
			ok = false
			break
		var n := int(code)
		if n < 1000 or n > 9999:
			ok = false
			break
		lo = mini(lo, n)
		hi = maxi(hi, n)
	_check(ok, "_gen_code() всегда four-значный 1000–9999")
	_check(hi - lo > 1000, "_gen_code() покрывает диапазон (разброс %d)" % (hi - lo))

## all_guests_ready(): нужен хост, хотя бы один гость и готовность всех гостей.
func _check_guests_ready() -> void:
	var role0 := Net.role
	var lobby0 := Net.lobby.duplicate(true)

	Net.role = ""
	Net.lobby = {}
	_check(not Net.all_guests_ready(), "офлайн — гости не готовы")

	Net.role = "host"
	Net.lobby = {1: {"name": "H"}}
	_check(not Net.all_guests_ready(), "хост один — стартовать некому")

	Net.lobby = {1: {"name": "H"}, 2: {"name": "G", "ready": false}}
	_check(not Net.all_guests_ready(), "гость не нажал «Готов»")

	Net.lobby = {1: {"name": "H"}, 2: {"name": "G", "ready": true}}
	_check(Net.all_guests_ready(), "единственный гость готов")

	Net.lobby = {1: {"name": "H"}, 2: {"ready": true}, 3: {"ready": false}}
	_check(not Net.all_guests_ready(), "один из гостей не готов")

	Net.role = role0
	Net.lobby = lobby0

## «+connect_lobby <id>» из аргументов запуска. Без него — 0 (обычный старт),
## и никакого автоподключения не затевается.
func _check_connect_lobby() -> void:
	_check(Net._parse_connect_lobby() == 0, "без «+connect_lobby» автоджойна нет")
	_check(Net.pending_invite.is_empty(), "на старте нет висящего приглашения")
	Net.accept_pending_invite()  # пусто — просто не должно падать
	_check(Net.role == "" and Net.lobby_pending == "", "accept без приглашения — no-op")

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
