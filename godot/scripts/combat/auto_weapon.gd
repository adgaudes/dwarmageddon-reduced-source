class_name AutoWeapon
extends Weapon
## Chiodatrice automatica (D-038, D-092): spara da sola al nemico piu vicino in linea di
## tiro, o dove guarda chi spara in mira manuale (D-089). I chiodi volano all'altezza di chi
## spara e si fermano sul mondo statico: un argine protegge ma blocca anche i propri colpi.
## Con `weapon_id` i valori vengono da WeaponCatalog (livelli e bivi: Raffica, Chiodi da ponte,
## Rimbalzanti, Incandescenti); senza (la Torretta del compagno) restano quelli impostati.
## Chiodi e macchie di fuoco sono istanze di due MultiMesh: nessun nodo per colpo.
## Fusa col Picchetto diventa Fortino (par. 4.1): ogni tanto alza un cono di argine verso i
## nemici e ci mette sopra una torretta, una chiodatrice figlia coi suoi livelli e bivi.

signal fired(count: int)

const NAIL_COLOR := Color(1.0, 0.85, 0.35)
const NAIL_LENGTH := 0.42
const HIT_RADIUS := 0.45
const MAX_NAILS := 64
## Senza linea di tiro si riprova dopo questo tempo, non a ogni passo (R-35).
const BLOCKED_RETRY := 0.08
## Candidati provati col raggio per colpo: i piu vicini bastano.
const MAX_CANDIDATES := 8
## Macchie di fuoco degli Incandescenti: raggio, durata, danno e cadenza del danno.
const FIRE_COLOR := Color(1.0, 0.35, 0.05)
const FIRE_RADIUS := 1.0
const FIRE_SECONDS := 2.0
const FIRE_TICK := 0.5
const FIRE_DAMAGE := 1
const MAX_PATCHES := 16
## Fortino: dischi del cono (raggio, quota in frazioni di `turret_height`), dal piu largo.
const FORT_DISCS: Array[Vector2] = [Vector2(1.0, 0.4), Vector2(0.7, 1.1 / 1.5), Vector2(0.4, 1.0)]
## Per riportarlo alla base i dischi sono un po' piu larghi: la campana del pennello lascerebbe
## un gradino sui fianchi.
const FORT_LOWER_RADII: Array[float] = [1.4, 1.0, 0.7]
## Distanza minima del cono dal giocatore, distanza lasciata fra cono e nemico, e fra due coni.
const FORT_MIN_DISTANCE := 1.5
const FORT_ENEMY_GAP := 2.0
const FORT_SPACING := 2.0
const FORT_MUZZLE := 0.3
const FORT_COLOR := Color(0.55, 0.5, 0.42)

## Altezza di sparo rispetto all'origine di chi spara.
@export var muzzle_height := 0.0
## Distanza della canna dall'origine, lungo la direzione del colpo (O-04).
@export var muzzle_forward := 0.0
@export var fire_interval := 0.5
@export var weapon_range := 9.0
@export var damage := 1
@export var projectile_speed := 24.0
## Nemici attraversati oltre il primo.
@export var pierce := 0
## Chiodi per colpo, a ventaglio.
@export var projectiles := 1
@export var spread_degrees := 12.0
## Rimbalzi sugli argini per chiodo (bivio Rimbalzanti).
var bounces := 0
## Ogni chiodo lascia una macchia di fuoco (bivio Incandescenti).
var fire_patches := false
## Deviazione casuale massima di ogni colpo, in gradi (bivio Raffica).
var spread_jitter := 0.0
## Coda delle scritture del terreno (dal loadout, dopo `add_child`): serve al Fortino.
var write_queue: TerrainWriteQueue
## Scala del danno dei chiodi per nemico (Enemy -> float): la imposta la Torretta per le
## combinazioni (D-093, scelta 7); non valida vale 1. Le armi del giocatore non la impostano.
var damage_scale: Callable

