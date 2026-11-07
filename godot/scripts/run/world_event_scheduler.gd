class_name WorldEventScheduler
extends RefCounted
## Sceglie a caso quali eventi del mondo arrivano in un livello e quando (D-097): il
## proprietario vuole eventi casuali, non a copione, in numero scelto nelle impostazioni.
## Logica pura: dato il seme si ripete uguale (gate e bot), ma il seme della run e casuale.


## [param count] eventi fra [param start] e [param end] secondi, distanziati di almeno
## [param min_gap] (meno se la finestra non basta), ognuno di un tipo a caso fra
## [param kinds]. Restituisce `[{at: float, kind: StringName}]` in ordine di tempo.
static func plan(kinds: Array[StringName], count: int, start: float, end: float, min_gap: float,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if kinds.is_empty() or count <= 0 or end <= start:
		return events
	var span := end - start
	var gap := minf(min_gap, span / float(count)) if count > 1 else 0.0
	# Istanti casuali nello spazio libero, poi ognuno spostato dei distacchi che lo precedono:
	# la distribuzione resta uniforme e nessuna coppia scende sotto `gap`.
	var free := span - gap * float(count - 1)
	var offsets: Array[float] = []
	for i in count:
		offsets.append(rng.randf_range(0.0, free))
	offsets.sort()
	for i in count:
		events.append({at = start + offsets[i] + gap * float(i), kind = kinds[rng.randi_range(0, kinds.size() - 1)]})
	return events


## Gli istanti di [param events] del tipo [param kind].
static func times_of(events: Array[Dictionary], kind: StringName) -> Array[float]:
	var times: Array[float] = []
	for event in events:
		if event.kind == kind:
			times.append(event.at)
	return times
