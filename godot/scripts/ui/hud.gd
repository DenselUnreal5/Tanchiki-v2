# ============================================================================
# hud.gd — игровой интерфейс поверх мира.
#
# Панель строится по числу игроков и позиционируется внутри их областей
# просмотра: в «горячем стуле» у каждого своя полоска HP, перки, счёт
# и миникарта.
# ============================================================================
class_name Hud
extends Control

const FEED_LIFE := 300  # тиков
const FEED_MAX := 6

## Иконки погодных условий для HUD.
const WEATHER_ICONS := {"clear": "☀️", "rain": "🌧", "fog": "🌫", "storm": "⛈"}

var panels := {}
var feed_entries: Array = []
## Пропорции карты: миникарта под них подстраивается, иначе карты
## разных режимов (CTF заметно меньше и другой формы) выглядят растянутыми.
var _map_aspect := 200.0 / 114.0

var _feed_box: VBoxContainer
var _banner: Label
var _banner_timer := 0
var _scoreboard: PanelContainer
var _scoreboard_body: VBoxContainer
var scoreboard_visible := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_feed_box = UiKit.vbox(3)
	_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed_box)

	_banner = UiKit.label("", 24, Cfg.UI_GOLD, true)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)

	_scoreboard = UiKit.panel()
	_scoreboard.visible = false
	_scoreboard.custom_minimum_size = Vector2(460, 0)
	_scoreboard_body = UiKit.vbox(4)
	_scoreboard.add_child(_scoreboard_body)
	add_child(_scoreboard)

