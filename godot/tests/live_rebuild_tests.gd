extends SceneTree
## Test della ricostruzione immediata quando si modificano i parametri
## (Inspector dell'editor o codice). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/live_rebuild_tests.gd

const ArenaScript := preload("res://scripts/arena/arena.gd")
const CameraRigScript := preload("res://scripts/camera/isometric_camera_rig.gd")

var _failures := 0


func _initialize() -> void:
	# I valori attesi sono calcolati a 60 passi fisici al secondo; il progetto ne usa 120.
	Engine.physics_ticks_per_second = 60
	await _test_arena()
	await _test_camera_rig()
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _test_arena() -> void:
	print("arena")
	var arena: Arena = ArenaScript.new()
	root.add_child(arena)
	await process_frame
	var count := _live_children(arena)
	_check(count == 8, "8 nodi generati: pavimento, 4 pilastri, landmark, sole, ambiente (got %d)" % count)

	arena.floor_size_cm = 4000.0
	arena.pillar_height_cm = 800.0
	await process_frame
	await process_frame
	_check(_live_children(arena) == 8, "nessun duplicato dopo le modifiche (got %d)" % _live_children(arena))
	var floor_mesh: BoxMesh = (arena.get_node("Floor/Mesh") as MeshInstance3D).mesh
	_check(is_equal_approx(floor_mesh.size.x, 40.0), "pavimento ridimensionato a 40 m (got %.1f)" % floor_mesh.size.x)
	var pillar: Node3D = arena.get_node("CornerPillar0")
	_check(is_equal_approx(pillar.position.y, 4.0) and is_equal_approx(pillar.position.x, 16.5),
		"pilastro alto 8 m e spostato col pavimento (got %s)" % pillar.position)
	arena.queue_free()
	await process_frame


func _test_camera_rig() -> void:
	print("camera rig")
	var rig: IsometricCameraRig = CameraRigScript.new()
	root.add_child(rig)
	await process_frame
	var camera: Camera3D = rig.get_node("Camera")
	_check(is_equal_approx(camera.position.z, 15.0), "braccio iniziale 15 m")
	rig.arm_length_cm = 2000.0
	rig.horizontal_fov_degrees = 70.0
	_check(is_equal_approx(camera.position.z, 20.0) and is_equal_approx(camera.fov, 70.0), "braccio e FOV aggiornati subito")
	rig.queue_free()
	await process_frame


func _live_children(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count
