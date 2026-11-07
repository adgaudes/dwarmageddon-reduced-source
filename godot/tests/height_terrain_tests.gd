extends SceneTree
## Test dello spike del terreno a rilievo continuo (HeightTerrain, HeightFlowField,
## TerrainSpike). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/height_terrain_tests.gd
## Invarianti: il pennello alza e scava a campana e rende il volume spostato; livella
## porta alla quota chiesta; la quota si legge interpolata; si sale solo sotto la
## pendenza massima e si scende sempre; il campo di percorso aggira un argine e non
## trova uscita da una fossa; salvare e ricaricare restituisce lo stesso rilievo; nella
## scena di prova il giocatore resta posato sul rilievo e la terra si conserva.

const EPSILON := 0.001
const GRADE := 0.8

var _failures := 0


func _initialize() -> void:
	_test_brush()
	_test_walking()
	_test_flow_field()
	_test_save()
	await _test_scene()
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _terrain(size := 48.0) -> HeightTerrain:
	var terrain := HeightTerrain.new()
	terrain.size_m = size
	terrain.build()
	return terrain


func _test_brush() -> void:
	print("Pennello")
	var terrain := _terrain()
	_check(terrain.resolution == 97 and is_zero_approx(terrain.height_at(Vector3(3.3, 0.0, -7.1))), "nasce piatto, 97 vertici per lato")
	var center := Vector3(4.0, 0.0, -6.0)
	var volume := terrain.sculpt(center, 3.0, 1.2)
	_check(absf(terrain.height_at(center) - 1.2) < EPSILON, "alza di quanto chiesto al centro (%.3f m)" % terrain.height_at(center))
	_check(is_zero_approx(terrain.height_at(center + Vector3(3.0, 0.0, 0.0))) and is_zero_approx(terrain.height_at(center + Vector3(0.0, 0.0, -3.5))),
		"a zero sul bordo e fuori dal pennello")
	var half_way := terrain.height_at(center + Vector3(1.5, 0.0, 0.0))
	_check(half_way > 0.5 and half_way < 0.9, "a campana: a meta raggio %.2f m" % half_way)
	# L'integrale della campana (1 - d2)^2 sul disco e pi R^2 / 3.
	var expected := 1.2 * PI * 9.0 / 3.0
	_check(absf(volume - expected) / expected < 0.03, "rende il volume alzato (%.2f m3, attesi %.2f)" % [volume, expected])
	var dug := terrain.sculpt(center, 3.0, -1.2)
	_check(absf(dug + volume) < 0.01 and absf(terrain.height_at(center)) < EPSILON, "scavare lo stesso tanto riporta a zero e rende il volume opposto")
	terrain.sculpt(center, 3.0, 50.0)
	_check(is_equal_approx(terrain.height_at(center), HeightTerrain.MAX_HEIGHT), "non supera la quota massima")
	terrain.sculpt(center, 3.0, -50.0)
	_check(is_equal_approx(terrain.height_at(center), HeightTerrain.MIN_HEIGHT), "ne scende sotto la minima")
	var flat := _terrain()
	flat.sculpt(Vector3.ZERO, 4.0, 2.0)
	for i in 40:
		flat.level(Vector3.ZERO, 4.0, 0.8, 0.3)
	_check(absf(flat.height_at(Vector3.ZERO) - 0.8) < 0.01 and absf(flat.height_at(Vector3(1.0, 0.0, 1.0)) - 0.8) < 0.05,
		"livella porta la zona alla quota chiesta (%.2f m)" % flat.height_at(Vector3.ZERO))
	var edge := _terrain()
	edge.sculpt(Vector3(24.0, 0.0, 24.0), 3.0, 1.0)
	_check(edge.height_at(Vector3(24.0, 0.0, 24.0)) > 0.9, "il pennello lavora anche sul bordo senza uscire dalla maglia")
	terrain.free()
	flat.free()
	edge.free()


