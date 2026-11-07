class_name Driller
extends Enemy
## Secondo boss, la Trivella (D-066, docs/RAILWAY_LEVEL_SPEC.md sezione 5).
##
## Regola col terreno, leggibile al primo incontro: **carica in linea retta e scava un
## solco; un argine la ferma**. Ciclo: mira (telegraph: la punta accelera e una
## striscia a terra mostra la linea), carica (fino a `charge_length` metri a
## `charge_speed`, ignorando il campo di percorso; la punta porta il terreno a
## `furrow_depth_m` sotto la base, mai oltre), poi riposo. Se la punta incontra un
## argine (`delta_at >= wall_min_delta_m`) lo apre fino alla base (niente rottami: solo
## una vena sotto ne rende) e la Trivella resta **stordita** `stun_seconds`: in quel
## tempo subisce danno moltiplicato. I solchi non la rallentano; non costruisce nulla.
## Chi sta sulla linea viene colpito e spinto di lato.
## E un Enemy registrato nell'EnemyDirector e si guida da solo (`self_driven`).

signal charge_started(target: Vector3)
## reason: "length" (fine corsa), "wall" (terrapieno), "blocked" (rovina o bordo).
signal charge_ended(reason: StringName)
signal furrowed(point: Vector3)
signal wall_broken(point: Vector3)
signal stunned(seconds: float)

enum Phase { REST, AIM, CHARGE, STUN }

const BODY_MODEL := preload("res://assets/models/driller.glb")
const BIT_MODEL := preload("res://assets/models/driller_bit.glb")
const BODY_RADIUS := 0.9
const BODY_HEIGHT := 2.4
## Lineare: vernice dello scafo, rosso ruggine scuro (e colore dei frammenti alla morte).
const BODY_COLOR := Color(0.5, 0.1, 0.06)
const EARTH_COLOR := Color(0.44, 0.33, 0.21)
## Innesto della punta: davanti al collare, a meta altezza della capsula (origine al centro).
const BIT_REST := Vector3(0.0, -0.2, -1.3)
## Distanza dal centro alla punta: li si legge il terreno da scavare.
const BIT_REACH := BODY_RADIUS + 1.4
const BIT_SPIN_MAX := 28.0
const BIT_SPIN_RATE := 24.0
const NO_WALL := Vector3.INF
## Raggio del solco e del varco aperto in un argine.
const FURROW_RADIUS := 1.2
## Il solco si scava ogni tanti metri percorsi e gli schizzi escono al massimo ogni tanti
## secondi (audit E-13): prima una pennellata e un nodo di particelle a ogni passo fisico.
const FURROW_STEP_M := 0.3
const FURROW_DEBRIS_SECONDS := 0.15
const BREACH_RADIUS := 2.4
const ACCELERATION := 30.0
const TURN_RATE := 3.0
## Colore della striscia di mira e sua larghezza.
const AIM_COLOR := Color(1.0, 0.2, 0.1, 0.45)
const AIM_WIDTH := 1.8
## Spinta laterale per chi viene colpito in carica.
const SIDE_PUSH := 2.6
## Quanto piu in alto di dove si e puo far atterrare la spinta laterale (audit E-11): basta a
## uscire dal solco della carica (0,8 m), non a finire in cima a un argine.
const PUSH_MAX_RISE_M := 1.0
## Lungo la linea di mira, un ostacolo che non e un argine entro questa distanza fa
## preferire il campo di percorso (non si carica contro una rovina).
const AIM_PROBE_METERS: Array[float] = [3.0, 6.0, 9.0]

# --- Movimento procedurale (ActorMotion): solo sul telaio visivo `_rig`.
const RIG_GROUND := Vector3(0.0, -BODY_HEIGHT * 0.5, 0.0)
const TRACK_HALF_LENGTH := 1.1
const TRACK_HALF_WIDTH := 0.95
const RUMBLE_HZ := 11.0
const RUMBLE_HEIGHT := 0.05
const RUMBLE_ROLL := 0.03
const STUN_PITCH := 0.09
const STUN_SINK := 0.08
const HEAVY_STAGGER_SECONDS := 0.3
const HEAVY_STAGGER_BACK := 0.08
const HEAVY_STAGGER_PITCH := 0.03

