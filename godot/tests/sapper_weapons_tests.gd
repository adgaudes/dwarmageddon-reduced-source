extends SceneTree
## Armi del Guastatore (spec D-092, par. 4.2): Lanciarottami, Carica da scavo coi bivi e la
## fusione Mortaio a crateri.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/sapper_weapons_tests.gd

const PlayerScene := preload("res://scenes/player/player.tscn")
## Dove il giocatore aspetta quando un test non lo usa.
const PLAYER_PARK := Vector3(15.0, 0.0, 15.0)

var _failures := 0
var _root: Node3D
var _director: EnemyDirector
var _field: TerrainField
var _queue: TerrainWriteQueue
var _player: PlayerCharacter


func _initialize() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	_director = EnemyDirector.new()
	_director.spawning = false
	_root.add_child(_director)
	_field = TerrainField.new()
	_field.render = false
	_field.size_m = Vector2(40.0, 40.0)
	get_root().add_child(_field)
	_queue = TerrainWriteQueue.new()
	_queue.terrain_field = _field
	get_root().add_child(_queue)
	_player = PlayerScene.instantiate()
	_player.terrain_field = _field
	get_root().add_child(_player)
	_player.set_max_health(1000)
	await process_frame
	_park_player()
	await _test_scrap_base()
	await _test_scrap_over_wall()
	await _test_scrap_cluster()
	await _test_scrap_heavy()
	await _test_scrap_caltrops()
	await _test_scrap_crater()
	await _test_scrap_no_node_per_shot()
	await _test_charge_base()
	await _test_charge_does_not_compound()
	await _test_charge_cluster()
	await _test_charge_pit()
	await _test_charge_double()
	await _test_charge_mine()
	await _test_mortar()
	await _test_boss_heavy()
	await _test_blast_spares_player()
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _enemy_at(p: Vector3, hp := 50) -> Enemy:
	var enemy := _director.spawn_at(p)
	enemy.health = hp
	enemy.max_health = hp
	if _director.terrain_field == null:
		enemy.global_position = p
	return enemy


func _shooter(at: Vector3) -> Node3D:
	var shooter := Node3D.new()
	_root.add_child(shooter)
	shooter.global_position = at
	return shooter


func _seconds(s: float) -> void:
	for i in int(s * Engine.physics_ticks_per_second):
		await physics_frame


func _clear() -> void:
	for enemy in _director.enemies:
		enemy.queue_free()
	_director.enemies.clear()
	for child in _root.get_children():
		if child != _director:
			child.queue_free()
	_director.player = null
	_director.terrain_field = null
	_park_player()
	await process_frame
	await physics_frame


func _reset_field() -> void:
	_queue.clear()
	_field.begin_batch()
	_field.reset_to_base(Vector3.ZERO, Vector2(20.0, 20.0))
	_field.end_batch()


## Il direttore muove i nemici solo col giocatore: lo si mette in [param at] e si accende.
func _use_player(at: Vector3) -> void:
	_player.global_position = Vector3(at.x, _field.height_at(at) + 1.0, at.z)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_director.player = _player
	_director.terrain_field = _field


func _park_player() -> void:
	_player.global_position = Vector3(PLAYER_PARK.x, _field.height_at(PLAYER_PARK) + 1.0, PLAYER_PARK.z)
	_player.velocity = Vector3.ZERO


func _launcher(level := 1, picks: Dictionary = {}, at := Vector3.ZERO) -> ScrapLauncher:
	var weapon := ScrapLauncher.new()
	weapon.weapon_id = &"scrap_launcher"
	weapon.shooter = _shooter(at)
	weapon.director = _director
	weapon.terrain_field = _field
	weapon.write_queue = _queue
	_root.add_child(weapon)
	weapon.set_level(level)
	for pick_at: int in picks:
		weapon.choose_branch(pick_at, picks[pick_at])
	return weapon


