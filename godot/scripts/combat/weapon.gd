class_name Weapon
extends Node3D
## Base delle armi (spec D-092, par. 8): livello, bivi presi e valori letti da WeaponCatalog.
## Le sottoclassi rileggono i valori in `_apply_stats()`. Senza `weapon_id` (la Torretta del
## compagno) l'arma usa i valori impostati a mano.

signal changed
## Suono chiesto dall'arma (piano 5): `&"fire"` allo sparo, `&"hit"` all'impatto. WeaponLoadout
## lo rilancia col proprio id e RunAudio suona `w_<arma>_<kind>`.
signal sound_requested(kind: StringName)

@export var weapon_id: StringName
@export var shooter: Node3D
@export var director: EnemyDirector
@export var terrain_field: TerrainField
## Mira manuale (D-089): l'arma segue chi spara invece di cercare il bersaglio da sola.
@export var manual_aim := false
var level := 1
## Bivi presi: {3: &"a"|&"b", 5: ...}.
var branches: Dictionary = {}
## Fusione (WeaponCatalog, `slot == &"fusion"`) se l'arma e stata fusa con la sua compagna.
var fusion_id: StringName = &""
## Modifiche permanenti (Officina, piano 4): stesse chiavi dei bivi, applicate dopo il catalogo.
var extra_mods: Dictionary = {}
var _fx_next: Dictionary[StringName, float] = {}


func _ready() -> void:
	if weapon_id != &"":
		_apply_stats()


func _sound(kind: StringName) -> void:
	sound_requested.emit(kind)


## Dove nascono gli effetti (WeaponFx): sotto il direttore, che resta nel mondo anche quando
## l'arma viene tolta o fusa; senza direttore sotto l'arma.
func fx_parent() -> Node:
	return director if is_instance_valid(director) and director.is_inside_tree() else self


## Vero se l'effetto [param key] puo ripartire: al piu uno ogni [param interval] secondi di gioco,
## per le armi che colpiscono a raffica (chiodi, falci, dischi).
func _fx_ready(key: StringName, interval: float) -> bool:
	var now := float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second
	if now < float(_fx_next.get(key, -1.0)):
		return false
	_fx_next[key] = now + interval
	return true


## Marca [param node] come effetto della fusione (per i test); restituisce il nodo.
func _fusion_fx(node: Node) -> Node:
	if node != null:
		node.set_meta(&"fx_fusion", fusion_id)
	return node


func stat(key: StringName) -> float:
	return WeaponCatalog.apply_mods(WeaponCatalog.stat(weapon_id, key, level, branches), key, extra_mods)


## Vero se la trasformazione [param option_id] (es. &"burst") e fra quelle prese.
func has_branch(option_id: StringName) -> bool:
	for at: int in branches:
		var options := WeaponCatalog.branch_options(weapon_id, at)
		var index := 0 if branches[at] == &"a" else 1
		if index < options.size() and options[index].id == option_id:
			return true
	return false


## Valore dell'effetto di fusione (base della voce di fusione), 0 se l'arma non e fusa.
func fusion_stat(key: StringName) -> float:
	if fusion_id == &"":
		return 0.0
	return float((WeaponCatalog.find(fusion_id).get(&"base", {}) as Dictionary).get(key, 0.0))


func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, WeaponCatalog.MAX_LEVEL)
	_apply_stats()
	changed.emit()


func choose_branch(at_level: int, pick: StringName) -> void:
	branches[at_level] = pick
	_apply_stats()
	changed.emit()


func _apply_stats() -> void:
	pass