var player: PlayerCharacter
var terrain_field: TerrainField
var path_field: PathField
var director: EnemyDirector
var lamp_field: LampField
var scrap_field: ScrapField
## Carovana del giocatore: il contatto colpisce le macchine e la carica spinge di lato e ferisce
## ogni macchina non guasta sulla sua strada.
var caravan: Caravan
var charge_speed := 6.0
var charge_length := 30.0
var aim_seconds := 2.0
var rest_seconds := 3.0
var stun_seconds := 3.0
var stun_damage_multiplier := 2.0
## Profondita del solco sotto la base e sporgenza minima di un argine che la ferma.
var furrow_depth_m := 0.8
var wall_min_delta_m := 0.8
var contact_damage := 2
var contact_radius := 1.5

var phase := Phase.REST
var phase_left := 0.0
var charge_direction := Vector3.FORWARD
var charge_start := Vector3.ZERO
var charges := 0
## Metri di solco scavati e argini aperti.
var furrow_length_m := 0.0
## Strada fatta dall'ultimo scavo del solco e attesa del prossimo schizzo.
var _furrow_travel := 0.0
var _furrow_debris_left := 0.0
var walls_broken := 0
## Punto dell'argine appena aperto dall'ultima carica, NO_WALL se nessuno.
var last_wall := NO_WALL

var _bit: MeshInstance3D
var _rig: Node3D
var _aim_strip: MeshInstance3D
var _bit_spin := 0.0
var _hit_this_charge: Dictionary[Node, bool] = {}
## Secondi di carica senza avanzare (incastrata in un fossato profondo o contro un bordo).
var _charge_stall := 0.0
var _motion_time := 0.0
var _stun_weight := 0.0


func setup_driller(hp: int, flash_material: Material) -> void:
	name = "Driller"
	kind = &"driller"
	self_driven = true
	# Nessun rallentamento in salita: cio che sporge lo sfonda; il corpo sale come gli altri.
	max_grade = 10.0
	floor_max_angle = atan(0.8)
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
	_bit = MeshInstance3D.new()
	_bit.name = "Bit"
	_bit.mesh = ActorModel.mesh_of(BIT_MODEL)
	ActorModel.dress(_bit, ActorModel.textured_paint(_bit.mesh, Color.WHITE, 0.0, 0.5))
	_bit.position = BIT_REST
	_rig.add_child(_bit)
	_aim_strip = MeshInstance3D.new()
	_aim_strip.name = "AimStrip"
	_aim_strip.top_level = true
	var strip := BoxMesh.new()
	strip.size = Vector3.ONE
	_aim_strip.mesh = strip
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = AIM_COLOR
	_aim_strip.material_override = material
	_aim_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_strip.visible = false
	add_child(_aim_strip)
	phase = Phase.REST
	phase_left = rest_seconds * 0.5


static func boss_spawn_height() -> float:
	return BODY_HEIGHT * 0.5 + 0.02


func spawn_center_height() -> float:
	return boss_spawn_height()


func death_debris_color() -> Color:
	return BODY_COLOR


func is_charging() -> bool:
	return phase == Phase.CHARGE


func is_stunned() -> bool:
	return phase == Phase.STUN


func is_aiming() -> bool:
	return phase == Phase.AIM


## Stordita subisce danno moltiplicato: e la finestra che un terrapieno le apre.
func take_damage(amount: int) -> bool:
	if phase == Phase.STUN:
		amount = int(ceil(amount * stun_damage_multiplier))
	return super.take_damage(amount)