func _charge(level := 1, picks: Dictionary = {}, shooter: Node3D = null) -> DigCharge:
	var weapon := DigCharge.new()
	weapon.weapon_id = &"dig_charge"
	weapon.shooter = shooter if shooter != null else _shooter(Vector3.ZERO)
	weapon.director = _director
	weapon.terrain_field = _field
	weapon.write_queue = _queue
	weapon.manual_aim = true
	_root.add_child(weapon)
	weapon.set_level(level)
	for at: int in picks:
		weapon.choose_branch(at, picks[at])
	return weapon


# --- Lanciarottami ------------------------------------------------------------------------

func _test_scrap_base() -> void:
	print("Lanciarottami: base")
	var enemy := _enemy_at(Vector3(0, 0, -8))
	var weapon := _launcher()
	_check(is_equal_approx(weapon.fire_interval, 1.6) and weapon.damage == 2, "valori dal catalogo")
	# Primo lancio dopo 0,3 s, volo di 0,7 s.
	await _seconds(0.8)
	_check(enemy.health == 50 and weapon.scrap_count() == 1, "in volo non fa ancora danno (vita %d)" % enemy.health)
	await _seconds(0.4)
	_check(enemy.health == 48, "all'arrivo 2 danni (vita %d)" % enemy.health)
	await _clear()
	_reset_field()


func _test_scrap_over_wall() -> void:
	print("Lanciarottami: scavalca l'argine")
	for x in range(-4, 5):
		_field.level(Vector3(x, 0.0, -4.0), 0.9, 2.0, 1.0)
	_check(_field.height_at(Vector3(0, 0, -4)) > 1.8, "c'e un argine alto 2 m in mezzo")
	var enemy := _enemy_at(Vector3(0, 0, -8))
	_launcher()
	await _seconds(1.2)
	_check(enemy.health == 48, "il rottame passa sopra e colpisce (vita %d)" % enemy.health)
	await _clear()
	_reset_field()


func _test_scrap_cluster() -> void:
	print("Lanciarottami: Grappolo")
	var point := Vector3(0, 0, -6)
	# Liv. 2 e 3: scoppio di 2,2 m; il nemico sta 1,2 m oltre il bordo.
	var plain := _launcher(2)
	var outside := _enemy_at(point + Vector3.FORWARD * (plain.blast_radius + 1.2))
	await physics_frame
	plain._cooldown = 1000.0
	plain.launch(point)
	await _seconds(1.0)
	_check(outside.health == 50, "senza bivio chi e oltre lo scoppio resta illeso (vita %d)" % outside.health)
	plain.queue_free()
	var weapon := _launcher(3, {3: &"a"})
	await physics_frame
	weapon._cooldown = 1000.0
	weapon.launch(point)
	await _seconds(1.0)
	_check(outside.health == 49, "un frammento lo colpisce, 1 danno (vita %d)" % outside.health)
	await _clear()
	_reset_field()


func _test_scrap_heavy() -> void:
	print("Lanciarottami: Rottame pesante")
	var point := Vector3(0, 0, -6)
	var enemy := _enemy_at(point + Vector3(0.8, 0, 0))
	var weapon := _launcher(3, {3: &"b"})
	await physics_frame
	weapon._cooldown = 1000.0
	weapon.launch(point)
	await _seconds(0.8)
	_check(enemy.health == 46, "4 danni (vita %d)" % enemy.health)
	_check(enemy.velocity.x > 1.0, "e lo spinge via dal punto (%.2f m/s)" % enemy.velocity.x)
	await _clear()
	_reset_field()


## Strada fatta in [param seconds] da un nemico che parte a 9 m dal giocatore e gli va incontro.
func _walk(seconds: float, caltrops: bool) -> Array:
	_use_player(Vector3.ZERO)
	var weapon := _launcher(5, {3: &"b", 5: &"a"})
	var enemy := _enemy_at(Vector3(0, 0, -9))
	await physics_frame
	weapon._cooldown = 1000.0
	if caltrops:
		# Triboli a 1 m dal punto, sulla linea di marcia (a -7 e -5) e di lato.
		weapon._drop_caltrops(Vector3(0, 0, -6), Vector3.BACK)
	var start := enemy.global_position.z
	await _seconds(seconds)
	var out := [enemy.global_position.z - start, enemy.health, weapon.caltrop_count()]
	await _clear()
	return out


