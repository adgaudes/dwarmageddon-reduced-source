extends SceneTree
## Catture dell'arena grande (D-042), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --script res://tests/tools/capture_district.gd -- --out=../output/district
## Produce: overview (tutta l'arena dall'alto), start (vista di gioco alla partenza),
## poi, dopo un minuto di orda, combat. Con `--visit=x,z` (ripetibile) aggiunge una
## vista di gioco col giocatore in quel punto (visit_0, visit_1, ...) ed esce senza combat.
## Con `--scene=railway` cattura il livello 2 (`railway_run.tscn`).

var _out := "../output/district"
var _scene_path := "res://scenes/main/arena_run.tscn"
var _visits: Array[Vector2] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			_scene_path = "res://scenes/main/%s_run.tscn" % arg.trim_prefix("--scene=")
		elif arg.begins_with("--visit="):
			var parts := arg.trim_prefix("--visit=").split(",")
			_visits.append(Vector2(parts[0].to_float(), parts[1].to_float()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	var scene: Node3D = (load(_scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	var player: PlayerCharacter = scene.get_node(^"Player")
	var director: EnemyDirector = scene.get_node(^"EnemyDirector")
	var district: RuinsDistrict = scene.get_node(^"District")
	var hud: CanvasLayer = scene.get_node(^"RunHud")
	var menu: LevelUpMenu = scene.get_node(^"LevelUpMenu")
	director.spawning = false
	for i in 10:
		await physics_frame
	await _save("start")

	# Vista dall'alto di tutta l'arena: camera ortogonale temporanea, nord in alto,
	# senza nebbia (a 150 m coprirebbe tutto).
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = maxf(district.half_x(), district.half_z()) * 2.0 + 16.0
	top.far = 400.0
	root.add_child(top)
	# look_at verticale e degenere: base esplicita (destra = +X, alto schermo = -Z, guarda -Y).
	top.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(0.0, 150.0, 0.0))
	top.make_current()
	var environment: Environment = (district.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	environment.fog_enabled = false
	hud.visible = false
	for i in 5:
		await process_frame
	await _save("overview")
	top.queue_free()
	environment.fog_enabled = true
	hud.visible = true
	(scene.get_node(^"CameraRig/Camera") as Camera3D).make_current()

	for i in _visits.size():
		player.global_position = Vector3(_visits[i].x, 0.88, _visits[i].y)
		for frame in 30:
			await physics_frame
		await _save("visit_%d" % i)
	if not _visits.is_empty():
		quit()
		return

	director.spawning = true
	for i in 3600:
		player.set_max_health(5)
		player._invulnerable_left = 1.0
		if menu.is_open:
			menu.press(0)
		await physics_frame
	await _save("combat")
	quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
