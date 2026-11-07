extends SceneTree
## Fusione delle macchine (D-093, piano B): taglie, vita, velocita, forza, costi, anteprime di
## fusione e sgancio, sei combinazioni e valori di partenza in CaravanTuning; poi, sulla carovana
## della scena `ruins_arena` (task 2), macchine a piu moduli, `fuse`, `detach` e `remove_machine`
## e la regola del capofila; la piazzola di fusione (task 4), su un campo creato qui e nella
## scena `arena_run`; infine il banco di fusione (task 5) sulla run vera, con eventi di input veri
## del controller e della tastiera; poi il profilo versione 3 (task 7): sezione [machines], file v2,
## futuri e non validi, e la scoperta di una combinazione fondendo dal banco. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/fusion_tests.gd

const TUNING_PATH := "res://resources/tuning/caravan_default.tres"
const ArenaScene := preload("res://scenes/main/ruins_arena.tscn")
const RunScene := preload("res://scenes/main/arena_run.tscn")
## Posizione del pezzo della Torretta sulla macchina (TurretModule.build_part).
const TURRET_PART_POSITION := Vector3(0.0, 0.42, -0.25)
const ProfileScript := preload("res://scripts/services/player_profile.gd")
## File di prova del profilo: mai `user://profile.cfg` del giocatore.
const PROFILE_PATH := "user://profile_fusion_test.cfg"

var _failures := 0
var t: CaravanTuning
var _scene: Node3D
var _player: PlayerCharacter
var _field: TerrainField
var _caravan: Caravan
var _queue: TerrainWriteQueue
var _xp: XpField
## Combinazioni ricevute da `combo_formed` e macchine da `machine_removed`.
var _combos_formed: Array[StringName] = []
var _removed: Array[Machine] = []
## Sezione piazzola: la pedana e il suo campo di 120 x 120 m.
var _pad: FusionPad
var _pad_field: TerrainField
## Sezione banco: la run di `arena_run.tscn`.
var _run: ArenaRun


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	if not OS.get_environment("PROTOTYPE01_SEED").is_valid_int():
		OS.set_environment("PROTOTYPE01_SEED", "20261014")
	t = load(TUNING_PATH) as CaravanTuning
	_check(t != null, "caravan_default.tres si carica come CaravanTuning")
	if t != null:
		_test_sizes()
		_test_costs()
		_test_combos()
		_test_preview()
		_test_tuning()
		_test_profile()
		await _test_caravan()
		await _test_pad()
		await _test_pad_in_run()
		await _test_bench()
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


func _test_sizes() -> void:
	print("sizes")
	var sizes := [0, 1, 1, 2, 2, 3]; var health := [6, 15, 23, 36, 45, 63]
	var speed := [5.0, 4.5, 4.5, 4.0, 4.0, 3.5]; var power := [1.0, 1.15, 1.30, 1.45, 1.60, 1.75]
	for n in range(1, 7):
		_check(MachineFusion.size_of(n, t) == sizes[n - 1], "taglia di %d moduli" % n)
		_check(MachineFusion.max_health_of(n, t) == health[n - 1], "vita di %d moduli" % n)
		_check(is_equal_approx(t.max_speed * MachineFusion.speed_factor_of(n, t), speed[n - 1]), "velocita di %d" % n)
		_check(is_equal_approx(MachineFusion.power_of(n, t), power[n - 1]), "forza di %d" % n)
	_check(MachineFusion.SIZE_NAMES[3] == "Colosso", "nomi delle taglie")
	var scales := [1.0, 1.25, 1.25, 1.5, 1.5, 1.8]
	for n in range(1, 7):
		_check(is_equal_approx(MachineFusion.model_scale_of(n, t), scales[n - 1]), "scala del modello di %d moduli" % n)


func _test_costs() -> void:
	print("costs")
	_check(MachineFusion.fuse_cost(1, t) == 1 and MachineFusion.fuse_cost(3, t) == 3 and MachineFusion.detach_cost(t) == 1, "costi")
	var total := 0
	for i in 5: total += MachineFusion.fuse_cost(1, t)
	_check(total == 5, "sei piccole in un colosso: 5 rottami")


func _test_combos() -> void:
	print("combos")
	_check(MachineCatalog.COMBOS.size() == 6 and MachineCatalog.find_combo(&"dozer").name == "Ruspa", "sei combinazioni coi nomi della spec")
	_check(MachineCatalog.find_combo(&"extractor").parts == [&"drill", &"magnet"], "parti dell'Estrattore")
	_check(MachineCatalog.combos_of([&"magnet", &"drill"]) == [&"extractor"], "l'ordine dei moduli non conta")
	_check(MachineCatalog.combos_of([&"turret", &"beacon", &"siren"]) == [&"reflector", &"trap"], "due combinazioni in una macchina")
	_check(MachineCatalog.combos_of([&"drill", &"shovel", &"cargo"]) == [&"mobile_mixer", &"dozer"], "Betoniera e Ruspa")
	_check(MachineCatalog.combos_of([&"turret", &"turret"]).is_empty() and MachineCatalog.find_combo(&"nope").is_empty(), "nessuna")
	var ids: Array[StringName] = []
	for combo in MachineCatalog.combos():
		ids.append(combo.id)
	_check(ids == MachineCatalog.COMBOS and is_same(MachineCatalog.combos(), MachineCatalog.combos()), "voci nell'ordine di COMBOS, costruite una volta")
	_check(MachineCatalog.find_combo(&"trap").text == "Chi e attirato prende doppio danno dalla Torretta.", "testo della Trappola")
	_check(MachineCatalog.combos_of([&"drill", &"magnet", &"magnet"]) == [&"extractor"], "un modulo doppio non ripete la combinazione")


func _test_preview() -> void:
	print("preview")
	var p := MachineFusion.preview_fuse([&"drill"], 6, 6, [&"magnet"], 3, 6, t)
	_check(p.size == 1 and p.max_health == 15 and p.health == 11 and is_equal_approx(p.speed, 4.5), "anteprima: media, 11/15, 4,5 m/s")
	_check(p.combos == [&"extractor"] and p.new_combos == [&"extractor"] and p.cost == 1 and p.allowed, "anteprima: combinazione nuova, costo 1")
	var d := MachineFusion.preview_detach([&"turret", &"beacon", &"siren"], 2, 23, 23, t)
	_check(d.source.max_health == 15 and d.source.health == 15 and d.detached.max_health == 6, "sgancio: 15/15 e 6/6")
	_check(d.lost_combos == [&"trap"] and d.source.combos == [&"reflector"] and d.cost == 1, "sgancio: Trappola persa")
	_check(not MachineFusion.preview_detach([&"cargo"], 0, 6, 6, t).allowed, "una piccola non si sgancia")
	var bad := MachineFusion.preview_detach([&"cargo", &"turret"], 2, 15, 15, t)
	_check(not bad.allowed and bad.source.is_empty() and bad.detached.is_empty() and bad.cost == 1, "indice fuori dai moduli: anteprima vuota, non permessa")
	_check(MachineFusion.carried_health(0, 0, 15) == 15 and MachineFusion.carried_health(5, 10, 6) == 3, "vita portata: massimo nullo -> piena; meta -> meta")
	_check(not MachineFusion.preview_fuse([&"cargo", &"turret", &"magnet"], 23, 23, [&"drill", &"shovel", &"siren", &"welder"], 36, 36, t).allowed, "oltre 6 moduli no")
	var q := MachineFusion.preview_fuse([&"drill", &"magnet"], 15, 15, [&"shovel"], 6, 6, t)
	_check(q.new_combos == [&"dozer"] and q.combos == [&"extractor", &"dozer"] and q.modules == [&"drill", &"magnet", &"shovel"], "anteprima: solo la Ruspa e nuova, la seconda entra nella prima")


func _test_tuning() -> void:
	print("tuning")
	_check(t.size_min_modules == PackedInt32Array([1, 2, 4, 6]) and is_equal_approx(t.power_per_extra_module, 0.15), "taglie e forza")
	_check(is_equal_approx(t.pad_boss_fraction, 0.5) and t.pad_warning_seconds == 15.0 and t.pad_distance_min == 20.0 and t.pad_distance_max == 30.0 and t.pad_cells == 4, "piazzola")
	_check(t.fuse_cost_per_module == 1 and t.detach_cost_per_module == 1 and t.max_modules_per_machine == 6, "costi e massimo per macchina")


# --- Sezione carovana (task 2) ---------------------------------------------------------------

