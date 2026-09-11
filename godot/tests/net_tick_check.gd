# ============================================================================
# net_tick_check.gd — Net.current_tick: растёт строго физическим тиком,
# никогда не откатывается и не обнуляется, TTL ввода считается по нему.
#
# Без сети и без main.tscn — автозагрузка Net уже поднята средой, этого
# достаточно.
#
# Запуск:
#   godot --headless --path godot tests/net_tick_check.tscn
# ============================================================================
extends Node

var failures := 0

func _ready() -> void:
	await _check_grows_with_physics_frames()
	_check_survives_leave()
	_check_command_ttl()

	print("=== ПРОВЕРКА СЕТЕВОГО ТИКА ЗАВЕРШЕНА, проблем: %d ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Ждём сигнал physics_frame N раз — он бьёт раз на каждый _physics_process,
## поэтому это надёжнее часов настенных: не зависит от того, насколько
## загружена машина между кадрами. Допуск в 1 кадр — между моментом снятия
## "before" и первым сигналом порядок «кто раньше» не гарантирован.
func _check_grows_with_physics_frames() -> void:
	var before := Net.current_tick
	const WAIT_FRAMES := 10
	for i in WAIT_FRAMES:
		await get_tree().physics_frame
	var after := Net.current_tick
	_check(after - before >= WAIT_FRAMES - 1,
		"current_tick вырос примерно на %d физ. кадров (было %d, стало %d)"
			% [WAIT_FRAMES, before, after])

## leave() чистит кучу сетевого состояния, но current_tick — часы процесса,
## а не партии или подключения: их сбрасывать нельзя.
func _check_survives_leave() -> void:
	var before := Net.current_tick
	Net.leave()
	Net.leave()
	var after := Net.current_tick
	_check(after >= before, "current_tick не падает и не обнуляется в leave()")

## TTL ввода (COMMAND_TTL_TICKS) должен считаться по current_tick, а не по
## настенным часам — подставляем "at" вручную, без реальной сети.
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
