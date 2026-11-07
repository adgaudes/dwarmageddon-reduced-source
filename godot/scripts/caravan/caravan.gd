class_name Caravan
extends Node3D
## Carovana di macchine (spec D-093, Sezioni 1, 4 e 5): possiede le Machine (figlie di questo
## nodo) e il pool dei rottami dei Cassoni, e tiene la firma di fornitura del compagno di oggi
## (`carried`, `carried_changed`, `can_supply`, `spend`, `can_supply_count`, `spend_count`):
## lampioni e audio non cambiano chiamata. Le macchine tengono un posto del grappolo attorno
## al giocatore; la direzione "dietro" e quella del compagno, applicata al capofila.
## Riparazione (Sezione 4): tenendo Interagisci entro `repair_range` da una macchina guasta la si
## rimette in moto (`_tick_repair`); senza giocatore nessuna riparazione.

signal carried_changed(carried: int)
## Macchine, moduli (aggiunti, livelli, accesi o spenti), capienza o stato di una macchina
## (guasta, in ritirata, di nuovo in ordine) cambiati: HUD e luci dei Faro.
signal changed
signal machine_added(machine: Machine)
## Una macchina tolta dalla carovana (assorbita da una fusione o rimossa).
signal machine_removed(machine: Machine)
## [param machine] ha assorbito un'altra macchina (`fuse`).
signal fused(machine: Machine)
## [param machine] e la macchina nuova nata da uno sgancio (`detach`).
signal detached(machine: Machine)
## Una fusione ha formato una combinazione che nessuna delle due macchine aveva.
signal combo_formed(combo_id: StringName)

const MACHINE_SCENE_PATH := "res://scenes/caravan/machine.tscn"
## Altezza dell'origine della macchina sul suolo (meta del box di collisione).
const GROUND_CLEARANCE := 0.3
## Rotazioni (gradi) provate attorno al giocatore per un posto o una ritirata non percorribili.
const SLOT_SEARCH_DEGREES: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0]
## Margine sulla durata della riparazione: la somma dei passi non la raggiunge esatta.
const REPAIR_EPSILON := 0.0001
## Stacco degli eventi: i rottami del Cassone cadono in fila a lato della macchina, a questa
## distanza dal centro (in scala col modello) e a `DETACH_SCRAP_SPACING` m l'uno dall'altro.
const DETACH_SCRAP_SIDE_M := 1.0
const DETACH_SCRAP_SPACING := 0.8

@export var tuning: CaravanTuning
@export var player: PlayerCharacter
@export var scrap_field: ScrapField
## Opzionale: per raggiungere il giocatore aggirando mura e terrapieni (D-038).
@export var path_field: PathField

var machines: Array[Machine] = []
## Moltiplicatore della velocita massima: le macchine lo leggono a ogni passo, quindi vale
## per tutte, anche per quelle aggiunte dopo.
var speed_scale := 1.0
## Posti per i moduli oltre `tuning.module_limit` (Officina mobile, piano C): stanno qui e non
## nel tuning, che e condiviso e non si modifica.
var extra_module_slots := 0
## Rottami di tutti i Cassoni, guasti compresi. Assegnarlo ridistribuisce il totale dal
## capofila in poi (una notifica sola).
var carried: int:
	get:
		var total := 0
		for module in modules_of(&"cargo"):
			total += (module as CargoModule).carried
		return total
	set(value):
		_begin_cargo_change()
		var left := maxi(value, 0)
		for module in modules_of(&"cargo"):
			var cargo := module as CargoModule
			var put := mini(left, cargo.capacity)
			cargo.carried = put
			left -= put
		_end_cargo_change()
var capacity: int:
	get:
		var total := 0
		for module in modules_of(&"cargo"):
			total += (module as CargoModule).capacity
		return total

## Servizi di `configure`, passati a ogni modulo (anche futuro) che ha una proprieta col nome.
var _services: Dictionary[StringName, Variant] = {}
## Livello di ogni tipo di modulo (carte di livello) e capienza in piu dei Cassoni: valgono
## anche per i moduli aggiunti dopo.
var _levels: Dictionary[StringName, int] = {}
var _cargo_bonus := 0
var _machine_scene: PackedScene
var _machine_serial := 0
## Notifiche dei rottami raggruppate: una sola `carried_changed` per operazione pubblica.
var _cargo_batch := 0
var _last_carried := 0
## Ultimo punto chiesto a `can_supply_count`: `spend_count` preleva dal Cassone piu vicino.
var _supply_point := Vector3.INF
## Riparazione in corso: la macchina, i secondi tenuti, e durata e pagamento decisi all'inizio
## della tenuta (con o senza rottami; revisione finale, A3).
var _repair_machine: Machine
var _repair_elapsed := 0.0
var _repair_duration_now := 1.0
var _repair_paid := false


