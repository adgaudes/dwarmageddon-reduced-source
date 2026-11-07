extends SceneTree
## Colosso pilotato, eventi e relitti (D-093, piano C): valori di partenza in CaravanTuning e forza
## a bordo in MachineFusion; poi, sulla carovana della scena `ruins_arena` (task 2), i posti in piu,
## il Cassone piu vicino, lo stacco gratuito degli eventi, il guasto e la ritirata forzata.
## Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/colossus_tests.gd

const TUNING_PATH := "res://resources/tuning/caravan_default.tres"
const ArenaScene := preload("res://scenes/main/ruins_arena.tscn")
const RunScene := preload("res://scenes/main/arena_run.tscn")
const RailwayScene := preload("res://scenes/main/railway_run.tscn")

var _failures := 0
var t: CaravanTuning
var _scene: Node3D
var _field: TerrainField
var _caravan: Caravan
var _queue: TerrainWriteQueue
var _scrap_field: ScrapField
## Sezioni sulla run vera (`arena_run.tscn`, dal task 3).
var _run: ArenaRun
var _player: PlayerCharacter


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	if not OS.get_environment("PROTOTYPE01_SEED").is_valid_int():
		OS.set_environment("PROTOTYPE01_SEED", "20261014")
	t = load(TUNING_PATH) as CaravanTuning
	_check(t != null, "caravan_default.tres si carica come CaravanTuning")
	if t != null:
		_test_tuning()
		_test_power()
		await _test_caravan()
		await _test_relics()
		await _test_events()
		# Sezioni dei task 5-7, in ordine: _test_pilot, _test_mechanic, _test_workshop (tutte con await).
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


func _seconds(seconds: float) -> void:
	await _frames(ceili(seconds * 60))


func _test_tuning() -> void:
	print("tuning")
	_check(is_equal_approx(t.pilot_hold_seconds, 0.5) and is_equal_approx(t.pilot_mount_range, 2.5), "tenuta e portata della salita")
	_check(is_equal_approx(t.pilot_power_bonus, 0.5) and is_equal_approx(t.pilot_speed_factor, 0.7), "+50% ai moduli, -30% di velocita")
	_check(is_equal_approx(t.pilot_fuel_interval, 10.0) and t.pilot_fuel_cost == 1 and is_equal_approx(t.pilot_eject_below, 0.3), "carburante e sbalzo")
	_check(t.pilot_trample_damage == 2 and is_equal_approx(t.pilot_aim_reach, 3.0) and is_equal_approx(t.pilot_forced_retreat_seconds, 6.0), "travolgere, mira, ritirata forzata")
	_check(t.quake_detach_count == 1 and t.train_detach_count == 1 and is_equal_approx(t.train_throw_min, 6.0) and is_equal_approx(t.train_throw_max, 8.0), "eventi")
	_check(is_equal_approx(t.relic_pickup_range, 2.0) and t.module_limit == 6, "relitto a 2 m; il limite del tuning resta 6")


func _test_power() -> void:
	print("power")
	_check(is_equal_approx(MachineFusion.power_of(6, t), 1.75) and is_equal_approx(MachineFusion.power_of(6, t, true), 2.625), "forza del colosso: 1,75 autonomo, 2,625 pilotato")
	_check(is_equal_approx(MachineFusion.power_of(1, t, true), 1.5), "una piccola pilotata (solo logica) varrebbe 1,5")
	_check(is_equal_approx(MachineFusion.pilot_speed(6.0, t), 4.2), "6 m/s a piedi: 4,2 a bordo")


func _test_caravan() -> void:
	print("caravan")
	_scene = ArenaScene.instantiate()
	_scene.name = "Scene"
	root.add_child(_scene)
	_field = _scene.get_node(^"TerrainField")
	_caravan = _scene.get_node(^"Caravan")
	_scrap_field = _scene.get_node(^"ScrapField")
	_queue = TerrainWriteQueue.new()
	_queue.name = "TerrainWriteQueue"
	_queue.terrain_field = _field
	_scene.add_child(_queue)
	_caravan.configure({terrain_field = _field, write_queue = _queue})
	await _frames(2)
	_check(_caravan.scrap_field == _scrap_field, "la carovana usa lo ScrapField della scena")
	await _reset()
	_test_module_limit()
	await _test_nearest_cargo()
	await _test_detach_random()
	await _test_break_and_retreat()
	root.remove_child(_scene)
	_scene.queue_free()


