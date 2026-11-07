@tool
class_name RuinsDistrict
extends OvergrownArena
## Arena grande (D-042): un quartiere in rovina di circa 200x200 m, tutto
## giocabile, costruito con gli stessi mattoni dell'arena piccola (OvergrownArena).
##
## Dentro il perimetro ci sono solo rovine basse (al massimo 4,5 m, cosi non
## coprono mai il giocatore visto dalla camera a sud), auto, macerie, alberi e
## lampioni, che formano strade e strettoie per il campo di percorso. Le torri
## alte restano fuori dal perimetro, come skyline. I **punti di interesse** del
## terreno (cortili con argini, depositi con vena, trincee) sono prodotti qui come
## pennellate (`terrain_strokes`) e applicati al rilievo continuo da ArenaRun.
##
## Deterministico per seme: editor, gioco e test vedono lo stesso quartiere.

## Passo storico della pianta (2,4 m): raggi di cortili e lotti si misurano ancora in questi passi.
const CELL := 2.4
## Orientamento del cortile: lato aperto. 0 = +X Unreal (nord, -Z Godot),
## 1 = -X Unreal (sud), 2 = +Y Unreal (est, +X Godot), 3 = -Y Unreal (ovest).
const SIDES := 4
## Varianti dei cortili secondari, in ordine di assegnazione.
const COURTYARD_VARIANTS: Array[StringName] = [&"three_gates", &"two_gates", &"broken", &"double", &"three_gates", &"broken"]
## Risoluzione della mappa di occupazione, in metri.
const OCCUPANCY_STEP := 1.0
## Gusci delle rovine basse: spessore dei muri e altezza minima di un tratto
## (sopra la quota di tiro, 0,88 m: dove un chiodo si ferma il muro si vede).
const SHELL_WALL_THICKNESS := 0.5
## Metri di macerie dipinte oltre l'ingombro di ogni rovina.
const RUBBLE_SPILL_M := 2.5
const SHELL_MIN_WALL := 1.3
const SHELL_VINE_REACH := 0.3
## Corona spezzata in cima ai muri (D-068): altezze dei pezzi e dei tondini, misura della porta.
const CROWN_PIECE_HEIGHT := Vector2(0.12, 0.42)
const REBAR_HEIGHT := Vector2(0.3, 0.8)
const DOOR_SIZE := Vector2(1.0, 2.1)
## Pennellate dei punti di interesse (spec 6.1): argini dei cortili, cumuli, solchi.
const RING_STEP := 1.6
const RAMPART_HEIGHT := 1.4
## Pennello degli argini: piu stretto di quello del giocatore, cosi il fianco supera la
## pendenza di marcia (circa 1,1 m/m contro 0,8) e l'argine e un muro, non una rampa.
const RAMPART_BRUSH := 2.0
## Un varco toglie le pennellate a meno di questa distanza dalla sua direzione: restano
## circa 2,8 m di passaggio piano.
const GATE_CLEAR_M := 2.4
const DEPOSIT_HEIGHT := 1.5
const DEPOSIT_TINT := Color(0.5, 0.28, 0.12)
const TRENCH_STEP := 1.2
const TRENCH_BRUSH := 1.6
const TRENCH_DEPTH := -0.8
const NO_TINT := Color(0.0, 0.0, 0.0, 0.0)
## Verde del prato dipinto sul color map di Terrain3D (sotto i ciuffi).
const GRASS_PAINT := Color(0.42, 0.55, 0.22)
## Passo delle pennellate di prato dipinto.
const GRASS_PITCH := 3.0
## Direzione mondo (XZ) dei varchi 0..3.
const GATE_DIRECTIONS: Array[Vector2] = [Vector2(0.0, -1.0), Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2(-1.0, 0.0)]
## Tipi di pennellata che sono cortili (anelli di argini).
const COURTYARD_KINDS: Array[StringName] = [&"start", &"three_gates", &"two_gates", &"broken", &"double"]

@export_group("District")
## Raggio della piazza centrale: dentro il suolo e lastricato, fuori prevale il verde.
@export var plaza_radius_m := 30.0:
	set(value):
		plaza_radius_m = value
		_queue_rebuild()
## Attorno al punto di partenza non nascono edifici, oggetti ne altri punti di interesse.
@export var start_clear_radius := 20.0:
	set(value):
		start_clear_radius = value
		_queue_rebuild()
## Raggio del cortile di partenza, in celle (anello di mura con quattro varchi).
@export_range(2, 6) var start_courtyard_radius := 4:
	set(value):
		start_courtyard_radius = value
		_queue_rebuild()
## Passo dei lotti edificabili e quota di lotti occupati da una rovina.
@export var lot_size := 20.0:
	set(value):
		lot_size = value
		_queue_rebuild()
@export_range(0.0, 1.0) var lot_fill := 0.55:
	set(value):
		lot_fill = value
		_queue_rebuild()

@export_group("Points of interest")
@export_range(0, 12) var courtyard_count := 5:
	set(value):
		courtyard_count = value
		_queue_rebuild()
@export_range(0, 30) var deposit_count := 10:
	set(value):
		deposit_count = value
		_queue_rebuild()
@export_range(0, 12) var trench_count := 4:
	set(value):
		trench_count = value
		_queue_rebuild()

@export_group("Props")
@export_range(0, 80) var car_count := 22:
	set(value):
		car_count = value
		_queue_rebuild()
@export_range(0, 80) var rubble_count := 18:
	set(value):
		rubble_count = value
		_queue_rebuild()
@export_range(0, 80) var barrier_count := 16:
	set(value):
		barrier_count = value
		_queue_rebuild()
@export_range(0, 60) var lamp_count := 14:
	set(value):
		lamp_count = value
		_queue_rebuild()
