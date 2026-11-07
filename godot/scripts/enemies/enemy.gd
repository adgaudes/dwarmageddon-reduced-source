class_name Enemy
extends CharacterBody3D
## "Rottamatore": nemico base dell'orda lenta (D-038). Costruito e guidato da
## EnemyDirector, che calcola la velocita di tutti in un solo passo; qui restano
## stato, aspetto e danni. Collide solo col mondo statico: le celle Raised lo
## fermano, gli altri nemici no (li separa lo sterzo del direttore).

signal died(enemy: Enemy)
## Arrivato al punto della commissione; emesso a ogni passo finche resta li.
signal errand_reached(enemy: Enemy)

const HEIGHT := 1.0
const RADIUS := 0.32
const FLASH_SECONDS := 0.08
const CARGO_SIZE := 0.36

# --- Movimento procedurale (ActorMotion): solo sul visual `_body`, mai sul corpo fisico.
## Sotto questa velocita planare (m/s) il rottamatore e fermo: niente andatura.
const GAIT_MIN_SPEED := 0.25
## Radianti di fase per metro percorso: l'andatura segue la strada fatta, non il tempo.
const GAIT_RADIANS_PER_METER := 6.5
## Rollio massimo (rad) dell'andatura a papera, alternato sui due cingoli.
const GAIT_ROLL := 0.11
## Saltello (m) in piu a ogni mezzo passo, oltre al sollevamento dovuto al rollio.
const GAIT_BOB := 0.025
## Velocita (1/s) con cui l'andatura entra ed esce quando parte o si ferma.
const GAIT_BLEND_RATE := 8.0
## Sfasamento fra un rottamatore e il successivo (angolo aureo): l'orda non marcia a tempo.
const GAIT_PHASE_STEP := 2.399963
## Mezza carreggiata e mezza lunghezza (m) dell'impronta: il visual si alza di
## |angolo| x braccio, cosi inclinandosi non entra nel terreno.
const FOOTPRINT_HALF_WIDTH := 0.3
const FOOTPRINT_HALF_LENGTH := 0.4
## Affondo a contatto col giocatore: durata dello scatto e pausa prima del successivo (s).
const LUNGE_SECONDS := 0.2
const LUNGE_PAUSE := 0.35
## Affondo: avanzamento (m) e beccheggio in avanti (rad) al culmine.
const LUNGE_REACH := 0.2
const LUNGE_PITCH := 0.2
## Barcollamento quando e colpito: durata (s), arretramento (m), muso in su (rad).
const STAGGER_SECONDS := 0.2
const STAGGER_BACK := 0.16
const STAGGER_PITCH := 0.28

## Contatore per lo sfasamento dell'andatura: deterministico, non consuma l'rng dell'orda.
static var _gait_serial := 0


## Riparte da zero a ogni run (R-08): stesso seme, stesse fasi, catture confrontabili.
static func reset_gait_serial() -> void:
	_gait_serial = 0