## Direzione planare (unitaria) dell'ultimo colpo: chi ascolta `fired` la usa per il rinculo.
var last_fire_direction := Vector3.ZERO
var _cooldown := 0.3
## Chiodi in volo: {position, direction, travelled, pierce, bounces, hit}.
var _nails: Array[Dictionary] = []
## Macchie di fuoco: {position, left, tick}.
var _patches: Array[Dictionary] = []
var _nail_view: MultiMeshInstance3D
var _patch_view: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
## Fortino: torrette vive {weapon, center, left} e tempo al prossimo cono.
var _turrets: Array[Dictionary] = []
var _fort_left := -1.0


func _ready() -> void:
	_rng.seed = 7
	var nail_mesh := BoxMesh.new()
	nail_mesh.size = Vector3(0.07, 0.07, NAIL_LENGTH)
	nail_mesh.material = _glow_material(NAIL_COLOR, 1.5)
	_nail_view = _make_view(nail_mesh, MAX_NAILS)
	var patch_mesh := CylinderMesh.new()
	patch_mesh.top_radius = FIRE_RADIUS
	patch_mesh.bottom_radius = FIRE_RADIUS
	patch_mesh.height = 0.04
	patch_mesh.radial_segments = 16
	patch_mesh.rings = 1
	patch_mesh.material = _glow_material(FIRE_COLOR, 2.0)
	_patch_view = _make_view(patch_mesh, MAX_PATCHES)
	super._ready()


func _apply_stats() -> void:
	fire_interval = stat(&"fire_interval")
	damage = int(stat(&"damage"))
	weapon_range = stat(&"weapon_range")
	pierce = int(stat(&"pierce"))
	projectiles = int(stat(&"projectiles"))
	spread_degrees = stat(&"spread_degrees")
	projectile_speed = stat(&"projectile_speed")
	bounces = int(stat(&"bounces"))
	fire_patches = stat(&"fire_patch") > 0.0
	spread_jitter = stat(&"spread_jitter")


func _physics_process(delta: float) -> void:
	_move_nails(delta)
	_tick_patches(delta)
	if shooter == null or director == null:
		return
	if fusion_id == &"fort":
		_tick_fort(delta)
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if manual_aim and shooter.has_method(&"facing_direction"):
		if director.enemies_near(muzzle(), weapon_range).is_empty():
			_cooldown = BLOCKED_RETRY
			return
		_cooldown = fire_interval
		_fire_toward(shooter.facing_direction())
		return
	var target := find_target()
	if target == null:
		_cooldown = BLOCKED_RETRY
		return
	_cooldown = fire_interval
	_fire_at(target)


func muzzle() -> Vector3:
	return shooter.global_position + Vector3(0.0, muzzle_height, 0.0)


## Punto da cui parte il chiodo: la canna, davanti a chi spara nella direzione del colpo.
func muzzle_toward(direction: Vector3) -> Vector3:
	return muzzle() + direction * muzzle_forward


## Nemico vivo piu vicino entro la portata con linea di tiro libera, o null.
func find_target() -> Enemy:
	var origin := muzzle()
	var candidates := director.enemies_near(origin, weapon_range)
	candidates.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	var space := get_world_3d().direct_space_state
	var tried := 0
	for enemy in candidates:
		if enemy.is_dead:
			continue
		if tried >= MAX_CANDIDATES:
			break
		tried += 1
		var aim := Vector3(enemy.global_position.x, origin.y, enemy.global_position.z)
		var query := PhysicsRayQueryParameters3D.create(origin, aim, 1)
		if space.intersect_ray(query).is_empty():
			return enemy
	return null


func nail_count() -> int:
	return _nails.size()


func fire_patch_count() -> int:
	return _patches.size()