# ------------------------------------------------------------------ сборка
## Пересобирает панели под текущий состав игроков.
func build(players: Array, world: World) -> void:
	for p in panels.values():
		p["root"].queue_free()
	panels.clear()
	_map_aspect = world.map.width / world.map.height

	for player in players:
		var palette := Cfg.team_palette(player.color_key)
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

		# ---- верхняя левая часть: имя, HP ----
		var left := UiKit.vbox(2)
		left.position = Vector2(12, 10)
		left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(left)

		var name_label := UiKit.label(player.name, 12, palette["trim"], true)
		left.add_child(name_label)

		var hp_wrap := Control.new()
		hp_wrap.custom_minimum_size = Vector2(190, 14)
		var hp_bg := ColorRect.new()
		hp_bg.color = Color(0, 0, 0, 0.65)
		hp_bg.size = Vector2(190, 14)
		hp_wrap.add_child(hp_bg)
		var hp_fill := ColorRect.new()
		hp_fill.color = Cfg.UI_ACCENT
		hp_fill.size = Vector2(190, 14)
		hp_wrap.add_child(hp_fill)
		var shield_fill := ColorRect.new()
		shield_fill.color = Cfg.shield
		shield_fill.position = Vector2(0, 10)
		shield_fill.size = Vector2(0, 4)
		hp_wrap.add_child(shield_fill)
		left.add_child(hp_wrap)

		var hp_text := UiKit.label("", 10, Cfg.UI_MUTED)
		left.add_child(hp_text)

		# Строка состояния сети. В одиночной игре скрыта: пустое место
		# в углу экрана — тоже цена.
		var net_label := UiKit.label("", 9, Color("#7fd0ff"))
		net_label.visible = false
		left.add_child(net_label)

		# ---- нагрев ствола ----
		# Узкая полоска прямо под здоровьем: она нужна в те же моменты,
		# что и HP, и разносить их по разным углам экрана нельзя.
		var heat_wrap := Control.new()
		heat_wrap.custom_minimum_size = Vector2(190, 5)
		var heat_bg := ColorRect.new()
		heat_bg.color = Color(0, 0, 0, 0.55)
		heat_bg.size = Vector2(190, 5)
		heat_wrap.add_child(heat_bg)
		var heat_fill := ColorRect.new()
		heat_fill.color = Cfg.UI_WARN
		heat_fill.size = Vector2(0, 5)
		heat_wrap.add_child(heat_fill)
		left.add_child(heat_wrap)

		# ---- верхняя правая часть: счёт, задача, погода ----
		var right := UiKit.vbox(2)
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(right)

		var score := UiKit.label("", 17, Cfg.UI_GOLD)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(score)
		var objective := UiKit.label("", 11, Cfg.UI_TEXT)
		objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(objective)
		var weather_label := UiKit.label("", 11, Color("#aabbdd"))
		weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(weather_label)

		# ---- нижняя часть: опыт и перки ----
		var bottom := UiKit.vbox(4)
		bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bottom)

		var xp_label := UiKit.label("", 10, Cfg.UI_GOLD)
		bottom.add_child(xp_label)
		var xp_wrap := Control.new()
		xp_wrap.custom_minimum_size = Vector2(220, 6)
		var xp_bg := ColorRect.new()
		xp_bg.color = Color(0, 0, 0, 0.65)
		xp_bg.size = Vector2(220, 6)
		xp_wrap.add_child(xp_bg)
		var xp_fill := ColorRect.new()
		xp_fill.color = Cfg.UI_GOLD
		xp_fill.size = Vector2(0, 6)
		xp_wrap.add_child(xp_fill)
		bottom.add_child(xp_wrap)

		# ---- активная способность: иконка, подсказка клавиши и кулдаун ----
		var ability_row := UiKit.hbox(6)
		ability_row.visible = false
		bottom.add_child(ability_row)
		var ability_label := UiKit.label("", 10, Cfg.UI_TEXT)
		ability_row.add_child(ability_label)
		var cd_wrap := Control.new()
		cd_wrap.custom_minimum_size = Vector2(90, 6)
		var cd_bg := ColorRect.new()
		cd_bg.color = Color(0, 0, 0, 0.65)
		cd_bg.size = Vector2(90, 6)
		cd_wrap.add_child(cd_bg)
		var cd_fill := ColorRect.new()
		cd_fill.color = Cfg.UI_ACCENT
		cd_fill.size = Vector2(0, 6)
		cd_wrap.add_child(cd_fill)
		ability_row.add_child(cd_wrap)

		var perks := UiKit.hbox(4)
		bottom.add_child(perks)

		# ---- миникарта ----
		var mm := Minimap.new()
		mm.world = world
		mm.player = player
		root.add_child(mm)

		panels[player.index] = {
			"root": root, "left": left, "right": right, "bottom": bottom,
			"name": name_label, "hp_fill": hp_fill, "hp_bg": hp_bg,
			"shield_fill": shield_fill, "hp_text": hp_text,
			"heat_fill": heat_fill, "heat_wrap": heat_wrap,
			"net": net_label,
			"score": score, "objective": objective, "weather": weather_label,
			"xp_label": xp_label, "xp_fill": xp_fill, "perks": perks,
			"ability_row": ability_row, "ability_label": ability_label,
			"ability_fill": cd_fill,
			"minimap": mm, "last_perks": "",
		}
	layout(players)

