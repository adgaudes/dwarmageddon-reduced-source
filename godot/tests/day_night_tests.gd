extends SceneTree
## Test del ciclo giorno/notte, tappa 1 (D-058, `docs/DAY_NIGHT_PLAN.md`, sezione 11).
## Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/day_night_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")
const DAY := DayNightCycle.Phase.DAY
const DUSK := DayNightCycle.Phase.DUSK
const NIGHT := DayNightCycle.Phase.NIGHT

var _failures := 0
var _scene: Node3D
var _run: ArenaRun
var _player: PlayerCharacter
var _caravan: Caravan
## La macchina col Faro, aggiunta dalla suite (task 4 di D-093: la luce della carovana viene
## dai Faro; il Cassone capofila non illumina piu).
var _machine: Machine
## Il capofila, il Cassone.
var _lead: Machine
var _director: EnemyDirector
var _hud: RunHud
var _cycle: DayNightCycle


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_director = _scene.get_node(^"EnemyDirector")
	_hud = _scene.get_node(^"RunHud")
	_cycle = _run.day_night
	_director.spawning = false
	(_scene.get_node(^"PlayerWeapon") as AutoWeapon).set_physics_process(false)
	await _frames(5)
	# Il Cassone nasce nel _ready della carovana; il Faro lo aggiunge la suite.
	_lead = _caravan.lead()
	_machine = _caravan.add_machine(&"beacon")
	# Il terremoto (D-075) ha la sua suite: qui il tempo salta e il suo annuncio coprirebbe
	# quello della notte. Dopo i primi passi: la regia imposta l'evento al suo _ready.
	if _run.quake_event != null:
		_run.quake_event.schedule([])
	_test_phases_and_times()
	_test_cycle_off()
	_test_launch_option()
	await _test_light_field()
	await _test_dark_speed()
	await _test_dark_damage()
	_test_cards()
	await _test_rendering_and_lights()
	await _test_hud_and_audio()
	# Per ultimo: abbattere il Demolitore chiude il livello.
	await _test_errand_and_boss_unchanged()
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


func _place_player(at: Vector3) -> void:
	_player.global_position = Vector3(at.x, 0.88, at.z)
	_player.velocity = Vector3.ZERO
	_player._invulnerable_left = 0.0


func _planar_speed(enemy: Enemy) -> float:
	return Vector2(enemy.velocity.x, enemy.velocity.z).length()


func _test_phases_and_times() -> void:
	print("phases")
	var cycle := DayNightCycle.new()
	cycle.night_start_seconds = 270.0
	cycle.dusk_seconds = 45.0
	var changes := [0]
	cycle.phase_changed.connect(func(_phase: DayNightCycle.Phase) -> void: changes[0] += 1)
	cycle.advance(0.0)
	var day_at_0 := cycle.phase == DAY and cycle.night_factor == 0.0
	cycle.advance(269.9)
	var day_before := cycle.phase == DAY
	cycle.advance(270.0)
	var dusk_start := cycle.phase == DUSK and is_zero_approx(cycle.night_factor)
	cycle.advance(292.5)
	var dusk_half := cycle.phase == DUSK and absf(cycle.night_factor - 0.5) < 0.001
	cycle.advance(315.0)
	var night := cycle.phase == NIGHT and is_equal_approx(cycle.night_factor, 1.0)
	_check(day_at_0 and day_before, "giorno fino a 269,9 s")
	_check(dusk_start and dusk_half, "tramonto da 270 s, fattore 0,5 a meta")
	_check(night and changes[0] == 2, "notte da 315 s; phase_changed emesso due volte (%d)" % changes[0])
	_check(is_equal_approx(cycle.seconds_to_dusk(100.0), 170.0) and cycle.seconds_to_dusk(400.0) == 0.0, "secondi al tramonto")
	cycle.free()


func _test_cycle_off() -> void:
	print("cycle off")
	var cycle := DayNightCycle.new()
	cycle.district = _scene.get_node(^"District")
	cycle.night_start_seconds = 0.0
	var changes := [0]
	cycle.phase_changed.connect(func(_phase: DayNightCycle.Phase) -> void: changes[0] += 1)
	var sun: DirectionalLight3D = cycle.district.get_node(^"SunLight")
	var energy := sun.light_energy
	cycle.advance(1000.0)
	_check(cycle.phase == DAY and cycle.night_factor == 0.0 and changes[0] == 0, "ciclo spento: sempre giorno, nessuna emissione")
	_check(not is_finite(cycle.seconds_to_dusk(10.0)), "ciclo spento: tramonto infinito")
	_check(is_equal_approx(sun.light_energy, energy), "ciclo spento: sole invariato dopo 1000 s")
	cycle.free()


