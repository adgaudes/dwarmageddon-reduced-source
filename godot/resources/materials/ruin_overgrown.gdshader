shader_type spatial;
// Edifici in rovina: facciate a finestre, colature, muschio sui piani orizzontali
// e rampicanti che scendono dal tetto e salgono da terra. Coordinate mondo.
// Dal playtest del 14 ottobre 2026 (O-10, D-090) gli strati `walls` sono texture CC0
// fotografiche di Poly Haven (tools/textures/fetch_wall_textures.py) con normal map:
// 0 intonaco con mattoni a vista, 1 muschio, 2 mattoni grezzi (bordi spezzati e corone),
// 3 calcestruzzo (facce orizzontali). Albedo, normal e ORM in triplanare, coordinate mondo.

#include "res://resources/materials/noise.gdshaderinc"

uniform sampler2DArray walls_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray walls_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray walls_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength = 1.0;
// Ripetizioni della tile per metro sui muri.
uniform float wall_tile_scale = 0.35;
const float WALL_PLASTER = 0.0;
const float WALL_MOSS = 1.0;
const float WALL_BRICK = 2.0;
const float WALL_CONCRETE = 3.0;

instance uniform vec4 base_tint : source_color = vec4(0.66, 0.62, 0.55, 1.0);
// Quota mondo del tetto del blocco: i rampicanti partono da qui.
instance uniform float top_y = 10.0;
// 0 = pulito, 1 = sommerso dal verde.
instance uniform float overgrowth = 0.5;
// 0 = muro pieno, 1 = facciata a finestre.
instance uniform float windows = 1.0;
// Quanto i rampicanti coprono le pareti vicino a tetto e terra: 1 per le torri,
// meno per le rovine basse (tutta la parete e vicina a entrambi e sarebbe solo verde).
instance uniform float vine_reach = 1.0;
// Con `batched` (corone dei muri in MultiMesh, D-068) tinta e verde vengono dal
// colore di istanza: RGB = tinta, A = overgrowth; niente finestre ne rampicanti dall'alto.
uniform bool batched = false;

uniform vec3 moss_a : source_color = vec3(0.15, 0.30, 0.07);
uniform vec3 moss_b : source_color = vec3(0.36, 0.48, 0.12);
uniform vec3 window_dark : source_color = vec3(0.07, 0.07, 0.06);
uniform float floor_height = 3.2;
uniform float bay_width = 2.6;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 instance_color;

vec3 wall_triplanar(sampler2DArray tex, vec3 p, vec3 n, float layer) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, vec3(p.zy * wall_tile_scale, layer)).rgb * w.x
		+ texture(tex, vec3(p.xz * wall_tile_scale, layer)).rgb * w.y
		+ texture(tex, vec3(p.xy * wall_tile_scale, layer)).rgb * w.z;
}

