extends SceneTree
## Test del treno della ferrovia sul rilievo continuo (tappa B): preavviso, fascia
## riportata alla base senza rottami, vene dei vagoni azzerate, rottamatori travolti,
## giocatore e macchina della carovana spinti su un punto calpestabile, lampioni e rottami a terra
## spazzati, direzione alternata. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/train_tests.gd

const RunScene := preload("res://scenes/main/railway_run.tscn")

var _failures := 0
var _scene: Node3D
var _run: ArenaRun
var _train: TrainEvent
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
	_train = _scene.get_node(^"TrainEvent")
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
	await _test_pass_flattens_and_hits()
	await _test_half_dug_wagon()
	await _test_third_train_from_the_other_side()
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


func _place(body: Node3D, at: Vector3, lift: float) -> void:
	body.global_position = Vector3(at.x, _field.height_at(at) + lift, at.z)
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	body.reset_physics_interpolation()


func _unprotect_start() -> void:
	_run._start_protect_left = 0.0
	_field.set_protected(Vector3.ZERO, _field.tuning.start_protected_radius_m, false)


func _wagons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in _run.district.terrain_strokes:
		if s.kind == &"wagon":
			out.append(s)
	return out


func _test_setup() -> void:
	print("setup")
	_check(_run.train_event == _train and _train.is_enabled(), "il treno e collegato alla regia")
	# D-097: un solo evento di serie, a un istante casuale nella finestra prima del boss.
	var end := _run.boss_call_at - _run.tuning.world_events_boss_margin
	_check(_run.world_event_plan.size() == 1 and _train.next_at >= _run.tuning.world_events_start_seconds and _train.next_at <= end,
		"un passaggio casuale fra %.0f e %.0f s (%.0f)" % [_run.tuning.world_events_start_seconds, end, _train.next_at])
	_check(_train.state == TrainEvent.State.IDLE and not _hud.is_boss_warning_visible(), "all'inizio nessun treno e nessun annuncio")
	_check(_audio.has_sound(&"train_horn"), "il fischio esiste nella libreria")


func _test_warning() -> void:
	print("warning")
	_train.warning_seconds = 1.0
	_train.next_at = _run.elapsed + 1.05
	await _frames(6)
	_check(_train.state == TrainEvent.State.WARNING, "entro il preavviso il treno e annunciato")
	_check(_train.heading == -1 and _train.direction_name() == "EST", "il primo treno viene da est")
	_check(_hud.is_boss_warning_visible() and _hud.event_warning_text().begins_with("TRENO DA EST"), "annuncio a schermo: %s" % _hud.event_warning_text())
	_check(_audio.play_count(&"train_horn") >= 1, "fischio al preavviso")
	_check(is_equal_approx(absf(_train.track_z), 2.4), "binario scelto a z = %.1f" % _train.track_z)


