extends SceneTree
## Moduli Torretta, Calamita e Faro (spec D-093, task 4 del piano A) sulla run vera di
## `arena_run.tscn`: livelli per tipo e bonus della carovana che valgono anche per le macchine
## aggiunte dopo, luci dei Faro col fattore di notte, il Cassone che non illumina piu. Poi, su una
## seconda scena (la prima finisce con la carovana piena), Trivella, Pala, Saldatore e Sirena
## (task 8). Su una terza scena le sei combinazioni del piano B (task 6), con macchine fuse.
## Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/machine_modules_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")
## Piano aperto e quasi in piano attorno a z 16 (machine_damage_tests): i casi del task 8 stanno
## lungo +-X, con z fra 12 e 20.
const AREA := Vector3(0.0, 0.0, 16.0)
## Il capofila a 2,5 m dal giocatore lungo -X: i posti 1-4 delle macchine nuove seguono lui.
const LEAD_OFFSET := Vector3(-2.5, 0.0, 0.0)

var _failures := 0
var _scene: Node3D
var _run: ArenaRun
var _field: TerrainField
var _player: PlayerCharacter
var _caravan: Caravan
var _director: EnemyDirector
var _xp: XpField
var _scraps: ScrapField
var _lamps: LampField
var _path: PathField
var _pad: ExtractionPad
## Macchine aggiunte dalla suite, di giorno e di notte: ognuna va in write_queue.bodies.
var _added: Array[Machine] = []
## Colpi della Torretta contati dal segnale `fired`.
var _shots := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _load_run()
	_test_lead_gives_no_light()
	await _test_turret_fires_and_stops()
	_test_turret_levels()
	await _test_magnet()
	await _test_bonuses_for_late_machines()
	await _test_beacon_at_night()
	_test_added_machines_registered()
	# Uscendo dall'albero il Faro libera la sua sorgente; resta la torcia.
	var lights := _run.light_field
	root.remove_child(_scene)
	_check(lights.source_count() == 1, "tolta la scena, il Faro ha liberato la sua sorgente (%d)" % lights.source_count())
	_scene.queue_free()
	await _frames(2)
	await _load_run()
	await _test_new_modules()
	_test_power()
	root.remove_child(_scene)
	_scene.queue_free()
	await _frames(2)
	await _load_run()
	await _test_combos()
	root.remove_child(_scene)
	_scene.queue_free()
	# T-12: i nodi messi in coda con queue_free vanno liberati prima di uscire. In piu le
	# campane della notte ancora in riproduzione si chiudono solo dopo un giro del server audio,
	# che va col tempo vero e non coi passi (a scena tolta i passi durano pochi millisecondi):
	# senza l'attesa all'uscita restano istanze Ogg perse.
	await _frames(2)
	var until := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < until:
		await process_frame
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Istanzia la run e la prepara ai test: niente chiodatrice del giocatore (non deve togliere i
## bersagli ai moduli), niente level-up (i rottamatori uccisi lasciano frammenti), boss ne eventi
## quando il tempo salta alla notte; il giocatore non muore.
func _load_run() -> void:
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_field = _scene.get_node(^"TerrainField")
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_director = _scene.get_node(^"EnemyDirector")
	_xp = _scene.get_node(^"XpField")
	_scraps = _scene.get_node(^"ScrapField")
	_lamps = _scene.get_node(^"LampField")
	_path = _scene.get_node(^"PathField")
	_pad = _scene.get_node(^"ExtractionPad")
	_added.clear()
	_director.spawning = false
	await _frames(5)
	(_scene.get_node(^"PlayerWeapon") as AutoWeapon).set_physics_process(false)
	_run.progression.xp_first_level = 100000
	_run.boss_call_at = 0.0
	for event: WorldEvent in [_run.quake_event, _run.train_event]:
		if event != null:
			event.schedule([])
	_player._invulnerable_left = 3600.0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _place_player(at: Vector3) -> void:
	_player.global_position = Vector3(at.x, _field.height_at(at) + 0.88, at.z)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _place_machine(machine: Machine, at: Vector3) -> void:
	machine.global_position = Vector3(at.x, _field.height_at(at) + Caravan.GROUND_CLEARANCE, at.z)
	machine.velocity = Vector3.ZERO
	machine.reset_physics_interpolation()


func _add(module_id: StringName) -> Machine:
	var machine := _caravan.add_machine(module_id)
	_check(machine != null and machine.has_module(module_id), "add_machine(%s)" % module_id)
	if machine != null:
		_added.append(machine)
	return machine


## Tutte le mesh del pezzo [param part_name] sul layer visivo della macchina.
func _part_on_layer(machine: Machine, part_name: NodePath) -> bool:
	var part := machine.get_node_or_null(part_name)
	if part == null:
		return false
	var visuals := part.find_children("*", "VisualInstance3D", true, false)
	return not visuals.is_empty() and visuals.all(func(n: Node) -> bool: return (n as VisualInstance3D).layers == Machine.VISUAL_LAYER)


## Raggio dell'attrattore [param node] nel campo dei frammenti, -1 se non c'e.
func _attractor_radius(node: Node3D) -> float:
	for entry in _xp.attractors:
		if entry.node == node:
			return entry.radius
	return -1.0


func _on_turret_fired(count: int) -> void:
	_shots += count


## Plan choice 1: la prima macchina (il Cassone) non porta piu il faro; all'inizio l'unica
## sorgente e la torcia del giocatore.
func _test_lead_gives_no_light() -> void:
	print("lead gives no light")
	var lead := _caravan.lead()
	var fields := _run.light_field
	_check(lead != null and lead.has_module(&"cargo"), "il capofila e il Cassone")
	_check(fields.source_count() == 1 and fields.source_node(_run.torch_light_id) == _player,
		"solo la torcia nel campo delle luci: il Cassone non e una sorgente (%d)" % fields.source_count())
	_check(lead.find_child("BeaconLight", true, false) == null and _caravan.beacon_lights().is_empty(),
		"nessuna BeaconLight sul Cassone, nessun Faro nella carovana")
	_check(_director.caravan == _caravan, "il direttore ha la carovana")


## Una macchina Torretta spara a un rottamatore entro 8 m da se stessa; spenta smette (i chiodi
## in volo finiscono), riaccesa riprende.
func _test_turret_fires_and_stops() -> void:
	print("turret")
	_place_player(Vector3.ZERO)
	var machine := _add(&"turret")
	if machine == null:
		return
	machine.set_physics_process(false)
	var spot := Vector3(-3.0, 0.0, -3.0)
	_place_machine(machine, spot)
	var module := machine.module(&"turret") as TurretModule
	var gun := module.weapon()
	var tuning := _caravan.tuning
	_check(gun != null and gun.get_parent() == module and gun.is_inside_tree() and gun.weapon_id == &"",
		"la Torretta ha la sua chiodatrice, figlia del modulo, senza weapon_id")
	_check(gun.shooter == machine and gun.director == _director and is_equal_approx(gun.muzzle_height, 0.55),
		"spara dalla macchina, col direttore, canna a 0,55 m")
	_check(is_equal_approx(gun.weapon_range, tuning.turret_range) and is_equal_approx(gun.weapon_range, 8.0)
		and gun.damage == _run.tuning.weapon_damage and is_equal_approx(gun.projectile_speed, _run.tuning.projectile_speed),
		"portata 8 m, danno e velocita dei chiodi della run")
	_check(is_equal_approx(gun.fire_interval, 0.9), "intervallo di base 0,9 s (%.3f)" % gun.fire_interval)
	_check(_part_on_layer(machine, ^"TurretPart"), "TurretPart montato, sul layer visivo 2")
	gun.fired.connect(_on_turret_fired)
	_shots = 0
	var enemy := _director.spawn_at(spot + Vector3(5.0, 0.0, 0.0))
	enemy.health = 50
	var peak := 0
	for i in 90:
		await physics_frame
		peak = maxi(peak, gun.nail_count())
	_check(_shots > 0 and peak > 0, "spara al rottamatore a 5 m (%d colpi, %d chiodi in volo al massimo)" % [_shots, peak])
	_check(is_instance_valid(enemy) and enemy.health < 50, "e lo colpisce (vita %d)" % (enemy.health if is_instance_valid(enemy) else -1))

	module.set_active(false)
	_check(gun.shooter == null, "spenta: niente tiratore")
	await _frames(30)
	_shots = 0
	var quiet := true
	for i in 60:
		await physics_frame
		quiet = quiet and gun.nail_count() == 0
	var in_range := is_instance_valid(enemy) and not enemy.is_dead \
		and Machine.planar_distance(enemy.global_position, machine.global_position) < gun.weapon_range
	_check(in_range and quiet and _shots == 0, "spenta non spara piu, col rottamatore ancora a tiro (%d colpi)" % _shots)
	module.set_active(true)
	_check(gun.shooter == machine, "riaccesa spara di nuovo dalla macchina")
	for i in 90:
		await physics_frame
		if _shots > 0:
			break
	_check(_shots > 0, "e riprende a sparare")
	gun.fired.disconnect(_on_turret_fired)
	_director.clear_horde()
	await _frames(20)


## Torretta veloce: il livello del tipo vale per ogni torretta, anche per quelle aggiunte dopo.
func _test_turret_levels() -> void:
	print("turret levels")
	var tuning := _caravan.tuning
	var expected := tuning.turret_interval / pow(tuning.turret_rate_per_level, 2)
	_check(is_equal_approx(expected, 0.9 / (1.35 * 1.35)), "la taratura da 0,9 / 1,35^2 (%.4f)" % expected)
	_caravan.set_module_level(&"turret", 2)
	_check(_caravan.module_level(&"turret") == 2, "module_level della Torretta: 2")
	var first := _caravan.modules_of(&"turret")
	_check(first.size() == 1 and is_equal_approx((first[0] as TurretModule).weapon().fire_interval, expected),
		"set_module_level(turret, 2): la torretta passa a %.4f s" % expected)
	var late := _add(&"turret")
	if late == null:
		return
	var all := _caravan.modules_of(&"turret")
	_check(all.size() == 2 and all.all(func(m: MachineModule) -> bool: return is_equal_approx((m as TurretModule).weapon().fire_interval, expected)),
		"una Torretta aggiunta dopo ha lo stesso intervallo (%.4f)" % (late.module(&"turret") as TurretModule).weapon().fire_interval)
	_check((late.module(&"turret") as TurretModule).weapon().shooter == late, "e spara dalla sua macchina")


## Calamita: attrattore di 2,5 m, 4,0 col livello 1; spenta lo toglie e i frammenti che
## volavano verso di lei scelgono di nuovo il bersaglio.
func _test_magnet() -> void:
	print("magnet")
	var machine := _add(&"magnet")
	if machine == null:
		return
	machine.set_physics_process(false)
	_place_player(Vector3(-4.0, 0.0, -4.0))
	_place_machine(machine, Vector3(4.0, 0.0, 4.0))
	var module := machine.module(&"magnet") as MagnetModule
	_check(is_equal_approx(_attractor_radius(machine), 2.5), "attrattore di 2,5 m sulla macchina (%.2f)" % _attractor_radius(machine))
	_check(_attractor_radius(_caravan.lead()) < 0.0, "il Cassone non attira")
	_check(_part_on_layer(machine, ^"MagnetPart"), "MagnetPart montato, sul layer visivo 2")
	_caravan.set_module_level(&"magnet", 1)
	_check(is_equal_approx(_attractor_radius(machine), 4.0), "col livello 1: 4,0 m (%.2f)" % _attractor_radius(machine))

	var before := _xp.count()
	_xp.spawn(machine.global_position + Vector3(-2.0, 0.0, 0.0), 1)
	var fragment: Dictionary = _xp._fragments.back()
	await _frames(2)
	_check(fragment.target == machine, "un frammento a 2 m vola verso la Calamita")
	module.set_active(false)
	_check(_attractor_radius(machine) < 0.0, "spenta: attrattore tolto")
	_check(fragment.target == null, "il frammento che volava verso di lei torna a scegliere")
	var node: Node3D = fragment.node
	var at := node.global_position
	await _frames(10)
	_check(fragment.target == null and Machine.planar_distance(node.global_position, at) < 0.01,
		"e resta fermo: nessun altro lo attira")
	module.set_active(true)
	_check(is_equal_approx(_attractor_radius(machine), 4.0), "riaccesa: di nuovo 4,0 m")
	await _frames(60)
	_check(not _xp._fragments.has(fragment) and _xp.count() == before, "il frammento arriva alla Calamita")


## Bonus della carovana per le macchine che arrivano dopo: capienza dei Cassoni e velocita.
func _test_bonuses_for_late_machines() -> void:
	print("late machines")
	var tuning := _caravan.tuning
	_caravan.speed_scale = 1.15
	_caravan.add_cargo_capacity(2)
	var machine := _add(&"cargo")
	if machine == null:
		return
	_check(machine.cargo().capacity == tuning.cargo_capacity + 2 and machine.cargo().capacity == 7,
		"un Cassone aggiunto dopo add_cargo_capacity(2) porta 7 rottami (%d)" % machine.cargo().capacity)
	# Pieno non cerca rottami; senza campo di percorso la meta e il posto, non la cella vicina.
	machine.cargo().carried = machine.cargo().capacity
	var path := _caravan.path_field
	_caravan.path_field = null
	_place_player(Vector3(4.0, 0.0, 0.0))
	_place_machine(machine, Vector3(-5.0, 0.0, 0.0))
	var peak := 0.0
	for i in 60:
		await physics_frame
		peak = maxf(peak, Vector2(machine.velocity.x, machine.velocity.z).length())
	_caravan.path_field = path
	_caravan.speed_scale = 1.0
	_check(absf(peak - tuning.max_speed * 1.15) < 0.3 and peak > tuning.max_speed + 0.4,
		"aggiunta dopo speed_scale = 1,15 corre a %.2f m/s (%.2f)" % [tuning.max_speed * 1.15, peak])


## Faro: sorgente di 11 m sulla macchina (13 col livello 1) e la sua BeaconLight. Aggiunto di
## notte, la luce si accende al fattore corrente al passo dopo; spento e riacceso a fattore
## fermo, la luce segue.
func _test_beacon_at_night() -> void:
	print("beacon at night")
	var cycle := _run.day_night
	_run.elapsed = cycle.night_start_seconds + cycle.dusk_seconds + 1.0
	await _frames(3)
	var factor := cycle.night_factor
	_check(cycle.phase == DayNightCycle.Phase.NIGHT and is_equal_approx(factor, 1.0), "e notte, fattore 1")
	var machine := _add(&"beacon")
	if machine == null:
		return
	var module := machine.module(&"beacon") as BeaconModule
	var fields := _run.light_field
	var base := _run.tuning.beacon_radius
	_check(is_equal_approx(base, 11.0) and module.light_id != -1 and is_equal_approx(fields.radius_of(module.light_id), base),
		"sorgente di 11 m (%.1f)" % fields.radius_of(module.light_id))
	_check(fields.source_count() == 2 and fields.source_node(module.light_id) == machine,
		"la sorgente e la macchina col Faro, non la carovana ne il Cassone")
	var light := module.light
	_check(light != null and light.name == &"BeaconLight" and light.get_parent() == module
		and light.position.is_equal_approx(Vector3(0.0, 1.6, 0.0)) and light.light_color.is_equal_approx(Color(1.0, 0.9, 0.72))
		and not light.shadow_enabled, "BeaconLight figlia del modulo: a 1,6 m, luce calda, senza ombre")
	_check(_part_on_layer(machine, ^"BeaconPart"), "BeaconPart montato, sul layer visivo 2")
	await _frames(2)
	_check(light.visible and is_equal_approx(light.light_energy, 2.2 * factor) and is_equal_approx(light.omni_range, base * 1.15),
		"aggiunto di notte: acceso al fattore corrente (energia %.2f, portata %.2f)" % [light.light_energy, light.omni_range])
	var listed := _caravan.beacon_lights()
	_check(listed.size() == 1 and listed[0].light == light and is_equal_approx(listed[0].radius, base), "beacon_lights: il Faro acceso")

	module.set_active(false)
	_check(not light.visible and is_zero_approx(fields.radius_of(module.light_id)) and _caravan.beacon_lights().is_empty(),
		"spento: luce nascosta e raggio 0")
	await _frames(2)
	_check(not light.visible, "e resta spento a fattore fermo")
	module.set_active(true)
	_check(is_equal_approx(fields.radius_of(module.light_id), base), "riacceso: di nuovo 11 m")
	await _frames(2)
	_check(light.visible and is_equal_approx(light.light_energy, 2.2 * factor), "e la luce si riaccende al fattore corrente")
	_caravan.set_module_level(&"beacon", 1)
	var upgraded := base + _run.tuning.beacon_radius_per_level
	_check(is_equal_approx(upgraded, 13.0) and is_equal_approx(fields.radius_of(module.light_id), upgraded),
		"set_module_level(beacon, 1): sorgente di 13 m (%.1f)" % fields.radius_of(module.light_id))
	await _frames(2)
	_check(is_equal_approx(light.omni_range, upgraded * 1.15), "al passo dopo la portata della luce segue (%.2f)" % light.omni_range)

	# Di giorno il Faro resta acceso: lo nasconde solo il fattore (D-093, regola 4 del task).
	_run.elapsed = 1.0
	await _frames(3)
	_check(cycle.phase == DayNightCycle.Phase.DAY and not light.visible and module.active
		and is_equal_approx(fields.radius_of(module.light_id), upgraded), "di giorno la luce si spegne ma il Faro resta una sorgente")


## Review Focus #5: ogni macchina aggiunta a meta run (di giorno e di notte) sta nella
## carovana, in write_queue.bodies e nella carovana del direttore.
func _test_added_machines_registered() -> void:
	print("added machines registered")
	var missing := _added.filter(func(m: Machine) -> bool:
		return not (_caravan.machines.has(m) and _run.write_queue.bodies.has(m)))
	_check(_added.size() == 5 and missing.is_empty() and _director.caravan == _caravan,
		"%d macchine aggiunte, tutte nella carovana e in write_queue.bodies (%d fuori)" % [_added.size(), missing.size()])
	_check(_caravan.module_count() == 6 and not _caravan.has_room(), "sei moduli: carovana piena")


# --- Trivella, Pala, Saldatore e Sirena (task 8), sulla seconda scena -----------------------

## Giocatore in AREA, capofila a 2,5 m lungo -X, le quattro macchine nuove ai posti 1-4, spente:
## ogni caso accende solo il suo modulo e ne riporta il timer all'intervallo intero subito dopo
## un'attesa (i conti dei passi partono da li).
func _test_new_modules() -> void:
	print("new modules")
	_scraps._veins.clear()
	_scraps.take_near(AREA, 40.0, _scraps.count())
	_check(_caravan.machines.size() == 1, "seconda scena: solo il capofila")
	_place_player_solved(AREA)
	_place_machine(_caravan.lead(), AREA + LEAD_OFFSET)
	var drill := _add(&"drill")
	var shovel := _add(&"shovel")
	var welder := _add(&"welder")
	var siren := _add(&"siren")
	if drill == null or shovel == null or welder == null or siren == null:
		return
	_check(drill.module(&"drill") is DrillModule and shovel.module(&"shovel") is ShovelModule
		and welder.module(&"welder") is WelderModule and siren.module(&"siren") is SirenModule,
		"Trivella, Pala, Saldatore e Sirena hanno il loro script")
	for each: Machine in [drill, shovel, welder, siren]:
		var id := each.primary_module_id()
		_check(_part_on_layer(each, NodePath("%sPart" % String(id).capitalize())), "pezzo di %s sul layer visivo" % id)
		each.modules[0].set_active(false)
	_gather_machines()
	for each in _caravan.machines:
		_check(await _settle(each), "%s fermo al suo posto" % each.primary_module_id())
	await _test_drill(drill)
	await _test_shovel(shovel)
	await _test_welder(welder, drill)
	await _test_siren(siren)
	await _test_broken_idle(drill, shovel, welder, siren)


## Trivella: senza vene una buca a 1 m dal rottamatore verso la macchina, ma mai su un cumulo,
## vicino a un lampione, nella piazzola attiva o sul giocatore; da una vena un rottame a terra,
## raggiungibile dal Cassone, senza scavare.
func _test_drill(drill: Machine) -> void:
	print("drill")
	var tuning := _caravan.tuning
	var module := drill.module(&"drill") as DrillModule
	var queue := _run.write_queue
	var n_drill := roundi(tuning.drill_interval * Engine.physics_ticks_per_second)
	var d := drill.global_position
	var w := _side(drill)
	var ideal := d + w * 3.0
	var enemy_at := d + w * 4.0
	_spawn_still(enemy_at)
	_check(_flat(ideal) and module.clear_spot(ideal, tuning.drill_radius), "(a) punto ideale in base e libero")
	module.set_active(true)
	module._drill_left = tuning.drill_interval
	await _frames(n_drill + 3)
	var floor_h := _field.base_height_at(ideal) - tuning.drill_depth
	_check(absf(_field.height_at(ideal) - floor_h) < 0.05,
		"(a) rottamatore a 4 m, nessuna vena: buca fra lui e la macchina (%.2f m dal fondo)" % (_field.height_at(ideal) - floor_h))
	_field.reset_to_base(ideal, Vector2(2.0, 2.0))

	# (b) Un cumulo senza vene sul punto ideale: oltre la tolleranza, niente buca.
	_field.sculpt(ideal, 1.5, 0.8)
	_check(_field.delta_at(ideal) > tuning.drill_flat_tolerance and module.clear_spot(ideal, tuning.drill_radius),
		"(b) cumulo di %.2f m sul punto ideale, libero" % _field.delta_at(ideal))
	await _frames(1)
	module._drill_left = tuning.drill_interval
	_check(await _no_write(n_drill + 3, [ideal]), "(b) cumulo senza vene: nessuna buca")
	_field.reset_to_base(ideal, Vector2(2.0, 2.0))

	# (c) Un lampione a 1,5 m dal punto ideale lo toglie: il lampione resta in piedi.
	var lamp_at := ideal + Vector3(0.0, 0.0, 1.5 * _toward_area_z(ideal))
	_check(_flat(ideal) and module.clear_spot(ideal, tuning.drill_radius) and _lamps.can_place(lamp_at),
		"(c) punto ideale libero, lampione possibile a 1,5 m")
	_lamps._build_post(lamp_at)
	_check(not module.clear_spot(ideal, tuning.drill_radius), "(c) col lampione a 1,5 m il punto non e libero")
	await _frames(1)
	module._drill_left = tuning.drill_interval
	_check(await _no_write(n_drill + 3, [ideal, lamp_at]) and _lamps.count() == 1, "(c) nessuna buca, il lampione resta in piedi")
	_lamps.remove_all(&"test")

	# (d) Piazzola di estrazione attiva: nessuna scrittura nel suo disco attorno al giocatore.
	ideal = AREA + Vector3(-3.5, 0.0, 1.6)
	enemy_at = ideal + _planar_unit(ideal - d)
	_director.clear_horde()
	_spawn_still(enemy_at)
	_check(_flat(ideal) and module.clear_spot(ideal, tuning.drill_radius)
		and Machine.planar_distance(enemy_at, d) <= tuning.drill_reach
		and Machine.planar_distance(ideal, AREA) < _pad.radius_m + tuning.drill_radius,
		"(d) punto ideale libero, nel disco della piazzola, rottamatore a portata")
	_pad.hold_seconds = 3600.0
	_pad.begin()
	_check(not module.clear_spot(ideal, tuning.drill_radius), "(d) a estrazione attiva il punto non e libero")
	await _frames(1)
	module._drill_left = tuning.drill_interval
	_check(await _no_write(n_drill + 3, [ideal]), "(d) piazzola attiva: nessuna scrittura nel suo disco")
	_pad.active = false
	if _pad._ring != null:
		_pad._ring.hide_ring()
	if _pad.hud != null:
		_pad.hud.clear_event_warning(RunHud.WarningPriority.EXTRACTION)
	_pad.hold_seconds = _run.tuning.extraction_hold_seconds

	# (e) Il punto ideale e il giocatore: mai una scrittura entro `keep_clear` da lui.
	enemy_at = AREA + _planar_unit(AREA - d)
	_director.clear_horde()
	_spawn_still(enemy_at)
	var spot: Variant = module.point_toward(enemy_at, d, DrillModule.HOLE_GAP_M)
	_check(spot != null and Machine.planar_distance(spot, AREA) < 0.01 and Machine.planar_distance(enemy_at, d) <= tuning.drill_reach
		and not module.clear_spot(AREA, tuning.drill_radius), "(e) il punto ideale e sul giocatore")
	await _frames(1)
	module._drill_left = tuning.drill_interval
	_check(await _no_write(n_drill + 3, [AREA]), "(e) nessuna scrittura sul giocatore")
	_director.clear_horde()

	# (f) Una vena a 3 m sotto un cumulo: un rottame in meno nella vena, uno a terra fuori dal
	# cumulo in un punto aperto, il terreno com'era; poi il Cassone lo raccoglie.
	var vein_at := d + w * 3.0
	_field.sculpt(vein_at, 1.2, 1.0)
	var samples: Array[Vector3] = [vein_at]
	for k in 8:
		samples.append(vein_at + Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0)) * 0.6)
	var heights: Array[float] = []
	for p in samples:
		heights.append(_field.height_at(p))
	_scraps.add_vein(vein_at, 1.2, 4, _field.base_height_at(vein_at))
	_caravan.carried = tuning.starting_scrap
	var scraps_before := _scraps.count()
	await _frames(1)
	module._drill_left = tuning.drill_interval
	var drilled := false
	var quiet := true
	for k in roundi(4.5 * Engine.physics_ticks_per_second):
		await physics_frame
		quiet = quiet and queue.pending() == 0
		if _scraps.vein_scrap_left(vein_at) == 3:
			drilled = true
			break
	_check(drilled and _scraps.count() == scraps_before + 1, "(f) vena a 3 m: entro 4,5 s un rottame in meno e uno a terra")
	var dropped := _scraps.positions_near(vein_at, 3.0)
	_check(dropped.size() == 1 and _caravan.is_open_point(dropped[0]) and Machine.planar_distance(dropped[0], vein_at) > 1.2,
		"(f) il rottame e fuori dal cumulo, in un punto aperto (%s)" % [dropped])
	var same := true
	for k in samples.size():
		same = same and _field.height_at(samples[k]) == heights[k]
	_check(quiet and queue.pending() == 0 and same, "(f) nessuna scrittura: il cumulo e com'era")
	_scraps._veins.clear()
	var collected := false
	for k in 300:
		await physics_frame
		if _caravan.carried == tuning.starting_scrap + 1 and _scraps.count() == scraps_before:
			collected = true
			break
	_check(collected, "(f) il Cassone raccoglie il rottame (%d a bordo)" % _caravan.carried)
	module.set_active(false)
	_field.reset_to_base(vein_at, Vector2(2.0, 2.0))
	await _regather()