## Позиционирует панели по областям просмотра.
func layout(players: Array) -> void:
	var split := players.size() > 1
	for player in players:
		if not panels.has(player.index):
			continue
		var panel: Dictionary = panels[player.index]
		var vp: Rect2 = player.viewport
		var root: Control = panel["root"]
		root.position = vp.position
		root.size = vp.size

		var mm_w := 140.0 if split else 200.0
		var mm_h := roundf(mm_w / maxf(0.2, _map_aspect))
		var mm: Minimap = panel["minimap"]
		mm.position = Vector2(vp.size.x - mm_w - 10.0, 10.0)
		mm.size = Vector2(mm_w, mm_h)

		var right: VBoxContainer = panel["right"]
		right.position = Vector2(vp.size.x - mm_w - 24.0 - 260.0, 10.0)
		right.custom_minimum_size = Vector2(260, 0)
		right.size = Vector2(260, 60)

		var bottom: VBoxContainer = panel["bottom"]
		bottom.position = Vector2(12, vp.size.y - 80.0)

		var hp_w := 150.0 if split else 190.0
		(panel["hp_bg"] as ColorRect).size.x = hp_w
		(panel["hp_fill"] as ColorRect).size.x = hp_w

	# Размер берём у окна: собственный size у Control может быть ещё не пересчитан
	# в тот кадр, когда HUD только собран.
	var screen := get_viewport_rect().size
	_feed_box.position = Vector2(screen.x * 0.5 - 180.0, 132.0 if split else 10.0)
	_feed_box.custom_minimum_size = Vector2(360, 0)
	_banner.position = Vector2(screen.x * 0.5 - 300.0, screen.y * 0.22)
	_banner.size = Vector2(600, 40)
	_scoreboard.position = Vector2(screen.x * 0.5 - 230.0, screen.y * 0.5 - 180.0)

func show_hud() -> void:
	visible = true

func hide_hud() -> void:
	visible = false
	hide_scoreboard()

# ------------------------------------------------------------------ обновление
## Состояние сети: оборот, потери и молчание. Показывается только
## в сетевой партии — и это единственное место, где игрок вообще узнаёт,
## что связь плохая, а не «игра тормозит».
func _update_net(panel: Dictionary) -> void:
	var label: Label = panel["net"]
	if not Net.is_online:
		label.visible = false
		return
	label.visible = true
	var st := Net.stats()
	if Net.role == "host":
		label.text = I18n.t("hud.net.host", {"n": Net.lobby.size() - 1},
			"сеть: хост, игроков рядом %d" % (Net.lobby.size() - 1))
		label.modulate = Color.WHITE
		return

	var lost: int = int(st["snap_lost"])
	var total: int = maxi(1, int(st["snap_in"]) + lost)
	label.text = I18n.t("hud.net.client",
		{"rtt": int(st["rtt"]), "loss": int(round(float(lost) * 100.0 / float(total)))},
		"сеть: %d мс, потерь %d%%" % [int(st["rtt"]),
			int(round(float(lost) * 100.0 / float(total)))])
	# Молчащая сеть подсвечивается: застывшая картинка без объяснения —
	# худшее, что можно показать игроку.
	label.modulate = Cfg.UI_DANGER if _game_stale() else Color.WHITE

func _game_stale() -> bool:
	var g := get_parent()
	while g != null and not g.has_method("net_peer_left"):
		g = g.get_parent()
	return g != null and bool(g.get("net_stale"))

## Индикатор способности. Обновляется каждый кадр, потому что кулдаун —
## единственное в HUD, что меняется непрерывно.
func _update_ability(panel: Dictionary, player) -> void:
	var row: Control = panel["ability_row"]
	var tank = player.tank
	if tank == null or tank.ability_id == "":
		row.visible = false
		return
	row.visible = true

	var ab := Abilities.get_ability(tank.ability_id)
	var label: Label = panel["ability_label"]
	var fill: ColorRect = panel["ability_fill"]
	# Второй игрок сидит на цифровом блоке — у него и подсказка своя.
	var key := "Q" if player.index == 0 else "Num -"
	var icon := String(ab.get("icon", "✦"))
	var name := I18n.dn(ab, "name", "ability")

	if tank.ability_timer > 0:
		label.text = I18n.t("hud.ability.active", {"icon": icon, "name": name},
			"%s %s — работает" % [icon, name])
		label.modulate = Color.WHITE
		fill.size.x = 90.0
	elif tank.ability_cd <= 0:
		label.text = I18n.t("hud.ability.ready", {"icon": icon, "name": name, "key": key},
			"%s %s · [%s] готово" % [icon, name, key])
		label.modulate = Color.WHITE
		fill.size.x = 90.0
	else:
		label.text = I18n.t("hud.ability.cooldown",
			{"icon": icon, "name": name, "sec": "%.1f" % (float(tank.ability_cd) / float(Cfg.TICK_HZ))},
			"%s %s · %.1f с" % [icon, name, float(tank.ability_cd) / float(Cfg.TICK_HZ)])
		label.modulate = Color(1, 1, 1, 0.55)
		fill.size.x = 90.0 * tank.ability_ready
	fill.color = ab.get("color", Cfg.UI_ACCENT)

