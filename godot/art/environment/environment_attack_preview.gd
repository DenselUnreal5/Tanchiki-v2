extends Node2D

var pages: Array[Node2D] = []
var animations: Array[AnimatedSprite2D] = []
var buttons: Array[Button] = []

const GUNS := [
	["Обычная пушка", "tank_shots", ["muzzle", "projectile", "impact", "explosion"]],
	["Кислотная пушка", "acid_shots", ["muzzle", "projectile", "impact", "acid_cloud"]],
	["Огнемёт", "flamethrower_shots", ["muzzle", "flame_stream", "impact", "fire_burst"]],
	["Электрическая пушка", "electric_shots", ["muzzle", "projectile", "impact", "discharge"]],
	["Ледяная пушка", "ice_shots", ["muzzle", "ice_shards", "impact", "freeze_loop"]],
]

func _ready() -> void:
	var bg := Polygon2D.new()
	bg.polygon = PackedVector2Array([Vector2.ZERO, Vector2(1280, 0), Vector2(1280, 720), Vector2(0, 720)])
	bg.color = Color("#172021")
	add_child(bg)
	for title in ["Окружение: 36 объектов", "Выстрелы: 5 пушек", "Атаки боссов: 8 анимаций"]:
		var page := Node2D.new()
		pages.append(page)
		add_child(page)
		var button := Button.new()
		button.position = Vector2(20 + buttons.size() * 415, 18)
		button.size = Vector2(405, 44)
		button.text = title
		button.pressed.connect(show_page.bind(buttons.size()))
		buttons.append(button)
		add_child(button)
	_build_props()
	_build_guns()
	_build_bosses()
	show_page(0)

func show_page(index: int) -> void:
	for i in pages.size():
		pages[i].visible = i == index
		buttons[i].disabled = i == index

func _label(parent: Node, text: String, pos: Vector2, font_size: int = 16, width: float = 180) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)

func _build_props() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/environment_pixels.gdshader")
	var group_index := 0
	for group in EnvironmentArt.ITEMS:
		_label(pages[0], ["Военные объекты", "Пустыня", "Джунгли"][group_index], Vector2(20 + group_index * 420, 85), 23, 400)
		var item_index := 0
		for id in EnvironmentArt.ITEMS[group]:
			var sprite := Sprite2D.new()
			sprite.texture = load("res://art/environment/%s/%s.tres" % [group, id])
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.material = mat
			var col := item_index % 4
			var row := item_index / 4
			sprite.position = Vector2(66 + group_index * 420 + col * 99, 195 + row * 165)
			sprite.scale = Vector2.ONE * 0.32
			pages[0].add_child(sprite)
			_label(pages[0], String(id).replace("_", "\n"), sprite.position + Vector2(-49, 62), 12, 98)
			item_index += 1
		group_index += 1

func _anim(parent: Node, frames: SpriteFrames, anim: String, pos: Vector2, size: float = 78) -> void:
	var sprite := AnimatedSprite2D.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/shot_pixels.gdshader")
	sprite.material = mat
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames = frames
	sprite.animation = anim
	sprite.scale = Vector2.ONE * size / 222.0
	sprite.position = pos
	sprite.animation_finished.connect(sprite.play)
	parent.add_child(sprite)
	animations.append(sprite)
	sprite.play()

func _build_guns() -> void:
	for row in GUNS.size():
		var info: Array = GUNS[row]
		var frames: SpriteFrames = load("res://art/fx/%s/%s.tres" % [info[1], info[1]])
		_label(pages[1], info[0], Vector2(10, 135 + row * 110), 19, 230)
		for col in 4:
			var pos := Vector2(365 + col * 250, 145 + row * 110)
			_anim(pages[1], frames, info[2][col], pos)
			_label(pages[1], info[2][col], pos + Vector2(-95, 42), 14, 190)

func _build_bosses() -> void:
	var names := [["charge_dust", "spin_loop", "ram_impact", "meltdown"],
		["acid_charge", "acid_stream_loop", "acid_splash", "phase_shift"]]
	for row in 2:
		var id: String = ["rammer_attacks", "chimera_attacks"][row]
		var frames: SpriteFrames = load("res://art/fx/%s/%s.tres" % [id, id])
		_label(pages[2], ["Джаггернаут-Таран", "Фантом-Химера"][row], Vector2(20, 86 + row * 285), 24, 1240)
		for col in 4:
			var pos := Vector2(175 + col * 310, 225 + row * 285)
			_anim(pages[2], frames, names[row][col], pos, 160)
			_label(pages[2], names[row][col], pos + Vector2(-120, 97), 18, 240)
