extends SceneTree
## Test con eventi di input reali (joypad, tasti con modificatori), non azioni
## simulate: coprono i percorsi che Input.action_press non attraversa.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/input_events_tests.gd

const SmokeTestScene := preload("res://scenes/main/smoke_test.tscn")
## Giocatore, rottami e carovana collegati, senza run ne nemici: Interagisci e riparazione.
const RuinsScene := preload("res://scenes/main/ruins_arena.tscn")
const TRIGGER_RIGHT := JOY_AXIS_TRIGGER_RIGHT
const LEFT_X := JOY_AXIS_LEFT_X

var _failures := 0
var _player: PlayerCharacter
var _field: TerrainField
var _caravan: Caravan
## Emissioni di `interact_pressed` dall'inizio del caso.
var _interact_presses := 0


func _initialize() -> void:
	# I valori attesi sono calcolati a 60 passi fisici al secondo; il progetto ne usa 120.
	Engine.physics_ticks_per_second = 60
	await _load_scene()
	_test_ui_actions_have_joypad()
	await _test_trigger_holds_brush()
	await _reload_scene()
	await _test_actions_ignore_modifiers()
	await _reload_scene()
	_use_reference_tuning(_player)
	await _test_move_actuation_threshold()
	await _reload_scene()
	await _test_tuning_switcher()
	await _reload_scene()
	_use_reference_tuning(_player)
	await _test_hold_per_source()
	await _reload_scene()
	_use_reference_tuning(_player)
	await _test_mouse_aim_switch()
	await _reload_scene()
	await _test_tool_released_without_event()
	await _reload_scene()
	await _test_active_weapon_keys()
	root.get_node("Scene").free()
	await _load_ruins_scene()
	await _test_interact_repairs(true)
	await _test_interact_repairs(false)
	await _test_interact_release_resets()
	await _test_interact_echo()
	await _test_interact_focus_out()
	await _test_interact_held_by_hand()
	await _test_interact_cleared_at_death()
	var ruins := root.get_node("Scene")
	root.remove_child(ruins)
	ruins.queue_free()
	# T-12: i nodi messi in coda con queue_free vanno liberati prima di uscire, o
	# il motore segnala istanze ObjectDB perse all'uscita.
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


## Grilletto analogico: finche e premuto il pennello lavora a ogni passo; al rilascio si
## ferma; una nuova pressione riparte (tappa A: azione continua, non un colpo per pressione).
func _test_trigger_holds_brush() -> void:
	print("right trigger")
	var strokes := [0]
	_field.player_sculpted.connect(func(_c: Vector3, _r: float, _v: float, _m: int) -> void: strokes[0] += 1)
	for value in [0.3, 0.6, 0.8, 1.0, 0.9]:
		_joy_motion(TRIGGER_RIGHT, value)
		await _frames(1)
	_check(_player.tool_held and strokes[0] >= 2, "grilletto tirato: pennello continuo (%d pennellate)" % strokes[0])
	_joy_motion(TRIGGER_RIGHT, 0.2)
	await _frames(2)
	var after_release: int = strokes[0]
	await _frames(3)
	_check(not _player.tool_held and strokes[0] == after_release, "sotto la soglia il pennello si ferma")
	_joy_motion(TRIGGER_RIGHT, 1.0)
	await _frames(2)
	_check(strokes[0] > after_release, "nuova pressione: riparte")
	_joy_motion(TRIGGER_RIGHT, 0.0)
	await _frames(1)


## I menu devono funzionare col solo controller: Godot 4.7 non lega A e B a
## ui_accept e ui_cancel di default, il progetto si.
func _test_ui_actions_have_joypad() -> void:
	print("ui joypad bindings")
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	_check(a.is_action(&"ui_accept"), "A conferma nei menu (ui_accept)")
	_check(b.is_action(&"ui_cancel"), "B torna indietro nei menu (ui_cancel)")


