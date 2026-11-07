class_name EnemyDirector
extends Node3D
## Orda lenta (D-038): fa nascere i rottamatori in un anello attorno al
## giocatore, fuori dallo schermo (D-039), con ritmo crescente e li muove tutti
## in un solo passo fisico. Chi resta troppo indietro torna sull'anello. Ogni nemico segue il
## PathField verso il giocatore (aggira le mura, passa dai varchi); se il
## giocatore e irraggiungibile punta dritto e si ammassa contro le mura.
## Le celle Lowered lo rallentano come rallentano il giocatore.

signal enemy_killed(world_position: Vector3, total: int)

const SCAVENGER_MODEL := preload("res://assets/models/scavenger.glb")
## Lineare: vernice dello scafo dei rottamatori (e colore dei loro frammenti).
const BODY_COLOR := Color(0.42, 0.1, 0.05)
## Lineare: scafo dei rottamatori veloci (D-056), blu elettrico per distinguerli a colpo d'occhio.
const RUNNER_COLOR := Color(0.05, 0.22, 0.85)
## Lineare: scafo dei saltatori (D-066), verde acido.
const HOPPER_COLOR := Color(0.18, 0.75, 0.08)
const SEPARATION_RADIUS := 0.8
const SEPARATION_WEIGHT := 1.6
## Sotto questa distanza dal giocatore si punta dritto, senza waypoint.
const DIRECT_CHASE_DISTANCE := 1.8
const ACCELERATION := 18.0
## Distanza planare a cui una commissione (Enemy.errand_point) e raggiunta.
const ERRAND_REACH := 0.9

@export var tuning: RunTuning
@export var player: PlayerCharacter
@export var path_field: PathField
## Rilievo continuo: pendenza di marcia e spine degli argini.
@export var terrain_field: TerrainField
@export var spawning := true
## Scala dell'anello di comparsa e della distanza minima (D-078): segue la distanza della
## camera (braccio / 15 m), cosi con la camera lontana i nemici non appaiono in vista.
var ring_scale := 1.0

var enemies: Array[Enemy] = []
var kills := 0
## Nemici riportati sull'anello di comparsa perche troppo lontani.
var leashed := 0
## Argini rosicchiati dai rottamatori bloccati.
var gnaws := 0
var _terrain_body: StaticBody3D
var elapsed := 0.0
## Danno da contatto con le celle Raised (upgrade Terrapieni spinati); 0 = spento.
## Notte (D-058): al buio, fuori dalle luci di `light_field`, i rottamatori corrono di piu
## e mordono piu forte. Con `light_field` nullo o `night_active` falso nulla cambia.
var light_field: LightField
var night_active := false
## Contatti avvenuti al buio (test e simulazione).
var dark_contacts := 0
## La carovana (Caravan.configure la collega): i rottamatori colpiscono le sue macchine a
## contatto (`_apply_machine_contacts`).
var caravan: Caravan
var spike_damage := 0
var spike_interval := 0.8
## Prato logico (piano 3 delle armi): sul prato i nemici vanno a 1 - `meadow_slow` (Erba alta).
var meadow: MeadowMap
var meadow_slow := 0.0
## Moltiplica l'attesa fra due morsi agli argini (Argini rinforzati: piu alta, morsi piu radi).
var gnaw_scale := 1.0
var rng := RandomNumberGenerator.new()
var _spawn_timer := 1.0
var _body_mesh: Mesh
var _base_material: Material
var _runner_material: Material
var _hopper_material: Material
## Rottamatori veloci e saltatori nati finora.
var runners_spawned := 0
var hoppers_spawned := 0
var _flash_material := StandardMaterial3D.new()
# Riusati a ogni passo (R-10): secchi di separazione e copia dell'elenco dei nemici.
var _buckets: Dictionary[Vector2i, Array] = {}
## Chiavi dei secchi riempiti in questo passo.
var _bucket_keys: Array[Vector2i] = []
var _step_list: Array[Enemy] = []