func _ready() -> void:
	if tuning == null:
		tuning = CaravanTuning.new()
	_add_machine(&"cargo", global_position, tuning.starting_scrap)
	print("PROTOTYPE01_CARAVAN_READY machines=%d carried=%d" % [machines.size(), carried])


## Dopo il giocatore e prima delle macchine (figlie) e della run: l'HUD legge il progresso di
## questo passo. In pausa (level-up) si ferma.
func _physics_process(delta: float) -> void:
	_tick_repair(delta)


## Servizi della run (`director`, `terrain_field`, `write_queue`, `xp_field`, `light_field`,
## `run_tuning`, `lamp_field`, `extraction_pad`): li salva e li passa ai moduli, presenti e futuri.
## I moduli gia presenti rifanno `apply_level`: chi e nato prima dei servizi (Torretta,
## Calamita, Faro) si registra ora.
func configure(services: Dictionary) -> void:
	for key: Variant in services:
		_services[StringName(key)] = services[key]
	for machine in machines:
		for module in machine.modules:
			_give_services(module)
			module.apply_level(module.level)
		_track_body(machine)
	var director: Object = _services.get(&"director")
	if director != null and &"caravan" in director:
		director.set(&"caravan", self)


## Aggiunge una macchina col modulo [param module_id] nel posto libero piu basso, in
## [param at] o sul suolo del suo posto. Null a carovana piena o per un modulo sconosciuto.
func add_machine(module_id: StringName, at: Variant = null) -> Machine:
	return _add_machine(module_id, at, 0)


func module_count() -> int:
	var total := 0
	for machine in machines:
		total += machine.modules.size()
	return total


## Moduli che la carovana puo portare: `tuning.module_limit` piu `extra_module_slots`.
func module_limit() -> int:
	return tuning.module_limit + extra_module_slots


func has_room(count := 1) -> bool:
	return module_count() + count <= module_limit()


func count_of(module_id: StringName) -> int:
	return modules_of(module_id).size()


func modules_of(module_id: StringName) -> Array[MachineModule]:
	var result: Array[MachineModule] = []
	for machine in machines:
		for module in machine.modules:
			if module.module_id == module_id:
				result.append(module)
	return result


## Livello delle carte di un tipo di modulo (Torretta veloce, Calamita potente, Faro): vale per
## i moduli presenti e per quelli che arrivano dopo.
func set_module_level(module_id: StringName, level: int) -> void:
	_levels[module_id] = level
	for module in modules_of(module_id):
		module.apply_level(level)
	changed.emit()


func module_level(module_id: StringName) -> int:
	return _levels.get(module_id, 0)


## Luci dei Faro accesi, `{light: OmniLight3D, radius: float}`: ArenaRun vi applica il
## fattore di notte, come alla torcia.
func beacon_lights() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for module in modules_of(&"beacon"):
		var beacon := module as BeaconModule
		if beacon != null and beacon.active:
			result.append({light = beacon.light, radius = beacon.radius()})
	return result


## Capofila (scelta 8 di D-093): la macchina piu vecchia con un Cassone non guasto; altrimenti
## la piu vecchia con un Cassone; altrimenti la prima; altrimenti null.
func lead() -> Machine:
	var with_cargo: Machine = null
	for machine in machines:
		if machine.has_module(&"cargo"):
			if not machine.is_broken():
				return machine
			if with_cargo == null:
				with_cargo = machine
	if with_cargo != null:
		return with_cargo
	return machines[0] if not machines.is_empty() else null


## La macchina con un Cassone (anche guasta) piu vicina a [param point] nel piano, la prima
## nell'ordine della carovana a pari distanza; senza Cassoni il capofila; senza macchine null.
func nearest_cargo_machine(point: Vector3) -> Machine:
	var best: Machine = null
	var best_distance := INF
	for machine in machines:
		if not machine.has_module(&"cargo"):
			continue
		var distance := Machine.planar_distance(machine.global_position, point)
		if distance < best_distance:
			best = machine
			best_distance = distance
	return best if best != null else lead()


