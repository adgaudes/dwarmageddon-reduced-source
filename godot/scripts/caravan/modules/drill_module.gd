class_name DrillModule
extends MachineModule
## Trivella (spec D-093, Sezione 1): ogni `drill_interval` secondi (diviso per la forza della
## macchina, scelta 4 del piano B), se una vena con rottami tocca il cerchio di `drill_reach`
## attorno alla macchina, ne estrae un rottame e lo posa a terra sul bordo della vena verso la
## macchina (accanto alla macchina se li non si passa), senza scrivere il terreno. Altrimenti
## scava una buca (`DigCharge.dig_crater`) a 1 m dal nemico vivo piu vicino entro `drill_reach`,
## verso la macchina: solo su suolo entro `drill_flat_tolerance` dalla base e in un punto libero
## (`clear_spot`).
## Combinazioni (scelta 7 di D-093). Estrattore (con la Calamita): dopo una buca i rottami a terra
## entro `extractor_radius` vanno nei Cassoni, se c'e posto; dopo una vena lo stesso attorno al
## rottame cavato. Ruspa (con la Pala): ogni `dozer_spacing` m percorsi un fossato dietro la
## macchina, oltre `keep_clear` da lei, e un argine alla sua destra, gratis, con le regole di
## `clear_spot`.

## Distanza della buca dal nemico, verso la macchina.
const HOLE_GAP_M := 1.0
## Il rottame della vena cade oltre il bordo di tanto, verso la macchina...
const DROP_OUTSIDE_M := 0.4
## ...o, se li non si passa, a tanto dalla macchina verso la vena.
const DROP_BESIDE_M := 0.6

## Oltre tanti `dozer_spacing` in un passo la macchina e stata spostata (ritorno al posto): la
## Ruspa riprende a misurare da li senza scavare.
const DOZER_JUMP := 3.0

## Secondi al prossimo colpo di trivella; a 0 lavora al primo passo.
var _drill_left := 0.0
## Ruspa: punto (della macchina) dell'ultimo fossato, da cui si misura il tratto; INF finche la
## Ruspa non lavora.
var _dozer_from := Vector3.INF


func tick(delta: float) -> void:
	_tick_dozer()
	_drill_left -= delta
	if _drill_left > TIMER_EPSILON:
		return
	_drill_left = interval()
	if terrain_field == null:
		return
	if not _drill_vein():
		_drill_hole()


## Secondi fra due colpi: `drill_interval` diviso per la forza.
func interval() -> float:
	return caravan.tuning.drill_interval / power


## Vero se una vena con rottami tocca il raggio: ne cede uno, a terra, e il terreno resta com'e.
func _drill_vein() -> bool:
	if scrap_field == null:
		return false
	var reach := caravan.tuning.drill_reach
	var here := machine.global_position
	var vein := scrap_field.vein_touching(here, reach)
	if vein.is_empty():
		return false
	var center: Vector3 = vein.center
	var away := Vector3(here.x - center.x, 0.0, here.z - center.z)
	away = away.normalized() if away.length() >= 0.01 else Vector3.BACK
	var drop := Vector3(center.x, 0.0, center.z) + away * (float(vein.radius) + DROP_OUTSIDE_M)
	if not caravan.is_open_point(drop):
		drop = Vector3(here.x, 0.0, here.z) - away * DROP_BESIDE_M
	if not scrap_field.take_from_vein(here, reach, drop):
		return false
	_dust(center, float(vein.radius))
	print("PROTOTYPE01_DRILL_HOLE x=%.1f z=%.1f vein=%d" % [center.x, center.z, 1])
	_extract(drop)
	return true


## Buca a `HOLE_GAP_M` dal nemico vivo piu vicino, verso la macchina, se il punto e quasi alla
## base e libero.
func _drill_hole() -> void:
	if write_queue == null:
		return
	var tuning := caravan.tuning
	var enemy := nearest_enemy(tuning.drill_reach)
	if enemy == null:
		return
	var spot: Variant = point_toward(enemy.global_position, machine.global_position, HOLE_GAP_M)
	if spot == null:
		return
	var point: Vector3 = spot
	if absf(terrain_field.height_at(point) - terrain_field.base_height_at(point)) > tuning.drill_flat_tolerance:
		return
	if not clear_spot(point, tuning.drill_radius):
		return
	DigCharge.dig_crater(write_queue, terrain_field, point, tuning.drill_radius, tuning.drill_depth)
	_dust(point, tuning.drill_radius)
	print("PROTOTYPE01_DRILL_HOLE x=%.1f z=%.1f vein=%d" % [point.x, point.z, 0])
	_extract(point)