func update_hud(world: World) -> void:
	for player in world.players:
		if not panels.has(player.index):
			continue
		var panel: Dictionary = panels[player.index]
		var tank: Tank = player.tank
		if tank == null:
			continue

		var hp_ratio := maxf(0.0, tank.hp / tank.max_hp)
		var hp_fill: ColorRect = panel["hp_fill"]
		var hp_full: float = (panel["hp_bg"] as ColorRect).size.x
		hp_fill.size.x = hp_full * hp_ratio
		hp_fill.color = Cfg.UI_ACCENT if hp_ratio > 0.5 else (Cfg.UI_WARN if hp_ratio > 0.25 else Cfg.UI_DANGER)
		var shield: ColorRect = panel["shield_fill"]
		shield.visible = tank.shield_hp > 0.0
		shield.size.x = hp_full * minf(1.0, tank.shield_hp / 30.0)

		var hp_text := "%d / %d HP" % [ceil(tank.hp), int(tank.max_hp)]
		if tank.shield_hp > 0.0:
			hp_text += I18n.t("hud.shield", {"n": int(ceil(tank.shield_hp))},
				" +%d щит" % int(ceil(tank.shield_hp)))
		(panel["hp_text"] as Label).text = hp_text

		(panel["score"] as Label).text = I18n.t("hud.score", {"n": player.score}, "Счёт %d" % player.score)

		var progress := world.progress_for(player)
		var objective: Label = panel["objective"]
		match world.mode:
			"defense":
				var base_hp := int(ceil(float(world.base["hp"]))) if world.base != null else 0
				var left := int(progress["current"])
				var state := "…" if world.wave_state == "delay" else I18n.t("hud.left", {"n": left}, "%d в поле" % left)
				var strike := ""
				# Только первый игрок владеет авиаударом — индикатор у него же.
				if player.index == 0:
					if world.airstrike_cooldown > 0:
						var secs := int(ceil(float(world.airstrike_cooldown) / float(Cfg.TICK_HZ)))
						strike = I18n.t("hud.strikeCd", {"n": secs}, "  ✈ %dс" % secs)
					else:
						strike = I18n.t("hud.strikeReady", {}, "  ✈ ГОТОВ (F)")
				objective.text = I18n.t("hud.wave",
					{"cur": world.wave, "total": Cfg.MODES["defense"]["waves"], "hp": base_hp, "state": state},
					"Волна %d / %d   🏰 %d HP   (%s)" % [world.wave, Cfg.MODES["defense"]["waves"], base_hp, state]) + strike
			"koth":
				var left_ticks := maxi(0, world.time_limit - world.tick)
				var sec := int(ceil(float(left_ticks) / 60.0))
				var time_str := "%d:%02d" % [sec / 60, sec % 60]
				objective.text = I18n.t("hud.alive",
					{"cur": progress["current"], "total": progress["total"], "time": time_str},
					"Выживших %d / %d   ⏱ %s" % [progress["current"], progress["total"], time_str])
			"ffa":
				objective.text = I18n.t("hud.frags",
					{"cur": progress["current"], "target": progress["target"], "deaths": player.deaths},
					"Фраги %d / %d   ✝ %d" % [progress["current"], progress["target"], player.deaths])
			_:
				var txt := I18n.t("hud.flags",
					{"a": world.team_score["player"], "b": world.team_score["enemy"],
						"limit": Cfg.MODES["ctf"]["cap_limit"]},
					"Флаги %d : %d (до %d)" % [world.team_score["player"], world.team_score["enemy"], Cfg.MODES["ctf"]["cap_limit"]])
				if tank.carrying_flag:
					txt += I18n.t("hud.flagYou", {}, "  ⚑ у вас флаг!")
				objective.text = txt

		# Индикатор погоды и времени суток.
		var w := world.weather
		if w != null:
			var icon: String = WEATHER_ICONS.get(w.condition, "🌤")
			(panel["weather"] as Label).text = "%s %s" % [icon, I18n.t("time." + w.time_key, {}, w.time_name)]

		var need: int = player.xp_to_next_level()
		(panel["xp_fill"] as ColorRect).size.x = 220.0 * minf(1.0, float(player.session_xp) / float(need))
		(panel["xp_label"] as Label).text = I18n.t("hud.xp", {
			"lvl": player.session_level, "xp": player.session_xp, "need": need,
			"plvl": Prof.global_level, "pxp": Prof.global_xp, "pneed": Prof.xp_to_next_level(),
		}, "Ур. %d · %d/%d XP   |   Профиль %d · %d/%d" % [
			player.session_level, player.session_xp, need,
			Prof.global_level, Prof.global_xp, Prof.xp_to_next_level()])

		# Нагрев: полоска прячется, пока ствол холодный — в спокойный момент
		# на экране и без неё есть что читать.
		var heat_tank = player.tank
		var heat: float = heat_tank.heat if heat_tank != null else 0.0
		var heat_wrap2: Control = panel["heat_wrap"]
		heat_wrap2.visible = heat > 0.02
		if heat_wrap2.visible:
			var fill: ColorRect = panel["heat_fill"]
			fill.size.x = 190.0 * clampf(heat, 0.0, 1.0)
			if heat_tank != null and heat_tank.overheated:
				# Перегрев мигает: это не «много жара», а «стрелять нельзя».
				var k := 0.5 + 0.5 * sin(float(world.tick) * 0.35)
				fill.color = Color(1.0, 0.35 + 0.25 * k, 0.2)
			else:
				fill.color = Cfg.UI_WARN.lerp(Cfg.UI_DANGER, heat)

		_update_net(panel)

		_update_ability(panel, player)

		# Перки перерисовываем только при изменении набора.
		var key := ",".join(player.perk_ids)
		if key != String(panel["last_perks"]):
			panel["last_perks"] = key
			var box: HBoxContainer = panel["perks"]
			for child in box.get_children():
				child.queue_free()
			for id in player.perk_ids:
				var perk := Perks.get_perk(id)
				var slot := PanelContainer.new()
				var st := UiKit.flat(Color(0, 0, 0, 0.72), Cfg.RADIUS_SM, 1, Cfg.UI_BORDER)
				st.content_margin_left = 7
				st.content_margin_right = 7
				st.content_margin_top = 2
				st.content_margin_bottom = 2
				slot.add_theme_stylebox_override("panel", st)
				slot.add_child(UiKit.label("%s %s" % [Perks.perk_icon(id), I18n.dn(perk, "name", "perk")],
					10, Cfg.UI_GOLD))
				box.add_child(slot)

	_tick_feed()
	if _banner_timer > 0:
		_banner_timer -= 1
		if _banner_timer == 0:
			var tw := create_tween()
			tw.tween_property(_banner, "modulate:a", 0.0, 0.25)
	if scoreboard_visible:
		_render_scoreboard(world)

