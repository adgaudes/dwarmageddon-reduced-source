class_name HeightFlowField
extends RefCounted
## SPIKE: campo di percorso sul terreno a rilievo continuo. Griglia grossa (CELL metri)
## coi centri sui vertici di HeightTerrain; una visita a costo crescente dal bersaglio
## (Dijkstra a code a secchi, costi interi come in PathField) dice a ogni casella verso
## quale vicina andare e quanta strada manca, in metri. Un passaggio fra due caselle e
## ammesso se, vertice per vertice lungo il tratto, chi cammina non trova mai una salita
## oltre `max_grade`: lo stesso criterio di [method HeightTerrain.slide_move], cosi il
## campo non promette strade che il rottamatore poi non riesce a fare. In discesa si
## passa sempre, quindi in una fossa ripida si entra ma non si esce.
## Codice di prova: non e usato dal livello vero.

## Lato di una casella del campo, in metri: multiplo intero di HeightTerrain.CELL.
const CELL := 1.5
## Vertici del terreno per lato di casella: i sottopassi con cui si controlla la pendenza.
const SUBSTEPS := int(CELL / HeightTerrain.CELL)
## Costi interi in decimi di casella: le distanze in metri ne derivano.
const ORTHO_COST := 10
const DIAG_COST := 14
const UNREACHED := 0x7fffffff
## Prima i quattro lati, poi le diagonali.
const DX: PackedInt32Array = [1, -1, 0, 0, 1, 1, -1, -1]
const DZ: PackedInt32Array = [0, 0, 1, -1, 1, -1, 1, -1]

var side := 0
## Per casella: indice della casella successiva verso il bersaglio, -1 se non ci si arriva.
var next := PackedInt32Array()
## Per casella: metri di strada fino al bersaglio, -1 se non ci si arriva.
var distance := PackedFloat32Array()

var _half := 0.0


## Ricalcola il campo verso [param goal]. [param max_grade]: salita massima (m per m).
## [param window_m] > 0 limita la visita a un quadrato di quel semilato attorno al
## bersaglio (U-02): fuori le caselle restano senza strada e chi cammina punta dritto.
func rebuild(terrain: HeightTerrain, goal: Vector3, max_grade: float, window_m := 0.0) -> void:
	assert(is_equal_approx(SUBSTEPS * HeightTerrain.CELL, CELL), "CELL deve essere multiplo della maglia del terreno")
	_half = terrain.half_extent()
	var res := terrain.resolution
	# Solo le caselle il cui vertice sta nella maglia: con un lato non multiplo di CELL
	# (es. 100 m) l'ultima striscia di terreno resta fuori dal campo e `cell_of` la
	# riporta sulla casella di bordo (U-01).
	side = (res - 1) / SUBSTEPS + 1
	assert((side - 1) * SUBSTEPS < res, "l'ultima casella deve avere il vertice nella maglia")
	var count := side * side
	next.resize(count)
	next.fill(-1)
	distance.resize(count)
	distance.fill(-1.0)
	var heights := terrain.heights
	var max_rise := max_grade * HeightTerrain.CELL
	var max_rise_diagonal := max_rise * 1.41421356

	var dist := PackedInt32Array()
	dist.resize(count)
	dist.fill(UNREACHED)
	var buckets: Array[PackedInt32Array] = []
	var bucket_count := DIAG_COST + 1
	buckets.resize(bucket_count)
	for b in bucket_count:
		buckets[b] = PackedInt32Array()
	var start := cell_of(goal)
	var min_x := 0
	var min_z := 0
	var max_x := side - 1
	var max_z := side - 1
	if window_m > 0.0:
		var span := int(ceil(window_m / CELL))
		min_x = maxi(start % side - span, 0)
		max_x = mini(start % side + span, side - 1)
		min_z = maxi(start / side - span, 0)
		max_z = mini(start / side + span, side - 1)
	dist[start] = 0
	next[start] = start
	buckets[0].append(start)
	var pending := 1
	var level := 0
	while pending > 0:
		var bucket := buckets[level % bucket_count]
		if bucket.is_empty():
			level += 1
			continue
		buckets[level % bucket_count] = PackedInt32Array()
		for current in bucket:
			pending -= 1
			if dist[current] != level:
				continue
			var cx := current % side
			var cz := current / side
			for k in 8:
				var ox := DX[k]
				var oz := DZ[k]
				var nx := cx + ox
				var nz := cz + oz
				if nx < min_x or nz < min_z or nx > max_x or nz > max_z:
					continue
				var neighbor := nz * side + nx
				var diagonal := ox != 0 and oz != 0
				var c := level + (DIAG_COST if diagonal else ORTHO_COST)
				if dist[neighbor] <= c:
					continue
				# Si cammina dalla vicina verso `current`, un vertice del terreno alla volta.
				var rise := max_rise_diagonal if diagonal else max_rise
				var step := -oz * res - ox
				var index := nz * SUBSTEPS * res + nx * SUBSTEPS
				var previous := heights[index]
				var passable := true
				for s in SUBSTEPS:
					index += step
					var height := heights[index]
					if height - previous > rise:
						passable = false
						break
					previous = height
				if not passable:
					continue
				dist[neighbor] = c
				next[neighbor] = current
				buckets[c % bucket_count].append(neighbor)
				pending += 1
	for i in count:
		if dist[i] != UNREACHED:
			distance[i] = dist[i] * (CELL / ORTHO_COST)


func cell_of(point: Vector3) -> int:
	var x := clampi(int(round((point.x + _half) / CELL)), 0, side - 1)
	var z := clampi(int(round((point.z + _half) / CELL)), 0, side - 1)
	return z * side + x


## Distanza fra due caselle in caselle (scacchiera): quante ne separa il giocatore
## dall'ultimo bersaglio calcolato.
func cells_apart(a: int, b: int) -> int:
	if a < 0 or b < 0 or side <= 0:
		return 0x7fffffff
	return maxi(absi(a % side - b % side), absi(a / side - b / side))


func center_of(cell: int) -> Vector3:
	return Vector3((cell % side) * CELL - _half, 0.0, (cell / side) * CELL - _half)


## Direzione in piano (unitaria) da seguire da [param point]: quella fra il centro della
## sua casella e quello della successiva. Zero se da li non si arriva o si e arrivati.
func direction_at(point: Vector3) -> Vector3:
	var cell := cell_of(point)
	if next[cell] < 0:
		return Vector3.ZERO
	var toward := center_of(next[cell]) - center_of(cell)
	return toward.normalized() if toward.length_squared() > 0.0001 else Vector3.ZERO
