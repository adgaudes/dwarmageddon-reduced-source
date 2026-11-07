class_name MagnetModule
extends MachineModule
## Calamita (spec D-093, Sezione 1): la macchina attira i frammenti di esperienza entro
## `magnet_radius`, piu `magnet_radius_per_level` per livello del tipo (Calamita potente), per la
## forza della macchina (scelta 4 di D-093).
## Spenta toglie l'attrattore: i frammenti in volo verso di lei scelgono un altro bersaglio.


## Raggio d'attrazione al livello corrente, per la forza.
func radius() -> float:
	if caravan == null or caravan.tuning == null:
		return 0.0
	return (caravan.tuning.magnet_radius + caravan.tuning.magnet_radius_per_level * level) * power


## Idempotente (la carovana la richiama quando arrivano i servizi): senza campo dei frammenti
## o spenta non attira.
func apply_level(new_level: int) -> void:
	super.apply_level(new_level)
	if active and is_instance_valid(xp_field) and machine != null:
		xp_field.set_attractor(machine, radius())


func _on_active_changed(on: bool) -> void:
	if on:
		apply_level(level)
	elif is_instance_valid(xp_field) and machine != null:
		xp_field.remove_attractor(machine)


func _exit_tree() -> void:
	if is_instance_valid(xp_field) and machine != null:
		xp_field.remove_attractor(machine)


## Ferro di cavallo rosso con le punte chiare, sul retro del pianale (la calamita del compagno).
func build_part() -> Node3D:
	var part := Node3D.new()
	part.position = Vector3(0.0, 0.55, 0.42)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.08, 0.06)
	var tip := StandardMaterial3D.new()
	tip.albedo_color = Color(0.8, 0.8, 0.82)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.1, 0.4, 0.1)
		arm.mesh = arm_mesh
		arm.material_override = red
		arm.position = Vector3(side * 0.14, 0.2, 0.0)
		part.add_child(arm)
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(0.11, 0.08, 0.11)
		cap.mesh = cap_mesh
		cap.material_override = tip
		cap.position = Vector3(side * 0.14, 0.42, 0.0)
		part.add_child(cap)
	var bridge := MeshInstance3D.new()
	var bridge_mesh := BoxMesh.new()
	bridge_mesh.size = Vector3(0.38, 0.1, 0.1)
	bridge.mesh = bridge_mesh
	bridge.material_override = red
	part.add_child(bridge)
	return part
