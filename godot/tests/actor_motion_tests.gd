extends SceneTree
## Test del movimento procedurale degli attori (ActorMotion). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/actor_motion_tests.gd
## Invarianti: il movimento tocca solo i visual (corpi fisici e collisioni identici con
## l'interruttore acceso o spento), i visual tornano a riposo da fermi, gli scostamenti
## restano nei limiti dichiarati dalle costanti, i rottamatori hanno fasi diverse,
## l'interruttore globale ferma tutto.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CARAVAN_TUNING := preload("res://resources/tuning/caravan_default.tres")
const EPSILON := 0.0001

var _failures := 0
var _world: Node3D
var _player: PlayerCharacter
var _caravan: Caravan
## La macchina della carovana (il compagno di oggi, D-093 task 3).
var _machine: Machine
var _director: EnemyDirector
var _boss: Demolisher
var _enemies: Array[Enemy] = []


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _test_bodies_unchanged_by_motion()
	await _test_player()
	await _test_machine()
	await _test_scavengers()
	await _test_boss()
	await _test_off_switch()
	ActorMotion.enabled = true
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


## Pavimento, giocatore, carovana con una macchina, sei rottamatori e un Demolitore (senza griglia: il
## boss non si guida da solo, il test gli da la velocita che serve).
func _build_world() -> void:
	_world = Node3D.new()
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	_player = PLAYER_SCENE.instantiate()
	_player.position = Vector3(0.0, 0.9, 0.0)
	_world.add_child(_player)
	_caravan = Caravan.new()
	_caravan.tuning = CARAVAN_TUNING
	_caravan.player = _player
	_caravan.position = Vector3(3.0, 0.32, 3.0)
	_world.add_child(_caravan)
	_director = EnemyDirector.new()
	_director.player = _player
	_director.spawning = false
	_world.add_child(_director)
	root.add_child(_world)
	await _frames(2)
	# La macchina nasce nel _ready della carovana.
	_machine = _caravan.lead()
	_enemies.clear()
	for i in 6:
		_enemies.append(_director.spawn_at(Vector3(-6.0 + i * 1.3, 0.0, -7.0 - (i % 2))))
	_boss = Demolisher.new()
	_boss.setup_demolisher(50, _director.flash_material())
	_director.add_enemy(_boss, Vector3(9.0, Demolisher.boss_spawn_height(), -6.0))
	await _frames(10)


func _free_world() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(action)
	_world.queue_free()
	await _frames(2)


## Una sequenza fissa di gioco: corsa, dash, colpi subiti e dati. Restituisce le
## trasformazioni di corpi e collisioni alla fine.
func _play_sequence() -> Array[Transform3D]:
	await _build_world()
	Input.action_press(&"move_right")
	await _frames(30)
	_player._start_dash()
	_player.on_hit()
	_player.kick(Vector3.LEFT)
	for enemy in _enemies:
		enemy.take_damage(1)
		enemy.notify_contact()
	_boss.take_damage(1)
	_boss.velocity = Vector3(0.0, 0.0, 1.5)
	_caravan.spend()
	await _frames(25)
	Input.action_release(&"move_right")
	Input.action_press(&"move_forward")
	await _frames(25)
	Input.action_release(&"move_forward")
	await _frames(10)
	var result: Array[Transform3D] = [_player.global_transform, _machine.global_transform, _boss.global_transform,
		_player.get_node(^"Collision").global_transform, _machine.get_node(^"Collision").global_transform]
	for enemy in _enemies:
		result.append(enemy.global_transform)
		result.append((enemy.get_child(0) as CollisionShape3D).global_transform)
	await _free_world()
	return result


func _test_bodies_unchanged_by_motion() -> void:
	print("Corpi fisici identici con e senza movimento procedurale")
	# La prima esecuzione nel processo differisce di qualche centimetro sulla macchina anche
	# a parita di interruttore (riscaldamento del motore fisico): si scarta.
	await _play_sequence()
	ActorMotion.enabled = true
	var animated := await _play_sequence()
	ActorMotion.enabled = false
	var still := await _play_sequence()
	ActorMotion.enabled = true
	_check(animated.size() == still.size() and animated.size() == 17, "stessa scena nelle due esecuzioni (%d corpi e collisioni)" % animated.size())
	var worst := 0.0
	for i in mini(animated.size(), still.size()):
		worst = maxf(worst, animated[i].origin.distance_to(still[i].origin))
		worst = maxf(worst, animated[i].basis.x.distance_to(still[i].basis.x) + animated[i].basis.z.distance_to(still[i].basis.z))
	_check(worst < EPSILON, "posizioni e rotazioni di corpi e collisioni coincidono (scarto %.6f)" % worst)
	_check(animated[0].origin.length() > 2.0, "la sequenza ha davvero mosso il giocatore")


