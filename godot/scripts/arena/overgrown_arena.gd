@tool
class_name OvergrownArena
extends Node3D
## Arena di gioco: piazza urbana in rovina riconquistata dalla natura (D-036).
##
## Tutto e generato da primitive e shader, senza asset esterni, con un seme fisso:
## editor e gioco mostrano la stessa arena (D-017). Unita native Godot (metri).
## Orientamento: la camera guarda verso -Z. A nord (-Z) torri alte e skyline,
## ai lati edifici medi e un treno arrugginito, a sud solo elementi bassi per
## non coprire il giocatore. Il quadrato centrale resta libero per la griglia
## del terreno e la corsia dell'hazard.
## Il piano del suolo e a y = 0 nello spazio locale; il nodo va lasciato in origine
## perche gli shader lavorano in coordinate mondo.

## Lato delle porzioni di erba, fiori e detriti (audit V-01): il frustum scarta le altre.
const COVER_TILE_M := 32.0
const RUIN_SHADER := preload("res://resources/materials/ruin_overgrown.gdshader")
const RUST_SHADER := preload("res://resources/materials/rusted_metal.gdshader")
const FOLIAGE_SHADER := preload("res://resources/materials/foliage.gdshader")
const GRASS_SHADER := preload("res://resources/materials/grass_blades.gdshader")
const ENV_BAKED_SHADER := preload("res://resources/materials/env_baked.gdshader")
## Tile dipinte dei muri (restyling 2026-10-11): 0 intonaco e mattoni, 1 muschio, 2 corteccia.
## Caricate a runtime (`_surface_texture`), non con preload: in un worktree nuovo sono
## puntatori LFS e un preload fallito bloccherebbe la compilazione.
const WALLS_ALBEDO_PATH := "res://assets/textures/surfaces/walls_albedo.png"
const WALLS_ORM_PATH := "res://assets/textures/surfaces/walls_orm.png"
const WALLS_NORMAL_PATH := "res://assets/textures/surfaces/walls_normal.png"
## Tile dipinte delle piante: 0 ciuffi d'erba (tre colonne), 1 cartelle di foglie.
const PLANTS_ALBEDO_PATH := "res://assets/textures/surfaces/plants_albedo.png"
## Modelli generati da tools/blender/build_arena_assets.py (D-037), rifiniti con
## texture cotta (D-073).
const CAR_MODEL := preload("res://assets/models/wrecked_car.glb")
const CARRIAGE_MODEL := preload("res://assets/models/train_carriage.glb")
const TREE_MODEL := preload("res://assets/models/overgrown_tree.glb")
const BARRIER_MODEL := preload("res://assets/models/concrete_barrier.glb")
const LAMP_POST_MODEL := preload("res://assets/models/lamp_post.glb")

const WORLD_STATIC_LAYER := 1

## Rilievo continuo (D-085): quote per prato, detriti, prop e rovine; senza, tutto a quota 0.
@export var terrain_field: TerrainField
@export var layout_seed := 20261004:
	set(value):
		layout_seed = value
		_queue_rebuild()
## Mezzo lato dell'area giocabile lungo X; oltre c'e un muro invisibile.
@export var play_half_extent := 24.0:
	set(value):
		play_half_extent = value
		_queue_rebuild()
## Mezzo lato lungo Z; 0 = quadrato, uguale a `play_half_extent`. Un'arena
## rettangolare (la ferrovia, D-066) lo imposta; tutto il resto legge half_x()/half_z().
@export var play_half_extent_z := 0.0:
	set(value):
		play_half_extent_z = value
		_queue_rebuild()
## Mezzo lato del quadrato centrale tenuto libero (griglia 11x11 + corsia hazard).
@export var clear_half_extent := 16.8:
	set(value):
		clear_half_extent = value
		_queue_rebuild()
@export_range(0, 150000, 100) var grass_tufts := 24000:
	set(value):
		grass_tufts = value
		_queue_rebuild()
@export_range(0, 8000, 50) var flowers := 1400:
	set(value):
		flowers = value
		_queue_rebuild()
## Detriti a terra: sassi e foglie secche (D-069), un MultiMesh.
@export_range(0, 40000, 100) var litter := 9000:
	set(value):
		litter = value
		_queue_rebuild()

const CONCRETE_TINTS: Array[Color] = [
	Color(0.70, 0.64, 0.55), Color(0.62, 0.58, 0.52), Color(0.74, 0.60, 0.48),
	Color(0.56, 0.54, 0.50), Color(0.68, 0.56, 0.44),
]
const CAR_PAINTS: Array[Color] = [
	Color(0.62, 0.20, 0.14), Color(0.18, 0.45, 0.46), Color(0.82, 0.76, 0.60),
	Color(0.86, 0.64, 0.16), Color(0.30, 0.36, 0.52),
]
const LEAF_TINTS: Array[Color] = [
	Color(0.22, 0.42, 0.10), Color(0.34, 0.50, 0.12), Color(0.17, 0.34, 0.09),
	Color(0.44, 0.54, 0.15),
]
const LITTER_COLORS: Array[Color] = [
	Color(0.50, 0.46, 0.40), Color(0.42, 0.40, 0.36), Color(0.58, 0.52, 0.44),
	Color(0.62, 0.40, 0.14), Color(0.70, 0.50, 0.18), Color(0.48, 0.30, 0.12),
]
const FLOWER_COLORS: Array[Color] = [
	Color(0.95, 0.45, 0.35), Color(0.45, 0.55, 0.95), Color(0.98, 0.82, 0.25),
	Color(0.95, 0.92, 0.85), Color(0.75, 0.40, 0.85),
]
const SUN_COLOR := Color(1.0, 0.84, 0.62)
## Cielo dipinto di giorno e ambiente freddo (restyling 2026-10-11).
const SKY_SHADER := preload("res://resources/materials/sky_painted.gdshader")
const SKY_DAY_TOP := Color(0.26, 0.46, 0.82)
const SKY_DAY_HORIZON := Color(0.96, 0.80, 0.62)
const SKY_DAY_GROUND := Color(0.42, 0.38, 0.28)
const AMBIENT_COLOR := Color(0.38, 0.44, 0.95)
const AMBIENT_ENERGY := 0.6
## Sole di giorno (D-094): controluce laterale da nord-ovest, la camera guarda verso -Z.
const SUN_DIRECTION := Vector3(0.7, -0.45, 0.55)
const SUN_ENERGY := 3.0

var _generated: Array[Node] = []
var _rebuild_pending := false
var _rng := RandomNumberGenerator.new()
var _ruin_material: ShaderMaterial
var _rust_material: ShaderMaterial
var _foliage_material: ShaderMaterial
var _bush_material: ShaderMaterial
var _canopy_material: ShaderMaterial
var _grass_material: ShaderMaterial
var _shared_hidden: ShaderMaterial
var _shared_canopies: Array[ArrayMesh] = []
## Vero quando il prato lo fa GrassField (a particelle, con Terrain3D): niente ciuffi nel MultiMesh.
var gpu_grass := false
var _litter_material: StandardMaterial3D
## Corone dei muri e tondini di ferro di tutte le rovine e torri, in due MultiMesh
## (D-068, D-070): le sottoclassi accodano con `_append_instance`.
var _crown_buffer := PackedFloat32Array()
var _crown_count := 0
var _rebar_buffer := PackedFloat32Array()
var _rebar_count := 0
## Muro (corpo) che porta ogni corona e tondino, null per le torri: sul rilievo le istanze
## salgono e scendono con il loro muro (audit R-05).
var _crown_hosts: Array = []
var _rebar_hosts: Array = []
var _crown_material: ShaderMaterial
var _shared_bush: ArrayMesh
var _metal_material: StandardMaterial3D
var _tire_material: StandardMaterial3D
var _trunk_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
## Materiali con texture cotta dei modelli rifiniti (D-073), uno per materiale
## importato: la texture e condivisa, la tinta e per istanza.
var _baked_materials: Dictionary[Material, ShaderMaterial] = {}
## Statistiche dell'ultima costruzione, per log e test.
var stats := {}


func _ready() -> void:
	rebuild()
	if not Engine.is_editor_hint():
		print("PROTOTYPE01_EXPOSURE_READY")
		print("PROTOTYPE01_ARENA_READY style=overgrown_ruins play=%.0fx%.0fm blocks=%d props=%d trees=%d"
			% [half_x() * 2.0, half_z() * 2.0, stats.blocks, stats.props, stats.trees])


## Mezzi lati dell'area giocabile: X e Z (Z uguale a X se `play_half_extent_z` e 0).
func half_x() -> float:
	return play_half_extent


