extends SceneTree
## Banco di prova della luce (D-094): carica il quartiere una volta e cattura le stesse
## inquadrature con piu varianti di Environment e sole, lette da un JSON. Non e una suite.
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 20000 --script res://tests/tools/lighting_lab.gd -- --variants=<file.json> --out=../output/lighting_lab [--preset=3] [--night|--dusk] [--scene=railway] [--hud] [--visit=x,z]...
## Il JSON e un dizionario nome -> {"env": {proprieta: valore}, "sun": {...}, "sun_dir": [x, y, z],
## "clouds_off": true}.
## I colori si scrivono come [r, g, b]; le costanti come numeri. Ogni variante parte dallo
## stato di gioco: i valori toccati si ripristinano prima della successiva.

var _out := "../output/lighting_lab"
var _preset := 3
var _night := false
var _dusk := false
var _scene_path := "res://scenes/main/arena_run.tscn"
var _variants_path := ""
var _visits: Array[Vector2] = []
var _hide_hud := true


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--preset="):
			_preset = int(arg.trim_prefix("--preset="))
		elif arg == "--night":
			_night = true
		elif arg == "--dusk":
			_dusk = true
		elif arg.begins_with("--scene="):
			_scene_path = "res://scenes/main/%s_run.tscn" % arg.trim_prefix("--scene=")
		elif arg == "--hud":
			_hide_hud = false
		elif arg.begins_with("--variants="):
			_variants_path = arg.trim_prefix("--variants=")
		elif arg.begins_with("--visit="):
			var parts := arg.trim_prefix("--visit=").split(",")
			_visits.append(Vector2(parts[0].to_float(), parts[1].to_float()))
	if _visits.is_empty():
		_visits.append(Vector2.ZERO)
	var variants := {"base": {}}
	if _variants_path != "":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_variants_path))
		if parsed is Dictionary:
			variants.merge(parsed)
		else:
			push_error("LAB variants non leggibili: %s" % _variants_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	root.get_node(^"GameSettings").set_preset(_preset)
	var scene: Node3D = (load(_scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	var player: PlayerCharacter = scene.get_node(^"Player")
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	if _hide_hud:
		(scene.get_node(^"RunHud") as CanvasLayer).visible = false
	var run := scene.get_node(^"Run")
	# Notte e tramonto veri: la run fa avanzare il ciclo (con torcia e lampioni). Il ciclo
	# si anticipa a ogni passo, perche la run lo riconfigura dopo il caricamento; si
	# aspetta il buio pieno o meta tramonto.
	var cycle: DayNightCycle = scene.get_node(^"DayNightCycle")
	var target := 1.0 if _night else (0.5 if _dusk else 0.0)
	for i in 6000:
		player.set_max_health(10)
		player._invulnerable_left = 1.0
		if target > 0.0:
			cycle.night_start_seconds = minf(cycle.night_start_seconds, 1.0)
		await physics_frame
		if i >= 120 and cycle.night_factor >= target:
			break
	print("LAB elapsed=%.1f night_factor=%.2f" % [run.get(&"elapsed"), cycle.night_factor])
	var sun: DirectionalLight3D = scene.find_child("SunLight", true, false)
	var env: Environment = (scene.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	for v in _visits.size():
		player.global_position = Vector3(_visits[v].x, player.global_position.y + 2.0, _visits[v].y)
		for frame in 45:
			player._invulnerable_left = 1.0
			await physics_frame
		for name: String in variants:
			var restore := _apply(variants[name], env, sun)
			for frame in 20:
				await process_frame
			await _save("%s_v%d" % [name, v])
			_restore(restore, env, sun)
	print("LAB done run=%s" % run.name)
	quit()


func _apply(spec: Dictionary, env: Environment, sun: DirectionalLight3D) -> Dictionary:
	var restore := {"env": {}, "sun": {}}
	for key: String in spec.get("env", {}):
		restore["env"][key] = env.get(key)
		env.set(key, _value(spec["env"][key], env.get(key)))
	for key: String in spec.get("sun", {}):
		restore["sun"][key] = sun.get(key)
		sun.set(key, _value(spec["sun"][key], sun.get(key)))
	var clouds := sun.get_parent().get_node_or_null(^"CloudShadows") as Node3D
	if spec.get("clouds_off", false) and clouds != null:
		restore["clouds"] = clouds
		clouds.process_mode = Node.PROCESS_MODE_DISABLED
		clouds.visible = false
	if spec.has("fill"):
		var f: Dictionary = spec["fill"]
		var fill := DirectionalLight3D.new()
		fill.light_energy = f.get("energy", 0.5)
		var c: Array = f.get("color", [0.6, 0.7, 1.0])
		fill.light_color = Color(c[0], c[1], c[2])
		fill.light_specular = 0.0
		var fd: Array = f.get("dir", [-0.2, -0.3, -1.0])
		fill.basis = Basis.looking_at(Vector3(fd[0], fd[1], fd[2]).normalized(), Vector3.UP)
		sun.get_parent().add_child(fill)
		restore["fill"] = fill
	if spec.has("sun_dir"):
		restore["basis"] = sun.basis
		var d: Array = spec["sun_dir"]
		sun.basis = Basis.looking_at(Vector3(d[0], d[1], d[2]).normalized(), Vector3.UP)
	return restore


func _restore(restore: Dictionary, env: Environment, sun: DirectionalLight3D) -> void:
	for key: String in restore["env"]:
		env.set(key, restore["env"][key])
	for key: String in restore["sun"]:
		sun.set(key, restore["sun"][key])
	if restore.has("basis"):
		sun.basis = restore["basis"]
	if restore.has("fill"):
		(restore["fill"] as Node).queue_free()
	if restore.has("clouds"):
		(restore["clouds"] as Node3D).process_mode = Node.PROCESS_MODE_INHERIT


func _value(raw: Variant, current: Variant) -> Variant:
	if current is Color and raw is Array:
		return Color(raw[0], raw[1], raw[2], raw[3] if raw.size() > 3 else 1.0)
	if current is int and raw is float:
		return int(raw)
	return raw


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
