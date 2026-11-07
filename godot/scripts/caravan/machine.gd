class_name Machine
extends CharacterBody3D
## Macchina della carovana (spec D-093, Sezioni 1 e 4): il carrello del compagno di oggi
## (D-032) con i moduli come nodi figli (piu d'uno dal piano B, pezzi impilati sul pianale,
## taglia dal numero dei moduli). Autonoma e non pilotabile: tiene il suo posto nel grappolo
## attorno al giocatore, o va dove un modulo la chiama (il Cassone verso i rottami). Senza
## carovana o senza giocatore resta ferma.
## Danni (Sezione 4): rottamatori e boss la colpiscono a contatto (`take_hit`, poi `hit_cooldown`
## d'immunita); a 0 PV si guasta (ferma, moduli spenti, fumo, punto esclamativo, anello rosso)
## finche non la si ripara (`repair`); con poca vita si ritira dal lato opposto al nemico piu
## vicino; senza colpi la vita risale. Troppo lontana dal giocatore, o incastrata, torna al posto.

enum State { OK, RETREAT, BROKEN }

signal state_changed(state: int)
## Un colpo andato a segno: [param amount] PV tolti.
signal damaged(amount: int)

## Lineari: carrozzeria chiara, striscia gialla anteriore, rottami color ruggine.
const BODY_COLOR := Color(0.75, 0.75, 0.68)
const STRIPE_COLOR := Color(1.0, 0.78, 0.05)
const CARGO_SIZE := 0.22
## Layer visivo delle mesh della macchina (solo il 2): anelli e pennello, decal sul layer 1,
## non le dipingono (scelta 12 di D-093).
const VISUAL_LAYER := 2

# --- Movimento procedurale (ActorMotion): un "telaio" calcolato a ogni passo e applicato
# a modello, cubetti e pezzi montati (restano figli diretti: chi li cerca per nome li trova).
## Punto d'appoggio a terra del telaio, nello spazio della macchina (origine al centro del box).
const RIG_GROUND := Vector3(0.0, -0.3, 0.0)
## Mezzo passo e mezza carreggiata (m): inclinandosi il telaio si alza di |angolo| x braccio.
const WHEEL_HALF_LENGTH := 0.42
const WHEEL_HALF_WIDTH := 0.4
## Inclinazione (rad) per ogni m/s^2 di accelerazione: muso in su partendo, giu frenando,
## rollio verso l'esterno quando scarta di lato. Limite in rad.
const TILT_PER_ACCELERATION := 0.005
const TILT_MAX := 0.12
## Rollio in curva (rad) per ogni rad/s di sterzata a piena velocita.
const TURN_ROLL := 0.02
## Velocita (1/s) con cui l'inclinazione insegue il bersaglio.
const TILT_RATE := 9.0
## Sospensioni: molla (rigidezza 1/s^2, smorzamento 1/s). Il telaio salta in su di
## BOUNCE_KICK_* (m/s) quando cambia il carico o la velocita cambia di colpo; non scende sotto il riposo.
const BOUNCE_STIFFNESS := 180.0
const BOUNCE_DAMPING := 11.0
const BOUNCE_KICK_CARGO := 0.75
const BOUNCE_KICK_PER_SPEED_CHANGE := 0.2
const BOUNCE_MAX := 0.08
## Sobbalzi della strada in marcia: radianti per metro e altezza (m) a piena velocita.
const ROAD_RADIANS_PER_METER := 7.0
const ROAD_BUMP := 0.015
## Tremito del motore da fermo: frequenza (Hz), rollio (rad) e sobbalzo (m). Sparisce in marcia.
const SHIVER_HZ := 13.0
const SHIVER_ROLL := 0.014
const SHIVER_HEIGHT := 0.008
## Cubetti che ballano quando il carico cambia: durata (s), frequenza (Hz), salto (m), rotazione (rad).
const CARGO_WOBBLE_SECONDS := 0.5
const CARGO_WOBBLE_HZ := 4.5
const CARGO_WOBBLE_HOP := 0.07
const CARGO_WOBBLE_TWIST := 0.3

# --- Guinzaglio e ritirata.
## Incastrata: in una finestra di STUCK_WINDOW secondi si sposta in tutto meno di
## STUCK_SPEED x finestra (m) restando a piu di STUCK_GOAL_DISTANCE (m) dalla meta finale;
## oppure sta su un punto non aperto per la carovana (`Caravan.is_open_point`: buca scavata,
## da li il giocatore non si raggiunge), a qualunque distanza dalla meta.
const STUCK_GOAL_DISTANCE := 2.0
const STUCK_SPEED := 0.5
const STUCK_WINDOW := 0.5
## In ritirata il nemico piu vicino si ricerca al piu ogni tanti secondi.
const THREAT_REFRESH := 0.25

# --- Segni dello stato: anello a terra, fumo e punto esclamativo del guasto.
## Scatola del Decal dell'anello (raggio 0,75 m = meta del lato), centrata sul suolo.
const RING_SIZE := Vector3(1.5, 0.6, 1.5)
## Lineare: fumo grigio medio della macchina guasta, leggibile anche sull'asfalto scuro
## (revisione finale, A2; prima 0,05, invisibile dalla camera di gioco). Sbuffi di raggio
## SMOKE_RADIUS (m) e opacita SMOKE_ALPHA.
const SMOKE_COLOR := Color(0.4, 0.4, 0.4)
const SMOKE_RADIUS := 0.28
const SMOKE_ALPHA := 0.7
## Altezza del punto esclamativo sull'origine della macchina.
const BROKEN_MARK_HEIGHT := 1.5
## Fumo: punto di partenza degli sbuffi e raggio della sfera d'emissione; dimensione in pixel
## del punto esclamativo. Valori a scala 1 (macchina piccola).
const SMOKE_POSITION := Vector3(0.0, 0.45, 0.1)
const SMOKE_EMISSION_RADIUS := 0.15
const BROKEN_MARK_PIXEL := 0.006

