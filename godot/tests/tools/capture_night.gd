extends SceneTree
## Catture del ciclo giorno/notte (D-058, tappa 1), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 3000 --script res://tests/tools/capture_night.gd -- --out=../output/night
## Produce: day (giorno, indicatore con il tempo al tramonto), dusk (tramonto a meta),
## night_beacon (notte dentro il faro della carovana: una macchina col Faro, aggiunta qui),
## night_dark (notte fuori dalle luci, 20 rottamatori attorno), night_upgraded (Torcia e Faro
## al livello 3).

var _out := "../output/night"
var _scene: Node3D
var _run: ArenaRun


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	_scene = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	var player: PlayerCharacter = _scene.get_node(^"Player")
	var caravan: Caravan = _scene.get_node(^"Caravan")
	var director: EnemyDirector = _scene.get_node(^"EnemyDirector")
	director.spawning = false
	(_scene.get_node(^"PlayerWeapon") as AutoWeapon).set_physics_process(false)
	player._invulnerable_left = 3000.0
	for i in 30:
		await physics_frame
	# Il faro e il modulo di una macchina (task 4 di D-093): il Cassone capofila non illumina.
	var lead := caravan.lead()
	var beacon := caravan.add_machine(&"beacon")
	for i in 10:
		await physics_frame
	await _save("day")
	# Tramonto a meta.
	_run.elapsed = _run.day_night.night_start_seconds + _run.day_night.dusk_seconds * 0.5
	for i in 20:
		await physics_frame
	await _save("dusk")
	# Notte, accanto alla macchina col Faro.
	_run.elapsed = _run.day_night.night_start_seconds + _run.day_night.dusk_seconds + 2.0
	for i in 20:
		await physics_frame
	await _save("night_beacon")
	# Notte lontano dal Faro, con l'orda attorno.
	beacon.set_physics_process(false)
	beacon.global_position = player.global_position + Vector3(40.0, 0.0, 0.0)
	beacon.reset_physics_interpolation()
	for i in 20:
		director.spawn_at(player.global_position + Vector3(cos(i * 0.314) * 9.0, 0.0, sin(i * 0.314) * 9.0))
	for i in 40:
		await physics_frame
	await _save("night_dark")
	# Torcia e Faro al massimo.
	beacon.global_position = player.global_position + Vector3(6.0, 0.0, 0.0)
	beacon.reset_physics_interpolation()
	_run.apply_upgrade(&"torch_range", 3)
	_run.apply_upgrade(&"beacon_range", 3)
	for i in 20:
		await physics_frame
	await _save("night_upgraded")
	# Quattro lampioni attorno al giocatore (tappa 2).
	var lamps: LampField = _scene.get_node(^"LampField")
	caravan.add_cargo_capacity(12)
	caravan.add_scrap(12)
	# Il Cassone paga i lampioni: fermo, lo si porta accanto a ognuno.
	lead.set_physics_process(false)
	for offset in [Vector3(7.2, 0.0, 0.0), Vector3(-7.2, 0.0, 0.0), Vector3(0.0, 0.0, 7.2), Vector3(0.0, 0.0, -7.2)]:
		var world: Vector3 = player.global_position + offset
		lead.global_position = world + Vector3(0.0, 0.3, 2.0)
		lead.reset_physics_interpolation()
		lamps.place_at(world)
	lead.global_position = player.global_position + Vector3(6.0, 0.3, 0.0)
	lead.reset_physics_interpolation()
	for i in 20:
		await physics_frame
	await _save("night_lamps")
	quit()


func _save(name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	var err := root.get_viewport().get_texture().get_image().save_png(path)
	print("PROTOTYPE01_CAPTURE path=%s err=%d" % [path, err])
