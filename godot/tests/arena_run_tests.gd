extends SceneTree
## Test del prototipo della promessa A (D-038). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/arena_run_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")

var _failures := 0
var _scene: Node3D
var _run: ArenaRun
var _field: TerrainField
var _district: RuinsDistrict
var _player: PlayerCharacter
var _caravan: Caravan
var _director: EnemyDirector
var _weapon: AutoWeapon
var _path: PathField
var _xp: XpField
var _menu: LevelUpMenu


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_field = _scene.get_node(^"TerrainField")
	_district = _scene.get_node(^"District")
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_director = _scene.get_node(^"EnemyDirector")
	_weapon = _scene.get_node(^"PlayerWeapon")
	_path = _scene.get_node(^"PathField")
	_xp = _scene.get_node(^"XpField")
	_menu = _scene.get_node(^"LevelUpMenu")
	_director.spawning = false
	await _frames(5)
	# Dopo il _ready della scena, che riattiverebbe il passo fisico.
	_weapon.set_physics_process(false)
	_test_caravan_wiring()
	_test_courtyard_walls()
	_test_path_uses_gates()
	await _test_sealed_courtyard()
	await _test_contact_damage()
	await _test_hit_shove_and_dash()
	await _test_pit_escape_ramp()
	await _test_aim_modes()
	await _test_weapon_kills_and_drops_xp()
	await _test_xp_follows_relief()
	await _test_wall_blocks_line_of_fire()
	await _test_uphill_slows_enemies()
	await _test_dig_debris_throttled()
	await _test_level_up_flow()
	await _test_weapon_branch_flow()
	_test_caravan_upgrades()
	await _test_caravan_skips_scrap_behind_rampart()
	# Dopo i conti di macchine, attrattori e luci dei test della carovana: aggiunge macchine.
	await _test_machine_card_level_up()
	await _test_death_ends_run()
	await _test_pause_quit_confirms_and_banks()
	# T-12: i nodi messi in coda con queue_free vanno liberati prima di uscire, o
	# il motore segnala istanze ObjectDB perse all'uscita.
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Audit U-02: "Esci" dalla pausa chiede una seconda pressione e, come "Torna al menu",
## incassa la run prima di uscire (R-20). Scena nuova: quella sopra e gia finita.
func _test_pause_quit_confirms_and_banks() -> void:
	print("pause quit")
	root.remove_child(_scene)
	_scene.queue_free()
	var scene: Node3D = RunScene.instantiate()
	root.add_child(scene)
	current_scene = scene
	var run: ArenaRun = scene.get_node(^"Run")
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	await _frames(5)
	var pause := root.get_node("PauseMenu")
	var quits := [0]
	pause.set(&"quit_action", func() -> void: quits[0] += 1)
	var profile := root.get_node("PlayerProfile") as PlayerProfileService
	var runs_before := profile.runs
	pause.call(&"pause_game")
	var quit_button: Button = pause.get_node("%QuitButton")
	var label := quit_button.text
	quit_button.pressed.emit()
	_check(quits[0] == 0 and not run.is_over and quit_button.text != label, "prima pressione di Esci: chiede conferma (%s)" % quit_button.text)
	pause.call(&"resume_game")
	pause.call(&"pause_game")
	_check(quit_button.text == label, "chiudere la pausa annulla la conferma")
	quit_button.pressed.emit()
	quit_button.pressed.emit()
	_check(quits[0] == 1 and run.is_over and profile.runs == runs_before + 1, "seconda pressione: run incassata (%d run) e uscita" % profile.runs)
	pause.call(&"resume_game")
	current_scene = null
	root.remove_child(scene)
	scene.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _clear_enemies() -> void:
	for enemy in _director.enemies:
		enemy.queue_free()
	_director.enemies.clear()


func _place_player(at: Vector3) -> void:
	_player.global_position = Vector3(at.x, 0.88, at.z)
	_player.velocity = Vector3.ZERO
	_path.solve()


## Raggio in metri dell'anello del cortile di partenza.
func _ring_radius() -> float:
	return _run.tuning.wall_ring_radius * RuinsDistrict.CELL


## Chiude un varco come farebbe l'argine: tre pennellate lungo l'anello, cosi fra il tappo
## e le pennellate vicine non resta una sella calpestabile.
func _seal_gate(gate: Vector3) -> void:
	var tangent := Vector3(-gate.z, 0.0, gate.x).normalized()
	for k in [-1, 0, 1]:
		_field.sculpt(gate + tangent * 1.6 * k, 2.0, 1.4)


