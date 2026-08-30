# ============================================================================
# music_state.gd — проверка связки музыки с состояниями игры.
#
# Проверяется ровно то, что нельзя услышать в дымовом тесте: какая тема
# играет в меню и в бою, останавливается ли музыка на выборе перка и
# продолжается ли с того же места после него.
# ============================================================================
extends Node

var game: Node
var failures := 0

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(3)

	# Обе темы собираются в фоне: без них проверять нечего.
	var guard := 0
	while (Mus._menu == null or Mus._combat == null) and guard < 2000:
		guard += 1
		await _frames(1)
	_check(Mus._menu != null and Mus._combat != null, "обе темы собраны")

	await _frames(60)
	_check(Mus._current == "menu", "в меню играет тема меню")
	_check(_active().playing, "плеер меню запущен")

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	await _frames(4)
	_check(Mus._current == "combat", "в бою играет боевая тема")

	# Старт партии сразу открывает выбор перка — это и есть проверяемый случай.
	_check(game.state == "perk", "после старта открыт выбор перка")
	_check(_active().stream_paused, "на выборе перка музыка стоит на паузе")
	var pos_before := _active().get_playback_position()

	game._on_perk_chosen(game.perk_player, "")
	await _frames(4)
	while game.state == "perk":
		game._on_perk_chosen(game.perk_player, "")
		await _frames(2)
	_check(not _active().stream_paused, "после выбора музыка продолжается")
	# Позиция не сбросилась: трек именно продолжился, а не начался заново.
	_check(_active().get_playback_position() >= pos_before - 0.05,
		"трек продолжился с того же места (%.2f -> %.2f с)"
			% [pos_before, _active().get_playback_position()])

	game.pause()
	await _frames(2)
	_check(not _active().stream_paused, "в меню паузы музыка не останавливается")
	game.resume()
	await _frames(2)

	game.to_menu()
	await _frames(60)
	_check(Mus._current == "menu", "после боя вернулась тема меню")

	print("=== ПРОВЕРКА МУЗЫКИ ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _active() -> AudioStreamPlayer:
	return Mus._players[Mus._active]

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