## Pala: con un rottamatore a 6 m e 5 rottami un argine alto almeno base + 0,9 a 1,5 m da lui,
## per un rottame; con la sola riserva per una riparazione nessun argine.
func _test_shovel(shovel: Machine) -> void:
	print("shovel")
	var tuning := _caravan.tuning
	var module := shovel.module(&"shovel") as ShovelModule
	var n_shovel := roundi(tuning.shovel_interval * Engine.physics_ticks_per_second)
	var sh := shovel.global_position
	var w := _side(shovel)
	var bank := sh + w * (6.0 - tuning.shovel_gap)
	_spawn_still(sh + w * 6.0)
	_check(_flat(bank) and module.clear_spot(bank, tuning.shovel_radius), "punto dell'argine in base e libero")
	var reserve := tuning.shovel_cost + tuning.repair_cost - 1
	_caravan.carried = reserve
	module.set_active(true)
	module._shovel_left = tuning.shovel_interval
	_check(await _no_write(n_shovel + 3, [bank]) and _caravan.carried == reserve,
		"%d rottami (sotto la riserva): nessun argine, nessun rottame speso" % reserve)
	_caravan.carried = 5
	module._shovel_left = tuning.shovel_interval
	await _frames(n_shovel + 3)
	_check(_caravan.carried == 5 - tuning.shovel_cost and _field.height_at(bank) >= _field.base_height_at(bank) + 0.9,
		"5 rottami: argine a %.2f m sulla base fra lui e la macchina, %d rottami a bordo" % [_field.delta_at(bank), _caravan.carried])
	module.set_active(false)
	_field.reset_to_base(bank, Vector2(2.0, 2.0))
	_caravan.carried = tuning.starting_scrap
	await _clear_enemies()


