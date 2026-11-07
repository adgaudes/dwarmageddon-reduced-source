extends SceneTree
## Catture del terremoto (D-075), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 3000 --script res://tests/tools/capture_quake.gd -- --out=../output/quake
## Produce: warning (annuncio con freccia e polvere sulla faglia), quake (il fronte a meta
## corsa), aftermath (la faglia rialzata, impronte dell'orda).

var _out := "../output/quake"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	var scene: Node3D = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(scene)
	var run: ArenaRun = scene.get_node(^"Run")
	var quake: QuakeEvent = scene.get_node(^"QuakeEvent")
	var player: PlayerCharacter = scene.get_node(^"Player")
	var director: EnemyDirector = scene.get_node(^"EnemyDirector")
	director.spawning = false
	for i in 10:
		await physics_frame
	player.global_position = Vector3(0.0, 0.88, 8.0)
	player.velocity = Vector3.ZERO
	for i in 8:
		director.spawn_at(Vector3(-8.0 + i * 2.2, 0.0, -6.0))
	quake.warning_seconds = 4.0
	quake.distance_min = 6.0
	quake.distance_max = 8.0
	quake.next_at = run.elapsed + 4.5
	for i in 90:
		await physics_frame
	await _save("warning")
	while quake.state != QuakeEvent.State.SHAKING:
		await physics_frame
	while quake._front < quake.fault_cells.size() / 2 and quake.state == QuakeEvent.State.SHAKING:
		await physics_frame
	await _save("quake")
	while quake.state == QuakeEvent.State.SHAKING:
		await physics_frame
	for i in 45:
		await physics_frame
	await _save("aftermath")
	quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
