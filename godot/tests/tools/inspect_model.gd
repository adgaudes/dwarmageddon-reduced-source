extends SceneTree
## Stampa superfici, materiali e colori di vertice di un modello importato.
## Uso: godot_console --headless --path godot --script res://tests/tools/inspect_model.gd --quit-after 100 -- --model=overgrown_tree


func _initialize() -> void:
	var model_name := "overgrown_tree"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="):
			model_name = arg.trim_prefix("--model=")
	var scene: Node = (load("res://assets/models/%s.glb" % model_name) as PackedScene).instantiate()
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		print("MESH %s surfaces=%d" % [mi.name, mi.mesh.get_surface_count()])
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			var arrays := mi.mesh.surface_get_arrays(s)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var sample := ""
			if colors.size() > 0:
				sample = "%s .. %s" % [colors[0], colors[colors.size() - 1]]
			var tex := (mat as BaseMaterial3D).albedo_texture if mat is BaseMaterial3D else null
			var vc := (mat as BaseMaterial3D).vertex_color_use_as_albedo if mat is BaseMaterial3D else false
			var normal := (mat as BaseMaterial3D).normal_enabled and (mat as BaseMaterial3D).normal_texture != null if mat is BaseMaterial3D else false
			# ORM: l'import glTF mette roughness/metallo in roughness_texture/metallic_texture e
			# l'occlusione in ao_texture (restyling 2026-10-11).
			var std := mat as BaseMaterial3D
			var orm := std != null and (std.roughness_texture != null or std.metallic_texture != null)
			var ao := std != null and std.ao_enabled and std.ao_texture != null
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var tris := indices.size() / 3 if indices.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			print("  SURFACE %d name=%s texture=%s normal=%s orm=%s ao=%s vertex_color_albedo=%s colors=%d %s verts=%d tris=%d" % [
				s, mat.resource_name if mat else "", tex != null, normal, orm, ao, vc, colors.size(), sample,
				(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), tris])
	scene.free()
	quit()
