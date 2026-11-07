class_name CraneMagnet
extends ActiveWeapon
## Calamita da gru (spec D-092, par. 4.3), attiva del Meccanico: nel punto di mira un
## elettromagnete per `pull_seconds` tira verso il centro i nemici entro `pull_radius` (deriva a
## `pull_speed`, rimessa a ogni passo: i boss non si muovono) e verso chi spara l'esperienza entro
## `xp_radius`; alla fine l'attrattore dell'esperienza torna com'era. Bivi: Schiacciasassi (alla
## fine danno a chi e al centro), Gru mobile (il centro segue il capofila della carovana),
## Polarita inversa (alla fine respinge: chi sbatte contro un argine prende danno), Raccolta (i
## rottami a terra nel raggio passano ai Cassoni, fin dove c'e posto). Senza carovana le sue
## parti si saltano.

const FIELD_COLOR := Color(0.2, 0.95, 0.9)
const CRUSH_RADIUS := 1.5
const REPEL_SPEED := 9.0
## Dopo la spinta si guarda chi ha un argine alle spalle (come il Martello pneumatico).
const REPEL_CHECK_SECONDS := 0.3
const REPEL_DAMAGE := 2
const WALL_RISE := 0.6
const WALL_PROBE := 1.0

## Servizi dal WeaponLoadout (dopo `add_child`): ognuno puo mancare.
var caravan: Caravan
var xp_field: XpField
var scrap_field: ScrapField
var _pull_left := 0.0
var _center := Vector3.ZERO
## Attrattore dell'esperienza preso in prestito: campo, nodo e raggio di prima (-1: non c'era).
var _xp_owner: XpField
var _xp_node: Node3D
var _xp_saved := -1.0
## Respinti dalla Polarita inversa in attesa del controllo dell'argine: {enemy, away}.
var _repelled: Array[Dictionary] = []
var _repel_left := 0.0
var _ring: MeshInstance3D


func _ready() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.95
	mesh.outer_radius = 1.0
	mesh.rings = 48
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = FIELD_COLOR.linear_to_srgb()
	material.emission_enabled = true
	material.emission = FIELD_COLOR.linear_to_srgb()
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	_ring = MeshInstance3D.new()
	_ring.mesh = mesh
	_ring.top_level = true
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ring.hide()
	add_child(_ring)
	super._ready()


func pulling() -> bool:
	return _pull_left > 0.0


func pull_center() -> Vector3:
	return _center


func _fire(at: Vector3) -> void:
	if pulling():
		_release(false)
	_center = at
	_pull_left = stat(&"pull_seconds")
	_follow_lead()
	_borrow_xp_attractor()
	_place_ring()
	_ring.show()
	WeaponFx.sparks(fx_parent(), _center + Vector3(0.0, 0.4, 0.0), FIELD_COLOR, 10, 4.0)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_repel(delta)
	if _pull_left <= 0.0:
		return
	_follow_lead()
	if director != null:
		var speed := stat(&"pull_speed")
		for enemy in director.enemies_near(_center, stat(&"pull_radius")):
			if not enemy.is_dead:
				Welder.pull_toward(enemy, _center, speed)
	_place_ring()
	_pull_left -= delta
	if _pull_left <= 0.0:
		_release(true)


## Tolta a meta (fusione con la Saldatrice, fine livello): l'attrattore non resta acceso.
func _exit_tree() -> void:
	if pulling():
		_release(false)


