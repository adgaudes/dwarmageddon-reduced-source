class_name FusionPad
extends Node3D
## Piazzola di fusione (D-093, piano B, scelta 1): a `pad_boss_fraction` della chiamata del boss
## una pedana di `pad_cells` x `pad_cells` celle da `pad_cell_m` (6 m di lato) atterra a
## `pad_distance_min`-`pad_distance_max` m dal giocatore, su un punto dove il disco circoscritto e
## piano entro `pad_flat_tolerance`, il centro sta alla base (ne cumulo ne buca), percorribile e
## raggiungibile, fuori dai binari e senza lampioni sotto. Si annuncia `pad_warning_seconds` prima
## con la freccia (priorita piu bassa dell'annuncio unico), da aperta protegge il suo disco e alla
## chiamata del boss si richiude. Solo modello: nessuna collisione, nessuna sorgente di LightField.
## Come la piazzola di estrazione non ha un passo fisico proprio: `ArenaRun` la fa avanzare.
## Banco (scelta 9): Interagisci sulla pedana, senza guaste da riparare vicino, chiede il banco;
## lo apre `ArenaRun` a fine passo se nello stesso passo non si apre un altro menu.

signal warned(center: Vector3)
signal landed(center: Vector3)
signal closed

enum Phase { WAITING, SEARCHING, WARNING, OPEN, CLOSED }

## Candidati per anello e passo angolare (24 angoli ogni 15 gradi).
const ANGLES := 24
## Discesa e risalita del modello (solo presentazione) e quota da cui scende.
const DESCENT_SECONDS := 1.5
const RISE_SECONDS := 1.0
const DROP_HEIGHT := 14.0
const NOTICE_SECONDS := 3.0
## Ripiego: dislivello misurato sulla griglia di 1 m dentro il disco.
const RELIEF_STEP := 1.0
const DECK_THICKNESS := 0.12
const MAST_HEIGHT := 4.5
const BEAM_HEIGHT := 26.0
## Colori lineari, come le altre costanti del progetto.
const DECK_COLOR := Color(0.32, 0.34, 0.37)
const EDGE_COLOR := Color(1.0, 0.8, 0.08)
const CRANE_COLOR := Color(1.0, 0.45, 0.08)
const CABLE_COLOR := Color(0.12, 0.12, 0.12)
const LAMP_COLOR := Color(1.0, 0.92, 0.72)
const BEAM_COLOR := Color(0.45, 0.8, 1.0, 0.22)
const DUST_COLOR := Color(0.72, 0.64, 0.5)

var terrain_field: TerrainField
var player: PlayerCharacter
var hud: RunHud
var caravan: Caravan
var path_field: PathField
var lamp_field: LampField
var tuning := CaravanTuning.new()
## Vector3 -> bool: il punto sta sui binari. Non valida = nessun binario.
var on_tracks: Callable
## Ultimo ripiego, senza candidati utilizzabili: il punto di partenza del livello.
var fallback_point := Vector3.ZERO
var rng := RandomNumberGenerator.new()

var phase := Phase.WAITING
## Centro della pedana (quota del suolo all'avviso e all'atterraggio).
var center := Vector3.ZERO

## Secondi di livello dell'arrivo; negativo = non programmata.
var _arrive_at := -1.0
## Protezione che c'era sotto il disco prima dell'atterraggio (rovine, cortile): torna alla
## chiusura. Vuota = la pedana non protegge nulla.
var _protection_before: Dictionary = {}
## Ricerca a passi: candidati, prossimo da valutare, miglior ripiego e lampioni del momento.
var _candidates: Array[Vector3] = []
var _next_candidate := 0
var _best_point := Vector3.ZERO
var _best_relief := INF
var _lamps: Array[Vector3] = []
var _result: Dictionary = {}
var _model: Node3D
var _light: OmniLight3D
var _descent_left := 0.0
var _rise_left := 0.0
## Interagisci premuto sulla pedana in questo passo: `ArenaRun` apre il banco a fine passo.
var _bench_requested := false


