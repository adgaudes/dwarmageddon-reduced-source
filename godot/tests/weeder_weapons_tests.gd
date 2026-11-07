extends SceneTree
## Armi dell'Erbacciaia (D-092, piano 3, task 4): Falce rotante, Roveto, Falciarovi e i bivi.
## Scena di prova con un giocatore vero: i test di rallentamento hanno bisogno che il direttore
## muova i nemici (`director.player`); i test da fermi lo staccano (`_still`).
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/weeder_weapons_tests.gd

const SmokeTestScene := preload("res://scenes/main/smoke_test.tscn")

var _failures := 0
var _scene: Node3D
var _player: PlayerCharacter
var _director: EnemyDirector
var _field: TerrainField
var _queue: TerrainWriteQueue
var _weapons: Array[Node] = []


func _initialize() -> void:
	_scene = SmokeTestScene.instantiate()
	root.add_child(_scene)
	_player = _scene.get_node(^"Player")
	_director = EnemyDirector.new()
	_director.spawning = false
	_director.player = _player
	_field = _scene.get_node(^"TerrainField")
	_director.terrain_field = _field
	_scene.add_child(_director)
	_queue = TerrainWriteQueue.new()
	_queue.terrain_field = _field
	_scene.add_child(_queue)
	await _seconds(0.5)
	await _test_scythe_base()
	await _test_scythe_meadow_speed()
	await _test_scythe_long()
	await _test_scythe_sharp()
	await _test_scythe_haymaking()
	await _test_scythe_furrow()
	await _test_bramble_shape()
	await _test_bramble_crossing()
	await _test_bramble_expires()
	await _test_bramble_gnawed()
	await _test_bramble_ring()
	await _test_bramble_roots()
	await _test_bramble_advance()
	await _test_scythe_bramble_trail()
	await _test_no_meadow()
	await _test_boss()
	await _seconds(0.1)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _seconds(s: float) -> void:
	for i in int(s * Engine.physics_ticks_per_second):
		await physics_frame