func _ready() -> void:
	Enemy.reset_gait_serial()
	if tuning == null:
		tuning = RunTuning.new()
	# Una mesh e un materiale per tutta l'orda: un nemico costa una draw call.
	_body_mesh = ActorModel.mesh_of(SCAVENGER_MODEL)
	_base_material = ActorModel.textured_paint(_body_mesh, BODY_COLOR, 2.0)
	_runner_material = ActorModel.textured_paint(_body_mesh, RUNNER_COLOR, 3.0)
	_hopper_material = ActorModel.textured_paint(_body_mesh, HOPPER_COLOR, 3.0)
	_flash_material.albedo_color = Color.WHITE
	_flash_material.emission_enabled = true
	_flash_material.emission = Color.WHITE


func _physics_process(delta: float) -> void:
	if player == null:
		return
	elapsed += delta
	if spawning and (path_field == null or path_field.is_ready()):
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_batch()
			_spawn_timer = current_spawn_interval()
	_move_enemies(delta)


func current_spawn_interval() -> float:
	var t := clampf(elapsed / maxf(tuning.spawn_ramp_seconds, 1.0), 0.0, 1.0)
	return lerpf(tuning.spawn_interval_start, tuning.spawn_interval_min, t)


func current_enemy_health() -> int:
	return tuning.enemy_health + int(elapsed / maxf(tuning.enemy_health_growth_seconds, 1.0))


## Quota di rottamatori veloci fra i nuovi nati, in questo momento del livello.
func current_runner_share() -> float:
	if tuning.runner_share_max <= 0.0 or elapsed < tuning.runner_start_seconds:
		return 0.0
	var t := clampf((elapsed - tuning.runner_start_seconds) / maxf(tuning.runner_ramp_seconds, 1.0), 0.0, 1.0)
	return tuning.runner_share_max * t


## Quota di saltatori fra i nuovi nati, in questo momento del livello (D-066).
func current_hopper_share() -> float:
	if tuning.hopper_share_max <= 0.0 or elapsed < tuning.hopper_start_seconds:
		return 0.0
	var t := clampf((elapsed - tuning.hopper_start_seconds) / maxf(tuning.hopper_ramp_seconds, 1.0), 0.0, 1.0)
	return tuning.hopper_share_max * t


## Fattore di velocita in salita (spec tappa A, 2.5): 1 in piano e in discesa, giu fino a
## `uphill_min_speed` quando la pendenza raggiunge la massima del nemico (i saltatori,
## con 1,2, rallentano meno dei rottamatori sulla stessa salita).
func uphill_speed_scale(enemy: Enemy, grade: float) -> float:
	if grade <= 0.0:
		return 1.0
	return lerpf(1.0, tuning.uphill_min_speed, clampf(grade / enemy.max_grade, 0.0, 1.0))


## Crea un nemico in un punto preciso (test, eventi scriptati). [param runner]:
## rottamatore veloce, con meno vita.
func spawn_at(world: Vector3, runner := false) -> Enemy:
	return spawn_kind(world, &"runner" if runner else &"scavenger")


## Crea un nemico del tipo dato: `scavenger` (base), `runner` (veloce, meno vita),
## `hopper` (saltatore: meno vita, non rallentato dalle celle Lowered).
func spawn_kind(world: Vector3, kind: StringName) -> Enemy:
	var enemy := Enemy.new()
	enemy.name = "Enemy%d" % (kills + enemies.size())
	enemy.kind = kind
	match kind:
		&"runner":
			runners_spawned += 1
			enemy.speed_scale = tuning.runner_speed / maxf(tuning.enemy_speed, 0.01)
			enemy.setup(maxi(ceili(current_enemy_health() * tuning.runner_health_share), 1), _body_mesh, _runner_material, _flash_material)
		&"hopper":
			hoppers_spawned += 1
			enemy.max_grade = 1.2
			enemy.floor_max_angle = atan(1.2)
			enemy.setup(maxi(ceili(current_enemy_health() * tuning.hopper_health_share), 1), _body_mesh, _hopper_material, _flash_material)
		_:
			enemy.setup(current_enemy_health(), _body_mesh, _base_material, _flash_material)
	add_enemy(enemy, Vector3(world.x, Enemy.spawn_height(), world.z))
	return enemy