func _test_player() -> void:
	print("Giocatore")
	await _build_world()
	_director.set_physics_process(false)
	var model: Node3D = _player.get_node(^"Model")
	var rest := _player._model_rest
	var collision: CollisionShape3D = _player.get_node(^"Collision")
	_check(model.transform.is_equal_approx(rest), "da fermo il modello e a riposo")

	Input.action_press(&"move_forward")
	var max_bob := 0.0
	var min_bob := 0.0
	var max_tilt := 0.0
	var poses := {}
	for i in 40:
		await physics_frame
		var offset := model.transform.origin - rest.origin
		max_bob = maxf(max_bob, offset.y)
		min_bob = minf(min_bob, offset.y)
		max_tilt = maxf(max_tilt, model.transform.basis.y.angle_to(Vector3.UP))
		poses[snappedf(offset.y, 0.001)] = true
	# Il passo lo fanno le animazioni dello scheletro (character_animator_tests.gd): il modello non saltella.
	_check(absf(max_bob) < EPSILON and absf(min_bob) < EPSILON, "camminando il modello non sale ne scende (max %.3f)" % max_bob)
	_check(_player._animator != null and _player._animator.move_blend() > 0.5,
		"camminando l'animatore passa alla corsa (%.2f)" % (_player._animator.move_blend() if _player._animator != null else -1.0))
	_check(max_tilt > _player.tuning.lean_angle * 0.7 and max_tilt <= _player.tuning.lean_angle + EPSILON,
		"si inclina in avanti entro LEAN_ANGLE (%.3f rad)" % max_tilt)
	_check((model.transform.basis.y.normalized()).z < -0.05, "l'inclinazione va nella direzione di marcia (avanti = -Z)")
	_check(is_zero_approx(_player.rotation.x) and is_zero_approx(_player.rotation.z) and _player.scale.is_equal_approx(Vector3.ONE),
		"il corpo fisico non si inclina e non si scala")
	_check(collision.transform.is_equal_approx(Transform3D.IDENTITY), "la collisione non si muove")

	# Dash: la scala del dash resta su _body, l'impulso sta sul modello.
	_player._start_dash()
	await physics_frame
	_check(_player._animator.fired_count(&"dodge") == 1, "lo scatto chiede la capriola all'animatore")
	_check(_player.is_dashing and _player._body.scale.is_equal_approx(_player._base_body_scale * _player.tuning.dash_scale_multiplier),
		"nel dash la scala 1,15 del corpo visivo resta quella del codice di gioco")
	var squash := model.transform.basis.get_scale()
	_check(squash.y < 1.0 - _player.tuning.dash_squash * 0.3 and squash.y >= 1.0 - _player.tuning.dash_squash - EPSILON and squash.x > 1.0,
		"partenza del dash: schiacciato entro DASH_SQUASH (y %.3f)" % squash.y)
	while _player.is_dashing:
		await physics_frame
	await physics_frame
	var stretch := model.transform.basis.get_scale()
	_check(stretch.y > 1.0 + _player.tuning.dash_stretch * 0.3 and stretch.y <= 1.0 + _player.tuning.dash_stretch + EPSILON,
		"arrivo del dash: allungato entro DASH_STRETCH (y %.3f)" % stretch.y)
	_check(_player._body.scale.is_equal_approx(_player._base_body_scale), "a fine dash la scala del corpo visivo torna quella base")
	Input.action_release(&"move_forward")
	await _frames(40)
	_check(model.transform.is_equal_approx(rest), "fermo dopo corsa e dash: modello di nuovo a riposo")

	# Colpo: sussulto insieme al lampo rosso.
	_player.on_hit()
	await physics_frame
	var flinch := model.transform
	_check(_player._hit_flash_left > 0.0 and flinch.origin.z - rest.origin.z > _player.tuning.flinch_back * 0.4
		and flinch.origin.z - rest.origin.z <= _player.tuning.flinch_back + EPSILON and flinch.basis.get_scale().y < 1.0,
		"colpito: arretra e si schiaccia entro i limiti mentre lampeggia")
	await _frames(int(_player.tuning.flinch_seconds * 60.0) + 12)
	_check(model.transform.is_equal_approx(rest), "dopo il sussulto torna a riposo")

	# Rinculo: opposto al colpo, nello spazio del personaggio.
	_player.rotation.y = PI * 0.5
	_player.kick(Vector3.RIGHT)
	await physics_frame
	var pushed := _player.global_basis * (model.transform.origin - rest.origin)
	_check(pushed.x > _player.tuning.recoil_back * 0.3 and pushed.length() <= _player.tuning.recoil_back + EPSILON and absf(pushed.z) < 0.01,
		"rinculo nella direzione chiesta, entro RECOIL_BACK (%.3f m)" % pushed.length())
	await _frames(int(_player.tuning.recoil_seconds * 60.0) + 12)
	_check(model.transform.is_equal_approx(rest), "dopo il rinculo torna a riposo")

	# Collegamento opzionale all'arma, senza dipendenza diretta.
	var weapon := AutoWeapon.new()
	_world.add_child(weapon)
	_player.recoil_source = weapon
	weapon.fired.connect(_player._on_recoil_source_fired)
	weapon.last_fire_direction = Vector3.FORWARD
	weapon.fired.emit(1)
	_check(_player._recoil == 1.0 and (_player.global_basis * _player._recoil_direction).is_equal_approx(Vector3.BACK),
		"il segnale fired dell'arma da un rinculo opposto al colpo")
	await _free_world()