## Programma l'arrivo a [param seconds] di livello e azzera la ricerca; una pedana ancora a
## terra sparisce subito.
func schedule(seconds: float) -> void:
	_release_protection()
	if _model != null:
		_model.hide()
	_descent_left = 0.0
	_rise_left = 0.0
	_arrive_at = seconds
	phase = Phase.WAITING
	_candidates.clear()
	_result = {}


func arrive_at() -> float:
	return _arrive_at


func warning_at() -> float:
	return maxf(_arrive_at - tuning.pad_warning_seconds, 0.0)


func is_open() -> bool:
	return phase == Phase.OPEN


func half_size() -> float:
	return tuning.pad_cells * tuning.pad_cell_m * 0.5


## Raggio del disco circoscritto al quadrato: quello che deve essere piano e che si protegge.
func flat_radius() -> float:
	return half_size() * sqrt(2.0)


## Il punto sta sul quadrato della pedana (piano XZ).
func contains(point: Vector3) -> bool:
	var h := half_size()
	return absf(point.x - center.x) <= h and absf(point.z - center.z) <= h


## Il banco si puo chiedere: pedana aperta, giocatore vivo sul quadrato, nessuna guasta da
## riparare entro `repair_range` (con una guasta vicina vince la riparazione).
func bench_available() -> bool:
	if phase != Phase.OPEN or caravan == null or not is_instance_valid(player) or not player.is_alive():
		return false
	return contains(player.global_position) and caravan.repair_target() == null


## Da `ArenaRun._on_interact_pressed` (Interagisci premuto): segna la richiesta solo se il banco e disponibile.
func request_bench() -> void:
	if bench_available():
		_bench_requested = true


func has_bench_request() -> bool:
	return _bench_requested


## Consuma la richiesta: vero se c'era e il banco e ancora disponibile a fine passo.
func take_bench_request() -> bool:
	var requested := _bench_requested
	_bench_requested = false
	return requested and bench_available()


## Scarta la richiesta (un altro menu si apre nello stesso passo, la pedana si chiude).
func drop_bench_request() -> void:
	_bench_requested = false


## Luce della lampada (accesa da `ArenaRun` col fattore di notte); null finche non atterra.
func light() -> OmniLight3D:
	return _light


## Un passo, dal tempo di livello: ricerca a passi, avviso, arrivo; e l'animazione del modello.
func advance(elapsed: float, delta: float) -> void:
	_tick_model(delta)
	if _arrive_at < 0.0 or phase == Phase.OPEN or phase == Phase.CLOSED:
		return
	if phase == Phase.WAITING:
		if elapsed < warning_at() - tuning.pad_search_lead_seconds:
			return
		phase = Phase.SEARCHING
		_begin_search(_search_origin())
	if phase == Phase.SEARCHING:
		if _result.is_empty():
			_search_step(tuning.pad_candidates_per_step)
		if elapsed < warning_at():
			return
		_warn()
	if elapsed >= _arrive_at:
		# Nei 15 s dell'avviso il disco non e protetto: se qualcuno l'ha scavato o alzato, una
		# ricerca intera adesso; senza un punto piano resta quello annunciato.
		if terrain_field != null and not _is_level(center):
			var again := find_landing_now(_search_origin())
			if again.flat:
				center = Vector3(again.point.x, terrain_field.height_at(again.point), again.point.z)
				print("PROTOTYPE01_FUSION_PAD_MOVED x=%.1f z=%.1f" % [center.x, center.z])
		land_at(center)
		return
	if hud != null:
		var direction := center - (player.global_position if player != null else fallback_point)
		direction.y = 0.0
		hud.set_event_warning("PIAZZOLA DI FUSIONE", direction, _arrive_at - elapsed, RunHud.FUSION_COLOR, true,
			RunHud.WarningPriority.FUSION)