func _test_walking() -> void:
	print("Camminare")
	var terrain := _terrain()
	terrain.sculpt(Vector3(6.0, 0.0, 0.0), 3.0, 0.6)
	terrain.sculpt(Vector3(-6.0, 0.0, 0.0), 2.0, 3.0)
	var normal := terrain.normal_at(Vector3(4.5, 0.0, 0.0))
	_check(normal.y > 0.8 and normal.x < -0.1, "la normale sul fianco guarda in fuori (%.2f, %.2f)" % [normal.x, normal.y])
	# Cumulo basso: si attraversa. Passi da 5 cm come a 120 Hz.
	var point := Vector3(1.0, 0.0, 0.0)
	var top := 0.0
	for i in 200:
		point = terrain.slide_move(point, point + Vector3(0.05, 0.0, 0.0), GRADE)
		top = maxf(top, point.y)
	_check(point.x > 10.0 and top > 0.55, "un cumulo basso si scavalca (arrivato a x=%.1f, quota massima %.2f)" % [point.x, top])
	# Cumulo alto e stretto: e un muro.
	point = Vector3(-1.0, 0.0, 0.0)
	for i in 200:
		point = terrain.slide_move(point, point + Vector3(-0.05, 0.0, 0.0), GRADE)
	_check(point.x > -6.0 and point.y < 1.5, "un cumulo alto e stretto ferma (fermo a x=%.2f, quota %.2f)" % [point.x, point.y])
	# Di sbieco contro il muro si scorre lungo il fianco.
	var start := point
	for i in 100:
		point = terrain.slide_move(point, point + Vector3(-0.035, 0.0, 0.035), GRADE)
	_check(point.z > start.z + 1.0, "di sbieco contro il muro si scorre (z da %.2f a %.2f)" % [start.z, point.z])
	# In discesa si passa sempre, anche se ripida.
	var summit := Vector3(-6.0, 0.0, 0.0)
	_check(terrain.can_step(summit, summit + Vector3(0.6, 0.0, 0.0), GRADE) and not terrain.can_step(summit + Vector3(0.6, 0.0, 0.0), summit, GRADE),
		"dalla cima si scende, dal fianco non si risale")
	var corner := terrain.slide_move(Vector3(23.0, 0.0, 23.0), Vector3(40.0, 0.0, 40.0), GRADE)
	_check(corner.x < terrain.half_extent() and corner.z < terrain.half_extent(), "non si esce dai bordi")
	terrain.free()


