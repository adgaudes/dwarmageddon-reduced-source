class_name LevelCatalog
extends RefCounted
## Catalogo dei livelli della prima campagna (D-040, D-066): ordine, titolo, scena e
## boss di ciascuno. Il profilo sblocca i livelli per indice (`levels_unlocked`); un
## livello senza scena e "in costruzione" e si vede nella mappa ma non si gioca.
## Statico e in codice: tre voci non meritano una risorsa.

const LEVELS: Array[Dictionary] = [
	{id = &"district", title = "Quartiere in rovina", boss = "Il Demolitore", scene = "res://scenes/main/arena_run.tscn",
		text = "Piazza e cortili. Il Demolitore smonta i terrapieni e alza barricate."},
	{id = &"railway", title = "La ferrovia", boss = "La Trivella", scene = "res://scenes/main/railway_run.tscn",
		text = "Un corridoio di binari: il treno spiana la fascia, la Trivella carica dritta."},
	{id = &"yard", title = "Il cantiere", boss = "La Gru", scene = "",
		text = "In costruzione."},
]


static func all() -> Array[Dictionary]:
	return LEVELS


static func count() -> int:
	return LEVELS.size()


## Indice (da 0) del livello, -1 se l'id non esiste.
static func index_of(id: StringName) -> int:
	for i in LEVELS.size():
		if LEVELS[i].id == id:
			return i
	return -1


static func find(id: StringName) -> Dictionary:
	var index := index_of(id)
	return LEVELS[index] if index >= 0 else {}


static func title_of(id: StringName) -> String:
	return find(id).get("title", "")


static func scene_of(id: StringName) -> String:
	return find(id).get("scene", "")


## Un livello e giocabile se ha una scena.
static func is_playable(id: StringName) -> bool:
	return not scene_of(id).is_empty()


## Id del livello successivo, vuoto se questo e l'ultimo.
static func next_of(id: StringName) -> StringName:
	var index := index_of(id)
	return LEVELS[index + 1].id if index >= 0 and index + 1 < LEVELS.size() else &""


## Il primo livello della campagna.
static func first() -> StringName:
	return LEVELS[0].id
