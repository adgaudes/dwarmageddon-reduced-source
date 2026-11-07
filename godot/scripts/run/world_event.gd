class_name WorldEvent
extends Node3D
## Base degli eventi del mondo (terremoto, treno; D-097): niente orari fissi. ArenaRun
## chiede a WorldEventScheduler quanti eventi e quando, secondo le impostazioni di
## Gameplay, e consegna a ogni evento i suoi istanti con `schedule()`. L'evento resta
## fermo finche non arriva `next_at`, poi passa all'istante successivo o si spegne.

## Secondi di livello del prossimo evento; INF = nessuno in programma.
var next_at := INF
var _queued: Array[float] = []


## Tipo dell'evento per il pianificatore e le impostazioni (`&"quake"`, `&"train"`).
func event_kind() -> StringName:
	return &""


## Programma gli eventi agli istanti [param times] (secondi di livello); vuoto = nessuno.
func schedule(times: Array[float]) -> void:
	_queued = times.duplicate()
	_queued.sort()
	_advance_schedule()


## Istanti ancora da venire dopo `next_at`.
func queued_times() -> Array[float]:
	return _queued.duplicate()


func seconds_to_next(elapsed: float) -> float:
	return next_at - elapsed


## Finito (o saltato) un evento: si passa al prossimo istante in programma.
func _advance_schedule() -> void:
	next_at = _queued.pop_front() if not _queued.is_empty() else INF
