extends SceneTree
## Catture del prototipo della promessa A (non e una suite). Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --script res://tests/tools/capture_run.gd -- --out=../output/run

var _out := "../output/run"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	var scene: Node3D = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(scene)
	var run: ArenaRun = scene.get_node(^"Run")
	var player: PlayerCharacter = scene.get_node(^"Player")
	# Abbastanza a lungo perche l'orda arrivi ai varchi; il giocatore resta fermo e invulnerabile.
	for i in 1500:
		player.set_max_health(5)
		player._invulnerable_left = 1.0
		await physics_frame
	await _save("combat")
	var xp: XpField = scene.get_node(^"XpField")
	xp.spawn(player.global_position + Vector3(0.5, 0.0, 0.0), run.progression.xp_to_next())
	for i in 60:
		await process_frame
	await _save("level_up")
	quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
