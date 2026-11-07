class_name ActiveTelegraph
extends Node3D
## Telegrafo a terra delle armi attive (piano 5 di D-092, spec par. "Effetti"): con la mira
## manuale un anello del colore della classe segue il punto in cui partirebbe la prima attiva
## carica; alla partenza di un'attiva, con qualunque mira, l'anello lampeggia sul punto colpito.
## Un solo nodo per il loadout, due mesh; niente in pausa.

const FLASH_SECONDS := 0.35
const DEFAULT_RADIUS := 1.5
## Chiavi del catalogo che danno la misura dell'effetto, in ordine di preferenza.
const RADIUS_KEYS: Array[StringName] = [&"ring_radius", &"blast_radius", &"pull_radius", &"pool_radius"]
const LIFT := 0.06

var loadout: WeaponLoadout
var aim_ring: MeshInstance3D
var flash_ring: MeshInstance3D
var _flash_left := 0.0


func _ready() -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	aim_ring = _make_ring("AimRing", 0.55)
	flash_ring = _make_ring("FlashRing", 0.9)


## Misura dell'effetto di [param weapon] in metri (raggio), per l'anello.
static func radius_of(weapon: ActiveWeapon) -> float:
	for key in RADIUS_KEYS:
		var value := weapon.stat(key)
		if value > 0.0:
			return value
	return DEFAULT_RADIUS


func show_aim(at: Vector3, radius: float, color: Color) -> void:
	_place(aim_ring, at, radius, color, 0.55)


func hide_aim() -> void:
	aim_ring.visible = false


func flash(at: Vector3, radius: float, color: Color) -> void:
	_place(flash_ring, at, radius, color, 0.9)
	_flash_left = FLASH_SECONDS


func _process(delta: float) -> void:
	if get_tree().paused:
		aim_ring.visible = false
		flash_ring.visible = false
		return
	if _flash_left > 0.0:
		_flash_left -= delta
		flash_ring.visible = _flash_left > 0.0
		var mat := flash_ring.material_override as StandardMaterial3D
		mat.albedo_color.a = 0.9 * clampf(_flash_left / FLASH_SECONDS, 0.0, 1.0)
	_update_aim()


func _update_aim() -> void:
	var weapon := _ready_active()
	if weapon == null or not loadout.manual_aim:
		hide_aim()
		return
	show_aim(weapon.aim_point(), radius_of(weapon), loadout.class_color())


func _ready_active() -> ActiveWeapon:
	if loadout == null:
		return null
	for weapon in loadout.actives():
		if weapon.can_trigger():
			return weapon
	return null


func _place(ring: MeshInstance3D, at: Vector3, radius: float, color: Color, alpha: float) -> void:
	var ground := at.y
	if loadout != null and loadout.terrain_field != null:
		ground = loadout.terrain_field.height_at(at)
	ring.global_position = Vector3(at.x, ground + LIFT, at.z)
	ring.scale = Vector3(radius, 1.0, radius)
	var mat := ring.material_override as StandardMaterial3D
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	ring.visible = true


func _make_ring(node_name: String, alpha: float) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	var ring := MeshInstance3D.new()
	ring.name = node_name
	ring.mesh = torus
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	return ring
