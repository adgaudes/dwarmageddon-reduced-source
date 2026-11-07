extends SceneTree
## Cattura ravvicinata di un punto dell'arena con una camera libera, non e una suite.
## Serve a giudicare i dettagli della passata artistica (D-068) che la camera di gioco
## mostra da lontano. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --script res://tests/tools/capture_closeup.gd -- --out=../output/district_v2 --at=55,0,55 --from=45,8,70 --name=ruin
## `--at=x,y,z` e il punto guardato, `--from=x,y,z` la posizione della camera (in metri,
## coordinate mondo), `--name` il file PNG; `--scene=railway` cattura il livello 2.
## Ripetibili: ogni terna `--at/--from/--name` produce una cattura.

var _out := "../output/district_v2"
var _scene_path := "res://scenes/main/arena_run.tscn"
var _shots: Array[Dictionary] = []


func _initialize() -> void:
	var current := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			_scene_path = "res://scenes/main/%s_run.tscn" % arg.trim_prefix("--scene=")
		elif arg.begins_with("--at="):
			current["at"] = _vec3(arg.trim_prefix("--at="))
		elif arg.begins_with("--from="):
			current["from"] = _vec3(arg.trim_prefix("--from="))
		elif arg.begins_with("--name="):
			current["name"] = arg.trim_prefix("--name=")
			_shots.append(current)
			current = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	var scene: Node3D = (load(_scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	var director: EnemyDirector = scene.get_node(^"EnemyDirector")
	var hud: CanvasLayer = scene.get_node(^"RunHud")
	director.spawning = false
	hud.visible = false
	for i in 10:
		await physics_frame
	var camera := Camera3D.new()
	camera.fov = 45.0
	root.add_child(camera)
	camera.make_current()
	for shot in _shots:
		var at: Vector3 = shot.get("at", Vector3.ZERO)
		var from: Vector3 = shot.get("from", at + Vector3(-8.0, 6.0, 12.0))
		camera.global_position = from
		camera.look_at(at, Vector3.UP)
		for i in 5:
			await process_frame
		await _save(shot["name"])
	quit()


static func _vec3(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
