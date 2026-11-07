class_name SettingsMenu
extends PanelContainer
## Pannello impostazioni navigabile con controller, tastiera e mouse.
## Dal restyling 2026-10-11: preset grafico in testa, opzioni di qualita una a una (una
## modifica porta il preset a Personalizzato), limite di fps fino a 240 e Illimitato,
## contenuto scorrevole che segue il focus.
## Dal playtest del 14 ottobre 2026 (O-11): tre schede (Grafica, Audio, Controlli) al posto
## di una lista unica, etichette centrate accanto ai menu, interruttori in colonna con le
## altre righe, mira manuale della chiodatrice (D-089). Le schede si costruiscono qui sopra
## le righe della scena: nomi unici e percorsi restano quelli di prima.

signal back_requested

@onready var _preset_option: OptionButton = %PresetOption
@onready var _fps_option: OptionButton = %FpsOption
@onready var _vsync_option: OptionButton = %VsyncOption
@onready var _msaa_option: OptionButton = %MsaaOption
@onready var _window_option: OptionButton = %WindowOption
@onready var _scale_option: OptionButton = %ScaleOption
@onready var _shadow_option: OptionButton = %ShadowOption
@onready var _ssao_option: OptionButton = %SsaoOption
@onready var _gi_option: OptionButton = %GiOption
@onready var _glow_option: OptionButton = %GlowOption
@onready var _volumetric_check: CheckButton = %VolumetricCheck
@onready var _texture_option: OptionButton = %TextureOption
@onready var _vegetation_option: OptionButton = %VegetationOption
@onready var _screen_aa_option: OptionButton = %ScreenAaOption
@onready var _fsr_check: CheckButton = %FsrCheck
@onready var _master_volume: HSlider = %MasterVolume
@onready var _master_value: Label = %MasterVolumeValue
@onready var _sfx_volume: HSlider = %SfxVolume
@onready var _sfx_value: Label = %SfxVolumeValue
@onready var _camera_option: OptionButton = %CameraOption
@onready var _invert_x: CheckButton = %InvertX
@onready var _invert_y: CheckButton = %InvertY
@onready var _back_button: Button = %BackButton
@onready var _settings: GameSettingsService = get_node(^"/root/GameSettings")

const TABS: Array[Array] = [["Gameplay", &"GameplayHeader"], ["Grafica", &"GraphicsHeader"], ["Audio", &"AudioHeader"],
	["Controlli", &"ControlsHeader"]]
const LABEL_WIDTH := 300.0
var _tab_buttons: Array[Button] = []
var _tab_rows: Array[Array] = [[], [], [], []]
var current_tab := 0
var _manual_aim_check: CheckButton
## Scheda Gameplay (D-097), costruita nel codice come la mira manuale.
var _world_events_option: OptionButton
var _quake_check: CheckButton
var _train_check: CheckButton
var _night_check: CheckButton

const RENDER_SCALES: Array[float] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
const PRESET_LABELS: Array[String] = ["Steam Deck", "Basso", "Medio", "Alto (predefinito)", "Massimo", "Personalizzato"]


func _ready() -> void:
	_fill_options()
	_preset_option.item_selected.connect(_on_preset_selected)
	_fps_option.item_selected.connect(_on_fps_selected)
	_vsync_option.item_selected.connect(_on_vsync_selected)
	_msaa_option.item_selected.connect(_on_msaa_selected)
	_window_option.item_selected.connect(_on_window_selected)
	_scale_option.item_selected.connect(_on_scale_selected)
	_shadow_option.item_selected.connect(_on_quality_selected.bind(_settings.set_shadow_quality))
	_ssao_option.item_selected.connect(_on_quality_selected.bind(_settings.set_ssao_quality))
	_gi_option.item_selected.connect(_on_quality_selected.bind(_settings.set_gi_mode))
	_glow_option.item_selected.connect(_on_quality_selected.bind(_settings.set_glow_quality))
	_texture_option.item_selected.connect(_on_quality_selected.bind(_settings.set_texture_quality))
	_vegetation_option.item_selected.connect(_on_quality_selected.bind(_settings.set_vegetation_density))
	_screen_aa_option.item_selected.connect(_on_quality_selected.bind(_settings.set_screen_aa))
	_volumetric_check.toggled.connect(_on_quality_toggled.bind(_settings.set_volumetric_fog))
	_fsr_check.toggled.connect(_on_quality_toggled.bind(_settings.set_fsr_upscaling))
	_master_volume.value_changed.connect(_on_master_volume_changed)
	_sfx_volume.value_changed.connect(_on_sfx_volume_changed)
	_camera_option.item_selected.connect(_on_camera_selected)
	_invert_x.toggled.connect(_settings.set_invert_aim_x)
	_invert_y.toggled.connect(_settings.set_invert_aim_y)
	_back_button.pressed.connect(func(): back_requested.emit())
	_build_tabs()


