shader_type spatial;
render_mode cull_disabled;
// Fili del prato a particelle (playtest del 14 ottobre 2026, O-09): ciuffi di lame
// affusolate generati da GrassField, piazzati da grass_field_process.gdshader. UV.y e
// l'altezza normalizzata della lama (0 al piede, 1 in punta), UV.x sfasa la lama nel
// ciuffo. Il colore viene dalla color map del terreno (COLOR) mescolata alla tinta del
// prato; il vento e quello condiviso della vegetazione (wind.gdshaderinc).

#include "res://resources/materials/wind.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.17, 0.27, 0.08);
uniform vec3 tip_color : source_color = vec3(0.58, 0.68, 0.27);
uniform vec3 dry_color : source_color = vec3(0.62, 0.56, 0.30);
// Quanto la color map del terreno tinge i fili.
uniform float ground_tint = 0.2;
uniform float wind_strength = 0.22;

varying float tip;
varying float seed;
varying vec3 world_pos;

void vertex() {
	tip = UV.y;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	seed = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	VERTEX += wind_offset(origin.xz, tip, wind_strength, seed + UV.x, TIME);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = mix(base_color, tip_color, smoothstep(0.0, 1.0, tip));
	// Chiazze secche e variazione per ciuffo, cosi il prato non e un tappeto uniforme.
	float dry = smoothstep(0.55, 0.85, value_noise(world_pos.xz * 0.18)) * 0.6 + seed * 0.15;
	col = mix(col, dry_color, dry * smoothstep(0.2, 1.0, tip));
	col *= 0.85 + 0.3 * seed;
	col = mix(col, col * COLOR.rgb * 1.6, ground_tint);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
	// Piede in ombra: occlusione finta che lega i fili al terreno.
	AO = mix(0.35, 1.0, smoothstep(0.0, 0.6, tip));
	AO_LIGHT_AFFECT = 0.4;
	BACKLIGHT = col * 0.45;
}
