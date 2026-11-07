extends SceneTree
## Test del primo boss, il Demolitore (D-043), sul rilievo continuo (D-085): cerca la
## cima piu alta, la spiana conservando la terra, rottami solo dalle vene, cantiere piano
## e barricate a cumulo. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/boss_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")
## Frame entro cui il boss ricontrolla bersagli e rottamatori (Demolisher.RETARGET_SECONDS).
const RETARGET_FRAMES := 30

var _failures := 0
var _scene: Node3D
var _run: ArenaRun
var _field: TerrainField
var _district: RuinsDistrict
var _player: PlayerCharacter
var _director: EnemyDirector
var _weapon: AutoWeapon
var _path: PathField
var _hud: RunHud
var _scrap: ScrapField
var _boss: Demolisher


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_field = _scene.get_node(^"TerrainField")
	_district = _scene.get_node(^"District")
	_player = _scene.get_node(^"Player")
	_director = _scene.get_node(^"EnemyDirector")
	_weapon = _scene.get_node(^"PlayerWeapon")
	_path = _scene.get_node(^"PathField")
	_hud = _scene.get_node(^"RunHud")
	_scrap = _scene.get_node(^"ScrapField")
	_director.spawning = false
	await _frames(5)
	_weapon.set_physics_process(false)
	await _test_call_and_arrival()
	await _test_walls_attract_and_feed_barricades()
	await _test_digging_a_barricade()
	await _test_boss_levels_player_mound()
	await _test_boss_levels_player_mound_without_scrap()
	await _test_boss_demolishes_deposit_and_scrap_comes_out()
	await _test_barricade_is_mound()
	await _test_scrap_is_not_buried()
	await _test_own_barricade_in_the_way()
	await _test_abandons_unreachable_wall()
	await _test_no_carrier_without_route()
	await _test_spawn_point_is_walkable()
	await _test_caravan_ignores_sealed_scrap()
	await _test_site_moves_when_occupied()
	await _test_carrier_waits_without_site()
	await _test_uphill_slows()
	await _test_contact_damage()
	await _test_weapon_hits_boss()
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


func _place_boss(at: Vector3) -> void:
	_boss.global_position = Vector3(at.x, _field.height_at(at) + Demolisher.boss_spawn_height(), at.z)
	_boss.velocity = Vector3.ZERO
	_boss.demolish_point = Vector3.INF
	_boss.wall_point = Vector3.INF
	_boss._retarget_left = 0.0


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _first_stroke(kind: StringName) -> Dictionary:
	for stroke: Dictionary in _district.terrain_strokes:
		if stroke.kind == kind:
			return stroke
	return {}


## Anello di argini (come quelli del quartiere) attorno a [param center]: chi sta dentro
## non ha strada verso fuori.
func _seal_ring(center: Vector3, radius := 3.0) -> void:
	var count := 16
	var amount := 1.4 / RuinsDistrict.line_overlap(TAU * radius / count, 2.0)
	for k in count:
		var angle := TAU * k / count
		_field.sculpt(center + Vector3(cos(angle), 0.0, sin(angle)) * radius, 2.0, amount)


func _open_ring(center: Vector3, radius := 3.0) -> void:
	_flatten(center, radius + 3.0)


## Riporta il disco alla quota di base (due passate: la seconda spiana i bordi).
func _flatten(at: Vector3, radius: float) -> void:
	_field.level(at, radius, _field.base_height_at(at), 1.0)
	_field.level(at, radius, _field.base_height_at(at), 1.0)