## I quattro varchi del cortile di partenza, sui lati dell'anello (XZ).
func _gates() -> Array[Vector3]:
	var r := _ring_radius()
	return [Vector3(0.0, 0.0, -r), Vector3(0.0, 0.0, r), Vector3(r, 0.0, 0.0), Vector3(-r, 0.0, 0.0)]


## Collegamenti della carovana nella scena (task 3 di D-093): un NodePath sbagliato in una
## scena non da errore, lascia la proprieta nulla e il gioco senza rottami ne lampioni pagati.
func _test_caravan_wiring() -> void:
	print("caravan wiring")
	var lead := _caravan.lead() if _caravan != null else null
	_check(_caravan != null and lead != null and lead.has_module(&"cargo"), "la scena ha la carovana, con un Cassone capofila")
	if lead == null:
		return
	var lamps: LampField = _scene.get_node(^"LampField")
	var audio: RunAudio = _scene.get_node(^"RunAudio")
	var quake: QuakeEvent = _scene.get_node(^"QuakeEvent")
	_check(_run.caravan == _caravan and lamps.caravan == _caravan and audio.caravan == _caravan and quake.caravan == _caravan,
		"Run, LampField, RunAudio e QuakeEvent puntano alla carovana")
	_check(_caravan.player == _player and _caravan.scrap_field == _scrap_field_node() and _caravan.path_field == _path,
		"la carovana conosce giocatore, rottami e campo di percorso")
	_check(not _scrap_field_node().veins().is_empty(), "le vene dei cumuli sono nel campo dei rottami (%d)" % _scrap_field_node().veins().size())
	_check(_run.write_queue.bodies.has(_player) and _run.write_queue.bodies.has(lead), "giocatore e capofila in write_queue.bodies")
	_check(lead.cargo().terrain_field == _field and lead.cargo().director == _director and lead.cargo().run_tuning == _run.tuning,
		"i servizi della run arrivano al Cassone")
	_check(_run.loadout.caravan == _caravan and _run.class_perks.caravan == _caravan, "loadout e carte di classe hanno la carovana")
	# Scelta 1 di D-093: il Cassone non porta piu il faro, la luce della carovana viene dai Faro.
	_check(_run.light_field.source_count() == 1 and _run.light_field.source_node(_run.torch_light_id) == _player,
		"all'inizio solo la torcia nel campo delle luci: il Cassone capofila non illumina")
	_check(_director.caravan == _caravan and is_same(_run.progression.module_count.get_object(), _caravan)
		and _run.progression.module_count.get_method() == &"count_of",
		"il direttore ha la carovana; le carte dei moduli contano le macchine della carovana")


## Il cortile di partenza e un anello di argini sul rilievo con quattro varchi piani.
func _test_courtyard_walls() -> void:
	print("courtyard")
	var ring_radius := _ring_radius()
	var start: Dictionary = _district.terrain_strokes[0]
	_check(start.kind == &"start" and is_equal_approx(start.radius, ring_radius), "il cortile di partenza e un anello di %.1f m" % ring_radius)
	var high := 0
	for p: Vector2 in start.points:
		if _field.height_at(Vector3(p.x, 0.0, p.y)) > 1.0:
			high += 1
	_check(high == start.points.size(), "l'argine supera 1 m su tutte le pennellate (%d/%d)" % [high, start.points.size()])
	var flat := true
	for i in 16:
		var angle := TAU * i / 16.0
		var p := Vector3(cos(angle), 0.0, sin(angle)) * ring_radius * 0.5
		flat = flat and absf(_field.height_at(p)) < 0.3
	_check(flat, "dentro il cortile il suolo e quasi piano")
	var gates_open := true
	for gate in _gates():
		gates_open = gates_open and absf(_field.height_at(gate)) < 0.3
	_check(gates_open, "quattro varchi aperti")
	_check(_path.is_ready(), "campo di percorso pronto")


## Da fuori gli argini il percorso attraversa l'anello solo nei varchi.
func _test_path_uses_gates() -> void:
	print("path")
	_place_player(Vector3.ZERO)
	var ring := _ring_radius()
	var start := Vector3(6.0, 0.0, -15.0)
	var point := start
	var reached := false
	var through_wall := false
	for i in 80:
		var next: Variant = _path.next_waypoint(point)
		if next == null:
			break
		point = next
		var distance := Vector2(point.x, point.z).length()
		if distance > ring - 1.2 and distance < ring + 1.2 and minf(absf(point.x), absf(point.z)) > 2.0:
			through_wall = true
		if _path.cell_of(point) == _path.cell_of(_player.global_position):
			reached = true
			break
	_check(reached, "il percorso arriva al giocatore dal nord-est esterno")
	_check(not through_wall, "il percorso passa solo dai varchi")


