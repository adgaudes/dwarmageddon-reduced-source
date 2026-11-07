class_name ScrapLauncher
extends Weapon
## Lanciarottami (spec D-092, par. 4.2), automatica del Guastatore: ogni `fire_interval`, se c'e
## un nemico entro `weapon_range`, lancia un rottame a parabola (`flight_seconds`, apice 3 m) sul
## gruppo piu fitto (in mira manuale davanti a chi spara, alla distanza del nemico piu vicino).
## Nessun controllo di linea di tiro: scavalca gli argini. All'arrivo `damage` entro
## `blast_radius`. Bivi: Grappolo (tre frammenti appena fuori dallo scoppio) o Rottame pesante
## (4 danni e spinta); Bulloni sparsi (quattro triboli che rallentano e feriscono) o Cratere
## (lo scoppio scava 0,4 m). Fuso con la Carica da scavo diventa il Mortaio a crateri: ogni
## rottame apre un cratere e ogni `charge_every`-esimo colpo e una carica da scavo completa.
## Rottami, triboli e scoppi sono istanze di MultiMesh: nessun nodo per colpo.

const SCRAP_COLOR := Color(0.55, 0.32, 0.18)
const CALTROP_COLOR := Color(0.3, 0.3, 0.32)
const BLAST_COLOR := Color(1.0, 0.45, 0.15)
## Altezza dell'apice della parabola sopra la retta fra partenza e arrivo.
const APEX := 3.0
## Il rottame parte all'altezza delle mani.
const HAND_HEIGHT := 0.8
const MAX_SCRAPS := 12
## Scia del rottame: copie sempre piu piccole lungo la parabola, TRAIL_STEP di volo indietro.
const TRAIL_GHOSTS := 3
const TRAIL_STEP := 0.06
const TRAIL_COLOR := Color(0.62, 0.53, 0.40, 0.55)
## Grappolo: frammenti tangenti allo scoppio, lungo il volo e a 120 gradi.
const FRAGMENT_COUNT := 3
const FRAGMENT_RADIUS := 1.0
const FRAGMENT_DAMAGE := 1
## Bulloni sparsi: quattro triboli a 1 m dal punto, lungo il volo e di lato.
const CALTROP_COUNT := 4
const CALTROP_DISTANCE := 1.0
const CALTROP_SECONDS := 4.0
const CALTROP_REACH := 0.5
## Rallentamento del 40%, rinnovato a ogni passo per un attimo: chi esce riparte subito.
const CALTROP_SLOW := 0.6
const CALTROP_SLOW_SECONDS := 0.15
const CALTROP_DAMAGE := 1
const MAX_CALTROP_SETS := 8
## Cratere: 0,4 m sotto la base, raggio 1,5 m.
const CRATER_DEPTH := 0.4
const CRATER_RADIUS := 1.5
const BLAST_SECONDS := 0.25
const MAX_BLASTS := 12
const BLOCKED_RETRY := 0.1

## Coda delle scritture sul terreno (Cratere, Mortaio), dal WeaponLoadout.
var write_queue: TerrainWriteQueue
var fire_interval := 1.6
var weapon_range := 12.0
var blast_radius := 1.8
var damage := 2
var flight_seconds := 0.7
var cluster := false
var shove := 0.0
var caltrops := false
var crater := false
## Rottami arrivati (il Mortaio fa una carica ogni `charge_every`).
var shots := 0
var _cooldown := 0.3
## Rottami in volo: {from, to, t, total}.
var _scraps: Array[Dictionary] = []
## Triboli di uno scoppio: {center, points: Array[Vector3], left, hit: Array}.
var _caltrop_sets: Array[Dictionary] = []
## Scoppi da mostrare: {position, radius, left}.
var _blasts: Array[Dictionary] = []
var _scrap_view: MultiMeshInstance3D
var _trail_view: MultiMeshInstance3D
var _caltrop_view: MultiMeshInstance3D
var _blast_view: MultiMeshInstance3D