func _fire_at(target: Enemy) -> void:
	var base := muzzle()
	var forward := Vector3(target.global_position.x - base.x, 0.0, target.global_position.z - base.z).normalized()
	if shooter.has_method(&"face_shot"):
		shooter.face_shot(forward)
	_fire_toward(forward)


func _fire_toward(forward: Vector3) -> void:
	if spread_jitter > 0.0:
		forward = forward.rotated(Vector3.UP, deg_to_rad(_rng.randf_range(-spread_jitter, spread_jitter)))
	var origin := muzzle_toward(forward)
	last_fire_direction = forward
	var count := maxi(projectiles, 1)
	for i in count:
		if _nails.size() >= MAX_NAILS:
			break
		var angle := deg_to_rad(spread_degrees) * (i - (count - 1) * 0.5)
		var direction := forward.rotated(Vector3.UP, angle)
		_nails.append({position = origin, direction = direction, travelled = 0.0, pierce = pierce, bounces = bounces, hit = []})
	_refresh_nail_view()
	fired.emit(count)


## Query del chiodo riusata a ogni tratto (audit E-15: prima una nuova per chiodo e passo).
var _ray := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1)


func _move_nails(delta: float) -> void:
	if _nails.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var step := projectile_speed * delta
	var enemies := director.enemies if director != null else []
	# Scarto rapido (audit E-15): oltre questa distanza dal punto medio del tratto nessun
	# nemico puo essere colpito, qualunque sia il suo bonus di raggio.
	var reach := step * 0.5 + HIT_RADIUS + _max_hit_bonus(enemies)
	var reach_squared := reach * reach
	for k in range(_nails.size() - 1, -1, -1):
		var nail: Dictionary = _nails[k]
		var from: Vector3 = nail.position
		var to: Vector3 = from + nail.direction * step
		var alive := true
		_ray.from = from
		_ray.to = to
		var wall := space.intersect_ray(_ray)
		var mid := (from + to) * 0.5
		var bounce_normal := Vector3.ZERO
		if not wall.is_empty():
			to = wall.position
			var planar := Vector3(wall.normal.x, 0.0, wall.normal.z)
			if nail.bounces > 0 and planar.length_squared() > 0.01:
				bounce_normal = planar.normalized()
			else:
				alive = false
		if director != null:
			# Indietro: un nemico ucciso qui esce da `enemies` durante il ciclo.
			for e in range(enemies.size() - 1, -1, -1):
				if e >= enemies.size():
					continue
				var enemy: Enemy = enemies[e]
				var ex := enemy.global_position.x - mid.x
				var ez := enemy.global_position.z - mid.z
				if ex * ex + ez * ez > reach_squared:
					continue
				if enemy.is_dead or nail.hit.has(enemy):
					continue
				if _segment_distance(from, to, enemy.global_position) <= HIT_RADIUS + enemy.hit_radius_bonus:
					nail.hit.append(enemy)
					enemy.take_damage(_damage_for(enemy))
					if _fx_ready(&"nail", 0.08):
						WeaponFx.sparks(fx_parent(), enemy.global_position + Vector3(0.0, 0.6, 0.0), NAIL_COLOR, 6, 5.0, true)
					# La macchia nasce al primo nemico colpito, anche se il chiodo prosegue.
					if fire_patches and nail.hit.size() == 1:
						_spawn_patch(enemy.global_position)
					if nail.pierce <= 0:
						alive = false
						break
					nail.pierce -= 1
		nail.travelled += step
		if nail.travelled >= weapon_range * 1.3:
			alive = false
		if alive and bounce_normal != Vector3.ZERO:
			nail.bounces -= 1
			nail.direction = (nail.direction as Vector3).bounce(bounce_normal)
			to += bounce_normal * 0.05
		nail.position = to
		if not alive:
			if fire_patches and nail.hit.is_empty():
				_spawn_patch(to)
			_nails.remove_at(k)
	_refresh_nail_view()


