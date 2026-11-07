shader_type spatial;
// Lamiera arrugginita (auto, vagoni, pali): vernice residua, ruggine a macchie,
// muschio sulle superfici rivolte in alto. Coordinate mondo.

#include "res://resources/materials/noise.gdshaderinc"

instance uniform vec4 paint : source_color = vec4(0.85, 0.66, 0.16, 1.0);
// 0 = vernice intatta, 1 = tutta ruggine.
instance uniform float rust = 0.55;
instance uniform float overgrowth = 0.4;

uniform vec3 rust_a : source_color = vec3(0.45, 0.20, 0.08);
uniform vec3 rust_b : source_color = vec3(0.70, 0.36, 0.12);
uniform vec3 moss_a : source_color = vec3(0.16, 0.32, 0.08);
uniform vec3 moss_b : source_color = vec3(0.36, 0.48, 0.12);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec2 uv = abs(n.y) > 0.5 ? world_pos.xz : (abs(n.x) > abs(n.z) ? world_pos.zy : world_pos.xy);

	float r = smoothstep(0.45, 0.55, fbm(uv * 0.9) + rust * 0.6 - 0.3);
	vec3 rust_col = mix(rust_a, rust_b, value_noise(uv * 3.0));
	vec3 col = mix(paint.rgb * (0.8 + 0.25 * value_noise(uv * 2.0)), rust_col, r);

	float moss = smoothstep(0.45, 0.8, n.y) * smoothstep(0.4, 0.5, fbm(world_pos.xz * 0.7) + overgrowth * 0.35);
	vec3 moss_col = mix(moss_a, moss_b, value_noise(world_pos.xz * 1.5));

	ALBEDO = mix(col, moss_col, moss);
	ROUGHNESS = mix(0.55, 0.9, max(r, moss));
	METALLIC = 0.35 * (1.0 - r) * (1.0 - moss);
}
