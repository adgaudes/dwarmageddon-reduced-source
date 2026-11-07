extends SceneTree
## Relitti sepolti (spec D-093, Sezione 5): posa sotto cumuli e vagoni ma non dove c'e una
## cassa, luccichio arancione da vicino, telaio sempre a vista che segue il suolo, apertura
## allo scavo, scelta fra due moduli in coda dopo le casse, rottami a carovana piena, treno che
## li porta via. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/machine_wrecks_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")
const RailwayScene := preload("res://scenes/main/railway_run.tscn")
const WRECK_GLINT := Color(1.0, 0.45, 0.1)

var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	# Seme del gate se manca (il -Seed del gate vince): la posa dei relitti si ripete.
	if not OS.get_environment("PROTOTYPE01_SEED").is_valid_int():
		OS.set_environment("PROTOTYPE01_SEED", "20261014")
	_test_pick_points_exclude()
	_test_wreck_cards()
	await _test_frame_and_glint()
	await _test_opening_by_digging()
	await _test_run_wrecks()
	await _test_train_takes_wreck()
	# I nodi in coda con queue_free vanno liberati prima di uscire (T-12).
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


func _make_field() -> TerrainField:
	var field := TerrainField.new()
	field.render = false
	field.size_m = Vector2(40.0, 40.0)
	root.add_child(field)
	return field


func _make_buried(buried: BuriedCaches, field: TerrainField, player: Node3D) -> BuriedCaches:
	buried.terrain_field = field
	buried.player = player
	root.add_child(buried)
	return buried


func _dispose(nodes: Array[Node]) -> void:
	for node in nodes:
		root.remove_child(node)
		node.queue_free()
	await _frames(2)


func _place(body: Node3D, field: TerrainField, at: Vector3, lift: float) -> void:
	body.global_position = Vector3(at.x, field.height_at(at) + lift, at.z)
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	body.reset_physics_interpolation()


## Indice della pennellata coi rottami da cui viene [param p] (a meta raggio dal centro), -1 se nessuna.
func _source_stroke(strokes: Array, p: Vector3) -> int:
	for i in strokes.size():
		var stroke: Dictionary = strokes[i]
		var d := Vector2(p.x, p.z).distance_to(stroke.center)
		if int(stroke.get(&"scrap", 0)) > 0 and absf(d - float(stroke.radius) * 0.5) < 0.01:
			return i
	return -1


## Ogni relitto della run a meta raggio di una pennellata coi rottami ancora alta, sopra la
## base + 0,1, una pennellata diversa per relitto e nessuna cassa dentro.
func _wrecks_apart(run: ArenaRun) -> bool:
	var strokes := run.district.terrain_strokes
	var sources := {}
	var placed := true
	for i in run.wrecks.count():
		var p := run.wrecks.position_of(i)
		var source := _source_stroke(strokes, p)
		placed = placed and source >= 0 and run.terrain_field.height_at(p) > p.y + BuriedCaches.OPEN_MARGIN
		if source < 0:
			continue
		sources[source] = true
		var center: Vector2 = strokes[source].center
		for j in run.caches.count():
			var cache := run.caches.position_of(j)
			placed = placed and Vector2(cache.x, cache.z).distance_to(center) > float(strokes[source].radius)
	return placed and sources.size() == run.wrecks.count()


# --- Senza scena -------------------------------------------------------------------------

func _test_pick_points_exclude() -> void:
	print("pick points exclude")
	var strokes: Array[Dictionary] = [
		{kind = &"deposit", center = Vector2(5.0, 5.0), radius = 4.0, scrap = 6},
		{kind = &"ring", center = Vector2(0.0, -6.0), radius = 5.0, scrap = 0},
		{kind = &"wagon", center = Vector2(-8.0, 0.0), radius = 3.0, scrap = 8},
		{kind = &"deposit", center = Vector2(-2.0, 9.0), radius = 3.0, scrap = 5},
	]
	var a := RandomNumberGenerator.new()
	a.seed = 7
	var b := RandomNumberGenerator.new()
	b.seed = 7
	_check(BuriedCaches.pick_points(strokes, a, 4) == BuriedCaches.pick_points(strokes, b, 4, [] as Array[Vector3]),
		"senza punti esclusi gli stessi punti di prima")
	var c := RandomNumberGenerator.new()
	c.seed = 7
	var excluded: Array[Vector3] = [Vector3(6.0, 0.0, 5.5)]
	var points := BuriedCaches.pick_points(strokes, c, 4, excluded)
	var outside := points.size() == 2
	for p in points:
		outside = outside and Vector2(p.x, p.z).distance_to(Vector2(5.0, 5.0)) > 4.0
	_check(outside, "la pennellata con un punto escluso si salta: %s" % [points])