func half_z() -> float:
	return play_half_extent_z if play_half_extent_z > 0.0 else play_half_extent


func half_extents() -> Vector2:
	return Vector2(half_x(), half_z())


func _queue_rebuild() -> void:
	if not is_node_ready() or _rebuild_pending:
		return
	_rebuild_pending = true
	_flush_rebuild.call_deferred()


func _flush_rebuild() -> void:
	if _rebuild_pending:
		rebuild()


## Ricostruzione idempotente e deterministica.
func rebuild() -> void:
	_rebuild_pending = false
	for node in _generated:
		remove_child(node)
		node.queue_free()
	_generated.clear()
	stats = {"blocks": 0, "props": 0, "trees": 0, "tufts": 0, "flowers": 0}
	_rng.seed = layout_seed
	_make_materials()
	_compose()


## Composizione della piazza (48x48 m). Le sottoclassi (RuinsDistrict) la sostituiscono.
func _compose() -> void:
	_reset_ruin_details()
	_build_boundary()
	_build_north()
	_build_skyline()
	_build_east()
	_build_west_train()
	_build_south_edge()
	_build_ring_props()
	_build_ruin_details()
	_build_ground_cover()
	_add_sun()
	_add_environment()


## Raggio della piazza del suolo: oltre, la natura prevale sul costruito.
func plaza_radius() -> float:
	return play_half_extent * 0.85


## Lato del piano del suolo, oltre il perimetro giocabile.
func ground_size() -> float:
	return 220.0


## Oltre questa distanza dal centro (lungo X) non cresce vegetazione.
func cover_limit() -> float:
	return play_half_extent + 14.0


## Lo stesso margine, lungo Z: con un'arena rettangolare il verde segue il bordo.
func cover_limit_z() -> float:
	return cover_limit() - half_x() + half_z()


## Quota della vegetazione: sulla piazza il suolo e a zero.
func cover_height() -> float:
	return 0.0


## Il punto e escluso dalla vegetazione? Qui il quadrato centrale, dove le celle
## del terreno cambiano altezza.
func _cover_excluded(p: Vector2) -> bool:
	return absf(p.x) < clear_half_extent - 2.6 and absf(p.y) < clear_half_extent - 2.6


## Probabilita [0,1] che un punto candidato porti un ciuffo; segue la formula del suolo.
## [param bonus] alza la copertura (prato piu fitto nelle conche del rilievo).
func _cover_chance(p: Vector2, bonus := 0.0) -> float:
	var cover := _cover_sampled(p) + bonus
	return 1.0 if cover >= 0.5 + _rng.randf_range(-0.04, 0.06) else 0.0


## Passo del reticolo su cui `ground_cover_at` viene campionata e interpolata (T-02):
## la formula ha lunghezze d'onda di ~11 m, a 2 m l'errore e sotto il rumore del
## pennello; costa 2,3 us per nodo invece che per candidato.
const COVER_LATTICE_PITCH := 2.0
const COVER_UNSAMPLED := -1.0e9
var _cover_lattice := PackedFloat32Array()
var _cover_lattice_side := 0
var _cover_lattice_origin := 0.0


func _reset_cover_lattice() -> void:
	var limit := cover_limit()
	_cover_lattice_side = int(ceil(limit * 2.0 / COVER_LATTICE_PITCH)) + 2
	_cover_lattice_origin = -limit
	_cover_lattice.resize(_cover_lattice_side * _cover_lattice_side)
	_cover_lattice.fill(COVER_UNSAMPLED)


## `ground_cover_at` interpolata bilinearmente dal reticolo, calcolato a richiesta.
func _cover_sampled(p: Vector2) -> float:
	if _cover_lattice.is_empty():
		_reset_cover_lattice()
	var fx := clampf((p.x - _cover_lattice_origin) / COVER_LATTICE_PITCH, 0.0, _cover_lattice_side - 1.001)
	var fy := clampf((p.y - _cover_lattice_origin) / COVER_LATTICE_PITCH, 0.0, _cover_lattice_side - 1.001)
	var ix := int(fx)
	var iy := int(fy)
	var tx := fx - ix
	var ty := fy - iy
	var i := iy * _cover_lattice_side + ix
	var top := lerpf(_cover_node(i), _cover_node(i + 1), tx)
	var bottom := lerpf(_cover_node(i + _cover_lattice_side), _cover_node(i + _cover_lattice_side + 1), tx)
	return lerpf(top, bottom, ty)


func _cover_node(i: int) -> float:
	var v := _cover_lattice[i]
	if v == COVER_UNSAMPLED:
		v = ground_cover_at(Vector2(_cover_lattice_origin + (i % _cover_lattice_side) * COVER_LATTICE_PITCH,
			_cover_lattice_origin + (i / _cover_lattice_side) * COVER_LATTICE_PITCH))
		_cover_lattice[i] = v
	return v


# --- Materiali -----------------------------------------------------------------

func _make_materials() -> void:
	_ruin_material = ShaderMaterial.new()
	_ruin_material.shader = RUIN_SHADER
	apply_wall_tiles(_ruin_material)
	_rust_material = ShaderMaterial.new()
	_rust_material.shader = RUST_SHADER
	_foliage_material = ShaderMaterial.new()
	_foliage_material.shader = FOLIAGE_SHADER
	# Cespugli: cartelle di foglie dipinte (restyling 2026-10-11).
	_bush_material = ShaderMaterial.new()
	_bush_material.shader = FOLIAGE_SHADER
	_bush_material.set_shader_parameter(&"textured", true)
	_set_surface_texture(_bush_material, &"plants_albedo", PLANTS_ALBEDO_PATH)
	# Le chiome alte oscillano poco; cespugli ed erba leggono lo stesso campo di vento
	# (wind.gdshaderinc, D-083), cosi le raffiche attraversano insieme prato e fronde.
	_canopy_material = ShaderMaterial.new()
	_canopy_material.shader = FOLIAGE_SHADER
	_canopy_material.set_shader_parameter(&"wind_strength", 0.05)
	_canopy_material.set_shader_parameter(&"textured", true)
	_set_surface_texture(_canopy_material, &"plants_albedo", PLANTS_ALBEDO_PATH)
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_set_surface_texture(_grass_material, &"plants_albedo", PLANTS_ALBEDO_PATH)
	_grass_material.set_shader_parameter(&"wind_strength", 0.14)
	_grass_material.set_shader_parameter(&"blade_height", TUFT_HEIGHT)
	_litter_material = StandardMaterial3D.new()
	_litter_material.vertex_color_use_as_albedo = true
	_litter_material.roughness = 0.95
	_metal_material = StandardMaterial3D.new()
	_metal_material.albedo_color = Color(0.30, 0.22, 0.17)
	_metal_material.metallic = 0.4
	_metal_material.roughness = 0.8
	_tire_material = StandardMaterial3D.new()
	_tire_material.albedo_color = Color(0.07, 0.07, 0.07)
	_tire_material.roughness = 0.95
	_trunk_material = StandardMaterial3D.new()
	_trunk_material.albedo_color = Color(0.46, 0.36, 0.26)
	_trunk_material.roughness = 0.95
	_dark_material = StandardMaterial3D.new()
	_dark_material.albedo_color = Color(0.06, 0.06, 0.05)
	_dark_material.roughness = 0.6


# --- Mattoni di base -------------------------------------------------------------

func _add_generated(node: Node) -> void:
	add_child(node)
	_generated.append(node)


