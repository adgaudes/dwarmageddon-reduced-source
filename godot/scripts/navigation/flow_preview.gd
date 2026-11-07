class_name FlowPreview
extends Node3D
## Impronte dell'orda (idea 8 di docs/FEATURE_IDEAS.md): dopo ogni comando del
## tool terreno mostra per pochi secondi i percorsi che l'orda fara dall'anello
## di comparsa al giocatore, seguendo il PathField gia risolto. Galloni a terra
## che puntano lungo il flusso; chiudi un varco e le scie girano verso gli altri.
## Se il giocatore e murato il campo non ha strada e i nemici puntano dritto:
## le scie fanno lo stesso e finiscono contro il muro con una sbarra.
##
## Costo: un solo MultiMesh, al massimo `max_marks` istanze; un tracciamento per
## ogni attivazione (e uno per ogni ricalcolo del campo mentre le impronte sono
## visibili, se `follow_field`, nel frame dopo), mai un ricalcolo del campo in piu. A riposo
## `_process` e spento: nessun lavoro e nessuna allocazione.
##
## Il boss cambia le celle con `force_cell_state` (solo `cell_changed`): qui si
## ascolta `command_applied`, quindi le sue modifiche non attivano le impronte.

signal shown
signal hidden

const MARK_SHADER := preload("res://resources/materials/flow_mark.gdshader")
const KIND_FLOW := 0
const KIND_BLOCKED := 1
const VISITED_OPEN := 1
const VISITED_BLOCKED := 2
## La sbarra di una scia chiusa fuori e piu grande di un'impronta.
const BLOCKED_SCALE := 1.6
## Passi massimi di una scia (celle del campo): limita il lavoro anche su giri lunghi.
const MAX_TRAIL_STEPS := 160
## Raggi alternativi, in celle del campo, se il punto dell'anello e dentro un ostacolo.
const START_NUDGES: Array[float] = [0.0, 1.0, -1.0, 2.0, -2.0, 3.0, -3.0]
## Attesa massima del ricalcolo del campo dopo un comando, poi si traccia comunque.
const SOLVE_WAIT_SECONDS := 0.5

@export var path_field: PathField
## Rilievo continuo (D-085): le impronte partono dalle pennellate del giocatore e stanno alle quote.
@export var terrain_field: TerrainField
## Mostra le impronte a ogni comando del tool terreno del giocatore.
@export var auto_show_on_terrain_change := true
## Mentre sono visibili, le impronte seguono i ricalcoli del campo (il giocatore
## che si sposta); l'anello di partenza resta quello dell'attivazione.
@export var follow_field := true
## Secondi di visibilita per attivazione, dissolvenze comprese.
@export_range(0.5, 10.0, 0.1) var duration := 3.0
@export_range(0.0, 2.0, 0.05) var fade_in := 0.2
@export_range(0.0, 3.0, 0.05) var fade_out := 0.9
## Raggio dell'anello da cui partono le scie (l'orda nasce fra 17 e 23 m).
@export_range(4.0, 36.0, 0.5) var ring_radius := 19.0
## Scie tracciate, a pari distanza angolare sull'anello.
@export_range(1, 48) var sample_count := 20
## Metri fra due impronte lungo una scia.
@export_range(0.4, 6.0, 0.1) var spacing := 1.5
## Lato di un'impronta, in metri.
@export_range(0.2, 3.0, 0.05) var mark_size := 1.1
## Le scie si fermano a questa distanza dal giocatore.
@export_range(0.5, 6.0, 0.1) var stop_radius := 2.2
## Tetto di impronte (istanze del MultiMesh).
@export_range(16, 600) var max_marks := 320
## Colore (lineare): magenta, distinto da ciano, giallo, arancio e rosso gia in uso.
@export var color := Color(1.0, 0.06, 0.62, 0.95)
## Colore della sbarra dove una scia resta chiusa fuori.
@export var blocked_color := Color(1.0, 0.92, 0.98, 1.0)
## Quanto crescono le impronte dove confluiscono piu scie (0 = tutte uguali):
## il varco che porta piu orda si legge dalla taglia.
@export_range(0.0, 1.5, 0.05) var weight_gain := 0.6
## Altezza sopra la cima della cella, in metri.
@export var lift := 0.05