## La scena con la sua carovana, una coda di scrittura e un campo dei frammenti creati qui e
## passati a `configure`.
func _test_caravan() -> void:
	print("caravan")
	_scene = ArenaScene.instantiate()
	_scene.name = "Scene"
	root.add_child(_scene)
	_player = _scene.get_node(^"Player")
	_field = _scene.get_node(^"TerrainField")
	_caravan = _scene.get_node(^"Caravan")
	_queue = TerrainWriteQueue.new()
	_queue.name = "TerrainWriteQueue"
	_queue.terrain_field = _field
	_scene.add_child(_queue)
	_xp = XpField.new()
	_xp.name = "XpField"
	_xp.player = _player
	_scene.add_child(_xp)
	_caravan.configure({terrain_field = _field, write_queue = _queue, xp_field = _xp})
	_caravan.combo_formed.connect(func(id: StringName) -> void: _combos_formed.append(id))
	_caravan.machine_removed.connect(func(machine: Machine) -> void: _removed.append(machine))
	await _frames(2)
	_check(_queue.bodies.has(_caravan.lead()), "il capofila sta nella coda di scrittura")
	await _test_fuse_two()
	await _test_fuse_lead_absorbed()
	await _test_fuse_rejects()
	await _test_six_into_colossus()
	await _test_detach()
	await _test_detach_keeps_fraction()
	await _test_remove_machine()
	await _test_lead_rule()
	await _test_combo_signal()
	await _test_duplicates()
	root.remove_child(_scene)
	_scene.queue_free()


## Carovana con il solo Cassone (3 rottami): le macchine di prima escono con `remove_machine`.
func _reset() -> Machine:
	for machine in _caravan.machines.duplicate():
		_caravan.remove_machine(machine)
	await _frames(1)
	var lead := _caravan.add_machine(&"cargo")
	_caravan.carried = 3
	_combos_formed.clear()
	_removed.clear()
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


func _visible_cubes(machine: Machine) -> int:
	return machine._cargo.filter(func(c: MeshInstance3D) -> bool: return c.visible).size()


func _test_fuse_two() -> void:
	print("fuse two")
	var lead := await _reset()
	var turret := _add(&"turret")
	_check(_caravan.can_fuse(lead, turret), "si possono fondere")
	_check(_caravan.fuse(lead, turret), "fusione riuscita")
	_check(_caravan.machines.size() == 1 and lead.module_ids() == [&"cargo", &"turret"] and _caravan.carried == 2,
		"una macchina, 1 rottame speso (%s, %d)" % [lead.module_ids(), _caravan.carried])
	_check(lead.size == MachineFusion.Size.MEDIUM and lead.max_health == 15 and lead.health == 15,
		"media, 15/15 (%d/%d)" % [lead.health, lead.max_health])
	_check(is_equal_approx(lead.model_scale, 1.25) and is_equal_approx(lead.power, 1.15) and is_equal_approx(lead.top_speed(), 4.5)
		and is_equal_approx(lead.contact_reach(), _caravan.tuning.contact_radius * 1.25), "scala 1,25, forza 1,15, 4,5 m/s, contatto in scala")
	_check(lead.modules.all(func(m: MachineModule) -> bool: return is_equal_approx(m.power, 1.15)), "la forza passa a ogni modulo")
	var part := lead.get_node_or_null(^"TurretPart") as Node3D
	var expected := Machine.RIG_GROUND + (TURRET_PART_POSITION + Machine.PART_STACK[1] - Machine.RIG_GROUND) * 1.25
	_check(part != null and part.position.is_equal_approx(expected) and part.scale.is_equal_approx(Vector3.ONE * 1.25),
		"pezzo impilato al posto 1 e in scala attorno al suolo (%s)" % [part.position if part != null else Vector3.INF])
	var ring := lead.get_node(^"GroundRing") as Decal
	_check(ring.size.is_equal_approx(Machine.RING_SIZE * 1.25) and ring.position.is_equal_approx(Machine.RIG_GROUND), "anello in scala, sul suolo")
	_check(not _queue.bodies.has(turret) and _removed == [turret], "assorbita fuori dalla coda, machine_removed")
	await _frames(1)
	_check(lead.get_node_or_null(^"TurretPart") != null and not is_instance_valid(turret), "pezzo montato, assorbita liberata")


## Il capofila (Cassone con 3 rottami) entra in una Torretta: i rottami passano col modulo meno
## il costo, la Torretta diventa capofila; da guasta non si sgancia nulla.
func _test_fuse_lead_absorbed() -> void:
	print("fuse lead absorbed")
	var lead := await _reset()
	var turret := _add(&"turret")
	_check(_caravan.lead() == lead and lead.cargo().carried == 3, "il Cassone e capofila con 3 rottami")
	_check(_caravan.fuse(turret, lead), "la Torretta assorbe il capofila")
	_check(_caravan.machines == [turret] and turret.module_ids() == [&"turret", &"cargo"] and _caravan.lead() == turret,
		"la Torretta e la sola macchina e il capofila (%s)" % [turret.module_ids()])
	_check(turret.cargo() != null and turret.cargo().carried == 2 and _caravan.carried == 2 and _caravan.working_carried() == 2,
		"i rottami passano col Cassone meno il costo (%d)" % _caravan.carried)
	_check(_caravan.can_detach(turret, 1), "da sana si sgancia il Cassone")
	_break(turret)
	_check(turret.is_broken() and not _caravan.can_detach(turret, 1) and _caravan.detach(turret, 1) == null
		and turret.modules.size() == 2 and _caravan.carried == 2, "da guasta non si sgancia, niente cambia")
	await _frames(1)


func _test_fuse_rejects() -> void:
	print("fuse rejects")
	var lead := await _reset()
	var turret := _add(&"turret")
	var drill := _add(&"drill")
	var before := _caravan.module_count()
	_break(turret)
	_check(turret.is_broken() and not _caravan.can_fuse(lead, turret) and not _caravan.fuse(lead, turret)
		and not _caravan.fuse(turret, lead), "guasta: no")
	_check(not _caravan.fuse(lead, lead), "stessa macchina: no")
	_caravan.carried = 0
	_check(not _caravan.can_fuse(lead, drill) and not _caravan.fuse(lead, drill), "senza rottami: no")
	_caravan.carried = 3
	var stranger := (load(Caravan.MACHINE_SCENE_PATH) as PackedScene).instantiate() as Machine
	_check(not _caravan.can_fuse(lead, stranger) and not _caravan.fuse(lead, stranger) and not _caravan.fuse(stranger, drill),
		"macchina estranea: no")
	stranger.free()
	_check(_caravan.machines.size() == 3 and _caravan.carried == 3 and _caravan.module_count() == before
		and lead.module_ids() == [&"cargo"] and drill.module_ids() == [&"drill"], "niente cambia")
	# Sette moduli in una: la carovana ne ammette 7 solo qui (copia della taratura).
	var tuning := _caravan.tuning
	lead = await _reset()
	_caravan.tuning = tuning.duplicate() as CaravanTuning
	_caravan.tuning.module_limit = 7
	lead.cargo().capacity = 10
	_caravan.carried = 10
	for id: StringName in [&"turret", &"drill", &"shovel", &"siren", &"beacon"]:
		_caravan.fuse(lead, _add(id))
	var magnet := _add(&"magnet")
	_check(lead.modules.size() == 6 and _caravan.working_carried() >= 1, "base da 6 moduli, rottami bastano")
	_check(not _caravan.can_fuse(lead, magnet) and not _caravan.fuse(lead, magnet) and not _caravan.fuse(magnet, lead)
		and lead.modules.size() == 6 and _caravan.carried == 5 and _caravan.machines.size() == 2, "7 moduli in una: no")
	_caravan.tuning = tuning


func _test_six_into_colossus() -> void:
	print("colossus")
	var lead := await _reset()
	var others: Array[Machine] = []
	for id: StringName in [&"turret", &"turret", &"drill", &"shovel", &"siren"]:
		others.append(_add(id))
	_caravan.carried = 5
	for m in others:
		_check(_caravan.fuse(lead, m), "fusione")
	_check(_caravan.carried == 0 and lead.modules.size() == 6 and lead.size == MachineFusion.Size.COLOSSUS, "colosso per 5 rottami")
	_check(lead.max_health == 63 and is_equal_approx(lead.top_speed(), 3.5) and is_equal_approx(lead.power, 1.75),
		"63 PV, 3,5 m/s, forza 1,75 (%d, %.2f, %.2f)" % [lead.max_health, lead.top_speed(), lead.power])
	_check(lead.get_node_or_null(^"TurretPart2") != null and lead.get_node_or_null(^"TurretModule2") != null and lead.slot == 0,
		"nomi distinti, posto 0")
	_check(lead._parts.size() == 5 and is_equal_approx(lead.model_scale, 1.8), "cinque pezzi, scala 1,8")