func _test_call_and_arrival() -> void:
	print("call and arrival")
	_check(is_equal_approx(_run.boss_call_at, _run.tuning.boss_call_seconds), "chiamata a %.0f s dal tuning" % _run.boss_call_at)
	_check(_run.boss_phase == ArenaRun.BossPhase.WAITING and not _hud.is_boss_warning_visible(), "prima della chiamata nessun annuncio")
	_place_player(Vector3.ZERO)
	_run.boss_call_at = _run.elapsed + 0.05
	await _frames(6)
	_check(_run.boss_phase == ArenaRun.BossPhase.WARNING, "a tempo scaduto il boss e annunciato")
	_check(_hud.is_boss_warning_visible() and not _hud.is_boss_bar_visible(), "annuncio visibile, barra vita non ancora")
	var names := ["NORD", "EST", "SUD", "OVEST"]
	_check(names.has(_run.boss_direction_name) and is_equal_approx(_run.boss_direction.length(), 1.0),
		"direzione annunciata: %s" % _run.boss_direction_name)
	_check(_run.boss == null and _run._boss_warning_left > _run.tuning.boss_warning_seconds - 1.0,
		"preavviso di %.0f s prima dell'arrivo" % _run.tuning.boss_warning_seconds)
	_run._boss_warning_left = 0.05
	await _frames(6)
	_boss = _run.boss as Demolisher
	_check(_run.boss_phase == ArenaRun.BossPhase.ACTIVE and _boss != null, "finito il preavviso il Demolitore entra in campo")
	if _boss == null:
		return
	_check(_boss.terrain_field == _field, "il boss conosce il rilievo")
	_check(_boss.global_position.y >= _field.height_at(_boss.global_position) + Demolisher.boss_spawn_height() - 0.3,
		"nasce sopra il rilievo (y %.2f, suolo %.2f)" % [_boss.global_position.y, _field.height_at(_boss.global_position)])
	_check(_director.enemies.has(_boss), "registrato fra i nemici: armi e scavo esplosivo lo vedono")
	var offset := _boss.global_position - _player.global_position
	offset.y = 0.0
	_check(offset.normalized().dot(_run.boss_direction) > 0.9, "arriva dalla direzione annunciata")
	_check(absf(offset.length() - _run.tuning.boss_spawn_distance) < 12.0, "a circa %.0f m (%.1f)" % [_run.tuning.boss_spawn_distance, offset.length()])
	_check(_hud.is_boss_bar_visible() and not _hud.is_boss_warning_visible(), "barra vita visibile, annuncio sparito")
	_check(_boss.health == _run.tuning.boss_health, "vita %d" % _boss.health)