## Un passo fisico, chiamato dall'EnemyDirector.
func drive(delta: float) -> void:
	if player == null or terrain_field == null:
		return
	var pos := global_position
	var to_player := _planar(player.global_position - pos)
	if phase != Phase.STUN:
		if to_player.length() <= contact_radius:
			player.take_damage(contact_damage)
		# Anche le macchine della carovana a contatto (D-093, scelta 7).
		if caravan != null:
			for machine in caravan.machines:
				if _planar(machine.global_position - pos).length() <= contact_radius:
					machine.take_hit(contact_damage)
	if lamp_field != null and lamp_field.count() > 0:
		lamp_field.knock_down_near(pos, contact_radius)
	phase_left -= delta
	match phase:
		Phase.REST:
			_face(to_player, delta)
			_settle(delta)
			if phase_left <= 0.0:
				_start_aim()
		Phase.AIM:
			_face(charge_direction, delta)
			_settle(delta)
			_update_aim_strip()
			if phase_left <= 0.0:
				_start_charge()
		Phase.CHARGE:
			_tick_charge(delta)
		Phase.STUN:
			_settle(delta)
			if phase_left <= 0.0:
				phase = Phase.REST
				phase_left = rest_seconds


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * TURN_RATE, 1.0))


## Da ferma: frena e resta appoggiata a terra.
func _settle(delta: float) -> void:
	var planar := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, ACCELERATION * delta)
	velocity = Vector3(planar.x, 0.0 if is_on_floor() else velocity.y - 9.8 * delta, planar.z)
	move_and_slide()


func _start_aim() -> void:
	phase = Phase.AIM
	phase_left = aim_seconds
	charge_direction = _aim_direction()
	_aim_strip.visible = true
	_update_aim_strip()


## Dritto verso il giocatore; se nei primi metri c'e una rovina (non un argine, quello
## lo vuole e lo sfonda) segue il campo di percorso.
func _aim_direction() -> Vector3:
	var pos := global_position
	var direct := _planar(player.global_position - pos)
	if direct.length_squared() < 0.01:
		return -global_basis.z
	direct = direct.normalized()
	if path_field == null or not path_field.is_ready():
		return direct
	for meters in AIM_PROBE_METERS:
		var probe := pos + direct * meters
		# Il fianco di un argine non e percorribile ma non e una rovina: se attorno alla sonda
		# sporge un argine, la linea resta dritta e lo sfonda.
		if not path_field.is_walkable(probe) and terrain_field.highest_bump(probe, BREACH_RADIUS, wall_min_delta_m) == null:
			var waypoint: Variant = path_field.next_waypoint(pos)
			if waypoint != null:
				var via := _planar(waypoint - pos)
				if via.length_squared() > 0.01:
					return via.normalized()
			break
	return direct


func _update_aim_strip() -> void:
	var from := global_position
	# Sopra rotaie e massicciata del livello 2 (0,36 m): la striscia si vede anche sui binari.
	from.y = terrain_field.height_at(from) + 0.4
	var to := from + charge_direction * charge_length
	var mid := (from + to) * 0.5
	var basis := Basis(Vector3.UP, atan2(-charge_direction.x, -charge_direction.z))
	_aim_strip.global_transform = Transform3D(basis.scaled_local(Vector3(AIM_WIDTH, 0.04, charge_length)), mid)


func _start_charge() -> void:
	phase = Phase.CHARGE
	phase_left = INF
	charges += 1
	charge_start = global_position
	last_wall = NO_WALL
	# Il primo passo della carica scava subito.
	_furrow_travel = FURROW_STEP_M
	_furrow_debris_left = 0.0
	_charge_stall = 0.0
	_hit_this_charge.clear()
	_aim_strip.visible = false
	var target := charge_start + charge_direction * charge_length
	print("PROTOTYPE01_DRILLER_CHARGE n=%d dir=(%.2f, %.2f)" % [charges, charge_direction.x, charge_direction.z])
	charge_started.emit(target)


