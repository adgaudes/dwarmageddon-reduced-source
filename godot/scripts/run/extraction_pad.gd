class_name ExtractionPad
extends Node3D
## La piazzola di estrazione (D-076, idea 3 di FEATURE_IDEAS.md): battuto il boss il
## livello non finisce subito. Il mezzo di estrazione atterra solo su una piazzola piana
## attorno al giocatore (sul rilievo continuo, D-085: un **disco di `radius_m`** con
## dislivello sotto `tolerance_m`), tenuta
## **integra e occupata per `hold_seconds`** mentre l'orda continua ad arrivare. La
## piazzola segue il giocatore: e lui a scegliere dove, spianando con il tool. Se il suolo
## cambia o il giocatore si sposta su un punto non piano, il conto riparte.
##
## A terra un anello mostra la piazzola: verde
## quando e integra, rosso quando no.
## Come il treno e il terremoto non ha un passo fisico proprio: `ArenaRun` lo fa avanzare.

signal extraction_started
signal pad_changed(intact: bool)
signal extraction_completed

const INTACT_COLOR := Color(0.25, 0.9, 0.55, 0.35)
const BROKEN_COLOR := Color(0.95, 0.3, 0.2, 0.35)
const LANDING_COLOR := Color(0.6, 0.85, 1.0)

## Rilievo continuo (D-085): la piazzola e un disco piano.
@export var terrain_field: TerrainField
@export var player: PlayerCharacter
@export var hud: RunHud

## Secondi di piazzola integra e occupata prima dell'atterraggio.
var hold_seconds := 8.0
## Rilievo: raggio del disco e dislivello massimo ammesso dentro.
var radius_m := 3.0
var tolerance_m := 0.35

var active := false
var intact := false
var held := 0.0
## Rilievo: centro del disco (sotto il giocatore).
var center_point := Vector3.ZERO
var _ring: BrushPreview


func is_active() -> bool:
	return active


## Rilievo: il disco attorno a [param point] e piano entro la tolleranza.
func is_flat_at(point: Vector3) -> bool:
	return terrain_field != null and terrain_field.is_flat(point, radius_m, tolerance_m)


func begin() -> void:
	active = true
	held = 0.0
	intact = false
	_ensure_ring()
	print("PROTOTYPE01_EXTRACTION_CALLED hold=%.1f" % hold_seconds)
	extraction_started.emit()


## Un passo, dal tempo di livello.
func advance(delta: float) -> void:
	if not active or terrain_field == null or player == null:
		return
	center_point = Vector3(player.global_position.x, 0.0, player.global_position.z)
	var now := is_flat_at(center_point)
	if now != intact:
		intact = now
		if not intact:
			held = 0.0
		pad_changed.emit(intact)
	if intact:
		held += delta
	_update_marker()
	if hud != null:
		if intact:
			hud.set_event_warning("ESTRAZIONE: TIENI LA PIAZZOLA", Vector3.FORWARD, hold_seconds - held,
				RunHud.EXTRACTION_COLOR, false, RunHud.WarningPriority.EXTRACTION)
		else:
			var hint := "ESTRAZIONE: SPIANA UN DISCO DI %d M" % int(round(radius_m * 2.0))
			hud.set_event_warning(hint, Vector3.FORWARD, hold_seconds, RunHud.EXTRACTION_COLOR, false,
				RunHud.WarningPriority.EXTRACTION)
	if held >= hold_seconds:
		_complete()


func _complete() -> void:
	active = false
	if hud != null:
		hud.clear_event_warning(RunHud.WarningPriority.EXTRACTION)
	var at := Vector3(center_point.x, terrain_field.height_at(center_point), center_point.z)
	DebrisBurst.spawn(get_parent(), at + Vector3(0.0, 0.5, 0.0), LANDING_COLOR, 24, 6.0, 0.16)
	if _ring != null:
		_ring.hide_ring()
	print("PROTOTYPE01_EXTRACTION_DONE x=%.1f z=%.1f" % [at.x, at.z])
	extraction_completed.emit()


func _ensure_ring() -> void:
	if _ring == null:
		_ring = BrushPreview.new()
		_ring.name = "PadRing"
		add_child(_ring)


func _update_marker() -> void:
	if _ring != null:
		var at := Vector3(center_point.x, terrain_field.height_at(center_point) + 0.5, center_point.z)
		_ring.show_ring(at, radius_m, INTACT_COLOR if intact else BROKEN_COLOR)