func _test_scrap_caltrops() -> void:
	print("Lanciarottami: Bulloni sparsi")
	var free: Array = await _walk(2.5, false)
	var slowed: Array = await _walk(2.5, true)
	_check(slowed[0] < free[0] - 0.4, "chi attraversa i triboli e piu lento (%.2f contro %.2f m)" % [slowed[0], free[0]])
	_check(slowed[1] == 49, "e perde 1 PV, una volta sola (vita %d)" % slowed[1])
	var weapon := _launcher(5, {3: &"b", 5: &"a"})
	await physics_frame
	weapon._cooldown = 1000.0
	weapon._drop_caltrops(Vector3(0, 0, -6), Vector3.BACK)
	_check(weapon.caltrop_count() == 4, "quattro triboli")
	await _seconds(4.2)
	_check(weapon.caltrop_count() == 0, "dopo 4 s spariscono")
	await _clear()
	_reset_field()


func _test_scrap_crater() -> void:
	print("Lanciarottami: Cratere")
	var point := Vector3(0, 0, -6)
	var weapon := _launcher(5, {3: &"b", 5: &"b"})
	await physics_frame
	weapon._cooldown = 1000.0
	weapon.launch(point)
	await _seconds(1.0)
	var h := _field.height_at(point)
	_check(h < -0.3 and h > -0.5, "lo scoppio scava 0,4 m sotto la base (%.2f m)" % h)
	await _clear()
	_reset_field()


func _test_scrap_no_node_per_shot() -> void:
	print("Lanciarottami: niente nodi per colpo")
	_enemy_at(Vector3(0, 0, -8), 500)
	var weapon := _launcher(5, {3: &"a", 5: &"a"})
	await physics_frame
	var children := weapon.get_child_count()
	await _seconds(3.0)
	_check(weapon.shots >= 2, "ha sparato (%d colpi)" % weapon.shots)
	_check(weapon.get_child_count() == children, "i figli dell'arma restano %d" % children)
	await _clear()
	_reset_field()


# --- Carica da scavo ----------------------------------------------------------------------

func _test_charge_base() -> void:
	print("Carica da scavo: base")
	var center := Vector3(0, 0, -6)
	var near := _enemy_at(center + Vector3(2.3, 0, 0))
	var far := _enemy_at(center + Vector3(3.0, 0, 0))
	var weapon := _charge()
	await physics_frame
	_check(weapon.trigger(), "si posa")
	_check(weapon.charge_count() == 1 and weapon.cooldown_left > 7.9, "una carica a terra, ricarica 8 s")
	await _seconds(0.9)
	_check(near.health == 50, "prima della miccia nessun danno (vita %d)" % near.health)
	await _seconds(0.2)
	_check(near.health == 46 and far.health == 50, "dopo 1 s 4 danni entro 2,5 m, niente oltre (%d, %d)" % [near.health, far.health])
	_check(weapon.charge_count() == 0, "la carica non c'e piu")
	await _seconds(0.3)
	var h := _field.height_at(center)
	_check(absf(h + 0.8) <= 0.1, "cratere a -0,8 m nel centro (%.2f m)" % h)
	await _clear()
	_reset_field()


func _test_charge_does_not_compound() -> void:
	print("Carica da scavo: profondita fissa")
	var weapon := _charge()
	await physics_frame
	for i in 3:
		weapon.cooldown_left = 0.0
		weapon.trigger()
		await _seconds(1.4)
	var h := _field.height_at(Vector3(0, 0, -6))
	_check(h > -0.9, "tre cariche nello stesso punto non vanno sotto -0,8 m (%.2f m)" % h)
	await _clear()
	_reset_field()


