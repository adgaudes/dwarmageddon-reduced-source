extends SceneTree
## Test del profilo permanente e dell'Officina (D-049). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/workshop_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")
const ProfileScript := preload("res://scripts/services/player_profile.gd")
const TEMP_PATH := "user://test_profile.cfg"
const RECOVERY_PATH := "user://test_profile_recovery.cfg"

var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_test_catalog()
	_test_profile_rules()
	_test_persistence()
	_test_save_recovery()
	await _test_new_profile_changes_nothing()
	await _test_permanent_upgrades_apply()
	await _test_class_permanents()
	await _test_unlocks_and_recipes()
	await _test_workshop_tabs()
	await _test_recipe_book()
	await _test_combinations_book()
	await _test_banking_and_workshop_flow()
	_remove_profile_files(TEMP_PATH)
	# T-12: i nodi messi in coda con queue_free vanno liberati prima di uscire, o
	# il motore segnala istanze ObjectDB perse all'uscita.
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Autoload a runtime: nel test runner il nome globale non esiste in compilazione.
func _profile() -> PlayerProfileService:
	return root.get_node("PlayerProfile") as PlayerProfileService


func _start_run() -> Node3D:
	var scene: Node3D = RunScene.instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	return scene


func _end_run(scene: Node3D) -> void:
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	await _frames(2)


func _test_catalog() -> void:
	print("catalog")
	var ids := {}
	var sane := true
	for entry in PermanentCatalog.all():
		ids[entry.id] = true
		var costs: Array = entry.costs
		sane = sane and not costs.is_empty() and not String(entry.name).is_empty() and not String(entry.text).is_empty()
		for i in costs.size():
			sane = sane and costs[i] > 0 and (i == 0 or costs[i] > costs[i - 1])
	_check(PermanentCatalog.all().size() >= 6 and ids.size() == PermanentCatalog.all().size(), "almeno 6 upgrade permanenti con id distinti (%d)" % ids.size())
	_check(sane, "ogni upgrade ha nome, testo e costi crescenti")
	_check(PermanentCatalog.max_level(&"base_health") == 3 and PermanentCatalog.max_level(&"nope") == 0, "livello massimo dal numero di costi")


func _test_profile_rules() -> void:
	print("profile rules")
	var profile: PlayerProfileService = ProfileScript.new()
	profile.profile_path = ""
	_check(profile.scrap == 0 and profile.levels.is_empty() and profile.levels_unlocked == 1, "profilo nuovo: niente rottami, niente upgrade")
	_check(not profile.buy(&"base_health") and profile.level_of(&"base_health") == 0, "senza rottami non si compra")
	profile.bank_run(7, false)
	_check(profile.scrap == 7 and profile.runs == 1 and profile.victories == 0 and profile.levels_unlocked == 1, "una sconfitta incassa i rottami e conta la run")
	_check(profile.cost_of(&"base_health") == 4 and profile.buy(&"base_health"), "primo livello di Telaio rinforzato: 4 rottami")
	_check(profile.scrap == 3 and profile.level_of(&"base_health") == 1 and profile.cost_of(&"base_health") == 8, "rottami scalati, il livello successivo costa 8")
	_check(not profile.can_buy(&"base_health"), "3 rottami non bastano per il secondo livello")
	profile.bank_run(40, true)
	_check(profile.victories == 1 and profile.levels_unlocked == 2, "una vittoria sblocca il livello successivo")
	_check(profile.buy(&"base_health") and profile.buy(&"base_health"), "con i rottami si arriva al massimo")
	_check(profile.cost_of(&"base_health") == -1 and not profile.buy(&"base_health"), "al massimo non si compra oltre")
	_check(not profile.buy(&"nope"), "un id sconosciuto non si compra")
	profile.free()


