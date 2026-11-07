extends SceneTree
## Test del secondo boss, la Trivella, sul rilievo continuo (tappa B): carica dritta con
## solco idempotente, argine che la ferma senza rottami, vena sotto l'argine, rialzo basso
## superato, rovina aggirata, treno che la colpisce, sconfitta che chiude il livello.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/driller_tests.gd

const RunScene := preload("res://scenes/main/railway_run.tscn")

var _failures := 0
var _scene: Node3D
var _run: ArenaRun
var _field: TerrainField
var _player: PlayerCharacter
var _caravan: Caravan
var _director: EnemyDirector
var _weapon: AutoWeapon
var _path: PathField
var _hud: RunHud
var _scrap: ScrapField
var _train: TrainEvent
var _audio: RunAudio
var _boss: Driller


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_field = _scene.get_node(^"TerrainField")
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_director = _scene.get_node(^"EnemyDirector")
	_weapon = _scene.get_node(^"PlayerWeapon")
	_path = _scene.get_node(^"PathField")
	_hud = _scene.get_node(^"RunHud")
	_scrap = _scene.get_node(^"ScrapField")
	_train = _scene.get_node(^"TrainEvent")
	_audio = _scene.get_node(^"RunAudio")
	_director.spawning = false
	# Niente treni durante questi test, salvo dove richiesto.
	_train.next_at = 1.0e9
	await _frames(5)
	_weapon.set_physics_process(false)
	await _test_call_and_arrival()
	await _test_aim_and_charge()
	await _test_aims_through_rampart()
	await _test_side_push_lands_on_ground()
	await _test_machines_and_the_driller()
	await _test_wall_stops_and_stuns()
	await _test_wall_over_vein_gives_scrap()
	await _test_low_mound_does_not_stop()
	await _test_furrow_is_idempotent()
	await _test_furrow_does_not_fill_trench()
	await _test_charge_length_and_trench()
	await _test_blocked_by_ruin_uses_path()
	await _test_train_hits_boss()
	await _test_defeat_completes_level()
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
	_player.global_position = Vector3(at.x, _field.height_at(at) + 0.88, at.z)
	_player.velocity = Vector3.ZERO
	_player._invulnerable_left = 0.0
	_path.solve()


func _place_boss(at: Vector3, phase: Driller.Phase, left: float) -> void:
	_boss.global_position = Vector3(at.x, _field.height_at(at) + Driller.boss_spawn_height(), at.z)
	_boss.velocity = Vector3.ZERO
	_boss.phase = phase
	_boss.phase_left = left
	_boss.reset_physics_interpolation()


func _place_machine(machine: Machine, at: Vector3) -> void:
	machine.global_position = Vector3(at.x, _field.height_at(at) + Caravan.GROUND_CLEARANCE, at.z)
	machine.velocity = Vector3.ZERO
	machine.reset_physics_interpolation()


## Macchina in ordine, a vita piena e colpibile subito (fuori dall'immunita del colpo prima).
func _ready_machine(machine: Machine) -> void:
	if machine.is_broken():
		machine.repair(1.0)
	machine.heal(machine.max_health)
	machine._hit_cooldown_left = 0.0
	machine._invulnerable_left = 0.0


func _count_bursts() -> int:
	return _scene.find_children("*", "CPUParticles3D", true, false).size()