## Un argine entro il raggio lo attira piu del giocatore e lo spiana; gli argini non
## hanno vene, i rottami a terra li portano i rottamatori al cantiere: ogni due nasce
## una barricata a cumulo fra lui e il giocatore (D-045).
func _test_walls_attract_and_feed_barricades() -> void:
	print("walls and barricades")
	var lead := (_scene.get_node(^"Caravan") as Caravan).lead()
	lead.set_physics_process(false)
	_place_player(Vector3.ZERO)
	_place_boss(Vector3(4.8, 0.0, -17.0))
	var first_frame := -1
	var first_point := Vector3.INF
	for i in 900:
		await physics_frame
		if _boss.is_demolishing() and first_point == Vector3.INF:
			first_point = _boss.demolish_point
		if _boss.walls_demolished >= 1:
			first_frame = i
			break
	_check(first_frame >= 0, "raggiunge un argine del cortile e lo spiana (frame %d)" % first_frame)
	_check(first_point != Vector3.INF and _field.delta_at(first_point) < 0.3, "l'argine spianato non sporge piu dalla base (%.2f)" % _field.delta_at(first_point))
	_check(_boss.barricade_points.is_empty(), "un argine spianato non basta per una barricata")
	_check(_scrap.count() == 0, "un argine senza vena non lascia rottami")
	# Fermo dov'e: i controlli che seguono riguardano solo i rottamatori.
	_boss.speed = 0.0
	_boss.velocity = Vector3.ZERO
	_boss.wall_attraction_radius = 0.0
	_boss.demolish_point = Vector3.INF
	_boss.wall_point = Vector3.INF
	for k in 2:
		_scrap.spawn_on_ground(_boss.global_position + Vector3(2.5 + k, 0.0, 2.0))
	var scraps := _scrap.positions_near(_boss.global_position, _boss.carrier_scrap_radius)
	_check(scraps.size() == 2, "due rottami a terra alla portata dei suoi rottamatori")
	if scraps.size() < 2:
		return
	# I rottamatori consegnano e poi tornano dal giocatore: qui non deve morire.
	_player._invulnerable_left = 600.0
	var first := _director.spawn_at(scraps[0] + Vector3(0.7, 0.0, 0.7))
	await _frames(RETARGET_FRAMES)
	_check(first.has_errand and _boss.crew_size() == 1, "un rottamatore vicino lascia il giocatore e va al rottame")
	for i in 600:
		await physics_frame
		if first.carrying_scrap:
			break
	_check(first.carrying_scrap and _scrap.count() == 1, "lo raccoglie e lo porta addosso")
	var site := _boss.site_point()
	_check(site != Vector3.INF and _field.is_flat(site, 2.4, 0.35), "il boss sceglie un cantiere piano")
	first.take_damage(first.health)
	await _frames(2)
	_check(_scrap.count() == 2 and _boss.crew_size() == 0, "abbattuto mentre e carico, lascia cadere il rottame")

	var haulers: Array[Enemy] = []
	for position in _scrap.positions_near(_boss.global_position, _boss.carrier_scrap_radius):
		haulers.append(_director.spawn_at(position + Vector3(0.7, 0.0, 0.7)))
	for i in 1500:
		await physics_frame
		if _boss.barricade_points.size() >= 1:
			break
	_check(_boss.barricade_points.size() == 1, "due rottami consegnati al cantiere: una barricata (%d)" % _boss.barricade_points.size())
	_check(_scrap.count() == 0 and _boss.site_scrap() == 0, "i rottami sono finiti nella barricata")
	var audio: RunAudio = _scene.get_node(^"RunAudio")
	_check(audio.play_count(&"boss_spawn") == 1 and audio.play_count(&"boss_demolish") >= 1
		and audio.play_count(&"carrier_pickup") >= 2 and audio.play_count(&"boss_barricade") == 1,
		"si sentono arrivo, argine spianato, rottami raccolti e barricata")
	_check(haulers.all(func(e: Enemy) -> bool: return not e.has_errand and not e.carrying_scrap),
		"consegnato il rottame, tornano a inseguire il giocatore")
	for hauler in haulers:
		_director.enemies.erase(hauler)
		hauler.queue_free()
	_boss.speed = _run.tuning.boss_speed
	_boss.wall_attraction_radius = _run.tuning.boss_wall_attraction_radius
	lead.set_physics_process(true)
	_player._invulnerable_left = 0.0
	if _boss.barricade_points.size() == 1:
		var p: Vector3 = _boss.barricade_points[0]
		_check(_field.delta_at(p) > 1.0, "la barricata e un cumulo di oltre 1 m (%.2f)" % _field.delta_at(p))
		_check(_planar_distance(p, _player.global_position) < _planar_distance(_boss.global_position, _player.global_position),
			"sta fra il boss e il giocatore")
		_check(_planar_distance(p, _player.global_position) > 2.0, "non nasce addosso al giocatore")
		# Il boss non considera le proprie barricate come bersaglio.
		_boss._retarget_left = 0.0
		await _frames(2)
		_check(_boss.wall_point == Vector3.INF or _planar_distance(_boss.wall_point, p) > 1.5, "le proprie barricate non lo attirano")


func _test_digging_a_barricade() -> void:
	print("dig barricade")
	if _boss.barricade_points.is_empty():
		_check(false, "nessuna barricata da scavare")
		return
	var p: Vector3 = _boss.barricade_points[0]
	_director.set_physics_process(false)
	_flatten(p, 3.0)
	await _frames(2)
	_check(_boss.barricade_points.is_empty() and _field.delta_at(p) < 0.5, "spianata la barricata, il boss la dimentica")
	_director.set_physics_process(true)


