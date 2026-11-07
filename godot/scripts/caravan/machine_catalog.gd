class_name MachineCatalog
extends RefCounted
## Moduli delle macchine della carovana (spec D-093, Sezione 1). Dati in un solo posto, come
## WeaponCatalog; i valori stanno in CaravanTuning. Ogni voce: id, name, icon (UiIcon), color
## (anello a terra e casella nella striscia del HUD), text (una riga, per le carte),
## unlocked_by_default (sbloccato in Officina da subito). Nel piano A tutti e otto sono
## disponibili per prova fino alla scheda Macchine dell'Officina (piano C, scelta 2 di D-093).

const MODULES: Array[StringName] = [&"cargo", &"turret", &"magnet", &"beacon", &"drill", &"shovel", &"welder", &"siren"]
## Combinazioni del piano B (scelta 7 di D-093): valgono coi due moduli nella stessa macchina.
const COMBOS: Array[StringName] = [&"extractor", &"reflector", &"mobile_mixer", &"armored_bait", &"dozer", &"trap"]

## Costruito una volta sola: le voci sono condivise, chi le legge non le modifica.
static var _entries: Array[Dictionary] = []
static var _by_id: Dictionary[StringName, Dictionary] = {}
static var _combos: Array[Dictionary] = []
static var _combos_by_id: Dictionary[StringName, Dictionary] = {}


static func all() -> Array[Dictionary]:
	if _entries.is_empty():
		_entries = _build()
		for entry in _entries:
			_by_id[entry.id] = entry
	return _entries


## Colori accesi e distinti fra loro e dal rosso del guasto, per staccarsi dal terreno.
static func _build() -> Array[Dictionary]:
	return [
		{id = &"cargo", name = "Cassone", icon = &"crate", color = Color("f2a33a"), unlocked_by_default = true,
			text = "Raccoglie i rottami e li fornisce a lampioni e riparazioni."},
		{id = &"turret", name = "Torretta", icon = &"turret", color = Color("4f7df2"), unlocked_by_default = true,
			text = "Una chiodatrice che spara al rottamatore piu vicino."},
		{id = &"magnet", name = "Calamita", icon = &"magnet", color = Color("2fd9a0"), unlocked_by_default = true,
			text = "Attira i frammenti di esperienza vicini."},
		{id = &"beacon", name = "Faro", icon = &"beacon", color = Color("ffe36b"), unlocked_by_default = true,
			text = "Fa luce di notte attorno alla carovana."},
		{id = &"drill", name = "Trivella", icon = &"drill", color = Color("b07cf2"), unlocked_by_default = false,
			text = "Scava buche attorno al grappolo; su una vena estrae rottami."},
		{id = &"shovel", name = "Pala", icon = &"scoop", color = Color("9ad94a"), unlocked_by_default = false,
			text = "Alza un piccolo argine davanti al nemico piu vicino coi rottami del Cassone."},
		{id = &"welder", name = "Saldatore", icon = &"solder", color = Color("56d3f5"), unlocked_by_default = false,
			text = "Ripara piano le altre macchine vicine, anche quelle guaste."},
		{id = &"siren", name = "Sirena", icon = &"siren", color = Color("f25cc8"), unlocked_by_default = false,
			text = "Attira su di se i rottamatori vicini."},
	]


## Voce del catalogo, o dizionario vuoto.
static func find(id: StringName) -> Dictionary:
	all()
	return _by_id.get(id, {})


## Nome del modulo, o stringa vuota se sconosciuto.
static func name_of(id: StringName) -> String:
	return String(find(id).get(&"name", ""))


## Combinazioni nell'ordine di COMBOS, costruite una volta. Ogni voce: id, name, parts (i due
## moduli), text (una riga, per il banco e il Ricettario).
static func combos() -> Array[Dictionary]:
	if _combos.is_empty():
		_combos = [
			_combo(&"extractor", "Estrattore", &"drill", &"magnet", "Le buche risucchiano i rottami vicini nel Cassone."),
			_combo(&"reflector", "Riflettore", &"turret", &"beacon", "I nemici illuminati prendono doppio danno dalla Torretta."),
			_combo(&"mobile_mixer", "Betoniera mobile", &"shovel", &"cargo", "Gli argini della Pala sono gratis."),
			_combo(&"armored_bait", "Esca blindata", &"welder", &"siren", "Mentre attira subisce meta danno."),
			_combo(&"dozer", "Ruspa", &"drill", &"shovel", "Scava un fossato con un argine a lato dove passa."),
			_combo(&"trap", "Trappola", &"turret", &"siren", "Chi e attirato prende doppio danno dalla Torretta."),
		]
		for entry in _combos:
			_combos_by_id[entry.id] = entry
	return _combos


static func _combo(id: StringName, combo_name: String, a: StringName, b: StringName, text: String) -> Dictionary:
	var parts: Array[StringName] = [a, b]
	return {id = id, name = combo_name, parts = parts, text = text}


## Voce della combinazione, o dizionario vuoto.
static func find_combo(id: StringName) -> Dictionary:
	combos()
	return _combos_by_id.get(id, {})


## Combinazioni presenti fra [param module_ids], nell'ordine di COMBOS, ognuna una volta sola.
static func combos_of(module_ids: Array[StringName]) -> Array[StringName]:
	var found: Array[StringName] = []
	for entry in combos():
		var complete := true
		for part: StringName in entry.parts:
			if not module_ids.has(part):
				complete = false
				break
		if complete:
			found.append(entry.id)
	return found