# --- Piu moduli (piano B): pezzi impilati e taglia.
## Scarto del pezzo del modulo i-esimo rispetto alla posizione del suo `build_part`: il primo
## dove sta, gli altri a destra e sinistra e via via piu in alto sul pianale.
const PART_STACK: Array[Vector3] = [Vector3(0, 0, 0), Vector3(0.32, 0.3, 0), Vector3(-0.32, 0.3, 0),
	Vector3(0.32, 0.6, 0), Vector3(-0.32, 0.6, 0), Vector3(0, 0.9, 0), Vector3(0, 1.2, 0)]

var caravan: Caravan
var modules: Array[MachineModule] = []
## Taglia, forza dei moduli, fattore della velocita massima e scala del modello: dal numero dei
## moduli (MachineFusion), rifatti a ogni modulo aggiunto o tolto.
var size := MachineFusion.Size.SMALL
var power := 1.0
var speed_factor := 1.0
var model_scale := 1.0
## Punti vita del telaio (`chassis_health`, li imposta la carovana).
var max_health := 6
var health := 6
var state := State.OK
## Indice del posto nel grappolo (CaravanTuning.cluster_slots).
var slot := 0
## Rottamatori travolti finora (test e benchmark).
var trampled := 0
## Vero col giocatore a bordo (piano C): travolge di `pilot_trample_damage`.
var piloted := false

var _cargo: Array[MeshInstance3D] = []
var _cargo_mesh: BoxMesh
var _cargo_material: StandardMaterial3D
## Stato del movimento procedurale (vedi le costanti RIG_*, TILT_*, BOUNCE_*, SHIVER_*, CARGO_WOBBLE_*).
var _cargo_rest: Array[Vector3] = []
var _parts: Array[Node3D] = []
## Posa di riposo di ogni pezzo (impilata, a scala 1) e posa di montaggio (come l'ha costruita
## il modulo o chi l'ha montato).
var _part_rest: Array[Transform3D] = []
var _part_mount: Array[Transform3D] = []
## Il modulo che ha montato ogni pezzo (impilato secondo il suo indice in `modules`).
var _part_owner: Dictionary[Node3D, MachineModule] = {}
## Scala del telaio attorno a RIG_GROUND (`model_scale`): fra telaio e pose di riposo.
var _scale_rig := Transform3D.IDENTITY
## Combinazioni dei moduli (MachineCatalog.combos_of), rifatte a ogni modulo aggiunto o tolto.
var _combos: Array[StringName] = []
var _model_rest := Transform3D.IDENTITY
var _motion_time := 0.0
var _road_phase := 0.0
var _last_local_velocity := Vector3.ZERO
var _last_yaw := 0.0
var _tilt_pitch := 0.0
var _tilt_roll := 0.0
## Sospensioni: (altezza, velocita verticale).
var _bounce := Vector2.ZERO
## 1 appena il carico cambia, scende a 0 in CARGO_WOBBLE_SECONDS.
var _cargo_wobble := 0.0
var _shown_carried := -1
var _motion_at_rest := true
## Materiali propri della macchina (la vernice). Li tiene anche la macchina: se li tenesse
## solo la superficie del modello, liberando il modello verrebbero liberati prima della sua
## istanza di resa e il server segnalerebbe `Parameter "material" is null` (verificato in
## headless su una macchina senza cubetti; anche il compagno senza cubetti lo fa).
var _own_materials: Array[Material] = []

# --- Danni e stato.
## Secondi d'immunita dopo l'ultimo colpo (`hit_cooldown`) e d'invulnerabilita concessa.
var _hit_cooldown_left := 0.0
var _invulnerable_left := 0.0
## Frazione di PV dei colpi ridotti (Esca blindata) non ancora tolta: due mezzi colpi fanno 1 PV.
var _damage_carry := 0.0
## Secondi senza colpi da danneggiata (fermi a 0 da guasta o a vita piena) e PV rigenerati da allora.
var _since_hit := 0.0
var _regen_given := 0
## Secondi prima di poter travolgere di nuovo (`trample_interval` dopo l'ultimo colpo).
var _trample_left := 0.0
## Secondi di ritirata forzata ancora da fare (`force_retreat`, piano C).
var _forced_retreat_left := 0.0

# --- Guinzaglio e ritirata.
## Meta finale dell'ultimo `_choose_destination` (ritirata, modulo o posto; mai un waypoint).
var _goal_point := Vector3.ZERO
## Secondi d'incastro: il maggiore fra `_slow_time` (finestre quasi ferme lontano dalla meta) e
## `_trapped_time` (passi di fila su un punto non aperto). A `stuck_seconds` si torna al posto.
var _stuck_time := 0.0
var _slow_time := 0.0
var _trapped_time := 0.0
## Finestra in corso: posizione all'inizio e secondi trascorsi.
var _window_start := Vector3.INF
var _window_time := 0.0
var _threat_left := 0.0
## Dal nemico piu vicino verso il giocatore (piano XZ, normalizzata); ZERO senza minaccia.
var _threat_direction := Vector3.ZERO

