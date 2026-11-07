extends SceneTree
## Test delle impronte dell'orda (FlowPreview) sul rilievo continuo. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/flow_preview_tests.gd
##
## Scena sintetica: campo da 64 m, cortile di argini (raggio 9,6 m) con un varco per
## lato come quello di partenza, bersaglio fermo al centro, campo di percorso intero.
## In headless i colori del MultiMesh non si leggono: si verificano posizioni e conteggi.

const HALF_EXTENT := 32.0
const RING_M := 9.6
const GATE_CLEAR := 2.4
const NORTH := Vector3(0.0, 0.0, -RING_M)
const SOUTH := Vector3(0.0, 0.0, RING_M)
const EAST := Vector3(RING_M, 0.0, 0.0)
const WEST := Vector3(-RING_M, 0.0, 0.0)

var _failures := 0
var _world: Node3D
var _target: Node3D
var _relief: TerrainField
var _field: PathField
var _flow: FlowPreview


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_world = Node3D.new()
	root.add_child(_world)
	_target = Node3D.new()
	_target.name = "Target"
	_world.add_child(_target)
	_relief = TerrainField.new()
	_relief.name = "TerrainField"
	_relief.size_m = Vector2(HALF_EXTENT * 2.0, HALF_EXTENT * 2.0)
	_relief.tuning = TerrainTuning.new()
	_relief.render = false
	_world.add_child(_relief)
	await _frames(2)
	_build_courtyard()
	_field = PathField.new()
	_field.name = "PathField"
	_field.target = _target
	_field.terrain_field = _relief
	_field.half_extent = HALF_EXTENT
	_field.window_cells = 0
	_world.add_child(_field)
	_flow = FlowPreview.new()
	_flow.name = "FlowPreview"
	_flow.path_field = _field
	_flow.terrain_field = _relief
	_world.add_child(_flow)
	await _frames(20)
	await _test_idle_before_command()
	await _test_trails_after_player_stroke()
	_test_marks_follow_field()
	await _test_closing_gate_moves_trails()
	await _test_forced_changes_do_not_trigger()
	await _test_sealed_courtyard()
	await _test_duration_and_retrigger()
	await _test_manual_only()
	_test_mark_cap()
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


func _seconds(seconds: float) -> void:
	await _frames(int(round(seconds * 60.0)))


## Anello di argini con cresta continua di 1,4 m (pennelli di 2 m ogni 1,6 m, come il
## quartiere) e un varco al centro di ogni lato.
func _build_courtyard() -> void:
	# Un multiplo di 4: un punto cade esattamente su ogni varco (e viene tolto), come nel quartiere.
	var count := 40
	var amount := 1.4 / RuinsDistrict.line_overlap(TAU * RING_M / count, 2.0)
	for k in count:
		var angle := TAU * k / count
		var p := Vector2(cos(angle), sin(angle)) * RING_M
		var in_gate := false
		for gate in [NORTH, SOUTH, EAST, WEST]:
			if p.distance_to(Vector2(gate.x, gate.z)) < GATE_CLEAR:
				in_gate = true
		if in_gate:
			continue
		_relief.sculpt(Vector3(p.x, 0.0, p.y), 2.0, amount)


## Tre pennellate lungo l'anello: il tappo di un varco, senza selle fra tappo e argine
## (come `_seal_gate` in arena_run_tests).
func _gate_points(gate: Vector3) -> Array[Vector3]:
	var tangent := Vector3(-gate.z, 0.0, gate.x).normalized()
	return [gate - tangent * 1.6, gate, gate + tangent * 1.6]


## Il giocatore riapre un varco (DIG): le tre pennellate del tappo in negativo.
func _player_dig(gate: Vector3) -> void:
	for p in _gate_points(gate):
		_relief.player_sculpt(p, 2.0, -1.4, TerrainField.ToolMode.DIG)


## Il giocatore chiude un varco (RAISE).
func _player_raise(gate: Vector3) -> void:
	for p in _gate_points(gate):
		_relief.player_sculpt(p, 2.0, 1.4, TerrainField.ToolMode.RAISE)


## Boss o evento chiude un varco (`sculpt`, non del giocatore).
func _seal(gate: Vector3) -> void:
	for p in _gate_points(gate):
		_relief.sculpt(p, 2.0, 1.4)


## Impronte entro 1,5 m dal punto (piano XZ).
func _marks_near(world: Vector3) -> int:
	var count := 0
	for mark in _flow.marks:
		if Vector2(mark.x - world.x, mark.z - world.z).length() <= 1.5:
			count += 1
	return count


func _marks_inside_courtyard() -> int:
	var count := 0
	for mark in _flow.marks:
		if Vector2(mark.x, mark.z).length() < RING_M - 2.0:
			count += 1
	return count


## Impronte sopra un argine (delta oltre 0,8 m).
func _marks_on_ramparts() -> int:
	var count := 0
	for mark in _flow.marks:
		if _relief.delta_at(mark) > 0.8:
			count += 1
	return count


func _multimesh() -> MultiMesh:
	return (_flow.get_node(^"Marks") as MultiMeshInstance3D).multimesh


