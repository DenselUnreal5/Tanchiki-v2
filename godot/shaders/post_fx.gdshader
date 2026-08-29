// ============================================================================
// post_fx.gdshader — постобработка игрового мира.
//
// Материал вешается на SubViewportContainer, поэтому обрабатывается ровно
// картинка мира: HUD, меню и оверлеи рисуются поверх и остаются чистыми.
//
// Порядок операций такой же, как в киношном пайплайне: сначала свечение
// (оно работает с исходной яркостью), затем экспозиция, подъём чёрного,
// контраст, насыщенность, раздельная тонировка теней и светов, виньетка.
// ============================================================================
shader_type canvas_item;
render_mode unshaded;

// ---------------------------------------------------------------- свечение
// Сила свечения. 0 — выключено (шейдер тогда не делает лишних выборок).
uniform float bloom : hint_range(0.0, 2.0) = 0.0;
// Яркость, с которой пиксель начинает светиться.
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.62;
// Радиус в пикселях: во сколько текселей уходят кольца выборок.
uniform float bloom_radius : hint_range(1.0, 24.0) = 6.0;
// Размер одного текселя вьюпорта (1/ширина, 1/высота).
uniform vec2 texel = vec2(0.00078, 0.00139);

// ---------------------------------------------------------------- градация
uniform float exposure : hint_range(0.2, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
// Подъём чёрного: туман и дымка «съедают» глубину теней.
uniform float lift : hint_range(0.0, 0.3) = 0.0;
// Раздельная тонировка: цвет теней и цвет светов.
uniform vec3 shadow_tint : source_color = vec3(1.0);
uniform vec3 highlight_tint : source_color = vec3(1.0);

// ---------------------------------------------------------------- виньетка
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_soft : hint_range(0.1, 1.2) = 0.55;
// Соотношение сторон вьюпорта, чтобы виньетка была круглой, а не овальной.
uniform float aspect = 1.777;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// Сколько яркости пикселя уходит в свечение.
vec3 bright_pass(vec3 c) {
	float l = dot(c, LUMA);
	float k = max(l - bloom_threshold, 0.0) / max(1.0 - bloom_threshold, 0.001);
	return c * k * k;
}

void fragment() {
	vec3 col = texture(TEXTURE, UV).rgb;

	// ---- свечение: два кольца по 6 выборок.
	// Полноценный многопроходный блюр здесь не нужен и не по карману слабым
	// видеокартам: яркие объекты в игре мелкие и контрастные, им хватает
	// широкого мягкого ореола.
	if (bloom > 0.001) {
		vec3 sum = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			float a = float(i) * 1.0472;  // 60°
			vec2 d = vec2(cos(a), sin(a));
			vec2 o1 = clamp(UV + d * texel * bloom_radius, vec2(0.0), vec2(1.0));
			vec2 o2 = clamp(UV - d * texel * bloom_radius * 2.2, vec2(0.0), vec2(1.0));
			sum += bright_pass(texture(TEXTURE, o1).rgb);
			sum += bright_pass(texture(TEXTURE, o2).rgb) * 0.55;
		}
		col += sum * (bloom / 9.3);
	}

	// ---- тональная коррекция
	col *= exposure;
	col = col * (1.0 - lift) + vec3(lift);
	col = (col - 0.5) * contrast + 0.5;

	float l = dot(max(col, vec3(0.0)), LUMA);
	col = mix(vec3(l), col, saturation);
	col *= mix(shadow_tint, highlight_tint, smoothstep(0.0, 0.75, l));

	// ---- виньетка
	if (vignette > 0.001) {
		vec2 d = (UV - vec2(0.5)) * vec2(aspect, 1.0);
		float r = length(d) * 1.42;
		col *= mix(1.0, smoothstep(1.05, vignette_soft, r), vignette);
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