func _ready() -> void:
	var scrap := BoxMesh.new()
	scrap.size = Vector3(0.32, 0.22, 0.42)
	scrap.material = _material(SCRAP_COLOR, false)
	_scrap_view = _make_view(scrap, MAX_SCRAPS, false)
	var ghost := BoxMesh.new()
	ghost.size = Vector3(0.22, 0.16, 0.22)
	var ghost_material := StandardMaterial3D.new()
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.albedo_color = Color(TRAIL_COLOR.linear_to_srgb(), TRAIL_COLOR.a)
	ghost.material = ghost_material
	_trail_view = _make_view(ghost, MAX_SCRAPS * TRAIL_GHOSTS, false)
	var caltrop := CylinderMesh.new()
	caltrop.top_radius = 0.0
	caltrop.bottom_radius = 0.14
	caltrop.height = 0.2
	caltrop.radial_segments = 4
	caltrop.rings = 1
	caltrop.material = _material(CALTROP_COLOR, false)
	_caltrop_view = _make_view(caltrop, MAX_CALTROP_SETS * CALTROP_COUNT, false)
	var blast := SphereMesh.new()
	blast.radius = 1.0
	blast.height = 0.6
	blast.radial_segments = 20
	blast.rings = 6
	blast.material = _material(BLAST_COLOR, true)
	_blast_view = _make_view(blast, MAX_BLASTS, true)
	super._ready()


func _apply_stats() -> void:
	fire_interval = stat(&"fire_interval")
	weapon_range = stat(&"weapon_range")
	blast_radius = stat(&"blast_radius")
	damage = int(stat(&"damage"))
	flight_seconds = maxf(stat(&"flight_seconds"), 0.05)
	cluster = stat(&"cluster") > 0.0
	shove = stat(&"shove")
	caltrops = stat(&"caltrops") > 0.0
	crater = stat(&"crater") > 0.0


func scrap_count() -> int:
	return _scraps.size()


func caltrop_count() -> int:
	var count := 0
	for group: Dictionary in _caltrop_sets:
		count += (group.points as Array).size()
	return count


func _physics_process(delta: float) -> void:
	_move_scraps(delta)
	_tick_caltrops(delta)
	_tick_blasts(delta)
	if shooter == null or director == null:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var target: Variant = _aim_point()
	if target == null:
		_cooldown = BLOCKED_RETRY
		return
	_cooldown = fire_interval
	launch(target)


## Punto d'arrivo: il gruppo piu fitto in portata (in manuale davanti a chi spara, alla
## distanza del nemico piu vicino); null se nessun nemico e in portata.
func _aim_point() -> Variant:
	var origin := shooter.global_position
	var nearest: Enemy = null
	var nearest_d := INF
	for enemy in director.enemies_near(origin, weapon_range):
		var d := origin.distance_squared_to(enemy.global_position)
		if not enemy.is_dead and d < nearest_d:
			nearest_d = d
			nearest = enemy
	if nearest == null:
		return null
	if manual_aim:
		var forward: Vector3 = shooter.facing_direction() if shooter.has_method(&"facing_direction") else -shooter.global_basis.z
		forward = Vector3(forward.x, 0.0, forward.z).normalized()
		var reach := Vector2(nearest.global_position.x - origin.x, nearest.global_position.z - origin.z).length()
		return origin + forward * reach
	var cluster_at: Variant = ActiveWeapon.cluster_center(director, origin, weapon_range)
	var target: Vector3 = cluster_at if cluster_at != null else nearest.global_position
	if shooter.has_method(&"face_shot"):
		shooter.face_shot(target - origin)
	return target


## Lancia un rottame verso [param target] (sul suolo di quel punto).
func launch(target: Vector3) -> void:
	_sound(&"fire")
	if _scraps.size() >= MAX_SCRAPS:
		return
	var from := shooter.global_position + Vector3(0.0, HAND_HEIGHT, 0.0) if shooter != null else target
	_scraps.append({from = from, to = Vector3(target.x, _ground(target), target.z), t = 0.0, total = flight_seconds})


