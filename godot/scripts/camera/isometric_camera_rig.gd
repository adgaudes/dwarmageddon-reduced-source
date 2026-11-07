@tool
class_name IsometricCameraRig
extends Node3D
## Camera isometrica fissa: porta di SpringArm + Camera del personaggio Unreal.
##
## Rotazione assoluta (top_level), nessuna collisione, nessuna rotazione libera.
## Segue soltanto la posizione del bersaglio, come il braccio Unreal agganciato
## al centro della capsula.
##
## Tre distanze (D-078, restyling 2026-10-11): vicina 11 m, normale 15 m, lontana 20 m.
## `camera_zoom_cycle` (Y, C) le cicla, `camera_zoom_in`/`camera_zoom_out` (rotellina)
## le scorrono; il passaggio e interpolato (circa 0,25 s). Pitch e FOV non cambiano.

## Emesso quando si sceglie una distanza (anche se l'interpolazione deve ancora arrivarci).
signal distance_changed(index: int, arm_m: float)

const DISTANCE_PRESETS_CM: Array[float] = [1100.0, 1500.0, 2000.0]
const DEFAULT_DISTANCE_INDEX := 1
## Costante dell'interpolazione esponenziale del braccio (1/s): a 12 arriva in circa 0,25 s.
const DISTANCE_SMOOTHING := 12.0

## Braccio Unreal 1500 uu.
@export var arm_length_cm := 1500.0:
	set(value):
		arm_length_cm = value
		# Un valore imposto da fuori (editor, test) vale anche come bersaglio: niente rimbalzo.
		_arm_target_cm = value
		if _camera != null:
			_apply()
## Pitch Unreal del braccio, in gradi.
@export var pitch_degrees := -55.0:
	set(value):
		pitch_degrees = value
		if _camera != null:
			_apply()
## FOV orizzontale: default di UCameraComponent.
@export var horizontal_fov_degrees := 90.0:
	set(value):
		horizontal_fov_degrees = value
		if _camera != null:
			_apply()
@export var target: Node3D

## Indice del preset di distanza corrente (0 vicina, 1 normale, 2 lontana).
var distance_index := DEFAULT_DISTANCE_INDEX

var _camera: Camera3D
var _arm_target_cm := 1500.0


func _ready() -> void:
	# Nell'editor il nodo resta com'e nel .tscn: top_level, interpolazione e
	# trasformazione scritti qui finirebbero nella scena al salvataggio (P-06).
	if Engine.is_editor_hint():
		return
	top_level = true
	# Il rig si muove in _process: niente interpolazione propria, legge quella del bersaglio.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera = get_node_or_null(^"Camera") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera"
		add_child(_camera)
	_arm_target_cm = arm_length_cm
	_apply()
	_camera.make_current()
	print("PROTOTYPE01_CAMERA_READY arm=%.1fm pitch=%.0f hfov=%.0f"
		% [UnrealSpace.length(arm_length_cm), pitch_degrees, horizontal_fov_degrees])


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_equal_approx(arm_length_cm, _arm_target_cm):
		var target_cm := _arm_target_cm
		if absf(arm_length_cm - target_cm) < 1.0:
			arm_length_cm = target_cm
		else:
			var k := 1.0 - exp(-DISTANCE_SMOOTHING * delta)
			# Il setter riallinea il bersaglio: lo si ripristina dopo.
			arm_length_cm = lerpf(arm_length_cm, target_cm, k)
			_arm_target_cm = target_cm
	if target != null:
		global_position = target.get_global_transform_interpolated().origin


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed(&"camera_zoom_cycle"):
		cycle_distance()
	elif event.is_action_pressed(&"camera_zoom_in"):
		set_distance_index(distance_index - 1)
	elif event.is_action_pressed(&"camera_zoom_out"):
		set_distance_index(distance_index + 1)


## Sceglie un preset; con `instant` il braccio ci va subito (avvio, impostazioni caricate).
func set_distance_index(index: int, instant := false) -> void:
	var clamped := clampi(index, 0, DISTANCE_PRESETS_CM.size() - 1)
	var changed := clamped != distance_index or not is_equal_approx(_arm_target_cm, DISTANCE_PRESETS_CM[clamped])
	distance_index = clamped
	if instant:
		arm_length_cm = DISTANCE_PRESETS_CM[clamped]
	else:
		_arm_target_cm = DISTANCE_PRESETS_CM[clamped]
	if changed:
		distance_changed.emit(distance_index, UnrealSpace.length(DISTANCE_PRESETS_CM[distance_index]))


func cycle_distance() -> void:
	set_distance_index((distance_index + 1) % DISTANCE_PRESETS_CM.size())


## Lunghezza attuale del braccio in metri (durante l'interpolazione e intermedia).
func current_arm_m() -> float:
	return UnrealSpace.length(arm_length_cm)


## Lunghezza del preset scelto in metri.
func target_arm_m() -> float:
	return UnrealSpace.length(_arm_target_cm)


func _apply() -> void:
	if Engine.is_editor_hint():
		return
	# Rig orientato verso -Z (forward Godot = +X Unreal, yaw 0).
	global_basis = Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), 0.0, 0.0))
	_camera.position = Vector3(0.0, 0.0, UnrealSpace.length(arm_length_cm))
	_camera.basis = Basis.IDENTITY
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = horizontal_fov_degrees
	if target != null:
		global_position = target.global_position