## Saldatore: +1 PV ogni `welder_interval` alla macchina danneggiata in raggio (non a se stesso);
## una guasta in raggio riparte dopo `welder_broken_seconds`, gratis, anche se intanto la si
## ripara a mano (Review Focus 2: la tenuta si azzera e non paga).
func _test_welder(welder: Machine, drill: Machine) -> void:
	print("welder")
	var tuning := _caravan.tuning
	var module := welder.module(&"welder") as WelderModule
	var hz := Engine.physics_ticks_per_second
	var n_heal := roundi(tuning.welder_interval * hz)
	var n_fix := roundi(tuning.welder_broken_seconds * hz)
	var nominal := roundi(tuning.repair_seconds * hz)
	var here := welder.global_position

	# (i) La Trivella ferma a 2 m, a 3 PV; il Saldatore a 2 PV non si salda da solo.
	drill.set_physics_process(false)
	_place_machine(drill, here + Vector3(0.0, 0.0, 2.0 * _toward_area_z(here)))
	drill.health = 3
	welder.health = 2
	_check(drill.state == Machine.State.OK and welder.state == Machine.State.OK, "Trivella a 3 PV e Saldatore a 2 PV, in ordine")
	module.set_active(true)
	module._heal_left = tuning.welder_interval
	var steps := await _steps_until_health(drill, 4, n_heal + 10)
	_check(steps >= n_heal - 2 and steps <= n_heal + 2, "una macchina a 3 PV entro 4 m sale a 4 in %d passi (%d attesi)" % [steps, n_heal])
	_check(welder.health == 2, "il Saldatore non salda se stesso (%d PV)" % welder.health)
	drill.set_physics_process(true)
	drill.health = drill.max_health
	welder.health = welder.max_health

	# (ii) Una guasta a 1,5 m dal giocatore e in raggio torna in ordine da sola, gratis.
	var spot := AREA + _planar_unit(here - AREA) * 1.5
	_check(Machine.planar_distance(spot, _player.global_position) <= tuning.repair_range
		and Machine.planar_distance(spot, here) <= tuning.welder_range, "il punto e in raggio di riparazione e di saldatura")
	var carried := _caravan.carried
	_place_machine(drill, spot)
	_break(drill)
	# La saldatura e appena scattata: con `welder_broken_seconds` multiplo di `welder_interval`
	# il +1 PV cadrebbe nel passo della riparazione. Il suo timer riparte un passo dopo.
	await _frames(1)
	module._heal_left = tuning.welder_interval
	steps = -1
	for k in n_fix + 10:
		await physics_frame
		if not drill.is_broken():
			steps = k + 1
			break
	_check(steps >= n_fix - 2 and steps <= n_fix + 2, "la guasta torna in ordine in %d passi (%d attesi)" % [steps, n_fix])
	_check(drill.health == ceili(drill.max_health * tuning.repair_health_fraction) and _caravan.carried == carried,
		"a %d PV, senza spendere (%d rottami)" % [drill.health, _caravan.carried])
	drill.module(&"drill").set_active(false)

	# (iii) Riparazione a mano in corso quando salda il Saldatore: si azzera e non paga.
	_caravan.carried = 3
	_place_machine(drill, spot)
	_break(drill)
	await _frames(n_fix - roundi(nominal * 2.0 / 3.0))
	_check(drill.is_broken() and _caravan.repair_target() == drill, "ancora guasta, bersaglio della riparazione")
	_player.interact_held = true
	var fixed := false
	for k in 80:
		await physics_frame
		if not drill.is_broken():
			fixed = true
			break
	_check(fixed and _caravan.repair_progress() > 0.5 and _caravan.carried == 3,
		"la salda il Saldatore a riparazione a mano in corso (%.2f), nessun rottame speso" % _caravan.repair_progress())
	await _frames(1)
	_check(_caravan.repair_progress() == 0.0 and _caravan.repairing_machine() == null, "la riparazione a mano si azzera")
	await _frames(nominal + 5)
	_check(_caravan.carried == 3, "e non paga (%d rottami)" % _caravan.carried)
	_player.interact_held = false
	drill.module(&"drill").set_active(false)
	module.set_active(false)
	drill.health = drill.max_health
	await _regather()


