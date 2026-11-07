class_name Demolisher
extends Enemy
## Primo boss di fine livello (D-043, CAMPAIGN_STRUCTURE_SPEC sezione 5): il Demolitore.
##
## Regola col terreno, leggibile al primo incontro: **i terrapieni lo attirano e lui
## li smonta**. Ogni muro smontato lascia a terra un rottame; i **rottamatori**
## vicini lo raccolgono e lo portano al **cantiere** (lastra arancione), dove ogni
## `walls_per_barricade` rottami nasce una **barricata** (cumulo scuro) fra
## lui e il giocatore, che ferma i chiodi (D-045).
## Soluzioni che il campo offre:
## - una salita lo rallenta come ogni altro nemico;
## - un muro a sacrificio lo tiene fermo dove la chiodatrice lo colpisce, ma
##   alimenta le sue barricate;
## - abbattere un rottamatore carico gli fa cadere il rottame: lo prende chi arriva prima;
## - scavare o occupare il cantiere lo costringe a sceglierne un altro;
## - scavare una barricata la fa crollare e restituisce il rottame.
## E un Enemy registrato nell'EnemyDirector (cosi armi, scavo esplosivo e torretta
## lo colpiscono), ma si guida da solo: `self_driven`.

signal wall_demolished(at: Vector3)
signal barricade_built(at: Vector3)
signal scrap_delivered(at: Vector3, stocked: int)
## Un rottamatore della squadra ha raccolto un rottame.
signal scrap_taken

const BODY_MODEL := preload("res://assets/models/demolisher.glb")
const BLADE_MODEL := preload("res://assets/models/demolisher_blade.glb")
const BODY_RADIUS := 0.9
const BODY_HEIGHT := 2.4
const BODY_COLOR := Color(0.85, 0.55, 0.05)
## Posizione locale della lama a riposo; martellando sale di BLADE_HAMMER_LIFT.
const BLADE_REST := Vector3(0.0, -0.6, -1.15)
const BLADE_HAMMER_LIFT := 0.35
## Colore lineare delle barricate: ferro scuro, distinto dai terrapieni del giocatore.
const BARRICADE_COLOR := Color(0.07, 0.06, 0.09)
const SITE_COLOR := Color(1.0, 0.35, 0.08, 0.6)
## Rilievo continuo (D-085): barricata a cumulo, martello che spiana, scavo sotto la base
## di una vena. Un argine vale come bersaglio da WALL_MIN_DELTA di sporgenza dalla base.
const BARRICADE_HEIGHT := 1.5
const BARRICADE_RADIUS := 2.4
const HAMMER_RADIUS := 3.6
const HAMMER_RATE := 3.0
## Colpi di martello al secondo (audit E-12): prima uno a ogni passo fisico, con 9 pennellate.
const HAMMER_INTERVAL := 0.1
const WALL_MIN_DELTA := 0.8
const WALL_DONE_DELTA := 0.3
## Distanza (oltre il corpo) da cui il martello raggiunge il bersaglio.
const DEMOLISH_REACH := 2.4
## La terra tolta va in otto pennellate larghe e basse attorno: si conserva senza creare
## nuove cime che il boss inseguirebbe (sotto WALL_MIN_DELTA).
const SPOIL_POINTS := 8
const SPOIL_RADIUS := 3.0
const VEIN_DIG_DEPTH := 0.6
## Raggio (m) entro cui una barricata o un punto ignorato escludono un bersaglio.
const POINT_MATCH_M := 1.5
## Terra dei terrapieni (RG_EARTH dello shader del suolo), per i frammenti.
const EARTH_COLOR := Color(0.44, 0.33, 0.21)
const ACCELERATION := 10.0
const RETARGET_SECONDS := 0.4
## Un muro che non si avvicina per tanto (rovina in mezzo, blocco non figlio della
## griglia) viene lasciato perdere per WALL_IGNORE_SECONDS: si torna a inseguire il
## giocatore col campo di percorso invece di restare incastrati.
const WALL_STALL_SECONDS := 2.0
const WALL_IGNORE_SECONDS := 8.0
## Sotto questa distanza dal giocatore punta dritto, senza waypoint.
const DIRECT_CHASE_DISTANCE := 3.0

