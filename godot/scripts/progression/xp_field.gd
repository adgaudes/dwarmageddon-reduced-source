class_name XpField
extends Node3D
## Frammenti di esperienza a terra (PROGRESSION_SPEC, sezione 4): nascono dove
## muore un nemico e volano verso chi li attira entro il suo raggio. Il
## giocatore attira sempre; le macchine della carovana col modulo Calamita (MagnetModule).

signal collected(amount: int)

const FRAGMENT_COLOR := Color(0.1, 0.95, 0.75)
const FRAGMENT_SIZE := 0.22
const COLLECT_DISTANCE := 0.55
const FLY_SPEED := 9.0
const FLY_ACCELERATION := 30.0
const MAX_FRAGMENTS := 250
## Altezza dei frammenti sopra il suolo.
const HOVER_HEIGHT := 0.35

@export var player: Node3D
@export var player_radius := 2.5
## Rilievo continuo (audit P-01): i frammenti stanno sopra il suolo e lo seguono. Senza,
## stanno a quota fissa (scene minori).
var terrain_field: TerrainField:
	set(value):
		if terrain_field != null and terrain_field.region_changed.is_connected(_on_region_changed):
			terrain_field.region_changed.disconnect(_on_region_changed)
		terrain_field = value
		if terrain_field != null:
			terrain_field.region_changed.connect(_on_region_changed)

## Attrattori aggiuntivi: { node: Node3D, radius: float }.
var attractors: Array[Dictionary] = []
var _fragments: Array[Dictionary] = []
var _mesh := BoxMesh.new()
var _material := StandardMaterial3D.new()
var _time := 0.0


func _ready() -> void:
	_mesh.size = Vector3.ONE * FRAGMENT_SIZE
	_material.albedo_color = FRAGMENT_COLOR.linear_to_srgb()
	_material.emission_enabled = true
	_material.emission = FRAGMENT_COLOR.linear_to_srgb()
	_material.emission_energy_multiplier = 1.2


func count() -> int:
	return _fragments.size()


func spawn(world: Vector3, value: int) -> void:
	# Oltre il limite il valore si somma al frammento piu vecchio: niente va perso.
	if _fragments.size() >= MAX_FRAGMENTS:
		_fragments[0].value += value
		return
	var node := MeshInstance3D.new()
	node.mesh = _mesh
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.rotation = Vector3(PI * 0.25, 0.0, PI * 0.25)
	add_child(node)
	node.global_position = Vector3(world.x, _hover_y(world), world.z)
	_fragments.append({node = node, value = value, speed = 0.0, target = null})


func set_attractor(node: Node3D, radius: float) -> void:
	for entry in attractors:
		if entry.node == node:
			entry.radius = radius
			return
	attractors.append({node = node, radius = radius})


## Toglie l'attrattore [param node] (una Calamita spenta): i frammenti che volavano verso di
## lui tornano a scegliere il bersaglio.
func remove_attractor(node: Node3D) -> void:
	for k in range(attractors.size() - 1, -1, -1):
		if is_instance_valid(attractors[k].node) and attractors[k].node == node:
			attractors.remove_at(k)
	for fragment: Dictionary in _fragments:
		if not is_instance_valid(fragment.target) or fragment.target == node:
			fragment.target = null


func _physics_process(delta: float) -> void:
	_time += delta
	for k in range(_fragments.size() - 1, -1, -1):
		var fragment: Dictionary = _fragments[k]
		var node: MeshInstance3D = fragment.node
		# Un bersaglio liberato (una macchina tolta) non si insegue: se ne sceglie un altro.
		if not is_instance_valid(fragment.target):
			fragment.target = null
		if fragment.target == null:
			fragment.target = _attractor_for(node.global_position)
		if fragment.target == null:
			node.rotation.y += delta * 2.0
			continue
		var target: Node3D = fragment.target
		var goal := target.global_position
		var to_goal := Vector3(goal.x - node.global_position.x, 0.0, goal.z - node.global_position.z)
		if to_goal.length() <= COLLECT_DISTANCE:
			_fragments.remove_at(k)
			node.queue_free()
			collected.emit(fragment.value)
			continue
		fragment.speed = minf(fragment.speed + FLY_ACCELERATION * delta, FLY_SPEED * 2.0)
		var next := node.global_position + to_goal.normalized() * minf(fragment.speed * delta, to_goal.length())
		next.y = _hover_y(next)
		node.global_position = next


func _attractor_for(world: Vector3) -> Node3D:
	if player != null and _planar_distance(player.global_position, world) <= player_radius:
		return player
	for entry in attractors:
		var node: Node3D = entry.node
		if is_instance_valid(node) and _planar_distance(node.global_position, world) <= entry.radius:
			return node
	return null


func _hover_y(world: Vector3) -> float:
	return (terrain_field.height_at(world) if terrain_field != null else 0.0) + HOVER_HEIGHT


## Il suolo e cambiato in [param aabb]: i frammenti fermi li dentro si riappoggiano.
func _on_region_changed(aabb: AABB) -> void:
	for fragment: Dictionary in _fragments:
		var node: Node3D = fragment.node
		var at := node.global_position
		if at.x >= aabb.position.x and at.x <= aabb.end.x and at.z >= aabb.position.z and at.z <= aabb.end.z:
			node.global_position.y = _hover_y(at)


static func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