## Sirena: nei primi `siren_active` secondi del ciclo un rottamatore a 7 m le arriva vicino, poi
## non e piu tirato fino al ciclo dopo; boss e portatori in commissione non si tirano mai.
func _test_siren(siren: Machine) -> void:
	print("siren")
	var tuning := _caravan.tuning
	var module := siren.module(&"siren") as SirenModule
	var n_on := roundi(tuning.siren_active * Engine.physics_ticks_per_second)
	var n_cycle := roundi(tuning.siren_period * Engine.physics_ticks_per_second)
	var sr := siren.global_position
	var w := _side(siren)
	var z := Vector3(0.0, 0.0, _toward_area_z(sr))
	var pulled := _director.spawn_at(sr + w * 7.0)
	pulled.health = 9999
	pulled.speed_scale = 0.0
	var boss := Enemy.new()
	boss.self_driven = true
	_director.add_enemy(boss, sr + w * 5.0 + z * 1.5 + Vector3(0.0, Enemy.spawn_height(), 0.0))
	var carrier := _director.spawn_at(sr + w * 4.0 + z * 2.5)
	carrier.speed_scale = 0.0
	carrier.has_errand = true
	carrier.errand_point = carrier.global_position
	var all_in := true
	for enemy: Enemy in [pulled, boss, carrier]:
		all_in = all_in and Machine.planar_distance(enemy.global_position, sr) <= tuning.siren_range
	_check(all_in, "rottamatore, boss e portatore entro il raggio della Sirena")
	await _frames(1)
	var boss_at := boss.global_position
	var carrier_at := carrier.global_position
	module.set_active(true)
	module._cycle_time = 0.0
	siren.grant_invulnerability(10.0)
	await _frames(n_on - 1)
	_check(module.is_attracting() and Machine.planar_distance(pulled.global_position, sr) < 3.0,
		"nei primi %.0f s il rottamatore a 7 m le arriva vicino (%.2f m)" % [tuning.siren_active, Machine.planar_distance(pulled.global_position, sr)])
	_check(boss.drift == Vector3.ZERO and Machine.planar_distance(boss.global_position, boss_at) < 0.05
		and Machine.planar_distance(carrier.global_position, carrier_at) < 0.05, "il boss e il portatore in commissione non si tirano")
	await _frames(1)
	_check(not module.is_attracting(), "finiti i %.0f s non attira piu" % tuning.siren_active)
	await _frames(30)
	var stopped_at := pulled.global_position
	await _frames(n_cycle - n_on - 35)
	_check(Machine.planar_distance(pulled.global_position, stopped_at) < 0.05 and not module.is_attracting(),
		"nel resto del ciclo il rottamatore non e piu tirato")
	await _frames(5)
	_check(module.is_attracting(), "al ciclo dopo attira di nuovo")
	module.set_active(false)
	await _clear_enemies()


