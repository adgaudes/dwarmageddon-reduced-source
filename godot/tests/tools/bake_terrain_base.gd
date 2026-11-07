extends SceneTree
## Cuoce il rilievo di base di un livello (D-085) in `levels/<id>/base.bin`: apre la
## scena del catalogo, toglie le aree protette, ricalcola `RuinsDistrict.apply_base_relief`
## e salva con `TerrainField.save_base`. Da rilanciare quando cambiano il seme del
## livello, il rumore o le rovine; il file e in LFS. Comando:
##   godot_console --headless --path godot --script res://tests/tools/bake_terrain_base.gd -- --level=railway
## (senza argomento: `district`).


func _initialize() -> void:
	var level_id := &"district"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_id = StringName(arg.trim_prefix("--level="))
	var scene_path := LevelCatalog.scene_of(level_id)
	var scene: Node3D = (load(scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame
	var district: RuinsDistrict = scene.get_node(^"District")
	var field: TerrainField = scene.get_node(^"TerrainField")
	var out := "res://levels/%s/base.bin" % level_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	# Il livello ha gia protetto rovine e cortile: la base si cuoce senza protezioni.
	field.set_protected(Vector3.ZERO, field.half_extents().length() * 2.0, false)
	district.apply_base_relief(field)
	var bytes := field.save_base(out, district.layout_seed)
	print("PROTOTYPE01_TERRAIN_BASE_BAKED level=%s path=%s bytes=%d" % [level_id, out, bytes])
	scene.queue_free()
	await physics_frame
	quit(0 if bytes > 0 else 1)
