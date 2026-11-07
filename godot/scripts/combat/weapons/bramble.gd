class_name Bramble
extends ActiveWeapon
## Roveto (spec D-092, par. 4.4), attiva dell'Erbacciaia: un seme nel punto di mira fa crescere
## in `grow_seconds` una siepe di rovi lunga `hedge_length`, di traverso alla direzione di lancio
## (un tratto ogni metro, appena curvata verso chi lancia), che dura `hedge_seconds`. I rovi
## (BrambleField) rallentano, feriscono e si fanno rosicchiare. Bivi: Cerchio di rovi (anello
## chiuso di raggio `ring`), Spine lunghe, Radici (chi entra resta fermo `roots` s), Rovo che
## avanza (per ADVANCE_SECONDS la siepe va verso il gruppo di nemici piu fitto). Telegrafo: una
## linea magenta a terra mentre la siepe cresce.

const TELEGRAPH_COLOR := Color(0.95, 0.15, 0.65)
const SEGMENT_STEP := 1.0
## Curvatura della siepe verso chi lancia: metri di rientro per metro al quadrato dal centro.
const BOW := 0.08
const ADVANCE_SECONDS := 3.0
const ADVANCE_SPEED := 2.0
const ADVANCE_REACH := 6.0
## La siepe che avanza si ferma a questa distanza dal centro del gruppo.
const ADVANCE_STOP := 0.3
const MAX_STRIPS := 32

var _field: BrambleField
## Siepi che avanzano: {id, left}.
var _advancing: Array[Dictionary] = []
var _telegraph: MultiMeshInstance3D
var _telegraph_left := 0.0


func _ready() -> void:
	_field = BrambleField.new()
	_field.name = "Hedges"
	add_child(_field)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.03, 0.14)
	var material := StandardMaterial3D.new()
	material.albedo_color = TELEGRAPH_COLOR.linear_to_srgb()
	material.emission_enabled = true
	material.emission = TELEGRAPH_COLOR.linear_to_srgb()
	material.emission_energy_multiplier = 1.4
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_STRIPS
	multimesh.visible_instance_count = 0
	_telegraph = MultiMeshInstance3D.new()
	_telegraph.multimesh = multimesh
	_telegraph.top_level = true
	_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_telegraph)
	super._ready()


## Rovi di quest'arma.
func field() -> BrambleField:
	return _field


func _fire(at: Vector3) -> void:
	plant(at)


## Pianta la siepe in [param at] (di traverso alla direzione da chi spara); restituisce l'id.
func plant(at: Vector3) -> int:
	_sound(&"hit")
	_sync_field()
	var points := ring_points(at, stat(&"ring")) if stat(&"ring") > 0.0 else _line_points(at)
	var id := _field.add_hedge(points, stat(&"hedge_seconds"), stat(&"slow"), int(stat(&"damage")),
		stat(&"damage_interval"), int(stat(&"hedge_hp")), stat(&"roots"))
	if stat(&"advance") > 0.0:
		_advancing.append({id = id, left = ADVANCE_SECONDS})
	_show_telegraph(points, stat(&"ring") > 0.0)
	# Foglie e terra smossa dove spunta la siepe: tre ciuffi lungo i punti.
	var half := points.size() >> 1
	for i: int in [0, half, points.size() - 1]:
		var p: Vector3 = points[i]
		var ground := terrain_field.height_at(p) if terrain_field != null else p.y
		WeaponFx.burst(fx_parent(), Vector3(p.x, ground + 0.3, p.z), BrambleField.LEAF_COLOR, 6, 3.0, 0.13)
	var mid: Vector3 = points[half]
	WeaponFx.dust(fx_parent(), Vector3(mid.x, terrain_field.height_at(mid) if terrain_field != null else mid.y, mid.z), WeaponFx.EARTH, 1.2, 6)
	return id


## Anello chiuso di raggio [param radius] attorno ad [param at], un tratto ogni SEGMENT_STEP.
static func ring_points(at: Vector3, radius: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var count := maxi(ceili(TAU * radius / SEGMENT_STEP), 6)
	for i in count:
		var a := TAU * i / count
		out.append(at + Vector3(cos(a), 0.0, sin(a)) * radius)
	return out


func _line_points(at: Vector3) -> Array[Vector3]:
	var forward := Vector3.FORWARD
	if shooter != null:
		var origin := shooter.global_position
		forward = Vector3(at.x - origin.x, 0.0, at.z - origin.z)
		if forward.length_squared() < 1e-4:
			forward = shooter.facing_direction() if shooter.has_method(&"facing_direction") else Vector3.FORWARD
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var side := forward.cross(Vector3.UP).normalized()
	var count := maxi(roundi(stat(&"hedge_length") / SEGMENT_STEP), 1)
	var out: Array[Vector3] = []
	for i in count:
		var t := (i - (count - 1) * 0.5) * SEGMENT_STEP
		out.append(at + side * t - forward * (BOW * t * t))
	return out


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_sync_field()
	_tick_telegraph(delta)
	for k in range(_advancing.size() - 1, -1, -1):
		var item: Dictionary = _advancing[k]
		item.left -= delta
		if item.left <= 0.0 or not _field.has_hedge(item.id):
			_advancing.remove_at(k)
			continue
		_advance(item.id, delta)


## Rovo che avanza: la siepe va verso il centro del gruppo piu fitto attorno a lei, se c'e.
func _advance(id: int, delta: float) -> void:
	if director == null:
		return
	var center: Vector3 = _field.hedge_center(id)
	var target: Variant = densest_cluster(center, ADVANCE_REACH)
	if target == null:
		return
	var to := Vector3(target.x - center.x, 0.0, target.z - center.z)
	if to.length() <= ADVANCE_STOP:
		return
	_field.move_hedge(id, to.limit_length(ADVANCE_SPEED * delta))


func _sync_field() -> void:
	_field.director = director
	_field.terrain_field = terrain_field
	_field.grow_seconds = stat(&"grow_seconds")


## Linea magenta a terra lungo la siepe finche cresce.
func _show_telegraph(points: Array[Vector3], closed: bool) -> void:
	var multimesh := _telegraph.multimesh
	var count := mini(points.size() - 1 + (1 if closed else 0), MAX_STRIPS)
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var mid := (a + b) * 0.5
		var ground := terrain_field.height_at(mid) if terrain_field != null else mid.y
		var basis := Basis(Vector3.UP, atan2(-along.z, along.x)) * Basis.from_scale(Vector3(maxf(along.length(), 0.3), 1.0, 1.0))
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(mid.x, ground + 0.04, mid.z)))
	multimesh.visible_instance_count = maxi(count, 0)
	_telegraph_left = maxf(stat(&"grow_seconds"), 0.3)


func _tick_telegraph(delta: float) -> void:
	if _telegraph_left <= 0.0:
		return
	_telegraph_left -= delta
	if _telegraph_left <= 0.0:
		_telegraph.multimesh.visible_instance_count = 0