func _test_sealed_courtyard() -> void:
	print("sealed")
	for gate in _gates():
		_seal_gate(gate)
	await _frames(2)
	_path.solve()
	var outside := Vector3(6.0, 0.0, -15.0)
	_check(_path.cost_at(outside) == PathField.UNREACHABLE, "cortile chiuso: da fuori il giocatore e irraggiungibile")
	_check(_path.next_waypoint(outside) == null, "nessun waypoint: i nemici puntano dritto contro gli argini")
	for gate in _gates():
		_field.level(gate, 4.0, _field.base_height_at(gate), 1.0)
	await _frames(2)
	_path.solve()
	_check(_path.cost_at(outside) < PathField.UNREACHABLE, "varchi riaperti: di nuovo raggiungibile")


func _test_contact_damage() -> void:
	print("contact")
	_clear_enemies()
	_place_player(Vector3.ZERO)
	var start_health := _player.health
	_director.spawn_at(Vector3(3.0, 0.0, 0.0))
	var hit_frame := -1
	for i in 150:
		await physics_frame
		if _player.health < start_health:
			hit_frame = i
			break
	_check(hit_frame >= 0, "il rottamatore raggiunge il giocatore e lo colpisce (frame %d)" % hit_frame)
	await _frames(30)
	_check(_player.health == start_health - 1, "invulnerabilita: un solo colpo in 0,5 s (vita %d)" % _player.health)
	_clear_enemies()
	_player.set_max_health(_run.tuning.player_max_health)


## Playtest O-01: vita 10, spinta dei nemici al colpo, scatto intoccabile, vita in numero
## e lampo rosso nel HUD.
func _test_hit_shove_and_dash() -> void:
	print("hit shove and dash")
	_clear_enemies()
	_check(_run.tuning.player_max_health == 10, "vita base 10 (%d)" % _run.tuning.player_max_health)
	_player.set_max_health(_run.tuning.player_max_health)
	_place_player(Vector3.ZERO)
	var near := _director.spawn_at(Vector3(1.2, 0.0, 0.0))
	var far := _director.spawn_at(Vector3(9.0, 0.0, 0.0))
	await physics_frame
	_player._invulnerable_left = 0.0
	var start := near.global_position.x
	_check(_player.take_damage(1), "il colpo va a segno")
	_check(near.velocity.x > 4.0, "il nemico vicino viene respinto (%.1f m/s)" % near.velocity.x)
	_check(absf(far.velocity.x) < 4.0, "quello lontano no")
	await _frames(6)
	_check(near.global_position.x > start + 0.3, "il nemico arretra (%.2f -> %.2f)" % [start, near.global_position.x])
	var hud := _run.hud
	_check(hud._health_label.text == "9/10", "vita in numero nel HUD (%s)" % hud._health_label.text)
	_check(hud.damage_flash_alpha() > 0.0, "lampo rosso al colpo")
	_player._invulnerable_left = 0.0
	_player.is_dashing = true
	_check(not _player.take_damage(1) and _player.health == 9, "durante lo scatto i colpi non passano")
	_player.is_dashing = false
	_clear_enemies()
	_player.set_max_health(_run.tuning.player_max_health)
	# Playtest O-02: la terra dello zaino si vede nel HUD e segue lo zaino.
	var before := hud.gauge_text()
	_check(before.contains("m³") and before.contains("/%d" % roundi(_player.pack.capacity)), "indicatore della terra nel HUD: %s" % before)
	_player.pack.give(5.0)
	_check(hud.gauge_text().contains("%d/" % roundi(_player.pack.amount)), "la terra nel HUD segue lo zaino: %s" % hud.gauge_text())
	_player.pack.take(5.0)