# --- Movimento procedurale (ActorMotion): solo sul telaio visivo `_rig`, che porta
# scafo e lama; il corpo fisico e `_blade.position` restano del codice di gioco.
## Punto d'appoggio a terra del telaio, nello spazio del boss (origine al centro della capsula).
const RIG_GROUND := Vector3(0.0, -BODY_HEIGHT * 0.5, 0.0)
## Mezza lunghezza e mezza larghezza (m) dei cingoli: inclinandosi il telaio si alza
## di |angolo| x braccio e non entra nel terreno.
const TRACK_HALF_LENGTH := 1.05
const TRACK_HALF_WIDTH := 0.95
## Vibrazione dei cingoli in marcia: frequenze (Hz), sobbalzo (m) e rollio (rad) a piena velocita.
const RUMBLE_HZ := 9.0
const RUMBLE_ROLL_HZ := 5.3
const RUMBLE_HEIGHT := 0.035
const RUMBLE_ROLL := 0.02
## Spostamento del peso: velocita angolare (rad/s) data al beccheggio per ogni m/s di
## cambio di velocita in avanti (parte: muso in su; si ferma: muso in giu).
const SHIFT_KICK := 0.45
## Molla che riporta il beccheggio a zero (rigidezza 1/s^2, smorzamento 1/s) e suo limite (rad).
const SHIFT_STIFFNESS := 90.0
const SHIFT_DAMPING := 9.0
const SHIFT_MAX := 0.06
## Caricamento del colpo di lama: mentre la lama sale lo scafo alza il muso (rad) e
## arretra (m); quando la lama cala torna giu con lei.
const WINDUP_PITCH := 0.05
const WINDUP_BACK := 0.06
## Velocita (1/s) con cui il caricamento entra ed esce a inizio e fine demolizione.
const WINDUP_BLEND_RATE := 8.0
## Barcollamento pesante quando e colpito: durata (s), arretramento (m), muso in su (rad),
## e scossone laterale (rad) alla frequenza indicata (Hz).
const HEAVY_STAGGER_SECONDS := 0.32
const HEAVY_STAGGER_BACK := 0.1
const HEAVY_STAGGER_PITCH := 0.04
const HEAVY_STAGGER_SHAKE := 0.02
const HEAVY_STAGGER_SHAKE_HZ := 6.0
## Frequenza del martello in `_tick_demolition` (rad/s): la stessa formula, per caricare a tempo.
const BLADE_HAMMER_RATE := 14.0

var player: PlayerCharacter
var terrain_field: TerrainField
var path_field: PathField
var director: EnemyDirector
## Lampioni del giocatore: abbattuti quando entrano nel raggio di contatto (D-058).
var lamp_field: LampField
## Carovana del giocatore: il contatto colpisce le sue macchine; niente barricate sopra di loro.
var caravan: Caravan
var speed := 1.7
var contact_damage := 2
var contact_radius := 1.5
var demolish_seconds := 1.2
var wall_attraction_radius := 12.0
var walls_per_barricade := 2
var max_barricades := 8
## Rottami a terra: senza, le barricate nascono direttamente dal boss (D-043).
var scrap_field: ScrapField
var max_carriers := 3
var carrier_scrap_radius := 10.0
var carrier_recruit_radius := 14.0
var carrier_timeout := 10.0

## Barricate a cumulo sul rilievo (centro XZ, y = 0).
var barricade_points: Array[Vector3] = []
var walls_demolished := 0
## Bersaglio e cantiere sul rilievo; Vector3.INF = nessuno.
var wall_point := Vector3.INF
var demolish_point := Vector3.INF
## Vero se il punto in demolizione ha una vena: si scava sotto la base per i rottami.
var _demolish_vein := false
var _site_point := Vector3.INF
var _ignored_points: Dictionary[Vector3, float] = {}

var _demolish_left := 0.0
## Tempo accumulato dall'ultimo colpo di martello.
var _hammer_accum := 0.0
var _retarget_left := 0.0
## Distanza minima raggiunta dal muro scelto e secondi senza avvicinarsi.
var _wall_best_distance := INF
var _wall_stall_left := WALL_STALL_SECONDS
var _blade: MeshInstance3D
## Rottamatori al lavoro per lui: secondi rimasti prima che lascino la commissione.
var _crew: Dictionary[Enemy, float] = {}
var _site_scrap := 0
var _site_marker: MeshInstance3D
## Telaio visivo: genitore di scafo e lama, l'unico nodo mosso dal movimento procedurale.
var _rig: Node3D
var _motion_time := 0.0
var _last_forward_speed := 0.0
## Beccheggio da spostamento del peso: (angolo, velocita angolare).
var _shift := Vector2.ZERO
var _windup_weight := 0.0
## Riusato a ogni passo (E-08): chi va tolto dalla squadra o dai muri ignorati.
var _to_remove: Array = []


