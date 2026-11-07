extends SceneTree
## Orda sul rilievo continuo (spec sezione 4): rallentamento in salita, rottamatori che
## rosicchiano gli argini quando restano bloccati.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/terrain_horde_tests.gd

const PlayerScene := preload("res://scenes/player/player.tscn")

var _failures := 0
var _field: TerrainField
var _player: PlayerCharacter
var _path: PathField
var _director: EnemyDirector


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_field = TerrainField.new()
	_field.size_m = Vector2(64.0, 64.0)
	_field.tuning = TerrainTuning.new()
	root.add_child(_field)
	_player = PlayerScene.instantiate()
	_player.terrain_field = _field
	root.add_child(_player)
	_player.position = Vector3(0, 0.9, 0)
	_path = PathField.new()
	_path.target = _player
	_path.terrain_field = _field
	_path.half_extent = 30.0
	_path.window_cells = 0
	root.add_child(_path)
	_director = EnemyDirector.new()
	_director.player = _player
	_director.path_field = _path
	_director.tuning = RunTuning.new()
	_director.terrain_field = _field
	_director.spawning = false
	root.add_child(_director)
	await _frames(3)
	await _test_uphill_slows()
	await _test_enemy_gnaws_out_of_pit()
	await _test_spawn_on_mound()
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Review finale: un nemico nato su un cumulo deve nascere sopra il rilievo, non dentro
## (la heightfield ha una faccia sola: chi nasce sotto cade per sempre).
func _test_spawn_on_mound() -> void:
	print("spawn on mound")
	var at := Vector3(12.0, 0.0, 12.0)
	_field.sculpt(at, 3.0, 2.0)
	await _frames(2)
	var enemy := _director.spawn_at(at)
	var ground := _field.height_at(at)
	_check(enemy.global_position.y >= ground + Enemy.spawn_height() - 0.05, "nasce sopra il cumulo (y %.2f, suolo %.2f)" % [enemy.global_position.y, ground])
	await _frames(30)
	_check(enemy.global_position.y > _field.height_at(enemy.global_position) - 0.5, "dopo mezzo secondo e ancora sopra il suolo (y %.2f)" % enemy.global_position.y)
	_director.clear_horde()
	await _frames(2)


func _test_uphill_slows() -> void:
	print("uphill")
	# Dosso dolce (calpestabile) fra nemico e giocatore: il nemico lo sale dritto.
	_field.sculpt(Vector3(0, 0, -7), 6.0, 2.0)
	await _frames(2)
	_path.solve()
	var enemy := _director.spawn_kind(Vector3(0, 0.6, -11.5), &"scavenger")
	enemy.global_position.y = _field.height_at(enemy.global_position) + 0.6
	var flat := _director.spawn_kind(Vector3(26, 0.6, -11.5), &"scavenger")
	await _frames(45)
	var climbed := _planar(enemy.global_position - Vector3(0, 0, -11.5)).length()
	var walked := _planar(flat.global_position - Vector3(26, 0, -11.5)).length()
	_check(climbed < walked * 0.85, "in salita il rottamatore avanza meno (%.1f < %.1f)" % [climbed, walked])
	_director.clear_horde()
	await _frames(2)


func _test_enemy_gnaws_out_of_pit() -> void:
	print("gnaw")
	# Conca con pareti ripide attorno al nemico.
	var at := Vector3(-15, 0, 10)
	_field.sculpt(at, 2.0, -1.8)
	await _frames(2)
	var enemy := _director.spawn_kind(at, &"scavenger")
	enemy.global_position = Vector3(at.x, _field.height_at(at) + 0.6, at.z)
	var wall := at + Vector3(1.6, 0, -1.0)
	var h_wall := _field.height_at(wall)
	await _frames(60 * 4)
	_check(_director.gnaws > 0, "dopo 2 s fermo il nemico rosicchia (%d)" % _director.gnaws)
	_check(_field.height_at(wall) < h_wall - 0.05 or enemy.global_position.distance_to(at) > 3.0, "la parete si abbassa o il nemico e uscito")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _planar(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
