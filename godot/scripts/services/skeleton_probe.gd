extends Node3D
## Sonda dello scheletro di progetto (Fase 3 della migrazione).
##
## Non e gameplay: verifica che il progetto parta, che la mappa input sia
## caricata e che la conversione di scala da Unreal sia quella attesa.
## Il movimento ora e del personaggio reale (Fase 5); la sonda resta come
## verifica di avvio e strumento di cattura.

## Fattore di conversione: Unreal lavora in centimetri, Godot in metri.
const UNREAL_UNITS_TO_METERS := 0.01

## Azioni semantiche attese. Il gameplay non deve mai leggere tasti fisici.
const EXPECTED_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"aim_up", &"aim_down", &"aim_left", &"aim_right",
	&"dash", &"terrain_tool", &"terrain_mode", &"pause", &"weapon_aim_mode", &"interact",
]
## Azioni dei menu: in Godot 4.7 nascono senza pulsanti joypad, il progetto le
## ridefinisce con A e B (trappola in GODOT_WORKFLOW.md). Se l'editor rigenera
## project.godot i menu non si confermano piu col controller: qui si controlla.
const MENU_ACTIONS: Array[StringName] = [&"ui_accept", &"ui_cancel"]
## La mira e solo da stick destro: non ha un equivalente tastiera (il mouse punta).
const JOYPAD_ONLY_PREFIX := "aim_"


func _ready() -> void:
	print("PROTOTYPE01_GODOT_SKELETON_READY")
	# Marker del protocollo di smoke test Unreal, conservati per parita.
	print("PROTOTYPE01_SMOKE_TEST_OK")
	_report_input_map()
	_report_scale_reference()
	_capture_if_requested()


## Con `-- --capture=<percorso.png>` salva un PNG del primo frame utile ed esce.
## Richiede una finestra reale: in --headless i frame non vengono disegnati.
func _capture_if_requested() -> void:
	var path := RunLaunchOptions.capture_path()
	if path.is_empty():
		return
	for i in 10:
		await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("PROTOTYPE01_CAPTURE path=%s err=%d" % [path, err])
	get_tree().quit()


## Verifica che ogni azione esista e che, tranne la mira, abbia sia un evento
## tastiera/mouse sia uno joypad: controller e tastiera devono restare equivalenti (U-13).
func _report_input_map() -> void:
	var missing: Array[StringName] = []
	var unbound: Array[StringName] = []
	var incomplete: Array[StringName] = []
	var actions := EXPECTED_ACTIONS + MENU_ACTIONS
	for action in actions:
		if not InputMap.has_action(action):
			missing.append(action)
			continue
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			unbound.append(action)
		elif not String(action).begins_with(JOYPAD_ONLY_PREFIX) and not _has_keyboard_and_joypad(events):
			incomplete.append(action)

	print("PROTOTYPE01_INPUT_ACTIONS total=%d missing=%d unbound=%d incomplete=%d"
		% [actions.size(), missing.size(), unbound.size(), incomplete.size()])
	if missing.is_empty() and unbound.is_empty() and incomplete.is_empty():
		print("PROTOTYPE01_INPUT_READY")
	if not missing.is_empty():
		push_error("Azioni mancanti nella mappa input: %s" % str(missing))
	if not unbound.is_empty():
		push_warning("Azioni senza eventi: %s" % str(unbound))
	if not incomplete.is_empty():
		push_error("Azioni senza tastiera/mouse o senza joypad: %s" % str(incomplete))


static func _has_keyboard_and_joypad(events: Array[InputEvent]) -> bool:
	var keyboard := false
	var joypad := false
	for event in events:
		keyboard = keyboard or event is InputEventKey or event is InputEventMouseButton
		joypad = joypad or event is InputEventJoypadButton or event is InputEventJoypadMotion
	return keyboard and joypad


## Rende esplicita la conversione di scala, principale fonte di errore
## della migrazione (vedi R-G6 in GODOT_MIGRATION_ANALYSIS.md).
func _report_scale_reference() -> void:
	var arena_side_m := 6000.0 * UNREAL_UNITS_TO_METERS
	var camera_arm_m := 1500.0 * UNREAL_UNITS_TO_METERS
	var cell_size_m := 240.0 * UNREAL_UNITS_TO_METERS
	print("PROTOTYPE01_SCALE arena=%.1fm camera_arm=%.1fm cell=%.2fm"
		% [arena_side_m, camera_arm_m, cell_size_m])