## Fine dell'attrazione; con [param finished] gli effetti finali dei bivi.
func _release(finished: bool) -> void:
	if finished:
		_sound(&"hit")
	_pull_left = 0.0
	_return_xp_attractor()
	_ring.hide()
	if not finished or director == null:
		return
	# Il rilascio: un colpo secco al centro, e con la Polarita inversa l'onda che respinge.
	WeaponFx.burst(fx_parent(), _center + Vector3(0.0, 0.4, 0.0), WeaponFx.RUST, 8, 4.0, 0.13)
	if stat(&"repel") > 0.0:
		WeaponFx.shockwave(fx_parent(), _center, stat(&"pull_radius"), FIELD_COLOR)
	var radius := stat(&"pull_radius")
	var crush := int(stat(&"crush"))
	if crush > 0:
		for enemy in director.enemies_near(_center, CRUSH_RADIUS):
			if not enemy.is_dead:
				enemy.take_damage(crush)
	if stat(&"repel") > 0.0:
		_repelled.clear()
		for enemy in director.enemies_near(_center, radius):
			if enemy.is_dead or enemy.self_driven:
				continue
			var away := Vector3(enemy.global_position.x - _center.x, 0.0, enemy.global_position.z - _center.z)
			away = away.normalized() if away.length_squared() > 1e-6 else Vector3.FORWARD
			_repelled.append({enemy = enemy, away = away})
		director.shove_from(_center, radius, REPEL_SPEED)
		_repel_left = REPEL_CHECK_SECONDS
	if stat(&"salvage") > 0.0:
		_salvage(radius)


## Raccolta: i rottami a terra nel raggio passano ai Cassoni della carovana, fin dove hanno posto.
func _salvage(radius: float) -> void:
	if scrap_field == null or not is_instance_valid(caravan):
		return
	var room := caravan.room()
	if room <= 0:
		return
	var taken := scrap_field.take_near(_center, radius, room)
	if taken > 0:
		caravan.add_scrap(taken)


func _tick_repel(delta: float) -> void:
	if _repelled.is_empty():
		return
	_repel_left -= delta
	if _repel_left > 0.0:
		return
	for entry in _repelled:
		if is_instance_valid(entry.enemy) and not entry.enemy.is_dead and _wall_behind(entry.enemy.global_position, entry.away):
			entry.enemy.take_damage(REPEL_DAMAGE)
	_repelled.clear()


## Stesso test di Jackhammer._wall_behind: un argine entro WALL_PROBE nella direzione della spinta.
func _wall_behind(position: Vector3, away: Vector3) -> bool:
	if terrain_field == null:
		return false
	return terrain_field.height_at(position + away * WALL_PROBE) - terrain_field.height_at(position) > WALL_RISE


## Gru mobile: il centro sta sul capofila della carovana, se c'e; altrimenti resta dove e
## stato messo.
func _follow_lead() -> void:
	if stat(&"mobile") <= 0.0 or not is_instance_valid(caravan) or not caravan.is_inside_tree():
		return
	var lead := caravan.lead()
	if is_instance_valid(lead) and lead.is_inside_tree():
		_center = lead.global_position


func _borrow_xp_attractor() -> void:
	if xp_field == null or shooter == null:
		return
	_xp_owner = xp_field
	_xp_node = shooter
	_xp_saved = -1.0
	for entry in xp_field.attractors:
		if entry.node == shooter:
			_xp_saved = entry.radius
	xp_field.set_attractor(shooter, maxf(stat(&"xp_radius"), _xp_saved))


## Rimette l'attrattore di chi spara com'era: al raggio di prima, o lo toglie se non c'era.
func _return_xp_attractor() -> void:
	if _xp_owner == null:
		return
	if is_instance_valid(_xp_owner):
		if _xp_saved >= 0.0:
			_xp_owner.set_attractor(_xp_node, _xp_saved)
		else:
			for k in range(_xp_owner.attractors.size() - 1, -1, -1):
				if _xp_owner.attractors[k].node == _xp_node:
					_xp_owner.attractors.remove_at(k)
	_xp_owner = null
	_xp_node = null


func _place_ring() -> void:
	var radius := stat(&"pull_radius")
	var ground := terrain_field.height_at(_center) if terrain_field != null else _center.y
	_ring.global_position = Vector3(_center.x, ground + 0.12, _center.z)
	_ring.scale = Vector3(radius, 1.0, radius)
