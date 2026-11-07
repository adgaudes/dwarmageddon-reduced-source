class_name TerrainSpike
extends Node3D
## SPIKE del terreno a rilievo continuo (docs/TERRAIN_SYSTEM.md): scena isolata,
## non collegata al livello vero. L'ingegnere scolpisce liberamente con un pennello
## (scava, alza, livella), cammina sul rilievo che ha fatto, e un gruppo di rottamatori
## lo raggiunge aggirando cio che non riesce a salire.
## Comandi: gli stessi del gioco. `terrain_tool` tenuto premuto scolpisce,
## `terrain_mode` cambia modo; F6 salva il rilievo, F7 lo ricarica.

enum Mode { DIG, RAISE, LEVEL }

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const SCAVENGER_MODEL := preload("res://assets/models/scavenger.glb")
const SAVE_PATH := "user://terrain_spike.bin"
const MODE_NAMES: Array[String] = ["SCAVA", "ALZA", "LIVELLA"]
const MODE_COLORS: Array[Color] = [Color(0.1, 0.85, 1.0), Color(1.0, 0.8, 0.1), Color(0.6, 1.0, 0.5)]

## Altezza del centro della capsula del giocatore sopra il suolo.
const PLAYER_HEIGHT := 0.88
## Salita massima percorribile (m di quota per m): circa 39 gradi.
const MAX_GRADE := 0.8
const BRUSH_RADIUS := 2.4
## Metri al secondo al centro del pennello.
const SCULPT_RATE := 2.2
## Frazione al secondo con cui "livella" porta la zona alla quota dei piedi.
const LEVEL_RATE := 5.0
## Distanza del pennello col controller, e massima col mouse.
const TOOL_REACH := 3.6
const TOOL_REACH_MAX := 8.0
## Serbatoio di terra (m3): scavare lo riempie, alzare lo svuota.
const SOIL_CAPACITY := 60.0
const SOIL_START := 20.0
const ENEMY_COUNT := 40
const ENEMY_SPEED := 2.3
const ENEMY_RING := 28.0
## Secondi minimi fra due ricalcoli del campo di percorso.
const FIELD_INTERVAL := 0.25
## Finestra del campo di percorso attorno al giocatore (semilato, m) e di quante caselle
## deve spostarsi il giocatore prima di ricalcolarlo (U-02).
const FIELD_WINDOW_M := 48.0
const FIELD_MOVE_CELLS := 2

var terrain: HeightTerrain
var player: PlayerCharacter
var field := HeightFlowField.new()
var mode := Mode.DIG
var soil := SOIL_START
## Microsecondi dell'ultimo ricalcolo del campo, dell'ultimo colpo di pennello e
## dell'ultimo passo fisico di questa scena (suolo del giocatore, pennello, campo, rottamatori).
var field_usec := 0
var sculpt_usec := 0
var step_usec := 0
var enemies: Array[Node3D] = []
## Spento, i rottamatori non si muovono (catture e test).
var enemies_active := true

var _cursor: MeshInstance3D
var _cursor_material := StandardMaterial3D.new()
var _hud: Label
var _field_dirty := true
var _field_wait := 0.0
var _goal_cell := -1
## Ultimo punto del suolo raggiunto dal giocatore (INF = non ancora posato).
var _last_player := Vector3.INF
## Lato del terreno in metri (96 di default; 204 per le misure di scala, U-02).
@export var terrain_size_m := 96.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	# Dopo il giocatore: prima si muove lui, poi lo si posa sul rilievo.
	process_physics_priority = 10
	_build_world()
	terrain = HeightTerrain.new()
	terrain.name = "Terrain"
	terrain.size_m = terrain_size_m
	add_child(terrain)
	_shape_landscape()
	terrain.changed.connect(func() -> void: _field_dirty = true)

	player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0.0, terrain.height_at(Vector3.ZERO) + PLAYER_HEIGHT, 0.0)
	var rig := IsometricCameraRig.new()
	rig.name = "CameraRig"
	rig.target = player
	add_child(rig)

	var ring := TorusMesh.new()
	ring.inner_radius = BRUSH_RADIUS - 0.07
	ring.outer_radius = BRUSH_RADIUS
	ring.rings = 48
	ring.ring_segments = 6
	_cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cursor_material.no_depth_test = true
	_cursor = MeshInstance3D.new()
	_cursor.name = "BrushCursor"
	_cursor.mesh = ring
	_cursor.material_override = _cursor_material
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cursor)

	_build_hud()
	_spawn_enemies()
	_refresh_field()
	print("PROTOTYPE01_TERRAIN_SPIKE_READY resolution=%d cell=%.2f size=%.0f" % [terrain.resolution, HeightTerrain.CELL, terrain.size_m])


