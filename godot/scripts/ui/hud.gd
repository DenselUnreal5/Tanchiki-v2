class_name Hud
extends Control

const FEED_LIFE := 300
const FEED_MAX := 6

const WEATHER_ICONS := {"clear": "☀️", "rain": "🌧", "fog": "🌫", "storm": "⛈"}

var panels := {}
var feed_entries: Array = []
var _map_aspect := 200.0 / 114.0

var _feed_box: VBoxContainer
var _banner: Label
var _banner_timer := 0
var _wave_box: VBoxContainer
var _wave_title: Label
var _wave_sub: Label
var _tutorial_box: PanelContainer
var _tutorial_title: Label
var _tutorial_step: Label
var _tutorial_desc: Label
var _tutorial_progress: Label
var _scoreboard: ThemedPanel
var _scoreboard_body: VBoxContainer
var scoreboard_visible := false
var _last_sb_data: Array = []
var _perk_tooltip: PanelContainer
var _perk_tooltip_body: VBoxContainer

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

	_wave_box = UiKit.vbox(2)
	_wave_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_box.visible = false
	add_child(_wave_box)
	_wave_title = UiKit.label("", 18, Cfg.UI_GOLD, true)
	_wave_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_box.add_child(_wave_title)
	_wave_sub = UiKit.label("", 12, Cfg.UI_TEXT)
	_wave_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_box.add_child(_wave_sub)

	_tutorial_box = PanelContainer.new()
	_tutorial_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_box.visible = false
	var tut_st := UiKit.flat(Color(0.05, 0.08, 0.13, 0.94), Cfg.RADIUS_SM, 1, Cfg.UI_GOLD)
	tut_st.content_margin_left = 14
	tut_st.content_margin_right = 14
	tut_st.content_margin_top = 8
	tut_st.content_margin_bottom = 8
	_tutorial_box.add_theme_stylebox_override("panel", tut_st)

	var tut_vbox := UiKit.vbox(2)
	tut_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_box.add_child(tut_vbox)

	var top_row := UiKit.hbox(8)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_vbox.add_child(top_row)

	_tutorial_title = UiKit.label("", 13, Cfg.UI_GOLD, true)
	_tutorial_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_tutorial_title)

	_tutorial_step = UiKit.label("", 12, Color("#a3e635"), true)
	top_row.add_child(_tutorial_step)

	_tutorial_desc = UiKit.label("", 11, Cfg.UI_TEXT, false)
	_tutorial_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_vbox.add_child(_tutorial_desc)

	_tutorial_progress = UiKit.label("", 11, Color("#38bdf8"), true)
	tut_vbox.add_child(_tutorial_progress)

	add_child(_tutorial_box)

	_scoreboard = UiKit.panel()
	_scoreboard.visible = false
	_scoreboard.custom_minimum_size = Vector2(500, 0)
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_STOP
	_scoreboard_body = UiKit.vbox(4)
	_scoreboard_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_scoreboard.add_child(_scoreboard_body)
	add_child(_scoreboard)

	_perk_tooltip = PanelContainer.new()
	_perk_tooltip.visible = false
	_perk_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perk_tooltip.z_index = 200
	var tip_st := UiKit.flat(Color(0.06, 0.08, 0.12, 0.96), Cfg.RADIUS_SM)
	tip_st.border_width_left = 3
	tip_st.border_color = Cfg.UI_GOLD
	tip_st.content_margin_left = 10
	tip_st.content_margin_right = 10
	tip_st.content_margin_top = 8
	tip_st.content_margin_bottom = 8
	_perk_tooltip.add_theme_stylebox_override("panel", tip_st)

	_perk_tooltip_body = UiKit.vbox(4)
	_perk_tooltip_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perk_tooltip.add_child(_perk_tooltip_body)
	add_child(_perk_tooltip)

