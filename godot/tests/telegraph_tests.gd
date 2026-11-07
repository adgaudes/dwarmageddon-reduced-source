extends SceneTree
## Suite del telegrafo delle attive (piano 5 di D-092): anello di mira con la mira manuale,
## mai oltre la portata; lampo alla partenza in entrambe le mire; niente in pausa ne senza
## attive.
##   godot_console --headless --path godot --script res://tests/telegraph_tests.gd

var _failures := 0
var _root: Node3D
var _director: EnemyDirector
var _field: TerrainField
var _queue: TerrainWriteQueue


func _initialize() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	_director = EnemyDirector.new()
	_director.spawning = false
	_root.add_child(_director)
	_field = TerrainField.new()
	_field.render = false
	_field.size_m = Vector2(40.0, 40.0)
	get_root().add_child(_field)
	_queue = TerrainWriteQueue.new()
	_queue.terrain_field = _field
	get_root().add_child(_queue)
	await process_frame
	await _test_no_actives()
	await _test_manual_aim_ring()
	await _test_flash_and_pause()
	await _test_auto_aim_flash_only()
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
		await process_frame


func _loadout(manual: bool) -> WeaponLoadout:
	var shooter := Node3D.new()
	shooter.set_script(preload("res://tests/support/cursor_shooter.gd"))
	_root.add_child(shooter)
	var loadout := WeaponLoadout.new()
	loadout.player = shooter
	loadout.director = _director
	loadout.terrain_field = _field
	loadout.write_queue = _queue
	loadout.class_id = &"engineer"
	_root.add_child(loadout)
	loadout.set_manual_aim(manual)
	return loadout


func _dispose(loadout: WeaponLoadout) -> void:
	var shooter := loadout.player
	loadout.queue_free()
	shooter.queue_free()
	await _frames(2)


func _test_no_actives() -> void:
	print("no actives")
	var loadout := _loadout(true)
	await _frames(3)
	_check(loadout.telegraph != null and not loadout.telegraph.aim_ring.visible and not loadout.telegraph.flash_ring.visible,
		"senza attive nessun anello")
	await _dispose(loadout)


func _test_manual_aim_ring() -> void:
	print("manual aim ring")
	var loadout := _loadout(true)
	var stake := loadout.add(&"seismic_stake") as ActiveWeapon
	loadout.player.cursor = Vector3(20.0, 0.0, 0.0)
	await _frames(3)
	var ring := loadout.telegraph.aim_ring
	var reach := stake.stat(&"aim_range")
	var flat := Vector2(ring.global_position.x, ring.global_position.z)
	_check(ring.visible and flat.length() <= reach + 0.01 and flat.length() > reach - 0.5,
		"cursore lontano: anello alla portata (%.2f m su %.1f)" % [flat.length(), reach])
	_check(is_equal_approx(ring.scale.x, stake.stat(&"ring_radius")), "anello largo come l'anello del picchetto (%.1f m)" % ring.scale.x)
	var mat := ring.material_override as StandardMaterial3D
	var accent: Color = ClassCatalog.find(&"engineer").color
	_check(is_equal_approx(mat.albedo_color.r, accent.r) and is_equal_approx(mat.albedo_color.g, accent.g), "colore della classe")
	loadout.player.cursor = Vector3(2.0, 0.0, -2.0)
	await _frames(2)
	_check(Vector2(ring.global_position.x, ring.global_position.z).is_equal_approx(Vector2(2.0, -2.0)), "l'anello segue il cursore")
	await _dispose(loadout)


func _test_flash_and_pause() -> void:
	print("flash and pause")
	var loadout := _loadout(true)
	loadout.add(&"seismic_stake")
	loadout.player.cursor = Vector3(3.0, 0.0, 0.0)
	await _frames(2)
	_check(loadout.trigger_active(0), "il picchetto parte")
	await _frames(1)
	var telegraph := loadout.telegraph
	_check(telegraph.flash_ring.visible, "lampo alla partenza")
	_check(not telegraph.aim_ring.visible, "in ricarica niente anello di mira")
	var start := Time.get_ticks_msec()
	while telegraph.flash_ring.visible and Time.get_ticks_msec() - start < 2000:
		await process_frame
	var lasted := Time.get_ticks_msec() - start
	_check(not telegraph.flash_ring.visible and lasted < 1000, "il lampo si spegne da solo (%d ms)" % lasted)
	(loadout.actives()[0] as ActiveWeapon).cooldown_left = 0.0
	await _frames(2)
	_check(telegraph.aim_ring.visible, "carico di nuovo: anello di mira")
	paused = true
	await _frames(2)
	_check(not telegraph.aim_ring.visible and not telegraph.flash_ring.visible, "in pausa nessun anello")
	paused = false
	await _dispose(loadout)


func _test_auto_aim_flash_only() -> void:
	print("auto aim")
	var loadout := _loadout(false)
	loadout.add(&"seismic_stake")
	await _frames(3)
	_check(not loadout.telegraph.aim_ring.visible, "mira automatica: niente anello di mira")
	loadout.trigger_active(0)
	await _frames(1)
	_check(loadout.telegraph.flash_ring.visible, "mira automatica: lampo alla partenza")
	await _dispose(loadout)
