class_name UiFxService
extends CanvasLayer
## Autoload UiFx (D-081): feedback dell'interfaccia per tutte le schermate. Cursore a
## chiodo che segue il Control con il focus, suoni (ui_move, ui_confirm, ui_back,
## ui_open), rimbalzo dei pulsanti premuti, pop-in dei pannelli e velo per le
## transizioni di scena. Sopra a tutto (layer 110), attivo anche a gioco fermo.
## Gli script lo raggiungono con `get_node_or_null(^"/root/UiFx") as UiFxService`.

const FADE_OUT_SECONDS := 0.25
const FADE_IN_SECONDS := 0.35
const CURSOR_SECONDS := 0.09
const CURSOR_SIZE := 26.0
const CURSOR_GAP := 10.0
const POP_SECONDS := 0.15

var cursor_enabled := true
var is_transitioning := false

var _veil: ColorRect
var _cursor: UiIcon
var _target: Control
var _audio: AudioStreamPlayer
var _streams: Dictionary[StringName, AudioStream] = {}
var _play_counts: Dictionary[StringName, int] = {}
var _scene_changes := 0
var _time := 0.0
var _last_sound_frame := -1
var _pulsed: Control


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cursor = UiIcon.make(&"arrow_right", CURSOR_SIZE, UiPalette.BORDER_LIGHT)
	_cursor.name = "Cursor"
	_cursor.size = Vector2(CURSOR_SIZE, CURSOR_SIZE)
	_cursor.visible = false
	add_child(_cursor)
	# Il velo sta sopra il cursore e, durante la transizione, ferma l'input.
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.color = Color(UiPalette.BG, 0.0)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.visible = false
	add_child(_veil)
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	_audio.max_polyphony = 4
	add_child(_audio)
	get_tree().node_added.connect(_on_node_added)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	# I pulsanti gia nell'albero (autoload caricati prima, come PauseMenu).
	_hook_existing(get_tree().root)


func _hook_existing(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_hook_existing(child)


## Vero se [param button] ha il feedback di UiFx collegato.
func is_hooked(button: BaseButton) -> bool:
	return button.pressed.is_connected(_on_button_pressed.bind(button))


func polyphony() -> int:
	return _audio.max_polyphony


## Durante una transizione tutto l'input si ferma: niente pausa sopra la scena nuova.
func _input(event: InputEvent) -> void:
	if is_transitioning and not event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


func cursor_target() -> Control:
	return _target if is_instance_valid(_target) else null


func cursor_visible() -> bool:
	return _cursor.visible


func cursor_position() -> Vector2:
	return _cursor.position + _cursor.size * 0.5


func veil_alpha() -> float:
	return _veil.color.a


func scene_changes() -> int:
	return _scene_changes


func play_count(id: StringName) -> int:
	return _play_counts.get(id, 0)


## Suono di interfaccia; sintetizzato alla prima richiesta e tenuto in cache.
func play(id: StringName, volume_db := -8.0) -> void:
	# Il tic del cursore cede il passo: se nello stesso frame suona gia un'altra cosa
	# (conferma, pannello che si apre) non si sente un tic sopra.
	var frame := Engine.get_process_frames()
	if id == &"ui_move" and _last_sound_frame == frame:
		return
	_last_sound_frame = frame
	_play_counts[id] = play_count(id) + 1
	if not _streams.has(id):
		var stream := SfxLibrary.build(id)
		if stream == null:
			return
		_streams[id] = stream
	_audio.stream = _streams[id]
	_audio.volume_db = volume_db
	_audio.play()


## Un pannello che si apre: scala 0,96 -> 1 e alpha 0 -> 1, anche a gioco fermo.
func pop_in(control: Control) -> void:
	if control == null:
		return
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.96, 0.96)
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	# Il pivot si ricalcola a ogni passo: al primo frame il layout puo non esserci ancora.
	tween.tween_method(func(value: float) -> void:
		control.pivot_offset = control.size * 0.5
		control.scale = Vector2(value, value), 0.96, 1.0, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, POP_SECONDS)
	play(&"ui_open", -10.0)


## Cambio di scena con il velo: chiude in 0,25 s, cambia, riapre in 0,35 s.
func fade_to_scene(path: String) -> void:
	_transition(func() -> void:
		_scene_changes += 1
		get_tree().change_scene_to_file(path))


func fade_reload() -> void:
	_transition(func() -> void:
		_scene_changes += 1
		get_tree().reload_current_scene())


func _transition(change: Callable) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_hide_cursor()
	_veil.visible = true
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_veil, "color:a", 1.0, FADE_OUT_SECONDS)
	tween.tween_callback(func() -> void:
		get_tree().paused = false
		change.call())
	tween.tween_interval(0.05)
	tween.tween_property(_veil, "color:a", 0.0, FADE_IN_SECONDS)
	tween.tween_callback(func() -> void:
		_veil.visible = false
		is_transitioning = false)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		if not is_hooked(button):
			button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_pressed(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	play(&"ui_confirm")
	if not button.is_inside_tree():
		return
	# Rimbalzo: 0,97 e ritorno in 80 ms, attorno al centro.
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(button, "scale", Vector2(0.97, 0.97), 0.04)
	tween.tween_property(button, "scale", Vector2.ONE, 0.04)


func _on_focus_changed(control: Control) -> void:
	_target = control
	if not cursor_enabled or control == null or is_transitioning:
		_hide_cursor()
		return
	play(&"ui_move", -12.0)
	if not _cursor.visible:
		# Da nascosto parte gia accanto al bersaglio, un po' piu a sinistra.
		_cursor.position = _cursor_rest(control) - Vector2(24.0, 0.0)
	_cursor.visible = true


func _cursor_rest(control: Control) -> Vector2:
	var rect := control.get_global_rect()
	return Vector2(rect.position.x - CURSOR_SIZE - CURSOR_GAP, rect.position.y + rect.size.y * 0.5 - CURSOR_SIZE * 0.5)


func _hide_cursor() -> void:
	_cursor.visible = false


func _process(delta: float) -> void:
	_time += delta
	var target := cursor_target()
	_pulse(target)
	if target == null or not target.is_visible_in_tree() or not target.has_focus() or is_transitioning or not cursor_enabled:
		_hide_cursor()
		return
	if not _cursor.visible:
		_cursor.visible = true
		_cursor.position = _cursor_rest(target)
	# Insegue il bersaglio ogni frame (anche se si sposta per layout, scroll o pop-in)
	# con un ritardo esponenziale di CURSOR_SECONDS, e oscilla piano.
	var rest := _cursor_rest(target) + Vector2(sin(_time * 6.0) * 2.0, 0.0)
	var k := 1.0 - exp(-delta / (CURSOR_SECONDS * 0.4))
	_cursor.position = _cursor.position.lerp(rest, k)


## Il controllo con il focus respira: self_modulate fra 1 e 1,12, un ciclo ogni 1,6 s.
## Il precedente torna bianco quando perde il focus.
func _pulse(target: Control) -> void:
	if _pulsed != target:
		if is_instance_valid(_pulsed):
			_pulsed.self_modulate = Color.WHITE
		_pulsed = target
	if target == null or not target.has_focus():
		if is_instance_valid(target):
			target.self_modulate = Color.WHITE
		return
	var glow := 1.0 + 0.12 * (0.5 + 0.5 * sin(_time * TAU / 1.6))
	target.self_modulate = Color(glow, glow, glow, 1.0)