## Playtest O-03: da una buca con le pareti troppo ripide si esce spingendo contro la
## parete: dopo un attimo si ritaglia una rampa e il giocatore risale.
func _test_pit_escape_ramp() -> void:
	print("pit escape")
	_clear_enemies()
	var spot := Vector3(-30.0, 0.0, 22.0)
	_field.set_protected(spot, 8.0, false)
	for i in 10:
		_field.sculpt(spot, 2.6, -0.3)
	_place_player(Vector3(spot.x, _field.height_at(spot) + 0.9, spot.z))
	await _frames(20)
	var bottom := _field.height_at(spot)
	_check(_field.grade_between(spot, spot + Vector3(1.8, 0.0, 0.0)) > _field.tuning.max_grade, "buca con le pareti troppo ripide (fondo %.2f)" % bottom)
	var start_x := _player.global_position.x
	Input.action_press(&"move_right")
	for i in 240:
		await physics_frame
	Input.action_release(&"move_right")
	_check(_player.escape_ramps >= 1, "spingendo contro la parete si ritaglia una rampa (%d)" % _player.escape_ramps)
	_check(_player.global_position.x > start_x + 2.5, "il giocatore esce dalla buca (%.1f m)" % (_player.global_position.x - start_x))
	_place_player(Vector3.ZERO)


## D-089 e playtest O-04: mira automatica e manuale commutabili; il chiodo parte dalla canna.
func _test_aim_modes() -> void:
	print("aim modes")
	_clear_enemies()
	_place_player(Vector3.ZERO)
	_player.set_aim_mode(PlayerCharacter.AimMode.AUTO)
	_check(not _weapon.manual_aim and _run.hud.aim_text() == "MIRA AUTO", "si parte in mira automatica")
	# Nemico a est, il giocatore guarda a nord. L'arma e spenta nei test: la si accende qui.
	_director.set_physics_process(false)
	_weapon.set_physics_process(true)
	_player.rotation.y = 0.0
	_director.spawn_at(Vector3(5.0, 0.0, 0.0))
	_weapon._cooldown = 0.0
	await _frames(3)
	_check(_weapon.last_fire_direction.x > 0.9, "in automatico spara verso il nemico (%s)" % str(_weapon.last_fire_direction))
	await _frames(10)
	_check(_player.facing_direction().x > 0.7, "e il corpo si gira verso il bersaglio (%s)" % str(_player.facing_direction()))
	var origin := _weapon.muzzle_toward(Vector3.RIGHT)
	_check(origin.x > _player.global_position.x + 0.4 and origin.y > _player.global_position.y + 0.1, "il chiodo parte dalla canna, davanti e piu in alto del busto")
	_player.toggle_aim_mode()
	_check(_weapon.manual_aim and _run.hud.aim_text() == "MIRA MANUALE", "il tasto passa alla mira manuale")
	var settings := root.get_node_or_null(^"GameSettings") as GameSettingsService
	_check(settings == null or settings.manual_aim, "la scelta resta nelle impostazioni")
	# In manuale spara dove guarda, anche se il nemico e altrove.
	_clear_enemies()
	_director.spawn_at(Vector3(5.0, 0.0, 0.0))
	_player._shot_facing_left = 0.0
	_player.rotation.y = 0.0
	_weapon._cooldown = 0.0
	await _frames(2)
	_player.rotation.y = 0.0
	_weapon._cooldown = 0.0
	await physics_frame
	_check(_weapon.last_fire_direction.z < -0.9, "in manuale spara dove guarda (%s)" % str(_weapon.last_fire_direction))
	_player.toggle_aim_mode()
	_check(not _weapon.manual_aim, "e si torna all'automatica")
	_weapon.set_physics_process(false)
	_director.set_physics_process(true)
	_clear_enemies()


## Audit P-01: i frammenti di esperienza stanno sopra il rilievo, non a quota fissa: su un
## cumulo non spariscono dentro il terreno, e se il suolo sale sotto di loro risalgono.
func _test_xp_follows_relief() -> void:
	print("xp on relief")
	var spot := Vector3(-14.0, 0.0, -14.0)
	_field.set_protected(spot, 4.0, false)
	_field.sculpt(spot, 2.5, 1.5)
	_xp.spawn(spot, 1)
	var node: Node3D = _xp._fragments[_xp._fragments.size() - 1].node
	_check(node.global_position.y >= _field.height_at(spot) + 0.2, "su un cumulo il frammento sta sopra il suolo (%.2f su %.2f)" % [node.global_position.y, _field.height_at(spot)])
	_field.sculpt(spot, 2.5, 1.0)
	await _frames(1)
	_check(node.global_position.y >= _field.height_at(spot) + 0.2, "il suolo sale sotto il frammento: risale (%.2f su %.2f)" % [node.global_position.y, _field.height_at(spot)])
	_field.level(spot, 3.5, _field.base_height_at(spot), 1.0)
	await _frames(1)


