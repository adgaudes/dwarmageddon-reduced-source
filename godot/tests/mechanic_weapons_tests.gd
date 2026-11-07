extends SceneTree
## Armi del Meccanico (spec D-092, par. 4.3): Saldatrice, Calamita da gru, Bobina di Tesla.
## Scena di prova con un giocatore vero (il direttore muove i nemici solo se ce l'ha), lontano
## dalla zona dei test; i nemici "fermi" hanno `speed_scale = 0`: si muovono solo per deriva
## e spinte, cosi si misura l'arma e non l'inseguimento.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/mechanic_weapons_tests.gd

const SmokeTestScene := preload("res://scenes/main/smoke_test.tscn")
const CARAVAN_TUNING := preload("res://resources/tuning/caravan_default.tres")
## Centro della calamita in mira manuale: un tiratore senza `facing_direction` guarda verso -Z.
const MAGNET_CENTER := Vector3(0.0, 0.0, -6.0)

var _failures := 0
var _scene: Node3D
var _player: PlayerCharacter
var _director: EnemyDirector
var _field: TerrainField
var _queue: TerrainWriteQueue
## Contenitore dei nodi di un test (tiratori, armi, carovane, campi): svuotato da _clear.
var _tmp: Node3D


func _initialize() -> void:
	_scene = SmokeTestScene.instantiate()
	root.add_child(_scene)
	_player = _scene.get_node(^"Player")
	_field = _scene.get_node(^"TerrainField")
	_director = EnemyDirector.new()
	_director.spawning = false
	_director.player = _player
	_director.terrain_field = _field
	# I nemici fermi per prova non devono rosicchiare il terreno.
	_director.tuning = RunTuning.new()
	_director.tuning.gnaw_delay_s = 999.0
	_scene.add_child(_director)
	_queue = TerrainWriteQueue.new()
	_queue.terrain_field = _field
	_scene.add_child(_queue)
	_tmp = Node3D.new()
	_scene.add_child(_tmp)
	# La scena entra nell'albero (e il campo si prepara) solo al primo passo.
	await _seconds(0.5)
	await _reset_field()
	await _test_welder_chain()
	await _test_welder_gap_and_ditch()
	await _test_welder_lead()
	await _test_welder_double_arc()
	await _test_welder_fusion_point()
	await _test_welder_static()
	await _test_welder_wire()
	await _test_welder_arcs_no_nodes()
	await _test_magnet_pull_and_boss()
	await _test_magnet_xp()
	await _test_magnet_freed_restores_xp()
	await _test_magnet_crush()
	await _test_magnet_mobile()
	await _test_magnet_repel()
	await _test_magnet_salvage()
	await _test_magnet_no_drift_after()
	await _test_tesla()
	await _seconds(0.1)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _seconds(s: float) -> void:
	for i in int(s * Engine.physics_ticks_per_second):
		await physics_frame


func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _reset_field() -> void:
	_queue.clear()
	_field.begin_batch()
	_field.reset_to_base(Vector3.ZERO, Vector2(24.0, 24.0))
	_field.end_batch()
	_player.global_position = Vector3(0.0, _field.height_at(Vector3(0, 0, 18)) + 1.0, 18.0)
	_player.velocity = Vector3.ZERO
	_player.set_max_health(1000)
	await _seconds(0.2)


func _clear() -> void:
	_director.clear_horde()
	for child in _tmp.get_children():
		child.queue_free()
	await _seconds(0.3)


## Nemico con 50 PV; fermo (`speed_scale = 0`) salvo [param walking].
func _enemy_at(p: Vector3, walking := false) -> Enemy:
	var enemy := _director.spawn_at(p)
	enemy.health = 50
	enemy.max_health = 50
	if not walking:
		enemy.speed_scale = 0.0
	return enemy


func _node_at(p: Vector3) -> Node3D:
	var node := Node3D.new()
	_tmp.add_child(node)
	node.global_position = Vector3(p.x, _field.height_at(p) + 0.9, p.z)
	return node


