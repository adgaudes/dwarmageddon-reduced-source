class_name PlayerProfileService
extends Node
## Profilo permanente del giocatore (D-049): rottami in Officina, upgrade
## permanenti comprati (anche gli sblocchi delle armi), run giocate e vinte, ultima classe
## scelta e fusioni scoperte (versione 2, D-092), combinazioni delle macchine scoperte
## (versione 3, D-093: sezione [machines]). Salvato in `user://profile.cfg`,
## separato dalle impostazioni. Registrato come autoload `PlayerProfile`; gli
## altri script lo raggiungono con `get_node("/root/PlayerProfile")` tipizzato
## `PlayerProfileService` (il nome globale non esiste in --check-only ne nei test).

signal changed

const DEFAULT_PATH := "user://profile.cfg"
## Versione del file (R-19): un profilo di versione piu alta viene letto per quello che si
## capisce; le voci sconosciute si conservano e si riscrivono, non si perdono.
const VERSION := 3

## Percorso del salvataggio; vuoto = non si salva (test).
var profile_path := DEFAULT_PATH
## Rottami da spendere in Officina.
var scrap := 0
## Livello di ogni upgrade permanente posseduto.
var levels: Dictionary[StringName, int] = {}
var runs := 0
var victories := 0
## Livelli di campagna sbloccati: i primi N del LevelCatalog (D-066).
var levels_unlocked := 1
## Id dei livelli completati almeno una volta.
var completed_levels: PackedStringArray = []
## Classe scelta l'ultima volta (versione 2): la run parte con questa.
var last_class: StringName = ClassCatalog.DEFAULT
## Fusioni scoperte almeno una volta (ricettario dell'Officina, versione 2).
var recipes: PackedStringArray = []
## Combinazioni delle macchine scoperte almeno una volta (versione 3, D-093): id di
## MachineCatalog; quelli che questa versione non conosce si conservano.
var machine_combos: PackedStringArray = []
## Esito dell'ultimo salvataggio (R-18): OK, oppure l'errore che i pannelli possono mostrare.
var last_save_error := OK
## Versione letta dal file (0 = file senza versione o assente).
var loaded_version := 0
## Da dove viene il profilo caricato: "main", "tmp" o "bak" (recupero, audit S-01), "" se nuovo.
var load_source := ""
## Copia del file illeggibile trovata al caricamento (audit S-02), oppure "".
var corrupt_copy := ""
## Upgrade con id non in catalogo (file di una versione diversa): conservati tali e quali.
var _unknown_upgrades: Dictionary[String, int] = {}
## Chiavi di [profile] e sezioni intere che questa versione non conosce (S-03): si riscrivono.
var _unknown_profile_keys: Dictionary[String, Variant] = {}
var _unknown_sections: Dictionary[String, Dictionary] = {}
## Chiavi di [machines] diverse da `combinations` (versioni future): si riscrivono tali e quali.
var _unknown_machine_keys: Dictionary[String, Variant] = {}

const KNOWN_PROFILE_KEYS: Array[String] = ["version", "scrap", "runs", "victories", "levels_unlocked", "completed_levels", "last_class"]


func _init() -> void:
	# Sotto i test (SceneTree con script) si parte da un profilo vuoto e non si
	# scrive nulla: il profilo reale del giocatore non deve cambiare ne falsare i test.
	# Deciso gia qui: un test puo usare il profilo prima del primo frame.
	var main_loop := Engine.get_main_loop()
	if main_loop != null and main_loop.get_script() != null:
		profile_path = ""


func _ready() -> void:
	if not profile_path.is_empty():
		load_profile()


func reset() -> void:
	scrap = 0
	levels.clear()
	runs = 0
	victories = 0
	levels_unlocked = 1
	completed_levels.clear()
	last_class = ClassCatalog.DEFAULT
	recipes.clear()
	machine_combos.clear()
	loaded_version = 0
	load_source = ""
	corrupt_copy = ""
	_unknown_upgrades.clear()
	_unknown_profile_keys.clear()
	_unknown_sections.clear()
	_unknown_machine_keys.clear()


func level_of(id: StringName) -> int:
	return levels.get(id, 0)


