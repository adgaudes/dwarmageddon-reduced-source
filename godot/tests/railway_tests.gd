extends SceneTree
## Test del livello 2, la ferrovia, sul rilievo continuo (tappa B): pianta rettangolare,
## fascia dei binari piatta e libera, cortile a cavallo, vagoni come cumuli con vena,
## depositi e trincee fuori fascia, saltatori per pendenza. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/railway_tests.gd

const RunScene := preload("res://scenes/main/railway_run.tscn")

var _failures := 0
var _scene: Node3D
var _district: RailwayDistrict
var _field: TerrainField
var _path: PathField
var _player: PlayerCharacter
var _director: EnemyDirector
var _scrap: ScrapField
var _run: ArenaRun


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_district = _scene.get_node(^"District")
	_field = _scene.get_node(^"TerrainField")
	_path = _scene.get_node(^"PathField")
	_player = _scene.get_node(^"Player")
	_director = _scene.get_node(^"EnemyDirector")
	_scrap = _scene.get_node(^"ScrapField")
	_run = _scene.get_node(^"Run")
	_director.spawning = false
	await _frames(5)
	_test_caravan_wiring()
	_test_scale()
	_test_track_strip()
	_test_start_courtyard_straddles_tracks()
	_test_wagons()
	_test_features_off_tracks()
	_test_blocks_inside_and_off_tracks()
	_test_determinism()
	_test_trenches_reserved()
	await _test_baked_base_matches_code()
	await _test_spawn_and_path_in_corridor()
	await _test_markers_include_wagons()
	await _test_hoppers()
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


func _strokes(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in _district.terrain_strokes:
		if s.kind == kind:
			out.append(s)
	return out


## Collegamenti della carovana nella scena (task 3 di D-093): un NodePath sbagliato in una
## scena non da errore, lascia la proprieta nulla.
func _test_caravan_wiring() -> void:
	print("caravan wiring")
	var caravan := _scene.get_node_or_null(^"Caravan") as Caravan
	var lead := caravan.lead() if caravan != null else null
	_check(caravan != null and lead != null and lead.has_module(&"cargo"), "la scena ha la carovana, con un Cassone capofila")
	if lead == null:
		return
	var lamps: LampField = _scene.get_node(^"LampField")
	var audio: RunAudio = _scene.get_node(^"RunAudio")
	var train: TrainEvent = _scene.get_node(^"TrainEvent")
	_check(_run.caravan == caravan and lamps.caravan == caravan and audio.caravan == caravan and train.caravan == caravan,
		"Run, LampField, RunAudio e TrainEvent puntano alla carovana")
	_check(caravan.player == _player and caravan.scrap_field == _scrap and caravan.path_field == _path,
		"la carovana conosce giocatore, rottami e campo di percorso")
	_check(not _scrap.veins().is_empty(), "le vene di vagoni e depositi sono nel campo dei rottami (%d)" % _scrap.veins().size())
	_check(_run.write_queue.bodies.has(_player) and _run.write_queue.bodies.has(lead), "giocatore e capofila in write_queue.bodies")


func _test_scale() -> void:
	print("scale")
	_check(_district.half_x() > _district.half_z() * 2.0, "corridoio lungo in X (%.0f x %.0f m)" % [_district.half_x() * 2.0, _district.half_z() * 2.0])
	_check((_field.half_extents() - _district.half_extents()).length() < 0.3, "il rilievo copre l'arena a meno di mezzo vertice (%s)" % _field.half_extents())
	_check(_field.resolution_x == 639 and _field.resolution_z == 246, "campo 639 x 246 vertici (%d x %d)" % [_field.resolution_x, _field.resolution_z])
	var collision: TerrainCollision = _field.get_node(^"Collision")
	_check(collision.chunk_count() == 21 * 9, "chunk di collisione 21 x 9 (%d)" % collision.chunk_count())
	_check(is_equal_approx(_path.half_extent, _district.half_x()) and is_equal_approx(_path.half_z(), _district.half_z()), "campo di percorso esteso all'arena rettangolare")
	_check(_path.world_columns == 266 and _path.world_rows == 102, "campo di 266 x 102 celle (%d x %d)" % [_path.world_columns, _path.world_rows])
	_check(_district.get_node_or_null(^"Tracks") != null, "binari costruiti")
	_check(_district.get_node_or_null(^"RuinCrowns") != null and _district.get_node_or_null(^"RuinRebar") != null, "corone e tondini delle rovine costruiti")


## La fascia e piatta a quota zero nella base, senza bump, e libera da ostacoli statici.
func _test_track_strip() -> void:
	print("track strip")
	var rect := _district.track_rect()
	_check(is_equal_approx(rect.position.y, -RailwayDistrict.TRACK_HALF_WIDTH) and is_equal_approx(rect.size.y, RailwayDistrict.TRACK_HALF_WIDTH * 2.0) and is_equal_approx(rect.size.x, _district.half_x() * 2.0),
		"track_rect copre tutta la lunghezza, 7,2 m di larghezza")
	_check(not RailwayDistrict.is_on_tracks(Vector2(0.0, 4.0)) and RailwayDistrict.is_on_tracks(Vector2(100.0, -3.5)), "is_on_tracks distingue dentro e fuori la fascia")
	var flat := true
	var no_bump := true
	var x := -_district.half_x() + 2.0
	while x < _district.half_x() - 2.0:
		for z: float in [-3.0, 0.0, 3.0]:
			var p := Vector3(x, 0.0, z)
			if absf(_field.base_height_at(p)) > 0.05:
				flat = false
			# I vagoni sporgono dalla base: fuori dai loro cumuli nessun bump.
			var near_wagon := false
			for w in _strokes(&"wagon"):
				if absf(w.center.x - x) < w.radius + 0.5:
					near_wagon = true
			if not near_wagon and _field.delta_at(p) > 0.05:
				no_bump = false
		x += 1.5
	_check(flat, "la base della fascia e a quota zero per tutta la lunghezza")
	_check(no_bump, "fuori dai vagoni la fascia non sporge dalla base")
	_check(absf(_field.base_height_at(Vector3(40.0, 0.0, 6.5))) < 1.3 and absf(_field.base_height_at(Vector3(40.0, 0.0, 20.0))) < 2.5, "oltre il raccordo il rilievo riprende")
	var space := _district.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(_district.half_x() * 2.0 - 2.0, 2.0, RailwayDistrict.TRACK_HALF_WIDTH * 2.0 - 0.2)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), Vector3(0.0, 1.2, 0.0))
	query.collision_mask = 1
	var foreign := 0
	for hit in space.intersect_shape(query, 128):
		if hit.collider != _field.collision_body():
			foreign += 1
	_check(foreign == 0, "nessun ostacolo statico sulla fascia dei binari (%d)" % foreign)