## Risultato dell'ultimo tracciamento (per test, HUD e strumenti).
var marks := PackedVector3Array()
## Scia di ogni impronta (indice del campione sull'anello).
var mark_trails := PackedInt32Array()
## KIND_FLOW o KIND_BLOCKED per ogni impronta.
var mark_kinds := PackedByteArray()
## Scie tracciate, arrivate al giocatore (anche confluendo in un'altra) e chiuse fuori.
var trail_count := 0
var reached_trails := 0
var blocked_trails := 0
var trace_count := 0
var last_trace_usec := 0

var _multimesh: MultiMesh
var _instance: MultiMeshInstance3D
var _material: ShaderMaterial
var _showing := false
var _age := 0.0
## Un comando e arrivato: si aspetta il prossimo `solved` del campo.
var _armed := false
var _armed_left := 0.0
var _ring_center := Vector3.ZERO
## Il campo si e ricalcolato mentre le impronte sono visibili: si ritraccia fra tanti `_process` (2 = il frame dopo quello del ricalcolo).
var _retrace_wait := 0
var _points := PackedVector3Array()
## Celle del campo gia percorse da una scia in questo tracciamento (VISITED_*).
var _visited := PackedByteArray()
## Per cella percorsa: la cella successiva verso il giocatore (-1 = fine) e quante scie ci passano.
var _next_cell := PackedInt32Array()
var _flow := PackedInt32Array()
## Per impronta: direzione e cella del campo (-1 fuori finestra), usate a fine tracciamento.
var _mark_headings := PackedVector3Array()
var _mark_cells := PackedInt32Array()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_material = ShaderMaterial.new()
	_material.shader = MARK_SHADER
	_material.set_shader_parameter(&"fade", 0.0)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = max_marks
	_multimesh.visible_instance_count = 0
	# Le impronte stanno ovunque attorno al giocatore: niente culling per istanza.
	_multimesh.custom_aabb = AABB(Vector3(-400.0, -5.0, -400.0), Vector3(800.0, 10.0, 800.0))
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Marks"
	_instance.multimesh = _multimesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.visible = false
	add_child(_instance)
	set_process(false)
	if terrain_field != null:
		terrain_field.player_sculpted.connect(_on_player_sculpted)
	if path_field != null:
		path_field.solved.connect(_on_field_solved)


## Mostra subito le impronte col campo com'e adesso; richiamarla fa ripartire il tempo.
func show_now() -> void:
	if path_field == null or not path_field.is_ready() or path_field.target == null:
		return
	_armed = false
	_retrace_wait = 0
	_ring_center = path_field.target.global_position
	_age = 0.0
	trace()
	_material.set_shader_parameter(&"fade", _fade_at(0.0))
	_instance.visible = true
	set_process(true)
	if not _showing:
		_showing = true
		shown.emit()


## Nasconde subito le impronte.
func hide_now() -> void:
	_armed = false
	_retrace_wait = 0
	_instance.visible = false
	_multimesh.visible_instance_count = 0
	set_process(false)
	if _showing:
		_showing = false
		hidden.emit()


func is_showing() -> bool:
	return _showing


## Impronte attualmente disegnate.
func mark_count() -> int:
	return _multimesh.visible_instance_count if _showing else 0


## True se nell'ultimo tracciamento nessuna scia arriva al giocatore.
func is_blocked() -> bool:
	return trail_count > 0 and reached_trails == 0


