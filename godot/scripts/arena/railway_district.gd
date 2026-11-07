@tool
class_name RailwayDistrict
extends RuinsDistrict
## Livello 2, la ferrovia (D-066, D-087, docs/RAILWAY_LEVEL_SPEC.md): un corridoio
## rettangolare lungo X (est-ovest) e stretto in Z, attraversato per tutta la
## lunghezza da una **fascia di binari** larga 7,2 m attorno a z = 0.
##
## Sul rilievo continuo (tappa B) la fascia e piatta nella base (il rumore si spegne
## sui binari con un raccordo ai lati) e riservata: niente rovine, oggetti ne cortili
## sopra, salvo i **vagoni**: cumuli con una vena di rottami che il treno spiana. Il
## cortile di partenza sta a cavallo dei binari: l'anello perde i tratti sulla fascia,
## cosi i varchi est e ovest coincidono con i binari. Stessi mattoni del quartiere
## (RuinsDistrict), pianta e perimetro diversi: torri a nord, bordo basso a sud, un
## portale di galleria a ciascuna estremita da cui entra il treno.

## Mezza larghezza della fascia dei binari (metri) e raccordo ai lati nel rilievo di base.
const TRACK_HALF_WIDTH := 3.6
const TRACK_EDGE_BLEND := 2.0
## Quota Z dei due binari.
const TRACK_Z: Array[float] = [-2.4, 2.4]
## Scartamento visivo delle rotaie (metri) e passo delle traversine.
const RAIL_GAUGE := 1.44
const SLEEPER_PITCH := 0.9
## Vagoni: cumuli con vena sulla fascia (spec tappa B, sezione 3).
const WAGON_RADIUS := 3.0
const WAGON_HEIGHT := 1.5
const WAGON_SCRAP := 8
## Tinta (lineare) della fascia (ghiaia scura) e dei vagoni (ruggine, come i rottami).
## Tinta della massicciata sopra la ghiaia CC0: solo un po piu scura e calda.
const BALLAST_TINT := Color(0.62, 0.58, 0.52)
const WAGON_TINT := Color(0.55, 0.22, 0.06)
## Portali di galleria alle estremita: quanto sporgono oltre l'area giocabile.
const PORTAL_DEPTH := 8.0

@export_group("Railway")
## Vagoni abbandonati sui binari: cumuli con vena che rendono rottami finche il treno non passa.
@export_range(0, 12) var wagon_count := 5:
	set(value):
		wagon_count = value
		_queue_rebuild()
## Distanza minima fra due vagoni lungo i binari.
@export var wagon_spacing := 24.0:
	set(value):
		wagon_spacing = value
		_queue_rebuild()


func _init() -> void:
	super()
	# 319,2 x 122,4 m (era una griglia di 133 x 51 celle di 2,4 m).
	play_half_extent = 159.6
	play_half_extent_z = 61.2
	# Lotti piu fitti: il corridoio ha meno righe di lotti del quartiere.
	lot_size = 16.0
	courtyard_count = 4
	deposit_count = 6
	trench_count = 4
	car_count = 16
	rubble_count = 16
	barrier_count = 14
	lamp_count = 12
	tree_count = 30
	bush_count = 50


# --- Geometria della fascia ----------------------------------------------------------

## Mezza larghezza della fascia dei binari, in metri.
static func track_half_width() -> float:
	return TRACK_HALF_WIDTH


## Il punto (mondo XZ) sta sulla fascia dei binari?
static func is_on_tracks(p: Vector2) -> bool:
	return absf(p.y) <= TRACK_HALF_WIDTH


## Rettangolo mondo XZ della fascia, per tutta la lunghezza dell'arena.
func track_rect() -> Rect2:
	return Rect2(-half_x(), -TRACK_HALF_WIDTH, half_x() * 2.0, TRACK_HALF_WIDTH * 2.0)


## 0 sulla fascia, 1 oltre il raccordo: il rumore di base si spegne sui binari.
static func track_calm(z: float) -> float:
	return smoothstep(TRACK_HALF_WIDTH, TRACK_HALF_WIDTH + TRACK_EDGE_BLEND, absf(z))


func _relief_calm(p: Vector2) -> float:
	return super(p) * track_calm(p.y)


## Nessuna strada dipinta: la fascia dei binari prende il suo posto.
func _road_segments() -> Array:
	return []


## Dopo macerie e solchi la fascia torna esattamente a zero (anche sotto le macerie
## vicine), con il raccordo ai lati.
func _sculpt_base_details(field: TerrainField) -> void:
	super(field)
	var half := field.half_extents()
	for iz in field.resolution_z:
		var z := iz * TerrainField.SPACING - half.y
		var calm := track_calm(z)
		if calm >= 1.0:
			continue
		for ix in field.resolution_x:
			field._heights[iz * field.resolution_x + ix] *= calm


# --- Composizione ----------------------------------------------------------------------

