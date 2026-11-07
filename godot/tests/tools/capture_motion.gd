extends SceneTree
## Sequenze di fotogrammi del movimento procedurale degli attori (non e una suite).
## Con finestra reale, alla frequenza fisica vera del progetto (120 Hz):
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --script res://tests/tools/capture_motion.gd -- --out=../output/motion
## Per ogni sequenza salva FRAMES fotogrammi (`<nome>_0.png` ...) e una striscia
## `<nome>_strip.png` coi ritagli attorno all'attore affiancati 4x2, da guardare in un
## colpo: giocatore che cammina, scatta, viene colpito, rincula; macchina della carovana che parte e
## carico che cambia; rottamatori in marcia, colpiti, in affondo; Demolitore in marcia,
## che martella, colpito; e l'insieme dalla camera di gioco.
## Il rinculo qui e collegato a mano (`weapon.fired` -> `player.kick`).

const FRAMES := 8
const CROP := Vector2i(400, 400)

var _out := "../output/motion"
var _scene: Node3D
var _closeup: Camera3D
var _game_camera: Camera3D
var _player: PlayerCharacter


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	_scene = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(_scene)
	var run: ArenaRun = _scene.get_node(^"Run")
	_player = _scene.get_node(^"Player")
	var caravan: Caravan = _scene.get_node(^"Caravan")
	var director: EnemyDirector = _scene.get_node(^"EnemyDirector")
	var weapon: AutoWeapon = _scene.get_node(^"PlayerWeapon")
	var field: TerrainField = _scene.get_node(^"TerrainField")
	director.spawning = false
	weapon.fired.connect(func(_count: int) -> void: _player.kick(-weapon.last_fire_direction))
	await _steps(20)
	var machine := caravan.lead()
	(_scene.get_node(^"RunHud") as CanvasLayer).visible = false
	_game_camera = _scene.get_node(^"CameraRig/Camera")
	_closeup = Camera3D.new()
	_closeup.fov = 30.0
	_closeup.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_scene.add_child(_closeup)
	_closeup.make_current()

	# --- Giocatore.
	Input.action_press(&"move_right")
	await _steps(30)
	await _sequence("player_walk", _player, 4, 11.5, 60.0, 20.0)
	_player._start_dash()
	# Passo 6: otto fotogrammi coprono tutta la capriola (CharacterAnimator.DODGE_SECONDS).
	await _sequence("player_dash", _player, 6, 11.5, 60.0, 20.0)
	Input.action_release(&"move_right")
	# Le altre andature (la mira resta dov'e) e lo scavo da fermo.
	for gait: Array in [["player_run_forward", &"move_forward"], ["player_run_back", &"move_back"], ["player_strafe_left", &"move_left"]]:
		await _steps(40)
		Input.action_press(gait[1])
		await _steps(30)
		await _sequence(gait[0], _player, 4, 11.5, 60.0, 20.0)
		Input.action_release(gait[1])
	await _steps(60)
	if _player._animator != null:
		_player._animator.play_dig()
	await _sequence("player_dig", _player, 7, 11.5, 60.0, 20.0)
	await _steps(120)
	_player.on_hit()
	await _sequence("player_hit", _player, 1, 11.5, 60.0, 20.0)
	await _steps(60)
	_player.kick(_player.global_basis.z)
	await _sequence("player_recoil", _player, 1, 11.5, 90.0, 15.0)

	# --- Macchina: carico che cambia da fermo, poi partenza e curva dietro al giocatore.
	await _steps(120)
	caravan.spend()
	await _sequence("machine_cargo", machine, 2, 8.5, 40.0, 30.0)
	await _steps(60)
	Input.action_press(&"move_back")
	await _steps(6)
	await _sequence("machine_start", machine, 2, 8.5, 60.0, 25.0)
	Input.action_release(&"move_back")
	Input.action_press(&"move_left")
	await _steps(10)
	await _sequence("machine_turn", machine, 3, 8.5, 60.0, 25.0)
	Input.action_release(&"move_left")
	await _steps(90)

	# --- Rottamatori: in marcia (uno carico), colpito, in affondo sul giocatore.
	weapon.set_physics_process(false)
	var center := _player.global_position
	var enemies: Array[Enemy] = []
	for i in 6:
		var angle := TAU * i / 6.0 + 0.4
		enemies.append(director.spawn_at(center + Vector3(cos(angle), 0.0, sin(angle)) * (6.0 + (i % 2))))
	enemies[0].set_carrying(true)
	await _steps(60)
	await _sequence("scavenger_walk", enemies[0], 4, 7.0, 50.0, 25.0)
	_game_camera.make_current()
	await _sequence("gameplay_horde", _player, 4, 0.0, 0.0, 0.0)
	_closeup.make_current()
	enemies[1].take_damage(1)
	await _sequence("scavenger_hit", enemies[1], 1, 7.0, 50.0, 25.0)
	var lunger: Enemy = null
	for i in 600:
		_keep_player_alive()
		await physics_frame
		for enemy in enemies:
			if enemy._lunge_left > Enemy.LUNGE_PAUSE:
				lunger = enemy
		if lunger != null:
			break
	if lunger != null:
		# Dalla parte del rottamatore, col giocatore dietro: l'affondo non resta coperto.
		var side := lunger.global_position - _player.global_position
		await _sequence("scavenger_lunge", lunger, 1, 7.0, rad_to_deg(atan2(side.x, side.z)) + 50.0, 30.0)
	_player.on_hit()
	_game_camera.make_current()
	await _sequence("gameplay_contact", _player, 2, 0.0, 0.0, 0.0)
	_closeup.make_current()
	director.clear_horde()
	_player.global_position = Vector3(0.0, 0.88, 0.0)
	_player.velocity = Vector3.ZERO

	# --- Demolitore: in marcia, colpito, poi contro un terrapieno che smonta a martellate.
	run.call_boss()
	run._boss_warning_left = 0.0
	for i in 600:
		_keep_player_alive()
		await physics_frame
		if run.boss != null:
			break
	var boss := run.boss as Demolisher
	# Dentro il cortile, senza attrazione per i muri: cosi cammina verso il giocatore.
	var attraction := boss.wall_attraction_radius
	boss.wall_attraction_radius = 0.0
	boss.global_position = _player.global_position + Vector3(-6.0, 0.0, 3.0)
	boss.global_position.y = Demolisher.boss_spawn_height()
	await _steps(4)
	await _sequence("boss_start", boss, 3, 19.0, 60.0, 20.0)
	await _steps(16)
	await _sequence("boss_walk", boss, 2, 19.0, 60.0, 20.0)
	boss.take_damage(1)
	await _sequence("boss_hit", boss, 2, 19.0, 60.0, 20.0)
	_game_camera.make_current()
	await _sequence("gameplay_boss", _player, 4, 0.0, 0.0, 0.0)
	_closeup.make_current()
	boss.wall_attraction_radius = attraction
	await physics_frame
	field.sculpt(boss.global_position - boss.global_basis.z * 3.0, 2.0, 1.4)
	for i in 900:
		_keep_player_alive()
		await physics_frame
		if boss.is_demolishing():
			break
	print("CAPTURE_MOTION boss_demolishing=%s" % boss.is_demolishing())
	await _steps(12)
	await _sequence("boss_hammer", boss, 1, 19.0, 80.0, 15.0)
	await _sequence("boss_hammer_front", boss, 1, 19.0, 150.0, 20.0)
	quit()