## Da guaste nessun modulo lavora: niente scritture, vena intatta, rottami e PV com'erano, la
## Sirena non attira.
func _test_broken_idle(drill: Machine, shovel: Machine, welder: Machine, siren: Machine) -> void:
	print("broken idle")
	var tuning := _caravan.tuning
	var n_shovel := roundi(tuning.shovel_interval * Engine.physics_ticks_per_second)
	var lead := _caravan.lead()
	var four: Array[Machine] = [drill, shovel, welder, siren]
	for each in four:
		each.modules[0].set_active(true)
	_place_machine(drill, AREA + Vector3(-8.0, 0.0, -2.0))
	_break(drill)
	var vein_at := drill.global_position + Vector3(-3.0, 0.0, 0.0)
	_scraps.add_vein(vein_at, 1.2, 4, _field.base_height_at(vein_at))
	_place_machine(shovel, AREA + Vector3(8.0, 0.0, -2.0))
	_break(shovel)
	_spawn_still(shovel.global_position + Vector3(6.0, 0.0, 0.0))
	_caravan.carried = 5
	_place_machine(welder, AREA + Vector3(-8.0, 0.0, 2.0))
	_break(welder)
	lead.set_physics_process(false)
	_place_machine(lead, welder.global_position + Vector3(0.0, 0.0, 2.0 * _toward_area_z(welder.global_position)))
	lead.health = 3
	_place_machine(siren, AREA + Vector3(8.0, 0.0, 2.0))
	_break(siren)
	var lured := _director.spawn_at(siren.global_position + Vector3(7.0, 0.0, 0.0))
	lured.health = 9999
	lured.speed_scale = 0.0
	var siren_module := siren.module(&"siren") as SirenModule
	_check(four.all(func(m: Machine) -> bool: return not m.modules[0].active), "guaste, le quattro macchine hanno il modulo spento")
	var scraps_before := _scraps.count()
	var lured_at := lured.global_position
	var quiet := true
	for k in n_shovel + 3:
		await physics_frame
		quiet = quiet and _run.write_queue.pending() == 0 and not siren_module.is_attracting()
	_check(quiet, "per %d passi nessuna scrittura e la Sirena non attira" % (n_shovel + 3))
	_check(_scraps.vein_scrap_left(vein_at) == 4 and _scraps.count() == scraps_before and _caravan.carried == 5,
		"la vena resta a 4, nessun rottame a terra, 5 rottami a bordo")
	_check(lead.health == 3 and Machine.planar_distance(lured.global_position, lured_at) < 0.05,
		"il capofila resta a 3 PV, il rottamatore non si muove")
	lead.set_physics_process(true)
	lead.health = lead.max_health
	for each in four:
		each.repair(1.0)
		each.modules[0].set_active(false)
	_scraps._veins.clear()
	await _clear_enemies()


# --- Forza dei moduli (piano B, scelta 4 di D-093), sulla seconda scena ------------------------

## Macchine di due moduli (forza 1,15): Torretta intervallo / forza; Calamita, Faro e Sirena
## raggio x forza; Trivella, Pala e Saldatore intervallo / forza (il Saldatore anche i 6 s sulle
## guaste); Cassone raggio di ricerca x forza. I moduli gia montati prendono la forza nuova
## (`set_power` riapplica il livello): attrattore e sorgente di luce seguono. Una piccola resta
## com'era.
func _test_power() -> void:
	print("power")
	var tuning := _caravan.tuning
	var p := 1.15
	for each in _caravan.machines.duplicate():
		if each != _caravan.lead():
			_caravan.remove_machine(each)
	var lead := _caravan.lead()
	_check(_caravan.machines.size() == 1 and is_equal_approx(lead.power, 1.0)
		and is_equal_approx(lead.cargo().pickup_radius(), tuning.pickup_radius_from_player)
		and is_equal_approx(lead.cargo().pickup_radius(), 6.0), "il Cassone da solo cerca a 6 m")
	_caravan.carried = 5
	var turret_machine := _add(&"turret")
	var beacon_machine := _add(&"beacon")
	var magnet_machine := _add(&"magnet")
	if turret_machine == null or beacon_machine == null or magnet_machine == null:
		return
	_check(_caravan.fuse(turret_machine, beacon_machine) and _caravan.fuse(lead, magnet_machine),
		"Torretta + Faro e Cassone + Calamita fusi")
	_check(is_equal_approx(turret_machine.power, p) and is_equal_approx(lead.power, p), "forza 1,15 su due moduli")
	var turret := turret_machine.module(&"turret") as TurretModule
	var beacon := turret_machine.module(&"beacon") as BeaconModule
	_check(is_equal_approx(turret.power, p) and is_equal_approx(beacon.power, p), "ogni modulo ha la forza della macchina")
	_check(is_equal_approx(turret.weapon().fire_interval, 0.9 / p),
		"Torretta: intervallo / forza (%.4f)" % turret.weapon().fire_interval)
	_check(is_equal_approx(beacon.radius(), _run.tuning.beacon_radius * p)
		and is_equal_approx(_run.light_field.radius_of(beacon.light_id), 11.0 * p),
		"Faro: raggio x forza, anche nel campo delle luci (%.3f)" % _run.light_field.radius_of(beacon.light_id))
	var magnet := lead.module(&"magnet") as MagnetModule
	_check(is_equal_approx(magnet.radius(), 2.5 * p) and is_equal_approx(_attractor_radius(lead), 2.5 * p),
		"Calamita: raggio x forza, anche l'attrattore (%.3f)" % _attractor_radius(lead))
	_check(is_equal_approx(lead.cargo().pickup_radius(), 6.0 * p) and lead.cargo().capacity == tuning.cargo_capacity,
		"Cassone: ricerca a 6 x forza, capienza invariata (%.3f)" % lead.cargo().pickup_radius())
	var drill_machine := _add(&"drill")
	var shovel_machine := _add(&"shovel")
	if drill_machine == null or shovel_machine == null:
		return
	_caravan.carried = 5
	_check(_caravan.fuse(drill_machine, shovel_machine), "Trivella + Pala fuse")
	var drill := drill_machine.module(&"drill") as DrillModule
	var shovel := drill_machine.module(&"shovel") as ShovelModule
	_check(is_equal_approx(drill.interval(), 4.0 / p) and is_equal_approx(shovel.interval(), 5.0 / p),
		"Trivella 4 / forza, Pala 5 / forza (%.4f, %.4f)" % [drill.interval(), shovel.interval()])
	_caravan.remove_machine(turret_machine)
	_caravan.remove_machine(drill_machine)
	var welder_machine := _add(&"welder")
	var siren_machine := _add(&"siren")
	if welder_machine == null or siren_machine == null:
		return
	_caravan.carried = 5
	_check(_caravan.fuse(welder_machine, siren_machine), "Saldatore + Sirena fusi")
	var welder := welder_machine.module(&"welder") as WelderModule
	var siren := welder_machine.module(&"siren") as SirenModule
	_check(is_equal_approx(welder.heal_interval(), 3.0 / p) and is_equal_approx(welder.broken_seconds(), 6.0 / p),
		"Saldatore 3 / forza e 6 / forza (%.4f, %.4f)" % [welder.heal_interval(), welder.broken_seconds()])
	_check(is_equal_approx(siren.range_m(), 8.0 * p), "Sirena 8 x forza (%.3f)" % siren.range_m())
	var lone := _add(&"turret")
	if lone == null:
		return
	var lone_turret := lone.module(&"turret") as TurretModule
	_check(is_equal_approx(lone.power, 1.0) and is_equal_approx(lone_turret.weapon().fire_interval, 0.9),
		"una piccola resta com'era (%.4f)" % lone_turret.weapon().fire_interval)


