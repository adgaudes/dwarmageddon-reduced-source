extends SceneTree
## Test di impostazioni, pausa, focus e inversione dello stick destro.

const GameSettingsScript := preload("res://scripts/services/game_settings.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")

var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_test_defaults()
	_test_apply()
	_test_persistence()
	_test_terrain_detail_follows_quality()
	await _test_volume_validation()
	await _test_deferred_save()
	await _test_pause_and_focus()
	await _test_volume_sliders()
	await _test_aim_inversion()
	_test_graphics_presets()
	_test_isolation_and_deck()
	# Le prove salvano piu volte: restano .bak e .tmp oltre al file (audit K-11).
	var own := "settings_test_%d.cfg" % OS.get_process_id()
	var dir := DirAccess.open("user://")
	for file in dir.get_files():
		if file.begins_with("settings_test_") and not file.begins_with(own):
			dir.remove(file)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Autoload a runtime: nel test runner il nome globale non esiste ancora in compilazione.
func _settings() -> Node:
	return root.get_node("GameSettings")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _test_defaults() -> void:
	print("settings defaults")
	var settings := GameSettingsScript.new()
	_check(settings.fps_cap == 60, "limite predefinito 60 fps (restyling 2026-10-11)")
	_check(settings.vsync_mode == DisplayServer.VSYNC_MAILBOX, "VSync predefinita Mailbox")
	_check(settings.msaa_3d == Viewport.MSAA_4X, "MSAA 3D predefinito 4x")
	_check(is_equal_approx(settings.render_scale, 1.0), "scala rendering predefinita 100%")
	_check(not settings.invert_aim_x and not settings.invert_aim_y, "assi mira non invertiti")
	_check(is_equal_approx(settings.master_volume, 1.0) and is_equal_approx(settings.sfx_volume, 0.8), "volumi predefiniti 100% e 80%")
	settings.free()


func _test_apply() -> void:
	print("settings apply")
	var settings := GameSettingsScript.new()
	settings.fps_cap = 90
	settings.msaa_3d = Viewport.MSAA_2X
	settings.render_scale = 0.7
	settings.apply_settings(root)
	_check(Engine.max_fps == 90, "applica Engine.max_fps")
	_check(root.msaa_3d == Viewport.MSAA_2X, "applica MSAA al viewport")
	_check(is_equal_approx(root.scaling_3d_scale, 0.7), "applica scala 3D al viewport")
	settings.master_volume = 0.5
	settings.sfx_volume = 0.0
	settings.apply_settings(root)
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01, "applica il volume generale al bus Master")
	_check(sfx_bus > 0 and AudioServer.is_bus_mute(sfx_bus), "volume effetti a zero: bus SFX muto")
	_settings().apply_settings(root)
	settings.free()


