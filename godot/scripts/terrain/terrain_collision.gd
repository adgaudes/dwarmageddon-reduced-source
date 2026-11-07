class_name TerrainCollision
extends Node
## Collisione del rilievo continuo (D-085): un solo StaticBody3D sul layer 1 con un
## HeightMapShape3D per chunk di CHUNK_CELLS celle; su `region_changed` si rigenerano
## solo i chunk toccati, nello stesso passo fisico. La collisione di Terrain3D non va
## bene per il gioco (copre un raggio attorno alla camera o ricalcola tutto: 5-35 ms).

const CHUNK_CELLS := 32

var body: StaticBody3D
var _field: TerrainField
var _shapes: Dictionary[Vector2i, HeightMapShape3D] = {}
var _chunks_x := 0
var _chunks_z := 0
var _refreshed := 0


func setup(field: TerrainField) -> void:
	_field = field
	body = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var chunk_m := CHUNK_CELLS * TerrainField.SPACING
	var half := _field.half_extents()
	_chunks_x = int(ceil(half.x * 2.0 / chunk_m)) + 1
	_chunks_z = int(ceil(half.y * 2.0 / chunk_m)) + 1
	for cx in _chunks_x:
		for cz in _chunks_z:
			var key := Vector2i(-_chunks_x / 2 + cx, -_chunks_z / 2 + cz)
			var shape := HeightMapShape3D.new()
			shape.map_width = CHUNK_CELLS + 1
			shape.map_depth = CHUNK_CELLS + 1
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = Vector3((key.x + 0.5) * chunk_m, 0.0, (key.y + 0.5) * chunk_m)
			collider.scale = Vector3(TerrainField.SPACING, 1.0, TerrainField.SPACING)
			body.add_child(collider)
			_shapes[key] = shape
			_refresh_chunk(key)
	_refreshed = 0
	_field.region_changed.connect(refresh_aabb)


func chunk_count() -> int:
	return _shapes.size()


func refreshed_count() -> int:
	return _refreshed


func refresh_aabb(aabb: AABB) -> void:
	var chunk_m := CHUNK_CELLS * TerrainField.SPACING
	var lo := Vector2i(int(floor(aabb.position.x / chunk_m)), int(floor(aabb.position.z / chunk_m)))
	var hi := Vector2i(int(floor(aabb.end.x / chunk_m)), int(floor(aabb.end.z / chunk_m)))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var key := Vector2i(cx, cz)
			if _shapes.has(key):
				_refresh_chunk(key)


func _refresh_chunk(key: Vector2i) -> void:
	var shape: HeightMapShape3D = _shapes[key]
	var chunk_m := CHUNK_CELLS * TerrainField.SPACING
	var base := Vector3(key.x * chunk_m, 0.0, key.y * chunk_m)
	var heights := PackedFloat32Array()
	heights.resize((CHUNK_CELLS + 1) * (CHUNK_CELLS + 1))
	var i := 0
	for z in CHUNK_CELLS + 1:
		for x in CHUNK_CELLS + 1:
			heights[i] = _field.height_at(base + Vector3(x * TerrainField.SPACING, 0.0, z * TerrainField.SPACING))
			i += 1
	shape.map_data = heights
	_refreshed += 1