func _static_body(node_name: String, xform: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.transform = xform
	body.collision_layer = WORLD_STATIC_LAYER
	body.collision_mask = 0
	_add_generated(body)
	return body


func _mesh_child(parent: Node3D, mesh: Mesh, material: Material, local := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = local
	parent.add_child(mi)
	return mi


func _box_shape_child(parent: Node3D, size: Vector3, local := Transform3D.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = local
	parent.add_child(collision)


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Mesh unitarie condivise (R-32): cespugli e macerie si scalano nella trasformazione invece
## di creare una mesh (e una draw call con vertex buffer proprio) per pezzo.
var _shared_box: BoxMesh
var _shared_sphere: SphereMesh


func _unit_box_mesh() -> BoxMesh:
	if _shared_box == null:
		_shared_box = _box(Vector3.ONE)
	return _shared_box


## Ciuffo di cespuglio: sfera a pochi segmenti, vertici spostati a caso lungo il
## raggio, facce piatte (una mesh condivisa per tutti i cespugli).
## Cespuglio a cartelle (restyling 2026-10-11): sei quad unitari, tre verticali
## incrociati a 60 gradi e tre inclinati, con UV 0..1 per le foglie dipinte e normali
## ammorbidite verso l'alto, cosi la luce li legge come una massa.
func _bush_card_mesh() -> ArrayMesh:
	if _shared_bush != null:
		return _shared_bush
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
	for k in 6:
		var yaw := TAU * float(k % 3) / 3.0 * 0.5 + (0.3 if k >= 3 else 0.0)
		var tilt := 0.0 if k < 3 else deg_to_rad(35.0) * (1.0 if k % 2 == 0 else -1.0)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
		var corners: Array[Vector3] = [Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
			Vector3(1.0, 2.0, 0.0), Vector3(-1.0, 2.0, 0.0)]
		var face_normal := basis * Vector3.BACK
		var normal := (Vector3.UP * 1.2 + face_normal).normalized()
		for index in [0, 1, 2, 0, 2, 3]:
			st.set_normal(normal)
			st.set_color(Color.WHITE)
			st.set_uv(uvs[index])
			st.add_vertex(basis * corners[index])
	st.generate_tangents()
	_shared_bush = st.commit()
	return _shared_bush


func _unit_sphere_mesh() -> SphereMesh:
	if _shared_sphere == null:
		_shared_sphere = SphereMesh.new()
		_shared_sphere.radius = 1.0
		_shared_sphere.height = 2.0
		_shared_sphere.radial_segments = 9
		_shared_sphere.rings = 5
	return _shared_sphere


## Istanzia un modello Blender e rimappa i materiali semantici sugli shader dell'arena.
## `params` sono gli instance uniform da impostare su ogni mesh del modello.
## Istanza di un modello dell'arena con i materiali condivisi, per chi sta fuori
## dall'arena (il treno del livello 2): il nodo appartiene a [param parent], non alla
## ricostruzione dell'arena.
func spawn_model(scene: PackedScene, parent: Node3D, local: Transform3D, params: Dictionary) -> Node3D:
	return _model(scene, parent, local, params)


func _model(scene: PackedScene, parent: Node3D, local: Transform3D, params: Dictionary) -> Node3D:
	var model := scene.instantiate() as Node3D
	model.transform = local
	parent.add_child(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(surface)
			mi.set_surface_override_material(surface, _material_for(source.resource_name if source else "", source))
		for key: StringName in params:
			mi.set_instance_shader_parameter(key, params[key])
	return model


## Materiale di Godot per una superficie importata. Un modello rifinito (D-073) porta la
## texture cotta nel materiale: la legge `env_baked.gdshader`, con la tinta per istanza
## sulle superfici `paint`. Il fogliame resta sul suo shader. Un modello a blocchi (D-037)
## ha solo nomi semantici, rimappati sugli shader procedurali dell'arena.
func _material_for(semantic: String, source: Material = null) -> Material:
	if semantic != "leaves" and source is BaseMaterial3D and (source as BaseMaterial3D).albedo_texture != null:
		return _baked_material(source as BaseMaterial3D, semantic == "paint")
	match semantic:
		"paint":
			return _rust_material
		"concrete":
			return _ruin_material
		"leaves":
			return _canopy_material
		"bark":
			return _trunk_material
		"metal":
			return _metal_material
		"tire":
			return _tire_material
	return _dark_material


func _baked_material(source: BaseMaterial3D, tintable: bool) -> ShaderMaterial:
	var cached: ShaderMaterial = _baked_materials.get(source)
	if cached != null:
		return cached
	var material := ShaderMaterial.new()
	material.shader = ENV_BAKED_SHADER
	material.set_shader_parameter(&"albedo_tex", source.albedo_texture)
	material.set_shader_parameter(&"tintable", 1.0 if tintable else 0.0)
	material.set_shader_parameter(&"base_roughness", source.roughness)
	material.set_shader_parameter(&"base_metallic", 0.3 if tintable else 0.1)
	# Normal e ORM cotte (restyling 2026-10-11): l'import glTF mette roughness/metallo in
	# roughness_texture (stessa immagine di metallic_texture) e l'occlusione in ao_texture.
	var normal := source.normal_texture if source.normal_enabled else null
	var orm := source.roughness_texture if source.roughness_texture != null else source.ao_texture
	material.set_shader_parameter(&"has_maps", normal != null and orm != null)
	if normal != null:
		material.set_shader_parameter(&"normal_tex", normal)
	if orm != null:
		material.set_shader_parameter(&"orm_tex", orm)
	_baked_materials[source] = material
	return material


func _pick(colors: Array[Color]) -> Color:
	return colors[_rng.randi_range(0, colors.size() - 1)]


## Blocco di rovina con collisione. `base` e il centro della base, nel piano locale.
func _ruin_block(node_name: String, base: Vector3, size: Vector3, yaw_deg: float,
		tint: Color, overgrowth: float, windows := 1.0, collide := true) -> StaticBody3D:
	var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), base + Vector3(0.0, size.y * 0.5, 0.0))
	var body := _static_body(node_name, xform)
	var mi := _mesh_child(body, _box(size), _ruin_material)
	mi.set_instance_shader_parameter(&"base_tint", tint)
	mi.set_instance_shader_parameter(&"top_y", base.y + size.y)
	mi.set_instance_shader_parameter(&"overgrowth", overgrowth)
	mi.set_instance_shader_parameter(&"windows", windows)
	if collide:
		_box_shape_child(body, size)
	stats.blocks += 1
	return body


## Torre spezzata: corpo principale, gradoni rotti in cima, rampicanti in facciata.
func _tower(node_name: String, center: Vector2, footprint: Vector2, height: float,
		overgrowth: float, facade_vines := true) -> void:
	var tint := _pick(CONCRETE_TINTS)
	var yaw := _rng.randf_range(-4.0, 4.0)
	_ruin_block(node_name, Vector3(center.x, 0.0, center.y), Vector3(footprint.x, height, footprint.y),
		yaw, tint, overgrowth)
	# Sommita crollata: due o tre blocchi decrescenti, sfalsati.
	var top := height
	var w := footprint.x
	var d := footprint.y
	for i in _rng.randi_range(1, 3):
		w *= _rng.randf_range(0.45, 0.75)
		d *= _rng.randf_range(0.5, 0.85)
		var h := _rng.randf_range(2.0, 6.0)
		var offset := Vector2(_rng.randf_range(-0.3, 0.3) * footprint.x, _rng.randf_range(-0.3, 0.3) * footprint.y)
		_ruin_block("%sTop%d" % [node_name, i], Vector3(center.x + offset.x, top, center.y + offset.y),
			Vector3(w, h, d), yaw + _rng.randf_range(-6.0, 6.0), tint, minf(overgrowth + 0.1, 1.0), 1.0, false)
		top += h
	# Chioma sul tetto: la natura sopra le rovine.
	for i in _rng.randi_range(2, 4):
		var p := Vector3(center.x + _rng.randf_range(-0.35, 0.35) * footprint.x, height,
			center.y + _rng.randf_range(-0.35, 0.35) * footprint.y)
		_bush(p, _rng.randf_range(1.4, 2.6), false)
	# Bordo del tetto spezzato e, a volte, una lastra di facciata crollata (D-070).
	_edge_crown(center, footprint, height, yaw, tint)
	if facade_vines and _rng.randf() < 0.45:
		_fallen_slab(node_name, center, footprint, height, yaw, tint)
	if facade_vines:
		_facade_vines(center, footprint, height)


## Frammenti e tondini lungo i quattro bordi del tetto di una torre, nei MultiMesh condivisi.
func _edge_crown(center: Vector2, footprint: Vector2, height: float, yaw_deg: float, tint: Color) -> void:
	var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(center.x, 0.0, center.y))
	var linear := tint.srgb_to_linear()
	for side in 4:
		var along_x := side < 2
		var direction := 1.0 if side % 2 == 0 else -1.0
		var length := footprint.x if along_x else footprint.y
		var across := direction * ((footprint.y if along_x else footprint.x) * 0.5 - 0.3)
		var pieces := maxi(2, int(length / 2.5))
		for i in pieces:
			if _rng.randf() < 0.4:
				continue
			var along := -length * 0.5 + length * (i + _rng.randf_range(0.2, 0.8)) / pieces
			var size := Vector3(_rng.randf_range(0.6, 1.6), _rng.randf_range(0.2, 0.7), _rng.randf_range(0.4, 0.6))
			if not along_x:
				size = Vector3(size.z, size.y, size.x)
			var local := Vector3(along, height + size.y * 0.5, across) if along_x else Vector3(across, height + size.y * 0.5, along)
			var tilt := Basis(Vector3.FORWARD if along_x else Vector3.RIGHT, _rng.randf_range(-0.15, 0.15))
			_append_instance(_crown_buffer, _crown_count, xform * Transform3D(tilt.scaled_local(size), local),
				Color(linear * _rng.randf_range(0.8, 0.95), 0.4))
			_crown_count += 1
			_crown_hosts.append(null)
			if _rng.randf() < 0.5:
				var rebar_height := _rng.randf_range(0.5, 1.3)
				var lean := Basis.from_euler(Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4)))
				var rebar_local := local + Vector3(0.0, size.y * 0.5 + rebar_height * 0.4, 0.0)
				_append_instance(_rebar_buffer, _rebar_count,
					xform * Transform3D(lean.scaled_local(Vector3(0.08, rebar_height, 0.08)), rebar_local),
					Color(0.16, 0.09, 0.05))
				_rebar_count += 1
				_rebar_hosts.append(null)


