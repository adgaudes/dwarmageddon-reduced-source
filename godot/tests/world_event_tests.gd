extends SceneTree
## Suite degli eventi del mondo casuali (D-097): il pianificatore (quanti, quando, di che
## tipo, distacco minimo, ripetibilita col seme), le voci della scheda Gameplay nel servizio
## delle impostazioni (default, limiti, salvataggio) e la regia che le rispetta (numero di
## eventi, evento spento, notte spenta, treno spento sulla ferrovia).
##   godot_console --headless --path godot --script res://tests/world_event_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")
const RailwayScene := preload("res://scenes/main/railway_run.tscn")

var _failures := 0
var _settings: GameSettingsService


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_settings = root.get_node(^"GameSettings")
	_test_plan_shape()
	_test_plan_small_window()
	_test_plan_edge_cases()
	_test_plan_seed_and_kinds()
	_test_settings_defaults_and_save()
	await _test_run_count()
	await _test_run_quake_off_and_no_night()
	await _test_railway_train_off()
	_settings.reset_to_defaults()
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


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _test_plan_shape() -> void:
	print("plan shape")
	var kinds: Array[StringName] = [&"quake"]
	var plan := WorldEventScheduler.plan(kinds, 4, 90.0, 690.0, 60.0, _rng(7))
	_check(plan.size() == 4, "quattro eventi chiesti, quattro programmati")
	var inside := true
	var spaced := true
	for i in plan.size():
		inside = inside and plan[i].at >= 90.0 and plan[i].at <= 690.0
		if i > 0:
			spaced = spaced and plan[i].at - plan[i - 1].at >= 60.0 - 0.001
	_check(inside, "tutti nella finestra 90-690 s")
	_check(spaced, "in ordine e distanziati di almeno 60 s")


func _test_plan_small_window() -> void:
	print("plan small window")
	var kinds: Array[StringName] = [&"quake"]
	var plan := WorldEventScheduler.plan(kinds, 5, 100.0, 200.0, 60.0, _rng(3))
	var ok := plan.size() == 5
	for i in plan.size():
		ok = ok and plan[i].at >= 100.0 and plan[i].at <= 200.0
		if i > 0:
			ok = ok and plan[i].at - plan[i - 1].at >= 20.0 - 0.001
	_check(ok, "finestra stretta: cinque eventi dentro, distacco ridotto a 20 s")


func _test_plan_edge_cases() -> void:
	print("plan edge cases")
	var none: Array[StringName] = []
	var kinds: Array[StringName] = [&"quake"]
	_check(WorldEventScheduler.plan(none, 3, 90.0, 690.0, 60.0, _rng(1)).is_empty(), "nessun evento acceso: nessun evento")
	_check(WorldEventScheduler.plan(kinds, 0, 90.0, 690.0, 60.0, _rng(1)).is_empty(), "zero eventi chiesti: nessuno")
	_check(WorldEventScheduler.plan(kinds, 2, 300.0, 200.0, 60.0, _rng(1)).is_empty(), "finestra vuota (boss anticipato): nessuno")
	var one := WorldEventScheduler.plan(kinds, 1, 90.0, 690.0, 60.0, _rng(1))
	_check(one.size() == 1 and WorldEventScheduler.times_of(one, &"quake").size() == 1 and WorldEventScheduler.times_of(one, &"train").is_empty(),
		"times_of separa gli istanti per tipo")


func _test_plan_seed_and_kinds() -> void:
	print("plan seed and kinds")
	var kinds: Array[StringName] = [&"quake", &"train"]
	var a := WorldEventScheduler.plan(kinds, 3, 90.0, 690.0, 60.0, _rng(42))
	var b := WorldEventScheduler.plan(kinds, 3, 90.0, 690.0, 60.0, _rng(42))
	_check(a == b, "stesso seme, stesso piano")
	var firsts := {}
	var seen := {}
	for s in 40:
		var plan := WorldEventScheduler.plan(kinds, 1, 90.0, 690.0, 60.0, _rng(1000 + s))
		firsts[snappedf(plan[0].at, 1.0)] = true
		seen[plan[0].kind] = true
	_check(firsts.size() > 30, "semi diversi, istanti diversi (%d su 40)" % firsts.size())
	_check(seen.has(&"quake") and seen.has(&"train"), "con due eventi accesi escono entrambi i tipi")


