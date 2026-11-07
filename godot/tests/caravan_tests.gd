extends SceneTree
## Carovana di macchine, piano A (spec D-093): Machine, Caravan e modulo Cassone sul nodo
## `Caravan` della scena `ruins_arena` (dal task 3 al posto del compagno), piu i controlli che
## erano di companion_tests (fornitura, campo dei rottami). La scena non ha un campo di
## percorso: il test ne aggiunge uno e lo passa alla carovana. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/caravan_tests.gd

const ArenaScene := preload("res://scenes/main/ruins_arena.tscn")
const TURRET_SCRIPT := preload("res://scripts/caravan/modules/turret_module.gd")
const MAGNET_SCRIPT := preload("res://scripts/caravan/modules/magnet_module.gd")
const TUNING_PATH := "res://resources/tuning/caravan_default.tres"
## Quota dell'origine del giocatore sul suolo.
const PLAYER_CLEARANCE := 0.88

var _failures := 0
var _scene: Node3D
var _player: PlayerCharacter
var _field: TerrainField
var _scraps: ScrapField
var _path: PathField
var _caravan: Caravan
## Valori di `carried_changed` ricevuti dalla carovana corrente.
var _emitted: Array[int] = []


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _load_scene()
	_test_starts_with_cargo()
	await _test_supply_distance()
	await _test_lead_follows_player()
	await _test_speed_scale_moves_machine()
	await _test_pickup_near_player_only()
	await _test_skips_scrap_behind_rampart()
	await _test_ignores_sealed_scrap()
	await _test_cluster_of_three()
	_test_module_limit()
	await _test_two_cargo_supply()
	await _test_switched_off_cargo_releases_scrap()
	await _reload_scene()
	await _test_scrap_field_offset_and_cap()
	# T-12: i nodi messi in coda con queue_free vanno liberati prima di uscire.
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


## La carovana della scena: una macchina col Cassone, 3 rottami su 5, sul layer visivo 2.
func _test_starts_with_cargo() -> void:
	print("caravan ready")
	_check(_caravan.player == _player and _caravan.scrap_field == _scraps and _caravan.tuning != null
		and _caravan.tuning.resource_path == TUNING_PATH, "il nodo Caravan della scena e collegato a giocatore, rottami e taratura")
	var lead := _caravan.lead()
	_check(_caravan.machines.size() == 1 and lead != null and lead.has_module(&"cargo") and lead.cargo() != null,
		"la carovana parte con una macchina col Cassone")
	_check(_caravan.carried == 3 and _caravan.capacity == 5 and _caravan.room() == 2,
		"3 rottami a bordo su 5 (%d/%d)" % [_caravan.carried, _caravan.capacity])
	_check(_emitted.size() == 1 and _emitted[0] == 3, "carried_changed una volta, col totale (%s)" % [_emitted])
	_check(lead.name == &"Machine1" and lead.get_parent() == _caravan and lead.slot == 0 and lead.primary_module_id() == &"cargo",
		"Machine1, figlia della carovana, nel posto 0")
	_check(lead.health == 6 and lead.max_health == 6 and lead.state == Machine.State.OK and not lead.is_broken(),
		"telaio da 6 PV, in ordine")
	_check(lead.collision_layer == 8 and lead.collision_mask == 1, "layer 8 e maschera 1, come il compagno")
	_check(Machine.planar_distance(lead.global_position, _caravan.global_position) < 0.01, "nasce dove sta la carovana")
	_check(_caravan.global_position.is_equal_approx(Vector3(0.0, 0.3, 2.5)), "dove stava il compagno (%s)" % _caravan.global_position)
	_check(lead._cargo.size() == 5 and lead._cargo.filter(func(c: MeshInstance3D) -> bool: return c.visible).size() == 3,
		"cinque cubetti sul pianale, tre visibili")
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	lead.mount_part(&"TestPart", part)
	var visuals := lead.find_children("*", "VisualInstance3D", true, false)
	var off_layer := visuals.filter(func(n: Node) -> bool: return (n as VisualInstance3D).layers != Machine.VISUAL_LAYER)
	_check(visuals.size() >= 7 and off_layer.is_empty() and lead._parts.size() == 1,
		"modello, cubetti e pezzi montati sul layer visivo 2 (%d visual, %d fuori)" % [visuals.size(), off_layer.size()])
	# Le ombre delle nuvole scuriscono la macchina come scurivano il compagno; l'anello del
	# pennello no (scelta 12 di D-093).
	var clouds := _scene.get_node_or_null(^"OvergrownArena/CloudShadows") as Decal
	var brush := _player.get_node_or_null(^"BrushPreview") as Decal
	_check(clouds is CloudShadows and brush is BrushPreview, "ombre delle nuvole e anello del pennello in scena")
	if clouds != null and brush != null:
		var shaded := visuals.all(func(n: Node) -> bool: return ((n as VisualInstance3D).layers & clouds.cull_mask) != 0)
		var painted := visuals.any(func(n: Node) -> bool: return ((n as VisualInstance3D).layers & brush.cull_mask) != 0)
		_check(shaded and (clouds.cull_mask & 1) != 0,
			"le ombre delle nuvole raggiungono la macchina e il layer 1 (cull_mask %d)" % clouds.cull_mask)
		_check(not painted and (brush.cull_mask & 1) != 0,
			"l'anello del pennello non dipinge la macchina, solo il layer 1 (cull_mask %d)" % brush.cull_mask)


