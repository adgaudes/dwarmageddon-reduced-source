class_name ClassCatalog
extends RefCounted
## Le quattro classi del roster (D-077, D-092): nome, colore d'accento, kit iniziale e mazzo.
## Il kit elenca le armi della spec; `start_weapons` restituisce solo quelle gia implementate
## (con uno script), cosi una classe senza armi pronte parte comunque.

const DEFAULT := &"engineer"


static func all() -> Array[Dictionary]:
	return [
		{id = &"engineer", name = "Ingegnere", color = Color(1.0, 0.45, 0.08),
			kit = [&"nailgun", &"seismic_stake"], text = "Equilibrata: chiodi e argini."},
		{id = &"sapper", name = "Guastatore", color = Color(0.9, 0.12, 0.08),
			kit = [&"scrap_launcher", &"dig_charge"], text = "Scavo esplosivo: crateri e parabole."},
		{id = &"mechanic", name = "Meccanico", color = Color(0.1, 0.75, 0.72),
			kit = [&"welder", &"crane_magnet"], text = "Compagno potenziato: archi elettrici e calamite."},
		{id = &"weeder", name = "Erbacciaia", color = Color(0.85, 0.15, 0.6),
			kit = [&"scythe", &"bramble"], start_cards = [&"tall_grass"], text = "Vegetazione come difesa: falci e rovi."},
	]


static func find(id: StringName) -> Dictionary:
	for entry in all():
		if entry.id == id:
			return entry
	return {}


static func start_weapons(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for weapon_id: StringName in find(id).get(&"kit", []):
		if not WeaponCatalog.find(weapon_id).is_empty():
			out.append(weapon_id)
	return out


## Carte (UpgradeCatalog) con cui la classe parte al livello 1 (l'Erbacciaia: Erba alta,
## spec par. 5, per un mazzo di partenza pari alle altre).
static func start_cards(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(find(id).get(&"start_cards", []))
	return out