## Candidati attorno a [param origin]: anelli di 25, 22,5, 27,5, 20 e 30 m (dai valori della
## taratura), 24 angoli ogni 15 gradi da uno scarto casuale di `rng`.
func candidate_points(origin: Vector3) -> Array[Vector3]:
	var mid := (tuning.pad_distance_min + tuning.pad_distance_max) * 0.5
	var quarter := (tuning.pad_distance_max - tuning.pad_distance_min) * 0.25
	var radii: Array[float] = [mid, mid - quarter, mid + quarter, tuning.pad_distance_min, tuning.pad_distance_max]
	var step := TAU / ANGLES
	var offset := rng.randf() * step
	var points: Array[Vector3] = []
	for radius in radii:
		for i in ANGLES:
			var angle := offset + i * step
			points.append(Vector3(origin.x + cos(angle) * radius, 0.0, origin.z + sin(angle) * radius))
	return points


## Ricerca intera in un passo: `{point, flat}`. `flat` vale se il punto e un candidato buono;
## altrimenti il candidato utilizzabile col dislivello minore, o `fallback_point`.
func find_landing_now(origin: Vector3) -> Dictionary:
	_begin_search(origin)
	_search_step(_candidates.size())
	return _result


## Atterra su [param point] (chiamata dall'arrivo, dai test e dalle catture).
func land_at(point: Vector3) -> void:
	if hud != null and phase == Phase.WARNING:
		hud.clear_event_warning(RunHud.WarningPriority.FUSION)
	# Un secondo atterraggio rimette prima il disco di quello precedente.
	_release_protection()
	center = Vector3(point.x, terrain_field.height_at(point) if terrain_field != null else point.y, point.z)
	phase = Phase.OPEN
	_ensure_model()
	_model.position = center + Vector3.UP * DROP_HEIGHT
	_model.reset_physics_interpolation()
	_model.show()
	_descent_left = DESCENT_SECONDS
	_rise_left = 0.0
	var flat := false
	if terrain_field != null:
		flat = _is_level(center)
		_protection_before = terrain_field.snapshot_protected(center, flat_radius())
		terrain_field.set_protected(center, flat_radius(), true)
	if hud != null:
		hud.show_notice("PIAZZOLA DI FUSIONE ATTERRATA", NOTICE_SECONDS, RunHud.FUSION_COLOR)
	print("PROTOTYPE01_FUSION_PAD_LANDED x=%.1f z=%.1f flat=%s" % [center.x, center.z, flat])
	landed.emit(center)


## Si richiude in ogni fase: niente avviso, protezione di prima rimessa, modello che risale e si nasconde.
func close() -> void:
	if phase == Phase.CLOSED:
		return
	var was_warning := phase == Phase.WARNING
	var was_shown := was_warning or phase == Phase.OPEN
	phase = Phase.CLOSED
	_result = {}
	_bench_requested = false
	_release_protection()
	if _model != null and _model.visible:
		_descent_left = 0.0
		_rise_left = RISE_SECONDS
	if hud != null:
		if was_warning:
			hud.clear_event_warning(RunHud.WarningPriority.FUSION)
		if was_shown:
			hud.show_notice("LA PIAZZOLA SI RICHIUDE", NOTICE_SECONDS, RunHud.FUSION_COLOR)
	print("PROTOTYPE01_FUSION_PAD_CLOSED")
	closed.emit()


## Rimette la protezione che c'era sotto il disco prima dell'atterraggio.
func _release_protection() -> void:
	if not _protection_before.is_empty() and terrain_field != null:
		terrain_field.restore_protected(_protection_before)
	_protection_before = {}


# --- Ricerca ------------------------------------------------------------------------------

func _search_origin() -> Vector3:
	var origin := player.global_position if player != null else fallback_point
	return Vector3(origin.x, 0.0, origin.z)


func _begin_search(origin: Vector3) -> void:
	_candidates = candidate_points(origin)
	_next_candidate = 0
	_best_point = fallback_point
	_best_relief = INF
	_lamps = lamp_field.positions() if lamp_field != null else ([] as Array[Vector3])
	_result = {}


