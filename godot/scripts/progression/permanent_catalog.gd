class_name PermanentCatalog
extends RefCounted
## Upgrade permanenti dell'Officina (D-041, D-049; CAMPAIGN_STRUCTURE_SPEC sezione 3; D-092 par.
## 6.2). Si comprano coi rottami portati fuori dai livelli e restano per sempre. Dati in
## un solo posto; gli effetti li applica ArenaRun all'avvio del livello. Ogni voce:
## id, name, costs (rottami per ogni livello: la lunghezza e il livello massimo), text,
## group (la sezione dell'Officina: &"common" o una classe di ClassCatalog; gli upgrade di una
## classe valgono solo giocandola). Lo sblocco di un'arma comune e una voce `unlock_<arma>` a
## un livello, con `weapon` e il costo da WeaponCatalog.

## Sezioni dell'Officina nell'ordine in cui si mostrano, con il titolo.
const GROUPS: Array[Array] = [
	[&"common", "Comune"], [&"engineer", "Ingegnere"], [&"sapper", "Guastatore"],
	[&"mechanic", "Meccanico"], [&"weeder", "Erbacciaia"],
]
## Fusioni del ricettario, nell'ordine in cui si mostrano.
const RECIPES: Array[StringName] = [&"fort", &"mortar", &"tesla_coil", &"scythe_bramble", &"disc_dozer", &"compactor"]
const UNLOCK_PREFIX := "unlock_"

## Costruito una volta sola: le voci sono condivise, chi le legge non le modifica.
static var _entries: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if _entries.is_empty():
		_entries = _build()
	return _entries


static func _build() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{id = &"tool_reach", group = &"common", name = "Prolunga", costs = [6, 14],
			text = "Il tool arriva 1,2 metri piu lontano."},
		{id = &"pack_size", group = &"common", name = "Zainetto largo", costs = [12, 20, 30],
			text = "Lo zainetto porta 20 metri cubi di terra in piu."},
		{id = &"base_health", group = &"common", name = "Telaio rinforzato", costs = [4, 8, 14],
			text = "Un punto vita in piu a ogni livello."},
		{id = &"reflexes", group = &"common", name = "Riflessi da officina", costs = [5, 10],
			text = "Dopo un colpo resti intoccabile 0,2 secondi in piu."},
		{id = &"cargo", group = &"common", name = "Cassone saldato", costs = [4, 8, 12],
			text = "Ogni Cassone parte con 2 posti in piu per i rottami."},
		{id = &"stock", group = &"common", name = "Scorta", costs = [3, 7],
			text = "Parti con 2 rottami in piu nei Cassoni."},
		{id = &"salvage", group = &"common", name = "Paracadute per rottami", costs = [10],
			text = "Se vieni rottamato salvi tre quarti del cassone invece di meta."},
		{id = &"toolbox", group = &"engineer", name = "Cassetta degli attrezzi", costs = [8, 16],
			text = "La chiodatrice parte al livello 2; al secondo livello anche il picchetto."},
		{id = &"spare_stakes", group = &"engineer", name = "Picchetti di scorta", costs = [10],
			text = "Il picchetto sismico si ricarica il 10% prima."},
		{id = &"dry_powder", group = &"sapper", name = "Polvere asciutta", costs = [8, 16],
			text = "La carica da scavo fa un danno in piu per livello."},
		{id = &"charge_pack", group = &"sapper", name = "Zaino di cariche", costs = [12],
			text = "Parti con Scavo esplosivo al livello 1."},
		{id = &"fixed_turret", group = &"mechanic", name = "Torretta fissa", costs = [30],
			text = "Parti con una seconda macchina, con la Torretta."},
		{id = &"good_oil", group = &"mechanic", name = "Olio buono", costs = [8],
			text = "Le macchine vanno il 15% piu veloci."},
		{id = &"good_seeds", group = &"weeder", name = "Semi buoni", costs = [8, 16],
			text = "Il roveto dura 3 secondi in piu per livello."},
		{id = &"green_thumb", group = &"weeder", name = "Pollice verde", costs = [12],
			text = "Erba alta parte al livello 2."},
	]
	for weapon in WeaponCatalog.all():
		if int(weapon.get(&"unlock_cost", 0)) <= 0 or weapon.slot == &"fusion":
			continue
		entries.append({id = unlock_id(weapon.id), group = &"common", weapon = weapon.id,
			name = "Sblocca: %s" % weapon.name, costs = [int(weapon.unlock_cost)], text = weapon.text})
	return entries


## Voce del catalogo, o dizionario vuoto.
static func find(id: StringName) -> Dictionary:
	for entry in all():
		if entry.id == id:
			return entry
	return {}


static func max_level(id: StringName) -> int:
	var entry := find(id)
	return (entry.costs as Array).size() if not entry.is_empty() else 0


static func unlock_id(weapon_id: StringName) -> StringName:
	return StringName(UNLOCK_PREFIX + String(weapon_id))


## Arma sbloccata dalla voce [param id], o &"" se la voce non e uno sblocco.
static func weapon_of(id: StringName) -> StringName:
	return find(id).get(&"weapon", &"")
