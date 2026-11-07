shader_type canvas_item;
// Cielo dipinto al tramonto per lo sfondo del menu iniziale (D-080): stessi colori
// della famiglia di `sky_painted.gdshader`, ridotti a 2D con bande di rumore che
// scorrono piano, sole basso a destra, terra scura sotto l'orizzonte e vignetta.
uniform vec3 top_color : source_color = vec3(0.16, 0.14, 0.30);
uniform vec3 horizon_color : source_color = vec3(0.96, 0.60, 0.36);
uniform vec3 ground_color : source_color = vec3(0.09, 0.07, 0.05);
uniform vec3 sun_color : source_color = vec3(1.0, 0.78, 0.45);
uniform vec2 sun_position = vec2(0.72, 0.58);
uniform float drift = 0.004;

float hash(vec2 p) {
	// Hash senza seno: stabile anche con coordinate grandi (niente rettangoli).
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float bands = (noise(vec2(uv.x * 5.0 + TIME * drift, uv.y * 12.0)) * 0.6 + noise(vec2(uv.x * 11.0 - TIME * drift, uv.y * 25.0)) * 0.4) * 0.06;
	float horizon = 0.62;
	vec3 sky = mix(top_color, horizon_color, smoothstep(0.0, horizon, uv.y + bands));
	float sun = exp(-length((uv - sun_position) * vec2(1.6, 1.0)) * 9.0);
	sky += sun_color * sun * 0.55;
	float ground = smoothstep(horizon + 0.02, horizon + 0.08, uv.y);
	vec3 color = mix(sky, ground_color, ground);
	float vignette = smoothstep(1.2, 0.35, length((uv - 0.5) * vec2(1.3, 1.0)));
	COLOR = vec4(color * mix(0.55, 1.0, vignette), 1.0);
}
