extends SceneTree
## Suite del terremoto del quartiere (D-075) sul rilievo continuo (D-085): programmazione,
## preavviso con faglia vicina al giocatore, scossa che alza una cresta di pennellate con
## un solco a fianco risparmiando giocatore, macchina della carovana e boss, rottamatori travolti,
## lampioni caduti, rottami che rotolano, intervallo successivo, opzione di avvio.
##   godot_console --headless --path godot --script res://tests/quake_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")
const RailwayScene := preload("res://scenes/main/railway_run.tscn")

var _failures := 0
var _scene: Node3D
var _run: ArenaRun
var _quake: QuakeEvent
var _field: TerrainField
var _player: PlayerCharacter
var _caravan: Caravan
## Il capofila della carovana (il compagno di oggi).
var _machine: Machine
var _director: EnemyDirector
var _weapon: AutoWeapon
var _hud: RunHud
var _lamps: LampField
var _scrap: ScrapField
var _audio: RunAudio


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_quake = _scene.get_node(^"QuakeEvent")
	_field = _scene.get_node(^"TerrainField")
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_director = _scene.get_node(^"EnemyDirector")
	_weapon = _scene.get_node(^"PlayerWeapon")
	_hud = _scene.get_node(^"RunHud")
	_lamps = _scene.get_node(^"LampField")
	_scrap = _scene.get_node(^"ScrapField")
	_audio = _scene.get_node(^"RunAudio")
	_director.spawning = false
	await _frames(5)
	# La macchina nasce nel _ready della carovana.
	_machine = _caravan.lead()
	_weapon.set_physics_process(false)
	_test_setup()
	await _test_warning()
	await _test_shake()
	await _test_crest_lifts_player_and_machine()
	_test_options()
	await _test_empty_fault_is_skipped()
	await _test_railway_has_no_quake()
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


func _place(body: Node3D, at: Vector3, y: float) -> void:
	body.global_position = Vector3(at.x, _field.height_at(at) + y, at.z)
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	body.reset_physics_interpolation()


func _test_setup() -> void:
	print("setup")
	_check(_run.quake_event == _quake and _quake.is_enabled(), "il terremoto e collegato alla regia")
	# D-097: un solo evento di serie, a un istante casuale nella finestra prima del boss.
	var end := _run.boss_call_at - _run.tuning.world_events_boss_margin
	_check(_run.world_event_plan.size() == 1 and _quake.next_at >= _run.tuning.world_events_start_seconds and _quake.next_at <= end,
		"un terremoto casuale fra %.0f e %.0f s (%.0f)" % [_run.tuning.world_events_start_seconds, end, _quake.next_at])
	_check(_quake.queued_times().is_empty(), "nessun altro terremoto dopo il primo")
	_check(_quake.state == QuakeEvent.State.IDLE and not _hud.is_boss_warning_visible(), "all'inizio nessun terremoto e nessun annuncio")
	_check(_audio.has_sound(&"quake_rumble"), "il brontolio esiste nella libreria")


func _test_warning() -> void:
	print("warning")
	_place(_player, Vector3(0.0, 0.0, 0.0), 0.88)
	# Il disco di partenza e protetto nei primi 10 s: qui lo si toglie subito, cosi la
	# faglia ha tutte le sue pennellate.
	_run._start_protect_left = 0.0
	_field.set_protected(Vector3.ZERO, _field.tuning.start_protected_radius_m, false)
	# Faglia deterministica: il seme della run e casuale, quello dell'evento qui no.
	_quake.rng.seed = 20261010
	_quake.warning_seconds = 3.0
	_quake.next_at = _run.elapsed + 3.5
	await _frames(40)
	_check(_quake.state == QuakeEvent.State.WARNING, "entro il preavviso il terremoto e annunciato")
	var points := _quake.fault_points.size()
	_check(points == _quake.length_cells, "faglia di %d pennellate" % points)
	var distance := Vector2(_quake.fault_center.x, _quake.fault_center.z).length()
	_check(distance >= _quake.distance_min - 0.01 and distance <= _quake.distance_max + 0.01,
		"centro della faglia a %.1f m dal giocatore" % distance)
	var all_inside := true
	var spaced := true
	for i in _quake.fault_points.size():
		var p: Vector3 = _quake.fault_points[i]
		all_inside = all_inside and absf(p.x) <= _field.half_extent() and absf(p.z) <= _field.half_extent()
		if i > 0:
			spaced = spaced and absf(p.distance_to(_quake.fault_points[i - 1]) - QuakeEvent.FAULT_STEP) < 0.01
	_check(all_inside and spaced, "pennellate dentro il rilievo, a passo di %.1f m" % QuakeEvent.FAULT_STEP)
	_check(_hud.is_boss_warning_visible() and _hud.event_warning_text().begins_with("TERREMOTO"), "annuncio a schermo: %s" % _hud.event_warning_text())
	_check(_audio.play_count(&"quake_rumble") >= 1, "brontolio al preavviso")


