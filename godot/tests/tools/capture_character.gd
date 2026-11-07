extends SceneTree
## Catture di un personaggio con scheletro (non e una suite). Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --script res://tests/tools/capture_character.gd -- --out=../output/character
## Mette in fila una copia del modello per posa (`POSES`: animazione e secondo), su un
## piano neutro, e salva la fila da davanti, da dietro e dalla camera di gioco. Stampa
## le animazioni del modello (`CHARACTER_ANIMATIONS`). `--model=res://...glb` cambia modello,
## `--poses=Jog_Fwd@0.2,Dig@1.5` sceglie le pose (animazione@secondo).

const SUIT_COLOR_LINEAR := Color(1.0, 0.35, 0.02)
## Animazione ("" = posa di riposo) e secondo a cui fermarla.
var POSES: Array[Array] = [
	["", 0.0], ["Idle", 0.0], ["Pistol_Idle", 0.0], ["Jog_Fwd", 0.0], ["Jog_Fwd", 0.25],
	["Pistol_Aim_Neutral", 0.0], ["Hit_Chest", 0.15], ["Interact", 1.0], ["Death01", 2.3],
]
const SPACING := 1.6

var _out := "../output/character"
var _model := "res://assets/models/player_engineer.glb"
var _camera: Camera3D
## Riempimenti dello zainetto da mostrare (`--pack=0,0.5,1`): una copia in riposo per valore.
var _pack_fills: Array[float] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--model="):
			_model = arg.trim_prefix("--model=")
		elif arg.begins_with("--pack="):
			for value in arg.trim_prefix("--pack=").split(","):
				_pack_fills.append(value.to_float())
		elif arg.begins_with("--poses="):
			POSES.clear()
			for pose in arg.trim_prefix("--poses=").split(","):
				POSES.append([pose.get_slice("@", 0), pose.get_slice("@", 1).to_float()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))

	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.32, 0.36, 0.4)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.42, 0.4, 0.36)
	floor_mesh.material_override = floor_material
	world.add_child(floor_mesh)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.make_current()

	var scene: PackedScene = load(_model)
	var suit := StandardMaterial3D.new()
	suit.vertex_color_use_as_albedo = true
	suit.roughness = 0.8
	suit.albedo_color = SUIT_COLOR_LINEAR.linear_to_srgb()
	for fill in _pack_fills:
		POSES.append(["", fill])
	for i in POSES.size():
		var model: Node3D = scene.instantiate()
		world.add_child(model)
		model.position.x = (i - (POSES.size() - 1) * 0.5) * SPACING
		ActorModel.apply_materials(ActorModel.mesh_instance_of(model), {
			"suit": suit,
			"detail": ActorModel.paint_material(Color.WHITE, 2.5),
		})
		if i >= POSES.size() - _pack_fills.size():
			_set_pack_fill(model, POSES[i][1])
			continue
		var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
		if i == 0:
			var lengths := PackedStringArray()
			for animation_name in player.get_animation_list():
				lengths.append("%s=%.2fs" % [animation_name, player.get_animation(animation_name).length])
			print("CHARACTER_ANIMATIONS ", ", ".join(lengths))
			print("CHARACTER_TREE")
			model.print_tree_pretty()
		var animation: String = POSES[i][0]
		if animation != "":
			player.play(animation)
			player.seek(POSES[i][1], true)
			player.pause()

	var center := Vector3(0.0, 0.85, 0.0)
	var width := POSES.size() * SPACING
	# Il fronte dei modelli guarda -Z: la camera "davanti" sta a z negativo.
	await _shot("row_front", center, width * 1.25, 180.0, 12.0)
	await _shot("row_back", center, width * 1.25, 0.0, 30.0)
	await _shot("row_game", center, width * 1.25, 0.0, 55.0)
	await _shot("row_side", center + Vector3(-width * 0.25, 0.0, 0.0), width * 0.7, 215.0, 15.0)
	await _shot("row_side_b", center + Vector3(width * 0.25, 0.0, 0.0), width * 0.7, 145.0, 15.0)
	quit()


## Zainetto di terra (spec sezione 3): striscia e sacca come le mostra PlayerCharacter.
func _set_pack_fill(model: Node3D, fill: float) -> void:
	var sack := model.find_child("PackSack", true, false) as MeshInstance3D
	if sack == null or sack.mesh == null:
		return
	var material := ShaderMaterial.new()
	material.shader = PlayerCharacter.PACK_GAUGE_SHADER
	material.set_shader_parameter(&"pack_fill", fill)
	for surface in sack.mesh.get_surface_count():
		var source := sack.mesh.surface_get_material(surface)
		if source != null and source.resource_name == "pack_gauge":
			sack.set_surface_override_material(surface, material)
	sack.scale = Vector3.ONE * (PlayerCharacter.PACK_FULL_SCALE if fill > 0.9 else 1.0)


func _shot(name: String, target: Vector3, distance: float, yaw_deg: float, pitch_deg: float) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	_camera.fov = 30.0
	_camera.look_at_from_position(target + offset, target)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