@export_range(0, 120) var tree_count := 36:
	set(value):
		tree_count = value
		_queue_rebuild()
@export_range(0, 200) var bush_count := 60:
	set(value):
		bush_count = value
		_queue_rebuild()

## I punti di interesse come pennellate sul rilievo continuo (D-085, spec 6.1).
## Ogni voce: { kind: StringName, center: Vector2 (XZ), radius: float (anello: raggio in m;
##   deposito e trincea: raggio del pennello), height: float (m al colmo, + argine o cumulo,
##   - solco), tint: Color (alfa 0 = nessuna), scrap: int, marker: Vector2, gates: Array[int],
##   points: Array[Vector2] (centri delle pennellate), brush: float (raggio del pennello),
##   step: float (passo fra i punti, 0 = punto singolo) }.
var terrain_strokes: Array[Dictionary] = []

## Mappa di occupazione dell'area giocabile a passo di 1 m: 1 = riservato
## (punto di interesse, edificio, oggetto con collisione).
var _occupancy := PackedByteArray()
var _occupancy_columns := 0
var _occupancy_rows := 0
var _unit_box: BoxMesh
## Ingombri (XZ) delle rovine interne e dei palazzi ai lati, nell'ordine di costruzione.
var _block_rects: Array[Rect2] = []
## Muri a moduli con la cima spezzata (O-10): le corone a blocchi non servono piu.
var crowns_from_modules := true


func _init() -> void:
	play_half_extent = 102.0
	clear_half_extent = 0.0
	grass_tufts = 90000
	flowers = 4000


# --- Parametri che l'arena base legge ---------------------------------------------

func plaza_radius() -> float:
	return plaza_radius_m


func ground_size() -> float:
	return maxf(half_x(), half_z()) * 2.0 + 160.0


func cover_limit() -> float:
	return half_x() + 20.0


## Senza celle Normal (12 cm) i ciuffi partono da quota zero; sul rilievo li appoggia
## il Task 14 del terreno continuo (`terrain_field.height_at`).
func cover_height() -> float:
	return 0.0


func _cover_excluded(p: Vector2) -> bool:
	return _is_reserved(p)


## Fuori dalla piazza il verde e quasi ovunque: niente rumore, costo basso.
func _cover_chance(p: Vector2, bonus := 0.0) -> float:
	if p.length() > plaza_radius_m * 1.25:
		return 0.72
	return super._cover_chance(p, bonus)


# --- Composizione --------------------------------------------------------------------

func _compose() -> void:
	terrain_strokes.clear()
	_block_rects.clear()
	_reset_occupancy()
	stats["strokes"] = 0
	_build_boundary()
	_plan_start_courtyard()
	_plan_courtyards()
	_plan_deposits()
	_plan_trenches()
	_reset_ruin_details()
	_build_blocks()
	_build_props()
	_build_perimeter()
	_build_ruin_details()
	_build_ground_cover()
	_add_sun()
	_add_environment()


# --- Occupazione -----------------------------------------------------------------------

func _reset_occupancy() -> void:
	_occupancy_columns = int(ceil(half_x() * 2.0 / OCCUPANCY_STEP)) + 2
	_occupancy_rows = int(ceil(half_z() * 2.0 / OCCUPANCY_STEP)) + 2
	_occupancy.resize(_occupancy_columns * _occupancy_rows)
	_occupancy.fill(0)


func _occupancy_index(p: Vector2) -> int:
	var x := int(floor((p.x + half_x()) / OCCUPANCY_STEP)) + 1
	var y := int(floor((p.y + half_z()) / OCCUPANCY_STEP)) + 1
	if x < 0 or y < 0 or x >= _occupancy_columns or y >= _occupancy_rows:
		return -1
	return y * _occupancy_columns + x


func _is_reserved(p: Vector2) -> bool:
	var i := _occupancy_index(p)
	return i >= 0 and _occupancy[i] != 0


## Il rettangolo (mondo XZ) e libero e tutto dentro l'area giocabile?
func _is_free(rect: Rect2) -> bool:
	if rect.position.x < -half_x() or rect.position.y < -half_z() \
			or rect.end.x > half_x() or rect.end.y > half_z():
		return false
	var y := rect.position.y
	while y <= rect.end.y:
		var x := rect.position.x
		while x <= rect.end.x:
			if _is_reserved(Vector2(x, y)):
				return false
			x += OCCUPANCY_STEP
		y += OCCUPANCY_STEP
	return true


func _reserve(rect: Rect2) -> void:
	var y := rect.position.y
	while y <= rect.end.y:
		var x := rect.position.x
		while x <= rect.end.x:
			var i := _occupancy_index(Vector2(x, y))
			if i >= 0:
				_occupancy[i] = 1
			x += OCCUPANCY_STEP
		y += OCCUPANCY_STEP


## Rettangolo centrato, con margine.
static func _rect_around(center: Vector2, half: Vector2, margin := 0.0) -> Rect2:
	return Rect2(center - half - Vector2(margin, margin), (half + Vector2(margin, margin)) * 2.0)


## Punto casuale entro l'area giocabile, a distanza minima dal centro, con il
## rettangolo richiesto libero; null se non lo trova.
func _find_free_spot(half: Vector2, margin: float, min_center_distance: float, attempts := 40) -> Variant:
	var limit := half_x() - half.length() - margin - 1.0
	var limit_z := half_z() - half.length() - margin - 1.0
	for attempt in attempts:
		var p := Vector2(_rng.randf_range(-limit, limit), _rng.randf_range(-limit_z, limit_z))
		if p.length() < min_center_distance:
			continue
		if _is_free(_rect_around(p, half, margin)):
			return p
	return null


# --- Punti di interesse del terreno ---------------------------------------------------

