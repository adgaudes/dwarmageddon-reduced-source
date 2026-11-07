class_name ConfigIO
extends RefCounted
## Salvataggio e caricamento robusti di un ConfigFile (R-12, audit del 14 ottobre S-01/S-02).
## Si scrive su `<percorso>.tmp`; il file buono attuale diventa `<percorso>.bak`; poi il
## `.tmp` prende il suo posto. Su Windows `DirAccess.rename` di Godot cancella la
## destinazione prima di spostare (`dir_access_windows.cpp`): mai rinominare sopra il file
## vero, e mai cancellare il `.tmp` se l'ultimo passo fallisce. Al caricamento, se il file
## manca o non si legge, si ripiega sul `.tmp` (piu recente) e poi sul `.bak`; un file
## illeggibile viene copiato in `<percorso>.corrupt-<ora>` prima che qualcuno lo sovrascriva.


static func save_atomic(config: ConfigFile, path: String) -> Error:
	var temp := path + ".tmp"
	var error := config.save(temp)
	if error != OK:
		return error
	var base := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		error = DirAccess.rename_absolute(base, base + ".bak")
		if error != OK:
			# Il vero e intatto; il .tmp resta per il recupero.
			return error
	# Se fallisce restano .bak (precedente) e .tmp (nuovo): `load_recovering` li trova.
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), base)


## Carica [param path] con ripiego. Restituisce `config` (vuoto se nulla si legge),
## `error` (OK se letto o recuperato, ERR_FILE_NOT_FOUND se non esiste nulla, altrimenti
## l'errore del file principale), `source` ("main", "tmp", "bak" o "") e `corrupt_copy`
## (percorso della copia del file principale illeggibile, oppure "").
static func load_recovering(path: String) -> Dictionary:
	var config := ConfigFile.new()
	var main_error := config.load(path)
	if main_error == OK:
		return {config = config, error = OK, source = "main", corrupt_copy = ""}
	var corrupt_copy := ""
	if main_error != ERR_FILE_NOT_FOUND and FileAccess.file_exists(path):
		corrupt_copy = "%s.corrupt-%d" % [path, int(Time.get_unix_time_from_system())]
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(corrupt_copy))
	for suffix: String in [".tmp", ".bak"]:
		if not FileAccess.file_exists(path + suffix):
			continue
		var candidate := ConfigFile.new()
		if candidate.load(path + suffix) == OK:
			return {config = candidate, error = OK, source = suffix.trim_prefix("."), corrupt_copy = corrupt_copy}
	return {config = ConfigFile.new(), error = main_error, source = "", corrupt_copy = corrupt_copy}
