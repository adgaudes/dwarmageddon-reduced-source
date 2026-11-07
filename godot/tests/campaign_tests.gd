extends SceneTree
## Test della campagna (D-040, D-066): catalogo dei livelli, sblocco nel profilo,
## mappa di campagna dal menu, prossimo livello dalla vittoria, `--level=`. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/campaign_tests.gd

const MenuScene := preload("res://scenes/main/main_menu.tscn")
const RunScene := preload("res://scenes/main/arena_run.tscn")
const RailwayScene := preload("res://scenes/main/railway_run.tscn")
const ProfileScript := preload("res://scripts/services/player_profile.gd")
const TEMP_PATH := "user://campaign_tests_profile.cfg"

var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_test_catalog()
	_test_launch_option()
	_test_profile_unlocks()
	await _test_campaign_map()
	await _test_victory_offers_next_level()
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


func _profile() -> PlayerProfileService:
	return root.get_node("PlayerProfile") as PlayerProfileService


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(1)


func _test_catalog() -> void:
	print("catalog")
	_check(LevelCatalog.count() >= 3 and LevelCatalog.first() == &"district", "tre livelli, il primo e il quartiere")
	_check(LevelCatalog.index_of(&"district") == 0 and LevelCatalog.index_of(&"railway") == 1 and LevelCatalog.index_of(&"nope") == -1, "indici per id")
	_check(LevelCatalog.next_of(&"district") == &"railway" and LevelCatalog.next_of(&"railway") == &"yard", "successivo di ciascuno")
	_check(LevelCatalog.next_of(LevelCatalog.all()[LevelCatalog.count() - 1].id) == &"", "l'ultimo non ha successivo")
	_check(LevelCatalog.is_playable(&"district") and LevelCatalog.is_playable(&"railway") and not LevelCatalog.is_playable(&"yard"),
		"i primi due si giocano, il cantiere e in costruzione")
	var scenes_exist := true
	for entry in LevelCatalog.all():
		if LevelCatalog.is_playable(entry.id):
			scenes_exist = scenes_exist and ResourceLoader.exists(entry.scene)
	_check(scenes_exist, "le scene dei livelli giocabili esistono")
	_check(LevelCatalog.title_of(&"railway") == "La ferrovia" and LevelCatalog.title_of(&"nope") == "", "titoli")
	var run_scene: Node3D = RunScene.instantiate()
	var rail_scene: Node3D = RailwayScene.instantiate()
	_check((run_scene.get_node(^"Run") as ArenaRun).level_id == &"district" and (rail_scene.get_node(^"Run") as ArenaRun).level_id == &"railway",
		"ogni scena sa quale livello e")
	run_scene.free()
	rail_scene.free()


func _test_launch_option() -> void:
	print("launch option")
	_check(RunLaunchOptions.level_id(PackedStringArray(["--level=railway"])) == &"railway", "--level=railway letto")
	_check(RunLaunchOptions.level_id(PackedStringArray()) == &"", "senza opzione, vuoto")
	_check(RunLaunchOptions.wants_autostart(PackedStringArray(["--level=railway"])), "--level salta il menu")


func _test_profile_unlocks() -> void:
	print("profile unlocks")
	var profile: PlayerProfileService = ProfileScript.new()
	profile.profile_path = ""
	_check(profile.levels_unlocked == 1 and not profile.has_completed(&"district"), "profilo nuovo: solo il primo livello")
	profile.bank_run(5, false, 0, &"district")
	_check(profile.levels_unlocked == 1 and not profile.has_completed(&"district"), "una sconfitta non sblocca nulla")
	profile.bank_run(20, true, 0, &"district")
	_check(profile.levels_unlocked == 2 and profile.has_completed(&"district"), "vincere il primo sblocca il secondo e lo segna completato")
	profile.bank_run(20, true, 1, &"railway")
	_check(profile.levels_unlocked == 3 and profile.has_completed(&"railway"), "vincere il secondo sblocca il terzo")
	profile.bank_run(20, true, 0, &"district")
	_check(profile.levels_unlocked == 3 and profile.completed_levels.size() == 2, "rivincere il primo non toglie nulla e non duplica")
	profile.profile_path = TEMP_PATH
	profile.save_profile()
	var loaded: PlayerProfileService = ProfileScript.new()
	_check(loaded.load_profile(TEMP_PATH) == OK and loaded.levels_unlocked == 3 and loaded.has_completed(&"railway") and loaded.has_completed(&"district"),
		"sblocchi e completati sopravvivono al salvataggio")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	profile.free()
	loaded.free()


