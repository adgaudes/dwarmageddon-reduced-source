class_name LampField
extends Node3D
## Lampioni piazzabili (D-058, tappa 2; `DAY_NIGHT_SPEC.md` sezione 7). Possiede i
## lampioni: regole di piazzamento, limite, costo in rottami della carovana, nodo visivo e
## luce di ciascuno, registrazione in `LightField`, rimozione quando il suolo sotto
## cambia o quando il Demolitore ci passa sopra. Non blocca il passaggio: il campo di
## percorso non lo vede. Sul rilievo continuo (D-085) un lampione e un punto: si pianta
## su suolo piano, a distanza da altri lampioni, e cade se il suolo si sposta di oltre
## FALL_SHIFT_M.

signal lamps_changed(count: int)
signal lamp_placed(at: Vector3)
signal lamp_lost(at: Vector3, reason: StringName)

const POLE_HEIGHT := 2.2
const HEAD_SIZE := 0.36
const LAMP_COLOR := Color(1.0, 0.85, 0.55)
## Rilievo continuo: disco piano richiesto, distanza minima fra pali, spostamento che abbatte.
const FLAT_RADIUS_M := 1.0
const FLAT_TOLERANCE_M := 0.3
const MIN_SPACING_M := 2.0
const FALL_SHIFT_M := 0.4

## Rilievo continuo (D-085): i lampioni stanno su punti del rilievo.
@export var terrain_field: TerrainField
## Chi paga i lampioni (rottami dei Cassoni); senza carovana sono gratis (scene senza carovana).
@export var caravan: Caravan

## Copiati dal tuning da ArenaRun.
var scrap_cost := 3
var max_count := 6
var light_radius := 5.0
## Luce logica dove registrare i lampioni; senza, i lampioni sono solo visivi.
var light_field: LightField

## Rilievo: { position: Vector3 (base del palo), node: Node3D, source: int, rest_height: float }.
var _posts: Array[Dictionary] = []
var _pole_mesh: CylinderMesh
var _head_mesh: BoxMesh
var _pole_material: StandardMaterial3D
var _head_material: StandardMaterial3D


func _ready() -> void:
	if terrain_field != null:
		terrain_field.region_changed.connect(_on_region_changed)


func count() -> int:
	return _posts.size()


## Basi dei pali nel mondo.
func positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for post in _posts:
		result.append(post.position)
	return result


## Il punto puo ricevere un lampione (regole della specifica, senza il costo).
func can_place(point: Vector3) -> bool:
	if _posts.size() >= max_count or terrain_field == null:
		return false
	var half := terrain_field.half_extents()
	if absf(point.x) > half.x - FLAT_RADIUS_M or absf(point.z) > half.y - FLAT_RADIUS_M:
		return false
	if terrain_field.is_protected(point) or not terrain_field.is_flat(point, FLAT_RADIUS_M, FLAT_TOLERANCE_M):
		return false
	for post in _posts:
		if _planar_distance(post.position, point) < MIN_SPACING_M:
			return false
	return true


## La carovana ha i rottami per un lampione, nei Cassoni entro il raggio di rifornimento dal punto.
func can_afford(world_target: Vector3) -> bool:
	if caravan == null:
		return true
	return caravan.can_supply_count(world_target, scrap_cost)


## Piazza un lampione nel punto sotto [param world_target], pagandolo. False se rifiutato.
func place_at(world_target: Vector3) -> bool:
	var point := Vector3(world_target.x, 0.0, world_target.z)
	if not can_place(point):
		print("PROTOTYPE01_LAMP_REJECTED x=%.1f z=%.1f reason=ground count=%d" % [point.x, point.z, count()])
		return false
	if not can_afford(world_target):
		print("PROTOTYPE01_LAMP_REJECTED x=%.1f z=%.1f reason=scrap" % [point.x, point.z])
		return false
	if caravan != null:
		caravan.spend_count(scrap_cost)
	var base := _build_post(point)
	print("PROTOTYPE01_LAMP_PLACED x=%.1f z=%.1f count=%d" % [point.x, point.z, count()])
	lamp_placed.emit(base)
	lamps_changed.emit(count())
	return true
## Abbatte i lampioni entro [param radius] (piano XZ) da [param world]; restituisce quanti.
func knock_down_near(world: Vector3, radius: float) -> int:
	var hit_posts := 0
	for i in range(_posts.size() - 1, -1, -1):
		if _planar_distance(_posts[i].position, world) <= radius:
			_remove_post(i, &"demolisher")
			hit_posts += 1
	return hit_posts