## Registra un nemico gia costruito (boss): armi e scavo esplosivo lo vedono come gli altri.
## [param world].y e l'altezza del centro sopra il suolo: sul rilievo si somma la quota del
## terreno (un corpo nato dentro la heightfield, che ha una faccia sola, cadrebbe per sempre).
func add_enemy(enemy: Enemy, world: Vector3) -> void:
	add_child(enemy)
	if terrain_field != null:
		world.y += terrain_field.height_at(world)
	enemy.global_position = world
	# Entra nell'albero all'origine e viene spostato nello stesso passo: senza questo
	# l'interpolazione fisica lo disegnerebbe per un frame fra l'origine e l'anello (E-10).
	enemy.reset_physics_interpolation()
	enemy.died.connect(_on_enemy_died)
	enemies.append(enemy)


func flash_material() -> Material:
	return _flash_material


## L'orda si ritira (fine livello): tutti i nemici spariscono senza lasciare esperienza.
func clear_horde() -> void:
	for enemy in enemies:
		enemy.is_dead = true
		enemy.collision_layer = 0
		enemy.collision_mask = 0
		var tween := enemy.create_tween()
		tween.tween_property(enemy, ^"scale", Vector3.ONE * 0.05, 0.25)
		tween.tween_callback(enemy.queue_free)
	enemies.clear()