func setup_demolisher(hp: int, flash_material: Material) -> void:
	name = "Demolisher"
	kind = &"demolisher"
	self_driven = true
	hit_radius_bonus = BODY_RADIUS - RADIUS
	health = hp
	max_health = hp
	collision_layer = 16
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	# Modelli `demolisher` e `demolisher_blade` (tools/blender/build_actor_assets.py):
	# origine dello scafo a terra, quella del boss al centro della capsula. Lo scafo e
	# "vernice" tinta con BODY_COLOR; fessura rossa e lampeggiante sono luminosi.
	_body = MeshInstance3D.new()
	_body.mesh = ActorModel.mesh_of(BODY_MODEL)
	_base_material = ActorModel.textured_paint(_body.mesh, BODY_COLOR, 2.5, 0.7)
	_flash_material = flash_material
	ActorModel.dress(_body, _base_material)
	_body.position.y = -BODY_HEIGHT * 0.5
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_rig.add_child(_body)
	# La lama resta un nodo a parte: il codice la fa martellare.
	_blade = MeshInstance3D.new()
	_blade.mesh = ActorModel.mesh_of(BLADE_MODEL)
	ActorModel.dress(_blade, ActorModel.textured_paint(_blade.mesh, Color.WHITE, 0.0, 0.5))
	_blade.position = BLADE_REST
	_rig.add_child(_blade)


func _ready() -> void:
	floor_max_angle = atan(0.8)
	if terrain_field != null:
		terrain_field.region_changed.connect(_on_region_changed)
	died.connect(func(_enemy: Enemy) -> void: _dismiss_crew())


## Altezza del centro della capsula sopra il pavimento.
static func boss_spawn_height() -> float:
	return BODY_HEIGHT * 0.5 + 0.02


func spawn_center_height() -> float:
	return boss_spawn_height()


func death_debris_color() -> Color:
	return BODY_COLOR


func is_demolishing() -> bool:
	return demolish_point != Vector3.INF


func crew_size() -> int:
	return _crew.size()


## Punto del cantiere sul rilievo, Vector3.INF se nessuno.
func site_point() -> Vector3:
	return _site_point


## Rottami gia consegnati al cantiere.
func site_scrap() -> int:
	return _site_scrap


## Centro del cantiere, XZ con y = 0.
func _site_position() -> Vector3:
	return _site_point


## Centro del bersaglio corrente.
func _wall_position() -> Vector3:
	return wall_point


## Un passo fisico, chiamato dall'EnemyDirector.
func drive(delta: float) -> void:
	if player == null or terrain_field == null:
		return
	var pos := global_position
	var to_player := _planar(player.global_position - pos)
	if to_player.length() <= contact_radius:
		player.take_damage(contact_damage)
	# Anche le macchine della carovana a contatto (D-093, scelta 7).
	if caravan != null:
		for machine in caravan.machines:
			if _planar(machine.global_position - pos).length() <= contact_radius:
				machine.take_hit(contact_damage)
	if lamp_field != null and lamp_field.count() > 0:
		lamp_field.knock_down_near(pos, contact_radius)

	_tick_crew(delta)
	_retarget_left -= delta
	var retarget := _retarget_left <= 0.0
	if retarget:
		_retarget_left = RETARGET_SECONDS
		_recruit_carriers()
		if not _site_is_valid() and _any_carrier_loaded():
			_choose_site()
		_try_build_at_site()

	if is_demolishing():
		_tick_demolition(delta)
		return

	_tick_ignored_walls(delta)
	if retarget:
		var chosen_point := _nearest_wall_point()
		if chosen_point.distance_to(wall_point) > 0.01:
			wall_point = chosen_point
			_wall_best_distance = INF
			_wall_stall_left = WALL_STALL_SECONDS
	var has_wall := wall_point != Vector3.INF and _point_is_target(wall_point) and _still_stands(wall_point)
	if has_wall and _wall_stalled(delta):
		_ignored_points[wall_point] = WALL_IGNORE_SECONDS
		print("PROTOTYPE01_BOSS_WALL_ABANDONED x=%.1f z=%.1f" % [wall_point.x, wall_point.z])
		wall_point = Vector3.INF
		has_wall = false
	var direction := Vector3.ZERO
	if has_wall:
		direction = _planar(_wall_position() - pos).normalized()
	else:
		if to_player.length() > DIRECT_CHASE_DISTANCE and path_field != null:
			var waypoint: Variant = path_field.next_waypoint(pos)
			if waypoint != null:
				direction = _planar(waypoint - pos).normalized()
		if direction.is_zero_approx():
			direction = to_player.normalized()

	var current_speed := speed
	if not direction.is_zero_approx():
		# In salita rallenta in proporzione alla pendenza davanti (come l'orda, Task 7).
		var grade := terrain_field.grade_between(pos, pos + direction * 0.5)
		if grade > 0.0:
			var min_speed: float = director.tuning.uphill_min_speed if director != null and director.tuning != null else 0.5
			current_speed *= lerpf(1.0, min_speed, clampf(grade / terrain_field.tuning.max_grade, 0.0, 1.0))
	var planar := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * current_speed, ACCELERATION * delta)
	velocity = Vector3(planar.x, 0.0 if is_on_floor() else velocity.y - 9.8 * delta, planar.z)
	move_and_slide()
	if planar.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-planar.x, -planar.z), minf(delta * 6.0, 1.0))

	# Arrivato al bersaglio scelto, o fermato da un argine qualunque: lo spiana.
	if has_wall and _planar(wall_point - global_position).length() <= BODY_RADIUS + DEMOLISH_REACH:
		_start_demolition_at(wall_point)
		return
	var terrain_body := terrain_field.collision_body()
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() != terrain_body:
			continue
		# Fermato da un fianco ripido: la cima piu vicina oltre il punto di contatto.
		var contact := collision.get_position() - collision.get_normal() * 0.3
		var bump: Variant = terrain_field.highest_bump(contact, DEMOLISH_REACH, WALL_MIN_DELTA)
		if bump == null:
			continue
		var at := Vector3((bump as Vector3).x, 0.0, (bump as Vector3).z)
		if _point_is_target(at):
			_start_demolition_at(at)
			return