## In Unreal MapKey ignora i modificatori: Shift+Spazio fa comunque il dash.
func _test_actions_ignore_modifiers() -> void:
	print("modifiers")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.shift_pressed = true
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	_check(_player.is_dashing, "Shift+Spazio avvia il dash")
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(1)

	# Dorsale sinistro (LB): in Godot e JOY_BUTTON_LEFT_SHOULDER (9), non il 4 (Back).
	var shoulder := InputEventJoypadButton.new()
	shoulder.button_index = JOY_BUTTON_LEFT_SHOULDER
	shoulder.pressed = true
	Input.parse_input_event(shoulder)
	await _frames(2)
	_check(_player.terrain_tool_mode == TerrainField.ToolMode.RAISE, "dorsale sinistro cambia modalita")
	shoulder = shoulder.duplicate()
	shoulder.pressed = false
	Input.parse_input_event(shoulder)
	await _frames(1)
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_BACK
	back.pressed = true
	Input.parse_input_event(back)
	await _frames(2)
	_check(_player.terrain_tool_mode == TerrainField.ToolMode.RAISE, "il tasto Back non cambia modalita")
	back = back.duplicate()
	back.pressed = false
	Input.parse_input_event(back)
	await _frames(1)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.ctrl_pressed = true
	click.pressed = true
	Input.parse_input_event(click)
	await _frames(2)
	# Sul rilievo il ciclo e Scava -> Alza -> Livella (-> Lampione se c'e il campo).
	_check(_player.terrain_tool_mode == TerrainField.ToolMode.LEVEL, "Ctrl+clic destro cambia modalita (Alza -> Livella)")
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await _frames(1)


## IA_Move ha un UInputTriggerDown (soglia 0,5 sul modulo): sotto non ci si
## muove, sopra la velocita segue il modulo grezzo dello stick.
func _test_move_actuation_threshold() -> void:
	print("move threshold")
	_joy_motion(LEFT_X, 0.4)
	await _frames(60)
	_check(Vector2(_player.velocity.x, _player.velocity.z).is_zero_approx(), "stick a 0,4: fermo")
	_joy_motion(LEFT_X, 0.6)
	await _frames(60)
	_check(absf(_player.velocity.x - 3.6) < 0.01, "stick a 0,6: 3,6 m/s (got %.3f)" % _player.velocity.x)
	_joy_motion(LEFT_X, 1.0)
	await _frames(60)
	_check(absf(_player.velocity.x - 6.0) < 0.01, "stick a 1,0: 6 m/s (got %.3f)" % _player.velocity.x)
	_joy_motion(LEFT_X, 0.0)
	await _frames(10)


## Strumento di playtest: Tab alterna i preset di feel. La croce direzionale non
## piu: e la navigazione dei menu (ui_left/ui_right) e cambiava preset per sbaglio (U-12).
func _test_tuning_switcher() -> void:
	print("tuning switcher")
	var switcher: TuningSwitcher = root.get_node("Scene/TuningSwitcher")
	_check(switcher.presets.size() == 4, "4 preset caricati (got %d)" % switcher.presets.size())
	_check(_player.tuning.display_name == "Scattante", "si parte da Scattante, il default")
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await _frames(2)
	_check(_player.tuning.display_name == "Unreal (riferimento)", "Tab -> Unreal (got %s)" % _player.tuning.display_name)
	var dpad := InputEventJoypadButton.new()
	dpad.button_index = JOY_BUTTON_DPAD_RIGHT
	dpad.pressed = true
	Input.parse_input_event(dpad)
	await _frames(2)
	_check(_player.tuning.display_name == "Unreal (riferimento)", "la croce destra non cambia preset (got %s)" % _player.tuning.display_name)
	var tab_release := InputEventKey.new()
	tab_release.physical_keycode = KEY_TAB
	tab_release.pressed = false
	Input.parse_input_event(tab_release)
	await _frames(2)
	Input.parse_input_event(tab)
	await _frames(2)
	_check(_player.tuning.display_name == "Pesante", "Tab di nuovo -> Pesante (got %s)" % _player.tuning.display_name)
	# Il nuovo tuning agisce davvero: velocita massima Pesante 5,5 m/s.
	Input.action_press(&"move_right")
	await _frames(240)
	Input.action_release(&"move_right")
	_check(absf(_player.velocity.x - 5.5) < 0.01, "velocita del preset Pesante 5,5 m/s (got %.3f)" % _player.velocity.x)


## P-02: ogni sorgente tiene l'azione per conto suo. Clic sinistro tenuto, grilletto
## tirato, clic rilasciato, grilletto che varia: un solo comando dello strumento.
func _test_hold_per_source() -> void:
	print("hold per source")
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_check(_player.tool_held, "il clic tiene il pennello")
	_joy_motion(TRIGGER_RIGHT, 0.6)
	await _frames(1)
	_joy_motion(TRIGGER_RIGHT, 1.0)
	await _frames(1)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _frames(1)
	_check(_player.tool_held, "clic rilasciato ma grilletto tirato: resta premuto")
	_joy_motion(TRIGGER_RIGHT, 0.0)
	await _frames(2)
	_check(not _player.tool_held, "rilasciato tutto: si ferma")
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_check(_player.tool_held, "una nuova pressione riparte")
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _frames(1)