## Dal compagno (companion_tests): can_supply vuole rottami a bordo e il Cassone entro il raggio
## di rifornimento dal bersaglio; il campo dei rottami poggia i rottami sul rilievo.
func _test_supply_distance() -> void:
	print("supply")
	var lead := _caravan.lead()
	lead.set_physics_process(false)
	var target := Vector3(0.0, 0.0, 2.0)
	_place_machine(lead, Vector3(0.0, 0.0, -2.0))
	_check(_caravan.carried == 3 and _caravan.can_supply(target), "vicino e con rottami rifornisce")
	_caravan.carried = 0
	_check(not _caravan.can_supply(target), "senza rottami no")
	_caravan.carried = 3
	_place_machine(lead, Vector3(20.0, 0.0, 20.0))
	_check(not _caravan.can_supply(target), "lontano no")
	_check(_scraps.terrain_field == _field, "il campo dei rottami sta sul rilievo")
	var spot := Vector3(4.0, 0.0, 4.0)
	_scraps.spawn_on_ground(spot)
	var found: Variant = _scraps.nearest(spot, 0.1)
	_check(found != null and absf((found as Vector3).y - ScrapField.SCRAP_SIZE) < ScrapField.BOB_HEIGHT + 0.01, "il rottame poggia sulla quota del rilievo")
	_scraps.take_near(spot, 0.5, 10)
	_place_machine(lead, Vector3(0.0, 0.0, 2.5))
	lead.set_physics_process(true)
	await _frames(2)


## Il capofila segue il giocatore che cammina 10 m e si ferma 2,5 m dietro di lui.
func _test_lead_follows_player() -> void:
	print("lead follows")
	var lead := _caravan.lead()
	var start := _player.global_position
	Input.action_press(&"move_right")
	for i in 240:
		await physics_frame
		if Machine.planar_distance(_player.global_position, start) >= 10.0:
			break
	Input.action_release(&"move_right")
	var walked := _player.global_position - start
	walked.y = 0.0
	await _frames(150)
	var offset := lead.global_position - _player.global_position
	offset.y = 0.0
	var along := offset.dot(walked.normalized())
	_check(walked.length() >= 9.5, "il giocatore cammina 10 m (%.1f)" % walked.length())
	_check(absf(offset.length() - 2.5) <= 0.6, "il capofila si ferma a 2,5 +- 0,6 m (%.2f)" % offset.length())
	_check(along < -1.5, "dietro al giocatore (%.2f m lungo il cammino)" % along)
	_check(Vector2(lead.velocity.x, lead.velocity.z).length() < 0.3, "e resta fermo (%.2f m/s)" % lead.velocity.length())


