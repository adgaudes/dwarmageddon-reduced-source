class_name DigCharge
extends ActiveWeapon
## Carica da scavo (spec D-092, par. 4.2), attiva del Guastatore: una carica nel punto di mira
## che dopo `fuse_seconds` esplode, fa `damage` entro `blast_radius` e apre un cratere a
## profondita fissa (`crater_depth` sotto la base, raggio `crater_radius`). Fino allo scoppio un
## disco rosso a terra mostra dove colpira. Bivi: Grappolo (tre cariche minori a ventaglio) o
## Pozzo (cratere da 1,6 m a pareti ripide: chi ci cade non risale); Doppia carica (due usi per
## ricarica) o Mina (resta a terra finche un nemico la calpesta, al massimo due pose). Le
## esplosioni passano solo da `Enemy.take_damage`: non feriscono mai il giocatore.

const CHARGE_COLOR := Color(0.95, 0.12, 0.08)
## Grappolo: le cariche laterali stanno a questa distanza dalla centrale, piegate verso chi lancia.
const CLUSTER_SPACING := 1.5
const CLUSTER_BEND := PI / 6.0
## Mina: scoppia quando un nemico arriva entro questo raggio.
const MINE_TRIGGER := 0.8
## Pose di mine tenute a terra; la successiva toglie la piu vecchia.
const MAX_MINES := 2
## Pozzo: forza della pennellata oltre 1, cosi il fondo e piatto fino a 1,3 m dal centro e la
## parete scende di oltre un metro per metro (sopra `max_grade` dei nemici).
const STEEP_STRENGTH := 3.0
## Margine sotto il quale un cratere non si riscrive (fondo gia raggiunto o piu basso).
const DUG_MARGIN := 0.02

## Cariche a terra: {position, fuse_left, mine, pose, damage, view}.
var _charges: Array[Dictionary] = []
## Usi fatti dall'ultima ricarica (Doppia carica: la ricarica parte al secondo).
var _used := 0
## Contatore delle pose: le mine di una stessa posa (Grappolo) contano come una.
var _poses := 0


## Esplosione di una carica in [param at]: [param damage] a ogni nemico vivo entro
## [param radius] e cratere a profondita fissa. Usata anche dal Mortaio a crateri.
static func explode(director: EnemyDirector, queue: TerrainWriteQueue, field: TerrainField, at: Vector3, damage: int,
		radius: float, crater_radius: float, crater_depth: float, steep := false) -> Array[Enemy]:
	var hit: Array[Enemy] = []
	if director != null:
		for enemy in director.enemies_near(at, radius):
			if not enemy.is_dead:
				hit.append(enemy)
		for enemy in hit:
			enemy.take_damage(damage)
	dig_crater(queue, field, at, crater_radius, crater_depth, steep)
	return hit


## Cratere a profondita fissa (come le Crepe del Martello): verso `base - depth` e solo se il
## suolo nel centro e piu alto; due scoppi nello stesso punto non scavano di piu.
static func dig_crater(queue: TerrainWriteQueue, field: TerrainField, at: Vector3, radius: float, depth: float,
		steep := false) -> void:
	if queue == null or field == null or depth <= 0.0 or radius <= 0.0:
		return
	var floor_h := field.base_height_at(at) - depth
	if field.height_at(at) > floor_h + DUG_MARGIN:
		queue.push_level(at, radius, floor_h, STEEP_STRENGTH if steep else 1.0)


func charge_count() -> int:
	return _charges.size()


func charge_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for charge in _charges:
		out.append(charge.position)
	return out


## Pose di mine a terra.
func mine_count() -> int:
	return _mine_poses().size()


## Usi rimasti prima della ricarica.
func uses_left() -> int:
	return maxi(int(stat(&"uses")), 1) - _used