## P-01: la mira passa al mouse solo con uno spostamento cumulativo di 6 px entro
## 0,25 s; con il mouse fermo da 0,5 s lo stick sinistro la riporta al controller.
func _test_mouse_aim_switch() -> void:
	print("mouse aim switch")
	_check(_player.aim_device == PlayerCharacter.AimDevice.GAMEPAD, "si parte dal controller")
	_mouse_motion(Vector2(1.0, 0.0))
	await _frames(2)
	_check(_player.aim_device == PlayerCharacter.AimDevice.GAMEPAD, "1 px di mouse non cambia dispositivo")
	# La finestra scade (0,33 s): i pixel precedenti non contano piu.
	await _frames(20)
	_mouse_motion(Vector2(1.0, 0.0))
	await _frames(1)
	_mouse_motion(Vector2(0.0, 1.5))
	await _frames(2)
	_check(_player.aim_device == PlayerCharacter.AimDevice.GAMEPAD, "tocchi sparsi sotto soglia non cambiano dispositivo")
	_mouse_motion(Vector2(8.0, 0.0))
	await _frames(2)
	_check(_player.aim_device == PlayerCharacter.AimDevice.MOUSE, "8 px di mouse -> mira mouse")
	_joy_motion(LEFT_X, 1.0)
	await _frames(10)
	_check(_player.aim_device == PlayerCharacter.AimDevice.MOUSE, "stick sinistro col mouse appena mosso: resta il mouse")
	await _frames(30)
	_check(_player.aim_device == PlayerCharacter.AimDevice.GAMEPAD, "stick sinistro con mouse fermo da 0,5 s -> torna al controller")
	_joy_motion(LEFT_X, 0.0)
	await _frames(2)
	# Tre frazioni di pixel in rapida successione sommano oltre la soglia: e un movimento vero.
	for i in 3:
		_mouse_motion(Vector2(2.5, 0.0))
		await _frames(1)
	await _frames(1)
	_check(_player.aim_device == PlayerCharacter.AimDevice.MOUSE, "7,5 px cumulativi in 3 frame -> mira mouse")
	await _frames(10)


## [param relative] in pixel del viewport di gioco. Trappola: in headless la finestra
## e 64x64 e lo stretch `canvas_items` scala `relative` di 20 prima che arrivi ai nodi.
func _mouse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(640.0, 400.0)
	event.global_position = event.position
	event.relative = relative * root.get_final_transform().get_scale()
	Input.parse_input_event(event)


## Audit I-01 e I-03: il rilascio che non arriva mai come evento (Alt-Tab: Godot svuota
## lo stato di Input senza eventi) non lascia il pennello attivo; una ripetizione
## automatica della tastiera non conta come rilascio.
func _test_tool_released_without_event() -> void:
	print("tool released without event")
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_check(_player.tool_held, "il clic tiene il pennello")
	_player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not _player.tool_held, "finestra senza focus: pennello rilasciato")
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _frames(1)
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_check(_player.tool_held, "una nuova pressione riparte")
	# Stato di Input svuotato senza evento di rilascio.
	Input.action_release(&"terrain_tool")
	await _frames(2)
	_check(not _player.tool_held, "Input dice rilasciato: il pennello si ferma anche senza evento")
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _frames(1)
	var dash_key: InputEventKey = null
	for event in InputMap.action_get_events(&"dash"):
		if event is InputEventKey:
			dash_key = (event as InputEventKey).duplicate()
	_check(dash_key != null, "lo scatto ha un tasto")
	if dash_key == null:
		return
	dash_key.pressed = true
	Input.parse_input_event(dash_key)
	await _frames(1)
	var echo := dash_key.duplicate() as InputEventKey
	echo.echo = true
	Input.parse_input_event(echo)
	await _frames(1)
	var sources: Dictionary = _player._held_actions.get(&"dash", {})
	_check(sources.has("InputEventKey"), "la ripetizione del tasto non lo rilascia")
	var release := dash_key.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(1)