func _move_scraps(delta: float) -> void:
	for k in range(_scraps.size() - 1, -1, -1):
		var scrap: Dictionary = _scraps[k]
		scrap.t += delta
		if scrap.t >= scrap.total:
			_scraps.remove_at(k)
			var to: Vector3 = scrap.to
			var from: Vector3 = scrap.from
			var flight := Vector3(to.x - from.x, 0.0, to.z - from.z)
			_burst(to, flight.normalized() if flight.length_squared() > 1e-4 else Vector3.FORWARD)
	var multimesh := _scrap_view.multimesh
	var trail := _trail_view.multimesh
	multimesh.visible_instance_count = _scraps.size()
	var ghosts := 0
	for i in _scraps.size():
		var scrap: Dictionary = _scraps[i]
		var u: float = scrap.t / scrap.total
		multimesh.set_instance_transform(i, Transform3D(Basis(Vector3(1.0, 0.4, 0.2).normalized(), scrap.t * 9.0), _arc_point(scrap, u)))
		for g in range(1, TRAIL_GHOSTS + 1):
			var back := u - TRAIL_STEP * g
			if back <= 0.0:
				break
			var size := 1.0 - float(g) / (TRAIL_GHOSTS + 1)
			trail.set_instance_transform(ghosts, Transform3D(Basis.from_scale(Vector3.ONE * size), _arc_point(scrap, back)))
			ghosts += 1
	trail.visible_instance_count = ghosts


static func _arc_point(scrap: Dictionary, u: float) -> Vector3:
	return (scrap.from as Vector3).lerp(scrap.to, u) + Vector3.UP * 4.0 * APEX * u * (1.0 - u)


## Scoppio del rottame in [param at]; [param direction] e la direzione del volo (piana).
func _burst(at: Vector3, direction: Vector3) -> void:
	_sound(&"hit")
	shots += 1
	var charge_shot := fusion_id != &"" and shots % maxi(int(fusion_stat(&"charge_every")), 1) == 0
	# Crateri dal meno profondo al piu profondo: nella coda vince l'ultimo, il piu basso.
	if crater:
		DigCharge.dig_crater(write_queue, terrain_field, at, CRATER_RADIUS, CRATER_DEPTH)
	if charge_shot:
		# Mortaio: una carica da scavo completa, coi valori base della Carica.
		var radius := _charge_stat(&"blast_radius")
		DigCharge.explode(director, write_queue, terrain_field, at, int(_charge_stat(&"damage")), radius,
			_charge_stat(&"crater_radius"), _charge_stat(&"crater_depth"))
		_show_blast(at, radius)
		_fusion_fx(WeaponFx.shockwave(fx_parent(), at, radius, BLAST_COLOR))
		_fusion_fx(WeaponFx.burst(fx_parent(), at + Vector3(0.0, 0.3, 0.0), WeaponFx.EARTH, 16, 7.0, 0.2))
	else:
		if fusion_id != &"":
			DigCharge.dig_crater(write_queue, terrain_field, at, fusion_stat(&"crater_radius"), fusion_stat(&"crater_depth"))
		DigCharge.explode(director, null, null, at, damage, blast_radius, 0.0, 0.0)
		_show_blast(at, blast_radius)
		WeaponFx.burst(fx_parent(), at + Vector3(0.0, 0.3, 0.0), WeaponFx.RUST, 8, 5.0, 0.12)
		WeaponFx.dust(fx_parent(), at, WeaponFx.DUST, 0.6, 5)
	if shove > 0.0 and director != null:
		# I boss (self_driven) non si spostano: li salta shove_from.
		director.shove_from(at, blast_radius, shove)
	if cluster:
		for i in FRAGMENT_COUNT:
			var p := at + direction.rotated(Vector3.UP, TAU * i / FRAGMENT_COUNT) * (blast_radius + FRAGMENT_RADIUS)
			p.y = _ground(p)
			DigCharge.explode(director, null, null, p, FRAGMENT_DAMAGE, FRAGMENT_RADIUS, 0.0, 0.0)
			_show_blast(p, FRAGMENT_RADIUS)
	if caltrops:
		_drop_caltrops(at, direction)


