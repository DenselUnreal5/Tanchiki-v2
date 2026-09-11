# ============================================================================
# net_peer.gd — интеграционная проверка сетевой партии.
#
# Запускается двумя процессами: один хостом, второй клиентом. Один процесс
# тут не годится — высокоуровневая сеть Godot живёт на дереве сцены, и двух
# независимых пиров в одном дереве не сделать.
#
#   godot --headless --path . tests/net_peer.tscn -- host
#   godot --headless --path . tests/net_peer.tscn -- client
#
# Обе стороны печатают отпечаток карты и сводку состояния. Совпадение
# отпечатков доказывает, что карта собралась одинаково по одному seed —
# именно ради этого карта и не передаётся по сети.
# ============================================================================
extends Node

var game: Node
var failures := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var role := String(args[0]) if args.size() > 0 else "host"
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _frames(3)

	if role == "host":
		await _run_host()
	else:
		await _run_client()

	print("=== %s ЗАВЕРШЁН, проблем: %d ===" % [role.to_upper(), failures])
	Net.leave()
	await _frames(2)
	get_tree().quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------- хост
func _run_host() -> void:
	Net.my_name = "Хост"
	_check(Net.host_game(), "порт открыт")
	# Ждём клиента.
	var guard := 0
	while Net.lobby.size() < 2 and guard < 900:
		guard += 1
		await _frames(1)
	_check(Net.lobby.size() >= 2, "клиент подключился (в лобби %d)" % Net.lobby.size())
	if Net.lobby.size() < 2:
		return

	game.ui.settings["mode"] = "ffa"
	game.ui.settings["game_type"] = "single"
	game.ui.settings["difficulty"] = "medium"
	game.ui.settings["level"] = 1
	# Гроза над джунглями: ветер валит деревья (world.gd:_update_treefall),
	# и это мутация карты помимо разрушенных построек. Клиент сам её не
	# считает — только повторяет дельты хоста, — поэтому финальная сверка
	# отпечатков заодно проверяет, что повал доехал один в один.
	game.ui.settings["weather"] = "storm"
	game.ui.settings["location"] = "jungle"

	# Лобби прошло — дальше «Играть» запускает синхронный отсчёт, а не
	# партию напрямую. Отсчёт идёт по реальным секундам (SceneTreeTimer), а
	# безматчевая сцена в headless крутит process_frame гораздо чаще 60 Гц —
	# поэтому ждём по настенным часам, а не по числу кадров.
	Net.host_begin_countdown()
	var cd_started := Time.get_ticks_msec()
	while Net.countdown_left != 0 and Time.get_ticks_msec() - cd_started < 8000:
		await _frames(1)
	_check(Net.countdown_left == 0, "отсчёт хоста дошёл до нуля")
	if Net.countdown_left != 0:
		return

	game.start_match()
	_dismiss_perks()
	_check(game.world != null, "мир создан")
	_check(game.remote_players.size() == 1, "сетевой игрок заведён")

	# Танк сетевого игрока обязан существовать в мире хоста.
	var remote_tank_ok := false
	for t in game.world.tanks:
		if t.owner_peer != 0 and t.owner_peer != multiplayer.get_unique_id():
			remote_tank_ok = true
	_check(remote_tank_ok, "танк клиента есть в мире хоста")

	# Авторитетный спавн игроков обязан реально слать host_tank_spawned, а
	# не молчать из-за того, что _match_active ещё не выставлен (см.
	# Net.begin_match()) — иначе состав долетал бы только оптом, в roster.
	_check(Net.stat_tank_spawn_out >= 2,
		"host_tank_spawned реально ушёл при спавне игроков (%d раз)" % Net.stat_tank_spawn_out)

	# Отпечаток снимается дважды: до боя он проверяет, что карта собралась
	# одинаково по seed, после боя — что разрушения доехали до клиента.
	print("  карта хоста до боя: %s" % _map_hash(game.world.map))
	await _frames(420)
	_check(game.world.tick > 200, "партия крутится (тик %d)" % game.world.tick)
	print("  танков: %d, пуль: %d" % [game.world.tanks.size(), game.world.bullets.size()])

	# Дальше мир замирает: сверять карты в движении бессмысленно — хост
	# уйдёт вперёд на те разрушения, которые клиент ещё не получил.
	game.pause()
	await _frames(60)
	# Последний отпечаток отправляем принудительно: клиент сверит его
	# со своим и, если надо, попросит карту целиком. Мир при этом уже
	# замер, поэтому сверка честная — обе стороны на одном состоянии.
	# Отпечаток замершего мира шлём несколько раз подряд: клиент сверяется
	# по последнему пришедшему, и так он гарантированно попадёт на тот,
	# что снят с уже неподвижной карты.
	print("  карта хоста после боя: %s" % _map_hash(game.world.map))
	for i in 6:
		Net.host_event("mapsum", {"h": game.world.map.checksum()})
		await _frames(30)
	await _frames(120)