func _compose() -> void:
	terrain_strokes.clear()
	_block_rects.clear()
	_reset_occupancy()
	stats["strokes"] = 0
	stats["wagons"] = 0
	_build_boundary()
	_reserve_tracks()
	_plan_start_courtyard()
	_plan_wagons()
	_plan_courtyards()
	_plan_deposits()
	_plan_trenches()
	_build_tracks()
	_reset_ruin_details()
	_build_blocks()
	_build_props()
	_build_perimeter()
	_build_ruin_details()
	_build_ground_cover()
	_add_sun()
	_add_environment()


## La fascia dei binari, con un margine di una cella, non ospita nulla (nemmeno
## un oggetto il cui ingombro sporga sulla fascia).
func _reserve_tracks() -> void:
	var half := TRACK_HALF_WIDTH + CELL
	_reserve(Rect2(-half_x(), -half, half_x() * 2.0, half * 2.0))


## Cortile di partenza a cavallo dei binari: l'anello perde le pennellate sulla fascia,
## cosi i varchi est e ovest coincidono con i binari e il treno passa senza toccare argini.
func _plan_start_courtyard() -> void:
	var r := start_courtyard_radius
	var gates: Array[int] = [0, 1, 2, 3]
	var points: Array[Vector2] = []
	for p in _ring_points(Vector2.ZERO, r * CELL, gates):
		if absf(p.y) > TRACK_HALF_WIDTH + RAMPART_BRUSH * 0.6:
			points.append(p)
	_add_ring_stroke(&"start", Vector2.ZERO, r * CELL, gates, points)
	_reserve(_rect_around(Vector2.ZERO, Vector2.ONE * start_clear_radius))


## Vagoni merci sui binari: cumuli con vena, lontani dalla partenza e fra loro. Rendono
## rottami come i depositi, ma il treno li spiana e azzera la vena senza lasciarne.
func _plan_wagons() -> void:
	var placed: Array[float] = []
	var limit := half_x() - 12.0
	for i in wagon_count:
		var x := 0.0
		var found := false
		for attempt in 40:
			x = _rng.randf_range(-limit, limit)
			if absf(x) < start_clear_radius + 8.0:
				continue
			var far := true
			for other in placed:
				if absf(other - x) < wagon_spacing:
					far = false
					break
			if far:
				found = true
				break
		if not found:
			continue
		placed.append(x)
		# La pianta in celle sceglieva qui il binario con un numero casuale: si consuma lo
		# stesso numero cosi le posizioni restano quelle di prima (spec sezione 3, D-065).
		_rng.randf()
		var center := Vector2(x, 0.0)
		_add_stroke(&"wagon", center, WAGON_RADIUS, WAGON_HEIGHT, WAGON_TINT, WAGON_SCRAP, [], [center], WAGON_RADIUS, 0.0)
		stats.wagons += 1


## Trincee parallele ai binari (canali di scolo), mai di traverso.
func _plan_trenches() -> void:
	for i in trench_count:
		var length := _rng.randi_range(6, 14)
		var half := Vector2(length * CELL * 0.5, 1.0)
		var spot: Variant = _find_free_spot(half, 2.0, start_clear_radius + 4.0)
		if spot == null:
			continue
		var center: Vector2 = spot
		_reserve(_rect_around(center, half, 2.0))
		var a := center - Vector2(half.x - CELL * 0.5, 0.0)
		var b := center + Vector2(half.x - CELL * 0.5, 0.0)
		var steps := maxi(int(a.distance_to(b) / TRENCH_STEP), 1)
		var points: Array[Vector2] = []
		for t in steps + 1:
			points.append(a.lerp(b, float(t) / steps))
		_add_stroke(&"trench", center, TRENCH_BRUSH, TRENCH_DEPTH, NO_TINT, 0, [], points, TRENCH_BRUSH, a.distance_to(b) / steps)


## Le pennellate di cortili, depositi e argini sbavano sulla fascia per il raggio del
## pennello: la fascia torna alla base e solo i vagoni vi restano sopra.
func apply_strokes(field: TerrainField, scrap_field: ScrapField = null) -> void:
	field.begin_batch()
	super(field, scrap_field)
	field.reset_to_base(Vector3.ZERO, Vector2(half_x(), TRACK_HALF_WIDTH))
	for stroke: Dictionary in terrain_strokes:
		if stroke.kind != &"wagon":
			continue
		var amount: float = stroke.height / line_overlap(stroke.step, stroke.brush)
		for p: Vector2 in stroke.points:
			field.sculpt(Vector3(p.x, 0.0, p.y), stroke.brush, amount)
	field.end_batch()
	# Una vena sulla fascia, esaurita, torna del colore della ghiaia, non bianca.
	if scrap_field != null:
		for vein in scrap_field.veins():
			if is_on_tracks(Vector2(vein.center.x, vein.center.z)):
				vein.exhausted_tint = BALLAST_TINT