## Olio buono e Motore truccato passano da `speed_scale` (prima scrivevano la velocita che il
## compagno leggeva dalla sua taratura): una macchina vera, lontana dal giocatore su terreno
## aperto, corre a max_speed x speed_scale. Senza campo di percorso: col campo la meta e la
## cella vicina e la velocita resta sotto distanza x 3.
func _test_speed_scale_moves_machine() -> void:
	print("speed scale")
	var lead := _caravan.lead()
	var max_speed := _caravan.tuning.max_speed
	_caravan.path_field = null
	var peaks: Array[float] = []
	for scale: float in [1.0, 1.4]:
		_caravan.speed_scale = scale
		_place_player(Vector3(10.0, 0.0, 0.0))
		_place_machine(lead, Vector3(-2.0, 0.0, 0.0))
		var peak := 0.0
		for i in 60:
			await physics_frame
			peak = maxf(peak, Vector2(lead.velocity.x, lead.velocity.z).length())
		peaks.append(peak)
	_caravan.speed_scale = 1.0
	_caravan.path_field = _path
	_check(absf(peaks[0] - max_speed) < 0.3, "a speed_scale 1 la macchina corre a max_speed (%.2f m/s)" % peaks[0])
	_check(absf(peaks[1] - max_speed * 1.4) < 0.3 and peaks[1] > max_speed + 1.0,
		"a speed_scale 1,4 corre a max_speed x 1,4 (%.2f m/s contro %.1f)" % [peaks[1], max_speed])


## Raccoglie un rottame entro 6 m dal giocatore e ignora quello a 9 m.
func _test_pickup_near_player_only() -> void:
	print("pickup radius")
	var center := Vector3(0.0, 0.0, -2.0)
	_place_player(center)
	var lead := _caravan.lead()
	_place_machine(lead, center + Vector3(0.0, 0.0, 2.5))
	await _frames(30)
	var near := center + Vector3(-4.0, 0.0, 3.0)
	var far := center + Vector3(0.0, 0.0, -9.0)
	_scraps.spawn_on_ground(near)
	_scraps.spawn_on_ground(far)
	_emitted.clear()
	await _frames(180)
	_check(lead.cargo().carried == 4 and _caravan.carried == 4, "raccoglie il rottame a 5 m dal giocatore (carried %d)" % _caravan.carried)
	_check(_scraps.nearest(near, 0.1) == null, "il rottame vicino non e piu a terra")
	_check(_scraps.nearest(far, 0.1) != null, "quello a 9 m resta a terra")
	_check(_emitted.size() == 1 and _emitted[0] == 4, "una notifica per la raccolta, col totale (%s)" % [_emitted])
	_scraps.take_near(far, 0.5, 10)


