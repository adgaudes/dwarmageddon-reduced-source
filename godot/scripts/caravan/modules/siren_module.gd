class_name SirenModule
extends MachineModule
## Sirena (spec D-093, Sezione 1): ciclo di `siren_period` secondi; nei primi `siren_active`
## attira verso la macchina, a `siren_pull_speed` m/s (`Welder.pull_toward`), i rottamatori vivi
## entro `siren_range` per la forza della macchina (scelta 4 del piano B): non i boss
## (`self_driven`) ne i portatori in commissione. A ogni accensione il ciclo riparte dall'inizio.

## Secondi dall'inizio del ciclo.
var _cycle_time := 0.0


func tick(delta: float) -> void:
	var tuning := caravan.tuning
	if _cycle_time <= 0.0:
		print("PROTOTYPE01_SIREN_ON")
	if _cycle_time < tuning.siren_active - TIMER_EPSILON and is_instance_valid(director):
		var here := machine.global_position
		var reach := range_m()
		for enemy in director.enemies:
			if not is_instance_valid(enemy) or enemy.is_dead or enemy.self_driven or enemy.has_errand:
				continue
			if Machine.planar_distance(enemy.global_position, here) <= reach:
				Welder.pull_toward(enemy, here, tuning.siren_pull_speed)
	_cycle_time += delta
	if _cycle_time >= tuning.siren_period - TIMER_EPSILON:
		_cycle_time = 0.0


## Raggio d'attrazione: `siren_range` per la forza.
func range_m() -> float:
	return caravan.tuning.siren_range * power


## Vero nella parte attiva del ciclo (da accesa).
func is_attracting() -> bool:
	return active and caravan != null and _cycle_time < caravan.tuning.siren_active - TIMER_EPSILON


func _on_active_changed(_on: bool) -> void:
	_cycle_time = 0.0


## Tromba grigia con la bocca verso l'esterno e lampeggiante rosso, su un palo al centro.
func build_part() -> Node3D:
	var part := Node3D.new()
	part.position = Vector3(0.0, 0.36, 0.05)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.14, 0.15)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.6, 0.62, 0.64)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.95, 0.12, 0.08)
	lamp.emission_enabled = true
	lamp.emission = Color(0.95, 0.12, 0.08)
	lamp.emission_energy_multiplier = 1.5
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.035
	pole_mesh.bottom_radius = 0.035
	pole_mesh.height = 0.5
	pole.mesh = pole_mesh
	pole.material_override = dark
	pole.position = Vector3(0.0, 0.25, 0.0)
	part.add_child(pole)
	var horn := MeshInstance3D.new()
	var horn_mesh := CylinderMesh.new()
	horn_mesh.top_radius = 0.05
	horn_mesh.bottom_radius = 0.16
	horn_mesh.height = 0.3
	horn.mesh = horn_mesh
	horn.material_override = grey
	horn.position = Vector3(0.0, 0.5, -0.1)
	horn.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	part.add_child(horn)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.08
	beacon_mesh.height = 0.12
	beacon.mesh = beacon_mesh
	beacon.material_override = lamp
	beacon.position = Vector3(0.0, 0.62, 0.08)
	part.add_child(beacon)
	return part