## Carovana con il solo Cassone (3 rottami) e nessun posto in piu: le macchine di prima escono con
## `remove_machine` (come in fusion_tests).
func _reset() -> Machine:
	for machine in _caravan.machines.duplicate():
		_caravan.remove_machine(machine)
	_caravan.extra_module_slots = 0
	await _frames(1)
	var lead := _caravan.add_machine(&"cargo")
	_caravan.carried = 3
	return lead


## Capofila Cassone con la Torretta fusa dentro: 5 rottami chiesti (ne entrano 2, Cassone pieno a
## 5), fusione da 1, ne restano 4 nel Cassone.
func _reset_fused() -> Machine:
	var lead: Machine = await _reset()
	var turret := _add(&"turret")
	_caravan.add_scrap(5)
	_check(_caravan.fuse(lead, turret) and lead.modules.size() == 2 and _caravan.carried == 4, "Cassone e Torretta fusi, 4 rottami")
	return lead


func _add(module_id: StringName) -> Machine:
	var machine := _caravan.add_machine(module_id)
	_check(machine != null and machine.has_module(module_id), "add_machine(%s)" % module_id)
	return machine


## Guasta subito, senza immunita ne invulnerabilita.
func _break(machine: Machine) -> void:
	machine._hit_cooldown_left = 0.0
	machine._invulnerable_left = 0.0
	machine.take_hit(machine.health)


func _place(machine: Machine, at: Vector3) -> void:
	machine.global_position = Vector3(at.x, _field.height_at(at) + Caravan.GROUND_CLEARANCE, at.z)
	machine.velocity = Vector3.ZERO
	machine.reset_physics_interpolation()


## Officina mobile: il settimo posto sta nella carovana (`extra_module_slots`), non nel tuning.
func _test_module_limit() -> void:
	print("module limit")
	for id: StringName in [&"turret", &"drill", &"shovel", &"welder", &"siren"]:
		_add(id)
	_check(_caravan.module_count() == 6 and not _caravan.has_room() and _caravan.module_limit() == 6, "piena a 6")
	_caravan.extra_module_slots = 1
	_check(_caravan.module_limit() == 7 and _caravan.has_room() and _caravan.add_machine(&"magnet") != null, "Officina mobile: settimo posto")
	_check(not _caravan.has_room() and _caravan.tuning.module_limit == 6, "piena a 7; il tuning condiviso resta 6")


func _test_nearest_cargo() -> void:
	print("nearest cargo")
	await _reset()
	var a := _caravan.lead()
	var b := _add(&"cargo")
	var c := _add(&"turret")
	_place(a, Vector3(10, 0, 0))
	_place(b, Vector3(2, 0, 0))
	_place(c, Vector3(0, 0, 0))
	_check(_caravan.nearest_cargo_machine(Vector3.ZERO) == b, "il Cassone piu vicino, non il capofila ne la Torretta")
	_break(b)
	_check(_caravan.nearest_cargo_machine(Vector3.ZERO) == b, "anche guasto")
	_caravan.remove_machine(a)
	_caravan.remove_machine(b)
	_check(_caravan.nearest_cargo_machine(Vector3.ZERO) == c and _caravan.lead() == c, "senza Cassoni il capofila")
	_caravan.remove_machine(c)
	_check(_caravan.nearest_cargo_machine(Vector3.ZERO) == null, "senza macchine null")