## Armi attive (D-092): E e grilletto sinistro per lo slot 1, F e dorsale destro per lo slot 2;
## un comando per pressione, il grilletto analogico non ripete finche resta tirato.
func _test_active_weapon_keys() -> void:
	print("active weapons")
	var pressed: Array[int] = []
	_player.active_weapon_pressed.connect(func(slot: int) -> void: pressed.append(slot))
	for keycode in [KEY_E, KEY_F]:
		var key := InputEventKey.new()
		key.physical_keycode = keycode
		key.pressed = true
		Input.parse_input_event(key)
		await _frames(2)
		key = key.duplicate()
		key.pressed = false
		Input.parse_input_event(key)
		await _frames(1)
	_check(pressed == ([0, 1] as Array[int]), "E usa lo slot 1, F lo slot 2 (%s)" % [pressed])
	pressed.clear()
	for value in [0.3, 0.7, 0.9, 1.0, 0.8]:
		_joy_motion(JOY_AXIS_TRIGGER_LEFT, value)
		await _frames(1)
	_joy_motion(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await _frames(1)
	var shoulder := InputEventJoypadButton.new()
	shoulder.button_index = JOY_BUTTON_RIGHT_SHOULDER
	shoulder.pressed = true
	Input.parse_input_event(shoulder)
	await _frames(2)
	shoulder = shoulder.duplicate()
	shoulder.pressed = false
	Input.parse_input_event(shoulder)
	await _frames(1)
	_check(pressed == ([0, 1] as Array[int]), "grilletto sinistro una volta sola per pressione, dorsale destro per lo slot 2 (%s)" % [pressed])


# --- Interagisci e riparazione (carovana D-093, task 7) --------------------------------------
# Un evento passato a Input.parse_input_event arriva al giocatore un passo dopo: i conti dei
# passi dal parse hanno qualche passo di tolleranza.

## Tenere X (o R) accanto a una macchina guasta la ripara in `repair_seconds`: in ordine, a
## meta vita, 2 rottami in meno.
func _test_interact_repairs(joypad: bool) -> void:
	var button_name := "X" if joypad else "R"
	print("interact repairs (%s)" % button_name)
	var lead := await _prepare_repair()
	var tuning := _caravan.tuning
	var nominal := roundi(tuning.repair_seconds * Engine.physics_ticks_per_second)
	var press := _interact_event(joypad)
	Input.parse_input_event(press)
	var step := await _steps_until_repaired(lead, nominal + 30)
	_check(step >= nominal - 2 and step <= nominal + 4, "%s tenuto: riparata al passo %d (%d nominali)" % [button_name, step, nominal])
	_check(lead.state == Machine.State.OK and lead.health == ceili(lead.max_health * tuning.repair_health_fraction),
		"di nuovo in ordine con %d PV" % lead.health)
	_check(_caravan.carried == 1, "%d rottami spesi (ne resta %d)" % [tuning.repair_cost, _caravan.carried])
	_check(_interact_presses == 1, "una sola interact_pressed per la pressione")
	await _release_interact(press)


## Rilasciato a 1 s il progresso torna a zero e non si spende niente.
func _test_interact_release_resets() -> void:
	print("interact release resets")
	var lead := await _prepare_repair()
	var press := _interact_event(false)
	Input.parse_input_event(press)
	await _frames(61)
	_check(_caravan.repair_progress() > 0.6, "dopo 1 s tenuto il progresso supera 0,6 (%.2f)" % _caravan.repair_progress())
	await _release_interact(press)
	_check(_caravan.repair_progress() == 0.0 and _caravan.carried == 3 and lead.is_broken(),
		"rilasciato: progresso 0, 3 rottami, ancora guasta")


## Una ripetizione automatica di R non e ne rilascio ne nuova pressione.
func _test_interact_echo() -> void:
	print("interact echo")
	await _prepare_repair()
	var press := _interact_event(false)
	Input.parse_input_event(press)
	await _frames(31)
	var before := _caravan.repair_progress()
	var echo := press.duplicate() as InputEventKey
	echo.echo = true
	Input.parse_input_event(echo)
	await _frames(2)
	_check(_player.interact_held and _caravan.repair_progress() > before and _interact_presses == 1,
		"dopo l'eco R resta tenuto, il progresso sale (%.2f -> %.2f), una sola pressione" % [before, _caravan.repair_progress()])
	await _release_interact(press)


## Perdita del focus a meta (Alt-Tab): la tenuta cade subito e il progresso torna a zero.
func _test_interact_focus_out() -> void:
	print("interact focus out")
	await _prepare_repair()
	var press := _interact_event(false)
	Input.parse_input_event(press)
	await _frames(46)
	_check(_caravan.repair_progress() > 0.0, "a meta tenuta il progresso sale (%.2f)" % _caravan.repair_progress())
	_player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not _player.interact_held, "finestra senza focus: Interagisci rilasciato subito")
	await _frames(2)
	_check(_caravan.repair_progress() == 0.0, "e il progresso torna a zero")
	await _release_interact(press)


