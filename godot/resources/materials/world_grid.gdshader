shader_type spatial;
// Sostituto del WorldGridMaterial Unreal: griglia in coordinate mondo,
// indipendente dalla scala della mesh. Linea fine ogni metro, marcata ogni 10.

uniform vec3 base_color : source_color = vec3(0.42, 0.42, 0.42);
uniform vec3 line_color : source_color = vec3(0.30, 0.30, 0.30);
uniform float minor_spacing = 1.0;
uniform float major_spacing = 10.0;
uniform float minor_width = 0.02;
uniform float major_width = 0.06;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float spacing, float width) {
	vec2 d = abs(fract(p / spacing + 0.5) - 0.5) * spacing;
	vec2 aa = fwidth(p);
	vec2 l = 1.0 - smoothstep(vec2(width * 0.5), vec2(width * 0.5) + aa, d);
	return max(l.x, l.y);
}

void fragment() {
	float minor = grid_line(world_pos.xz, minor_spacing, minor_width);
	float major = grid_line(world_pos.xz, major_spacing, major_width);
	float line = max(minor * 0.5, major);
	ALBEDO = mix(base_color, line_color, line);
	ROUGHNESS = 0.9;
}
