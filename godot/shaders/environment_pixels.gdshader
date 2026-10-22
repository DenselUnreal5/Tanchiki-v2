shader_type canvas_item;
render_mode unshaded;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	vec4 px = texture(TEXTURE, UV);
	vec2 cell = fract(UV * vec2(4.0, 3.0));
	float gutter = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
	if (px.a < 0.55 || gutter < 0.006) { discard; }
	COLOR = vec4(px.rgb, 1.0) * tint;
}
