class_name GrassField
extends Node3D
## Prato a particelle attorno al giocatore (playtest del 14 ottobre 2026, O-09): sostituisce
## i ciuffi del MultiMesh del quartiere quando Terrain3D c'e (solo con finestra). Adattato
## dall'esempio a particelle di Terrain3D 1.0.2 (MIT, addons/terrain_3d/extras/particle_example):
## una griglia di GPUParticles3D che segue il bersaglio a scatti di `spacing`, ogni particella
## un ciuffo di lame piazzato dalla GPU leggendo quote, control map e color map. Le
## particelle ripartono quando il bersaglio si sposta o il rilievo cambia, cosi il prato
## sparisce dagli scavi e dagli argini nuovi.

const PROCESS_SHADER := preload("res://resources/materials/grass_field_process.gdshader")
const BLADE_SHADER := preload("res://resources/materials/grass_field_blades.gdshader")
## Distanza fra i ciuffi per densita della vegetazione (GraphicsQuality.VEGETATION).
const SPACING_BY_DENSITY: Array[float] = [0.55, 0.42, 0.32]
## Lame per ciuffo e loro altezza in unita del ciuffo (la scala la da il process).
const BLADES := 6
const BLADE_SEGMENTS := 2
## Secondi minimi fra due ripartenze dovute a cambi del rilievo.
const RESTART_COOLDOWN := 0.2

@export var terrain_field: TerrainField
## Il prato si centra qui (il giocatore): la camera dall'alto guarda sempre attorno a lui.
@export var target: Node3D
@export var cell_width := 14.0
@export_range(1, 9, 2) var grid_width := 5
## Altezza dei ciuffi in metri (minima e massima).
@export var min_height := 0.35
@export var max_height := 0.62

var spacing := 0.32
var process_material: ShaderMaterial
var blade_material: ShaderMaterial
var particle_nodes: Array[GPUParticles3D] = []
var restarts := 0

var _rows := 1
var _offsets: Array[Vector3] = []
var _last_center := Vector3(INF, 0.0, INF)
var _restart_pending := false
var _cooldown := 0.0


## Costruisce la griglia sul terreno pronto. `density` e l'indice di densita della vegetazione.
func setup(field: TerrainField, follow: Node3D, density: int) -> void:
	terrain_field = field
	target = follow
	spacing = SPACING_BY_DENSITY[clampi(density, 0, SPACING_BY_DENSITY.size() - 1)]
	_build_materials()
	_create_grid()
	if not terrain_field.region_changed.is_connected(_on_region_changed):
		terrain_field.region_changed.connect(_on_region_changed)


func clump_mesh() -> ArrayMesh:
	# Ciuffo di lame affusolate a raggiera, leggermente curve: la punta si piega verso
	# l'esterno. UV.y = altezza normalizzata, UV.x = fase della lama per il vento.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for b in BLADES:
		var yaw := TAU * (float(b) + rng.randf_range(-0.3, 0.3)) / float(BLADES)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-out.z, 0.0, out.x)
		var root := out * rng.randf_range(0.02, 0.10)
		var height := rng.randf_range(0.7, 1.0)
		var lean := rng.randf_range(0.15, 0.35)
		var width := rng.randf_range(0.035, 0.05)
		var phase := float(b) / float(BLADES)
		var rows: Array = []
		for k in BLADE_SEGMENTS + 1:
			var t := float(k) / float(BLADE_SEGMENTS)
			var center := root + out * lean * t * t + Vector3(0.0, height * t, 0.0)
			var half := side * width * (1.0 - t)
			rows.append([center - half, center + half, t])
		for k in BLADE_SEGMENTS:
			var a: Array = rows[k]
			var c: Array = rows[k + 1]
			# Normale fra l'alto e il fianco: luce morbida da sopra, come un prato vero.
			var normal := (Vector3.UP * 0.7 + out * 0.3).normalized()
			for v in [[a[0], a[2]], [a[1], a[2]], [c[1], c[2]], [a[0], a[2]], [c[1], c[2]], [c[0], c[2]]]:
				st.set_normal(normal)
				st.set_color(Color.WHITE)
				st.set_uv(Vector2(phase, v[1]))
				st.add_vertex(v[0])
	return st.commit()