func build(players: Array, world: World) -> void:
	stop_killcam()
	for p in panels.values():
		p["root"].queue_free()
	panels.clear()
	_map_aspect = world.map.width / world.map.height

	for player in players:
		var palette := Cfg.team_palette(player.color_key)
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

		var left := UiKit.vbox(2)
		left.position = Vector2(12, 10)
		left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(left)

		var name_label := UiKit.label(player.name, 12, palette["trim"], true)
		left.add_child(name_label)

		var hp_bar := UiKit.rounded_bar(190, 14, Cfg.UI_ACCENT)
		var hp_wrap: Control = hp_bar["wrap"]
		var hp_bg: ColorRect = hp_bar["bg"]
		var hp_fill: ColorRect = hp_bar["fill"]
		var shield_fill := ColorRect.new()
		shield_fill.color = Cfg.shield
		shield_fill.position = Vector2(0, 10)
		shield_fill.size = Vector2(0, 4)
		hp_wrap.add_child(shield_fill)
		left.add_child(hp_wrap)

		var hp_text := UiKit.label("", 10, Cfg.UI_MUTED)
		left.add_child(hp_text)

		var net_label := UiKit.label("", 9, Color("#7fd0ff"))
		net_label.visible = false
		left.add_child(net_label)

		var heat_bar := UiKit.rounded_bar(190, 5, Cfg.UI_WARN)
		var heat_wrap: Control = heat_bar["wrap"]
		var heat_fill: ColorRect = heat_bar["fill"]
		left.add_child(heat_wrap)

		var acid_row := UiKit.hbox(4)
		acid_row.visible = false
		acid_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left.add_child(acid_row)

		var acid_icon := UiKit.label("🧪", 10)
		acid_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		acid_row.add_child(acid_icon)

		var acid_label := UiKit.label("", 10, Color("#a3e635"), true)
		acid_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		acid_row.add_child(acid_label)

		var acid_bar := UiKit.rounded_bar(70, 5, Color("#84cc16"))
		var acid_bar_wrap: Control = acid_bar["wrap"]
		var acid_bar_fill: ColorRect = acid_bar["fill"]
		acid_bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		acid_row.add_child(acid_bar_wrap)

		var freeze_row := UiKit.hbox(4)
		freeze_row.visible = false
		freeze_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left.add_child(freeze_row)

		var freeze_icon := UiKit.label("🧊", 10)
		freeze_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		freeze_row.add_child(freeze_icon)

		var freeze_label := UiKit.label("", 10, Color("#38bdf8"), true)
		freeze_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		freeze_row.add_child(freeze_label)

		var freeze_bar := UiKit.rounded_bar(70, 5, Color("#0ea5e9"))
		var freeze_bar_wrap: Control = freeze_bar["wrap"]
		var freeze_bar_fill: ColorRect = freeze_bar["fill"]
		freeze_bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		freeze_row.add_child(freeze_bar_wrap)

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

		var bottom := UiKit.vbox(4)
		bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bottom)

		var xp_label := UiKit.label("", 10, Cfg.UI_GOLD)
		bottom.add_child(xp_label)
		var xp_bar := UiKit.rounded_bar(220, 6, Cfg.UI_GOLD)
		var xp_wrap: Control = xp_bar["wrap"]
		var xp_fill: ColorRect = xp_bar["fill"]
		bottom.add_child(xp_wrap)

		var ability_row := UiKit.hbox(6)
		ability_row.visible = false
		bottom.add_child(ability_row)
		var ability_icon := PerkIcons.make_view("", 14, Color.WHITE)
		ability_row.add_child(ability_icon)
		var ability_label := UiKit.label("", 10, Cfg.UI_TEXT)
		ability_row.add_child(ability_label)
		var cd_bar := UiKit.rounded_bar(90, 6, Cfg.UI_ACCENT)
		var cd_wrap: Control = cd_bar["wrap"]
		var cd_fill: ColorRect = cd_bar["fill"]
		ability_row.add_child(cd_wrap)

		var perks := UiKit.hbox(4)
		bottom.add_child(perks)

		var mm := Minimap.new()
		mm.world = world
		mm.player = player
		root.add_child(mm)

		panels[player.index] = {
			"root": root, "left": left, "right": right, "bottom": bottom,
			"name": name_label, "hp_wrap": hp_wrap, "hp_fill": hp_fill, "hp_bg": hp_bg,
			"shield_fill": shield_fill, "hp_text": hp_text,
			"heat_fill": heat_fill, "heat_wrap": heat_wrap,
			"acid_row": acid_row, "acid_label": acid_label, "acid_fill": acid_bar_fill,
			"freeze_row": freeze_row, "freeze_label": freeze_label, "freeze_fill": freeze_bar_fill,
			"net": net_label,
			"score": score, "objective": objective, "weather": weather_label,
			"xp_label": xp_label, "xp_fill": xp_fill, "perks": perks,
			"ability_row": ability_row, "ability_label": ability_label,
			"ability_icon": ability_icon,
			"ability_fill": cd_fill,
			"minimap": mm, "last_perks": "",
		}
	layout(players, world)