func _test_persistence() -> void:
	print("settings persistence")
	var temp_path := "user://settings_test_%d.cfg" % Time.get_ticks_usec()
	var saved := GameSettingsScript.new()
	saved.fps_cap = 144
	saved.vsync_mode = DisplayServer.VSYNC_DISABLED
	saved.msaa_3d = Viewport.MSAA_8X
	saved.render_scale = 0.6
	saved.window_mode = GameSettingsScript.WindowModeChoice.BORDERLESS_FULLSCREEN
	saved.invert_aim_x = true
	saved.invert_aim_y = true
	saved.master_volume = 0.35
	saved.sfx_volume = 0.6
	_check(saved.save_settings(temp_path) == OK, "salva in un file temporaneo")
	var loaded := GameSettingsScript.new()
	_check(loaded.load_settings(temp_path) == OK, "ricarica il file temporaneo")
	_check(loaded.fps_cap == 144, "round trip limite fps")
	_check(loaded.vsync_mode == DisplayServer.VSYNC_DISABLED, "round trip VSync")
	_check(loaded.msaa_3d == Viewport.MSAA_8X, "round trip MSAA")
	_check(is_equal_approx(loaded.render_scale, 0.6), "round trip scala rendering")
	_check(loaded.window_mode == GameSettingsScript.WindowModeChoice.BORDERLESS_FULLSCREEN, "round trip modalita finestra")
	_check(loaded.invert_aim_x and loaded.invert_aim_y, "round trip inversione assi")
	_check(is_equal_approx(loaded.master_volume, 0.35) and is_equal_approx(loaded.sfx_volume, 0.6), "round trip volumi")
	# Audit S-01/S-02: un file illeggibile non fa perdere le impostazioni, si recupera il .bak.
	saved.fps_cap = 30
	saved.save_settings(temp_path)
	var garbage := FileAccess.open(temp_path, FileAccess.WRITE)
	garbage.store_string("[graphics
fps_cap = = =
")
	garbage.close()
	_check(loaded.load_settings(temp_path) == OK and loaded.fps_cap == 144, "file illeggibile: impostazioni recuperate dal .bak (%d)" % loaded.fps_cap)
	var dir := DirAccess.open("user://")
	for file in dir.get_files():
		if file.begins_with(temp_path.get_file()):
			dir.remove(file)
	saved.free()
	loaded.free()


## Valori fuori intervallo o di tipo sbagliato nel file non passano cosi come sono.
func _test_volume_validation() -> void:
	print("volume validation")
	var temp_path := "user://settings_test_volume_%d.cfg" % Time.get_ticks_usec()
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", 7.5)
	config.set_value("audio", "sfx_volume", "forte")
	_check(config.save(temp_path) == OK, "scrive un file con volumi non validi")
	var loaded := GameSettingsScript.new()
	_check(loaded.load_settings(temp_path) == OK, "lo ricarica")
	_check(is_equal_approx(loaded.master_volume, 1.0), "volume oltre il massimo limitato a 1")
	_check(is_equal_approx(loaded.sfx_volume, GameSettingsScript.DEFAULT_SFX_VOLUME), "volume non numerico: default")
	config.set_value("audio", "master_volume", -2)
	config.set_value("audio", "sfx_volume", NAN)
	config.save(temp_path)
	loaded.load_settings(temp_path)
	_check(is_zero_approx(loaded.master_volume), "volume negativo limitato a 0")
	_check(is_equal_approx(loaded.sfx_volume, GameSettingsScript.DEFAULT_SFX_VOLUME), "NaN: default")
	# U-04: interi e booleani di tipo sbagliato nel file non passano (`int("abc")`
	# sarebbe 0 = "Illimitato", `bool("false")` sarebbe true).
	config.set_value("graphics", "fps_cap", "abc")
	config.set_value("graphics", "msaa_3d", 2.0)
	config.set_value("graphics", "window_mode", true)
	config.set_value("graphics", "render_scale", "meta")
	config.set_value("controls", "invert_aim_x", "false")
	config.set_value("controls", "invert_aim_y", 1)
	config.save(temp_path)
	loaded.load_settings(temp_path)
	_check(loaded.fps_cap == GameSettingsScript.DEFAULT_FPS_CAP, "fps_cap non intero: default (%d)" % loaded.fps_cap)
	_check(loaded.msaa_3d == GameSettingsScript.DEFAULT_MSAA_3D and loaded.window_mode == GameSettingsScript.DEFAULT_WINDOW_MODE,
		"msaa_3d e window_mode non interi: default")
	_check(is_equal_approx(loaded.render_scale, GameSettingsScript.DEFAULT_RENDER_SCALE), "render_scale non numerica: default")
	_check(not loaded.invert_aim_x and not loaded.invert_aim_y, "inversioni non booleane: false")
	# I setter salvano a fine frame: il percorso resta quello temporaneo.
	loaded.set_master_volume(1.4)
	loaded.set_sfx_volume(0.45)
	_check(is_equal_approx(loaded.master_volume, 1.0) and is_equal_approx(loaded.sfx_volume, 0.45), "i setter limitano a 0-1")
	await process_frame
	var reloaded := GameSettingsScript.new()
	reloaded.load_settings(temp_path)
	_check(is_equal_approx(reloaded.sfx_volume, 0.45), "i setter salvano a fine frame")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	loaded.free()
	reloaded.free()
	_settings().apply_settings(root)


## Un cursore trascinato chiama il setter a ogni passo: una sola scrittura per frame (U-05).
func _test_deferred_save() -> void:
	print("deferred save")
	var temp_path := "user://settings_test_deferred_%d.cfg" % Time.get_ticks_usec()
	var settings := GameSettingsScript.new()
	settings.settings_path = temp_path
	var emitted := [0]
	settings.changed.connect(func() -> void: emitted[0] += 1)
	for i in 20:
		settings.set_master_volume(1.0 - i * 0.05)
	_check(settings.save_count == 0 and not FileAccess.file_exists(temp_path), "nel frame dei 20 cambi nessuna scrittura")
	_check(emitted[0] == 20, "ogni cambio emette changed subito (%d)" % emitted[0])
	await process_frame
	_check(settings.save_count == 1 and FileAccess.file_exists(temp_path), "a fine frame una sola scrittura (%d)" % settings.save_count)
	var reloaded := GameSettingsScript.new()
	reloaded.load_settings(temp_path)
	_check(is_equal_approx(reloaded.master_volume, 0.05), "con l'ultimo valore (%.2f)" % reloaded.master_volume)
	await process_frame
	_check(settings.save_count == 1, "senza altri cambi non si riscrive")
	settings.set_sfx_volume(0.3)
	await process_frame
	_check(settings.save_count == 2, "un cambio in un altro frame scrive di nuovo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	settings.free()
	reloaded.free()
	_settings().apply_settings(root)


## I cursori del volume si usano con croce direzionale e tastiera e scrivono
## nel servizio. Il servizio reale salva: qui punta a un file temporaneo.
func _test_volume_sliders() -> void:
	print("volume sliders")
	var service: Node = _settings()
	var real_path: String = service.settings_path
	var temp_path := "user://settings_test_sliders_%d.cfg" % Time.get_ticks_usec()
	var real_existed := FileAccess.file_exists(real_path)
	var real_modified := FileAccess.get_modified_time(real_path) if real_existed else 0
	service.settings_path = temp_path
	var pause_menu := root.get_node("PauseMenu")
	pause_menu.pause_game()
	pause_menu.open_settings()
	await process_frame
	var master: HSlider = pause_menu.get_node("%SettingsPanel").get_node("%MasterVolume")
	var sfx: HSlider = pause_menu.get_node("%SettingsPanel").get_node("%SfxVolume")
	var master_label: Label = pause_menu.get_node("%SettingsPanel").get_node("%MasterVolumeValue")
	_check(is_equal_approx(master.value, 1.0) and is_equal_approx(sfx.value, 0.8), "i cursori mostrano i valori correnti")
	_check(master.focus_mode == Control.FOCUS_ALL and sfx.focus_mode == Control.FOCUS_ALL, "i cursori prendono il focus")
	# I volumi stanno nella scheda Audio (playtest O-11): ci si passa con il dorsale destro,
	# due volte da Gameplay (D-097) passando per Grafica.
	_check((pause_menu.get_node("%SettingsPanel") as SettingsMenu).current_tab == 0, "le impostazioni si aprono sulla scheda Gameplay")
	for i in 2:
		_send_joypad_button(JOY_BUTTON_RIGHT_SHOULDER, true)
		await process_frame
		_send_joypad_button(JOY_BUTTON_RIGHT_SHOULDER, false)
		await process_frame
	_check((pause_menu.get_node("%SettingsPanel") as SettingsMenu).current_tab == 2, "il dorsale destro passa a Grafica e poi ad Audio")
	master.grab_focus()
	_send_joypad_button(JOY_BUTTON_DPAD_LEFT, true)
	await process_frame
	_send_joypad_button(JOY_BUTTON_DPAD_LEFT, false)
	await process_frame
	_check(is_equal_approx(service.master_volume, 0.95), "croce a sinistra abbassa il volume generale di un passo (%.2f)" % service.master_volume)
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.95)) < 0.01, "il bus Master segue il cursore")
	_check(master_label.text == "95%", "etichetta aggiornata (%s)" % master_label.text)
	_check(pause_menu.focused_control() == master, "il focus resta sul cursore")
	_send_joypad_button(JOY_BUTTON_DPAD_DOWN, true)
	await process_frame
	_send_joypad_button(JOY_BUTTON_DPAD_DOWN, false)
	await process_frame
	_check(pause_menu.focused_control() == sfx, "croce in basso passa al volume effetti")
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_LEFT
		key.physical_keycode = KEY_LEFT
		key.pressed = pressed
		Input.parse_input_event(key)
		await process_frame
	_check(is_equal_approx(service.sfx_volume, 0.75), "freccia sinistra abbassa il volume effetti (%.2f)" % service.sfx_volume)
	# A sul cursore non deve chiudere il menu ne arrivare al gioco.
	_send_joypad_button(JOY_BUTTON_A, true)
	await process_frame
	_send_joypad_button(JOY_BUTTON_A, false)
	await process_frame
	_check(paused and pause_menu.is_open(), "A su un cursore non chiude il menu")
	var saved := GameSettingsScript.new()
	saved.load_settings(temp_path)
	_check(is_equal_approx(saved.master_volume, 0.95) and is_equal_approx(saved.sfx_volume, 0.75), "i cursori salvano nel file configurato")
	saved.free()
	_check(FileAccess.file_exists(real_path) == real_existed and (not real_existed or FileAccess.get_modified_time(real_path) == real_modified),
		"il file reale delle impostazioni non e stato toccato")
	service.master_volume = GameSettingsScript.DEFAULT_MASTER_VOLUME
	service.sfx_volume = GameSettingsScript.DEFAULT_SFX_VOLUME
	service.apply_audio()
	service.settings_path = real_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	pause_menu.resume_game()
	await process_frame


