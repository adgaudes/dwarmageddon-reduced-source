class_name SiteBlade
extends Weapon
## Lama da cantiere (spec D-092, par. 4.5), automatica del kit comune: ogni `fire_interval` lancia
## un disco che rotola sul terreno verso il nemico piu vicino (in mira manuale dove guarda chi
## spara). Il disco segue la quota, gira verso la discesa e ci accelera (fino a +50%), entrato in
## un fossato ci resta a girare per `ditch_seconds`; colpisce ogni nemico una volta. Bivi: Due
## lame, Lama dentata, Rimbalzo sugli argini, Solco. Fusa con l'Ariete diventa la Ruspa a dischi:
## dischi grandi il doppio che spianano e un disco enorme ogni `big_every` secondi.

const DISC_COLOR := Color(0.75, 0.78, 0.82)
const MAX_DISCS := 16
const HIT_RADIUS := 0.45
## Sterzata verso la discesa, per metro di pendenza e per secondo.
const DOWNHILL_STEER := 3.0
## Fossato: delta sotto la base oltre il quale il disco ci resta a girare.
const DITCH_DEPTH := -0.5
## Argine: salita davanti al disco oltre la quale si ferma o rimbalza.
const WALL_RISE := 0.45
## Passo delle scritture di Solco e Ruspa lungo il percorso.
const WRITE_EVERY := 0.8
const GROOVE_DEPTH := 0.25
const BLOCKED_RETRY := 0.1
## Ogni disco lascia uno sbuffo di polvere ogni DUST_EVERY metri (il disco enorme ogni meta).
const DUST_EVERY := 2.0

## Coda delle scritture sul terreno (Solco, Ruspa), dal WeaponLoadout.
var write_queue: TerrainWriteQueue
var fire_interval := 2.5
var damage := 2
var weapon_range := 10.0
var speed := 8.0
var travel := 10.0
var disc_radius := 0.4
var discs := 1
var twin_angle := 15.0
var ditch_seconds := 3.0
var bounces := 0
var groove := false
var _cooldown := 0.3
var _big_left := 0.0
## Dischi enormi della Ruspa lanciati finora.
var big_launched := 0
## Dischi: {position, direction, speed, travelled, ditch_left, bounces, hit, radius, big, write_left}.
var _discs: Array[Dictionary] = []
var _view: MultiMeshInstance3D
var _spin := 0.0


func _ready() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.12
	mesh.radial_segments = 20
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = DISC_COLOR.linear_to_srgb()
	material.metallic = 0.8
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = Color(1.0, 0.6, 0.2)
	material.emission_energy_multiplier = 0.4
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_DISCS
	multimesh.visible_instance_count = 0
	_view = MultiMeshInstance3D.new()
	_view.multimesh = multimesh
	_view.top_level = true
	_view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_view)
	super._ready()


func _apply_stats() -> void:
	fire_interval = stat(&"fire_interval")
	damage = int(stat(&"damage"))
	weapon_range = stat(&"weapon_range")
	speed = stat(&"projectile_speed")
	travel = stat(&"travel")
	disc_radius = stat(&"disc_radius")
	discs = maxi(int(stat(&"discs")), 1)
	twin_angle = stat(&"twin_angle")
	ditch_seconds = stat(&"ditch_seconds")
	bounces = int(stat(&"bounces"))
	groove = stat(&"groove") > 0.0
	if fusion_id != &"":
		disc_radius *= fusion_stat(&"radius_mul")
		if _big_left <= 0.0:
			_big_left = fusion_stat(&"big_every")


func disc_count() -> int:
	return _discs.size()


func disc_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for disc in _discs:
		out.append(disc.position)
	return out


func _physics_process(delta: float) -> void:
	_move_discs(delta)
	if shooter == null or director == null:
		return
	if fusion_id != &"":
		_big_left -= delta
		if _big_left <= 0.0:
			_big_left = fusion_stat(&"big_every")
			_launch_big(_aim_direction())
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var direction := _aim_direction()
	if direction == Vector3.ZERO:
		_cooldown = BLOCKED_RETRY
		return
	_cooldown = fire_interval
	_launch(direction)