## Righe in colonna e schede (O-11).
func _build_tabs() -> void:
	var content: VBoxContainer = %Content
	_build_gameplay_rows(content)
	for check: CheckButton in [_volumetric_check, _fsr_check, _manual_aim_check, _quake_check, _train_check, _night_check,
			_invert_x, _invert_y]:
		_wrap_check(content, check)
	for row in content.get_children():
		if row is HBoxContainer:
			_align_row(row)
	# Righe per scheda: tutto cio che sta fra un'intestazione e la successiva.
	var section := -1
	for child in content.get_children():
		for i in TABS.size():
			if child.name == TABS[i][1]:
				section = i
		if child == _back_button or child.name == &"Title" or section < 0:
			continue
		_tab_rows[section].append(child)
	var bar := HBoxContainer.new()
	bar.name = "Tabs"
	bar.add_theme_constant_override(&"separation", 8)
	content.add_child(bar)
	content.move_child(bar, content.get_node(^"Title").get_index() + 1)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var tab := Button.new()
		tab.name = "Tab%d" % i
		tab.text = TABS[i][0]
		tab.theme_type_variation = &"MainButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size = Vector2(0, 46)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_tab.bind(i))
		bar.add_child(tab)
		_tab_buttons.append(tab)
	show_tab(0)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Se il focus arriva su una riga di un'altra scheda (mouse, codice), si passa a quella.
func _on_focus_changed(control: Control) -> void:
	if control == null or not is_visible_in_tree():
		return
	for i in _tab_rows.size():
		if i == current_tab:
			continue
		for row: Control in _tab_rows[i]:
			if row == control or row.is_ancestor_of(control):
				show_tab(i)
				return


## Scheda Gameplay (D-097), prima delle altre: quanti eventi del mondo per livello, quali
## possono capitare, la notte e la mira manuale (spostata dai Controlli: e una scelta di gioco).
func _build_gameplay_rows(content: VBoxContainer) -> void:
	var at := content.get_node(^"GraphicsHeader").get_index()
	var header := Label.new()
	header.name = "GameplayHeader"
	header.theme_type_variation = &"SectionLabel"
	header.text = "Gameplay"
	var count_row := HBoxContainer.new()
	count_row.name = "WorldEventsRow"
	var count_label := Label.new()
	count_label.name = "Label"
	count_label.text = "Eventi del mondo per livello"
	count_row.add_child(count_label)
	_world_events_option = OptionButton.new()
	_world_events_option.name = "WorldEventsOption"
	_world_events_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for count in GameSettingsService.WORLD_EVENT_COUNTS:
		_world_events_option.add_item("%d%s" % [count, " (predefinito)" if count == GameSettingsService.DEFAULT_WORLD_EVENT_COUNT else ""])
	_world_events_option.item_selected.connect(_on_world_events_selected)
	count_row.add_child(_world_events_option)
	_quake_check = _new_check("QuakeCheck", "Terremoto", _settings.set_quake_enabled)
	_train_check = _new_check("TrainCheck", "Treno (ferrovia)", _settings.set_train_enabled)
	_night_check = _new_check("NightCheck", "Notte", _settings.set_night_enabled)
	_manual_aim_check = _new_check("ManualAim", "Mira manuale della chiodatrice", _settings.set_manual_aim)
	var note := Label.new()
	note.name = "GameplayNote"
	note.theme_type_variation = &"MutedLabel"
	note.text = "Eventi casuali: tipo e momento cambiano a ogni livello. Le scelte valgono dalla prossima partenza."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var nodes: Array[Control] = [header, count_row, _quake_check, _train_check, _night_check, _manual_aim_check, note]
	for node in nodes:
		content.add_child(node)
		content.move_child(node, at)
		at += 1


