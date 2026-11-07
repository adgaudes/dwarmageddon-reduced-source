extends SceneTree
## Test del personaggio (Fase 5). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/player_tests.gd
## Con --fixed-fps 60 ogni frame e un passo fisico da 1/60 s, deterministico.
## I valori attesi sono calcolati a mano dal modello UCharacterMovementComponent a 60 fps.

const DT := 1.0 / 60.0
const PlanarMovementScript := preload("res://scripts/player/planar_movement.gd")
const SmokeTestScene := preload("res://scenes/main/smoke_test.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")

var _failures := 0


func _initialize() -> void:
	# I valori attesi sono calcolati a 60 passi fisici al secondo; il progetto ne usa 120.
	Engine.physics_ticks_per_second = 60
	_test_movement_model()
	await _test_player_in_scene()
	await _test_pack_gauge()
	await _test_class_color()
	# T-12: i nodi messi in coda con queue_free vanno liberati prima di uscire, o
	# il motore segnala istanze ObjectDB perse all'uscita.
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Zainetto di terra sul modello (spec sezione 3): la striscia sul fianco segue il riempimento.
func _test_pack_gauge() -> void:
	print("pack gauge")
	var field := TerrainField.new()
	field.size_m = Vector2(32.0, 32.0)
	field.tuning = TerrainTuning.new()
	field.render = false
	root.add_child(field)
	var player: PlayerCharacter = PlayerScene.instantiate()
	player.terrain_field = field
	root.add_child(player)
	await _frames(2)
	var material := player.pack_gauge_material()
	_check(material != null and absf(float(material.get_shader_parameter(&"pack_fill")) - 20.0 / 60.0) < 0.01, "pack_fill parte da 20/60")
	var sack := player.find_child("PackSack", true, false) as Node3D
	_check(sack != null, "la sacca esiste nel modello")
	_check(sack != null and is_equal_approx(sack.scale.x, 1.0), "a zaino mezzo vuoto la sacca e normale")
	player.pack.give(40.0)
	_check(material != null and absf(float(material.get_shader_parameter(&"pack_fill")) - 1.0) < 0.01, "zaino pieno = pack_fill 1")
	_check(sack != null and sack.scale.x > 1.1, "a zaino pieno la sacca si gonfia")
	player.queue_free()
	field.queue_free()


## Segnaposto delle classi (D-092): la tuta prende il colore di classe e ci torna dopo il colpo.
func _test_class_color() -> void:
	print("class color")
	var player: PlayerCharacter = PlayerScene.instantiate()
	root.add_child(player)
	await _frames(2)
	var suit := player._body_material
	var teal := Color(0.1, 0.75, 0.72).srgb_to_linear()
	player.set_class_color(teal)
	_check(suit.albedo_color.is_equal_approx(teal.linear_to_srgb()), "la tuta prende il colore di classe")
	player.on_hit()
	_check(not suit.albedo_color.is_equal_approx(teal.linear_to_srgb()), "il colpo lampeggia")
	await _frames(60)
	_check(suit.albedo_color.is_equal_approx(teal.linear_to_srgb()), "dopo il lampo torna al colore di classe")
	player.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _test_movement_model() -> void:
	print("movement model")
	var model: PlanarMovement = PlanarMovementScript.new()
	var forward := Vector3(0, 0, -1)

	# Accelerazione: 20.48 m/s^2 -> 6 m/s raggiunti al 18esimo frame (0.293 s).
	var v := Vector3.ZERO
	var frames := 0
	while v.length() < 6.0 - 1e-4 and frames < 100:
		v = model.calc_velocity(v, forward, DT)
		frames += 1
	_check(frames == 18, "0->6 m/s in 18 frame (got %d)" % frames)
	_check(is_equal_approx(v.length(), 6.0), "velocita limitata a 6 m/s (got %.4f)" % v.length())

	# Analogico: stick a meta -> velocita massima 3 m/s.
	var half := Vector3.ZERO
	for i in 120:
		half = model.calc_velocity(half, forward * 0.5, DT)
	_check(is_equal_approx(half.length(), 3.0), "stick 0.5 -> 3 m/s (got %.4f)" % half.length())

	# Frenata: v' = v*(1 - 16/60) - 20.48/60, stop dopo 6 frame, ~0.156 m.
	var distance := 0.0
	frames = 0
	while not v.is_zero_approx() and frames < 100:
		v = model.calc_velocity(v, Vector3.ZERO, DT)
		distance += v.length() * DT
		frames += 1
	_check(frames == 6, "frenata da 6 m/s in 6 frame (got %d)" % frames)
	_check(absf(distance - 0.156) < 0.005, "spazio di frenata ~0.156 m (got %.4f)" % distance)

	# Dash: 30 m/s imposti a ogni frame, frenati a 21.66 m/s dal modello.
	var dash := model.calc_velocity(Vector3(0, 0, -30), Vector3.ZERO, DT)
	_check(absf(dash.length() - 21.659) < 0.01, "velocita effettiva dash ~21.66 m/s (got %.3f)" % dash.length())

	# A 120 Hz (impostazione del progetto) la frenata pesa meno per passo:
	# v = 30 * (1 - 16/120) - 20,48/120 = 25,83 m/s, come Unreal ad alto framerate.
	var dash_120 := model.calc_velocity(Vector3(0, 0, -30), Vector3.ZERO, 1.0 / 120.0)
	_check(absf(dash_120.length() - 25.829) < 0.01, "dash a 120 Hz ~25.83 m/s (got %.3f)" % dash_120.length())


