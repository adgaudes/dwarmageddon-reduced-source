class_name WelderModule
extends MachineModule
## Saldatore (spec D-093, Sezione 1): ogni `welder_interval` secondi +1 PV alla macchina non
## guasta piu danneggiata entro `welder_range` (lui escluso, la prima della carovana a pari
## danno). Una guasta che resta in raggio `welder_broken_seconds` secondi riparte gratis con
## `repair_health_fraction` della vita; il tempo di una guasta che esce dal raggio torna a zero.
## Entrambi i tempi sono divisi per la forza della macchina (scelta 4 del piano B).

## Altezza delle scintille sulla macchina saldata.
const SPARK_HEIGHT := 0.6

## Secondi alla prossima saldatura; a 0 lavora al primo passo.
var _heal_left := 0.0
## Secondi passati in raggio da ogni macchina guasta.
var _broken_elapsed: Dictionary[Machine, float] = {}


func tick(delta: float) -> void:
	var tuning := caravan.tuning
	var here := machine.global_position
	for other in caravan.machines:
		if other == machine:
			continue
		if not other.is_broken() or Machine.planar_distance(other.global_position, here) > tuning.welder_range:
			_broken_elapsed.erase(other)
			continue
		var elapsed: float = _broken_elapsed.get(other, 0.0) + delta
		if elapsed < broken_seconds() - TIMER_EPSILON:
			_broken_elapsed[other] = elapsed
			continue
		_broken_elapsed.erase(other)
		var module_id := other.primary_module_id()
		other.repair(tuning.repair_health_fraction)
		_sparks(other)
		print("PROTOTYPE01_WELDER_FIX module=%s" % module_id)
	_heal_left -= delta
	if _heal_left > TIMER_EPSILON:
		return
	_heal_left = heal_interval()
	var target: Machine = null
	var most := 0
	for other in caravan.machines:
		if other == machine or other.is_broken() or Machine.planar_distance(other.global_position, here) > tuning.welder_range:
			continue
		if other.max_health - other.health > most:
			most = other.max_health - other.health
			target = other
	if target != null:
		target.heal(1)
		_sparks(target)


## Secondi fra due saldature: `welder_interval` diviso per la forza.
func heal_interval() -> float:
	return caravan.tuning.welder_interval / power


## Secondi in raggio dopo cui una guasta riparte: `welder_broken_seconds` diviso per la forza.
func broken_seconds() -> float:
	return caravan.tuning.welder_broken_seconds / power


## Dimentica [param other] (macchina tolta dalla carovana: `Caravan.remove_machine`).
func forget(other: Machine) -> void:
	_broken_elapsed.erase(other)


## Spento (macchina guasta) dimentica le guaste che stava saldando.
func _on_active_changed(_on: bool) -> void:
	_broken_elapsed.clear()


func _sparks(other: Machine) -> void:
	WeaponFx.sparks(fx_parent(), other.global_position + Vector3(0.0, SPARK_HEIGHT, 0.0), WeaponFx.SPARK, 8, 4.0, true)


## Bombola rossa e torcia scura col becco acceso, sul retro del pianale.
func build_part() -> Node3D:
	var part := Node3D.new()
	part.position = Vector3(0.0, 0.36, 0.3)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.7, 0.1, 0.08)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.14, 0.15)
	var flame := StandardMaterial3D.new()
	flame.albedo_color = Color(0.5, 0.8, 1.0)
	flame.emission_enabled = true
	flame.emission = Color(0.5, 0.8, 1.0)
	flame.emission_energy_multiplier = 2.0
	var tank := MeshInstance3D.new()
	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 0.11
	tank_mesh.bottom_radius = 0.11
	tank_mesh.height = 0.45
	tank.mesh = tank_mesh
	tank.material_override = red
	tank.position = Vector3(-0.15, 0.22, 0.0)
	part.add_child(tank)
	var torch := MeshInstance3D.new()
	var torch_mesh := BoxMesh.new()
	torch_mesh.size = Vector3(0.06, 0.06, 0.34)
	torch.mesh = torch_mesh
	torch.material_override = dark
	torch.position = Vector3(0.15, 0.3, -0.05)
	part.add_child(torch)
	var tip := MeshInstance3D.new()
	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(0.05, 0.05, 0.06)
	tip.mesh = tip_mesh
	tip.material_override = flame
	tip.position = Vector3(0.15, 0.3, -0.25)
	part.add_child(tip)
	return part