## Carovana senza giocatore (la macchina sta ferma) col capofila in [param p], a
## [param clearance] dal suolo come i tiratori di prova.
func _caravan_at(p: Vector3, clearance := 0.9) -> Caravan:
	var caravan := Caravan.new()
	caravan.tuning = CARAVAN_TUNING
	caravan.position = Vector3(p.x, _field.height_at(p) + clearance, p.z)
	_tmp.add_child(caravan)
	return caravan


func _welder(level := 1, picks: Dictionary = {}, caravan: Caravan = null, at := Vector3.ZERO) -> Welder:
	var weapon := Welder.new()
	weapon.weapon_id = &"welder"
	weapon.shooter = _node_at(at)
	weapon.director = _director
	weapon.terrain_field = _field
	_tmp.add_child(weapon)
	weapon.caravan = caravan
	weapon.set_level(level)
	for at_level: int in picks:
		weapon.choose_branch(at_level, picks[at_level])
	return weapon


func _magnet(level := 1, picks: Dictionary = {}, caravan: Caravan = null) -> CraneMagnet:
	var magnet := CraneMagnet.new()
	magnet.weapon_id = &"crane_magnet"
	magnet.shooter = _node_at(Vector3.ZERO)
	magnet.director = _director
	magnet.terrain_field = _field
	magnet.write_queue = _queue
	magnet.manual_aim = true
	_tmp.add_child(magnet)
	magnet.caravan = caravan
	magnet.set_level(level)
	for at_level: int in picks:
		magnet.choose_branch(at_level, picks[at_level])
	return magnet


func _hit_count(enemies: Array[Enemy]) -> int:
	var n := 0
	for enemy in enemies:
		if enemy.health < 50:
			n += 1
	return n


## Aspetta che l'attrazione finisca (al massimo [param limit] secondi).
func _until_released(magnet: CraneMagnet, limit := 6.0) -> void:
	var steps := 0
	while magnet.pulling() and steps < int(limit * Engine.physics_ticks_per_second):
		await physics_frame
		steps += 1


func _attractor_radius(xp: XpField, node: Node3D) -> float:
	for entry in xp.attractors:
		if entry.node == node:
			return entry.radius
	return -1.0


# --- Saldatrice -----------------------------------------------------------------------------

func _test_welder_chain() -> void:
	print("Saldatrice: catena")
	var line: Array[Enemy] = [_enemy_at(Vector3(0, 0, -3)), _enemy_at(Vector3(0, 0, -4.5)), _enemy_at(Vector3(0, 0, -6))]
	var fourth := _enemy_at(Vector3(0, 0, -7.5))
	var weapon := _welder()
	_check(is_equal_approx(weapon.fire_interval, 1.2) and weapon.jumps == 3, "valori dal catalogo")
	await _seconds(0.6)
	_check(_hit_count(line) == 3, "tre nemici a 1,5 m l'uno dall'altro: tre colpiti (%d)" % _hit_count(line))
	_check(line[0].health == 49 and line[2].health == 49, "1 danno ciascuno")
	_check(fourth.health == 50, "il quarto no: tre bersagli in tutto")
	await _clear()


func _test_welder_gap_and_ditch() -> void:
	print("Saldatrice: salto lungo nei fossati")
	var line: Array[Enemy] = [_enemy_at(Vector3(0, 0, -3)), _enemy_at(Vector3(0, 0, -4.5)), _enemy_at(Vector3(0, 0, -8))]
	_welder()
	await _seconds(0.6)
	_check(_hit_count(line) == 2 and line[2].health == 50, "terzo a 3,5 m: due colpiti (%d)" % _hit_count(line))
	await _clear()
	_field.dig_to_base_offset(Vector3(0, 0, -4.5), 1.2, 0.8)
	line = [_enemy_at(Vector3(0, 0, -3)), _enemy_at(Vector3(0, 0, -4.5)), _enemy_at(Vector3(0, 0, -8))]
	_check(_field.delta_at(line[1].global_position) < -0.5, "il secondo sta nel fossato (%.2f)" % _field.delta_at(line[1].global_position))
	_welder()
	await _seconds(0.6)
	_check(_hit_count(line) == 3, "dal fossato il salto arriva a 4 m: tre colpiti (%d)" % _hit_count(line))
	await _clear()
	await _reset_field()