## Un argine a cavallo del confine delle regioni, un solco, un argine fuori fascia, un
## lampione, un rottame a terra, un rottamatore, il giocatore sul binario e la macchina
## accanto: dopo il passaggio la fascia e alla base, chi era sopra e morto o spinto fuori,
## i rottami non aumentano e le vene dei vagoni sono azzerate.
func _test_pass_flattens_and_hits() -> void:
	print("pass")
	_train.speed = 80.0
	_unprotect_start()
	# Davanti al treno (viene da est): argine sul confine x = 0 (Review Focus 1), solco, argine fuori fascia.
	_field.sculpt(Vector3(0.0, 0.0, 2.4), 2.0, 1.4)
	_field.sculpt(Vector3(24.0, 0.0, 0.0), 2.0, -0.8)
	_field.sculpt(Vector3(24.0, 0.0, 9.0), 2.0, 1.4)
	var lamp_at := Vector3(-30.0, 0.0, -2.4)
	_caravan.add_scrap(3)
	_place(_machine, lamp_at + Vector3(2.0, 0.0, 3.0), 0.3)
	_lamps.place_at(lamp_at)
	_check(_lamps.count() == 1, "lampione piazzato sulla fascia")
	_scrap.spawn_on_ground(Vector3(-40.0, 0.0, 0.0))
	var scrap_before := _scrap.count()
	var wagons := _wagons()
	var enemy := _director.spawn_at(Vector3(-50.0, 0.0, 0.0))
	var enemy_died := [false]
	enemy.died.connect(func(_e: Enemy) -> void: enemy_died[0] = true)
	var bystander := _director.spawn_at(Vector3(-50.0, 0.0, 10.0))
	# I nemici restano dove sono: lo spettatore non deve camminare fino alla fascia.
	_director.set_physics_process(false)
	var kills_before := _director.kills
	_place(_player, Vector3(30.0, 0.0, _train.track_z), 0.88)
	_player._invulnerable_left = 0.0
	var health_before := _player.health
	# Un argine alto proprio dove il treno spingerebbe il giocatore (Review Focus 2).
	var push_side := 1.0 if _train.track_z >= 0.0 else -1.0
	var landing_z := push_side * (RailwayDistrict.TRACK_HALF_WIDTH + TrainEvent.PUSH_MARGIN)
	_field.sculpt(Vector3(30.0, 0.0, landing_z), 2.0, 1.6)
	_place(_machine, Vector3(33.0, 0.0, 0.0), 0.3)
	for i in 90:
		await physics_frame
		if _train.state == TrainEvent.State.PASSING:
			break
	_check(_train.state == TrainEvent.State.PASSING, "finito il preavviso il treno e in corsa")
	_check(_train.get_node_or_null(^"Train") != null and _train.get_node(^"Train").get_child_count() == _run.tuning.train_carriages + 1,
		"convoglio di %d vagoni piu la locomotiva" % _run.tuning.train_carriages)
	_check(not _hud.is_boss_warning_visible(), "annuncio tolto all'ingresso")
	for i in 600:
		await physics_frame
		if _train.state == TrainEvent.State.IDLE:
			break
	_check(_train.state == TrainEvent.State.IDLE and _train.passes == 1, "il passaggio e finito (%d)" % _train.passes)
	_check(absf(_field.delta_at(Vector3(0.0, 0.0, 2.4))) < 0.02 and absf(_field.delta_at(Vector3(24.0, 0.0, 0.0))) < 0.02, "argine e solco sulla fascia tornano alla base")
	_check(_field.delta_at(Vector3(24.0, 0.0, 9.0)) > 1.0, "l'argine fuori dalla fascia resta")
	var flat := true
	for s: Dictionary in wagons:
		var c := Vector3(s.center.x, 0.0, s.center.y)
		flat = flat and absf(_field.delta_at(c)) < 0.02 and _scrap.vein_scrap_left(c) == 0
	_check(flat and _train.wagons_swept == wagons.size(), "vagoni spianati e vene azzerate (%d)" % _train.wagons_swept)
	_check(_train.volume_flattened > 20.0, "terra spostata dal treno: %.0f m3" % _train.volume_flattened)
	_check(_scrap.count() <= scrap_before - 1, "nessun rottame dai vagoni e il rottame a terra e sparito (%d -> %d)" % [scrap_before, _scrap.count()])
	_check(_lamps.count() == 0, "lampione sulla fascia abbattuto")
	_check(enemy_died[0] and _director.kills == kills_before + 1, "rottamatore sulla fascia travolto e contato come abbattuto")
	_check(not bystander.is_dead, "rottamatore fuori dalla fascia illeso")
	_check(_player.health == health_before - _run.tuning.train_player_damage, "giocatore colpito: %d -> %d" % [health_before, _player.health])
	var pp := _player.global_position
	_check(not RailwayDistrict.is_on_tracks(Vector2(pp.x, pp.z)), "giocatore spinto fuori dalla fascia (z=%.1f)" % pp.z)
	_check(_field.delta_at(pp) < 0.5 and _field.slope_at(pp) <= _field.tuning.max_grade + 0.01, "spinto su un punto calpestabile, non sull'argine (z=%.1f)" % pp.z)
	var cp := _machine.global_position
	_check(not RailwayDistrict.is_on_tracks(Vector2(cp.x, cp.z)), "macchina spinta fuori (z=%.1f)" % cp.z)
	_check(_train.player_hits == 1 and _train.enemies_hit == 1, "un colpo al giocatore, un rottamatore (%d, %d)" % [_train.player_hits, _train.enemies_hit])
	_check(_train.next_at == INF, "passato il treno, nessun altro in programma")
	_check(_audio.play_count(&"train_horn") >= 2, "fischio anche all'ingresso")
	bystander.queue_free()
	_director.enemies.clear()
	_director.set_physics_process(true)