# --- Combinazioni (piano B, scelta 7 di D-093), sulla terza scena --------------------------------

## Le sei combinazioni su macchine fuse con `caravan.fuse`, una alla volta (la carovana tiene al
## piu sei moduli). Il capofila resta fermo: non va a raccogliere i rottami dei casi.
func _test_combos() -> void:
	print("combos")
	_scraps._veins.clear()
	_scraps.take_near(AREA, 40.0, _scraps.count())
	_place_player_solved(AREA)
	var lead := _caravan.lead()
	lead.set_physics_process(false)
	_place_machine(lead, AREA + LEAD_OFFSET)
	await _test_combo_reflector()
	await _test_combo_trap()
	await _test_combo_both()
	await _test_combo_armored_bait()
	await _test_combo_mobile_mixer()
	await _test_combo_extractor()
	await _test_combo_dozer()
	await _test_combo_off_when_broken()
	lead.set_physics_process(true)


## Macchina fusa coi moduli [param ids] nell'ordine: la prima aggiunta e la base, le altre vi
## entrano una per volta (i rottami per pagare la fusione li mette il test).
func _fused(ids: Array[StringName]) -> Machine:
	var base := _add(ids[0])
	if base == null:
		return null
	for k in range(1, ids.size()):
		var other := _add(ids[k])
		_caravan.carried = _caravan.capacity
		if other == null or not _caravan.fuse(base, other):
			_check(false, "fusione di %s" % ids[k])
			return null
	_check(base.module_ids() == ids, "macchina fusa %s" % [base.module_ids()])
	return base


## Danno del primo chiodo della Torretta di [param machine] su un rottamatore fermo in
## [param at], -1 se entro 3 s non lo colpisce. Poi niente nemici e nessun chiodo in volo.
func _first_nail_damage(machine: Machine, at: Vector3) -> int:
	var gun := (machine.module(&"turret") as TurretModule).weapon()
	var enemy := _spawn_still(at)
	var start := enemy.health
	var dealt := -1
	for i in 180:
		await physics_frame
		if is_instance_valid(enemy) and enemy.health < start:
			dealt = start - enemy.health
			break
	_director.clear_horde()
	for i in 120:
		await physics_frame
		if gun.nail_count() == 0:
			break
	await _frames(5)
	return dealt


## Torretta ferma nel punto del caso, col tempo della Sirena congelato (la macchina non fa passi).
func _still_turret(ids: Array[StringName]) -> Machine:
	var machine := _fused(ids)
	if machine == null:
		return null
	machine.set_physics_process(false)
	_place_machine(machine, AREA + Vector3(3.0, 0.0, 2.0))
	return machine


## Riflettore: Torretta + Faro, rottamatore entro il raggio del Faro (e della Torretta): un
## chiodo toglie 2 x weapon_damage.
func _test_combo_reflector() -> void:
	print("combo reflector")
	var damage := _run.tuning.weapon_damage
	var machine := _still_turret([&"turret", &"beacon"])
	if machine == null:
		return
	var beacon := machine.module(&"beacon") as BeaconModule
	var at := machine.global_position + Vector3(5.0, 0.0, 0.0)
	_check(machine.has_combo(&"reflector") and beacon.active and 5.0 < beacon.radius(),
		"Riflettore formato, rottamatore a 5 m nel raggio del Faro (%.2f m)" % beacon.radius())
	var dealt := await _first_nail_damage(machine, at)
	_check(dealt == 2 * damage, "Riflettore: un chiodo toglie %d (2 x %d)" % [dealt, damage])
	# Il Faro (12,65 m) arriva oltre la portata della Torretta (8 m): la scala si chiede direttamente.
	var turret := machine.module(&"turret") as TurretModule
	var far := _spawn_still(machine.global_position + Vector3(beacon.radius() + 0.5, 0.0, 0.0))
	var near := _spawn_still(at)
	_check(is_equal_approx(turret._combo_scale(far), 1.0) and is_equal_approx(turret._combo_scale(near), _caravan.tuning.combo_damage_scale),
		"oltre il raggio del Faro scala 1, dentro %.1f" % turret._combo_scale(near))
	await _clear_enemies()
	_caravan.remove_machine(machine)
	await _frames(2)


## Trappola: Torretta + Sirena; nella fase attiva un rottamatore attirato a 6 m prende il doppio,
## fuori fase il danno normale.
func _test_combo_trap() -> void:
	print("combo trap")
	var tuning := _caravan.tuning
	var damage := _run.tuning.weapon_damage
	var machine := _still_turret([&"turret", &"siren"])
	if machine == null:
		return
	var siren := machine.module(&"siren") as SirenModule
	var at := machine.global_position + Vector3(6.0, 0.0, 0.0)
	siren._cycle_time = 0.0
	_check(machine.has_combo(&"trap") and siren.is_attracting() and 6.0 < siren.range_m(),
		"Trappola formata, Sirena che attira, rottamatore a 6 m nel suo raggio (%.2f m)" % siren.range_m())
	var dealt := await _first_nail_damage(machine, at)
	_check(dealt == 2 * damage, "Trappola nella fase attiva: un chiodo toglie %d (2 x %d)" % [dealt, damage])
	siren._cycle_time = tuning.siren_active + 0.1
	_check(not siren.is_attracting(), "fuori fase la Sirena non attira")
	dealt = await _first_nail_damage(machine, at)
	_check(dealt == damage, "Trappola fuori fase: danno normale (%d)" % dealt)
	_caravan.remove_machine(machine)
	await _frames(2)


## Riflettore e Trappola insieme: rottamatore illuminato e attirato, 4 x weapon_damage.
func _test_combo_both() -> void:
	print("combo both")
	var damage := _run.tuning.weapon_damage
	var machine := _still_turret([&"turret", &"beacon", &"siren"])
	if machine == null:
		return
	var siren := machine.module(&"siren") as SirenModule
	siren._cycle_time = 0.0
	_check(machine.has_combo(&"reflector") and machine.has_combo(&"trap") and siren.is_attracting(),
		"Torretta + Faro + Sirena: Riflettore e Trappola, la Sirena attira")
	var dealt := await _first_nail_damage(machine, machine.global_position + Vector3(6.0, 0.0, 0.0))
	_check(dealt == 4 * damage, "i due raddoppi si moltiplicano: %d (4 x %d)" % [dealt, damage])
	_caravan.remove_machine(machine)
	await _frames(2)


## Esca blindata: Saldatore + Sirena; mentre attira due colpi da 1 a 0,9 s tolgono 1 PV (un solo
## `damaged`, da 1), a Sirena ferma 2.
func _test_combo_armored_bait() -> void:
	print("combo armored bait")
	var tuning := _caravan.tuning
	var gap := roundi(0.9 * Engine.physics_ticks_per_second)
	var machine := _fused([&"welder", &"siren"])
	if machine == null:
		return
	await _settle(machine)
	var siren := machine.module(&"siren") as SirenModule
	var hits: Array[int] = []
	var on_damaged := func(amount: int) -> void: hits.append(amount)
	machine.damaged.connect(on_damaged)
	machine._hit_cooldown_left = 0.0
	siren._cycle_time = 0.0
	var start := machine.health
	_check(machine.has_combo(&"armored_bait") and is_equal_approx(machine.hit_scale(), tuning.combo_hit_scale),
		"Esca blindata formata: con la Sirena che attira la scala del danno e %.2f" % machine.hit_scale())
	var first := machine.take_hit(1)
	await _frames(gap)
	var attracting := siren.is_attracting()
	var second := machine.take_hit(1)
	_check(first and second and attracting and machine.health == start - 1,
		"Sirena che attira: due colpi da 1 a 0,9 s tolgono 1 PV (%d -> %d)" % [start, machine.health])
	_check(hits.size() == 1 and hits[0] == 1, "un solo damaged, da 1 PV (%s)" % [hits])
	await _frames(gap)
	hits.clear()
	siren._cycle_time = tuning.siren_active + 0.01
	start = machine.health
	_check(not siren.is_attracting() and is_equal_approx(machine.hit_scale(), 1.0), "Sirena ferma: scala 1")
	first = machine.take_hit(1)
	await _frames(gap)
	attracting = siren.is_attracting()
	second = machine.take_hit(1)
	_check(first and second and not attracting and machine.health == start - 2,
		"Sirena ferma: due colpi da 1 tolgono 2 PV (%d -> %d)" % [start, machine.health])
	_check(hits.size() == 2 and hits[0] == 1 and hits[1] == 1, "due damaged da 1 (%s)" % [hits])
	machine.damaged.disconnect(on_damaged)
	_caravan.remove_machine(machine)
	await _frames(2)