func _test_persistence() -> void:
	print("persistence")
	_check(_profile().profile_path.is_empty(), "sotto i test il profilo reale non viene letto ne scritto")
	var profile: PlayerProfileService = ProfileScript.new()
	profile.profile_path = TEMP_PATH
	profile.bank_run(30, true)
	profile.buy(&"tool_reach")
	profile.buy(&"cargo")
	profile.buy(&"cargo")
	var scrap_left := profile.scrap
	var loaded: PlayerProfileService = ProfileScript.new()
	_check(loaded.load_profile(TEMP_PATH) == OK, "il profilo salvato si ricarica")
	_check(loaded.scrap == scrap_left and loaded.runs == 1 and loaded.victories == 1 and loaded.levels_unlocked == 2, "rottami e conteggi tornano uguali")
	_check(loaded.level_of(&"tool_reach") == 1 and loaded.level_of(&"cargo") == 2 and loaded.level_of(&"stock") == 0, "upgrade comprati tornano uguali")
	var config := ConfigFile.new()
	config.set_value("profile", "scrap", -50)
	config.set_value("profile", "runs", "molte")
	config.set_value("upgrades", "base_health", 99)
	config.set_value("upgrades", "inventato", 3)
	config.save(TEMP_PATH)
	_check(loaded.load_profile(TEMP_PATH) == OK and loaded.scrap == 0 and loaded.runs == 0, "valori non validi diventano zero")
	_check(loaded.level_of(&"base_health") == 3 and not loaded.levels.has(&"inventato"), "livelli oltre il massimo ridotti, id sconosciuti non applicati")
	# R-19: l'id sconosciuto sopravvive a un salvataggio e il file porta la versione.
	loaded.scrap = 7
	_check(loaded.save_profile() == OK and loaded.last_save_error == OK, "salvataggio atomico riuscito")
	var reread := ConfigFile.new()
	_check(reread.load(TEMP_PATH) == OK and reread.get_value("upgrades", "inventato", 0) == 3
		and reread.get_value("profile", "version", 0) == PlayerProfileService.VERSION and reread.get_value("profile", "scrap", 0) == 7,
		"id sconosciuto conservato e versione scritta")
	_check(not FileAccess.file_exists(TEMP_PATH + ".tmp"), "nessun file temporaneo lasciato in giro")
	# R-18: percorso non scrivibile: errore riportato, non ignorato.
	var broken: PlayerProfileService = ProfileScript.new()
	broken.profile_path = "user://non_esiste_dir/sub/profile.cfg"
	broken.scrap = 1
	_check(broken.save_profile() != OK and broken.last_save_error != OK, "salvataggio impossibile: errore riportato in last_save_error")
	broken.free()
	loaded.load_profile("user://non_esiste_profile.cfg")
	_check(loaded.scrap == 0 and loaded.levels.is_empty(), "file assente: profilo nuovo")
	profile.free()
	loaded.free()