func _test_boss_levels_player_mound() -> void:
	print("boss levels mound")
	_place_player(Vector3.ZERO)
	var at := Vector3(6.0, 0.0, 0.0)
	_field.sculpt(at, 2.4, 1.6)
	_place_boss(at + Vector3(-5.0, 0.0, 0.0))
	_player._invulnerable_left = 600.0
	var demolished := _boss.walls_demolished
	# Audit E-12: il martello batteva a ogni passo con 9 pennellate (9 aggiornamenti del
	# terreno per passo); ora a 10 Hz con la terra smossa in un solo aggiornamento.
	var updates := [0, 0]
	var counter := func(_aabb: AABB) -> void:
		if _boss.is_demolishing() and _boss._demolish_left <= 0.0:
			updates[0] += 1
	_field.region_changed.connect(counter)
	for i in 60 * 6:
		await physics_frame
		if _boss.is_demolishing() and _boss._demolish_left <= 0.0:
			updates[1] += 1
	_field.region_changed.disconnect(counter)
	var per_second: float = updates[0] * 60.0 / maxf(updates[1], 1.0)
	_check(updates[1] > 10 and per_second <= 30.0, "martello: %.0f aggiornamenti del terreno al secondo (%d passi di martello)" % [per_second, updates[1]])
	_check(_field.delta_at(at) < 0.6, "il Demolitore spiana il cumulo del giocatore (delta %.2f)" % _field.delta_at(at))
	_check(_boss.walls_demolished == demolished + 1, "contato come un solo muro demolito (%d)" % (_boss.walls_demolished - demolished))
	_check(not _boss.is_demolishing() or _planar_distance(_boss.demolish_point, at) > 3.0, "spianato, non rimartella lo stesso punto")
	_player._invulnerable_left = 0.0


func _test_boss_levels_player_mound_without_scrap() -> void:
	print("no scrap from plain mound")
	var before := _scrap.count()
	var at := Vector3(-6.0, 0.0, 0.0)
	_field.sculpt(at, 2.4, 1.6)
	_place_boss(at + Vector3(5.0, 0.0, 0.0))
	_player._invulnerable_left = 600.0
	await _frames(60 * 6)
	_check(_field.delta_at(at) < 0.6, "anche questo cumulo viene spianato (delta %.2f)" % _field.delta_at(at))
	_check(_scrap.count() == before, "un argine senza vena non da rottami al boss")
	_player._invulnerable_left = 0.0


func _test_boss_demolishes_deposit_and_scrap_comes_out() -> void:
	print("deposit")
	var deposit: Dictionary = _first_stroke(&"deposit")
	var at := Vector3(deposit.center.x, 0.0, deposit.center.y)
	var before := _scrap.count()
	_check(_scrap.vein_scrap_left(at) >= 6, "il deposito ha una vena (%d)" % _scrap.vein_scrap_left(at))
	_place_player(at + Vector3(0.0, 0.0, 14.0))
	_player._invulnerable_left = 600.0
	_place_boss(at + Vector3(5.0, 0.0, 0.0))
	await _frames(60 * 10)
	_check(_scrap.count() > before, "spianando un cumulo con vena escono rottami (%d)" % (_scrap.count() - before))
	_check(_scrap.vein_scrap_left(at) < 6, "la vena si consuma (%d)" % _scrap.vein_scrap_left(at))
	_scrap.take_near(at, 12.0, 20)
	_player._invulnerable_left = 0.0


func _test_barricade_is_mound() -> void:
	print("barricade")
	_place_player(Vector3.ZERO)
	_place_boss(Vector3(0.0, 0.0, -5.0))
	_boss.speed = 0.0
	_boss._site_scrap = _boss.walls_per_barricade
	_boss._try_build_at_site()
	_check(_boss.barricade_points.size() == 1, "una barricata costruita (%d)" % _boss.barricade_points.size())
	if _boss.barricade_points.is_empty():
		_boss.speed = _run.tuning.boss_speed
		return
	var p: Vector3 = _boss.barricade_points[0]
	_check(_field.delta_at(p) > 1.0, "la barricata e un cumulo di oltre 1 m (%.2f)" % _field.delta_at(p))
	_check(not _field.is_flat(p, 2.4, 0.35), "il cantiere non e piu piano")
	_flatten(p, 3.0)
	await _frames(2)
	_check(_boss.barricade_points.is_empty(), "scavata la barricata, il boss la dimentica")
	_boss.speed = _run.tuning.boss_speed


