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

	# Колокол обязан делить петлю нацело: иначе на стыке петли интервал
	# между ударами будет не 10 секунд, и это слышно на каждом обороте.
	var bar := 60.0 / Mus.MENU_BPM * 4.0
	var period := bar * float(Mus.BELL_EVERY_BARS)
	var loop_len := bar * float(Mus.MENU_BARS)
	_check(absf(period - 10.0) < 0.001, "колокол бьёт раз в %.3f с" % period)
	_check(absf(fmod(loop_len, period)) < 0.001,
		"петля %.3f с делится на период колокола нацело" % loop_len)

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["level"] = 1
	game.start_match()
	await _frames(4)
	# Тема боя называется по локации, а не «combat» вообще: у пустоши
	# и джунглей свои папки. Проверяем именно совпадение с картой —
	# несовпадение означало бы, что игрок слышит чужую землю.
	var loc := String(game.world.level.get("location", Locations.CITY))
	var want := Locations.music_of(loc)
	_check(Mus._current == want,
		"в бою играет музыка локации: %s -> «%s» (играет «%s»)" % [loc, want, Mus._current])

	# Старт партии сразу открывает выбор перка — это и есть проверяемый случай.
	_check(game.state == "perk", "после старта открыт выбор перка")
	# Раньше здесь музыка вставала на паузу. Теперь она обязана продолжать
	# играть, только тише: пауза на несколько секунд звучала как обрыв.
	_check(not _active().stream_paused, "на выборе перка музыка не останавливается")
	var pos_before := _active().get_playback_position()
	await _frames(20)
	_check(_active().get_playback_position() > pos_before,
		"на выборе перка трек идёт дальше (%.2f -> %.2f с)"
			% [pos_before, _active().get_playback_position()])
	# Громкость: −3.1 дБ, то есть амплитуда 0.7 от полной — «на 30% тише».
	# Приглушение живёт на шине, а не на плеере: кроссфейд твинит громкость
	# самого плеера и затирал бы его.
	var bus := AudioServer.get_bus_index("Music")
	var bus_db := AudioServer.get_bus_volume_db(bus)
	_check(absf(bus_db - Mus.PERK_DUCK_DB) < 0.01,
		"на выборе перка громкость %.1f дБ (ждали %.1f)" % [bus_db, Mus.PERK_DUCK_DB])
	var quiet := db_to_linear(bus_db)
	_check(absf(quiet - 0.7) < 0.01,
		"это ровно 0.70 от полной громкости (получилось %.2f)" % quiet)

	var pos_ducked := _active().get_playback_position()
	game._on_perk_chosen(game.perk_player, "")
	await _frames(4)
	while game.state == "perk":
		game._on_perk_chosen(game.perk_player, "")
		await _frames(2)
	_check(not _active().stream_paused, "после выбора музыка продолжается")
	var bus_after := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	_check(absf(bus_after) < 0.01,
		"после выбора громкость вернулась к полной (%.1f дБ)" % bus_after)
	# Позиция не сбросилась: трек именно продолжился, а не начался заново.
	_check(_active().get_playback_position() >= pos_ducked - 0.05,
		"трек продолжился с того же места (%.2f -> %.2f с)"
			% [pos_ducked, _active().get_playback_position()])

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