func _test_detach() -> void:
	print("detach")
	var m := await _reset()
	_caravan.fuse(m, _add(&"turret"))
	_caravan.fuse(m, _add(&"siren"))
	_caravan.carried = 3
	_check(m.module_ids() == [&"cargo", &"turret", &"siren"] and m.max_health == 23 and m.health == 23, "[cargo, turret, siren] 23/23")
	_check(_caravan.can_detach(m, 2) and not _caravan.can_detach(m, 3), "si sgancia un modulo che c'e")
	var new := _caravan.detach(m, 2)
	_check(new != null and new.module_ids() == [&"siren"] and new.health == 6 and new.max_health == 6 and _queue.bodies.has(new),
		"Sirena piccola e piena")
	_check(m.max_health == 15 and m.health == 15 and _caravan.carried == 2 and new.slot != m.slot,
		"sorgente 15/15, 1 rottame, posto diverso (%d/%d, %d)" % [m.health, m.max_health, _caravan.carried])
	_check(m.get_node_or_null(^"SirenPart") == null and m.get_node_or_null(^"SirenModule") == null and m._parts.size() == 1,
		"pezzo e modulo tolti dalla sorgente")
	_check(_caravan.detach(new, 0) == null and not _caravan.can_detach(new, 0), "una piccola non si sgancia")
	# Il Cassone con 2 rottami: la macchina nuova li porta, il totale scende solo del costo.
	var cargo := _caravan.detach(m, 0)
	_check(cargo != null and cargo.module_ids() == [&"cargo"] and cargo.cargo().carried == 1 and cargo.cargo().capacity == 5
		and _caravan.carried == 1, "il Cassone sganciato porta i suoi rottami (%d)" % _caravan.carried)
	_check(m.module_ids() == [&"turret"] and m.cargo() == null and m.size == MachineFusion.Size.SMALL and m.max_health == 6
		and is_equal_approx(m.model_scale, 1.0), "la sorgente torna piccola")
	_check(_caravan.lead() == cargo, "capofila: la macchina col Cassone")
	_caravan.fuse(cargo, m)
	_caravan.carried = 0
	_check(cargo.modules.size() == 2 and not _caravan.can_detach(cargo, 1) and _caravan.detach(cargo, 1) == null,
		"senza rottami non si sgancia")


## Revisione finale: la sganciata nasce con la frazione di vita della sorgente, cosi sganciare e
## rifondere non cura (prima: telaio nuovo pieno, +40% di vita a 2 rottami il giro).
func _test_detach_keeps_fraction() -> void:
	print("detach keeps fraction")
	var m := await _reset()
	_caravan.fuse(m, _add(&"turret"))
	_caravan.carried = 3
	m.health = 3
	var p := MachineFusion.preview_detach(m.module_ids(), 1, 3, 15, _caravan.tuning)
	_check(p.source.health == 1 and p.detached.health == 1 and p.detached.max_health == 6, "anteprima: 1/6 e 1/6")
	var turret := _caravan.detach(m, 1)
	_check(turret != null and turret.health == 1 and turret.max_health == 6 and m.health == 1 and m.max_health == 6,
		"a 3/15: sorgente 1/6, sganciata 1/6 (%d, %d)" % [m.health, turret.health if turret != null else -1])
	_check(_caravan.fuse(m, turret) and m.health == 3 and m.max_health == 15 and _caravan.carried == 1,
		"rifusa: torna 3/15, 2 rottami spesi, niente cura (%d/%d)" % [m.health, m.max_health])
	await _frames(1)


func _test_remove_machine() -> void:
	print("remove machine")
	var lead := await _reset()
	var turret := _add(&"turret")
	var welder := _add(&"welder")
	var spot := Vector3(4.0, 0.0, 6.0)
	_player.global_position = Vector3(spot.x, _field.height_at(spot) + 0.88, spot.z)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	var at := spot + Vector3(1.0, 0.0, 0.0)
	turret.global_position = Vector3(at.x, _field.height_at(at) + Caravan.GROUND_CLEARANCE, at.z)
	turret.reset_physics_interpolation()
	_break(turret)
	# Il Saldatore fermo tiene la chiave della guasta (lo stato del suo `tick` in raggio).
	welder.set_physics_process(false)
	var welding := welder.module(&"welder") as WelderModule
	welding._broken_elapsed[turret] = 1.0
	_player.interact_held = true
	await _frames(20)
	_check(_caravan.repairing_machine() == turret and _caravan.repair_progress() > 0.0, "riparazione della Torretta in corso")
	var carried := _caravan.carried
	_caravan.remove_machine(turret)
	_check(_caravan.repairing_machine() == null and _caravan.repair_progress() == 0.0, "riparazione azzerata")
	_check(not welding._broken_elapsed.has(turret) and not _queue.bodies.has(turret) and not _caravan.machines.has(turret)
		and _removed == [turret], "nessun riferimento rimasto")
	await _frames(int(_caravan.tuning.repair_seconds * 60.0) + 10)
	_check(_caravan.carried == carried and not is_instance_valid(turret), "niente speso, Torretta liberata")
	_player.interact_held = false
	welder.set_physics_process(true)
	var second := _add(&"cargo")
	_caravan.remove_machine(lead)
	_check(_caravan.lead() == second, "tolto il capofila: il secondo Cassone")
	_caravan.remove_machine(second)
	_caravan.remove_machine(welder)
	_check(_caravan.machines.is_empty() and _caravan.lead() == null, "carovana vuota: nessun capofila")
	await _frames(1)


func _test_lead_rule() -> void:
	print("lead rule")
	var first := await _reset()
	var second := _add(&"cargo")
	_check(_caravan.lead() == first, "il Cassone piu vecchio")
	_break(first)
	_check(_caravan.lead() == second, "il primo guasto: il secondo")
	_break(second)
	_check(_caravan.lead() == first, "entrambi guasti: il primo")
	_caravan.remove_machine(first)
	_caravan.remove_machine(second)
	var turret := _add(&"turret")
	_add(&"drill")
	_check(_caravan.lead() == turret, "nessun Cassone: la prima macchina")


func _test_combo_signal() -> void:
	print("combo signal")
	await _reset()
	var drill := _add(&"drill")
	var magnet := _add(&"magnet")
	_check(_caravan.fuse(drill, magnet) and _combos_formed == [&"extractor"], "combo_formed una volta: Estrattore (%s)" % [_combos_formed])
	_check(drill.combos() == [&"extractor"] and drill.has_combo(&"extractor"), "la macchina ha l'Estrattore")
	_check(_caravan.fuse(drill, _add(&"turret")) and _combos_formed == [&"extractor"], "una Torretta non la riemette")
	_break(drill)
	_check(not drill.has_combo(&"extractor") and drill.combos() == [&"extractor"], "da guasta la combinazione non vale")


func _test_duplicates() -> void:
	print("duplicates")
	var lead := await _reset()
	var magnet := _add(&"magnet")
	var other := _add(&"magnet")
	_check(_caravan.fuse(magnet, other), "due Calamite fuse")
	await _frames(1)
	var entries := _xp.attractors.filter(func(e: Dictionary) -> bool: return is_instance_valid(e.node) and e.node == magnet)
	_check(entries.size() == 1 and _xp.attractors.size() == 1, "un solo attrattore per la macchina (%d)" % _xp.attractors.size())
	var second := _add(&"cargo")
	_check(_caravan.fuse(lead, second), "due Cassoni fusi")
	_caravan.carried = 7
	_check(_caravan.capacity == 10 and _visible_cubes(lead) == 7, "capienza 10, cubetti visibili == carried (%d)" % _visible_cubes(lead))
	await _frames(120)
	_check(_visible_cubes(lead) == _caravan.carried and _xp.attractors.size() == 1, "dopo 2 s cubetti e attrattore in ordine")
	# Sganciando una delle due Calamite la gemella che resta tiene il suo attrattore.
	var single := _caravan.detach(magnet, 1)
	await _frames(1)
	var nodes := _xp.attractors.map(func(e: Dictionary) -> Object: return e.node)
	_check(single != null and nodes.size() == 2 and nodes.has(magnet) and nodes.has(single), "sganciata una Calamita: due attrattori, uno per macchina")
	# Revisione finale: il secondo Cassone della stessa macchina pretende un rottame solo se la
	# macchina ci sta andando (niente pretesa fantasma dal suo ultimo bersaglio).
	var boxes := lead.modules.filter(func(mod: MachineModule) -> bool: return mod is CargoModule)
	_check(boxes.size() == 2, "due Cassoni sul capofila (%d)" % boxes.size())
	if boxes.size() == 2:
		var second_box := boxes[1] as CargoModule
		var scrap_at := Vector3(7.0, 0.0, 7.0)
		second_box._target = scrap_at
		second_box._searched = true
		lead._goal_point = Vector3.ZERO
		_check(second_box.claimed_scrap() == null and not _caravan.is_scrap_claimed(scrap_at, null), "la macchina va altrove: nessuna pretesa")
		lead._goal_point = scrap_at
		_check(second_box.claimed_scrap() == scrap_at and _caravan.is_scrap_claimed(scrap_at, null), "la macchina ci va: pretesa valida")
		second_box._forget_target()