func _tick_charge(delta: float) -> void:
	var before := global_position
	rotation.y = atan2(-charge_direction.x, -charge_direction.z)
	var planar := Vector3(velocity.x, 0.0, velocity.z).move_toward(charge_direction * charge_speed, ACCELERATION * delta)
	velocity = Vector3(planar.x, 0.0 if is_on_floor() else velocity.y - 9.8 * delta, planar.z)
	move_and_slide()
	var pos := global_position
	var tip := pos + charge_direction * BIT_REACH
	# L'argine si cerca davanti al pennello del solco, altrimenti il solco lo eroderebbe
	# prima che la punta lo tocchi.
	var wall: Variant = terrain_field.bump_along(pos + charge_direction * BODY_RADIUS,
		tip + charge_direction * (FURROW_RADIUS + 0.6), wall_min_delta_m)
	if wall != null:
		_break_wall(Vector3((wall as Vector3).x, 0.0, (wall as Vector3).z))
		return
	# Solco: la punta scava fino a furrow_depth_m sotto la base, mai oltre e mai in su
	# (un fossato del giocatore piu profondo resta com'e).
	_furrow_travel += Vector2(velocity.x, velocity.z).length() * delta
	_furrow_debris_left -= delta
	if _furrow_travel >= FURROW_STEP_M and terrain_field.height_at(tip) > terrain_field.base_height_at(tip) - furrow_depth_m + 0.05:
		var volume := terrain_field.dig_to_base_offset(Vector3(tip.x, 0.0, tip.z), FURROW_RADIUS, furrow_depth_m)
		if volume < -0.01:
			furrow_length_m += _furrow_travel
			if _furrow_debris_left <= 0.0:
				_furrow_debris_left = FURROW_DEBRIS_SECONDS
				DebrisBurst.spawn(get_parent(), Vector3(tip.x, terrain_field.height_at(tip) + 0.3, tip.z), EARTH_COLOR, 6, 3.0, 0.16)
			furrowed.emit(Vector3(tip.x, 0.0, tip.z))
		_furrow_travel = 0.0
	_hit_in_the_way(player, true)
	# Una macchina guasta resta dov'e: i nemici la ignorano (spec D-093, Sezione 4).
	if caravan != null:
		for machine in caravan.machines:
			if not machine.is_broken():
				_hit_in_the_way(machine, true)
	# Fermata contro una rovina o il bordo (mai contro il terreno: quello lo scava).
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		# Il pavimento non conta: solo pareti (normale quasi orizzontale) che non sono celle.
		if collision.get_normal().y > 0.5:
			continue
		var collider := collision.get_collider() as Node
		if collider != null and collider != terrain_field.collision_body():
			_end_charge(&"blocked")
			return
	if _planar(pos - charge_start).length() >= charge_length:
		_end_charge(&"length")
		return
	# Ferma da piu di un secondo (fossato profondo, bordo): la carica finisce come contro una rovina.
	_charge_stall = _charge_stall + delta if _planar(global_position - before).length() < 0.02 else 0.0
	if _charge_stall > 1.0:
		_end_charge(&"blocked")


func _hit_in_the_way(body: Node3D, damages: bool) -> void:
	if body == null or _hit_this_charge.has(body):
		return
	var offset := _planar(body.global_position - global_position)
	if offset.length() > contact_radius + 0.4:
		return
	_hit_this_charge[body] = true
	var side := Vector3(-charge_direction.z, 0.0, charge_direction.x)
	if offset.dot(side) < 0.0:
		side = -side
	if damages and body is PlayerCharacter:
		(body as PlayerCharacter).take_damage(contact_damage)
	elif damages and body is Machine:
		(body as Machine).take_hit(contact_damage)
	var landing: Variant = _side_landing(body.global_position, side)
	if landing == null:
		return
	var lift := clampf(body.global_position.y - terrain_field.height_at(body.global_position), 0.3, 1.5)
	var at: Vector3 = landing
	at.y = terrain_field.height_at(at) + lift
	body.global_position = at
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	body.reset_physics_interpolation()


## Dove atterra la spinta laterale (audit E-11): prima il lato da cui il corpo gia pende,
## poi l'altro, a piena distanza e a meta; il punto deve stare nel campo, fuori dalle
## rovine, su suolo calpestabile e non molto piu alto di dove si trova (come la
## spinta del treno, `TrainEvent._push_out`). Null se tutto e murato: niente spinta.
func _side_landing(from: Vector3, side: Vector3) -> Variant:
	var half := terrain_field.half_extents()
	var ground := terrain_field.height_at(from)
	for direction: Vector3 in [side, -side]:
		for distance: float in [SIDE_PUSH, SIDE_PUSH * 0.5]:
			var probe := Vector3(from.x, 0.0, from.z) + direction * distance
			if absf(probe.x) > half.x - 1.0 or absf(probe.z) > half.y - 1.0:
				continue
			if path_field != null and not path_field.is_walkable(probe):
				continue
			if terrain_field.height_at(probe) - ground > PUSH_MAX_RISE_M:
				continue
			if terrain_field.slope_at(probe) > terrain_field.tuning.max_grade:
				continue
			return probe
	return null


