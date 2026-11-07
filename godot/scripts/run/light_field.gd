class_name LightField
extends RefCounted
## Sorgenti di luce "logiche" del ciclo giorno/notte (D-058, tappa 1): torcia del
## giocatore, Faro della carovana (le macchine col BeaconModule) e, dalla tappa 2, i
## lampioni. Logica pura: dice se un punto e illuminato confrontando la distanza planare col
## raggio di ogni sorgente.
## Un nodo liberato o fuori dall'albero conta come spento, senza errori.

var _sources: Dictionary[int, Dictionary] = {}
var _next_id := 1
# Istantanea delle sorgenti accese (x, z, raggio al quadrato), rinfrescata da `refresh()`
# una volta per passo: `is_lit` scorre array impacchettati invece dei dizionari.
var _xs := PackedFloat32Array()
var _zs := PackedFloat32Array()
var _r2 := PackedFloat32Array()
var _snapshot_valid := false
var _snapshot_frame := -1


## Registra una sorgente centrata su [param node]; restituisce il suo id (da 1 in su).
func add_source(node: Node3D, radius: float) -> int:
	var id := _next_id
	_next_id += 1
	_sources[id] = {node = node, radius = maxf(radius, 0.0)}
	_snapshot_valid = false
	return id


func set_radius(id: int, radius: float) -> void:
	if _sources.has(id):
		_sources[id].radius = maxf(radius, 0.0)
		_snapshot_valid = false


func radius_of(id: int) -> float:
	return _sources[id].radius if _sources.has(id) else 0.0


## Nodo della sorgente [param id], o null se l'id non c'e o il nodo e stato liberato.
func source_node(id: int) -> Node3D:
	if not _sources.has(id):
		return null
	var holder: Variant = _sources[id].node
	return holder as Node3D if is_instance_valid(holder) else null


func remove_source(id: int) -> void:
	_sources.erase(id)
	_snapshot_valid = false


## Rilegge le posizioni delle sorgenti: da chiamare una volta per passo prima di molte
## domande (`is_lit` lo fa da solo se l'istantanea manca, ma le sorgenti si muovono).
func refresh() -> void:
	_xs.clear()
	_zs.clear()
	_r2.clear()
	for source: Dictionary in _sources.values():
		var holder: Variant = source.node
		if not is_instance_valid(holder):
			continue
		var node := holder as Node3D
		if node == null or not node.is_inside_tree():
			continue
		var origin := node.global_position
		var radius: float = source.radius
		_xs.append(origin.x)
		_zs.append(origin.z)
		_r2.append(radius * radius)
	_snapshot_valid = true
	_snapshot_frame = Engine.get_physics_frames()


func source_count() -> int:
	return _sources.size()


## Il punto e dentro almeno una sorgente accesa? Planare: la quota non conta.
## Legge l'istantanea di `refresh()`, rifatta da sola al piu una volta per passo fisico
## (le sorgenti si muovono): nello stesso passo di un cambiamento serve `refresh()`.
func is_lit(world: Vector3) -> bool:
	if not _snapshot_valid or _snapshot_frame != Engine.get_physics_frames():
		refresh()
	for i in _xs.size():
		var dx := world.x - _xs[i]
		var dz := world.z - _zs[i]
		if dx * dx + dz * dz <= _r2[i]:
			return true
	return false