# --- Sezione piazzola (task 4) ---------------------------------------------------------------

## Pedana su un campo piano di 120 x 120 m creato qui, senza PathField, lampioni ne binari.
func _test_pad() -> void:
	print("pad")
	_pad_field = TerrainField.new()
	_pad_field.render = false
	_pad_field.size_m = Vector2(120.0, 120.0)
	root.add_child(_pad_field)
	_pad = FusionPad.new()
	_pad.name = "FusionPad"
	_pad.terrain_field = _pad_field
	_pad.tuning = t
	_pad.rng.seed = 8
	root.add_child(_pad)
	await process_frame
	_check(is_equal_approx(_pad.half_size(), 3.0) and is_equal_approx(_pad.flat_radius(), 3.0 * sqrt(2.0)) and _pad.light() == null,
		"6 m di lato, disco di 4,24 m, nessuna luce prima dell'atterraggio")
	_test_pad_candidates()
	_test_pad_landing_flat()
	_reset_pad_field()
	_test_pad_avoids_pit()
	_reset_pad_field()
	_test_pad_fallback()
	_reset_pad_field()
	await _test_pad_contains()
	_test_pad_keeps_other_protection()
	_reset_pad_field()
	_test_pad_rechecks_at_arrival()
	root.remove_child(_pad)
	_pad.queue_free()
	root.remove_child(_pad_field)
	_pad_field.queue_free()
	await _frames(2)


func _reset_pad_field() -> void:
	_pad_field.reset_to_base(Vector3.ZERO, Vector2(60.0, 60.0))


## Candidati che `find_landing_now` vedra: lo stato del generatore torna com'era.
func _next_candidates(origin: Vector3) -> Array[Vector3]:
	var state := _pad.rng.state
	var points := _pad.candidate_points(origin)
	_pad.rng.state = state
	return points


## Dislivello di un candidato come lo misura la pedana per il ripiego: quota massima meno
## minima sulla griglia di 1 m dentro il disco, o lo scarto del centro dalla base se e maggiore.
func _pad_relief(p: Vector3) -> float:
	var r := _pad.flat_radius()
	var lo := INF
	var hi := -INF
	for ix in range(-4, 5):
		for iz in range(-4, 5):
			if ix * ix + iz * iz > r * r:
				continue
			var h := _pad_field.height_at(p + Vector3(ix, 0.0, iz))
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return maxf(hi - lo, absf(_pad_field.delta_at(p)))


func _test_pad_candidates() -> void:
	print("pad candidates")
	var origin := Vector3(2.0, 0.0, -1.0)
	var points := _next_candidates(origin)
	var radii := [25.0, 22.5, 27.5, 20.0, 30.0]
	var shaped := points.size() == 120 and points == _pad.candidate_points(origin)
	for i in points.size():
		var d := Vector2(points[i].x - origin.x, points[i].z - origin.z).length()
		shaped = shaped and absf(d - float(radii[floori(i / 24.0)])) < 0.001
	_check(shaped, "120 candidati: raggi 25, 22,5, 27,5, 20, 30 m, ripetibili col generatore")
	var a0 := Vector2(points[0].x - origin.x, points[0].z - origin.z).angle()
	var a1 := Vector2(points[1].x - origin.x, points[1].z - origin.z).angle()
	_check(absf(angle_difference(a0, a1) - deg_to_rad(15.0)) < 0.001, "24 angoli ogni 15 gradi")
	_check(_next_candidates(origin)[0] != points[0], "lo scarto cambia a ogni ricerca")


func _test_pad_landing_flat() -> void:
	print("pad landing flat")
	var r := _pad.find_landing_now(Vector3.ZERO)
	var d := Vector2(r.point.x, r.point.z).length()
	_check(r.flat and d >= 20.0 and d <= 30.0, "piano, a 20-30 m")
	_check(absf(d - 25.0) < 0.001, "il primo candidato buono e sull'anello di 25 m (%.2f)" % d)


## Review Focus 1: ne buca ne cumulo, e una buca larga a fondo piatto non vale (delta).
func _test_pad_avoids_pit() -> void:
	print("pad avoids pit")
	var points := _next_candidates(Vector3.ZERO)
	_pad_field.sculpt(points[0], 3.0, -1.0)
	_pad_field.sculpt(points[1], 3.0, 1.0)
	var r := _pad.find_landing_now(Vector3.ZERO)
	var p: Vector3 = r.point
	_check(r.flat and p != points[0] and p != points[1], "buca sul primo candidato e cumulo sul secondo: un altro punto")
	_check(_pad_field.is_flat(p, _pad.flat_radius(), 0.35) and absf(_pad_field.delta_at(p)) <= 0.35,
		"il punto scelto e piano entro 0,35 m e alla base (%.2f)" % _pad_field.delta_at(p))
	_reset_pad_field()
	points = _next_candidates(Vector3.ZERO)
	for i in 20:
		_pad_field.dig_to_base_offset(points[0], 9.0, 1.0)
	# Scavo di raggio 9 m ripetuto: fondo piatto largo 12 m (a 6 m dal centro e ancora a -1 m).
	_check(_pad_field.is_flat(points[0], _pad.flat_radius(), 0.35) and _pad_field.delta_at(points[0]) < -0.9
		and _pad_field.delta_at(points[0] + Vector3(6.0, 0.0, 0.0)) < -0.9, "buca larga 12 m: fondo piatto, 1 m sotto la base")
	r = _pad.find_landing_now(Vector3.ZERO)
	p = r.point
	_check(r.flat and p != points[0] and absf(_pad_field.delta_at(p)) <= 0.35, "la buca a fondo piatto non va (delta)")


## Revisione finale: il centro annunciato viene scavato durante l'avviso; all'arrivo la pedana
## cerca di nuovo e atterra su un punto piano; una nuova programmazione da aperta la nasconde.
func _test_pad_rechecks_at_arrival() -> void:
	print("pad rechecks at arrival")
	_pad.fallback_point = Vector3.ZERO
	_pad.schedule(30.0)
	_pad.advance(_pad.warning_at() - 1.0, 0.0)
	_pad.advance(_pad.warning_at(), 0.0)
	var announced := _pad.center
	_check(_pad.phase == FusionPad.Phase.WARNING and Vector2(announced.x, announced.z).length() >= 20.0, "avviso dato, centro fissato")
	_pad_field.sculpt(announced, 3.0, -1.0)
	_pad.advance(30.0, 0.0)
	var c := _pad.center
	_check(_pad.is_open() and Vector2(c.x - announced.x, c.z - announced.z).length() > 1.0
		and _pad_field.is_flat(c, _pad.flat_radius(), 0.35) and absf(_pad_field.delta_at(c)) <= 0.35,
		"scavato il centro annunciato: atterra altrove, in piano (%.1f m)" % Vector2(c.x - announced.x, c.z - announced.z).length())
	_check(_pad_field.is_protected(c) and not _pad_field.is_protected(announced), "protetto il disco nuovo, non quello annunciato")
	var model := _pad.get_node(^"Model") as Node3D
	_pad.schedule(90.0)
	_check(not model.visible and _pad.phase == FusionPad.Phase.WAITING and not _pad_field.is_protected(c),
		"riprogrammata da aperta: modello nascosto, disco libero")
	_pad.close()
	_pad.schedule(-1.0)


func _test_pad_fallback() -> void:
	print("pad fallback")
	for ix in range(-12, 13):
		for iz in range(-12, 13):
			var p := Vector3(ix * 3.0, 0.0, iz * 3.0)
			var d := Vector2(p.x, p.z).length()
			if d >= 15.0 and d <= 35.0:
				_pad_field.sculpt(p, 2.5, 0.6 + fposmod(p.x * 0.37 + p.z * 0.61, 1.0) * 0.8)
	var points := _next_candidates(Vector3.ZERO)
	var best := Vector3.INF
	var best_relief := INF
	for p in points:
		var relief := _pad_relief(p)
		if relief < best_relief:
			best = p
			best_relief = relief
	var r := _pad.find_landing_now(Vector3.ZERO)
	_check(not r.flat and r.point == best and best_relief > 0.35,
		"anello a cumuli: non piano, il candidato col dislivello minore (%.2f m)" % best_relief)
	_pad.fallback_point = Vector3(1.0, 0.0, 2.0)
	_pad.on_tracks = func(_p: Vector3) -> bool: return true
	r = _pad.find_landing_now(Vector3.ZERO)
	_check(not r.flat and r.point == Vector3(1.0, 0.0, 2.0), "tutto sui binari: il punto di partenza")
	_pad.on_tracks = Callable()


