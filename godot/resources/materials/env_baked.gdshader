shader_type spatial;
// Prop dell'ambiente con texture cotta (D-073: auto, vagoni, barriere, lampioni, tronchi).
// Colore, usura degli spigoli, occlusione e sporco vengono dalla texture cotta in
// Blender; per istanza restano la tinta sulle superfici "vernice", la ruggine a macchie
// (solo sulla vernice: e dove la vernice e saltata) e il muschio sulle facce rivolte in
// alto, in coordinate mondo come in rusted_metal.gdshader.
// Dal restyling 2026-10-11 legge anche normal map e ORM cotte (`has_maps`) e aggiunge
// una rim light leggera, come gli attori.

#include "res://resources/materials/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
// R occlusione, G roughness, B metallo.
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform bool has_maps = false;
// 1 = superficie "vernice": moltiplicata per `tint` e soggetta alla ruggine.
uniform float tintable = 0.0;
uniform float base_roughness = 0.7;
uniform float base_metallic = 0.0;
uniform float rim_strength = 0.08;

// Si chiama `tint` come nel fogliame: un albero ha tronco cotto e chioma sullo stesso
// nodo, e le uniform per istanza di materiali diversi condividono gli indici.
instance uniform vec4 tint : source_color = vec4(1.0);
// 0 = vernice intatta, 1 = tutta ruggine (solo dove `tintable` = 1).
instance uniform float rust = 0.0;
instance uniform float overgrowth = 0.0;

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

	vec3 tex = texture(albedo_tex, UV).rgb;
	vec3 col = mix(tex, tex * tint.rgb, tintable);
	// La ruggine tiene l'usura cotta: piu chiara dove la texture e chiara.
	float r = tintable * smoothstep(0.45, 0.58, fbm(uv * 0.9) + rust * 0.6 - 0.3);
	vec3 rust_col = mix(rust_a, rust_b, value_noise(uv * 3.0)) * (0.6 + 0.6 * dot(tex, vec3(0.333)));
	col = mix(col, rust_col, r);

	float moss = smoothstep(0.45, 0.8, n.y) * smoothstep(0.4, 0.5, fbm(world_pos.xz * 0.7) + overgrowth * 0.35);
	vec3 moss_col = mix(moss_a, moss_b, value_noise(world_pos.xz * 1.5));

	float rough = base_roughness;
	float metal = base_metallic;
	if (has_maps) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
		vec3 orm = texture(orm_tex, UV).rgb;
		rough = orm.g;
		metal = orm.b;
		AO = orm.r;
		AO_LIGHT_AFFECT = 0.3;
	}
	ALBEDO = mix(col, moss_col, moss);
	ROUGHNESS = mix(rough, 0.9, max(r, moss));
	METALLIC = metal * (1.0 - r) * (1.0 - moss);
	RIM = rim_strength;
	RIM_TINT = 0.8;
}