## Betoniera mobile: Pala + Cassone senza rottami, rottamatore a 5 m: l'argine sale lo stesso,
## gratis e senza riserva.
func _test_combo_mobile_mixer() -> void:
	print("combo mobile mixer")
	var tuning := _caravan.tuning
	var machine := _fused([&"shovel", &"cargo"])
	if machine == null:
		return
	await _settle(machine)
	var module := machine.module(&"shovel") as ShovelModule
	var d := machine.global_position
	var w := _side(machine)
	var bank := d + w * (5.0 - tuning.shovel_gap)
	_spawn_still(d + w * 5.0)
	_caravan.carried = 0
	_check(machine.has_combo(&"mobile_mixer") and _flat(bank) and module.clear_spot(bank, tuning.shovel_radius)
		and _caravan.carried == 0, "Betoniera mobile formata, 0 rottami, punto dell'argine in base e libero")
	module._shovel_left = 0.0
	await _frames(1)
	var queued := _run.write_queue.pending() > 0
	await _drain()
	_check(queued and _field.height_at(bank) >= _field.base_height_at(bank) + 0.9,
		"con 0 rottami l'argine sale a %.2f m sulla base" % _field.delta_at(bank))
	_check(_caravan.carried == 0, "nessun rottame speso (%d a bordo)" % _caravan.carried)
	_field.reset_to_base(bank, Vector2(2.0, 2.0))
	_caravan.remove_machine(machine)
	await _clear_enemies()


## Estrattore: Trivella + Calamita; dopo la buca i tre rottami a terra entro 3 m vanno nei
## Cassoni, quello a 4,5 m resta; poi il rottame cavato da una vena entra subito a bordo.
func _test_combo_extractor() -> void:
	print("combo extractor")
	var tuning := _caravan.tuning
	var machine := _fused([&"drill", &"magnet"])
	if machine == null:
		return
	await _settle(machine)
	var module := machine.module(&"drill") as DrillModule
	var d := machine.global_position
	var w := _side(machine)
	var hole := d + w * 3.0
	_spawn_still(d + w * 4.0)
	for offset: Vector3 in [Vector3(0.0, 0.0, 1.2), Vector3(0.0, 0.0, -1.2), w * 1.5, w * 4.5]:
		_scraps.spawn_on_ground(hole + offset)
	_caravan.carried = 0
	var scraps_before := _scraps.count()
	_check(machine.has_combo(&"extractor") and _flat(hole) and module.clear_spot(hole, tuning.drill_radius)
		and _scraps.positions_near(hole, tuning.extractor_radius).size() == 3 and _caravan.room() >= 3,
		"Estrattore formato, buca in base e libera, tre rottami entro 3 m, posto a bordo")
	module._drill_left = 0.0
	await _frames(2)
	_check(_caravan.carried == 3 and _scraps.count() == scraps_before - 3
		and _scraps.positions_near(hole + w * 4.5, 0.5).size() == 1,
		"dopo la buca 3 rottami a bordo (%d), quello a 4,5 m resta a terra" % _caravan.carried)
	await _drain()
	_check(absf(_field.height_at(hole) - (_field.base_height_at(hole) - tuning.drill_depth)) < 0.05,
		"e la buca c'e (%.2f m sulla base)" % _field.delta_at(hole))
	_field.reset_to_base(hole, Vector2(2.0, 2.0))
	await _clear_enemies()
	var vein_at := d + w * 3.0
	_scraps.add_vein(vein_at, 1.2, 4, _field.base_height_at(vein_at))
	scraps_before = _scraps.count()
	module._drill_left = 0.0
	await _frames(2)
	_check(_scraps.vein_scrap_left(vein_at) == 3 and _caravan.carried == 4 and _scraps.count() == scraps_before,
		"dalla vena un rottame dritto a bordo (%d), nessuno a terra" % _caravan.carried)
	_scraps._veins.clear()
	_scraps.take_near(AREA, 40.0, _scraps.count())
	_caravan.carried = tuning.starting_scrap
	_caravan.remove_machine(machine)
	await _frames(2)


## Ruspa: Trivella + Pala che percorre almeno 6 m in piano (il giocatore si sposta di 8 m, la
## macchina lo segue): almeno due fossati con l'argine a lato, nessuna scrittura entro
## `keep_clear` dal giocatore o da una macchina, la pedana protetta sulla scia intatta.
func _test_combo_dozer() -> void:
	print("combo dozer")
	var tuning := _caravan.tuning
	var queue := _run.write_queue
	var machine := _fused([&"drill", &"shovel"])
	if machine == null:
		return
	await _settle(machine)
	var start := machine.global_position
	# La pedana: un disco protetto attorno alla partenza, dove cadrebbe il primo fossato (0,8 m
	# dietro il punto di partenza).
	var pad_at := start
	var snapshot := _field.snapshot_protected(pad_at, 1.2)
	_field.set_protected(pad_at, 1.2, true)
	var pad_points: Array[Vector3] = [pad_at]
	# Anello a 0,4 m: i quattro vertici (passo 0,5 m) attorno a ogni punto stanno nel disco.
	for k in 8:
		pad_points.append(pad_at + Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0)) * 0.4)
	var pad_heights: Array[float] = []
	for p in pad_points:
		pad_heights.append(_field.height_at(p))
	_check(machine.has_combo(&"dozer") and _flat(start) and _flat(start + Vector3(8.0, 0.0, 0.0)),
		"Ruspa formata, in piano")
	_place_player_solved(AREA + Vector3(8.0, 0.0, 0.0))
	var ditches: Array[Vector3] = []
	var banks: Array[Vector3] = []
	var seen: Dictionary[Vector3, bool] = {}
	var clear := true
	var nearest_pad := INF
	for i in roundi(5.0 * Engine.physics_ticks_per_second):
		await physics_frame
		nearest_pad = minf(nearest_pad, Machine.planar_distance(machine.global_position, pad_at))
		for job: Dictionary in queue._jobs:
			var center: Vector3 = job.center
			if seen.has(center):
				continue
			seen[center] = true
			clear = clear and Machine.planar_distance(center, _player.global_position) > tuning.keep_clear
			for each in _caravan.machines:
				clear = clear and Machine.planar_distance(center, each.global_position) > tuning.keep_clear
			if is_equal_approx(float(job.target), _field.base_height_at(center) - tuning.dozer_ditch_depth):
				ditches.append(center)
			elif is_equal_approx(float(job.target), _field.base_height_at(center) + tuning.dozer_bank_height):
				banks.append(center)
	var travelled := Machine.planar_distance(machine.global_position, start)
	await _drain()
	_check(travelled >= 6.0, "la macchina ha percorso %.2f m" % travelled)
	_check(ditches.size() >= 2 and banks.size() >= 2, "%d fossati e %d argini lungo la scia" % [ditches.size(), banks.size()])
	_check(clear, "nessuna scrittura entro keep_clear dal giocatore o da una macchina")
	# Pennello di 0,8 m su vertici ogni 0,5 m: fuori da un vertice il centro arriva a circa tre
	# quarti della quota piena (la campana), quindi si chiede almeno il 60 %.
	var deep := true
	var shallowest := -INF
	for p in ditches:
		shallowest = maxf(shallowest, _field.delta_at(p))
		deep = deep and _field.delta_at(p) <= -0.6 * tuning.dozer_ditch_depth
	var high := true
	var lowest := INF
	for p in banks:
		lowest = minf(lowest, _field.delta_at(p))
		high = high and _field.delta_at(p) >= 0.6 * tuning.dozer_bank_height
	_check(not ditches.is_empty() and deep,
		"fossati scavati verso %.1f m (il meno profondo a %.2f m)" % [tuning.dozer_ditch_depth, shallowest])
	_check(not banks.is_empty() and high,
		"argini alzati verso %.1f m (il piu basso a %.2f m)" % [tuning.dozer_bank_height, lowest])
	var intact := true
	for k in pad_points.size():
		intact = intact and _field.height_at(pad_points[k]) == pad_heights[k]
	_check(nearest_pad < 1.2 and intact,
		"la scia parte dalla pedana (%.2f m), che resta intatta" % nearest_pad)
	_field.restore_protected(snapshot)
	for p in ditches + banks:
		_field.reset_to_base(p, Vector2(1.5, 1.5))
	_place_player_solved(AREA)
	await _test_dozer_bank_guard(machine)
	_caravan.remove_machine(machine)
	await _frames(2)