## Danno di un chiodo su [param enemy]: `damage`, o `damage` per `damage_scale` arrotondato
## (almeno 1) se la scala c'e.
func _damage_for(enemy: Enemy) -> int:
	if not damage_scale.is_valid():
		return damage
	return maxi(roundi(damage * float(damage_scale.call(enemy))), 1)


# --- Fortino --------------------------------------------------------------------------------

## Torrette vive del Fortino.
func fort_turrets() -> Array[Weapon]:
	var out: Array[Weapon] = []
	for turret in _turrets:
		out.append(turret.weapon)
	return out


func _tick_fort(delta: float) -> void:
	for k in range(_turrets.size() - 1, -1, -1):
		var turret: Dictionary = _turrets[k]
		turret.left -= delta
		if turret.left <= 0.0:
			_drop_turret(k)
	if _fort_left < 0.0:
		_fort_left = fusion_stat(&"every")
	_fort_left -= delta
	if _fort_left > 0.0:
		return
	# Piena o senza nemici: la prossima attende, riprovando poco dopo.
	_fort_left = BLOCKED_RETRY
	if write_queue == null or terrain_field == null or _turrets.size() >= int(fusion_stat(&"max_turrets")):
		return
	var spot: Variant = _fort_spot()
	if spot == null:
		return
	_fort_left = fusion_stat(&"every")
	_raise_turret(spot)


## Centro del cono: verso il nemico vivo piu vicino, entro `reach`, lontano da zone protette e
## dagli altri coni; null se non ci sono nemici in portata o posto libero.
func _fort_spot() -> Variant:
	var origin := shooter.global_position
	var nearest: Enemy = null
	for enemy in director.enemies_near(origin, weapon_range):
		if not enemy.is_dead and (nearest == null or origin.distance_squared_to(enemy.global_position) < origin.distance_squared_to(nearest.global_position)):
			nearest = enemy
	if nearest == null:
		return null
	var toward := Vector3(nearest.global_position.x - origin.x, 0.0, nearest.global_position.z - origin.z)
	var span := toward.length()
	toward = toward / span if span > 1e-3 else Vector3.FORWARD
	var distance := clampf(span - FORT_ENEMY_GAP, FORT_MIN_DISTANCE, fusion_stat(&"reach"))
	var half := terrain_field.half_extents()
	for degrees: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var p := origin + toward.rotated(Vector3.UP, deg_to_rad(degrees)) * distance
		if absf(p.x) > half.x - 1.0 or absf(p.z) > half.y - 1.0 or terrain_field.is_protected(p):
			continue
		var crowded := false
		for turret in _turrets:
			var other: Vector3 = turret.center
			if Vector2(p.x - other.x, p.z - other.z).length() < FORT_SPACING:
				crowded = true
				break
		if not crowded:
			return Vector3(p.x, terrain_field.base_height_at(p), p.z)
	return null


func _raise_turret(center: Vector3) -> void:
	var height := fusion_stat(&"turret_height")
	for disc in FORT_DISCS:
		write_queue.push_level(center, disc.x, center.y + height * disc.y)
	# Il cono sale tra polvere e zolle.
	_fusion_fx(WeaponFx.dust(fx_parent(), center, WeaponFx.DUST, 0.5, 10, FORT_DISCS[0].x))
	_fusion_fx(WeaponFx.burst(fx_parent(), center + Vector3(0.0, 0.4, 0.0), WeaponFx.EARTH, 10, 4.5, 0.14))
	# Dal proprio script, non dal nome di classe: un riferimento di AutoWeapon a se stessa
	# teneva vivi gli script all'uscita (risorse e RID persi nei test).
	var turret: Weapon = (get_script() as Script).new()
	turret.name = "FortTurret"
	turret.weapon_id = &"nailgun"
	turret.level = level
	turret.branches = branches.duplicate()
	turret.director = director
	turret.terrain_field = terrain_field
	# Ferma sul cono, non segue il giocatore.
	turret.top_level = true
	var marker := Marker3D.new()
	marker.name = "Muzzle"
	marker.add_child(_turret_mesh())
	turret.add_child(marker)
	turret.shooter = marker
	turret.set(&"muzzle_height", FORT_MUZZLE)
	add_child(turret)
	turret.global_position = center + Vector3(0.0, height, 0.0)
	turret.set(&"fire_interval", turret.get(&"fire_interval") / maxf(fusion_stat(&"rate"), 0.05))
	_turrets.append({weapon = turret, center = center, left = fusion_stat(&"turret_seconds")})
	print("PROTOTYPE01_FORT_RAISED at=(%.1f, %.1f) turrets=%d" % [center.x, center.z, _turrets.size()])