func _test_pause_and_focus() -> void:
	print("pause and focus")
	var pause_menu := root.get_node("PauseMenu")
	if pause_menu.is_open():
		pause_menu.resume_game()
	_send_pause_key()
	await process_frame
	_check(paused and pause_menu.is_open(), "Esc apre il menu e mette in pausa")
	var focused: Control = pause_menu.focused_control()
	_check(focused != null and focused.name == &"ResumeButton", "focus su Riprendi all'apertura")
	pause_menu.open_settings()
	await process_frame
	focused = pause_menu.focused_control()
	_check(focused != null and focused.name == &"WorldEventsOption", "focus sulla prima impostazione (eventi del mondo, scheda Gameplay)")
	_check_settings_menu_rows(pause_menu)
	# R-13: Esc dalle Impostazioni torna al pannello di pausa, come B; non riprende il gioco.
	_send_pause_key()
	await process_frame
	focused = pause_menu.focused_control()
	_check(paused and pause_menu.is_open() and focused != null and focused.name == &"ResumeButton",
		"Esc nelle Impostazioni torna alla pausa, come B")
	_send_pause_joypad()
	await process_frame
	_check(not paused and not pause_menu.is_open(), "Start chiude il menu e riprende")

	# A e Spazio condividono ui_accept con il dash: il Control deve consumare l'evento.
	var player: PlayerCharacter = PlayerScene.instantiate()
	root.add_child(player)
	pause_menu.pause_game()
	await process_frame
	# Pressione e rilascio in frame distinti, come un dito reale.
	_send_joypad_button(JOY_BUTTON_A, true)
	await process_frame
	_send_joypad_button(JOY_BUTTON_A, false)
	await process_frame
	await physics_frame
	_check(not paused and not player.is_dashing, "A su Riprendi non attiva il dash")
	player.queue_free()
	await process_frame