## Cortile di partenza: anello con quattro varchi attorno all'origine (D-038).
func _plan_start_courtyard() -> void:
	var r := start_courtyard_radius
	var gates: Array[int] = [0, 1, 2, 3]
	_add_ring_stroke(&"start", Vector2.ZERO, r * CELL, gates, _ring_points(Vector2.ZERO, r * CELL, gates))
	# Area di partenza libera da edifici e oggetti.
	_reserve(_rect_around(Vector2.ZERO, Vector2.ONE * start_clear_radius))


## Cortili secondari: varianti del cortile di partenza, lontani fra loro.
func _plan_courtyards() -> void:
	var placed: Array[Vector2] = []
	for i in courtyard_count:
		var variant := COURTYARD_VARIANTS[i % COURTYARD_VARIANTS.size()]
		var radius := _rng.randi_range(3, 5)
		var half := Vector2.ONE * (radius + 0.5) * CELL
		var center: Variant = null
		for attempt in 60:
			var found: Variant = _find_free_spot(half, 4.0, start_clear_radius + half.x + 6.0, 1)
			if found == null:
				continue
			var candidate: Vector2 = found
			var far := true
			for other in placed:
				if other.distance_to(candidate) < 40.0:
					far = false
					break
			if far:
				center = _snap_to_step(candidate)
				break
		if center == null:
			continue
		placed.append(center)
		var gates: Array[int] = []
		var broken := 0.0
		match variant:
			&"three_gates":
				gates = [0, 1, 2, 3]
				gates.erase(_rng.randi_range(0, SIDES - 1))
			&"two_gates", &"double":
				if _rng.randf() < 0.5:
					gates = [0, 1]
				else:
					gates = [2, 3]
			&"broken":
				gates = [0, 1, 2, 3]
				broken = 0.3
		# La pianta in celle riservava il rettangolo attorno al baricentro delle celle
		# dell'anello (varchi e celle "broken" esclusi, con un numero casuale per cella):
		# si rifa lo stesso conto cosi il quartiere resta identico (D-065).
		_reserve(_rect_around(center + _ring_cells_centroid(radius, gates, broken), half, 4.0))
		# Generatore proprio per le pennellate mancanti: `_rng` resta com'era e la pianta
		# del quartiere non cambia (D-065).
		var stroke_rng := RandomNumberGenerator.new()
		stroke_rng.seed = layout_seed + 101 + i
		var points := _ring_points(center, radius * CELL, gates, broken, stroke_rng)
		if variant == &"double" and radius >= 4:
			var inner_gates: Array[int] = [2 if gates.has(0) else 0]
			points.append_array(_ring_points(center, 2 * CELL, inner_gates))
		_add_ring_stroke(variant, center, radius * CELL, gates, points)


## Depositi di rottami: cumuli di 2 o 3 passi con una vena dentro (spec 5.1), nella
## stessa posizione dei vecchi blocchi di celle (il cumulo sta al baricentro del blocco).
func _plan_deposits() -> void:
	for i in deposit_count:
		var size := 2 if _rng.randf() < 0.6 else 3
		var half := Vector2.ONE * size * CELL * 0.5
		var spot: Variant = _find_free_spot(half, 3.0, start_clear_radius + 6.0)
		if spot == null:
			continue
		var center := _snap_to_step(spot)
		# Un blocco di lato pari non ha una cella centrale: il baricentro sta a mezzo passo.
		var heap := center + (Vector2(-CELL, CELL) * 0.5 if size % 2 == 0 else Vector2.ZERO)
		_reserve(_rect_around(heap, half, 3.0))
		var heap_radius := size * CELL * 0.5 + 1.0
		_add_stroke(&"deposit", heap, heap_radius, DEPOSIT_HEIGHT, DEPOSIT_TINT, 6 + 2 * (size - 2), [], [heap], heap_radius, 0.0)


## Trincee: solchi gia scavati (canali crollati) lungo X o Z, fossati pronti; stessa
## linea delle vecchie file di celle.
func _plan_trenches() -> void:
	for i in trench_count:
		var length := _rng.randi_range(6, 14)
		var along_x := _rng.randf() < 0.5
		var half := Vector2(1.0, length * CELL * 0.5) if along_x else Vector2(length * CELL * 0.5, 1.0)
		var spot: Variant = _find_free_spot(half, 2.0, start_clear_radius + 4.0)
		if spot == null:
			continue
		var center := _snap_to_step(spot)
		@warning_ignore("integer_division")
		var lo := -(length / 2)
		var hi := lo + length - 1
		# Assi Unreal della vecchia griglia: x avanti = -Z Godot, y destra = +X Godot.
		var a := center + (Vector2(0.0, -lo * CELL) if along_x else Vector2(lo * CELL, 0.0))
		var b := center + (Vector2(0.0, -hi * CELL) if along_x else Vector2(hi * CELL, 0.0))
		_reserve(_rect_around((a + b) * 0.5, half, 2.0))
		var steps := maxi(int(a.distance_to(b) / TRENCH_STEP), 1)
		var points: Array[Vector2] = []
		for t in steps + 1:
			points.append(a.lerp(b, float(t) / steps))
		_add_stroke(&"trench", (a + b) * 0.5, TRENCH_BRUSH, TRENCH_DEPTH, NO_TINT, 0, [], points, TRENCH_BRUSH, a.distance_to(b) / steps)


## Baricentro mondo (XZ, relativo al centro) delle celle dell'anello di raggio [param radius]
## passi, senza i varchi in [param gates]; con [param broken] > 0 una quota casuale di
## celle manca (un `_rng.randf()` per cella, come la vecchia griglia). Serve alla riserva
## dei cortili per tenere la pianta di prima (D-065).
func _ring_cells_centroid(radius: int, gates: Array[int], broken := 0.0) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) != radius:
				continue
			var is_gate := (dx == radius and dy == 0 and gates.has(0)) \
				or (dx == -radius and dy == 0 and gates.has(1)) \
				or (dy == radius and dx == 0 and gates.has(2)) \
				or (dy == -radius and dx == 0 and gates.has(3))
			if is_gate:
				continue
			if broken > 0.0 and _rng.randf() < broken:
				continue
			# Assi Unreal della vecchia griglia: x avanti = -Z Godot, y destra = +X Godot.
			sum += Vector2(dy * CELL, -dx * CELL)
			count += 1
	return sum / count if count > 0 else Vector2.ZERO


