extends SceneTree
## Test dell'arena grande (D-042) sul rilievo continuo (D-085): quartiere in rovina
## con TerrainField di 204 m e punti di interesse come pennellate. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/district_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")

var _failures := 0
var _scene: Node3D
var _district: RuinsDistrict
var _field: TerrainField
var _path: PathField
var _player: PlayerCharacter
var _director: EnemyDirector


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_district = _scene.get_node(^"District")
	_field = _scene.get_node(^"TerrainField")
	_path = _scene.get_node(^"PathField")
	_player = _scene.get_node(^"Player")
	_director = _scene.get_node(^"EnemyDirector")
	_director.spawning = false
	# Prima del primo passo: il rilievo ha gia sporcato il campo di percorso e un costo
	# si deve poter leggere senza griglia (il bot lo fa al primo tick).
	_check(_path.cost_at(Vector3(10.0, 0.0, 10.0)) >= 0.0, "costo leggibile prima del primo passo fisico")
	await _frames(5)
	_test_scale()
	_test_features()
	_test_strokes_applied_to_field()
	_test_determinism()
	await _test_baked_base_matches_code()
	_test_blocks_are_low_and_inside()
	_test_start_area_is_clear()
	await _test_far_path_and_spawn()
	await _test_window_follows_player()
	await _test_markers()
	_test_ruin_crowns_follow_walls()
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