## Il boss non costruisce sopra un rottame; e alzare il suolo sotto un rottame lo fa
## rotolare piu in basso (Task 9), non lo seppellisce.
func _test_scrap_is_not_buried() -> void:
	print("scrap under a mound")
	_place_player(Vector3.ZERO)
	var at := Vector3(0.0, 0.0, 6.0)
	var before := _scrap.count()
	_scrap.spawn_on_ground(at)
	_check(_scrap.nearest(at, 0.5) != null, "rottame posato a terra")
	_check(not _boss._point_is_free(at), "il boss non ci costruisce sopra una barricata")
	_field.sculpt(at, 2.4, 1.5)
	await _frames(2)
	var moved: Variant = _scrap.nearest(at, 4.0)
	_check(_scrap.count() == before + 1 and moved != null and _planar_distance(moved, at) > 1.0, "il suolo si alza: il rottame rotola, non e sepolto")
	_flatten(at, 3.0)
	_scrap.take_near(at, 5.0, 1)


## R-06: una propria barricata sulla linea verso il giocatore non va spianata.
func _test_own_barricade_in_the_way() -> void:
	print("own barricade in the way")
	_place_player(Vector3.ZERO)
	var p := Vector3(0.0, 0.0, -6.0)
	_boss._raise_barricade_at(p)
	_place_boss(p + Vector3(0.0, 0.0, -3.4))
	var radius := _boss.wall_attraction_radius
	_boss.wall_attraction_radius = 0.0
	var touched := false
	for i in 90:
		await physics_frame
		if _boss.is_demolishing():
			touched = true
			break
	_check(not touched and _boss.barricade_points.has(p), "spingendo contro la propria barricata non la spiana")
	_boss.wall_attraction_radius = radius
	_flatten(p, 3.0)
	await _frames(2)


## R-01: una cima che non si avvicina (qui: il boss non puo muoversi) viene lasciata perdere
## dopo WALL_STALL_SECONDS, e per un po' non lo attira piu.
func _test_abandons_unreachable_wall() -> void:
	print("abandons an unreachable wall")
	_place_player(Vector3.ZERO)
	_place_boss(Vector3(0.0, 0.0, -14.0))
	var mound := Vector3(0.0, 0.0, -9.0)
	_field.sculpt(mound, 2.4, 1.6)
	var radius := _boss.wall_attraction_radius
	_boss.wall_attraction_radius = 6.0
	_boss.speed = 0.0
	await _frames(3)
	_check(_boss.wall_point != Vector3.INF and _planar_distance(_boss.wall_point, mound) < 1.0, "il cumulo lo attira")
	var gave_up := -1
	for i in 240:
		await physics_frame
		if _boss.wall_point == Vector3.INF or _planar_distance(_boss.wall_point, mound) > 1.0:
			gave_up = i
			break
	var expected := int(Demolisher.WALL_STALL_SECONDS * 60.0)
	_check(gave_up >= expected - 5 and gave_up <= expected + 30,
		"senza avvicinarsi per %.0f s lo lascia perdere (frame %d)" % [Demolisher.WALL_STALL_SECONDS, gave_up])
	var next: Vector3 = _boss._nearest_wall_point()
	_check(not _boss._ignored_points.is_empty() and (next == Vector3.INF or _planar_distance(next, mound) > 1.0), "e per un po' quel cumulo non lo attira piu")
	_check(not _boss.is_demolishing(), "non e rimasto incastrato a spianare")
	_boss._ignored_points.clear()
	_boss.speed = _run.tuning.boss_speed
	_boss.wall_attraction_radius = radius
	_flatten(mound, 3.0)


