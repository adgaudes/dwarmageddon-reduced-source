extends SceneTree
## Benchmark del campo di percorso su un'arena grande (D-039). Non e una suite:
## il gate non lo esegue. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/tools/benchmark_path_field.gd -- [--extent=240] [--walls=400] [--window=64]
##
## Misura su un'arena sintetica (half_extent in metri, muri statici casuali):
## riempimento iniziale, costo del Dijkstra, costo di un ricentro, e un giro
## del bersaglio attraverso l'arena. Confronta anche con il campo intero
## (window_cells = 0) sulla stessa arena, se non e troppo grande.

var _world: Node3D
var _target: Node3D


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	var extent := _arg("extent", 240.0)
	var walls := int(_arg("walls", 400.0))
	var window := int(_arg("window", 64.0))
	_world = Node3D.new()
	root.add_child(_world)
	_target = Node3D.new()
	_world.add_child(_target)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in walls:
		var size := Vector3(rng.randf_range(1.0, 10.0), 1.0, rng.randf_range(1.0, 10.0))
		var center := Vector3(rng.randf_range(-extent + 6.0, extent - 6.0), 0.5, rng.randf_range(-extent + 6.0, extent - 6.0))
		_add_wall(center, size)
	await physics_frame
	await physics_frame
	print("BENCH arena=%0.0fx%0.0f m walls=%d cells=%d" % [extent * 2.0, extent * 2.0, walls, int(round(extent * 2.0 / 1.2)) ** 2])
	await _measure(extent, window)
	if extent <= 240.0:
		await _measure(extent, 0)
	quit(0)


func _measure(extent: float, window: int) -> void:
	_target.global_position = Vector3.ZERO
	var field := PathField.new()
	field.target = _target
	field.half_extent = extent
	field.window_cells = window
	field.min_solve_interval = 0.0
	var t0 := Time.get_ticks_usec()
	_world.add_child(field)
	while not field.is_ready():
		await physics_frame
	var ready_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var label := "window=%d" % window if window > 0 else "full"
	print("BENCH %s cells=%d ready_ms=%0.1f (chunks=%d) first_solve_ms=%0.2f"
		% [label, field.columns * field.columns, ready_ms, field.chunks_scanned, field.last_solve_usec / 1000.0])
	# Dijkstra ripetuto nella stessa posizione.
	var total := 0
	for i in 20:
		field.solve()
		total += field.last_solve_usec
	print("BENCH %s solve_avg_ms=%0.2f" % [label, total / 20.0 / 1000.0])
	# Giro: il bersaglio attraversa l'arena in diagonale a 6 m/s per 20 s simulati.
	var worst_frame := 0
	var recenters := field.recenter_count
	var recenter_total := 0
	var solve_total := 0
	var solves := 0
	var frames := 0
	var speed := 6.0
	var pos := Vector3(-extent + 2.0, 0.0, -extent + 2.0)
	var dir := Vector3(1.0, 0.0, 1.0).normalized()
	var t_start := Time.get_ticks_usec()
	while frames < 1200 and pos.x < extent - 2.0:
		var f0 := Time.get_ticks_usec()
		pos += dir * speed / 60.0
		_target.global_position = pos
		var before_solve := field.last_solve_usec
		var before_recenter := field.recenter_count
		await physics_frame
		var cost := Time.get_ticks_usec() - f0
		worst_frame = maxi(worst_frame, cost)
		if field.recenter_count != before_recenter:
			recenter_total += field.last_recenter_usec
		if field.last_solve_usec != before_solve:
			solve_total += field.last_solve_usec
			solves += 1
		frames += 1
	var elapsed_ms := (Time.get_ticks_usec() - t_start) / 1000.0
	recenters = field.recenter_count - recenters
	print("BENCH %s sweep frames=%d elapsed_ms=%0.0f worst_frame_ms=%0.2f recenters=%d recenter_avg_ms=%0.2f solves=%d solve_avg_ms=%0.2f chunks_total=%d"
		% [label, frames, elapsed_ms, worst_frame / 1000.0, recenters,
			(recenter_total / 1000.0 / recenters) if recenters > 0 else 0.0,
			solves, (solve_total / 1000.0 / solves) if solves > 0 else 0.0, field.chunks_scanned])
	field.queue_free()
	await physics_frame


func _add_wall(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	body.position = center


func _arg(name: String, fallback: float) -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.trim_prefix("--%s=" % name).to_float()
	return fallback