## Sul rilievo: il punto sporge ancora dalla base (o ha una vena con rottami).
func _still_stands(at: Vector3) -> bool:
	return terrain_field.highest_bump(at, HAMMER_RADIUS * 0.5, WALL_MIN_DELTA) != null or _vein_under(at)


## Sul rilievo: un punto e un bersaglio se non e una propria barricata ne un punto ignorato.
func _point_is_target(at: Vector3) -> bool:
	for b in barricade_points:
		if _planar(b - at).length() <= POINT_MATCH_M + BARRICADE_RADIUS * 0.5:
			return false
	for ignored in _ignored_points:
		if _planar(ignored - at).length() <= POINT_MATCH_M:
			return false
	return true


func _start_demolition_at(at: Vector3) -> void:
	demolish_point = Vector3(at.x, 0.0, at.z)
	# Il martello si aggancia alla cima locale, non al primo punto di contatto.
	var peak: Variant = terrain_field.highest_bump(demolish_point, HAMMER_RADIUS * 0.5, 0.0)
	if peak != null:
		demolish_point = Vector3((peak as Vector3).x, 0.0, (peak as Vector3).z)
	_demolish_vein = scrap_field != null and scrap_field.vein_scrap_left(demolish_point) > 0 \
			or _vein_under(demolish_point)
	_demolish_left = demolish_seconds
	_hammer_accum = 0.0
	velocity = Vector3.ZERO
	print("PROTOTYPE01_BOSS_DEMOLISH_START x=%.1f z=%.1f vein=%s" % [at.x, at.z, _demolish_vein])


## Vero se [param at] cade dentro una vena con rottami.
func _vein_under(at: Vector3) -> bool:
	if scrap_field == null:
		return false
	for vein in scrap_field.veins():
		if vein.scrap_left > 0 and _planar(vein.center - at).length() <= vein.radius:
			return true
	return false