## Ritraccia le scie dall'anello fissato all'attivazione, senza toccare il tempo.
func trace() -> void:
	var start_usec := Time.get_ticks_usec()
	if _multimesh.instance_count != max_marks:
		_multimesh.instance_count = max_marks
	marks.clear()
	mark_trails.clear()
	mark_kinds.clear()
	trail_count = 0
	reached_trails = 0
	blocked_trails = 0
	var cells := path_field.columns * path_field.columns
	if _visited.size() != cells:
		_visited.resize(cells)
		_next_cell.resize(cells)
		_flow.resize(cells)
	_visited.fill(0)
	_flow.fill(0)
	_mark_headings.clear()
	_mark_cells.clear()
	var goal := path_field.target.global_position
	goal.y = 0.0
	var center := Vector3(_ring_center.x, 0.0, _ring_center.z)
	for i in sample_count:
		if marks.size() >= max_marks:
			break
		var angle := TAU * i / sample_count
		var out := Vector3(cos(angle), 0.0, sin(angle))
		for nudge in START_NUDGES:
			var start := center + out * (ring_radius + nudge * path_field.cell_size)
			if path_field.is_walkable(start):
				_trace_trail(i, start, goal)
				break
	_write_marks(goal)
	trace_count += 1
	last_trace_usec = Time.get_ticks_usec() - start_usec


func _process(delta: float) -> void:
	if _armed:
		_armed_left -= delta
		if _armed_left <= 0.0:
			show_now()
	if not _showing:
		if not _armed:
			set_process(false)
		return
	_age += delta
	if _age >= duration:
		hide_now()
		return
	if _retrace_wait > 0:
		_retrace_wait -= 1
		if _retrace_wait == 0:
			trace()
	_material.set_shader_parameter(&"fade", _fade_at(_age))


func _fade_at(age: float) -> float:
	var rise := 1.0 if fade_in <= 0.0 else clampf(age / fade_in, 0.0, 1.0)
	var fall := 1.0 if fade_out <= 0.0 else clampf((duration - age) / fade_out, 0.0, 1.0)
	return minf(rise, fall)


## Una pennellata del giocatore sul rilievo (non quelle di boss ed eventi: `sculpt`).
func _on_player_sculpted(_center: Vector3, _radius: float, _volume: float, _mode: int) -> void:
	if not auto_show_on_terrain_change or path_field == null:
		return
	# Il campo si ricalcola al suo prossimo passo fisico: le scie si tracciano li.
	_armed = true
	_armed_left = SOLVE_WAIT_SECONDS
	set_process(true)


func _on_field_solved() -> void:
	if _armed:
		# Non nello stesso passo fisico del ricalcolo del campo (E-05): le scie si
		# tracciano nel prossimo `_process`, fuori dal budget del passo.
		_armed_left = 0.0
	elif _showing and follow_field:
		# Non nello stesso frame del ricalcolo del campo: i due costi non si sommano.
		_retrace_wait = 2


## Segue il campo da [param start] finche arriva al giocatore, confluisce in una
## scia gia tracciata o resta chiusa fuori; poi posa le impronte lungo il percorso.
func _trace_trail(trail: int, start: Vector3, goal: Vector3) -> void:
	_points.clear()
	_points.append(start)
	var pos := start
	var blocked := false
	var merged := false
	var merged_blocked := false
	var arrived := false
	var previous := -1
	var step := path_field.cell_size
	var stop_sq := stop_radius * stop_radius
	for i in MAX_TRAIL_STEPS:
		var to_goal := goal - pos
		to_goal.y = 0.0
		if to_goal.length_squared() <= stop_sq:
			arrived = true
			break
		var waypoint: Variant = path_field.next_waypoint(pos)
		var next: Vector3
		if waypoint != null:
			next = waypoint
		else:
			# Nessuna strada nel campo: come i nemici, dritto verso il giocatore.
			next = pos + to_goal.normalized() * step
			if not path_field.is_walkable(next):
				blocked = true
				break
		pos = next
		_points.append(pos)
		var cell := path_field.cell_of(pos)
		if not path_field.is_inside(cell):
			previous = -1
			continue
		var index := cell.y * path_field.columns + cell.x
		if index == previous:
			# Passo corto in linea retta: stessa cella di prima, non e una confluenza.
			continue
		if previous >= 0:
			_next_cell[previous] = index
		if _visited[index] != 0:
			# Confluenza: da qui in poi le impronte ci sono gia e l'esito e lo stesso;
			# la scia a valle porta una scia in piu.
			merged = true
			merged_blocked = _visited[index] == VISITED_BLOCKED
			var downstream := index
			for hop in MAX_TRAIL_STEPS:
				if downstream < 0:
					break
				_flow[downstream] += 1
				downstream = _next_cell[downstream]
			break
		_visited[index] = VISITED_OPEN
		_next_cell[index] = -1
		_flow[index] = 1
		previous = index
	trail_count += 1
	# Finiti i passi senza arrivare (in linea retta contro un muro): chiusa fuori.
	if not arrived and not merged:
		blocked = true
	if blocked or merged_blocked:
		blocked_trails += 1
		# Chi confluira in questa scia restera chiuso fuori come lei.
		for point in _points:
			var cell := path_field.cell_of(point)
			if path_field.is_inside(cell):
				_visited[cell.y * path_field.columns + cell.x] = VISITED_BLOCKED
	else:
		reached_trails += 1
	_emit_marks(trail, goal, blocked)


