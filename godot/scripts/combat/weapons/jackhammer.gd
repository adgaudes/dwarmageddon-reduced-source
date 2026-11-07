class_name Jackhammer
extends Weapon
## Martello pneumatico (spec D-092, par. 4.5), automatica del kit comune: ogni `fire_interval`,
## se c'e qualcuno in portata, un'onda attorno a chi spara fa `damage` e spinge via; chi ha un
## argine entro un metro alle spalle (rispetto alla spinta) prende il doppio. Bivi: Onda larga,
## Stordente, Crepe (tre crateri attorno), Eco nei fossati (colpisce chi sta in basso fino a 8 m).
## Fuso con la Betoniera diventa il Costipatore: ogni onda blocca per un attimo, ogni terza lascia
## un anello di cemento basso.

const WAVE_COLOR := Color(1.0, 0.8, 0.45)
## Argine alle spalle: salita oltre la quale il colpo vale doppio.
const WALL_RISE := 0.6
const WALL_PROBE := 1.0
const CRACK_COUNT := 3
const CRACK_DISTANCE := 2.0
const CRACK_RADIUS := 1.0
const CRACK_DEPTH := 0.3
const ECHO_RANGE := 8.0
const ECHO_DEPTH := -0.4
const WAVE_SHOW_SECONDS := 0.25
const BLOCKED_RETRY := 0.1

## Coda delle scritture sul terreno (Crepe, anelli del Costipatore), dal WeaponLoadout.
var write_queue: TerrainWriteQueue
var fire_interval := 2.0
var damage := 1
var wave_radius := 3.0
var shove_speed := 6.0
var stun := 0.0
var cracks := false
var echo := false
## Onde fatte (il Costipatore lascia un anello ogni `ring_every`).
var waves := 0
var _cooldown := 0.5
var _rng := RandomNumberGenerator.new()
var _ring: MeshInstance3D
var _ring_left := 0.0


func _ready() -> void:
	_rng.seed = 11
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.84
	mesh.outer_radius = 1.0
	mesh.rings = 32
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = WAVE_COLOR.linear_to_srgb()
	material.emission_enabled = true
	material.emission = WAVE_COLOR.linear_to_srgb()
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


func _apply_stats() -> void:
	fire_interval = stat(&"fire_interval")
	damage = int(stat(&"damage"))
	wave_radius = stat(&"wave_radius")
	shove_speed = stat(&"shove_speed")
	stun = stat(&"stun")
	cracks = stat(&"cracks") > 0.0
	echo = stat(&"echo") > 0.0
	if fusion_id != &"":
		stun = maxf(stun, fusion_stat(&"stun"))


func _physics_process(delta: float) -> void:
	_tick_ring(delta)
	if shooter == null or director == null:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var center := shooter.global_position
	if director.enemies_near(center, wave_radius).is_empty() and not (echo and not _echo_targets(center, []).is_empty()):
		_cooldown = BLOCKED_RETRY
		return
	_cooldown = fire_interval
	wave(center)
	_sound(&"fire")


## Un'onda centrata in [param center]; restituisce i nemici colpiti.
func wave(center: Vector3) -> Array[Enemy]:
	waves += 1
	var hit: Array[Enemy] = []
	for enemy in director.enemies_near(center, wave_radius):
		if enemy.is_dead:
			continue
		hit.append(enemy)
		var amount := damage
		var away := Vector3(enemy.global_position.x - center.x, 0.0, enemy.global_position.z - center.z)
		away = away.normalized() if away.length_squared() > 1e-6 else Vector3.FORWARD
		if _wall_behind(enemy.global_position, away):
			amount *= 2
		if stun > 0.0:
			enemy.stun(stun)
		enemy.take_damage(amount)
	# Dopo lo stordimento: la spinta resta (Enemy.stun azzera solo la velocita di prima).
	director.shove_from(center, wave_radius, shove_speed)
	if echo:
		for enemy in _echo_targets(center, hit):
			hit.append(enemy)
			enemy.take_damage(damage)
	if cracks:
		_open_cracks(center)
	if fusion_id != &"" and waves % maxi(int(fusion_stat(&"ring_every")), 1) == 0:
		_cement_ring(center)
	_show_ring(center)
	var ground := Vector3(center.x, terrain_field.height_at(center) if terrain_field != null else center.y, center.z)
	WeaponFx.dust(fx_parent(), ground, WeaponFx.DUST, 0.4, 10, wave_radius * 0.9)
	WeaponFx.burst(fx_parent(), ground + Vector3(0.0, 0.2, 0.0), WeaponFx.EARTH, 6, 3.0, 0.12)
	return hit


func _wall_behind(position: Vector3, away: Vector3) -> bool:
	if terrain_field == null:
		return false
	return terrain_field.height_at(position + away * WALL_PROBE) - terrain_field.height_at(position) > WALL_RISE


func _echo_targets(center: Vector3, already: Array[Enemy]) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if terrain_field == null:
		return out
	for enemy in director.enemies_near(center, ECHO_RANGE):
		if not enemy.is_dead and not already.has(enemy) and terrain_field.delta_at(enemy.global_position) < ECHO_DEPTH:
			out.append(enemy)
	return out


func _open_cracks(center: Vector3) -> void:
	if write_queue == null or terrain_field == null:
		return
	var start := _rng.randf() * TAU
	for i in CRACK_COUNT:
		var angle := start + TAU * i / CRACK_COUNT
		var p := center + Vector3(cos(angle), 0.0, sin(angle)) * CRACK_DISTANCE
		# Crateri a profondita fissa sotto la base: stando fermi non si scava un pozzo.
		var floor_h := terrain_field.base_height_at(p) - CRACK_DEPTH
		if terrain_field.height_at(p) > floor_h + 0.02:
			write_queue.push_level(p, CRACK_RADIUS, floor_h)
			WeaponFx.burst(fx_parent(), Vector3(p.x, terrain_field.height_at(p) + 0.2, p.z), WeaponFx.EARTH, 6, 3.5, 0.12)


## Costipatore: un anello basso di cemento sul bordo dell'onda.
func _cement_ring(center: Vector3) -> void:
	if write_queue == null or terrain_field == null:
		return
	var count := maxi(16, ceili(TAU * wave_radius / 0.5))
	for i in count:
		var angle := TAU * i / count
		var p := center + Vector3(cos(angle), 0.0, sin(angle)) * wave_radius
		write_queue.push_level(p, 0.6, terrain_field.base_height_at(p) + fusion_stat(&"ring_height"))
	var ground := Vector3(center.x, terrain_field.height_at(center), center.z)
	_fusion_fx(WeaponFx.dust(fx_parent(), ground, WeaponFx.CEMENT, 0.5, 14, wave_radius))


func _show_ring(center: Vector3) -> void:
	var ground := terrain_field.height_at(center) if terrain_field != null else center.y
	_ring.global_position = Vector3(center.x, ground + 0.15, center.z)
	_ring_left = WAVE_SHOW_SECONDS
	_ring.show()


func _tick_ring(delta: float) -> void:
	if _ring_left <= 0.0:
		return
	_ring_left -= delta
	var t := 1.0 - clampf(_ring_left / WAVE_SHOW_SECONDS, 0.0, 1.0)
	var r := lerpf(wave_radius * 0.5, wave_radius, t)
	_ring.scale = Vector3(r, 1.0, r)
	_ring.transparency = t
	if _ring_left <= 0.0:
		_ring.hide()