func _test_player_in_scene() -> void:
	print("player in scene")
	var scene := SmokeTestScene.instantiate()
	root.add_child(scene)
	var player: PlayerCharacter = scene.get_node("Player")
	_use_reference_tuning(player)
	await _frames(10)
	_check(player.is_on_floor(), "il personaggio poggia sul pavimento")
	_check(absf(player.global_position.y - 0.88) < 0.02, "centro capsula a 0.88 m (got %.3f)" % player.global_position.y)

	# Movimento a destra (tastiera o stick): +X Godot = +Y Unreal.
	var start := player.global_position
	Input.action_press(&"move_right")
	await _frames(60)
	_check(absf(player.velocity.x - 6.0) < 0.01 and absf(player.velocity.z) < 0.01,
		"move_right -> 6 m/s su +X (got %s)" % player.velocity)
	Input.action_release(&"move_right")
	await _frames(10)
	_check(player.velocity.is_zero_approx() or Vector2(player.velocity.x, player.velocity.z).is_zero_approx(),
		"si ferma al rilascio")
	var moved := player.global_position - start
	_check(moved.x > 4.5 and moved.x < 5.5, "spostamento ~5 m in 1 s (got %.3f)" % moved.x)

	# Mira stick: alto -> yaw 0 (verso -Z), destra -> yaw -90.
	Input.action_press(&"aim_right", 1.0)
	await _frames(60)
	_check(absf(player.rotation.y + PI / 2) < 0.01, "aim_right -> yaw -90 (got %.1f)" % rad_to_deg(player.rotation.y))
	Input.action_release(&"aim_right")
	Input.action_press(&"aim_up", 1.0)
	await _frames(60)
	_check(absf(player.rotation.y) < 0.01, "aim_up -> yaw 0 (got %.1f)" % rad_to_deg(player.rotation.y))
	Input.action_release(&"aim_up")

	# Stick oltre la dead zone ma piano: ruota piu lentamente.
	Input.action_press(&"aim_down", 0.3)
	await _frames(5)
	var slow_yaw := absf(player.rotation.y)
	Input.action_release(&"aim_down")
	_check(slow_yaw > 0.0 and slow_yaw < 0.5, "stick leggero ruota lentamente (got %.1f deg)" % rad_to_deg(slow_yaw))
	Input.action_press(&"aim_up", 0.1)
	var yaw_before := player.rotation.y
	await _frames(10)
	_check(is_equal_approx(player.rotation.y, yaw_before), "stick sotto dead zone non ruota")
	Input.action_release(&"aim_up")

	# Mouse: un movimento sopra soglia passa alla mira mouse; la direzione e quella
	# del punto del piano orizzontale sotto il cursore (qui 5 m verso -X).
	var camera := player.get_viewport().get_camera_3d()
	var target_point := player.global_position + Vector3(-5.0, 0.0, 0.0)
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(target_point)
	motion.global_position = motion.position
	motion.relative = Vector2(8.0, 0.0)
	Input.parse_input_event(motion)
	await _frames(2)
	_check(player.aim_device == PlayerCharacter.AimDevice.MOUSE, "movimento mouse -> mira mouse")
	# In headless il cursore del viewport non segue gli eventi: si verifica la deproiezione diretta.
	var aim_dir := player.aim_direction_at_screen(motion.position).normalized()
	_check(aim_dir.distance_to(Vector3(-1, 0, 0)) < 0.01, "deproiezione cursore -> direzione -X (got %s)" % aim_dir)
	Input.action_press(&"aim_up", 1.0)
	await _frames(30)
	Input.action_release(&"aim_up")
	_check(player.aim_device == PlayerCharacter.AimDevice.GAMEPAD, "stick destro -> torna alla mira gamepad")

	# Dash nella direzione dell'ultimo movimento valido (+X).
	# Si misura in passi fisici dal segnale di avvio: Unreal muove 11 frame (0,18 s a 60 fps)
	# e rende di nuovo disponibile il dash a 1,2 s dall'attivazione.
	var marks := {}
	player.dash_started.connect(func(): marks[&"start"] = Engine.get_physics_frames(), CONNECT_ONE_SHOT)
	player.dash_ready.connect(func(): marks[&"ready"] = Engine.get_physics_frames(), CONNECT_ONE_SHOT)
	start = player.global_position
	_send_dash()
	await _frames(2)
	_check(player.is_dashing, "dash avviato")
	var dash_frames := 0
	while player.is_dashing and dash_frames < 60:
		await _frames(1)
		dash_frames += 1
	moved = player.global_position - start
	_check(absf(moved.x - 3.97) < 0.02 and absf(moved.z) < 0.01, "dash ~3.97 m su +X, 11 frame (got %s)" % moved)
	_check(player.is_dash_on_cooldown, "cooldown dopo il dash")

	_send_dash()
	await _frames(2)
	_check(not player.is_dashing, "dash ignorato in cooldown")
	var waited := 0
	while player.is_dash_on_cooldown and waited < 200:
		await _frames(1)
		waited += 1
	var ready_after: float = (marks.get(&"ready", 0) - marks.get(&"start", 0)) * DT
	_check(absf(ready_after - 1.2) <= DT + 1e-4, "dash di nuovo pronto ~1.2 s dopo l'attivazione (got %.3f s)" % ready_after)

	_send_dash()
	await _frames(2)
	_check(player.is_dashing, "dash di nuovo disponibile dopo il cooldown")

	# R-17: un rilascio avvenuto in pausa non arriva al personaggio. Alla ripresa
	# l'azione non deve ripetersi ne restare "premuta" (mangerebbe la pressione dopo).
	var mode_before := player.terrain_tool_mode
	_send_key(KEY_Q, true)
	await _frames(2)
	_check(player.terrain_tool_mode != mode_before, "Q cambia modalita del tool")
	paused = true
	await _frames(2)
	_send_key(KEY_Q, false)
	await _frames(2)
	paused = false
	await _frames(3)
	var mode_after_first := player.terrain_tool_mode
	_check(mode_after_first != mode_before, "ripresa dopo il rilascio in pausa: nessun comando ripetuto")
	_send_key(KEY_Q, true)
	await _frames(2)
	# Sul rilievo il ciclo ha tre modi (Scava, Alza, Livella): conta che il modo sia cambiato ancora.
	_check(player.terrain_tool_mode != mode_after_first, "la pressione successiva non viene scartata")
	_send_key(KEY_Q, false)
	await _frames(1)

	scene.queue_free()
	await _frames(1)


func _send_key(physical_key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical_key
	event.pressed = pressed
	Input.parse_input_event(event)


## Pressione e rilascio come eventi reali, consegnati al frame successivo.
func _send_dash() -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = &"dash"
		event.pressed = pressed
		Input.parse_input_event(event)


## I valori attesi sono quelli del riferimento Unreal, non del preset di default.
func _use_reference_tuning(player: PlayerCharacter) -> void:
	player.apply_tuning(load("res://resources/tuning/player_default.tres"))


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