## Direzione del lancio: verso il nemico piu vicino in portata (o dove si guarda in manuale),
## zero se nessun nemico e in portata.
func _aim_direction() -> Vector3:
	var origin := shooter.global_position
	var near := director.enemies_near(origin, weapon_range)
	if near.is_empty():
		return Vector3.ZERO
	if manual_aim and shooter.has_method(&"facing_direction"):
		return shooter.facing_direction()
	var best: Enemy = null
	var best_d := INF
	for enemy in near:
		var d := origin.distance_squared_to(enemy.global_position)
		if not enemy.is_dead and d < best_d:
			best_d = d
			best = enemy
	if best == null:
		return Vector3.ZERO
	var to := Vector3(best.global_position.x - origin.x, 0.0, best.global_position.z - origin.z)
	if shooter.has_method(&"face_shot"):
		shooter.face_shot(to)
	return to.normalized()


func _launch(direction: Vector3) -> void:
	_sound(&"fire")
	for i in discs:
		if _discs.size() >= MAX_DISCS:
			break
		var angle := deg_to_rad(twin_angle) * (i - (discs - 1) * 0.5) * 2.0 if discs > 1 else 0.0
		_add_disc(direction.rotated(Vector3.UP, angle), disc_radius, travel, false)


func _launch_big(direction: Vector3) -> void:
	_sound(&"fire")
	if direction == Vector3.ZERO or _discs.size() >= MAX_DISCS:
		return
	big_launched += 1
	_add_disc(direction, fusion_stat(&"big_radius"), fusion_stat(&"big_travel"), true)


func _add_disc(direction: Vector3, radius: float, distance: float, big: bool) -> void:
	var origin := shooter.global_position + direction * 0.6
	_discs.append({position = Vector3(origin.x, _ground(origin) + radius, origin.z), direction = direction,
		travelled = 0.0, distance = distance, ditch_left = -1.0, bounces = bounces, hit = [], radius = radius,
		big = big, write_left = 0.0, dust_left = 0.5})


func _move_discs(delta: float) -> void:
	if _discs.is_empty():
		_view.multimesh.visible_instance_count = 0
		return
	_spin += delta * speed * 2.0
	for k in range(_discs.size() - 1, -1, -1):
		var disc: Dictionary = _discs[k]
		if not _step_disc(disc, delta):
			_discs.remove_at(k)
	_refresh_view()


## Un passo del disco; falso quando il disco finisce.
func _step_disc(disc: Dictionary, delta: float) -> bool:
	var p: Vector3 = disc.position
	var direction: Vector3 = disc.direction
	var radius: float = disc.radius
	var here := _ground(p)
	if terrain_field != null and not disc.big:
		# Sterza verso la discesa: il gradiente della quota attorno al disco.
		var e := 0.5
		var gradient := Vector3(_ground(p + Vector3(e, 0, 0)) - _ground(p - Vector3(e, 0, 0)), 0.0,
			_ground(p + Vector3(0, 0, e)) - _ground(p - Vector3(0, 0, e))) / (2.0 * e)
		direction = (direction - gradient * DOWNHILL_STEER * delta).normalized()
	var along := (_ground(p + direction * 0.5) - here) / 0.5
	var current := speed * clampf(1.0 - along * 1.5, 0.7, 1.5)
	var step := current * delta
	var in_ditch: bool = terrain_field != null and terrain_field.delta_at(p) < DITCH_DEPTH and not disc.big
	if terrain_field != null and _ground(p + direction * (radius + 0.2)) - here > WALL_RISE:
		# Dentro un fossato le pareti lo rimandano indietro: gira sul fondo. Fuori, un argine
		# lo ferma (o lo fa rimbalzare col bivio).
		if not in_ditch:
			if disc.bounces <= 0 or disc.big:
				return false
			disc.bounces -= 1
		var normal := terrain_field.normal_at(p + direction * (radius + 0.2))
		var planar := Vector3(normal.x, 0.0, normal.z)
		planar = planar.normalized() if planar.length_squared() > 1e-4 else -direction
		direction = direction.bounce(planar).normalized()
	var next := p + direction * step
	disc.direction = direction
	disc.position = Vector3(next.x, _ground(next) + radius, next.z)
	if terrain_field != null and terrain_field.delta_at(next) < DITCH_DEPTH and not disc.big:
		if disc.ditch_left < 0.0:
			disc.ditch_left = ditch_seconds
		disc.ditch_left -= delta
		if disc.ditch_left <= 0.0:
			return false
	else:
		disc.travelled += step
		if disc.travelled >= disc.distance:
			return false
	_hit_enemies(disc)
	disc.dust_left -= step
	if disc.dust_left <= 0.0:
		_dust(disc)
	disc.write_left -= step
	if disc.write_left <= 0.0:
		disc.write_left = WRITE_EVERY
		_write_ground(disc)
	return true