func _test_launch_option() -> void:
	print("launch option")
	_check(is_equal_approx(RunLaunchOptions.night_start_seconds(270.0, PackedStringArray()), 270.0), "senza argomento vale il tuning")
	_check(RunLaunchOptions.night_start_seconds(270.0, PackedStringArray(["--night-at=5"])) == 5.0, "--night-at=5 letto")
	_check(RunLaunchOptions.wants_autostart(PackedStringArray(["--night-at=0"])), "--night-at salta il menu")
	_check(is_equal_approx(_cycle.night_start_seconds, _run.tuning.night_start_seconds) and is_equal_approx(_cycle.dusk_seconds, _run.tuning.dusk_seconds),
		"la run copia tramonto e durata dal tuning (%.0f + %.0f s)" % [_cycle.night_start_seconds, _cycle.dusk_seconds])


func _test_light_field() -> void:
	print("light field")
	var field := LightField.new()
	var lamp := Node3D.new()
	_scene.add_child(lamp)
	lamp.global_position = Vector3(10.0, 0.0, 10.0)
	var id := field.add_source(lamp, 6.0)
	_check(id == 1 and field.source_count() == 1, "sorgente registrata con id 1")
	_check(field.is_lit(Vector3(15.0, 3.0, 10.0)) and field.is_lit(Vector3(16.0, 0.0, 10.0)), "dentro a 5 m e sul bordo a 6 m (quota ignorata)")
	_check(not field.is_lit(Vector3(16.01, 0.0, 10.0)) and not field.is_lit(Vector3(30.0, 0.0, 30.0)), "fuori a 6,01 m e lontano")
	lamp.global_position = Vector3(30.0, 0.0, 30.0)
	await _frames(1)
	_check(field.is_lit(Vector3(33.0, 0.0, 30.0)) and not field.is_lit(Vector3(15.0, 0.0, 10.0)), "la sorgente segue il nodo")
	field.set_radius(id, 2.0)
	_check(is_equal_approx(field.radius_of(id), 2.0) and not field.is_lit(Vector3(33.0, 0.0, 30.0)), "set_radius restringe la luce")
	lamp.queue_free()
	await _frames(1)
	_check(not field.is_lit(Vector3(30.0, 0.0, 30.0)) and field.source_count() == 1, "nodo liberato: spento, senza errori")
	field.remove_source(id)
	_check(field.source_count() == 0 and field.radius_of(id) == 0.0, "remove_source")


func _measure_speed(at: Vector3, night: bool) -> float:
	_director.night_active = night
	var enemy := _director.spawn_at(at)
	for i in 30:
		await physics_frame
	if not is_instance_valid(enemy) or enemy.is_dead:
		return -1.0
	var speed := _planar_speed(enemy)
	enemy.take_damage(enemy.health)
	await _frames(2)
	return speed


func _test_dark_speed() -> void:
	print("dark speed")
	_place_player(Vector3.ZERO)
	_machine.global_position = Vector3(-3.0, _machine.global_position.y, 0.0)
	_machine.reset_physics_interpolation()
	_machine.set_physics_process(false)
	_player._invulnerable_left = 600.0
	var base := _run.tuning.enemy_speed
	var far_night := await _measure_speed(Vector3(20.0, 0.0, 0.0), true)
	var near_night := await _measure_speed(Vector3(4.0, 0.0, 0.0), true)
	var far_day := await _measure_speed(Vector3(20.0, 0.0, 0.0), false)
	_check(absf(far_night - base * _run.tuning.night_dark_speed_scale) < base * 0.03,
		"a 20 m al buio di notte corre x%.2f (%.2f m/s)" % [_run.tuning.night_dark_speed_scale, far_night])
	_check(absf(near_night - base) < base * 0.03, "a 4 m, nella torcia, velocita normale (%.2f m/s)" % near_night)
	_check(absf(far_day - base) < base * 0.03, "di giorno a 20 m velocita normale (%.2f m/s)" % far_day)
	_director.night_active = false


