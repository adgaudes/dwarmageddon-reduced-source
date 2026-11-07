extends SceneTree
## Catture della luce del quartiere (playtest del 14 ottobre 2026, O-07): stessa inquadratura
## di gioco con ombre, SSAO e GI accesi o spenti, per vedere quanto contano. Non e una suite.
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 4000 --script res://tests/tools/capture_lighting.gd -- --out=../output/lighting [--preset=4] [--distance=2]

var _out := "../output/lighting"
var _preset := 4
var _distance := 2


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--preset="):
			_preset = int(arg.trim_prefix("--preset="))
		elif arg.begins_with("--distance="):
			_distance = int(arg.trim_prefix("--distance="))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	var settings := root.get_node(^"GameSettings")
	settings.set_preset(_preset)
	var scene: Node3D = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(scene)
	var player: PlayerCharacter = scene.get_node(^"Player")
	var rig := scene.get_node(^"CameraRig")
	for i in 240:
		player.set_max_health(5)
		player._invulnerable_left = 1.0
		await physics_frame
	rig.set_distance_index(_distance, true)
	for i in 30:
		await process_frame
	var sun: DirectionalLight3D = scene.find_child("SunLight", true, false)
	var env: Environment = (scene.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	print("LIGHTING sun=%s shadow=%s energy=%.2f ssao=%s ssil=%s sdfgi=%s ambient=%.2f" % [
		sun != null, sun.shadow_enabled, sun.light_energy, env.ssao_enabled, env.ssil_enabled,
		env.sdfgi_enabled, env.ambient_light_energy])
	await _save("p%d_all_on" % _preset)
	sun.shadow_enabled = false
	await _save("p%d_no_shadow" % _preset)
	sun.shadow_enabled = true
	var ssao := env.ssao_enabled
	env.ssao_enabled = false
	await _save("p%d_no_ssao" % _preset)
	env.ssao_enabled = ssao
	var ssil := env.ssil_enabled
	var sdfgi := env.sdfgi_enabled
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	await _save("p%d_no_gi" % _preset)
	env.ssil_enabled = ssil
	env.sdfgi_enabled = sdfgi
	var volumetric := env.volumetric_fog_enabled
	env.volumetric_fog_enabled = false
	await _save("p%d_no_volfog" % _preset)
	env.volumetric_fog_enabled = volumetric
	quit()


func _save(name: String) -> void:
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