func _test_weapon_kills_and_drops_xp() -> void:
	print("weapon")
	_clear_enemies()
	_place_player(Vector3.ZERO)
	_director.set_physics_process(false)
	var enemy := _director.spawn_at(Vector3(5.0, 0.0, 0.0))
	var kills := _director.kills
	var fragments := _xp.count()
	_weapon.set_physics_process(true)
	await _frames(90)
	_weapon.set_physics_process(false)
	_check(not is_instance_valid(enemy) or enemy.is_dead, "la chiodatrice abbatte un rottamatore a 5 m")
	_check(_director.kills == kills + 1, "uccisione contata")
	_check(_xp.count() == fragments + 1, "rilascia un frammento di esperienza")
	# Frammenti a perdere (D-047): nascono dove muore e si liberano da soli.
	var victim := _director.spawn_at(Vector3(-6.0, 0.0, 3.0))
	victim.take_damage(victim.health)
	var bursts := _director.get_children().filter(func(n: Node) -> bool:
		return n is CPUParticles3D and (n as CPUParticles3D).global_position.distance_to(Vector3(-6.0, 0.5, 3.0)) < 0.6)
	_check(bursts.size() == 1, "un rottamatore abbattuto schizza frammenti nel punto in cui muore")
	await _frames(90)
	_check(bursts.all(func(n: Variant) -> bool: return not is_instance_valid(n)), "i frammenti si liberano da soli")
	_director.set_physics_process(true)
	await _frames(2)
	_clear_enemies()


func _test_wall_blocks_line_of_fire() -> void:
	print("line of fire")
	_clear_enemies()
	# Un punto dell'argine in diagonale, lontano dai varchi.
	var direction := Vector2(2.0 * RuinsDistrict.CELL, -_run.tuning.wall_ring_radius * RuinsDistrict.CELL).normalized()
	var outward := Vector3(direction.x, 0.0, direction.y)
	var wall := outward * _ring_radius()
	_place_player(wall - outward * 3.0)
	_director.set_physics_process(false)
	var behind := _director.spawn_at(wall + outward * 2.0)
	behind.global_position.y = _field.height_at(behind.global_position) + Enemy.spawn_height()
	await _frames(2)
	_check(_weapon.find_target() == null, "nessun bersaglio dietro un argine")
	behind.global_position = _player.global_position - outward * 3.0
	behind.global_position.y = _field.height_at(behind.global_position) + Enemy.spawn_height()
	await _frames(1)
	_check(_weapon.find_target() == behind, "lo stesso nemico allo scoperto e un bersaglio")
	_director.set_physics_process(true)
	_clear_enemies()


## In salita il rottamatore rallenta (Task 7): dosso dolce fuori dal cortile.
func _test_uphill_slows_enemies() -> void:
	print("uphill")
	_clear_enemies()
	_place_player(Vector3.ZERO)
	var mound := Vector3(0.0, 0.0, -16.0)
	_field.sculpt(mound, 5.0, 2.0)
	await _frames(2)
	_path.solve()
	var normal_enemy := _director.spawn_at(Vector3(12.0, 0.0, -12.0))
	normal_enemy.global_position.y = _field.height_at(normal_enemy.global_position) + Enemy.spawn_height()
	var slow_enemy := _director.spawn_at(Vector3(0.0, 0.0, -19.5))
	slow_enemy.global_position.y = _field.height_at(slow_enemy.global_position) + Enemy.spawn_height()
	await _frames(20)
	var normal_speed := Vector2(normal_enemy.velocity.x, normal_enemy.velocity.z).length()
	var slow_speed := Vector2(slow_enemy.velocity.x, slow_enemy.velocity.z).length()
	_check(normal_speed > 2.0, "in piano va a piena velocita (%.2f m/s)" % normal_speed)
	_check(slow_speed < normal_speed * 0.85, "in salita rallenta (%.2f m/s)" % slow_speed)
	_field.level(mound, 6.0, _field.base_height_at(mound), 1.0)
	await _frames(2)
	_clear_enemies()