func _test_machine() -> void:
	print("Macchina della carovana")
	await _build_world()
	_director.set_physics_process(false)
	await _frames(60)
	var model: Node3D = _machine.get_node(^"Model")
	var rest := _machine._model_rest
	var idle_limit := Machine.SHIVER_HEIGHT + Machine.SHIVER_ROLL * (Machine.WHEEL_HALF_WIDTH + 1.0) + EPSILON
	var worst := 0.0
	var lowest := 0.0
	var poses := {}
	for i in 30:
		await physics_frame
		worst = maxf(worst, model.transform.origin.distance_to(rest.origin))
		lowest = minf(lowest, model.transform.origin.y - rest.origin.y)
		poses[snappedf(model.transform.basis.y.x, 0.0005)] = true
	_check(_machine.velocity.length() < 0.05, "la macchina e ferma accanto al giocatore")
	_check(worst <= idle_limit and lowest >= -EPSILON, "da fermo resta entro il tremito del motore (%.4f <= %.4f), mai sotto terra" % [worst, idle_limit])
	_check(poses.size() > 3, "il tremito del motore si vede (%d pose)" % poses.size())

	# Carico che cambia: cubetti che ballano, poi fermi sul pianale.
	var cube := _machine._cargo[0]
	var cube_rest := _machine._cargo_rest[0]
	_caravan.spend()
	var hop := 0.0
	for i in 12:
		await physics_frame
		hop = maxf(hop, cube.transform.origin.y - cube_rest.y)
	_check(hop > Machine.CARGO_WOBBLE_HOP * 0.3 and hop <= Machine.CARGO_WOBBLE_HOP + Machine.BOUNCE_MAX + idle_limit,
		"speso un rottame i cubetti saltano entro i limiti (%.3f m)" % hop)
	await _frames(int(Machine.CARGO_WOBBLE_SECONDS * 60.0) + 40)
	_check(cube.transform.origin.distance_to(cube_rest) <= idle_limit and cube.get_parent() == _machine,
		"poi tornano sul pianale, sempre figli della macchina")

	# Pezzi montati: figli diretti (chi li cerca per nome li trova) e solidali al telaio.
	var part := Node3D.new()
	part.position = Vector3(0.0, 0.42, -0.25)
	_machine.mount_part(&"TurretPart", part)
	var replacement := Node3D.new()
	replacement.position = Vector3(0.0, 0.42, -0.25)
	_machine.mount_part(&"TurretPart", replacement)
	await _frames(2)
	_check(replacement.get_parent() == _machine and _machine._parts.size() == 1 and _machine._parts[0] == replacement,
		"un pezzo rimontato sostituisce il vecchio e resta figlio diretto della macchina")
	# R-38: il terzo montaggio dello stesso nome non deve accumulare pezzi ne rinominarli.
	var third := Node3D.new()
	third.position = Vector3(0.0, 0.42, -0.25)
	_machine.mount_part(&"TurretPart", third)
	await _frames(2)
	var named := _machine.get_children().filter(func(n: Node) -> bool: return n.name == &"TurretPart")
	_check(named.size() == 1 and named[0] == third and _machine._parts.size() == 1 and _machine.has_node(^"TurretPart"),
		"al terzo montaggio c'e un solo TurretPart, col nome giusto")

	# In marcia: si inclina, sobbalza e tutto resta attaccato al telaio.
	Input.action_press(&"move_right")
	var max_tilt := 0.0
	var max_rise := 0.0
	var min_rise := 0.0
	var max_gap := 0.0
	var moved := false
	for i in 90:
		await physics_frame
		if i == 45:
			Input.action_release(&"move_right")
			Input.action_press(&"move_back")
		max_tilt = maxf(max_tilt, model.transform.basis.y.angle_to(Vector3.UP))
		var rig := model.transform * rest.affine_inverse()
		max_rise = maxf(max_rise, rig.origin.y)
		min_rise = minf(min_rise, (rig * Machine.RIG_GROUND).y - Machine.RIG_GROUND.y)
		max_gap = maxf(max_gap, third.transform.origin.distance_to(rig * Vector3(0.0, 0.42, -0.25)))
		moved = moved or _machine.velocity.length() > 2.0
	Input.action_release(&"move_back")
	var tilt_limit := Machine.TILT_MAX * 1.42 + Machine.SHIVER_ROLL
	var rise_limit := Machine.BOUNCE_MAX + Machine.ROAD_BUMP + Machine.SHIVER_HEIGHT \
		+ tilt_limit * (Machine.WHEEL_HALF_LENGTH + Machine.WHEEL_HALF_WIDTH + absf(Machine.RIG_GROUND.y))
	_check(moved and max_tilt > 0.02 and max_tilt <= tilt_limit, "seguendo il giocatore si inclina entro TILT_MAX (%.3f rad)" % max_tilt)
	_check(max_rise <= rise_limit and min_rise >= -EPSILON, "sobbalza entro i limiti (%.3f m) e le ruote non entrano nel terreno" % max_rise)
	_check(max_gap < EPSILON, "il pezzo montato resta solidale al telaio")
	_check(is_zero_approx(_machine.rotation.x) and is_zero_approx(_machine.rotation.z)
		and (_machine.get_node(^"Collision") as Node3D).transform.is_equal_approx(Transform3D.IDENTITY),
		"corpo fisico e collisione non si inclinano")
	await _free_world()