## Audit C-01 (oggi in arena_run_tests): un rottame raggiungibile solo aggirando un argine
## non e una meta in linea retta, la macchina spingerebbe contro l'argine.
func _test_skips_scrap_behind_rampart() -> void:
	print("scrap behind rampart")
	var p := Vector3(-6.0, 0.0, -8.0)
	_field.set_protected(p, 16.0, false)
	_place_player(p)
	for x in range(-10, 11, 2):
		_field.sculpt(p + Vector3(x, 0.0, 3.5), 1.6, 1.6)
	var lead := _caravan.lead()
	_place_machine(lead, p + Vector3(0.0, 0.0, 1.0))
	_path.solve()
	var scrap := p + Vector3(0.0, 0.0, 5.8)
	_scraps.spawn_on_ground(scrap)
	await _frames(2)
	_check(_path.cost_at(scrap) != PathField.UNREACHABLE and Machine.planar_distance(scrap, _player.global_position) <= 6.0,
		"il rottame ha una strada attorno all'argine ed e entro 6 m dal giocatore")
	var destination := lead._choose_destination()
	_check(Machine.planar_distance(destination, scrap) > 1.0,
		"rottame dietro un argine: non e la meta della macchina (meta a %.1f m dal rottame)" % Machine.planar_distance(destination, scrap))
	_field.reset_to_base(p + Vector3(0.0, 0.0, 3.5), Vector2(13.0, 3.0))
	await _frames(2)
	_path.solve()
	destination = lead._choose_destination()
	_check(Machine.planar_distance(destination, scrap) < 0.5,
		"tolto l'argine il rottame torna la meta (meta a %.1f m)" % Machine.planar_distance(destination, scrap))
	_scraps.take_near(scrap, 1.5, 10)


## R-05 (oggi in boss_tests): la macchina non punta a un rottame chiuso in un anello di argini;
## riaperto l'anello, al passo dopo la nuova soluzione del percorso, si.
func _test_ignores_sealed_scrap() -> void:
	print("sealed scrap")
	var q := Vector3(-3.0, 0.0, 8.0)
	_place_player(q)
	var lead := _caravan.lead()
	lead.cargo().carried = 0
	_place_machine(lead, q + Vector3(-1.5, 0.0, 0.0))
	var sealed := q + Vector3(5.5, 0.0, 0.0)
	_seal_ring(sealed)
	await _frames(2)
	_path.solve()
	var before := _scraps.count()
	_scraps.spawn_on_ground(sealed)
	_check(_path.cost_at(sealed) == PathField.UNREACHABLE, "il rottame e chiuso nell'anello")
	var destination := lead._choose_destination()
	_check(Machine.planar_distance(destination, sealed) > 1.0, "il rottame sigillato non e la meta della macchina")
	_open_ring(sealed)
	await _frames(2)
	_path.solve()
	destination = lead._choose_destination()
	_check(Machine.planar_distance(destination, sealed) < 0.5,
		"riaperto, il rottame torna la meta (costo %.1f, meta %s)" % [_path.cost_at(sealed), destination])
	_scraps.take_near(sealed, 1.0, 1)
	_check(_scraps.count() == before, "pulizia")
	await _frames(2)