func _test_start_courtyard_straddles_tracks() -> void:
	print("start courtyard")
	var start := _strokes(&"start")
	_check(start.size() == 1 and start[0].center == Vector2.ZERO, "cortile di partenza all'origine")
	if start.is_empty():
		return
	var on_strip := 0
	for p: Vector2 in start[0].points:
		if absf(p.y) <= RailwayDistrict.TRACK_HALF_WIDTH + 1.0:
			on_strip += 1
	_check(on_strip == 0, "nessuna pennellata dell'anello sulla fascia")
	var r: float = start[0].radius
	# A nord e a sud ci sono i varchi: l'argine si sonda a 30 gradi dal varco.
	var beside := Vector2(sin(PI / 6.0), cos(PI / 6.0)) * r
	_check(_field.delta_at(Vector3(beside.x, 0.0, -beside.y)) > 0.9 and _field.delta_at(Vector3(beside.x, 0.0, beside.y)) > 0.9, "argini a nord e a sud in piedi")
	_check(_field.delta_at(Vector3(r, 0.0, 0.0)) < 0.2 and _field.delta_at(Vector3(-r, 0.0, 2.4)) < 0.2, "varchi est e ovest aperti sulla fascia")


func _test_wagons() -> void:
	print("wagons")
	var wagons := _strokes(&"wagon")
	_check(wagons.size() >= 3, "almeno tre vagoni sui binari (%d)" % wagons.size())
	var ok := true
	for i in wagons.size():
		var w: Dictionary = wagons[i]
		ok = ok and RailwayDistrict.is_on_tracks(w.center) and w.scrap == RailwayDistrict.WAGON_SCRAP and w.tint == RailwayDistrict.WAGON_TINT
		ok = ok and absf(w.center.x) >= _district.start_clear_radius + 6.0
		ok = ok and _field.delta_at(Vector3(w.center.x, 0.0, w.center.y)) > 1.2
		ok = ok and _scrap.vein_scrap_left(Vector3(w.center.x, 0.0, w.center.y)) == RailwayDistrict.WAGON_SCRAP
		for j in i:
			ok = ok and absf(wagons[j].center.x - w.center.x) >= _district.wagon_spacing - 0.01
	_check(ok, "ogni vagone e un cumulo sulla fascia con vena da %d, lontano dalla partenza e dagli altri" % RailwayDistrict.WAGON_SCRAP)


