class_name UpgradeCatalog
extends RefCounted
## Upgrade del primo prototipo (PROGRESSION_SPEC, sezione 6; D-038). Dati in
## un solo posto; gli effetti li applica ArenaRun. Ogni voce:
## id, deck (&"common" o una classe di ClassCatalog: spec D-092, par. 5), name, category,
## rarity, max_level, requires ("", "caravan" o "module:<id del modulo>": la carta compare
## solo con la carovana, o con almeno una macchina con quel modulo), text. Le vecchie carte
## della chiodatrice (nail_*) sono diventate i suoi livelli e bivi in WeaponCatalog.
## Le voci con `filler = true` sono ripetibili senza limite (max_level 0) e
## compaiono solo quando le carte vere non bastano a riempire l'offerta (D-056).
## `values` (R-15): le grandezze dell'effetto, lette da `ArenaRun.apply_upgrade` e
## sostituite nel `text` con `{chiave}`: un solo posto da ritoccare per bilanciare.

enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }

const RARITY_NAMES: Array[String] = ["COMUNE", "NON COMUNE", "RARO", "LEGGENDARIO"]
## Lineari, convertiti dalla UI.
const RARITY_COLORS: Array[Color] = [
	Color(0.75, 0.75, 0.72), Color(0.25, 0.85, 0.3), Color(0.2, 0.55, 1.0), Color(1.0, 0.55, 0.05),
]
const CATEGORY_NAMES := {
	&"weapon": "Arma", &"companion": "Carovana", &"terrain": "Tool terreno", &"character": "Personaggio",
}


## Valore numerico di un upgrade (`values[key]`), o [param default] se manca.
static func value(id: StringName, key: StringName, default: float = 0.0) -> float:
	for entry in all():
		if entry.id == id:
			var values: Dictionary = entry.get("values", {})
			return float(values.get(key, default))
	return default


## Testo della carta con i valori sostituiti (es. "{rate}" -> "25").
static func describe(entry: Dictionary) -> String:
	var text: String = entry.text
	var values: Dictionary = entry.get("values", {})
	for key in values:
		var v: Variant = values[key]
		var shown := (str(int(v)) if is_equal_approx(float(v), roundf(float(v))) else "%.1f" % float(v)) if typeof(v) != TYPE_STRING else String(v)
		text = text.replace("{%s}" % key, shown)
	return text