# ----------------------------------------------------------------- клиент
func _run_client() -> void:
	Net.my_name = "Клиент"
	_check(Net.join_game("127.0.0.1"), "подключение начато")

	# Лобби видно и хосту, и клиенту — а не только хосту, который сам себя
	# в него сразу заносит. Это и есть проверка «оба видят друг друга».
	var lobby_guard := 0
	while Net.lobby.size() < 2 and lobby_guard < 900:
		lobby_guard += 1
		await _frames(1)
	_check(Net.lobby.size() >= 2, "клиент видит обоих в лобби (у себя %d)" % Net.lobby.size())

	# Хост держит пятисекундный отсчёт перед стартом, а до партии кадры
	# в headless крутятся много чаще 60 Гц — ждём по настенным часам,
	# иначе бюджет кадров кончится раньше, чем реальные пять секунд хоста.
	var wait_started := Time.get_ticks_msec()
	while game.world == null and Time.get_ticks_msec() - wait_started < 12000:
		await _frames(1)
	_check(game.world != null, "хост объявил партию, мир собран")
	if game.world == null:
		return
	_dismiss_perks()

	_check(game.world.puppet, "мир клиента — марионетка (сам ничего не считает)")
	print("  карта клиента до боя: %s" % _map_hash(game.world.map))

	# Предсказание проверяем, пока хост ещё активно шлёт снапшоты — он
	# замирает (game.pause()) ближе к концу теста, и сверка ниже не
	# дождалась бы свежих данных, если бы проверка стояла позже.
	#
	# Ждём не просто появления game.players[0].tank, а первой РЕАЛЬНОЙ
	# сверки (game._last_reconciled_tick > -1): свежесозданный танк на
	# клиенте стартует с x=0,y=0 (net_spawn_puppet не несёт координат —
	# они приходят только со снапшотом), и пока не прошла хотя бы одна
	# _reconcile_local_tank(), координаты не настоящие. Настенные часы —
	# та же причина, что и во всех остальных ожиданиях сети в этом файле.
	var predict_guard_started := Time.get_ticks_msec()
	while (game.players.is_empty() or game.players[0].tank == null
			or game._last_reconciled_tick < 0) and Time.get_ticks_msec() - predict_guard_started < 8000:
		await _frames(1)
	if not game.players.is_empty() and game.players[0].tank != null and game._last_reconciled_tick >= 0:
		await _check_prediction(game.players[0].tank)
	else:
		_check(false, "дождались первой сверки своего танка перед проверкой предсказания")

	await _frames(420)
	# Ждём финальную сверку от замершего хоста. Сравнивать раньше нельзя:
	# хост ушёл бы вперёд на те разрушения, которые к нам ещё не доехали,
	# и тест ловил бы задержку пакета вместо расхождения.
	# Ждём, пока хост замрёт и отстреляется финальными отпечатками.
	await _frames(330)
	print("  карта клиента после боя: %s" % _map_hash(game.world.map))
	print("  сверок карты: %d, расхождений: %d" % [game.net_sums, game.net_desyncs])
	_check(game.net_sums > 0, "сверка отпечатка карты работает")
	# Главная проверка: последняя сверка снята с неподвижной карты у обеих
	# сторон, поэтому отпечатки обязаны совпасть.
	print("  последняя сверка: свой %08x, хоста %08x"
		% [game.net_last_mine, game.net_last_theirs])
	_check(game.net_last_mine == game.net_last_theirs,
		"карта клиента совпала с хостовой")
	_check(game.world.tanks.size() > 0, "состав пришёл: танков %d" % game.world.tanks.size())

	# Состояние должно двигаться: если снапшоты не доходят, координаты
	# останутся нулевыми, а мир — застывшим.
	var moved := false
	for t in game.world.tanks:
		if t.x > 1.0 or t.y > 1.0:
			moved = true
	_check(moved, "танки получили координаты от хоста")

	var mine = null
	for t in game.world.tanks:
		if t.owner_peer == multiplayer.get_unique_id():
			mine = t
	_check(mine != null, "свой танк найден и привязан к камере")
	_check(game.players[0].tank == mine, "HUD и камера смотрят на свой танк")

