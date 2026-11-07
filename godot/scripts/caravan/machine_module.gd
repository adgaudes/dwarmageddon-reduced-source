class_name MachineModule
extends Node3D
## Modulo di una macchina della carovana (spec D-093, Sezione 1): nodo figlio della Machine,
## che ne chiama `tick` a ogni passo fisico finche il modulo e attivo. Da solo e il modulo
## inerte di un id fuori catalogo.
## I servizi li passa la carovana dopo `add_child`, alle proprieta con lo stesso nome (come
## WeaponLoadout.give_services): nel `_ready` del modulo sono ancora null. Subito dopo la
## carovana chiama `apply_level`, e la richiama quando arrivano servizi nuovi (`configure`):
## chi si registra presso un servizio lo fa li, in modo idempotente, e solo se il servizio c'e.
## Ogni servizio puo mancare (null): i moduli lo controllano prima di usarlo.

## I timer dei moduli scattano a `<= TIMER_EPSILON`: in float64 la somma dei passi da 1/60 s
## manca la soglia esatta di un soffio.
const TIMER_EPSILON := 0.0001

var module_id: StringName
var machine: Machine
var caravan: Caravan
var level := 0
## Forza della macchina (Machine.power, scelta 4 di D-093): la imposta la macchina con `set_power`
## a ogni modulo aggiunto o tolto; raggi e intervalli dei moduli la includono.
var power := 1.0
## Un modulo spento non fa `tick` e non chiede mete: lo spegne il guasto della macchina (il
## Faro resta acceso anche di giorno, la sua luce la nasconde il fattore di notte).
var active := true

# --- Servizi (dalla carovana) ---
var player: PlayerCharacter
var director: EnemyDirector
var terrain_field: TerrainField
var write_queue: TerrainWriteQueue
var scrap_field: ScrapField
var xp_field: XpField
var light_field: LightField
var path_field: PathField
var run_tuning: RunTuning
var lamp_field: LampField
var extraction_pad: ExtractionPad


## Un passo fisico del modulo, dopo il movimento della macchina.
func tick(_delta: float) -> void:
	pass


## Punto in cui il modulo vuole portare la macchina, o null (la macchina tiene il suo posto).
func wanted_destination() -> Variant:
	return null


## Pezzo visibile da montare sulla macchina (Machine.mount_part), o null.
func build_part() -> Node3D:
	return null


## Livello del tipo di modulo (carte di livello): vale per tutti i moduli del tipo.
func apply_level(new_level: int) -> void:
	level = new_level


## Forza nuova (Machine._rebuild): riapplica il livello, cosi raggi e intervalli la seguono.
func set_power(value: float) -> void:
	power = value
	apply_level(level)


## Accende o spegne il modulo; a ogni cambio la carovana avvisa (`changed`: HUD, luci dei Faro).
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_on_active_changed(on)
	if caravan != null:
		caravan.changed.emit()


func _on_active_changed(_on: bool) -> void:
	pass


# --- Aiuti dei moduli ------------------------------------------------------------------------

## Vero se il modulo puo scrivere il terreno in [param p] con un pennello di [param radius]:
## dentro il campo con 1 m di margine, non protetto, oltre `keep_clear` dal giocatore e da ogni
## macchina (anche guasta), oltre `radius + 0.5` da ogni lampione e, a estrazione in corso,
## fuori dal disco della piazzola (`radius_m + radius`) attorno al giocatore.
func clear_spot(p: Vector3, radius: float) -> bool:
	if caravan == null or terrain_field == null:
		return false
	var half := terrain_field.half_extents()
	if absf(p.x) > half.x - 1.0 or absf(p.z) > half.y - 1.0:
		return false
	if terrain_field.is_protected(p):
		return false
	var keep_clear := caravan.tuning.keep_clear
	if is_instance_valid(player) and Machine.planar_distance(p, player.global_position) <= keep_clear:
		return false
	for each in caravan.machines:
		if Machine.planar_distance(p, each.global_position) <= keep_clear:
			return false
	if is_instance_valid(lamp_field):
		for post in lamp_field.positions():
			if Machine.planar_distance(p, post) <= radius + 0.5:
				return false
	if is_instance_valid(extraction_pad) and extraction_pad.is_active() and is_instance_valid(player) \
			and Machine.planar_distance(p, player.global_position) <= extraction_pad.radius_m + radius:
		return false
	return true


## Il nemico vivo piu vicino alla macchina (piano XZ) entro [param reach], o null.
func nearest_enemy(reach: float) -> Enemy:
	if not is_instance_valid(director) or machine == null:
		return null
	var here := machine.global_position
	var nearest: Enemy = null
	var best := reach
	for enemy in director.enemies:
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue
		var distance := Machine.planar_distance(enemy.global_position, here)
		if distance <= best:
			best = distance
			nearest = enemy
	return nearest


## Punto a [param distance] da [param from] verso [param to] nel piano XZ (y 0), o null se i
## due punti coincidono (meno di 1 cm).
func point_toward(from: Vector3, to: Vector3, distance: float) -> Variant:
	var offset := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if offset.length() < 0.01:
		return null
	return Vector3(from.x, 0.0, from.z) + offset.normalized() * distance


## Genitore degli effetti: il direttore, se e nell'albero; null li salta.
func fx_parent() -> Node:
	if is_instance_valid(director) and director.is_inside_tree():
		return director
	return null