func _test_charge_cluster() -> void:
	print("Carica da scavo: Grappolo")
	var weapon := _charge(3, {3: &"a"})
	await physics_frame
	weapon.trigger()
	var points := weapon.charge_positions()
	_check(points.size() == 3, "tre cariche")
	var spaced := points.size() == 3 and points[0].distance_to(points[1]) > 1.4 and points[0].distance_to(points[2]) > 1.4
	_check(spaced, "a 1,5 m l'una dall'altra")
	await _seconds(1.5)
	var dug := 0
	for p: Vector3 in points:
		if _field.height_at(p) < -0.3:
			dug += 1
	_check(dug == 3, "tre crateri (%d)" % dug)
	_check(_field.height_at(points[0]) > -0.5 if not points.is_empty() else false, "crateri minori da 0,4 m")
	await _clear()
	_reset_field()


## Un nemico dentro il cratere, col giocatore a 6 m: dopo 5 s e ancora sul fondo?
func _trapped_after(picks: Dictionary) -> float:
	var center := Vector3(0, 0, -6)
	var weapon := _charge(3, picks)
	await physics_frame
	weapon.trigger()
	await _seconds(1.5)
	_use_player(Vector3.ZERO)
	var enemy := _enemy_at(center)
	await _seconds(5.0)
	var depth := _field.delta_at(enemy.global_position)
	await _clear()
	_reset_field()
	return depth


func _test_charge_pit() -> void:
	print("Carica da scavo: Pozzo")
	var center := Vector3(0, 0, -6)
	var weapon := _charge(3, {3: &"b"})
	await physics_frame
	weapon.trigger()
	await _seconds(1.5)
	_check(_field.height_at(center) < -1.5, "pozzo da 1,6 m (%.2f m)" % _field.height_at(center))
	_check(_field.height_at(center + Vector3(1.4, 0, 0)) < -1.0, "con le pareti ripide (%.2f m a 1,4 m)" % _field.height_at(center + Vector3(1.4, 0, 0)))
	await _clear()
	_reset_field()
	# Senza rosicchiare (il tempo prima del morso e lungo): conta solo la pendenza.
	var gnaw_delay := _director.tuning.gnaw_delay_s
	_director.tuning.gnaw_delay_s = 100.0
	var in_pit: float = await _trapped_after({3: &"b"})
	_check(in_pit < -1.0, "chi cade nel pozzo dopo 5 s e ancora dentro (%.2f m)" % in_pit)
	var in_crater: float = await _trapped_after({})
	_check(in_crater > -0.3, "da un cratere normale invece esce (%.2f m)" % in_crater)
	_director.tuning.gnaw_delay_s = gnaw_delay


func _test_charge_double() -> void:
	print("Carica da scavo: Doppia carica")
	var weapon := _charge(5, {3: &"b", 5: &"a"})
	await physics_frame
	_check(weapon.uses_left() == 2, "due usi")
	_check(weapon.trigger(), "il primo parte")
	_check(weapon.cooldown_left == 0.0 and weapon.uses_left() == 1, "senza ricarica, resta un uso")
	_check(weapon.trigger(), "il secondo parte")
	_check(not weapon.trigger(), "il terzo no")
	_check(weapon.cooldown_left > 1.0 and weapon.uses_left() == 2, "ricarica partita, usi di nuovo 2")
	await _clear()
	_reset_field()


func _test_charge_mine() -> void:
	print("Carica da scavo: Mina")
	var weapon := _charge(5, {3: &"b", 5: &"b"})
	await physics_frame
	weapon.trigger()
	await _seconds(3.0)
	_check(weapon.charge_count() == 1, "senza nemici non esplode per 3 s")
	_check(_field.height_at(Vector3(0, 0, -6)) > -0.1, "nessun cratere")
	var enemy := _enemy_at(Vector3(0.5, 0, -6))
	await _seconds(0.2)
	_check(enemy.health < 50 and weapon.charge_count() == 0, "esplode quando un nemico arriva (vita %d)" % enemy.health)
	await _clear()
	_reset_field()
	var mines := _charge(5, {3: &"b", 5: &"b"})
	await physics_frame
	var first := Vector3.ZERO
	for i in 3:
		mines.shooter.rotation.y = i * PI * 0.5
		mines.cooldown_left = 0.0
		mines.trigger()
		if i == 0:
			first = mines.charge_positions()[0]
	var points := mines.charge_positions()
	var has_first := false
	for p in points:
		if p.distance_to(first) < 0.1:
			has_first = true
	_check(mines.mine_count() == 2 and not has_first, "la terza mina toglie la prima (%d mine)" % mines.mine_count())
	await _clear()
	_reset_field()