func _test_features_off_tracks() -> void:
	print("features")
	var kinds := {}
	var off := true
	var parallel := true
	for s: Dictionary in _district.terrain_strokes:
		kinds[s.kind] = kinds.get(s.kind, 0) + 1
		if s.kind == &"wagon" or s.kind == &"start":
			continue
		for p: Vector2 in s.points:
			off = off and not RailwayDistrict.is_on_tracks(p)
		if s.kind == &"trench":
			var a: Vector2 = s.points[0]
			var b: Vector2 = s.points[s.points.size() - 1]
			parallel = parallel and absf(a.y - b.y) < 0.01
	_check(kinds.get(&"deposit", 0) >= 4, "almeno quattro depositi fuori dai binari (%d)" % kinds.get(&"deposit", 0))
	_check(kinds.get(&"trench", 0) >= 2, "almeno due trincee (%d)" % kinds.get(&"trench", 0))
	var courtyards := 0
	for kind: StringName in kinds:
		if kind != &"start" and kind != &"deposit" and kind != &"trench" and kind != &"wagon":
			courtyards += kinds[kind]
	_check(courtyards >= 3, "almeno tre cortili secondari (%d)" % courtyards)
	_check(off, "cortili, depositi e trincee fuori dalla fascia dei binari")
	_check(parallel, "le trincee corrono parallele ai binari")


func _test_blocks_inside_and_off_tracks() -> void:
	print("blocks")
	var ex := _district.half_x()
	var ez := _district.half_z()
	var inside := true
	var off := true
	var low := true
	var blocks := 0
	for child in _district.get_children():
		if not (child is StaticBody3D) or not child.name.begins_with("Block"):
			continue
		blocks += 1
		var body := child as StaticBody3D
		var size := Vector3.ZERO
		for part in body.get_children():
			if part is CollisionShape3D:
				size = ((part as CollisionShape3D).shape as BoxShape3D).size
		low = low and size.y > 0.0 and size.y <= 4.5
		inside = inside and absf(body.position.x) + size.x * 0.5 <= ex and absf(body.position.z) + size.z * 0.5 <= ez
		off = off and absf(body.position.z) - size.z * 0.5 >= RailwayDistrict.TRACK_HALF_WIDTH
	_check(blocks >= 20, "almeno 20 rovine basse (%d)" % blocks)
	_check(low, "nessuna rovina interna piu alta di 4,5 m")
	_check(inside, "tutte le rovine dentro il rettangolo giocabile")
	_check(off, "nessuna rovina sopra la fascia dei binari")


func _test_determinism() -> void:
	print("determinism")
	var before := _district.terrain_strokes.duplicate(true)
	var stats_before := _district.stats.duplicate()
	_district.rebuild()
	_check(_district.terrain_strokes == before, "stesse pennellate dopo la ricostruzione")
	_check(_district.stats == stats_before, "stesse statistiche dopo la ricostruzione %s" % [_district.stats])


## Le trincee riservano la loro area: nessuna rovina sopra un solco e nessun solco sopra un altro.
func _test_trenches_reserved() -> void:
	print("trenches reserved")
	var trenches := _strokes(&"trench")
	var clear := true
	var apart := true
	for i in trenches.size():
		for p: Vector2 in trenches[i].points:
			for rect: Rect2 in _district.block_rects():
				clear = clear and not rect.grow(1.0).has_point(p)
		for j in i:
			apart = apart and trenches[i].center.distance_to(trenches[j].center) > 4.0
	_check(clear, "nessuna rovina sopra una trincea")
	_check(apart, "trincee distinte fra loro")


## La base cotta in `levels/railway/base.bin` e quella che il codice ricalcola: un file
## vecchio verrebbe caricato in silenzio (stesso seme), qui invece si confronta.
func _test_baked_base_matches_code() -> void:
	print("baked base")
	var fresh := TerrainField.new()
	fresh.size_m = _field.size_m
	fresh.tuning = _field.tuning
	fresh.render = false
	root.add_child(fresh)
	await _frames(2)
	_district.apply_base_relief(fresh)
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 400:
		var p := Vector3(rng.randf_range(-150.0, 150.0), 0.0, rng.randf_range(-58.0, 58.0))
		worst = maxf(worst, absf(fresh.height_at(p) - _field.base_height_at(p)))
	_check(worst < 0.01, "base cotta uguale a quella ricalcolata (scarto massimo %.4f m)" % worst)
	fresh.queue_free()
	await _frames(2)


