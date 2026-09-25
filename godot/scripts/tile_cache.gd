class_name TileCache
extends Node

## Кэш статичных тайлов карты, разбитый на чанки.
##
## Раньше вся карта (~8160 тайлов) запекалась одним TileBakeView в один
## огромный SubViewport, и любое изменение карты — снесли дом, свалили
## дерево, затопило клетку в «Царе горы» — заново прогоняло GDScript-
## отрисовку ВСЕЙ карты: 80–150 мс фриза на каждое разрушение (в hot seat
## вдвое больше — у каждого вида был свой кэш).
##
## Теперь карта нарезана на чанки CHUNK×CHUNK тайлов, у каждого свой
## маленький SubViewport, который перерисовывается только когда чанк
## «испачкан». Чанк рисует свои тайлы плюс по клетке соседей сверху,
## слева и справа (обрезка — границей вьюпорта): тени, трещины и разметка
## вылезают на соседние клетки, и так порядок наложения внутри чанка
## остаётся тем же, что в старом проходе по всей карте.
##
## Что пачкает чанк — журнал GameMap.changes: смена тайла пачкает чанки в
## радиусе 3 клеток (рисование тайла смотрит на соседей до ±2, плюс
## вылезание на клетку), урон — в радиусе 1. Видимые игрокам чанки
## (с запасом в чанк) перерисовываются сразу, остальные — в фоне, в
## пределах бюджета времени на кадр. Один кэш на матч общий для всех видов.

const CHUNK := 8
const BUDGET_MS := 3.0
const SNOW_EPS := 0.03
## Запас вокруг экрана. Чанки в экране (+ этот запас) пекутся сразу,
## остальные — в фоне, ближние к камере первыми, так что к моменту, когда
## чанк въезжает в кадр, он обычно уже готов.
const VIEW_MARGIN := Cfg.TILE

## Бит «не срочно» в маске грязного чанка: перепекание из-за снега идёт в
## фоне даже для видимых чанков.
const LAZY := 1

var world: World = null
## Игроки, чьи камеры определяют «видимые» чанки (PlayerState).
var players: Array = []

var _master: TileBakeView
var _vps: Array = []
var _views: Array = []
var _texs: Array = []
var _rects: Array = []
var _baked: PackedByteArray = PackedByteArray()
var _ccols := 0
var _crows := 0

## Грязные чанки: индекс -> 0 (срочно) или LAZY.
var _dirty := {}
var _seen_changes := 0
var _seen_epoch := -1
var _baked_snow := -1.0
var _cost_us := 700.0
var _built := false
var _first_request_frame := -1
var _drawn_once := false
var _settle_frames := 0

func _ready() -> void:
	if world != null:
		_build()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_master):
		_master.free()

func _build() -> void:
	var map := world.map
	_ccols = int(ceil(float(map.cols) / CHUNK))
	_crows = int(ceil(float(map.rows) / CHUNK))

	# «Мастер» один раз строит тяжёлые ленивые кэши (классы дорог, полосы,
	# фонари, параметры локации) — чанки берут готовые, а не пересчитывают
	# их каждый по-своему. В дерево он не добавляется и ничего не рисует.
	_master = TileBakeView.new()
	_master.world = world
	_master._read_location()
	_master._build_road_class()
	_master._build_lamps()
	_baked_snow = _current_snow()

	_baked.resize(_ccols * _crows)
	_vps.resize(_ccols * _crows)
	_views.resize(_ccols * _crows)
	_texs.resize(_ccols * _crows)
	for cr in _crows:
		for cc in _ccols:
			var r0 := cr * CHUNK
			var c0 := cc * CHUNK
			var r1 := mini(map.rows - 1, r0 + CHUNK - 1)
			var c1 := mini(map.cols - 1, c0 + CHUNK - 1)
			_rects.append(Rect2(c0 * Cfg.TILE, r0 * Cfg.TILE,
				(c1 - c0 + 1) * Cfg.TILE, (r1 - r0 + 1) * Cfg.TILE))

	_seen_changes = map.changes.size()
	_seen_epoch = map.changes_epoch
	for i in _rects.size():
		_dirty[i] = 0
	_built = true

## Вьюпорт чанка заводится при первом запекании, а не все сразу: ~135
## SubViewport-ов на старте стоили бы лишних десятков миллисекунд.
func _ensure_chunk(idx: int) -> void:
	if _vps[idx] != null:
		return
	var rect: Rect2 = _rects[idx]
	var vp := SubViewport.new()
	vp.size = Vector2i(int(rect.size.x), int(rect.size.y))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)

	var v := TileBakeView.new()
	v.world = world
	v.c0 = int(rect.position.x) / Cfg.TILE
	v.r0 = int(rect.position.y) / Cfg.TILE
	v.c1 = int(rect.end.x) / Cfg.TILE - 1
	v.r1 = int(rect.end.y) / Cfg.TILE - 1
	v.cache = self
	v.bake_snow = _baked_snow
	v.share_caches_from(_master)
	vp.add_child(v)

	_vps[idx] = vp
	_views[idx] = v
	_texs[idx] = vp.get_texture()

