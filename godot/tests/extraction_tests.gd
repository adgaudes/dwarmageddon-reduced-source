extends SceneTree
## Suite della piazzola di estrazione (D-076) sul rilievo continuo (D-085): battuto il
## boss il livello continua, il disco di 3 m attorno al giocatore deve essere piano e
## tenuto per `hold_seconds`; un cumulo dentro lo rompe e azzera il conto; senza il nodo
## la vittoria e immediata.
##   godot_console --headless --path godot --script res://tests/extraction_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")

var _failures := 0
var _scene: Node3D
var _run: ArenaRun
var _pad: ExtractionPad
var _field: TerrainField
var _player: PlayerCharacter
var _director: EnemyDirector
var _weapon: AutoWeapon
var _hud: RunHud
var _audio: RunAudio


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _open_scene()
	_test_setup()
	await _test_boss_death_calls_extraction()
	await _test_pad_broken_and_held()
	await _test_without_pad()
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _open_scene() -> void:
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_pad = _scene.get_node(^"ExtractionPad")
	_field = _scene.get_node(^"TerrainField")
	_player = _scene.get_node(^"Player")
	_director = _scene.get_node(^"EnemyDirector")
	_weapon = _scene.get_node(^"PlayerWeapon")
	_hud = _scene.get_node(^"RunHud")
	_audio = _scene.get_node(^"RunAudio")
	_director.spawning = false
	await _frames(5)
	_weapon.set_physics_process(false)
	# Il disco di partenza e protetto nei primi 10 s: qui si toglie, per scolpire subito.
	_run._start_protect_left = 0.0
	_field.set_protected(Vector3.ZERO, _field.tuning.start_protected_radius_m, false)


func _close_scene() -> void:
	paused = false
	root.remove_child(_scene)
	_scene.queue_free()
	await _frames(2)


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


## Chiama il boss, lo fa comparire subito e lo abbatte.
func _kill_boss() -> void:
	_run.call_boss()
	_run._boss_warning_left = 0.05
	for i in 20:
		await physics_frame
		if _run.boss != null:
			break
	# Audit B-01: le barricate del Demolitore servono alla mappa anche dopo la sua liberazione.
	(_run.boss as Demolisher).barricade_points.append(Vector3(9.0, 0.0, -7.0))
	_run.boss.take_damage(_run.boss.health)
	await _frames(2)


func _test_setup() -> void:
	print("setup")
	_check(_run.extraction_pad == _pad and not _pad.is_active(), "la piazzola e collegata alla regia e spenta")
	_check(is_equal_approx(_pad.hold_seconds, _run.tuning.extraction_hold_seconds) and is_equal_approx(_pad.radius_m, 3.0),
		"tenuta di %.0f s su un disco piano di %.0f m" % [_pad.hold_seconds, _pad.radius_m])


func _test_boss_death_calls_extraction() -> void:
	print("boss death")
	_pad.hold_seconds = 1.0
	# Il giocatore al centro del cortile di partenza: disco piano attorno.
	_place_player(Vector3.ZERO)
	_check(_pad.is_flat_at(Vector3.ZERO), "il centro del cortile e un disco piano")
	var plays := _audio.play_count(&"boss_warning")
	var witness := _director.spawn_at(Vector3(14.0, 0.0, 0.0))
	witness.speed_scale = 0.0
	await _kill_boss()
	_check(not _run.is_over and _run.boss_phase == ArenaRun.BossPhase.EXTRACTION, "boss abbattuto: il livello continua con l'estrazione")
	_check(_pad.is_active() and _pad.intact, "piazzola attiva e integra sotto il giocatore")
	_check(_hud.event_warning_text().begins_with("ESTRAZIONE: TIENI"), "annuncio senza freccia: %s" % _hud.event_warning_text())
	_check(_audio.play_count(&"boss_warning") > plays, "sirena alla chiamata dell'estrazione")
	_check(is_instance_valid(witness) and not witness.is_dead and _director.enemies.has(witness), "l'orda non si ritira: la pressione continua")
	await _frames(30)
	_check(not is_instance_valid(_run.boss) and _run.map_barricade_points().has(Vector3(9.0, 0.0, -7.0)),
		"boss liberato: la mappa conserva le sue barricate")


func _test_pad_broken_and_held() -> void:
	print("pad")
	await _frames(20)
	var held_before := _pad.held
	_check(held_before > 0.2, "il conto sale mentre la piazzola e integra (%.2f s)" % held_before)
	var mound := _player.global_position + Vector3(1.5, 0.0, 0.0)
	mound.y = 0.0
	_field.sculpt(mound, 2.0, 0.6)
	await _frames(2)
	_check(not _pad.intact and is_zero_approx(_pad.held), "un cumulo nel disco rompe la piazzola e azzera il conto")
	_check(_hud.event_warning_text().begins_with("ESTRAZIONE: SPIANA"), "annuncio: %s" % _hud.event_warning_text())
	# Audit R-01: un solo annuncio a schermo; durante l'estrazione un terremoto in arrivo
	# deve vedersi lo stesso, con la sua freccia, e poi l'estrazione torna.
	var quake: QuakeEvent = _run.quake_event
	quake.warning_seconds = 3.0
	quake.next_at = _run.elapsed + 2.5
	await _frames(10)
	_check(_hud.event_warning_text().begins_with("TERREMOTO") and _hud._boss_arrow.visible,
		"durante l'estrazione il terremoto in arrivo ha la precedenza: %s" % _hud.event_warning_text())
	quake.state = QuakeEvent.State.IDLE
	quake.next_at = _run.elapsed + 999.0
	await _frames(2)
	_check(_hud.event_warning_text().begins_with("ESTRAZIONE"), "finito il preavviso torna l'estrazione: %s" % _hud.event_warning_text())
	_check(not _run.is_over, "il livello non finisce")
	_field.level(mound, 3.0, _field.base_height_at(mound), 1.0)
	_field.level(mound, 3.0, _field.base_height_at(mound), 1.0)
	await _frames(2)
	_check(_pad.intact, "spianato, la piazzola torna integra")
	var completed := [false]
	_run.level_completed.connect(func() -> void: completed[0] = true)
	for i in 120:
		await physics_frame
		if _run.is_over:
			break
	var panel: GameOverPanel = _scene.get_node(^"GameOverPanel")
	_check(completed[0] and _run.is_over and _run.boss_phase == ArenaRun.BossPhase.DEFEATED, "tenuta per %.0f s: livello completato" % _pad.hold_seconds)
	_check(panel.is_open and panel.is_victory and paused, "schermata di vittoria, gioco fermo")
	_check(not _pad.is_active() and _hud.event_warning_text().is_empty(), "piazzola spenta e annuncio tolto")
	await _close_scene()


func _test_without_pad() -> void:
	print("without pad")
	await _open_scene()
	_run.extraction_pad = null
	await _kill_boss()
	_check(_run.is_over and _run.boss_phase == ArenaRun.BossPhase.DEFEATED, "senza piazzola la vittoria e immediata, come prima")
	await _close_scene()