// Normal map in triplanare, fusione "whiteout" (Ben Golus): normale mondo perturbata.
vec3 wall_triplanar_normal(vec3 p, vec3 n, float layer) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 tx = texture(walls_normal, vec3(p.zy * wall_tile_scale, layer)).rgb * 2.0 - 1.0;
	vec3 ty = texture(walls_normal, vec3(p.xz * wall_tile_scale, layer)).rgb * 2.0 - 1.0;
	vec3 tz = texture(walls_normal, vec3(p.xy * wall_tile_scale, layer)).rgb * 2.0 - 1.0;
	tx = vec3(tx.xy * normal_strength + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy * normal_strength + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy * normal_strength + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	instance_color = COLOR;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float up = n.y;
	float side = 1.0 - abs(up);
	vec2 uv = abs(n.x) > abs(n.z) ? world_pos.zy : world_pos.xy;
	if (up > 0.5 || up < -0.5) {
		uv = world_pos.xz;
	}

	vec3 tint_rgb = batched ? instance_color.rgb : base_tint.rgb;
	float growth = batched ? instance_color.a : overgrowth;
	float win_amount = batched ? 0.0 : windows;
	float roof_y = batched ? world_pos.y + 100.0 : top_y;
	// Superficie: intonaco sulle pareti, calcestruzzo sulle facce orizzontali (pavimenti,
	// solai, cime), mattoni grezzi sulle corone e sotto il bordo dei tratti crollati.
	float edge = batched ? 1.0 : smoothstep(0.55, 0.05, roof_y - world_pos.y) * step(0.5, side);
	float brick_mask = clamp(edge * smoothstep(0.35, 0.6, fbm(uv * 0.9 + 11.0) + edge * 0.4), 0.0, 1.0);
	float layer = abs(up) > 0.6 ? WALL_CONCRETE : WALL_PLASTER;
	vec3 surface = wall_triplanar(walls_albedo, world_pos, n, layer);
	vec3 surface_orm = wall_triplanar(walls_orm, world_pos, n, layer);
	vec3 surface_n = wall_triplanar_normal(world_pos, n, layer);
	if (brick_mask > 0.01) {
		surface = mix(surface, wall_triplanar(walls_albedo, world_pos, n, WALL_BRICK), brick_mask);
		surface_orm = mix(surface_orm, wall_triplanar(walls_orm, world_pos, n, WALL_BRICK), brick_mask);
		surface_n = normalize(mix(surface_n, wall_triplanar_normal(world_pos, n, WALL_BRICK), brick_mask));
	}
	vec3 plaster_orm = surface_orm;
	// Tinta per istanza solo come velatura: le texture fotografiche hanno gia il loro colore
	// (le tinte sono chiare, circa 0,65: si normalizzano).
	vec3 col = surface * mix(vec3(1.0), tint_rgb / 0.65, 0.45) * (0.9 + 0.2 * fbm(uv * 0.35));
	// Colature verticali.
	col *= 0.86 + 0.18 * value_noise(vec2(uv.x * 2.5, uv.y * 0.15));
	// Umidita sotto il tetto: una fascia piu scura a mezza altezza.
	float damp = smoothstep(roof_y - 0.2, roof_y - 1.6, world_pos.y) * (1.0 - smoothstep(roof_y - 1.6, roof_y - 3.2, world_pos.y));
	col *= 1.0 - 0.22 * damp * side * fbm(uv * 0.8);
	// Crepe sottili sulle pareti e sporco al piede (D-068).
	float crack = 1.0 - smoothstep(0.0, 0.014, abs(fbm(uv * 0.6 + 5.0) - 0.5));
	col *= 1.0 - 0.45 * crack * side;
	col *= mix(mix(0.72, 1.0, smoothstep(0.0, 0.7, world_pos.y)), 1.0, 1.0 - side);

	// Finestre: alcune murate, alcune sfondate (piu scure), nessuna al piano terra pieno.
	vec2 cell = vec2(uv.x / bay_width, uv.y / floor_height);
	vec2 f = fract(cell);
	float hole = step(0.22, f.x) * step(f.x, 0.78) * step(0.28, f.y) * step(f.y, 0.82);
	float frame = step(0.18, f.x) * step(f.x, 0.82) * step(0.25, f.y) * step(f.y, 0.86) - hole;
	float present = step(0.18, hash12(floor(cell) + vec2(3.0, 7.0)));
	float allowed = win_amount * side * step(0.9, world_pos.y);
	float win = hole * present * allowed;
	vec3 window_col = window_dark * (0.8 + 0.6 * hash12(floor(cell)));
	// Cornice e davanzale: il vano sembra incassato invece che dipinto (D-069).
	col = mix(col, col * 0.72, frame * present * allowed);
	col = mix(col, window_col, win);
	// Linea di solaio a ogni piano: la facciata si legge come edificio (D-070).
	float slab_line = step(fract(uv.y / floor_height + 0.04), 0.05) * win_amount * side * step(2.0, world_pos.y);
	col = mix(col, col * 0.78, slab_line);

	// Verde: muschio sopra, rampicanti dall'alto e dal basso sulle pareti.
	float vine_n = fbm(vec2(uv.x * 0.8, uv.y * 0.11));
	// Fili verticali e bordi sfrangiati invece di macchie piatte (D-068).
	float strands = value_noise(vec2(uv.x * 5.0, uv.y * 0.9)) * 0.14 + value_noise(uv * vec2(14.0, 3.0)) * 0.06;
	float from_top = 1.0 - smoothstep(0.0, 9.0, roof_y - world_pos.y);
	float from_ground = 1.0 - smoothstep(0.0, 6.0, world_pos.y);
	float vines = smoothstep(0.62, 0.72, vine_n + strands + growth * 0.35 + (from_top + from_ground) * 0.3 * vine_reach - 0.2);
	float moss_top = smoothstep(0.4, 0.8, up) * smoothstep(0.35, 0.45, fbm(world_pos.xz * 0.4) + growth * 0.3 - (1.0 - vine_reach) * 0.12);
	float green = clamp(max(vines * side * mix(0.4, 1.0, growth), moss_top), 0.0, 1.0);
	vec3 moss_tex = wall_triplanar(walls_albedo, world_pos, n, WALL_MOSS);
	vec3 moss = moss_tex * mix(moss_a, moss_b, fbm(world_pos.xz * 0.3 + world_pos.y * 0.15)) * 2.6;
	moss *= 0.8 + 0.35 * value_noise(uv * vec2(9.0, 2.5));

	ALBEDO = mix(col, moss, green);
	ROUGHNESS = mix(mix(0.7, 1.0, plaster_orm.g), 0.95, green);
	AO = plaster_orm.r;
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(surface_n, n, green * 0.6), 0.0)).xyz);
	AO_LIGHT_AFFECT = 0.3;
}