## Рисует запечённые чанки, пересекающие rect, на canvas (вызывать из
## _draw этого canvas, в координатах карты).
func draw_visible(canvas: CanvasItem, rect: Rect2) -> void:
	if not _built:
		return
	var cc0 := maxi(0, int(floor(rect.position.x / (CHUNK * Cfg.TILE))))
	var cc1 := mini(_ccols - 1, int(floor(rect.end.x / (CHUNK * Cfg.TILE))))
	var cr0 := maxi(0, int(floor(rect.position.y / (CHUNK * Cfg.TILE))))
	var cr1 := mini(_crows - 1, int(floor(rect.end.y / (CHUNK * Cfg.TILE))))
	for cr in range(cr0, cr1 + 1):
		for cc in range(cc0, cc1 + 1):
			var i := cr * _ccols + cc
			if _baked[i] != 0:
				canvas.draw_texture_rect(_texs[i], _rects[i], false)

## Всё, что видно игрокам, уже запечено и отрисовано — экран загрузки
## может уходить.
func visible_ready() -> bool:
	return _drawn_once and _settle_frames == 0 and not _has_urgent_visible()

func report_cost(usec: int) -> void:
	# Скользящее среднее цены одного чанка — по нему считаем, сколько
	# фоновых чанков влезает в бюджет кадра.
	_cost_us = lerpf(_cost_us, float(usec), 0.2)

func _process(_delta: float) -> void:
	if not _built or world == null:
		return
	if not _drawn_once and _first_request_frame >= 0 \
			and Engine.get_process_frames() > _first_request_frame:
		_drawn_once = true
	if _settle_frames > 0:
		_settle_frames -= 1
	_collect_map_changes()
	_collect_snow()
	if _dirty.is_empty():
		return

	var views := _player_views()
	var picked := []
	var background := []
	for idx in _dirty.keys():
		if int(_dirty[idx]) & LAZY == 0 and _is_visible(idx, views):
			picked.append(idx)
		else:
			background.append(idx)
	var urgent_count := picked.size()
	var spent := _cost_us * picked.size()
	if not background.is_empty():
		var budget_us := BUDGET_MS * 1000.0
		background.sort_custom(func(a, b): return _dist2(a, views) < _dist2(b, views))
		for idx in background:
			if spent > 0.0 and spent + _cost_us > budget_us:
				break
			spent += _cost_us
			picked.append(idx)

	for idx in picked:
		_dirty.erase(idx)
		_ensure_chunk(idx)
		var v: TileBakeView = _views[idx]
		v.bake_snow = _baked_snow
		v.queue_redraw()
		(_vps[idx] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
		_baked[idx] = 1
	if not picked.is_empty() and _first_request_frame < 0:
		_first_request_frame = Engine.get_process_frames()
	if urgent_count > 0:
		# Срочные (видимые) чанки реально нарисуются в конце этого кадра.
		_settle_frames = 2

func _collect_map_changes() -> void:
	var map := world.map
	if map.changes_epoch != _seen_epoch:
		_seen_epoch = map.changes_epoch
		_seen_changes = map.changes.size()
		for i in _rects.size():
			_dirty[i] = 0
		return
	var n := map.changes.size()
	if n == _seen_changes:
		return
	for k in range(_seen_changes, n):
		var e: int = map.changes[k]
		if e >= 0:
			_mark_tiles(e / map.cols, e % map.cols, 3)
		else:
			var i := -e - 1
			_mark_tiles(i / map.cols, i % map.cols, 1)
	_seen_changes = n

func _mark_tiles(r: int, c: int, radius: int) -> void:
	var cr0 := maxi(0, r - radius) / CHUNK
	var cr1 := mini(_crows - 1, (r + radius) / CHUNK)
	var cc0 := maxi(0, c - radius) / CHUNK
	var cc1 := mini(_ccols - 1, (c + radius) / CHUNK)
	for cr in range(cr0, cr1 + 1):
		for cc in range(cc0, cc1 + 1):
			_dirty[cr * _ccols + cc] = 0

## Снег меняет цвет земли/дорог. Раньше он попадал в кэш только при
## случайном перезапекании; теперь, когда снег заметно сменился, вся карта
## плавно перепекается в фоне.
func _collect_snow() -> void:
	var s := _current_snow()
	if absf(s - _baked_snow) < SNOW_EPS:
		return
	_baked_snow = s
	for i in _rects.size():
		if not _dirty.has(i):
			_dirty[i] = LAZY

func _current_snow() -> float:
	if world.weather == null:
		return 0.0
	return clampf(world.weather.snow * Sets.weather_scale(), 0.0, 1.0) * 0.55

func _player_views() -> Array:
	var out := []
	for p in players:
		if p == null:
			continue
		var size: Vector2 = p.viewport.size
		if size.x <= 0.0 or size.y <= 0.0:
			size = Vector2(1280, 720)
		out.append(Rect2(p.camera - size * 0.5, size).grow(VIEW_MARGIN))
	return out

func _is_visible(idx: int, views: Array) -> bool:
	if views.is_empty():
		return true
	var rect: Rect2 = _rects[idx]
	for v in views:
		if (v as Rect2).intersects(rect):
			return true
	return false

func _has_urgent_visible() -> bool:
	var views := _player_views()
	for idx in _dirty.keys():
		if int(_dirty[idx]) & LAZY == 0 and _is_visible(idx, views):
			return true
	return false

func _dist2(idx: int, views: Array) -> float:
	var center: Vector2 = (_rects[idx] as Rect2).get_center()
	if views.is_empty():
		return 0.0
	var best := INF
	for v in views:
		best = minf(best, center.distance_squared_to((v as Rect2).get_center()))
	return best