static func _at(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


func _test_scale() -> void:
	print("scale")
	_check(_district.play_half_extent >= 100.0, "area giocabile di almeno 200 m di lato (%.0f)" % (_district.play_half_extent * 2.0))
	_check(_field.resolution_x == 409 and _field.resolution_z == 409, "quartiere 204 m -> 409 vertici per lato (%d)" % _field.resolution_x)
	_check(absf(_field.half_extent() - _district.play_half_extent) <= 0.5, "il rilievo copre l'arena (%.1f m)" % (_field.half_extent() * 2.0))
	_check(is_equal_approx(_path.half_extent, _district.play_half_extent), "campo di percorso esteso all'arena")


func _test_features() -> void:
	print("features")
	var strokes := _district.terrain_strokes
	var kinds := {}
	for s: Dictionary in strokes:
		kinds[s.kind] = kinds.get(s.kind, 0) + 1
	_check(kinds.get(&"start", 0) == 1, "un cortile di partenza")
	var courtyards := strokes.filter(func(s: Dictionary) -> bool: return s.height > 0.0 and not s.gates.is_empty())
	_check(courtyards.size() >= 4, "almeno quattro cortili con varchi (%d)" % courtyards.size())
	_check(kinds.get(&"deposit", 0) >= 6, "almeno sei depositi di rottami (%d)" % kinds.get(&"deposit", 0))
	_check(kinds.get(&"trench", 0) >= 2, "almeno due trincee (%d)" % kinds.get(&"trench", 0))
	var start: Dictionary = strokes[0]
	_check(start.kind == &"start" and start.center == Vector2.ZERO and start.gates.size() == 4 and start.points.size() >= 20,
		"partenza: anello di pennellate con quattro varchi all'origine (%d punti)" % start.points.size())

	var far_apart := true
	var away_from_start := true
	var variants := {}
	for i in courtyards.size():
		var a: Dictionary = courtyards[i]
		if a.kind != &"start":
			variants[a.kind] = true
			away_from_start = away_from_start and a.center.length() >= _district.start_clear_radius
		for j in range(i + 1, courtyards.size()):
			var b: Dictionary = courtyards[j]
			if a.kind != &"start" and b.kind != &"start" and a.center.distance_to(b.center) < 40.0:
				far_apart = false
	_check(far_apart, "cortili secondari ad almeno 40 m l'uno dall'altro")
	_check(away_from_start, "cortili secondari fuori dall'area di partenza")
	_check(variants.size() >= 3, "almeno tre varianti di cortile %s" % [variants.keys()])

	var all_inside := true
	var half := _field.half_extents()
	for s: Dictionary in strokes:
		for p: Vector2 in s.points:
			all_inside = all_inside and absf(p.x) <= half.x and absf(p.y) <= half.y
	_check(all_inside, "tutte le pennellate dei punti di interesse sono dentro il rilievo")
	_check(int(_district.stats.get("strokes", 0)) == strokes.size(), "le statistiche contano le pennellate (%d)" % strokes.size())


## I punti di interesse sono pennellate sul rilievo: argini alti, cumuli con vena,
## cortili piani, base mossa (spec 6.1).
func _test_strokes_applied_to_field() -> void:
	print("strokes")
	var strokes := _district.terrain_strokes
	_check(strokes.size() >= 10, "il quartiere produce pennellate (%d)" % strokes.size())
	if strokes.is_empty():
		return
	var start: Dictionary = strokes[0]
	_check(start.kind == &"start" and start.points.size() > 8, "cortile di partenza come anello di pennellate (%d punti)" % start.points.size())
	var ring_point: Vector2 = start.points[0]
	_check(_field.height_at(_at(ring_point)) > 1.0, "l'argine del cortile e alto piu di 1 m (%.2f)" % _field.height_at(_at(ring_point)))
	_check(_field.delta_at(_at(ring_point)) > 0.8, "l'argine sporge dalla base (il Demolitore lo vede) (%.2f)" % _field.delta_at(_at(ring_point)))
	_check(absf(_field.height_at(Vector3.ZERO)) < 0.3, "il centro del cortile e quasi piano (%.2f)" % _field.height_at(Vector3.ZERO))
	var deposits := 0
	var heaps_ok := true
	for stroke: Dictionary in strokes:
		if stroke.kind == &"deposit":
			deposits += 1
			heaps_ok = heaps_ok and stroke.scrap >= 6 and _field.height_at(_at(stroke.center)) > 1.0
	_check(deposits >= 6, "almeno sei depositi (%d)" % deposits)
	_check(heaps_ok, "ogni deposito e un cumulo alto piu di 1 m con una vena di almeno 6 rottami")
	var bumpy := 0
	for i in 40:
		if absf(_field.base_height_at(Vector3(-90.0 + i * 4.5, 0.0, 60.0))) > 0.15:
			bumpy += 1
	_check(bumpy > 10, "il rilievo di base e mosso (%d/40 campioni oltre 15 cm)" % bumpy)


func _test_determinism() -> void:
	print("determinism")
	var strokes_before := _district.terrain_strokes.duplicate(true)
	var stats_before: Dictionary = _district.stats.duplicate()
	_district.rebuild()
	_check(_district.terrain_strokes == strokes_before, "stesse pennellate dopo la ricostruzione (%d)" % _district.terrain_strokes.size())
	_check(_district.stats == stats_before, "stesse statistiche dopo la ricostruzione %s" % [_district.stats])
	var other := RuinsDistrict.new()
	other.layout_seed = _district.layout_seed + 1
	other.grass_tufts = 0
	other.flowers = 0
	root.add_child(other)
	_check(other.terrain_strokes != strokes_before and other.terrain_strokes.size() >= 10, "un altro seme produce un altro quartiere")
	other.queue_free()


## La base cotta in `levels/district/base.bin` e quella che il codice ricalcola.
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
		var p := Vector3(rng.randf_range(-98.0, 98.0), 0.0, rng.randf_range(-98.0, 98.0))
		worst = maxf(worst, absf(fresh.height_at(p) - _field.base_height_at(p)))
	_check(worst < 0.01, "base cotta uguale a quella ricalcolata (scarto massimo %.4f m)" % worst)
	fresh.queue_free()
	await _frames(2)


func _test_blocks_are_low_and_inside() -> void:
	print("blocks")
	var e := _district.play_half_extent
	var low := true
	var inside := true
	var blocks := 0
	for child in _district.get_children():
		if not (child is StaticBody3D) or not child.name.begins_with("Block"):
			continue
		blocks += 1
		var body := child as StaticBody3D
		# Ingombro = la collisione (blocco pieno), non i pezzi visibili del guscio.
		var size := Vector3.ZERO
		for part in body.get_children():
			if part is CollisionShape3D:
				size = ((part as CollisionShape3D).shape as BoxShape3D).size
		low = low and size.y > 0.0 and size.y <= 4.5
		inside = inside and absf(body.position.x) + size.x * 0.5 <= e and absf(body.position.z) + size.z * 0.5 <= e
	_check(blocks >= 20, "almeno 20 rovine basse dentro il perimetro (%d)" % blocks)
	_check(low, "nessuna rovina interna piu alta di 4,5 m: non coprono il giocatore")
	_check(inside, "tutte le rovine interne dentro l'area giocabile")


func _test_start_area_is_clear() -> void:
	print("start area")
	var space := _district.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	var r := _district.start_clear_radius - 0.5
	shape.size = Vector3(r * 2.0, 2.0, r * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), Vector3(0.0, 1.0, 0.0))
	query.collision_mask = 1
	var terrain_body: StaticBody3D = _field.get_node(^"Collision").body
	var foreign := 0
	for hit in space.intersect_shape(query, 64):
		var collider: Node = hit.collider
		if collider != terrain_body:
			foreign += 1
	_check(foreign == 0, "nessun ostacolo statico nell'area di partenza (%d)" % foreign)


