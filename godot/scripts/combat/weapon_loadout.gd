class_name WeaponLoadout
extends Node
## Slot delle armi del giocatore (spec D-092, par. 3 e 8): 3 automatiche e 2 attive. Parte col
## kit della classe (ClassCatalog), aggiunge armi, le fa salire di livello e sceglie i bivi
## (ai livelli 3 e 5 si sale solo scegliendo una trasformazione). Adotta la chiodatrice gia
## presente nella scena (`PlayerWeapon`) invece di crearne una seconda; se la classe non la
## usa la spegne. Riceve dal giocatore la pressione dei tasti delle attive.

signal changed
signal active_triggered(slot: int, at: Vector3)
## Una fusione fatta (ricettario dell'Officina).
signal fused(fusion_id: StringName)
## Suono chiesto da un'arma (piano 5), con l'id dell'arma: lo ascolta RunAudio.
signal weapon_sound(id: StringName, kind: StringName)

const AUTO_SLOTS := 3
const ACTIVE_SLOTS := 2

var player: Node3D
var director: EnemyDirector
var terrain_field: TerrainField
var write_queue: TerrainWriteQueue
## Servizi facoltativi (piano 3): passano alle armi che hanno una proprieta con lo stesso nome.
var caravan: Caravan
var xp_field: XpField
var scrap_field: ScrapField
var meadow: MeadowMap
## Moltiplica la ricarica delle attive (Miccia corta).
var active_cooldown_scale := 1.0
var class_id: StringName
## La chiodatrice della scena: entra negli slot solo se la classe la usa.
var adopted: Weapon
var manual_aim := false
## Modifiche permanenti per arma (Officina): valgono anche per le armi aggiunte dopo.
var _weapon_mods: Dictionary[StringName, Dictionary] = {}
var _autos: Array[Weapon] = []
var _actives: Array[ActiveWeapon] = []
## Telegrafo a terra delle attive (piano 5).
var telegraph: ActiveTelegraph


func _ready() -> void:
	if player != null and player.has_signal(&"active_weapon_pressed"):
		player.active_weapon_pressed.connect(trigger_active)
	telegraph = ActiveTelegraph.new()
	telegraph.name = "ActiveTelegraph"
	telegraph.loadout = self
	add_child(telegraph)


## Colore d'accento della classe, per il telegrafo; ocra se la classe non c'e.
func class_color() -> Color:
	return ClassCatalog.find(class_id).get(&"color", Color(1.0, 0.8, 0.35))


## Script di ogni arma del catalogo: `scripts/combat/weapons/<id>.gd` (la chiodatrice e
## AutoWeapon); null se l'arma non e ancora implementata.
static func script_for(id: StringName) -> Script:
	if id == &"nailgun":
		return AutoWeapon
	if id == &"":
		return null
	var path := "res://scripts/combat/weapons/%s.gd" % id
	return load(path) as Script if ResourceLoader.exists(path) else null


## Passa all'arma i servizi del loadout che lei dichiara (proprieta con lo stesso nome).
func give_services(w: Weapon) -> void:
	for key: StringName in [&"write_queue", &"caravan", &"xp_field", &"scrap_field", &"meadow"]:
		if key in w:
			w.set(key, get(key))
	if w is ActiveWeapon:
		(w as ActiveWeapon).cooldown_scale = active_cooldown_scale


## Modifiche permanenti di un'arma (chiavi dei bivi, es. `{cooldown_mul = 0.9}`), per quella
## presente e per quella aggiunta dopo.
func set_weapon_mods(id: StringName, mods: Dictionary) -> void:
	_weapon_mods[id] = mods
	var w := weapon(id)
	if w != null:
		w.extra_mods = mods
		w.set_level(w.level)


func set_active_cooldown_scale(scale: float) -> void:
	active_cooldown_scale = scale
	for active in _actives:
		active.cooldown_scale = scale
		active.changed.emit()


## La chiodatrice della scena (senza `weapon_id` diventa la chiodatrice del catalogo).
func adopt(weapon: Weapon) -> void:
	adopted = weapon
	if weapon.weapon_id == &"":
		weapon.weapon_id = &"nailgun"
	weapon.set_level(1)
	_set_enabled(weapon, false)


func _on_weapon_sound(kind: StringName, w: Weapon) -> void:
	weapon_sound.emit(w.weapon_id, kind)


func setup_class(id: StringName) -> void:
	class_id = id
	for weapon_id in ClassCatalog.start_weapons(id):
		add(weapon_id)
	print("PROTOTYPE01_LOADOUT class=%s weapons=%s" % [id, ",".join(PackedStringArray(all_ids()))])


func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for weapon: Weapon in _autos + _actives:
		ids.append(weapon.weapon_id)
	return ids


func has_weapon(id: StringName) -> bool:
	return weapon(id) != null


func weapon(id: StringName) -> Weapon:
	for w: Weapon in _autos + _actives:
		if w.weapon_id == id:
			return w
	return null


func level_of(id: StringName) -> int:
	var w := weapon(id)
	return w.level if w != null else 0


