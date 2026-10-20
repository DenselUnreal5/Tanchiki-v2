extends "res://tests/reel.gd"

const CLASS_TEXT := {
	"en": {
		"standard.name": "UNIVERSAL", "standard.tag": "The all-rounder",
		"standard.f1": "Balanced armor, speed and firepower",
		"standard.f2": "+10% match XP: perks arrive sooner",
		"standard.f3": "Fits any build you can imagine",
		"grunt.name": "GRUNT", "grunt.tag": "Built to take a beating",
		"grunt.f1": "+15% armor",
		"grunt.f2": "Self-repair: 60 HP per minute",
		"grunt.f3": "Medkits heal 30% more · less damage when low",
		"scout.name": "SCOUT", "scout.tag": "Light, fast, fragile",
		"scout.f1": "+30% speed",
		"scout.f2": "Dash recharges 30% faster",
		"scout.f3": "15% dodge chance · ram damage ×1.5",
		"heavy.name": "BRUTE", "heavy.tag": "A breakthrough tank",
		"heavy.f1": "Double armor",
		"heavy.f2": "Ram damage ×3",
		"heavy.f3": "Stuns and freezes last half as long",
		"sniper.name": "SNIPER", "sniper.tag": "One shot, one wreck",
		"sniper.f1": "Double damage per shot",
		"sniper.f2": "Very fast shells",
		"sniper.f3": "Ambush: first shot at an unready enemy ×1.3",
		"mortar.name": "MORTAR", "mortar.tag": "Siege artillery",
		"mortar.f1": "Shells fly over walls",
		"mortar.f2": "Explosions hit a whole area",
		"mortar.f3": "Buildings take 50% more damage",
		"other": "5 more classes to master", "cta": "COMING SOON TO STEAM",
	},
	"ru": {
		"standard.name": "УНИВЕРСАЛ", "standard.tag": "Мастер на все руки",
		"standard.f1": "Баланс брони, скорости и огня",
		"standard.f2": "+10% опыта: перки приходят чаще",
		"standard.f3": "Подходит под любой билд",
		"grunt.name": "РЯДОВОЙ", "grunt.tag": "Создан держать удар",
		"grunt.f1": "+15% брони",
		"grunt.f2": "Самопочинка: 60 HP в минуту",
		"grunt.f3": "Аптечки лечат на 30% сильнее · меньше урона при низком HP",
		"scout.name": "РАЗВЕДЧИК", "scout.tag": "Лёгкий, быстрый, хрупкий",
		"scout.f1": "+30% скорости",
		"scout.f2": "Рывок перезаряжается на 30% быстрее",
		"scout.f3": "15% уклонения · урон тарана ×1.5",
		"heavy.name": "ГРОМИЛА", "heavy.tag": "Танк прорыва",
		"heavy.f1": "Двойная броня",
		"heavy.f2": "Урон тарана ×3",
		"heavy.f3": "Оглушение и заморозка вдвое короче",
		"sniper.name": "СНАЙПЕР", "sniper.tag": "Один выстрел — один остов",
		"sniper.f1": "Двойной урон за выстрел",
		"sniper.f2": "Очень быстрые снаряды",
		"sniper.f3": "Засада: первый выстрел по неготовому врагу ×1.3",
		"mortar.name": "МИНОМЁТ", "mortar.tag": "Осадная артиллерия",
		"mortar.f1": "Снаряды летят через стены",
		"mortar.f2": "Взрыв накрывает площадь",
		"mortar.f3": "Здания разрушаются на 50% сильнее",
		"other": "Ещё 5 классов на выбор", "cta": "СКОРО В STEAM",
	},
	"fr": {
		"standard.name": "POLYVALENT", "standard.tag": "Bon en tout",
		"standard.f1": "Blindage, vitesse et puissance équilibrés",
		"standard.f2": "+10 % d'XP : les perks arrivent plus vite",
		"standard.f3": "S'adapte à tous les builds",
		"grunt.name": "FANTASSIN", "grunt.tag": "Fait pour encaisser",
		"grunt.f1": "+15 % de blindage",
		"grunt.f2": "Auto-réparation : 60 PV par minute",
		"grunt.f3": "Soins +30 % · moins de dégâts quand il est affaibli",
		"scout.name": "ÉCLAIREUR", "scout.tag": "Léger, rapide, fragile",
		"scout.f1": "+30 % de vitesse",
		"scout.f2": "Ruée rechargée 30 % plus vite",
		"scout.f3": "15 % d'esquive · éperonnage ×1,5",
		"heavy.name": "COLOSSE", "heavy.tag": "Un tank de percée",
		"heavy.f1": "Blindage doublé",
		"heavy.f2": "Dégâts d'éperonnage ×3",
		"heavy.f3": "Étourdissement et gel deux fois plus courts",
		"sniper.name": "TIREUR D'ÉLITE", "sniper.tag": "Un tir, une épave",
		"sniper.f1": "Dégâts doublés par tir",
		"sniper.f2": "Obus ultra-rapides",
		"sniper.f3": "Embuscade : premier tir sur un ennemi surpris ×1,3",
		"mortar.name": "MORTIER", "mortar.tag": "Artillerie de siège",
		"mortar.f1": "Les obus passent par-dessus les murs",
		"mortar.f2": "Des explosions qui couvrent une zone",
		"mortar.f3": "Bâtiments : +50 % de dégâts",
		"other": "5 autres classes à maîtriser", "cta": "BIENTÔT SUR STEAM",
	},
	"es": {
		"standard.name": "UNIVERSAL", "standard.tag": "Bueno en todo",
		"standard.f1": "Blindaje, velocidad y potencia equilibrados",
		"standard.f2": "+10 % de XP: las mejoras llegan antes",
		"standard.f3": "Encaja con cualquier build",
		"grunt.name": "SOLDADO", "grunt.tag": "Hecho para aguantar",
		"grunt.f1": "+15 % de blindaje",
		"grunt.f2": "Autorreparación: 60 PV por minuto",
		"grunt.f3": "Botiquines +30 % · menos daño con poca vida",
		"scout.name": "EXPLORADOR", "scout.tag": "Ligero, rápido, frágil",
		"scout.f1": "+30 % de velocidad",
		"scout.f2": "El impulso se recarga un 30 % antes",
		"scout.f3": "15 % de esquiva · embestida ×1,5",
		"heavy.name": "BRUTO", "heavy.tag": "Un tanque de asalto",
		"heavy.f1": "Blindaje doble",
		"heavy.f2": "Daño de embestida ×3",
		"heavy.f3": "Aturdimiento y congelación duran la mitad",
		"sniper.name": "FRANCOTIRADOR", "sniper.tag": "Un disparo, un tanque menos",
		"sniper.f1": "Doble daño por disparo",
		"sniper.f2": "Proyectiles muy rápidos",
		"sniper.f3": "Emboscada: primer disparo a un enemigo desprevenido ×1,3",
		"mortar.name": "MORTERO", "mortar.tag": "Artillería de asedio",
		"mortar.f1": "Los proyectiles pasan por encima de los muros",
		"mortar.f2": "Explosiones que cubren un área",
		"mortar.f3": "Edificios: +50 % de daño",
		"other": "5 clases más por dominar", "cta": "PRÓXIMAMENTE EN STEAM",
	},
}