## Valuta al piu [param count] candidati; il primo buono chiude la ricerca, finiti i candidati
## vince il ripiego.
func _search_step(count: int) -> void:
	var left := count
	while left > 0 and _next_candidate < _candidates.size():
		var p := _candidates[_next_candidate]
		_next_candidate += 1
		left -= 1
		if not _is_usable(p):
			continue
		if _is_level(p):
			_result = {point = p, flat = true}
			return
		var relief := _relief(p)
		if relief < _best_relief:
			_best_relief = relief
			_best_point = p
	if _next_candidate >= _candidates.size():
		_result = {point = _best_point, flat = false}


## Avviso: finisce la ricerca se serve e fissa il centro.
func _warn() -> void:
	if _result.is_empty():
		_search_step(_candidates.size())
	var point: Vector3 = _result.point
	center = Vector3(point.x, terrain_field.height_at(point) if terrain_field != null else 0.0, point.z)
	phase = Phase.WARNING
	print("PROTOTYPE01_FUSION_PAD_WARNING x=%.1f z=%.1f at=%.1f" % [center.x, center.z, _arrive_at])
	warned.emit(center)


## Dentro il campo col margine, percorribile e raggiungibile (PathField pronto), centro e angoli
## fuori dai binari, nessun lampione sotto il disco: tutto tranne la planarita.
func _is_usable(p: Vector3) -> bool:
	if terrain_field == null:
		return false
	var limit := terrain_field.half_extents() - Vector2.ONE * (flat_radius() + 2.0)
	if absf(p.x) > limit.x or absf(p.z) > limit.y:
		return false
	if on_tracks.is_valid():
		var h := half_size()
		for corner: Vector3 in [Vector3.ZERO, Vector3(h, 0.0, h), Vector3(-h, 0.0, h), Vector3(h, 0.0, -h), Vector3(-h, 0.0, -h)]:
			if on_tracks.call(p + corner):
				return false
	var r := flat_radius()
	for lamp in _lamps:
		if Vector2(lamp.x - p.x, lamp.z - p.z).length() <= r:
			return false
	if path_field != null and path_field.is_ready():
		if not path_field.is_walkable(p) or path_field.cost_at(p) == PathField.UNREACHABLE:
			return false
	return true


## Disco piano entro la tolleranza e centro alla base (ne cumulo ne buca a fondo piatto). Prima
## lo scarto del centro, una lettura: `is_flat` legge tutto il disco.
func _is_level(p: Vector3) -> bool:
	return absf(terrain_field.delta_at(p)) <= tuning.pad_flat_tolerance \
		and terrain_field.is_flat(p, flat_radius(), tuning.pad_flat_tolerance)


## Dislivello per il ripiego: quota massima meno minima sulla griglia di 1 m dentro il disco,
## o lo scarto del centro dalla base se e maggiore. Solo per i candidati non piani.
func _relief(p: Vector3) -> float:
	var r := flat_radius()
	var n := int(r / RELIEF_STEP)
	var lo := INF
	var hi := -INF
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var offset := Vector3(ix * RELIEF_STEP, 0.0, iz * RELIEF_STEP)
			if offset.length_squared() > r * r:
				continue
			var h := terrain_field.height_at(p + offset)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return maxf(hi - lo, absf(terrain_field.delta_at(p)))


# --- Modello --------------------------------------------------------------------------------

func _tick_model(delta: float) -> void:
	if _model == null or not _model.visible:
		return
	if _descent_left > 0.0:
		_descent_left = maxf(_descent_left - delta, 0.0)
		var k := _descent_left / DESCENT_SECONDS
		_model.position = center + Vector3.UP * DROP_HEIGHT * k * k
		if _descent_left == 0.0:
			DebrisBurst.spawn(self, center + Vector3.UP * 0.3, DUST_COLOR, 28, 6.0, 0.2)
	elif _rise_left > 0.0:
		_rise_left = maxf(_rise_left - delta, 0.0)
		var k := 1.0 - _rise_left / RISE_SECONDS
		_model.position = center + Vector3.UP * DROP_HEIGHT * k * k
		if _rise_left == 0.0:
			_model.hide()


