extends SceneTree
## Cache delle pendenze e dei passi del campo di percorso (audit N-01): un ricentro copia
## i chunk gia calcolati invece di ricalcolare 4096 celle (51-64 ms misurati), i chunk
## attorno alla finestra si precalcolano a rate, e una modifica del terreno li invalida.
## Ogni controllo confronta la finestra con un ricalcolo completo dal terreno.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/path_cache_tests.gd

var _failures := 0
var _field: TerrainField
var _path: PathField
var _target: Node3D


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_field = TerrainField.new()
	_field.size_m = Vector2(160.0, 160.0)
	_field.tuning = TerrainTuning.new()
	root.add_child(_field)
	# Rilievo vario e ripetibile: cumuli e buche di ogni pendenza.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261014
	for i in 90:
		var at := Vector3(rng.randf_range(-76.0, 76.0), 0.0, rng.randf_range(-76.0, 76.0))
		_field.sculpt(at, rng.randf_range(1.5, 5.0), rng.randf_range(-1.6, 1.8))
	_target = Node3D.new()
	_target.position = Vector3(-60.0, 0.0, -60.0)
	root.add_child(_target)
	_path = PathField.new()
	_path.target = _target
	_path.terrain_field = _field
	_path.half_extent = 78.0
	_path.window_cells = 32
	_path.recenter_margin_cells = 4
	root.add_child(_path)
	await _frames(4)
	await _test_walk_matches_full_recompute()
	await _test_edits_inside_and_outside_window()
	await _test_prefetch_avoids_sync_work()
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Celle interne della finestra (a 2 celle dal bordo, dove le diagonali vedono le stesse
## vicine) diverse da un ricalcolo completo dal terreno.
func _mismatches() -> int:
	_path._flush_terrain()
	var slope := _path._slope_blocked.duplicate()
	var steps := _path._step_mask.duplicate()
	_path._slopes_all = true
	_path._refresh_slopes()
	var n := _path.columns
	var bad := 0
	# Celle bloccate (audit N-02: ricombinate solo nel rettangolo cambiato) su tutta la finestra.
	for i in n * n:
		var expected := 1 if _path._static_blocked[i] != 0 or slope[i] != 0 else 0
		if _path._blocked[i] != expected:
			bad += 1
	for y in range(2, n - 2):
		for x in range(2, n - 2):
			var i := y * n + x
			if slope[i] != _path._slope_blocked[i] or steps[i] != _path._step_mask[i]:
				bad += 1
	return bad


func _walk(from: Vector3, to: Vector3, step_m: float, frames_per_step: int) -> int:
	var worst := 0
	var steps := int(ceil(from.distance_to(to) / step_m))
	for k in steps + 1:
		_target.global_position = from.lerp(to, float(k) / steps)
		var recenters := _path.recenter_count
		await _frames(frames_per_step)
		if _path.recenter_count != recenters:
			worst = maxi(worst, _mismatches())
	return worst


func _test_walk_matches_full_recompute() -> void:
	print("walk")
	var before := _path.recenter_count
	var worst := await _walk(Vector3(-60.0, 0.0, -60.0), Vector3(60.0, 0.0, 60.0), 2.0, 2)
	_check(_path.recenter_count - before >= 10, "la finestra si e ricentrata lungo la diagonale (%d)" % (_path.recenter_count - before))
	_check(worst == 0, "dopo ogni ricentro la finestra coincide con il ricalcolo completo (%d celle diverse al peggio)" % worst)
	worst = await _walk(Vector3(60.0, 0.0, 60.0), Vector3(-60.0, 0.0, 60.0), 3.0, 1)
	_check(worst == 0, "anche tornando su zone gia viste (%d)" % worst)


func _test_edits_inside_and_outside_window() -> void:
	print("edits")
	var here := Vector3(-60.0, 0.0, 60.0)
	_target.global_position = here
	await _frames(3)
	# Dentro la finestra, poi via e ritorno.
	_field.sculpt(here + Vector3(3.0, 0.0, 2.0), 3.0, 1.6)
	_field.sculpt(here + Vector3(-4.0, 0.0, -3.0), 2.5, -1.4)
	await _frames(2)
	_check(_mismatches() == 0, "modifica nella finestra: coincide subito")
	await _walk(here, Vector3(60.0, 0.0, -60.0), 4.0, 1)
	var far := Vector3(-60.0, 0.0, -60.0)
	# Fuori dalla finestra (la finestra ora e lontana): cumulo e buca.
	_field.sculpt(far + Vector3(2.0, 0.0, 0.0), 3.5, 1.7)
	_field.sculpt(far + Vector3(-5.0, 0.0, 4.0), 3.0, -1.5)
	var worst := await _walk(Vector3(60.0, 0.0, -60.0), here, 4.0, 1)
	_check(worst == 0, "ritorno sulla modifica fatta nella finestra (%d)" % worst)
	worst = await _walk(here, far, 4.0, 1)
	_check(worst == 0, "arrivo sulla modifica fatta fuori dalla finestra (%d)" % worst)


func _test_prefetch_avoids_sync_work() -> void:
	print("prefetch")
	var here := Vector3(0.0, 0.0, 0.0)
	_target.global_position = here
	await _frames(3)
	# Tempo per precalcolare i chunk attorno alla finestra.
	await _frames(900)
	var sync_before := _path.terrain_chunks_sync
	var recenters := _path.recenter_count
	_target.global_position = here + Vector3(7.0, 0.0, 0.0)
	await _frames(2)
	_check(_path.recenter_count > recenters, "spostamento oltre il margine: ricentro")
	_check(_path.terrain_chunks_sync == sync_before, "il ricentro usa solo chunk gia pronti (%d calcolati sul momento)" % (_path.terrain_chunks_sync - sync_before))
	_check(_mismatches() == 0, "e coincide con il ricalcolo completo")
