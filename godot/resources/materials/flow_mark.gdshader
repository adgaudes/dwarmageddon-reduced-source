shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Impronte dell'orda (FlowPreview): un quad a terra per impronta, disegnato qui.
// COLOR = colore di istanza del MultiMesh; INSTANCE_CUSTOM.x = forma
// (0 gallone che punta verso -Z locale, 1 sbarra "strada chiusa");
// INSTANCE_CUSTOM.y = metri che mancano al giocatore, per l'onda che scorre verso di lui.

uniform float fade = 1.0;
uniform float pulse_speed = 5.0;
uniform float pulse_length = 4.8; // metri fra due creste dell'onda
uniform float pulse_depth = 0.45; // quanto l'onda scurisce fra due creste

varying float shape;
varying float remaining;

void vertex() {
	shape = INSTANCE_CUSTOM.x;
	remaining = INSTANCE_CUSTOM.y;
}

float band(float d, float half_width, float soft) {
	return 1.0 - smoothstep(half_width - soft, half_width + soft, abs(d));
}

void fragment() {
	vec2 p = UV - 0.5; // p.y < 0 = avanti
	float soft = 0.03;
	float fill;
	float edge;
	if (shape < 0.5) {
		// Gallone: punta in avanti, due bracci all'indietro.
		float d = (p.y + 0.24) - abs(p.x) * 0.95;
		float side = 1.0 - smoothstep(0.40, 0.44, abs(p.x));
		fill = band(d, 0.10, soft) * side;
		edge = band(d, 0.17, soft) * (1.0 - smoothstep(0.45, 0.49, abs(p.x)));
	} else {
		// Sbarra trasversale con due tacche: il percorso finisce qui.
		float side = 1.0 - smoothstep(0.42, 0.46, abs(p.x));
		float stripes = step(0.5, fract(p.x * 4.0 + 0.25));
		fill = band(p.y, 0.15, soft) * side * mix(0.45, 1.0, stripes);
		edge = band(p.y, 0.22, soft) * (1.0 - smoothstep(0.46, 0.5, abs(p.x)));
	}
	float wave = 0.5 + 0.5 * sin(remaining * 6.2831853 / pulse_length + TIME * pulse_speed);
	float glow = mix(1.0 - pulse_depth, 1.0, wave);
	// Bordo scuro sotto il colore: resta leggibile su erba chiara e su terra.
	vec3 dark = COLOR.rgb * 0.12;
	ALBEDO = mix(dark, COLOR.rgb * (0.75 + 0.5 * wave), fill);
	ALPHA = max(fill * glow, edge * 0.6) * COLOR.a * fade;
}