# --- Fusione, sgancio e rimozione (piano B) --------------------------------------------------

## Vero se [param other] puo entrare in [param base]: entrambe nella carovana, diverse, non
## guaste, insieme entro `max_modules_per_machine` moduli, e i rottami dei Cassoni funzionanti
## pagano il costo (`fuse_cost_per_module` per modulo della seconda).
func can_fuse(base: Machine, other: Machine) -> bool:
	if base == other or not machines.has(base) or not machines.has(other):
		return false
	if base.is_broken() or other.is_broken():
		return false
	if base.modules.size() + other.modules.size() > tuning.max_modules_per_machine:
		return false
	return working_carried() >= MachineFusion.fuse_cost(other.modules.size(), tuning)


## [param other] entra in [param base] (scelta 2 di D-093), che tiene posto, nome e ordine:
## paga, ricrea su [param base] ogni modulo della seconda (i rottami di un Cassone passano col
## modulo), toglie la seconda e da alla base la frazione di vita delle due (scelta 3). Gira solo
## ad albero fermo (dal banco). Falso, senza effetti, se `can_fuse` e falso.
func fuse(base: Machine, other: Machine) -> bool:
	if not can_fuse(base, other):
		return false
	var health_sum := base.health + other.health
	var max_sum := base.max_health + other.max_health
	var combos_before: Array[StringName] = []
	combos_before.append_array(base.combos())
	combos_before.append_array(other.combos())
	var cost := MachineFusion.fuse_cost(other.modules.size(), tuning)
	_begin_cargo_change()
	pay(cost)
	for module in other.modules.duplicate():
		var scrap := 0
		var box := module as CargoModule
		if box != null:
			scrap = box.carried
			box.carried = 0
		_attach_module(base, module.module_id, scrap)
	remove_machine(other)
	base.health = MachineFusion.carried_health(health_sum, max_sum, base.max_health)
	_end_cargo_change()
	for combo_id in base.combos():
		if not combos_before.has(combo_id):
			print("PROTOTYPE01_COMBO_FORMED combo=%s" % combo_id)
			combo_formed.emit(combo_id)
	print("PROTOTYPE01_MACHINE_FUSED modules=%s size=%s cost=%d machines=%d" % [
		",".join(base.module_ids()), MachineFusion.SIZE_NAMES[base.size], cost, machines.size()])
	fused.emit(base)
	changed.emit()
	return true


## Vero se il modulo [param module_index] di [param machine] si puo sganciare: macchina nella
## carovana, non guasta, con almeno due moduli, e i Cassoni funzionanti pagano lo sgancio.
func can_detach(machine: Machine, module_index: int) -> bool:
	if not machines.has(machine) or machine.is_broken():
		return false
	if machine.modules.size() < 2 or module_index < 0 or module_index >= machine.modules.size():
		return false
	return working_carried() >= MachineFusion.detach_cost(tuning)


## Sgancia il modulo [param module_index] di [param machine] in una macchina piccola nuova, al
## primo posto libero sul suolo e coi rottami del modulo se e un Cassone; sorgente e sganciata
## conservano entrambe la frazione di vita (scelta 3 di D-093; dalla revisione finale anche la
## sganciata, altrimenti sgancia-e-rifondi curava a 2 rottami il giro). Gira solo ad albero fermo
## (dal banco). La macchina nuova, o null se `can_detach` e falso.
func detach(machine: Machine, module_index: int) -> Machine:
	if not can_detach(machine, module_index):
		return null
	var health := machine.health
	var max_health := machine.max_health
	var cost := MachineFusion.detach_cost(tuning)
	_begin_cargo_change()
	pay(cost)
	var module := machine.modules[module_index]
	var module_id := module.module_id
	var scrap := 0
	var box := module as CargoModule
	if box != null:
		scrap = box.carried
		box.carried = 0
	# `remove_module` ricostruisce la macchina: i moduli rimasti si registrano di nuovo (un
	# gemello di quello tolto, due Calamite sulla stessa macchina, torna in `set_power`).
	machine.remove_module(module)
	machine.health = MachineFusion.carried_health(health, max_health, machine.max_health)
	var created := _add_machine(module_id, null, scrap)
	created.health = MachineFusion.carried_health(health, max_health, created.max_health)
	_end_cargo_change()
	print("PROTOTYPE01_MACHINE_DETACHED module=%s cost=%d machines=%d" % [module_id, cost, machines.size()])
	detached.emit(created)
	changed.emit()
	return created