## Pianale con bordo giallo, gru arancione in un angolo (albero, braccio, cavo, gancio) e
## lampada in cima con la sua luce e un fascio verticale trasparente, visibile da lontano.
func _ensure_model() -> void:
	if _model != null:
		return
	_model = Node3D.new()
	_model.name = "Model"
	_model.top_level = true
	add_child(_model)
	var size := half_size() * 2.0
	_add_box("Deck", Vector3(size, DECK_THICKNESS, size), Vector3(0.0, DECK_THICKNESS * 0.5, 0.0), _material(DECK_COLOR))
	var edge := _material(EDGE_COLOR)
	var edge_y := DECK_THICKNESS + 0.03
	var along := half_size() - 0.15
	_add_box("EdgeNorth", Vector3(size, 0.06, 0.3), Vector3(0.0, edge_y, -along), edge)
	_add_box("EdgeSouth", Vector3(size, 0.06, 0.3), Vector3(0.0, edge_y, along), edge)
	_add_box("EdgeWest", Vector3(0.3, 0.06, size), Vector3(-along, edge_y, 0.0), edge)
	_add_box("EdgeEast", Vector3(0.3, 0.06, size), Vector3(along, edge_y, 0.0), edge)
	var crane := _material(CRANE_COLOR)
	var corner := Vector3(along - 0.2, DECK_THICKNESS, along - 0.2)
	_add_box("CraneMast", Vector3(0.3, MAST_HEIGHT, 0.3), corner + Vector3(0.0, MAST_HEIGHT * 0.5, 0.0), crane)
	var jib_length := 3.2
	var jib_y := MAST_HEIGHT - 0.3
	_add_box("CraneJib", Vector3(jib_length, 0.22, 0.22), corner + Vector3(-jib_length * 0.5 + 0.15, jib_y, 0.0), crane)
	var tip := corner + Vector3(-jib_length + 0.3, jib_y, 0.0)
	_add_box("CraneCable", Vector3(0.04, 1.8, 0.04), tip + Vector3(0.0, -1.0, 0.0), _material(CABLE_COLOR))
	_add_box("CraneHook", Vector3(0.28, 0.22, 0.14), tip + Vector3(0.0, -2.0, 0.0), crane)
	var lamp_at := corner + Vector3(0.0, MAST_HEIGHT + 0.2, 0.0)
	var lamp_material := _material(LAMP_COLOR)
	lamp_material.emission_enabled = true
	lamp_material.emission = LAMP_COLOR.linear_to_srgb()
	lamp_material.emission_energy_multiplier = 3.0
	_add_box("Lamp", Vector3(0.45, 0.3, 0.45), lamp_at, lamp_material)
	_light = OmniLight3D.new()
	_light.name = "PadLight"
	_light.position = lamp_at
	_light.light_color = LAMP_COLOR
	_light.shadow_enabled = false
	_light.omni_range = tuning.pad_light_radius
	_light.light_energy = 0.0
	_light.visible = false
	_model.add_child(_light)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.2
	beam_mesh.bottom_radius = 0.35
	beam_mesh.height = BEAM_HEIGHT
	var beam_material := StandardMaterial3D.new()
	beam_material.albedo_color = BEAM_COLOR
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	beam.mesh = beam_mesh
	beam.material_override = beam_material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.layers = Machine.VISUAL_LAYER
	beam.position = lamp_at + Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)
	_model.add_child(beam)


func _add_box(part_name: String, size: Vector3, at: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = material
	part.layers = Machine.VISUAL_LAYER
	part.position = at
	_model.add_child(part)
	return part


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.linear_to_srgb()
	material.roughness = 0.85
	return material
