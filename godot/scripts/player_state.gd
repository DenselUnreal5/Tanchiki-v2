# ============================================================================
# player_state.gd — управляемый человеком игрок.
#
# Здесь живёт всё, что относится к конкретному человеку: набор перков,
# внутрипартийный уровень и опыт, счёт, серии убийств, камера и область
# просмотра. Второй игрок в «горячем стуле» полностью независим от первого.
# ============================================================================
class_name PlayerState
extends RefCounted

var index: int
var name: String
var color_key: String
var scheme                      # Ctl.MouseAimScheme | Ctl.KeyboardAimScheme
## Сетевой номер соединения: 0 — локальная игра, 1 — хост, дальше клиенты.
var peer_id := 0

var tank: Tank = null

## Постоянные улучшения профиля (гараж), применяются к танку при спавне.
var upgrade_mods := {}
## Экипированная косметика: {hull, track, turret}.
var cosmetics := {}

## Экипированные перки. Танк держит ссылку на этот же массив.
var perk_ids: Array = []

var session_xp := 0
var session_level := 1
## Сколько раз ещё нужно показать выбор перка.
var pending_level_ups := 0

var score := 0
var kills := 0
var deaths := 0
var captures := 0
var damage_dealt := 0.0

## Метки времени убийств для челленджа «5 убийств за 10 секунд».
var kill_ticks: Array = []
## Серия убийств без полученного урона.
var clean_streak := 0

var camera := Vector2.ZERO
var viewport := Rect2(0, 0, 0, 0)

## Ссылка на карту мира — камере нужны её размеры. Ставится World.
var map: GameMap = null

## Таймер вспышки при получении урона, тиков.
var damage_flash := 0
## Тряска экрана только для этого игрока.
var shake := 0.0

func _init(index_: int, name_: String, color_key_: String, scheme_) -> void:
	index = index_
	name = name_
	color_key = color_key_
	scheme = scheme_

# ------------------------------------------------------------------ перки
func has_perk(id: String) -> bool:
	return perk_ids.has(id)

## Экипирует перк. При переполнении вытесняет самый старый.
func equip_perk(id: String) -> bool:
	if has_perk(id):
		return false
	perk_ids.append(id)
	while perk_ids.size() > Cfg.MAX_EQUIPPED_PERKS:
		perk_ids.pop_front()
	if tank != null:
		tank.recompute()
	return true

func unequip_perk(id: String) -> bool:
	var i := perk_ids.find(id)
	if i == -1:
		return false
	perk_ids.remove_at(i)
	if tank != null:
		tank.recompute()
	return true

## Сбрасывает всё, что относится к одной партии.
func reset_for_match() -> void:
	perk_ids.clear()
	upgrade_mods = {}
	session_xp = 0
	session_level = 1
	pending_level_ups = 0
	score = 0
	kills = 0
	deaths = 0
	captures = 0
	damage_dealt = 0.0
	kill_ticks.clear()
	clean_streak = 0
	damage_flash = 0
	shake = 0.0
	tank = null

# ------------------------------------------------------------------ опыт
func xp_to_next_level() -> int:
	return Cfg.xp_for_session_level(session_level)

## @return сколько уровней получено
func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	session_xp += amount
	var gained := 0
	var guard := 0
	while session_xp >= xp_to_next_level() and guard < 100:
		guard += 1
		session_xp -= xp_to_next_level()
		session_level += 1
		pending_level_ups += 1
		gained += 1
	return gained

# ------------------------------------------------------------------ ввод
## Вызывается танком каждый тик.
func control(t: Tank, world) -> void:
	scheme.apply(t, self, world)

## Радиус подбора аптечек с учётом перка «Магнит».
var pickup_radius: float:
	get:
		var mult: float = float(tank.mods["pickupRadiusMult"]) if tank != null else 1.0
		return Cfg.PICKUP_R_MAGNET if mult > 1.0 else Cfg.PICKUP_R

# ------------------------------------------------------------------ камера
## Держит камеру на танке, аккуратно обрабатывая случай, когда карта меньше
## области просмотра.
func update_camera() -> void:
	var w := viewport.size.x
	var h := viewport.size.y
	var map_w := map.width if map != null else float(Cfg.MAP_W)
	var map_h := map.height if map != null else float(Cfg.MAP_H)
	if tank != null:
		# Танк мёртв — камера остаётся на месте гибели.
		camera.x = tank.x
		camera.y = tank.y
	camera.x = map_w / 2.0 if map_w <= w else clampf(camera.x, w / 2.0, map_w - w / 2.0)
	camera.y = map_h / 2.0 if map_h <= h else clampf(camera.y, h / 2.0, map_h - h / 2.0)

## Переводит точку экрана в мировые координаты для этого игрока.
func screen_to_world(screen_x: float, screen_y: float) -> Vector2:
	return Vector2(
		screen_x - viewport.position.x - viewport.size.x / 2.0 + camera.x,
		screen_y - viewport.position.y - viewport.size.y / 2.0 + camera.y)

## Попадает ли точка экрана в область просмотра этого игрока.
func contains_screen_point(sx: float, sy: float) -> bool:
	return viewport.has_point(Vector2(sx, sy))

func tick() -> void:
	if damage_flash > 0:
		damage_flash -= 1
	if shake > 0.0:
		shake -= 1.0
