extends SceneTree
## Catture del livello 2, la ferrovia (D-066), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 4000 --script res://tests/tools/capture_railway.gd -- --out=../output/railway
## Produce: warning (annuncio del treno con freccia), train (il convoglio che passa
## accanto al cortile di partenza), aftermath (la fascia spianata, vagone compreso),
## driller_aim (la Trivella che mira, striscia a terra), driller_charge (in carica, solco dietro),
## driller_stun (ferma contro un terrapieno, punta scoperta).

var _out := "../output/railway"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	var scene: Node3D = preload("res://scenes/main/railway_run.tscn").instantiate()
	root.add_child(scene)
	var run: ArenaRun = scene.get_node(^"Run")
	var train: TrainEvent = scene.get_node(^"TrainEvent")
	var player: PlayerCharacter = scene.get_node(^"Player")
	var director: EnemyDirector = scene.get_node(^"EnemyDirector")
	var district: RailwayDistrict = scene.get_node(^"District")
	director.spawning = false
	for i in 10:
		await physics_frame
	# Il giocatore accanto al vagone piu vicino alla partenza, fuori dalla fascia.
	var wagon_x := 40.0
	for s: Dictionary in district.terrain_strokes:
		if s.kind == &"wagon" and absf(s.center.x) < absf(wagon_x):
			wagon_x = s.center.x
	player.global_position = Vector3(wagon_x - 6.0, 0.88, 7.0)
	player.velocity = Vector3.ZERO
	for i in 6:
		director.spawn_at(Vector3(wagon_x + 6.0 + i * 2.0, 0.0, train.track_z))
	train.warning_seconds = 4.0
	train.next_at = run.elapsed + 4.5
	for i in 60:
		await physics_frame
	await _save("warning")
	while train.state != TrainEvent.State.PASSING:
		await physics_frame
	# Il muso del treno arriva all'altezza del giocatore.
	while absf(train.head_x() - player.global_position.x) > 4.0 and train.state == TrainEvent.State.PASSING:
		await physics_frame
	await _save("train")
	while train.state == TrainEvent.State.PASSING:
		await physics_frame
	for i in 30:
		await physics_frame
	await _save("aftermath")

	# La Trivella: chiamata subito, arrivo accanto al giocatore sulla fascia spianata.
	train.next_at = 1.0e9
	player.global_position = Vector3(-5.0, 0.88, 0.0)
	player.velocity = Vector3.ZERO
	run.call_boss()
	# Fisica a 120 Hz nel gioco (non 60 come nei test): dodici passi bastano a un preavviso di 0,01 s.
	run._boss_warning_left = 0.01
	for i in 12:
		await physics_frame
	var boss := run.boss as Driller
	if boss == null:
		quit()
		return
	boss.global_position = Vector3(8.0, Driller.boss_spawn_height(), 0.0)
	boss.reset_physics_interpolation()
	boss.phase = Driller.Phase.REST
	boss.phase_left = 0.05
	while boss.phase != Driller.Phase.AIM:
		await physics_frame
	for i in 40:
		await physics_frame
	await _save("driller_aim")
	while boss.phase != Driller.Phase.CHARGE:
		await physics_frame
	for i in 75:
		await physics_frame
	await _save("driller_charge")
	# Un terrapieno davanti alla prossima carica.
	while boss.phase != Driller.Phase.REST:
		await physics_frame
	# Giocatore e terrapieno esattamente sulla linea della Trivella, che mira dritta.
	player.global_position = Vector3(boss.global_position.x - 11.0, 0.88, boss.global_position.z)
	player.velocity = Vector3.ZERO
	var field: TerrainField = scene.get_node(^"TerrainField")
	field.sculpt(boss.global_position + Vector3(-7.2, 0.0, 0.0), 2.0, 1.4)
	boss.phase_left = 0.05
	while boss.phase != Driller.Phase.STUN:
		await physics_frame
	for i in 20:
		await physics_frame
	await _save("driller_stun")
	quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
