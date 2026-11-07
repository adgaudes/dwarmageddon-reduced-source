class_name UnrealSpace
extends RefCounted
## Unico punto di conversione da spazio Unreal a spazio Godot (R-G6).
##
## Unreal: centimetri, Z-up, X-forward, Y-right.
## Godot:  metri,     Y-up, -Z-forward, X-right.
## Mappatura assi: UE X -> Godot -Z, UE Y -> Godot +X, UE Z -> Godot +Y.

const CM_TO_M := 0.01


## Converte una lunghezza scalare (cm -> m).
static func length(unreal_cm: float) -> float:
	return unreal_cm * CM_TO_M


## Converte una posizione o un'estensione (cm, assi Unreal) in metri e assi Godot.
static func position(unreal_cm: Vector3) -> Vector3:
	return Vector3(unreal_cm.y, unreal_cm.z, -unreal_cm.x) * CM_TO_M


## Inversa di position(): metri e assi Godot -> centimetri e assi Unreal.
static func to_unreal_position(godot_m: Vector3) -> Vector3:
	return Vector3(-godot_m.z, godot_m.x, godot_m.y) / CM_TO_M


## Direzione "forward" di un FRotator Unreal (pitch, yaw in gradi), in assi Godot.
static func rotator_forward(pitch_deg: float, yaw_deg: float) -> Vector3:
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	var unreal_dir := Vector3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch))
	return Vector3(unreal_dir.y, unreal_dir.z, -unreal_dir.x)
