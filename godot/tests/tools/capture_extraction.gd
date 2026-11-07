extends SceneTree
## Catture della piazzola di estrazione (D-076), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 3000 --script res://tests/tools/capture_extraction.gd -- --out=../output/extraction
## Produce: broken (boss battuto, un muro dentro il 3x3: lastra rossa e invito a spianare),
## holding (3x3 piano, lastra verde e conto alla rovescia con l'orda intorno), landed
## (schermata di vittoria).

var _out := "../output/extraction"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	var scene: Node3D = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(scene)
	var run: ArenaRun = scene.get_node(^"Run")
	var pad: ExtractionPad = scene.get_node(^"ExtractionPad")
	var field: TerrainField = scene.get_node(^"TerrainField")
	var player: PlayerCharacter = scene.get_node(^"Player")
	var director: EnemyDirector = scene.get_node(^"EnemyDirector")
	director.spawning = false
	for i in 10:
		await physics_frame
	player.global_position = Vector3(0.0, 0.88, 0.0)
	player.velocity = Vector3.ZERO
	run.call_boss()
	run._boss_warning_left = 0.01
	for i in 12:
		await physics_frame
	if run.boss == null:
		quit()
		return
	pad.hold_seconds = 6.0
	var wall := Vector3(2.4, 0.0, 2.4)
	run._start_protect_left = 0.0
	field.set_protected(Vector3.ZERO, field.tuning.start_protected_radius_m, false)
	field.sculpt(wall, 2.0, 1.4)
	run.boss.global_position = Vector3(9.0, run.boss.global_position.y, 4.0)
	run.boss.take_damage(run.boss.health)
	for i in 6:
		director.spawn_at(Vector3(-10.0 + i * 1.6, 0.0, -9.0))
	for i in 40:
		await physics_frame
	await _save("broken")
	field.level(wall, 2.4, field.base_height_at(wall), 1.0)
	for i in 150:
		await physics_frame
	await _save("holding")
	while not run.is_over:
		await physics_frame
	for i in 20:
		await process_frame
	await _save("landed")
	quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