## Punto piu vicino sul passo storico di 2,4 m (la pianta nasce ancora su quel reticolo).
static func _snap_to_step(p: Vector2) -> Vector2:
	return Vector2(roundf(p.x / CELL) * CELL, roundf(p.y / CELL) * CELL)


# --- Pennellate del terreno continuo -------------------------------------------------------

func _add_stroke(kind: StringName, center: Vector2, radius: float, height: float, tint: Color, scrap: int,
		gates: Array[int], points: Array[Vector2], brush: float, step: float) -> void:
	terrain_strokes.append({
		kind = kind, center = center, radius = radius, height = height, tint = tint, scrap = scrap,
		marker = center, gates = gates, points = points, brush = brush, step = step,
	})
	stats.strokes += 1


func _add_ring_stroke(kind: StringName, center: Vector2, radius_m: float, gates: Array[int], points: Array[Vector2]) -> void:
	_add_stroke(kind, center, radius_m, RAMPART_HEIGHT, NO_TINT, 0, gates, points, RAMPART_BRUSH, TAU * radius_m / _ring_count(radius_m))


## Punti dell'anello: un multiplo di 4, cosi un punto cade esattamente su ogni varco.
static func _ring_count(radius_m: float) -> int:
	return maxi(1, roundi(TAU * radius_m / RING_STEP / 4.0)) * 4


## Centri delle pennellate di un anello di raggio [param radius_m], uno ogni ~RING_STEP m,
## senza quelli a meno di GATE_CLEAR_M dai varchi in [param gates]; con [param broken] > 0
## ne manca una quota a caso (l'argine e piu basso in quei tratti). Il primo punto sta in
## diagonale, a meta di un tratto pieno.
func _ring_points(center: Vector2, radius_m: float, gates: Array[int], broken := 0.0,
		rng: RandomNumberGenerator = null) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var count := _ring_count(radius_m)
	var first := roundi(count / 8.0)
	for k in count:
		var angle := TAU * float(k + first) / count
		var p := center + Vector2(cos(angle), sin(angle)) * radius_m
		var in_gate := false
		for gate in gates:
			in_gate = in_gate or p.distance_to(center + GATE_DIRECTIONS[gate] * radius_m) < GATE_CLEAR_M
		if in_gate:
			continue
		if broken > 0.0 and rng != null and rng.randf() < broken:
			continue
		points.append(p)
	return points


## Ingombri XZ delle rovine (con le ali) e dei palazzi ai lati: macerie e aree protette.
func block_rects() -> Array[Rect2]:
	return _block_rects


## Strade del quartiere: la sola est-ovest a z = 0 (solco nella base e strato d'asfalto).
func _road_segments() -> Array:
	return [[Vector2(-half_x(), 0.0), Vector2(half_x(), 0.0)]]


## Attenuazione del rilievo: 20 % nella piazza e nel cortile di partenza, pieno fuori.
func _relief_calm(p: Vector2) -> float:
	return 1.0 - 0.8 * (1.0 - smoothstep(plaza_radius_m * 0.6, plaza_radius_m * 1.3, p.length()))


## Somma delle campane (1 - d^2)^2 di una fila di pennelli a passo [param step]: divide
## l'altezza di una pennellata cosi il colmo della fila vale l'altezza voluta.
static func line_overlap(step: float, brush: float) -> float:
	if step <= 0.0:
		return 1.0
	var total := 1.0
	var k := 1
	while k * step < brush:
		var d := k * step / brush
		total += 2.0 * (1.0 - d * d) * (1.0 - d * d)
		k += 1
	return total


## Rilievo di base del quartiere (spec 6.1): rumore a tre ottave attenuato nella piazza,
## cumuli di macerie attorno alle rovine e solchi lungo le strade; poi `commit_base()`.
## Deterministico per `layout_seed`, indipendente dall'ordine di costruzione. In tre passi,
## cosi la ferrovia puo spianare la fascia dei binari prima di fissare la base.
func apply_base_relief(field: TerrainField) -> void:
	_write_base_noise(field)
	_sculpt_base_details(field)
	_finish_base(field)


## Rumore a tre ottave attenuato (piazza, cortile e, nella ferrovia, fascia dei binari).
func _write_base_noise(field: TerrainField) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = layout_seed
	noise.frequency = 0.025
	var half := field.half_extents()
	for iz in field.resolution_z:
		for ix in field.resolution_x:
			var x := ix * TerrainField.SPACING - half.x
			var z := iz * TerrainField.SPACING - half.y
			var h := noise.get_noise_2d(x, z) * 1.2 + noise.get_noise_2d(x * 2.8, z * 2.8) * 0.5 + noise.get_noise_2d(x * 6.5, z * 6.5) * 0.25
			field._heights[iz * field.resolution_x + ix] = h * _relief_calm(Vector2(x, z))