func _virtual_rect(rect: Rect2) -> Rect2:
	var s := UiKit.ui_scale()
	return Rect2(rect.position / s, rect.size / s)

func layout(players: Array, world: World = null) -> void:
	var split := players.size() > 1
	for player in players:
		if not panels.has(player.index):
			continue
		var panel: Dictionary = panels[player.index]
		var vp: Rect2 = _virtual_rect(player.viewport)
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
		(panel["hp_wrap"] as Control).custom_minimum_size.x = hp_w

	var screen := UiKit.virtual_screen(self)
	var wave_ui := world != null and world.mode == "defense"
	_wave_box.visible = wave_ui
	if wave_ui:
		_wave_box.position = Vector2(screen.x * 0.5 - 150.0, 10.0)
		_wave_box.custom_minimum_size = Vector2(300, 0)
		_wave_box.size = Vector2(300, 46)

	var tutorial_ui := world != null and world.mode == "tutorial"
	_tutorial_box.visible = tutorial_ui
	if tutorial_ui:
		var tut_w := minf(540.0, screen.x - 40.0)
		_tutorial_box.position = Vector2(screen.x * 0.5 - tut_w * 0.5, 10.0)
		_tutorial_box.custom_minimum_size = Vector2(tut_w, 0)
		_tutorial_box.size = Vector2(tut_w, 54)

	var mm_w := 140.0 if split else 200.0
	var mm_h := roundf(mm_w / maxf(0.2, _map_aspect))
	var feed_x := screen.x - mm_w - 10.0
	var feed_y := 10.0 + mm_h + 8.0
	if not players.is_empty():
		var p0: PlayerState = players[0]
		var vp: Rect2 = _virtual_rect(p0.viewport)
		feed_x = vp.position.x + vp.size.x - mm_w - 10.0
		feed_y = vp.position.y + 10.0 + mm_h + 8.0
	_feed_box.position = Vector2(feed_x, feed_y)
	_feed_box.custom_minimum_size = Vector2(mm_w, 0)
	_feed_box.size = Vector2(mm_w, 0)
	for child in _feed_box.get_children():
		if child is Control:
			child.custom_minimum_size = Vector2(mm_w, 0)

	_banner.position = Vector2(screen.x * 0.5 - 300.0, screen.y * 0.22)
	_banner.size = Vector2(600, 40)
	_scoreboard.position = Vector2(screen.x * 0.5 - 230.0, screen.y * 0.5 - 180.0)
	_place_killcam(players)

var _killcam: KillCamView = null

func play_killcam(clip: Dictionary, map: GameMap, players: Array) -> void:
	if _killcam == null:
		_killcam = KillCamView.new()
		add_child(_killcam)
	_place_killcam(players)
	_killcam.play(clip, map)

func _place_killcam(players: Array) -> void:
	if _killcam == null or players.is_empty():
		return
	var vp := _virtual_rect(players[0].viewport)
	_killcam.position = Vector2(
		vp.position.x + (vp.size.x - KillCamView.VIEW_SIZE.x) * 0.5,
		vp.position.y + vp.size.y - KillCamView.VIEW_SIZE.y - 14.0)

func stop_killcam() -> void:
	if _killcam != null and _killcam.running:
		_killcam.stop()

func show_hud() -> void:
	visible = true

func hide_hud() -> void:
	visible = false
	hide_scoreboard()
	stop_killcam()

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
	label.modulate = Cfg.UI_DANGER if _game_stale() else Color.WHITE