func _test_welder_lead() -> void:
	print("Saldatrice: arco dal capofila della carovana")
	var a := _enemy_at(Vector3(0, 0, -3))
	var b := _enemy_at(Vector3(5, 0, -3))
	_welder(1, {}, _caravan_at(Vector3(5, 0, 0)))
	await _seconds(0.6)
	_check(a.health == 49 and b.health == 49, "capofila a 5 m: due catene (%d, %d)" % [a.health, b.health])
	await _clear()
	a = _enemy_at(Vector3(0, 0, -3))
	b = _enemy_at(Vector3(12, 0, -3))
	_welder(1, {}, _caravan_at(Vector3(12, 0, 0)))
	await _seconds(0.6)
	_check(a.health == 49 and b.health == 50, "capofila a 12 m: una sola (%d, %d)" % [a.health, b.health])
	await _clear()


func _test_welder_double_arc() -> void:
	print("Saldatrice: Arco doppio")
	var group: Array[Enemy] = [_enemy_at(Vector3(0, 0, -3)), _enemy_at(Vector3(0, 0, 3))]
	_welder()
	await _seconds(0.6)
	var single := _hit_count(group)
	await _clear()
	group = [_enemy_at(Vector3(0, 0, -3)), _enemy_at(Vector3(0, 0, 3))]
	_welder(3, {3: &"a"})
	await _seconds(0.6)
	_check(_hit_count(group) > single, "due archi colpiscono piu nemici dello stesso schieramento (%d contro %d)" % [_hit_count(group), single])
	await _clear()


func _test_welder_fusion_point() -> void:
	print("Saldatrice: Punto di fusione")
	var line: Array[Enemy] = [_enemy_at(Vector3(0, 0, -3)), _enemy_at(Vector3(0, 0, -4.5)), _enemy_at(Vector3(0, 0, -6))]
	_welder(3, {3: &"b"})
	await _seconds(0.6)
	_check(line[0].health == 47 and line[1].health == 50 and line[2].health == 50,
		"3 danni al primo, gli altri illesi (%d, %d, %d)" % [line[0].health, line[1].health, line[2].health])
	await _clear()


func _test_welder_static() -> void:
	print("Saldatrice: Carica statica")
	# Punto di fusione: l'arco colpisce solo il primo, il vicino lo ferisce solo la carica.
	var target := _enemy_at(Vector3(0, 0, -3))
	var neighbor := _enemy_at(Vector3(0, 0, -3.6))
	_welder(5, {3: &"b", 5: &"a"})
	await _seconds(0.45)
	_check(target.health == 47 and neighbor.health == 50, "colpito solo il primo (%d, %d)" % [target.health, neighbor.health])
	await _seconds(0.6)
	_check(neighbor.health < 50, "il vicino a 0,6 m dal colpito perde PV entro 1 s (%d)" % neighbor.health)
	_check(target.health == 47, "il colpito non ferisce se stesso (%d)" % target.health)
	await _clear()


func _test_welder_wire() -> void:
	print("Saldatrice: Filo teso")
	var plain := _enemy_at(Vector3(2.5, 0, 0))
	_welder(5, {3: &"a", 5: &"a"}, _caravan_at(Vector3(5, 0, 0)))
	await _seconds(1.4)
	var without := plain.health
	await _clear()
	var wired := _enemy_at(Vector3(2.5, 0, 0))
	_welder(5, {3: &"a", 5: &"b"}, _caravan_at(Vector3(5, 0, 0)))
	await _seconds(1.4)
	_check(wired.health < without, "chi sta sul filo fra giocatore e capofila perde piu PV (%d contro %d)" % [wired.health, without])
	await _clear()
	var lone := _enemy_at(Vector3(0, 0, -3))
	var weapon := _welder(5, {3: &"a", 5: &"b"})
	await _seconds(0.6)
	_check(lone.health < 50 and weapon.caravan == null, "senza carovana spara lo stesso, filo spento (%d)" % lone.health)
	await _clear()