func _test_scavengers() -> void:
	print("Rottamatori")
	await _build_world()
	var phases := {}
	for enemy in _enemies:
		phases[snappedf(fposmod(enemy.gait_phase(), TAU), 0.01)] = true
	_check(phases.size() == _enemies.size(), "ogni rottamatore ha la sua fase d'andatura (%d su %d)" % [phases.size(), _enemies.size()])

	var enemy := _enemies[0]
	var rest := enemy._body_rest
	var max_lift := Enemy.GAIT_ROLL * Enemy.FOOTPRINT_HALF_WIDTH + Enemy.GAIT_BOB
	var seen_lift := 0.0
	var seen_roll := 0.0
	var lowest := 0.0
	var rolls := {}
	for i in 60:
		await physics_frame
		for other in _enemies:
			var offset := other._body.transform.origin - other._body_rest.origin
			seen_lift = maxf(seen_lift, offset.y)
			lowest = minf(lowest, offset.y)
			seen_roll = maxf(seen_roll, absf(other._body.rotation.z))
		rolls[snappedf(_enemies[0]._body.rotation.z - _enemies[1]._body.rotation.z, 0.002)] = true
	_check(enemy.velocity.length() > 1.0, "i rottamatori inseguono il giocatore")
	_check(seen_roll > Enemy.GAIT_ROLL * 0.8 and seen_roll <= Enemy.GAIT_ROLL + EPSILON, "andatura a papera entro GAIT_ROLL (%.3f rad)" % seen_roll)
	_check(seen_lift > 0.01 and seen_lift <= max_lift + EPSILON and lowest >= -EPSILON, "si alzano entro il limite (%.3f m), mai sotto terra" % seen_lift)
	_check(rolls.size() > 4, "due rottamatori non oscillano a tempo")
	_check(is_zero_approx(enemy.rotation.x) and is_zero_approx(enemy.rotation.z) and enemy.scale.is_equal_approx(Vector3.ONE)
		and (enemy.get_child(0) as CollisionShape3D).transform.is_equal_approx(Transform3D.IDENTITY),
		"corpo fisico e collisione non oscillano")

	# Da qui i nemici li muove il test: fermi, poi colpo e affondo.
	_director.set_physics_process(false)
	for other in _enemies:
		other.velocity = Vector3.ZERO
	for i in 20:
		for other in _enemies:
			other.tick_visuals(1.0 / 60.0)
	var all_rest := true
	for other in _enemies:
		all_rest = all_rest and other._body.transform.is_equal_approx(other._body_rest)
	_check(all_rest, "da fermi tornano tutti a riposo")

	enemy.set_carrying(true)
	_check(enemy._cargo.get_parent() == enemy._body and (enemy._body_rest * enemy._cargo.position).is_equal_approx(Vector3(0.0, 0.35, 0.06)),
		"il rottame portato e figlio del visual, alla stessa altezza di prima")
	enemy.take_damage(1)
	enemy.tick_visuals(1.0 / 60.0)
	var back := enemy._body.transform.origin.z - rest.origin.z
	_check(back > Enemy.STAGGER_BACK * 0.5 and back <= Enemy.STAGGER_BACK + EPSILON and enemy._body.rotation.x > 0.0,
		"colpito: spinto indietro entro STAGGER_BACK (%.3f m), muso in su" % back)
	_check(is_equal_approx(enemy.position.y, Enemy.spawn_height()) or enemy.is_on_floor(), "il corpo fisico non arretra")
	for i in int(Enemy.STAGGER_SECONDS * 60.0) + 2:
		enemy.tick_visuals(1.0 / 60.0)
	_check(enemy._body.transform.is_equal_approx(rest), "dopo il barcollamento torna a riposo")

	enemy.notify_contact()
	var reach := 0.0
	for i in int((Enemy.LUNGE_SECONDS + Enemy.LUNGE_PAUSE) * 60.0) + 3:
		enemy.tick_visuals(1.0 / 60.0)
		reach = minf(reach, enemy._body.transform.origin.z - rest.origin.z)
	_check(reach < -Enemy.LUNGE_REACH * 0.8 and reach >= -Enemy.LUNGE_REACH - EPSILON, "a contatto: affondo in avanti entro LUNGE_REACH (%.3f m)" % -reach)
	_check(enemy._body.transform.is_equal_approx(rest), "dopo l'affondo torna a riposo")
	await _free_world()