func _test_idle_before_command() -> void:
	print("idle")
	_check(not _flow.is_showing(), "all'avvio nessuna impronta")
	_check(_flow.mark_count() == 0 and _flow.marks.is_empty(), "nessuna istanza visibile")
	_check(_flow.trace_count == 0, "nessun tracciamento senza comando (%d)" % _flow.trace_count)
	_check(not _flow.is_processing(), "a riposo _process e spento")
	_check(not (_flow.get_node(^"Marks") as MultiMeshInstance3D).visible, "il MultiMesh e nascosto")
	# Il bersaglio che si muove fa ricalcolare il campo, ma senza comando niente impronte.
	_target.global_position = Vector3(1.5, 0.0, 0.0)
	await _frames(20)
	_check(not _flow.is_showing() and _flow.trace_count == 0, "il campo ricalcolato da solo non mostra nulla")
	_target.global_position = Vector3.ZERO
	await _frames(20)


func _test_trails_after_player_stroke() -> void:
	print("trails after a player stroke")
	_relief.player_sculpt(Vector3(2.4, 0.0, 2.4), 2.4, -0.8, TerrainField.ToolMode.DIG)
	_check(not _flow.is_showing(), "nello stesso istante il campo e ancora vecchio: si aspetta")
	await _frames(20)
	_check(_flow.is_showing(), "dopo il ricalcolo del campo le impronte ci sono")
	_check(_flow.trace_count == 1, "un solo tracciamento (%d)" % _flow.trace_count)
	_check(_flow.mark_count() > 20, "impronte posate (%d)" % _flow.mark_count())
	_check(_flow.mark_count() == _flow.marks.size() and _multimesh().visible_instance_count == _flow.marks.size(),
		"istanze visibili = impronte")
	_check(_flow.mark_count() <= _flow.max_marks, "sotto il tetto (%d <= %d)" % [_flow.mark_count(), _flow.max_marks])
	_check(_flow.trail_count == _flow.sample_count, "una scia per campione (%d)" % _flow.trail_count)
	_check(_flow.reached_trails == _flow.trail_count and _flow.blocked_trails == 0 and not _flow.is_blocked(),
		"cortile aperto: tutte le scie arrivano")
	_check((_flow.get_node(^"Marks") as MultiMeshInstance3D).visible, "il MultiMesh e visibile")
	_check(_multimesh().use_colors and _multimesh().use_custom_data, "colore e dati per istanza attivi")
	print("  info trace_ms=%.3f marks=%d" % [_flow.last_trace_usec / 1000.0, _flow.mark_count()])


func _test_marks_follow_field() -> void:
	print("marks follow the field")
	var monotonic := true
	var walkable := true
	var at_height := true
	var last_trail := -1
	var last_cost := INF
	var far_start := 0
	for i in _flow.marks.size():
		var mark := _flow.marks[i]
		var cost := _field.cost_at(mark)
		# Le impronte stanno fra una cella e l'altra, anche sul piede di un argine: conta
		# che il punto sia raggiungibile e non in cima a un argine, non la pendenza locale.
		if cost == PathField.UNREACHABLE or _relief.delta_at(mark) > 0.8:
			walkable = false
		if absf(mark.y - _relief.height_at(mark)) > 0.6:
			at_height = false
		if _flow.mark_trails[i] != last_trail:
			last_trail = _flow.mark_trails[i]
			if Vector2(mark.x, mark.z).length() > _flow.ring_radius - 4.0:
				far_start += 1
		elif cost > last_cost + 0.001:
			monotonic = false
		last_cost = cost
	_check(walkable, "ogni impronta sta su un punto raggiungibile, non in cima a un argine")
	_check(at_height, "le impronte stanno alla quota del rilievo")
	_check(monotonic, "lungo ogni scia il costo verso il giocatore non cresce mai")
	_check(far_start == _flow.trail_count, "ogni scia parte dall'anello (%d)" % far_start)
	_check(_marks_on_ramparts() == 0, "nessuna impronta sopra un argine")
	for gate: Array in [["nord", NORTH], ["sud", SOUTH], ["est", EAST], ["ovest", WEST]]:
		var count := _marks_near(gate[1])
		_check(count > 0, "le scie passano dal varco %s (%d impronte)" % [gate[0], count])
	_check(_marks_inside_courtyard() > 8, "le scie entrano nel cortile (%d)" % _marks_inside_courtyard())
	var near := INF
	for mark in _flow.marks:
		near = minf(near, Vector2(mark.x, mark.z).length())
	_check(near >= _flow.stop_radius - 0.9 and near < _flow.stop_radius + 2.0,
		"le scie si fermano attorno al giocatore (%.2f m)" % near)


func _test_closing_gate_moves_trails() -> void:
	print("closing a gate moves the trails")
	await _seconds(1.0)
	_player_raise(NORTH)
	await _frames(20)
	_check(_flow.is_showing() and _flow.trace_count == 2, "le impronte sono state ritracciate (%d)" % _flow.trace_count)
	_check(_marks_near(NORTH) == 0, "nessuna impronta dal varco nord chiuso")
	_check(_marks_near(SOUTH) + _marks_near(EAST) + _marks_near(WEST) > 0, "le scie passano dagli altri varchi")
	_check(_flow.reached_trails == _flow.trail_count, "tutte le scie arrivano ancora")