## Abbatte i lampioni con la base nel rettangolo XZ (il treno); ritorna quanti.
func knock_down_in_rect(rect: Rect2) -> int:
	var hit := 0
	for i in range(_posts.size() - 1, -1, -1):
		var p: Vector3 = _posts[i].position
		if rect.has_point(Vector2(p.x, p.z)):
			_remove_post(i, &"demolisher")
			hit += 1
	return hit


## Toglie tutti i lampioni (ricostruzioni, test).
func remove_all(reason: StringName) -> void:
	for i in range(_posts.size() - 1, -1, -1):
		_remove_post(i, reason)


func _ensure_meshes() -> void:
	if _pole_mesh != null:
		return
	_pole_mesh = CylinderMesh.new()
	_pole_mesh.top_radius = 0.06
	_pole_mesh.bottom_radius = 0.09
	_pole_mesh.height = POLE_HEIGHT
	_pole_mesh.radial_segments = 8
	_pole_material = StandardMaterial3D.new()
	_pole_material.albedo_color = Color(0.25, 0.22, 0.2)
	_head_mesh = BoxMesh.new()
	_head_mesh.size = Vector3.ONE * HEAD_SIZE
	_head_material = StandardMaterial3D.new()
	_head_material.albedo_color = LAMP_COLOR
	_head_material.emission_enabled = true
	_head_material.emission = LAMP_COLOR
	_head_material.emission_energy_multiplier = 3.0


## Palo, testa e luce con la base in [param base]; restituisce il nodo e l'id della sorgente.
func _spawn_lamp_node(lamp_name: String, base: Vector3) -> Array:
	_ensure_meshes()
	var lamp := Node3D.new()
	lamp.name = lamp_name
	add_child(lamp)
	lamp.global_position = base
	var pole := MeshInstance3D.new()
	pole.mesh = _pole_mesh
	pole.material_override = _pole_material
	pole.position = Vector3(0.0, POLE_HEIGHT * 0.5, 0.0)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.add_child(pole)
	var head := MeshInstance3D.new()
	head.mesh = _head_mesh
	head.material_override = _head_material
	head.position = Vector3(0.0, POLE_HEIGHT + HEAD_SIZE * 0.5, 0.0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.add_child(head)
	# I lampioni non proiettano mai ombre (specifica, sezione 10).
	var light := OmniLight3D.new()
	light.name = "LampLight"
	light.position = Vector3(0.0, POLE_HEIGHT, 0.0)
	light.light_color = LAMP_COLOR
	light.light_energy = 1.8
	light.omni_range = light_radius * 1.15
	light.shadow_enabled = false
	lamp.add_child(light)
	var source_id := light_field.add_source(lamp, light_radius) if light_field != null else 0
	return [lamp, source_id]


## Rilievo: palo con la base alla quota del suolo; ricorda la quota per la caduta.
func _build_post(point: Vector3) -> Vector3:
	var ground := terrain_field.height_at(point)
	var base := Vector3(point.x, ground, point.z)
	var made := _spawn_lamp_node("Lamp_%d" % (_posts.size() + 1), base)
	_posts.append({ position = base, node = made[0], source = made[1], rest_height = ground })
	return base


func _free_entry(entry: Dictionary) -> void:
	if light_field != null and entry.source > 0:
		light_field.remove_source(entry.source)
	var node: Node3D = entry.node
	remove_child(node)
	node.queue_free()


func _remove_post(index: int, reason: StringName) -> void:
	var entry: Dictionary = _posts[index]
	_posts.remove_at(index)
	_free_entry(entry)
	var at: Vector3 = entry.position
	print("PROTOTYPE01_LAMP_LOST x=%.1f z=%.1f reason=%s count=%d" % [at.x, at.z, reason, count()])
	lamp_lost.emit(at, reason)
	lamps_changed.emit(count())


## Il suolo sotto un palo si e spostato di oltre FALL_SHIFT_M (scavo, rialzo, martello,
## terremoto): il lampione cade.
func _on_region_changed(aabb: AABB) -> void:
	var probe_y := aabb.position.y + 0.1
	for i in range(_posts.size() - 1, -1, -1):
		var p: Vector3 = _posts[i].position
		if not aabb.has_point(Vector3(p.x, probe_y, p.z)):
			continue
		if absf(terrain_field.height_at(p) - float(_posts[i].rest_height)) > FALL_SHIFT_M:
			_remove_post(i, &"terrain")


static func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