## Un nemico nato sull'anello attorno al giocatore trova la strada; il campo
## copre il giocatore ovunque si trovi.
func _test_far_path_and_spawn() -> void:
	print("path and spawn")
	var spot: Variant = _director._find_spawn_point()
	_check(spot != null, "punto di comparsa trovato sull'anello")
	if spot != null:
		var distance := Vector2(spot.x, spot.z).length()
		_check(distance >= _director.tuning.spawn_ring_min - 0.01 and distance <= _director.tuning.spawn_ring_max + 1.5,
			"a %.1f m dal giocatore" % distance)
		_check(_path.cost_at(spot) < PathField.UNREACHABLE, "il giocatore e raggiungibile da li")
	var enemy := _director.spawn_at(Vector3(0.0, 0.0, -14.0))
	await _frames(90)
	_check(enemy.global_position.z > -11.5, "il rottamatore avanza verso il cortile (z=%.1f)" % enemy.global_position.z)
	enemy.queue_free()
	_director.enemies.clear()


## Indicatori a bordo schermo: i piu vicini fuori vista, mai quelli esauriti.
## Audit R-05: corone e tondini delle rovine salgono e scendono con il loro muro sul rilievo.
func _test_ruin_crowns_follow_walls() -> void:
	print("ruin crowns")
	# Le prove precedenti ricostruiscono il quartiere a quota zero: lo si riappoggia (ripetibile).
	_district.settle_on_relief()
	# Con i muri a moduli (O-10) le corone a blocchi non ci sono piu: si controllano anche i tondini.
	var checked := 0
	var wrong := 0
	for pair: Array in [["RuinCrowns", _district._crown_hosts, _district._crown_buffer], ["RuinRebar", _district._rebar_hosts, _district._rebar_buffer]]:
		var details: MultiMeshInstance3D = _district.get_node_or_null(NodePath(pair[0]))
		if details == null:
			continue
		var hosts: Array = pair[1]
		var flat: PackedFloat32Array = pair[2]
		var live := details.multimesh.buffer
		for i in hosts.size():
			var host: Variant = hosts[i]
			if host == null or not (host as Node).has_meta(&"flat_y"):
				continue
			var shift := (host as Node3D).position.y - float((host as Node).get_meta(&"flat_y"))
			if absf(shift) < 0.05:
				continue
			checked += 1
			if absf(live[i * 16 + 7] - (flat[i * 16 + 7] + shift)) > 0.001:
				wrong += 1
	_check(checked > 10 and wrong == 0, "corone e tondini spostati con il loro muro (%d controllati, %d fuori posto)" % [checked, wrong])