## Il martello spiana il punto verso la quota di base (o sotto, se c'e una vena): la
## terra tolta va in un anello attorno (si conserva) e il volume scavato sotto la base
## scala le vene. Finito quando il punto non sporge piu.
func _tick_demolition_at(delta: float) -> void:
	_demolish_left -= delta
	_blade.position.y = BLADE_REST.y + absf(sin(_demolish_left * BLADE_HAMMER_RATE)) * BLADE_HAMMER_LIFT
	var facing := _planar(demolish_point - global_position)
	if facing.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-facing.x, -facing.z), minf(delta * 8.0, 1.0))
	if _demolish_left > 0.0:
		return
	_hammer_accum += delta
	if _hammer_accum < HAMMER_INTERVAL:
		return
	var hammer_step := _hammer_accum
	_hammer_accum = 0.0
	var base := terrain_field.base_height_at(demolish_point)
	var target := base - VEIN_DIG_DEPTH if _demolish_vein else base
	var removed := -terrain_field.level(demolish_point, HAMMER_RADIUS, target, HAMMER_RATE * hammer_step)
	if removed > 0.0:
		var spoil_amount := removed / (SPOIL_POINTS * PI * SPOIL_RADIUS * SPOIL_RADIUS / 3.0)
		# Le 8 pennellate di terra smossa in un solo aggiornamento del terreno.
		terrain_field.begin_batch()
		for k in SPOIL_POINTS:
			var angle := TAU * k / SPOIL_POINTS
			terrain_field.sculpt(demolish_point + Vector3(cos(angle), 0.0, sin(angle)) * (HAMMER_RADIUS + 2.0), SPOIL_RADIUS, spoil_amount)
		terrain_field.end_batch()
		if scrap_field != null:
			scrap_field.extract_from_veins(demolish_point, HAMMER_RADIUS, removed)
	var digging_vein := _demolish_vein and _vein_under(demolish_point)
	if digging_vein:
		if terrain_field.delta_at(demolish_point) >= -VEIN_DIG_DEPTH + 0.1:
			return
	elif terrain_field.highest_bump(demolish_point, HAMMER_RADIUS * 0.5, WALL_DONE_DELTA) != null:
		# Finito solo quando tutta la cima attorno al punto e spianata.
		return
	var at := demolish_point
	demolish_point = Vector3.INF
	wall_point = Vector3.INF
	_blade.position.y = BLADE_REST.y
	walls_demolished += 1
	DebrisBurst.spawn(get_parent(), Vector3(at.x, terrain_field.height_at(at) + 0.6, at.z), EARTH_COLOR, 14, 5.0, 0.22)
	print("PROTOTYPE01_BOSS_WALL_DEMOLISHED x=%.1f z=%.1f total=%d" % [at.x, at.z, walls_demolished])
	wall_demolished.emit(at)


func _tick_demolition(delta: float) -> void:
	_tick_demolition_at(delta)


# --- Rottamatori al lavoro (D-045) ---------------------------------------------------

## Manda i rottamatori liberi piu vicini a prendere i rottami attorno al boss.
func _recruit_carriers() -> void:
	if scrap_field == null or director == null or _crew.size() >= max_carriers:
		return
	if barricade_points.size() >= max_barricades:
		return
	for scrap in scrap_field.positions_near(global_position, carrier_scrap_radius):
		if _crew.size() >= max_carriers:
			return
		var claimed := false
		for carrier: Enemy in _crew:
			if not carrier.carrying_scrap and _planar(carrier.errand_point - scrap).length() < 0.2:
				claimed = true
				break
		if claimed:
			continue
		# Rottame senza strada dal giocatore (oltre un muro chiuso): nessuno lo raggiungerebbe.
		if not _reachable(scrap):
			continue
		var best: Enemy = null
		var best_distance := carrier_recruit_radius
		for enemy in director.enemies:
			if enemy == self or enemy.is_dead or enemy.self_driven or enemy.has_errand:
				continue
			# Stessa regione del giocatore e del rottame: altrimenti spingerebbe contro il muro.
			if not _reachable(enemy.global_position):
				continue
			var distance := _planar(enemy.global_position - scrap).length()
			if distance < best_distance:
				best_distance = distance
				best = enemy
		if best == null:
			continue
		best.set_errand(scrap)
		_crew[best] = carrier_timeout
		if not best.errand_reached.is_connected(_on_carrier_arrived):
			best.errand_reached.connect(_on_carrier_arrived)
			best.died.connect(_on_carrier_died)


## Il punto, o una cella vicina (chi sta addosso a una rovina puo avere il centro in una
## cella segnata come bloccata), ha una strada verso il giocatore nel campo di percorso.
func _reachable(point: Vector3) -> bool:
	if path_field == null or not path_field.is_ready():
		return true
	if path_field.cost_at(point) != PathField.UNREACHABLE:
		return true
	var step := path_field.cell_size
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dz != 0) and path_field.cost_at(point + Vector3(dx * step, 0.0, dz * step)) != PathField.UNREACHABLE:
				return true
	return false