## Stacco degli eventi (terremoto, treno): gratis, senza macchina nuova, la sorgente conserva la
## frazione di vita, i rottami di un Cassone staccato cadono a terra accanto alla macchina.
func _test_detach_random() -> void:
	print("detach random")
	var m: Machine = await _reset_fused()
	m.health = 10
	_check(m.max_health == 15, "media a 15 PV (10/15)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var id := _caravan.detach_random(m, rng)
	_check(id == &"turret" or id == &"cargo", "stacca uno dei due (%s)" % id)
	_check(m.modules.size() == 1 and m.max_health == 6 and m.health == 4 and _caravan.machines.size() == 1, "sorgente a un modulo, 4/6 (frazione conservata), nessuna macchina nuova")
	_check(_caravan.detach_random(m, rng) == &"" and m.modules.size() == 1, "una piccola non perde nulla")
	var outsider := Machine.new()
	_check(_caravan.detach_random(outsider, rng) == &"", "una macchina fuori dalla carovana non perde nulla")
	outsider.free()
	# Cassone staccato coi rottami: a terra. Si rifonde finche lo staccato e il Cassone (lo
	# staccato con la Torretta non lascia rottami: il conteggio di prima resta valido).
	var before := _scrap_field.count()
	var dropped: Array[Vector3] = []
	var on_spawn := func(at: Vector3) -> void: dropped.append(at)
	_scrap_field.scrap_spawned.connect(on_spawn)
	m = await _reset_fused()
	var tries := 1
	while _caravan.detach_random(m, rng) != &"cargo" and tries < 20:
		m = await _reset_fused()
		tries += 1
	_scrap_field.scrap_spawned.disconnect(on_spawn)
	_check(tries < 20, "il Cassone esce entro 20 prove (%d)" % tries)
	_check(_caravan.carried == 0 and _scrap_field.count() == before + 4 and dropped.size() == 4, "4 rottami a terra (5 meno il costo della fusione)")
	var beside := dropped.size() == 4
	for i in dropped.size():
		var from_machine := Machine.planar_distance(dropped[i], m.global_position)
		beside = beside and from_machine > 0.5 and from_machine < 2.0
		if i > 0:
			beside = beside and is_equal_approx(Machine.planar_distance(dropped[i], dropped[i - 1]), 0.8)
	_check(beside, "in fila accanto alla macchina, a 0,8 m l'uno dall'altro")
	# Da guasta: si stacca lo stesso e resta guasta a 0 PV.
	m = await _reset_fused()
	_break(m)
	_check(_caravan.detach_random(m, rng) != &"" and m.modules.size() == 1 and m.is_broken() and m.health == 0, "anche da guasta, resta guasta")


func _test_break_and_retreat() -> void:
	print("break and retreat")
	var m: Machine = await _reset()
	var hits := [0]
	m.damaged.connect(func(_amount: int) -> void: hits[0] += 1)
	m.break_down()
	_check(m.is_broken() and m.health == 0 and hits[0] == 0 and m._hit_cooldown_left == 0.0, "guasta subito, senza damaged ne immunita")
	m.break_down()
	_check(m.is_broken() and m.health == 0, "su una guasta non fa nulla")
	m.repair(0.5)
	m.force_retreat(1.0)
	await _frames(1)
	_check(m.state == Machine.State.RETREAT, "in ritirata forzata a meta vita (sopra retreat_below)")
	await _seconds(1.1)
	_check(m.state == Machine.State.OK, "scaduta: torna in ordine")
	m.force_retreat(1.0)
	m.break_down()
	_check(m.is_broken(), "guasta vince sulla ritirata forzata")
	_check(m.trample_damage() == 1, "travolgere di base 1")
	m.piloted = true
	_check(m.trample_damage() == 2, "travolgere pilotato 2")
	m.piloted = false


# --- Relitti dei moduli staccati (task 3) ------------------------------------------------------

## Run vera senza nemici, level-up, boss ne eventi (come fusion_tests._test_bench); il disco
## protetto della partenza si toglie per poter scolpire vicino al giocatore.
func _test_relics() -> void:
	print("relics")
	await _start_run(RunScene)
	var relics := _run.module_relics
	_check(relics != null and relics.get_parent() == _run and relics.name == "ModuleRelics" and relics.terrain_field == _field
		and relics.player == _player and relics.count() == 0, "ModuleRelics creato da ArenaRun coi servizi, vuoto")
	if relics == null:
		_stop_run()
		return
	# `arena_run.tscn` ha il terremoto e non il treno (sta nella scena dei binari).
	_check(_run.quake_event != null and _run.quake_event.module_relics == relics
		and (_run.train_event == null or _run.train_event.module_relics == relics), "il terremoto (e il treno, se c'e) riceve i relitti")
	await _test_relic_pickup()
	await _test_relic_full_and_nearest()
	await _test_relic_follows_ground()
	await _test_relic_glint()
	_test_relic_models()
	_stop_run()


## Run vera di [param scene] senza nemici, level-up, boss ne eventi in programma; il disco
## protetto della partenza e tolto.
func _start_run(scene: PackedScene) -> void:
	_scene = scene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_field = _scene.get_node(^"TerrainField")
	(_scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	await _frames(5)
	(_scene.get_node(^"PlayerWeapon") as AutoWeapon).set_physics_process(false)
	_run.progression.xp_first_level = 100000
	_run.boss_call_at = 0.0
	for event: WorldEvent in [_run.quake_event, _run.train_event]:
		if event != null:
			event.schedule([])
	_run._start_protect_left = 0.0
	_field.set_protected(Vector3.ZERO, _field.tuning.start_protected_radius_m, false)


func _stop_run() -> void:
	root.remove_child(_scene)
	_scene.queue_free()


func _test_relic_pickup() -> void:
	var relics := _run.module_relics
	var at := _player.global_position + Vector3(1.0, 0.0, 0.0)
	var i := relics.drop(&"siren", at)
	_check(relics.count() == 1 and relics.module_of(i) == &"siren" and relics.nearest_index(_player.global_position, 2.0) == i, "relitto a 1 m")
	_check(relics.nearest_index(_player.global_position, 0.5) == -1, "fuori portata: nessun indice")
	await _frames(1)
	_check(_run.hud.caravan_strip().relic_prompt_visible() and not _run.hud.caravan_strip().bench_prompt_visible(), "tasto Riprendi acceso")
	var machines := _caravan.machines.size()
	await _joy(JOY_BUTTON_X)
	await _frames(2)
	_check(relics.count() == 0 and _caravan.machines.size() == machines + 1 and _caravan.machines[-1].primary_module_id() == &"siren", "X: la Sirena torna macchina piccola")
	_check(not _run.fusion_pad.has_bench_request(), "la pressione che riprende non chiede il banco")
	await _frames(1)
	_check(not _run.hud.caravan_strip().relic_prompt_visible(), "ripreso: tasto Riprendi spento")


func _test_relic_full_and_nearest() -> void:
	while _caravan.has_room():
		_caravan.add_machine(&"turret")
	var relics := _run.module_relics
	relics.drop(&"drill", _player.global_position + Vector3(1.5, 0.0, 0.0))
	relics.drop(&"shovel", _player.global_position + Vector3(0.6, 0.0, 0.0))
	await _frames(1)
	_check(not _run.hud.caravan_strip().relic_prompt_visible() and not _run.relic_available(), "piena: tasto spento")
	await _key(KEY_R)
	await _frames(2)
	_check(relics.count() == 2, "piena: R non prende nulla")
	_caravan.remove_machine(_caravan.machines[-1])
	await _frames(1)
	_check(_run.relic_available() and _run.hud.caravan_strip().relic_prompt_visible(), "con posto: tasto Riprendi acceso")
	await _key(KEY_R)
	await _frames(2)
	_check(relics.count() == 1 and relics.module_of(relics.nearest_index(_player.global_position, 5.0)) == &"drill"
		and _caravan.machines[-1].primary_module_id() == &"shovel", "con posto: R prende la Pala, la piu vicina")
	relics.discard_in_rect(Rect2(-100, -100, 200, 200))
	_check(relics.count() == 0, "discard_in_rect li toglie")


func _test_relic_follows_ground() -> void:
	var relics := _run.module_relics
	var at := _player.global_position + Vector3(4.0, 0.0, 0.0)
	var i := relics.drop(&"turret", at)
	var y0 := relics.position_of(i).y
	_check(is_equal_approx(y0, _field.height_at(at)), "il pezzo poggia alla quota del suolo")
	_field.set_protected(at, 2.0, false)
	_field.sculpt(at, 1.0, 1.0)
	await _frames(4)
	_check(relics.position_of(i).y > y0 + 0.5, "il pezzo sale col suolo")
	relics.take(i)
	_check(relics.count() == 0, "take lo toglie")


## Il luccichio si vede solo entro GLINT_RANGE dal giocatore; senza relitti _process e spento.
func _test_relic_glint() -> void:
	var relics := _run.module_relics
	var near := relics.drop(&"magnet", _player.global_position + Vector3(1.0, 0.0, 0.0))
	var far := relics.drop(&"beacon", _player.global_position + Vector3(0.0, 0.0, ModuleRelics.GLINT_RANGE + 3.0))
	await process_frame
	await process_frame
	_check(relics.is_processing() and relics.glint_visible(near) and not relics.glint_visible(far), "luccichio vicino si, lontano no")
	relics.take(near)
	relics.take(far)
	_check(relics.count() == 0 and not relics.is_processing(), "senza relitti il luccichio non gira")


## Pezzo del modulo (Torretta) o, senza pezzo (Cassone), cubo da 0,4 m del colore del catalogo;
## sempre sul layer visivo delle macchine.
func _test_relic_models() -> void:
	var relics := _run.module_relics
	var turret := relics.drop(&"turret", _player.global_position + Vector3(-3.0, 0.0, 0.0))
	var cargo := relics.drop(&"cargo", _player.global_position + Vector3(-3.0, 0.0, 2.0))
	var meshes := relics.piece_of(turret).find_children("*", "MeshInstance3D", true, false)
	var layered := not meshes.is_empty()
	for mesh: MeshInstance3D in meshes:
		layered = layered and mesh.layers == Machine.VISUAL_LAYER
	_check(meshes.size() > 1 and layered, "Torretta: il suo pezzo, sul layer delle macchine")
	var bottom := INF
	for mesh: MeshInstance3D in meshes:
		bottom = minf(bottom, (mesh.global_transform * mesh.mesh.get_aabb()).position.y)
	_check(absf(bottom - relics.position_of(turret).y) < 0.01, "il punto piu basso del pezzo sta alla quota del suolo (%.3f su %.3f)"
		% [bottom, relics.position_of(turret).y])
	var boxes := relics.piece_of(cargo).find_children("*", "MeshInstance3D", true, false)
	var box: MeshInstance3D = boxes[0] if boxes.size() == 1 else null
	_check(box != null and box.mesh is BoxMesh and (box.mesh as BoxMesh).size.is_equal_approx(Vector3.ONE * 0.4)
		and (box.material_override as StandardMaterial3D).albedo_color == MachineCatalog.find(&"cargo").color
		and box.layers == Machine.VISUAL_LAYER, "Cassone senza pezzo: cubo da 0,4 m del suo colore")
	relics.take(turret)
	relics.take(cargo)
	# Indici fuori lista: risposte neutre invece di un errore (gli eventi e i task dopo le chiamano).
	_check(relics.module_of(-1) == &"" and relics.module_of(99) == &"" and relics.position_of(99) == Vector3.INF
		and relics.position_of(-1) == Vector3.INF and relics.take(99) == &"" and relics.take(-1) == &"", "indici fuori lista: nome vuoto e INF")


# --- Terremoto e treno staccano moduli (task 4) -------------------------------------------------

## Terremoto sulla run del quartiere (`arena_run.tscn`), treno su quella dei binari
## (`railway_run.tscn`).
func _test_events() -> void:
	print("events: quake")
	await _start_run(RunScene)
	var ready_quake := _run.module_relics != null and _run.quake_event != null and _run.quake_event.module_relics == _run.module_relics
	_check(ready_quake and _run.quake_event.module_detach_count == t.quake_detach_count and not _run.quake_event.on_tracks.is_valid(),
		"il terremoto ha i relitti e il numero di moduli del tuning; nel quartiere niente binari")
	if ready_quake:
		await _test_quake_detaches()
		await _test_quake_once_per_machine()
	_stop_run()
	await _frames(2)
	print("events: train")
	await _start_run(RailwayScene)
	var ready_train := _run.module_relics != null and _run.train_event != null and _run.train_event.module_relics == _run.module_relics
	_check(ready_train and _run.train_event.module_detach_count == t.train_detach_count
		and is_equal_approx(_run.train_event.throw_min, t.train_throw_min) and is_equal_approx(_run.train_event.throw_max, t.train_throw_max),
		"il treno ha i relitti e i valori del tuning")
	if ready_train:
		await _test_train_breaks_and_detaches()
		await _test_train_small_only_breaks()
		await _test_train_sweeps_relics()
	_stop_run()


func _until(condition: Callable, seconds: float) -> bool:
	for i in ceili(seconds * 60):
		if condition.call():
			return true
		await physics_frame
	return condition.call()


func _place_player(at: Vector3) -> void:
	_player.global_position = Vector3(at.x, _field.height_at(at) + 0.88, at.z)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


## Terremoto deterministico (seme dell'evento fisso, giocatore nell'origine) con preavviso corto:
## ritorna la faglia appena annunciata.
func _start_quake(cells_per_second: float) -> Array[Vector3]:
	var quake := _run.quake_event
	_place_player(Vector3.ZERO)
	quake.rng.seed = 20261010
	quake.warning_seconds = 0.5
	quake.cells_per_second = cells_per_second
	quake.schedule([_run.elapsed + quake.warning_seconds + 0.1])
	await _until(func() -> bool: return quake.state == QuakeEvent.State.WARNING, 2.0)
	return quake.fault_points.duplicate()


## Dove il terremoto posa il modulo staccato alla pennellata [param p]: oltre il solco se si puo,
## altrimenti dal lato della cresta, altrimenti sul punto (fuori dai binari: qui non ce ne sono).
func _quake_relic_point(p: Vector3) -> Vector3:
	var side := _run.quake_event.fault_side()
	var limit := _field.half_extents()
	for candidate: Vector3 in [p + side * 2.5, p - side * 2.5]:
		if absf(candidate.x) <= limit.x and absf(candidate.z) <= limit.y and not _field.is_protected(candidate):
			return candidate
	return p


## Prima pennellata (con una dopo) lontana dal giocatore il cui relitto cadrebbe fuori dalla
## fascia dei binari (il controllo del test vale anche qui, dove la fascia non c'e); -1 se nessuna.
func _quake_index(fault: Array[Vector3]) -> int:
	for i in range(1, fault.size() - 1):
		var c := _quake_relic_point(fault[i])
		var far := Machine.planar_distance(fault[i], _player.global_position) > 4.0 \
			and Machine.planar_distance(fault[i + 1], _player.global_position) > 4.0
		if far and not RailwayDistrict.is_on_tracks(Vector2(c.x, c.z)):
			return i
	return -1


func _test_quake_detaches() -> void:
	print("quake detaches")
	var quake := _run.quake_event
	var relics := _run.module_relics
	var fused: Machine = await _reset_fused()
	var small := _add(&"drill")
	_check(_caravan.lead() == fused and _caravan.machines[1] == small, "capofila fuso (Cassone e Torretta), dietro una Trivella")
	var hits := {}
	var on_hit := func(what: StringName) -> void: hits[what] = int(hits.get(what, 0)) + 1
	quake.quake_hit.connect(on_hit)
	var fault: Array[Vector3] = await _start_quake(1000.0)
	var k := _quake_index(fault)
	_check(quake.state == QuakeEvent.State.WARNING and k >= 0, "faglia annunciata, pennellata scelta (%d di %d)" % [k, fault.size()])
	if k < 0:
		quake.quake_hit.disconnect(on_hit)
		return
	var before := quake.quakes
	# Le macchine seguono il giocatore: rimesse sulla faglia a ogni passo fino alla scossa.
	var pinned := func() -> bool:
		if quake.quakes > before:
			return true
		_place(fused, fault[k])
		_place(small, fault[k + 1])
		return false
	await _until(pinned, 4.0)
	quake.quake_hit.disconnect(on_hit)
	_check(quake.quakes == before + 1, "il terremoto e passato")
	_check(fused.modules.size() == 1 and not fused.is_broken() and small.modules.size() == 1 and not small.is_broken(),
		"la fusa perde un modulo, la piccola no, nessuna guasta")
	var expected := _quake_relic_point(fault[k])
	var index := relics.nearest_index(expected, 0.5)
	var p := relics.position_of(index)
	_check(relics.count() == 1 and index >= 0 and not RailwayDistrict.is_on_tracks(Vector2(p.x, p.z))
		and absf(Machine.planar_distance(p, fault[k]) - 2.5) < 0.01, "un relitto a terra a 2,5 m dalla faglia, fuori dalla fascia")
	_check(_cargo_and_turret(relics.module_of(index), fused.primary_module_id()), "il relitto e il modulo staccato (%s)" % relics.module_of(index))
	_check(quake.modules_detached == 1 and int(hits.get(&"module", 0)) == 1, "una macchina colpita: modules_detached 1, un quake_hit module")
	_check(_caravan.lead() != null and _caravan.carried >= 0, "capofila valido")


## Un colosso da 6 che segue il fronte della faglia: un solo modulo per terremoto; al terremoto
## dopo ne perde un altro (`_detached` si azzera alla scossa).
func _test_quake_once_per_machine() -> void:
	print("quake once per machine")
	var quake := _run.quake_event
	var relics := _run.module_relics
	relics.discard_in_rect(Rect2(-500.0, -500.0, 1000.0, 1000.0))
	var colossus: Machine = await _reset_fused()
	for id: StringName in [&"drill", &"shovel", &"welder", &"siren"]:
		var other := _add(id)
		_caravan.add_scrap(5)
		_caravan.fuse(colossus, other)
	_check(colossus.modules.size() == 6 and _caravan.machines.size() == 1, "colosso da 6 moduli")
	var fault: Array[Vector3] = await _start_quake(4.0)
	_check(fault.size() >= 4, "faglia di %d pennellate" % fault.size())
	var before := quake.quakes
	var visited := {}
	# Sempre sulla prossima pennellata del fronte.
	var follow := func() -> bool:
		if quake.quakes > before:
			return true
		var i: int = mini(quake._front, fault.size() - 1) if quake.is_shaking() else 0
		if quake.is_shaking():
			visited[i] = true
		_place(colossus, fault[i])
		return false
	await _until(follow, 10.0)
	_check(quake.quakes == before + 1 and visited.size() >= 3, "terremoto passato col colosso su %d pennellate" % visited.size())
	_check(colossus.modules.size() == 5 and relics.count() == 1 and quake.modules_detached == 1, "un solo modulo per terremoto")
	fault = await _start_quake(1000.0)
	var k := maxi(_quake_index(fault), 0)
	before = quake.quakes
	var pinned := func() -> bool:
		if quake.quakes > before:
			return true
		_place(colossus, fault[k])
		return false
	await _until(pinned, 4.0)
	_check(quake.quakes == before + 1 and colossus.modules.size() == 4 and relics.count() == 2, "al terremoto dopo ne perde un altro")
	relics.discard_in_rect(Rect2(-500.0, -500.0, 1000.0, 1000.0))


## Il relitto e la macchina si sono divisi Cassone e Torretta.
func _cargo_and_turret(relic: StringName, kept: StringName) -> bool:
	return (relic == &"cargo" and kept == &"turret") or (relic == &"turret" and kept == &"cargo")


## Un passaggio del treno corto e veloce; [param each_frame] gira prima di ogni passo. Vero se e
## passato.
func _train_pass(each_frame: Callable) -> bool:
	var train := _run.train_event
	var passes := train.passes
	train.warning_seconds = 1.0
	train.speed = 80.0
	train.next_at = _run.elapsed + 1.05
	for i in 900:
		each_frame.call()
		await physics_frame
		if train.passes > passes:
			return true
	return false


func _test_train_breaks_and_detaches() -> void:
	print("train breaks and detaches")
	var train := _run.train_event
	var relics := _run.module_relics
	var at := Vector3(10.0, 0.0, 0.0)
	# Fuori dalla fascia ma entro il guinzaglio (oltre leash_distance la macchina torna da lui).
	_place_player(at + Vector3(0.0, 0.0, 12.0))
	var fused: Machine = await _reset_fused()
	var companions := [0]
	var on_hit := func(what: StringName) -> void:
		if what == &"companion":
			companions[0] += 1
	train.train_hit.connect(on_hit)
	# Tenuta sulla fascia (seguirebbe il giocatore) finche il treno non la investe.
	var pinned := func() -> void:
		if not fused.is_broken():
			_place(fused, at)
	var passed: bool = await _train_pass(pinned)
	train.train_hit.disconnect(on_hit)
	_check(passed and companions[0] == 1, "il treno e passato e ha investito la macchina una volta")
	_check(fused.is_broken() and fused.modules.size() == 1, "guasta e con un modulo in meno")
	var p := relics.position_of(0)
	_check(relics.count() == 1 and absf(p.z) >= RailwayDistrict.TRACK_HALF_WIDTH + 6.0 - 0.01
		and absf(p.z) <= RailwayDistrict.TRACK_HALF_WIDTH + 8.0 + 0.01 and not RailwayDistrict.is_on_tracks(Vector2(p.x, p.z)),
		"relitto a 6-8 m oltre il bordo, fuori dalla fascia (z=%.2f)" % p.z)
	_check(p.z > 0.0 and absf(p.x - at.x) < 1.0 and is_equal_approx(p.y, _field.height_at(p)),
		"dal lato della spinta (a z = 0 verso sud), alla x della macchina, al suolo")
	_check(_cargo_and_turret(relics.module_of(0), fused.primary_module_id()), "il relitto e il modulo staccato (%s)" % relics.module_of(0))
	_check(absf(fused.global_position.z) > RailwayDistrict.TRACK_HALF_WIDTH, "spinta fuori come oggi")


func _test_train_small_only_breaks() -> void:
	print("train small only breaks")
	var relics := _run.module_relics
	relics.discard_in_rect(Rect2(-500.0, -500.0, 1000.0, 1000.0))
	var at := Vector3(-10.0, 0.0, 1.0)
	_place_player(at + Vector3(0.0, 0.0, 12.0))
	var small: Machine = await _reset()
	var pinned := func() -> void:
		if not small.is_broken():
			_place(small, at)
	var passed: bool = await _train_pass(pinned)
	_check(passed, "il treno e passato")
	_check(small.is_broken() and small.modules.size() == 1 and relics.count() == 0, "la piccola si guasta e basta")
	_check(absf(small.global_position.z) > RailwayDistrict.TRACK_HALF_WIDTH, "spinta fuori")


func _test_train_sweeps_relics() -> void:
	print("train sweeps relics")
	var relics := _run.module_relics
	_place_player(Vector3(0.0, 0.0, 20.0))
	var keeper: Machine = await _reset()
	_place(keeper, Vector3(2.0, 0.0, 21.0))
	var i := relics.drop(&"drill", Vector3(5.0, 0.0, 1.5))
	var p := relics.position_of(i)
	_check(relics.count() == 1 and RailwayDistrict.is_on_tracks(Vector2(p.x, p.z)), "relitto posato sulla fascia")
	var passed: bool = await _train_pass(func() -> void: pass)
	_check(passed and relics.count() == 0, "il treno porta via il relitto")
	_check(not keeper.is_broken(), "fuori dalla fascia la macchina resta intera")


func _send_joypad_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


## Pressione e rilascio in frame distinti, come un dito reale (da fusion_tests).
func _joy(button: JoyButton) -> void:
	_send_joypad_button(button, true)
	await process_frame
	_send_joypad_button(button, false)
	await process_frame


func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _key(key: Key) -> void:
	_send_key(key, true)
	await process_frame
	_send_key(key, false)
	await process_frame
