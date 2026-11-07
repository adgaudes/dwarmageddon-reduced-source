extends SceneTree
## Coda delle scritture delle armi sul terreno (spec D-092, par. 8-9). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/terrain_write_queue_tests.gd

var _failures := 0


func _initialize() -> void:
	var field := TerrainField.new()
	field.render = false
	field.size_m = Vector2(40.0, 40.0)
	get_root().add_child(field)
	var queue := TerrainWriteQueue.new()
	queue.terrain_field = field
	get_root().add_child(queue)
	await process_frame

	print("una scrittura per passo")
	for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		queue.push_level(Vector3(x, 0.0, 0.0), 1.0, 1.0)
	_check(queue.pending() == 5, "cinque scritture in coda")
	# `physics_frame` arriva prima del passo dei nodi: il primo passo si vede al secondo segnale.
	await physics_frame
	await physics_frame
	_check(queue.pending() == 4, "dopo un passo ne restano quattro (%d)" % queue.pending())
	for i in 4:
		await physics_frame
	_check(queue.pending() == 0, "dopo cinque passi la coda e vuota")
	var reached := true
	for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		reached = reached and is_equal_approx(field.height_at(Vector3(x, 0.0, 0.0)), 1.0)
	_check(reached, "ogni disco arriva alla quota chiesta al centro")

	print("punti scartati")
	field.set_protected(Vector3(0.0, 0.0, 10.0), 2.0, true)
	queue.push_level(Vector3(0.0, 0.0, 10.0), 1.0, 1.0)
	queue.push_level(Vector3(100.0, 0.0, 0.0), 1.0, 1.0)
	_check(queue.pending() == 0, "punto protetto e punto fuori campo non entrano in coda")

	print("raggio limitato")
	queue.push_level(Vector3(0.0, 0.0, -10.0), 6.0, 1.0)
	await physics_frame
	await physics_frame
	_check(is_equal_approx(field.height_at(Vector3(0.0, 0.0, -10.0)), 1.0), "il centro sale")
	_check(is_zero_approx(field.height_at(Vector3(0.0, 0.0, -14.0))), "a 4 m dal centro non cambia: raggio ridotto a 2,5 m")

	# Review I1: chi sta su un disco che sale viene sollevato, non resta incastrato.
	print("corpi sollevati")
	var director := EnemyDirector.new()
	director.spawning = false
	director.terrain_field = field
	get_root().add_child(director)
	queue.director = director
	var body := Node3D.new()
	get_root().add_child(body)
	body.global_position = Vector3(6.0, field.height_at(Vector3(6.0, 0.0, 6.0)) + 0.5, 6.0)
	queue.bodies = [body]
	await physics_frame
	var enemy := director.spawn_at(Vector3(-6.0, 0.0, 6.0))
	queue.push_level(Vector3(-6.0, 0.0, 6.0), 1.0, 1.2)
	queue.push_level(Vector3(6.0, 0.0, 6.0), 1.0, 1.2)
	for i in 4:
		await physics_frame
	var ground := field.height_at(enemy.global_position)
	_check(enemy.global_position.y >= ground + enemy.spawn_center_height() - 0.01, "il nemico sul disco sale col terreno (%.2f su %.2f)" % [enemy.global_position.y, ground])
	_check(is_equal_approx(body.global_position.y - field.height_at(body.global_position), 0.5), "il giocatore resta alla stessa altezza sul suolo")

	# Review I4: una scrittura urgente passa davanti alla coda.
	print("scrittura urgente")
	for i in 10:
		queue.push_level(Vector3(-15.0 + i, 0.0, -15.0), 0.5, 0.5)
	queue.push_level(Vector3(10.0, 0.0, -10.0), 1.0, 0.8, 1.0, true)
	# Un passo solo, a mano: con i segnali i passi elaborati dipendono dal momento della chiamata.
	queue.set_physics_process(false)
	queue._physics_process(0.0)
	queue.set_physics_process(true)
	_check(is_equal_approx(field.height_at(Vector3(10.0, 0.0, -10.0)), 0.8) and queue.pending() == 10, "l'urgente e la prima a essere scritta (%.2f m, %d in coda)" % [field.height_at(Vector3(10.0, 0.0, -10.0)), queue.pending()])
	queue.clear()

	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)