# ------------------------------------------------------------ предсказание
## Подменяет схему ввода на фиксированную команду и проверяет, что позиция
## своего танка сдвигается СРАЗУ в том же кадре — раньше, чем мог бы дойти
## следующий снапшот хоста (иначе это была бы просто интерполяция, а не
## Tank.predict_move()). Второй шаг — что после сверки с хостом (см.
## game.gd::_reconcile_local_tank) позиция остаётся близкой к авторитетной,
## а не расходится буфером повторов.
func _check_prediction(mine: Tank) -> void:
	var scripted := ScriptedScheme.new()
	game.players[0].scheme = scripted
	var before := Vector2(mine.x, mine.y)
	var tick_before: int = game._last_reconciled_tick
	scripted.cmd = {"mx": 1.0, "my": 0.0, "ax": mine.x + 100.0, "ay": mine.y,
		"fire": false, "mine": false, "dash": false, "airstrike": false, "ability": false}
	# Кадр рендера — не то же самое, что тик симуляции: headless без vsync
	# может прогнать несколько process_frame раньше, чем накопитель
	# _client_frame() дотянет до Cfg.TICK_SEC. Ждём, пока world.tick
	# реально продвинется хотя бы на один тик.
	var tick_before_move: int = game.world.tick
	var tick_guard := 0
	while int(game.world.tick) <= tick_before_move and tick_guard < 60:
		tick_guard += 1
		await _frames(1)
	var delta := Vector2(mine.x, mine.y) - before
	_check(delta.length() > 0.01,
		"предсказание сдвигает свой танк в тот же тик, не дожидаясь снапшота (Δ=%.3f)" % delta.length())

	# Ждём, пока придёт снапшот НОВЕЕ того, что был на момент включения
	# движения, и _reconcile_local_tank() (game.gd) его обработает —
	# только тогда сверка честная: сравниваем предсказанную позицию с
	# хостовой на тик, который уже включает наше движение. Настенные
	# часы, не число кадров — та же ловушка, что и в net_dedicated.gd.
	var wait_started := Time.get_ticks_msec()
	while game._last_reconciled_tick <= tick_before and Time.get_ticks_msec() - wait_started < 8000:
		await _frames(1)
	var last_reconciled: int = game._last_reconciled_tick
	var reconciled := last_reconciled > tick_before
	_check(reconciled, "пришла новая сверка после включения движения")
	if reconciled:
		var auth := Net.latest_snapshot_tank(mine.net_id)
		var err := Vector2(mine.x - float(auth["x"]), mine.y - float(auth["y"])).length()
		_check(err < 40.0,
			"локальная позиция близка к авторитетной после сверки (Δ=%.1f)" % err)
	scripted.cmd = Ctl.empty_command()

## Тестовая заглушка ввода: MouseAimScheme/GamepadScheme читают настоящие
## устройства ОС, недоступные в headless — здесь просто фиксированная
## команда на каждый тик.
class ScriptedScheme extends RefCounted:
	var cmd: Dictionary = {}
	func read_command(_player) -> Dictionary:
		return cmd

# ------------------------------------------------------------------ утилиты
## Отпечаток карты: по нему сверяется, что генератор дал одно и то же.
func _map_hash(map: GameMap) -> String:
	var h := 5381
	for i in map.tiles.size():
		h = ((h * 33) ^ map.tiles[i]) & 0x7FFFFFFF
	return "%dx%d/%08x" % [map.cols, map.rows, h]

func _dismiss_perks() -> void:
	var guard := 0
	while game.state == "perk" and guard < 20:
		guard += 1
		game._on_perk_chosen(game.perk_player, "")

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ок: ", what)
	else:
		failures += 1
		print("  ОШИБКА: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
