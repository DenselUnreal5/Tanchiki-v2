# ============================================================================
# post_fx.gd — цветокоррекция, свечение и виньетка поверх картинки мира.
#
# Материал вешается на SubViewportContainer каждого игрока: обрабатывается
# только мир, HUD и меню рисуются поверх и не трогаются.
#
# Главная мысль: градация не статичный «фильтр», а продолжение погоды.
# В игре уже есть цикл дня и ночи и условия (ясно/дождь/туман/гроза) —
# именно они и ведут экспозицию, насыщенность и тонировку. Ночью картинка
# уходит в холод и теряет цвет, в туман поднимается чёрное, в грозу молния
# на мгновение выбивает экспозицию вверх.
# ============================================================================
class_name PostFx
extends RefCounted

## Уровни качества (хранятся в профиле).
const OFF := 0
const MEDIUM := 1   # градация + виньетка
const HIGH := 2     # то же плюс экранное свечение

const SHADER_PATH := "res://shaders/post_fx.gdshader"

## Настройки для дня и для ночи; между ними интерполируем по освещённости.
## Экспозиция намеренно чуть выше единицы и днём, и ночью: мир уже
## затемняется собственным погодным слоем (WorldView._draw_weather), и если
## градация снова уводит яркость вниз, картинка становится грязной.
## Настроение здесь делают тонировка и насыщенность, а не общее затемнение.
const DAY := {
	"exposure": 1.05, "contrast": 1.06, "saturation": 1.06,
	"shadow": Color(0.95, 0.98, 1.06), "highlight": Color(1.06, 1.02, 0.94),
	"vignette": 0.16, "bloom": 0.5, "threshold": 0.66,
}
const NIGHT := {
	"exposure": 1.08, "contrast": 1.12, "saturation": 0.80,
	"shadow": Color(0.80, 0.88, 1.18), "highlight": Color(1.02, 0.97, 0.88),
	"vignette": 0.34, "bloom": 0.95, "threshold": 0.46,
}

static func make_material(quality: int) -> ShaderMaterial:
	if quality <= OFF:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	return mat

## Пересчитывает параметры под текущее состояние мира.
## @param view_size размер области просмотра игрока в пикселях
static func update(mat: ShaderMaterial, world, player, view_size: Vector2, quality: int) -> void:
	if mat == null or world == null:
		return

	var w = world.weather
	# Настройки могут выключить погоду и цикл дня и ночи: тогда градация
	# остаётся ровной дневной, без ночного холода и дымки.
	var k := Sets.weather_scale()
	var light: float = w.light if (w != null and Sets.day_night) else 1.0
	var fog: float = w.fog * k if w != null else 0.0
	var rain: float = w.rain * k if w != null else 0.0
	var flash: float = w.flash * k if w != null else 0.0
	var t := clampf((light - 0.18) / 0.82, 0.0, 1.0)  # 0 — ночь, 1 — день

	var exposure := lerpf(NIGHT["exposure"], DAY["exposure"], t)
	var contrast := lerpf(NIGHT["contrast"], DAY["contrast"], t)
	var saturation := lerpf(NIGHT["saturation"], DAY["saturation"], t)
	var vignette := lerpf(NIGHT["vignette"], DAY["vignette"], t)
	var shadow: Color = NIGHT["shadow"].lerp(DAY["shadow"], t)
	var highlight: Color = NIGHT["highlight"].lerp(DAY["highlight"], t)
	var lift := 0.0

	# --- туман: дымка съедает глубину теней и цвет
	lift += 0.07 * fog
	saturation *= 1.0 - 0.28 * fog
	contrast *= 1.0 - 0.14 * fog

	# --- дождь: холодный и блёклый кадр
	saturation *= 1.0 - 0.18 * rain
	shadow = shadow.lerp(Color(0.80, 0.88, 1.12), 0.35 * rain)

	# --- молния: мгновенная передержка
	exposure += flash * 0.38
	saturation += flash * 0.25

	# --- тяжёлое ранение: кадр обесцвечивается и уходит в красное
	if player != null and player.tank != null and player.tank.alive:
		var hp_ratio: float = player.tank.hp / maxf(1.0, player.tank.max_hp)
		if hp_ratio < 0.35:
			var hurt := clampf((0.35 - hp_ratio) / 0.35, 0.0, 1.0)
			saturation *= 1.0 - 0.45 * hurt
			shadow = shadow.lerp(Color(1.15, 0.72, 0.70), 0.6 * hurt)
			vignette += 0.25 * hurt

	mat.set_shader_parameter("exposure", exposure)
	mat.set_shader_parameter("contrast", contrast)
	mat.set_shader_parameter("saturation", maxf(0.0, saturation))
	mat.set_shader_parameter("lift", lift)
	mat.set_shader_parameter("shadow_tint", Vector3(shadow.r, shadow.g, shadow.b))
	mat.set_shader_parameter("highlight_tint", Vector3(highlight.r, highlight.g, highlight.b))
	mat.set_shader_parameter("vignette", clampf(vignette, 0.0, 1.0))
	mat.set_shader_parameter("vignette_soft", 0.55)
	mat.set_shader_parameter("aspect", view_size.x / maxf(1.0, view_size.y))

	# --- свечение
	if quality >= HIGH:
		var bloom := lerpf(NIGHT["bloom"], DAY["bloom"], t)
		bloom += 0.3 * fog + 0.35 * flash
		mat.set_shader_parameter("bloom", bloom)
		mat.set_shader_parameter("bloom_threshold", lerpf(NIGHT["threshold"], DAY["threshold"], t))
		mat.set_shader_parameter("bloom_radius", 7.0)
		mat.set_shader_parameter("texel", Vector2(1.0 / maxf(1.0, view_size.x), 1.0 / maxf(1.0, view_size.y)))
	else:
		mat.set_shader_parameter("bloom", 0.0)