## Audit del 14 ottobre, S-01/S-02/S-03: su Windows la rinomina di Godot cancella la
## destinazione prima di spostare; un salvataggio fallito o un file illeggibile non
## devono costare il profilo.
func _test_save_recovery() -> void:
	print("save recovery")
	var path := RECOVERY_PATH
	_remove_profile_files(path)
	var profile: PlayerProfileService = ProfileScript.new()
	profile.profile_path = path
	profile.scrap = 11
	profile.save_profile()
	profile.scrap = 12
	profile.save_profile()
	var bak := ConfigFile.new()
	_check(bak.load(path + ".bak") == OK and bak.get_value("profile", "scrap", 0) == 11,
		"il salvataggio precedente resta come copia di riserva (.bak)")
	# Salvataggio interrotto dopo aver spostato il vero in .bak: resta solo il .tmp nuovo.
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".tmp"))
	var loaded: PlayerProfileService = ProfileScript.new()
	_check(loaded.load_profile(path) == OK and loaded.scrap == 12 and loaded.load_source == "tmp",
		"file principale mancante: si recupera il .tmp (%d da %s)" % [loaded.scrap, loaded.load_source])
	# File principale illeggibile: copia conservata e recupero dal .bak.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	var garbage := FileAccess.open(path, FileAccess.WRITE)
	garbage.store_string("[profile
scrap = = =
")
	garbage.close()
	_check(loaded.load_profile(path) == OK and loaded.scrap == 11 and loaded.load_source == "bak",
		"file illeggibile: si recupera il .bak (%d da %s)" % [loaded.scrap, loaded.load_source])
	_check(not loaded.corrupt_copy.is_empty() and FileAccess.get_file_as_string(loaded.corrupt_copy).begins_with("[profile
scrap"),
		"il file illeggibile e conservato tale e quale (%s)" % loaded.corrupt_copy)
	# Nessuna copia valida: profilo vuoto, ma il primo salvataggio non distrugge l'originale.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	garbage = FileAccess.open(path, FileAccess.WRITE)
	garbage.store_string("[profile
scrap = = =
")
	garbage.close()
	_check(loaded.load_profile(path) != OK and loaded.scrap == 0 and not loaded.corrupt_copy.is_empty(), "nessuna copia valida: profilo nuovo e errore riportato")
	var kept := loaded.corrupt_copy
	loaded.save_profile()
	_check(FileAccess.file_exists(kept) and FileAccess.get_file_as_string(kept).begins_with("[profile
scrap"), "dopo il salvataggio la copia del file illeggibile c'e ancora")
	# Rinomina finale impossibile (al posto del file c'e una cartella): il .tmp non si cancella.
	_remove_profile_files(path)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path))
	profile.scrap = 30
	_check(profile.save_profile() != OK and FileAccess.file_exists(path + ".tmp"), "rinomina fallita: il .tmp con i dati nuovi resta su disco")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# S-03: chiavi sconosciute di [profile] e versione piu alta sopravvivono a un salvataggio.
	_remove_profile_files(path)
	var future := ConfigFile.new()
	future.set_value("profile", "version", PlayerProfileService.VERSION + 4)
	future.set_value("profile", "scrap", 5)
	future.set_value("profile", "prestige", 2)
	future.set_value("cosmetics", "hat", "red")
	future.save(path)
	loaded.load_profile(path)
	loaded.scrap = 6
	loaded.save_profile()
	var reread := ConfigFile.new()
	_check(reread.load(path) == OK and reread.get_value("profile", "prestige", 0) == 2 and reread.get_value("cosmetics", "hat", "") == "red"
		and reread.get_value("profile", "version", 0) == PlayerProfileService.VERSION + 4 and reread.get_value("profile", "scrap", 0) == 6,
		"chiavi e sezioni sconosciute e versione piu alta conservate")
	_remove_profile_files(path)
	profile.free()
	loaded.free()


func _remove_profile_files(path: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with(path.get_file() + ".corrupt"):
			dir.remove(file)


func _test_new_profile_changes_nothing() -> void:
	print("new profile")
	_profile().reset()
	var scene := _start_run()
	await _frames(3)
	var run: ArenaRun = scene.get_node(^"Run")
	var player: PlayerCharacter = scene.get_node(^"Player")
	var caravan: Caravan = scene.get_node(^"Caravan")
	_check(player.max_health == run.tuning.player_max_health and is_zero_approx(player.tool_range_bonus_m), "vita e portata del tool come da tuning")
	_check(caravan.capacity == caravan.tuning.cargo_capacity and caravan.carried == caravan.tuning.starting_scrap, "cassone come da tuning")
	_check(caravan.machines.size() == 1 and caravan.count_of(&"turret") == 0, "nessuna torretta: una sola macchina, il Cassone")
	await _end_run(scene)


func _test_permanent_upgrades_apply() -> void:
	print("permanent upgrades")
	var profile := _profile()
	profile.reset()
	profile.levels = {&"tool_reach": 1, &"base_health": 2, &"reflexes": 1, &"cargo": 1, &"stock": 1, &"fixed_turret": 1, &"salvage": 1, &"pack_size": 1}
	# La Torretta fissa e del Meccanico (D-092, piano 4).
	profile.last_class = &"mechanic"
	var scene := _start_run()
	await _frames(3)
	var run: ArenaRun = scene.get_node(^"Run")
	var player: PlayerCharacter = scene.get_node(^"Player")
	var caravan: Caravan = scene.get_node(^"Caravan")
	var field: TerrainField = scene.get_node(^"TerrainField")
	_check(player.max_health == run.tuning.player_max_health + 2 and player.health == player.max_health, "Telaio rinforzato 2: vita %d" % player.max_health)
	_check(is_equal_approx(player.invulnerability_seconds, run.tuning.player_invulnerability + 0.2), "Riflessi: invulnerabilita %.1f s" % player.invulnerability_seconds)
	var reach := Vector2(player.terrain_target.x - player.global_position.x, player.terrain_target.z - player.global_position.z).length()
	_check(is_equal_approx(player.tool_range_bonus_m, 1.2) and absf(reach - (field.tuning.tool_range_m + 1.2)) < 0.05, "Prolunga: il tool arriva a %.1f m" % reach)
	_check(is_equal_approx(player.pack.capacity, field.tuning.pack_capacity_m3 + 20.0), "Zainetto largo: capacita %.0f m3" % player.pack.capacity)
	_check(caravan.capacity == caravan.tuning.cargo_capacity + 2, "Cassone saldato: capacita %d" % caravan.capacity)
	_check(caravan.carried == caravan.tuning.starting_scrap + 2, "Scorta: parte con %d rottami" % caravan.carried)
	# Torretta fissa (scelta 6 di D-093): una seconda macchina, con la Torretta; il capofila
	# resta il Cassone.
	var turrets := caravan.modules_of(&"turret")
	_check(caravan.machines.size() == 2 and turrets.size() == 1 and caravan.lead().has_module(&"cargo"),
		"Torretta fissa: due macchine, la seconda con la Torretta")
	if turrets.size() == 1:
		var turret := turrets[0] as TurretModule
		var machine := turret.machine
		_check(machine != caravan.lead() and machine.has_node(^"TurretPart") and not caravan.lead().has_node(^"TurretPart"),
			"il pezzo della torretta sta sulla sua macchina, non sul Cassone")
		_check(turret.weapon().is_inside_tree() and turret.weapon().shooter == machine and turret.weapon().director == run.director,
			"Torretta fissa: in funzione dall'inizio, spara dalla sua macchina")
		_check(run.write_queue.bodies.has(machine), "la macchina della Torretta sta in write_queue.bodies")
		var ground := field.height_at(machine.global_position) + Caravan.GROUND_CLEARANCE
		_check(absf(machine.global_position.y - ground) < 0.1, "e poggia sul suolo (quota %.2f, suolo %.2f)" % [machine.global_position.y, ground])
	_check(run.progression.level_of(&"turret_rate") == 0, "la Torretta fissa non consuma livelli di Torretta veloce")
	_check(run.scrap_out(false) == int(floor(caravan.carried * 0.75)), "Paracadute: morendo si salvano tre quarti (%d)" % run.scrap_out(false))
	await _end_run(scene)


## Piano 4: gli upgrade di una classe valgono solo giocandola.
func _test_class_permanents() -> void:
	print("upgrade permanenti di classe")
	var profile := _profile()
	profile.reset()
	profile.levels = {&"fixed_turret": 1, &"toolbox": 2, &"spare_stakes": 1}
	profile.last_class = &"engineer"
	var scene := _start_run()
	await _frames(3)
	var run: ArenaRun = scene.get_node(^"Run")
	_check(run.class_id == &"engineer", "la classe viene dal profilo")
	var engineer_caravan: Caravan = scene.get_node(^"Caravan")
	_check(engineer_caravan.machines.size() == 1 and engineer_caravan.count_of(&"turret") == 0, "Torretta fissa: non la monta l'Ingegnere")
	_check(run.loadout.level_of(&"nailgun") == 2 and run.loadout.level_of(&"seismic_stake") == 2, "Cassetta degli attrezzi 2: chiodatrice e picchetto al livello 2")
	var stake := run.loadout.weapon(&"seismic_stake") as ActiveWeapon
	_check(is_equal_approx(stake.cooldown_total(), 15.0 * 0.85 * 0.9), "Picchetti di scorta: ricarica -10%% (%.2f s)" % stake.cooldown_total())
	await _end_run(scene)
	profile.levels = {&"fixed_turret": 1, &"good_oil": 1, &"toolbox": 2}
	profile.last_class = &"mechanic"
	scene = _start_run()
	await _frames(3)
	run = scene.get_node(^"Run")
	var caravan: Caravan = scene.get_node(^"Caravan")
	_check(run.class_id == &"mechanic" and caravan.machines.size() == 2 and caravan.count_of(&"turret") == 1, "Torretta fissa: la monta il Meccanico")
	_check(run.loadout.level_of(&"nailgun") == 0, "la Cassetta dell'Ingegnere non vale per il Meccanico")
	# Valore sul disco, fuori dalla cache: `load()` restituirebbe la stessa istanza che la
	# carovana tiene, e il confronto con la risorsa condivisa sarebbe con se stessa. Senza
	# ripiego: se il file mancasse il controllo fallirebbe.
	var on_disk := ResourceLoader.load("res://resources/tuning/caravan_default.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as CaravanTuning
	var base_speed: float = on_disk.max_speed
	var top_speed := caravan.tuning.max_speed * caravan.speed_scale
	_check(on_disk != caravan.tuning and is_equal_approx(top_speed, base_speed * 1.15),
		"Olio buono: macchine +15%% (%.2f)" % top_speed)
	_check(is_equal_approx(caravan.tuning.max_speed, base_speed),
		"taratura condivisa intatta (%.2f in scena, %.2f sul disco)" % [caravan.tuning.max_speed, base_speed])
	await _end_run(scene)
	profile.levels = {&"dry_powder": 2, &"charge_pack": 1}
	profile.last_class = &"sapper"
	scene = _start_run()
	await _frames(3)
	run = scene.get_node(^"Run")
	_check(run.loadout.weapon(&"dig_charge").stat(&"damage") == 6.0, "Polvere asciutta 2: la carica fa 6 danni")
	_check(run.progression.level_of(&"dig_blast") == 1 and run.dig_blast_radius > 0.0, "Zaino di cariche: Scavo esplosivo al livello 1")
	await _end_run(scene)
	profile.levels = {&"green_thumb": 1, &"good_seeds": 2}
	profile.last_class = &"weeder"
	scene = _start_run()
	await _frames(3)
	run = scene.get_node(^"Run")
	_check(run.progression.level_of(&"tall_grass") == 2, "Pollice verde: Erba alta al livello 2")
	_check(run.loadout.weapon(&"bramble").stat(&"hedge_seconds") == 21.0, "Semi buoni 2: il roveto dura 21 s")
	await _end_run(scene)
	profile.reset()


func _test_unlocks_and_recipes() -> void:
	print("sblocchi e ricette")
	var profile := _profile()
	profile.reset()
	var scene := _start_run()
	await _frames(3)
	var run: ArenaRun = scene.get_node(^"Run")
	var has_blade := func(r: ArenaRun) -> bool:
		return WeaponOffers.cards(r.loadout, r.class_id, r._unlocked_weapons()).any(func(c: Dictionary) -> bool: return c.weapon_id == &"site_blade")
	_check(not has_blade.call(run), "senza sblocco la Lama non compare fra le carte")
	await _end_run(scene)
	profile.levels = {&"unlock_site_blade": 1}
	scene = _start_run()
	await _frames(3)
	run = scene.get_node(^"Run")
	_check(has_blade.call(run), "sbloccata in Officina, la Lama compare")
	for id in [&"nailgun", &"seismic_stake"]:
		while run.loadout.level_of(id) < WeaponCatalog.MAX_LEVEL:
			if run.loadout.needs_branch(id):
				run.loadout.choose_branch(id, &"a")
			else:
				run.loadout.level_up(id)
	run.loadout.fuse(&"nailgun")
	_check(profile.has_recipe(&"fort"), "una fusione fatta in partita entra nel ricettario")
	await _end_run(scene)
	profile.reset()


## Officina fuori da una run, come nel menu: pannello nuovo aperto sul profilo autoload.
func _open_workshop() -> WorkshopPanel:
	var workshop := WorkshopPanel.new()
	root.add_child(workshop)
	await _frames(1)
	workshop.open()
	await _frames(1)
	return workshop


func _close_workshop(workshop: WorkshopPanel) -> void:
	workshop.close()
	root.remove_child(workshop)
	workshop.queue_free()
	await _frames(2)


func _visible_card(workshop: WorkshopPanel, id: StringName) -> bool:
	return workshop._buttons.has(id) and workshop._buttons[id].is_visible_in_tree()


func _focused_card(workshop: WorkshopPanel) -> Button:
	var focus := root.gui_get_focus_owner() as Button
	if focus == null or not focus.is_visible_in_tree() or not workshop.is_ancestor_of(focus):
		return null
	return focus if focus.theme_type_variation == &"CardButton" else null


func _send_joy(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	await _frames(2)


func _send_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
	await _frames(2)


## Piano 4: schede per sezione (Comune e classi) come le Impostazioni (D-091).
func _test_workshop_tabs() -> void:
	print("officina a schede")
	var profile := _profile()
	profile.reset()
	profile.last_class = &"engineer"
	var workshop: WorkshopPanel = await _open_workshop()
	var names := WorkshopPanel.TAB_NAMES
	var same_as_groups := names.size() == PermanentCatalog.GROUPS.size() + 1
	for i in PermanentCatalog.GROUPS.size():
		same_as_groups = same_as_groups and names[i] == PermanentCatalog.GROUPS[i][1]
	_check(same_as_groups and names[-1] == "Ricettario", "sei schede: le cinque sezioni e il Ricettario (%s)" % ", ".join(names))
	_check(workshop.current_tab == 1, "all'apertura la scheda della classe dell'ultima run (Ingegnere)")
	_check(_focused_card(workshop) == workshop._buttons.get(&"toolbox"), "il fuoco parte sulla prima carta della scheda")
	await _send_joy(JOY_BUTTON_RIGHT_SHOULDER)
	var focus := _focused_card(workshop)
	_check(workshop.current_tab == 2 and focus != null and focus == workshop._buttons.get(&"dry_powder"),
		"RB: scheda successiva (Guastatore) e fuoco su una sua carta visibile")
	await _send_joy(JOY_BUTTON_LEFT_SHOULDER)
	await _send_joy(JOY_BUTTON_LEFT_SHOULDER)
	_check(workshop.current_tab == 0 and _focused_card(workshop) == workshop._buttons.get(&"tool_reach"), "LB: torna indietro di una scheda alla volta")
	await _send_joy(JOY_BUTTON_LEFT_SHOULDER)
	_check(workshop.current_tab == WorkshopPanel.TAB_NAMES.size() - 1 and _focused_card(workshop) != null, "LB dalla prima scheda gira all'ultima (Ricettario)")
	await _send_key(KEY_PAGEDOWN)
	_check(workshop.current_tab == 0, "PagGiu: scheda successiva, come RB")
	await _send_key(KEY_PAGEUP)
	_check(workshop.current_tab == 5, "PagSu: scheda precedente, come LB")
	workshop.show_tab(0)
	var pressed_tabs := workshop._tab_buttons.filter(func(b: Button) -> bool: return b.button_pressed)
	_check(pressed_tabs.size() == 1 and pressed_tabs[0] == workshop._tab_buttons[0], "una sola scheda accesa, quella mostrata")
	_check(_visible_card(workshop, &"unlock_site_blade") and _visible_card(workshop, &"tool_reach") and not _visible_card(workshop, &"fixed_turret"),
		"Comune: sblocco della Lama e Prolunga, non la Torretta fissa")
	_check(not _visible_card(workshop, &"toolbox") and not _visible_card(workshop, &"good_seeds"), "Comune: niente upgrade di classe")
	var icon := workshop._buttons[&"unlock_site_blade"].get_node_or_null(^"Icon") as UiIcon
	_check(icon != null and icon.kind == WeaponCatalog.find(&"site_blade").icon, "la carta di sblocco ha l'icona dell'arma")
	workshop.show_tab(3)
	_check(_visible_card(workshop, &"fixed_turret") and _visible_card(workshop, &"good_oil") and not _visible_card(workshop, &"tool_reach"),
		"Meccanico: Torretta fissa e Olio buono, non gli upgrade comuni")
	workshop.show_tab(0)
	profile.scrap = 15
	workshop.press(&"unlock_site_blade")
	_check(profile.level_of(&"unlock_site_blade") == 1 and profile.scrap == 0 and workshop.row_text(&"unlock_site_blade").contains("1/1")
		and profile.unlocked_weapons().has(&"site_blade"), "sbloccare la Lama con 15 rottami: 1/1 e arma sbloccata")
	_check(workshop.row_text(&"unlock_site_blade").contains("Al massimo"), "la carta di sblocco comprata dice Al massimo")
	await _close_workshop(workshop)
	profile.reset()
	profile.last_class = &"weeder"
	workshop = await _open_workshop()
	_check(workshop.current_tab == 4 and _focused_card(workshop) == workshop._buttons.get(&"good_seeds"), "ultima classe Erbacciaia: si apre la sua scheda")
	await _close_workshop(workshop)
	profile.reset()


## Piano 4: il ricettario mostra le sei fusioni, scoperte o da scoprire; non si compra.
func _test_recipe_book() -> void:
	print("ricettario")
	var profile := _profile()
	profile.reset()
	profile.scrap = 50
	var workshop: WorkshopPanel = await _open_workshop()
	workshop.show_tab(WorkshopPanel.TAB_NAMES.size() - 1)
	var all_shown := true
	for id in PermanentCatalog.RECIPES:
		all_shown = all_shown and workshop._recipe_buttons.has(id) and workshop._recipe_buttons[id].is_visible_in_tree()
	_check(all_shown and workshop._recipe_buttons.size() == 6 and not _visible_card(workshop, &"tool_reach"), "Ricettario: le sei fusioni e nient'altro")
	var hidden := workshop.recipe_text(&"mortar")
	_check(hidden.contains("?") and hidden.contains("Lanciarottami") and not hidden.contains("Mortaio") and not hidden.contains("Carica da scavo"),
		"fusione da scoprire: ??? e l'indizio con la prima parte (%s)" % hidden.replace("\n", " | "))
	var card := workshop._recipe_buttons[&"mortar"]
	_check((card.get_node(^"Icon") as UiIcon).kind == &"lock", "fusione da scoprire: icona del lucchetto")
	card.grab_focus()
	_check(workshop._detail_name.text == "???" and workshop._detail_text.text.contains("Lanciarottami + ?"), "il dettaglio segue la carta della fusione da scoprire")
	var events := [0]
	workshop.purchased.connect(func(_id: StringName) -> void: events[0] += 1)
	workshop.rejected.connect(func(_id: StringName) -> void: events[0] += 1)
	card.pressed.emit()
	workshop.press(&"mortar")
	_check(events[0] == 0 and profile.scrap == 50 and not profile.has_recipe(&"mortar"), "premere una fusione non compra e non emette nulla")
	profile.discover_recipe(&"mortar")
	var shown := workshop.recipe_text(&"mortar")
	_check(shown.contains("Mortaio a crateri") and shown.contains("Lanciarottami + Carica da scavo"),
		"fusione scoperta: nome e parti (%s)" % shown.replace("\n", " | "))
	_check((card.get_node(^"Icon") as UiIcon).kind == WeaponCatalog.find(&"mortar").icon, "fusione scoperta: la sua icona")
	_check(workshop._detail_name.text == "Mortaio a crateri" and workshop._detail_text.text.contains(WeaponCatalog.find(&"mortar").text),
		"il dettaglio della fusione scoperta ha nome e testo")
	_check(workshop.recipe_text(&"fort").contains("Chiodatrice + ?"), "le altre restano da scoprire (Chiodatrice + ?)")
	await _close_workshop(workshop)
	profile.reset()


func _combo_card(workshop: WorkshopPanel, id: StringName) -> Button:
	return workshop.find_child("Combo_%s" % id, true, false) as Button


## Piano B (task 7): sotto le fusioni, le sei combinazioni delle macchine, scoperte in partita.
func _test_combinations_book() -> void:
	print("combinazioni delle macchine")
	var profile := _profile()
	profile.reset()
	var workshop: WorkshopPanel = await _open_workshop()
	var column := workshop._overlay.get_child(0).get_child(0) as Control
	var cards := workshop.find_child("Cards", true, false) as Control
	var height_first_tab := cards.get_combined_minimum_size().y
	var last := WorkshopPanel.TAB_NAMES.size() - 1
	workshop.show_tab(last)
	var all_shown := true
	for id in MachineCatalog.COMBOS:
		var card := _combo_card(workshop, id)
		all_shown = all_shown and card != null and card.is_visible_in_tree()
	var combos := workshop.find_child("Combos", true, false) as VBoxContainer
	var label := combos.get_child(0) as Label if combos != null else null
	var grid := combos.get_node_or_null(^"Grid_combos") as GridContainer if combos != null else null
	_check(all_shown and grid != null and grid.get_child_count() == 6 and grid.columns == (workshop.find_child("Grid_recipes", true, false) as GridContainer).columns,
		"Ricettario: sei carte Combo_<id> in Grid_combos, colonne come le fusioni")
	_check(label != null and label.text == "Combinazioni delle macchine" and not workshop._tab_grids.has(grid), "etichetta della sezione, griglia fuori da _tab_grids")
	_check(workshop.combo_text(&"extractor") == "???\nTrivella + ?", "combinazione da scoprire: ??? e la prima macchina (%s)" % workshop.combo_text(&"extractor").replace("\n", " | "))
	var extractor := _combo_card(workshop, &"extractor")
	_check((extractor.get_node(^"Icon") as UiIcon).kind == &"lock" and extractor.text == workshop.combo_text(&"extractor"), "da scoprire: icona del lucchetto")
	_combo_card(workshop, &"trap").grab_focus()
	_check(workshop._detail_name.text == "???" and workshop._detail_text.text == "Torretta + ?\n\nSi scopre la prima volta che fondi queste due macchine in partita.",
		"il dettaglio segue la carta della combinazione da scoprire (%s)" % workshop._detail_text.text.replace("\n", " | "))
	profile.discover_combo(&"extractor")
	_check(workshop.combo_text(&"extractor") == "Estrattore\nTrivella + Calamita" and extractor.text == workshop.combo_text(&"extractor"),
		"dopo la scoperta: Estrattore, Trivella + Calamita")
	_check((extractor.get_node(^"Icon") as UiIcon).kind == MachineCatalog.find(&"drill").icon and workshop.combo_text(&"dozer") == "???\nTrivella + ?",
		"scoperta: icona della Trivella; la Ruspa resta da scoprire")
	var last_recipe := workshop._recipe_buttons[PermanentCatalog.RECIPES[-1]]
	last_recipe.grab_focus()
	await _send_joy(JOY_BUTTON_DPAD_DOWN)
	_check(_focused_card(workshop) == extractor, "croce in giu dall'ultima fusione: focus su Combo_extractor")
	_check(workshop._detail_name.text == "Estrattore" and workshop._detail_text.text == "Trivella + Calamita\n\n" + MachineCatalog.find_combo(&"extractor").text,
		"il dettaglio della combinazione scoperta ha nome e testo")
	last_recipe.grab_focus()
	await _send_key(KEY_DOWN)
	_check(_focused_card(workshop) == extractor, "freccia giu: stessa cosa da tastiera")
	var height_book := cards.get_combined_minimum_size().y
	_check(is_equal_approx(height_book, height_first_tab) and is_equal_approx(height_book, cards.custom_minimum_size.y),
		"le carte non cambiano altezza fra le schede (%.0f e %.0f)" % [height_first_tab, height_book])
	var fits := column.get_combined_minimum_size()
	_check(fits.x <= 1280.0 and fits.y <= 800.0, "il pannello sta in 1280x800 (%.0f x %.0f)" % [fits.x, fits.y])
	workshop.show_tab(0)
	_check(not extractor.is_visible_in_tree() and not combos.is_visible_in_tree(), "le combinazioni si vedono solo nel Ricettario")
	await _close_workshop(workshop)
	profile.reset()


func _test_banking_and_workshop_flow() -> void:
	print("banking and workshop")
	var profile := _profile()
	profile.reset()
	profile.scrap = 5
	var scene := _start_run()
	await _frames(3)
	var run: ArenaRun = scene.get_node(^"Run")
	var player: PlayerCharacter = scene.get_node(^"Player")
	var panel: GameOverPanel = scene.get_node(^"GameOverPanel")
	var workshop: WorkshopPanel = scene.get_node(^"WorkshopPanel")
	var audio: RunAudio = scene.get_node(^"RunAudio")
	var expected := run.scrap_out(false)
	player._invulnerable_left = 0.0
	player.take_damage(player.health)
	await _frames(2)
	_check(panel.is_open and not panel.is_victory, "rottamato: schermata di fine livello")
	_check(profile.scrap == 5 + expected and profile.runs == 1, "i rottami salvati vanno in Officina (%d + %d)" % [5, expected])
	_check((panel._summary.text as String).contains("Rottami in Officina\t%d" % profile.scrap), "il riepilogo mostra il totale in Officina")
	_check(not workshop.is_open, "l'Officina resta chiusa finche non la si chiede")
	panel.workshop_requested.emit()
	_check(workshop.is_open and workshop.row_text(&"base_health").contains("0/3"), "dal pulsante si apre l'Officina con il catalogo")
	var bought := [0]
	var refused := [0]
	workshop.purchased.connect(func(_id: StringName) -> void: bought[0] += 1)
	workshop.rejected.connect(func(_id: StringName) -> void: refused[0] += 1)
	var before := profile.scrap
	workshop.press(&"base_health")
	_check(bought[0] == 1 and profile.level_of(&"base_health") == 1 and profile.scrap == before - 4, "comprare scala i rottami e alza il livello")
	_check(workshop.row_text(&"base_health").contains("1/3"), "la riga si aggiorna")
	workshop.press(&"fixed_turret")
	_check(refused[0] == 1 and profile.level_of(&"fixed_turret") == 0 and workshop.row_text(&"fixed_turret").contains("ne mancano"), "senza rottami l'acquisto e rifiutato e la riga dice quanti ne mancano")
	_check(audio.play_count(&"upgrade_chosen") >= 1 and audio.play_count(&"tool_reject") >= 1, "acquisto e rifiuto si sentono")
	var closed := [false]
	workshop.closed.connect(func() -> void: closed[0] = true)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await _frames(2)
	_check(closed[0] and not workshop.is_open and panel.is_open, "B chiude l'Officina e torna alla schermata di fine livello")
	await _end_run(scene)
	# R-20: abbandonare dalla pausa incassa la quota di morte.
	scene = _start_run()
	await _frames(3)
	run = scene.get_node(^"Run")
	var caravan: Caravan = scene.get_node(^"Caravan")
	caravan.add_scrap(4)
	var abandon_expected := run.scrap_out(false)
	var scrap_before := profile.scrap
	var pause_menu := root.get_node("PauseMenu")
	pause_menu.call(&"pause_game")
	await _frames(1)
	run.abandon_run()
	_check(run.is_over and profile.scrap == scrap_before + abandon_expected and abandon_expected > 0,
		"abbandono: incassata la quota di morte (%d)" % abandon_expected)
	run.abandon_run()
	_check(profile.scrap == scrap_before + abandon_expected, "un secondo abbandono non incassa due volte")
	pause_menu.call(&"resume_game")
	await _end_run(scene)
	# Il livello successivo parte con cio che si e comprato.
	scene = _start_run()
	await _frames(3)
	player = scene.get_node(^"Player")
	run = scene.get_node(^"Run")
	_check(player.max_health == run.tuning.player_max_health + 1, "la run successiva parte con l'upgrade comprato")
	await _end_run(scene)
	profile.reset()