static func all() -> Array[Dictionary]:
	return [
		# --- Carte di livello dei moduli (scelta 5 di D-093): valgono per tutte le macchine del
		# tipo, anche quelle che arrivano dopo; gli effetti li calcolano i moduli dalla taratura.
		{id = &"turret_rate", deck = &"common", name = "Torretta veloce", category = &"companion", rarity = Rarity.UNCOMMON, max_level = 2,
			requires = "module:turret", values = {rate_percent = 35},
			text = "Le torrette sparano il {rate_percent}% piu spesso."},
		{id = &"magnet_range", deck = &"common", name = "Calamita potente", category = &"companion", rarity = Rarity.UNCOMMON, max_level = 1,
			requires = "module:magnet", values = {radius_per_level = 1.5},
			text = "Le calamite attirano {radius_per_level} m piu lontano."},
		{id = &"companion_cargo", deck = &"common", name = "Cassone rinforzato", category = &"companion", rarity = Rarity.UNCOMMON, max_level = 2,
			requires = "module:cargo", values = {capacity = 2, scrap_now = 1},
			text = "Ogni Cassone porta {capacity} rottami in piu e ne trovi {scrap_now} subito."},
		{id = &"dig_blast", deck = &"sapper", name = "Scavo esplosivo", category = &"terrain", rarity = Rarity.UNCOMMON, max_level = 3,
			requires = "", values = {damage = 2, radius = 2.4, radius_per_level = 0.8, every_seconds = 0.5},
			text = "Ogni {every_seconds} s di scavo colpisce i rottamatori entro {radius} m ({damage} danni), piu {radius_per_level} m per livello."},
		{id = &"spiked_wall", deck = &"engineer", name = "Argini spinati", category = &"terrain", rarity = Rarity.UNCOMMON, max_level = 2,
			requires = "", values = {damage = 1, interval = 0.8, interval_level_2 = 0.5},
			text = "I rottamatori che spingono contro un argine si fanno male ({damage} danno ogni {interval} s)."},
		{id = &"brush_size", deck = &"engineer", name = "Pala larga", category = &"terrain", rarity = Rarity.COMMON, max_level = 3,
			requires = "", values = {radius_per_level = 0.4},
			text = "Il pennello del tool e piu largo di {radius_per_level} m per livello."},
		{id = &"boots", deck = &"common", name = "Scarponi slacciati", category = &"character", rarity = Rarity.COMMON, max_level = 3,
			requires = "", values = {speed_percent = 10}, text = "Corri il {speed_percent}% piu veloce."},
		{id = &"patch", deck = &"common", name = "Toppa", category = &"character", rarity = Rarity.COMMON, max_level = 3,
			requires = "", values = {health = 1}, text = "Un punto vita in piu e ti rimetti in sesto del tutto."},
		{id = &"reach", deck = &"common", name = "Tasche larghe", category = &"character", rarity = Rarity.COMMON, max_level = 3,
			requires = "", values = {radius_percent = 40}, text = "Raggio di raccolta dei frammenti piu ampio del {radius_percent}%."},
		{id = &"torch_range", deck = &"common", name = "Torcia", category = &"character", rarity = Rarity.COMMON, max_level = 3,
			requires = "", values = {radius_per_level = 1.5}, text = "La tua luce arriva {radius_per_level} metri piu lontano."},
		{id = &"beacon_range", deck = &"common", name = "Faro", category = &"companion", rarity = Rarity.UNCOMMON, max_level = 3,
			requires = "module:beacon", values = {radius_per_level = 2.0}, text = "I fari illuminano {radius_per_level} metri piu lontano."},
		# --- Mazzi di classe (spec D-092, par. 5): effetti in ClassPerks -----------------------
		{id = &"reinforced_banks", deck = &"engineer", name = "Argini rinforzati", category = &"terrain", rarity = Rarity.UNCOMMON, max_level = 2,
			requires = "", values = {percent = 30}, text = "I rottamatori rosicchiano i tuoi argini il {percent}% piu piano per livello."},
		{id = &"quick_cast", deck = &"engineer", name = "Getto rapido", category = &"terrain", rarity = Rarity.COMMON, max_level = 2,
			requires = "", values = {percent = 20}, text = "Alzare costa il {percent}% di terra in meno per livello."},
		{id = &"short_fuse", deck = &"sapper", name = "Miccia corta", category = &"weapon", rarity = Rarity.COMMON, max_level = 3,
			requires = "", values = {percent = 10}, text = "Le armi attive si ricaricano il {percent}% prima per livello."},
		{id = &"chain_reaction", deck = &"sapper", name = "Reazione a catena", category = &"terrain", rarity = Rarity.RARE, max_level = 1,
			requires = "", values = {damage = 1, radius = 1.5},
			text = "Un rottamatore ucciso dentro un cratere esplode: {damage} danno entro {radius} m."},
		{id = &"tuned_engine", deck = &"mechanic", name = "Motore truccato", category = &"companion", rarity = Rarity.UNCOMMON, max_level = 2,
			requires = "caravan", values = {speed_percent = 20, damage = 1},
			text = "Le macchine vanno il {speed_percent}% piu veloci per livello e travolgono chi incontrano ({damage} danno)."},
		{id = &"field_weld", deck = &"mechanic", name = "Saldatura al volo", category = &"companion", rarity = Rarity.RARE, max_level = 1,
			requires = "caravan", values = {seconds = 45, range = 4},
			text = "Con una delle macchine entro {range} m recuperi un punto vita ogni {seconds} s."},
		{id = &"tall_grass", deck = &"weeder", name = "Erba alta", category = &"terrain", rarity = Rarity.COMMON, max_level = 2,
			requires = "", values = {percent = 20}, text = "Sul prato i rottamatori rallentano del {percent}% per livello."},
		{id = &"healing_bush", deck = &"weeder", name = "Cespuglio medicinale", category = &"character", rarity = Rarity.UNCOMMON, max_level = 2,
			requires = "", values = {seconds = 60, seconds_level_2 = 40},
			text = "Stando sul prato recuperi un punto vita ogni {seconds} s ({seconds_level_2} s al livello 2)."},
		{id = &"pocket_seeds", deck = &"weeder", name = "Semi in tasca", category = &"terrain", rarity = Rarity.COMMON, max_level = 1,
			requires = "", values = {}, text = "Gli argini che alzi si coprono di prato."},
		{id = &"field_patch", deck = &"common", name = "Rattoppo al volo", category = &"character", rarity = Rarity.COMMON, max_level = 0,
			requires = "", filler = true, values = {heal = 1}, text = "Recuperi un punto vita."},
		{id = &"lucky_scrap", deck = &"common", name = "Rottame di fortuna", category = &"companion", rarity = Rarity.COMMON, max_level = 0,
			requires = "module:cargo", filler = true, values = {scrap_now = 1}, text = "Un rottame in piu in un Cassone, se c'e posto."},
		{id = &"nail_jar", deck = &"common", name = "Barattolo di chiodi", category = &"weapon", rarity = Rarity.COMMON, max_level = 0,
			requires = "", filler = true, values = {damage = 2, radius = 7.0},
			text = "Scoppia un barattolo: {damage} danni a tutti i rottamatori entro {radius} metri."},
	]