var health := 2
var max_health := 2
var is_dead := false
## Ricarica del danno da terrapieno spinato.
var spike_cooldown := 0.0
## Si guida da solo con drive() (boss): l'EnemyDirector non lo sterza ne lo riporta sull'anello.
var self_driven := false
## Moltiplicatore della velocita dell'orda: i rottamatori veloci (D-056) ne hanno piu di 1.
var speed_scale := 1.0
## Tipo (scavenger, runner, hopper): per test, simulazioni e log.
var kind: StringName = &"scavenger"
## Pendenza massima percorribile (rilievo continuo); `floor_max_angle` ne deriva.
var max_grade := 0.8
## Secondi fermo contro il terreno e stato del rosicchio.
var stuck_seconds := 0.0
var gnaw_left := 0.0
var is_gnawing := false
## Raggio in piu rispetto a un rottamatore, per i colpi (corpi grandi).
var hit_radius_bonus := 0.0
## Secondi di stordimento (Martello, Betoniera: D-092): il direttore non lo fa camminare.
var stun_left := 0.0
## Rallentamento (Roveto, triboli, Pale da scavo): velocita x `slow_factor` finche `slow_left > 0`.
var slow_left := 0.0
var slow_factor := 1.0
## Deriva planare in m/s (calamite, campi): il direttore la somma alla velocita del passo e
## poi la azzera; chi la vuole la rimette a ogni passo. I boss la ignorano.
var drift := Vector3.ZERO
## Commissione (D-045): il direttore lo porta a `errand_point` invece che dal giocatore.
var has_errand := false
var errand_point := Vector3.ZERO
## Porta un rottame sulla schiena (visibile): se muore lo lascia cadere.
var carrying_scrap := false
var _cargo: MeshInstance3D
var _flash_left := 0.0
var _body: MeshInstance3D
var _base_material: Material
var _flash_material: Material
## Stato del movimento procedurale (vedi le costanti GAIT_*, LUNGE_*, STAGGER_*).
var _body_rest := Transform3D.IDENTITY
var _gait_phase := 0.0
var _gait_weight := 0.0
var _lunge_left := 0.0
## 1 appena colpito, scende a 0 in STAGGER_SECONDS.
var _stagger := 0.0
var _at_rest := true


## Mesh e materiali condivisi da tutta l'orda. Il modello (`scavenger`) ha una sola
## superficie: scafo, visiera luminosa e chele sono colori di vertice.
func setup(hp: int, body_mesh: Mesh, base_material: Material, flash_material: Material) -> void:
	health = hp
	max_health = hp
	collision_layer = 16
	collision_mask = 1
	floor_max_angle = atan(max_grade)
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	_base_material = base_material
	_flash_material = flash_material
	_body = MeshInstance3D.new()
	_body.mesh = body_mesh
	ActorModel.dress(_body, base_material)
	# Origine del modello a terra, quella del nemico al centro della capsula.
	_body.position.y = -HEIGHT * 0.5
	add_child(_body)
	_body_rest = _body.transform
	_gait_serial += 1
	_gait_phase = fmod(_gait_serial * GAIT_PHASE_STEP, TAU)


## Il materiale "vernice" di questo nemico (base, veloce o saltatore).
func paint_material() -> Material:
	return _base_material


## Restituisce true se il colpo lo uccide.
func take_damage(amount: int) -> bool:
	if is_dead:
		return false
	health -= amount
	_flash_left = FLASH_SECONDS
	_body.material_override = _flash_material
	_stagger = 1.0
	if health <= 0:
		is_dead = true
		died.emit(self)
		return true
	return false


func set_errand(point: Vector3) -> void:
	has_errand = true
	errand_point = point


func clear_errand() -> void:
	has_errand = false


func set_carrying(value: bool) -> void:
	carrying_scrap = value
	if value and _cargo == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * CARGO_SIZE
		var material := StandardMaterial3D.new()
		material.albedo_color = ScrapField.SCRAP_COLOR.linear_to_srgb()
		_cargo = MeshInstance3D.new()
		_cargo.mesh = mesh
		_cargo.material_override = material
		# Sul portapacchi del modello (0,66 m da terra). Figlio del visual: ne segue
		# andatura e barcollamento invece di restare sospeso sopra.
		_cargo.position = Vector3(0.0, 0.35, 0.06) - _body_rest.origin
		_body.add_child(_cargo)
	if _cargo != null:
		_cargo.visible = value


## Passo fisico dei nemici `self_driven`; gli altri li muove il direttore.
func drive(_delta: float) -> void:
	pass


## Ferma il nemico per [param seconds] (il piu lungo vince), subito: la velocita si azzera, ma
## una spinta data dopo (Martello) resta. I boss (`self_driven`) non si stordiscono.
func stun(seconds: float) -> void:
	if self_driven:
		return
	stun_left = maxf(stun_left, seconds)
	velocity.x = 0.0
	velocity.z = 0.0