func _test_welder_arcs_no_nodes() -> void:
	print("Saldatrice: archi senza nodi per colpo")
	for i in 6:
		_enemy_at(Vector3(-2.0 + i * 0.8, 0, -3.0 - (i % 2)))
	var weapon := _welder(5, {3: &"a", 5: &"a"}, _caravan_at(Vector3(3, 0, 0)))
	await physics_frame
	var children := weapon.get_child_count()
	await _seconds(0.36)
	_check(weapon.drawn_segments() > 0, "gli archi sono segmenti di una MultiMesh (%d)" % weapon.drawn_segments())
	await _seconds(1.64)
	_check(weapon.get_child_count() == children, "sparando i figli dell'arma restano %d" % children)
	await _clear()


# --- Calamita da gru ------------------------------------------------------------------------

func _test_magnet_pull_and_boss() -> void:
	print("Calamita: attrazione, boss fermo")
	var enemy := _enemy_at(MAGNET_CENTER + Vector3(5, 0, 0))
	var boss := Enemy.new()
	boss.self_driven = true
	_director.add_enemy(boss, MAGNET_CENTER + Vector3(-3, Enemy.spawn_height(), 0))
	await _seconds(0.1)
	var boss_start := boss.global_position
	var magnet := _magnet()
	await physics_frame
	_check(magnet.trigger(), "si attiva")
	_check(magnet.pulling() and _planar(magnet.pull_center(), MAGNET_CENTER) < 0.1, "centro nel punto di mira")
	await _seconds(3.1)
	_check(_planar(enemy.global_position, MAGNET_CENTER) < 2.0, "un nemico a 5 m dal centro finisce entro 2 m in 3 s (%.2f)" % _planar(enemy.global_position, MAGNET_CENTER))
	_check(_planar(boss.global_position, boss_start) < 0.2, "il boss nel raggio non si sposta (%.2f)" % _planar(boss.global_position, boss_start))
	_check(not magnet.pulling(), "dopo 3 s smette")
	await _clear()


func _test_magnet_xp() -> void:
	print("Calamita: esperienza")
	var magnet := _magnet()
	var xp := XpField.new()
	xp.player = magnet.shooter
	xp.player_radius = 2.5
	_tmp.add_child(xp)
	magnet.xp_field = xp
	var got: Array[int] = [0]
	xp.collected.connect(func(amount: int) -> void: got[0] += amount)
	xp.spawn(magnet.shooter.global_position + Vector3(9, 0, 0), 3)
	await _seconds(0.5)
	_check(xp.count() == 1, "senza calamita un frammento a 9 m resta a terra")
	magnet.trigger()
	await _seconds(0.1)
	_check(is_equal_approx(_attractor_radius(xp, magnet.shooter), 10.0), "durante l'attrazione il raggio e 10 m")
	await _seconds(2.0)
	_check(xp.count() == 0 and got[0] == 3, "il frammento a 9 m viene raccolto (%d)" % got[0])
	await _until_released(magnet)
	await physics_frame
	_check(_attractor_radius(xp, magnet.shooter) < 0.0, "dopo la fine l'attrattore aggiunto sparisce")
	# Con un attrattore gia presente (altro potenziamento) torna al suo raggio.
	xp.set_attractor(magnet.shooter, 4.0)
	magnet.cooldown_left = 0.0
	magnet.trigger()
	await _seconds(0.1)
	_check(is_equal_approx(_attractor_radius(xp, magnet.shooter), 10.0), "il raggio sale a 10 m")
	await _until_released(magnet)
	await physics_frame
	_check(is_equal_approx(_attractor_radius(xp, magnet.shooter), 4.0), "poi torna quello di prima (%.1f)" % _attractor_radius(xp, magnet.shooter))
	await _clear()


func _test_magnet_freed_restores_xp() -> void:
	print("Calamita: tolta a meta (fusione)")
	var magnet := _magnet()
	var xp := XpField.new()
	_tmp.add_child(xp)
	magnet.xp_field = xp
	var shooter := magnet.shooter
	magnet.trigger()
	await _seconds(0.5)
	magnet.queue_free()
	await _seconds(0.1)
	_check(_attractor_radius(xp, shooter) < 0.0, "l'attrattore non resta acceso")
	await _clear()


