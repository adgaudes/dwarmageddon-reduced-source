class_name DebrisBurst
extends RefCounted
## Schizzo di frammenti a perdere (D-047): nemico abbattuto, cella scavata o
## rialzata, muro smontato dal boss. Solo presentazione: nessuna collisione,
## nessuno stato di gioco. Il nodo si libera da solo a fine emissione.

const LIFETIME := 0.45
const GRAVITY := Vector3(0.0, -14.0, 0.0)

static var _shrink: Curve
## Mesh (con materiale) per (colore, dimensione): gli schizzi di un'orda condividono
## le stesse risorse invece di allocarne di nuove a ogni morte (T-06).
static var _meshes: Dictionary[String, BoxMesh] = {}


## [param color] lineare, come le altre costanti di colore del progetto.
static func spawn(parent: Node, at: Vector3, color: Color, amount := 6, speed := 3.5, size := 0.14) -> CPUParticles3D:
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0.0, 1.0))
		_shrink.add_point(Vector2(0.6, 0.9))
		_shrink.add_point(Vector2(1.0, 0.0))
	var burst := CPUParticles3D.new()
	burst.mesh = _mesh_for(color, size)
	burst.amount = amount
	burst.lifetime = LIFETIME
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.direction = Vector3.UP
	burst.spread = 65.0
	burst.initial_velocity_min = speed * 0.5
	burst.initial_velocity_max = speed
	burst.gravity = GRAVITY
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.3
	burst.scale_amount_curve = _shrink
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Posizione prima di entrare nell'albero: impostata dopo, i frammenti partono dall'origine.
	burst.top_level = true
	burst.position = at
	parent.add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)
	return burst


## Quante coppie (colore, dimensione) distinte sono in cache (per i test).
static func cached_mesh_count() -> int:
	return _meshes.size()


static func _mesh_for(color: Color, size: float) -> BoxMesh:
	var key := "%s|%.4f" % [color.to_html(true), size]
	var mesh: BoxMesh = _meshes.get(key)
	if mesh == null:
		var material := StandardMaterial3D.new()
		material.albedo_color = color.linear_to_srgb()
		material.roughness = 0.9
		mesh = BoxMesh.new()
		mesh.size = Vector3.ONE * size
		mesh.material = material
		_meshes[key] = mesh
	return mesh