## Costo del prossimo livello di [param id]; -1 se e al massimo o non esiste.
func cost_of(id: StringName) -> int:
	var entry := PermanentCatalog.find(id)
	if entry.is_empty() or level_of(id) >= (entry.costs as Array).size():
		return -1
	return entry.costs[level_of(id)]


func can_buy(id: StringName) -> bool:
	var cost := cost_of(id)
	return cost >= 0 and scrap >= cost


## Compra il prossimo livello; false se e al massimo o i rottami non bastano.
func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	scrap -= cost_of(id)
	levels[id] = level_of(id) + 1
	print("PROTOTYPE01_PERMANENT_BOUGHT id=%s level=%d scrap=%d" % [id, levels[id], scrap])
	save_profile()
	changed.emit()
	return true


## Ricorda la classe (sconosciute ignorate) e salva.
func set_last_class(id: StringName) -> void:
	if ClassCatalog.find(id).is_empty() or id == last_class:
		return
	last_class = id
	save_profile()
	changed.emit()


## Segna la fusione come scoperta; vero la prima volta (e salva).
func discover_recipe(id: StringName) -> bool:
	if has_recipe(id):
		return false
	recipes.append(String(id))
	print("PROTOTYPE01_RECIPE_DISCOVERED id=%s" % id)
	save_profile()
	changed.emit()
	return true


func has_recipe(id: StringName) -> bool:
	return recipes.has(String(id))


## Segna la combinazione delle macchine come scoperta; vero la prima volta (e salva).
func discover_combo(id: StringName) -> bool:
	if has_combo(id):
		return false
	machine_combos.append(String(id))
	print("PROTOTYPE01_COMBO_DISCOVERED id=%s" % id)
	save_profile()
	changed.emit()
	return true


func has_combo(id: StringName) -> bool:
	return machine_combos.has(String(id))


## Armi comuni sbloccate in Officina (voci `unlock_<arma>` comprate).
func unlocked_weapons() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in PermanentCatalog.all():
		var weapon: StringName = entry.get(&"weapon", &"")
		if weapon != &"" and level_of(entry.id) >= 1:
			out.append(weapon)
	return out


func has_completed(level_id: StringName) -> bool:
	return completed_levels.has(String(level_id))


## Fine di un livello: incassa i rottami portati fuori. Una vittoria sblocca il livello
## successivo a [param level_index] (da 0) e segna [param level_id] come completato.
## Restituisce l'esito del salvataggio (F-03): il chiamante lo mostra, lo stato in memoria
## resta aggiornato comunque.
func bank_run(scrap_out: int, victory: bool, level_index := 0, level_id: StringName = &"") -> Error:
	scrap += maxi(scrap_out, 0)
	runs += 1
	if victory:
		victories += 1
		levels_unlocked = maxi(levels_unlocked, level_index + 2)
		if not level_id.is_empty() and not completed_levels.has(String(level_id)):
			completed_levels.append(String(level_id))
	print("PROTOTYPE01_PROFILE_BANKED scrap_out=%d total=%d runs=%d victories=%d" % [scrap_out, scrap, runs, victories])
	var error := save_profile()
	changed.emit()
	return error