## Cumuli di macerie attorno alle rovine e solchi lungo le strade.
func _sculpt_base_details(field: TerrainField) -> void:
	var rubble := RandomNumberGenerator.new()
	rubble.seed = layout_seed + 7
	for block in block_rects():
		for k in 6:
			var angle := TAU * k / 6.0
			var p := block.get_center() + Vector2(cos(angle), sin(angle)) * (block.size.length() * 0.5 + 1.5)
			field.sculpt(Vector3(p.x, 0, p.y), 3.0, rubble.randf_range(0.4, 0.8))
	# Solco di 0,3 m al colmo (la fila di pennelli si somma), attenuato come il rumore.
	var furrow := -0.3 / line_overlap(1.5, 2.0)
	for road: Array in _road_segments():
		var from: Vector2 = road[0]
		var to: Vector2 = road[1]
		var length := from.distance_to(to)
		for t in int(length / 1.5) + 1:
			var p: Vector2 = from.lerp(to, minf(t * 1.5 / length, 1.0))
			field.sculpt(Vector3(p.x, 0, p.y), 2.0, furrow * _relief_calm(p))


func _finish_base(field: TerrainField) -> void:
	field.commit_base()
	field._mirror_all()
	# Le quote del rumore sono scritte senza pennello: collisione e percorso vanno avvisati.
	field.region_changed.emit(field._full_aabb())


## Pennellate dei punti di interesse sopra la base: sporgono da essa, cosi il Demolitore
## le vede come gli argini del layout. Con [param scrap_field] ogni deposito registra la
## sua vena di rottami alla quota di base del cumulo (spec 5.1).
## La run (ArenaRun) chiama sempre `settle_on_relief` dopo il rilievo: niente prato a quota
## zero da buttare (audit R-04).
func _cover_waits_for_settle() -> bool:
	return true


func apply_strokes(field: TerrainField, scrap_field: ScrapField = null) -> void:
	# Centinaia di pennellate: un solo aggiornamento di specchio, collisione e campo alla fine
	# (audit PF-03: prima uno per pennellata, a ogni avvio del livello).
	field.begin_batch()
	for stroke: Dictionary in terrain_strokes:
		var amount: float = stroke.height / line_overlap(stroke.step, stroke.brush)
		for p: Vector2 in stroke.points:
			field.sculpt(Vector3(p.x, 0.0, p.y), stroke.brush, amount)
		var center := Vector3(stroke.center.x, 0.0, stroke.center.y)
		if stroke.scrap > 0 and scrap_field != null:
			scrap_field.add_vein(center, stroke.radius, stroke.scrap, field.base_height_at(center))
	field.end_batch()
	paint_surface(field)


## Strati e tinte di Terrain3D per il quartiere (spec 6.2): piazza lastricata, strada in
## asfalto, cime di argini e cumuli in terra smossa, ruggine sui depositi. Niente in
## headless; da richiamare quando Terrain3D diventa pronto (`TerrainField.render_ready`).
func paint_surface(field: TerrainField) -> void:
	if field.terrain3d() == null:
		return
	# Centinaia di strati e tinte: un solo caricamento delle mappe alla fine.
	field.begin_batch()
	field.paint_layer(Vector3.ZERO, plaza_radius_m * 0.8, TerrainSurface.LAYER_SLABS)
	# Macerie attorno alle rovine (playtest del 14 ottobre, O-08): il crollo si sparge
	# oltre i muri; prima delle strade, che restano sopra.
	for rect: Rect2 in _block_rects:
		var c := rect.get_center()
		field.paint_layer(Vector3(c.x, 0.0, c.y), maxf(rect.size.x, rect.size.y) * 0.5 + RUBBLE_SPILL_M, TerrainSurface.LAYER_RUBBLE)
	for road: Array in _road_segments():
		var from: Vector2 = road[0]
		var to: Vector2 = road[1]
		var length := from.distance_to(to)
		for t in int(length / 1.5) + 1:
			var p: Vector2 = from.lerp(to, minf(t * 1.5 / length, 1.0))
			field.paint_layer(Vector3(p.x, 0.0, p.y), 2.2, TerrainSurface.LAYER_ASPHALT)
	for stroke: Dictionary in terrain_strokes:
		if stroke.height <= 0.0:
			continue
		for p: Vector2 in stroke.points:
			field.paint_layer(Vector3(p.x, 0.0, p.y), stroke.brush * 0.6, TerrainSurface.LAYER_DUG_SOIL)
		if stroke.tint.a > 0.0:
			field.tint(Vector3(stroke.center.x, 0.0, stroke.center.y), stroke.radius, stroke.tint, 1.0)
	# Prato dipinto dove cresce il verde (stessa formula dei ciuffi), fuori dalla piazza.
	field.tint_points(_grass_points(field), GRASS_PITCH * 0.9, GRASS_PAINT, 0.55)
	field.end_batch()


## Prato logico (MeadowMap, piano 3 delle armi): le stesse pennellate della pittura verde di
## `paint_surface`, anche in headless.
func fill_meadow(map: MeadowMap, field: TerrainField) -> void:
	for p in _grass_points(field):
		map.mark(p, GRASS_PITCH * 0.6)


## Centri delle pennellate di prato: fuori dalla piazza, dove la copertura verde e piena.
func _grass_points(field: TerrainField) -> Array[Vector3]:
	var green: Array[Vector3] = []
	var half := field.half_extents()
	var k := 0
	for z in range(int(-half.y / GRASS_PITCH), int(half.y / GRASS_PITCH) + 1):
		for x in range(int(-half.x / GRASS_PITCH), int(half.x / GRASS_PITCH) + 1):
			k += 1
			var p := Vector2(x * GRASS_PITCH + (0.7 if k % 2 == 0 else -0.7), z * GRASS_PITCH)
			if p.length() < plaza_radius_m * 0.8 or _cover_sampled(p) < 0.5:
				continue
			green.append(Vector3(p.x, 0.0, p.y))
	return green


# --- Edifici e oggetti dentro il perimetro ----------------------------------------------