func _test_magnet_crush() -> void:
	print("Calamita: Schiacciasassi")
	var enemy := _enemy_at(MAGNET_CENTER + Vector3(3, 0, 0))
	var outside := _enemy_at(MAGNET_CENTER + Vector3(0, 0, 9))
	var magnet := _magnet(3, {3: &"a"})
	await physics_frame
	magnet.trigger()
	await _until_released(magnet)
	await _seconds(0.1)
	_check(enemy.health == 47, "alla fine 3 danni a chi e stato tirato al centro (%d)" % enemy.health)
	_check(outside.health == 50, "chi e fuori no")
	await _clear()


func _test_magnet_mobile() -> void:
	print("Calamita: Gru mobile")
	var caravan := _caravan_at(MAGNET_CENTER + Vector3(0, 0, 2))
	var lead := caravan.lead()
	var magnet := _magnet(3, {3: &"b"}, caravan)
	var enemy := _enemy_at(Vector3(6, 0, -2))
	await physics_frame
	magnet.trigger()
	await _seconds(0.1)
	_check(_planar(magnet.pull_center(), lead.global_position) < 0.1, "il centro e sul capofila")
	lead.global_position += Vector3(4, 0, 0)
	await _seconds(2.0)
	_check(_planar(magnet.pull_center(), lead.global_position) < 0.1, "il centro si sposta col capofila")
	_check(_planar(enemy.global_position, lead.global_position) < 2.0, "e tira verso dove sta ora (%.2f)" % _planar(enemy.global_position, lead.global_position))
	await _clear()
	magnet = _magnet(3, {3: &"b"})
	await physics_frame
	magnet.trigger()
	await _seconds(0.2)
	_check(_planar(magnet.pull_center(), MAGNET_CENTER) < 0.1, "senza carovana resta nel punto di mira")
	await _clear()


func _test_magnet_repel() -> void:
	print("Calamita: Polarita inversa")
	# Argine alto 1,5 m a est del centro; il nemico davanti e stordito: la calamita non lo
	# tira, la spinta finale lo manda contro l'argine.
	for z in range(-9, -2):
		_field.level(MAGNET_CENTER + Vector3(4.8, 0, z + 6), 0.9, 1.5, 1.0)
	var pinned := _enemy_at(MAGNET_CENTER + Vector3(3.4, 0, 0))
	var free := _enemy_at(MAGNET_CENTER + Vector3(-3, 0, 0))
	pinned.stun(20.0)
	var magnet := _magnet(5, {3: &"b", 5: &"a"})
	await physics_frame
	magnet.trigger()
	await _until_released(magnet)
	var free_end := _planar(free.global_position, MAGNET_CENTER)
	await _seconds(0.6)
	var free_after := _planar(free.global_position, MAGNET_CENTER)
	_check(free_after > free_end + 1.0 and free_after > 1.5, "alla fine respinge: da %.2f a %.2f m dal centro" % [free_end, free_after])
	_check(pinned.health == 48, "chi finisce contro l'argine prende 2 danni (%d)" % pinned.health)
	_check(free.health == 50, "chi non trova argini no (%d)" % free.health)
	await _clear()
	await _reset_field()