func _planar(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## La fascia dei binari e l'unico corridoio garantito libero da rovine: i test di
## carica si fanno li, con i vagoni gia spianati e il cortile di partenza non protetto. Casse
## e relitti dei vagoni si scartano prima: col suolo alla base si aprirebbero e il loro menu
## fermerebbe il gioco (come fa il treno). Rettangolo allargato di due celle come in
## TrainEvent: `reset_to_base` arriva al vertice oltre il bordo, e una cassa appena fuori si
## aprirebbe (pausa del menu a meta suite, secondo il seme).
func _clear_tracks() -> void:
	_run.discard_buried_in_rect((_run.district as RailwayDistrict).track_rect().grow(TerrainField.SPACING * 2.0))
	_field.reset_to_base(Vector3.ZERO, Vector2(_run.district.half_x(), RailwayDistrict.TRACK_HALF_WIDTH))
	_run._start_protect_left = 0.0
	_field.set_protected(Vector3.ZERO, _field.tuning.start_protected_radius_m, false)
	_path.solve()


## Aspetta che la Trivella entri nella fase, al massimo [param frames].
func _wait_phase(phase: Driller.Phase, frames: int) -> bool:
	for i in frames:
		if _boss.phase == phase:
			return true
		await physics_frame
	return _boss.phase == phase


func _test_call_and_arrival() -> void:
	print("call and arrival")
	_check(_run.tuning.boss_kind == &"driller", "il tuning della ferrovia chiama la Trivella")
	_place_player(Vector3(0.0, 0.0, 20.0))
	_run.boss_call_at = _run.elapsed + 0.05
	await _frames(6)
	_check(_run.boss_phase == ArenaRun.BossPhase.WARNING, "a tempo scaduto il boss e annunciato")
	_check(_hud.event_warning_text().begins_with("LA TRIVELLA ARRIVA DA"), "annuncio con il suo nome: %s" % _hud.event_warning_text())
	_run._boss_warning_left = 0.05
	await _frames(6)
	_boss = _run.boss as Driller
	_check(_boss != null and _run.boss_phase == ArenaRun.BossPhase.ACTIVE, "finito il preavviso entra la Trivella")
	if _boss == null:
		return
	_check(_hud.boss_name_text() == "LA TRIVELLA" and _hud.is_boss_bar_visible(), "barra vita con il suo nome")
	_check(_boss.health == _run.tuning.driller_health and _boss.kind == &"driller" and _boss.self_driven, "vita e tipo dal tuning")
	_check(_director.enemies.has(_boss) and _train.boss == _boss, "registrata fra i nemici e nota al treno")
	_check(_audio.play_count(&"boss_spawn") >= 1, "suono d'ingresso")


## Dopo il riposo mira al giocatore (striscia a terra), poi carica dritta scavando un solco;
## il giocatore sulla linea viene colpito una volta e spinto di lato.
func _test_aim_and_charge() -> void:
	print("aim and charge")
	_clear_tracks()
	_place_player(Vector3(-20.0, 0.0, 0.0))
	_place_boss(Vector3(2.0, 0.0, 0.0), Driller.Phase.REST, 0.1)
	_check(await _wait_phase(Driller.Phase.AIM, 30), "dal riposo passa alla mira")
	_check(_boss.get_node(^"AimStrip").visible, "striscia di mira visibile")
	_check(_boss.charge_direction.dot(Vector3(-1.0, 0.0, 0.0)) > 0.95, "mira verso il giocatore (ovest)")
	var charges := _audio.play_count(&"driller_charge")
	var health_before := _player.health
	_check(await _wait_phase(Driller.Phase.CHARGE, int(_boss.aim_seconds * 60.0) + 20), "finita la mira parte la carica")
	_check(not _boss.get_node(^"AimStrip").visible and _audio.play_count(&"driller_charge") == charges + 1, "striscia nascosta e suono della carica")
	var start := _boss.global_position
	# Audit E-13: in carica scavava e creava un nodo di particelle a ogni passo fisico.
	var updates := [0]
	var counter := func(_aabb: AABB) -> void: updates[0] += 1
	_field.region_changed.connect(counter)
	var bursts_before := _count_bursts()
	await _frames(60)
	_field.region_changed.disconnect(counter)
	var bursts := _count_bursts() - bursts_before
	var furrow := maxf(_boss.furrow_length_m, 0.1)
	_check(updates[0] / furrow <= 5.0 and bursts <= 8, "solco a rate: %.1f aggiornamenti per metro, %d schizzi in 1 s" % [updates[0] / furrow, bursts])
	var moved := _boss.global_position - start
	_check(moved.x < -3.0 and absf(moved.z) < 0.5, "avanza dritta verso ovest (%.1f m)" % -moved.x)
	var speed := _planar(_boss.velocity).length()
	_check(absf(speed - _boss.charge_speed) < 0.5, "a %.1f m/s" % speed)
	_check(_boss.furrow_length_m >= 2.0, "lascia un solco dietro di se (%.1f m)" % _boss.furrow_length_m)
	# La punta sta 2,3 m davanti al corpo: il solco comincia da li.
	var behind := Vector3(start.x - 4.0, 0.0, 0.0)
	_check(_field.delta_at(behind) < -0.6, "il punto attraversato e 0,8 m sotto la base (%.2f)" % _field.delta_at(behind))
	_check(await _wait_phase(Driller.Phase.REST, 400), "la carica finisce in riposo")
	_check(_player.health == health_before - _boss.contact_damage, "giocatore colpito una volta (%d -> %d)" % [health_before, _player.health])
	_check(absf(_player.global_position.z) >= Driller.SIDE_PUSH - 0.5, "e spinto di lato (z=%.1f)" % _player.global_position.z)
	_check(_boss.charges == 1 and _boss.walls_broken == 0, "una carica, nessun argine")


## Audit E-11: la spinta laterale non infila il giocatore in un cumulo. Con un cumulo da
## 1,5 m sul lato della spinta va dall'altra parte; con cumuli su entrambi i lati resta dov'e.
## In tutti i casi resta sopra il suolo e poggia a terra.
func _test_side_push_lands_on_ground() -> void:
	print("side push lands on ground")
	_clear_tracks()
	var p := Vector3(-20.0, 0.0, 0.0)
	_place_player(p)
	_place_boss(p + Vector3(1.0, 0.0, 0.0), Driller.Phase.CHARGE, 5.0)
	_boss.charge_direction = Vector3(-1.0, 0.0, 0.0)
	_boss._hit_this_charge.clear()
	# Il lato di spinta e -Z (offset nullo lungo il lato): li un cumulo da 1,5 m.
	_field.sculpt(p + Vector3(0.0, 0.0, -Driller.SIDE_PUSH), 2.0, 1.5)
	_boss._hit_in_the_way(_player, false)
	var landed := _player.global_position
	_check(landed.z > 1.0, "con un cumulo sul lato della spinta finisce dall'altra parte (z=%.1f)" % landed.z)
	_check(landed.y >= _field.height_at(landed) - 0.05, "atterra sopra il suolo (%.2f su %.2f)" % [landed.y, _field.height_at(landed)])
	_boss.phase = Driller.Phase.REST
	_boss.phase_left = 10.0
	await _frames(60)
	_check(_player.is_on_floor() and _player.global_position.y >= _field.height_at(_player.global_position) - 0.05, "e poggia a terra dopo un secondo")
	# Cumuli da entrambe le parti: nessun punto buono, nessuna spinta.
	_place_player(p)
	_place_boss(p + Vector3(1.0, 0.0, 0.0), Driller.Phase.REST, 10.0)
	_field.sculpt(p + Vector3(0.0, 0.0, Driller.SIDE_PUSH), 2.0, 1.5)
	_field.sculpt(p + Vector3(0.0, 0.0, Driller.SIDE_PUSH * 0.5), 1.2, 1.5)
	_field.sculpt(p + Vector3(0.0, 0.0, -Driller.SIDE_PUSH * 0.5), 1.2, 1.5)
	var before := _player.global_position
	_boss._hit_this_charge.clear()
	_boss._hit_in_the_way(_player, false)
	_check(_player.global_position.distance_to(before) < 0.01, "tutto murato: nessuna spinta")
	_field.reset_to_base(p, Vector2(4.0, 4.0))
	_boss.phase = Driller.Phase.REST
	_path.solve()


## D-093 (task 6): la carica ferisce (2 PV) e spinge di lato una macchina sulla sua strada, una
## volta per carica; ferma entro 1,5 m la colpisce col contatto, stordita no; una macchina guasta
## sulla linea della carica resta dov'e (i nemici la ignorano). Il capofila torna poi in ordine.
func _test_machines_and_the_driller() -> void:
	print("machines and the driller")
	_clear_tracks()
	var machine := _caravan.lead()
	var p := Vector3(-20.0, 0.0, 0.0)
	_place_player(p + Vector3(-6.0, 0.0, 3.0))
	machine.set_physics_process(false)
	_ready_machine(machine)
	_place_machine(machine, p)
	# A 1,7 m: fuori dal contatto (1,5 m), dentro la portata della carica (1,5 + 0,4).
	_place_boss(p + Vector3(1.7, 0.0, 0.0), Driller.Phase.CHARGE, 5.0)
	_boss.charge_direction = Vector3(-1.0, 0.0, 0.0)
	_boss._hit_this_charge.clear()
	var health := machine.health
	_boss._hit_in_the_way(machine, true)
	var pushed := machine.global_position
	_check(machine.health == health - _boss.contact_damage,
		"la carica toglie %d PV alla macchina sulla sua strada (%d -> %d)" % [_boss.contact_damage, health, machine.health])
	_check(absf(pushed.z - p.z) >= Driller.SIDE_PUSH * 0.5 - 0.05, "e la spinge di lato (z=%.1f)" % pushed.z)
	_boss._hit_in_the_way(machine, true)
	_check(machine.health == health - _boss.contact_damage and machine.global_position.distance_to(pushed) < 0.01,
		"nella stessa carica una seconda volta non cambia nulla")
	_boss.phase = Driller.Phase.REST
	_boss.phase_left = 60.0
	# Ferma a 1,2 m: il contatto la colpisce una volta; stordita no.
	_ready_machine(machine)
	_place_machine(machine, p)
	_place_boss(p + Vector3(1.2, 0.0, 0.0), Driller.Phase.REST, 60.0)
	health = machine.health
	await _frames(30)
	_check(machine.health == health - _boss.contact_damage,
		"a riposo entro 1,5 m toglie esattamente %d PV in 0,5 s (%d -> %d)" % [_boss.contact_damage, health, machine.health])
	_ready_machine(machine)
	_place_boss(p + Vector3(1.2, 0.0, 0.0), Driller.Phase.STUN, 60.0)
	health = machine.health
	_check(machine.accepts_contact(), "la macchina e di nuovo colpibile")
	await _frames(30)
	_check(machine.health == health, "stordita non la colpisce (%d PV)" % machine.health)
	# Guasta sulla linea di una carica vera: resta dov'e.
	_ready_machine(machine)
	_check(machine.take_hit(machine.health) and machine.is_broken(), "la macchina e guasta")
	machine.set_physics_process(true)
	_place_player(Vector3(-24.0, 0.0, 0.0))
	_player.grant_invulnerability(600.0)
	var on_line := Vector3(-10.0, 0.0, 0.0)
	_place_machine(machine, on_line)
	await _frames(2)
	var rest := machine.global_position
	_place_boss(Vector3(2.0, 0.0, 0.0), Driller.Phase.REST, 0.05)
	_check(await _wait_phase(Driller.Phase.CHARGE, 200), "la Trivella carica verso ovest")
	var passed := false
	for i in 400:
		await physics_frame
		passed = passed or _boss.global_position.x < on_line.x - 2.0
		if _boss.phase != Driller.Phase.CHARGE:
			break
	var moved := _planar(machine.global_position - rest).length()
	_check(passed and moved < 0.05, "la carica passa sulla macchina guasta senza spostarla (%.3f m)" % moved)
	machine.repair(1.0)
	_check(machine.health == machine.max_health and not machine.is_broken(), "riparata a vita piena per i test che seguono")
	_player._invulnerable_left = 0.0
	_boss.phase = Driller.Phase.REST
	_boss.phase_left = 60.0


## Un argine del giocatore sulla linea non e una rovina: la Trivella lo vuole e mira dritta,
## anche se la sonda di mira cade sul suo fianco (pendenza alta, delta sotto 0,8).
func _test_aims_through_rampart() -> void:
	print("aim through rampart")
	_clear_tracks()
	_place_player(Vector3(-24.0, 0.0, 0.0))
	_place_boss(Vector3(2.0, 0.0, 0.0), Driller.Phase.REST, 0.05)
	_field.sculpt(Vector3(-5.2, 0.0, 0.0), 2.0, 1.4)
	_check(await _wait_phase(Driller.Phase.AIM, 30), "mira")
	_check(_boss.charge_direction.dot(Vector3(-1.0, 0.0, 0.0)) > 0.95, "mira dritta attraverso l'argine (%.2f, %.2f)" % [_boss.charge_direction.x, _boss.charge_direction.z])
	_field.level(Vector3(-5.2, 0.0, 0.0), 2.4, _field.base_height_at(Vector3(-5.2, 0.0, 0.0)), 1.0)
	_boss.phase = Driller.Phase.REST
	_boss.phase_left = 60.0


## Un argine sulla linea ferma la carica: il varco torna alla base senza rottami e la
## Trivella resta stordita con danno doppio; poi riposa e mira di nuovo.
func _test_wall_stops_and_stuns() -> void:
	print("wall")
	_clear_tracks()
	_place_player(Vector3(-24.0, 0.0, 0.0))
	_place_boss(Vector3(2.0, 0.0, 0.0), Driller.Phase.REST, 0.05)
	var wall := Vector3(-9.6, 0.0, 0.0)
	_field.sculpt(wall, 2.0, 1.4)
	var scrap_before := _scrap.count()
	_check(await _wait_phase(Driller.Phase.CHARGE, 200), "carica verso l'argine")
	var stunned := false
	for i in 240:
		await physics_frame
		if _boss.phase == Driller.Phase.STUN:
			stunned = true
			break
	_check(stunned and _boss.walls_broken == 1 and _boss.last_wall.distance_to(wall) < 2.5, "l'argine la ferma e la stordisce (%s)" % _boss.last_wall)
	_check(_field.delta_at(wall) < 0.3, "il varco e aperto (delta %.2f)" % _field.delta_at(wall))
	_check(_scrap.count() == scrap_before, "nessun rottame dal varco")
	_check(_planar(_boss.velocity).length() < 0.3, "ferma")
	var health := _boss.health
	_boss.take_damage(5)
	_check(_boss.health == health - int(ceil(5 * _boss.stun_damage_multiplier)), "stordita subisce danno x%.0f (%d -> %d)" % [_boss.stun_damage_multiplier, health, _boss.health])
	_check(_audio.play_count(&"boss_demolish") >= 1, "suono dell'argine sfondato")
	_boss.phase_left = 0.05
	await _frames(6)
	_check(_boss.phase == Driller.Phase.REST, "finito lo stordimento riposa")
	health = _boss.health
	_boss.take_damage(5)
	_check(_boss.health == health - 5, "fuori dallo stordimento danno normale")


## Un argine con una vena sotto rende i rottami della vena (non del terreno).
func _test_wall_over_vein_gives_scrap() -> void:
	print("vein under wall")
	_clear_tracks()
	_place_player(Vector3(-24.0, 0.0, 0.0))
	_place_boss(Vector3(2.0, 0.0, 0.0), Driller.Phase.REST, 0.05)
	var wall := Vector3(-9.6, 0.0, 0.0)
	_field.sculpt(wall, 2.4, 1.5)
	_scrap.add_vein(wall, 2.4, 4, _field.base_height_at(wall) + 1.0)
	var before := _scrap.count()
	_check(await _wait_phase(Driller.Phase.CHARGE, 200), "carica")
	for i in 240:
		await physics_frame
		if _boss.phase == Driller.Phase.STUN:
			break
	_check(_boss.phase == Driller.Phase.STUN and _scrap.count() > before, "sfondando il cumulo con la vena escono rottami (%d)" % (_scrap.count() - before))
	_scrap._veins.clear()
	_boss.phase_left = 0.05
	await _frames(6)


## Review Focus 3: un rialzo basso (< 0,8 m) non la ferma.
func _test_low_mound_does_not_stop() -> void:
	print("low mound")
	_clear_tracks()
	_place_player(Vector3(-30.0, 0.0, 0.0))
	_place_boss(Vector3(2.0, 0.0, 0.0), Driller.Phase.REST, 0.05)
	_field.sculpt(Vector3(-9.6, 0.0, 0.0), 2.0, 0.5)
	var walls_before := _boss.walls_broken
	_check(await _wait_phase(Driller.Phase.CHARGE, 200), "carica")
	var stunned := false
	for i in 400:
		await physics_frame
		if _boss.phase == Driller.Phase.STUN:
			stunned = true
		if _boss.phase == Driller.Phase.REST:
			break
	_check(not stunned and _boss.walls_broken == walls_before and _boss.global_position.x < -12.0, "supera il rialzo basso senza stordirsi (x=%.1f, argini %d)" % [_boss.global_position.x, _boss.walls_broken - walls_before])


## Review Focus 4: una seconda carica sullo stesso solco non scava oltre.
func _test_furrow_is_idempotent() -> void:
	print("furrow idempotent")
	_clear_tracks()
	_place_player(Vector3(-100.0, 0.0, 0.0))
	_place_boss(Vector3(0.0, 0.0, 0.0), Driller.Phase.REST, 0.05)
	_check(await _wait_phase(Driller.Phase.CHARGE, 200), "prima carica")
	_check(await _wait_phase(Driller.Phase.REST, 700), "si ferma da sola")
	var probe := Vector3(-10.0, 0.0, 0.0)
	var first := _field.delta_at(probe)
	_check(first < -0.6 and first > -1.0, "solco a %.2f m" % first)
	_place_boss(Vector3(0.0, 0.0, 0.0), Driller.Phase.REST, 0.05)
	_check(await _wait_phase(Driller.Phase.CHARGE, 200), "seconda carica sulla stessa linea")
	_check(await _wait_phase(Driller.Phase.REST, 700), "si ferma di nuovo")
	_check(absf(_field.delta_at(probe) - first) < 0.08, "il solco resta a %.2f m (era %.2f)" % [_field.delta_at(probe), first])



## Un fossato del giocatore piu profondo del solco non viene riempito dalla carica.
func _test_furrow_does_not_fill_trench() -> void:
	print("furrow keeps trench")
	_clear_tracks()
	_place_player(Vector3(-100.0, 0.0, 0.0))
	_place_boss(Vector3(0.0, 0.0, 0.0), Driller.Phase.REST, 0.05)
	var trench := Vector3(-12.0, 0.0, 0.0)
	_field.sculpt(trench, 2.0, -1.6)
	var depth_before := _field.delta_at(trench)
	_check(await _wait_phase(Driller.Phase.CHARGE, 200), "carica attraverso il fossato")
	_check(await _wait_phase(Driller.Phase.REST, 700), "si ferma da sola")
	_check(_field.delta_at(trench) <= depth_before + 0.05, "il fossato resta profondo (%.2f, era %.2f)" % [_field.delta_at(trench), depth_before])


## La carica finisce dopo `charge_length` metri; un solco non la rallenta.
func _test_charge_length_and_trench() -> void:
	print("length and trench")
	_clear_tracks()
	_place_player(Vector3(-100.0, 0.0, 0.0))
	_place_boss(Vector3(0.0, 0.0, 0.0), Driller.Phase.REST, 0.05)
	for k in 6:
		_field.sculpt(Vector3(-8.0 - k * 2.4, 0.0, 0.0), 2.0, -0.8)
	_check(await _wait_phase(Driller.Phase.CHARGE, 200), "carica verso ovest")
	var start := _boss.global_position
	var in_trench_speed := 0.0
	for i in 600:
		await physics_frame
		if _boss.phase != Driller.Phase.CHARGE:
			break
		if _field.delta_at(_boss.global_position) < -0.4:
			in_trench_speed = maxf(in_trench_speed, _planar(_boss.velocity).length())
	var travelled := _planar(_boss.global_position - start).length()
	_check(_boss.phase == Driller.Phase.REST, "si ferma da sola")
	_check(absf(travelled - _boss.charge_length) < 2.0, "dopo %.1f m (limite %.0f)" % [travelled, _boss.charge_length])
	_check(in_trench_speed > _boss.charge_speed - 0.5, "nel solco va a piena velocita (%.1f m/s)" % in_trench_speed)


## Con una rovina sulla linea diretta mira lungo il campo di percorso invece di
## incastrarsi; fermata contro un ostacolo che non e il terreno.
func _test_blocked_by_ruin_uses_path() -> void:
	print("ruin")
	var district: RuinsDistrict = _run.district
	var block: StaticBody3D = null
	for child in district.get_children():
		if child is StaticBody3D and child.name.begins_with("Block") and absf(child.position.z) > 12.0 \
				and absf(child.position.x) < 120.0:
			block = child
			break
	_check(block != null, "una rovina bassa trovata")
	if block == null:
		return
	var size := Vector3.ZERO
	for part in block.get_children():
		if part is CollisionShape3D:
			size = ((part as CollisionShape3D).shape as BoxShape3D).size
	var side := 1.0 if block.position.z > 0.0 else -1.0
	var boss_at: Vector3 = _run._walkable_near(block.position + Vector3(0.0, 0.0, side * (size.z * 0.5 + 4.0)), 8.0)
	var player_at: Vector3 = _run._walkable_near(block.position - Vector3(0.0, 0.0, side * (size.z * 0.5 + 6.0)), 8.0)
	_place_player(player_at)
	_place_boss(boss_at, Driller.Phase.REST, 0.05)
	_check(await _wait_phase(Driller.Phase.AIM, 30), "mira")
	var direct := _planar(player_at - boss_at).normalized()
	var aimed := _planar(_boss.charge_direction).normalized()
	_check(aimed.dot(direct) < 0.98, "non mira dritto nella rovina (deviazione %.0f gradi)" % rad_to_deg(acos(clampf(aimed.dot(direct), -1.0, 1.0))))
	_check(await _wait_phase(Driller.Phase.CHARGE, 200), "carica")
	_check(await _wait_phase(Driller.Phase.REST, 700), "e si ferma (per lunghezza o ostacolo)")


## Il treno che la travolge sui binari le toglie `train_boss_damage` e la spinge fuori.
func _test_train_hits_boss() -> void:
	print("train")
	_place_player(Vector3(0.0, 0.0, 30.0))
	# A riposo (stordita il danno raddoppierebbe): resta ferma sul binario.
	_place_boss(Vector3(-20.0, 0.0, _train.track_z if _train.track_z != 0.0 else 2.4), Driller.Phase.REST, 60.0)
	var health := _boss.health
	_train.speed = 80.0
	_train.warning_seconds = 0.5
	_train.next_at = _run.elapsed + 0.55
	for i in 700:
		await physics_frame
		if _train.passes >= 1:
			break
	_check(_train.passes == 1, "un treno e passato")
	_check(_boss.health == health - _run.tuning.train_boss_damage, "la Trivella perde %d (%d -> %d)" % [_run.tuning.train_boss_damage, health, _boss.health])
	_check(not RailwayDistrict.is_on_tracks(_planar(_boss.global_position)), "e spinta fuori dalla fascia (z=%.1f)" % _boss.global_position.z)
	_train.next_at = 1.0e9


func _test_defeat_completes_level() -> void:
	print("defeat")
	var completed := [false]
	_run.level_completed.connect(func() -> void: completed[0] = true)
	_boss.phase = Driller.Phase.REST
	_boss.phase_left = 60.0
	# La piazzola di estrazione (D-076) ha la sua suite: qui si prova la vittoria diretta.
	_run.extraction_pad = null
	_boss.take_damage(_boss.health)
	await _frames(3)
	_check(completed[0] and _run.boss_phase == ArenaRun.BossPhase.DEFEATED and _run.is_over, "alla sua morte il livello e completato")
	_check(_director.enemies.is_empty(), "l'orda si ritira")