## Nemici vivi entro [param radius] (piano XZ) da [param origin].
func enemies_near(origin: Vector3, radius: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	for enemy in enemies:
		if _planar(enemy.global_position - origin).length() <= radius:
			result.append(enemy)
	return result


func _spawn_batch() -> void:
	var room := tuning.max_alive - enemies.size()
	if room <= 0:
		return
	var count := mini(rng.randi_range(tuning.batch_min, tuning.batch_max), room)
	var origin: Variant = _find_spawn_point()
	if origin == null:
		return
	for i in count:
		var offset := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		var point: Vector3 = origin + offset
		if path_field != null and not path_field.is_walkable(point):
			point = origin
		var hopper_share := current_hopper_share()
		if hopper_share > 0.0 and rng.randf() < hopper_share:
			spawn_kind(point, &"hopper")
			continue
		var share := current_runner_share()
		spawn_at(point, share > 0.0 and rng.randf() < share)


## Punto libero sull'anello di comparsa attorno al giocatore, riportato dentro
## l'area giocabile; null se dopo alcuni tentativi non ne trova uno.
func _find_spawn_point() -> Variant:
	var e := (path_field.half_extent if path_field != null else 24.0) - 1.5
	var ez := (path_field.half_z() if path_field != null else 24.0) - 1.5
	var center := player.global_position
	for attempt in 12:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(tuning.spawn_ring_min, tuning.spawn_ring_max) * ring_scale
		var point := Vector3(
			clampf(center.x + cos(angle) * radius, -e, e), 0.0,
			clampf(center.z + sin(angle) * radius, -ez, ez))
		if _planar(point - center).length() < tuning.spawn_min_player_distance * ring_scale:
			continue
		if path_field != null and not path_field.is_walkable(point):
			continue
		return point
	return null


func _move_enemies(delta: float) -> void:
	if night_active and light_field != null:
		light_field.refresh()
	# Si svuotano solo i secchi usati nel passo prima (audit E-14: prima tutte le chiavi mai
	# visitate, fino a 4096); il dizionario troppo grande si azzera prima di riempirlo, cosi
	# nessun passo resta senza separazione.
	for key in _bucket_keys:
		_buckets[key].clear()
	_bucket_keys.clear()
	if _buckets.size() > 4096:
		_buckets.clear()
	for enemy in enemies:
		var key := Vector2i(floori(enemy.global_position.x), floori(enemy.global_position.z))
		var bucket: Array = _buckets.get(key, [])
		if bucket.is_empty():
			_buckets[key] = bucket
			_bucket_keys.append(key)
		bucket.append(enemy)

	# Copia riusata: un nemico che muore durante il passo esce subito dall'elenco.
	_step_list.clear()
	_step_list.append_array(enemies)
	for enemy: Enemy in _step_list:
		if enemy.is_dead:
			continue
		enemy.tick_visuals(delta)
		if enemy.self_driven:
			enemy.drive(delta)
			continue
		var pos := enemy.global_position
		var to_player := _planar(player.global_position - pos)
		var direction := Vector3.ZERO
		if enemy.has_errand:
			# Commissione del boss (D-045): dritto al punto, senza guinzaglio.
			var to_errand := _planar(enemy.errand_point - pos)
			if to_errand.length() <= ERRAND_REACH:
				enemy.errand_reached.emit(enemy)
			else:
				direction = to_errand.normalized()
		else:
			# Fuori guinzaglio, o fuori dalla finestra del campo (dove andrebbe dritto e
			# resterebbe nelle rovine, E-01): torna sull'anello.
			var lost := to_player.length() > tuning.enemy_leash_distance
			if not lost and path_field != null and path_field.is_ready() and to_player.length() > tuning.spawn_ring_max * ring_scale + 1.0 					and not path_field.is_inside(path_field.cell_of(pos)):
				lost = true
			if lost and _leash(enemy):
				continue
			if to_player.length() > DIRECT_CHASE_DISTANCE and path_field != null:
				var waypoint: Variant = path_field.next_waypoint(pos)
				if waypoint != null:
					direction = _planar(waypoint - pos).normalized()
			if direction.is_zero_approx():
				direction = to_player.normalized()
		direction += _separation(enemy) * SEPARATION_WEIGHT
		var speed := tuning.enemy_speed * enemy.speed_scale
		if enemy.stun_left > 0.0:
			speed = 0.0
		if enemy.slow_left > 0.0:
			speed *= enemy.slow_factor
		if meadow != null and meadow_slow > 0.0 and meadow.is_meadow(pos):
			speed *= 1.0 - meadow_slow
		# Una sola domanda alla luce per nemico e per passo: vale per velocita e contatto.
		var in_dark := night_active and light_field != null and not light_field.is_lit(pos)
		# I nemici in commissione (portatori del boss) restano come sono (specifica, sezione 5).
		if in_dark and not enemy.has_errand:
			speed *= tuning.night_dark_speed_scale
		if terrain_field != null:
			# In salita si rallenta in proporzione alla pendenza davanti, fino a uphill_min_speed.
			var ahead := pos + direction.normalized() * 0.6 if not direction.is_zero_approx() else pos
			speed *= uphill_speed_scale(enemy, terrain_field.grade_between(pos, ahead))
		# Lo stordito resta fermo anche sotto una calamita.
		var desired := direction.limit_length(1.0) * speed + (enemy.drift if enemy.stun_left <= 0.0 else Vector3.ZERO)
		enemy.drift = Vector3.ZERO
		var planar := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z).move_toward(desired, ACCELERATION * delta)
		enemy.velocity = Vector3(planar.x, 0.0 if enemy.is_on_floor() else enemy.velocity.y - 9.8 * delta, planar.z)
		enemy.move_and_slide()
		if terrain_field != null:
			_tick_gnaw(enemy, direction, _planar(enemy.global_position - pos).length(), delta)
		if planar.length() > 0.2:
			enemy.rotation.y = atan2(-planar.x, -planar.z)
		_apply_contacts(enemy, in_dark)
	_apply_machine_contacts()


## Di notte e fuori da ogni luce logica?
func is_in_dark(world: Vector3) -> bool:
	return night_active and light_field != null and not light_field.is_lit(world)