func _test_pad_contains() -> void:
	print("pad contains")
	var c := Vector3(5.0, 0.0, -4.0)
	_pad.land_at(c)
	_check(_pad.is_open() and _pad.phase == FusionPad.Phase.OPEN and _pad.light() != null and _pad.light().name == "PadLight",
		"atterrata: aperta, con la luce PadLight")
	_check(_pad.contains(c + Vector3(2.9, 0, 2.9)) and not _pad.contains(c + Vector3(3.1, 0, 0)), "quadrato di 6 m")
	var deck := _pad.get_node_or_null(^"Model/Deck") as MeshInstance3D
	_check(deck != null and (deck.mesh as BoxMesh).size.is_equal_approx(Vector3(6.0, 0.12, 6.0)) and deck.layers == Machine.VISUAL_LAYER,
		"pianale 6 x 0,12 x 6 m sul layer visivo delle macchine")
	_check(_pad_field.is_protected(c) and _pad_field.is_protected(c + Vector3(4.0, 0.0, 0.0))
		and not _pad_field.is_protected(c + Vector3(5.0, 0.0, 0.0)), "protegge il disco circoscritto")
	# Senza ArenaRun nessuno la fa avanzare: i passi qui, a 60 Hz.
	var model := _pad.get_node(^"Model") as Node3D
	_check(model.position.y > _pad_field.height_at(c) + 10.0, "il modello parte dall'alto")
	for i in 100:
		_pad.advance(0.0, 1.0 / 60.0)
	_check(absf(model.position.y - _pad_field.height_at(c)) < 0.001, "dopo 1,5 s il modello poggia a terra")
	_pad.close()
	_check(not _pad.is_open() and _pad.phase == FusionPad.Phase.CLOSED and not _pad_field.is_protected(c), "chiusa: disco non piu protetto")
	for i in 70:
		_pad.advance(0.0, 1.0 / 60.0)
	_check(not model.visible, "il modello risale e si nasconde")
	await _frames(2)


## Un disco protetto da altri (rovina, cortile) che si sovrappone alla pedana resta protetto
## dopo la chiusura, anche dopo un secondo atterraggio o una nuova programmazione.
func _test_pad_keeps_other_protection() -> void:
	print("pad keeps other protection")
	var c := Vector3(5.0, 0.0, -4.0)
	_pad_field.set_protected(c + Vector3(3.0, 0.0, 0.0), 3.0, true)
	var only_other := c + Vector3(5.5, 0.0, 0.0)
	var both := c + Vector3(2.0, 0.0, 0.0)
	var only_pad := c + Vector3(-3.0, 0.0, 0.0)
	_check(not _pad_field.is_protected(only_pad) and _pad_field.is_protected(both) and _pad_field.is_protected(only_other),
		"prima: protetto solo il disco dell'altro")
	_pad.land_at(c)
	_check(_pad_field.is_protected(only_pad) and _pad_field.is_protected(both) and _pad_field.is_protected(only_other), "atterrata: tutto protetto")
	_pad.close()
	_check(not _pad_field.is_protected(only_pad) and _pad_field.is_protected(both) and _pad_field.is_protected(only_other),
		"chiusa: torna libero solo cio che proteggeva la pedana")
	_pad.land_at(c)
	_pad.land_at(c + Vector3(-12.0, 0.0, 0.0))
	_check(not _pad_field.is_protected(only_pad) and _pad_field.is_protected(both) and _pad_field.is_protected(c + Vector3(-12.0, 0.0, 0.0)),
		"secondo atterraggio: il disco di prima torna com'era")
	_pad.schedule(100.0)
	_check(not _pad_field.is_protected(c + Vector3(-12.0, 0.0, 0.0)) and _pad_field.is_protected(both) and _pad_field.is_protected(only_other),
		"nuova programmazione da aperta: disco rimesso, l'altro intatto")
	_pad.close()
	_pad_field.set_protected(c + Vector3(3.0, 0.0, 0.0), 3.0, false)


## Nella scena `arena_run`: servizi, arrivo a meta della chiamata, avviso, atterraggio,
## marker, protezione, luce e chiusura alla chiamata del boss.
func _test_pad_in_run() -> void:
	print("pad in run")
	var scene: Node3D = RunScene.instantiate()
	root.add_child(scene)
	var run: ArenaRun = scene.get_node(^"Run")
	var player: PlayerCharacter = scene.get_node(^"Player")
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	await _frames(5)
	var pad := run.fusion_pad
	_check(pad != null and pad.get_parent() == run and pad.terrain_field == run.terrain_field and pad.path_field == run.director.path_field
		and pad.lamp_field == run.lamp_field and pad.caravan == run.caravan and pad.tuning == run.caravan.tuning, "pedana creata da ArenaRun coi servizi")
	if pad == null:
		root.remove_child(scene)
		scene.queue_free()
		return
	_check(is_equal_approx(pad.arrive_at(), run.boss_call_at * 0.5) and is_equal_approx(pad.warning_at(), run.boss_call_at * 0.5 - 15.0),
		"a meta della chiamata, 15 s di preavviso")
	_check(pad.rng.seed == run.run_seed + 8 and pad.fallback_point == run._start_position and not pad.on_tracks.is_valid(),
		"seme della run + 8, ripiego al punto di partenza, nessun binario")
	var warned := [0]
	var landed := [0]
	pad.warned.connect(func(_c: Vector3) -> void: warned[0] += 1)
	pad.landed.connect(func(_c: Vector3) -> void: landed[0] += 1)
	var origin := player.global_position
	pad.schedule(run.elapsed + 16.0)
	await _frames(72)
	var text := run.hud.event_warning_text()
	_check(pad.phase == FusionPad.Phase.WARNING and warned[0] == 1 and text == "PIAZZOLA DI FUSIONE  -  15" and run.hud.is_boss_warning_visible(),
		"dopo 1,2 s: avviso con freccia e conto 15 (%s)" % text)
	var d := Vector2(pad.center.x - origin.x, pad.center.z - origin.z).length()
	_check(d >= 20.0 and d <= 30.0, "a 20-30 m dal giocatore (%.1f)" % d)
	await physics_frame
	run.hud.set_event_warning("TRENO", Vector3.LEFT, 5.0, RunHud.TRAIN_COLOR)
	await process_frame
	_check(run.hud.event_warning_text().begins_with("TRENO"), "il treno nello stesso passo vince sulla pedana")
	# Il segnale physics_frame viene prima dei passi dei nodi: il secondo segue il passo dopo.
	await _frames(2)
	_check(run.hud.event_warning_text().begins_with("PIAZZOLA DI FUSIONE"), "il passo dopo torna la pedana")
	# Notte piena prima dell'arrivo: la lampada deve accendersi davvero.
	run.day_night.night_start_seconds = 1.0
	run.day_night.dusk_seconds = 0.001
	await _frames(900)
	var light := pad.light()
	_check(pad.is_open() and landed[0] == 1 and run.terrain_field.is_protected(pad.center) and light != null,
		"arrivata: aperta, disco protetto, luce")
	_check(light != null and is_equal_approx(run.day_night.night_factor, 1.0) and is_equal_approx(light.omni_range, t.pad_light_radius)
		and is_equal_approx(light.light_energy, 2.2) and light.visible,
		"di notte la lampada e accesa: energia 2,2, raggio %.0f m" % t.pad_light_radius)
	var away := Vector3(origin.x - pad.center.x, 0.0, origin.z - pad.center.z).normalized() * 25.0
	var spot := pad.center + away
	player.global_position = Vector3(spot.x, run.terrain_field.height_at(spot) + 0.88, spot.z)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var marker := _pad_marker(run)
	_check(not marker.is_empty() and marker.color == ArenaRun.MARKER_FUSION_COLOR and absf(float(marker.distance) - 25.0) < 0.1
		and run.marker_min_distance() < 25.0, "a 25 m il marker PIAZZOLA")
	var h := run.terrain_field.height_at(pad.center)
	run.terrain_field.player_sculpt(pad.center, 1.5, -0.6, TerrainField.ToolMode.DIG)
	_check(is_equal_approx(run.terrain_field.height_at(pad.center), h), "un attrezzo sul centro non cambia la quota")
	run.call_boss()
	_check(not pad.is_open() and pad.phase == FusionPad.Phase.CLOSED and not run.terrain_field.is_protected(pad.center)
		and not run.hud.event_warning_text().begins_with("PIAZZOLA") and _pad_marker(run).is_empty(),
		"chiamato il boss: chiusa, nessun avviso ne marker, centro non protetto")
	# Pedana programmata e boss chiamato prima dell'avviso (boss riportato in attesa a mano).
	run.boss_phase = ArenaRun.BossPhase.WAITING
	run.boss_call_at = 0.0
	pad.schedule(run.elapsed + 15.5)
	await _frames(15)
	_check(pad.phase == FusionPad.Phase.SEARCHING, "ricerca in corso prima dell'avviso")
	run.call_boss()
	await _frames(75)
	_check(pad.phase == FusionPad.Phase.CLOSED and warned[0] == 1 and landed[0] == 1 and not pad.is_open()
		and not run.hud.event_warning_text().begins_with("PIAZZOLA") and _pad_marker(run).is_empty(),
		"boss chiamato prima dell'avviso: nessun avviso, nessun atterraggio")
	root.remove_child(scene)
	scene.queue_free()