const STAGE := {
	"standard": {"loc": "city", "weather": "clear", "time": "day", "seed": 8101, "pull": 230.0},
	"grunt": {"loc": "jungle", "weather": "rain", "time": "day", "seed": 8202, "pull": 220.0},
	"scout": {"loc": "dust", "weather": "clear", "time": "day", "seed": 8303, "pull": 260.0, "dash": 35},
	"heavy": {"loc": "frost", "weather": "snow", "time": "day", "seed": 8404, "pull": 200.0, "ram": true},
	"sniper": {"loc": "shore", "weather": "clear", "time": "dusk", "seed": 8505, "pull": 380.0, "dist": 360.0},
	"mortar": {"loc": "city", "weather": "clear", "time": "dusk", "seed": 8606, "pull": 260.0},
}

const PAINT := Color("#3f7d3f")
const CARD := 200.0
const HERO := 380.0

var class_id := "scout"
var hero: Control
var strip: HBoxContainer
var logo: Label
var cta_label: Label

func _texts() -> Dictionary:
	return CLASS_TEXT

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--class="):
			class_id = a.substr(8)
	if not STAGE.has(class_id):
		class_id = "scout"
	subs_name = "class_" + class_id
	await _setup()
	_build_class_overlay()
	await _class_video()
	_teardown()

func _build_class_overlay() -> void:
	hero = Control.new()
	hero.size = Vector2(W, 300)
	hero.position = Vector2(0, 380)
	hero.visible = false
	overlay.add_child(hero)
	strip = HBoxContainer.new()
	strip.add_theme_constant_override("separation", 30)
	strip.position = Vector2(W, 470)
	strip.visible = false
	overlay.add_child(strip)
	logo = _big_label(62)
	logo.text = "IRON STORM"
	logo.position = Vector2(20, 230)
	logo.visible = false
	overlay.add_child(logo)
	cta_label = _big_label(36)
	cta_label.add_theme_color_override("font_color", Color("#ffd54a"))
	cta_label.position = Vector2(20, 760)
	cta_label.visible = false
	overlay.add_child(cta_label)