## Lastra di facciata staccata dalla torre, appoggiata di sbieco al piede del lato sud.
func _fallen_slab(node_name: String, center: Vector2, footprint: Vector2, height: float,
		yaw_deg: float, tint: Color) -> void:
	var size := Vector3(footprint.x * _rng.randf_range(0.25, 0.4), minf(height * 0.3, 7.0), 0.3)
	var lean := deg_to_rad(_rng.randf_range(55.0, 70.0))
	var x := center.x + _rng.randf_range(-0.3, 0.3) * footprint.x
	var z := center.y + footprint.y * 0.5 + cos(lean) * size.y * 0.5 + 0.2
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, lean)
	var body := _static_body(node_name + "Slab", Transform3D(Basis(), Vector3(x, sin(lean) * size.y * 0.5 + 0.1, z)))
	var mi := _mesh_child(body, _unit_box_mesh(), _ruin_material, Transform3D(basis.scaled_local(size), Vector3.ZERO))
	mi.set_instance_shader_parameter(&"base_tint", tint * 0.9)
	mi.set_instance_shader_parameter(&"top_y", size.y)
	mi.set_instance_shader_parameter(&"overgrowth", 0.6)
	mi.set_instance_shader_parameter(&"windows", 0.0)
	mi.set_instance_shader_parameter(&"vine_reach", 0.3)


## Passa le tile dipinte dei muri a un materiale con ruin_overgrown.gdshader.
static func apply_wall_tiles(material: ShaderMaterial) -> void:
	_set_surface_texture(material, &"walls_albedo", WALLS_ALBEDO_PATH)
	_set_surface_texture(material, &"walls_orm", WALLS_ORM_PATH)
	_set_surface_texture(material, &"walls_normal", WALLS_NORMAL_PATH)


static func _set_surface_texture(material: ShaderMaterial, uniform: StringName, path: String) -> void:
	if ResourceLoader.exists(path):
		material.set_shader_parameter(uniform, load(path))


func _reset_ruin_details() -> void:
	_crown_buffer.clear()
	_crown_count = 0
	_rebar_buffer.clear()
	_rebar_count = 0
	_crown_hosts.clear()
	_rebar_hosts.clear()


## Accoda un'istanza (trasformazione completa e colore) al buffer di un MultiMesh.
static func _append_instance(buffer: PackedFloat32Array, index: int, xform: Transform3D, color: Color) -> void:
	buffer.resize((index + 1) * 16)
	var base := index * 16
	var b := xform.basis
	var o := xform.origin
	buffer[base] = b.x.x
	buffer[base + 1] = b.y.x
	buffer[base + 2] = b.z.x
	buffer[base + 3] = o.x
	buffer[base + 4] = b.x.y
	buffer[base + 5] = b.y.y
	buffer[base + 6] = b.z.y
	buffer[base + 7] = o.y
	buffer[base + 8] = b.x.z
	buffer[base + 9] = b.y.z
	buffer[base + 10] = b.z.z
	buffer[base + 11] = o.z
	buffer[base + 12] = color.r
	buffer[base + 13] = color.g
	buffer[base + 14] = color.b
	buffer[base + 15] = color.a


## I due MultiMesh delle corone e dei tondini: due draw call per tutte le rovine e torri.
func _build_ruin_details() -> void:
	if _crown_material == null:
		_crown_material = ShaderMaterial.new()
		_crown_material.shader = RUIN_SHADER
		_crown_material.set_shader_parameter(&"batched", true)
		apply_wall_tiles(_crown_material)
	_add_multimesh("RuinCrowns", _unit_box_mesh(), _crown_buffer, _crown_count, _crown_material)
	_add_multimesh("RuinRebar", _unit_box_mesh(), _rebar_buffer, _rebar_count, _dark_material)
	stats.crown_pieces = _crown_count
	stats.rebar = _rebar_count


## Rampicanti pendenti sulla facciata sud (quella vista dalla camera).
func _facade_vines(center: Vector2, footprint: Vector2, height: float) -> void:
	var count := int(footprint.x * 1.2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _box(Vector3(1.0, 1.0, 1.0))
	mm.instance_count = count
	var face_z := center.y + footprint.y * 0.5 + 0.08
	for i in count:
		var length := _rng.randf_range(2.0, height * 0.6)
		var width := _rng.randf_range(0.25, 0.9)
		var x := center.x + _rng.randf_range(-0.48, 0.48) * footprint.x
		var basis := Basis.from_scale(Vector3(width, length, 0.12))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, height - length * 0.5, face_z)))
		mm.set_instance_color(i, _pick(LEAF_TINTS) * _rng.randf_range(0.5, 0.8))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FacadeVines"
	mmi.multimesh = mm
	mmi.material_override = _foliage_material
	mmi.set_instance_shader_parameter(&"tint", Color(1, 1, 1))
	_add_generated(mmi)


func _tree(base: Vector3, scale: float) -> void:
	var body := _static_body("Tree", Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), base))
	var tint := _pick(LEAF_TINTS) * 1.6
	var model := _model(TREE_MODEL, body, Transform3D(Basis.from_scale(Vector3.ONE * scale), Vector3.ZERO), {&"tint": tint})
	_thicken_canopy(model, tint, int(absi(int(base.x * 13.0 + base.z * 7.0))))
	var shape := CylinderShape3D.new()
	shape.radius = 0.4 * scale
	shape.height = 3.0 * scale
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.1 * scale, 1.5 * scale, 0.0)
	body.add_child(collision)
	stats.trees += 1


## Chioma piena (playtest del 14 ottobre 2026): il modello ha solo 42 cartelle di foglie e
## dall'alto sembrava un foglio verde. Le sue foglie si nascondono e al loro posto, nello
## stesso volume, va una chioma generata: un centinaio di cartelle a grappoli con normali
## sferiche, cosi la luce la modella come un volume (lato in ombra, bordo illuminato).
func _thicken_canopy(model: Node3D, tint: Color, variant: int) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(surface)
			if source == null or source.resource_name != "leaves":
				continue
			var vertices: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var bounds := AABB(vertices[0], Vector3.ZERO)
			for v in vertices:
				bounds = bounds.expand(v)
			mi.set_surface_override_material(surface, _hidden_material())
			var crown := MeshInstance3D.new()
			crown.name = "Crown"
			crown.mesh = _canopy_mesh(variant)
			crown.material_override = _canopy_material
			crown.transform = mi.transform * Transform3D(Basis.from_scale(bounds.size * 0.55), bounds.get_center())
			mi.get_parent().add_child(crown)
			crown.set_instance_shader_parameter(&"tint", tint)
			return


## Materiale che non disegna nulla (neppure in ombra): nasconde una superficie importata.
func _hidden_material() -> ShaderMaterial:
	if _shared_hidden == null:
		var shader := Shader.new()
		shader.code = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { discard; }\n"
		_shared_hidden = ShaderMaterial.new()
		_shared_hidden.shader = shader
	return _shared_hidden


## Chioma unitaria (ellissoide di raggio 1): grappoli di cartelle di foglie orientate a
## caso, con la normale che esce dal centro della chioma. Tre varianti condivise.
func _canopy_mesh(variant: int) -> ArrayMesh:
	var index := posmod(variant, 3)
	if _shared_canopies.size() > index and _shared_canopies[index] != null:
		return _shared_canopies[index]
	while _shared_canopies.size() <= index:
		_shared_canopies.append(null)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + index
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
	for cluster in 8:
		var cluster_center := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 1.0), rng.randf_range(-1.0, 1.0)).limit_length(0.62)
		for card in 13:
			var center := cluster_center + Vector3(rng.randf_range(-0.32, 0.32), rng.randf_range(-0.26, 0.26), rng.randf_range(-0.32, 0.32))
			var basis := Basis.from_euler(Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.0, TAU), rng.randf_range(-0.9, 0.9)))
			var half := rng.randf_range(0.2, 0.3)
			var corners: Array[Vector3] = [Vector3(-half, -half, 0.0), Vector3(half, -half, 0.0), Vector3(half, half, 0.0), Vector3(-half, half, 0.0)]
			var normal := (center + Vector3(0.0, 0.35, 0.0)).normalized()
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(normal)
				st.set_color(Color.WHITE)
				st.set_uv(uvs[k])
				st.add_vertex(center + basis * corners[k])
	st.generate_tangents()
	_shared_canopies[index] = st.commit()
	return _shared_canopies[index]