## Carica un file; valori assenti o non validi diventano quelli di un profilo nuovo. Se il
## file manca o non si legge si recupera l'ultimo salvataggio buono (`ConfigIO`); un file
## illeggibile resta copiato a parte, cosi il prossimo salvataggio non lo distrugge.
func load_profile(path_override: String = "") -> Error:
	if not path_override.is_empty():
		profile_path = path_override
	reset()
	if profile_path.is_empty():
		return OK
	var result := ConfigIO.load_recovering(profile_path)
	corrupt_copy = result.corrupt_copy
	if not corrupt_copy.is_empty():
		print("PROTOTYPE01_PROFILE_CORRUPT copy=%s" % corrupt_copy)
	var error: Error = result.error
	if error == ERR_FILE_NOT_FOUND:
		return OK
	if error != OK:
		return error
	var config: ConfigFile = result.config
	load_source = result.source
	if load_source != "main":
		print("PROTOTYPE01_PROFILE_RECOVERED from=%s" % load_source)
	loaded_version = _validated_count(config.get_value("profile", "version", 0))
	scrap = _validated_count(config.get_value("profile", "scrap", 0))
	runs = _validated_count(config.get_value("profile", "runs", 0))
	victories = _validated_count(config.get_value("profile", "victories", 0))
	levels_unlocked = maxi(_validated_count(config.get_value("profile", "levels_unlocked", 1)), 1)
	var completed: Variant = config.get_value("profile", "completed_levels", PackedStringArray())
	if completed is PackedStringArray or completed is Array:
		for item in completed:
			if item is String and not completed_levels.has(item):
				completed_levels.append(item)
	var saved_class := StringName(str(config.get_value("profile", "last_class", String(ClassCatalog.DEFAULT))))
	last_class = saved_class if not ClassCatalog.find(saved_class).is_empty() else ClassCatalog.DEFAULT
	if config.has_section("recipes"):
		for key in config.get_section_keys("recipes"):
			if config.get_value("recipes", key, false) == true and not recipes.has(key):
				recipes.append(key)
	# [machines] (versione 3): una lista di id non valida vale vuota, senza errori.
	if config.has_section("machines"):
		for key in config.get_section_keys("machines"):
			var value: Variant = config.get_value("machines", key)
			if key != "combinations":
				_unknown_machine_keys[key] = value
			elif value is PackedStringArray or value is Array:
				for item: Variant in value:
					if item is String and not machine_combos.has(item):
						machine_combos.append(item)
	for entry in PermanentCatalog.all():
		var id: StringName = entry.id
		var level := mini(_validated_count(config.get_value("upgrades", String(id), 0)), (entry.costs as Array).size())
		if level > 0:
			levels[id] = level
	if config.has_section("upgrades"):
		for key in config.get_section_keys("upgrades"):
			if PermanentCatalog.find(StringName(key)).is_empty():
				_unknown_upgrades[key] = _validated_count(config.get_value("upgrades", key, 0))
	for section in config.get_sections():
		if section == "upgrades" or section == "recipes" or section == "machines":
			continue
		for key in config.get_section_keys(section):
			if section == "profile":
				if not KNOWN_PROFILE_KEYS.has(key):
					_unknown_profile_keys[key] = config.get_value(section, key)
				continue
			if not _unknown_sections.has(section):
				_unknown_sections[section] = {}
			_unknown_sections[section][key] = config.get_value(section, key)
	return OK


func save_profile(path_override: String = "") -> Error:
	if not path_override.is_empty():
		profile_path = path_override
	if profile_path.is_empty():
		return OK
	var config := ConfigFile.new()
	for section: String in _unknown_sections:
		for key: String in _unknown_sections[section]:
			config.set_value(section, key, _unknown_sections[section][key])
	for key: String in _unknown_profile_keys:
		config.set_value("profile", key, _unknown_profile_keys[key])
	# Un file di una versione piu alta resta tale: questa build non lo "declassa" (S-03).
	config.set_value("profile", "version", maxi(VERSION, loaded_version))
	config.set_value("profile", "scrap", scrap)
	config.set_value("profile", "runs", runs)
	config.set_value("profile", "victories", victories)
	config.set_value("profile", "levels_unlocked", levels_unlocked)
	config.set_value("profile", "completed_levels", completed_levels)
	config.set_value("profile", "last_class", String(last_class))
	for id in recipes:
		config.set_value("recipes", id, true)
	config.set_value("machines", "combinations", machine_combos)
	for key in _unknown_machine_keys:
		config.set_value("machines", key, _unknown_machine_keys[key])
	for id: StringName in levels:
		config.set_value("upgrades", String(id), levels[id])
	for key in _unknown_upgrades:
		config.set_value("upgrades", key, _unknown_upgrades[key])
	last_save_error = ConfigIO.save_atomic(config, profile_path)
	if last_save_error != OK:
		# Marker su stderr, non push_error: il gate conta le righe "ERROR:" e qui un test lo provoca apposta.
		printerr("PROTOTYPE01_PROFILE_SAVE_FAILED path=%s error=%d" % [profile_path, last_save_error])
	return last_save_error


static func _validated_count(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return maxi(value, 0)
	if typeof(value) == TYPE_FLOAT and not is_nan(value):
		return maxi(int(value), 0)
	return 0