func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_ground_player()
	if Input.is_action_just_pressed(&"terrain_mode"):
		mode = (mode + 1) % Mode.size() as Mode
	var target := brush_target()
	_cursor.global_position = target + Vector3.UP * 0.12
	_cursor_material.albedo_color = MODE_COLORS[mode]
	if Input.is_action_pressed(&"terrain_tool"):
		apply_brush(target, delta)

	_field_wait -= delta
	var goal_cell := field.cell_of(player.global_position)
	if _field_wait <= 0.0 and (_field_dirty or field.cells_apart(goal_cell, _goal_cell) >= FIELD_MOVE_CELLS):
		_refresh_field()
	if enemies_active:
		_move_enemies(delta)
	step_usec = Time.get_ticks_usec() - started
	_refresh_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F6:
		print("PROTOTYPE01_TERRAIN_SPIKE_SAVED bytes=%d" % terrain.save_heights(SAVE_PATH))
	elif key.keycode == KEY_F7:
		print("PROTOTYPE01_TERRAIN_SPIKE_LOADED ok=%s" % terrain.load_heights(SAVE_PATH))


## Punto del suolo su cui agisce il pennello: davanti al personaggio col controller,
## sotto il cursore (entro TOOL_REACH_MAX) col mouse.
func brush_target() -> Vector3:
	var origin := player.global_position
	var point := origin - player.global_basis.z * TOOL_REACH
	var camera := get_viewport().get_camera_3d()
	if player.aim_device == PlayerCharacter.AimDevice.MOUSE and camera != null:
		var mouse := get_viewport().get_mouse_position()
		var hit: Variant = Plane(Vector3.UP, origin.y - PLAYER_HEIGHT).intersects_ray(
			camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		if hit != null:
			var offset := (hit as Vector3) - origin
			offset.y = 0.0
			point = origin + offset.limit_length(TOOL_REACH_MAX)
	point.y = terrain.height_at(point)
	return point


## Un passo di pennello nel modo corrente. La terra si conserva: scavare riempie il
## serbatoio, alzare lo svuota e si ferma quando e vuoto.
func apply_brush(target: Vector3, delta: float) -> void:
	var started := Time.get_ticks_usec()
	var moved := 0.0
	match mode:
		Mode.DIG:
			if soil < SOIL_CAPACITY:
				moved = terrain.sculpt(target, BRUSH_RADIUS, -SCULPT_RATE * delta)
		Mode.RAISE:
			if soil > 0.0:
				moved = terrain.sculpt(target, BRUSH_RADIUS, SCULPT_RATE * delta)
		Mode.LEVEL:
			var feet := player.global_position.y - PLAYER_HEIGHT
			if soil > 0.0 or terrain.height_at(target) > feet:
				moved = terrain.level(target, BRUSH_RADIUS, feet, LEVEL_RATE * delta)
	soil = clampf(soil - moved, 0.0, SOIL_CAPACITY)
	sculpt_usec = Time.get_ticks_usec() - started


func _ground_player() -> void:
	var here := player.global_position
	var before := _last_player
	if before == Vector3.INF:
		before = here
	var reached := terrain.slide_move(before, here, MAX_GRADE)
	player.global_position = Vector3(reached.x, reached.y + PLAYER_HEIGHT, reached.z)
	player.velocity.y = 0.0
	_last_player = Vector3(reached.x, reached.y, reached.z)



func _refresh_field() -> void:
	var started := Time.get_ticks_usec()
	field.rebuild(terrain, player.global_position, MAX_GRADE, FIELD_WINDOW_M)
	field_usec = Time.get_ticks_usec() - started
	_field_dirty = false
	_field_wait = FIELD_INTERVAL
	_goal_cell = field.cell_of(player.global_position)


func _move_enemies(delta: float) -> void:
	var goal := player.global_position
	for enemy in enemies:
		var here := enemy.global_position
		var flat := Vector3(goal.x - here.x, 0.0, goal.z - here.z)
		if flat.length() < 1.1:
			_place_on_ring(enemy)
			continue
		var direction := field.direction_at(here)
		# Senza strada (in una fossa, dietro un argine chiuso) punta dritto e si ferma dove non sale.
		if direction == Vector3.ZERO or flat.length() < HeightFlowField.CELL * 1.5:
			direction = flat.normalized()
		var reached := terrain.slide_move(here, here + direction * ENEMY_SPEED * delta, MAX_GRADE)
		enemy.global_position = reached
		var up := terrain.normal_at(reached)
		var forward := (direction - up * direction.dot(up)).normalized()
		if forward.length_squared() > 0.5:
			enemy.global_basis = Basis.looking_at(forward, up)


func _spawn_enemies() -> void:
	var paint := ActorModel.paint_material(Color(0.55, 0.2, 0.08))
	for i in ENEMY_COUNT:
		var enemy: Node3D = SCAVENGER_MODEL.instantiate()
		enemy.name = "Scavenger%d" % i
		ActorModel.mesh_instance_of(enemy).material_override = paint
		add_child(enemy)
		enemies.append(enemy)
		_place_on_ring(enemy)


func _place_on_ring(enemy: Node3D) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var limit := terrain.half_extent() - 2.0
	var point := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * ENEMY_RING
	point.x = clampf(point.x, -limit, limit)
	point.z = clampf(point.z, -limit, limit)
	point.y = terrain.height_at(point)
	enemy.global_position = point
	enemy.reset_physics_interpolation()


## Rilievo naturale di partenza: ondulazioni, tre colline, il letto asciutto e curvo
## di un torrente. Nessun angolo retto.
func _shape_landscape() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.035
	var half := terrain.half_extent()
	for iz in terrain.resolution:
		for ix in terrain.resolution:
			var x := ix * HeightTerrain.CELL - half
			var z := iz * HeightTerrain.CELL - half
			# Piatto attorno alla partenza, mosso piu lontano.
			var calm := smoothstep(4.0, 14.0, Vector2(x, z).length())
			terrain.heights[iz * terrain.resolution + ix] = noise.get_noise_2d(x, z) * 0.55 * calm
	for hill: Array in [[Vector3(-17.0, 0.0, -12.0), 8.0, 2.6], [Vector3(15.0, 0.0, -20.0), 6.0, 1.7], [Vector3(21.0, 0.0, 13.0), 9.0, 2.2]]:
		terrain.sculpt(hill[0], hill[1], hill[2])
	for i in 60:
		var t := i / 59.0
		var point := Vector3(lerpf(-40.0, 40.0, t), 0.0, 16.0 + sin(t * TAU * 1.2) * 7.0)
		terrain.sculpt(point, 3.2, -0.5)
	terrain.commit_base()


func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.basis = Basis.looking_at(Vector3(-0.55, -0.6, -0.58).normalized(), Vector3.UP)
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	# Due split invece di quattro: la mesh unica del terreno viene disegnata in ogni split (U-11).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.30, 0.50, 0.80)
	sky_material.sky_horizon_color = Color(0.76, 0.80, 0.80)
	sky_material.ground_horizon_color = Color(0.70, 0.66, 0.54)
	sky_material.ground_bottom_color = Color(0.30, 0.32, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24.0, 20.0)
	_hud.add_theme_font_size_override(&"font_size", 20)
	_hud.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_hud)


func _refresh_hud() -> void:
	_hud.text = "PROVA TERRENO LIBERO\nModo: %s   (cambia modo: tasto del gioco)\nTerra nel serbatoio: %.1f / %.0f m3\nRottamatori: %d   Campo: %.1f ms   Passo: %.2f ms   %d fps\nF6 salva il rilievo, F7 lo ricarica" % [
		MODE_NAMES[mode], soil, SOIL_CAPACITY, enemies.size(), field_usec / 1000.0, step_usec / 1000.0, Engine.get_frames_per_second()]
