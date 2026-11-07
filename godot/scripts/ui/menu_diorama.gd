class_name MenuDiorama
extends Node3D
## Sfondo 3D animato del menu iniziale (playtest del 14 ottobre 2026, O-12): un angolo di
## quartiere al tramonto (MenuDistrict) sul rilievo continuo con texture e prato a
## particelle del gioco, l'Ingegnere fermo accanto al compagno sotto un lampione acceso,
## e una camera che scorre piano avanti e indietro. Solo con finestra: in headless il menu
## resta col cielo dipinto 2D.

const ENGINEER := preload("res://assets/models/player_engineer.glb")
const COMPANION := preload("res://assets/models/companion_cart.glb")
const TERRAIN_TUNING := preload("res://resources/tuning/terrain_arena.tres")
## Dove stanno i personaggi: a destra del centro, perche a sinistra c'e il menu.
const CREW_AT := Vector3(3.6, 0.0, 5.6)
const CAMERA_FROM := Vector3(1.8, 3.1, 17.5)
const CAMERA_LOOK := Vector3(1.2, 1.7, 0.0)
## Ampiezza (m) e velocita (rad/s) dello scorrimento della camera.
const SWAY := 2.6
const SWAY_SPEED := 0.055

var terrain: TerrainField
var district: MenuDistrict
var camera: Camera3D
var grass: GrassField
var _focus: Node3D
var _time := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "MenuCamera"
	camera.fov = 48.0
	camera.position = CAMERA_FROM
	add_child(camera)
	camera.current = true
	terrain = TerrainField.new()
	terrain.name = "TerrainField"
	terrain.size_m = Vector2(96.0, 96.0)
	terrain.tuning = TERRAIN_TUNING
	add_child(terrain)
	_sculpt()
	district = MenuDistrict.new()
	district.name = "District"
	district.terrain_field = terrain
	add_child(district)
	district.settle_on_relief()
	_focus = Node3D.new()
	_focus.name = "Focus"
	add_child(_focus)
	_focus.position = _on_ground(CREW_AT)
	_add_crew()
	if terrain.terrain3d() != null:
		_on_render_ready()
	else:
		terrain.render_ready.connect(_on_render_ready, CONNECT_ONE_SHOT)
	_place_camera()


func _process(delta: float) -> void:
	_time += delta
	_place_camera()


## Rilievo morbido: due dossi dietro le rovine e uno a sinistra (niente conche: il fango
## lucido sembrerebbe acqua).
func _sculpt() -> void:
	terrain.begin_batch()
	for stroke: Array in [[Vector3(-14.0, 0.0, -20.0), 9.0, 1.4], [Vector3(18.0, 0.0, -24.0), 11.0, 1.8],
			[Vector3(-22.0, 0.0, 10.0), 7.0, 0.9]]:
		for i in 6:
			terrain.sculpt(stroke[0], stroke[1], float(stroke[2]) / 6.0)
	terrain.end_batch()
	terrain.commit_base()


func _add_crew() -> void:
	var engineer := ENGINEER.instantiate() as Node3D
	engineer.name = "Engineer"
	add_child(engineer)
	engineer.position = _on_ground(CREW_AT)
	# Il modello guarda verso -Z: girato a tre quarti verso la camera.
	engineer.rotation.y = deg_to_rad(155.0)
	var players := engineer.find_children("*", "AnimationPlayer", true, false)
	var player := players[0] as AnimationPlayer if not players.is_empty() else null
	if player != null and player.has_animation(&"Idle"):
		player.get_animation(&"Idle").loop_mode = Animation.LOOP_LINEAR
		player.play(&"Idle")
	var cart := COMPANION.instantiate() as Node3D
	cart.name = "Companion"
	add_child(cart)
	cart.position = _on_ground(CREW_AT + Vector3(1.9, 0.0, 0.9))
	cart.rotation.y = deg_to_rad(-60.0)
	# Il lampione accanto e acceso: una pozza calda sui personaggi.
	var lamp := OmniLight3D.new()
	lamp.name = "LampLight"
	lamp.light_color = Color(1.0, 0.72, 0.42)
	lamp.light_energy = 2.2
	lamp.omni_range = 9.0
	lamp.shadow_enabled = true
	add_child(lamp)
	lamp.position = _on_ground(Vector3(6.2, 0.0, 4.2)) + Vector3(0.0, 4.6, 0.0)


func _on_render_ready() -> void:
	district.paint_surface(terrain)
	district.drop_tuft_cover()
	grass = GrassField.new()
	grass.name = "GrassField"
	add_child(grass)
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	grass.setup(terrain, _focus, settings.vegetation_density if settings != null else 2)


func _place_camera() -> void:
	var sway := sin(_time * SWAY_SPEED * TAU) * SWAY
	var bob := sin(_time * 0.13) * 0.18
	camera.position = CAMERA_FROM + Vector3(sway, bob, 0.0)
	camera.look_at(CAMERA_LOOK + Vector3(sway * 0.35, 0.0, 0.0), Vector3.UP)


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.height_at(p), p.z)