## Bulloni sparsi: quattro triboli attorno ad [param at], il primo lungo [param direction].
func _drop_caltrops(at: Vector3, direction: Vector3) -> void:
	if _caltrop_sets.size() >= MAX_CALTROP_SETS:
		_caltrop_sets.pop_front()
	var points: Array[Vector3] = []
	for i in CALTROP_COUNT:
		var p := at + direction.rotated(Vector3.UP, TAU * i / CALTROP_COUNT) * CALTROP_DISTANCE
		points.append(Vector3(p.x, _ground(p), p.z))
	_caltrop_sets.append({center = at, points = points, left = CALTROP_SECONDS, hit = []})
	_refresh_caltrops()


func _tick_caltrops(delta: float) -> void:
	if _caltrop_sets.is_empty():
		return
	for k in range(_caltrop_sets.size() - 1, -1, -1):
		var group: Dictionary = _caltrop_sets[k]
		group.left -= delta
		if group.left <= 0.0:
			_caltrop_sets.remove_at(k)
			continue
		if director == null:
			continue
		# Una sola ricerca per gruppo di triboli, poi la distanza da ognuno.
		for enemy in director.enemies_near(group.center, CALTROP_DISTANCE + CALTROP_REACH):
			if enemy.is_dead:
				continue
			for p: Vector3 in group.points:
				if Vector2(enemy.global_position.x - p.x, enemy.global_position.z - p.z).length() > CALTROP_REACH:
					continue
				enemy.slow(CALTROP_SLOW, CALTROP_SLOW_SECONDS)
				# Il danno al primo passaggio di ogni nemico sul gruppo.
				if not (group.hit as Array).has(enemy):
					group.hit.append(enemy)
					enemy.take_damage(CALTROP_DAMAGE)
				break
	_refresh_caltrops()


func _refresh_caltrops() -> void:
	var multimesh := _caltrop_view.multimesh
	var i := 0
	for group: Dictionary in _caltrop_sets:
		for p: Vector3 in group.points:
			multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, p.x + p.z), p + Vector3(0.0, 0.1, 0.0)))
			i += 1
	multimesh.visible_instance_count = i


func _show_blast(at: Vector3, radius: float) -> void:
	if _blasts.size() >= MAX_BLASTS:
		_blasts.pop_front()
	_blasts.append({position = Vector3(at.x, _ground(at), at.z), radius = radius, left = BLAST_SECONDS})


func _tick_blasts(delta: float) -> void:
	var multimesh := _blast_view.multimesh
	if _blasts.is_empty():
		multimesh.visible_instance_count = 0
		return
	for k in range(_blasts.size() - 1, -1, -1):
		_blasts[k].left -= delta
		if _blasts[k].left <= 0.0:
			_blasts.remove_at(k)
	multimesh.visible_instance_count = _blasts.size()
	for i in _blasts.size():
		var blast: Dictionary = _blasts[i]
		var t := 1.0 - clampf(blast.left / BLAST_SECONDS, 0.0, 1.0)
		var r: float = lerpf(0.4, 1.0, t) * blast.radius
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, r, r)), blast.position))
		multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.7 * (1.0 - t)))


static func _charge_stat(key: StringName) -> float:
	return WeaponCatalog.stat(&"dig_charge", key, 1, {})


func _ground(p: Vector3) -> float:
	if terrain_field != null:
		return terrain_field.height_at(p)
	return shooter.global_position.y if shooter != null else p.y


func _material(color: Color, glow: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.linear_to_srgb()
	material.roughness = 0.7
	if glow:
		material.emission_enabled = true
		material.emission = color.linear_to_srgb()
		material.emission_energy_multiplier = 1.5
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
	else:
		material.metallic = 0.6
	return material


func _make_view(mesh: Mesh, count: int, colors: bool) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colors
	multimesh.mesh = mesh
	multimesh.instance_count = count
	multimesh.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.multimesh = multimesh
	view.top_level = true
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	return view