## Rovine basse sui lotti liberi: formano strade e strettoie.
func _build_blocks() -> void:
	var count := 0
	var x := -half_x() + lot_size
	while x < half_x() - lot_size * 0.5:
		var z := -half_z() + lot_size
		while z < half_z() - lot_size * 0.5:
			var center := Vector2(x, z) + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0))
			var footprint := Vector2(_rng.randf_range(6.0, 14.0), _rng.randf_range(5.0, 12.0))
			var roll := _rng.randf()
			if roll < lot_fill and center.length() > start_clear_radius + footprint.length() \
					and _is_free(_rect_around(center, footprint * 0.5, 3.0)):
				_low_ruin(count, center, footprint)
				count += 1
			z += lot_size
		x += lot_size


## Rovina bassa (2,5-4,5 m) senza tetto, con eventuale ala a L e macerie accanto.
func _low_ruin(index: int, center: Vector2, footprint: Vector2) -> void:
	var tint := _pick(CONCRETE_TINTS)
	var height := _rng.randf_range(2.5, 4.5)
	var yaw := _rng.randf_range(-6.0, 6.0)
	_ruin_shell("Block%d" % index, Vector3(center.x, 0.0, center.y), Vector3(footprint.x, height, footprint.y),
		yaw, tint, _rng.randf_range(0.1, 0.5))
	_reserve(_rect_around(center, footprint * 0.5, 1.0))
	_block_rects.append(_rect_around(center, footprint * 0.5))
	if _rng.randf() < 0.5:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var wing_size := Vector2(_rng.randf_range(4.0, 7.0), _rng.randf_range(3.0, 6.0))
		var wing_center := center + Vector2(side * (footprint.x * 0.5 + wing_size.x * 0.5 - 0.3), footprint.y * 0.5 - wing_size.y * 0.5)
		if _is_free(_rect_around(wing_center, wing_size * 0.5, 1.0)):
			_ruin_shell("Block%dWing" % index, Vector3(wing_center.x, 0.0, wing_center.y),
				Vector3(wing_size.x, maxf(height * _rng.randf_range(0.5, 0.8), SHELL_MIN_WALL), wing_size.y), yaw, tint, 0.5)
			_reserve(_rect_around(wing_center, wing_size * 0.5, 1.0))
			_block_rects.append(_rect_around(wing_center, wing_size * 0.5))
	if _rng.randf() < 0.5:
		var rubble_center := center + Vector2(0.0, footprint.y * 0.5 + 2.5)
		if _is_free(_rect_around(rubble_center, Vector2.ONE * 2.2, 0.5)):
			_rubble(Vector3(rubble_center.x, 0.0, rubble_center.y), 1.8)
			_reserve(_rect_around(rubble_center, Vector2.ONE * 2.2))
	# Il verde cresce dentro, sul pavimento, non piu sul tetto.
	for i in _rng.randi_range(1, 3):
		var p := center + Vector2(_rng.randf_range(-0.3, 0.3) * footprint.x, _rng.randf_range(-0.3, 0.3) * footprint.y)
		_bush(Vector3(p.x, 0.1, p.y), _rng.randf_range(1.2, 2.2), false)


## Guscio di edificio sventrato: muri perimetrali a tratti di altezza diversa,
## pavimento interno, macerie e un lembo di solaio crollato. La collisione resta
## il blocco pieno, e nessun tratto di muro e piu basso di `SHELL_MIN_WALL`: nemici,
## chiodi e campo di percorso lo vedono come un blocco, e dove un chiodo si ferma
## c'e sempre un muro visibile.
func _ruin_shell(node_name: String, base: Vector3, size: Vector3, yaw_deg: float,
		tint: Color, overgrowth: float) -> StaticBody3D:
	var body := _static_body(node_name, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), base))
	_box_shape_child(body, size, Transform3D(Basis(), Vector3(0.0, size.y * 0.5, 0.0)))
	stats.blocks += 1
	var t := SHELL_WALL_THICKNESS
	var inner := Vector2(size.x - t * 2.0, size.z - t * 2.0)
	_shell_piece(body, Vector3(0.0, 0.06, 0.0), Vector3(inner.x, 0.12, inner.y), tint * 0.6, base.y + 0.12, 0.25, 0.0)
	for side in 4:
		var along_x := side < 2
		var direction := 1.0 if side % 2 == 0 else -1.0
		# I muri lungo Z stanno fra quelli lungo X: niente facce sovrapposte agli angoli.
		var length := size.x if along_x else inner.y
		var segments := maxi(2, roundi(length / 3.0))
		var segment := length / segments
		var door_segment := _rng.randi_range(0, segments - 1) if side == 0 else -1
		for s in segments:
			var wall_height := maxf(SHELL_MIN_WALL, size.y * _rng.randf_range(0.4, 1.0))
			if _rng.randf() < 0.3:
				wall_height = size.y
			var along := -length * 0.5 + segment * (s + 0.5)
			var across := direction * ((size.z if along_x else size.x) * 0.5 - t * 0.5)
			var at := Vector3(along, wall_height * 0.5, across) if along_x else Vector3(across, wall_height * 0.5, along)
			# Modulo con la cima spezzata (O-10): base del tratto a terra, lunghezza lungo x
			# del modulo (ruotato di 90 gradi per i muri lungo Z).
			var broken := wall_height < size.y - 0.3
			# Variante da un hash, non dal generatore: la disposizione del quartiere (e il
			# rilievo cotto che ne dipende) resta identica.
			var variant := ("%s:%d:%d" % [node_name, side, s]).hash()
			var module := RuinModules.broken_wall(variant) if broken else RuinModules.whole_wall(variant)
			var turn := Basis() if along_x else Basis(Vector3.UP, PI * 0.5)
			# Le finestre ora sono vani veri nei moduli: niente finestre dipinte (windows 0).
			_shell_piece(body, at - Vector3(0.0, wall_height * 0.5, 0.0), Vector3(segment, wall_height, t),
				tint, base.y + wall_height, overgrowth, 0.0, turn, module)
			# Cima spezzata: qualche pezzo e tondini sui tratti crollati (D-068).
			if broken:
				_wall_crown(body, at, along_x, segment, wall_height, t, tint)
			# Una porta scura sulla facciata sud (quella vista dalla camera).
			if s == door_segment and wall_height >= DOOR_SIZE.y + 0.2 and segment >= DOOR_SIZE.x + 0.6:
				var door_at := Vector3(along, DOOR_SIZE.y * 0.5, across + direction * (t * 0.5 + 0.02))
				_mesh_child(body, _unit_box_mesh(), _dark_material,
					Transform3D(Basis.from_scale(Vector3(DOOR_SIZE.x, DOOR_SIZE.y, 0.06)), door_at))
	# Macerie sul pavimento.
	for i in _rng.randi_range(2, 4):
		var chunk := Vector3(_rng.randf_range(0.5, 1.6), _rng.randf_range(0.25, 0.7), _rng.randf_range(0.5, 1.4))
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0.0, TAU), _rng.randf_range(-0.3, 0.3)))
		var at := Vector3(_rng.randf_range(-0.38, 0.38) * inner.x, chunk.y * 0.4 + 0.1, _rng.randf_range(-0.38, 0.38) * inner.y)
		_shell_piece(body, at, chunk, _pick(CONCRETE_TINTS), base.y + at.y + chunk.y, 0.7, 0.0, basis)
	# Lembo di solaio crollato, appoggiato a un muro lungo X.
	if _rng.randf() < 0.6:
		var slab := Vector3(inner.x * _rng.randf_range(0.35, 0.6), 0.22, inner.y * _rng.randf_range(0.45, 0.7))
		var toward := 1.0 if _rng.randf() < 0.5 else -1.0
		var lean := deg_to_rad(_rng.randf_range(16.0, 26.0)) * toward
		var rise := sin(absf(lean)) * slab.z * 0.5
		var at := Vector3(_rng.randf_range(-0.2, 0.2) * inner.x, rise + 0.25, -toward * (inner.y * 0.5 - cos(lean) * slab.z * 0.5))
		_shell_piece(body, at, slab, tint * 0.85, base.y + at.y + rise, overgrowth, 0.0, Basis(Vector3.RIGHT, lean))
	return body


