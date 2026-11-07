shader_type spatial;
// Attori low-poly (tools/blender/build_actor_assets.py): il colore sta nei vertici,
// cosi un attore costa una sola superficie. Due indicatori nelle UV:
//   UV.x = 1  la faccia emette luce (occhi, fari);
//   UV.y = 1  la faccia e "vernice": il colore di vertice fa da ombreggiatura e la
//             tinta la decide il codice di gioco (`tint`).

uniform vec3 tint : source_color = vec3(1.0);
uniform float emission_energy = 2.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	ALBEDO = COLOR.rgb * mix(vec3(1.0), tint, UV.y);
	ROUGHNESS = roughness;
	EMISSION = COLOR.rgb * UV.x * emission_energy;
}