## E-04: un rottame chiuso dentro un anello di argini non recluta nessuno.
func _test_no_carrier_without_route() -> void:
	print("no carrier without a route")
	_place_player(Vector3.ZERO)
	var scrap_world := Vector3(0.0, 0.0, 12.0)
	_seal_ring(scrap_world)
	await _frames(2)
	_path.solve()
	_scrap.spawn_on_ground(scrap_world)
	_check(_path.cost_at(scrap_world) == PathField.UNREACHABLE, "il rottame e senza strada")
	_place_boss(scrap_world + Vector3(0.0, 0.0, 7.0))
	_boss.speed = 0.0
	var radius := _boss.wall_attraction_radius
	_boss.wall_attraction_radius = 0.0
	var outsider := _director.spawn_at(scrap_world + Vector3(7.0, 0.0, 0.0))
	await _frames(RETARGET_FRAMES)
	_check(not outsider.has_errand and _boss.crew_size() == 0, "nessun rottamatore reclutato verso un rottame irraggiungibile")
	_open_ring(scrap_world)
	await _frames(2)
	_path.solve()
	await _frames(RETARGET_FRAMES)
	_check(outsider.has_errand and _boss.crew_size() == 1, "riaperta la strada, viene reclutato")
	# Abbattuto come in gioco: il boss lo toglie dalla squadra da solo.
	outsider.take_damage(outsider.health)
	await _frames(2)
	_scrap.take_near(scrap_world, 8.0, 2)
	_boss.speed = _run.tuning.boss_speed
	_boss.wall_attraction_radius = radius
	await _frames(2)


## T-01: con una rovina sul punto d'ingresso, il boss nasce sulla cella percorribile piu vicina.
func _test_spawn_point_is_walkable() -> void:
	print("spawn point is walkable")
	_place_player(Vector3.ZERO)
	_run.boss_direction = Vector3(0.0, 0.0, -1.0)
	var block := StaticBody3D.new()
	block.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(22.0, 2.0, 16.0)
	shape.shape = box
	block.add_child(shape)
	_scene.add_child(block)
	block.global_position = _run.boss_direction * _run.tuning.boss_spawn_distance + Vector3(0.0, 1.0, 0.0)
	await _frames(2)
	_path.scan_static_obstacles()
	var naive := _run.boss_direction * _run.tuning.boss_spawn_distance
	_check(not _path.is_walkable(naive), "il punto d'ingresso nominale e dentro la rovina")
	var point: Vector3 = _run._boss_spawn_point()
	_check(_path.is_walkable(point), "il boss nasce su una cella percorribile (%s)" % point)
	_check(_planar_distance(point, naive) <= 24.0, "vicino al punto nominale (%.1f m)" % _planar_distance(point, naive))
	_scene.remove_child(block)
	block.free()
	await _frames(2)
	_path.scan_static_obstacles()


## R-05: il Cassone non punta a un rottame chiuso dentro un anello di argini.
func _test_caravan_ignores_sealed_scrap() -> void:
	print("caravan ignores sealed scrap")
	# Il rottame sta entro il raggio di raccolta dal giocatore (6 m), ma il giocatore e la
	# macchina restano fuori dal fianco dell'anello; il cassone deve avere posto.
	_place_player(Vector3(-3.0, 0.0, 0.0))
	var caravan: Caravan = _scene.get_node(^"Caravan")
	caravan.carried = 0
	var lead := caravan.lead()
	var sealed := Vector3(2.5, 0.0, 0.0)
	_seal_ring(sealed)
	await _frames(2)
	_path.solve()
	var before := _scrap.count()
	_scrap.spawn_on_ground(sealed)
	# Un Cassone guasto o in ritirata non chiede mete: il controllo sotto sarebbe vuoto.
	_check(lead.state == Machine.State.OK, "il capofila e in ordine (stato %d, %d PV)" % [lead.state, lead.health])
	var destination: Vector3 = lead._choose_destination()
	_check(_planar_distance(destination, sealed) > 1.0, "il rottame sigillato non e la destinazione del Cassone")
	_open_ring(sealed)
	await _frames(2)
	_path.solve()
	destination = lead._choose_destination()
	_check(_planar_distance(destination, sealed) < 0.5, "riaperto, il rottame torna a essere la destinazione (costo %.1f, dest %s, rottami %d)" % [_path.cost_at(sealed), destination, _scrap.count()])
	_scrap.take_near(sealed, 1.0, 1)
	_check(_scrap.count() == before, "pulizia")
	await _frames(2)


