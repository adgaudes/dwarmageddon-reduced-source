class_name CargoModule
extends MachineModule
## Cassone (spec D-093, Sezione 1): il cassone del compagno di oggi (D-032). Raccoglie i
## rottami vicini al giocatore e li tiene per lampioni e riparazioni; la carovana somma i
## Cassoni e fa da fornitore. Guasto non raccoglie (scelta 3 di D-093). Il raggio di ricerca dei
## rottami attorno al giocatore cresce con la forza della macchina, la capienza no (scelta 4 del
## piano B).

## Passo di campionamento della linea dritta verso un rottame (audit C-01).
const LINE_STEP_M := 0.6
## Due mete piu vicine di cosi (piano XZ) sono lo stesso rottame.
const SAME_SCRAP_M := 0.01

## Rottami a bordo, sempre fra 0 e `capacity`: aggiorna i cubetti e avvisa la carovana.
var carried := 0:
	set(value):
		carried = clampi(value, 0, capacity)
		if machine != null:
			machine.refresh_cargo_view()
		if caravan != null:
			caravan.notify_cargo_changed()
## Copia della capienza del tuning: le carte la aumentano senza toccare la risorsa.
var capacity := 0

## Meta in cache (rottame o null) e secondi alla prossima ricerca; `_searched` falso = da rifare.
var _target: Variant = null
var _searched := false
var _search_left := 0.0
var _watched_field: PathField


func add_capacity(extra: int) -> void:
	capacity += extra
	if machine != null:
		machine.refresh_cargo_view()


## Raggio di ricerca dei rottami attorno al giocatore: `pickup_radius_from_player` per la forza.
func pickup_radius() -> float:
	return caravan.tuning.pickup_radius_from_player * power


func room() -> int:
	return capacity - carried


## Rottame in cui il Cassone e diretto, o null (lo legge la carovana per non mandarci un
## altro Cassone). Spento non ne punta nessuno, anche se `active` e cambiato senza l'hook; in
## ritirata nemmeno: la macchina non va ai rottami, li lascia agli altri Cassoni. Vale solo se
## la macchina ci sta andando davvero: con due Cassoni sulla stessa macchina il secondo, chiesto
## quando il primo era pieno, terrebbe altrimenti una pretesa fantasma sul suo vecchio rottame.
func claimed_scrap() -> Variant:
	if not _searched or _target == null or not active or machine == null or machine.state != Machine.State.OK:
		return null
	return _target if Machine.planar_distance(machine.goal_point(), _target) <= SAME_SCRAP_M else null


## Rottame raggiungibile piu vicino al giocatore, se c'e posto. La ricerca costa una
## scansione dei rottami e una linea campionata: si rifa al piu ogni `cargo_search_interval`,
## e subito se il rottame in cache sparisce o il campo di percorso cambia.
func wanted_destination() -> Variant:
	_watch_path_field()
	if scrap_field == null or player == null or room() <= 0 or machine.is_broken():
		_forget_target()
		return null
	if _searched and _target != null and scrap_field.nearest(_target, SAME_SCRAP_M) == null:
		_forget_target()
	if not _searched or _search_left <= 0.0:
		_target = _nearest_reachable_scrap()
		_searched = true
		_search_left = caravan.tuning.cargo_search_interval
	return _target


func tick(delta: float) -> void:
	_search_left = maxf(_search_left - delta, 0.0)
	if scrap_field == null or room() <= 0 or machine.is_broken():
		return
	var taken := scrap_field.take_near(machine.global_position, caravan.tuning.collect_radius, room())
	if taken > 0:
		carried += taken
		print("PROTOTYPE01_SCRAP_COLLECTED carried=%d" % caravan.carried)


func _forget_target() -> void:
	_target = null
	_searched = false


## Un Cassone spento (la macchina guasta) non viene piu interrogato: lascia subito agli
## altri Cassoni il rottame che aveva puntato.
func _on_active_changed(on: bool) -> void:
	if not on:
		_forget_target()


## Una nuova soluzione del campo di percorso puo aprire o chiudere la strada verso un
## rottame (R-05): la meta in cache si riperde.
func _watch_path_field() -> void:
	if path_field == _watched_field:
		return
	if _watched_field != null and _watched_field.solved.is_connected(_forget_target):
		_watched_field.solved.disconnect(_forget_target)
	_watched_field = path_field
	if path_field != null:
		path_field.solved.connect(_forget_target)


## Rottame piu vicino al giocatore che abbia una strada nel campo di percorso (R-05):
## uno oltre un muro chiuso farebbe spingere la macchina contro le mura per sempre. Un
## rottame che e gia la meta di un altro Cassone si salta.
func _nearest_reachable_scrap() -> Variant:
	var routed := path_field != null and path_field.is_ready()
	var candidates: Array[Vector3] = []
	for point in scrap_field.positions_near(player.global_position, pickup_radius()):
		if routed and path_field.cost_at(point) == PathField.UNREACHABLE:
			continue
		if caravan.is_scrap_claimed(point, self):
			continue
		candidates.append(point)
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return Machine.planar_distance(a, player.global_position) < Machine.planar_distance(b, player.global_position))
	# Verso il rottame la macchina va dritta: solo se la linea e percorribile, altrimenti
	# spingerebbe contro un argine che il campo di percorso aggira (audit C-01).
	for point in candidates:
		if _line_walkable(machine.global_position, point):
			return point
	return null


## Vero se si va da [param from] a [param to] in linea retta: niente ostacoli statici e
## nessuna salita oltre la pendenza del campo di percorso, campionando ogni 0,6 m.
func _line_walkable(from: Vector3, to: Vector3) -> bool:
	if path_field == null or not path_field.is_ready():
		return true
	var field := path_field.terrain_field
	var run := Machine.planar_distance(from, to)
	var steps := maxi(int(ceil(run / LINE_STEP_M)), 1)
	var previous := Vector3(from.x, 0.0, from.z)
	for i in range(1, steps + 1):
		var point := Vector3(from.x, 0.0, from.z).lerp(Vector3(to.x, 0.0, to.z), float(i) / steps)
		if not path_field.is_walkable(point):
			return false
		if field != null and not field.can_step(previous, point, path_field.max_grade):
			return false
		previous = point
	return true
