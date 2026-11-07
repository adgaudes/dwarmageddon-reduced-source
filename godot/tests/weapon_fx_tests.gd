extends SceneTree
## Effetti delle armi (D-092, piano 5, task 4): per ogni arma e fusione, con nemici davanti,
## nasce almeno un effetto nel gruppo `weapon_fx`; spenta l'arma, dopo 2 s non ne resta nessuno.
## Le fusioni devono mostrare anche un effetto proprio (meta `fx_fusion`). Il tetto di WeaponFx
## regge a molte armi insieme.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/weapon_fx_tests.gd

const SmokeTestScene := preload("res://scenes/main/smoke_test.tscn")

var _failures := 0
var _scene: Node3D
var _player: PlayerCharacter
var _director: EnemyDirector
var _field: TerrainField
var _queue: TerrainWriteQueue


func _initialize() -> void:
	_scene = SmokeTestScene.instantiate()
	root.add_child(_scene)
	_player = _scene.get_node(^"Player")
	_field = _scene.get_node(^"TerrainField")
	_director = EnemyDirector.new()
	_director.spawning = false
	_director.terrain_field = _field
	_director.tuning = RunTuning.new()
	_director.tuning.gnaw_delay_s = 999.0
	_scene.add_child(_director)
	_queue = TerrainWriteQueue.new()
	_queue.terrain_field = _field
	_scene.add_child(_queue)
	await _seconds(0.6)
	for case in _cases():
		await _test_case(case)
	await _test_cap()
	await _test_cap_priority()
	await _test_fx_ready()
	await _test_magnet_release()
	await _test_dozer_big_only()
	await _test_no_director()
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


func _fx_count() -> int:
	return _director.get_tree().get_node_count_in_group(WeaponFx.GROUP)


## Giocatore fermo al centro rivolto verso -Z, terreno alla base, nemici fermi e robusti: un
## anello a 2,2 m (le falci, l'onda) e un gruppo a 4-5 m davanti (le attive, i lanci).
func _reset() -> void:
	_queue.clear()
	_field.begin_batch()
	_field.reset_to_base(Vector3.ZERO, Vector2(30.0, 30.0))
	_field.end_batch()
	_director.player = null
	_player.global_position = Vector3(0.0, _field.height_at(Vector3.ZERO) + 1.0, 0.0)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	_player.set_max_health(1000)
	await _seconds(0.3)
	for i in 8:
		var a := TAU * i / 8.0
		_enemy(Vector3(cos(a), 0.0, sin(a)) * 2.2)
	for p: Vector3 in [Vector3(0, 0, -4), Vector3(0.6, 0, -4.4), Vector3(-0.6, 0, -4.2), Vector3(0.2, 0, -5), Vector3(-0.3, 0, -4.8)]:
		_enemy(p)


func _enemy(offset: Vector3) -> Enemy:
	var enemy := _director.spawn_at(_player.global_position + offset)
	enemy.health = 5000
	enemy.max_health = 5000
	enemy.speed_scale = 0.0
	return enemy


func _setup(w: Weapon, id: StringName, fusion: StringName) -> Weapon:
	w.weapon_id = id
	w.shooter = _player
	w.director = _director
	w.terrain_field = _field
	if &"write_queue" in w:
		w.set(&"write_queue", _queue)
	_scene.add_child(w)
	if fusion != &"":
		w.fusion_id = fusion
		w.set_level(WeaponCatalog.MAX_LEVEL)
	return w