## Un pezzo del guscio: il cubo unitario condiviso, scalato (stessa mesh e stesso
## materiale per tutti i pezzi di tutte le rovine).
func _shell_piece(body: Node3D, at: Vector3, size: Vector3, tint: Color, top_y: float,
		overgrowth: float, windows: float, basis := Basis(), mesh: Mesh = null) -> void:
	if _unit_box == null:
		_unit_box = _box(Vector3.ONE)
	var mi := _mesh_child(body, mesh if mesh != null else _unit_box, _ruin_material, Transform3D(basis.scaled_local(size), at))
	mi.set_instance_shader_parameter(&"base_tint", tint)
	mi.set_instance_shader_parameter(&"top_y", top_y)
	mi.set_instance_shader_parameter(&"overgrowth", overgrowth)
	mi.set_instance_shader_parameter(&"windows", windows)
	mi.set_instance_shader_parameter(&"vine_reach", SHELL_VINE_REACH)


## Corona di un tratto di muro crollato: due o tre pezzi bassi, sfalsati, sulla cima,
## e qualche tondino di ferro storto che sporge. Vanno nei MultiMesh condivisi
## (`_build_ruin_details`), in coordinate mondo: nessun nodo in piu per rovina.
func _wall_crown(body: Node3D, wall_at: Vector3, along_x: bool, segment: float,
		wall_height: float, thickness: float, tint: Color) -> void:
	var top := wall_at + Vector3(0.0, wall_height * 0.5, 0.0)
	for i in _rng.randi_range(2, 3):
		var piece_length := segment * _rng.randf_range(0.18, 0.4)
		var piece_height := _rng.randf_range(CROWN_PIECE_HEIGHT.x, CROWN_PIECE_HEIGHT.y)
		var shift := _rng.randf_range(-0.5, 0.5) * (segment - piece_length)
		# Frammenti, non lastre: spessore ridotto, un po' fuori asse, tinta piu sporca.
		var piece_thickness := thickness * _rng.randf_range(0.55, 0.95)
		var across := _rng.randf_range(-0.5, 0.5) * (thickness - piece_thickness)
		var local := top + (Vector3(shift, piece_height * 0.5, across) if along_x else Vector3(across, piece_height * 0.5, shift))
		var scale := Vector3(piece_length, piece_height, piece_thickness) if along_x else Vector3(piece_thickness, piece_height, piece_length)
		var tilt := Basis(Vector3.FORWARD if along_x else Vector3.RIGHT, _rng.randf_range(-0.12, 0.12))
		var xform := body.transform * Transform3D(tilt.scaled_local(scale), local)
		# Il colore di istanza arriva allo shader senza la conversione sRGB degli
		# instance uniform `source_color`: si converte qui per avere la tinta del muro.
		var crown_color := Color(tint.srgb_to_linear() * _rng.randf_range(0.8, 0.95), 0.3)
		# La cima la spezza gia il modulo (O-10), che sta sotto questa quota: niente pezzi
		# sospesi. Si calcolano lo stesso, per non cambiare la sequenza del generatore.
		if crowns_from_modules:
			continue
		_append_instance(_crown_buffer, _crown_count, xform, crown_color)
		_crown_count += 1
		_crown_hosts.append(body)
	for i in _rng.randi_range(0, 2):
		var rebar_height := _rng.randf_range(REBAR_HEIGHT.x, REBAR_HEIGHT.y)
		var shift := _rng.randf_range(-0.45, 0.45) * segment
		# I tondini escono da dentro il muro: con la cima del modulo frastagliata partono
		# un terzo piu in basso, cosi spuntano dalle tacche invece di galleggiare.
		var sink := wall_height * 0.3 if crowns_from_modules else 0.0
		var local := top + (Vector3(shift, rebar_height * 0.5 - sink, 0.0) if along_x else Vector3(0.0, rebar_height * 0.5 - sink, shift))
		var lean := Basis.from_euler(Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35)))
		var xform := body.transform * Transform3D(lean.scaled_local(Vector3(0.07, rebar_height, 0.07)), local)
		_append_instance(_rebar_buffer, _rebar_count, xform, Color(0.16, 0.09, 0.05))
		_rebar_count += 1
		_rebar_hosts.append(body)