func _keep_player_alive() -> void:
	_player.set_max_health(5)
	_player._invulnerable_left = 1.0


func _steps(count: int) -> void:
	for i in count:
		_keep_player_alive()
		await physics_frame


## Salva FRAMES fotogrammi, uno ogni [param stride] frame disegnati, con la camera
## ravvicinata che segue [param target] ([param distance] = 0: camera corrente, ferma).
## La camera segue il corpo fisico, quindi quel che si muove nel ritaglio e il visual.
func _sequence(name: String, target: Node3D, stride: int, distance: float, yaw_deg: float, pitch_deg: float) -> void:
	var strip := Image.create(CROP.x * 4, CROP.y * 2, false, Image.FORMAT_RGB8)
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	for frame in FRAMES:
		for i in stride:
			_keep_player_alive()
			await process_frame
			if distance > 0.0 and is_instance_valid(target):
				var at := target.get_global_transform_interpolated().origin
				_closeup.look_at_from_position(at + offset, at)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s_%d.png" % [name, frame])
		image.save_png(path)
		image.convert(Image.FORMAT_RGB8)
		var corner := (image.get_size() - CROP) / 2
		strip.blit_rect(image, Rect2i(corner, CROP), Vector2i((frame % 4) * CROP.x, (frame / 4) * CROP.y))
	var strip_path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s_strip.png" % name)
	var err := strip.save_png(strip_path)
	print("CAPTURE %s err=%d" % [strip_path, err])
