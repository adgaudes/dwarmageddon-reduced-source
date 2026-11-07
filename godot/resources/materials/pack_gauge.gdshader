shader_type spatial;
render_mode cull_back;
// Striscia dello zainetto di terra (spec terreno continuo, sezione 3): si riempie dal
// basso. La UV verticale della striscia vale 1 in basso e 0 in alto (export glTF).
uniform float pack_fill : hint_range(0.0, 1.0) = 0.0;
uniform vec3 empty_color : source_color = vec3(0.82, 0.78, 0.7);
uniform vec3 full_color : source_color = vec3(0.28, 0.2, 0.12);


void fragment() {
	float filled = step(1.0 - UV.y, pack_fill);
	ALBEDO = mix(empty_color, full_color, filled);
	ROUGHNESS = 0.7;
}