func _build_materials() -> void:
	process_material = ShaderMaterial.new()
	process_material.shader = PROCESS_SHADER
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.0145
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var noise_texture := NoiseTexture2D.new()
	noise_texture.seamless = true
	noise_texture.noise = noise
	process_material.set_shader_parameter(&"main_noise", noise_texture)
	process_material.set_shader_parameter(&"main_noise_scale", 0.012)
	process_material.set_shader_parameter(&"align_to_normal", true)
	process_material.set_shader_parameter(&"normal_strength", 0.4)
	process_material.set_shader_parameter(&"random_spacing", 0.8)
	process_material.set_shader_parameter(&"min_scale", Vector3(0.8, min_height, 0.8))
	process_material.set_shader_parameter(&"max_scale", Vector3(1.2, max_height, 1.2))
	process_material.set_shader_parameter(&"clod_scale_boost", 0.25)
	process_material.set_shader_parameter(&"patch_min_threshold", 0.0)
	process_material.set_shader_parameter(&"patch_max_threshold", 0.22)
	process_material.set_shader_parameter(&"surface_slope_min", 0.78)
	process_material.set_shader_parameter(&"distance_fade_ammount", 0.75)
	process_material.set_shader_parameter(&"wind_strength", 0.0)
	var terrain := terrain_field.terrain3d()
	process_material.set_shader_parameter(&"base_map", terrain.material.get_shader_param("base_map"))
	process_material.set_shader_parameter(&"base_half", terrain.material.get_shader_param("base_half"))
	process_material.set_shader_parameter(&"grow_layers",
		(1 << TerrainSurface.LAYER_DIRT) | (1 << TerrainSurface.LAYER_MUD))
	blade_material = ShaderMaterial.new()
	blade_material.shader = BLADE_SHADER


func _create_grid() -> void:
	for node in particle_nodes:
		node.queue_free()
	particle_nodes.clear()
	_rows = maxi(int(cell_width / spacing), 1)
	var half_grid := grid_width / 2
	_offsets.clear()
	for x in range(-half_grid, half_grid + 1):
		for z in range(-half_grid, half_grid + 1):
			_offsets.append(Vector3(float(x * _rows) * spacing, 0.0, float(z * _rows) * spacing))
	var heights := terrain_field.terrain3d().data.get_height_range()
	var aabb := AABB(Vector3(-cell_width * 0.5, heights.y - 1.0, -cell_width * 0.5),
		Vector3(cell_width, heights.x - heights.y + 2.0 + max_height, cell_width))
	var mesh := clump_mesh()
	for i in _offsets.size():
		var node := GPUParticles3D.new()
		node.name = "GrassCell%d" % i
		node.lifetime = 600.0
		node.amount = _rows * _rows
		node.explosiveness = 1.0
		node.process_material = process_material
		node.draw_pass_1 = mesh
		node.material_override = blade_material
		node.custom_aabb = aabb
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.fixed_fps = 30
		node.preprocess = 1.0 / 30.0
		node.use_fixed_seed = true
		# Le celle saltano al nuovo centro: niente interpolazione fisica fra due posizioni.
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		node.seed = 7
		add_child(node)
		node.emitting = true
		particle_nodes.append(node)
	_last_center = Vector3(INF, 0.0, INF)


func _physics_process(delta: float) -> void:
	if terrain_field == null or particle_nodes.is_empty() or not is_instance_valid(target):
		return
	_update_terrain_parameters()
	_cooldown = maxf(_cooldown - delta, 0.0)
	var center := target.global_position
	var moved := Vector2(center.x - _last_center.x, center.z - _last_center.z).length_squared() > 1.0
	if moved or (_restart_pending and _cooldown <= 0.0):
		_restart(center)


func _restart(center: Vector3) -> void:
	_restart_pending = false
	_cooldown = RESTART_COOLDOWN
	_last_center = center
	var snapped := Vector3(center.x, 0.0, center.z).snapped(Vector3.ONE)
	process_material.set_shader_parameter(&"camera_position", Vector3(snapped.x, center.y, snapped.z))
	for i in particle_nodes.size():
		var node := particle_nodes[i]
		node.global_position = ((snapped + _offsets[i]) / spacing).round() * spacing
		node.restart(true)
	restarts += 1


func _on_region_changed(_aabb: AABB) -> void:
	_restart_pending = true


func _update_terrain_parameters() -> void:
	var terrain := terrain_field.terrain3d()
	if terrain == null or terrain.data == null:
		return
	var rid := process_material.get_rid()
	RenderingServer.material_set_param(rid, "_background_mode", terrain.material.world_background)
	RenderingServer.material_set_param(rid, "_vertex_spacing", terrain.vertex_spacing)
	RenderingServer.material_set_param(rid, "_vertex_density", 1.0 / terrain.vertex_spacing)
	RenderingServer.material_set_param(rid, "_region_size", terrain.region_size)
	RenderingServer.material_set_param(rid, "_region_texel_size", 1.0 / terrain.region_size)
	RenderingServer.material_set_param(rid, "_region_map_size", 32)
	RenderingServer.material_set_param(rid, "_region_map", terrain.data.get_region_map())
	RenderingServer.material_set_param(rid, "_region_locations", terrain.data.get_region_locations())
	RenderingServer.material_set_param(rid, "_height_maps", terrain.data.get_height_maps_rid())
	RenderingServer.material_set_param(rid, "_control_maps", terrain.data.get_control_maps_rid())
	RenderingServer.material_set_param(rid, "_color_maps", terrain.data.get_color_maps_rid())
	RenderingServer.material_set_param(rid, "instance_spacing", spacing)
	RenderingServer.material_set_param(rid, "instance_rows", _rows)
	RenderingServer.material_set_param(rid, "max_dist", cell_width * float(grid_width) * 0.5)