func _test_spawn_and_path_in_corridor() -> void:
	print("corridor")
	_player.global_position = Vector3(100.0, _field.height_at(Vector3(100.0, 0.0, 0.0)) + 0.88, 0.0)
	_player.velocity = Vector3.ZERO
	await _frames(4)
	_check(_path.is_inside(_path.cell_of(_player.global_position)), "finestra ricentrata a 100 m lungo i binari")
	_check(_path.cost_at(_player.global_position) == 0.0, "costo zero sul giocatore")
	var inside := true
	var reachable := 0
	for i in 20:
		var spot: Variant = _director._find_spawn_point()
		if spot == null:
			inside = false
			continue
		inside = inside and absf(spot.x) <= _district.half_x() and absf(spot.z) <= _district.half_z()
		if _path.cost_at(spot) < PathField.UNREACHABLE:
			reachable += 1
	_check(inside, "punti di comparsa dentro il rettangolo")
	_check(reachable >= 15, "quasi tutti i punti di comparsa raggiungono il giocatore (%d/20)" % reachable)
	_player.global_position = Vector3(100.0, _field.height_at(Vector3(100.0, 0.0, 55.0)) + 0.88, 55.0)
	await _frames(4)
	var clamped := true
	for i in 20:
		var spot: Variant = _director._find_spawn_point()
		clamped = clamped and spot != null and absf(spot.z) <= _district.half_z()
	_check(clamped, "al bordo sud i punti restano dentro i 61 m")
	_player.global_position = Vector3(0.0, 0.88, 0.0)
	_player.velocity = Vector3.ZERO
	await _frames(4)


func _test_markers_include_wagons() -> void:
	print("markers")
	var hud: RunHud = _scene.get_node(^"RunHud")
	await _frames(70)
	var markers := _run.current_markers()
	var deposits := markers.filter(func(m: Dictionary) -> bool: return m.text == "ROTTAMI")
	_check(deposits.size() == 2, "due depositi indicati (%d)" % deposits.size())
	_check(hud.marker_count() == markers.size(), "l'HUD mostra gli stessi indicatori (%d)" % hud.marker_count())
	var nearest := INF
	var nearest_kind: StringName = &""
	for s: Dictionary in _district.terrain_strokes:
		var marker: Vector2 = s.marker
		if s.scrap > 0 and marker.length() >= ArenaRun.MARKER_MIN_DISTANCE and marker.length() < nearest:
			nearest = marker.length()
			nearest_kind = s.kind
	var first: Dictionary = deposits[0] if not deposits.is_empty() else {}
	_check(not first.is_empty() and absf(first.distance - nearest) < 0.1, "il primo indicato e il piu vicino (%s a %.0f m)" % [nearest_kind, nearest])
	# Vena azzerata: il marker del vagone sparisce.
	var wagon: Dictionary = _strokes(&"wagon")[0]
	_scrap.exhaust_veins_in_rect(Rect2(wagon.center - Vector2(4.0, 4.0), Vector2(8.0, 8.0)))
	await _frames(70)
	var left := _run.current_markers().filter(func(m: Dictionary) -> bool: return m.text == "ROTTAMI" and absf(m.distance - wagon.center.length()) < 0.5)
	_check(_scrap.vein_scrap_left(Vector3(wagon.center.x, 0.0, wagon.center.y)) == 0 and left.is_empty(), "a vena azzerata il vagone non e piu indicato")


## Saltatori (D-066, tappa B): dal tuning del livello 2, con meno vita e un altro colore,
## pendenza massima 1,2 e rallentamento in salita minore dei rottamatori.
func _test_hoppers() -> void:
	print("hoppers")
	var tuning := _director.tuning
	_check(tuning.hopper_share_max > 0.0 and RunTuning.new().hopper_share_max == 0.0, "quota dei saltatori solo nel tuning della ferrovia")
	var elapsed := _director.elapsed
	_director.elapsed = 0.0
	_check(is_zero_approx(_director.current_hopper_share()), "all'inizio nessun saltatore")
	_director.elapsed = tuning.hopper_start_seconds + tuning.hopper_ramp_seconds * 3.0
	_check(is_equal_approx(_director.current_hopper_share(), tuning.hopper_share_max), "a rampa finita la quota massima (%.0f%%)" % (tuning.hopper_share_max * 100.0))
	_director.elapsed = elapsed
	var walker := _director.spawn_at(Vector3(-12.0, 0.0, 12.0))
	var hopper := _director.spawn_kind(Vector3(-12.0, 0.0, 14.0), &"hopper")
	_check(hopper.kind == &"hopper" and is_equal_approx(hopper.max_grade, 1.2) and is_equal_approx(walker.max_grade, 0.8), "il saltatore sale fino a 1,2 m/m")
	_check(hopper.health == maxi(ceili(walker.health * tuning.hopper_health_share), 1), "meno vita (%d contro %d)" % [hopper.health, walker.health])
	_check(hopper.paint_material() != walker.paint_material(), "e di un altro colore")
	_check(is_equal_approx(_director.uphill_speed_scale(walker, 0.8), tuning.uphill_min_speed), "il rottamatore a 0,8 m/m va al minimo")
	_check(_director.uphill_speed_scale(hopper, 0.8) > _director.uphill_speed_scale(walker, 0.8) + 0.1, "il saltatore sulla stessa salita va piu forte")
	_check(is_equal_approx(_director.uphill_speed_scale(hopper, -0.5), 1.0), "in discesa velocita piena")
	for enemy: Enemy in [walker, hopper]:
		enemy.queue_free()
	_director.enemies.clear()