# --- Segni dello stato (figli diretti, fuori dal telaio).
var _ring: Decal
var _smoke: CPUParticles3D
## Dopo la riparazione: secondi finche gli sbuffi gia partiti non sono spariti (poi il fumo si
## nasconde).
var _smoke_left := 0.0
var _broken_mark: Label3D
## Sbuffo del fumo, condiviso da tutte le macchine (con materiale, crescita e sfumatura): mai
## una mesh o un materiale per macchina.
static var _smoke_mesh: SphereMesh
static var _smoke_growth: Curve
static var _smoke_fade: Gradient

@onready var _model: Node3D = $Model


func _ready() -> void:
	floor_max_angle = atan(0.8)
	_build_visuals()


## Aggiunge un modulo: figlio della macchina, col suo pezzo visibile se ne ha uno (il secondo
## dello stesso tipo si chiama `TurretModule2`, `TurretPart2`), poi ricostruisce taglia, vita e
## scala. I servizi glieli passa la carovana subito dopo.
func add_module(module: MachineModule) -> void:
	module.machine = self
	module.caravan = caravan
	var type_name := String(module.module_id).capitalize()
	if module.name.is_empty() or module.name.begins_with("@"):
		module.name = _free_child_name("%sModule" % type_name)
	modules.append(module)
	add_child(module)
	var part := module.build_part()
	if part != null:
		mount_part(_free_child_name("%sPart" % type_name), part)
		_part_owner[part] = module
	_rebuild()


## Toglie [param module]: fuori dall'albero subito (Calamita e Faro si liberano ora in
## `_exit_tree`), pezzo tolto, poi la ricostruzione. Il modulo viene liberato.
func remove_module(module: MachineModule) -> void:
	var index := modules.find(module)
	if index < 0:
		return
	modules.remove_at(index)
	for i in range(_parts.size() - 1, -1, -1):
		var part := _parts[i]
		if _part_owner.get(part) == module:
			_part_owner.erase(part)
			_parts.remove_at(i)
			_part_rest.remove_at(i)
			_part_mount.remove_at(i)
			remove_child(part)
			part.queue_free()
	remove_child(module)
	module.queue_free()
	_rebuild()


## Meta finale dell'ultimo `destination()` (rottame, punto di ritirata o posto nel grappolo).
func goal_point() -> Vector3:
	return _goal_point


## Tipi dei moduli, nell'ordine di montaggio.
func module_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for each in modules:
		ids.append(each.module_id)
	return ids


## Combinazioni dei moduli della macchina (anche da guasta: vedi `has_combo`).
func combos() -> Array[StringName]:
	return _combos


## Vero se la combinazione [param id] vale ora: i suoi moduli sulla macchina, non guasta.
func has_combo(id: StringName) -> bool:
	return not is_broken() and _combos.has(id)


## Velocita massima: quella della carovana per il fattore della taglia.
func top_speed() -> float:
	return caravan.tuning.max_speed * caravan.speed_scale * speed_factor


## Raggio di contatto della carovana in scala con la macchina.
func contact_reach() -> float:
	var tuning := _tuning()
	return tuning.contact_radius * model_scale if tuning != null else 0.0


func has_module(id: StringName) -> bool:
	return module(id) != null


func module(id: StringName) -> MachineModule:
	for candidate in modules:
		if candidate.module_id == id:
			return candidate
	return null


func cargo() -> CargoModule:
	return module(&"cargo") as CargoModule


## Tipo del primo modulo (icona e colore nel HUD), o vuoto.
func primary_module_id() -> StringName:
	return modules[0].module_id if not modules.is_empty() else &""


func is_broken() -> bool:
	return state == State.BROKEN


# --- Danni e stato ---------------------------------------------------------------------------

## Colpo da contatto (rottamatore, boss, carica della Trivella): falso, senza effetti, se la
## macchina e guasta, nell'immunita del colpo precedente o invulnerabile; altrimenti toglie
## [param amount] PV per `hit_scale` (la parte intera, il resto si somma al colpo dopo), apre
## `hit_cooldown` d'immunita e riparte da zero il tempo senza colpi. `damaged` solo se toglie PV.
func take_hit(amount: int) -> bool:
	if not accepts_contact() or _invulnerable_left > 0.0:
		return false
	var scaled := amount * hit_scale() + _damage_carry
	var dealt := int(scaled)
	_damage_carry = scaled - dealt
	health = maxi(health - dealt, 0)
	var tuning := _tuning()
	_hit_cooldown_left = tuning.hit_cooldown if tuning != null else 0.0
	_since_hit = 0.0
	_regen_given = 0
	print("PROTOTYPE01_MACHINE_HIT module=%s health=%d" % [primary_module_id(), health])
	if dealt > 0:
		damaged.emit(dealt)
	_update_state()
	return true


## Scala dei colpi subiti: `combo_hit_scale` con l'Esca blindata mentre la sua Sirena attira
## (scelta 7 di D-093), altrimenti 1.
func hit_scale() -> float:
	if not has_combo(&"armored_bait"):
		return 1.0
	var siren := module(&"siren") as SirenModule
	if siren == null or not siren.is_attracting():
		return 1.0
	return caravan.tuning.combo_hit_scale


