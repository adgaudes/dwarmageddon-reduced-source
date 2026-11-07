class_name WeaponFx
extends RefCounted
## Effetti leggibili delle armi (piano 5 di D-092): schegge, onda a terra, polvere. Solo
## presentazione, niente stato di gioco; ogni nodo e nel gruppo `weapon_fx` e si libera da
## solo. Un tetto di nodi vivi protegge il Deck quando cinque armi sparano nell'orda: oltre
## il tetto l'effetto si salta (il colpo resta, si perde solo la decorazione). Gli effetti minori
## (`minor`: polvere che rotola, scintille a raffica) si fermano RESERVE posti prima, cosi le
## attive e le fusioni mostrano sempre il loro colpo.

const GROUP := &"weapon_fx"
const MAX_LIVE := 40
const RESERVE := 10
const EARTH := Color(0.36, 0.25, 0.14)
const DUST := Color(0.62, 0.53, 0.40)
const RUST := Color(0.55, 0.25, 0.10)
const SPARK := Color(1.0, 0.82, 0.35)
const LEAF := Color(0.25, 0.55, 0.12)
const CEMENT := Color(0.55, 0.55, 0.53)

## Spento, nessun effetto nasce (confronto A/B del benchmark, `--no-fx`).
static var enabled := true
static var _ring_mesh: TorusMesh
static var _dust_meshes: Dictionary[String, SphereMesh] = {}
static var _spark_meshes: Dictionary[String, BoxMesh] = {}
static var _spark_fade: Curve


static func _room(parent: Node, minor := false) -> bool:
	if not enabled or parent == null or not parent.is_inside_tree():
		return false
	return parent.get_tree().get_node_count_in_group(GROUP) < MAX_LIVE - (RESERVE if minor else 0)


## Schegge che saltano (DebrisBurst) nel gruppo degli effetti delle armi.
static func burst(parent: Node, at: Vector3, color: Color, amount := 8, speed := 4.0, size := 0.1, minor := false) -> Node:
	if not _room(parent, minor):
		return null
	var node := DebrisBurst.spawn(parent, at, color, amount, speed, size)
	node.add_to_group(GROUP)
	return node


## Anello piatto che si allarga da 0,3 m a [param radius] e svanisce in [param seconds].
static func shockwave(parent: Node, at: Vector3, radius: float, color: Color, seconds := 0.45) -> Node:
	if not _room(parent):
		return null
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.82
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 40
		_ring_mesh.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true
	ring.position = at + Vector3(0.0, 0.08, 0.0)
	ring.scale = Vector3(0.3, 1.0, 0.3)
	ring.add_to_group(GROUP)
	parent.add_child(ring)
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, ^"scale", Vector3(radius, 1.0, radius), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, ^"albedo_color:a", 0.0, seconds).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)
	return ring


## Sbuffo di polvere morbida che sale piano (scavi, cemento, ruote, dischi). Con [param ring]
## maggiore di zero la polvere nasce su un anello di quel raggio (argini che salgono, onde).
static func dust(parent: Node, at: Vector3, color: Color, radius := 0.6, amount := 6, ring := 0.0, minor := false) -> Node:
	if not _room(parent, minor):
		return null
	var puff := CPUParticles3D.new()
	puff.mesh = _dust_mesh(color)
	puff.amount = amount
	puff.lifetime = 0.9
	puff.one_shot = true
	puff.explosiveness = 0.9
	if ring > 0.0:
		puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		puff.emission_ring_axis = Vector3.UP
		puff.emission_ring_radius = ring
		puff.emission_ring_inner_radius = maxf(ring - radius, 0.0)
		puff.emission_ring_height = 0.1
	else:
		puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		puff.emission_sphere_radius = radius
	puff.direction = Vector3.UP
	puff.spread = 35.0
	puff.initial_velocity_min = 0.4
	puff.initial_velocity_max = 1.2
	puff.gravity = Vector3(0.0, 0.3, 0.0)
	puff.damping_min = 1.5
	puff.damping_max = 2.5
	puff.scale_amount_min = 0.7
	puff.scale_amount_max = 1.6
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.top_level = true
	puff.position = at + Vector3(0.0, 0.15, 0.0)
	puff.add_to_group(GROUP)
	parent.add_child(puff)
	puff.emitting = true
	puff.finished.connect(puff.queue_free)
	return puff


## Scintille brevi e luminose (archi, chiodi, lame sul metallo): niente luce dinamica, solo
## materiale che brilla.
static func sparks(parent: Node, at: Vector3, color := SPARK, amount := 10, speed := 6.0, minor := false) -> Node:
	if not _room(parent, minor):
		return null
	if _spark_fade == null:
		_spark_fade = Curve.new()
		_spark_fade.add_point(Vector2(0.0, 1.0))
		_spark_fade.add_point(Vector2(1.0, 0.0))
	var node := CPUParticles3D.new()
	node.mesh = _spark_mesh(color)
	node.amount = amount
	node.lifetime = 0.35
	node.one_shot = true
	node.explosiveness = 1.0
	# Schegge allungate lungo la corsa: si leggono come scintille anche da 15 m.
	node.particle_flag_align_y = true
	node.direction = Vector3.UP
	node.spread = 80.0
	node.initial_velocity_min = speed * 0.5
	node.initial_velocity_max = speed
	node.gravity = Vector3(0.0, -9.0, 0.0)
	node.scale_amount_curve = _spark_fade
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	node.position = at
	node.add_to_group(GROUP)
	parent.add_child(node)
	node.emitting = true
	node.finished.connect(node.queue_free)
	return node


static func _spark_mesh(color: Color) -> BoxMesh:
	var key := color.to_html(true)
	var mesh: BoxMesh = _spark_meshes.get(key)
	if mesh == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color.linear_to_srgb()
		mesh = BoxMesh.new()
		mesh.size = Vector3(0.07, 0.32, 0.07)
		mesh.material = mat
		_spark_meshes[key] = mesh
	return mesh


static func _dust_mesh(color: Color) -> SphereMesh:
	var key := color.to_html(true)
	var mesh: SphereMesh = _dust_meshes.get(key)
	if mesh == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.linear_to_srgb(), 0.45)
		mesh = SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.44
		mesh.radial_segments = 8
		mesh.rings = 4
		mesh.material = mat
		_dust_meshes[key] = mesh
	return mesh