## Stacco degli eventi (piano C: terremoto, treno): con almeno due moduli toglie da
## [param machine] un modulo a caso ([param rng]), gratis, senza pedana e anche da guasta. Il
## modulo non diventa una macchina; la sorgente conserva la frazione di vita (`carried_health`;
## da guasta resta a 0 PV). I rottami di un Cassone staccato cadono a terra accanto alla macchina,
## uno ogni `DETACH_SCRAP_SPACING` m (senza `scrap_field` vanno persi). L'id del modulo tolto;
## `&""` se la macchina ha un modulo solo o non e nella carovana. [param by] (`&"quake"`,
## `&"train"`) finisce nel marker.
func detach_random(machine: Machine, rng: RandomNumberGenerator, by: StringName = &"event") -> StringName:
	if not machines.has(machine) or machine.modules.size() < 2:
		return &""
	var health := machine.health
	var max_health := machine.max_health
	var module := machine.modules[rng.randi_range(0, machine.modules.size() - 1)]
	var module_id := module.module_id
	var scrap := 0
	var box := module as CargoModule
	_begin_cargo_change()
	if box != null:
		scrap = box.carried
		box.carried = 0
	machine.remove_module(module)
	if not machine.is_broken():
		machine.health = MachineFusion.carried_health(health, max_health, machine.max_health)
	_end_cargo_change()
	if scrap_field != null and scrap > 0:
		var side := machine.global_basis.x
		side.y = 0.0
		side = side.normalized() if not side.is_zero_approx() else Vector3.RIGHT
		var along := side.cross(Vector3.UP)
		var start := machine.global_position + side * DETACH_SCRAP_SIDE_M * machine.model_scale
		for i in scrap:
			scrap_field.spawn_on_ground(start + along * DETACH_SCRAP_SPACING * (i - (scrap - 1) * 0.5))
	print("PROTOTYPE01_MODULE_DETACHED module=%s by=%s" % [module_id, by])
	changed.emit()
	return module_id


## Toglie [param machine] dalla carovana: fuori da `machines` e da `write_queue.bodies`, la
## riparazione azzerata se era sua, dimenticata dai Saldatori; fuori dall'albero subito (Calamita
## e Faro si liberano ora in `_exit_tree`), poi liberata.
func remove_machine(machine: Machine) -> void:
	var index := machines.find(machine)
	if index < 0:
		return
	machines.remove_at(index)
	var queue := _services.get(&"write_queue") as TerrainWriteQueue
	if queue != null:
		queue.bodies.erase(machine)
	if _repair_machine == machine:
		_repair_machine = null
		_repair_elapsed = 0.0
	for module in modules_of(&"welder"):
		(module as WelderModule).forget(machine)
	_begin_cargo_change()
	remove_child(machine)
	machine.queue_free()
	_end_cargo_change()
	print("PROTOTYPE01_MACHINE_REMOVED machines=%d" % machines.size())
	machine_removed.emit(machine)
	changed.emit()


## Le macchine guaste, nell'ordine della carovana (HUD, riparazione).
func broken_machines() -> Array[Machine]:
	var result: Array[Machine] = []
	for machine in machines:
		if machine.is_broken():
			result.append(machine)
	return result


## Il direttore dei nemici passato da `configure`, o null (la ritirata cerca li il nemico piu vicino).
func enemy_director() -> EnemyDirector:
	return _services.get(&"director") as EnemyDirector


# --- Rottami ---------------------------------------------------------------------------------

func room() -> int:
	return capacity - carried


## Riempie i Cassoni dal capofila in poi, guasti compresi; restituisce quanti ne sono entrati.
func add_scrap(amount: int) -> int:
	_begin_cargo_change()
	var left := maxi(amount, 0)
	for module in modules_of(&"cargo"):
		var cargo := module as CargoModule
		var put := mini(left, cargo.room())
		cargo.carried += put
		left -= put
	_end_cargo_change()
	return maxi(amount, 0) - left