## Come ActiveWeapon.trigger, ma la ricarica parte solo quando gli usi finiscono.
func trigger() -> bool:
	if not can_trigger():
		return false
	_used += 1
	if _used >= maxi(int(stat(&"uses")), 1):
		_used = 0
		cooldown_left = cooldown_total()
	var at := aim_point()
	_fire(at)
	_sound(&"fire")
	triggered.emit(at)
	changed.emit()
	return true


func _fire(at: Vector3) -> void:
	var mine := stat(&"mine") > 0.0
	_poses += 1
	if mine:
		var poses := _mine_poses()
		while poses.size() >= MAX_MINES:
			_drop_pose(poses.pop_front())
	var points: Array[Vector3] = [at]
	if int(stat(&"charges")) >= 3:
		var origin := shooter.global_position if shooter != null else at
		var forward := Vector3(at.x - origin.x, 0.0, at.z - origin.z)
		forward = forward.normalized() if forward.length_squared() > 1e-4 else Vector3.FORWARD
		var side := forward.cross(Vector3.UP).normalized()
		# Ventaglio: le laterali piegate di 30 gradi verso chi lancia.
		for sign_x: float in [1.0, -1.0]:
			points.append(at + (side * sign_x * cos(CLUSTER_BEND) - forward * sin(CLUSTER_BEND)) * CLUSTER_SPACING)
	for p in points:
		var ground := terrain_field.height_at(p) if terrain_field != null else p.y
		var spot := Vector3(p.x, ground, p.z)
		_charges.append({position = spot, fuse_left = stat(&"fuse_seconds"), mine = mine, pose = _poses,
			damage = int(stat(&"damage")), view = _make_view(spot, stat(&"blast_radius"), mine)})


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	for k in range(_charges.size() - 1, -1, -1):
		var charge: Dictionary = _charges[k]
		if charge.mine:
			if not _mine_stepped_on(charge.position):
				continue
		else:
			charge.fuse_left -= delta
			if charge.fuse_left > 0.0:
				continue
		_charges.remove_at(k)
		_blow(charge)


func _blow(charge: Dictionary) -> void:
	_sound(&"hit")
	(charge.view as Node).queue_free()
	var at: Vector3 = charge.position
	var radius := stat(&"blast_radius")
	WeaponFx.shockwave(fx_parent(), at, radius, CHARGE_COLOR)
	WeaponFx.burst(fx_parent(), at + Vector3(0.0, 0.3, 0.0), WeaponFx.EARTH, 16, 7.0, 0.2)
	WeaponFx.dust(fx_parent(), at, WeaponFx.DUST, 1.0, 8)
	explode(director, write_queue, terrain_field, charge.position, charge.damage, stat(&"blast_radius"),
		stat(&"crater_radius"), stat(&"crater_depth"), stat(&"pit") > 0.0)


func _mine_stepped_on(at: Vector3) -> bool:
	if director == null:
		return false
	for enemy in director.enemies_near(at, MINE_TRIGGER):
		if not enemy.is_dead:
			return true
	return false


## Pose di mine ancora a terra, dalla piu vecchia.
func _mine_poses() -> Array[int]:
	var poses: Array[int] = []
	for charge in _charges:
		if charge.mine and not poses.has(charge.pose):
			poses.append(charge.pose)
	return poses


## Toglie le mine della posa [param pose] senza farle esplodere.
func _drop_pose(pose: int) -> void:
	for k in range(_charges.size() - 1, -1, -1):
		if _charges[k].pose == pose:
			(_charges[k].view as Node).queue_free()
			_charges.remove_at(k)


## Telegrafo: disco rosso sul raggio dello scoppio (piu tenue per le mine, che aspettano).
func _make_view(at: Vector3, radius: float, mine: bool) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	mesh.radial_segments = 24
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(CHARGE_COLOR.linear_to_srgb(), 0.25 if mine else 0.45)
	material.emission_enabled = true
	material.emission = CHARGE_COLOR.linear_to_srgb()
	material.emission_energy_multiplier = 0.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.top_level = true
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	view.global_position = at + Vector3(0.0, 0.05, 0.0)
	view.reset_physics_interpolation()
	return view