## Vero se un contatto puo colpire ora: non guasta e fuori dall'immunita del colpo precedente.
## L'invulnerabilita concessa non conta qui (il direttore prova lo stesso il contatto, che non
## passa): la scansione costa uguale con le macchine protette di benchmark e catture.
func accepts_contact() -> bool:
	return not is_broken() and _hit_cooldown_left <= 0.0


## Vero se ora travolge (scelta 6 di D-093): da `trample_min_size` in su, non guasta (anche
## immune o in ritirata), in moto nel piano ad almeno `trample_min_speed` m/s e fuori
## dall'attesa del colpo precedente. La velocita e quella del corpo, non lo spostamento.
func can_trample() -> bool:
	var tuning := _tuning()
	if tuning == null or is_broken() or size < tuning.trample_min_size or _trample_left > 0.0:
		return false
	return Vector2(velocity.x, velocity.z).length() >= tuning.trample_min_speed


## Il direttore ha travolto almeno un rottamatore: si riprova fra `trample_interval` secondi.
func trample_done() -> void:
	var tuning := _tuning()
	_trample_left = tuning.trample_interval if tuning != null else 0.0


## Danno del travolgere a ogni rottamatore in contatto: `pilot_trample_damage` col giocatore a
## bordo (`piloted`), altrimenti `trample_damage`.
func trample_damage() -> int:
	var tuning := _tuning()
	if tuning == null:
		return 0
	return tuning.pilot_trample_damage if piloted else tuning.trample_damage


## Nessun colpo passa per almeno [param seconds] (benchmark, catture, test).
func grant_invulnerability(seconds: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left, seconds)


## Vita in piu fino al massimo; niente su una macchina guasta (la rimette in moto `repair`).
func heal(amount: int) -> void:
	if is_broken():
		return
	health = mini(health + amount, max_health)
	_update_state()


## Da guasta riparte con `ceil(max_health x fraction)` PV (almeno 1) e i moduli riaccesi; su una
## macchina non guasta non fa nulla.
func repair(fraction: float) -> void:
	if not is_broken():
		return
	health = clampi(ceili(max_health * fraction), 1, max_health)
	_damage_carry = 0.0
	_since_hit = 0.0
	_regen_given = 0
	_set_state(State.OK)
	_update_state()
	print("PROTOTYPE01_MACHINE_REPAIRED module=%s" % primary_module_id())


## Guasto immediato (piano C: il treno): vita a 0 e stato BROKEN come dopo un colpo mortale, ma
## senza `damaged` ne immunita; su una macchina gia guasta non fa nulla. Il marker del treno lo
## stampa il treno.
func break_down() -> void:
	if is_broken():
		return
	health = 0
	_update_state()


## Ritirata per almeno [param seconds] qualunque sia la vita (piano C: il pilota sbalzato); una
## macchina guasta resta guasta. Scaduta, la regola della vita riprende da "in ordine".
func force_retreat(seconds: float) -> void:
	_forced_retreat_left = maxf(_forced_retreat_left, seconds)
	_update_state()


## A ogni passo, anche senza giocatore: immunita, invulnerabilita, attesa del travolgere e
## ritirata forzata scadono, lo stato segue la vita, poi la rigenerazione (da danneggiata e non
## guasta: +1 PV dopo `regen_delay` secondi senza colpi, poi ogni `regen_interval`).
func _tick_health(delta: float) -> void:
	_hit_cooldown_left = maxf(_hit_cooldown_left - delta, 0.0)
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_trample_left = maxf(_trample_left - delta, 0.0)
	if _forced_retreat_left > 0.0:
		_forced_retreat_left = maxf(_forced_retreat_left - delta, 0.0)
		# Scaduta: si riparte da "in ordine" senza l'isteresi della ritirata (a meta vita non si
		# resta in ritirata fino a `retreat_until`); sotto `retreat_below` ci torna `_update_state`.
		var rules := _tuning()
		if _forced_retreat_left <= 0.0 and state == State.RETREAT and rules != null \
				and float(health) / maxi(max_health, 1) >= rules.retreat_below:
			_set_state(State.OK)
	if _smoke_left > 0.0:
		_smoke_left -= delta
		if _smoke_left <= 0.0 and not is_broken():
			_smoke.visible = false
	_update_state()
	if is_broken() or health >= max_health:
		_since_hit = 0.0
		_regen_given = 0
		return
	var tuning := caravan.tuning
	_since_hit += delta
	if _since_hit >= tuning.regen_delay + tuning.regen_interval * _regen_given:
		_regen_given += 1
		heal(1)


## Stato dalla vita: a 0 PV guasta (ne esce solo con `repair`); in ritirata forzata ritirata;
## sotto `retreat_below` del massimo in ritirata, sopra `retreat_until` di nuovo in ordine.
func _update_state() -> void:
	if state == State.BROKEN:
		return
	if health <= 0:
		_set_state(State.BROKEN)
		return
	if _forced_retreat_left > 0.0:
		_set_state(State.RETREAT)
		return
	var tuning := _tuning()
	if tuning == null:
		return
	var fraction := float(health) / maxi(max_health, 1)
	if state == State.OK and fraction < tuning.retreat_below:
		_set_state(State.RETREAT)
	elif state == State.RETREAT and fraction > tuning.retreat_until:
		_set_state(State.OK)