## Strati del quartiere piu la fascia: massicciata di ghiaia (texture CC0) per tutta la lunghezza.
func paint_surface(field: TerrainField) -> void:
	if field.terrain3d() == null:
		return
	field.begin_batch()
	super(field)
	var half := Vector2(half_x() + PORTAL_DEPTH, TRACK_HALF_WIDTH)
	field.paint_layer_rect(Vector3.ZERO, half, TerrainSurface.LAYER_GRAVEL)
	field.tint_rect(Vector3.ZERO, half, BALLAST_TINT, 0.8)
	field.end_batch()


## Niente prato sulla massicciata (la tinta di ghiaia lo copre comunque).
func _grass_points(field: TerrainField) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.assign(super(field).filter(func(p: Vector3) -> bool: return absf(p.z) > TRACK_HALF_WIDTH + 0.5))
	return out


## Massicciata, rotaie e traversine: solo mesh, nessuna collisione. Sporgono oltre
## il perimetro fino dentro i portali.
func _build_tracks() -> void:
	var tracks := Node3D.new()
	tracks.name = "Tracks"
	_add_generated(tracks)
	var length := half_x() * 2.0 + PORTAL_DEPTH * 2.0 + 8.0
	var ballast := StandardMaterial3D.new()
	ballast.albedo_color = Color(0.32, 0.30, 0.27)
	ballast.roughness = 0.95
	_mesh_child(tracks, _box(Vector3(length, 0.05, track_half_width() * 2.0 - 0.4)), ballast,
		Transform3D(Basis(), Vector3(0.0, 0.14, 0.0)))
	var rail_mesh := _box(Vector3(length, 0.14, 0.08))
	var sleeper_mesh := _box(Vector3(0.24, 0.1, 2.2))
	var sleepers := MultiMesh.new()
	sleepers.transform_format = MultiMesh.TRANSFORM_3D
	sleepers.mesh = sleeper_mesh
	var per_track := int(length / SLEEPER_PITCH)
	sleepers.instance_count = per_track * TRACK_Z.size()
	var index := 0
	for z in TRACK_Z:
		for side: float in [-RAIL_GAUGE * 0.5, RAIL_GAUGE * 0.5]:
			var rail := _mesh_child(tracks, rail_mesh, _rust_material, Transform3D(Basis(), Vector3(0.0, 0.29, z + side)))
			rail.set_instance_shader_parameter(&"paint", Color(0.36, 0.34, 0.33))
			rail.set_instance_shader_parameter(&"rust", 0.5)
			rail.set_instance_shader_parameter(&"overgrowth", 0.1)
		for i in per_track:
			var x := -length * 0.5 + (i + 0.5) * SLEEPER_PITCH
			sleepers.set_instance_transform(index, Transform3D(Basis(), Vector3(x, 0.21, z)))
			index += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sleepers"
	mmi.multimesh = sleepers
	mmi.material_override = _trunk_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracks.add_child(mmi)


## Perimetro: torri a nord, bordo basso a sud, portali di galleria alle estremita.
func _build_perimeter() -> void:
	_build_north_towers()
	_build_portals()
	_build_south_edge()


## Alle due estremita della linea: due piloni di cemento ai lati della fascia e un
## architrave sopra, cosi il treno entra ed esce da una bocca scura.
func _build_portals() -> void:
	var ex := half_x()
	var ez := half_z()
	var gap := track_half_width() + 1.6
	for side: float in [-1.0, 1.0]:
		var x := side * (ex + PORTAL_DEPTH)
		var label := "East" if side > 0.0 else "West"
		for pier: float in [-1.0, 1.0]:
			var depth := 14.0
			_tower("%sPortal%s" % [label, "N" if pier < 0.0 else "S"],
				Vector2(x, pier * (gap + depth * 0.5)), Vector2(PORTAL_DEPTH * 2.0 - 2.0, depth), 12.0, 0.6, false)
		_ruin_block("%sPortalLintel" % label, Vector3(x, 8.0, 0.0), Vector3(PORTAL_DEPTH * 2.0 - 2.0, 4.0, gap * 2.0),
			0.0, _pick(CONCRETE_TINTS), 0.7, 0.0, false)
		# Il resto del lato corto: edifici medi sopra e sotto il portale.
		var z := gap + 14.0 + 6.0
		var index := 0
		while z < ez - 6.0:
			var footprint := Vector2(_rng.randf_range(10.0, 14.0), _rng.randf_range(10.0, 16.0))
			for pier: float in [-1.0, 1.0]:
				_tower("%sBlock%d%s" % [label, index, "N" if pier < 0.0 else "S"],
					Vector2(side * (ex + 9.0 + footprint.x * 0.5), pier * (z + footprint.y * 0.5)), footprint,
					_rng.randf_range(10.0, 22.0), _rng.randf_range(0.6, 0.9))
			z += footprint.y + _rng.randf_range(8.0, 18.0)
			index += 1