## Rallenta il nemico a [param factor] (0..1) per [param seconds]; fra piu rallentamenti
## insieme vale il piu forte. I boss (`self_driven`) non rallentano.
func slow(factor: float, seconds: float) -> void:
	if self_driven:
		return
	slow_factor = minf(slow_factor, factor) if slow_left > 0.0 else factor
	slow_left = maxf(slow_left, seconds)


func tick_visuals(delta: float) -> void:
	spike_cooldown = maxf(spike_cooldown - delta, 0.0)
	stun_left = maxf(stun_left - delta, 0.0)
	if slow_left > 0.0:
		slow_left = maxf(slow_left - delta, 0.0)
		if slow_left <= 0.0:
			slow_factor = 1.0
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			ActorModel.dress(_body, _base_material)
	if ActorMotion.enabled:
		_animate(delta)
	elif not _at_rest:
		_reset_pose()


## Il giocatore e a portata di contatto (lo dice l'EnemyDirector): parte un affondo,
## solo visivo, se il precedente e finito.
func notify_contact() -> void:
	if _lunge_left <= 0.0:
		_lunge_left = LUNGE_SECONDS + LUNGE_PAUSE


## Fase dell'andatura (rad), sfasata per ogni rottamatore.
func gait_phase() -> float:
	return _gait_phase


## Andatura, affondo e barcollamento: pochi float e una sola scrittura sul visual.
## Chiamata per ogni nemico a ogni passo fisico: niente allocazioni, niente tween.
func _animate(delta: float) -> void:
	var speed_sq := velocity.x * velocity.x + velocity.z * velocity.z
	if speed_sq > GAIT_MIN_SPEED * GAIT_MIN_SPEED:
		_gait_phase += sqrt(speed_sq) * GAIT_RADIANS_PER_METER * delta
		_gait_weight = minf(_gait_weight + GAIT_BLEND_RATE * delta, 1.0)
	elif _gait_weight > 0.0:
		_gait_weight = maxf(_gait_weight - GAIT_BLEND_RATE * delta, 0.0)
	elif _stagger <= 0.0 and _lunge_left <= 0.0:
		if not _at_rest:
			_reset_pose()
		return
	var swing := sin(_gait_phase)
	var roll := swing * GAIT_ROLL * _gait_weight
	var pitch := 0.0
	var slide := 0.0
	if _stagger > 0.0:
		_stagger = maxf(_stagger - delta / STAGGER_SECONDS, 0.0)
		var hit := _stagger * _stagger
		slide = STAGGER_BACK * hit
		pitch = STAGGER_PITCH * hit
	if _lunge_left > 0.0:
		_lunge_left -= delta
		if _lunge_left > LUNGE_PAUSE:
			var thrust := sin(PI * (_lunge_left - LUNGE_PAUSE) / LUNGE_SECONDS)
			slide -= LUNGE_REACH * thrust
			pitch -= LUNGE_PITCH * thrust
	var lift := absf(roll) * FOOTPRINT_HALF_WIDTH + absf(pitch) * FOOTPRINT_HALF_LENGTH 		+ absf(swing) * GAIT_BOB * _gait_weight
	_body.transform = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)),
		Vector3(_body_rest.origin.x, _body_rest.origin.y + lift, _body_rest.origin.z + slide))
	_at_rest = false


func _reset_pose() -> void:
	_body.transform = _body_rest
	_at_rest = true


## Corpo sopra il pavimento: l'origine e al centro della capsula.
static func spawn_height() -> float:
	return HEIGHT * 0.5 + 0.02


## Quota del centro del corpo sopra il pavimento; i boss, piu alti, la ridefiniscono.
func spawn_center_height() -> float:
	return spawn_height()


## Colore dei frammenti alla morte; i boss lo ridefiniscono con la propria vernice.
func death_debris_color() -> Color:
	return Color(0.42, 0.1, 0.05)
