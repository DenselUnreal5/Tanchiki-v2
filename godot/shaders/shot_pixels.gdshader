shader_type canvas_item;
render_mode unshaded;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// Generated sheets contain faint matte fringes. Keep only solid pixel clusters
// and a transparent gutter at each atlas cell, without additive rectangle halos.
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	vec2 cell = fract(UV * vec2(8.0, 4.0));
	float edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
	if (texel.a < 0.55 || edge < 0.018) { discard; }
	COLOR = vec4(texel.rgb, 1.0) * tint;
}