func _contact_damage(at: Vector3, night: bool) -> int:
	_director.night_active = night
	_player._invulnerable_left = 0.0
	var before := _player.health
	var enemy := _director.spawn_at(at)
	await _frames(2)
	var taken := before - _player.health
	enemy.take_damage(enemy.health)
	await _frames(2)
	_player.heal(taken)
	return taken


func _test_dark_damage() -> void:
	print("dark damage")
	_place_player(Vector3(40.0, 0.0, 40.0))
	_machine.global_position = Vector3(40.0, _machine.global_position.y, 80.0)
	_machine.reset_physics_interpolation()
	var contact := _run.tuning.contact_damage
	# Dentro la torcia: il nemico nasce a contatto, a 0,5 m dal giocatore.
	var lit := await _contact_damage(_player.global_position + Vector3(0.5, 0.0, 0.0), true)
	_check(lit == contact, "a contatto nella luce di notte: %d danni (%d)" % [contact, lit])
	# Al buio: torcia spenta logicamente (raggio 0) per il tempo del test. Il Cassone resta
	# accanto al giocatore: da solo non illumina (scelta 1 di D-093).
	_run.light_field.set_radius(_run.torch_light_id, 0.0)
	_lead.set_physics_process(false)
	_lead.global_position = Vector3(41.0, _lead.global_position.y, 40.0)
	_lead.reset_physics_interpolation()
	_check(not _run.light_field.is_lit(_lead.global_position), "il Cassone accanto al giocatore non illumina nemmeno se stesso")
	var dark := await _contact_damage(_player.global_position + Vector3(0.5, 0.0, 0.0), true)
	_check(dark == contact + _run.tuning.night_dark_contact_bonus and _director.dark_contacts >= 1,
		"a contatto al buio di notte: %d danni (%d), contatto al buio contato" % [contact + _run.tuning.night_dark_contact_bonus, dark])
	var day := await _contact_damage(_player.global_position + Vector3(0.5, 0.0, 0.0), false)
	_check(day == contact, "di giorno: %d danni (%d)" % [contact, day])
	_run.light_field.set_radius(_run.torch_light_id, _run.torch_radius)
	_lead.set_physics_process(true)
	_director.night_active = false


func _test_errand_and_boss_unchanged() -> void:
	print("errand and boss")
	_place_player(Vector3.ZERO)
	_player._invulnerable_left = 600.0
	_director.night_active = true
	var carrier := _director.spawn_at(Vector3(20.0, 0.0, 0.0))
	carrier.set_errand(Vector3(60.0, 0.0, 0.0))
	for i in 60:
		await physics_frame
	var speed := _planar_speed(carrier)
	_check(absf(speed - _run.tuning.enemy_speed) < _run.tuning.enemy_speed * 0.03, "portatore in commissione al buio: velocita invariata (%.2f)" % speed)
	carrier.take_damage(carrier.health)
	await _frames(2)
	# Demolitore: chiamato subito, fermo al buio, stessa velocita e danno del tuning.
	_run.boss_call_at = _run.elapsed + 0.05
	await _frames(6)
	_run._boss_warning_left = 0.05
	await _frames(6)
	var boss := _run.boss as Demolisher
	_check(boss != null and is_equal_approx(boss.speed, _run.tuning.boss_speed) and boss.contact_damage == _run.tuning.boss_contact_damage,
		"Demolitore di notte: velocita e danno del tuning")
	if boss != null:
		boss.take_damage(boss.health)
		await _frames(3)
		paused = false
	_director.night_active = false


func _test_cards() -> void:
	print("cards")
	var torch := _run.tuning.torch_radius
	_run.apply_upgrade(&"torch_range", 1)
	_check(is_equal_approx(_run.light_field.radius_of(_run.torch_light_id), torch + _run.tuning.torch_radius_per_level), "Torcia livello 1: raggio %.1f" % _run.light_field.radius_of(_run.torch_light_id))
	var beacon := _machine.module(&"beacon") as BeaconModule
	_run.apply_upgrade(&"beacon_range", 2)
	_check(is_equal_approx(_run.light_field.radius_of(beacon.light_id), _run.tuning.beacon_radius + 2.0 * _run.tuning.beacon_radius_per_level)
		and _run.light_field.source_node(beacon.light_id) == _machine,
		"Faro livello 2 sulla macchina col Faro: raggio %.1f" % _run.light_field.radius_of(beacon.light_id))
	var solo := RunProgression.new()
	solo.has_caravan = false
	solo.setup(3)
	var ids := solo.eligible().map(func(u: Dictionary) -> StringName: return u.id)
	_check(ids.has(&"torch_range") and not ids.has(&"beacon_range"), "senza carovana la Torcia si, il Faro no")
	# La carta Faro richiede una macchina col Faro.
	solo.has_caravan = true
	solo.module_count = func(_id: StringName) -> int: return 0
	ids = solo.eligible().map(func(u: Dictionary) -> StringName: return u.id)
	_check(ids.has(&"torch_range") and not ids.has(&"beacon_range"), "con la carovana ma senza Faro, niente carta Faro")
	solo.module_count = func(id: StringName) -> int: return 1 if id == &"beacon" else 0
	ids = solo.eligible().map(func(u: Dictionary) -> StringName: return u.id)
	_check(ids.has(&"beacon_range"), "con un Faro la carta Faro c'e")
	_check(_run.progression.eligible().any(func(u: Dictionary) -> bool: return u.id == &"beacon_range"),
		"nella run, col Faro in carovana, la carta Faro e fra quelle possibili")