## Review finale: le zolle che saltano mentre si scava sono al piu una ogni 0,2 s, non una
## per passo fisico (120 nodi al secondo).
func _test_dig_debris_throttled() -> void:
	print("dig debris")
	_place_player(Vector3.ZERO)
	_run._start_protect_left = 0.0
	_field.set_protected(Vector3.ZERO, _field.tuning.start_protected_radius_m, false)
	var before := _scene.find_children("*", "CPUParticles3D", false, false).size()
	for i in 24:
		_field.player_sculpt(Vector3(3.0, 0.0, -3.0), 2.4, -0.05, TerrainField.ToolMode.DIG)
		await physics_frame
	var bursts := _scene.find_children("*", "CPUParticles3D", false, false).size() - before
	_check(bursts >= 1 and bursts <= 3, "24 passi di scavo in 0,4 s: da 1 a 3 zolle (%d)" % bursts)
	_field.level(Vector3(3.0, 0.0, -3.0), 3.0, _field.base_height_at(Vector3(3.0, 0.0, -3.0)), 1.0)
	await _frames(2)


func _test_level_up_flow() -> void:
	print("level up")
	_place_player(Vector3.ZERO)
	var level := _run.progression.level
	_xp.spawn(_player.global_position + Vector3(1.0, 0.0, 0.0), _run.progression.xp_to_next())
	await _frames(20)
	_check(_run.progression.level == level + 1, "il frammento raccolto fa salire di livello")
	_check(_menu.is_open and paused, "si apre la scelta e il gioco si ferma")
	_check(_menu.card_count() == 3, "tre carte")
	_menu.press(0)
	_check(_menu.is_open, "carte inattive subito dopo l'apertura")
	await create_timer(0.6, true).timeout
	# La prima carta e un'arma (D-092) e una carta "Nuova macchina" non scrive i livelli
	# (D-093): si prende la prima carta del mazzo.
	_menu.press(_first_deck_card())
	await _frames(2)
	_check(not _menu.is_open and not paused, "scelta fatta: il gioco riparte")
	_check(_run.progression.levels.size() == 1, "un upgrade acquisito %s" % [_run.progression.levels])


## Indice della prima carta che non e un'arma ne una "Nuova macchina", riconosciuta dalle righe
## che il menu espone (nome, tipo); -1 se non c'e.
func _first_deck_card() -> int:
	for i in _menu.card_count():
		var lines := _menu.card_text(i).split("\n")
		if not lines[1].begins_with(MachineOffers.NAME_PREFIX) and not lines[2].begins_with(UpgradeCatalog.CATEGORY_NAMES[&"weapon"]):
			return i
	return -1


## D-092: la carta bivio apre la scelta fra due trasformazioni; il livello sale solo dopo,
## e un secondo level-up in coda si apre dopo la trasformazione.
func _test_weapon_branch_flow() -> void:
	print("weapon branch")
	var loadout := _run.loadout
	_check(loadout != null and loadout.has_weapon(&"nailgun") and loadout.has_weapon(&"seismic_stake"), "kit dell'Ingegnere nella run")
	loadout.level_up(&"nailgun")
	_run._pending_level_ups = 2
	_run._on_upgrade_chosen(&"w:branch:nailgun")
	_check(_menu.is_open and _menu.card_count() == 2 and _menu.title_text() == "CHIODATRICE", "si apre la scelta della trasformazione")
	_check(loadout.level_of(&"nailgun") == 2 and _run._pending_level_ups == 2, "il livello non e ancora salito")
	await create_timer(0.6, true).timeout
	_menu.press(1)
	await _frames(3)
	_check(loadout.level_of(&"nailgun") == 3 and loadout.weapon(&"nailgun").has_branch(&"bridge"), "scelta: Chiodi da ponte al livello 3")
	_check(_menu.is_open and _menu.card_count() == 3 and _run._pending_level_ups == 1, "poi si apre il level-up rimasto")
	await create_timer(0.6, true).timeout
	# Una carta del mazzo: una macchina in piu cambierebbe i conti di _test_caravan_upgrades.
	_menu.press(_first_deck_card())
	await _frames(2)
	_check(not _menu.is_open and not paused, "finite le scelte il gioco riparte")