func _test_shake() -> void:
	print("shake")
	var fault := _quake.fault_points
	# Sulla faglia: un lampione, un rottame, un rottamatore, il giocatore, la macchina.
	# Giocatore e macchina in fondo alla faglia, lontani dal rottamatore.
	var enemy_point: Vector3 = fault[2]
	var scrap_point: Vector3 = fault[6]
	var player_point: Vector3 = fault[fault.size() - 2]
	var machine_point: Vector3 = fault[fault.size() - 1]
	# Una pennellata su suolo gia piano (la faglia puo attraversare l'argine del cortile).
	var crest_point: Vector3 = fault[9]
	for i in range(6, fault.size() - 3):
		var candidate: Vector3 = fault[i]
		if absf(_field.delta_at(candidate)) < 0.2 and absf(_field.delta_at(candidate + _quake.fault_side() * QuakeEvent.FAULT_STEP)) < 0.2:
			crest_point = candidate
			break
	_caravan.add_scrap(3)
	var lamp_point := Vector3.INF
	for i in [4, 5, 3]:
		var candidate: Vector3 = fault[i]
		_place(_machine, candidate + Vector3(1.0, 0.0, 1.0), 0.3)
		if _lamps.place_at(candidate):
			lamp_point = candidate
			break
	_check(_lamps.count() == 1, "lampione piazzato sulla faglia")
	_scrap.spawn_on_ground(scrap_point)
	var scrap_before := _scrap.count()
	# Rottamatori fermi (speed_scale 0): il test misura la scossa, non la camminata.
	var enemy := _director.spawn_at(enemy_point)
	enemy.speed_scale = 0.0
	var kills_before := _director.kills
	# Fuori dalla faglia ma vicino al giocatore: oltre il guinzaglio (40 m) il direttore lo
	# riporterebbe su un punto casuale dell'anello, con alcuni semi della run proprio sulla
	# faglia (seme 1026822462: era a 41,7 m dal giocatore).
	var far := player_point + _quake.fault_side() * 10.0
	var bystander := _director.spawn_at(far)
	bystander.speed_scale = 0.0
	var leashed_before := _director.leashed
	_place(_player, player_point, 0.88)
	_player._invulnerable_left = 0.0
	var health_before := _player.health
	_place(_machine, machine_point, 0.3)
	var next_before := _quake.next_at
	var started := [false]
	_quake.quake_started.connect(func(_center: Vector3) -> void: started[0] = true)
	# Preavviso restante (circa 3 s) piu scossa (18 pennellate a 14 al secondo): fino a 10 s.
	for i in 600:
		await physics_frame
		if _quake.quakes == 1:
			break
	_check(started[0] and _quake.quakes == 1 and _quake.state == QuakeEvent.State.IDLE, "la scossa e avvenuta e finita")
	_check(not _hud.is_boss_warning_visible(), "annuncio tolto alla scossa")
	_check(_field.delta_at(crest_point) > 0.8, "cresta alzata sulla faglia (%.2f)" % _field.delta_at(crest_point))
	var furrow := crest_point + _quake.fault_side() * 2.4
	_check(_field.delta_at(furrow) < -0.2, "solco a fianco della cresta (%.2f)" % _field.delta_at(furrow))
	_check(_quake.volume_moved > 20.0, "volume spostato contato (%.1f m3)" % _quake.volume_moved)
	# Giocatore e macchina risparmiano la propria pennellata: fino a quattro non alzate.
	var most := fault.size() - 1
	_check(_quake.cells_raised >= most - 3 and _quake.cells_raised <= most, "pennellate alzate lungo la faglia: %d su %d" % [_quake.cells_raised, fault.size()])
	_check(_field.delta_at(player_point) < 0.5, "il punto del giocatore e risparmiato (%.2f)" % _field.delta_at(player_point))
	_check(_player.health == health_before - _run.tuning.quake_player_damage and _quake.player_hits == 1,
		"giocatore sulla faglia colpito: %d -> %d" % [health_before, _player.health])
	_check(_field.delta_at(_machine.global_position) < 0.5, "il punto della macchina e risparmiato")
	_check((not is_instance_valid(enemy) or enemy.is_dead) and _director.kills == kills_before + 1 and _quake.enemies_hit == 1,
		"rottamatore sulla faglia travolto e contato")
	_check(is_instance_valid(bystander) and not bystander.is_dead and _director.leashed == leashed_before, "rottamatore lontano illeso e rimasto al suo posto")
	_check(_lamps.count() == 0, "lampione sulla faglia caduto")
	var resting := true
	for position in _scrap.positions_near(scrap_point, 8.0):
		resting = resting and absf(position.y - (_field.height_at(position) + ScrapField.SCRAP_SIZE)) < 0.1
	_check(_scrap.count() >= scrap_before and resting, "rottami in superficie, nessuno sepolto (%d)" % _scrap.count())
	_check(_quake.next_at == INF and next_before > 0.0, "finito il terremoto, nessun altro in programma")
	_check(_audio.play_count(&"quake_rumble") >= 2, "brontolio anche alla scossa")


