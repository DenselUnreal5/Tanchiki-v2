extends Node

var failures := 0

func _ready() -> void:
	await _check_grows_with_physics_frames()
	_check_survives_leave()
	_check_command_ttl()

	print("=== ПРОВЕРКА СЕТЕВОГО ТИКА ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check_grows_with_physics_frames() -> void:
	var before := Net.current_tick
	const WAIT_FRAMES := 10
	for i in WAIT_FRAMES:
		await get_tree().physics_frame
	var after := Net.current_tick
	_check(after - before >= WAIT_FRAMES - 1,
		"current_tick вырос примерно на %d физ. кадров (было %d, стало %d)"
			% [WAIT_FRAMES, before, after])

func _check_survives_leave() -> void:
	var before := Net.current_tick
	Net.leave()
	Net.leave()
	var after := Net.current_tick
	_check(after >= before, "current_tick не падает и не обнуляется в leave()")

func _check_command_ttl() -> void:
	var saved: Dictionary = Net._commands.duplicate()

	Net._commands[999] = {"at": Net.current_tick - Net.COMMAND_TTL_TICKS - 1, "mx": 0.0}
	_check(Net.command_of(999).is_empty(), "устаревший ввод (за пределами TTL) отброшен")

	Net._commands[999] = {"at": Net.current_tick, "mx": 0.0}
	_check(not Net.command_of(999).is_empty(), "свежий ввод (только что) не отброшен")

	Net._commands = saved

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)