## Tre macchine (Cassone, Torretta, Calamita) tengono i loro posti attorno al giocatore.
func _test_cluster_of_three() -> void:
	print("cluster of three")
	var center := Vector3(-6.0, 0.0, -2.0)
	_place_player(center)
	var lead := _caravan.lead()
	_place_machine(lead, center + Vector3(0.0, 0.0, 2.5))
	await _frames(2)
	var turret := _caravan.add_machine(&"turret")
	var magnet := _caravan.add_machine(&"magnet")
	_check(turret != null and magnet != null and _caravan.machines.size() == 3 and _caravan.module_count() == 3,
		"add_machine di turret e magnet: tre macchine")
	if turret == null or magnet == null:
		return
	_check(turret.slot == 1 and magnet.slot == 2 and turret.name == &"Machine2" and magnet.name == &"Machine3",
		"posti 1 e 2, nomi crescenti")
	_check(turret.has_module(&"turret") and turret.module(&"turret").get_script() == TURRET_SCRIPT and turret.cargo() == null,
		"la Torretta ha il suo modulo (TurretModule)")
	_check(magnet.has_module(&"magnet") and magnet.module(&"magnet").get_script() == MAGNET_SCRIPT, "la Calamita ha il suo modulo (MagnetModule)")
	_check(Caravan.module_script_for(&"nope") == MachineModule and Caravan.module_script_for(&"drill") != MachineModule,
		"un id fuori catalogo usa il modulo inerte, la Trivella ha il suo script")
	# Scena senza regia: niente direttore, campo dei frammenti ne taratura della run. I moduli
	# aspettano i servizi senza errori.
	_check((turret.module(&"turret") as TurretModule).weapon().shooter == null, "senza direttore la Torretta non spara")
	_check(_caravan.lead() == lead, "il capofila resta la macchina col Cassone")
	var ground := _field.height_at(turret.global_position) + Caravan.GROUND_CLEARANCE
	_check(absf(turret.global_position.y - ground) < 0.05 and Machine.planar_distance(turret.global_position, _caravan.slot_target(turret)) < 0.05,
		"la macchina nuova nasce sul suolo del suo posto")
	# Quattro secondi di cammino in quadrato (il giocatore corre a 6 m/s, le macchine a 5),
	# poi il grappolo si ricompone attorno a lui.
	for action: StringName in [&"move_right", &"move_back", &"move_left", &"move_forward"]:
		Input.action_press(action)
		await _frames(60)
		Input.action_release(action)
	await _frames(90)
	var cluster: Array[Machine] = [lead, turret, magnet]
	var distances: Array[String] = []
	var in_ring := true
	for machine in cluster:
		var distance := Machine.planar_distance(machine.global_position, _player.global_position)
		distances.append("%.2f" % distance)
		in_ring = in_ring and distance >= 2.0 and distance <= 4.0
	var closest := INF
	for i in cluster.size():
		for j in range(i + 1, cluster.size()):
			closest = minf(closest, Machine.planar_distance(cluster[i].global_position, cluster[j].global_position))
	_check(in_ring, "dopo il cammino stanno fra 2 e 4 m dal giocatore (%s)" % ", ".join(distances))
	_check(closest > 1.2, "e a piu di 1,2 m l'una dall'altra (%.2f)" % closest)


## Al piu 6 moduli; un modulo fuori catalogo non aggiunge nulla.
func _test_module_limit() -> void:
	print("module limit")
	_check(_caravan.add_machine(&"nope") == null and _caravan.machines.size() == 3, "un modulo fuori catalogo restituisce null")
	for id: StringName in [&"beacon", &"drill", &"shovel"]:
		_caravan.add_machine(id)
	_check(_caravan.module_count() == 6 and not _caravan.has_room(), "sei moduli: carovana piena")
	_check(_caravan.add_machine(&"welder") == null and _caravan.machines.size() == 6, "oltre il limite di 6 moduli add_machine restituisce null")
	var slots: Array[int] = []
	for machine in _caravan.machines:
		slots.append(machine.slot)
	var expected: Array[int] = [0, 1, 2, 3, 4, 5]
	_check(slots == expected and _caravan.machines[5].name == &"Machine6", "posti da 0 a 5 (%s)" % [slots])
	_check(_caravan.count_of(&"cargo") == 1 and _caravan.count_of(&"drill") == 1 and _caravan.modules_of(&"shovel").size() == 1,
		"count_of e modules_of per tipo")