func _game_stale() -> bool:
	var g := get_parent()
	while g != null and not g.has_method("net_peer_left"):
		g = g.get_parent()
	return g != null and bool(g.get("net_stale"))

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
	var key := "Q / Й" if player.index == 0 else "Num -"
	var icon := String(ab.get("icon", "✦"))
	var name := I18n.dn(ab, "name", "ability")
	var icon_view: PerkIconView = panel["ability_icon"]
	var tex_id: String = tank.ability_id
	if PerkIcons.texture_of(tex_id) == null:
		tex_id = "bot_" + tank.ability_id
	var has_tex := PerkIcons.texture_of(tex_id) != null
	icon_view.visible = has_tex
	if has_tex:
		icon_view.perk_id = tex_id
		icon = ""

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
	label.text = label.text.strip_edges()
	icon_view.modulate = label.modulate

func update_hud(world: World) -> void:
	if world.mode == "tutorial":
		var tinfo: Dictionary = world.get_tutorial_task_info()
		_tutorial_box.visible = true
		_tutorial_title.text = String(tinfo.get("title", ""))
		_tutorial_step.text = "[ %d / %d ]" % [int(tinfo.get("stage", 1)), int(tinfo.get("total", 12))]
		_tutorial_desc.text = String(tinfo.get("desc", ""))
		_tutorial_progress.text = String(tinfo.get("progress_text", ""))
	else:
		_tutorial_box.visible = false

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

		var acid_row: Control = panel["acid_row"]
		var acid_label: Label = panel["acid_label"]
		var acid_fill: ColorRect = panel["acid_fill"]
		if tank.acid_stacks > 0 and tank.acid_ticks_left > 0:
			acid_row.visible = true
			var sec_left: float = float(tank.acid_ticks_left) / float(Cfg.TICK_HZ)
			acid_label.text = "КИСЛОТА ×%d · %.1f с" % [tank.acid_stacks, sec_left]
			var prog: float = clampf(float(tank.acid_ticks_left) / float(Cfg.ACID_DURATION_TICKS), 0.0, 1.0)
			acid_fill.size.x = 70.0 * prog
			var pulse: float = 0.8 + 0.2 * sin(float(world.tick) * 0.35)
			acid_label.modulate = Color(1.0, 1.0, 1.0, pulse)
		else:
			acid_row.visible = false

		var freeze_row: Control = panel.get("freeze_row", null)
		var freeze_label: Label = panel.get("freeze_label", null)
		var freeze_fill: ColorRect = panel.get("freeze_fill", null)
		if freeze_row != null:
			if tank.freeze_ticks > 0:
				freeze_row.visible = true
				var sec_f: float = float(tank.freeze_ticks) / float(Cfg.TICK_HZ)
				freeze_label.text = "ЗАМОРОЗКА · %.1f с" % sec_f
				var f_max: float = float(tank.freeze_max_ticks) if "freeze_max_ticks" in tank and tank.freeze_max_ticks > 0 else float(Cfg.ICE_FREEZE_TICKS)
				var prog_f: float = clampf(float(tank.freeze_ticks) / f_max, 0.0, 1.0)
				freeze_fill.size.x = 70.0 * prog_f
				var pulse_f: float = 0.8 + 0.2 * sin(float(world.tick) * 0.4)
				freeze_label.modulate = Color(1.0, 1.0, 1.0, pulse_f)
			else:
				freeze_row.visible = false

		(panel["score"] as Label).text = I18n.t("hud.score", {"n": player.score}, "Счёт %d" % player.score)

		var progress := world.progress_for(player)
		var objective: Label = panel["objective"]
		match world.mode:
			"defense":
				var base_hp := int(ceil(float(world.base["hp"]))) if world.base != null else 0
				var strike := ""
				if player.index == 0:
					if world.airstrike_cooldown > 0:
						var secs := int(ceil(float(world.airstrike_cooldown) / float(Cfg.TICK_HZ)))
						strike = I18n.t("hud.strikeCd", {"n": secs}, "  Удар: %dс" % secs)
					else:
						strike = I18n.t("hud.strikeReady", {}, "  Удар: ГОТОВ (F)")
				objective.text = I18n.t("hud.base", {"hp": base_hp}, "База: %d HP" % base_hp) + strike
			"koth":
				var left_ticks := maxi(0, world.time_limit - world.tick)
				var sec := int(ceil(float(left_ticks) / 60.0))
				var time_str := "%d:%02d" % [sec / 60, sec % 60]
				var alive_bosses := 0
				var boss_icons := ""
				for t in world.tanks:
					if t.alive and t.is_boss:
						alive_bosses += 1
						if not t.enemy_type.is_empty() and t.enemy_type.has("icon"):
							boss_icons += " " + String(t.enemy_type["icon"])
				if alive_bosses > 0:
					objective.text = I18n.t("hud.koth_bosses",
						{"bosses": alive_bosses, "icons": boss_icons, "cur": progress["current"], "total": progress["total"], "time": time_str},
						"Царь Горы · Боссы: %d%s · Выживших %d/%d   %s" % [alive_bosses, boss_icons, progress["current"], progress["total"], time_str])
				else:
					objective.text = I18n.t("hud.koth_cleared",
						{"cur": progress["current"], "total": progress["total"], "time": time_str},
						"ВСЕ БОССЫ ПОВЕРЖЕНЫ! · Выживших %d/%d   %s" % [progress["current"], progress["total"], time_str])
			"ffa":
				objective.text = I18n.t("hud.frags",
					{"cur": progress["current"], "target": progress["target"], "deaths": player.deaths},
					"Фраги %d / %d   Смертей: %d" % [progress["current"], progress["target"], player.deaths])
			"tutorial":
				var tinfo: Dictionary = progress.get("task", world.get_tutorial_task_info())
				objective.text = "%s  [%s]" % [tinfo.get("title", "Обучение"), tinfo.get("keys", "")]
			_:
				var txt := I18n.t("hud.flags",
					{"a": world.team_score["player"], "b": world.team_score["enemy"],
						"limit": Cfg.MODES["ctf"]["cap_limit"]},
					"Флаги %d : %d (до %d)" % [world.team_score["player"], world.team_score["enemy"], Cfg.MODES["ctf"]["cap_limit"]])
				if tank.carrying_flag:
					txt += I18n.t("hud.flagYou", {}, "  ⚑ у вас флаг!")
				objective.text = txt

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

		var heat_tank = player.tank
		var heat: float = heat_tank.heat if heat_tank != null else 0.0
		var heat_wrap2: Control = panel["heat_wrap"]
		heat_wrap2.visible = heat > 0.02
		if heat_wrap2.visible:
			var fill: ColorRect = panel["heat_fill"]
			fill.size.x = 190.0 * clampf(heat, 0.0, 1.0)
			if heat_tank != null and heat_tank.overheated:
				var k := 0.5 + 0.5 * sin(float(world.tick) * 0.35)
				fill.color = Color(1.0, 0.35 + 0.25 * k, 0.2)
			else:
				fill.color = Cfg.UI_WARN.lerp(Cfg.UI_DANGER, heat)

		_update_net(panel)

		_update_ability(panel, player)

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
				var slot_row := HBoxContainer.new()
				slot_row.add_theme_constant_override("separation", 4)
				slot_row.add_child(PerkIcons.make_view(id, 15, Cfg.UI_GOLD))
				slot_row.add_child(UiKit.label(I18n.dn(perk, "name", "perk"), 10, Cfg.UI_GOLD))
				slot.add_child(slot_row)
				box.add_child(slot)

	if world.mode == "defense":
		var total_waves := int(Cfg.MODES["defense"]["waves"])
		if world.wave > total_waves:
			_wave_title.text = I18n.t("hud.wave.big.endless", {"cur": world.wave},
				"ВОЛНА %d ∞" % world.wave)
		else:
			_wave_title.text = I18n.t("hud.wave.big", {"cur": world.wave, "total": total_waves},
				"ВОЛНА %d / %d" % [world.wave, total_waves])
		if world.wave_state == "delay":
			var secs := int(ceil(float(maxi(0, world.wave_timer)) / float(Cfg.TICK_HZ)))
			var time_str := "%d:%02d" % [secs / 60, secs % 60]
			_wave_sub.text = I18n.t("hud.wave.next", {"time": time_str},
				"Следующая волна через %s" % time_str)
		else:
			var left := int(world.progress_for(world.players[0])["current"]) if not world.players.is_empty() else 0
			_wave_sub.text = I18n.t("hud.left", {"n": left}, "%d в поле" % left)

	_tick_feed()
	if _banner_timer > 0:
		_banner_timer -= 1
		if _banner_timer == 0:
			var tw := create_tween()
			tw.tween_property(_banner, "modulate:a", 0.0, 0.25)
	if scoreboard_visible:
		var sb_rows := world.scoreboard()
		if sb_rows != _last_sb_data:
			_last_sb_data = sb_rows.duplicate(true)
			_render_scoreboard(world, sb_rows)

