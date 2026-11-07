extends SceneTree
## Test dell'arena in rovina (D-036). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/ruins_arena_tests.gd

const ArenaScene := preload("res://scenes/main/ruins_arena.tscn")
const WORLD_STATIC := 1

var _failures := 0
var _scene: Node3D
var _arena: OvergrownArena
var _field: TerrainField
var _player: PlayerCharacter


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_scene = ArenaScene.instantiate()
	root.add_child(_scene)
	_arena = _scene.get_node(^"OvergrownArena")
	_field = _scene.get_node(^"TerrainField")
	_player = _scene.get_node(^"Player")
	await _frames(3)
	_test_build_is_deterministic()
	_test_clear_zone_is_free()
	_test_boundary_is_closed()
	await _test_player_stays_inside()
	_test_relief_present()
	# T-12: i nodi messi in coda con queue_free vanno liberati prima di uscire, o
	# il motore segnala istanze ObjectDB perse all'uscita.
	await _frames(2)
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


func _snapshot() -> Array:
	var result := []
	for child in _arena.get_children():
		# Le ombre delle nuvole (D-094) scorrono col vento: non fanno parte della costruzione.
		if child is Node3D and not child is CloudShadows:
			result.append([child.name.rstrip("0123456789@"), (child as Node3D).position.snapped(Vector3.ONE * 0.001)])
	return result


func _test_build_is_deterministic() -> void:
	print("determinism")
	var stats_before: Dictionary = _arena.stats.duplicate()
	var before := _snapshot()
	_arena.rebuild()
	var after := _snapshot()
	_check(stats_before == _arena.stats, "stesse statistiche dopo la ricostruzione %s" % [_arena.stats])
	_check(before.size() == after.size() and before == after, "stessi nodi nelle stesse posizioni (%d)" % after.size())
	_check(_arena.stats.blocks > 20 and _arena.stats.trees > 3 and _arena.stats.tufts > 1000, "arena popolata")


## Nessun ostacolo statico dell'arena dentro il quadrato della griglia e della corsia.
func _test_clear_zone_is_free() -> void:
	print("clear zone")
	var space := _scene.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	var half := _arena.clear_half_extent - 0.3
	shape.size = Vector3(half * 2.0, 2.5, half * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), Vector3(0.0, 1.6, 0.0))
	query.collision_mask = WORLD_STATIC
	var intruders: Array[String] = []
	for hit in space.intersect_shape(query, 64):
		var collider: Node = hit.collider
		if collider != _field.collision_body():
			intruders.append(str(collider.name))
	_check(intruders.is_empty(), "quadrato centrale libero (intrusi: %s)" % [intruders])


func _test_boundary_is_closed() -> void:
	print("boundary")
	var space := _scene.get_world_3d().direct_space_state
	var limit := _arena.play_half_extent * 1.42 + 1.5
	var open: Array[int] = []
	for i in 16:
		var angle := TAU * float(i) / 16.0
		var from := Vector3(0.0, 1.0, 0.0)
		var to := from + Vector3(cos(angle), 0.0, sin(angle)) * limit
		var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_STATIC)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			open.append(i)
	_check(open.is_empty(), "perimetro chiuso in 16 direzioni (aperte: %s)" % [open])


func _test_player_stays_inside() -> void:
	print("player inside")
	_player.global_position = Vector3(0.0, 0.88, 20.0)
	_player.velocity = Vector3.ZERO
	Input.action_press(&"move_back")
	await _frames(240)
	Input.action_release(&"move_back")
	var z := _player.global_position.z
	_check(z < _arena.play_half_extent + 0.1, "il muro sud ferma il giocatore (z=%.2f)" % z)


## L'arena in rovina sta su un campo da 128 m (tappa B): niente pavimento piatto.
func _test_relief_present() -> void:
	print("relief")
	_check(_field.resolution_x == 257 and _field.half_extents().is_equal_approx(Vector2(64.0, 64.0)), "campo da 128 m (%d vertici)" % _field.resolution_x)
	_check(_arena.terrain_field == _field and _arena._relief_ready(), "l'arena conosce il rilievo")
	_check(_arena.get_node_or_null(^"Ground") == null, "nessun pavimento piatto: il suolo e il rilievo")
