class_name SeismicStake
extends ActiveWeapon
## Picchetto sismico (spec D-092, par. 4.1), attiva dell'Ingegnere: piantato nel punto di mira,
## dopo `raise_delay` alza un anello di argine (raggio `ring_radius`, alto `ring_height`) che
## chiude dentro chi c'e; i rottamatori lo rosicchiano come ogni argine. Dopo `hold_seconds`
## torna alla base, salvo il bivio Argine permanente. Bivi del 5: Argine chiodato (danno a chi
## lo spinge) o Scossa (danno e spinta quando si alza). Le quote passano dalla TerrainWriteQueue.

const STAKE_COLOR := Color(1.0, 0.45, 0.08)
## Distanza fra i dischi dell'anello, in frazioni dello spessore: sotto 0,6 non restano buchi.
const DISC_SPACING := 0.6
const SPIKE_TICK := 0.6
const SHOCK_SHOVE_SPEED := 9.0
## Anelli tenuti in elenco (i permanenti restano nel terreno anche quando escono di qui).
const MAX_RINGS := 4

## Anelli: {center, radius, raise_left, hold_left, raised, spike_left, marker}.
var _rings: Array[Dictionary] = []


func ring_count() -> int:
	return _rings.size()


func _fire(at: Vector3) -> void:
	if _rings.size() >= MAX_RINGS:
		_drop_ring(0, false)
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.09
	mesh.height = 1.2
	var material := StandardMaterial3D.new()
	material.albedo_color = STAKE_COLOR.linear_to_srgb()
	material.emission_enabled = true
	material.emission = STAKE_COLOR.linear_to_srgb()
	mesh.material = material
	marker.mesh = mesh
	marker.top_level = true
	add_child(marker)
	var ground := terrain_field.height_at(at) if terrain_field != null else at.y
	marker.global_position = Vector3(at.x, ground + 0.4, at.z)
	WeaponFx.burst(fx_parent(), Vector3(at.x, ground + 0.2, at.z), WeaponFx.EARTH, 6, 2.5, 0.12)
	_rings.append({center = Vector3(at.x, ground, at.z), radius = stat(&"ring_radius"), raise_left = stat(&"raise_delay"),
		hold_left = stat(&"hold_seconds"), raised = false, spike_left = 0.0, marker = marker})


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	for k in range(_rings.size() - 1, -1, -1):
		var ring: Dictionary = _rings[k]
		if not ring.raised:
			ring.raise_left -= delta
			if ring.raise_left <= 0.0:
				_raise(ring)
			continue
		if stat(&"spike_damage") > 0.0:
			ring.spike_left -= delta
			if ring.spike_left <= 0.0:
				ring.spike_left = SPIKE_TICK
				for enemy in _enemies_on_ring(ring, stat(&"ring_width") + 0.3):
					enemy.take_damage(int(stat(&"spike_damage")))
		if stat(&"permanent") > 0.0:
			continue
		ring.hold_left -= delta
		if ring.hold_left <= 0.0:
			_drop_ring(k, true)


func _raise(ring: Dictionary) -> void:
	_sound(&"hit")
	ring.raised = true
	# L'onda corre dal picchetto all'anello, che sale tra la polvere.
	WeaponFx.shockwave(fx_parent(), ring.center, ring.radius + 0.4, STAKE_COLOR, 0.35)
	WeaponFx.dust(fx_parent(), ring.center, WeaponFx.DUST, 0.5, 16, ring.radius)
	var height := stat(&"ring_height")
	for p in _ring_points(ring):
		if write_queue != null and terrain_field != null:
			write_queue.push_level(p, stat(&"ring_width") + 0.1, terrain_field.base_height_at(p) + height)
	var shock := int(stat(&"shock_damage"))
	if shock > 0 and director != null:
		# Solo chi sta sull'anello, scagliato fuori; chi e dentro resta chiuso (review I-3).
		for enemy in _enemies_on_ring(ring, stat(&"ring_width")):
			enemy.take_damage(shock)
			if enemy.self_driven:
				continue
			var away := Vector3(enemy.global_position.x - ring.center.x, 0.0, enemy.global_position.z - ring.center.z)
			away = away.normalized() if away.length_squared() > 1e-6 else Vector3.FORWARD
			enemy.velocity = Vector3(away.x * SHOCK_SHOVE_SPEED, enemy.velocity.y, away.z * SHOCK_SHOVE_SPEED)
	print("PROTOTYPE01_STAKE_RAISED at=(%.1f, %.1f) radius=%.1f" % [ring.center.x, ring.center.z, ring.radius])


## Toglie l'anello dall'elenco; con [param lower] lo riporta alla base.
func _drop_ring(index: int, lower: bool) -> void:
	var ring: Dictionary = _rings[index]
	if lower and ring.raised and write_queue != null and terrain_field != null:
		for p in _ring_points(ring):
			write_queue.push_level(p, stat(&"ring_width") + 0.1, terrain_field.base_height_at(p))
	(ring.marker as Node).queue_free()
	_rings.remove_at(index)


func _ring_points(ring: Dictionary) -> Array[Vector3]:
	var radius: float = ring.radius
	var count := maxi(12, ceili(TAU * radius / (stat(&"ring_width") * DISC_SPACING)))
	var points: Array[Vector3] = []
	for i in count:
		var angle := TAU * i / count
		points.append(ring.center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return points


func _enemies_on_ring(ring: Dictionary, band: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if director == null:
		return out
	var center: Vector3 = ring.center
	for enemy in director.enemies_near(center, ring.radius + band):
		var d := Vector2(enemy.global_position.x - center.x, enemy.global_position.z - center.z).length()
		if not enemy.is_dead and absf(d - ring.radius) <= band:
			out.append(enemy)
	return out