## Audit C-01: un rottame raggiungibile solo aggirando un argine non e una meta in linea
## retta: il Cassone spingerebbe contro l'argine finche il giocatore non si allontana.
func _test_caravan_skips_scrap_behind_rampart() -> void:
	print("caravan and rampart")
	var p := Vector3(-30.0, 0.0, 30.0)
	_field.set_protected(p, 16.0, false)
	_place_player(p)
	for x in range(-10, 11, 2):
		_field.sculpt(p + Vector3(x, 0.0, 3.5), 1.6, 1.6)
	var lead := _caravan.lead()
	lead.global_position = p + Vector3(0.0, _field.height_at(p) + 0.3, 1.0)
	lead.reset_physics_interpolation()
	_path.solve()
	# A 5,8 m e non a 6: il limite di raccolta e 6 m dal giocatore, sul bordo il rottame
	# potrebbe restare fuori e il controllo passerebbe senza provare la linea dritta.
	var scrap := p + Vector3(0.0, 0.0, 5.8)
	_scrap_field_node().spawn_on_ground(scrap)
	await _frames(2)
	_check(_path.cost_at(scrap) != PathField.UNREACHABLE and Vector2(scrap.x - _player.global_position.x, scrap.z - _player.global_position.z).length() <= _caravan.tuning.pickup_radius_from_player,
		"il rottame ha una strada attorno all'argine ed e entro il raggio di raccolta")
	# Il Cassone ricerca la meta al piu ogni 0,2 s: una soluzione nuova del percorso la fa rifare ora.
	_path.solve()
	# Un Cassone guasto o in ritirata non chiede mete: il controllo sotto sarebbe vuoto.
	_check(lead.state == Machine.State.OK, "il capofila e in ordine (stato %d, %d PV)" % [lead.state, lead.health])
	var destination: Vector3 = lead._choose_destination()
	_check(Vector2(destination.x - scrap.x, destination.z - scrap.z).length() > 1.0,
		"rottame dietro un argine: non e la meta del Cassone (meta a %.1f m dal rottame)" % Vector2(destination.x - scrap.x, destination.z - scrap.z).length())
	_scrap_field_node().take_near(scrap, 1.5, 10)
	_field.reset_to_base(p + Vector3(0.0, 0.0, 3.5), Vector2(13.0, 3.0))


func _scrap_field_node() -> ScrapField:
	return _scene.get_node(^"ScrapField")


func _test_caravan_upgrades() -> void:
	print("caravan upgrades")
	var lead := _caravan.lead()
	var base_capacity := _caravan.tuning.cargo_capacity
	# Il level-up precedente sceglie una carta a caso: puo gia essere il cassone.
	var capacity_before := _caravan.capacity
	_run.apply_upgrade(&"companion_cargo", 1)
	_check(_caravan.capacity == capacity_before + 2, "cassone rinforzato: capacita +2")
	_check(_caravan.tuning.cargo_capacity == base_capacity, "la risorsa di tuning non cambia")
	# Torretta, Calamita e Faro sono moduli di macchine proprie (task 4 di D-093), non pezzi
	# del capofila; le carte di livello passano dal livello del tipo.
	var turret_machine := _caravan.add_machine(&"turret")
	var turret: TurretModule = turret_machine.module(&"turret") as TurretModule if turret_machine != null else null
	_check(turret != null and turret.weapon() != null and turret.weapon().shooter == turret_machine and turret_machine.has_node(^"TurretPart"),
		"la macchina Torretta spara da se e ha il suo pezzo")
	_check(not lead.has_node(^"TurretPart"), "il capofila non monta la torretta")
	var magnet_machine := _caravan.add_machine(&"magnet")
	_check(magnet_machine != null and magnet_machine.has_node(^"MagnetPart") and _xp.attractors.size() == 1 and _xp.attractors[0].node == magnet_machine,
		"la macchina Calamita ha il suo pezzo ed e l'unico attrattore")
	_check(not lead.has_node(^"MagnetPart"), "il capofila non attira")
	var beacon_machine := _caravan.add_machine(&"beacon")
	var beacon: BeaconModule = beacon_machine.module(&"beacon") as BeaconModule if beacon_machine != null else null
	_check(beacon != null and _run.light_field.source_count() == 2 and _run.light_field.source_node(beacon.light_id) == beacon_machine
		and is_equal_approx(_run.light_field.radius_of(beacon.light_id), _run.tuning.beacon_radius),
		"la macchina Faro e la seconda sorgente di luce, di %.0f m (la macchina, non la carovana)" % _run.tuning.beacon_radius)
	if turret == null or beacon == null or magnet_machine == null:
		return
	var rate := _caravan.tuning.turret_rate_per_level
	_run.apply_upgrade(&"turret_rate", 1)
	_check(is_equal_approx(turret.weapon().fire_interval, _caravan.tuning.turret_interval / rate) and _caravan.module_level(&"turret") == 1,
		"Torretta veloce 1: intervallo %.3f s" % turret.weapon().fire_interval)
	_run.apply_upgrade(&"magnet_range", 1)
	_check(is_equal_approx(_xp.attractors[0].radius, _caravan.tuning.magnet_radius + _caravan.tuning.magnet_radius_per_level),
		"Calamita potente: raggio %.1f m" % _xp.attractors[0].radius)
	_run.apply_upgrade(&"beacon_range", 1)
	_check(is_equal_approx(_run.light_field.radius_of(beacon.light_id), _run.tuning.beacon_radius + _run.tuning.beacon_radius_per_level),
		"Faro 1: raggio %.0f m" % _run.light_field.radius_of(beacon.light_id))