## Capienza in piu per ogni Cassone, anche per quelli che arrivano dopo.
func add_cargo_capacity(extra: int) -> void:
	_cargo_bonus += extra
	for module in modules_of(&"cargo"):
		(module as CargoModule).add_capacity(extra)
	changed.emit()


## Puo pagare un rialzo sulla cella che contiene [param world_target]?
func can_supply(world_target: Vector3) -> bool:
	return can_supply_count(world_target, 1)


func spend() -> void:
	spend_count(1)


## I Cassoni funzionanti entro `supply_radius` dal punto hanno almeno [param amount] rottami.
func can_supply_count(world_target: Vector3, amount: int) -> bool:
	_supply_point = world_target
	var available := 0
	for cargo in _working_cargo():
		if Machine.planar_distance(cargo.machine.global_position, world_target) <= tuning.supply_radius:
			available += cargo.carried
	return available >= amount


## Preleva dal Cassone funzionante piu vicino all'ultimo punto chiesto, poi dagli altri.
func spend_count(amount: int) -> void:
	var sources := _working_cargo()
	if _supply_point != Vector3.INF:
		var point := _supply_point
		sources.sort_custom(func(a: CargoModule, b: CargoModule) -> bool:
			return Machine.planar_distance(a.machine.global_position, point) < Machine.planar_distance(b.machine.global_position, point))
	_begin_cargo_change()
	_take(sources, amount)
	_end_cargo_change()
	print("PROTOTYPE01_SCRAP_SPENT carried=%d" % carried)


## Paga [param amount] rottami dai Cassoni funzionanti (anche dai guasti con
## [param include_broken]), dal capofila in poi: tutto o niente.
func pay(amount: int, include_broken := false) -> bool:
	var sources := _working_cargo()
	if include_broken:
		sources.clear()
		for module in modules_of(&"cargo"):
			sources.append(module as CargoModule)
	var available := 0
	for cargo in sources:
		available += cargo.carried
	if available < amount:
		return false
	_begin_cargo_change()
	_take(sources, amount)
	_end_cargo_change()
	return true


## Rottami dei soli Cassoni funzionanti (quelli da cui `pay` preleva senza `include_broken`).
func working_carried() -> int:
	var total := 0
	for cargo in _working_cargo():
		total += cargo.carried
	return total


## Chiamata da un Cassone quando il suo carico cambia: fuori da un'operazione della carovana
## (una raccolta, un'assegnazione diretta) avvisa subito, dentro una sola volta alla fine.
func notify_cargo_changed() -> void:
	if _cargo_batch == 0:
		_emit_carried()


## Vero se [param point] e gia la meta di un Cassone diverso da [param by].
func is_scrap_claimed(point: Vector3, by: MachineModule) -> bool:
	for module in modules_of(&"cargo"):
		if module == by:
			continue
		var claimed: Variant = (module as CargoModule).claimed_scrap()
		if claimed != null and Machine.planar_distance(claimed, point) <= CargoModule.SAME_SCRAP_M:
			return true
	return false


# --- Riparazione -----------------------------------------------------------------------------

## La macchina guasta piu vicina al giocatore (distanza planare) entro `repair_range`, la prima
## nell'ordine della carovana a pari distanza; null senza giocatore vivo o col giocatore a bordo
## (piano C: a bordo non si ripara). Non guarda se Interagisci e tenuto: serve anche al tasto nel HUD.
func repair_target() -> Machine:
	if not is_instance_valid(player) or not player.is_alive() or player.pilot != null:
		return null
	var best: Machine = null
	var best_distance := INF
	for machine in machines:
		if not machine.is_broken():
			continue
		var distance := Machine.planar_distance(machine.global_position, player.global_position)
		if distance <= tuning.repair_range and distance < best_distance:
			best = machine
			best_distance = distance
	return best


## La macchina che si sta riparando, o null.
func repairing_machine() -> Machine:
	return _repair_machine


## Avanzamento della riparazione in corso, 0..1; 0 se nessuna.
func repair_progress() -> float:
	if _repair_machine == null:
		return 0.0
	return clampf(_repair_elapsed / _repair_duration_now, 0.0, 1.0)