# ------------------------------------------------------------------ лента
func add_feed(text: String, color: Color = Color.WHITE) -> void:
	var entry := PanelContainer.new()
	var st := UiKit.flat(Color(0, 0, 0, 0.72), Cfg.RADIUS_SM)
	st.border_width_left = 3
	st.border_color = color
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	entry.add_theme_stylebox_override("panel", st)
	entry.add_child(UiKit.label(text, 11))
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_box.add_child(entry)
	_feed_box.move_child(entry, 0)
	feed_entries.push_front({"node": entry, "life": FEED_LIFE})
	while feed_entries.size() > FEED_MAX:
		var old = feed_entries.pop_back()
		old["node"].queue_free()

func clear_feed() -> void:
	for e in feed_entries:
		e["node"].queue_free()
	feed_entries.clear()

func _tick_feed() -> void:
	var kept := []
	for e in feed_entries:
		e["life"] = int(e["life"]) - 1
		if int(e["life"]) <= 0:
			e["node"].queue_free()
			continue
		# Плавно гасим угасающие строки.
		if int(e["life"]) < 60:
			(e["node"] as Control).modulate.a = float(e["life"]) / 60.0
		kept.append(e)
	feed_entries = kept

# ------------------------------------------------------------------ баннер
## Крупное сообщение в центре (открыт перк, забрали флаг и т.п.).
func banner(text: String, color: Color = Cfg.UI_GOLD, ticks: int = 150) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	_banner_timer = ticks

