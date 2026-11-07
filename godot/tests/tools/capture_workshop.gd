extends SceneTree
## Catture di Officina (D-049), mappa di fine livello (D-052) e menu (D-051), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --script res://tests/tools/capture_workshop.gd -- --out=../output/workshop
## Produce: game_over (fine livello col pulsante Officina), workshop (catalogo con
## un upgrade comprato, uno al massimo e alcuni fuori portata), menu (menu iniziale).

var _out := "../output/workshop"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	# Sotto --script il profilo non legge ne scrive il salvataggio reale.
	var profile := root.get_node("PlayerProfile") as PlayerProfileService
	profile.reset()
	profile.scrap = 9
	profile.levels = {&"base_health": 1, &"salvage": 1}
	var scene: Node3D = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	for i in 10:
		await physics_frame
	var player: PlayerCharacter = scene.get_node(^"Player")
	# Un po' di campo scolpito per la mappa: fossato a nord, muro a est, una breccia.
	var field: TerrainField = scene.get_node(^"TerrainField")
	(scene.get_node(^"Run") as ArenaRun)._start_protect_left = 0.0
	field.set_protected(Vector3.ZERO, field.tuning.start_protected_radius_m, false)
	for x in [-2.4, 0.0, 2.4]:
		field.player_sculpt(Vector3(x, 0.0, -12.0), 2.4, -0.8, TerrainField.ToolMode.DIG)
	for z in [-2.4, 0.0, 2.4]:
		field.player_sculpt(Vector3(4.8, 0.0, z), 2.4, 1.4, TerrainField.ToolMode.RAISE)
	field.player_sculpt(Vector3(-9.6, 0.0, 2.4), 2.4, -0.8, TerrainField.ToolMode.DIG)
	player._invulnerable_left = 0.0
	player.take_damage(player.health)
	for i in 70:
		await process_frame
	await _save("game_over")
	(scene.get_node(^"GameOverPanel") as GameOverPanel).workshop_requested.emit()
	for i in 5:
		await process_frame
	await _save("workshop")
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	var menu: Control = preload("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	for i in 10:
		await process_frame
	await _save("menu")
	quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