## Unico punto in cui lo stato cambia: guasta spegne i moduli e mostra fumo e punto esclamativo,
## riparata li riaccende; l'anello cambia colore, guinzaglio e ritirata ripartono da zero, e la
## carovana avvisa (`changed`: HUD, luci dei Faro).
func _set_state(next: State) -> void:
	if next == state:
		return
	var was_broken := state == State.BROKEN
	state = next
	if next == State.BROKEN:
		for each in modules:
			each.set_active(false)
		if _smoke != null:
			_smoke.visible = true
			_smoke.emitting = true
			_smoke_left = 0.0
			_broken_mark.visible = true
		print("PROTOTYPE01_MACHINE_BROKEN module=%s" % primary_module_id())
	elif was_broken:
		for each in modules:
			each.set_active(true)
		if _smoke != null:
			_smoke.emitting = false
			_smoke_left = _smoke.lifetime
			_broken_mark.visible = false
	_refresh_ring()
	_reset_stuck()
	_threat_left = 0.0
	_threat_direction = Vector3.ZERO
	state_changed.emit(state)
	if caravan != null:
		caravan.changed.emit()


func _tuning() -> CaravanTuning:
	return caravan.tuning if caravan != null else null


# --- Passo: meta, guinzaglio e ritirata ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if caravan == null:
		return
	_tick_health(delta)
	if caravan.player == null:
		return
	if is_broken():
		_stand_broken(delta)
		return
	var tuning := caravan.tuning
	if planar_distance(global_position, caravan.player.global_position) > tuning.leash_distance \
			or _stuck_time >= tuning.stuck_seconds:
		if _return_to_slot():
			return
	_tick_threat(delta)
	var top := top_speed()
	var destination := _choose_destination()
	var to_destination := destination - global_position
	to_destination.y = 0.0
	var desired := Vector3.ZERO
	var distance := to_destination.length()
	if distance > tuning.arrive_radius:
		# Rallenta in arrivo per non oscillare attorno al punto.
		desired = to_destination / distance * minf(top, distance * 3.0)
	var planar := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, tuning.acceleration * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity += get_gravity() * delta
	move_and_slide()
	_track_stuck(delta)

	if planar.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(-planar.x, -planar.z), minf(delta * 10.0, 1.0))

	# Moduli prima del telaio, come la raccolta del compagno: un carico che cambia fa
	# saltare le sospensioni nello stesso passo.
	for each in modules:
		if each.active:
			each.tick(delta)
	_update_motion(delta)


## Meta del passo. Guasta: nessuna (resta dov'e). In ritirata con un nemico vicino: il punto di
## ritirata, senza chiedere ai moduli. Altrimenti, in ordine: la prima chiesta da un modulo
## attivo (il Cassone verso un rottame; non in ritirata); lontano dal giocatore il campo di
## percorso, che aggira le mura; il posto nel grappolo. Annota in `_goal_point` la meta finale
## (mai il waypoint): la guarda il controllo dell'incastro.
func _choose_destination() -> Vector3:
	if is_broken():
		return global_position
	if state == State.RETREAT:
		if not _threat_direction.is_zero_approx():
			_goal_point = _retreat_point()
			return _goal_point
	else:
		for each in modules:
			if each.active:
				var wanted: Variant = each.wanted_destination()
				if wanted != null:
					_goal_point = wanted
					return wanted
	_goal_point = caravan.slot_target(self)
	var path_field := caravan.path_field
	if path_field != null and path_field.is_ready() \
			and planar_distance(global_position, caravan.player.global_position) > caravan.slot_of(slot).y + caravan.tuning.path_margin:
		var waypoint: Variant = path_field.next_waypoint(global_position)
		if waypoint != null:
			return waypoint
	return _goal_point


