class_name PlayerTuning
extends Resource
## Parametri di tuning del personaggio, con i valori e le unita di
## APrototype01Character (centimetri, secondi, gradi). La conversione in metri
## avviene una sola volta tramite UnrealSpace (D-023).

## Nome mostrato quando si cambia preset in gioco.
@export var display_name := "Unreal"

@export_group("Movement")
## PlanarMoveSpeed, cm/s.
@export var planar_move_speed_cm := 600.0
## MoveAcceleration (MaxAcceleration), cm/s^2.
@export var move_acceleration_cm := 2048.0
## MoveDeceleration (BrakingDecelerationWalking), cm/s^2.
@export var move_deceleration_cm := 2048.0
## GroundFriction: default di UCharacterMovementComponent, mai modificato dal prototipo.
@export var ground_friction := 8.0
## BrakingFrictionFactor: default di UCharacterMovementComponent.
@export var braking_friction_factor := 2.0

## ActuationThreshold di UInputTriggerDown su IA_Move: modulo minimo dello stick.
@export var move_actuation_threshold := 0.5

@export_group("Aim")
@export var aim_stick_dead_zone := 0.2
@export var gamepad_aim_sensitivity := 1.0
@export var gamepad_aim_rotation_interp_speed := 10.0
@export var mouse_aim_rotation_interp_speed := 25.0
## Spostamento cumulativo minimo del mouse, in pixel, entro `mouse_aim_delta_window`
## per passare alla mira mouse: su Steam Deck trackpad, giroscopio e tocco generano
## movimenti di frazioni di pixel che non devono rubare la mira al controller (P-01).
@export var mouse_aim_delta_threshold := 6.0
## Finestra (s) in cui si somma lo spostamento del mouse; scaduta, si riparte da zero.
@export var mouse_aim_delta_window := 0.25
## Con il mouse fermo da almeno questi secondi, lo stick sinistro sopra la dead zone
## riporta la mira al controller anche senza toccare lo stick destro.
@export var mouse_aim_idle_seconds := 0.5

@export_group("Motion")
## Movimento procedurale del modello (ActorMotion), solo visivo. Inclinazione (rad)
## verso la direzione di marcia a piena velocita di cammino, tetto del rapporto di
## velocita (nel dash si piega di piu, non oltre lean_angle * lean_speed_cap) e
## velocita (1/s) con cui l'inclinazione insegue il movimento.
@export var lean_angle := 0.12
@export var lean_speed_cap := 1.8
@export var lean_rate := 14.0
## Dash: schiacciamento alla partenza e allungamento all'arrivo (frazione dell'altezza),
## durata dell'impulso (s). La larghezza compensa di meta, per conservare il volume a occhio.
@export var dash_squash := 0.2
@export var dash_stretch := 0.14
@export var dash_pulse_seconds := 0.13
## Rinculo della chiodatrice: durata (s), arretramento (m) e inclinazione (rad) opposti al colpo.
@export var recoil_seconds := 0.1
@export var recoil_back := 0.07
@export var recoil_tilt := 0.07
## Sussulto quando e colpito: durata (s), schiacciamento (frazione), arretramento (m), busto indietro (rad).
@export var flinch_seconds := 0.24
@export var flinch_squash := 0.14
@export var flinch_back := 0.1
@export var flinch_pitch := 0.16

@export_group("Terrain")
## TerrainToolRange: distanza davanti al personaggio del bersaglio terreno, cm (min 100).
@export var terrain_tool_range_cm := 480.0

@export_group("Dash")
## DashSpeed, cm/s.
@export var dash_speed_cm := 3000.0
@export var dash_duration := 0.18
## Misurato dall'attivazione del dash.
@export var dash_cooldown := 1.2
@export var dash_scale_multiplier := 1.15
## Colori lineari, come FLinearColor in Unreal.
@export var dash_color_linear := Color(0.1, 0.9, 1.0)
@export var dash_cooldown_color_linear := Color(0.4, 0.4, 0.4)
