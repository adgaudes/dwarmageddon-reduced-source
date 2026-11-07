extends SceneTree
## Catture e misure dello spike del terreno a rilievo continuo (non e una suite).
## Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --quit-after 3000 --script res://tests/tools/capture_terrain_spike.gd -- --out=../output/terrain_spike [--size=204]
## Scolpisce da programma un cumulo, una trincea curva, una rampa e una piazzola, lascia
## camminare i rottamatori e salva la vista di gioco e due viste radenti. Stampa
## `TERRAIN_SPIKE_BENCH` (costo di pennello e campo di percorso, tempi di frame mentre
## si scolpisce senza sosta).

var _out := "../output/terrain_spike"
var _spike: TerrainSpike
var _closeup: Camera3D
var _game_camera: Camera3D


func _initialize() -> void:
	var size_m := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--size="):
			size_m = arg.trim_prefix("--size=").to_float()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	_spike = preload("res://scenes/spikes/terrain_spike.tscn").instantiate()
	if size_m > 0.0:
		_spike.terrain_size_m = size_m
	root.add_child(_spike)
	for i in 30:
		await physics_frame
	_game_camera = root.get_camera_3d()
	_closeup = Camera3D.new()
	_closeup.fov = 35.0
	_spike.add_child(_closeup)
	var terrain := _spike.terrain

	await _save("0_untouched")

	# Costo di un colpo di pennello.
	var started := Time.get_ticks_usec()
	for i in 80:
		terrain.sculpt(Vector3(6.0, 0.0, -5.0), TerrainSpike.BRUSH_RADIUS, 0.03)
	var sculpt_ms := (Time.get_ticks_usec() - started) / 80000.0
	# Trincea curva attorno al giocatore, a ovest.
	for i in 50:
		var angle := deg_to_rad(110.0 + i * 3.2)
		for pass_index in 3:
			terrain.sculpt(Vector3(sin(angle), 0.0, cos(angle)) * 8.5, 1.9, -0.45)
	# Argine alto e stretto a nord, con una rampa dolce dal lato del giocatore.
	for i in 24:
		terrain.sculpt(Vector3(-6.0 + i * 0.5, 0.0, -9.0), 2.0, 0.55)
	for i in 14:
		terrain.sculpt(Vector3(-9.0, 0.0, -1.5 - i * 0.5), 2.6, 0.02 * i)
	# Piazzola livellata su un fianco della collina.
	for i in 40:
		terrain.level(Vector3(-13.0, 0.0, -7.0), 3.5, 1.2, 0.2)

	started = Time.get_ticks_usec()
	for i in 10:
		_spike.field.rebuild(terrain, _spike.player.global_position, TerrainSpike.MAX_GRADE, TerrainSpike.FIELD_WINDOW_M)
	var field_ms := (Time.get_ticks_usec() - started) / 10000.0
	for i in 500:
		await physics_frame
	await _save("1_sculpted")
	_closeup.make_current()
	await _shot("2_trench_and_mound", Vector3(0.0, 0.5, 0.0), 26.0, 215.0, 24.0)
	await _shot("3_ridge_and_ramp", Vector3(-4.0, 0.8, -7.0), 20.0, 20.0, 20.0)
	await _shot("4_platform", Vector3(-13.0, 1.0, -7.0), 16.0, 300.0, 28.0)
	_game_camera.make_current()

	# Tempi di frame scolpendo senza sosta (caso peggiore) con i rottamatori in marcia.
	_spike.mode = TerrainSpike.Mode.RAISE
	var step_ms := 0.0
	var worst_step_ms := 0.0
	var frame_ms := 0.0
	var worst_frame_ms := 0.0
	var frames := 480
	var last := Time.get_ticks_usec()
	for i in frames:
		_spike.soil = TerrainSpike.SOIL_CAPACITY
		_spike.mode = TerrainSpike.Mode.RAISE if (i / 40) % 2 == 0 else TerrainSpike.Mode.DIG
		_spike.apply_brush(_spike.brush_target(), 1.0 / 120.0)
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_ms += (now - last) / 1000.0
		worst_frame_ms = maxf(worst_frame_ms, (now - last) / 1000.0)
		last = now
		step_ms += _spike.step_usec / 1000.0
		worst_step_ms = maxf(worst_step_ms, _spike.step_usec / 1000.0)
	var save_bytes := terrain.save_heights("user://terrain_spike_bench.bin")
	# `step` e il costo in CPU della scena per passo fisico (120 al secondo); `tick` il tempo
	# reale fra due passi, che il sincronismo verticale tiene comunque a 1/120 s.
	print("TERRAIN_SPIKE_BENCH vertices=%d sculpt_ms=%.3f field_ms=%.2f field_cells=%d step_ms_avg=%.3f step_ms_worst=%.2f tick_ms_avg=%.2f tick_ms_worst=%.2f fps=%d save_bytes=%d enemies=%d" % [
		terrain.resolution * terrain.resolution, sculpt_ms, field_ms, _spike.field.side * _spike.field.side,
		step_ms / frames, worst_step_ms, frame_ms / frames, worst_frame_ms, Engine.get_frames_per_second(), save_bytes, _spike.enemies.size()])
	quit()


func _shot(name: String, target: Vector3, distance: float, yaw_deg: float, pitch_deg: float) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	_closeup.look_at_from_position(target + offset, target)
	await _save(name)


func _save(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
