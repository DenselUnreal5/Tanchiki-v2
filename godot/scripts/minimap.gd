# ============================================================================
# minimap.gd — миникарта одного игрока.
#
# Статичная часть карты кэшируется в текстуру и перерисовывается только когда
# карта действительно изменилась (map.version). Врагов видно лишь по прямой
# видимости, а перк «Тень» убирает танк с чужой миникарты.
# ============================================================================
class_name Minimap
extends Control

var world: World = null
var player: PlayerState = null

var _cache: ImageTexture = null
var _cache_version := -1
var _image: Image = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or player == null:
		return
	var w := size.x
	var h := size.y

	if _cache_version != world.map.version:
		_render_cache()
		_cache_version = world.map.version

	draw_rect(Rect2(Vector2.ZERO, size), Color("#0a0a0a"))
	if _cache != null:
		draw_texture_rect(_cache, Rect2(Vector2.ZERO, size), false)

	var sx := w / world.map.width
	var sy := h / world.map.height

	# Аптечки.
	for p in world.pickups:
		if p.active:
			draw_rect(Rect2(p.x * sx - 1, p.y * sy - 1, 2, 2), Color.WHITE)

	# Флаги.
	for flag in world.flags:
		var c: Color = Cfg.flag_player if flag.team == "player" else Cfg.flag_enemy
		draw_rect(Rect2(flag.x * sx - 2, flag.y * sy - 2, 4, 4), c)

	# База «Обороны».
	if world.base != null:
		draw_rect(Rect2(world.base["x"] * sx - 3, world.base["y"] * sy - 3, 6, 6), Color("#7abf6a"))

	var viewer := player.tank

	for tank in world.tanks:
		if not tank.alive:
			continue
		var is_viewer: bool = tank == viewer
		var hostile := world.are_hostile(viewer, tank) if viewer != null else true

		# «Тень» скрывает танк с чужой миникарты.
		if not is_viewer and tank.shadow_timer > 0 and hostile:
			continue

		# Врагов видно только по прямой видимости.
		if hostile and viewer != null:
			if not world.map.has_line_of_sight(viewer.x, viewer.y, tank.x, tank.y):
				continue

		var palette := Cfg.team_palette(tank.color_key)
		var col: Color = Color.WHITE if is_viewer else palette["body"]
		var s := 4.0 if (is_viewer or tank.is_player_controlled) else 3.0
		draw_rect(Rect2(tank.x * sx - s * 0.5, tank.y * sy - s * 0.5, s, s), col)

	_draw_shot_pings(sx, sy, viewer)

	# Рамка области просмотра.
	var vp := player.viewport
	draw_rect(Rect2(
		(player.camera.x - vp.size.x * 0.5) * sx,
		(player.camera.y - vp.size.y * 0.5) * sy,
		vp.size.x * sx, vp.size.y * sy),
		Color(0.47, 0.86, 0.47, 0.7), false, 1.0)

## Отметки услышанных выстрелов — перк «Острый слух».
##
## Без перка отметок нет вовсе: иначе миникарта показывала бы всех стреляющих
## всем и обесценила бы и прямую видимость, и «Тень». Точка гаснет за 2.5 с,
## поэтому она говорит «там только что стреляли», а не «там стоит враг».
func _draw_shot_pings(sx: float, sy: float, viewer) -> void:
	if viewer == null or not viewer.alive:
		return
	var hearing: float = float(viewer.mods.get("hearingMult", 1.0))
	if hearing <= 1.0:
		return
	for ping in world.shot_pings:
		var age: int = world.tick - int(ping["tick"])
		if age < 0 or age > World.PING_LIFE:
			continue
		if String(ping["team"]) == viewer.team:
			continue
		var reach: float = float(ping["reach"]) * hearing
		var dx: float = float(ping["x"]) - viewer.x
		var dy: float = float(ping["y"]) - viewer.y
		if dx * dx + dy * dy > reach * reach:
			continue
		var fade := 1.0 - float(age) / float(World.PING_LIFE)
		var px: float = float(ping["x"]) * sx
		var py: float = float(ping["y"]) * sy
		var col := Color(1.0, 0.85, 0.35, 0.85 * fade)
		draw_arc(Vector2(px, py), 2.0 + 4.0 * (1.0 - fade), 0.0, TAU, 12, col, 1.0)
		draw_rect(Rect2(px - 1.0, py - 1.0, 2.0, 2.0), col)

func _render_cache() -> void:
	var map := world.map
	if _image == null or _image.get_width() != map.cols or _image.get_height() != map.rows:
		_image = Image.create(map.cols, map.rows, false, Image.FORMAT_RGBA8)
	# Земля на миникарте берётся у локации и притемняется: миникарта должна
	# читаться как та же карта, только мельче.
	var loc := Locations.get_location(String(world.level.get("location", Locations.CITY)))
	_image.fill(Color(loc["ground"]).darkened(0.35))
	for r in map.rows:
		for c in map.cols:
			var tile := map.get_tile(r, c)
			if tile == Cfg.T_EMPTY:
				continue
			var col := Color.TRANSPARENT
			match tile:
				Cfg.T_WALL:
					col = Color("#707070")
				Cfg.T_BRICK:
					col = Color("#8a8278")
				Cfg.T_WATER:
					col = Color("#2b3a8f")
				Cfg.T_SAND:
					col = Color("#c9b878")
				Cfg.T_ROAD:
					col = Color("#3a3b40")
				Cfg.T_BRIDGE:
					col = Color("#7a6a50")
				Cfg.T_GRASS:
					col = Color("#3d5c33")
				Cfg.T_DUNE:
					col = Color("#bfa967")
				Cfg.T_QUICKSAND:
					col = Color("#7d6a45")
				Cfg.T_TREE:
					col = Color("#245a33")
				Cfg.T_BASE_P:
					col = Cfg.base_p
				Cfg.T_BASE_E:
					col = Cfg.base_e
				_:
					continue
			_image.set_pixel(c, r, col)
	if _cache == null:
		_cache = ImageTexture.create_from_image(_image)
	else:
		_cache.update(_image)