## Libera la torretta e riporta il cono alla base.
func _drop_turret(index: int) -> void:
	var turret: Dictionary = _turrets[index]
	var center: Vector3 = turret.center
	if write_queue != null:
		for radius in FORT_LOWER_RADII:
			write_queue.push_level(center, radius, center.y)
	(turret.weapon as Node).queue_free()
	_turrets.remove_at(index)


func _turret_mesh() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.14
	mesh.bottom_radius = 0.22
	mesh.height = 0.4
	mesh.radial_segments = 8
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = FORT_COLOR.linear_to_srgb()
	mesh.material = material
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.position = Vector3(0.0, 0.2, 0.0)
	return view


func _spawn_patch(at: Vector3) -> void:
	if _patches.size() >= MAX_PATCHES:
		_patches.pop_front()
	var ground := shooter.global_position.y if shooter != null else at.y
	if terrain_field != null:
		ground = terrain_field.height_at(at)
	_patches.append({position = Vector3(at.x, ground + 0.03, at.z), left = FIRE_SECONDS, tick = 0.0})
	_refresh_patch_view()


func _tick_patches(delta: float) -> void:
	if _patches.is_empty():
		return
	for k in range(_patches.size() - 1, -1, -1):
		var patch: Dictionary = _patches[k]
		patch.left -= delta
		patch.tick -= delta
		if patch.tick <= 0.0 and director != null:
			patch.tick = FIRE_TICK
			for enemy in director.enemies_near(patch.position, FIRE_RADIUS):
				if not enemy.is_dead:
					enemy.take_damage(FIRE_DAMAGE)
		if patch.left <= 0.0:
			_patches.remove_at(k)
	_refresh_patch_view()


func _refresh_nail_view() -> void:
	var multimesh := _nail_view.multimesh
	multimesh.visible_instance_count = _nails.size()
	for i in _nails.size():
		var nail: Dictionary = _nails[i]
		multimesh.set_instance_transform(i, Transform3D(Basis.looking_at(nail.direction, Vector3.UP), nail.position))


func _refresh_patch_view() -> void:
	var multimesh := _patch_view.multimesh
	multimesh.visible_instance_count = _patches.size()
	for i in _patches.size():
		var patch: Dictionary = _patches[i]
		var fade := clampf(patch.left / FIRE_SECONDS, 0.2, 1.0)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(fade, 1.0, fade)), patch.position))


func _make_view(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	multimesh.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.multimesh = multimesh
	view.top_level = true
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Le istanze si riusano fra chiodi diversi: interpolarle le strascicherebbe fra due punti.
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	return view


static func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.linear_to_srgb()
	material.emission_enabled = true
	material.emission = color.linear_to_srgb()
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _max_hit_bonus(enemies: Array) -> float:
	var bonus := 0.0
	for enemy: Enemy in enemies:
		bonus = maxf(bonus, enemy.hit_radius_bonus)
	return bonus


## Distanza planare del punto dal segmento.
static func _segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var p2 := Vector2(p.x, p.z)
	var ab := b2 - a2
	var t := 0.0
	if ab.length_squared() > 1e-8:
		t = clampf((p2 - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (a2 + ab * t).distance_to(p2)