func _planar(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Giocatore fermo al centro, rivolto verso -Z, terreno alla base; nemici fermi se [param still].
func _reset(still: bool) -> void:
	_queue.clear()
	_field.begin_batch()
	_field.reset_to_base(Vector3.ZERO, Vector2(30.0, 30.0))
	_field.end_batch()
	_director.player = _player
	_player.global_position = Vector3(0.0, _field.height_at(Vector3.ZERO) + 1.0, 6.0)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	_player.set_max_health(10)
	await _seconds(0.5)
	_director.player = null if still else _player


func _clear() -> void:
	_director.clear_horde()
	for w in _weapons:
		if is_instance_valid(w):
			w.queue_free()
	_weapons.clear()
	_director.player = _player
	await _seconds(0.3)


func _enemy(offset: Vector3, hp := 50) -> Enemy:
	var enemy := _director.spawn_at(_player.global_position + offset)
	enemy.health = hp
	enemy.max_health = hp
	return enemy


func _setup(w: Weapon, level: int, picks: Dictionary) -> void:
	w.shooter = _player
	w.director = _director
	w.terrain_field = _field
	_scene.add_child(w)
	_weapons.append(w)
	w.set_level(level)
	for at: int in picks:
		w.choose_branch(at, picks[at])


func _scythe(level := 1, picks: Dictionary = {}) -> Scythe:
	var scythe := Scythe.new()
	scythe.weapon_id = &"scythe"
	_setup(scythe, level, picks)
	return scythe


func _bramble(level := 1, picks: Dictionary = {}) -> Bramble:
	var bramble := Bramble.new()
	bramble.weapon_id = &"bramble"
	bramble.write_queue = _queue
	_setup(bramble, level, picks)
	return bramble


## Danni presi in [param seconds] da un nemico fermo a [param distance] m dal giocatore.
func _hits_in(scythe_setup: Callable, distance: float, seconds: float) -> int:
	await _reset(true)
	var enemy := _enemy(Vector3(distance, 0.0, 0.0))
	var scythe: Scythe = scythe_setup.call()
	await _seconds(seconds)
	var lost := 50 - enemy.health
	scythe.queue_free()
	await _clear()
	return lost


## Secondi che un nemico partito a [param start] dal giocatore impiega ad arrivargli a
## [param stop] m, inseguendolo; [param setup] prepara le armi appena il nemico e nato.
func _time_to_reach(start: Vector3, stop: float, setup: Callable, limit := 6.0) -> float:
	await _reset(false)
	var enemy := _enemy(start)
	if setup.is_valid():
		setup.call()
	var frames := 0
	while frames < int(limit * Engine.physics_ticks_per_second):
		await physics_frame
		frames += 1
		if _planar(enemy.global_position - _player.global_position).length() <= stop:
			break
	return float(frames) / Engine.physics_ticks_per_second


# --- Falce rotante ---------------------------------------------------------------------

func _test_scythe_base() -> void:
	print("Falce rotante liv. 1")
	await _reset(true)
	var enemy := _enemy(Vector3(2.2, 0.0, 0.0))
	var scythe := _scythe()
	_check(scythe.blades == 2 and is_equal_approx(scythe.orbit_radius, 2.2), "valori dal catalogo")
	var frames := 0
	while enemy.health == 50 and frames < 90:
		await physics_frame
		frames += 1
	_check(enemy.health == 49, "un nemico fermo a 2,2 m prende 1 danno al primo passaggio (vita %d)" % enemy.health)
	await _seconds(0.45)
	_check(enemy.health == 49, "e non un secondo entro 0,5 s (vita %d)" % enemy.health)
	_check(scythe.blade_positions().size() == 2, "due falci")
	await _clear()


func _test_scythe_meadow_speed() -> void:
	print("Falce rotante sul prato")
	var off := await _hits_in(func() -> Scythe: return _scythe(), 2.2, 6.0)
	var on := await _hits_in(func() -> Scythe:
		var map := MeadowMap.new()
		map.setup(_field)
		map.mark(_player.global_position, 3.0)
		var scythe := _scythe()
		scythe.meadow = map
		return scythe, 2.2, 6.0)
	_check(on > off, "sul prato gira piu veloce: piu colpi in 6 s (%d contro %d)" % [on, off])


func _test_scythe_long() -> void:
	print("Falce lunga")
	var base := await _hits_in(func() -> Scythe: return _scythe(), 3.2, 1.6)
	var long := await _hits_in(func() -> Scythe: return _scythe(3, {3: &"a"}), 3.2, 1.6)
	_check(base == 0 and long >= 1, "colpisce a 3,2 m, dove la base non arriva (%d contro %d)" % [long, base])


func _test_scythe_sharp() -> void:
	print("Falce affilata")
	await _reset(true)
	var enemy := _enemy(Vector3(2.2, 0.0, 0.0))
	_scythe(3, {3: &"b"})
	var frames := 0
	while enemy.health == 50 and frames < 90:
		await physics_frame
		frames += 1
	_check(enemy.health == 48, "2 danni al colpo (vita %d)" % enemy.health)
	await _clear()


func _test_scythe_haymaking() -> void:
	print("Fienagione")
	await _reset(true)
	var map := MeadowMap.new()
	map.setup(_field)
	var enemy := _enemy(Vector3(2.2, 0.0, 0.0), 1)
	var point := enemy.global_position
	_check(not map.is_meadow(point), "prima niente prato")
	var scythe := _scythe(5, {3: &"b", 5: &"a"})
	scythe.meadow = map
	await _seconds(1.0)
	_check(not is_instance_valid(enemy) or enemy.is_dead, "il nemico vicino muore")
	_check(map.is_meadow(point), "dove e morto cresce il prato")
	await _clear()


func _test_scythe_furrow() -> void:
	print("Pale da scavo")
	var start := Vector3(5.5, 0.0, 0.0)
	var free := await _time_to_reach(start, 2.0, func() -> void: _scythe(5, {3: &"b", 5: &"a"}))
	await _clear()
	var furrow := await _time_to_reach(start, 2.0, func() -> void: _scythe(5, {3: &"b", 5: &"b"}))
	await _clear()
	_check(furrow > free + 0.08, "chi attraversa l'anello ci mette di piu (%.2f s contro %.2f s)" % [furrow, free])


# --- Roveto ------------------------------------------------------------------------------

func _test_bramble_shape() -> void:
	print("Roveto liv. 1")
	await _reset(true)
	var bramble := _bramble()
	_check(bramble.trigger(), "parte")
	var points := bramble.field().segment_positions()
	_check(points.size() == 6 and bramble.field().hedge_count() == 1, "una siepe di 6 tratti (%d)" % points.size())
	var min_x := INF
	var max_x := -INF
	var max_dz := 0.0
	var at_z := _player.global_position.z - 5.0
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		max_dz = maxf(max_dz, absf(p.z - at_z))
	_check(max_x - min_x > 4.5 and max_dz < 0.9, "di traverso al lancio (larga %.2f m, scarto %.2f m)" % [max_x - min_x, max_dz])
	_check(not bramble.trigger(), "poi si ricarica")
	await _clear()


func _test_bramble_crossing() -> void:
	print("Roveto: chi attraversa")
	var start := Vector3(0.0, 0.0, -9.0)
	var free := await _time_to_reach(start, 3.5, Callable())
	await _clear()
	var hurt := 0
	var through := await _time_to_reach(start, 3.5, func() -> void:
		var bramble := _bramble()
		bramble.trigger())
	for enemy in _director.enemies:
		hurt = 50 - enemy.health
	await _clear()
	_check(through > free + 0.25, "piu lento di uno libero (%.2f s contro %.2f s)" % [through, free])
	_check(hurt >= 1, "e perde vita (%d)" % hurt)


func _test_bramble_expires() -> void:
	print("Roveto: durata")
	await _reset(true)
	var bramble := _bramble()
	bramble.trigger()
	await _seconds(14.5)
	_check(bramble.field().hedge_count() == 1, "a 14,5 s c'e ancora")
	await _seconds(0.7)
	_check(bramble.field().hedge_count() == 0 and bramble.field().segment_count() == 0, "dopo 15 s sparisce")
	await _clear()


func _test_bramble_gnawed() -> void:
	print("Roveto rosicchiato")
	await _reset(true)
	var bramble := _bramble()
	bramble.trigger()
	var target: Vector3 = bramble.field().segment_positions()[0]
	for i in 5:
		var e := _director.spawn_at(target + Vector3(0.1 * (i - 2), 0.0, 0.05 * i))
		e.health = 50
	await _seconds(4.5)
	_check(bramble.field().segment_count() == 5, "cinque nemici fermi consumano un tratto in 4,5 s (%d tratti)" % bramble.field().segment_count())
	_check(bramble.field().hedge_count() == 1, "il resto della siepe resta")
	await _clear()


func _test_bramble_ring() -> void:
	print("Cerchio di rovi")
	await _reset(true)
	var bramble := _bramble(3, {3: &"a"})
	bramble.trigger()
	var at := _player.global_position + Vector3(0.0, 0.0, -5.0)
	var points := bramble.field().segment_positions()
	var on_ring := true
	var quadrants := {}
	for p in points:
		var offset := _planar(p - at)
		on_ring = on_ring and absf(offset.length() - 2.5) < 0.1
		quadrants[Vector2i(signi(roundi(offset.x * 10.0)), signi(roundi(offset.y * 10.0)))] = true
	_check(points.size() >= 14 and on_ring, "tratti a 2,5 m dal centro (%d)" % points.size())
	_check(quadrants.size() >= 4, "tutto attorno")
	await _clear()


func _test_bramble_roots() -> void:
	print("Radici")
	await _reset(false)
	var bramble := _bramble(5, {3: &"b", 5: &"a"})
	bramble.trigger()
	var enemy := _enemy(Vector3(0.0, 0.0, -8.0))
	var frames := 0
	while enemy.stun_left < 1.0 and frames < 300:
		await physics_frame
		frames += 1
	_check(enemy.stun_left >= 1.0, "chi entra viene fermato")
	var held := enemy.global_position
	await _seconds(1.25)
	_check(_planar(enemy.global_position - held).length() < 0.15, "resta fermo circa 1,5 s (%.2f m)" % _planar(enemy.global_position - held).length())
	await _seconds(1.0)
	_check(_planar(enemy.global_position - held).length() > 0.3, "poi riparte")
	await _clear()


func _test_bramble_advance() -> void:
	print("Rovo che avanza")
	await _reset(true)
	var bramble := _bramble(5, {3: &"b", 5: &"b"})
	var at := _player.global_position + Vector3(0.0, 0.0, -5.0)
	var cluster := at + Vector3(4.5, 0.0, 0.0)
	for i in 3:
		_director.spawn_at(cluster + Vector3(0.2 * i, 0.0, 0.0)).health = 50
	var id := bramble.plant(at)
	var before := _planar(bramble.field().hedge_center(id) - cluster).length()
	await _seconds(1.5)
	var after := _planar(bramble.field().hedge_center(id) - cluster).length()
	_check(after < before - 1.5, "la siepe si avvicina ai nemici (%.2f m -> %.2f m)" % [before, after])
	await _clear()


# --- Falciarovi --------------------------------------------------------------------------

func _test_scythe_bramble_trail() -> void:
	print("Falciarovi")
	await _reset(true)
	var scythe := _scythe(5, {3: &"a", 5: &"a"})
	scythe.fusion_id = &"scythe_bramble"
	scythe.set_level(5)
	await _seconds(1.0)
	var trail := scythe.trail()
	_check(trail != null and trail.segment_count() > 0, "in 1 s compaiono tratti di rovi")
	var on_orbit := true
	if trail != null:
		for p in trail.segment_positions():
			on_orbit = on_orbit and absf(_planar(p - _player.global_position).length() - scythe.orbit_radius) < 0.6
	_check(on_orbit, "lungo il giro delle falci")
	var most := 0
	for i in 6 * Engine.physics_ticks_per_second:
		await physics_frame
		most = maxi(most, trail.segment_count())
	_check(most <= Scythe.MAX_TRAIL and most > 20, "mai oltre 40 tratti vivi (massimo %d)" % most)
	await _clear()


func _test_no_meadow() -> void:
	print("senza prato")
	await _reset(true)
	var enemy := _enemy(Vector3(2.2, 0.0, 0.0), 1)
	var scythe := _scythe(5, {3: &"b", 5: &"a"})
	scythe.fusion_id = &"scythe_bramble"
	scythe.set_level(5)
	_check(scythe.meadow == null, "meadow assente")
	await _seconds(1.0)
	_check(not is_instance_valid(enemy) or enemy.is_dead, "Fienagione funziona senza prato")
	_check(scythe.trail() != null and scythe.trail().segment_count() > 0, "e anche la scia di rovi")
	await _clear()


func _test_boss() -> void:
	print("boss")
	await _reset(false)
	var boss := _enemy(Vector3(2.2, 0.0, 0.0))
	boss.self_driven = true
	var start := boss.global_position
	var scythe := _scythe(5, {3: &"b", 5: &"b"})
	scythe.fusion_id = &"scythe_bramble"
	scythe.set_level(5)
	var bramble := _bramble(5, {3: &"b", 5: &"a"})
	bramble.plant(boss.global_position)
	await _seconds(1.5)
	_check(boss.health < 50, "il boss prende danno")
	_check(_planar(boss.global_position - start).length() < 0.05, "ma non rallenta ne si ferma ne si sposta")
	_check(is_zero_approx(boss.stun_left) and is_zero_approx(boss.slow_left), "nessuno stordimento o rallentamento")
	await _clear()