func _test_campaign_map() -> void:
	print("campaign map")
	var profile := _profile()
	profile.reset()
	var menu: MainMenu = MenuScene.instantiate()
	root.add_child(menu)
	await _frames(3)
	var map: CampaignMapPanel = menu.get_node(^"CampaignMapPanel")
	var chosen: Array[StringName] = []
	map.level_chosen.connect(func(id: StringName) -> void: chosen.append(id))
	# Scegliere un livello cambia scena: qui si intercetta la scelta senza cambiarla.
	map.level_chosen.disconnect(menu.start_level)
	menu.start_run()
	_check(map.is_open and not menu._column.visible, "Gioca apre la mappa di campagna")
	_check(map.default_level() == &"district" and (menu.focused_control() as Button) == map._buttons[&"district"], "con un profilo nuovo il fuoco e sul primo livello")
	_check(map.can_play(&"district") and not map.can_play(&"railway") and not map.can_play(&"yard"), "solo il primo e giocabile")
	_check(map.button_text(&"railway").contains("X") and map.button_text(&"district").contains("QUARTIERE"), "il secondo e segnato bloccato: %s" % map.button_text(&"railway").replace("\n", " | "))
	map.press(&"railway")
	_check(chosen.is_empty() and map.is_open, "un livello bloccato non si sceglie")
	await _press(&"ui_cancel")
	_check(not map.is_open and menu._column.visible and (menu.focused_control() as Button) == menu._play, "B chiude la mappa e il fuoco torna su Gioca")
	profile.bank_run(10, true, 0, &"district")
	menu.start_run()
	_check(map.can_play(&"railway") and map.default_level() == &"railway" and (menu.focused_control() as Button) == map._buttons[&"railway"],
		"dopo la vittoria il fuoco e sulla ferrovia, sbloccata")
	_check(map.button_text(&"district").contains("V"), "il primo e segnato completato")
	_check(not map.can_play(&"yard") and map._buttons[&"yard"].disabled, "il cantiere resta in costruzione")
	map.press(&"railway")
	_check(chosen.is_empty() and map.is_open and map.choosing_class and map.chosen_level() == &"railway",
		"A sulla ferrovia apre la scelta della classe")
	map.press_class(&"engineer")
	_check(chosen == [&"railway"] and not map.is_open and not map.choosing_class, "A sulla classe parte la ferrovia")
	root.remove_child(menu)
	menu.queue_free()
	await _frames(2)
	profile.reset()
	await _test_class_choice()


## D-092 par. 6.1: dopo il livello si sceglie la classe fra quattro carte; l'ultima resta
## nel profilo e torna preselezionata; B dalle classi torna ai livelli, non al menu.
func _test_class_choice() -> void:
	print("class choice")
	var profile := _profile()
	profile.reset()
	profile.last_class = &"mechanic"
	var menu: MainMenu = MenuScene.instantiate()
	root.add_child(menu)
	await _frames(3)
	var map: CampaignMapPanel = menu.get_node(^"CampaignMapPanel")
	var chosen: Array[StringName] = []
	map.level_chosen.connect(func(id: StringName) -> void: chosen.append(id))
	map.level_chosen.disconnect(menu.start_level)
	menu.start_run()
	_check(map.is_open and not map.choosing_class, "la mappa si apre sui livelli")
	map.press(&"district")
	_check(map.choosing_class and map.is_open and chosen.is_empty() and map.chosen_level() == &"district",
		"premere un livello apre le classi senza partire")
	var cards := 0
	var visible_cards := true
	for entry in ClassCatalog.all():
		var card := map.class_card(entry.id)
		if card != null:
			cards += 1
			visible_cards = visible_cards and card.is_visible_in_tree()
	_check(cards == 4 and visible_cards, "quattro carte di classe visibili (%d)" % cards)
	_check(not map._buttons[&"district"].is_visible_in_tree(), "la riga dei livelli lascia il posto alle classi")
	_check(root.get_viewport().gui_get_focus_owner() == map.class_card(&"mechanic"), "il fuoco e sull'ultima classe scelta")
	await _press(&"ui_cancel")
	_check(map.is_open and not map.choosing_class and map._buttons[&"district"].is_visible_in_tree(),
		"B dalle classi torna ai livelli senza chiudere")
	_check(root.get_viewport().gui_get_focus_owner() == map._buttons[&"district"], "il fuoco torna sul livello scelto")
	await _press(&"ui_cancel")
	_check(not map.is_open and chosen.is_empty(), "un secondo B chiude la mappa")
	menu.start_run()
	map.press(&"district")
	await _press(&"ui_right")
	_check(root.get_viewport().gui_get_focus_owner() == map.class_card(&"weeder"), "la croce sposta il fuoco fra le classi")
	map.press_class(&"sapper")
	_check(chosen == [&"district"] and not map.is_open and not map.choosing_class, "A sul Guastatore parte il quartiere")
	_check(profile.last_class == &"sapper", "il profilo ricorda il Guastatore")
	menu.start_run()
	map.press(&"district")
	_check(root.get_viewport().gui_get_focus_owner() == map.class_card(&"sapper"), "alla volta dopo il fuoco e sul Guastatore")
	await _press(&"ui_cancel")
	await _press(&"ui_cancel")
	root.remove_child(menu)
	menu.queue_free()
	await _frames(2)
	profile.reset()