func _test_wreck_cards() -> void:
	print("wreck cards")
	var available: Array[StringName] = [&"turret", &"magnet", &"beacon", &"drill"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var cards := MachineOffers.wreck_cards(available, &"engineer", rng)
	var modules := {}
	var shaped := cards.size() == 2
	for card in cards:
		var module: StringName = card.module_id
		modules[module] = true
		shaped = shaped and available.has(module) and card.id == MachineOffers.card(module, &"engineer").id
	_check(shaped and modules.size() == 2, "due carte Nuova macchina di moduli diversi: %s" % [modules.keys()])
	_check(MachineOffers.wreck_cards(available, &"engineer", rng, 3).size() == 3, "chiedendone tre, tre")
	var one: Array[StringName] = [&"turret"]
	_check(MachineOffers.wreck_cards(one, &"engineer", rng).size() == 1, "con un solo modulo, una carta")
	_check(MachineOffers.wreck_cards([] as Array[StringName], &"engineer", rng).is_empty(), "senza moduli, nessuna carta")


# --- Campo da solo ---------------------------------------------------------------------

func _test_frame_and_glint() -> void:
	print("frame and glint")
	var field := _make_field()
	var player := Node3D.new()
	root.add_child(player)
	var wrecks := _make_buried(MachineWrecks.new(), field, player) as MachineWrecks
	var caches := _make_buried(BuriedCaches.new(), field, player)
	# Il campo prepara le quote nel suo _ready: nel primo test l'albero non e ancora partito.
	await process_frame
	var at := Vector3(4.0, 0.0, 4.0)
	var crate_at := Vector3(-8.0, 0.0, -8.0)
	field.sculpt(at, 3.0, 1.2)
	field.sculpt(crate_at, 3.0, 1.2)
	var points: Array[Vector3] = [at]
	wrecks.place(points)
	var crate_points: Array[Vector3] = [crate_at]
	caches.place(crate_points)
	_check(wrecks.glint_color == WRECK_GLINT and wrecks.marker_name == "WRECK"
		and wrecks._glint_material.albedo_color.is_equal_approx(WRECK_GLINT), "relitto: luccichio arancione, marker WRECK")
	_check(caches.glint_color == BuriedCaches.GLINT_COLOR and caches.marker_name == "CACHE"
		and caches._glint_material.albedo_color.is_equal_approx(BuriedCaches.GLINT_COLOR) and caches.count() == 1 and caches.frame_of(0) == null,
		"cassa: luccichio dorato, marker CACHE, nessun telaio")
	player.global_position = at + Vector3(2.0, 0.0, 0.0)
	await process_frame
	await process_frame
	_check(wrecks.glint_visible(0), "luccichio visibile col giocatore a 2 m")
	player.global_position = at + Vector3(0.0, 0.0, 5.0)
	await process_frame
	await process_frame
	_check(not wrecks.glint_visible(0), "luccichio nascosto col giocatore a 5 m")
	player.global_position = at + Vector3(10.0, 0.0, 0.0)
	await process_frame
	await process_frame
	var frame := wrecks.frame_of(0)
	_check(not wrecks.glint_visible(0) and frame != null and frame.is_visible_in_tree(), "a 10 m il telaio resta a vista")
	var before := frame.global_position.y if frame != null else 0.0
	_check(frame != null and absf(before - field.height_at(at)) < 0.01, "il telaio poggia sul suolo del cumulo (%.2f)" % before)
	var volume := field.sculpt(at, 1.5, -0.3)
	field.player_sculpted.emit(at, 1.5, volume, TerrainField.ToolMode.DIG)
	var after := frame.global_position.y if frame != null else 0.0
	_check(wrecks.closed_count() == 1 and absf(after - field.height_at(at)) < 0.01 and after <= before - 0.2,
		"scavando sopra il telaio scende col suolo (%.2f -> %.2f)" % [before, after])
	# Il treno spazza il vagone: relitto e telaio persi, non si apre quando il suolo torna alla base.
	var opened := [0]
	wrecks.cache_opened.connect(func(_at: Vector3) -> void: opened[0] += 1)
	_check(wrecks.discard_in_rect(Rect2(at.x - 1.0, at.z - 1.0, 2.0, 2.0)) == 1, "spazzato dal treno")
	field.reset_to_base(at, Vector2(4.0, 4.0))
	await process_frame
	_check(opened[0] == 0 and wrecks.closed_count() == 0, "perso senza aprirsi")
	_check(wrecks.frame_of(0) == null and not is_instance_valid(frame), "il telaio se ne va col relitto")
	await _dispose([wrecks, caches, player, field] as Array[Node])


func _test_opening_by_digging() -> void:
	print("opening by digging")
	var field := _make_field()
	var player := Node3D.new()
	root.add_child(player)
	var wrecks := _make_buried(MachineWrecks.new(), field, player) as MachineWrecks
	player.global_position = Vector3(15.0, 0.0, 15.0)
	var dug := Vector3(2.0, 0.0, -2.0)
	var other := Vector3(-8.0, 0.0, 6.0)
	field.sculpt(dug, 3.0, 1.2)
	field.sculpt(other, 3.0, 1.2)
	var points: Array[Vector3] = [dug, other]
	wrecks.place(points)
	await _frames(1)
	_check(wrecks.count() == 2 and wrecks.closed_count() == 2 and wrecks.frame_of(0) != null and wrecks.frame_of(1) != null,
		"due relitti posati, chiusi, coi telai")
	var opened: Array[Vector3] = []
	wrecks.cache_opened.connect(func(at: Vector3) -> void: opened.append(at))
	# Scavo a passi di 0,2 m: chiuso finche il centro resta sopra la base + 0,1.
	var closed_while_above := true
	var steps := 0
	while field.height_at(dug) > field.base_height_at(dug) + 0.1 and steps < 20:
		var volume := field.sculpt(dug, 1.5, -0.2)
		field.player_sculpted.emit(dug, 1.5, volume, TerrainField.ToolMode.DIG)
		steps += 1
		if field.height_at(dug) > field.base_height_at(dug) + 0.1 and not opened.is_empty():
			closed_while_above = false
	_check(closed_while_above and steps > 2, "nessuna apertura finche il suolo e sopra la base + 0,1 (%d passi)" % steps)
	_check(opened.size() == 1 and opened[0].distance_to(Vector3(dug.x, field.base_height_at(dug), dug.z)) < 0.01,
		"scavando fino alla base il relitto esce: %s" % [opened])
	_check(wrecks.frame_of(0) == null and wrecks.frame_of(1) != null, "il telaio del relitto aperto se ne va subito")
	for i in 3:
		var volume := field.sculpt(dug, 1.5, -0.2)
		field.player_sculpted.emit(dug, 1.5, volume, TerrainField.ToolMode.DIG)
	_check(opened.size() == 1 and wrecks.closed_count() == 1, "scavando ancora non si riapre")
	# Altri scavatori (Demolitore, armi): basta il cambio di regione.
	field.sculpt(other, 3.0, -1.5)
	_check(opened.size() == 2 and wrecks.closed_count() == 0 and wrecks.frame_of(1) == null, "si apre anche scavato da altri (region_changed)")
	await create_timer(0.8).timeout
	_check(wrecks.get_child_count() == 0, "luccichii, telai e relitti saliti spariti (%d nodi)" % wrecks.get_child_count())
	await _dispose([wrecks, player, field] as Array[Node])


# --- In una run --------------------------------------------------------------------------

func _test_run_wrecks() -> void:
	print("run")
	var scene: Node3D = RunScene.instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	var run: ArenaRun = scene.get_node(^"Run")
	var menu: LevelUpMenu = scene.get_node(^"LevelUpMenu")
	await _frames(3)
	var caravan := run.caravan
	var tuning := caravan.tuning
	var wrecks := run.wrecks
	_check(tuning.wrecks_per_level == 2 and wrecks != null and wrecks.count() == 2,
		"due relitti posati: %d" % (wrecks.count() if wrecks != null else -1))
	if wrecks == null:
		root.remove_child(scene)
		scene.queue_free()
		await _frames(2)
		return
	_check(_wrecks_apart(run), "sotto due cumuli diversi, sopra la base + 0,1, mai dove c'e una cassa")

	# Menu del relitto: due moduli diversi; la scelta aggiunge la macchina e non tocca i level-up.
	run._pending_level_ups = 0
	var machines := caravan.machines.size()
	var levels := run.progression.levels.duplicate()
	_check(caravan.has_room(), "la carovana ha posto")
	run._on_wreck_opened(Vector3.ZERO)
	await _frames(2)
	_check(menu.is_open and paused and menu.title_text() == "RELITTO SEPOLTO", "il relitto apre la scelta e ferma il gioco")
	var available := run._available_modules()
	var names := {}
	for module in available:
		names[MachineOffers.card(module, run.class_id).name] = true
	var shown := {}
	for i in menu.card_count():
		shown[menu.card_text(i).split("\n")[1]] = true
	_check(tuning.wreck_choices == 2 and menu.card_count() == tuning.wreck_choices and shown.size() == 2
		and shown.keys().all(func(card_name: String) -> bool: return names.has(card_name)),
		"due carte Nuova macchina di moduli diversi: %s" % [shown.keys()])
	await create_timer(0.6, true).timeout
	menu.press(0)
	await _frames(3)
	_check(caravan.machines.size() == machines + 1, "scelta: una macchina in piu")
	_check(run._pending_wrecks == 0 and run._pending_level_ups == 0 and run.progression.levels == levels and not run._wreck_menu,
		"consuma il relitto, non un level-up, e non scrive i livelli")
	_check(not menu.is_open and not paused, "il gioco riparte")
	var added := caravan.machines.back() as Machine
	var added_module := added.primary_module_id()
	_check(available.has(added_module) and run.write_queue.bodies.has(added) and added.module(added_module).level == caravan.module_level(added_module),
		"la macchina nuova (%s) ha i servizi della run e il livello del tipo" % added_module)

	# Cassa, relitto e level-up nello stesso passo: tre menu in quest'ordine, poi si riparte.
	# Lama da cantiere sbloccata in Officina: c'e una carta "nuova arma" (il profilo dei test non si salva).
	var profile := root.get_node("PlayerProfile") as PlayerProfileService
	profile.levels = {&"unlock_site_blade": 1}
	run._pending_level_ups = 1
	run._on_cache_opened(Vector3.ZERO)
	run._on_wreck_opened(Vector3.ZERO)
	await _frames(2)
	var titles: PackedStringArray = []
	var always_paused := true
	var queue_at_wreck := false
	for i in 10:
		if not menu.is_open:
			break
		always_paused = always_paused and paused
		var title := menu.title_text()
		# I bivi di un'arma aprono le due trasformazioni col nome dell'arma: non contano.
		if title == "CASSA SEPOLTA" or title == "RELITTO SEPOLTO":
			titles.append(title)
		elif title.begins_with("LIVELLO"):
			titles.append("LIVELLO")
		if title == "RELITTO SEPOLTO":
			queue_at_wreck = run._pending_level_ups == 1 and run._pending_caches == 0
		await create_timer(0.6, true).timeout
		menu.press(0)
		await _frames(3)
	_check(",".join(titles) == "CASSA SEPOLTA,RELITTO SEPOLTO,LIVELLO" and queue_at_wreck,
		"prima la cassa, poi il relitto, poi il level-up: %s" % ",".join(titles))
	_check(always_paused and not menu.is_open and not paused and run._pending_caches == 0 and run._pending_wrecks == 0 and run._pending_level_ups == 0,
		"fermo fino all'ultima scelta, poi il gioco riparte")

	# Carovana piena: nessun menu, i rottami nei Cassoni e quelli che non ci stanno a terra.
	while caravan.has_room() and caravan.add_machine(&"turret") != null:
		pass
	caravan.carried = caravan.capacity - 1
	machines = caravan.machines.size()
	var on_ground := run._scrap_field().count()
	run._on_wreck_opened(Vector3.ZERO)
	await _frames(3)
	_check(not caravan.has_room() and not menu.is_open and not paused and caravan.machines.size() == machines
		and run._pending_level_ups == 0 and run._pending_wrecks == 0, "carovana piena: nessun menu, nessuna macchina")
	_check(tuning.wreck_full_scrap == 3 and caravan.carried == caravan.capacity and run._scrap_field().count() == on_ground + tuning.wreck_full_scrap - 1,
		"un rottame a bordo, gli altri a terra (%d/%d, %d a terra)" % [caravan.carried, caravan.capacity, run._scrap_field().count() - on_ground])
	_check(run.hud.event_warning_text() == "RELITTO: +%d ROTTAMI" % tuning.wreck_full_scrap, "avviso nel HUD: %s" % run.hud.event_warning_text())
	profile.reset()
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	await _frames(2)


## Ferrovia: posa lontana dalle casse anche qui; il treno spiana i vagoni e porta via casse e
## relitti senza aprirli, anche quelli appena fuori dal tratto spianato in un passo.
func _test_train_takes_wreck() -> void:
	print("train")
	var scene: Node3D = RailwayScene.instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	var run: ArenaRun = scene.get_node(^"Run")
	var train: TrainEvent = scene.get_node(^"TrainEvent")
	var field: TerrainField = scene.get_node(^"TerrainField")
	var menu: LevelUpMenu = scene.get_node(^"LevelUpMenu")
	var caravan: Caravan = scene.get_node(^"Caravan")
	await _frames(5)
	var wrecks := run.wrecks
	_check(wrecks != null and train.machine_wrecks == wrecks, "il treno conosce i relitti")
	var high: Array[Dictionary] = []
	for stroke: Dictionary in run.district.terrain_strokes:
		var center := Vector3(stroke.center.x, 0.0, stroke.center.y)
		if stroke.kind == &"wagon" and field.height_at(center) > field.base_height_at(center) + 0.3:
			high.append(stroke)
	_check(high.size() >= 2, "almeno due vagoni ancora in piedi (%d)" % high.size())
	if wrecks == null or high.size() < 2:
		root.remove_child(scene)
		scene.queue_free()
		await _frames(2)
		return
	_check(wrecks.count() == 2 and _wrecks_apart(run), "ferrovia: due relitti sotto cumuli o vagoni diversi, mai dove c'e una cassa")
	var opened := [0]
	wrecks.cache_opened.connect(func(_at: Vector3) -> void: opened[0] += 1)
	var caches_opened := [0]
	run.caches.cache_opened.connect(func(_at: Vector3) -> void: caches_opened[0] += 1)

	# Un passo guidato a mano sul secondo vagone: reset_to_base arrotonda alla griglia di 0,5 m e
	# porta alla base anche i punti 0,2 m prima del rettangolo del passo; la cassa e il relitto
	# posati li si scartano, non si aprono.
	var edge: Dictionary = high[1]
	var vertex := floorf((edge.center.x + field._half.x) / TerrainField.SPACING) * TerrainField.SPACING - field._half.x
	var cache_index := run.caches.count()
	var edge_cache: Array[Vector3] = [Vector3(vertex + 0.1, 0.0, edge.center.y - 0.5)]
	run.caches.place(edge_cache)
	var edge_index := wrecks.count()
	var edge_wreck: Array[Vector3] = [Vector3(vertex + 0.1, 0.0, edge.center.y + 0.5)]
	wrecks.place(edge_wreck)
	_check(run.caches.count() == cache_index + 1 and wrecks.count() == edge_index + 1, "cassa e relitto sotto il secondo vagone")
	if run.caches.count() == cache_index + 1 and wrecks.count() == edge_index + 1:
		train._swept_x = vertex + 1.0
		train._head_x = vertex + 0.9
		train._sweep_band()
		await _frames(2)
		var cache_at := run.caches.position_of(cache_index)
		var wreck_at := wrecks.position_of(edge_index)
		_check(field.height_at(cache_at) <= cache_at.y + BuriedCaches.OPEN_MARGIN and field.height_at(wreck_at) <= wreck_at.y + BuriedCaches.OPEN_MARGIN,
			"il passo porta alla base anche i punti appena fuori dal suo rettangolo")
		_check(caches_opened[0] == 0 and opened[0] == 0 and run._pending_caches == 0 and run._pending_wrecks == 0 and not paused and not menu.is_open,
			"cassa e relitto sul bordo del passo scartati, non aperti")

	# Il passaggio vero sul primo vagone, col relitto sotto.
	var wagon: Dictionary = high[0]
	var index := wrecks.count()
	var points: Array[Vector3] = [Vector3(wagon.center.x, 0.0, wagon.center.y)]
	wrecks.place(points)
	var frame: Node3D = null
	if wrecks.count() > index:
		frame = wrecks.frame_of(index)
	_check(frame != null, "relitto sotto il vagone, col telaio")
	_place(run.player, field, Vector3(0.0, 0.0, 20.0), 0.88)
	_place(caravan.lead(), field, Vector3(0.0, 0.0, 22.0), 0.3)
	train.warning_seconds = 1.0
	train.speed = 80.0
	train.next_at = run.elapsed + 1.05
	for i in 700:
		await physics_frame
		if train.passes >= 1:
			break
	_check(train.passes >= 1, "il treno e passato")
	_check(opened[0] == 0 and caches_opened[0] == 0 and not paused and not menu.is_open and run._pending_wrecks == 0 and run._pending_caches == 0,
		"nessuna cassa o relitto aperto, nessun menu")
	_check(wrecks.frame_of(index) == null and not is_instance_valid(frame), "il telaio se ne va col vagone")
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	await _frames(2)