## Review Focus 5: un vagone scavato a meta ha gia dato rottami; il treno azzera il resto
## della vena ma i rottami a terra fuori fascia restano.
func _test_half_dug_wagon() -> void:
	print("half dug wagon")
	_scrap.take_in_rect(Rect2(-200.0, -70.0, 400.0, 140.0), 1000)
	_scrap._veins.clear()
	# Il rilievo ricaricato torna alla base ovunque: casse e relitti sepolti si aprirebbero
	# tutti e la loro scelta fermerebbe il gioco (D-092, D-093). Qui non servono.
	_run.discard_buried_in_rect(Rect2(-200.0, -70.0, 400.0, 140.0))
	_field.load_base(_run.base_relief_path(), _run.district.layout_seed)
	_run.district.apply_strokes(_field, _scrap)
	var wagon: Dictionary = _wagons()[0]
	var center := Vector3(wagon.center.x, 0.0, wagon.center.y)
	var before := _scrap.count()
	for i in 12:
		_field.player_sculpt(center, 2.4, -0.3, TerrainField.ToolMode.DIG)
	var spawned := _scrap.count() - before
	_check(spawned >= 2 and _scrap.vein_scrap_left(center) < RailwayDistrict.WAGON_SCRAP, "scavando il vagone escono rottami (%d)" % spawned)
	# I rottami usciti vengono portati fuori fascia prima del treno (come farebbe il Cassone).
	var moved := 0
	for scrap in _scrap._scraps:
		if RailwayDistrict.is_on_tracks(Vector2(scrap.global_position.x, scrap.global_position.z)):
			scrap.global_position.z = 6.0
			moved += 1
	_place(_player, Vector3(0.0, 0.0, 20.0), 0.88)
	_place(_machine, Vector3(0.0, 0.0, 22.0), 0.3)
	_train.speed = 80.0
	_train.next_at = _run.elapsed + 1.05
	for i in 700:
		await physics_frame
		if _train.passes >= 2:
			break
	_check(_train.passes == 2, "un altro treno e passato")
	_check(_scrap.vein_scrap_left(center) == 0 and absf(_field.delta_at(center)) < 0.02, "la vena del vagone e azzerata e il cumulo spianato")
	_check(moved > 0 and _scrap.count() >= moved, "i rottami gia usciti restano a terra (%d)" % _scrap.count())


func _test_third_train_from_the_other_side() -> void:
	print("third train")
	_place(_player, Vector3(0.0, 0.0, 20.0), 0.88)
	_place(_machine, Vector3(0.0, 0.0, 22.0), 0.3)
	_train.next_at = _run.elapsed + 1.05
	await _frames(6)
	_check(_train.state == TrainEvent.State.WARNING and _train.heading == -1 and _train.direction_name() == "EST", "il terzo treno torna da est")
	var health_before := _player.health
	for i in 90:
		await physics_frame
		if _train.state == TrainEvent.State.PASSING:
			break
	_check(_train.state == TrainEvent.State.PASSING and _train.head_x() > _run.district.half_x() - 30.0, "parte da oltre il portale est (x=%.0f)" % _train.head_x())
	for i in 600:
		await physics_frame
		if _train.state == TrainEvent.State.IDLE:
			break
	_check(_train.passes == 3, "terzo passaggio concluso")
	_check(_player.health == health_before and _train.player_hits == 0, "fuori dalla fascia il giocatore non e toccato")
