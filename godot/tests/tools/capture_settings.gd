extends SceneTree
## Cattura del pannello Impostazioni dal menu di pausa (restyling 2026-10-11), a 1280x800.
## Uso: godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 600 --script res://tests/tools/capture_settings.gd -- --out=../output/restyle/ui

const RunScene := preload("res://scenes/main/arena_run.tscn")

var _out := "../output/restyle/ui"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	var scene := RunScene.instantiate()
	root.add_child(scene)
	scene.get_node(^"EnemyDirector").spawning = false
	for i in 10:
		await physics_frame
	var pause_menu := root.get_node("PauseMenu")
	pause_menu.pause_game()
	await process_frame
	pause_menu.open_settings()
	await process_frame
	await process_frame
	await _save("settings_top")
	# Scorre fino in fondo spostando il focus sull'ultima riga.
	var menu: Control = pause_menu.get_node("%SettingsPanel")
	(menu.get_node("%BackButton") as Button).grab_focus()
	await process_frame
	await process_frame
	await _save("settings_bottom")
	quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://").path_join(_out)
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("%s.png" % name)
	var error := root.get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, error])
