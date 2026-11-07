extends SceneTree
## Scrive su file lo shader che Terrain3D genera per il suo materiale: e il punto di
## partenza di `resources/materials/terrain_relief.gdshader` (override del Task 14 del
## terreno continuo). Serve una finestra (in headless Terrain3D non esiste). Da rilanciare
## quando si aggiorna Terrain3D, poi riportare a mano il blocco "Rilievo (D-082)".
##   godot_console --path godot --resolution 320x200 --script res://tests/tools/dump_terrain_shader.gd -- --out=<file>

var _out := "user://terrain_generated.gdshader"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 12.0, 12.0), Vector3.ZERO, Vector3.UP)
	camera.current = true
	await process_frame
	var field := TerrainField.new()
	field.size_m = Vector2(64.0, 64.0)
	field.tuning = TerrainTuning.new()
	root.add_child(field)
	for i in 6:
		await process_frame
	var terrain := field.terrain3d()
	if terrain == null:
		print("DUMP_TERRAIN_SHADER FAIL reason=no_terrain3d (serve una finestra)")
		quit(1)
		return
	var material: Terrain3DMaterial = terrain.material
	material.shader_override_enabled = true
	await process_frame
	var shader: Shader = material.shader_override
	if shader == null or shader.code.is_empty():
		print("DUMP_TERRAIN_SHADER FAIL reason=empty_override")
		quit(1)
		return
	var file := FileAccess.open(_out, FileAccess.WRITE)
	file.store_string(shader.code)
	file.close()
	print("DUMP_TERRAIN_SHADER path=%s lines=%d" % [_out, shader.code.count("\n")])
	quit(0)
