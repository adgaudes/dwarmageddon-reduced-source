extends SceneTree
## Casse sepolte (spec D-092, par. 6.3): posa sotto cumuli e vagoni, luccichio da vicino,
## uscita allo scavo, scelta fra tre carte arma in coda ai level-up. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/buried_caches_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")

var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _test_opening_by_digging()
	await _test_glint_range()
	_test_pick_points()
	_test_roll_weapon_offer()
	await _test_run_caches()
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


func _make_caches(field: TerrainField, player: Node3D) -> BuriedCaches:
	var caches := BuriedCaches.new()
	caches.terrain_field = field
	caches.player = player
	root.add_child(caches)
	return caches


func _dispose(nodes: Array[Node]) -> void:
	for node in nodes:
		root.remove_child(node)
		node.queue_free()
	await _frames(2)


# --- Campo da solo ---------------------------------------------------------------------

func _test_opening_by_digging() -> void:
	print("opening by digging")
	var field := _make_field()
	var player := Node3D.new()
	root.add_child(player)
	var caches := _make_caches(field, player)
	# Il campo prepara le quote nel suo _ready: nel primo test l'albero non e ancora partito.
	await process_frame
	player.global_position = Vector3(15.0, 0.0, 15.0)
	var dug := Vector3(2.0, 0.0, -2.0)
	var other := Vector3(-8.0, 0.0, 6.0)
	field.sculpt(dug, 3.0, 1.2)
	field.sculpt(other, 3.0, 1.2)
	var points: Array[Vector3] = [dug, other]
	caches.place(points)
	await _frames(1)
	_check(caches.count() == 2 and caches.closed_count() == 2, "due casse posate, chiuse")
	var opened: Array[Vector3] = []
	caches.cache_opened.connect(func(at: Vector3) -> void: opened.append(at))
	# Scavo a passi di 0,2 m: chiusa finche il centro resta sopra la base + 0,1.
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
		"scavando fino alla base la cassa esce: %s" % [opened])
	for i in 3:
		var volume := field.sculpt(dug, 1.5, -0.2)
		field.player_sculpted.emit(dug, 1.5, volume, TerrainField.ToolMode.DIG)
	_check(opened.size() == 1 and caches.closed_count() == 1, "scavando ancora non si riapre")
	# Altri scavatori (Demolitore, armi): basta il cambio di regione.
	field.sculpt(other, 3.0, -1.5)
	_check(opened.size() == 2 and caches.closed_count() == 0, "si apre anche scavata da altri (region_changed)")
	await create_timer(0.8).timeout
	_check(caches.get_child_count() == 0, "luccichii e casse salite spariti (%d nodi)" % caches.get_child_count())
	await _dispose([caches, player, field] as Array[Node])


func _test_glint_range() -> void:
	print("glint")
	var field := _make_field()
	var player := Node3D.new()
	root.add_child(player)
	var caches := _make_caches(field, player)
	var at := Vector3(4.0, 0.0, 4.0)
	field.sculpt(at, 3.0, 1.2)
	var points: Array[Vector3] = [at]
	caches.place(points)
	player.global_position = at + Vector3(2.0, 0.0, 0.0)
	await process_frame
	await process_frame
	_check(caches.glint_visible(0), "luccichio visibile col giocatore a 2 m")
	player.global_position = at + Vector3(0.0, 0.0, 5.0)
	await process_frame
	await process_frame
	_check(not caches.glint_visible(0), "luccichio nascosto col giocatore a 5 m")
	# Il treno spazza il vagone: la cassa e persa, non si apre quando il suolo torna alla base.
	var opened := [0]
	caches.cache_opened.connect(func(_at: Vector3) -> void: opened[0] += 1)
	_check(caches.discard_in_rect(Rect2(at.x - 1.0, at.z - 1.0, 2.0, 2.0)) == 1, "spazzata dal treno")
	field.reset_to_base(at, Vector2(4.0, 4.0))
	_check(opened[0] == 0 and caches.closed_count() == 0, "persa senza aprirsi")
	await _dispose([caches, player, field] as Array[Node])