## Armi e fusioni: {id, fusion, make (Callable -> Weapon), active}. Le fusioni anticipano il
## proprio colpo speciale, che di serie arriva dopo 4-10 s.
func _cases() -> Array[Dictionary]:
	return [
		{id = &"nailgun", make = func() -> Weapon: return _setup(AutoWeapon.new(), &"nailgun", &"")},
		{id = &"seismic_stake", active = true, make = func() -> Weapon: return _setup(SeismicStake.new(), &"seismic_stake", &"")},
		{id = &"fort", fusion = &"fort", make = func() -> Weapon:
			var w: Weapon = _setup(AutoWeapon.new(), &"nailgun", &"fort")
			w.set(&"_fort_left", 0.0)
			return w},
		{id = &"scrap_launcher", make = func() -> Weapon: return _setup(ScrapLauncher.new(), &"scrap_launcher", &"")},
		{id = &"dig_charge", active = true, make = func() -> Weapon: return _setup(DigCharge.new(), &"dig_charge", &"")},
		{id = &"mortar", fusion = &"mortar", make = func() -> Weapon:
			var w: ScrapLauncher = _setup(ScrapLauncher.new(), &"scrap_launcher", &"mortar")
			w.shots = 3
			return w},
		{id = &"welder", make = func() -> Weapon: return _setup(Welder.new(), &"welder", &"")},
		{id = &"crane_magnet", active = true, make = func() -> Weapon: return _setup(CraneMagnet.new(), &"crane_magnet", &"")},
		{id = &"tesla_coil", fusion = &"tesla_coil", make = func() -> Weapon: return _setup(Welder.new(), &"welder", &"tesla_coil")},
		{id = &"scythe", make = func() -> Weapon: return _setup(Scythe.new(), &"scythe", &"")},
		{id = &"bramble", active = true, make = func() -> Weapon: return _setup(Bramble.new(), &"bramble", &"")},
		{id = &"scythe_bramble", fusion = &"scythe_bramble", make = func() -> Weapon: return _setup(Scythe.new(), &"scythe", &"scythe_bramble")},
		{id = &"site_blade", make = func() -> Weapon: return _setup(SiteBlade.new(), &"site_blade", &"")},
		{id = &"ram", active = true, make = func() -> Weapon: return _setup(Ram.new(), &"ram", &"")},
		{id = &"disc_dozer", fusion = &"disc_dozer", make = func() -> Weapon:
			var w: Weapon = _setup(SiteBlade.new(), &"site_blade", &"disc_dozer")
			w.set(&"_big_left", 0.1)
			return w},
		{id = &"jackhammer", make = func() -> Weapon: return _setup(Jackhammer.new(), &"jackhammer", &"")},
		{id = &"cement_mixer", active = true, make = func() -> Weapon: return _setup(CementMixer.new(), &"cement_mixer", &"")},
		{id = &"compactor", fusion = &"compactor", make = func() -> Weapon:
			var w: Jackhammer = _setup(Jackhammer.new(), &"jackhammer", &"compactor")
			w.waves = 2
			return w},
	]


func _test_case(case: Dictionary) -> void:
	await _reset()
	var weapon: Weapon = (case.make as Callable).call()
	var fusion: StringName = case.get(&"fusion", &"")
	var most := 0
	var fusion_fx := false
	for frame in int(4.0 * Engine.physics_ticks_per_second):
		if case.get(&"active", false) and frame % 30 == 0:
			(weapon as ActiveWeapon).cooldown_left = 0.0
			(weapon as ActiveWeapon).trigger()
		await physics_frame
		most = maxi(most, _fx_count())
		if fusion != &"" and not fusion_fx:
			for node in get_nodes_in_group(WeaponFx.GROUP):
				if node.get_meta(&"fx_fusion", &"") == fusion:
					fusion_fx = true
					break
	_check(most > 0, "%s: nasce un effetto (al piu %d insieme)" % [case.id, most])
	if fusion != &"":
		_check(fusion_fx, "%s: c'e un effetto proprio della fusione" % case.id)
	weapon.process_mode = Node.PROCESS_MODE_DISABLED
	await _seconds(2.0)
	_check(_fx_count() == 0, "%s: dopo 2 s nessun effetto resta (%d)" % [case.id, _fx_count()])
	weapon.queue_free()
	_director.clear_horde()
	await _seconds(0.2)


## Molte richieste insieme: mai oltre il tetto di nodi vivi.
func _test_cap() -> void:
	for i in WeaponFx.MAX_LIVE + 20:
		WeaponFx.burst(_director, Vector3(i * 0.1, 0.5, 0.0), WeaponFx.RUST)
	_check(_fx_count() <= WeaponFx.MAX_LIVE, "tetto: %d effetti vivi su %d chiesti" % [_fx_count(), WeaponFx.MAX_LIVE + 20])
	await _seconds(2.0)
	_check(_fx_count() == 0, "tetto: tutti liberati")