## Cespuglio: ciuffi sfaccettati e bitorzoluti (D-070), senza collisione.
func _bush(base: Vector3, size: float, count_as_prop := true) -> void:
	var root := Node3D.new()
	root.name = "Bush"
	root.position = base
	_add_generated(root)
	var tint := _pick(LEAF_TINTS)
	for i in _rng.randi_range(2, 4):
		var r := size * _rng.randf_range(0.35, 0.6)
		var offset := Vector3(_rng.randf_range(-0.5, 0.5) * size, -0.05, _rng.randf_range(-0.5, 0.5) * size)
		# Ciuffo unitario scalato e girato: raggio r, altezza circa 1,3 r.
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(r, r * 0.65, r))
		var mi := _mesh_child(root, _bush_card_mesh(), _bush_material, Transform3D(basis, offset))
		mi.set_instance_shader_parameter(&"tint", tint * _rng.randf_range(0.8, 1.1))
	if count_as_prop:
		stats.props += 1


## Auto abbandonata (modello Blender), leggermente inclinata.
func _car(base: Vector3, yaw_deg: float) -> void:
	var tilt := Basis(Vector3.FORWARD, deg_to_rad(_rng.randf_range(-3.0, 3.0)))
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * tilt
	var body := _static_body("WreckedCar", Transform3D(basis, base))
	_model(CAR_MODEL, body, Transform3D.IDENTITY, {
		&"tint": _pick(CAR_PAINTS),
		&"rust": _rng.randf_range(0.45, 0.8),
		# Playtest del 14 ottobre: da 0,3-0,8 il tetto era tutto muschio, l'auto sembrava verde.
		&"overgrowth": _rng.randf_range(0.0, 0.3),
	})
	_box_shape_child(body, Vector3(1.8, 1.5, 4.3), Transform3D(Basis(), Vector3(0.0, 0.75, 0.0)))
	_bush(base + basis * Vector3(0.9, 0.0, 1.6), 1.1, false)
	stats.props += 1


## Mucchio di macerie: lastre e blocchi inclinati.
func _rubble(center: Vector3, spread: float) -> void:
	var body := _static_body("Rubble", Transform3D(Basis(), center))
	for i in _rng.randi_range(5, 8):
		var size := Vector3(_rng.randf_range(0.6, 2.2), _rng.randf_range(0.3, 1.2), _rng.randf_range(0.6, 2.0))
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(0.0, TAU),
			_rng.randf_range(-0.35, 0.35)))
		var pos := Vector3(_rng.randf_range(-spread, spread), size.y * 0.35, _rng.randf_range(-spread, spread))
		var mi := _mesh_child(body, _unit_box_mesh(), _ruin_material, Transform3D(basis.scaled_local(size), pos))
		mi.set_instance_shader_parameter(&"base_tint", _pick(CONCRETE_TINTS))
		mi.set_instance_shader_parameter(&"top_y", center.y + pos.y + size.y)
		mi.set_instance_shader_parameter(&"overgrowth", 0.7)
		mi.set_instance_shader_parameter(&"windows", 0.0)
		_box_shape_child(body, size, Transform3D(basis, pos))
	stats.props += 1


## Lampione storto (modello Blender), spento: non e una fonte di luce.
func _lamp_post(base: Vector3) -> void:
	var lean := Basis.from_euler(Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(0.0, TAU),
		_rng.randf_range(-0.25, 0.25)))
	var body := _static_body("LampPost", Transform3D(lean, base))
	_model(LAMP_POST_MODEL, body, Transform3D.IDENTITY, {
		&"tint": Color(0.30, 0.37, 0.32),
		&"rust": _rng.randf_range(0.1, 0.3),
		&"overgrowth": 0.3,
	})
	var shape := CylinderShape3D.new()
	shape.radius = 0.15
	shape.height = 5.5
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 2.75, 0.0)
	body.add_child(collision)
	stats.props += 1


## Vagone ferroviario arrugginito (modello Blender), con felci sul tetto.
func _carriage(base: Vector3, yaw_deg: float, roll_deg: float, paint: Color) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.BACK, deg_to_rad(roll_deg))
	var body := _static_body("TrainCarriage", Transform3D(basis, base))
	_model(CARRIAGE_MODEL, body, Transform3D.IDENTITY, {
		&"tint": paint,
		&"rust": _rng.randf_range(0.35, 0.65),
		&"overgrowth": 0.9,
	})
	_box_shape_child(body, Vector3(2.9, 3.3, 13.0), Transform3D(Basis(), Vector3(0.0, 1.65, 0.0)))
	for i in _rng.randi_range(2, 4):
		var local := Vector3(_rng.randf_range(-0.8, 0.8), 3.2, _rng.randf_range(-5.5, 5.5))
		_bush(body.transform * local, _rng.randf_range(0.9, 1.6), false)
	stats.props += 1


## Barriera New Jersey in cemento (modello Blender): copertura bassa.
func _barrier(base: Vector3, yaw_deg: float) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var body := _static_body("ConcreteBarrier", Transform3D(basis, base))
	_model(BARRIER_MODEL, body, Transform3D.IDENTITY, {
		&"tint": _pick(CONCRETE_TINTS) * 1.25,
		&"rust": 0.0,
		&"overgrowth": _rng.randf_range(0.4, 0.8),
	})
	_box_shape_child(body, Vector3(0.6, 0.85, 3.0), Transform3D(Basis(), Vector3(0.0, 0.42, 0.0)))
	stats.props += 1


# --- Composizione ----------------------------------------------------------------

## Muri invisibili sul perimetro giocabile.
func _build_boundary() -> void:
	var h := 6.0
	var ex := half_x()
	var ez := half_z()
	var t := 1.0
	var walls := [
		[Vector3(0.0, h * 0.5, -ez - t * 0.5), Vector3(ex * 2.0 + t * 2.0, h, t)],
		[Vector3(0.0, h * 0.5, ez + t * 0.5), Vector3(ex * 2.0 + t * 2.0, h, t)],
		[Vector3(-ex - t * 0.5, h * 0.5, 0.0), Vector3(t, h, ez * 2.0)],
		[Vector3(ex + t * 0.5, h * 0.5, 0.0), Vector3(t, h, ez * 2.0)],
	]
	for i in walls.size():
		var body := _static_body("Boundary%d" % i, Transform3D(Basis(), walls[i][0]))
		_box_shape_child(body, walls[i][1])


## Fila nord: torri alte con una strada che si apre verso il landmark.
func _build_north() -> void:
	var z := -play_half_extent - 9.0
	var specs := [
		[Vector2(-34.0, z - 1.0), Vector2(13.0, 14.0), 26.0],
		[Vector2(-19.0, z + 0.5), Vector2(12.0, 13.0), 34.0],
		[Vector2(-6.5, z - 2.0), Vector2(9.0, 15.0), 21.0],
		[Vector2(15.0, z), Vector2(13.0, 14.0), 38.0],
		[Vector2(30.0, z - 1.5), Vector2(14.0, 15.0), 24.0],
	]
	for i in specs.size():
		_tower("NorthTower%d" % i, specs[i][0], specs[i][1], specs[i][2], _rng.randf_range(0.45, 0.85))
	# Macerie nella strada che porta verso nord, fuori dall'area giocabile.
	_rubble(Vector3(3.5, 0.0, -play_half_extent - 5.0), 2.5)


## Skyline lontano: grattacieli sommersi dal verde, sfumati dalla foschia.
func _build_skyline() -> void:
	var specs := [
		[Vector2(4.0, -110.0), Vector2(16.0, 16.0), 78.0],
		[Vector2(-40.0, -95.0), Vector2(18.0, 14.0), 55.0],
		[Vector2(45.0, -100.0), Vector2(15.0, 15.0), 62.0],
		[Vector2(-70.0, -80.0), Vector2(16.0, 16.0), 40.0],
		[Vector2(75.0, -75.0), Vector2(18.0, 16.0), 46.0],
		[Vector2(-15.0, -70.0), Vector2(14.0, 12.0), 32.0],
		[Vector2(28.0, -65.0), Vector2(12.0, 12.0), 28.0],
	]
	for i in specs.size():
		_tower("Skyline%d" % i, specs[i][0], specs[i][1], specs[i][2], _rng.randf_range(0.6, 0.95), false)


