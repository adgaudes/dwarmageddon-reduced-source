shader_type spatial;
// SPIKE: superficie del terreno a rilievo continuo (HeightTerrain). La quota arriva da
// una texture (R = quota in metri, G = scarto dal rilievo naturale): il vertice sale o
// scende qui, la normale si ricava dalle quote vicine. Erba dove nessuno ha toccato,
// terra chiara sui cumuli, terra scura negli scavi, terra nuda sui pendii ripidi.

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float resolution = 193.0;
uniform float cell = 0.5;
uniform vec3 grass : source_color = vec3(0.30, 0.46, 0.16);
uniform vec3 grass_dry : source_color = vec3(0.47, 0.50, 0.20);
uniform vec3 mound : source_color = vec3(0.56, 0.40, 0.22);
uniform vec3 pit : source_color = vec3(0.27, 0.18, 0.11);
uniform vec3 cliff : source_color = vec3(0.42, 0.30, 0.18);

varying vec2 height_uv;
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// I vertici cadono sui centri dei texel.
	height_uv = (UV * (resolution - 1.0) + 0.5) / resolution;
	VERTEX.y = textureLod(height_map, height_uv, 0.0).r;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float texel = 1.0 / resolution;
	float left = textureLod(height_map, height_uv - vec2(texel, 0.0), 0.0).r;
	float right = textureLod(height_map, height_uv + vec2(texel, 0.0), 0.0).r;
	float up = textureLod(height_map, height_uv - vec2(0.0, texel), 0.0).r;
	float down = textureLod(height_map, height_uv + vec2(0.0, texel), 0.0).r;
	vec3 normal = normalize(vec3(left - right, 2.0 * cell, up - down));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(normal, 0.0)).xyz);

	vec2 here = textureLod(height_map, height_uv, 0.0).rg;
	float delta = here.g;
	float steep = smoothstep(0.18, 0.42, 1.0 - normal.y);
	float disturbed = smoothstep(0.04, 0.3, abs(delta));
	// Due ottave ruotate fra loro: chiazze morbide, senza il reticolo del rumore a valori.
	vec2 turned = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * world_position.xz;
	float patches = value_noise(world_position.xz * 0.11) * 0.6 + value_noise(turned * 0.27 + 17.0) * 0.4;
	float grain = value_noise(turned * 3.1) * 0.6 + value_noise(world_position.xz * 7.3) * 0.4;

	vec3 ground = mix(grass, grass_dry, smoothstep(0.3, 0.75, patches) * 0.6) * (0.92 + grain * 0.16);
	vec3 soil = mix(mound, pit, smoothstep(-0.15, 0.15, -delta)) * (0.85 + grain * 0.3);
	// Strati sottili ogni 40 cm: dall'alto dicono quanto e alto un cumulo o fondo uno scavo.
	float strata = smoothstep(0.0, 0.06, abs(fract(here.r * 2.5) - 0.5) - 0.44);
	soil *= 1.0 - strata * 0.22;
	vec3 color = mix(ground, soil, disturbed);
	color = mix(color, cliff * (0.85 + grain * 0.3), steep * (1.0 - disturbed * 0.6));

	ALBEDO = color;
	ROUGHNESS = 0.95;
}