func _test_markers() -> void:
	print("markers")
	var run: ArenaRun = _scene.get_node(^"Run")
	var hud: RunHud = _scene.get_node(^"RunHud")
	_player.global_position = Vector3(0.0, 0.88, 0.0)
	await _frames(70)
	var markers := run.current_markers()
	var courtyards := markers.filter(func(m: Dictionary) -> bool: return m.text == "CORTILE")
	var deposits := markers.filter(func(m: Dictionary) -> bool: return m.text == "ROTTAMI")
	_check(courtyards.size() == 2 and deposits.size() == 2, "due cortili e due depositi indicati (%d, %d)" % [courtyards.size(), deposits.size()])
	_check(hud.marker_count() == markers.size(), "l'HUD mostra gli stessi indicatori (%d)" % hud.marker_count())
	# Audit R-03: senza modifiche del terreno l'aggiornamento non riscandisce i cortili.
	var checks := run.marker_bump_checks
	run._refresh_marker_targets()
	run._refresh_marker_targets()
	_check(run.marker_bump_checks == checks, "terreno fermo: nessun nuovo controllo delle cime (%d)" % (run.marker_bump_checks - checks))
	var court: Dictionary = {}
	for s2: Dictionary in _district.terrain_strokes:
		if s2.height > 0.0 and s2.scrap <= 0:
			court = s2
			break
	_field.sculpt(Vector3(court.center.x, 0.0, court.center.y) + Vector3(court.radius, 0.0, 0.0), 1.0, 0.01)
	run._refresh_marker_targets()
	_check(run.marker_bump_checks > checks, "una pennellata su un cortile lo fa ricontrollare")
	var far := true
	for m: Dictionary in markers:
		far = far and m.distance >= ArenaRun.MARKER_MIN_DISTANCE
	_check(far, "nessun indicatore per cio che e gia in vista (il cortile di partenza no)")
	# Il deposito indicato e davvero il piu vicino, nella direzione giusta.
	var nearest := INF
	var nearest_center := Vector2.ZERO
	var nearest_radius := 0.0
	for s: Dictionary in _district.terrain_strokes:
		var marker: Vector2 = s.marker
		if s.kind == &"deposit" and marker.length() >= ArenaRun.MARKER_MIN_DISTANCE and marker.length() < nearest:
			nearest = marker.length()
			nearest_center = marker
			nearest_radius = s.radius
	var first: Dictionary = deposits[0] if not deposits.is_empty() else {}
	_check(not first.is_empty() and absf(first.distance - nearest) < 0.1 and first.direction.normalized().dot(nearest_center.normalized()) > 0.99,
		"il primo deposito indicato e il piu vicino (%.0f m)" % nearest)
	# Vena esaurita (tutti i rottami estratti), sparisce dagli indicatori anche se il cumulo resta.
	var heap := _at(nearest_center)
	var scrap_field: ScrapField = _scene.get_node(^"ScrapField")
	_check(scrap_field.vein_scrap_left(heap) >= 6, "il deposito ha una vena (%d rottami)" % scrap_field.vein_scrap_left(heap))
	# Casse e relitti sepolti nel cumulo si aprirebbero e il loro menu fermerebbe il gioco.
	run.discard_buried_in_rect(Rect2(heap.x - nearest_radius, heap.z - nearest_radius, nearest_radius * 2.0, nearest_radius * 2.0))
	_field.sculpt(heap, nearest_radius, -2.0)
	scrap_field.extract_from_veins(heap, nearest_radius, 100.0)
	_check(scrap_field.vein_scrap_left(heap) == 0, "vena esaurita")
	await _frames(70)
	var still := false
	for m: Dictionary in run.current_markers():
		still = still or (m.text == "ROTTAMI" and absf(m.distance - nearest) < 0.1)
	_check(not still, "un deposito esaurito non e piu indicato")
func _test_window_follows_player() -> void:
	print("window")
	var recenters := _path.recenter_count
	_player.global_position = Vector3(70.0, 0.88, 60.0)
	_player.velocity = Vector3.ZERO
	await _frames(3)
	_check(_path.recenter_count > recenters, "finestra ricentrata dopo il salto a 70,60")
	var cell := _path.cell_of(_player.global_position)
	_check(_path.is_inside(cell), "il giocatore e dentro la finestra")
	_check(_path.cost_at(_player.global_position) == 0.0, "costo zero sulla cella del giocatore")
	# Dopo il ricentro una pennellata sporca il campo: il costo si rilegge senza griglia (bot sulle vene).
	_field.sculpt(Vector3(74.0, 0.0, 64.0), 2.4, 1.0)
	_check(_path.cost_at(Vector3(74.0, 0.0, 64.0)) >= 0.0, "costo leggibile dopo una pennellata nella finestra ricentrata")
	_player.global_position = Vector3(0.0, 0.88, 0.0)
	await _frames(3)