func _test_aim_inversion() -> void:
	print("aim inversion")
	var player: PlayerCharacter = PlayerScene.instantiate()
	root.add_child(player)
	_settings().invert_aim_x = false
	_settings().invert_aim_y = false
	_send_joypad_axis(JOY_AXIS_RIGHT_X, 0.8)
	await process_frame
	var normal_x: Vector2 = player.call("_raw_aim_input")
	_settings().invert_aim_x = true
	var inverted_x: Vector2 = player.call("_raw_aim_input")
	_check(normal_x.x > 0.0 and is_equal_approx(inverted_x.x, -normal_x.x), "inversione X ribalta lo stick destro")
	_send_joypad_axis(JOY_AXIS_RIGHT_X, 0.0)
	_send_joypad_axis(JOY_AXIS_RIGHT_Y, 0.8)
	await process_frame
	_settings().invert_aim_y = false
	var normal_y: Vector2 = player.call("_raw_aim_input")
	_settings().invert_aim_y = true
	var inverted_y: Vector2 = player.call("_raw_aim_input")
	_check(normal_y.y > 0.0 and is_equal_approx(inverted_y.y, -normal_y.y), "inversione Y ribalta lo stick destro")
	_send_joypad_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_settings().invert_aim_x = false
	_settings().invert_aim_y = false
	player.queue_free()
	await process_frame