func _test_flow_field() -> void:
	print("Campo di percorso")
	var terrain := _terrain()
	var field := HeightFlowField.new()
	var goal := Vector3(0.0, 0.0, -12.0)
	var start := Vector3(0.0, 0.0, 12.0)
	field.rebuild(terrain, goal, GRADE)
	var straight := field.distance[field.cell_of(start)]
	_check(straight > 0.0 and absf(straight - 24.0) < 3.0, "in piano va dritto (%.1f m)" % straight)
	_check(field.direction_at(start).z < -0.9, "e la direzione punta al bersaglio")
	# Finestra (U-02): a 6 m dal bersaglio il campo si ferma; vicino e uguale al campo intero.
	var near := Vector3(0.0, 0.0, -9.0)
	var near_full := field.distance[field.cell_of(near)]
	field.rebuild(terrain, goal, GRADE, 6.0)
	_check(field.distance[field.cell_of(start)] < 0.0 and field.direction_at(start) == Vector3.ZERO,
		"con una finestra di 6 m la casella a 24 m resta senza strada")
	_check(is_equal_approx(field.distance[field.cell_of(near)], near_full) and field.direction_at(near).z < -0.9,
		"dentro la finestra il campo e lo stesso (%.1f m)" % near_full)
	_check(field.cells_apart(field.cell_of(start), field.cell_of(goal)) == 16 and field.cells_apart(field.cell_of(start), -1) > 1000,
		"distanza in caselle: 16 fra partenza e bersaglio, infinita senza bersaglio")
	field.rebuild(terrain, goal, GRADE)
	# Argine alto fra i due, lungo 20 m.
	for i in 21:
		terrain.sculpt(Vector3(-10.0 + i, 0.0, 0.0), 2.0, 3.0)
	field.rebuild(terrain, goal, GRADE)
	var around := field.distance[field.cell_of(start)]
	_check(around > straight + 4.0, "un argine allunga la strada (%.1f m invece di %.1f)" % [around, straight])
	var cell := field.cell_of(start)
	var crossed := false
	var guard := 0
	while cell != field.cell_of(goal) and guard < 500:
		var following := field.next[cell]
		var here := field.center_of(cell)
		var there := field.center_of(following)
		here.y = terrain.height_at(here)
		there.y = terrain.height_at(there)
		crossed = crossed or there.y > 1.5
		cell = following
		guard += 1
	_check(cell == field.cell_of(goal) and not crossed, "seguendo il campo si arriva senza salire sull'argine")
	# Fossa profonda e ripida: ci si entra, non se ne esce.
	var pit := Vector3(14.0, 0.0, 14.0)
	terrain.sculpt(pit, 2.5, -4.0)
	field.rebuild(terrain, goal, GRADE)
	_check(field.distance[field.cell_of(pit)] < 0.0 and field.direction_at(pit) == Vector3.ZERO, "dal fondo di una fossa ripida non c'e strada")
	field.rebuild(terrain, pit, GRADE)
	_check(field.distance[field.cell_of(start)] > 0.0, "ma nella fossa si puo scendere")
	terrain.free()
	# Lato non multiplo di CELL (U-01): il campo tiene solo le caselle con vertice nella
	# maglia e i punti oltre l'ultima si riportano sul bordo, senza indici fuori maglia.
	var odd := _terrain(100.0)
	var odd_field := HeightFlowField.new()
	odd_field.rebuild(odd, Vector3.ZERO, GRADE)
	var expected_side := (odd.resolution - 1) / HeightFlowField.SUBSTEPS + 1
	_check(odd.resolution == 201 and odd_field.side == expected_side and odd_field.distance.size() == expected_side * expected_side,
		"lato di 100 m: %d caselle per lato su 201 vertici" % odd_field.side)
	var far_corner := Vector3(49.9, 0.0, 49.9)
	var corner_cell := odd_field.cell_of(far_corner)
	_check(corner_cell == expected_side * expected_side - 1 and odd_field.distance[corner_cell] > 60.0
		and odd_field.direction_at(far_corner).length() > 0.9,
		"l'angolo estremo cade nell'ultima casella e ha una strada (%.1f m)" % odd_field.distance[corner_cell])
	odd.free()


func _test_save() -> void:
	print("Salvataggio")
	var terrain := _terrain()
	terrain.sculpt(Vector3(3.0, 0.0, 3.0), 4.0, 1.7)
	terrain.sculpt(Vector3(-8.0, 0.0, 5.0), 3.0, -1.1)
	var path := "user://height_terrain_tests.bin"
	var size := terrain.save_heights(path)
	_check(size > 8 and size < terrain.heights.size() * 4, "il rilievo si salva compresso (%d byte per %d vertici)" % [size, terrain.heights.size()])
	var other := _terrain()
	_check(other.load_heights(path) and other.heights == terrain.heights, "ricaricato, e identico")
	var smaller := _terrain(24.0)
	_check(not smaller.load_heights(path), "un rilievo di un'altra misura viene rifiutato")
	# U-10: scrittura su .tmp e rinomina, anche sopra un file esistente.
	terrain.sculpt(Vector3(10.0, 0.0, -10.0), 2.0, 0.5)
	_check(terrain.save_heights(path) > 8 and not FileAccess.file_exists(path + ".tmp"), "si risalva sopra il file precedente senza lasciare il .tmp")
	_check(other.load_heights(path) and other.heights == terrain.heights, "e il file nuovo e quello ricaricato")
	# U-10: file vuoti, troncati o con dimensione dichiarata falsa si rifiutano
	# prima di decomprimere, lasciando il rilievo com'era.
	var before := other.heights.duplicate()
	var bytes := FileAccess.get_file_as_bytes(path)
	var bad_files := {
		"empty": PackedByteArray(),
		"short": bytes.slice(0, 10),
		"truncated": bytes.slice(0, 20),
		"wrong_magic": bytes.duplicate(),
		"lying_size": bytes.duplicate(),
	}
	bad_files["wrong_magic"].encode_u32(0, 0)
	bad_files["lying_size"].encode_u32(12, 16)
	for label: String in bad_files:
		var bad_path := "user://height_terrain_tests_%s.bin" % label
		var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
		bad_file.store_buffer(bad_files[label])
		bad_file.close()
		_check(not other.load_heights(bad_path) and other.heights == before, "file %s rifiutato, rilievo intatto" % label)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
	_check(not other.load_heights("user://height_terrain_tests_missing.bin"), "file assente rifiutato")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	terrain.free()
	other.free()
	smaller.free()


