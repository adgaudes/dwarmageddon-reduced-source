extends CanvasLayer
## Pausa globale con accesso alle impostazioni, ritorno al menu e uscita dal gioco.
## Il menu iniziale (D-051) la disattiva e ne riusa il pannello Impostazioni.

## Il pannello Impostazioni aperto da solo (dal menu iniziale) e stato chiuso.
signal settings_closed

const MAIN_MENU_SCENE := "res://scenes/main/main_menu.tscn"

## Falso nel menu iniziale: il tasto pausa non fa nulla.
var enabled := true
var _settings_only := false
var _menu_button: Button
var _prompts: ButtonPrompts

@onready var _overlay: Control = %Overlay
@onready var _pause_panel: PanelContainer = %PausePanel
@onready var _settings_panel: SettingsMenu = %SettingsPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
## Uscita dal gioco; i test la sostituiscono per non chiudere il processo.
var quit_action: Callable = func() -> void: get_tree().quit()
## Pulsante in attesa di conferma (audit U-02): Menu ed Esci chiedono una seconda pressione,
## cosi croce giu, giu, A dopo Riprendi non chiude la run per sbaglio.
var _armed: Button = null
var _armed_text := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.hide()
	_resume_button.pressed.connect(resume_game)
	_settings_button.pressed.connect(open_settings)
	_quit_button.pressed.connect(func() -> void: _confirm(_quit_button, "Premi di nuovo per uscire", quit_game))
	_menu_button = Button.new()
	_menu_button.name = "MenuButton"
	_menu_button.text = "Torna al menu"
	_menu_button.theme_type_variation = &"MainButton"
	_menu_button.custom_minimum_size = _settings_button.custom_minimum_size
	_menu_button.pressed.connect(func() -> void: _confirm(_menu_button, "Premi di nuovo: torna al menu", return_to_menu))
	_quit_button.add_sibling(_menu_button)
	_menu_button.get_parent().move_child(_menu_button, _quit_button.get_index())
	_settings_panel.back_requested.connect(_show_pause_panel)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_prompts = ButtonPrompts.create([[&"ui_accept", "Conferma"], [&"ui_cancel", "Indietro"]])
	_overlay.add_child(_prompts)
	_prompts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 28)
	_prompts.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _fx() -> UiFxService:
	return get_node_or_null(^"/root/UiFx") as UiFxService


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _fx() != null and _fx().is_transitioning:
		return
	# Esc e insieme `pause` e `ui_cancel`: a pannello aperto vale "Indietro", come B sul
	# controller (chiude le Impostazioni anche nel menu iniziale, dove la pausa e spenta).
	if _overlay.visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _fx() != null:
			_fx().play(&"ui_back")
		if _settings_panel.visible:
			_show_pause_panel()
		elif not _settings_only:
			resume_game()
	elif event.is_action_pressed(&"pause"):
		if not enabled:
			return
		# Gioco fermato da altro (level-up, fine run): la pausa non lo riattiva.
		if get_tree().paused and not is_open():
			return
		get_viewport().set_input_as_handled()
		if is_open():
			resume_game()
		else:
			pause_game()


## Ferma il gioco e porta il focus su Riprendi.
func pause_game() -> void:
	_disarm()
	get_tree().paused = true
	_overlay.show()
	_show_pause_panel()
	if _fx() != null:
		_fx().pop_in(_pause_panel)


## Nasconde la UI prima di riattivare il gameplay.
func resume_game() -> void:
	_disarm()
	_overlay.hide()
	get_viewport().gui_release_focus()
	get_tree().paused = false


func open_settings() -> void:
	_pause_panel.hide()
	# Il pannello Impostazioni arriva quasi al bordo a 800 px (Steam Deck): i prompt
	# in basso si sovrapporrebbero, e il pannello ha gia il pulsante Indietro (U-09).
	_prompts.hide()
	_settings_panel.open()
	if _fx() != null:
		_fx().pop_in(_settings_panel)


## Solo le Impostazioni, senza mettere in pausa: usato dal menu iniziale.
## Alla chiusura emette `settings_closed`.
func open_settings_only() -> void:
	_settings_only = true
	_overlay.show()
	open_settings()


## Abbandona il livello in corso e torna al menu iniziale.
func return_to_menu() -> void:
	_overlay.hide()
	get_viewport().gui_release_focus()
	_abandon_current_run()
	if _fx() != null:
		_fx().fade_to_scene(MAIN_MENU_SCENE)
	else:
		get_tree().paused = false
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Esce dal gioco; come "Torna al menu" la run in corso incassa prima la sua quota (audit U-02).
func quit_game() -> void:
	_abandon_current_run()
	quit_action.call()


## Abbandono a meta run: la run incassa la quota di morte prima di sparire (R-20).
func _abandon_current_run() -> void:
	var scene := get_tree().current_scene
	var run := scene.find_child("Run", false, false) if scene != null else null
	if run != null and run.has_method(&"abandon_run"):
		run.call(&"abandon_run")


## Prima pressione: il pulsante chiede conferma; seconda pressione sullo stesso: esegue.
func _confirm(button: Button, prompt: String, action: Callable) -> void:
	if _armed == button:
		_disarm()
		action.call()
		return
	_disarm()
	_armed = button
	_armed_text = button.text
	button.text = prompt


func _disarm() -> void:
	if _armed != null and is_instance_valid(_armed):
		_armed.text = _armed_text
	_armed = null


func _on_focus_changed(control: Control) -> void:
	if control != _armed:
		_disarm()


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func focused_control() -> Control:
	return get_viewport().gui_get_focus_owner()


func _show_pause_panel() -> void:
	_settings_panel.hide()
	_prompts.show()
	if _settings_only:
		_settings_only = false
		_overlay.hide()
		settings_closed.emit()
		return
	_pause_panel.show()
	_resume_button.grab_focus()