## Un argine ferma la carica: il varco torna alla base (la terra si polverizza, niente
## rottami salvo quelli di una vena sotto), la Trivella resta stordita con la punta scoperta.
func _break_wall(hit: Vector3) -> void:
	# Il varco si apre sulla cima dell'argine, non sul fianco dove la punta lo ha toccato.
	var crest: Variant = terrain_field.highest_bump(hit + charge_direction * 1.0, BREACH_RADIUS, 0.0)
	var point := Vector3((crest as Vector3).x, 0.0, (crest as Vector3).z) if crest != null else hit
	var volume := terrain_field.level(point, BREACH_RADIUS, terrain_field.base_height_at(point), 1.0)
	walls_broken += 1
	last_wall = point
	DebrisBurst.spawn(get_parent(), point + Vector3(0.0, 0.6, 0.0), EARTH_COLOR, 14, 5.0, 0.22)
	if scrap_field != null and volume < 0.0:
		scrap_field.extract_from_veins(point, BREACH_RADIUS, -volume)
	print("PROTOTYPE01_DRILLER_WALL x=%.1f z=%.1f total=%d" % [point.x, point.z, walls_broken])
	wall_broken.emit(point)
	_end_charge(&"wall")
	phase = Phase.STUN
	phase_left = stun_seconds
	print("PROTOTYPE01_DRILLER_STUNNED seconds=%.1f" % stun_seconds)
	stunned.emit(stun_seconds)


func _end_charge(reason: StringName) -> void:
	velocity = Vector3.ZERO
	phase = Phase.REST
	phase_left = rest_seconds
	print("PROTOTYPE01_DRILLER_CHARGE_END reason=%s furrow_m=%.1f" % [reason, furrow_length_m])
	charge_ended.emit(reason)


# --- Movimento procedurale -------------------------------------------------------------

## La punta gira (accelera in mira, piena in carica, si ferma stordita), i cingoli
## vibrano in carica, stordita affonda il muso; barcollamento pesante se colpita.
func _animate(delta: float) -> void:
	_motion_time += delta
	var spin_target := 0.0
	match phase:
		Phase.AIM:
			spin_target = BIT_SPIN_MAX * (1.0 - phase_left / maxf(aim_seconds, 0.01))
		Phase.CHARGE:
			spin_target = BIT_SPIN_MAX
	_bit_spin = move_toward(_bit_spin, spin_target, BIT_SPIN_RATE * delta)
	_bit.rotate_object_local(Vector3.FORWARD, _bit_spin * delta)
	var moving := clampf(Vector2(velocity.x, velocity.z).length() / maxf(charge_speed, 0.01), 0.0, 1.0)
	_stun_weight = move_toward(_stun_weight, 1.0 if phase == Phase.STUN else 0.0, 6.0 * delta)
	var pitch := STUN_PITCH * _stun_weight
	var roll := sin(_motion_time * TAU * 5.0) * RUMBLE_ROLL * moving
	var rise := (0.5 + 0.5 * sin(_motion_time * TAU * RUMBLE_HZ)) * RUMBLE_HEIGHT * moving - STUN_SINK * _stun_weight
	var slide := 0.0
	if _stagger > 0.0:
		_stagger = maxf(_stagger - delta / HEAVY_STAGGER_SECONDS, 0.0)
		var hit := _stagger * _stagger
		slide += HEAVY_STAGGER_BACK * hit
		pitch += HEAVY_STAGGER_PITCH * hit
	var pose := ActorMotion.tilt_on_ground(RIG_GROUND, pitch, roll, TRACK_HALF_LENGTH, TRACK_HALF_WIDTH)
	pose.origin += Vector3(0.0, rise, slide)
	_rig.transform = pose
	_at_rest = false


func _reset_pose() -> void:
	_rig.transform = Transform3D.IDENTITY
	_at_rest = true


static func _planar(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