## La rete di sicurezza vale solo per le pressioni nate da eventi: dopo una pressione e un
## rilascio veri, `interact_held` impostato a mano (bot, catture) resta.
func _test_interact_held_by_hand() -> void:
	print("interact held by hand")
	await _prepare_repair()
	var press := _interact_event(false)
	Input.parse_input_event(press)
	await _frames(2)
	await _release_interact(press)
	_player.interact_held = true
	await _frames(2)
	_check(_player.interact_held, "tenuto a mano dopo un rilascio vero: la rete non lo spegne")
	_player.interact_held = false
	await _frames(2)


## Alla morte del giocatore la tenuta cade subito.
func _test_interact_cleared_at_death() -> void:
	print("interact cleared at death")
	await _prepare_repair()
	var press := _interact_event(false)
	Input.parse_input_event(press)
	await _frames(2)
	_check(_player.interact_held, "R tiene Interagisci")
	_player.set_max_health(1)
	_player.take_damage(1)
	_check(not _player.is_alive() and not _player.interact_held, "giocatore morto: Interagisci rilasciato subito")
	await _release_interact(press)


## Ogni caso parte uguale: Interagisci rilasciato, contatore azzerato, 3 rottami, capofila
## guasto a 1,2 m dal giocatore.
func _prepare_repair() -> Machine:
	_player.interact_held = false
	_interact_presses = 0
	_caravan.carried = 3
	var lead := _caravan.lead()
	if lead.is_broken():
		lead.repair(1.0)
	var q := _player.global_position + Vector3(1.2, 0.0, 0.0)
	lead.global_position = Vector3(q.x, _field.height_at(q) + Caravan.GROUND_CLEARANCE, q.z)
	lead.velocity = Vector3.ZERO
	lead.reset_physics_interpolation()
	_break(lead)
	await _frames(2)
	return lead


func _break(machine: Machine) -> void:
	machine._hit_cooldown_left = 0.0
	machine._invulnerable_left = 0.0
	_check(machine.take_hit(machine.health) and machine.is_broken(), "%s guasto" % machine.primary_module_id())


## Passi fino alla riparazione di [param machine], -1 se non arriva entro [param limit].
func _steps_until_repaired(machine: Machine, limit: int) -> int:
	for i in limit:
		await physics_frame
		if not machine.is_broken():
			return i
	return -1


## Pressione vera di Interagisci: X del controller o R della tastiera.
func _interact_event(joypad: bool) -> InputEvent:
	if joypad:
		var button := InputEventJoypadButton.new()
		button.device = 0
		button.button_index = JOY_BUTTON_X
		button.pressed = true
		return button
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	key.pressed = true
	return key


func _release_interact(press: InputEvent) -> void:
	var release := press.duplicate() as InputEvent
	if release is InputEventKey:
		(release as InputEventKey).pressed = false
	else:
		(release as InputEventJoypadButton).pressed = false
	Input.parse_input_event(release)
	await _frames(2)


func _on_interact_pressed() -> void:
	_interact_presses += 1


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(640.0, 400.0)
	event.global_position = event.position
	Input.parse_input_event(event)


func _joy_motion(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _load_scene() -> void:
	var scene := SmokeTestScene.instantiate()
	scene.name = "Scene"
	root.add_child(scene)
	_player = scene.get_node("Player")
	_field = scene.get_node("TerrainField")
	await _frames(2)


func _reload_scene() -> void:
	root.get_node("Scene").free()
	await _load_scene()


func _load_ruins_scene() -> void:
	var scene := RuinsScene.instantiate()
	scene.name = "Scene"
	root.add_child(scene)
	_player = scene.get_node("Player")
	_field = scene.get_node("TerrainField")
	_caravan = scene.get_node("Caravan")
	_player.interact_pressed.connect(_on_interact_pressed)
	await _frames(2)


## I valori attesi sono quelli del riferimento Unreal, non del preset di default.
func _use_reference_tuning(player: PlayerCharacter) -> void:
	player.apply_tuning(load("res://resources/tuning/player_default.tres"))


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