func _test_settings_defaults_and_save() -> void:
	print("settings")
	_settings.reset_to_defaults()
	_check(_settings.world_event_count == 1 and _settings.quake_enabled and _settings.train_enabled and _settings.night_enabled,
		"di serie: un evento per livello, terremoto, treno e notte accesi")
	_settings.set_world_event_count(9)
	_check(_settings.world_event_count == GameSettingsService.WORLD_EVENT_COUNTS[-1], "il numero si ferma al massimo (%d)" % _settings.world_event_count)
	_settings.set_world_event_count(3)
	_settings.set_quake_enabled(false)
	_settings.set_night_enabled(false)
	_check(not _settings.world_event_enabled(&"quake") and _settings.world_event_enabled(&"train"), "world_event_enabled segue gli interruttori")
	var path := "user://world_event_settings_test_%d.cfg" % OS.get_process_id()
	var keep := _settings.settings_path
	_check(_settings.save_settings(path) == OK, "salvataggio riuscito")
	_settings.reset_to_defaults()
	_settings.load_settings(path)
	_check(_settings.world_event_count == 3 and not _settings.quake_enabled and _settings.train_enabled and not _settings.night_enabled,
		"ricaricate: 3 eventi, terremoto e notte spenti")
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("gameplay", "world_event_count", 42)
	config.set_value("gameplay", "quake_enabled", "no")
	config.save(path)
	_settings.load_settings(path)
	_check(_settings.world_event_count == 1 and _settings.quake_enabled, "valori non validi nel file: tornano quelli di serie")
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_settings.settings_path = keep
	_settings.reset_to_defaults()


func _start(scene: PackedScene) -> Node3D:
	var node: Node3D = scene.instantiate()
	root.add_child(node)
	(node.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	return node


func _stop(node: Node3D) -> void:
	root.remove_child(node)
	node.queue_free()
	await _frames(2)


func _test_run_count() -> void:
	print("run count")
	_settings.set_world_event_count(3)
	var scene := _start(RunScene)
	await _frames(3)
	var run: ArenaRun = scene.get_node(^"Run")
	var quake := run.quake_event
	var times := quake.queued_times()
	_check(run.world_event_plan.size() == 3 and times.size() == 2 and quake.next_at < times[0],
		"tre eventi chiesti: tre terremoti in programma (%.0f, %s)" % [quake.next_at, times])
	_check(quake.next_at >= run.tuning.world_events_start_seconds and times[-1] <= run.boss_call_at - run.tuning.world_events_boss_margin,
		"tutti prima della chiamata del boss")
	# Finito il primo si passa al secondo, non a un intervallo fisso.
	var second := times[0]
	quake._finish()
	_check(is_equal_approx(quake.next_at, second), "finito un terremoto, il prossimo e quello programmato (%.0f)" % quake.next_at)
	await _stop(scene)
	_settings.reset_to_defaults()


func _test_run_quake_off_and_no_night() -> void:
	print("run quake off")
	_settings.set_quake_enabled(false)
	_settings.set_night_enabled(false)
	var scene := _start(RunScene)
	await _frames(3)
	var run: ArenaRun = scene.get_node(^"Run")
	_check(run.world_event_plan.is_empty() and run.quake_event.next_at == INF, "terremoto spento: nessun evento nel quartiere")
	_check(run.day_night == null or run.day_night.night_start_seconds == 0.0, "notte spenta: il tramonto non arriva")
	await _stop(scene)
	_settings.reset_to_defaults()


func _test_railway_train_off() -> void:
	print("railway train off")
	_settings.set_train_enabled(false)
	var scene := _start(RailwayScene)
	await _frames(3)
	var run: ArenaRun = scene.get_node(^"Run")
	_check(run.world_event_plan.is_empty() and run.train_event.next_at == INF, "treno spento: nessun evento sulla ferrovia")
	await _stop(scene)
	_settings.reset_to_defaults()
	scene = _start(RailwayScene)
	await _frames(3)
	run = scene.get_node(^"Run")
	_check(run.world_event_plan.size() == 1 and run.train_event.next_at < INF, "treno acceso: un passaggio in programma")
	await _stop(scene)