func _pad_marker(run: ArenaRun) -> Dictionary:
	for marker in run.current_markers():
		if marker.text == "PIAZZOLA":
			return marker
	return {}


# --- Banco di fusione (task 5) ----------------------------------------------------------------

## Conta le riprese del gioco: un nodo che si ferma con la pausa riceve NOTIFICATION_UNPAUSED.
class PauseProbe extends Node:
	var resumed := 0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_UNPAUSED:
			resumed += 1


## Run vera, carovana Cassone + Torretta + Trivella, pedana posata sotto il giocatore.
func _test_bench() -> void:
	print("fusion bench")
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_field = _scene.get_node(^"TerrainField")
	(_scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	await _frames(5)
	# Niente chiodatrice, level-up, boss ne eventi (come caravan_hud_tests).
	(_scene.get_node(^"PlayerWeapon") as AutoWeapon).set_physics_process(false)
	_run.progression.xp_first_level = 100000
	_run.boss_call_at = 0.0
	for event: WorldEvent in [_run.quake_event, _run.train_event]:
		if event != null:
			event.schedule([])
	var bench := _run.fusion_bench
	_check(bench != null and bench.get_parent() == _run and bench.layer == 92 and bench.process_mode == Node.PROCESS_MODE_ALWAYS
		and not bench.is_open, "banco creato da ArenaRun: layer 92, sempre attivo, chiuso")
	if bench == null:
		root.remove_child(_scene)
		_scene.queue_free()
		return
	_check(_caravan.add_machine(&"turret") != null and _caravan.add_machine(&"drill") != null and _caravan.machines.size() == 3,
		"carovana Cassone + Torretta + Trivella")
	_run.fusion_pad.land_at(_player.global_position)
	await _frames(2)
	_check(_run.fusion_pad.is_open() and _run.fusion_pad.bench_available() and _caravan.working_carried() == 3,
		"pedana aperta sotto il giocatore, banco disponibile, 3 rottami nei Cassoni")
	await _test_bench_opens_paused()
	await _test_bench_controller_fuse()
	await _test_bench_keyboard_detach()
	await _test_bench_unknown_combo()
	await _test_bench_broken_and_short()
	await _test_bench_repair_wins()
	await _test_bench_menu_queue()
	await _test_discovery_from_fusion()
	paused = false
	root.remove_child(_scene)
	_scene.queue_free()


func _message_ink(bench: FusionBench) -> Color:
	return bench._message.get_theme_color(&"font_color")


func _send_joypad_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


## Pressione e rilascio in frame distinti, come un dito reale.
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


## Attesa oltre la grazia del banco (0,45 s).
func _wait_grace() -> void:
	await _frames(ceili(0.45 * Engine.physics_ticks_per_second))


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _place_machine(machine: Machine, at: Vector3) -> void:
	machine.global_position = Vector3(at.x, _field.height_at(at) + Caravan.GROUND_CLEARANCE, at.z)
	machine.velocity = Vector3.ZERO
	machine.reset_physics_interpolation()


## X vero sulla pedana: due passi e il banco e aperto, a gioco fermo, sulla scheda Fondi. Durante
## la grazia nessuna carta ha il focus e B non chiude; dopo, il focus e sulla prima carta.
func _test_bench_opens_paused() -> void:
	print("bench opens paused")
	var bench := _run.fusion_bench
	var opened := [0]
	bench.opened.connect(func() -> void: opened[0] += 1)
	_send_joypad_button(JOY_BUTTON_X, true)
	await _frames(2)
	_check(bench.is_open and paused and bench.title_text() == "BANCO DI FUSIONE", "X sulla pedana apre il banco in pausa")
	_check(opened[0] == 1 and bench.mode == FusionBench.Mode.FUSE and bench.step == FusionBench.Step.PICK_FIRST
		and bench.card_count() == 3, "aperto una volta, scheda Fondi, primo passo, una carta per macchina")
	_check(bench.scrap_text() == "Nei Cassoni: 3", "rottami nei Cassoni (%s)" % bench.scrap_text())
	_check(bench.card_text(0) == "Piccola - Cassone\nPV 6/6" and bench.card_text(1) == "Piccola - Torretta\nPV 6/6"
		and bench.card_text(2) == "Piccola - Trivella\nPV 6/6", "carte: taglia, moduli e vita (%s)" % bench.card_text(0).replace("\n", " | "))
	_check(_focused() == null, "durante la grazia nessuna carta ha il focus")
	_send_joypad_button(JOY_BUTTON_X, false)
	await _joy(JOY_BUTTON_B)
	_check(bench.is_open and paused, "B durante la grazia non chiude il banco")
	await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	await _key(KEY_PAGEDOWN)
	_check(bench.mode == FusionBench.Mode.FUSE, "RB e PagGiu durante la grazia non cambiano scheda")
	var enemy := _run.director.spawn_at(_player.global_position + Vector3(0.6, 0.0, 0.0))
	var elapsed := _run.elapsed
	var health := _player.health
	await _frames(30)
	_check(_run.elapsed == elapsed and _player.health == health and is_instance_valid(enemy) and bench.is_open,
		"30 passi a banco aperto: tempo e vita fermi con un rottamatore addosso")
	_check(_focused() == bench.card(0), "dopo la grazia il focus e sulla prima carta sceglibile")
	_run.director.clear_horde()


## Solo eventi del controller: A sceglie il capofila, croce a destra porta il focus sulla
## Torretta e l'anteprima la segue, A fonde, B chiude; una sola ripresa del gioco.
func _test_bench_controller_fuse() -> void:
	print("bench controller fuse")
	var bench := _run.fusion_bench
	var probe := PauseProbe.new()
	root.add_child(probe)
	var lead := _caravan.lead()
	var turret := _caravan.machines[1]
	await _joy(JOY_BUTTON_A)
	_check(bench.step == FusionBench.Step.PICK_SECOND and bench.card_count() == 3 and bench.card(0).disabled
		and "BASE" in bench.card_text(0) and _focused() == bench.card(0), "A sceglie la prima carta: il capofila resta la base, col focus")
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	_check(_focused() == bench.card(1) and bench.card_text(1).begins_with("Piccola - Torretta"), "croce a destra: focus sulla Torretta")
	var preview := bench.preview_text()
	_check("Media" in preview and "PV 15/15" in preview and "1 rottame" in preview, "anteprima della fusione")
	_check("Diventa: Media (2 moduli)" in preview and "PV 15/15  Velocita 4,5 m/s" in preview
		and "Costo: 1 rottame (nei Cassoni: 3)" in preview and "Combinazioni: nessuna" in preview,
		"anteprima: taglia, vita, velocita, combinazioni e costo (%s)" % preview.replace("\n", " | "))
	await _joy(JOY_BUTTON_A)
	_check(_caravan.machines.size() == 2 and not is_instance_valid(turret), "A conferma: la Torretta e assorbita")
	_check(_caravan.lead() == lead and lead.module_ids() == [&"cargo", &"turret"] and _caravan.working_carried() == 2,
		"capofila Cassone + Torretta, un rottame speso (%d)" % _caravan.working_carried())
	_check(bench.is_open and paused and bench.step == FusionBench.Step.PICK_FIRST and bench.card_count() == 2
		and bench.card_text(0) == "Media - Cassone + Torretta\nPV 15/15" and bench.scrap_text() == "Nei Cassoni: 2"
		and _focused() == bench.card(0), "dopo la conferma: banco aperto al primo passo, carte rifatte (%s)" % bench.card_text(0).replace("\n", " | "))
	_check(bench.message_text() == "Fusione fatta: Media - Cassone + Torretta" and _message_ink(bench) == FusionBench.INK_NOTICE,
		"esito in verde (%s)" % bench.message_text())
	await _joy(JOY_BUTTON_B)
	await _joy(JOY_BUTTON_B)
	await _frames(2)
	_check(not bench.is_open and not paused and probe.resumed == 1, "B, B: banco chiuso, gioco ripreso una volta (%d)" % probe.resumed)
	root.remove_child(probe)
	probe.free()


## Solo tastiera: R apre, PagGiu passa a Sgancia, Invio sul capofila fuso, freccia sul modulo
## Torretta, Invio sgancia, Esc chiude (senza aprire la pausa).
func _test_bench_keyboard_detach() -> void:
	print("bench keyboard detach")
	var bench := _run.fusion_bench
	var lead := _caravan.lead()
	var r := InputEventKey.new()
	r.physical_keycode = KEY_R
	r.pressed = true
	Input.parse_input_event(r)
	await _frames(2)
	_check(bench.is_open and paused and bench.mode == FusionBench.Mode.FUSE, "R sulla pedana apre il banco, sulla scheda Fondi")
	var release := r.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await _wait_grace()
	await _key(KEY_PAGEDOWN)
	_check(bench.mode == FusionBench.Mode.DETACH and bench.step == FusionBench.Step.PICK_FIRST and bench.card_count() == 2
		and not bench.card(0).disabled and bench.card(1).disabled and _focused() == bench.card(0),
		"PagGiu: Sgancia, la Trivella (un modulo) disattivata, focus sul capofila")
	await _key(KEY_ENTER)
	_check(bench.step == FusionBench.Step.PICK_SECOND and bench.card_count() == 2 and bench.card_text(0).begins_with("Cassone")
		and bench.card_text(1).begins_with("Torretta") and _focused() == bench.card(0), "Invio sul capofila: i suoi due moduli")
	await _key(KEY_RIGHT)
	var preview := bench.preview_text()
	_check(_focused() == bench.card(1) and "Piccola" in preview and "1 rottame" in preview
		and "Diventa: Piccola (1 modulo)" in preview, "freccia sulla Torretta: anteprima (%s)" % preview.replace("\n", " | "))
	await _key(KEY_ENTER)
	_check(_caravan.machines.size() == 3 and lead.module_ids() == [&"cargo"] and _caravan.machines[2].module_ids() == [&"turret"]
		and _caravan.working_carried() == 1, "Invio: la Torretta torna una macchina, un rottame speso")
	_check(bench.is_open and bench.mode == FusionBench.Mode.DETACH and bench.step == FusionBench.Step.PICK_FIRST
		and bench.card_count() == 3, "il banco resta aperto al primo passo, carte rifatte")
	var pause_menu := root.get_node(^"PauseMenu")
	await _key(KEY_ESCAPE)
	await _frames(1)
	_check(not bench.is_open and not paused and not pause_menu.is_open(), "Esc chiude il banco senza aprire la pausa")


## Trivella + Calamita formano l'Estrattore: mai vista (di serie) -> "???"; conosciuta -> nome.
func _test_bench_unknown_combo() -> void:
	print("bench unknown combo")
	var bench := _run.fusion_bench
	var drill := _caravan.machines[1]
	var magnet := _caravan.add_machine(&"magnet")
	_check(drill.module_ids() == [&"drill"] and magnet != null, "Trivella e Calamita nella carovana")
	if magnet == null:
		return
	bench.open(_caravan)
	_check(not bench.combo_known.call(&"extractor"), "di serie nessuna combinazione e conosciuta")
	var di := _caravan.machines.find(drill)
	var mi := _caravan.machines.find(magnet)
	bench.select(di)
	bench.card(mi).grab_focus()
	var preview := bench.preview_text()
	_check("???" in preview and not "Estrattore" in preview, "combinazione mai vista: ??? (%s)" % preview.replace("\n", " | "))
	var unknown := bench.combo_known
	bench.combo_known = func(_id: StringName) -> bool: return true
	bench.card(di).grab_focus()
	bench.card(mi).grab_focus()
	preview = bench.preview_text()
	_check("Combinazioni: Estrattore (nuova)" in preview and not "???" in preview, "conosciuta: Estrattore (nuova)")
	bench.combo_known = unknown
	var fits := bench._panel.get_combined_minimum_size()
	_check(fits.x <= 1280.0 - 32.0 and fits.y <= 800.0 - 32.0, "il pannello sta in 1280x800 (%.0f x %.0f)" % [fits.x, fits.y])
	bench.close()
	await _frames(1)


## Macchina guasta: carta disattivata con GUASTA e fuse falso; senza rottami la conferma non
## cambia nulla e lo dice.
func _test_bench_broken_and_short() -> void:
	print("bench broken and short")
	var bench := _run.fusion_bench
	var magnet := _caravan.machines[_caravan.machines.size() - 1]
	var drill: Machine = _caravan.machines.filter(func(m: Machine) -> bool: return m.module_ids() == [&"drill"])[0]
	_break(magnet)
	_check(magnet.is_broken(), "Calamita guasta")
	bench.open(_caravan)
	var count := _caravan.machines.size()
	var mi := _caravan.machines.find(magnet)
	_check(bench.card(mi).disabled and "GUASTA" in bench.card_text(mi), "carta della guasta disattivata, GUASTA")
	_check(not bench.fuse(0, mi) and _caravan.machines.size() == count and _caravan.working_carried() == 1, "fuse con la guasta: falso, nulla cambia")
	_caravan.carried = 0
	bench.select(0)
	_check(bench.card(mi).disabled, "anche al secondo passo la guasta e disattivata")
	bench.select(_caravan.machines.find(drill))
	_check(_caravan.machines.size() == count and _caravan.working_carried() == 0 and drill.module_ids() == [&"drill"]
		and bench.step == FusionBench.Step.PICK_SECOND and bench.message_text() == "Rottami insufficienti nei Cassoni"
		and _message_ink(bench) == FusionBench.INK_WARNING,
		"0 rottami: niente cambia, avviso in rosso (%s)" % bench.message_text())
	bench.close()
	_caravan.carried = 3
	await _frames(1)


## Guasta a 1 m sulla pedana, X tenuto: vince la riparazione, il banco non si apre; finita la
## riparazione con X ancora tenuto il banco resta chiuso (serve una pressione nuova).
func _test_bench_repair_wins() -> void:
	print("bench repair wins")
	var bench := _run.fusion_bench
	var strip := _run.hud.caravan_strip()
	var magnet := _caravan.machines[_caravan.machines.size() - 1]
	_place_machine(magnet, _player.global_position + Vector3(1.0, 0.0, 0.0))
	await _frames(2)
	_check(_run.fusion_pad.contains(magnet.global_position) and _caravan.repair_target() == magnet and not _run.fusion_pad.bench_available(),
		"guasta a 1 m sulla pedana: banco non disponibile")
	_send_joypad_button(JOY_BUTTON_X, true)
	await _frames(10)
	_check(not bench.is_open and _caravan.repair_progress() > 0.0 and not strip.bench_prompt_visible() and strip.prompt_visible(),
		"ripara, non apre")
	await _frames(roundi(_caravan.tuning.repair_seconds * Engine.physics_ticks_per_second) + 5)
	_check(not magnet.is_broken() and not bench.is_open and strip.bench_prompt_visible(), "riparata con X ancora tenuto: banco chiuso, tasto Banco")
	_send_joypad_button(JOY_BUTTON_X, false)
	await _frames(2)


## Un menu alla volta: level-up e X nello stesso passo; START a banco aperto; B tenendo X;
## richiesta e chiamata del boss nello stesso passo.
func _test_bench_menu_queue() -> void:
	print("bench menu queue")
	var bench := _run.fusion_bench
	var pad := _run.fusion_pad
	_send_joypad_button(JOY_BUTTON_X, true)
	await physics_frame
	_check(pad.has_bench_request(), "X sulla pedana: richiesta del banco")
	_run._pending_level_ups = 1
	await _frames(2)
	_check(_run.level_up_menu.is_open and not bench.is_open and not pad.has_bench_request(),
		"level-up e X nello stesso passo: si apre il level-up, non il banco")
	_send_joypad_button(JOY_BUTTON_X, false)
	for i in 3:
		if not _run.level_up_menu.is_open:
			break
		await _wait_grace()
		_run.level_up_menu.press(0)
		await _frames(2)
	await _frames(2)
	_check(not _run.level_up_menu.is_open and not bench.is_open and not paused, "scelta la carta: banco chiuso")

	var pause_menu := root.get_node(^"PauseMenu")
	_send_joypad_button(JOY_BUTTON_X, true)
	await _frames(2)
	_check(bench.is_open and paused, "X di nuovo: banco aperto")
	await _joy(JOY_BUTTON_START)
	await _frames(1)
	_check(not pause_menu.is_open() and bench.is_open and paused, "START a banco aperto: niente pausa, banco ancora aperto")
	await _wait_grace()
	await _joy(JOY_BUTTON_B)
	_check(not bench.is_open and not paused, "B chiude il banco tenendo X")
	await _frames(10)
	_check(not bench.is_open and not pad.has_bench_request(), "dopo 10 passi con X tenuto il banco resta chiuso")
	_send_joypad_button(JOY_BUTTON_X, false)
	await _frames(2)

	_send_joypad_button(JOY_BUTTON_X, true)
	await physics_frame
	_check(pad.has_bench_request(), "richiesta del banco")
	_run.call_boss()
	await _frames(2)
	_check(not pad.is_open() and not pad.has_bench_request() and not bench.is_open and not paused,
		"richiesta e call_boss() nello stesso passo: pedana chiusa, nessun banco")
	_send_joypad_button(JOY_BUTTON_X, false)
	await _frames(2)


## Trivella + Calamita fuse dal banco: il profilo (autoload, senza file sotto i test) scopre
## l'Estrattore; riaperto il banco, un'altra Trivella + Calamita lo mostra per nome.
func _test_discovery_from_fusion() -> void:
	print("discovery from fusion")
	var bench := _run.fusion_bench
	var profile := root.get_node(^"PlayerProfile") as PlayerProfileService
	_check(profile != null and not profile.has_combo(&"extractor") and not bench.combo_known.call(&"extractor"),
		"prima della fusione l'Estrattore non e conosciuto")
	if profile == null:
		return
	var drill: Machine = _caravan.machines.filter(func(m: Machine) -> bool: return m.module_ids() == [&"drill"])[0]
	var magnet: Machine = _caravan.machines.filter(func(m: Machine) -> bool: return m.module_ids() == [&"magnet"])[0]
	bench.open(_caravan)
	_check(bench.fuse(_caravan.machines.find(drill), _caravan.machines.find(magnet)) and drill.module_ids() == [&"drill", &"magnet"],
		"Trivella + Calamita fuse dal banco")
	_check(profile.has_combo(&"extractor") and profile.machine_combos == PackedStringArray(["extractor"]) and bench.combo_known.call(&"extractor"),
		"il profilo ha scoperto l'Estrattore, il banco lo sa")
	bench.close()
	await _frames(1)
	var drill_2 := _caravan.add_machine(&"drill")
	var magnet_2 := _caravan.add_machine(&"magnet")
	_check(drill_2 != null and magnet_2 != null, "un'altra Trivella e un'altra Calamita")
	if drill_2 != null and magnet_2 != null:
		bench.open(_caravan)
		bench.select(_caravan.machines.find(drill_2))
		bench.card(_caravan.machines.find(magnet_2)).grab_focus()
		var preview := bench.preview_text()
		_check("Combinazioni: Estrattore (nuova)" in preview and not "???" in preview,
			"riaperto il banco l'anteprima dice Estrattore (%s)" % preview.replace("\n", " | "))
		bench.close()
		await _frames(1)
	profile.reset()


# --- Profilo versione 3 (task 7) --------------------------------------------------------------

## Conta gli errori del motore (push_error, errori di parsing): un file non valido non ne stampa.
class ErrorCounter extends Logger:
	var errors := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors += 1


func _test_profile() -> void:
	_test_profile_v2_loads()
	_test_profile_v3_round_trip()
	_test_profile_future_machines()
	_test_profile_junk_machines()
	_remove_profile(PROFILE_PATH)


func _new_profile() -> PlayerProfileService:
	var profile: PlayerProfileService = ProfileScript.new()
	profile.profile_path = ""
	return profile


func _remove_profile(path: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


## Un profilo v2 scritto a mano si carica intatto, senza combinazioni; risalvato e v3 con [machines].
func _test_profile_v2_loads() -> void:
	print("profile v2 loads")
	_remove_profile(PROFILE_PATH)
	var config := ConfigFile.new()
	config.set_value("profile", "version", 2)
	config.set_value("profile", "scrap", 9)
	config.set_value("profile", "last_class", "sapper")
	config.set_value("recipes", "mortar", true)
	config.set_value("upgrades", "tool_reach", 1)
	config.set_value("mystery", "answer", 42)
	config.save(PROFILE_PATH)
	var p := _new_profile()
	_check(p.load_profile(PROFILE_PATH) == OK and p.loaded_version == 2, "il file v2 si carica")
	_check(p.scrap == 9 and p.has_recipe(&"mortar") and p.level_of(&"tool_reach") == 1 and p.last_class == &"sapper", "v2 intatto")
	_check(p.machine_combos.is_empty() and p.save_profile() == OK, "nessuna combinazione, si salva")
	var reread := ConfigFile.new()
	reread.load(PROFILE_PATH)
	_check(reread.get_value("profile", "version", 0) == 3 and reread.get_value("mystery", "answer", 0) == 42 and reread.has_section("machines"),
		"salvato v3, sezione sconosciuta intatta")
	_check(reread.get_value("machines", "combinations", PackedStringArray(["x"])) == PackedStringArray() and reread.get_section_keys("machines").size() == 1
		and reread.get_value("profile", "scrap", 0) == 9 and reread.get_value("recipes", "mortar", false) == true
		and reread.get_value("upgrades", "tool_reach", 0) == 1 and reread.get_value("profile", "last_class", "") == "sapper",
		"risalvato: combinazioni vuote, il resto del v2 com'era")
	p.free()


func _test_profile_v3_round_trip() -> void:
	print("profile v3 round trip")
	_remove_profile(PROFILE_PATH)
	var p := _new_profile()
	p.profile_path = PROFILE_PATH
	var changes := [0]
	p.changed.connect(func() -> void: changes[0] += 1)
	_check(p.discover_combo(&"extractor") and changes[0] == 1 and p.has_combo(&"extractor"), "prima scoperta dell'Estrattore: vero, changed")
	_check(not p.discover_combo(&"extractor") and changes[0] == 1 and p.machine_combos.size() == 1, "seconda volta: falso, nessun doppione")
	_check(not p.has_combo(&"dozer"), "la Ruspa resta da scoprire")
	var loaded := _new_profile()
	_check(loaded.load_profile(PROFILE_PATH) == OK and loaded.has_combo(&"extractor") and not loaded.has_combo(&"dozer"), "ricaricato: Estrattore ricordato")
	var reread := ConfigFile.new()
	reread.load(PROFILE_PATH)
	_check(reread.get_value("profile", "version", 0) == 3 and reread.get_value("machines", "combinations", PackedStringArray()) == PackedStringArray(["extractor"]),
		"[machines] combinations == [extractor], versione 3")
	loaded.save_profile()
	reread.load(PROFILE_PATH)
	_check(reread.get_section_keys("machines") == PackedStringArray(["combinations"])
		and reread.get_value("machines", "combinations", PackedStringArray()) == PackedStringArray(["extractor"]),
		"risalvato: nessuna chiave doppia in [machines]")
	p.free()
	loaded.free()


## Un file di una versione futura: combinazioni sconosciute e chiavi nuove di [machines] restano.
func _test_profile_future_machines() -> void:
	print("profile future machines")
	_remove_profile(PROFILE_PATH)
	var config := ConfigFile.new()
	config.set_value("profile", "version", 5)
	config.set_value("machines", "combinations", ["trap", "laser"])
	config.set_value("machines", "unlocked_modules", ["drill"])
	config.save(PROFILE_PATH)
	var p := _new_profile()
	_check(p.load_profile(PROFILE_PATH) == OK and p.loaded_version == 5, "il file della versione 5 si carica")
	_check(p.has_combo(&"trap") and p.has_combo(&"laser") and not p.has_combo(&"extractor"), "Trappola e laser (sconosciuta) conosciute")
	_check(p.save_profile() == OK, "si salva")
	var reread := ConfigFile.new()
	reread.load(PROFILE_PATH)
	var combos: Variant = reread.get_value("machines", "combinations", PackedStringArray())
	_check(reread.get_value("profile", "version", 0) == 5 and reread.get_value("machines", "unlocked_modules", []) == ["drill"]
		and combos is PackedStringArray and combos == PackedStringArray(["trap", "laser"]),
		"risalvato: versione 5, unlocked_modules e laser ancora li")
	p.free()


## combinations non valido: lista vuota, il resto si legge, nessun errore stampato.
func _test_profile_junk_machines() -> void:
	print("profile junk machines")
	_remove_profile(PROFILE_PATH)
	var config := ConfigFile.new()
	config.set_value("profile", "version", 3)
	config.set_value("profile", "scrap", 4)
	config.set_value("machines", "combinations", 42)
	config.save(PROFILE_PATH)
	var p := _new_profile()
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var loaded := p.load_profile(PROFILE_PATH)
	var saved := p.save_profile()
	OS.remove_logger(counter)
	_check(loaded == OK and saved == OK and p.machine_combos.is_empty() and p.scrap == 4, "combinations = 42: vuoto, il resto si legge")
	_check(counter.errors == 0, "nessuna riga ERROR (%d)" % counter.errors)
	var reread := ConfigFile.new()
	reread.load(PROFILE_PATH)
	var combos: Variant = reread.get_value("machines", "combinations", 0)
	_check(combos is PackedStringArray and (combos as PackedStringArray).is_empty(), "risalvato con una lista vuota")
	p.free()