func _test_scene() -> void:
	print("Scena di prova")
	Engine.physics_ticks_per_second = 60
	var spike: TerrainSpike = preload("res://scenes/spikes/terrain_spike.tscn").instantiate()
	spike.enemies_active = false
	root.add_child(spike)
	for i in 10:
		await physics_frame
	var player := spike.player
	var ground := spike.terrain.height_at(player.global_position)
	_check(absf(player.global_position.y - ground - TerrainSpike.PLAYER_HEIGHT) < EPSILON, "il giocatore e posato sul rilievo")
	_check(spike.enemies.size() == TerrainSpike.ENEMY_COUNT and spike.field.distance[spike.field.cell_of(player.global_position)] == 0.0,
		"rottamatori schierati e campo calcolato sul giocatore")

	# Alzare consuma terra, scavare la rende, e il conto torna.
	var target := player.global_position + Vector3(0.0, 0.0, -5.0)
	var before := spike.terrain.height_at(target)
	spike.mode = TerrainSpike.Mode.RAISE
	for i in 30:
		spike.apply_brush(target, 1.0 / 60.0)
	var raised := spike.terrain.height_at(target) - before
	var spent := TerrainSpike.SOIL_START - spike.soil
	_check(raised > 0.9 and spent > 1.0, "alzare fa un cumulo (%.2f m) e consuma terra (%.1f m3)" % [raised, spent])
	spike.mode = TerrainSpike.Mode.DIG
	for i in 30:
		spike.apply_brush(target, 1.0 / 60.0)
	_check(absf(spike.terrain.height_at(target) - before) < 0.01 and absf(spike.soil - TerrainSpike.SOIL_START) < 0.05,
		"scavare lo stesso tanto rimette terreno e serbatoio com'erano")
	spike.soil = 0.0
	spike.mode = TerrainSpike.Mode.RAISE
	spike.apply_brush(target, 1.0 / 60.0)
	_check(absf(spike.terrain.height_at(target) - before) < 0.01, "a serbatoio vuoto non si alza")

	# Camminando su un cumulo basso il giocatore sale con lui.
	spike.soil = TerrainSpike.SOIL_CAPACITY
	spike.terrain.sculpt(player.global_position + Vector3(4.0, 0.0, 0.0), 3.0, 0.7)
	Input.action_press(&"move_right")
	var highest := player.global_position.y
	var floating := 0.0
	for i in 70:
		await physics_frame
		highest = maxf(highest, player.global_position.y)
		floating = maxf(floating, absf(player.global_position.y - spike.terrain.height_at(player.global_position) - TerrainSpike.PLAYER_HEIGHT))
	Input.action_release(&"move_right")
	_check(highest > TerrainSpike.PLAYER_HEIGHT + 0.5 and floating < EPSILON,
		"camminando sale sul cumulo senza staccarsi dal suolo (quota massima %.2f)" % highest)

	# I rottamatori si avvicinano e restano posati.
	spike.enemies_active = true
	var enemy := spike.enemies[0]
	var distance := enemy.global_position.distance_to(player.global_position)
	for i in 120:
		await physics_frame
	var grounded := true
	for other in spike.enemies:
		grounded = grounded and absf(other.global_position.y - spike.terrain.height_at(other.global_position)) < EPSILON
	_check(enemy.global_position.distance_to(player.global_position) < distance - 2.0 and grounded,
		"i rottamatori avanzano verso il giocatore posati sul rilievo")
	spike.queue_free()
	await process_frame
