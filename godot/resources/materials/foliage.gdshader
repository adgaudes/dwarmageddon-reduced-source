shader_type spatial;
render_mode cull_disabled;
// Vegetazione: colore per vertice o per istanza (MultiMesh), tinta per istanza, vento
// dal campo condiviso di wind.gdshaderinc (D-083: cespugli e chiome si piegano alle
// stesse raffiche del prato; prima un'oscillazione per istanza).
// Con `textured` (restyling 2026-10-11) la superficie e una cartella di foglie dipinte:
// lo strato `leaf_layer` dell'array `plants`, ritagliato con alpha scissor (cespugli,
// chiome). Senza, resta il colore pieno (fiori, rampicanti).

#include "res://resources/materials/wind.gdshaderinc"

instance uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2DArray plants_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform bool textured = false;
uniform float leaf_layer = 1.0;
// Ampiezza massima dello spostamento in unita locali della mesh.
uniform float wind_strength = 0.12;
// Altezza locale della mesh (per normalizzare VERTEX.y): 2 per le cartelle dei cespugli.
uniform float plant_height = 2.0;

varying vec3 world_pos;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float seed = fract(origin.x * 0.731 + origin.z * 0.417);
	VERTEX += wind_offset(origin.xz, VERTEX.y / plant_height, wind_strength, seed, TIME);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb * tint.rgb;
	if (textured) {
		vec4 tex = texture(plants_albedo, vec3(UV, leaf_layer));
		ALPHA = tex.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		// La tinta per istanza e scura (LEAF_TINTS): qui modula solo la tonalita,
		// la luminosita viene dalla texture dipinta.
		vec3 hue = tint.rgb / max(max(tint.r, tint.g), max(tint.b, 0.001));
		// Playtest del 14 ottobre: a 1,15 e con piena saturazione i cespugli erano verde
		// fosforescente accanto al prato e ai muri fotografici.
		col = tex.rgb * mix(vec3(1.0), hue, 0.45) * mix(vec3(1.0), COLOR.rgb, 0.5) * 0.72;
	}
	col *= 0.8 + 0.35 * value_noise(world_pos.xz * 1.3 + world_pos.y * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = col * 0.25;
}