## R-03: cantiere occupato dal giocatore con scorta sufficiente: ne sceglie un altro e costruisce.
func _test_site_moves_when_occupied() -> void:
	print("site moves when occupied")
	_place_player(Vector3.ZERO)
	_place_boss(Vector3(0.0, 0.0, -9.6))
	_boss.speed = 0.0
	var radius := _boss.wall_attraction_radius
	_boss.wall_attraction_radius = 0.0
	_boss._choose_site()
	var site := _boss.site_point()
	_check(site != Vector3.INF, "cantiere scelto fra boss e giocatore")
	var before := _boss.barricade_points.size()
	_player.global_position = site + Vector3(0.0, 0.88, 0.0)
	_player._invulnerable_left = 600.0
	_boss._site_scrap = _boss.walls_per_barricade
	_boss._try_build_at_site()
	var built := _boss.barricade_points.size() == before + 1
	var elsewhere := built and _planar_distance(_boss.barricade_points.back(), site) > 1.0
	_check(built and elsewhere, "col giocatore sul cantiere la barricata nasce altrove (%d)" % _boss.barricade_points.size())
	for p: Vector3 in _boss.barricade_points.duplicate():
		_flatten(p, 3.0)
	await _frames(2)
	_player._invulnerable_left = 0.0
	_boss.speed = _run.tuning.boss_speed
	_boss.wall_attraction_radius = radius
	await _frames(2)


## R-04: un portatore carico senza cantiere valido aspetta accanto al boss senza far
## scadere il tempo (niente ciclo "molla, rireclutato" ogni 10 s).
func _test_carrier_waits_without_site() -> void:
	print("carrier waits without a site")
	_place_boss(Vector3(0.0, 0.0, -12.0))
	# Giocatore addosso al boss: nessuna direzione per il cantiere, nessun cantiere valido.
	_player.global_position = _boss.global_position + Vector3(0.0, 0.88, 0.0)
	_player._invulnerable_left = 600.0
	_boss.speed = 0.0
	_boss._clear_site(false)
	var carrier := _director.spawn_at(_boss.global_position + Vector3(3.0, 0.0, 0.0))
	carrier.set_errand(_boss.global_position)
	carrier.set_carrying(true)
	_boss._crew[carrier] = 1.0
	await _frames(90)
	_check(_boss._crew.has(carrier) and carrier.carrying_scrap and _boss._crew[carrier] >= 0.99,
		"senza cantiere il portatore carico aspetta e il tempo non scorre (%.2f)" % _boss._crew.get(carrier, -1.0))
	carrier.take_damage(carrier.health)
	await _frames(2)
	_scrap.take_near(_boss.global_position, 6.0, 3)
	_player._invulnerable_left = 0.0
	_boss.speed = _run.tuning.boss_speed
	_place_player(Vector3.ZERO)
	await _frames(2)


func _test_uphill_slows() -> void:
	print("uphill")
	_boss.wall_attraction_radius = 0.0
	_place_player(Vector3(6.0, 0.0, 2.4))
	_place_boss(Vector3(-6.0, 0.0, 2.4))
	_player._invulnerable_left = 600.0
	await _frames(40)
	var normal_speed := Vector2(_boss.velocity.x, _boss.velocity.z).length()
	_check(absf(normal_speed - _run.tuning.boss_speed) < 0.15, "in piano va a %.2f m/s" % normal_speed)
	# Dosso dolce fra boss e giocatore: lo sale e rallenta.
	var mound := Vector3(2.0, 0.0, 2.4)
	_field.sculpt(mound, 5.0, 2.0)
	_place_boss(Vector3(-2.5, 0.0, 2.4))
	await _frames(30)
	var slow_speed := Vector2(_boss.velocity.x, _boss.velocity.z).length()
	_check(slow_speed < _run.tuning.boss_speed * 0.85, "in salita rallenta (%.2f m/s)" % slow_speed)
	_flatten(mound, 6.0)
	_player._invulnerable_left = 0.0
	_boss.wall_attraction_radius = _run.tuning.boss_wall_attraction_radius