func _emit_marks(trail: int, goal: Vector3, blocked: bool) -> void:
	var count := _points.size()
	var next_at := spacing * 0.5
	var walked := 0.0
	for i in count - 1:
		var a := _points[i]
		var b := _points[i + 1]
		var length := a.distance_to(b)
		if length <= 0.0001:
			continue
		# Direzione lisciata su qualche cella: i passi a 45 gradi non fanno zigzag.
		var heading := _points[mini(i + 2, count - 1)] - _points[maxi(i - 1, 0)]
		while next_at <= walked + length:
			if marks.size() >= max_marks - 1:
				break
			_add_mark(trail, a.lerp(b, (next_at - walked) / length), heading, KIND_FLOW)
			next_at += spacing
		walked += length
	if blocked and marks.size() < max_marks:
		var last := _points[count - 1]
		var ahead := goal - last
		_add_mark(trail, last, ahead, KIND_BLOCKED)


func _add_mark(trail: int, pos: Vector3, heading: Vector3, kind: int) -> void:
	var cell := path_field.cell_of(pos)
	marks.append(Vector3(pos.x, _ground_y(pos) + lift, pos.z))
	mark_trails.append(trail)
	mark_kinds.append(kind)
	_mark_headings.append(heading)
	_mark_cells.append(cell.y * path_field.columns + cell.x if path_field.is_inside(cell) else -1)


## Scrive le istanze a tracciamento finito, quando si sa quante scie passano da ogni cella.
func _write_marks(goal: Vector3) -> void:
	var full := maxf(sample_count * 0.35, 1.0)
	for index in marks.size():
		var world := marks[index]
		var kind := mark_kinds[index]
		var heading := _mark_headings[index]
		heading.y = 0.0
		var forward := heading.normalized() if heading.length_squared() > 0.000001 else Vector3.FORWARD
		var back := -forward
		var right := Vector3.UP.cross(back)
		var cell := _mark_cells[index]
		var size := mark_size * BLOCKED_SCALE
		if kind == KIND_FLOW:
			var extra := clampf(((_flow[cell] if cell >= 0 else 1) - 1) / full, 0.0, 1.0)
			size = mark_size * (1.0 + weight_gain * extra)
		_multimesh.set_instance_transform(index, Transform3D(Basis(right * size, Vector3.UP, back * size), world))
		_multimesh.set_instance_color(index, blocked_color if kind == KIND_BLOCKED else color)
		# Metri che mancano al giocatore: fase dell'onda che scorre lungo la scia.
		var cost := path_field.costs[cell] if cell >= 0 else PathField.UNREACHABLE
		var remaining := cost * path_field.cell_size if cost != PathField.UNREACHABLE else world.distance_to(goal)
		_multimesh.set_instance_custom_data(index, Color(float(kind), remaining, 0.0, 0.0))
	_multimesh.visible_instance_count = marks.size()


## Quota del suolo sotto il punto: rilievo continuo o cima della cella della griglia.
func _ground_y(pos: Vector3) -> float:
	return terrain_field.height_at(pos) if terrain_field != null else 0.0