## Le pennellate di boss ed eventi (`sculpt`) non mostrano le impronte: solo quelle del giocatore.
func _test_forced_changes_do_not_trigger() -> void:
	print("forced changes")
	await _seconds(_flow.duration + 0.3)
	var traces := _flow.trace_count
	_relief.sculpt(Vector3(RING_M, 0.0, 4.0), 1.5, -0.5)
	await _frames(30)
	_check(not _flow.is_showing() and _flow.trace_count == traces, "una pennellata di boss o evento non mostra le impronte")
	_relief.sculpt(Vector3(RING_M, 0.0, 4.0), 1.5, 0.5)
	await _frames(30)
	_check(not _flow.is_showing() and _flow.trace_count == traces, "nemmeno una barricata")


func _test_sealed_courtyard() -> void:
	print("sealed courtyard")
	_seal(EAST)
	_seal(WEST)
	_player_raise(SOUTH)
	await _frames(20)
	_check(_flow.is_showing(), "le impronte compaiono anche senza strada")
	_check(_flow.is_blocked() and _flow.blocked_trails == _flow.trail_count, "cortile sigillato: tutte le scie sono bloccate (%d)" % _flow.blocked_trails)
	_check(_marks_inside_courtyard() == 0, "nessuna impronta dentro il cortile sigillato")
	var bars := 0
	for i in _flow.marks.size():
		if _flow.mark_kinds[i] == FlowPreview.KIND_BLOCKED:
			bars += 1
	_check(bars > 0 and bars <= _flow.trail_count, "sbarre di strada chiusa (%d)" % bars)
	# Riapre il varco nord: la strada torna.
	_player_dig(NORTH)
	await _frames(20)
	_check(not _flow.is_blocked() and _marks_near(NORTH) > 0, "riaperto il varco nord le scie passano di li (%d)" % _marks_near(NORTH))


func _test_duration_and_retrigger() -> void:
	print("duration")
	await _seconds(_flow.duration + 0.3)
	_check(not _flow.is_showing(), "dopo %.1f s le impronte spariscono" % _flow.duration)
	_check(_flow.mark_count() == 0 and _multimesh().visible_instance_count == 0, "nessuna istanza visibile")
	_check(not (_flow.get_node(^"Marks") as MultiMeshInstance3D).visible, "il MultiMesh e nascosto")
	_check(not _flow.is_processing(), "_process torna spento")
	_flow.show_now()
	_check(_flow.is_showing() and _flow.mark_count() > 0, "show_now() le mostra subito")
	await _seconds(2.0)
	_flow.show_now()
	await _seconds(2.0)
	_check(_flow.is_showing(), "show_now() ripetuto fa ripartire la durata")
	await _seconds(1.3)
	_check(not _flow.is_showing(), "poi spariscono")
	# Mentre sono visibili seguono i ricalcoli del campo senza allungare la durata.
	_flow.show_now()
	var traces := _flow.trace_count
	_target.global_position = Vector3(2.5, 0.0, 0.0)
	await _seconds(1.0)
	_check(_flow.trace_count == traces + 1, "un ritracciamento per ricalcolo del campo (%d)" % (_flow.trace_count - traces))
	await _seconds(2.3)
	_check(not _flow.is_showing(), "il ritracciamento non allunga la durata")
	_target.global_position = Vector3.ZERO
	await _frames(20)
	_flow.show_now()
	_flow.hide_now()
	_check(not _flow.is_showing() and _flow.mark_count() == 0, "hide_now() le nasconde subito")


func _test_manual_only() -> void:
	print("manual only")
	_flow.auto_show_on_terrain_change = false
	_player_dig(SOUTH)
	await _frames(30)
	_check(not _flow.is_showing(), "con auto_show spento la pennellata non mostra nulla")
	_flow.show_now()
	_check(_flow.is_showing() and not _flow.is_blocked(), "show_now() funziona comunque e trova la strada")
	_check(_marks_near(SOUTH) > 0, "le scie passano dal varco sud riaperto (%d impronte)" % _marks_near(SOUTH))
	_check(_marks_near(EAST) == 0, "nessuna dal varco est chiuso")
	_flow.hide_now()
	_flow.auto_show_on_terrain_change = true


func _test_mark_cap() -> void:
	print("mark cap")
	var samples := _flow.sample_count
	var spacing := _flow.spacing
	_flow.sample_count = 48
	_flow.spacing = 0.4
	_flow.show_now()
	_check(_flow.marks.size() <= _flow.max_marks, "48 scie fitte: sotto il tetto (%d <= %d)" % [_flow.marks.size(), _flow.max_marks])
	_check(_flow.marks.size() > _flow.max_marks / 2, "il tetto e davvero raggiunto o quasi (%d)" % _flow.marks.size())
	_check(_multimesh().instance_count == _flow.max_marks, "il MultiMesh non cresce")
	_flow.hide_now()
	_flow.sample_count = samples
	_flow.spacing = spacing