## Due Cassoni: fornitura per distanza, prelievo dal piu vicino, una notifica per operazione.
func _test_two_cargo_supply() -> void:
	print("two cargo supply")
	var p := Vector3(8.0, 0.0, 8.0)
	await _replace_caravan(p + Vector3(0.0, 0.0, 2.5))
	var queue := TerrainWriteQueue.new()
	_caravan.configure({write_queue = queue})
	var a := _caravan.lead()
	var b := _caravan.add_machine(&"cargo")
	_check(b != null and queue.bodies.has(a) and queue.bodies.has(b), "le macchine stanno in write_queue.bodies, anche quella aggiunta dopo")
	if b == null:
		queue.free()
		return
	await _frames(1)
	a.set_physics_process(false)
	b.set_physics_process(false)
	_place_machine(a, p + Vector3(1.0, 0.0, 0.0))
	_place_machine(b, p + Vector3(-4.0, 0.0, 0.0))
	a.cargo().carried = 2
	b.cargo().carried = 3
	_check(_caravan.carried == 5 and _caravan.capacity == 10, "due Cassoni con 2 e 3 rottami: carried 5 (%d)" % _caravan.carried)
	_check(_caravan.can_supply_count(p, 4), "entrambi entro 5 m dal punto: 4 rottami ci sono")
	_place_machine(b, p + Vector3(-7.0, 0.0, 0.0))
	_check(not _caravan.can_supply_count(p, 4), "uno a 7 m: 4 rottami no")
	_check(_caravan.can_supply_count(p, 2) and _caravan.can_supply(p), "ma il vicino ne fornisce 2")
	_place_machine(b, p + Vector3(-4.0, 0.0, 0.0))
	_check(_caravan.can_supply_count(p, 4), "tornato entro 5 m: di nuovo si")
	_emitted.clear()
	_caravan.spend_count(3)
	_check(a.cargo().carried == 0 and b.cargo().carried == 2,
		"spend_count(3) preleva prima dal piu vicino al punto (vicino %d, lontano %d)" % [a.cargo().carried, b.cargo().carried])
	_check(_emitted.size() == 1 and _emitted[0] == 2, "carried_changed una volta sola, col valore 2 (%s)" % [_emitted])

	a.cargo().carried = 3
	b.cargo().carried = 3
	_emitted.clear()
	var added := _caravan.add_scrap(10)
	_check(added == 4 and _caravan.carried == 10 and _caravan.room() == 0, "add_scrap(10) con 4 posti liberi ne mette 4 (%d)" % added)
	_check(_emitted.size() == 1 and _emitted[0] == 10, "una sola notifica (%s)" % [_emitted])
	_caravan.carried = 3
	_check(a.cargo().carried == 3 and b.cargo().carried == 0, "i rottami riempiono dal capofila in poi")

	# Il Cassone guasto conta nel totale ma non fornisce (scelta 3 di D-093).
	_caravan.carried = 7
	b.state = Machine.State.BROKEN
	_check(_caravan.carried == 7 and not _caravan.can_supply_count(p, 6), "i rottami del Cassone guasto contano ma non forniscono")
	_emitted.clear()
	_check(not _caravan.pay(6) and _caravan.carried == 7 and _emitted.is_empty(), "pay senza i guasti: tutto o niente")
	_check(_caravan.pay(6, true) and _caravan.carried == 1 and _emitted.size() == 1, "pay coi guasti compresi")
	b.state = Machine.State.OK

	# La firma di fornitura del compagno di oggi.
	_caravan.carried = 4
	_check(_caravan.can_supply(p) and _caravan.can_supply_count(p, 4), "can_supply(punto) e can_supply_count(punto, n)")
	_caravan.spend()
	_check(_caravan.carried == 3, "spend() toglie un rottame")
	_caravan.spend_count(2)
	_check(_caravan.carried == 1, "spend_count(n) ne toglie n")

	_caravan.add_cargo_capacity(2)
	_check(_caravan.capacity == 14 and a.cargo().capacity == 7 and a._cargo.size() == 7, "add_cargo_capacity(2): 7 per Cassone, coi cubetti")
	var c := _caravan.add_machine(&"cargo")
	_check(c != null and c.cargo().capacity == 7 and _caravan.capacity == 21, "un Cassone aggiunto dopo ha la stessa capienza")
	queue.free()


