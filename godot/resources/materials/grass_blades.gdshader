shader_type spatial;
render_mode cull_disabled;
// Prato basso (D-083, 12 ottobre 2026; prima D-068 e restyling 2026-10-11): due quad
// incrociati per ciuffo con i fili dipinti dello strato 0 dell'array `plants` (tre colonne
// di ciuffi diversi, scelte dall'id di istanza), ritagliati con alpha scissor (passata
// opaca), colore per istanza dal MultiMesh. Il vento e il campo condiviso di
// wind.gdshaderinc: raffiche che attraversano il prato, non lame che tremano da sole.

#include "res://resources/materials/wind.gdshaderinc"

uniform sampler2DArray plants_albedo : source_color, filter_linear_mipmap, repeat_disable;
// Colonne di varianti nello strato dei ciuffi.
uniform float variant_columns = 3.0;
// Ampiezza massima dello spostamento della punta, in metri (nel sistema del ciuffo).
uniform float wind_strength = 0.14;
// Altezza del quad in unita locali (per normalizzare VERTEX.y).
uniform float blade_height = 0.40;

varying vec3 world_pos;
varying float variant;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	variant = float(INSTANCE_ID % 3);
	float seed = fract(float(INSTANCE_ID) * 0.6180339);
	VERTEX += wind_offset(origin.xz, VERTEX.y / blade_height, wind_strength, seed, TIME);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// UV.y = 0 in punta, 1 al piede; la tile ha la punta in alto.
	vec2 uv = vec2((UV.x + variant) / variant_columns, UV.y);
	vec4 tex = texture(plants_albedo, vec3(uv, 0.0));
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Il colore di istanza e scuro (LEAF_TINTS): modula solo la tonalita.
	vec3 hue = COLOR.rgb / max(max(COLOR.r, COLOR.g), max(COLOR.b, 0.001));
	vec3 col = tex.rgb * mix(vec3(1.0), hue, 0.5) * (0.85 + 0.3 * value_noise(world_pos.xz * 1.3));
	// Piede che affonda nel terreno: piu scuro verso la base, cosi i fili non galleggiano.
	col *= mix(1.0, 0.78, smoothstep(0.55, 1.0, UV.y));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = col * 0.3;
}