func _test_rendering_and_lights() -> void:
	print("rendering and lights")
	var district: Node3D = _scene.get_node(^"District")
	var sun: DirectionalLight3D = district.get_node(^"SunLight")
	var environment: Environment = (district.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	var day_sun := sun.light_energy
	var day_ambient := environment.ambient_light_energy
	_run.elapsed = _cycle.night_start_seconds + _cycle.dusk_seconds + 1.0
	await _frames(3)
	_check(_cycle.phase == NIGHT and _director.night_active, "oltre il tramonto la run e di notte e il direttore lo sa")
	_check(sun.light_energy < day_sun and sun.light_energy > 0.0 and environment.ambient_light_energy < day_ambient and environment.ambient_light_energy > 0.0,
		"sole %.2f e ambiente %.2f: sotto il giorno, sopra zero" % [sun.light_energy, environment.ambient_light_energy])
	var torch: OmniLight3D = _player.get_node_or_null(^"TorchLight")
	var module := _machine.module(&"beacon") as BeaconModule
	var beacon: OmniLight3D = module.get_node_or_null(^"BeaconLight")
	var beacon_radius := _run.light_field.radius_of(module.light_id)
	_check(torch != null and beacon != null and torch.visible and beacon.visible, "torcia e faro esistono e sono accesi")
	_check(_lead.find_child("BeaconLight", true, false) == null, "il Cassone non ha una luce del faro")
	_check(torch != null and absf(torch.omni_range - _run.torch_radius * 1.15) < 0.01 and beacon != null and absf(beacon.omni_range - beacon_radius * 1.15) < 0.01,
		"portata delle luci coerente coi raggi logici")
	_run.elapsed = 1.0
	await _frames(3)
	_check(_cycle.phase == DAY and not _director.night_active and torch != null and not torch.visible and beacon != null and not beacon.visible
		and is_equal_approx(sun.light_energy, day_sun), "tornati al giorno: luci spente, sole com'era")


func _test_hud_and_audio() -> void:
	print("hud and audio")
	var audio: RunAudio = _scene.get_node(^"RunAudio")
	_hud.set_day_phase(DAY, 125.0)
	var day_text: String = _hud._day_label.text
	_hud.set_day_phase(NIGHT, 0.0)
	var night_text: String = _hud._day_label.text
	_check(day_text.contains("02:05") and night_text.contains("NOTTE") and _hud._day_label.visible, "indicatore: %s -> %s" % [day_text, night_text])
	_hud.set_day_phase(DAY, INF)
	_check(not _hud._day_label.visible, "ciclo spento: indicatore nascosto")
	var dusk_before := audio.play_count(&"dusk")
	var night_before := audio.play_count(&"nightfall")
	# Oltre il limite di frequenza del suono della notte (1 s), gia suonato nel test precedente.
	await _frames(75)
	_run.elapsed = _cycle.night_start_seconds + 0.5
	await _frames(2)
	_check(_cycle.phase == DUSK and _hud.is_night_notice_visible(), "al tramonto compare l'avviso")
	_run.elapsed = _cycle.night_start_seconds + _cycle.dusk_seconds + 1.0
	await _frames(2)
	_check(audio.play_count(&"dusk") == dusk_before + 1 and audio.play_count(&"nightfall") == night_before + 1, "campana al tramonto e colpo alla notte, una volta ciascuno")
	_run.elapsed = 1.0
	await _frames(2)