# --- Mortaio a crateri ----------------------------------------------------------------------

func _test_mortar() -> void:
	print("Mortaio a crateri")
	var weapon := _launcher()
	weapon.fusion_id = &"mortar"
	weapon.set_level(1)
	await physics_frame
	weapon._cooldown = 1000.0
	var points: Array[Vector3] = [Vector3(-8, 0, -6), Vector3(0, 0, -12), Vector3(8, 0, -6)]
	for p in points:
		weapon.launch(p)
		await _seconds(1.0)
	var dug := 0
	for p in points:
		if _field.height_at(p) < -0.3:
			dug += 1
	_check(dug == 3, "ogni rottame abbassa il terreno (%d su 3)" % dug)
	_check(_field.height_at(points[0]) > -0.6, "crateri da 0,5 m (%.2f m)" % _field.height_at(points[0]))
	var target := Vector3(0, 0, -6)
	var enemy := _enemy_at(target + Vector3(2.3, 0, 0))
	weapon.launch(target)
	await _seconds(1.0)
	_check(enemy.health == 46, "il quarto colpo e una carica: 4 danni a 2,3 m (vita %d)" % enemy.health)
	await _seconds(0.3)
	_check(absf(_field.height_at(target) + 0.8) <= 0.1, "e il suo cratere da 0,8 m (%.2f m)" % _field.height_at(target))
	await _clear()
	_reset_field()


# --- Boss e giocatore -------------------------------------------------------------------------

func _test_boss_heavy() -> void:
	print("Rottame pesante su un boss")
	var point := Vector3(0, 0, -6)
	var boss := _enemy_at(point + Vector3(0.8, 0, 0))
	boss.self_driven = true
	var start := boss.global_position
	var weapon := _launcher(3, {3: &"b"})
	await physics_frame
	weapon._cooldown = 1000.0
	weapon.launch(point)
	await _seconds(1.0)
	_check(boss.health == 46, "il boss prende il danno (vita %d)" % boss.health)
	_check(boss.velocity.length() < 0.01 and boss.global_position.distance_to(start) < 0.01, "ma non viene spostato")
	await _clear()
	_reset_field()


## Review Focus 3: le esplosioni non feriscono mai il giocatore.
func _test_blast_spares_player() -> void:
	print("Esplosioni e giocatore")
	_player.global_position = Vector3(0, _field.height_at(Vector3.ZERO) + 1.0, 0)
	await _seconds(0.3)
	var health := _player.health
	var enemy := _enemy_at(Vector3(1.0, 0, 0))
	var weapon := _charge(1, {}, _player)
	await physics_frame
	weapon._fire(Vector3(1.0, 0, 0))
	await _seconds(1.3)
	_check(enemy.health < 50, "la carica a 1 m e esplosa (vita del nemico %d)" % enemy.health)
	_check(_player.health == health, "la vita del giocatore non cambia (%d)" % _player.health)
	DigCharge.explode(_director, _queue, _field, _player.global_position, 4, 2.5, 2.0, 0.8)
	var launcher := _launcher(1, {}, Vector3(0, 0, 4))
	launcher.shooter.queue_free()
	launcher.shooter = _player
	launcher.fusion_id = &"mortar"
	launcher.set_level(1)
	await physics_frame
	launcher._cooldown = 1000.0
	launcher.shots = 3
	launcher.launch(_player.global_position + Vector3(0.5, 0, 0))
	await _seconds(1.0)
	_check(_player.health == health, "nemmeno la carica del Mortaio sotto i piedi (%d)" % _player.health)
	await _clear()
	_reset_field()