## Effetti minori (polvere dei dischi, scintille a raffica) solo fino a MAX_LIVE - RESERVE: i
## posti rimasti sono per gli effetti che dicono che un'attiva e partita.
func _test_cap_priority() -> void:
	for i in WeaponFx.MAX_LIVE:
		WeaponFx.dust(_director, Vector3(i * 0.1, 0.5, 0.0), WeaponFx.DUST, 0.6, 4, 0.0, true)
	_check(_fx_count() == WeaponFx.MAX_LIVE - WeaponFx.RESERVE, "priorita: i minori si fermano a %d (%d)" % [WeaponFx.MAX_LIVE - WeaponFx.RESERVE, _fx_count()])
	_check(WeaponFx.shockwave(_director, Vector3.ZERO, 2.0, WeaponFx.SPARK) != null, "priorita: un'onda importante trova posto")
	await _seconds(2.0)


## Una raffica: al piu un effetto per chiave ogni intervallo di gioco.
func _test_fx_ready() -> void:
	var w := AutoWeapon.new()
	_scene.add_child(w)
	var first := w._fx_ready(&"k", 0.1)
	var again := w._fx_ready(&"k", 0.1)
	var other := w._fx_ready(&"j", 0.1)
	await _seconds(0.12)
	var later := w._fx_ready(&"k", 0.1)
	_check(first and not again and other and later, "_fx_ready: %s %s %s %s" % [first, again, other, later])
	w.queue_free()
	await process_frame


## Calamita lasciata finire: il rilascio ha il suo effetto (i casi sopra la riattivano prima).
func _test_magnet_release() -> void:
	await _reset()
	var magnet: CraneMagnet = _setup(CraneMagnet.new(), &"crane_magnet", &"")
	magnet.trigger()
	var pull := magnet.stat(&"pull_seconds")
	await _seconds(pull - 0.05)
	_check(magnet.pulling(), "calamita: ancora attira prima della fine")
	# Le scintille della partenza (0,35 s) sono finite da un pezzo: quel che nasce ora e il rilascio.
	var most := 0
	for frame in int(0.5 * Engine.physics_ticks_per_second):
		await physics_frame
		if not magnet.pulling():
			most = maxi(most, _fx_count())
	_check(not magnet.pulling() and most > 0, "calamita: effetto al rilascio (%d)" % most)
	magnet.queue_free()
	_director.clear_horde()
	await _seconds(2.0)


## Ruspa a dischi: l'effetto della fusione e solo quello del disco enorme.
func _test_dozer_big_only() -> void:
	await _reset()
	var blade: SiteBlade = _setup(SiteBlade.new(), &"site_blade", &"disc_dozer")
	blade.set(&"_big_left", 999.0)
	var tagged := false
	for frame in int(2.5 * Engine.physics_ticks_per_second):
		await physics_frame
		blade.set(&"_big_left", 999.0)
		for node in get_nodes_in_group(WeaponFx.GROUP):
			if node.get_meta(&"fx_fusion", &"") == &"disc_dozer":
				tagged = true
	_check(blade.disc_count() >= 0 and not tagged, "ruspa: i dischi normali non hanno l'effetto della fusione")
	blade.queue_free()
	_director.clear_horde()
	await _seconds(2.0)


## Senza direttore ne terreno (un'arma appena creata, una prova): l'effetto nasce sotto l'arma.
func _test_no_director() -> void:
	await _reset()
	var stake := SeismicStake.new()
	stake.weapon_id = &"seismic_stake"
	stake.shooter = _player
	_scene.add_child(stake)
	stake.trigger()
	var most := 0
	for frame in int(1.5 * Engine.physics_ticks_per_second):
		await physics_frame
		var mine := 0
		for node in get_nodes_in_group(WeaponFx.GROUP):
			if stake.is_ancestor_of(node):
				mine += 1
		most = maxi(most, mine)
	_check(most > 0 and stake.fx_parent() == stake, "senza direttore: effetti sotto l'arma (%d)" % most)
	stake.queue_free()
	_director.clear_horde()
	await _seconds(0.3)
