extends SceneTree
## Strumento, non suite: cattura l'arena da piu punti di vista. Serve una finestra reale.
##   godot_console --path godot --resolution 1280x800 --script res://tests/tools/capture_arena.gd -- --out=<cartella>

const Scene := preload("res://scenes/main/ruins_arena.tscn")

## [nome, posizione camera, punto guardato]
const VIEWS := [
	["game", Vector3.ZERO, Vector3.ZERO],
	["overview", Vector3(0, 70, 55), Vector3(0, 0, -5)],
	["north", Vector3(0, 9, 14), Vector3(0, 8, -40)],
	["west", Vector3(10, 8, 6), Vector3(-28, 2, -2)],
	["corner_ne", Vector3(-6, 10, 10), Vector3(22, 1, -20)],
	["close_train", Vector3(-16, 4, 6), Vector3(-27, 1.5, -2)],
	["close_car", Vector3(-14, 3.5, -12), Vector3(-20.4, 0.6, -19.4)],
]


func _initialize() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var scene := Scene.instantiate()
	root.add_child(scene)
	for i in 20:
		await process_frame
	var game_camera := root.get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.far = 400.0
	root.add_child(camera)
	for view in VIEWS:
		if view[0] == "game":
			game_camera.make_current()
		else:
			camera.make_current()
			camera.look_at_from_position(view[1], view[2])
		for i in 6:
			await RenderingServer.frame_post_draw
		var path: String = "%s/%s.png" % [out, view[0]]
		var err := root.get_viewport().get_texture().get_image().save_png(path)
		print("CAPTURE %s err=%d" % [path, err])
	quit(0)