func add_feed(text: String, color: Color = Color.WHITE) -> void:
	var entry := PanelContainer.new()
	var st := UiKit.flat(Color(0, 0, 0, 0.30), Cfg.RADIUS_SM)
	st.border_width_left = 3
	st.border_color = Color(color.r, color.g, color.b, 0.85)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	entry.add_theme_stylebox_override("panel", st)

	var lbl := UiKit.label(text, 11)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(lbl)
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var feed_w: float = _feed_box.custom_minimum_size.x if _feed_box.custom_minimum_size.x > 0.0 else 200.0
	entry.custom_minimum_size = Vector2(feed_w, 0)
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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
		if int(e["life"]) < 60:
			(e["node"] as Control).modulate.a = float(e["life"]) / 60.0
		kept.append(e)
	feed_entries = kept

func banner(text: String, color: Color = Cfg.UI_GOLD, ticks: int = 150, font_size: int = 24) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.add_theme_font_size_override("font_size", font_size)
	_banner.modulate.a = 1.0
	_banner_timer = ticks

func toggle_scoreboard(world: World) -> void:
	scoreboard_visible = not scoreboard_visible
	_scoreboard.visible = scoreboard_visible
	if not scoreboard_visible:
		_hide_perk_tooltip()
	elif world != null:
		_last_sb_data.clear()
		_render_scoreboard(world, world.scoreboard())

