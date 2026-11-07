class_name PlanarMovement
extends RefCounted
## Porta di UCharacterMovementComponent::CalcVelocity e ApplyVelocityBraking
## in modalita Walking (senza fluidi, root motion o requested velocity),
## ridotta al piano XZ e in metri.
##
## Riprodotta alla lettera perche il feel validato dal playtest dipende da essa:
## anche il dash, che imposta la velocita a ogni frame, passa per la frenata.

const BRAKING_SUBSTEP_TIME := 1.0 / 33.0
## BRAKE_TO_STOP_VELOCITY Unreal: 10 cm/s.
const BRAKE_TO_STOP_VELOCITY := 0.1
const MIN_TICK_TIME := 1e-6
## IsExceedingMaxSpeed tollera l'1% oltre la velocita massima.
const OVER_VELOCITY_PERCENT := 1.01

var max_speed := 6.0
var max_acceleration := 20.48
var braking_deceleration := 20.48
var ground_friction := 8.0
var braking_friction_factor := 2.0


func configure(tuning: PlayerTuning) -> void:
	max_speed = UnrealSpace.length(tuning.planar_move_speed_cm)
	max_acceleration = UnrealSpace.length(tuning.move_acceleration_cm)
	braking_deceleration = UnrealSpace.length(tuning.move_deceleration_cm)
	ground_friction = tuning.ground_friction
	braking_friction_factor = tuning.braking_friction_factor


## [param input]: direzione planare con modulo 0..1, come AddMovementInput.
## [param speed_multiplier]: scala MaxWalkSpeed (penalita terreno).
## Restituisce la nuova velocita planare (y = 0).
func calc_velocity(velocity: Vector3, input: Vector3, delta: float, speed_multiplier := 1.0) -> Vector3:
	velocity.y = 0.0
	input.y = 0.0
	var speed_limit := maxf(max_speed * speed_multiplier, 0.0)
	var acceleration := input.limit_length(1.0) * max_acceleration
	var analog := acceleration.length() / max_acceleration if max_acceleration > 0.0 else 0.0
	var max_input_speed := speed_limit * analog
	var zero_acceleration := acceleration.is_zero_approx()
	var over_max := _is_exceeding(velocity, speed_limit)

	if zero_acceleration or over_max:
		var old_velocity := velocity
		velocity = _apply_braking(velocity, delta)
		if over_max and velocity.length_squared() < speed_limit * speed_limit \
				and acceleration.dot(old_velocity) > 0.0:
			velocity = old_velocity.normalized() * speed_limit
	else:
		# Sterzata per attrito: la velocita ruota verso la direzione richiesta.
		var direction := acceleration.normalized()
		var speed := velocity.length()
		velocity -= (velocity - direction * speed) * minf(delta * ground_friction, 1.0)

	if not zero_acceleration:
		var new_max := velocity.length() if _is_exceeding(velocity, max_input_speed) else max_input_speed
		velocity += acceleration * delta
		velocity = velocity.limit_length(new_max)

	return velocity


func _is_exceeding(velocity: Vector3, limit: float) -> bool:
	limit = maxf(limit, 0.0)
	return velocity.length_squared() > limit * limit * OVER_VELOCITY_PERCENT


func _apply_braking(velocity: Vector3, delta: float) -> Vector3:
	if velocity.is_zero_approx() or delta < MIN_TICK_TIME:
		return velocity

	var friction := maxf(ground_friction * maxf(braking_friction_factor, 0.0), 0.0)
	var deceleration := maxf(braking_deceleration, 0.0)
	var zero_friction := is_zero_approx(friction)
	var zero_braking := is_zero_approx(deceleration)
	if zero_friction and zero_braking:
		return velocity

	var old_velocity := velocity
	var max_step := clampf(BRAKING_SUBSTEP_TIME, 1.0 / 75.0, 1.0 / 20.0)
	var reverse_acceleration := Vector3.ZERO if zero_braking else -deceleration * velocity.normalized()
	var remaining := delta
	while remaining >= MIN_TICK_TIME:
		var step := minf(max_step, remaining * 0.5) \
			if remaining > max_step and not zero_friction else remaining
		remaining -= step
		velocity += (-friction * velocity + reverse_acceleration) * step
		if velocity.dot(old_velocity) <= 0.0:
			return Vector3.ZERO

	var speed_squared := velocity.length_squared()
	if speed_squared <= 1e-8 or (not zero_braking and speed_squared <= BRAKE_TO_STOP_VELOCITY * BRAKE_TO_STOP_VELOCITY):
		return Vector3.ZERO
	return velocity