## Un rottame gia meta di un Cassone si salta; spento quel Cassone (la macchina guasta, task 6)
## il rottame torna libero per gli altri, anche se `active` cambia senza l'hook.
func _test_switched_off_cargo_releases_scrap() -> void:
	print("switched off cargo releases scrap")
	var p := Vector3(8.0, 0.0, -6.0)
	await _replace_caravan(p + Vector3(0.0, 0.0, 2.5))
	var a := _caravan.lead()
	var b := _caravan.add_machine(&"cargo")
	if b == null:
		_check(false, "secondo Cassone aggiunto")
		return
	await _frames(1)
	# Passi fisici spenti: le mete si chiedono a mano, il tempo lo fa scorrere `tick`.
	a.set_physics_process(false)
	b.set_physics_process(false)
	_place_player(p)
	a.cargo().carried = 0
	b.cargo().carried = 0
	_place_machine(a, p + Vector3(-1.5, 0.0, 0.0))
	var scrap := p + Vector3(3.0, 0.0, 0.0)
	_place_machine(b, scrap + Vector3(0.0, 0.0, 1.5))
	_scraps.spawn_on_ground(scrap)
	var interval := _caravan.tuning.cargo_search_interval
	_check(Machine.planar_distance(a._choose_destination(), scrap) < 0.5 and a.cargo().claimed_scrap() != null,
		"il primo Cassone punta il rottame")
	_check(Machine.planar_distance(b._choose_destination(), scrap) > 1.0, "il secondo, piu vicino, lo salta: e gia meta del primo")
	a.cargo().set_active(false)
	_check(a.cargo().claimed_scrap() == null, "spento, il primo Cassone lascia il rottame")
	b.cargo().tick(interval)
	_check(Machine.planar_distance(b._choose_destination(), scrap) < 0.5, "alla ricerca dopo, il secondo Cassone lo punta")
	# `active` cambiato senza passare dall'hook: claimed_scrap guarda anche `active`.
	a.cargo().set_active(true)
	_check(Machine.planar_distance(a._choose_destination(), scrap) > 1.0, "riacceso, il primo lo salta: ora e del secondo")
	b.cargo().active = false
	_check(b.cargo().claimed_scrap() == null, "spento senza l'hook, nemmeno il secondo lo tiene")
	a.cargo().tick(interval)
	_check(Machine.planar_distance(a._choose_destination(), scrap) < 0.5, "e il primo lo riprende")
	_scraps.take_near(scrap, 0.5, 10)


## Dal compagno (companion_tests, P-03): il bob lavora in coordinate locali, quindi il campo puo
## stare ovunque. R-09: al tetto MAX_SCRAPS uno scavo ricicla il rottame piu lontano, non viene
## scartato. Su una scena appena caricata, col Cassone fermo (nessuna raccolta).
func _test_scrap_field_offset_and_cap() -> void:
	print("scrap field offset and cap")
	_caravan.lead().set_physics_process(false)
	_scraps.position.y = 1.0
	_scraps.spawn(Vector3(3.0, 0.5, 3.0))
	await _frames(3)
	var found: Variant = _scraps.nearest(Vector3(3.0, 0.0, 3.0), 0.1)
	_check(found != null and absf((found as Vector3).y - 0.5) <= ScrapField.BOB_HEIGHT + 0.001,
		"campo a y=1: il rottame resta alla quota mondo chiesta (got %s)" % str(found))
	_check(_scraps.is_processing(), "con rottami a terra il bob gira")

	for i in ScrapField.MAX_SCRAPS - 1:
		_scraps.spawn(Vector3(30.0 + i, 0.5, 30.0))
	_check(_scraps.count() == ScrapField.MAX_SCRAPS and _scraps.capped_count == 0, "al tetto senza riciclo (%d)" % _scraps.count())
	var farthest := Vector3(30.0 + ScrapField.MAX_SCRAPS - 2, 0.5, 30.0)
	_scraps.spawn(Vector3(0.0, 0.5, 0.0))
	await _frames(2)
	_check(_scraps.count() == ScrapField.MAX_SCRAPS and _scraps.capped_count == 1, "oltre il tetto il conteggio resta a MAX_SCRAPS")
	_check(_scraps.nearest(Vector3.ZERO, 0.1) != null, "il nuovo rottame esiste")
	_check(_scraps.nearest(farthest, 0.1) == null and _scraps.nearest(Vector3(3.0, 0.0, 3.0), 0.1) != null,
		"riciclato il piu lontano dal nuovo, non il piu vicino")
	var taken := _scraps.take_near(Vector3(30.0 + ScrapField.MAX_SCRAPS * 0.5, 0.0, 30.0), 100.0, ScrapField.MAX_SCRAPS)
	await _frames(1)
	_check(taken == ScrapField.MAX_SCRAPS and _scraps.count() == 0, "take_near rimuove tutti i rottami nel raggio (%d)" % taken)
	_check(not _scraps.is_processing(), "senza rottami il bob si ferma")