func _build_props() -> void:
	var min_distance := start_clear_radius * 0.6
	for i in car_count:
		var spot: Variant = _find_free_spot(Vector2(2.3, 2.3), 1.0, min_distance)
		if spot != null:
			_car(Vector3(spot.x, 0.0, spot.y), _rng.randf_range(0.0, 360.0))
			_reserve(_rect_around(spot, Vector2(2.3, 2.3)))
	for i in rubble_count:
		var spot: Variant = _find_free_spot(Vector2(2.4, 2.4), 1.0, min_distance)
		if spot != null:
			_rubble(Vector3(spot.x, 0.0, spot.y), _rng.randf_range(1.5, 2.4))
			_reserve(_rect_around(spot, Vector2(2.4, 2.4)))
	for i in barrier_count:
		var spot: Variant = _find_free_spot(Vector2(1.6, 1.6), 0.5, min_distance)
		if spot != null:
			_barrier(Vector3(spot.x, 0.0, spot.y), _rng.randf_range(0.0, 180.0))
			_reserve(_rect_around(spot, Vector2(1.6, 1.6)))
	for i in lamp_count:
		var spot: Variant = _find_free_spot(Vector2(0.5, 0.5), 0.5, min_distance)
		if spot != null:
			_lamp_post(Vector3(spot.x, 0.0, spot.y))
			_reserve(_rect_around(spot, Vector2(0.5, 0.5)))
	for i in tree_count:
		var scale := _rng.randf_range(0.9, 1.35)
		var spot: Variant = _find_free_spot(Vector2.ONE * scale, 0.5, min_distance)
		if spot != null:
			_tree(Vector3(spot.x, 0.0, spot.y), scale)
			_reserve(_rect_around(spot, Vector2.ONE * scale))
	for i in bush_count:
		var spot: Variant = _find_free_spot(Vector2(1.0, 1.0), 0.0, min_distance)
		if spot != null:
			_bush(Vector3(spot.x, 0.0, spot.y), _rng.randf_range(1.2, 2.2))


# --- Perimetro: la citta attorno al quartiere ---------------------------------------------

func _build_perimeter() -> void:
	_build_north_towers()
	_build_side_blocks()
	_build_west_wreck()
	# Sud: solo elementi bassi, la camera guarda da qui.
	_build_south_edge()


## Nord: torri alte in fila, con una seconda fila di skyline dietro.
func _build_north_towers() -> void:
	var ex := half_x()
	var ez := half_z()
	var x := -ex - 6.0
	var index := 0
	while x < ex + 6.0:
		var footprint := Vector2(_rng.randf_range(10.0, 15.0), _rng.randf_range(12.0, 16.0))
		_tower("NorthTower%d" % index, Vector2(x, -ez - 10.0 - _rng.randf_range(0.0, 3.0)), footprint,
			_rng.randf_range(18.0, 38.0), _rng.randf_range(0.45, 0.85))
		x += footprint.x + _rng.randf_range(6.0, 14.0)
		index += 1
	var skyline := maxi(7, int(ex / 15.0))
	for i in skyline:
		var sx := lerpf(-ex - 20.0, ex + 20.0, (i + 0.5) / skyline) + _rng.randf_range(-8.0, 8.0)
		_tower("Skyline%d" % i, Vector2(sx, -ez - _rng.randf_range(60.0, 110.0)), Vector2(_rng.randf_range(14.0, 18.0), _rng.randf_range(12.0, 16.0)),
			_rng.randf_range(40.0, 78.0), _rng.randf_range(0.6, 0.95), false)


## Est e ovest: edifici medi lungo i due lati.
func _build_side_blocks() -> void:
	var ex := half_x()
	var ez := half_z()
	for side in [-1.0, 1.0]:
		var z := -ez + 4.0
		var index := 0
		while z < ez - 10.0:
			var footprint := Vector2(_rng.randf_range(10.0, 14.0), _rng.randf_range(10.0, 16.0))
			_tower("%sBlock%d" % ["East" if side > 0.0 else "West", index],
				Vector2(side * (ex + 9.0 + footprint.x * 0.5), z + footprint.y * 0.5), footprint,
				_rng.randf_range(10.0, 22.0), _rng.randf_range(0.6, 0.9))
			z += footprint.y + _rng.randf_range(8.0, 18.0)
			index += 1


## A ovest un treno deragliato lungo il bordo.
func _build_west_wreck() -> void:
	var ex := half_x()
	var ez := half_z()
	var train_z := _rng.randf_range(-ez * 0.6, ez * 0.3)
	_carriage(Vector3(-ex - 4.0, 0.0, train_z - 13.5), 2.0, 0.0, Color(0.88, 0.68, 0.14))
	_carriage(Vector3(-ex - 3.4, 0.0, train_z), -7.0, 4.0, Color(0.72, 0.32, 0.12))
	# A -ex - 4.5: con l'imbardata di 24 gradi il muso entrava di ~2 m nell'area giocabile (R-30).
	_carriage(Vector3(-ex - 4.5, 0.0, train_z + 13.0), -24.0, 12.0, Color(0.88, 0.68, 0.14))