func _test_magnet_salvage() -> void:
	print("Calamita: Raccolta")
	var caravan := _caravan_at(Vector3(2, 0, 0), Caravan.GROUND_CLEARANCE)
	caravan.lead().set_physics_process(false)
	caravan.carried = 0
	var scraps := ScrapField.new()
	scraps.terrain_field = _field
	_tmp.add_child(scraps)
	scraps.spawn_on_ground(MAGNET_CENTER + Vector3(1, 0, 0))
	scraps.spawn_on_ground(MAGNET_CENTER + Vector3(-2, 0, 1))
	scraps.spawn_on_ground(MAGNET_CENTER + Vector3(10, 0, 0))
	var magnet := _magnet(5, {3: &"a", 5: &"b"}, caravan)
	magnet.scrap_field = scraps
	await physics_frame
	magnet.trigger()
	await _until_released(magnet)
	await _seconds(0.1)
	_check(caravan.carried == 2 and scraps.count() == 1, "due rottami nel raggio passano ai Cassoni (%d a bordo, %d a terra)" % [caravan.carried, scraps.count()])
	await _clear()
	# Senza carovana: nessun errore, i rottami restano dove sono.
	scraps = ScrapField.new()
	scraps.terrain_field = _field
	_tmp.add_child(scraps)
	scraps.spawn_on_ground(MAGNET_CENTER + Vector3(1, 0, 0))
	magnet = _magnet(5, {3: &"a", 5: &"b"})
	magnet.scrap_field = scraps
	await physics_frame
	magnet.trigger()
	await _until_released(magnet)
	await _seconds(0.1)
	_check(scraps.count() == 1, "senza carovana il rottame resta a terra")
	await _clear()


func _test_magnet_no_drift_after() -> void:
	print("Calamita: niente deriva dopo la fine (70 nemici e un boss)")
	var crowd: Array[Enemy] = []
	for i in 70:
		var angle := TAU * i / 70.0
		var r := 1.5 + (i % 5) * 0.9
		crowd.append(_enemy_at(MAGNET_CENTER + Vector3(cos(angle) * r, 0, sin(angle) * r)))
	var boss := Enemy.new()
	boss.self_driven = true
	_director.add_enemy(boss, MAGNET_CENTER + Vector3(2, Enemy.spawn_height(), 2))
	await _seconds(0.1)
	var boss_start := boss.global_position
	var magnet := _magnet()
	await physics_frame
	magnet.trigger()
	await _until_released(magnet)
	await physics_frame
	await physics_frame
	var start: Array[Vector3] = []
	for enemy in crowd:
		start.append(enemy.global_position)
	await _seconds(0.5)
	var worst := 0.0
	var drifting := 0
	for i in crowd.size():
		worst = maxf(worst, _planar(crowd[i].global_position, start[i]))
		if crowd[i].drift != Vector3.ZERO:
			drifting += 1
	_check(worst < 0.5, "nessun nemico si muove piu di 0,5 m in 0,5 s dopo la fine (%.2f)" % worst)
	_check(drifting == 0, "nessuna deriva rimasta")
	_check(_planar(boss.global_position, boss_start) < 0.2, "il boss non si e spostato (%.2f)" % _planar(boss.global_position, boss_start))
	await _clear()


# --- Bobina di Tesla ------------------------------------------------------------------------

func _test_tesla() -> void:
	print("Bobina di Tesla")
	var near := _enemy_at(Vector3(4, 0, 0))
	var far := _enemy_at(Vector3(-7, 0, 0))
	var weapon := _welder(5, {3: &"a", 5: &"a"})
	weapon.fusion_id = &"tesla_coil"
	weapon.set_level(5)
	await physics_frame
	var near_start := _planar(near.global_position, weapon.shooter.global_position)
	var far_start := far.global_position
	await _seconds(1.5)
	var near_now := _planar(near.global_position, weapon.shooter.global_position)
	_check(near_now < near_start - 0.5 and near.health < 50, "un nemico a 4 m si avvicina e prende danno (%.2f m, %d PV)" % [near_now, near.health])
	_check(_planar(far.global_position, far_start) < 0.1 and far.health == 50, "uno a 7 m no")
	await _clear()
	# Campo del capofila, lontano dal giocatore (niente catene della Saldatrice): solo la Bobina.
	var caravan := _caravan_at(Vector3(15, 0, 0))
	var lead := caravan.lead()
	var by_lead := _enemy_at(Vector3(15, 0, -4))
	weapon = _welder(5, {3: &"a", 5: &"a"}, caravan)
	weapon.fusion_id = &"tesla_coil"
	weapon.set_level(5)
	await _seconds(1.5)
	_check(_planar(by_lead.global_position, lead.global_position) < 3.5 and by_lead.health < 50,
		"il campo del capofila attira e scarica (%.2f m, %d PV)" % [_planar(by_lead.global_position, lead.global_position), by_lead.health])
	await _clear()
