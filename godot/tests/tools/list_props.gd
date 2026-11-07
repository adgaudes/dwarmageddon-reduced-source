extends SceneTree
## Stampa le posizioni dei prop con modello Blender del livello scelto (per le catture
## ravvicinate). Uso: godot_console --headless --path godot --script res://tests/tools/list_props.gd --quit-after 300 -- --scene=railway

var _scene_path := "res://scenes/main/arena_run.tscn"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene_path = "res://scenes/main/%s_run.tscn" % arg.trim_prefix("--scene=")
	var scene: Node = (load(_scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var district := scene.find_child("*District*", true, false)
	if district == null:
		district = scene.find_child("*Arena*", true, false)
	for name in ["WreckedCar", "TrainCarriage", "Tree", "ConcreteBarrier", "LampPost"]:
		var found := 0
		for node: Node3D in district.find_children(name, "StaticBody3D", false, false):
			if found < 4:
				print("PROP %s %.1f,%.1f,%.1f" % [name, node.global_position.x, node.global_position.y, node.global_position.z])
			found += 1
		print("PROP_COUNT %s %d" % [name, found])
	quit()
