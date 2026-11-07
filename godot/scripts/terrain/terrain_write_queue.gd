class_name TerrainWriteQueue
extends Node
## Coda delle scritture delle armi sul terreno (spec D-092, par. 8-9): al piu WRITES_PER_STEP
## pennellate per passo fisico, raggio limitato, punti protetti o fuori campo scartati. Un anello
## del picchetto sale cosi un disco alla volta: si vede crescere e non pesa su un solo frame.
## Un rialzo secco sotto un corpo lo incastrerebbe nella heightfield (GODOT_WORKFLOW): dopo ogni
## pennellata i nemici sul disco salgono col suolo e i corpi di `bodies` (giocatore, macchine
## della carovana) restano alla stessa altezza sul suolo, come fa il terremoto. Le scritture urgenti (la
## spianata davanti all'Ariete) passano davanti alla coda.

const WRITES_PER_STEP := 1
const MAX_RADIUS := 2.5

var terrain_field: TerrainField
## Per sollevare i nemici sui dischi che salgono (opzionale).
var director: EnemyDirector
## Giocatore e macchine della carovana: restano alla stessa altezza sul suolo se il suolo sale
## (opzionale). Si aggiunge un corpo alla volta (lista tipizzata).
var bodies: Array[Node3D] = []
var _jobs: Array[Dictionary] = []


func _ready() -> void:
	process_physics_priority = -10


## Porta il disco verso [param target] (TerrainField.level), quando tocca a lui; con
## [param urgent] prima di tutte le altre.
func push_level(center: Vector3, radius: float, target: float, strength := 1.0, urgent := false) -> void:
	if terrain_field == null or terrain_field.is_protected(center):
		return
	var half := terrain_field.half_extents()
	if absf(center.x) > half.x or absf(center.z) > half.y:
		return
	var job := {center = center, radius = minf(radius, MAX_RADIUS), target = target, strength = strength}
	if urgent:
		_jobs.push_front(job)
	else:
		_jobs.append(job)


func pending() -> int:
	return _jobs.size()


func clear() -> void:
	_jobs.clear()


func _physics_process(_delta: float) -> void:
	if _jobs.is_empty() or terrain_field == null:
		return
	terrain_field.begin_batch()
	for i in mini(WRITES_PER_STEP, _jobs.size()):
		var job: Dictionary = _jobs.pop_front()
		var offsets := _body_offsets(job.center, job.radius)
		if terrain_field.level(job.center, job.radius, job.target, job.strength) > 0.0:
			_lift(job.center, job.radius, offsets)
	terrain_field.end_batch()


## Altezza sul suolo dei corpi di `bodies` dentro il disco, prima della pennellata.
func _body_offsets(center: Vector3, radius: float) -> Dictionary:
	var offsets := {}
	for body in bodies:
		if body != null and is_instance_valid(body) and _planar(body.global_position, center) <= radius + 0.5:
			offsets[body] = body.global_position.y - terrain_field.height_at(body.global_position)
	return offsets


## Il suolo e salito: nemici sopra il suolo nuovo, corpi alla stessa altezza di prima.
func _lift(center: Vector3, radius: float, offsets: Dictionary) -> void:
	if director != null:
		for enemy in director.enemies_near(center, radius + 0.5):
			if enemy.is_dead or enemy.self_driven:
				continue
			var floor_y := terrain_field.height_at(enemy.global_position) + enemy.spawn_center_height()
			if enemy.global_position.y < floor_y:
				enemy.global_position.y = floor_y
				enemy.reset_physics_interpolation()
	for body: Node3D in offsets:
		var target: float = terrain_field.height_at(body.global_position) + offsets[body]
		if target > body.global_position.y:
			body.global_position.y = target
			body.reset_physics_interpolation()


static func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
