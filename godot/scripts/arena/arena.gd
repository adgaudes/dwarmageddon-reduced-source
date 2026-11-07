@tool
class_name Arena
extends Node3D
## Arena graybox: pavimento, pilastri angolari, landmark direzionale, sole e cielo.
##
## Porta di APrototype01ArenaActor. I parametri sono quelli Unreal in centimetri,
## convertiti una sola volta tramite UnrealSpace. La costruzione gira anche
## nell'editor (@tool), come OnConstruction in Unreal: editor e gioco coincidono,
## e si ripete a ogni modifica dei parametri dall'Inspector.
## Il piano superiore del pavimento e a y = 0 nello spazio locale.

const GRID_SHADER := preload("res://resources/materials/world_grid.gdshader")

@export var floor_size_cm := 6000.0:
	set(value):
		floor_size_cm = value
		_queue_rebuild()
@export var floor_thickness_cm := 40.0:
	set(value):
		floor_thickness_cm = value
		_queue_rebuild()
@export var pillar_height_cm := 500.0:
	set(value):
		pillar_height_cm = value
		_queue_rebuild()
@export var pillar_size_cm := 150.0:
	set(value):
		pillar_size_cm = value
		_queue_rebuild()
@export var pillar_inset_from_edge_cm := 350.0:
	set(value):
		pillar_inset_from_edge_cm = value
		_queue_rebuild()
@export var direction_marker_height_cm := 700.0:
	set(value):
		direction_marker_height_cm = value
		_queue_rebuild()
@export var direction_marker_size_cm := 200.0:
	set(value):
		direction_marker_size_cm = value
		_queue_rebuild()

## Colori lineari Unreal, nell'ordine dei pilastri (+X+Y, -X+Y, -X-Y, +X-Y in assi UE).
const PILLAR_COLORS_LINEAR: Array[Color] = [
	Color(0.9, 0.05, 0.05),
	Color(0.05, 0.8, 0.15),
	Color(0.1, 0.35, 0.95),
	Color(0.95, 0.85, 0.05),
]
const DIRECTION_MARKER_COLOR_LINEAR := Color(0.85, 0.1, 0.85)

## FRotator(-45, -30, 0) del sole Unreal; FColor(255, 236, 209).
const SUN_PITCH_DEG := -45.0
const SUN_YAW_DEG := -30.0
const SUN_COLOR := Color8(255, 236, 209)

## Nodi generati: non hanno owner, quindi non vengono salvati nella scena.
var _generated: Array[Node] = []
var _rebuild_pending := false


func _ready() -> void:
	rebuild()
	if not Engine.is_editor_hint():
		print("PROTOTYPE01_EXPOSURE_READY")
		var landmark := UnrealSpace.position(Vector3(0.0, _corner_offset_cm(), 0.0))
		print("PROTOTYPE01_ARENA_READY floor=%.1fm pillars=4 landmark=(%.1f, %.1f)"
			% [UnrealSpace.length(floor_size_cm), landmark.x, landmark.z])


## Piu modifiche nello stesso frame producono una sola ricostruzione.
func _queue_rebuild() -> void:
	if not is_node_ready() or _rebuild_pending:
		return
	_rebuild_pending = true
	_flush_rebuild.call_deferred()


func _flush_rebuild() -> void:
	# Una rebuild() diretta nel frattempo ha gia azzerato la richiesta.
	if _rebuild_pending:
		rebuild()


func _add_generated(node: Node) -> void:
	add_child(node)
	_generated.append(node)


func _corner_offset_cm() -> float:
	return floor_size_cm * 0.5 - pillar_inset_from_edge_cm


## Ricostruzione idempotente: rimuove sempre i nodi generati in precedenza.
func rebuild() -> void:
	_rebuild_pending = false
	for node in _generated:
		remove_child(node)
		node.queue_free()
	_generated.clear()

	var floor_extent := UnrealSpace.length(floor_size_cm)
	var floor_thickness := UnrealSpace.length(floor_thickness_cm)
	var grid_material := ShaderMaterial.new()
	grid_material.shader = GRID_SHADER
	_add_box("Floor", Vector3(floor_extent, floor_thickness, floor_extent),
		Vector3(0.0, -floor_thickness * 0.5, 0.0), grid_material)

	var corner := _corner_offset_cm()
	var unreal_corners: Array[Vector2] = [
		Vector2(corner, corner), Vector2(-corner, corner),
		Vector2(-corner, -corner), Vector2(corner, -corner),
	]
	var pillar_size := UnrealSpace.length(pillar_size_cm)
	var pillar_height := UnrealSpace.length(pillar_height_cm)
	for i in unreal_corners.size():
		var c := unreal_corners[i]
		var pos := UnrealSpace.position(Vector3(c.x, c.y, 0.0)) + Vector3(0.0, pillar_height * 0.5, 0.0)
		_add_box("CornerPillar%d" % i, Vector3(pillar_size, pillar_height, pillar_size),
			pos, _color_material(PILLAR_COLORS_LINEAR[i]))

	var marker_size := UnrealSpace.length(direction_marker_size_cm)
	var marker_height := UnrealSpace.length(direction_marker_height_cm)
	var marker_pos := UnrealSpace.position(Vector3(0.0, corner, 0.0)) + Vector3(0.0, marker_height * 0.5, 0.0)
	_add_box("DirectionMarker", Vector3(marker_size, marker_height, marker_size),
		marker_pos, _color_material(DIRECTION_MARKER_COLOR_LINEAR))

	_add_sun()
	_add_environment()


func _add_box(node_name: String, size: Vector3, pos: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	_add_generated(body)

	var mesh := BoxMesh.new()
	mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)


func _color_material(linear_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# StandardMaterial3D lavora in sRGB, i colori Unreal sono lineari.
	material.albedo_color = linear_color.linear_to_srgb()
	material.roughness = 0.6
	return material


func _add_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	var direction := UnrealSpace.rotator_forward(SUN_PITCH_DEG, SUN_YAW_DEG)
	sun.basis = Basis.looking_at(direction, Vector3.UP)
	sun.light_color = SUN_COLOR
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	_add_generated(sun)


func _add_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# Auto-esposizione disattivata, come r.EyeAdaptationQuality=0 in Unreal.
	var camera_attributes := CameraAttributesPractical.new()
	camera_attributes.auto_exposure_enabled = false

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	world_environment.camera_attributes = camera_attributes
	_add_generated(world_environment)