## Avanza finche il giocatore tiene Interagisci e il bersaglio resta lo stesso (guasto, entro
## raggio, giocatore vivo); altrimenti torna a zero. All'inizio della tenuta (e a ogni cambio di
## bersaglio) si decide: con almeno `repair_cost` rottami nella carovana dura `repair_seconds`
## e si paga, altrimenti `repair_seconds_without_scrap` gratis. Rottami arrivati o spariti a
## meta tenuta non cambiano la durata. Finita: paga (se i rottami non ci sono piu, gratis),
## ripara, marker.
func _tick_repair(delta: float) -> void:
	var target: Machine = repair_target() if is_instance_valid(player) and player.interact_held else null
	if target != _repair_machine:
		_repair_machine = target
		_repair_elapsed = 0.0
		if target != null:
			_repair_paid = carried >= tuning.repair_cost
			_repair_duration_now = tuning.repair_seconds if _repair_paid else tuning.repair_seconds_without_scrap
	if target == null:
		return
	_repair_elapsed += delta
	# float64: 90 x 1/60 = 1.4999999999999996.
	if _repair_elapsed < _repair_duration_now - REPAIR_EPSILON:
		return
	var machine := _repair_machine
	# Stato azzerato prima di pagare: `pay` e `repair` avvisano subito, e l'HUD legge gia 0.
	_repair_machine = null
	_repair_elapsed = 0.0
	var module_id := machine.primary_module_id()
	var paid := tuning.repair_cost if _repair_paid and pay(tuning.repair_cost, true) else 0
	machine.repair(tuning.repair_health_fraction)
	print("PROTOTYPE01_MACHINE_REPAIR_PAID module=%s paid=%d" % [module_id, paid])


# --- Grappolo --------------------------------------------------------------------------------

## Posto [param index] del grappolo: x = gradi dalla direzione "dietro", y = distanza (m).
## Oltre l'ultimo posto si riusa l'ultimo.
func slot_of(index: int) -> Vector2:
	var slots := tuning.cluster_slots
	if slots.is_empty():
		return Vector2(0.0, 2.5)
	return slots[clampi(index, 0, slots.size() - 1)]


## Punto del posto della macchina attorno al giocatore, sul suolo: il primo percorribile fra il
## posto e lo stesso ruotato di +-30 e +-60 gradi, altrimenti il posto com'e.
func slot_target(machine: Machine) -> Vector3:
	return _slot_point(machine.slot)


## Vero se [param point] e percorribile e da li si raggiunge il giocatore; senza campo di
## percorso (o non ancora pronto) ogni punto va bene.
func is_open_point(point: Vector3) -> bool:
	if path_field == null or not path_field.is_ready():
		return true
	return path_field.is_walkable(point) and path_field.cost_at(point) != PathField.UNREACHABLE


## Primo punto aperto (`is_open_point`) a [param distance] dal giocatore lungo [param direction]
## o la stessa ruotata di +-30 e +-60 gradi, sul suolo; null se nessuno lo e.
func walkable_near_player(direction: Vector3, distance: float) -> Variant:
	for degrees: float in SLOT_SEARCH_DEGREES:
		var point := _on_ground(player.global_position + direction.rotated(Vector3.UP, deg_to_rad(degrees)) * distance)
		if is_open_point(point):
			return point
	return null


func _slot_point(index: int) -> Vector3:
	var place := slot_of(index)
	var direction := _back_direction().rotated(Vector3.UP, deg_to_rad(place.x))
	var open: Variant = walkable_near_player(direction, place.y)
	if open != null:
		return open
	return _on_ground(player.global_position + direction * place.y)


## La regola del compagno di oggi, applicata al capofila: opposta alla velocita del
## giocatore sopra 1 m/s, altrimenti dal giocatore verso il capofila.
func _back_direction() -> Vector3:
	var back := Vector3.ZERO
	var player_planar := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if player_planar.length() > 1.0:
		back = -player_planar
	else:
		var leader := lead()
		if leader != null:
			back = leader.global_position - player.global_position
	back.y = 0.0
	if back.is_zero_approx():
		back = Vector3.BACK
	return back.normalized()


## [param point] alla quota del suolo; senza rilievo alla quota del giocatore.
func _on_ground(point: Vector3) -> Vector3:
	var field := _services.get(&"terrain_field") as TerrainField
	if field != null:
		point.y = field.height_at(point)
	elif player != null:
		point.y = player.global_position.y
	return point