func _hit_enemies(disc: Dictionary) -> void:
	if director == null:
		return
	var p: Vector3 = disc.position
	for enemy in director.enemies_near(p, disc.radius + HIT_RADIUS + 1.0):
		if enemy.is_dead or disc.hit.has(enemy):
			continue
		var d := Vector2(enemy.global_position.x - p.x, enemy.global_position.z - p.z).length()
		if d <= disc.radius + HIT_RADIUS + enemy.hit_radius_bonus:
			disc.hit.append(enemy)
			enemy.take_damage(damage)
			_sound(&"hit")
			if _fx_ready(&"hit", 0.1):
				WeaponFx.sparks(fx_parent(), enemy.global_position + Vector3(0.0, 0.5, 0.0), WeaponFx.SPARK, 6, 6.0, true)


## Polvere dietro il disco che rotola; nella Ruspa a dischi piu fitta e piu larga.
func _dust(disc: Dictionary) -> void:
	var big: bool = disc.big
	disc.dust_left = DUST_EVERY * (0.5 if big else 1.0)
	var p: Vector3 = disc.position
	# Polvere minore (cede il posto alle attive sotto carico); quella del disco enorme no.
	var node := WeaponFx.dust(fx_parent(), Vector3(p.x, _ground(p), p.z), WeaponFx.DUST, disc.radius, 6 if big else 3, 0.0, not big)
	if big:
		_fusion_fx(node)


## Solco (scava) o Ruspa (spiana verso la base) dove passa il disco.
func _write_ground(disc: Dictionary) -> void:
	if write_queue == null or terrain_field == null:
		return
	var p: Vector3 = disc.position
	var base := terrain_field.base_height_at(p)
	var here := terrain_field.height_at(p)
	if fusion_id != &"":
		# Spiana solo cio che sporge: i fossati del giocatore restano (come l'Ariete).
		if here > base + 0.05:
			write_queue.push_level(p, disc.radius + 0.4, base, 0.6)
	elif groove:
		# Solco a profondita fissa sotto la base: ripassare non scava di piu.
		if here > base - GROOVE_DEPTH + 0.02:
			write_queue.push_level(p, 0.5, base - GROOVE_DEPTH)


func _ground(p: Vector3) -> float:
	if terrain_field != null:
		return terrain_field.height_at(p)
	return shooter.global_position.y if shooter != null else 0.0


func _refresh_view() -> void:
	var multimesh := _view.multimesh
	multimesh.visible_instance_count = _discs.size()
	for i in _discs.size():
		var disc: Dictionary = _discs[i]
		var forward: Vector3 = disc.direction
		# Il cilindro ha l'asse su Y: lo si corica sul fianco lungo la corsa, poi rotola.
		var basis := Basis.looking_at(forward, Vector3.UP) * Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, _spin)
		multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * disc.radius), disc.position))