## Toglie dalla squadra chi e morto o e stato rimosso (l'orda che si ritira).
func _prune_crew() -> void:
	_to_remove.clear()
	for carrier in _crew:
		if not is_instance_valid(carrier) or carrier.is_dead:
			_to_remove.append(carrier)
	for carrier in _to_remove:
		_crew.erase(carrier)


func _any_carrier_loaded() -> bool:
	for carrier: Enemy in _crew:
		if carrier.carrying_scrap:
			return true
	return false


func _tick_crew(delta: float) -> void:
	_prune_crew()
	# `_release` toglie dal dizionario: si scorre una copia leggera solo se serve.
	_to_remove.clear()
	for carrier: Enemy in _crew:
		_to_remove.append(carrier)
	for carrier: Enemy in _to_remove:
		if not _crew.has(carrier):
			continue
		var waiting := carrier.carrying_scrap and not _site_is_valid()
		if waiting:
			# Senza cantiere valido aspetta accanto al boss, senza far scadere il tempo (R-04):
			# mollare il rottame e rireclutarlo ogni 10 s era un ciclo inutile.
			carrier.errand_point = global_position
			continue
		_crew[carrier] -= delta
		if _crew[carrier] <= 0.0:
			_release(carrier, true)
		elif carrier.carrying_scrap:
			carrier.errand_point = _site_position()


func _on_carrier_arrived(carrier: Enemy) -> void:
	if not _crew.has(carrier):
		return
	if not carrier.carrying_scrap:
		if scrap_field.take_near(carrier.errand_point, 0.3, 1) == 0:
			# Un Cassone (o un altro) e arrivato prima.
			_release(carrier, false)
			return
		carrier.set_carrying(true)
		_crew[carrier] = carrier_timeout
		if not _site_is_valid():
			_choose_site()
		print("PROTOTYPE01_BOSS_SCRAP_TAKEN crew=%d" % _crew.size())
		scrap_taken.emit()
		return
	var site := _site_position()
	if not _site_is_valid() or _planar(site - carrier.global_position).length() > 1.5:
		return
	_site_scrap += 1
	_release(carrier, false)
	print("PROTOTYPE01_BOSS_SCRAP_DELIVERED x=%.1f z=%.1f stocked=%d" % [site.x, site.z, _site_scrap])
	scrap_delivered.emit(site, _site_scrap)
	_try_build_at_site()


## Un rottamatore carico abbattuto lascia cadere il rottame: lo prende chi arriva prima.
func _on_carrier_died(carrier: Enemy) -> void:
	if not _crew.has(carrier):
		return
	_crew.erase(carrier)
	if carrier.carrying_scrap and scrap_field != null:
		scrap_field.spawn_on_ground(carrier.global_position)
		print("PROTOTYPE01_BOSS_SCRAP_DROPPED")


func _release(carrier: Enemy, drop_scrap: bool) -> void:
	_crew.erase(carrier)
	carrier.clear_errand()
	if carrier.carrying_scrap:
		carrier.set_carrying(false)
		if drop_scrap and scrap_field != null:
			scrap_field.spawn_on_ground(carrier.global_position)


func _dismiss_crew() -> void:
	_prune_crew()
	_to_remove.clear()
	for carrier: Enemy in _crew:
		_to_remove.append(carrier)
	for carrier: Enemy in _to_remove:
		_release(carrier, true)
	_clear_site()


func _site_is_valid() -> bool:
	return _site_point != Vector3.INF and terrain_field.is_flat(_site_point, BARRICADE_RADIUS, 0.35) \
			and not terrain_field.is_protected(_site_point)


func _choose_site() -> void:
	_clear_site(false)
	_site_point = _pick_barricade_point()
	if _site_point == Vector3.INF:
		return
	_ensure_site_marker(BARRICADE_RADIUS * 0.7)
	_site_marker.global_transform = Transform3D(Basis(), Vector3(_site_point.x, terrain_field.height_at(_site_point) + 0.05, _site_point.z))
	_site_marker.visible = true
	print("PROTOTYPE01_BOSS_SITE x=%.1f z=%.1f" % [_site_point.x, _site_point.z])


func _ensure_site_marker(side: float) -> void:
	if _site_marker == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(side, 0.06, side)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = SITE_COLOR
		_site_marker = MeshInstance3D.new()
		_site_marker.mesh = mesh
		_site_marker.material_override = material
		_site_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_site_marker.top_level = true
		add_child(_site_marker)


## I rottami gia consegnati restano del boss: passano al cantiere successivo.
func _clear_site(forget_scrap := true) -> void:
	_site_point = Vector3.INF
	if forget_scrap:
		_site_scrap = 0
	if _site_marker != null:
		_site_marker.visible = false