func hide_scoreboard() -> void:
	scoreboard_visible = false
	_scoreboard.visible = false
	_hide_perk_tooltip()

func _resolve_perk_info(id: String) -> Dictionary:
	var p := Perks.get_perk(id)
	if not p.is_empty():
		return {
			"name": I18n.dn(p, "name", "perk"),
			"desc": I18n.dn(p, "desc", "perk"),
			"icon": String(p.get("icon", "⭐")),
			"category": String(p.get("category", "")),
		}
	var bp := Perks.get_bot_perk(id)
	if not bp.is_empty():
		return {
			"name": I18n.dn(bp, "name", "perk"),
			"desc": I18n.dn(bp, "desc", "perk"),
			"icon": String(bp.get("icon", "🤖")),
			"category": "bot",
		}
	var ab := Abilities.get_ability(id)
	if not ab.is_empty():
		return {
			"name": I18n.dn(ab, "name", "ability"),
			"desc": I18n.dn(ab, "desc", "ability"),
			"icon": String(ab.get("icon", "✦")),
			"category": "ability",
		}
	return {
		"name": id.capitalize(),
		"desc": "",
		"icon": "⭐",
		"category": "",
	}

func _show_perk_tooltip(id: String, source_node: Control) -> void:
	if _perk_tooltip == null:
		return
	for child in _perk_tooltip_body.get_children():
		child.queue_free()

	var info := _resolve_perk_info(id)
	var header := UiKit.hbox(6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perk_tooltip_body.add_child(header)

	var icon_view := PerkIcons.make_view(id, 20, Cfg.UI_GOLD)
	icon_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon_view)

	var name_lbl := UiKit.label(info["name"], 12, Cfg.UI_GOLD, true)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_lbl)

	var cat: String = String(info["category"])
	if cat != "":
		var cat_text := ""
		match cat:
			"fire": cat_text = "[ОГОНЬ]"
			"defense": cat_text = "[ЗАЩИТА]"
			"speed": cat_text = "[СКОРОСТЬ]"
			"special": cat_text = "[ОСОБОЕ]"
			"challenge": cat_text = "[ЧЕЛЛЕНДЖ]"
			"bot": cat_text = "[БОТ]"
			"ability": cat_text = "[НАВЫК]"
			_: cat_text = "[%s]" % cat.to_upper()
		var cat_lbl := UiKit.label(cat_text, 9, Cfg.UI_MUTED)
		cat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(cat_lbl)

	var desc_text: String = String(info["desc"])
	if desc_text != "":
		var desc_lbl := UiKit.label(desc_text, 11, Cfg.UI_TEXT)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(250, 0)
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_perk_tooltip_body.add_child(desc_lbl)

	_perk_tooltip.reset_size()
	var gpos := source_node.global_position
	var vp_size := get_viewport_rect().size
	var s := UiKit.ui_scale()
	var tip_x := gpos.x - 20.0
	var tip_y := gpos.y - _perk_tooltip.size.y * s - 10.0
	if tip_y < 10.0:
		tip_y = gpos.y + source_node.size.y * s + 10.0
	if tip_x + 280.0 * s > vp_size.x - 10.0:
		tip_x = vp_size.x - 280.0 * s - 10.0
	if tip_x < 10.0:
		tip_x = 10.0
	_perk_tooltip.global_position = Vector2(tip_x, tip_y)
	_perk_tooltip.visible = true