## La scena con la sua carovana; il campo di percorso aggiunto qui passa alla carovana e ai
## suoi moduli (`configure` ridistribuisce anche giocatore, rottami e percorso).
func _load_scene() -> void:
	_scene = ArenaScene.instantiate()
	_scene.name = "Scene"
	_caravan = _scene.get_node(^"Caravan")
	_emitted.clear()
	_caravan.carried_changed.connect(_on_carried_changed)
	root.add_child(_scene)
	_player = _scene.get_node(^"Player")
	_field = _scene.get_node(^"TerrainField")
	_scraps = _scene.get_node(^"ScrapField")
	_path = PathField.new()
	_path.name = "PathField"
	_path.target = _player
	_path.terrain_field = _field
	_scene.add_child(_path)
	_caravan.path_field = _path
	_caravan.configure({terrain_field = _field})
	await _frames(2)
	for i in 10:
		if _path.is_ready():
			break
		await physics_frame
	_check(_path.is_ready(), "campo di percorso pronto")


func _reload_scene() -> void:
	root.remove_child(_scene)
	_scene.free()
	await _load_scene()


func _new_caravan(spot: Vector3) -> Caravan:
	var caravan := Caravan.new()
	caravan.name = "Caravan"
	caravan.tuning = load(TUNING_PATH) as CaravanTuning
	caravan.player = _player
	caravan.scrap_field = _scraps
	caravan.path_field = _path
	caravan.position = Vector3(spot.x, _field.height_at(spot) + Caravan.GROUND_CLEARANCE, spot.z)
	_emitted.clear()
	caravan.carried_changed.connect(_on_carried_changed)
	_scene.add_child(caravan)
	caravan.configure({terrain_field = _field})
	return caravan


func _replace_caravan(spot: Vector3) -> void:
	_scene.remove_child(_caravan)
	_caravan.queue_free()
	await _frames(2)
	_caravan = _new_caravan(spot)
	await _frames(1)


func _on_carried_changed(total: int) -> void:
	_emitted.append(total)


func _place_player(at: Vector3) -> void:
	_player.global_position = Vector3(at.x, _field.height_at(at) + PLAYER_CLEARANCE, at.z)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_path.solve()


func _place_machine(machine: Machine, at: Vector3) -> void:
	machine.global_position = Vector3(at.x, _field.height_at(at) + Caravan.GROUND_CLEARANCE, at.z)
	machine.velocity = Vector3.ZERO
	machine.reset_physics_interpolation()


## Anello di argini attorno a [param center] (come in boss_tests).
func _seal_ring(center: Vector3, radius := 3.0) -> void:
	var count := 16
	var amount := 1.4 / RuinsDistrict.line_overlap(TAU * radius / count, 2.0)
	for k in count:
		var angle := TAU * k / count
		_field.sculpt(center + Vector3(cos(angle), 0.0, sin(angle)) * radius, 2.0, amount)


func _open_ring(center: Vector3, radius := 3.0) -> void:
	# Due passate: la seconda spiana i bordi.
	_field.level(center, radius + 3.0, _field.base_height_at(center), 1.0)
	_field.level(center, radius + 3.0, _field.base_height_at(center), 1.0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