## Estrattore: i rottami a terra entro `extractor_radius` da [param at] nei Cassoni, fino al posto
## che resta.
func _extract(at: Vector3) -> void:
	if scrap_field == null or not machine.has_combo(&"extractor"):
		return
	var room := caravan.room()
	if room <= 0:
		return
	var taken := scrap_field.take_near(at, caravan.tuning.extractor_radius, room)
	if taken <= 0:
		return
	caravan.add_scrap(taken)
	print("PROTOTYPE01_EXTRACTOR scrap=%d" % taken)


## Ruspa (solo la prima Trivella della macchina): a ogni `dozer_spacing` m dal punto dell'ultimo
## fossato, un fossato sulla scia a `keep_clear + dozer_ditch_radius` dietro la macchina (se il
## suolo e entro `drill_flat_tolerance` dalla base e il punto e libero) e un argine a
## `dozer_bank_offset` alla sua destra, portato a base + `dozer_bank_height` dove il suolo e piu
## basso, se il punto e libero e nessuna parte del disco e gia piu alta. Il verso e quello del
## tratto percorso.
func _tick_dozer() -> void:
	if not machine.has_combo(&"dozer") or machine.module(&"drill") != self or terrain_field == null \
			or write_queue == null:
		_dozer_from = Vector3.INF
		return
	var here := machine.global_position
	if _dozer_from == Vector3.INF:
		_dozer_from = here
		return
	var tuning := caravan.tuning
	var moved := Vector3(here.x - _dozer_from.x, 0.0, here.z - _dozer_from.z)
	var distance := moved.length()
	if distance < tuning.dozer_spacing:
		return
	_dozer_from = here
	if distance > tuning.dozer_spacing * DOZER_JUMP:
		return
	var forward := moved / distance
	var point := Vector3(here.x, 0.0, here.z) - forward * (tuning.keep_clear + tuning.dozer_ditch_radius)
	var written := false
	if absf(terrain_field.height_at(point) - terrain_field.base_height_at(point)) <= tuning.drill_flat_tolerance \
			and clear_spot(point, tuning.dozer_ditch_radius):
		DigCharge.dig_crater(write_queue, terrain_field, point, tuning.dozer_ditch_radius, tuning.dozer_ditch_depth)
		written = true
	var bank := point + forward.cross(Vector3.UP) * tuning.dozer_bank_offset
	var target := terrain_field.base_height_at(bank) + tuning.dozer_bank_height
	# `level` abbassa anche: niente argine dove una parte del disco e gia piu alta (come la Pala).
	if clear_spot(bank, tuning.dozer_bank_radius) and terrain_field.height_at(bank) < target - 0.05 \
			and terrain_field.highest_bump(bank, tuning.dozer_bank_radius, tuning.dozer_bank_height) == null:
		write_queue.push_level(bank, tuning.dozer_bank_radius, target)
		written = true
	if written:
		_dust(point, tuning.dozer_ditch_radius)
		print("PROTOTYPE01_DOZER_TRENCH x=%.1f z=%.1f" % [point.x, point.z])


func _dust(at: Vector3, radius: float) -> void:
	WeaponFx.dust(fx_parent(), Vector3(at.x, terrain_field.height_at(at), at.z), WeaponFx.EARTH, radius, 8, 0.0, true)


## Punta d'acciaio verso il basso su un braccio scuro, sul muso del pianale.
func build_part() -> Node3D:
	var part := Node3D.new()
	part.position = Vector3(0.0, 0.5, -0.3)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.14, 0.15)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.7, 0.72, 0.75)
	steel.metallic = 0.6
	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.14, 0.14, 0.4)
	arm.mesh = arm_mesh
	arm.material_override = dark
	part.add_child(arm)
	var motor := MeshInstance3D.new()
	var motor_mesh := CylinderMesh.new()
	motor_mesh.top_radius = 0.1
	motor_mesh.bottom_radius = 0.1
	motor_mesh.height = 0.2
	motor.mesh = motor_mesh
	motor.material_override = dark
	motor.position = Vector3(0.0, 0.0, -0.22)
	part.add_child(motor)
	var bit := MeshInstance3D.new()
	var bit_mesh := CylinderMesh.new()
	bit_mesh.top_radius = 0.07
	bit_mesh.bottom_radius = 0.0
	bit_mesh.height = 0.36
	bit.mesh = bit_mesh
	bit.material_override = steel
	bit.position = Vector3(0.0, -0.28, -0.22)
	part.add_child(bit)
	return part
