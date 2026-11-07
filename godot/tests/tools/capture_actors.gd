extends SceneTree
## Catture dei modelli degli attori (non e una suite). Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --script res://tests/tools/capture_actors.gd -- --out=../output/actors
## Mette in posa giocatore, macchina della carovana, rottamatori e Demolitore nel cortile di
## partenza, fermi, e salva: la vista di gioco (`gameplay_*`) e primi piani a tre quarti
## (`player_*`, `machine_*`, `scavenger_*`, `boss_*`) con gli stati guidati dal codice:
## colori del dash, lampo del colpo, rottame sulla schiena, lama a meta martellata,
## pezzi dei moduli Torretta, Calamita e Faro montati.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MACHINE_SCENE := preload("res://scenes/caravan/machine.tscn")

var _out := "../output/actors"
var _scene: Node3D
var _closeup: Camera3D
var _game_camera: Camera3D
var _hud: CanvasLayer


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	# Pose ferme e ripetibili: niente movimento procedurale (per quello c'e capture_motion.gd).
	ActorMotion.enabled = false
	_scene = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(_scene)
	var player: PlayerCharacter = _scene.get_node(^"Player")
	var caravan: Caravan = _scene.get_node(^"Caravan")
	var director: EnemyDirector = _scene.get_node(^"EnemyDirector")
	_hud = _scene.get_node(^"RunHud")
	director.spawning = false
	for i in 10:
		await physics_frame
	var machine := caravan.lead()
	# Tutto fermo: le pose le decide questo script.
	for path: NodePath in [^"Player", ^"EnemyDirector", ^"PlayerWeapon"]:
		_scene.get_node(path).set_physics_process(false)
	machine.set_physics_process(false)
	_game_camera = _scene.get_node(^"CameraRig/Camera")
	_closeup = Camera3D.new()
	_closeup.fov = 30.0
	_scene.add_child(_closeup)

	# --- Posa: il giocatore al centro guarda in alto a destra, la macchina lo segue.
	player.global_position = Vector3(0.0, 0.88, 0.0)
	player.rotation.y = deg_to_rad(-30.0)
	machine.global_position = Vector3(-2.2, 0.3, 1.2)
	machine.reset_physics_interpolation()
	machine.rotation.y = deg_to_rad(-60.0)
	caravan.carried = 2
	# Seconda macchina, fuori dalla carovana (ferma), con i pezzi dei moduli Torretta, Calamita
	# e Faro (dai loro `build_part`, su moduli mai montati) e il cassone rinforzato pieno (7
	# rottami). In gioco ogni macchina ha un solo modulo: qui i pezzi stanno insieme per la foto.
	var upgraded: Machine = MACHINE_SCENE.instantiate()
	_scene.add_child(upgraded)
	upgraded.global_position = Vector3(2.4, 0.3, 1.6)
	upgraded.rotation.y = deg_to_rad(40.0)
	var parts := {&"TurretPart": TurretModule.new(), &"MagnetPart": MagnetModule.new(), &"BeaconPart": BeaconModule.new()}
	for part_name: StringName in parts:
		var module: MachineModule = parts[part_name]
		upgraded.mount_part(part_name, module.build_part())
		module.free()
	upgraded.set_cargo_view(caravan.tuning.cargo_capacity + 2, caravan.tuning.cargo_capacity + 2)

	# Rottamatori in cerchio, rivolti al giocatore come in partita.
	var enemies: Array[Enemy] = []
	for i in 8:
		var angle := TAU * i / 8.0 + 0.3
		var point := Vector3(cos(angle), 0.0, sin(angle)) * (4.2 + (i % 3) * 0.5)
		var enemy := director.spawn_at(point)
		enemy.rotation.y = atan2(point.x, point.z)
		enemies.append(enemy)
	enemies[1].set_carrying(true)
	enemies[4].set_carrying(true)
	enemies[2]._body.material_override = enemies[2]._flash_material

	# Demolitore in arrivo dall'alto dello schermo, verso il giocatore.
	var boss := Demolisher.new()
	boss.setup_demolisher(150, director.flash_material())
	_scene.add_child(boss)
	boss.global_position = Vector3(1.0, Demolisher.boss_spawn_height(), -7.0)
	boss.rotation.y = deg_to_rad(170.0)

	await _save("gameplay_lineup")

	# Stessa scena, tutti girati: il fronte deve leggersi da ogni lato.
	player.rotation.y = deg_to_rad(120.0)
	machine.rotation.y = deg_to_rad(150.0)
	upgraded.rotation.y = deg_to_rad(-110.0)
	for i in enemies.size():
		enemies[i].rotation.y = deg_to_rad(i * 45.0)
	boss.rotation.y = deg_to_rad(-70.0)
	boss._blade.position.y = Demolisher.BLADE_REST.y + Demolisher.BLADE_HAMMER_LIFT
	await _save("gameplay_turned")
	boss.rotation.y = deg_to_rad(20.0)
	player.rotation.y = 0.0
	await _save("gameplay_backs")

	# --- Primi piani.
	_hud.visible = false
	_closeup.make_current()
	player.rotation.y = 0.0
	await _shot("player_front", player.global_position, 4.2, 145.0, 22.0)
	await _shot("player_back", player.global_position, 4.2, 20.0, 40.0)
	await _shot("player_side", player.global_position, 4.2, 90.0, 15.0)

	# Stati del giocatore: normale, dash (ingrandito), ricarica, colpito.
	var states: Array[PlayerCharacter] = []
	for i in 4:
		var extra: PlayerCharacter = PLAYER_SCENE.instantiate()
		_scene.add_child(extra)
		extra.set_physics_process(false)
		extra.global_position = Vector3(-30.0 + i * 1.5, 0.88, 0.0)
		extra.rotation.y = deg_to_rad(180.0)
		states.append(extra)
	states[1]._set_body_color(states[1].tuning.dash_color_linear)
	states[1]._body.scale = states[1]._base_body_scale * states[1].tuning.dash_scale_multiplier
	states[2]._set_body_color(states[2].tuning.dash_cooldown_color_linear)
	states[3].on_hit()
	await _shot("player_states", Vector3(-27.75, 0.88, 0.0), 7.5, 25.0, 30.0)
	await _shot("player_states_game", Vector3(-27.75, 0.88, 0.0), 15.0, 0.0, 55.0, 53.0)

	machine.rotation.y = 0.0
	await _shot("machine_front", machine.global_position, 3.4, 145.0, 25.0)
	await _shot("machine_back", machine.global_position, 3.4, 20.0, 40.0)
	upgraded.rotation.y = 0.0
	await _shot("machine_upgraded_front", upgraded.global_position + Vector3.UP * 0.2, 3.6, 140.0, 25.0)
	await _shot("machine_upgraded_back", upgraded.global_position + Vector3.UP * 0.2, 3.6, 25.0, 40.0)

	# Rottamatori: normale, carico, lampo del colpo.
	var row: Array[Enemy] = [enemies[0], enemies[1], enemies[2]]
	for i in row.size():
		row[i].global_position = Vector3(30.0 + i * 1.3, Enemy.spawn_height(), 0.0)
		row[i].rotation.y = deg_to_rad(180.0)
	await _shot("scavenger_front", row[1].global_position, 4.2, 30.0, 28.0)
	for enemy in row:
		enemy.rotation.y = 0.0
	await _shot("scavenger_back", row[1].global_position, 4.2, 20.0, 45.0)

	boss.rotation.y = 0.0
	boss._blade.position.y = Demolisher.BLADE_REST.y
	var boss_center := boss.global_position + Vector3(0.0, -0.1, 0.0)
	await _shot("boss_front", boss_center, 9.5, 145.0, 22.0)
	boss._blade.position.y = Demolisher.BLADE_REST.y + Demolisher.BLADE_HAMMER_LIFT
	await _shot("boss_hammer", boss_center, 9.5, 110.0, 15.0)
	await _shot("boss_back", boss_center, 9.5, 20.0, 40.0)
	boss._body.material_override = boss._flash_material
	await _shot("boss_flash", boss_center, 9.5, 145.0, 22.0)
	quit()


## Primo piano: camera a [param distance] dal bersaglio, girata di [param yaw_deg]
## attorno all'asse verticale (0 = da dietro, come la camera di gioco) e alzata di
## [param pitch_deg].
func _shot(name: String, target: Vector3, distance: float, yaw_deg: float, pitch_deg: float, fov := 30.0) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	_closeup.fov = fov
	_closeup.look_at_from_position(target + offset, target)
	await _save(name)


func _save(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
