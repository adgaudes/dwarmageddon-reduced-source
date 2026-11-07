extends SceneTree
## Catture dell'identita e dell'interfaccia (D-079, D-080) a 1280x800: intro a tre
## tempi, menu, pausa. Stampa anche MENU_FRAME_MS (costo del menu con cielo e polvere).
## Le altre schermate le fanno gli script di cattura esistenti (run, workshop,
## campaign, settings, night, boss) con `--out=../output/identity`.
## Uso: godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 6000 --script res://tests/tools/capture_ui.gd -- --out=../output/identity

const IntroScene := preload("res://scenes/main/boot_intro.tscn")
const MenuScene := preload("res://scenes/main/main_menu.tscn")
const RunScene := preload("res://scenes/main/arena_run.tscn")

var _out := "../output/identity"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	await process_frame
	var intro := IntroScene.instantiate() as BootIntro
	intro.force_play = true
	intro.change_scene_on_finish = false
	root.add_child(intro)
	await _seconds(0.8)
	await _save("intro_0_8s")
	await _seconds(1.2)
	await _save("intro_2_0s")
	await _seconds(1.0)
	await _save("intro_3_0s")
	intro.queue_free()
	await process_frame
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	await _seconds(1.0)
	while not SfxLibrary.is_precached():
		await process_frame
	# Costo del menu: tempo reale per frame a vsync spento e senza limite di fps
	# (TIME_PROCESS include l'attesa del vsync e non dice nulla).
	var vsync := DisplayServer.window_get_vsync_mode()
	var max_fps := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for i in 30:
		await process_frame
	var start := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_usec() - start < 1000000:
		await process_frame
		frames += 1
	print("MENU_FRAME_MS %.2f" % ((Time.get_ticks_usec() - start) / 1000.0 / frames))
	DisplayServer.window_set_vsync_mode(vsync)
	Engine.max_fps = max_fps
	await _save("menu")
	menu.queue_free()
	await process_frame
	var run := RunScene.instantiate()
	root.add_child(run)
	run.get_node(^"EnemyDirector").spawning = false
	await _seconds(0.3)
	root.get_node("PauseMenu").pause_game()
	await _seconds(0.2)
	await _save("pause")
	quit()


## Secondi simulati: con --fixed-fps 60 ogni frame di processo vale 1/60 s (i tick
## fisici sono 120 al secondo e sfaserebbero i tempi dell'intro).
func _seconds(s: float) -> void:
	for i in int(s * 60):
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://").path_join(_out)
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("%s.png" % name)
	var error := root.get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, error])