func _test_boss() -> void:
	print("Demolitore")
	await _build_world()
	_director.set_physics_process(false)
	var rig := _boss._rig
	var step := 1.0 / 60.0
	_check(_boss._blade.get_parent() == rig and _boss._body.get_parent() == rig and rig.get_parent() == _boss,
		"scafo e lama sono figli del telaio; la lama resta un nodo a parte")
	_check(_boss._blade.position.is_equal_approx(Demolisher.BLADE_REST), "lama a BLADE_REST")
	for i in 5:
		_boss.tick_visuals(step)
	_check(rig.transform.is_equal_approx(Transform3D.IDENTITY), "da fermo il telaio e a riposo")

	# Partenza e marcia: peso indietro, poi vibrazione dei cingoli.
	_boss.velocity = -_boss.global_basis.z * _boss.speed
	var max_pitch := 0.0
	var max_roll := 0.0
	var lowest := 0.0
	var poses := {}
	for i in 60:
		_boss.tick_visuals(step)
		max_pitch = maxf(max_pitch, rig.rotation.x)
		max_roll = maxf(max_roll, absf(rig.rotation.z))
		lowest = minf(lowest, (rig.transform * Demolisher.RIG_GROUND).y - Demolisher.RIG_GROUND.y)
		poses[snappedf(rig.transform.origin.y, 0.0005)] = true
	_check(max_pitch > 0.01 and max_pitch <= Demolisher.SHIFT_MAX + EPSILON, "partendo alza il muso entro SHIFT_MAX (%.3f rad)" % max_pitch)
	_check(max_roll > Demolisher.RUMBLE_ROLL * 0.7 and max_roll <= Demolisher.RUMBLE_ROLL + EPSILON and poses.size() > 6,
		"in marcia i cingoli vibrano entro RUMBLE_ROLL (%.4f rad)" % max_roll)
	_check(lowest >= -EPSILON, "i cingoli non entrano nel terreno")
	_boss.velocity = Vector3.ZERO
	var min_pitch := 0.0
	for i in 90:
		_boss.tick_visuals(step)
		min_pitch = minf(min_pitch, rig.rotation.x)
	_check(min_pitch < -0.01 and min_pitch >= -Demolisher.SHIFT_MAX - EPSILON, "fermandosi abbassa il muso (%.3f rad)" % min_pitch)
	_check(rig.transform.is_equal_approx(Transform3D.IDENTITY), "fermo: il telaio torna a riposo")

	# Martello: lo scafo carica a tempo con la lama, che resta guidata dal codice di gioco.
	_boss.demolish_point = Vector3.ZERO
	var windup := 0.0
	for i in 40:
		_boss._demolish_left = 1.2 - i * step
		var raised := absf(sin(_boss._demolish_left * Demolisher.BLADE_HAMMER_RATE))
		_boss._blade.position.y = Demolisher.BLADE_REST.y + raised * Demolisher.BLADE_HAMMER_LIFT
		_boss.tick_visuals(step)
		windup = maxf(windup, rig.rotation.x)
		if i > 20:
			_failures += 0 if absf(rig.rotation.x - Demolisher.WINDUP_PITCH * raised) < 0.003 else 1
	_check(windup > Demolisher.WINDUP_PITCH * 0.8 and windup <= Demolisher.WINDUP_PITCH + EPSILON,
		"martellando lo scafo carica a tempo con la lama, entro WINDUP_PITCH (%.3f rad)" % windup)
	_check(is_equal_approx(_boss._blade.position.x, Demolisher.BLADE_REST.x) and is_equal_approx(_boss._blade.position.z, Demolisher.BLADE_REST.z),
		"la posizione locale della lama resta quella del codice di gioco")
	_boss.demolish_point = Vector3.INF
	_boss._blade.position.y = Demolisher.BLADE_REST.y
	for i in 30:
		_boss.tick_visuals(step)
	_check(rig.transform.is_equal_approx(Transform3D.IDENTITY), "finita la demolizione il telaio torna a riposo")

	# Colpo: barcollamento pesante, piu lungo e piu corto in metri di quello di un rottamatore.
	var body_before := _boss.global_transform
	_boss.take_damage(1)
	_boss.tick_visuals(step)
	var back := rig.transform.origin.z
	_check(back > Demolisher.HEAVY_STAGGER_BACK * 0.5 and back <= Demolisher.HEAVY_STAGGER_BACK + Demolisher.HEAVY_STAGGER_PITCH * Demolisher.BODY_HEIGHT,
		"colpito: il telaio arretra entro HEAVY_STAGGER_BACK (%.3f m)" % back)
	_check(_boss.global_transform.is_equal_approx(body_before), "il corpo fisico del boss non si sposta")
	for i in int(Demolisher.HEAVY_STAGGER_SECONDS * 60.0) + 30:
		_boss.tick_visuals(step)
	_check(rig.transform.is_equal_approx(Transform3D.IDENTITY), "dopo il barcollamento torna a riposo")
	await _free_world()


