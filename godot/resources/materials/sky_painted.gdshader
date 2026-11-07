shader_type sky;
// Cielo a gradiente dipinto (restyling 2026-10-11): tre colori interpolati con fasce
// leggere e un alone caldo attorno al sole. DayNightCycle interpola `top_color` e
// `horizon_color` verso la notte. Niente nuvole: la camera e quasi a piombo, del cielo
// si vedono soprattutto riflessi e nebbia.

uniform vec3 top_color : source_color = vec3(0.26, 0.46, 0.82);
uniform vec3 horizon_color : source_color = vec3(0.96, 0.80, 0.62);
uniform vec3 ground_color : source_color = vec3(0.42, 0.38, 0.28);
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.75, 0.45);
// Ampiezza delle fasce (pennellate orizzontali) sul gradiente.
uniform float band_noise = 0.06;

float band_hash(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void sky() {
	float h = EYEDIR.y;
	// Fasce: piccolo scarto del gradiente a scalini, come pennellate orizzontali.
	float bands = (band_hash(floor(h * 36.0)) - 0.5) * band_noise;
	vec3 col;
	if (h >= 0.0) {
		float t = smoothstep(0.0, 0.55, h + bands);
		col = mix(horizon_color, top_color, t);
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.25, -h));
	}
	float sun = pow(max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0), 24.0);
	col += sun_glow_color * sun * 0.6 * LIGHT0_ENERGY * float(LIGHT0_ENABLED);
	COLOR = col;
}