## Visiera dell'orda piu accesa di notte: materiali condivisi, nessun costo per nemico.
## Col modello rifinito (D-072) la luce sta nella superficie `lamp`, una per tutta l'orda.
func set_night(factor: float) -> void:
	if _base_material is ShaderMaterial:
		(_base_material as ShaderMaterial).set_shader_parameter(&"emission_energy", lerpf(2.0, 6.0, factor))
		(_runner_material as ShaderMaterial).set_shader_parameter(&"emission_energy", lerpf(3.0, 7.0, factor))
		(_hopper_material as ShaderMaterial).set_shader_parameter(&"emission_energy", lerpf(3.0, 7.0, factor))
	else:
		ActorModel.set_lamp_energy(_body_mesh, lerpf(3.0, 12.0, factor))


## Riporta un nemico disperso sull'anello di comparsa. False se non c'e posto.
func _leash(enemy: Enemy) -> bool:
	var point: Variant = _find_spawn_point()
	if point == null:
		return false
	var ground := terrain_field.height_at(point) if terrain_field != null else 0.0
	enemy.global_position = Vector3(point.x, ground + Enemy.spawn_height(), point.z)
	# Teletrasporto: senza questo l'interpolazione fisica disegna una striscia di 40 m.
	enemy.reset_physics_interpolation()
	enemy.velocity = Vector3.ZERO
	leashed += 1
	return true


func _apply_contacts(enemy: Enemy, in_dark := false) -> void:
	if enemy.is_dead:
		return
	if _planar(player.global_position - enemy.global_position).length() <= tuning.contact_radius:
		var damage := tuning.contact_damage
		if in_dark:
			damage += tuning.night_dark_contact_bonus
			dark_contacts += 1
		player.take_damage(damage)
		enemy.notify_contact()
	if spike_damage > 0 and enemy.spike_cooldown <= 0.0 and terrain_field != null:
		for i in enemy.get_slide_collision_count():
			var collider := enemy.get_slide_collision(i).get_collider() as Node
			if collider == null:
				continue
			# Sul rilievo la spina vale solo sugli argini (terreno rialzato), non sul piano.
			var is_wall := collider == _terrain_collision_body() and terrain_field.delta_at(enemy.global_position) > 0.3
			if is_wall:
				enemy.spike_cooldown = spike_interval
				enemy.take_damage(spike_damage)
				break


## Rottamatori contro le macchine (D-093, scelta 7; piano B, scelte 5 e 6). Per ogni macchina,
## fra i secchi gia riempiti in questo passo entro il suo raggio di contatto in scala
## (`contact_reach`, celle in `range(-c, c + 1)` con `c = ceili(raggio)`): prima il travolgere,
## se la macchina puo (`can_trample`, anche immune o in ritirata), che toglie `trample_damage()` a
## ogni rottamatore vivo in raggio e poi apre l'attesa della macchina (`trample_done`); poi, se
## la macchina accetta un colpo, il primo rottamatore vivo in raggio la colpisce di
## `contact_damage` (niente bonus del buio). I boss (`self_driven`) non si travolgono e colpiscono
## da soli in `drive`. Nessuna scansione di tutti i nemici e nessuna allocazione.
func _apply_machine_contacts() -> void:
	if caravan == null:
		return
	var damage := caravan.tuning.contact_damage
	for machine in caravan.machines:
		var trample := machine.can_trample()
		var contact := machine.accepts_contact()
		if not trample and not contact:
			continue
		var radius := machine.contact_reach()
		var pos := machine.global_position
		var base := Vector2i(floori(pos.x), floori(pos.z))
		var c := ceili(radius)
		var trample_damage := machine.trample_damage()
		var trampled_any := false
		var done := false
		for dx in range(-c, c + 1):
			for dz in range(-c, c + 1):
				var bucket: Variant = _buckets.get(base + Vector2i(dx, dz))
				if bucket == null:
					continue
				for enemy: Enemy in bucket:
					if enemy.is_dead or enemy.self_driven:
						continue
					if _planar(enemy.global_position - pos).length() > radius:
						continue
					if trample:
						enemy.take_damage(trample_damage)
						machine.trampled += 1
						trampled_any = true
						# Travolto a morte: non colpisce piu.
						if enemy.is_dead:
							continue
					if contact:
						contact = false
						# L'affondo solo per un colpo vero: non contro una macchina protetta.
						if machine.take_hit(damage):
							enemy.notify_contact()
					if not trample:
						done = true
						break
				if done:
					break
			if done:
				break
		if trampled_any:
			machine.trample_done()