func _test_contact_damage() -> void:
	print("contact")
	_boss.wall_attraction_radius = 0.0
	_player.set_max_health(_run.tuning.player_max_health)
	_place_boss(Vector3(-2.0, 0.0, -2.4))
	_place_player(Vector3(-0.9, 0.0, -2.4))
	await _frames(3)
	_check(_player.health == _run.tuning.player_max_health - _run.tuning.boss_contact_damage,
		"il contatto toglie %d punti vita (vita %d)" % [_run.tuning.boss_contact_damage, _player.health])
	_player.set_max_health(_run.tuning.player_max_health)
	_boss.wall_attraction_radius = _run.tuning.boss_wall_attraction_radius


func _test_weapon_hits_boss() -> void:
	print("weapon")
	_director.set_physics_process(false)
	_place_player(Vector3(0.0, 0.0, 2.4))
	_place_boss(Vector3(5.0, 0.0, 2.4))
	await _frames(2)
	var before := _boss.health
	_check(_weapon.find_target() == _boss, "la chiodatrice lo prende di mira")
	_weapon.set_physics_process(true)
	await _frames(120)
	_weapon.set_physics_process(false)
	_check(_boss.health < before, "i chiodi lo feriscono (%d -> %d)" % [before, _boss.health])
	_director.set_physics_process(true)


func _test_defeat_completes_level() -> void:
	print("defeat")
	_place_player(Vector3(0.0, 0.0, 2.4))
	_place_boss(Vector3(7.0, 0.0, 2.4))
	for i in 3:
		_director.spawn_at(Vector3(-6.0 + i, 0.0, 5.0))
	var kills := _director.kills
	var completed := [false]
	_run.level_completed.connect(func() -> void: completed[0] = true)
	var carried: int = (_scene.get_node(^"Caravan") as Caravan).carried
	# La piazzola di estrazione (D-076) ha la sua suite: qui si prova la vittoria diretta.
	_run.extraction_pad = null
	_boss.take_damage(_boss.health)
	await _frames(2)
	var panel: GameOverPanel = _scene.get_node(^"GameOverPanel")
	_check(completed[0] and _run.is_over and _run.boss_phase == ArenaRun.BossPhase.DEFEATED, "boss abbattuto: livello completato")
	_check(panel.is_open and panel.is_victory and paused, "schermata di vittoria, gioco fermo")
	_check(_director.enemies.is_empty() and not _director.spawning, "l'orda si ritira")
	_check(_run._final_map != null, "la mappa di fine run e catturata prima di congedare l'orda")
	_check(_director.kills == kills + 1, "conta solo il boss fra gli abbattuti")
	carried += _run.recovery_scrap()
	_check(_run.scrap_out(true) == carried + _run.tuning.boss_scrap_bonus, "rottami portati fuori: cassone + premio (%d)" % _run.scrap_out(true))
	_check(_run.scrap_out(false) == int(carried * _run.tuning.death_scrap_share), "morendo se ne salva la meta")
	var before: int = _run.recovery_scrap()
	var elapsed_before := _run.elapsed
	_run.elapsed += 600.0
	_check(_run.recovery_scrap() == before, "aspettare non rende rottami")
	_run.elapsed = elapsed_before
	_run.progression.level += int(3.0 * _run.tuning.recovery_scrap_levels)
	_check(_run.tuning.recovery_scrap_levels > 0.0 and _run.scrap_out(true) == carried + 3 + _run.tuning.boss_scrap_bonus
		and _run.recovery_scrap() == before + 3, "rottami di recupero: uno ogni %.0f livelli guadagnati" % _run.tuning.recovery_scrap_levels)
	_check(not _hud.is_boss_bar_visible(), "barra del boss nascosta")
	paused = false