func _send_pause_key() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		# Come un tasto reale: `pause` legge il tasto fisico, `ui_cancel` il keycode.
		event.physical_keycode = KEY_ESCAPE
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)


func _send_pause_joypad() -> void:
	_send_joypad_button(JOY_BUTTON_START, true)
	_send_joypad_button(JOY_BUTTON_START, false)


func _send_joypad_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


func _send_joypad_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _test_graphics_presets() -> void:
	print("graphics presets")
	var s: GameSettingsService = GameSettingsScript.new()
	s.settings_path = "user://settings_test_%d.cfg" % Time.get_ticks_usec()
	root.add_child(s)
	_check(s.FPS_CAPS.has(240) and s.FPS_CAPS.has(165) and s.FPS_CAPS[-1] == 0, "limiti fps fino a 240 e Illimitato in cima")
	_check(s.preset == GameSettingsService.Preset.HIGH, "preset predefinito Alto")
	s.set_preset(GameSettingsService.Preset.MAX)
	_check(s.gi_mode == 2 and s.volumetric_fog and s.shadow_quality == 3, "Massimo accende SDFGI, volumetrica, ombre alte")
	s.set_gi_mode(1)
	_check(s.preset == GameSettingsService.Preset.CUSTOM and s.volumetric_fog and s.shadow_quality == 3, "toccare un'opzione porta a Personalizzato senza cambiare le altre")
	s.set_preset(GameSettingsService.Preset.STEAM_DECK)
	_check(is_equal_approx(s.render_scale, 0.85) and s.fsr_upscaling and s.msaa_3d == Viewport.MSAA_DISABLED, "preset Deck: scala 0,85 con FSR, MSAA off")
	# File vecchio senza le chiavi nuove e con una chiave sconosciuta.
	var old := ConfigFile.new()
	old.set_value("graphics", "fps_cap", 120)
	old.set_value("graphics", "future_key", "x")
	old.set_value("mods", "something", 3)
	old.save(s.settings_path)
	_check(s.load_settings() == OK and s.fps_cap == 120 and s.preset == GameSettingsService.Preset.HIGH, "file vecchio: fps conservato, preset Alto")
	s.save_settings()
	var saved := ConfigFile.new()
	saved.load(s.settings_path)
	_check(saved.get_value("graphics", "future_key", "") == "x" and saved.get_value("mods", "something", 0) == 3, "chiavi e sezioni sconosciute conservate")
	_check(saved.get_value("graphics", "version", 0) == GameSettingsService.VERSION, "versione scritta nel file")
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	s.set_preset(GameSettingsService.Preset.MAX)
	s.apply_to_world(env, sun)
	_check(env.sdfgi_enabled and env.volumetric_fog_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "apply_to_world: Massimo")
	s.set_preset(GameSettingsService.Preset.STEAM_DECK)
	s.apply_to_world(env, sun)
	_check(not env.sdfgi_enabled and not env.ssil_enabled and not env.volumetric_fog_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "apply_to_world: Deck")
	_check(is_equal_approx(s.vegetation_multiplier(), 0.65), "densita vegetazione media sul Deck")
	s.set_preset(GameSettingsService.Preset.HIGH)
	s.apply_settings(root)
	_check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and root.msaa_3d == Viewport.MSAA_4X, "Alto: MSAA 4x senza FXAA")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(s.settings_path))
	root.remove_child(s)
	s.free()
	sun.free()


