extends SceneTree
## Catture delle impronte dell'orda (FlowPreview), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --script res://tests/tools/capture_flow.gd -- --out=../output/flow
## Produce, dalla camera di gioco e dall'alto (`*_top`): open (cortile aperto subito
## dopo uno scavo), north_closed (stesso punto dopo aver chiuso il varco nord),
## sealed (tutti i varchi chiusi: le scie finiscono contro le mura), faded (a tempo scaduto).
## Stampa anche il costo di un tracciamento (FLOW_TRACE).

const WALL_DISTANCE := 9.6

var _out := "../output/flow"
var _scene: Node3D
var _top: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	_scene = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(_scene)
	var player: PlayerCharacter = _scene.get_node(^"Player")
	var field: TerrainField = _scene.get_node(^"TerrainField")
	(_scene.get_node(^"Run") as ArenaRun)._start_protect_left = 0.0
	field.set_protected(Vector3.ZERO, field.tuning.start_protected_radius_m, false)
	var director: EnemyDirector = _scene.get_node(^"EnemyDirector")
	var flow: FlowPreview = _scene.get_node(^"FlowPreview")
	director.spawning = false
	for i in 20:
		await physics_frame
	_top = Camera3D.new()
	_top.position = Vector3(0.0, 46.0, 0.0)
	_top.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_top.fov = 60.0
	root.add_child(_top)
	# Qualche rottamatore sulle scie: le impronte non devono nasconderli.
	for spot: Vector3 in [Vector3(0.6, 0.0, -11.5), Vector3(-0.8, 0.0, -6.5), Vector3(5.5, 0.0, 0.4), Vector3(-12.0, 0.0, 0.8)]:
		director.spawn_at(spot)
	director.set_physics_process(false)

	field.player_sculpt(Vector3(2.4, 0.0, 2.4), 2.4, -0.8, TerrainField.ToolMode.DIG)
	await _settle()
	_report(flow, "open")
	await _save_both("open")

	field.player_sculpt(Vector3(0.0, 0.0, -WALL_DISTANCE), 2.4, 1.4, TerrainField.ToolMode.RAISE)
	await _settle()
	_report(flow, "north_closed")
	await _save_both("north_closed")

	for gate: Vector3 in [Vector3(WALL_DISTANCE, 0.0, 0.0), Vector3(-WALL_DISTANCE, 0.0, 0.0), Vector3(0.0, 0.0, WALL_DISTANCE)]:
		field.player_sculpt(gate, 2.4, 1.4, TerrainField.ToolMode.RAISE)
	await _settle()
	_report(flow, "sealed")
	await _save_both("sealed")

	var total := 0
	for i in 200:
		flow.trace()
		total += flow.last_trace_usec
	print("FLOW_TRACE sealed avg_ms=%.3f marks=%d" % [total / 200000.0, flow.marks.size()])
	while flow.is_showing():
		await process_frame
	await _save("faded")
	quit()


## Aspetta il ricalcolo del campo e la dissolvenza in entrata.
func _settle() -> void:
	for i in 40:
		await physics_frame


func _report(flow: FlowPreview, name: String) -> void:
	print("FLOW_TRACE %s ms=%.3f marks=%d trails=%d reached=%d blocked=%d showing=%s"
		% [name, flow.last_trace_usec / 1000.0, flow.mark_count(), flow.trail_count,
			flow.reached_trails, flow.blocked_trails, flow.is_showing()])


func _save_both(name: String) -> void:
	await _save(name)
	var game_camera := root.get_camera_3d()
	_top.make_current()
	await _save("%s_top" % name)
	game_camera.make_current()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