# ------------------------------------------------------------------ табло
func toggle_scoreboard(world: World) -> void:
	scoreboard_visible = not scoreboard_visible
	_scoreboard.visible = scoreboard_visible
	if scoreboard_visible and world != null:
		_render_scoreboard(world)

func hide_scoreboard() -> void:
	scoreboard_visible = false
	_scoreboard.visible = false

func _render_scoreboard(world: World) -> void:
	for child in _scoreboard_body.get_children():
		child.queue_free()

	var target: int = Cfg.MODES["ffa"]["frag_limit"] if world.mode == "ffa" else Cfg.MODES["ctf"]["cap_limit"]
	var head := ""
	match world.mode:
		"defense":
			head = I18n.t("sb.defense", {"cur": world.wave, "total": Cfg.MODES["defense"]["waves"]},
				"Оборона — волна %d из %d" % [world.wave, Cfg.MODES["defense"]["waves"]])
		"koth":
			head = I18n.t("sb.koth", {}, "Царь горы — побеждает последний выживший")
		"ffa":
			head = I18n.t("sb.ffa", {"target": target}, "Каждый за себя — до %d фрагов" % target)
		_:
			head = I18n.t("sb.ctf",
				{"a": world.team_score["player"], "b": world.team_score["enemy"], "target": target},
				"Захват флага — Свои %d : %d Враги (до %d)" % [world.team_score["player"], world.team_score["enemy"], target])

	var title := UiKit.label(head.to_upper(), 12, Cfg.UI_ACCENT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoreboard_body.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	_scoreboard_body.add_child(grid)

	for h in [I18n.t("go.table.rank", {}, "#"), I18n.t("go.table.tank", {}, "Танк"),
			I18n.t("go.table.kills", {}, "Фраги"), I18n.t("go.table.deaths", {}, "Смерти"),
			I18n.t("sb.perks", {}, "Перки")]:
		grid.add_child(UiKit.label(String(h).to_upper(), 10, Cfg.UI_MUTED))

	var rows := world.scoreboard()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var color: Color = Cfg.UI_ACCENT if bool(r["is_human"]) else Cfg.UI_TEXT
		grid.add_child(UiKit.label(str(i + 1), 12, color))
		var palette := Cfg.team_palette(String(r["color_key"]))
		var name_text: String = String(r["name"]) + ("" if bool(r["alive"]) else " †")
		var name_label := UiKit.label(name_text, 12, palette["body"] if not bool(r["is_human"]) else color)
		grid.add_child(name_label)
		grid.add_child(UiKit.label(str(r["kills"]), 12, color))
		grid.add_child(UiKit.label(str(r["deaths"]), 12, color))
		var icons := ""
		for id in r["perks"]:
			icons += Perks.any_perk_icon(id)
		grid.add_child(UiKit.label(icons, 12, Cfg.UI_GOLD))

	var hint := UiKit.label(I18n.t("sb.hint", {}, "Tab — скрыть"), 10, Cfg.UI_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoreboard_body.add_child(hint)
