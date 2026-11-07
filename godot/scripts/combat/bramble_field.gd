class_name BrambleField
extends Node3D
## Rovi a terra (spec D-092, par. 4.4): siepi fatte di tratti di raggio SEGMENT_RADIUS. Chi sta
## dentro un tratto rallenta a `1 - slow`, prende `damage` ogni `damage_interval` (una volta per
## siepe, anche se tocca due tratti vicini) e, con le Radici, resta fermo `roots` secondi la prima
## volta che entra. Ogni nemico dentro un tratto gli toglie 1 PV al secondo (i rovi rosicchiati):
## a 0 PV o a fine tempo il tratto sparisce. Il Roveto ne fa siepi intere, la Falciarovi una scia
## (`add_segment`, con `max_segments`). Vista: un MultiMesh di cespugli che crescono in
## `grow_seconds`, nessun nodo per tratto.

const SEGMENT_RADIUS := 0.6
## Il rallentamento e le radici si rinnovano a ogni passo per questo tempo: chi esce riparte subito.
const HOLD_STEP := 0.15
## PV tolti al tratto da ogni nemico dentro, al secondo.
const GNAW_PER_SECOND := 1.0
const FADE_SECONDS := 0.4
const MAX_VIEW := 96
const LEAF_COLOR := Color(0.12, 0.3, 0.1)
const THORN_COLOR := Color(0.9, 0.12, 0.6)

var director: EnemyDirector
var terrain_field: TerrainField
## Tempo in cui un cespuglio nuovo arriva alla dimensione piena (solo vista).
var grow_seconds := 1.0
## Tratti vivi al massimo (0: nessun limite); oltre, sparisce il piu vecchio.
var max_segments := 0
## Siepi: {id, slow, damage, damage_interval, roots, hp, segments: Array[Dictionary],
## cooldowns: {id nemico: secondi}, rooted: {id nemico: true}}. Tratti: {position, hp, left,
## age, yaw, serial}.
var _hedges: Array[Dictionary] = []
var _next_id := 1
var _serial := 0
var _view: MultiMeshInstance3D


func _ready() -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _bush_mesh()
	multimesh.instance_count = MAX_VIEW
	multimesh.visible_instance_count = 0
	_view = MultiMeshInstance3D.new()
	_view.multimesh = multimesh
	_view.top_level = true
	_view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_view)


## Nuova siepe coi tratti in [param points]; restituisce il suo id.
func add_hedge(points: Array[Vector3], seconds: float, slow: float, damage: int, damage_interval: float,
		hp: int, roots: float) -> int:
	var hedge := {id = _next_id, slow = slow, damage = damage, damage_interval = damage_interval,
		roots = roots, hp = float(hp), segments = [], cooldowns = {}, rooted = {}}
	_next_id += 1
	_hedges.append(hedge)
	for p in points:
		_append_segment(hedge, p, seconds)
	_enforce_cap()
	return hedge.id


## Un tratto in piu alla siepe [param id] (la scia della Falciarovi); falso se la siepe non c'e.
func add_segment(id: int, point: Vector3, seconds: float) -> bool:
	var hedge := _find(id)
	if hedge.is_empty():
		return false
	_append_segment(hedge, point, seconds)
	_enforce_cap()
	return true


func has_hedge(id: int) -> bool:
	return not _find(id).is_empty()


## Sposta tutti i tratti della siepe (Rovo che avanza).
func move_hedge(id: int, offset: Vector3) -> void:
	var hedge := _find(id)
	if hedge.is_empty():
		return
	var planar := Vector3(offset.x, 0.0, offset.z)
	for segment: Dictionary in hedge.segments:
		segment.position += planar


## Centro dei tratti della siepe, o null se e sparita.
func hedge_center(id: int) -> Variant:
	var hedge := _find(id)
	if hedge.is_empty() or (hedge.segments as Array).is_empty():
		return null
	return _center(hedge.segments)


func hedge_count() -> int:
	return _hedges.size()


func segment_count() -> int:
	var count := 0
	for hedge in _hedges:
		count += (hedge.segments as Array).size()
	return count


func segment_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for hedge in _hedges:
		for segment: Dictionary in hedge.segments:
			out.append(segment.position)
	return out


func clear() -> void:
	_hedges.clear()
	_refresh_view()


func _physics_process(delta: float) -> void:
	for k in range(_hedges.size() - 1, -1, -1):
		var hedge: Dictionary = _hedges[k]
		_tick_hedge(hedge, delta)
		if (hedge.segments as Array).is_empty():
			_hedges.remove_at(k)
	_refresh_view()


func _tick_hedge(hedge: Dictionary, delta: float) -> void:
	var segments: Array = hedge.segments
	for i in range(segments.size() - 1, -1, -1):
		var segment: Dictionary = segments[i]
		segment.age += delta
		segment.left -= delta
		if segment.left <= 0.0 or segment.hp <= 0.0:
			segments.remove_at(i)
	var cooldowns: Dictionary = hedge.cooldowns
	for key: int in cooldowns.keys():
		cooldowns[key] -= delta
		if cooldowns[key] <= 0.0:
			cooldowns.erase(key)
	if segments.is_empty() or director == null:
		return
	# Una sola ricerca per siepe: il cerchio che contiene tutti i tratti.
	var center := _center(segments)
	var reach := 0.0
	for segment: Dictionary in segments:
		reach = maxf(reach, _planar_distance(segment.position, center))
	for enemy in director.enemies_near(center, reach + SEGMENT_RADIUS + 1.0):
		if enemy.is_dead:
			continue
		var inside := false
		var limit := SEGMENT_RADIUS + enemy.hit_radius_bonus
		for segment: Dictionary in segments:
			if _planar_distance(enemy.global_position, segment.position) <= limit:
				segment.hp -= GNAW_PER_SECOND * delta
				inside = true
		if not inside:
			continue
		enemy.slow(1.0 - hedge.slow, HOLD_STEP)
		var id := enemy.get_instance_id()
		if hedge.roots > 0.0 and not (hedge.rooted as Dictionary).has(id):
			hedge.rooted[id] = true
			enemy.stun(hedge.roots)
		if not cooldowns.has(id):
			cooldowns[id] = hedge.damage_interval
			enemy.take_damage(hedge.damage)