## Righe del menu dopo il restyling (2026-10-11): preset, opzioni singole, fps esteso, scorrimento.
func _check_settings_menu_rows(pause_menu: Node) -> void:
	var settings: GameSettingsService = _settings()
	var menu: Control = pause_menu.get_node("%SettingsPanel")
	var preset_option: OptionButton = menu.get_node("%PresetOption")
	_check(preset_option.item_count == 6, "sei voci di preset")
	var before := settings.preset
	preset_option.select(GameSettingsService.Preset.MAX)
	preset_option.item_selected.emit(GameSettingsService.Preset.MAX)
	_check(settings.preset == GameSettingsService.Preset.MAX, "scegliere Massimo dal menu imposta il preset")
	var gi: OptionButton = menu.get_node("%GiOption")
	_check(gi.selected == 2, "la riga GI mostra SDFGI dopo il preset Massimo")
	gi.select(1)
	gi.item_selected.emit(1)
	_check(settings.preset == GameSettingsService.Preset.CUSTOM and preset_option.selected == GameSettingsService.Preset.CUSTOM, "toccare GI mostra Personalizzato")
	var fps: OptionButton = menu.get_node("%FpsOption")
	_check(fps.item_count == 8 and fps.get_item_text(7) == "Illimitato", "limite fps con otto voci, l'ultima Illimitato")
	var volumetric: CheckButton = menu.get_node("%VolumetricCheck")
	_check(volumetric.button_pressed == settings.volumetric_fog, "la spunta della volumetrica segue il servizio")
	_check(menu.get_node("%Content").get_parent() is ScrollContainer, "il contenuto scorre")
	settings.set_preset(before)
	# Playtest O-11 e D-097: quattro schede (Gameplay, Grafica, Audio, Controlli); ogni scheda
	# mostra solo le sue righe; mira manuale ed eventi del mondo in Gameplay.
	var panel := menu as SettingsMenu
	_check(panel.TABS.size() == 4 and panel.TABS[0][0] == "Gameplay", "quattro schede, Gameplay per prima")
	panel.show_tab(1)
	_check(menu.get_node("%PresetOption").is_visible_in_tree() == menu.is_visible_in_tree() and not menu.get_node("%MasterVolume").get_parent().visible, "scheda Grafica: niente volumi")
	panel.show_tab(2)
	_check(menu.get_node("%MasterVolume").get_parent().visible and not menu.get_node("%PresetOption").get_parent().visible, "scheda Audio: solo i volumi")
	panel.show_tab(3)
	_check(menu.get_node("%InvertX").get_parent().visible and menu.find_child("ManualAim", true, false).get_parent().visible == false, "scheda Controlli: inversioni, non la mira manuale")
	panel.show_tab(0)
	var aim: CheckButton = menu.find_child("ManualAim", true, false)
	var events: OptionButton = menu.find_child("WorldEventsOption", true, false)
	var quake: CheckButton = menu.find_child("QuakeCheck", true, false)
	var train: CheckButton = menu.find_child("TrainCheck", true, false)
	var night: CheckButton = menu.find_child("NightCheck", true, false)
	_check(aim != null and aim.get_parent().visible and events != null and events.get_parent().visible and quake.get_parent().visible
		and train.get_parent().visible and night.get_parent().visible and not menu.get_node("%PresetOption").get_parent().visible,
		"scheda Gameplay: eventi per livello, terremoto, treno, notte, mira manuale")
	_check(events.item_count == GameSettingsService.WORLD_EVENT_COUNTS.size() and events.selected == GameSettingsService.WORLD_EVENT_COUNTS.find(settings.world_event_count),
		"il numero di eventi mostra il valore corrente")
	var was := settings.manual_aim
	aim.button_pressed = not was
	_check(settings.manual_aim == not was, "la spunta della mira cambia l'impostazione")
	settings.set_manual_aim(was)
	var count_was := settings.world_event_count
	events.select(2)
	events.item_selected.emit(2)
	_check(settings.world_event_count == GameSettingsService.WORLD_EVENT_COUNTS[2], "scegliere 3 eventi dal menu imposta il servizio")
	settings.set_world_event_count(count_was)
	var quake_was := settings.quake_enabled
	quake.button_pressed = not quake_was
	_check(settings.quake_enabled == not quake_was, "la levetta del terremoto cambia l'impostazione")
	settings.set_quake_enabled(quake_was)
	var volumetric_row := menu.get_node("%VolumetricCheck").get_parent()
	_check(volumetric_row is HBoxContainer and (volumetric_row.get_node("Label") as Label).text.begins_with("Nebbia"), "gli interruttori stanno in colonna con un'etichetta")
	panel.show_tab(0)


