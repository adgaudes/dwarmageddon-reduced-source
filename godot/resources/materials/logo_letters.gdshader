shader_type canvas_item;
// Gradiente verticale sul riempimento delle lettere del logo (D-079): la Label
// disegna i glifi bianchi e l'outline scuro; moltiplicando per il gradiente il
// bianco prende rame -> ocra e l'outline resta scuro. `top_y`/`bottom_y` in pixel
// locali della Label.
uniform vec3 top_color : source_color = vec3(0.93, 0.70, 0.38);
uniform vec3 bottom_color : source_color = vec3(0.65, 0.33, 0.14);
uniform vec3 rim_color : source_color = vec3(1.0, 0.92, 0.78);
uniform float top_y = 0.0;
uniform float bottom_y = 96.0;
// Bisello: luce dove il glifo finisce verso l'alto-sinistra, ombra verso il basso-destra.
uniform float bevel_px = 2.0;
uniform float bevel_strength = 0.45;

varying float t;

void vertex() {
	t = clamp((VERTEX.y - top_y) / max(bottom_y - top_y, 1.0), 0.0, 1.0);
}

void fragment() {
	vec4 glyph = texture(TEXTURE, UV) * COLOR;
	vec3 fill = mix(top_color, bottom_color, t);
	fill = mix(rim_color, fill, smoothstep(0.0, 0.12, t));
	vec2 step = TEXTURE_PIXEL_SIZE * bevel_px;
	float up_left = texture(TEXTURE, UV - step).a;
	float down_right = texture(TEXTURE, UV + step).a;
	float light = clamp(glyph.a - up_left, 0.0, 1.0);
	float shade = clamp(glyph.a - down_right, 0.0, 1.0);
	fill = mix(fill, rim_color, light * bevel_strength);
	fill = mix(fill, bottom_color * 0.6, shade * bevel_strength);
	COLOR = vec4(glyph.rgb * fill, glyph.a);
}