func _test_off_switch() -> void:
	print("Interruttore globale")
	await _build_world()
	Input.action_press(&"move_right")
	_boss.velocity = Vector3(0.0, 0.0, 1.5)
	await _frames(20)
	var player_model: Node3D = _player.get_node(^"Model")
	var machine_model: Node3D = _machine.get_node(^"Model")
	_check(not player_model.transform.is_equal_approx(_player._model_rest) and not _boss._rig.transform.is_equal_approx(Transform3D.IDENTITY)
		and not _enemies[0]._body.transform.is_equal_approx(_enemies[0]._body_rest), "acceso: i visual si muovono")
	ActorMotion.enabled = false
	_player.on_hit()
	_player.kick()
	_caravan.spend()
	_enemies[0].take_damage(1)
	_boss.take_damage(1)
	var frozen := true
	for i in 30:
		await physics_frame
		frozen = frozen and player_model.transform.is_equal_approx(_player._model_rest) \
			and machine_model.transform.is_equal_approx(_machine._model_rest) \
			and _machine._cargo[0].transform.origin.is_equal_approx(_machine._cargo_rest[0]) \
			and _boss._rig.transform.is_equal_approx(Transform3D.IDENTITY)
		for enemy in _enemies:
			frozen = frozen and enemy._body.transform.is_equal_approx(enemy._body_rest)
	_check(frozen, "spento: tutti i visual a riposo e fermi, anche correndo e sotto i colpi")
	_check(_player.velocity.length() > 3.0 and _enemies[0].velocity.length() > 1.0, "il gioco intanto continua")
	ActorMotion.enabled = true
	await _frames(3)
	_check(not player_model.transform.is_equal_approx(_player._model_rest), "riacceso: il movimento riprende")
	await _free_world()