func _tank_art(cls: String, px: float) -> Control:
	var sprite := String(TankSprites.BY_CLASS.get(cls, "universal"))
	var box := Control.new()
	box.custom_minimum_size = Vector2(px, px)
	box.size = Vector2(px, px)
	for kind in ["hull", "turret"]:
		for layer in ["", "_paint"]:
			var tex: Texture2D = load(TankSprites.DIR + sprite + "_" + kind + layer + ".png")
			if tex == null:
				continue
			var r := TextureRect.new()
			r.texture = tex
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			if layer == "_paint":
				r.modulate = TankSprites.paint_modulate(PAINT)
			box.add_child(r)
	return box

func _class_card(cls: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.add_child(_tank_art(cls, CARD))
	if burn:
		var l := Label.new()
		l.text = String(CLASS_TEXT[lang][cls + ".name"])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.custom_minimum_size = Vector2(CARD, 34)
		l.add_theme_font_override("font", Fonts.bold)
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		l.add_theme_constant_override("outline_size", 10)
		col.add_child(l)
	return col

func _feature(key: String, frames: int, every_frame: Callable = Callable()) -> void:
	_say_keys(class_id + "." + key)
	for i in frames:
		_keep_alive()
		if every_frame.is_valid():
			every_frame.call(i)
		await _frames(1)

func _class_video() -> void:
	var stage: Dictionary = STAGE[class_id]
	var prev_class := String(Prof.equipped_class)
	Prof.equipped_class = class_id
	await _start("ffa", String(stage["loc"]), String(stage["weather"]), String(stage["time"]), int(stage["seed"]))
	Prof.equipped_class = prev_class
	var pilot = game.players[0].scheme
	pilot.dash_every = int(stage.get("dash", 170))
	pilot.ram = bool(stage.get("ram", false))
	pilot.close_dist = float(stage.get("dist", 210.0))
	var pull := float(stage["pull"])
	_pull_enemies(4, pull)

	for c in hero.get_children():
		c.queue_free()
	var art := _tank_art(class_id, HERO)
	art.position = Vector2((W - HERO) / 2.0, -20)
	art.pivot_offset = Vector2(HERO, HERO) / 2.0
	hero.add_child(art)
	hero.visible = true
	art.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(art, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var dim_in := create_tween()
	dim_in.tween_property(dim, "color:a", 0.5, 0.15)
	_say_keys(class_id + ".name", class_id + ".tag")
	for i in 60:
		_keep_alive()
		art.rotation = sin(float(i) * 0.08) * 0.12
		await _frames(1)
	hero.visible = false
	create_tween().tween_property(dim, "color:a", 0.0, 0.2)

	await _feature("f1", 75, func(i: int):
		if i == 20:
			_pull_enemies(5, pull))
	if class_id == "standard":
		var p = game.players[0]
		var k := float(W) / 1000.0
		game.ui.scale = Vector2(k, k)
		game.ui.size = Vector2(W, H) / k
		game.ui.show_perk_select(p, 0, Rng.new(11))
		_say_keys("standard.f2")
		await _frames(75)
		game.ui.hide_perk_select()
		game._apply_ui_scale()
		p.perk_ids.append("nitro")
		p.tank.recompute()
	else:
		await _feature("f2", 75, func(i: int):
			if i == 10:
				_pull_enemies(4, pull * 0.8)
			if class_id == "mortar" and i % 8 == 0:
				_blast_bricks(6, 2 + i % 3))
	await _feature("f3", 75, func(i: int):
		if i == 15:
			_pull_enemies(5, pull))

	_open_cue(["other"])
	caption.text = ""
	sub.text = ""
	for c in strip.get_children():
		c.queue_free()
	for cls in TankClasses.ids():
		if cls != class_id:
			strip.add_child(_class_card(cls))
	strip.visible = true
	create_tween().tween_property(dim, "color:a", 0.72, 0.3)
	var start_x := float(W) + 10.0
	var end_x := -5.0 * (CARD + 30.0) + float(W) - 10.0
	for i in 135:
		_keep_alive()
		strip.position = Vector2(lerpf(start_x, end_x, clampf(float(i) / 115.0, 0.0, 1.0)), 430)
		if i == 60:
			_open_cue(["cta"])
			logo.visible = true
			logo.scale = Vector2(1.3, 1.3)
			create_tween().tween_property(logo, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if burn:
				cta_label.text = _t("cta")
				cta_label.visible = true
		await _frames(1)
	_close_cue()
	await _end_match()