## Con abbastanza rottami consegnati alza la barricata, appena il punto e libero.
func _try_build_at_site() -> void:
	if _site_scrap < walls_per_barricade or barricade_points.size() >= max_barricades:
		return
	if not _site_is_valid():
		_choose_site()
	if _site_point != Vector3.INF and not _point_is_free(_site_point):
		# Occupato (giocatore, macchine, nemici, rottame): un altro cantiere, la scorta resta (R-03).
		_choose_site()
	if _site_point == Vector3.INF or not _point_is_free(_site_point):
		return
	var point := _site_point
	_site_scrap -= walls_per_barricade
	_clear_site(false)
	_raise_barricade_at(point)


## Sul rilievo: la cima piu sporgente dalla base entro il raggio di attrazione, o la vena
## piu vicina con rottami; mai una propria barricata ne un punto ignorato. Vector3.INF se nulla.
func _nearest_wall_point() -> Vector3:
	var best := Vector3.INF
	var best_distance := wall_attraction_radius
	# Anelli crescenti: la cima piu vicina conta piu di quella piu alta. Una sola passata
	# sul disco piu grande (audit E-16: prima quattro dischi annidati riscanditi).
	for bump: Variant in terrain_field.highest_bumps_by_ring(global_position, 3.0, wall_attraction_radius + 0.01, WALL_MIN_DELTA):
		if bump == null:
			continue
		var at := Vector3((bump as Vector3).x, 0.0, (bump as Vector3).z)
		if _point_is_target(at):
			best = at
			best_distance = _planar(at - global_position).length()
			break
	if scrap_field != null:
		for vein in scrap_field.veins():
			if vein.scrap_left <= 0:
				continue
			var at := Vector3(vein.center.x, 0.0, vein.center.z)
			var distance := _planar(at - global_position).length()
			if distance < best_distance and _point_is_target(at):
				best = at
				best_distance = distance
	return best


## Vero se da WALL_STALL_SECONDS il muro scelto non si avvicina.
func _wall_stalled(delta: float) -> bool:
	var distance := _planar(_wall_position() - global_position).length()
	if distance < _wall_best_distance - 0.05:
		_wall_best_distance = distance
		_wall_stall_left = WALL_STALL_SECONDS
		return false
	_wall_stall_left -= delta
	return _wall_stall_left <= 0.0


func _tick_ignored_walls(delta: float) -> void:
	if not _ignored_points.is_empty():
		_to_remove.clear()
		for point in _ignored_points:
			_ignored_points[point] -= delta
			if _ignored_points[point] <= 0.0:
				_to_remove.append(point)
		for point in _to_remove:
			_ignored_points.erase(point)


## Punto per una barricata sul rilievo: due passi avanti verso il giocatore (o tre, o uno)
## su cinque posizioni laterali, dove il suolo e piano e libero. Vector3.INF se nessuno.
func _pick_barricade_point() -> Vector3:
	var to_player := _planar(player.global_position - global_position)
	if to_player.length() < 0.1:
		return Vector3.INF
	var forward := to_player.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var step := BARRICADE_RADIUS
	for ahead in [2.0, 3.0, 1.0]:
		for lateral in [0.0, 1.0, -1.0, 2.0, -2.0]:
			var point: Vector3 = _planar(global_position) + forward * step * ahead + side * step * lateral
			if absf(point.x) > terrain_field.half_extents().x - step or absf(point.z) > terrain_field.half_extents().y - step:
				continue
			if not terrain_field.is_flat(point, BARRICADE_RADIUS, 0.35) or terrain_field.is_protected(point):
				continue
			if _point_is_free(point):
				return point
	return Vector3.INF


## Mai sopra giocatore, macchine, nemici, rottami o il boss stesso; mai in area protetta.
func _point_is_free(point: Vector3) -> bool:
	var step := BARRICADE_RADIUS
	if terrain_field.is_protected(point):
		return false
	if _planar(point - player.global_position).length() < step:
		return false
	if caravan != null:
		for machine in caravan.machines:
			if _planar(point - machine.global_position).length() < step:
				return false
	if _planar(point - global_position).length() < BODY_RADIUS + step * 0.75:
		return false
	if director != null:
		for other in director.enemies_near(point, step * 0.75):
			if other != self:
				return false
	if scrap_field != null and not scrap_field.positions_near(point, 1.2).is_empty():
		return false
	return true