## Audit R-02: giocatore e macchine sono risparmiati solo entro HIT_RADIUS, ma la cresta ha
## raggio CREST_RADIUS: appena fuori il suolo sale sotto di loro e va riappoggiati, come i nemici.
func _test_crest_lifts_player_and_machine() -> void:
	print("crest lifts player and machine")
	var q := Vector3(-30.0, 0.0, 30.0)
	_field.level(q, 6.0, _field.base_height_at(q), 1.0)
	_field.set_protected(q, 6.0, false)
	# Dal lato opposto al solco (che sta su `fault_side`), lungo una faglia perpendicolare.
	var side := _quake.fault_side()
	var along := Vector3(-side.z, 0.0, side.x)
	_place(_machine, q - side * 1.5, 0.3)
	_place(_player, q - side * 1.3 + along * 3.0, 0.88)
	_player._invulnerable_left = 5.0
	await _frames(10)
	var health := _player.health
	for k in 6:
		_quake._shake_point(q + along * ((k - 1) * QuakeEvent.FAULT_STEP))
	var c := _machine.global_position
	var p := _player.global_position
	_check(_player.health == health, "giocatore fuori dal raggio di colpo: nessun danno")
	_check(_field.delta_at(c) > 0.3 and c.y >= _field.height_at(c) + 0.2, "macchina riappoggiata sulla cresta (centro %.2f, suolo %.2f)" % [c.y, _field.height_at(c)])
	_check(_field.delta_at(p) > 0.3 and p.y >= _field.height_at(p) + 0.7, "giocatore riappoggiato sulla cresta (centro %.2f, suolo %.2f)" % [p.y, _field.height_at(p)])
	await _frames(30)
	_check(_machine.global_position.y >= _field.height_at(_machine.global_position) - 0.05
		and _player.global_position.y >= _field.height_at(_player.global_position) - 0.05, "dopo mezzo secondo entrambi sopra il suolo")


func _test_options() -> void:
	print("options")
	_check(is_equal_approx(RunLaunchOptions.quake_seconds(["--quake-at=5"]), 5.0), "--quake-at=5 forza il terremoto a 5 s")
	_check(is_equal_approx(RunLaunchOptions.quake_seconds(["--seed=3"]), -1.0), "senza opzione decide il pianificatore")
	_quake.schedule([])
	_check(_quake.next_at == INF, "senza istanti nessun terremoto in programma")


## Audit R-06: con tutto il campo protetto nessuna faglia e possibile: niente annuncio,
## il ciclo si salta.
func _test_empty_fault_is_skipped() -> void:
	print("empty fault")
	_field.set_protected(Vector3.ZERO, 400.0, true)
	_quake.state = QuakeEvent.State.IDLE
	_quake.next_at = _run.elapsed + 1.0
	var before := _quake.next_at
	await _frames(5)
	_check(_quake.state == QuakeEvent.State.IDLE and _quake.next_at > before and not _hud.is_boss_warning_visible(),
		"campo tutto protetto: nessun preavviso, prossimo terremoto spostato (%.0f -> %.0f)" % [before, _quake.next_at])
	_field.set_protected(Vector3.ZERO, 400.0, false)


func _test_railway_has_no_quake() -> void:
	print("railway")
	root.remove_child(_scene)
	_scene.queue_free()
	await _frames(2)
	var railway: Node3D = RailwayScene.instantiate()
	root.add_child(railway)
	(railway.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	await _frames(3)
	_check(railway.get_node_or_null(^"QuakeEvent") == null and (railway.get_node(^"Run") as ArenaRun).quake_event == null,
		"la ferrovia ha il treno, non il terremoto")
	root.remove_child(railway)
	railway.queue_free()
