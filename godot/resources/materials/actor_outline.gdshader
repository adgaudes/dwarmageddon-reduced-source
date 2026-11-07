shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
// Contorno degli attori (D-070): guscio rovesciato, vertici spinti lungo la normale.
// Si usa come `next_pass` di actor_paint.gdshader (ActorModel.outline_material()).

uniform vec3 color : source_color = vec3(0.05, 0.04, 0.03);
uniform float width = 0.028;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color;
}