## Review finale del restyling: le suite non devono toccare il file reale; il Deck si
## applica anche con un file vecchio finche il giocatore non sceglie un preset; i livelli
## bassi di SSAO e bagliore costano meno.
## Audit Q-02: il dettaglio ridotto del terreno non sparisce toccando un'opzione del Deck.
func _test_terrain_detail_follows_quality() -> void:
	print("terrain detail")
	var s := GameSettingsScript.new()
	s.set_preset(GameSettingsService.Preset.STEAM_DECK)
	_check(TerrainField.reduced_detail(s), "preset Steam Deck: terreno a dettaglio ridotto")
	s.set_ssao_quality(0)
	_check(s.preset == GameSettingsService.Preset.CUSTOM and TerrainField.reduced_detail(s), "spento l'SSAO (Personalizzato): resta ridotto")
	s.set_preset(GameSettingsService.Preset.HIGH)
	_check(not TerrainField.reduced_detail(s), "preset Alto: dettaglio pieno")
	s.free()


func _test_isolation_and_deck() -> void:
	print("isolation and deck")
	var live: GameSettingsService = _settings()
	_check(live.settings_path != "user://settings.cfg", "sotto test l'autoload non usa il file reale (%s)" % live.settings_path)
	var s: GameSettingsService = GameSettingsScript.new()
	s.settings_path = "user://settings_test_%d.cfg" % Time.get_ticks_usec()
	var old := ConfigFile.new()
	old.set_value("graphics", "fps_cap", 120)
	old.save(s.settings_path)
	OS.set_environment("SteamDeck", "1")
	_check(s.load_settings() == OK and s.preset == GameSettingsService.Preset.STEAM_DECK and is_equal_approx(s.render_scale, 0.85) and s.fps_cap == 120,
		"file vecchio sul Deck: preset Deck finche nessuno ha scelto, fps conservato")
	s.preset_chosen = true
	s.preset = GameSettingsService.Preset.HIGH
	s.save_settings()
	_check(s.load_settings() == OK and s.preset == GameSettingsService.Preset.HIGH, "preset scelto dal giocatore: il Deck non lo sovrascrive")
	OS.set_environment("SteamDeck", "")
	var env := Environment.new()
	s.set_glow_quality(1)
	s.apply_to_world(env, null)
	_check(env.get_glow_level(2) > 0.0 and env.get_glow_level(1) == 0.0 and env.get_glow_level(3) == 0.0 and env.get_glow_level(5) == 0.0, "bagliore basso: un solo livello")
	s.set_glow_quality(2)
	s.apply_to_world(env, null)
	_check(env.get_glow_level(5) > 0.0, "bagliore alto: piu livelli")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(s.settings_path))
	s.free()
