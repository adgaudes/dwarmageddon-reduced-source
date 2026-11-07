class_name MenuDistrict
extends RuinsDistrict
## Angolo di quartiere per lo sfondo del menu (playtest del 14 ottobre 2026, O-12): gli
## stessi pezzi del livello 1 (rovine a moduli, alberi, auto, macerie, lampione, prato),
## composti a mano per la camera del menu e illuminati al tramonto. La camera guarda verso
## -Z: le rovine stanno dietro, i personaggi a destra del centro, il menu a sinistra.

const SUNSET_SUN := Color(1.0, 0.62, 0.34)
const SUNSET_TOP := Color(0.22, 0.24, 0.46)
const SUNSET_HORIZON := Color(0.92, 0.50, 0.30)
const SUNSET_GROUND := Color(0.20, 0.15, 0.12)
const SUNSET_AMBIENT := Color(0.56, 0.46, 0.58)
## Il sole sta dietro le rovine, a sinistra: sagome in controluce e ombre lunghe, ma il
## riflesso radente sul terreno cade fuori dall'inquadratura (di fronte sembrava acqua).
const MENU_SUN_DIRECTION := Vector3(0.62, -0.26, 0.74)


func _init() -> void:
	play_half_extent = 40.0
	plaza_radius_m = 3.0
	start_clear_radius = 0.0
	flowers = 600
	litter = 1500


func _compose() -> void:
	terrain_strokes.clear()
	_block_rects.clear()
	_reset_occupancy()
	stats["strokes"] = 0
	_reset_ruin_details()
	_low_ruin(0, Vector2(-10.0, -13.0), Vector2(11.0, 7.0))
	_low_ruin(1, Vector2(6.0, -18.0), Vector2(12.0, 8.0))
	_low_ruin(2, Vector2(-25.0, -4.0), Vector2(8.0, 10.0))
	_low_ruin(3, Vector2(22.0, -7.0), Vector2(9.0, 8.0))
	_low_ruin(4, Vector2(-4.0, -32.0), Vector2(14.0, 9.0))
	_tree(Vector3(-4.5, 0.0, -4.0), 1.25)
	_tree(Vector3(14.0, 0.0, -1.5), 1.05)
	_tree(Vector3(-16.0, 0.0, 4.0), 1.15)
	_tree(Vector3(27.0, 0.0, 6.0), 1.2)
	_car(Vector3(-6.5, 0.0, 4.5), 38.0)
	_rubble(Vector3(10.0, 0.0, -7.0), 1.8)
	_rubble(Vector3(-14.0, 0.0, -3.0), 1.4)
	_lamp_post(Vector3(6.2, 0.0, 4.2))
	for spot: Vector3 in [Vector3(1.5, 0.0, -2.5), Vector3(-1.0, 0.0, 6.5), Vector3(11.0, 0.0, 3.0), Vector3(-11.0, 0.0, 8.0)]:
		_bush(spot, _rng.randf_range(1.2, 2.0), false)
	_build_ruin_details()
	_build_ground_cover()
	_add_sun()
	_add_environment()
	_golden_hour()


## Tramonto: sole basso e caldo dietro le rovine, cielo viola e arancio, foschia calda.
func _golden_hour() -> void:
	var sun := get_node_or_null(^"SunLight") as DirectionalLight3D
	if sun != null:
		sun.basis = Basis.looking_at(MENU_SUN_DIRECTION.normalized(), Vector3.UP)
		sun.light_color = SUNSET_SUN
		sun.light_energy = 1.35
	var world := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world == null:
		return
	var env := world.environment
	var sky := env.sky.sky_material as ShaderMaterial
	sky.set_shader_parameter(&"top_color", SUNSET_TOP)
	sky.set_shader_parameter(&"horizon_color", SUNSET_HORIZON)
	sky.set_shader_parameter(&"ground_color", SUNSET_GROUND)
	env.ambient_light_color = SUNSET_AMBIENT
	env.ambient_light_energy = 0.35
	env.fog_light_color = SUNSET_HORIZON
	env.fog_depth_begin = 22.0
	env.fog_depth_end = 110.0
	env.fog_sun_scatter = 0.15
	env.fog_density = 0.35


## Strati e tinte del terreno: una strada d'asfalto davanti alla camera, macerie attorno
## alle rovine, prato dipinto quasi ovunque (il prato a particelle cresce sul verde).
func paint_surface(field: TerrainField) -> void:
	if field.terrain3d() == null:
		return
	field.begin_batch()
	for rect: Rect2 in _block_rects:
		var c := rect.get_center()
		field.paint_layer(Vector3(c.x, 0.0, c.y), maxf(rect.size.x, rect.size.y) * 0.5 + RUBBLE_SPILL_M, TerrainSurface.LAYER_RUBBLE)
	var x := -40.0
	while x <= 40.0:
		field.paint_layer(Vector3(x, 0.0, 9.5 + x * 0.12), 2.4, TerrainSurface.LAYER_ASPHALT)
		x += 1.5
	var green: Array[Vector3] = []
	var z := -40.0
	while z <= 40.0:
		x = -40.0
		while x <= 40.0:
			var p := Vector2(x + (0.7 if int(z) % 2 == 0 else -0.7), z)
			if absf(p.y - (9.5 + p.x * 0.12)) > 3.0 and _cover_sampled(p) > 0.3:
				green.append(Vector3(p.x, 0.0, p.y))
			x += 3.0
		z += 3.0
	field.tint_points(green, 2.7, GRASS_PAINT, 0.55)
	field.end_batch()