func _terrain_collision_body() -> StaticBody3D:
	if _terrain_body == null and terrain_field != null:
		_terrain_body = (terrain_field.get_node(^"Collision") as TerrainCollision).body
	return _terrain_body


## Fermo contro il terreno da piu di gnaw_delay_s: rosicchia l'argine davanti a se.
## Solo scavo, mai rialzo: alzare sotto un corpo in piedi lo incastrerebbe nel campo.
func _tick_gnaw(enemy: Enemy, direction: Vector3, moved: float, delta: float) -> void:
	# Stordito (Martello, Betoniera): fermo per forza, non perche bloccato contro un argine.
	if enemy.stun_left > 0.0:
		enemy.stuck_seconds = 0.0
		enemy.is_gnawing = false
		return
	var against_terrain := false
	for i in enemy.get_slide_collision_count():
		if enemy.get_slide_collision(i).get_collider() == _terrain_collision_body():
			against_terrain = true
			break
	if against_terrain and moved < 0.2 * delta and not direction.is_zero_approx():
		enemy.stuck_seconds += delta
	else:
		enemy.stuck_seconds = 0.0
		enemy.is_gnawing = false
	if enemy.stuck_seconds < tuning.gnaw_delay_s:
		return
	enemy.is_gnawing = true
	enemy.gnaw_left -= delta
	if enemy.gnaw_left > 0.0:
		return
	enemy.gnaw_left = gnaw_scale
	var point := enemy.global_position + direction.normalized() * 1.0
	terrain_field.sculpt(point, tuning.gnaw_radius_m, -tuning.gnaw_depth_m)
	gnaws += 1
	print("PROTOTYPE01_ENEMY_GNAW total=%d" % gnaws)


## Respinge i nemici entro [param radius] da [param center] (colpo al giocatore, O-01):
## la velocita verso l'esterno cala da sola, perche ogni passo la riporta verso quella
## desiderata con ACCELERATION. I boss (self_driven) non si spostano.
func shove_from(center: Vector3, radius: float, speed: float) -> int:
	var shoved := 0
	for enemy in enemies:
		if enemy.is_dead or enemy.self_driven:
			continue
		var away := _planar(enemy.global_position - center)
		var distance := away.length()
		if distance > radius:
			continue
		var dir := away / distance if distance > 0.001 else Vector3.FORWARD
		var push := dir * speed * (1.0 - 0.5 * distance / radius)
		enemy.velocity = Vector3(push.x, enemy.velocity.y, push.z)
		shoved += 1
	return shoved


func _separation(enemy: Enemy) -> Vector3:
	var push := Vector3.ZERO
	var base := Vector2i(floori(enemy.global_position.x), floori(enemy.global_position.z))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := base + Vector2i(dx, dz)
			if not _buckets.has(key):
				continue
			for other: Enemy in _buckets[key]:
				if other == enemy:
					continue
				var away := _planar(enemy.global_position - other.global_position)
				var distance := away.length()
				if distance < SEPARATION_RADIUS and distance > 0.001:
					push += away / distance * (1.0 - distance / SEPARATION_RADIUS)
	return push


func _on_enemy_died(enemy: Enemy) -> void:
	enemies.erase(enemy)
	kills += 1
	var pos := enemy.global_position
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	var tween := enemy.create_tween()
	tween.tween_property(enemy, ^"scale", Vector3.ONE * 0.05, 0.12)
	tween.tween_callback(enemy.queue_free)
	if enemy.self_driven:
		DebrisBurst.spawn(self, pos, enemy.death_debris_color(), 28, 7.0, 0.3)
	else:
		DebrisBurst.spawn(self, pos, BODY_COLOR, 6)
	print("PROTOTYPE01_ENEMY_KILLED total=%d" % kills)
	enemy_killed.emit(pos, kills)


static func _planar(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