## Lato est: edifici medi, uno crollato a gradoni.
func _build_east() -> void:
	var x := play_half_extent + 8.0
	_tower("EastBlock0", Vector2(x, -12.0), Vector2(12.0, 14.0), 16.0, 0.7)
	_tower("EastBlock1", Vector2(x + 2.0, 6.0), Vector2(14.0, 12.0), 11.0, 0.8)
	_ruin_block("EastCollapsed", Vector3(x - 1.0, 0.0, 19.0), Vector3(10.0, 4.0, 9.0), 6.0,
		_pick(CONCRETE_TINTS), 0.9)
	_rubble(Vector3(play_half_extent + 1.5, 0.0, 15.0), 2.5)
	_tree(Vector3(x - 3.0, 4.0, 18.0), 1.2)


## Lato ovest: treno arrugginito deragliato, edifici dietro.
func _build_west_train() -> void:
	var x := -play_half_extent - 4.0
	_carriage(Vector3(x, 0.0, -15.0), 2.0, 0.0, Color(0.88, 0.68, 0.14))
	_carriage(Vector3(x + 0.6, 0.0, -1.5), -7.0, 4.0, Color(0.72, 0.32, 0.12))
	_carriage(Vector3(x + 2.0, 0.0, 11.5), -24.0, 12.0, Color(0.88, 0.68, 0.14))
	_tower("WestBlock0", Vector2(x - 14.0, -10.0), Vector2(14.0, 16.0), 22.0, 0.75)
	_tower("WestBlock1", Vector2(x - 12.0, 10.0), Vector2(12.0, 14.0), 13.0, 0.85)


## Lato sud: solo elementi bassi (muretti, cespugli), la camera guarda da qui.
func _build_south_edge() -> void:
	var z := half_z() + 1.6
	var x := -half_x() - 2.0
	while x < half_x() + 2.0:
		var length := _rng.randf_range(2.5, 6.0)
		var roll := _rng.randf()
		if roll < 0.25:
			_barrier(Vector3(x + 1.5, 0.0, z), 90.0 + _rng.randf_range(-8.0, 8.0))
			length = 3.0
		elif roll < 0.75:
			_ruin_block("SouthWall", Vector3(x + length * 0.5, 0.0, z + _rng.randf_range(-0.4, 0.4)),
				Vector3(length, _rng.randf_range(0.6, 1.4), 0.5), _rng.randf_range(-6.0, 6.0),
				_pick(CONCRETE_TINTS), 0.8, 0.0)
		else:
			_bush(Vector3(x + length * 0.5, 0.0, z), _rng.randf_range(1.2, 2.0))
		x += length + _rng.randf_range(0.2, 1.5)


## Anello fra il quadrato libero e il perimetro: auto, macerie, alberi, lampioni.
func _build_ring_props() -> void:
	var e := play_half_extent
	var c := clear_half_extent
	var mid := (e + c) * 0.5
	_car(Vector3(-mid, 0.0, -mid + 1.0), 35.0)
	_car(Vector3(mid + 0.5, 0.0, -2.0), 88.0)
	_car(Vector3(-mid - 0.5, 0.0, 4.5), -80.0)
	_car(Vector3(10.0, 0.0, -mid), 12.0)
	_car(Vector3(-9.0, 0.0, mid - 0.5), 100.0)
	_rubble(Vector3(mid, 0.0, mid), 2.0)
	_rubble(Vector3(-4.0, 0.0, -mid - 0.5), 1.8)
	_rubble(Vector3(-mid, 0.0, -9.0), 1.6)
	# Alberi solo a nord e ai lati: a sud coprirebbero il giocatore.
	_tree(Vector3(-mid + 0.5, 0.0, -mid - 2.0), 1.3)
	_tree(Vector3(mid - 1.0, 0.0, -mid), 1.15)
	_tree(Vector3(18.0, 0.0, -9.0), 0.95)
	_tree(Vector3(-mid, 0.0, 12.0), 1.0)
	_tree(Vector3(2.5, 0.0, -mid - 1.0), 1.25)
	_lamp_post(Vector3(-mid + 2.0, 0.0, -5.0))
	_lamp_post(Vector3(mid - 1.5, 0.0, 9.0))
	_lamp_post(Vector3(-15.0, 0.0, -mid))
	_barrier(Vector3(mid - 0.5, 0.0, -14.0), 8.0)
	_barrier(Vector3(-6.0, 0.0, -mid + 1.0), 84.0)
	_barrier(Vector3(13.5, 0.0, mid - 1.0), 100.0)
	_bush(Vector3(mid, 0.0, 15.0), 1.8)
	_bush(Vector3(-mid + 1.0, 0.0, 18.0), 1.6)
	_bush(Vector3(14.0, 0.0, mid + 0.5), 1.4)
	_bush(Vector3(5.0, 0.0, mid + 1.0), 1.2)


# --- Copertura vegetale ----------------------------------------------------------

## Formula del verde del suolo: i ciuffi crescono dove il suolo e verde.
func ground_cover_at(p: Vector2) -> float:
	var radius := plaza_radius()
	var edge := smoothstep(radius * 0.55, radius * 1.25, p.length())
	return _fbm(p * 0.09 + Vector2(3.7, 1.3)) + edge * 0.45 - 0.08 + (_value_noise(p * 2.7) - 0.5) * 0.08


func _build_ground_cover() -> void:
	# Rilievo atteso ma non ancora pronto (il quartiere nasce prima del campo nella scena):
	# niente prato a quota zero da buttare, lo costruisce `settle_on_relief` sulle quote
	# (audit R-04: prima a ogni avvio due costruzioni intere, una invisibile).
	if _cover_waits_for_settle() and terrain_field != null and not _relief_ready() and not Engine.is_editor_hint():
		return
	var limit := cover_limit()
	var limit_z := cover_limit_z()
	var height := cover_height()
	_reset_cover_lattice()
	# Generatore proprio: il prato si rifa anche da solo (`settle_on_relief`) e deve
	# uscire uguale a ogni costruzione, qualunque cosa sia stata estratta prima.
	var outer_rng := _rng
	_rng = RandomNumberGenerator.new()
	_rng.seed = layout_seed + 977
	# Il quartiere viene prima del rilievo nella scena: alla prima costruzione il campo
	# non e pronto e il prato nasce a quota zero; `settle_on_relief` lo rifa dopo.
	var relief_ready := _relief_ready()
	# Campionamento stratificato (T-02): una griglia di candidati con jitter invece del
	# rigetto su 144k punti; l'ordine e mescolato con un passo primo, cosi se i posti
	# finiscono prima della fine la copertura resta uniforme. I dati vanno dritti nel
	# buffer del MultiMesh (16 float per istanza: trasformazione 3x4 e colore).
	# Densita della vegetazione dalle impostazioni grafiche (restyling 2026-10-11):
	# vale alla prossima costruzione dell'arena, non a caldo.
	var density := _vegetation_multiplier()
	var tuft_target := int(grass_tufts * density)
	var flower_target := int(flowers * density)
	var litter_target := int(litter * density)
	var wanted := tuft_target + flower_target + litter_target
	# Candidati 3,5 volte i posti (erano 2): con il prato fitto (D-083) le zone verdi
	# esaurivano i candidati prima del numero richiesto.
	var side := int(ceil(sqrt(float(wanted) * 3.5)))
	var total := side * side
	var pitch := limit * 2.0 / maxf(float(side), 1.0)
	var pitch_z := limit_z * 2.0 / maxf(float(side), 1.0)
	var stride := 7919 if total % 7919 != 0 else 7907
	var tufts := PackedFloat32Array()
	var tuft_count := 0
	var flower_buffer := PackedFloat32Array()
	var flower_count := 0
	var litter_buffer := PackedFloat32Array()
	var litter_count := 0
	tufts.resize(grass_tufts * 16)
	flower_buffer.resize(flowers * 16)
	litter_buffer.resize(litter * 16)
	var flower_share := float(flower_target) / float(maxi(wanted, 1))
	var litter_share := float(litter_target) / float(maxi(wanted, 1))
	for k in total:
		if tuft_count >= tuft_target and flower_count >= flower_target and litter_count >= litter_target:
			break
		var index := (k * stride) % total
		var p := Vector2(-limit + (index % side + _rng.randf()) * pitch, -limit_z + (index / side + _rng.randf()) * pitch_z)
		if _cover_excluded(p):
			continue
		var ground := height
		var bonus := 0.0
		if relief_ready:
			var at := Vector3(p.x, 0.0, p.y)
			# Niente prato sui fianchi ripidi; piu fitto nelle conche (spec 6.2).
			if terrain_field.slope_at(at) > 0.6:
				continue
			ground = terrain_field.height_at(at)
			bonus = 0.12 * clampf(-terrain_field.delta_at(at), 0.0, 1.0)
		var chance := _cover_chance(p, bonus)
		var yaw := _rng.randf_range(0.0, TAU)
		# I detriti stanno anche sul costruito (chance 0), dove l'erba non cresce.
		if _rng.randf() < litter_share and litter_count < litter_target and chance >= 0.0:
			var leaf := _rng.randf() < 0.45
			var s := _rng.randf_range(0.6, 1.4)
			var size := Vector3(0.22 * s, 0.015, 0.16 * s) if leaf else Vector3(0.14 * s, 0.07 * s, 0.11 * s)
			var color := LITTER_COLORS[_rng.randi_range(3, 5)] if leaf else LITTER_COLORS[_rng.randi_range(0, 2)]
			_write_instance(litter_buffer, litter_count, yaw, size, Vector3(p.x, ground + size.y * 0.5, p.y), color)
			litter_count += 1
			continue
		if chance <= 0.0 or (chance < 1.0 and _rng.randf() > chance):
			continue
		if _rng.randf() < flower_share and flower_count < flower_target:
			var s := _rng.randf_range(0.7, 1.3)
			_write_instance(flower_buffer, flower_count, yaw, Vector3(s, s, s), Vector3(p.x, ground, p.y), _pick(FLOWER_COLORS))
			flower_count += 1
		elif tuft_count < tuft_target:
			# Prato basso (D-083): ciuffi piccoli e fitti, poco variati, tinta sobria.
			var s := _rng.randf_range(0.8, 1.25)
			_write_instance(tufts, tuft_count, yaw, Vector3(s, s * _rng.randf_range(0.8, 1.2), s), Vector3(p.x, ground, p.y),
				_pick(LEAF_TINTS) * _rng.randf_range(0.95, 1.2))
			tuft_count += 1
	tufts.resize(tuft_count * 16)
	flower_buffer.resize(flower_count * 16)
	litter_buffer.resize(litter_count * 16)
	if not gpu_grass:
		_add_tiled_cover("GrassTufts", _tuft_mesh(), tufts, tuft_count, _grass_material)
	_add_tiled_cover("Flowers", _flower_mesh(), flower_buffer, flower_count)
	_add_tiled_cover("Litter", _unit_box_mesh(), litter_buffer, litter_count, _litter_material)
	stats.tufts = tuft_count
	stats.flowers = flower_count
	stats.litter = litter_count
	_rng = outer_rng