func _hide_perk_tooltip() -> void:
	if _perk_tooltip != null:
		_perk_tooltip.visible = false

func _render_scoreboard(world: World, rows: Array = []) -> void:
	for child in _scoreboard_body.get_children():
		child.queue_free()

	if rows.is_empty():
		rows = world.scoreboard()

	var target: int = Cfg.MODES["ffa"]["frag_limit"] if world.mode == "ffa" else Cfg.MODES["ctf"]["cap_limit"]
	var head := ""
	match world.mode:
		"defense":
			var total_waves: int = Cfg.MODES["defense"]["waves"]
			if world.wave > total_waves:
				head = I18n.t("sb.defense.endless", {"cur": world.wave},
					"Оборона — волна %d (бесконечная)" % world.wave)
			else:
				head = I18n.t("sb.defense", {"cur": world.wave, "total": total_waves},
					"Оборона — волна %d из %d" % [world.wave, total_waves])
		"koth":
			head = I18n.t("sb.koth", {}, "Царь горы (Битва с боссами) — одолейте боссов и выживите")
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
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_scoreboard_body.add_child(grid)

	for h in [I18n.t("go.table.rank", {}, "#"), I18n.t("go.table.tank", {}, "Танк"),
			I18n.t("go.table.kills", {}, "Фраги"), I18n.t("go.table.deaths", {}, "Смерти"),
			I18n.t("sb.perks", {}, "Перки")]:
		grid.add_child(UiKit.label(String(h).to_upper(), 10, Cfg.UI_MUTED))

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

		var icons := HBoxContainer.new()
		icons.add_theme_constant_override("separation", 3)
		icons.mouse_filter = Control.MOUSE_FILTER_PASS
		for id in r["perks"]:
			var p_id := String(id)
			var p_box := PanelContainer.new()
			var p_st := UiKit.flat(Color(0.12, 0.15, 0.20, 0.85), Cfg.RADIUS_SM)
			p_st.content_margin_left = 3
			p_st.content_margin_right = 3
			p_st.content_margin_top = 2
			p_st.content_margin_bottom = 2
			p_box.add_theme_stylebox_override("panel", p_st)
			p_box.mouse_filter = Control.MOUSE_FILTER_STOP

			var v := PerkIcons.make_view(p_id, 14, Cfg.UI_GOLD)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p_box.add_child(v)

			p_box.mouse_entered.connect(func(): _show_perk_tooltip(p_id, p_box))
			p_box.mouse_exited.connect(_hide_perk_tooltip)
			icons.add_child(p_box)
		grid.add_child(icons)

	var hint := UiKit.label(I18n.t("sb.hint", {}, "Tab — скрыть · Наведите курсор на перк для описания"), 10, Cfg.UI_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoreboard_body.add_child(hint)