## D-093, Sezione 5: una carta "Nuova macchina" in un level-up vero. Il provider offre solo la
## Torretta e il recupero del Raro e dovuto: per l'Ingegnere la carta e l'unica Rara del pool,
## quindi entra nell'offerta qualunque sia il seme.
func _test_machine_card_level_up() -> void:
	print("machine card")
	var progression := _run.progression
	var provider := progression.machine_cards
	var available := _run._available_modules()
	_check(available.has(&"turret") and available.all(func(id: StringName) -> bool: return Caravan.module_script_for(id) != MachineModule),
		"si offrono solo i moduli con uno script (%s)" % [available])
	_check(_caravan.has_room() and provider.call().size() == available.size(), "con posto nella carovana una carta per modulo disponibile")
	progression.machine_cards = func() -> Array[Dictionary]: return [MachineOffers.card(&"turret", _run.class_id)] as Array[Dictionary]
	progression.level_ups_without_rare = progression.pity_level_ups
	_place_player(Vector3.ZERO)
	var levels := progression.levels.duplicate()
	var machines := _caravan.machines.size()
	var turrets := _caravan.count_of(&"turret")
	# Due livelli: dopo la carta macchina si apre il level-up rimasto.
	_xp.spawn(_player.global_position + Vector3(1.0, 0.0, 0.0),
		progression.xp_to_next() - progression.xp + progression.xp_to_next() + progression.xp_growth)
	await _frames(20)
	var pending := _run._pending_level_ups
	var index := -1
	for i in _menu.card_count():
		if _menu.card_text(i).split("\n")[1] == MachineOffers.NAME_PREFIX + MachineCatalog.name_of(&"turret"):
			index = i
	_check(_menu.is_open and pending == 2 and index >= 0, "level-up con la carta Nuova macchina: Torretta (carta %d, %d level-up)" % [index, pending])
	if index < 0:
		# Niente menu aperto ne pausa per i casi dopo.
		progression.machine_cards = provider
		_run._pending_level_ups = 0
		_menu.close()
		paused = false
		return
	_check(_menu.card_text(index).contains("NUOVO") and _menu.card_icon(index).kind == MachineCatalog.find(&"turret").icon,
		"la carta mostra NUOVO e l'icona del modulo")
	await create_timer(0.6, true).timeout
	_menu.press(index)
	await _frames(2)
	var added := _caravan.machines.back() as Machine
	_check(_caravan.machines.size() == machines + 1 and _caravan.count_of(&"turret") == turrets + 1, "scelta: una macchina in piu, con la Torretta")
	_check(_run._pending_level_ups == pending - 1 and progression.levels == levels, "consuma un level-up e non scrive i livelli")
	_check(_run.write_queue.bodies.has(added) and added.module(&"turret").level == _caravan.module_level(&"turret"),
		"la macchina nuova ha i servizi della run e il livello del tipo (%d)" % _caravan.module_level(&"turret"))
	_check(_menu.is_open, "si apre il level-up rimasto")
	await create_timer(0.6, true).timeout
	_menu.press(_first_deck_card())
	await _frames(2)
	_check(not _menu.is_open and not paused and _run._pending_level_ups == 0, "finite le scelte il gioco riparte")
	progression.machine_cards = provider
	while _caravan.has_room() and _caravan.add_machine(&"turret") != null:
		pass
	_check(_caravan.module_count() == _caravan.tuning.module_limit and MachineOffers.cards(_caravan, _run.class_id, available).is_empty()
		and provider.call().is_empty(), "carovana piena (%d moduli): nessuna carta macchina" % _caravan.module_count())


func _test_death_ends_run() -> void:
	print("death")
	_clear_enemies()
	_player.set_max_health(1)
	await _frames(60)
	_player.take_damage(1)
	await _frames(2)
	var game_over: GameOverPanel = _scene.get_node(^"GameOverPanel")
	_check(_run.is_over and game_over.is_open and paused, "vita a zero: fine run e gioco fermo")
	paused = false