## Passa il prato a GrassField (playtest del 14 ottobre 2026, O-09): toglie i ciuffi del
## MultiMesh e non li rifa piu; fiori e detriti restano.
func drop_tuft_cover() -> void:
	gpu_grass = true
	var old := get_node_or_null(^"GrassTufts")
	if old != null:
		_generated.erase(old)
		remove_child(old)
		old.queue_free()


## Vero se chi usa questa arena chiama sempre `settle_on_relief` (le run): allora il prato
## non si costruisce a quota zero. L'arena minore (`ruins_arena`) non lo chiama: costruisce subito.
func _cover_waits_for_settle() -> bool:
	return false


func _relief_ready() -> bool:
	return terrain_field != null and terrain_field.is_node_ready() and terrain_field.resolution_x > 0


## Corone e tondini (MultiMesh in coordinate mondo) con lo stesso scarto di quota del loro
## muro, dal buffer piatto della composizione: ripetibile (audit R-05).
func _shift_details(node_name: String, flat: PackedFloat32Array, hosts: Array) -> void:
	var node := get_node_or_null(NodePath(node_name)) as MultiMeshInstance3D
	if node == null or hosts.is_empty() or node.multimesh.instance_count != hosts.size():
		return
	var buffer := flat.duplicate()
	for i in hosts.size():
		var host: Variant = hosts[i]
		if host == null or not is_instance_valid(host) or not (host as Node).has_meta(&"flat_y"):
			continue
		buffer[i * 16 + 7] += (host as Node3D).position.y - float((host as Node).get_meta(&"flat_y"))
	node.multimesh.buffer = buffer


## Rilievo continuo (D-085): appoggia alle quote i corpi generati a quota zero (rovine
## un poco affondate, cosi i muri non galleggiano sulle ondulazioni) e rifa prato, fiori e
## detriti sulle quote. Da chiamare quando il rilievo di base e pronto; ripetibile.
func settle_on_relief() -> void:
	if not _relief_ready():
		return
	var half := terrain_field.half_extents()
	for node in _generated:
		if not (node is Node3D) or node is MultiMeshInstance3D or node is DirectionalLight3D or node is CloudShadows:
			continue
		# Contenitori delle porzioni di copertura: si rifanno sotto, non si spostano.
		if node.name in ["GrassTufts", "Flowers", "Litter"]:
			continue
		var body := node as Node3D
		if absf(body.position.x) > half.x or absf(body.position.z) > half.y:
			continue
		if not body.has_meta(&"flat_y"):
			body.set_meta(&"flat_y", body.position.y)
		var flat_y: float = body.get_meta(&"flat_y")
		var sink := 0.2 if String(body.name).begins_with("Block") else 0.0
		body.position.y = flat_y + terrain_field.height_at(body.position) - sink
	_shift_details("RuinCrowns", _crown_buffer, _crown_hosts)
	_shift_details("RuinRebar", _rebar_buffer, _rebar_hosts)
	for cover_name in ["GrassTufts", "Flowers", "Litter"]:
		var old := get_node_or_null(NodePath(cover_name))
		if old != null:
			_generated.erase(old)
			remove_child(old)
			old.queue_free()
	_build_ground_cover()


## Scrive un'istanza (rotazione attorno a Y, scala, posizione, colore) nel formato del
## buffer di MultiMesh: tre righe della trasformazione (x.x y.x z.x o.x ...) e RGBA.
static func _write_instance(buffer: PackedFloat32Array, index: int, yaw: float, scale: Vector3, origin: Vector3, color: Color) -> void:
	var c := cos(yaw)
	var sn := sin(yaw)
	var base := index * 16
	# Basis(Vector3.UP, yaw).scaled(scale): colonne x = (c, 0, -sn)·sx, y = (0, 1, 0)·sy, z = (sn, 0, c)·sz.
	buffer[base] = c * scale.x
	buffer[base + 1] = 0.0
	buffer[base + 2] = sn * scale.z
	buffer[base + 3] = origin.x
	buffer[base + 4] = 0.0
	buffer[base + 5] = scale.y
	buffer[base + 6] = 0.0
	buffer[base + 7] = origin.y
	buffer[base + 8] = -sn * scale.x
	buffer[base + 9] = 0.0
	buffer[base + 10] = c * scale.z
	buffer[base + 11] = origin.z
	buffer[base + 12] = color.r
	buffer[base + 13] = color.g
	buffer[base + 14] = color.b
	buffer[base + 15] = color.a


## Erba, fiori e detriti in porzioni da COVER_TILE_M (audit V-01): un MultiMesh grande
## come la mappa non esce mai dal frustum e la GPU elaborava tutto il prato (1,4 M
## triangoli su due passate) per vederne il 2-4 %. Un nodo [param node_name] con un
## MultiMeshInstance3D per porzione non vuota; le istanze si riordinano per porzione con
## un ordinamento a conteggio (origine nei float 3 e 11 di ogni istanza).
func _add_tiled_cover(node_name: String, mesh: Mesh, buffer: PackedFloat32Array, count: int,
		material: Material = null) -> void:
	var holder := Node3D.new()
	holder.name = node_name
	_add_generated(holder)
	var limit := cover_limit()
	var limit_z := cover_limit_z()
	var cols := maxi(int(ceil(limit * 2.0 / COVER_TILE_M)), 1)
	var rows := maxi(int(ceil(limit_z * 2.0 / COVER_TILE_M)), 1)
	var tile_of := PackedInt32Array()
	tile_of.resize(count)
	var offsets := PackedInt32Array()
	offsets.resize(cols * rows + 1)
	offsets.fill(0)
	for i in count:
		var tx := clampi(int((buffer[i * 16 + 3] + limit) / COVER_TILE_M), 0, cols - 1)
		var tz := clampi(int((buffer[i * 16 + 11] + limit_z) / COVER_TILE_M), 0, rows - 1)
		var t := tz * cols + tx
		tile_of[i] = t
		offsets[t + 1] += 1
	for t in cols * rows:
		offsets[t + 1] += offsets[t]
	var ordered := PackedFloat32Array()
	ordered.resize(count * 16)
	var cursor := offsets.duplicate()
	for i in count:
		var t := tile_of[i]
		var dst := cursor[t] * 16
		cursor[t] += 1
		var src := i * 16
		for j in 16:
			ordered[dst + j] = buffer[src + j]
	for t in cols * rows:
		var n := offsets[t + 1] - offsets[t]
		if n == 0:
			continue
		var tile := _cover_tile(mesh, ordered.slice(offsets[t] * 16, offsets[t + 1] * 16), n, material)
		tile.name = "%s_%d_%d" % [node_name, t % cols, t / cols]
		holder.add_child(tile)