func _append_segment(hedge: Dictionary, point: Vector3, seconds: float) -> void:
	_serial += 1
	# Rotazione fissa ma diversa per tratto: i cespugli non sembrano copiati.
	var yaw := fposmod(float(_serial) * 2.399, TAU)
	hedge.segments.append({position = point, hp = hedge.hp, left = seconds, age = 0.0, yaw = yaw, serial = _serial})


## Oltre `max_segments` sparisce il tratto piu vecchio.
func _enforce_cap() -> void:
	if max_segments <= 0:
		return
	var extra := segment_count() - max_segments
	for n in extra:
		var oldest_hedge: Dictionary = {}
		var oldest_index := -1
		var oldest_serial := 0
		for hedge in _hedges:
			var segments: Array = hedge.segments
			for i in segments.size():
				if oldest_index < 0 or segments[i].serial < oldest_serial:
					oldest_hedge = hedge
					oldest_index = i
					oldest_serial = segments[i].serial
		if oldest_index < 0:
			return
		(oldest_hedge.segments as Array).remove_at(oldest_index)
	for k in range(_hedges.size() - 1, -1, -1):
		if (_hedges[k].segments as Array).is_empty():
			_hedges.remove_at(k)


func _find(id: int) -> Dictionary:
	for hedge in _hedges:
		if hedge.id == id:
			return hedge
	return {}


static func _center(segments: Array) -> Vector3:
	var sum := Vector3.ZERO
	for segment: Dictionary in segments:
		sum += segment.position
	return sum / segments.size()


static func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _refresh_view() -> void:
	if _view == null:
		return
	var multimesh := _view.multimesh
	var shown := 0
	for hedge in _hedges:
		var hp_max: float = maxf(hedge.hp, 1.0)
		for segment: Dictionary in hedge.segments:
			if shown >= MAX_VIEW:
				break
			var grow := clampf(segment.age / maxf(grow_seconds, 0.01), 0.1, 1.0)
			var fade := clampf(segment.left / FADE_SECONDS, 0.05, 1.0)
			# Un tratto rosicchiato si sfoltisce.
			var health := lerpf(0.55, 1.0, clampf(segment.hp / hp_max, 0.0, 1.0))
			var size := grow * fade * health
			var p: Vector3 = segment.position
			var ground := terrain_field.height_at(p) if terrain_field != null else p.y
			var basis := Basis(Vector3.UP, segment.yaw).scaled(Vector3(size, size * (0.6 + 0.4 * grow), size))
			multimesh.set_instance_transform(shown, Transform3D(basis, Vector3(p.x, ground, p.z)))
			shown += 1
	multimesh.visible_instance_count = shown


## Cespuglio low-poly: un cumulo verde scuro a facce piatte con qualche spina magenta.
static func _bush_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 7
	var top := Vector3(0.0, 0.62, 0.0)
	var low: Array[Vector3] = []
	var mid: Array[Vector3] = []
	for i in sides:
		var a := TAU * i / sides
		var b := a + PI / sides
		low.append(Vector3(cos(a) * 0.42, 0.0, sin(a) * 0.42))
		mid.append(Vector3(cos(b) * 0.6, 0.3 + 0.06 * (i % 2), sin(b) * 0.6))
	var heart := Vector3(0.0, 0.3, 0.0)
	for i in sides:
		var j := (i + 1) % sides
		_face(leaves, low[i], low[j], mid[i], heart)
		_face(leaves, low[j], mid[j], mid[i], heart)
		_face(leaves, mid[i], mid[j], top, heart)
	leaves.set_material(_material(LEAF_COLOR, 0.0))
	leaves.commit(mesh)
	var thorns := SurfaceTool.new()
	thorns.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		var out := Vector3(cos(a), 0.55, sin(a)).normalized()
		var root := Vector3(cos(a) * 0.46, 0.36 + 0.1 * (i % 3), sin(a) * 0.46)
		var side := out.cross(Vector3.UP).normalized() * 0.05
		var tip := root + out * 0.26
		var lift := Vector3(0.0, 0.05, 0.0)
		_face(thorns, root - side, root + side, tip, root - out * 0.1)
		_face(thorns, root + side, root + lift, tip, root - out * 0.1)
		_face(thorns, root + lift, root - side, tip, root - out * 0.1)
	thorns.set_material(_material(THORN_COLOR, 0.6))
	thorns.commit(mesh)
	return mesh


## Triangolo a faccia piatta con la normale rivolta lontano da [param inside].
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot((a + b + c) / 3.0 - inside) < 0.0:
		normal = -normal
	for v in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(v)


static func _material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.linear_to_srgb()
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color.linear_to_srgb()
		material.emission_energy_multiplier = glow
	return material
