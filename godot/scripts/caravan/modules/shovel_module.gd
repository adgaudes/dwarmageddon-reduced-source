class_name ShovelModule
extends MachineModule
## Pala (spec D-093, Sezione 1): ogni `shovel_interval` secondi (diviso per la forza della
## macchina, scelta 4 del piano B) alza un argine fra il nemico vivo piu vicino entro
## `shovel_reach` e la macchina, a `shovel_gap` da lui: un disco di `shovel_radius` portato a
## `shovel_height` sopra la base (`push_level`). Solo in un punto libero (`clear_spot`), dove il
## suolo e piu basso dell'argine, e per `shovel_cost` rottami dai Cassoni funzionanti, purche ne
## restino `repair_cost` (la riserva per una riparazione). Con la Betoniera mobile (Pala e Cassone
## nella stessa macchina, scelta 7 di D-093) l'argine e gratis e senza riserva.

## Secondi al prossimo argine; a 0 lavora al primo passo.
var _shovel_left := 0.0


func tick(delta: float) -> void:
	_shovel_left -= delta
	if _shovel_left > TIMER_EPSILON:
		return
	_shovel_left = interval()
	if terrain_field == null or write_queue == null:
		return
	var tuning := caravan.tuning
	var enemy := nearest_enemy(tuning.shovel_reach)
	if enemy == null:
		return
	var spot: Variant = point_toward(enemy.global_position, machine.global_position, tuning.shovel_gap)
	if spot == null:
		return
	var point: Vector3 = spot
	var target := terrain_field.base_height_at(point) + tuning.shovel_height
	if not clear_spot(point, tuning.shovel_radius) or terrain_field.height_at(point) >= target - 0.05:
		return
	# `level` abbassa anche: niente argine dove una parte del disco e gia piu alta.
	if terrain_field.highest_bump(point, tuning.shovel_radius, tuning.shovel_height) != null:
		return
	if not machine.has_combo(&"mobile_mixer") and (caravan.working_carried() < tuning.shovel_cost + tuning.repair_cost
			or not caravan.pay(tuning.shovel_cost)):
		return
	write_queue.push_level(point, tuning.shovel_radius, target)
	WeaponFx.dust(fx_parent(), Vector3(point.x, terrain_field.height_at(point), point.z), WeaponFx.EARTH, 0.5, 10,
		tuning.shovel_radius, true)
	print("PROTOTYPE01_SHOVEL_BANK x=%.1f z=%.1f" % [point.x, point.z])


## Secondi fra due argini: `shovel_interval` diviso per la forza.
func interval() -> float:
	return caravan.tuning.shovel_interval / power


## Lama gialla inclinata su due bracci scuri, sul muso del pianale.
func build_part() -> Node3D:
	var part := Node3D.new()
	part.position = Vector3(0.0, 0.32, -0.5)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.14, 0.15)
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.68, 0.08)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.06, 0.06, 0.3)
		arm.mesh = arm_mesh
		arm.material_override = dark
		arm.position = Vector3(side * 0.22, 0.05, 0.1)
		part.add_child(arm)
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.7, 0.26, 0.05)
	blade.mesh = blade_mesh
	blade.material_override = yellow
	blade.rotation = Vector3(deg_to_rad(-20.0), 0.0, 0.0)
	part.add_child(blade)
	return part