## L'argine della Ruspa non abbassa il terreno piu alto (`level` abbassa anche): un tratto di
## 1,6 m lungo +X a passo spento, chiamato a mano. Con un cumulo di 1 m nel disco dove cadrebbe
## il suo, il cumulo resta alto com'era; in terreno aperto l'argine sale.
func _test_dozer_bank_guard(machine: Machine) -> void:
	var tuning := _caravan.tuning
	var module := machine.module(&"drill") as DrillModule
	machine.set_physics_process(false)
	var here := AREA + Vector3(-5.0, 0.0, 0.0)
	_place_machine(machine, here)
	var point := here - Vector3(tuning.keep_clear + tuning.dozer_ditch_radius, 0.0, 0.0)
	# Verso +X: la destra e +Z.
	var bank := point + Vector3(0.0, 0.0, tuning.dozer_bank_offset)
	_check(_flat(point) and _flat(bank) and module.clear_spot(point, tuning.dozer_ditch_radius)
		and module.clear_spot(bank, tuning.dozer_bank_radius), "punto del fossato e dell'argine in base e liberi")
	# Un cumulo di 1 m su un vertice a 0,45 m dal centro dell'argine, dal lato opposto al fossato:
	# il centro resta sotto base + `dozer_bank_height` (senza controllo l'argine si alzerebbe), la
	# cima sta nel disco dell'argine.
	var bump := Vector3(snappedf(bank.x, 0.5), 0.0, snappedf(bank.z + 0.45, 0.5))
	_field.sculpt(bump, 0.7, 1.0)
	var samples: Array[Vector3] = [bump, bump + Vector3(0.25, 0.0, 0.0), bump + Vector3(-0.25, 0.0, 0.0)]
	var before: Array[float] = []
	for p in samples:
		before.append(_field.height_at(p))
	_check(Machine.planar_distance(bump, bank) < tuning.dozer_bank_radius
		and _field.delta_at(bank) < tuning.dozer_bank_height - 0.05 and _field.delta_at(bump) > tuning.dozer_bank_height + 0.2,
		"cumulo di %.2f m nel disco dell'argine, centro a %.2f m" % [_field.delta_at(bump), _field.delta_at(bank)])
	module._dozer_from = machine.global_position - Vector3(1.6, 0.0, 0.0)
	module._tick_dozer()
	await _drain()
	var kept := true
	for k in samples.size():
		kept = kept and _field.height_at(samples[k]) == before[k]
	_check(kept, "il cumulo resta a %.2f m: nessun argine che lo abbassi" % _field.delta_at(bump))
	_field.reset_to_base(point, Vector2(1.5, 1.5))
	_field.reset_to_base(bank, Vector2(1.5, 1.5))
	module._dozer_from = machine.global_position - Vector3(1.6, 0.0, 0.0)
	module._tick_dozer()
	await _drain()
	_check(_field.delta_at(bank) >= 0.6 * tuning.dozer_bank_height,
		"in terreno aperto l'argine sale a %.2f m" % _field.delta_at(bank))
	_field.reset_to_base(point, Vector2(1.5, 1.5))
	_field.reset_to_base(bank, Vector2(1.5, 1.5))


## Guasta: `combos()` restano, `has_combo` e falso per tutte; la Torretta spenta non spara. Riparata
## le combinazioni tornano.
func _test_combo_off_when_broken() -> void:
	print("combo off when broken")
	var machine := _still_turret([&"turret", &"beacon", &"siren", &"drill", &"shovel"])
	if machine == null:
		return
	var combos := machine.combos()
	_check(combos.size() == 3 and combos.all(func(id: StringName) -> bool: return machine.has_combo(id)),
		"cinque moduli, tre combinazioni attive (%s)" % [combos])
	_break(machine)
	_check(machine.combos().size() == 3 and not combos.any(func(id: StringName) -> bool: return machine.has_combo(id)),
		"guasta: has_combo falso per tutte")
	var gun := (machine.module(&"turret") as TurretModule).weapon()
	gun.fired.connect(_on_turret_fired)
	_shots = 0
	var enemy := _spawn_still(machine.global_position + Vector3(5.0, 0.0, 0.0))
	await _frames(90)
	_check(gun.shooter == null and _shots == 0 and is_instance_valid(enemy) and enemy.health == 9999,
		"la Torretta spenta non spara (%d colpi)" % _shots)
	gun.fired.disconnect(_on_turret_fired)
	machine.repair(1.0)
	_check(machine.has_combo(&"reflector") and machine.has_combo(&"trap") and machine.has_combo(&"dozer"),
		"riparata, le combinazioni tornano")
	_caravan.remove_machine(machine)
	await _clear_enemies()


## Passi finche la coda delle scritture e vuota (al piu 2 s).
func _drain() -> void:
	for i in 120:
		await physics_frame
		if _run.write_queue.pending() == 0:
			return


## Come `_place_player`, poi risolve il campo di percorso dal punto nuovo (machine_damage_tests).
func _place_player_solved(at: Vector3) -> void:
	_place_player(at)
	_path.solve()


## Guasta subito, senza immunita ne invulnerabilita (subito dopo il posizionamento: una macchina
## in ordine tornerebbe al suo posto fra un passo e l'altro).
func _break(machine: Machine) -> void:
	machine._hit_cooldown_left = 0.0
	machine._invulnerable_left = 0.0
	_check(machine.take_hit(machine.health) and machine.is_broken(), "%s guasto" % machine.primary_module_id())


## Tutte le macchine al loro posto attorno al giocatore.
func _gather_machines() -> void:
	for each in _caravan.machines:
		_place_machine(each, _caravan.slot_target(each))


## Di nuovo tutte al loro posto, ferme. Prima il capofila al suo punto: se e andato a raccogliere,
## i posti delle altre ruoterebbero con lui.
func _regather() -> void:
	_place_machine(_caravan.lead(), AREA + LEAD_OFFSET)
	_gather_machines()
	for each in _caravan.machines:
		await _settle(each)


## Rottamatore fermo (stordito a lungo) e robusto.
func _spawn_still(at: Vector3) -> Enemy:
	var enemy := _director.spawn_at(at)
	enemy.health = 9999
	enemy.stun(60.0)
	return enemy


func _clear_enemies() -> void:
	_director.clear_horde()
	await _frames(20)


## Aspetta che [param machine] stia ferma per 10 passi (al piu 5 s).
func _settle(machine: Machine) -> bool:
	var still := 0
	for i in 300:
		await physics_frame
		still = still + 1 if Vector2(machine.velocity.x, machine.velocity.z).length() < 0.05 else 0
		if still >= 10:
			return true
	return false


## Passi fino a che la vita arriva a [param health], -1 se non ci arriva entro [param limit].
func _steps_until_health(machine: Machine, health: int, limit: int) -> int:
	for i in limit:
		await physics_frame
		if machine.health == health:
			return i
	return -1


## Lato del caso: +-X secondo la macchina rispetto ad AREA (-X entro 0,5 m), cosi i punti
## restano con z fra 12 e 20.
func _side(machine: Machine) -> Vector3:
	var dx := machine.global_position.x - AREA.x
	return Vector3(signf(dx) if absf(dx) >= 0.5 else -1.0, 0.0, 0.0)


## Verso di AREA.z lungo Z da [param p] (-1 se e gia li).
func _toward_area_z(p: Vector3) -> float:
	var dz := AREA.z - p.z
	return signf(dz) if absf(dz) > 0.01 else -1.0


func _planar_unit(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


## Il suolo in [param p] e alla base (entro 5 cm).
func _flat(p: Vector3) -> bool:
	return absf(_field.delta_at(p)) < 0.05


## Per [param steps] passi nessuna scrittura in coda (controllata a ogni passo), e alla fine le
## quote di [param points] identiche a prima.
func _no_write(steps: int, points: Array) -> bool:
	var before: Array[float] = []
	for p in points:
		before.append(_field.height_at(p))
	var quiet := true
	for i in steps:
		await physics_frame
		quiet = quiet and _run.write_queue.pending() == 0
	for i in points.size():
		quiet = quiet and _field.height_at(points[i]) == before[i]
	return quiet