## Guasta: ferma sul piano (resta la gravita); niente meta, rotazione, moduli ne guinzaglio.
func _stand_broken(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity += get_gravity() * delta
	move_and_slide()
	_update_motion(delta)


## In ritirata, al piu ogni THREAT_REFRESH secondi: il nemico vivo piu vicino alla macchina entro
## `retreat_enemy_range` (boss compresi) da la direzione della ritirata, dal nemico verso il
## giocatore. Nessuno in raggio, o nessun direttore: niente minaccia (la macchina tiene il posto).
func _tick_threat(delta: float) -> void:
	if state != State.RETREAT:
		return
	_threat_left -= delta
	if _threat_left > 0.0:
		return
	_threat_left = THREAT_REFRESH
	_threat_direction = Vector3.ZERO
	var director := caravan.enemy_director()
	if director == null:
		return
	var nearest: Enemy = null
	var best := caravan.tuning.retreat_enemy_range * caravan.tuning.retreat_enemy_range
	for enemy in director.enemies:
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue
		var offset := enemy.global_position - global_position
		var distance := offset.x * offset.x + offset.z * offset.z
		if distance <= best:
			best = distance
			nearest = enemy
	if nearest == null:
		return
	var away := caravan.player.global_position - nearest.global_position
	away.y = 0.0
	if not away.is_zero_approx():
		_threat_direction = away.normalized()


## A `retreat_distance` dal giocatore dal lato opposto alla minaccia, sul primo punto aperto
## (fino a +-60 gradi), altrimenti il posto.
func _retreat_point() -> Vector3:
	var point: Variant = caravan.walkable_near_player(_threat_direction, caravan.tuning.retreat_distance)
	return point if point != null else caravan.slot_target(self)


## Incastro (vedi STUCK_*): spostamento netto per finestre di STUCK_WINDOW secondi, non la
## velocita di un passo (una macchina che scivola avanti e indietro contro la parete di una
## buca resta "ferma"); e, a ogni passo, il punto non aperto per la carovana (sul fondo di una
## buca anche a meno di 2 m dal posto). Chi si muove davvero, o e arrivata su un punto aperto,
## riparte da zero.
func _track_stuck(delta: float) -> void:
	if caravan.is_open_point(global_position):
		_trapped_time = 0.0
	else:
		_trapped_time += delta
	if _window_start == Vector3.INF:
		_window_start = global_position
		_window_time = 0.0
	_window_time += delta
	# float64: 30 x 1/60 non fa 0,5 esatto.
	if _window_time >= STUCK_WINDOW - 0.0001:
		if planar_distance(_window_start, global_position) < STUCK_SPEED * _window_time \
				and planar_distance(global_position, _goal_point) > STUCK_GOAL_DISTANCE:
			_slow_time += _window_time
		else:
			_slow_time = 0.0
		_window_start = global_position
		_window_time = 0.0
	_stuck_time = maxf(_slow_time, _trapped_time)


## Incastro azzerato: cambio di stato, ritorno al posto.
func _reset_stuck() -> void:
	_stuck_time = 0.0
	_slow_time = 0.0
	_trapped_time = 0.0
	_window_start = Vector3.INF
	_window_time = 0.0


## Teletrasporto al posto nel grappolo (guinzaglio o incastro), poggiata sul suolo. Falso, e si
## riprova al passo dopo, se il posto non e percorribile.
func _return_to_slot() -> bool:
	var place := caravan.slot_target(self)
	if not caravan.is_open_point(place):
		return false
	global_position = place + Vector3(0.0, Caravan.GROUND_CLEARANCE, 0.0)
	velocity = Vector3.ZERO
	_last_local_velocity = Vector3.ZERO
	_bounce = Vector2.ZERO
	_reset_stuck()
	_threat_left = 0.0
	reset_physics_interpolation()
	return true


# --- Pezzi, cubetti e segni dello stato ------------------------------------------------------

## Cubetti del pianale: [param capacity] posti, i primi [param carried] visibili. Quando il
## carico cambia ballano e le sospensioni rispondono (solo visivo).
func set_cargo_view(capacity: int, carried: int) -> void:
	if capacity > _cargo.size():
		_add_cargo_slots(capacity - _cargo.size())
	for i in _cargo.size():
		_cargo[i].visible = i < carried
	if carried != _shown_carried:
		if _shown_carried >= 0:
			_cargo_wobble = 1.0
			_bounce.y += BOUNCE_KICK_CARGO
		_shown_carried = carried


## Cubetti di tutti i Cassoni della macchina: capienza e carico sommati. Una macchina senza
## Cassoni (e senza cubetti) non ne mostra.
func refresh_cargo_view() -> void:
	var total_capacity := 0
	var total_carried := 0
	for each in modules:
		var box := each as CargoModule
		if box != null:
			total_capacity += box.capacity
			total_carried += box.carried
	if total_capacity == 0 and _cargo.is_empty():
		return
	set_cargo_view(total_capacity, total_carried)


## Monta un pezzo visibile (upgrade): una sola istanza per nome.
func mount_part(part_name: StringName, part: Node3D) -> void:
	var old := get_node_or_null(NodePath(part_name))
	if old != null:
		var index := _parts.find(old as Node3D)
		if index >= 0:
			_parts.remove_at(index)
			_part_rest.remove_at(index)
			_part_mount.remove_at(index)
		_part_owner.erase(old as Node3D)
		# Via dall'albero subito: altrimenti il nuovo pezzo viene rinominato (@TurretPart@N)
		# e dal terzo montaggio dello stesso nome i pezzi si accumulano.
		remove_child(old)
		old.queue_free()
	part.name = part_name
	_set_visual_layer(part)
	add_child(part)
	_parts.append(part)
	_part_rest.append(part.transform)
	_part_mount.append(part.transform)
	part.transform = _scale_rig * part.transform


## [param base] se nessun figlio ha quel nome, altrimenti `base2`, `base3`, ...
func _free_child_name(base: String) -> StringName:
	var candidate := base
	var n := 2
	while has_node(NodePath(candidate)):
		candidate = "%s%d" % [base, n]
		n += 1
	return StringName(candidate)


## Dopo ogni modulo aggiunto o tolto: taglia, forza (a ogni modulo), fattore di velocita, scala
## e vita massima dal numero dei moduli (MachineFusion); la vita resta entro il nuovo massimo (la
## frazione la fissa la carovana). Poi combinazioni, pezzi impilati (PART_STACK secondo l'indice
## del modulo), modello, cubetti, anello, fumo e punto esclamativo in scala attorno a RIG_GROUND.
func _rebuild() -> void:
	var tuning := _tuning()
	var count := modules.size()
	if tuning != null and count > 0:
		size = MachineFusion.size_of(count, tuning) as MachineFusion.Size
		power = MachineFusion.power_of(count, tuning)
		speed_factor = MachineFusion.speed_factor_of(count, tuning)
		model_scale = MachineFusion.model_scale_of(count, tuning)
		max_health = MachineFusion.max_health_of(count, tuning)
		health = mini(health, max_health)
	for each in modules:
		each.set_power(power)
	_combos = MachineCatalog.combos_of(module_ids())
	_scale_rig = Transform3D(Basis.from_scale(Vector3.ONE * model_scale), RIG_GROUND * (1.0 - model_scale))
	for i in _parts.size():
		var rest := _part_mount[i]
		var owner_module: MachineModule = _part_owner.get(_parts[i])
		if owner_module != null:
			rest.origin += PART_STACK[mini(modules.find(owner_module), PART_STACK.size() - 1)]
		_part_rest[i] = rest
	if _ring != null:
		_ring.size = RING_SIZE * model_scale
		_smoke.position = _scale_rig * SMOKE_POSITION
		_smoke.emission_sphere_radius = SMOKE_EMISSION_RADIUS * model_scale
		_smoke.scale_amount_min = model_scale
		_smoke.scale_amount_max = 1.6 * model_scale
		_broken_mark.position = _scale_rig * Vector3(0.0, BROKEN_MARK_HEIGHT, 0.0)
		_broken_mark.pixel_size = BROKEN_MARK_PIXEL * model_scale
	refresh_cargo_view()
	_refresh_ring()
	if _model != null:
		_apply_rig(Transform3D.IDENTITY, 0.0)


static func planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _build_visuals() -> void:
	_model_rest = _model.transform
	_last_yaw = rotation.y
	# Modello `companion_cart` (tools/blender/build_actor_assets.py): la carrozzeria e
	# "vernice" tinta con BODY_COLOR, la striscia del muso e la superficie `stripe`.
	var body := ActorModel.mesh_instance_of(_model)
	if ActorModel.surface_material(body, "paint") != null:
		# Modello rifinito (D-072): carrozzeria dalla texture cotta, tinta BODY_COLOR.
		var paint := ActorModel.textured_paint(body.mesh, BODY_COLOR, 2.5)
		ActorModel.dress(body, paint)
		_own_materials.append(paint)
	else:
		var paint := ActorModel.paint_material(BODY_COLOR, 2.5)
		var stripe_material := StandardMaterial3D.new()
		stripe_material.albedo_color = STRIPE_COLOR.linear_to_srgb()
		ActorModel.apply_materials(body, {
			"detail": paint,
			"stripe": stripe_material,
		})
		_own_materials.append_array([paint, stripe_material])
	_set_visual_layer(_model)
	_build_status_marks()


func _add_cargo_slots(count: int) -> void:
	if _cargo_mesh == null:
		_cargo_mesh = BoxMesh.new()
		_cargo_mesh.size = Vector3.ONE * CARGO_SIZE
		_cargo_material = StandardMaterial3D.new()
		_cargo_material.albedo_color = ScrapField.SCRAP_COLOR.linear_to_srgb()
	for n in count:
		var i := _cargo.size()
		var cube := MeshInstance3D.new()
		cube.mesh = _cargo_mesh
		cube.material_override = _cargo_material
		cube.layers = VISUAL_LAYER
		# Due file sul pianale del cassone (0,30 m sopra l'origine nel modello).
		cube.position = Vector3((i % 2) * 0.28 - 0.14, 0.42 + (i / 2) * 0.24, 0.1)
		add_child(cube)
		_cargo.append(cube)
		_cargo_rest.append(cube.position)


## Mette sul layer visivo della macchina [param node] e tutto cio che contiene.
static func _set_visual_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = VISUAL_LAYER
	for child in node.get_children():
		_set_visual_layer(child)


## Anello a terra (Decal proprio, sul layer 1 del suolo: le mesh della macchina stanno sul 2),
## fumo e punto esclamativo del guasto, spenti finche la macchina non si guasta. Figli diretti
## della macchina, fuori dal telaio; tutti sul layer visivo della macchina.
func _build_status_marks() -> void:
	var ring_texture := BrushPreview.ring_texture()
	_ring = Decal.new()
	_ring.name = "GroundRing"
	_ring.texture_albedo = ring_texture
	_ring.texture_emission = ring_texture
	_ring.emission_energy = 1.5
	_ring.size = RING_SIZE
	_ring.position = RIG_GROUND
	_ring.cull_mask = 1
	_ring.layers = VISUAL_LAYER
	add_child(_ring)

	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	_smoke.mesh = _smoke_puff()
	_smoke.amount = 10
	_smoke.lifetime = 1.6
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = SMOKE_EMISSION_RADIUS
	_smoke.direction = Vector3.UP
	_smoke.spread = 15.0
	_smoke.initial_velocity_min = 0.5
	_smoke.initial_velocity_max = 0.9
	_smoke.gravity = Vector3(0.0, 0.3, 0.0)
	_smoke.damping_min = 0.2
	_smoke.damping_max = 0.4
	_smoke.scale_amount_min = 1.0
	_smoke.scale_amount_max = 1.6
	_smoke.scale_amount_curve = _smoke_growth
	_smoke.color_ramp = _smoke_fade
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.position = SMOKE_POSITION
	_smoke.layers = VISUAL_LAYER
	_smoke.emitting = false
	_smoke.visible = false
	add_child(_smoke)

	_broken_mark = Label3D.new()
	_broken_mark.name = "BrokenMark"
	_broken_mark.text = "!"
	_broken_mark.font_size = 96
	_broken_mark.pixel_size = BROKEN_MARK_PIXEL
	_broken_mark.modulate = BrushPreview.INVALID_COLOR
	_broken_mark.outline_size = 18
	_broken_mark.outline_modulate = Color.BLACK
	_broken_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_broken_mark.no_depth_test = true
	_broken_mark.position = Vector3(0.0, BROKEN_MARK_HEIGHT, 0.0)
	_broken_mark.layers = VISUAL_LAYER
	_broken_mark.visible = false
	add_child(_broken_mark)


## Colore dell'anello: rosso da guasta, altrimenti quello del modulo (MachineCatalog). Solo ai
## cambi (modulo aggiunto, stato), mai a ogni passo.
func _refresh_ring() -> void:
	if _ring == null:
		return
	if is_broken():
		_ring.modulate = BrushPreview.INVALID_COLOR
	else:
		_ring.modulate = MachineCatalog.find(primary_module_id()).get(&"color", Color.WHITE)


## Sbuffo del fumo, creato una volta per tutte le macchine: sfera grigia e trasparente che
## cresce e sfuma salendo.
static func _smoke_puff() -> SphereMesh:
	if _smoke_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color(SMOKE_COLOR.linear_to_srgb(), SMOKE_ALPHA)
		_smoke_mesh = SphereMesh.new()
		_smoke_mesh.radius = SMOKE_RADIUS
		_smoke_mesh.height = SMOKE_RADIUS * 2.0
		_smoke_mesh.radial_segments = 8
		_smoke_mesh.rings = 4
		_smoke_mesh.material = material
		_smoke_growth = Curve.new()
		_smoke_growth.add_point(Vector2(0.0, 0.35))
		_smoke_growth.add_point(Vector2(1.0, 1.0))
		_smoke_fade = Gradient.new()
		_smoke_fade.set_color(0, Color.WHITE)
		_smoke_fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	return _smoke_mesh


# --- Movimento procedurale ---------------------------------------------------------------

## Sospensioni, inclinazione in accelerazione e in curva, tremito del motore e cubetti
## che ballano: un solo telaio applicato a tutti i visual a partire dalle pose di riposo.
## Legge lo stato di gioco, non lo cambia.
func _update_motion(delta: float) -> void:
	if not ActorMotion.enabled:
		if not _motion_at_rest:
			_apply_rig(Transform3D.IDENTITY, 0.0)
			_motion_at_rest = true
		return
	_motion_time += delta
	var local_velocity := Vector3(velocity.x, 0.0, velocity.z) * global_basis
	var speed := local_velocity.length()
	var speed_ratio := clampf(speed / maxf(top_speed(), 0.01), 0.0, 1.0)
	var change := local_velocity - _last_local_velocity
	_last_local_velocity = local_velocity
	var acceleration := change / maxf(delta, 0.0001)
	var yaw_rate := wrapf(rotation.y - _last_yaw, -PI, PI) / maxf(delta, 0.0001)
	_last_yaw = rotation.y

	# Avanti e -Z: accelerando il muso sale (beccheggio positivo); scartando a destra
	# il telaio si corica a sinistra (rollio positivo), come in curva.
	var target_pitch := clampf(-acceleration.z * TILT_PER_ACCELERATION, -TILT_MAX, TILT_MAX)
	var target_roll := clampf(acceleration.x * TILT_PER_ACCELERATION - yaw_rate * speed_ratio * TURN_ROLL, -TILT_MAX, TILT_MAX)
	_tilt_pitch = ActorMotion.smooth(_tilt_pitch, target_pitch, TILT_RATE, delta)
	_tilt_roll = ActorMotion.smooth(_tilt_roll, target_roll, TILT_RATE, delta)

	_bounce.y += change.length() * BOUNCE_KICK_PER_SPEED_CHANGE
	_bounce = ActorMotion.spring(_bounce, BOUNCE_STIFFNESS, BOUNCE_DAMPING, delta)
	_road_phase = fmod(_road_phase + speed * ROAD_RADIANS_PER_METER * delta, TAU)
	var idle := 1.0 - speed_ratio
	var shiver := sin(_motion_time * TAU * SHIVER_HZ)
	var rise := clampf(_bounce.x, 0.0, BOUNCE_MAX) \
		+ (0.5 + 0.5 * sin(_road_phase)) * ROAD_BUMP * speed_ratio \
		+ (0.5 + 0.5 * shiver) * SHIVER_HEIGHT * idle
	var roll := _tilt_roll + shiver * SHIVER_ROLL * idle

	if _cargo_wobble > 0.0:
		_cargo_wobble = maxf(_cargo_wobble - delta / CARGO_WOBBLE_SECONDS, 0.0)
	var rig := ActorMotion.tilt_on_ground(RIG_GROUND, _tilt_pitch, roll, WHEEL_HALF_LENGTH, WHEEL_HALF_WIDTH)
	rig.origin.y += rise
	_apply_rig(rig, _cargo_wobble * _cargo_wobble)
	_motion_at_rest = false


## Applica il telaio a modello, cubetti visibili e pezzi montati, in scala (`_scale_rig`).
## [param wobble] (0..1) fa ballare i cubetti, ognuno con la sua fase.
func _apply_rig(rig: Transform3D, wobble: float) -> void:
	var frame := rig * _scale_rig
	_model.transform = frame * _model_rest
	# Tutti i cubetti, anche quelli nascosti: a interruttore spento tornano a riposo (P-05).
	for i in _cargo.size():
		var pose := Transform3D(Basis.IDENTITY, _cargo_rest[i])
		if wobble > 0.0:
			var beat := _motion_time * TAU * CARGO_WOBBLE_HZ + i * 1.9
			pose.basis = Basis.from_euler(Vector3(0.0, sin(beat) * CARGO_WOBBLE_TWIST * wobble, cos(beat) * CARGO_WOBBLE_TWIST * 0.5 * wobble))
			pose.origin.y += absf(sin(beat)) * CARGO_WOBBLE_HOP * wobble
		_cargo[i].transform = frame * pose
	for i in _parts.size():
		_parts[i].transform = frame * _part_rest[i]