func _new_check(node_name: String, text: String, setter: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.name = node_name
	check.text = text
	check.custom_minimum_size = Vector2(0, 40)
	check.toggled.connect(setter)
	return check


func _on_world_events_selected(index: int) -> void:
	_settings.set_world_event_count(GameSettingsService.WORLD_EVENT_COUNTS[index])


## Un interruttore diventa una riga come le altre: etichetta a sinistra, levetta a destra.
func _wrap_check(content: VBoxContainer, check: CheckButton) -> void:
	var row := HBoxContainer.new()
	row.name = "%sRow" % check.name
	content.add_child(row)
	content.move_child(row, check.get_index())
	var label := Label.new()
	label.name = "Label"
	label.text = check.text
	row.add_child(label)
	check.text = ""
	check.reparent(row, false)
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.alignment = HORIZONTAL_ALIGNMENT_RIGHT


## Etichetta larga uguale per tutte le righe, centrata in altezza sul controllo e a capo
## se lunga: prima stava in alto e le piu lunghe spingevano il menu a destra (O-11).
func _align_row(row: HBoxContainer) -> void:
	row.add_theme_constant_override(&"separation", 16)
	var label := row.get_node_or_null(^"Label") as Label
	if label == null:
		return
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.size_flags_horizontal = Control.SIZE_FILL
	label.size_flags_vertical = Control.SIZE_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Mostra le righe della scheda [param index] e nasconde le altre.
func show_tab(index: int) -> void:
	current_tab = clampi(index, 0, TABS.size() - 1)
	for i in _tab_rows.size():
		for node: Control in _tab_rows[i]:
			# Intestazioni e linee le sostituiscono le schede.
			var is_header := String(node.name).ends_with("Header") or String(node.name).ends_with("Rule")
			node.visible = i == current_tab and not is_header
	if current_tab < _tab_buttons.size():
		_tab_buttons[current_tab].set_pressed_no_signal(true)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var step := 0
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEUP:
			step = -1
		elif event.keycode == KEY_PAGEDOWN:
			step = 1
	if step != 0:
		get_viewport().set_input_as_handled()
		show_tab(posmod(current_tab + step, TABS.size()))
		_tab_buttons[current_tab].grab_focus()


## Sincronizza i controlli e mette il focus sulla prima opzione.
func open() -> void:
	_sync_from_settings()
	show()
	show_tab(0)
	_world_events_option.grab_focus()


func focused_control() -> Control:
	return get_viewport().gui_get_focus_owner()


func _fill_options() -> void:
	_add_items(_preset_option, PRESET_LABELS)
	_add_items(_fps_option, ["30", "60 (predefinito)", "90", "120", "144", "165", "240", "Illimitato"])
	_add_items(_vsync_option, ["Mailbox (predefinito)", "Classico", "Off"])
	_add_items(_msaa_option, ["Off", "2x", "4x (predefinito)", "8x"])
	_add_items(_window_option, ["Finestra", "Schermo intero", "Finestra senza bordi"])
	_add_items(_scale_option, ["50%", "60%", "70%", "80%", "90%", "100% (predefinito)"])
	_add_items(_shadow_option, ["Off", "Bassa", "Media", "Alta"])
	_add_items(_ssao_option, ["Off", "Bassa", "Alta"])
	_add_items(_gi_option, ["Off", "SSIL", "SDFGI"])
	_add_items(_glow_option, ["Off", "Basso", "Alto"])
	_add_items(_texture_option, ["Bassa", "Alta"])
	_add_items(_vegetation_option, ["Bassa", "Media", "Alta"])
	_add_items(_screen_aa_option, ["Off", "FXAA", "TAA"])
	_add_items(_camera_option, ["Vicina", "Normale (predefinita)", "Lontana"])


func _add_items(option: OptionButton, labels: Array[String]) -> void:
	for label in labels:
		option.add_item(label)


func _sync_from_settings() -> void:
	_preset_option.select(_settings.preset)
	_fps_option.select(GameSettingsService.FPS_CAPS.find(_settings.fps_cap))
	_vsync_option.select(GameSettingsService.VSYNC_MODES.find(_settings.vsync_mode))
	_msaa_option.select(GameSettingsService.MSAA_MODES.find(_settings.msaa_3d))
	_window_option.select(GameSettingsService.WINDOW_MODES.find(_settings.window_mode))
	_scale_option.select(_closest_scale_index(_settings.render_scale))
	_shadow_option.select(_settings.shadow_quality)
	_ssao_option.select(_settings.ssao_quality)
	_gi_option.select(_settings.gi_mode)
	_glow_option.select(_settings.glow_quality)
	_volumetric_check.set_pressed_no_signal(_settings.volumetric_fog)
	_texture_option.select(_settings.texture_quality)
	_vegetation_option.select(_settings.vegetation_density)
	_screen_aa_option.select(_settings.screen_aa)
	_fsr_check.set_pressed_no_signal(_settings.fsr_upscaling)
	_master_volume.set_value_no_signal(_settings.master_volume)
	_sfx_volume.set_value_no_signal(_settings.sfx_volume)
	_refresh_volume_labels()
	_camera_option.select(_settings.camera_distance)
	_invert_x.set_pressed_no_signal(_settings.invert_aim_x)
	_invert_y.set_pressed_no_signal(_settings.invert_aim_y)
	if _manual_aim_check != null:
		_manual_aim_check.set_pressed_no_signal(_settings.manual_aim)
		_world_events_option.select(GameSettingsService.WORLD_EVENT_COUNTS.find(_settings.world_event_count))
		_quake_check.set_pressed_no_signal(_settings.quake_enabled)
		_train_check.set_pressed_no_signal(_settings.train_enabled)
		_night_check.set_pressed_no_signal(_settings.night_enabled)


## Un preset riscrive tutte le opzioni di qualita: si risincronizzano le righe.
func _on_preset_selected(index: int) -> void:
	if index != _settings.preset:
		_settings.set_preset(index)
		_sync_from_settings()


# Riselezionare la voce gia attiva non tocca il servizio: niente riapplicazione
# della grafica ne scrittura su disco (U-05).
func _on_fps_selected(index: int) -> void:
	if GameSettingsService.FPS_CAPS[index] != _settings.fps_cap:
		_settings.set_fps_cap(GameSettingsService.FPS_CAPS[index])


func _on_vsync_selected(index: int) -> void:
	if GameSettingsService.VSYNC_MODES[index] != _settings.vsync_mode:
		_settings.set_vsync_mode(GameSettingsService.VSYNC_MODES[index])


func _on_window_selected(index: int) -> void:
	if GameSettingsService.WINDOW_MODES[index] != _settings.window_mode:
		_settings.set_window_mode(GameSettingsService.WINDOW_MODES[index])


func _on_msaa_selected(index: int) -> void:
	if GameSettingsService.MSAA_MODES[index] != _settings.msaa_3d:
		_settings.set_msaa_3d(GameSettingsService.MSAA_MODES[index])
		_preset_option.select(_settings.preset)


func _on_scale_selected(index: int) -> void:
	if not is_equal_approx(RENDER_SCALES[index], _settings.render_scale):
		_settings.set_render_scale(RENDER_SCALES[index])
		_preset_option.select(_settings.preset)


## Opzione di qualita a indice: il setter del servizio decide se e un cambiamento e
## porta il preset a Personalizzato; la riga del preset lo riflette.
func _on_quality_selected(index: int, setter: Callable) -> void:
	setter.call(index)
	_preset_option.select(_settings.preset)


func _on_quality_toggled(pressed: bool, setter: Callable) -> void:
	setter.call(pressed)
	_preset_option.select(_settings.preset)


func _on_camera_selected(index: int) -> void:
	if index != _settings.camera_distance:
		_settings.set_camera_distance(index)


func _on_master_volume_changed(value: float) -> void:
	if not is_equal_approx(value, _settings.master_volume):
		_settings.set_master_volume(value)
	_refresh_volume_labels()


func _on_sfx_volume_changed(value: float) -> void:
	if not is_equal_approx(value, _settings.sfx_volume):
		_settings.set_sfx_volume(value)
	_refresh_volume_labels()


func _refresh_volume_labels() -> void:
	_master_value.text = "%d%%" % roundi(_master_volume.value * 100.0)
	_sfx_value.text = "%d%%" % roundi(_sfx_volume.value * 100.0)


func _closest_scale_index(value: float) -> int:
	var closest := 0
	var distance := INF
	for index in RENDER_SCALES.size():
		var candidate_distance := absf(RENDER_SCALES[index] - value)
		if candidate_distance < distance:
			distance = candidate_distance
			closest = index
	return closest
