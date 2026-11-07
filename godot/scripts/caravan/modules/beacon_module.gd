class_name BeaconModule
extends MachineModule
## Faro (spec D-093, Sezione 1): il faro che il compagno portava sempre (D-058), ora il modulo
## di una macchina. Una sorgente di LightField centrata sulla macchina, di raggio
## `beacon_radius` piu `beacon_radius_per_level` per livello del tipo (carta Faro), e la sua
## OmniLight3D `BeaconLight`, che ArenaRun accende col fattore di notte (Caravan.beacon_lights).
## Di giorno resta acceso: la luce la nasconde il fattore. Spento: raggio 0 e luce nascosta.

## Id della sorgente in `light_field`, -1 finche non e registrata.
var light_id := -1
## Figlia diretta del modulo (non del pezzo): ne layer visivo ne telaio la toccano.
var light: OmniLight3D


func _init() -> void:
	# Le impostazioni della torcia di ArenaRun (`_make_game_light`).
	light = OmniLight3D.new()
	light.name = "BeaconLight"
	light.position = Vector3(0.0, 1.6, 0.0)
	light.light_color = Color(1.0, 0.9, 0.72)
	light.shadow_enabled = false
	light.visible = false
	add_child(light)


## Raggio logico della luce al livello corrente, per la forza della macchina (0 senza la taratura
## della run).
func radius() -> float:
	if run_tuning == null:
		return 0.0
	return (run_tuning.beacon_radius + run_tuning.beacon_radius_per_level * level) * power


## Idempotente (la carovana la richiama quando arrivano i servizi): registra la sorgente la
## prima volta, poi ne aggiorna il raggio. Spento non illumina.
func apply_level(new_level: int) -> void:
	super.apply_level(new_level)
	if not active or light_field == null or run_tuning == null or machine == null:
		return
	if light_id == -1:
		light_id = light_field.add_source(machine, radius())
	else:
		light_field.set_radius(light_id, radius())


func _on_active_changed(on: bool) -> void:
	if on:
		apply_level(level)
		return
	light.visible = false
	if light_field != null and light_id != -1:
		light_field.set_radius(light_id, 0.0)


func _exit_tree() -> void:
	if light_field != null and light_id != -1:
		light_field.remove_source(light_id)
		light_id = -1


## Palo scuro con la lanterna in cima, al centro del pianale.
func build_part() -> Node3D:
	var part := Node3D.new()
	part.position = Vector3(0.0, 0.36, 0.1)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.14, 0.15)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.86, 0.5)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.86, 0.5)
	glass.emission_energy_multiplier = 1.5
	part.add_child(_cylinder(0.12, 0.12, 0.06, 0.03, dark))
	part.add_child(_cylinder(0.035, 0.035, 0.95, 0.5, dark))
	part.add_child(_cylinder(0.11, 0.11, 0.18, 1.05, glass))
	part.add_child(_cylinder(0.02, 0.14, 0.08, 1.18, dark))
	return part


static func _cylinder(top: float, bottom: float, height: float, y: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = Vector3(0.0, y, 0.0)
	return node