func autos() -> Array[Weapon]:
	return _autos.duplicate()


func actives() -> Array[ActiveWeapon]:
	return _actives.duplicate()


func free_slots(slot: StringName) -> int:
	return AUTO_SLOTS - _autos.size() if slot == &"auto" else ACTIVE_SLOTS - _actives.size()


## Aggiunge l'arma al livello 1; null se sconosciuta, non implementata, gia presa o senza slot.
func add(id: StringName) -> Weapon:
	var entry := WeaponCatalog.find(id)
	if entry.is_empty() or entry.slot == &"fusion" or has_weapon(id) or free_slots(entry.slot) <= 0:
		return null
	var w: Weapon
	if adopted != null and adopted.weapon_id == id:
		w = adopted
		_set_enabled(w, true)
	else:
		var script := script_for(id)
		if script == null:
			return null
		w = script.new()
		w.weapon_id = id
		w.name = "Weapon_%s" % id
		add_child(w)
	w.shooter = player
	w.director = director
	w.terrain_field = terrain_field
	w.manual_aim = manual_aim
	give_services(w)
	if not w.sound_requested.is_connected(_on_weapon_sound):
		w.sound_requested.connect(_on_weapon_sound.bind(w))
	if _weapon_mods.has(id):
		w.extra_mods = _weapon_mods[id]
		w.set_level(w.level)
	if w is ActiveWeapon:
		var active := w as ActiveWeapon
		active.triggered.connect(func(at: Vector3) -> void: active_triggered.emit(_actives.find(active), at))
		active.triggered.connect(func(at: Vector3) -> void:
			if telegraph != null:
				telegraph.flash(at, ActiveTelegraph.radius_of(active), class_color()))
		_actives.append(active)
	else:
		_autos.append(w)
	w.changed.connect(changed.emit)
	print("PROTOTYPE01_WEAPON_ADDED id=%s" % id)
	changed.emit()
	return w


## Sale di un livello (2 o 4); al bivio o al massimo resta dov'e. Restituisce il livello.
func level_up(id: StringName) -> int:
	var w := weapon(id)
	if w == null:
		return 0
	if w.level >= WeaponCatalog.MAX_LEVEL or needs_branch(id):
		return w.level
	w.set_level(w.level + 1)
	_log_level(w)
	return w.level


## Vero se il prossimo livello dell'arma e un bivio (3 o 5).
func needs_branch(id: StringName) -> bool:
	var w := weapon(id)
	return w != null and w.level < WeaponCatalog.MAX_LEVEL and WeaponCatalog.BRANCH_LEVELS.has(w.level + 1)


## Sale al bivio scegliendo la trasformazione [param pick] (&"a" o &"b").
func choose_branch(id: StringName, pick: StringName) -> void:
	if not needs_branch(id):
		return
	var w := weapon(id)
	var at := w.level + 1
	w.branches[at] = pick
	w.set_level(at)
	_log_level(w)


## Vero se l'automatica [param auto_id] e la sua attiva compagna sono al livello 5 e non e gia fusa.
func can_fuse(auto_id: StringName) -> bool:
	var auto := weapon(auto_id)
	if auto == null or auto is ActiveWeapon or auto.fusion_id != &"" or auto.level < WeaponCatalog.MAX_LEVEL:
		return false
	var fusion := WeaponCatalog.fusion_of(auto_id)
	var partner: StringName = WeaponCatalog.find(auto_id).get(&"partner", &"")
	return fusion != &"" and level_of(partner) >= WeaponCatalog.MAX_LEVEL


## Fonde l'automatica con la compagna (spec par. 3): l'automatica resta coi suoi bivi e prende
## l'effetto della fusione, l'attiva esce dagli slot (la seconda attiva passa al primo).
func fuse(auto_id: StringName) -> bool:
	if not can_fuse(auto_id):
		return false
	var auto := weapon(auto_id)
	var partner := weapon(WeaponCatalog.find(auto_id).partner) as ActiveWeapon
	_actives.erase(partner)
	partner.queue_free()
	auto.fusion_id = WeaponCatalog.fusion_of(auto_id)
	auto.set_level(auto.level)
	print("PROTOTYPE01_WEAPON_FUSED id=%s fusion=%s" % [auto_id, auto.fusion_id])
	fused.emit(auto.fusion_id)
	changed.emit()
	return true


## Usa l'attiva dello slot [param slot] (0 o 1); vero se e partita.
func trigger_active(slot: int) -> bool:
	if slot < 0 or slot >= _actives.size():
		return false
	return _actives[slot].trigger()


func set_manual_aim(on: bool) -> void:
	manual_aim = on
	for w: Weapon in _autos + _actives:
		w.manual_aim = on


func _log_level(w: Weapon) -> void:
	print("PROTOTYPE01_WEAPON_LEVEL id=%s level=%d branches=%s" % [w.weapon_id, w.level, w.branches])


static func _set_enabled(w: Weapon, on: bool) -> void:
	w.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	w.visible = on