# --- Interni ---------------------------------------------------------------------------------

## Script del modulo di ogni tipo: un id fuori catalogo usa il modulo inerte.
static func module_script_for(module_id: StringName) -> GDScript:
	match module_id:
		&"cargo":
			return CargoModule
		&"turret":
			return TurretModule
		&"magnet":
			return MagnetModule
		&"beacon":
			return BeaconModule
		&"drill":
			return DrillModule
		&"shovel":
			return ShovelModule
		&"welder":
			return WelderModule
		&"siren":
			return SirenModule
	return MachineModule


func _add_machine(module_id: StringName, at: Variant, scrap: int) -> Machine:
	if not has_room() or not MachineCatalog.MODULES.has(module_id):
		return null
	if _machine_scene == null:
		_machine_scene = load(MACHINE_SCENE_PATH) as PackedScene
	var machine := _machine_scene.instantiate() as Machine
	_machine_serial += 1
	machine.name = "Machine%d" % _machine_serial
	machine.caravan = self
	machine.slot = _free_slot()
	machine.max_health = tuning.chassis_health
	machine.health = machine.max_health
	# Posto calcolato prima di entrare nella lista: la direzione "dietro" viene dal capofila
	# che c'e gia, non dalla macchina nuova ancora senza posizione.
	var place: Vector3
	if at != null:
		place = at
	elif player != null:
		place = _slot_point(machine.slot) + Vector3(0.0, GROUND_CLEARANCE, 0.0)
	else:
		place = global_position
	machine.position = to_local(place)
	add_child(machine)
	machine.reset_physics_interpolation()
	machines.append(machine)

	_attach_module(machine, module_id, scrap)
	_track_body(machine)
	print("PROTOTYPE01_MACHINE_ADDED module=%s machines=%d modules=%d" % [module_id, machines.size(), module_count()])
	machine_added.emit(machine)
	changed.emit()
	return machine


## Un modulo nuovo di tipo [param module_id] su [param machine]: servizi, livello del tipo e, se
## e un Cassone, capienza della carovana e [param scrap] rottami a bordo.
func _attach_module(machine: Machine, module_id: StringName, scrap: int) -> MachineModule:
	var module := module_script_for(module_id).new() as MachineModule
	module.module_id = module_id
	machine.add_module(module)
	_give_services(module)
	module.apply_level(module_level(module_id))
	if module is CargoModule:
		var cargo := module as CargoModule
		cargo.capacity = tuning.cargo_capacity + _cargo_bonus
		cargo.carried = scrap
	return module


## Indice di posto piu basso non occupato.
func _free_slot() -> int:
	var used: Dictionary[int, bool] = {}
	for machine in machines:
		used[machine.slot] = true
	var index := 0
	while used.has(index):
		index += 1
	return index


func _give_services(module: MachineModule) -> void:
	for key: StringName in [&"player", &"scrap_field", &"path_field"]:
		if key in module:
			module.set(key, get(key))
	for key in _services:
		if key in module:
			module.set(key, _services[key])


## Una macchina sta in `write_queue.bodies` finche esiste: resta alla stessa altezza sul suolo
## quando le armi o i moduli alzano il terreno sotto di lei.
func _track_body(machine: Machine) -> void:
	var queue := _services.get(&"write_queue") as TerrainWriteQueue
	if queue != null and not queue.bodies.has(machine):
		queue.bodies.append(machine)


func _working_cargo() -> Array[CargoModule]:
	var result: Array[CargoModule] = []
	for module in modules_of(&"cargo"):
		if not module.machine.is_broken():
			result.append(module as CargoModule)
	return result


## Toglie [param amount] rottami da [param sources], nell'ordine.
func _take(sources: Array[CargoModule], amount: int) -> void:
	var left := maxi(amount, 0)
	for cargo in sources:
		var taken := mini(left, cargo.carried)
		cargo.carried -= taken
		left -= taken


func _begin_cargo_change() -> void:
	_cargo_batch += 1


func _end_cargo_change() -> void:
	_cargo_batch -= 1
	if _cargo_batch == 0:
		_emit_carried()


func _emit_carried() -> void:
	var total := carried
	if total == _last_carried:
		return
	_last_carried = total
	carried_changed.emit(total)