func _cover_tile(mesh: Mesh, buffer: PackedFloat32Array, count: int, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buffer
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material if material != null else _foliage_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _add_multimesh(node_name: String, mesh: Mesh, buffer: PackedFloat32Array, count: int,
		material: Material = null) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	if count > 0:
		mm.buffer = buffer
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material if material != null else _foliage_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_generated(mmi)


## Ciuffo (D-068): tre quad incrociati a 60 gradi con la texture delle lame; la
## scala per istanza li porta a 0,3-0,65 m. UV.y = 0 in punta, 1 al piede.
const TUFT_HALF_WIDTH := 0.20
const TUFT_HEIGHT := 0.40
# Raggio della chiazza: tre coppie di quad attorno al centro del ciuffo.
const TUFT_PATCH_RADIUS := 0.26


func _tuft_mesh() -> ArrayMesh:
	# Chiazza di prato (D-083): tre coppie di quad incrociati, sfalsate attorno al
	# centro, per dodici triangoli. Una chiazza copre circa mezzo metro, cosi il prato
	# si chiude con meno istanze di quante ne servirebbero a ciuffi singoli.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
	for pair in 3:
		var around := TAU * float(pair) / 3.0
		var center := Vector3(cos(around), 0.0, sin(around)) * TUFT_PATCH_RADIUS * (0.0 if pair == 0 else 1.0)
		var height := TUFT_HEIGHT * (1.0 if pair == 0 else 0.85)
		for k in 2:
			var a := PI * 0.5 * float(k) + around * 0.5
			var side := Vector3(cos(a), 0.0, sin(a)) * TUFT_HALF_WIDTH
			var lean := Vector3(-sin(a), 0.0, cos(a)) * 0.03
			var corners: Array[Vector3] = [center - side, center + side,
				center + side + Vector3(0.0, height, 0.0) + lean, center - side + Vector3(0.0, height, 0.0) + lean]
			for index in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_color(Color.WHITE)
				st.set_uv(uvs[index])
				st.add_vertex(corners[index])
	return st.commit()


## Fiore: piccolo bocciolo su uno stelo.
## Testa del fiore: un ottaedro di 14 cm (8 triangoli). Era una sfera da 48 triangoli larga
## circa 4 pixel sul Deck: micro-triangoli, 192 k su 4000 fiori (audit V-05).
func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0.0, 0.28, 0.0)
	var top := center + Vector3(0.0, 0.05, 0.0)
	var bottom := center - Vector3(0.0, 0.05, 0.0)
	var ring: Array[Vector3] = [center + Vector3(0.07, 0.0, 0.0), center + Vector3(0.0, 0.0, 0.07),
		center + Vector3(-0.07, 0.0, 0.0), center + Vector3(0.0, 0.0, -0.07)]
	for k in 4:
		var a := ring[k]
		var b := ring[(k + 1) % 4]
		for v: Vector3 in [top, b, a, bottom, a, b]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


# --- Rumore (porta di noise.gdshaderinc) ------------------------------------------

static func _fract(v: float) -> float:
	return v - floorf(v)


static func _hash12(p: Vector2) -> float:
	var p3 := Vector3(_fract(p.x * 0.1031), _fract(p.y * 0.1031), _fract(p.x * 0.1031))
	var d := p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3(33.33, 33.33, 33.33))
	p3 += Vector3(d, d, d)
	return _fract((p3.x + p3.y) * p3.z)


static func _value_noise(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := _hash12(i)
	var b := _hash12(i + Vector2(1.0, 0.0))
	var c := _hash12(i + Vector2(0.0, 1.0))
	var d := _hash12(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func _fbm(p: Vector2) -> float:
	var v := 0.0
	var a := 0.5
	for k in 5:
		v += a * _value_noise(p)
		p = p * 2.03 + Vector2(17.1, 9.2)
		a *= 0.5
	return v


# --- Luce e atmosfera --------------------------------------------------------------

func _add_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	# Luce bassa e dorata in controluce laterale (D-094): il sole sta davanti alla camera,
	# a nord-ovest, circa 27 gradi sull'orizzonte. Le ombre lunghe scendono verso lo
	# spettatore e a destra, i rilievi hanno un lato acceso e uno in ombra, i bordi si
	# accendono. Prima arrivava da dietro la camera: luce frontale, la piu piatta.
	sun.basis = Basis.looking_at(SUN_DIRECTION.normalized(), Vector3.UP)
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	# Riflesso del sole contenuto: in controluce le lastre lisce diventavano bianche.
	sun.light_specular = 0.3
	sun.light_angular_distance = 1.5
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 90.0
	_add_generated(sun)
	var fill := FillLight.new()
	fill.sun = sun
	_add_generated(fill)
	var clouds := CloudShadows.new()
	clouds.sun = sun
	_add_generated(clouds)


func _add_environment() -> void:
	# Cielo a gradiente dipinto (restyling 2026-10-11, D-077); DayNightCycle ne interpola
	# i colori verso la notte.
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter(&"top_color", SKY_DAY_TOP)
	sky_material.set_shader_parameter(&"horizon_color", SKY_DAY_HORIZON)
	sky_material.set_shader_parameter(&"ground_color", SKY_DAY_GROUND)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Ambiente freddo e saturo a colore fisso (D-094): le ombre del sole caldo diventano
	# blu-viola invece che nere o grigie. L'ambiente dal cielo e stato provato: velava
	# tutto di grigio.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# AgX (D-094): tiene i colori saturi nelle alte luci, dove ACES li sbiancava.
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_agx_contrast = 1.4
	# Foschia del colore dell'orizzonte solo in lontananza: il campo di gioco resta nitido.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = SKY_DAY_HORIZON
	environment.fog_density = 0.5
	environment.fog_depth_begin = 45.0
	environment.fog_depth_end = 160.0
	environment.fog_depth_curve = 1.6
	environment.fog_sun_scatter = 0.25
	# La skyline lontana prende il colore del cielo (D-068).
	environment.fog_aerial_perspective = 0.45
	environment.ssao_enabled = true
	# Occlusione di contatto (O-07): raggio corto e curva piu dura, cosi si vede nei piedi
	# dei muri, nelle buche e sotto i prop, e tocca anche un po' la luce diretta.
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 2.4
	environment.ssao_power = 1.6
	environment.ssao_detail = 0.7
	environment.ssao_light_affect = 0.3
	# Bagliore a piu livelli, in soft light, solo su emissive e alte luci calde.
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.set_glow_level(1, 0.6)
	environment.set_glow_level(3, 0.8)
	environment.set_glow_level(5, 0.4)
	# Gradazione decisa: contrasto e saturazione alla Hades II.
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.15
	environment.adjustment_saturation = 1.3

	var camera_attributes := CameraAttributesPractical.new()
	camera_attributes.auto_exposure_enabled = false

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	world_environment.camera_attributes = camera_attributes
	_add_generated(world_environment)
	# Preset grafico (ombre, SSAO, GI, bagliore, volumetrica) dalle impostazioni, anche a caldo.
	var settings := _game_settings()
	if settings != null:
		settings.apply_to_world(environment, get_node_or_null(^"SunLight") as DirectionalLight3D)
		if not settings.changed.is_connected(_on_settings_changed):
			settings.changed.connect(_on_settings_changed)


## L'autoload non esiste in --check-only ne in alcune scene di test: si tollera l'assenza.
func _game_settings() -> GameSettingsService:
	return get_node_or_null(^"/root/GameSettings") as GameSettingsService if is_inside_tree() else null


func _vegetation_multiplier() -> float:
	var settings := _game_settings()
	return settings.vegetation_multiplier() if settings != null else 1.0


func _on_settings_changed() -> void:
	var settings := _game_settings()
	var world_environment := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if settings != null and world_environment != null and world_environment.environment != null:
		settings.apply_to_world(world_environment.environment, get_node_or_null(^"SunLight") as DirectionalLight3D)