func _test_pick_points() -> void:
	print("pick points")
	var strokes: Array[Dictionary] = [
		{kind = &"deposit", center = Vector2(5.0, 5.0), radius = 4.0, scrap = 6},
		{kind = &"ring", center = Vector2(0.0, -6.0), radius = 5.0, scrap = 0},
		{kind = &"wagon", center = Vector2(-8.0, 0.0), radius = 3.0, scrap = 8},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var points := BuriedCaches.pick_points(strokes, rng, 4)
	_check(points.size() == 2, "fra tre pennellate (due coi rottami) al massimo due punti: %d" % points.size())
	var inside := true
	var used := {}
	for p in points:
		var best := -1
		for i in strokes.size():
			var stroke := strokes[i]
			var d := Vector2(p.x, p.z).distance_to(stroke.center)
			if int(stroke.scrap) > 0 and d <= float(stroke.radius) and absf(d - float(stroke.radius) * 0.5) < 0.01:
				best = i
		inside = inside and best >= 0 and not used.has(best)
		used[best] = true
	_check(inside, "ogni punto a meta raggio di una pennellata diversa coi rottami: %s" % [points])
	_check(BuriedCaches.pick_points(strokes, rng, 1).size() == 1, "chiedendone uno, uno")


func _test_roll_weapon_offer() -> void:
	print("roll weapon offer")
	var progression := RunProgression.new()
	progression.setup(11)
	var cards: Array[Dictionary] = []
	for i in 5:
		cards.append({id = StringName("w:new:test_%d" % i), rarity = i % 3, category = &"weapon"})
	var offer := progression.roll_weapon_offer(cards)
	var ids := {}
	for card in offer:
		ids[card.id] = true
	_check(offer.size() == 3 and ids.size() == 3, "tre carte distinte")
	cards.append({id = &"w:fusion:test", rarity = UpgradeCatalog.Rarity.LEGENDARY, category = &"weapon"})
	var first_is_fusion := true
	for i in 10:
		first_is_fusion = first_is_fusion and progression.roll_weapon_offer(cards)[0].id == &"w:fusion:test"
	_check(first_is_fusion, "la fusione, se c'e, sempre per prima")
	_check(progression.roll_weapon_offer(cards.slice(0, 2)).size() == 2, "con due carte possibili, due")
	_check(progression.roll_weapon_offer([] as Array[Dictionary]).is_empty(), "senza carte possibili, nessuna")


# --- In una run --------------------------------------------------------------------------

func _test_run_caches() -> void:
	print("run")
	var scene: Node3D = RunScene.instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	var run: ArenaRun = scene.get_node(^"Run")
	var menu: LevelUpMenu = scene.get_node(^"LevelUpMenu")
	await _frames(3)
	_check(run.caches != null and run.caches.count() >= 3 and run.caches.count() <= 4, "casse posate: %d" % (run.caches.count() if run.caches != null else -1))
	var buried := true
	if run.caches != null:
		for i in run.caches.count():
			var p := run.caches.position_of(i)
			buried = buried and run.terrain_field.height_at(p) > p.y + 0.1
	_check(buried, "ogni cassa e sotto un cumulo, sopra la base + 0,1")
	run._pending_level_ups = 0
	# Lama da cantiere sbloccata in Officina: c'e una carta "nuova arma" (il profilo dei test non si salva).
	var profile := root.get_node("PlayerProfile") as PlayerProfileService
	profile.levels = {&"unlock_site_blade": 1}

	# Menu della cassa: solo carte arma.
	run._on_cache_opened(Vector3.ZERO)
	await _frames(2)
	_check(menu.is_open and paused and menu.title_text() == "CASSA SEPOLTA", "la cassa apre la scelta e ferma il gioco")
	var names := {}
	for card in WeaponOffers.cards(run.loadout, run.class_id, run._unlocked_weapons()):
		names[card.name] = true
	var only_weapons := menu.card_count() == 3
	for i in menu.card_count():
		only_weapons = only_weapons and names.has(menu.card_text(i).split("\n")[1])
	_check(only_weapons, "tre carte, tutte arma")
	# Carta "nuova arma" scelta come la premerebbe il giocatore (close, poi chosen).
	var new_id := &""
	for card in WeaponOffers.cards(run.loadout, run.class_id, run._unlocked_weapons()):
		if card.kind == &"new":
			new_id = card.weapon_id
			break
	menu.close()
	menu.chosen.emit(StringName("w:new:%s" % new_id))
	await _frames(3)
	_check(new_id != &"" and run.loadout.has_weapon(new_id), "arma nuova aggiunta: %s" % new_id)
	_check(run._pending_level_ups == 0 and run._pending_caches == 0 and not menu.is_open and not paused,
		"il level-up in coda non cambia, la cassa e consumata, il gioco riparte")

	# Bivio da una cassa: la trasformazione consuma la cassa, non un level-up.
	if run.loadout.level_of(&"nailgun") < 2:
		run.loadout.level_up(&"nailgun")
	run._on_cache_opened(Vector3.ZERO)
	await _frames(2)
	menu.close()
	menu.chosen.emit(&"w:branch:nailgun")
	_check(menu.is_open and menu.card_count() == 2 and run._pending_caches == 1, "il bivio apre le due trasformazioni")
	await create_timer(0.6, true).timeout
	menu.press(0)
	await _frames(3)
	_check(run._pending_caches == 0 and run._pending_level_ups == 0 and run.loadout.level_of(&"nailgun") == 3,
		"dopo la trasformazione la cassa e chiusa (casse %d, level-up %d)" % [run._pending_caches, run._pending_level_ups])
	_check(not menu.is_open and not paused, "e il gioco riparte")

	# Due casse e un level-up nello stesso passo: tre scelte, nessuna persa, poi si riparte.
	run._pending_level_ups = 1
	run._on_cache_opened(Vector3.ZERO)
	run._on_cache_opened(Vector3.ZERO)
	await _frames(2)
	var cache_screens := 0
	var level_screens := 0
	var always_paused := true
	for i in 10:
		if not menu.is_open:
			break
		always_paused = always_paused and paused
		if menu.title_text() == "CASSA SEPOLTA":
			cache_screens += 1
		elif menu.title_text().begins_with("LIVELLO"):
			level_screens += 1
		await create_timer(0.6, true).timeout
		menu.press(0)
		await _frames(3)
	_check(cache_screens == 2 and level_screens == 1, "due casse e un level-up scelti (%d, %d)" % [cache_screens, level_screens])
	_check(always_paused and not menu.is_open and not paused and run._pending_caches == 0 and run._pending_level_ups == 0,
		"fermo fino all'ultima scelta, poi il gioco riparte")

	# Slot pieni e tutto al 5: nessun menu, 2 rottami nei Cassoni della carovana.
	for i in 60:
		var cards := WeaponOffers.cards(run.loadout, run.class_id, run._unlocked_weapons())
		if cards.is_empty():
			break
		var card: Dictionary = cards[0]
		match card.kind:
			&"new":
				run.loadout.add(card.weapon_id)
			&"level":
				run.loadout.level_up(card.weapon_id)
			&"branch":
				run.loadout.choose_branch(card.weapon_id, &"a")
			&"fusion":
				run.loadout.fuse(card.weapon_id)
	_check(WeaponOffers.cards(run.loadout, run.class_id, run._unlocked_weapons()).is_empty(), "nessuna carta arma possibile")
	run.caravan.carried = 0
	run._on_cache_opened(Vector3.ZERO)
	await _frames(3)
	_check(not menu.is_open and not paused and run._pending_caches == 0, "nessun menu")
	_check(run.caravan.carried == 2, "2 rottami nella carovana: %d" % run.caravan.carried)
	_check(run.hud.event_warning_text().begins_with("CASSA SEPOLTA"), "avviso nel HUD: %s" % run.hud.event_warning_text())
	# Con un solo posto libero il secondo rottame resta a terra, come col compagno.
	run.caravan.carried = run.caravan.capacity - 1
	var on_ground := run._scrap_field().count()
	run._on_cache_opened(Vector3.ZERO)
	await _frames(3)
	_check(run.caravan.carried == run.caravan.capacity and run._scrap_field().count() == on_ground + 1,
		"cassone quasi pieno: un rottame a bordo, l'altro a terra (%d/%d, %d a terra)" % [run.caravan.carried, run.caravan.capacity, run._scrap_field().count() - on_ground])
	profile.reset()
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	await _frames(2)
