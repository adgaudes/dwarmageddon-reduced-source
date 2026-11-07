extends SceneTree
## Catture del rilievo continuo (D-085), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 3000 --script res://tests/tools/capture_terrain.gd -- --out=../output/terrain
## Produce: rampart (argine alzato dal giocatore, anello giallo del modo Alza), trench
## (solco scavato), vein_half (cumulo con vena scavato a meta, rottami fuori), barricade
## (barricata a cumulo del Demolitore), pack_back_empty e pack_back_full (ingegnere da
## dietro con lo zainetto vuoto e pieno), overview (tutta l'arena dall'alto).

var _out := "../output/terrain"
var _scene: Node3D
var _player: PlayerCharacter
var _field: TerrainField
var _district: RuinsDistrict
var _camera: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	_scene = (load("res://scenes/main/arena_run.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_player = _scene.get_node(^"Player")
	_field = _scene.get_node(^"TerrainField")
	_district = _scene.get_node(^"District")
	var run: ArenaRun = _scene.get_node(^"Run")
	var director: EnemyDirector = _scene.get_node(^"EnemyDirector")
	var scrap: ScrapField = _scene.get_node(^"ScrapField")
	director.spawning = false
	(_scene.get_node(^"PlayerWeapon") as Node).set_physics_process(false)
	for i in 10:
		await physics_frame
	run._start_protect_left = 0.0
	_field.set_protected(Vector3.ZERO, _field.tuning.start_protected_radius_m, false)
	_player._invulnerable_left = 600.0
	_camera = _scene.get_node(^"CameraRig/Camera")

	# Argine alzato dal giocatore davanti a se, col pennello in modo Alza (anello giallo).
	_face(Vector3(0.0, 0.0, 4.0), Vector3.FORWARD)
	_set_mode(TerrainField.ToolMode.RAISE)
	await _hold(1.2)
	await _save("rampart")

	# Solco scavato di fianco.
	_face(Vector3(6.0, 0.0, 2.0), Vector3.RIGHT)
	_set_mode(TerrainField.ToolMode.DIG)
	await _hold(1.2)
	await _save("trench")

	# Cumulo con vena scavato a meta: i rottami escono dalla base.
	var deposit := _first_stroke(&"deposit")
	if not deposit.is_empty():
		var heap := Vector3(deposit.center.x, 0.0, deposit.center.y)
		_face(heap + Vector3(0.0, 0.0, 5.0), Vector3.FORWARD)
		await _hold(2.5)
		await _save("vein_half")

	# Barricata del Demolitore, chiamato e piazzato vicino.
	_set_mode(TerrainField.ToolMode.DIG)
	_player.tool_held = false
	_place(Vector3.ZERO, Vector3.FORWARD)
	run.boss_call_at = run.elapsed + 0.05
	for i in 20:
		await physics_frame
	run._boss_warning_left = 0.05
	for i in 20:
		await physics_frame
	var boss := run.boss as Demolisher
	if boss != null:
		boss.speed = 0.0
		boss.global_position = Vector3(0.0, _field.height_at(Vector3(0.0, 0.0, -8.0)) + Demolisher.boss_spawn_height(), -8.0)
		boss._raise_barricade_at(Vector3(0.0, 0.0, -4.0))
		for i in 20:
			await physics_frame
		await _save("barricade")
		boss.take_damage(boss.health)
	run.extraction_pad = null

	# Ingegnere da dietro con lo zainetto vuoto e pieno (camera libera alle spalle).
	var hud: CanvasLayer = _scene.get_node(^"RunHud")
	hud.visible = false
	_place(Vector3(20.0, 0.0, 20.0), Vector3.FORWARD)
	var closeup := Camera3D.new()
	closeup.fov = 35.0
	root.add_child(closeup)
	for fill: float in [0.0, 1.0]:
		_player.pack.take(_player.pack.capacity)
		if fill > 0.0:
			_player.pack.give(_player.pack.capacity)
		var at := _player.global_position + Vector3(0.0, 0.4, 0.0)
		closeup.look_at_from_position(at + Vector3(1.2, 1.0, 3.2), at)
		closeup.make_current()
		for i in 5:
			await physics_frame
		await _save("pack_back_%s" % ("full" if fill > 0.0 else "empty"))
	closeup.queue_free()
	_camera.make_current()
	hud.visible = true

	# Tutta l'arena dall'alto, senza nebbia.
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = maxf(_district.half_x(), _district.half_z()) * 2.0 + 16.0
	top.far = 400.0
	root.add_child(top)
	top.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(0.0, 150.0, 0.0))
	top.make_current()
	var environment: Environment = (_district.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	environment.fog_enabled = false
	hud.visible = false
	for i in 5:
		await process_frame
	await _save("overview")
	quit()


func _first_stroke(kind: StringName) -> Dictionary:
	for stroke: Dictionary in _district.terrain_strokes:
		if stroke.kind == kind:
			return stroke
	return {}


func _place(at: Vector3, facing: Vector3) -> void:
	_player.global_position = Vector3(at.x, _field.height_at(at) + 0.88, at.z)
	_player.velocity = Vector3.ZERO
	_player.look_at(_player.global_position + facing, Vector3.UP)
	_player._update_terrain_target()


## Il giocatore a un passo dal bersaglio, che guarda verso [param facing].
func _face(target: Vector3, facing: Vector3) -> void:
	var reach: float = _field.tuning.tool_range_m + _player.tool_range_bonus_m
	_place(target - facing.normalized() * reach, facing)


func _set_mode(mode: int) -> void:
	while _player.terrain_tool_mode != mode:
		_player._toggle_terrain_mode()


func _hold(seconds: float) -> void:
	_player.tool_held = true
	for i in int(seconds * 60.0):
		await physics_frame
	_player.tool_held = false
	for i in 5:
		await physics_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