## Barricata a cumulo: in un colpo solo, su un punto appena verificato libero da corpi.
func _raise_barricade_at(point: Vector3) -> void:
	var at := Vector3(point.x, 0.0, point.z)
	barricade_points.append(at)
	terrain_field.sculpt(at, BARRICADE_RADIUS, BARRICADE_HEIGHT)
	terrain_field.tint(at, BARRICADE_RADIUS, BARRICADE_COLOR, 1.0)
	DebrisBurst.spawn(get_parent(), Vector3(at.x, terrain_field.height_at(at) + 0.6, at.z), BARRICADE_COLOR, 12, 4.0, 0.2)
	print("PROTOTYPE01_BOSS_BARRICADE x=%.1f z=%.1f standing=%d" % [at.x, at.z, barricade_points.size()])
	barricade_built.emit(at)


## Una barricata spianata (dal giocatore o da un evento) crolla: non e piu sua; un
## cantiere non piu piano viene lasciato.
func _on_region_changed(aabb: AABB) -> void:
	var probe_y := aabb.position.y + 0.1
	for i in range(barricade_points.size() - 1, -1, -1):
		var p := barricade_points[i]
		if not aabb.has_point(Vector3(p.x, probe_y, p.z)):
			continue
		if terrain_field.delta_at(p) < 0.5:
			barricade_points.remove_at(i)
			terrain_field.tint(p, BARRICADE_RADIUS, Color.WHITE, 1.0)
			print("PROTOTYPE01_BOSS_BARRICADE_DOWN x=%.1f z=%.1f standing=%d" % [p.x, p.z, barricade_points.size()])
	if _site_point != Vector3.INF and aabb.has_point(Vector3(_site_point.x, probe_y, _site_point.z)) and not _site_is_valid():
		_clear_site(false)


static func _planar(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Movimento procedurale ---------------------------------------------------------------

## Vibrazione dei cingoli, spostamento del peso, caricamento del colpo e barcollamento:
## tutto sommato in una sola trasformazione del telaio. La lama e figlia del telaio e
## continua a martellare in `_blade.position.y`, quindi i due movimenti si compongono.
func _animate(delta: float) -> void:
	_motion_time += delta
	var forward := -global_basis.z
	var forward_speed := velocity.x * forward.x + velocity.z * forward.z
	var moving := clampf(Vector2(velocity.x, velocity.z).length() / maxf(speed, 0.01), 0.0, 1.0)

	_shift.y += (forward_speed - _last_forward_speed) * SHIFT_KICK
	_last_forward_speed = forward_speed
	_shift = ActorMotion.spring(_shift, SHIFT_STIFFNESS, SHIFT_DAMPING, delta)
	var pitch := clampf(_shift.x, -SHIFT_MAX, SHIFT_MAX)
	var roll := sin(_motion_time * TAU * RUMBLE_ROLL_HZ) * RUMBLE_ROLL * moving
	var rise := (0.5 + 0.5 * sin(_motion_time * TAU * RUMBLE_HZ)) * RUMBLE_HEIGHT * moving
	var slide := 0.0

	_windup_weight = move_toward(_windup_weight, 1.0 if is_demolishing() else 0.0, WINDUP_BLEND_RATE * delta)
	if _windup_weight > 0.0:
		# Stessa fase della lama: 1 con la lama in alto, 0 quando batte.
		var raised := absf(sin(_demolish_left * BLADE_HAMMER_RATE)) * _windup_weight
		pitch += WINDUP_PITCH * raised
		slide += WINDUP_BACK * raised

	if _stagger > 0.0:
		_stagger = maxf(_stagger - delta / HEAVY_STAGGER_SECONDS, 0.0)
		var hit := _stagger * _stagger
		slide += HEAVY_STAGGER_BACK * hit
		pitch += HEAVY_STAGGER_PITCH * hit
		roll += sin(_motion_time * TAU * HEAVY_STAGGER_SHAKE_HZ) * HEAVY_STAGGER_SHAKE * hit

	var pose := ActorMotion.tilt_on_ground(RIG_GROUND, pitch, roll, TRACK_HALF_LENGTH, TRACK_HALF_WIDTH)
	pose.origin += Vector3(0.0, rise, slide)
	_rig.transform = pose
	_at_rest = false


func _reset_pose() -> void:
	_rig.transform = Transform3D.IDENTITY
	_shift = Vector2.ZERO
	_last_forward_speed = 0.0
	_at_rest = true