## Vittoria nel quartiere: la schermata offre la ferrovia; vittoria nella ferrovia:
## il cantiere non e giocabile, quindi niente pulsante.
func _test_victory_offers_next_level() -> void:
	print("next level")
	var profile := _profile()
	profile.reset()
	var scene: Node3D = RunScene.instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	await _frames(5)
	var run: ArenaRun = scene.get_node(^"Run")
	var panel: GameOverPanel = scene.get_node(^"GameOverPanel")
	var hud: RunHud = scene.get_node(^"RunHud")
	_check(hud.is_night_notice_visible() and hud.event_warning_text().begins_with("LIVELLO 1: QUARTIERE"), "all'avvio il titolo del livello: %s" % hud.event_warning_text())
	run._end_level(false)
	_check(panel.is_open and not panel.has_next_level(), "morendo nessun prossimo livello")
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	await _frames(2)
	scene = RunScene.instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	await _frames(5)
	run = scene.get_node(^"Run")
	panel = scene.get_node(^"GameOverPanel")
	run._end_level(true)
	_check(panel.is_open and panel.has_next_level() and panel._next.text.contains("La ferrovia"), "vincendo si offre la ferrovia: %s" % panel._next.text)
	_check(profile.levels_unlocked == 2 and profile.has_completed(&"district"), "il profilo sblocca la ferrovia")
	_check(not panel.shows_save_warning(), "senza errori di scrittura nessun avviso")
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	await _frames(2)
	# F-03: profilo non scrivibile (cartella inesistente): lo sblocco resta in memoria, il pannello avvisa.
	profile.reset()
	profile.profile_path = "user://no_such_dir_%d/profile.cfg" % Time.get_ticks_usec()
	scene = RunScene.instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	await _frames(5)
	run = scene.get_node(^"Run")
	panel = scene.get_node(^"GameOverPanel")
	run._end_level(true)
	_check(profile.last_save_error != OK and profile.levels_unlocked == 2, "salvataggio fallito (%d), sblocco in memoria" % profile.last_save_error)
	_check(panel.is_open and panel.shows_save_warning(), "il pannello di fine livello avvisa che il profilo non e salvato")
	profile.profile_path = ""
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	await _frames(2)
	scene = RailwayScene.instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	(scene.get_node(^"TrainEvent") as TrainEvent).next_at = 1.0e9
	await _frames(5)
	run = scene.get_node(^"Run")
	panel = scene.get_node(^"GameOverPanel")
	run._end_level(true)
	_check(panel.is_open and not panel.has_next_level(), "vincendo la ferrovia il cantiere non e ancora giocabile: nessun pulsante")
	_check(profile.levels_unlocked == 3 and profile.has_completed(&"railway"), "ma il profilo lo sblocca")
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	await _frames(2)
	profile.reset()
