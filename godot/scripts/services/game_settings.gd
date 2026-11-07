class_name GameSettingsService
extends Node
## Impostazioni persistenti del gioco e loro applicazione ai servizi Godot.
## Registrato come autoload `GameSettings`; altri script lo raggiungono con
## `get_node("/root/GameSettings")` tipizzato `GameSettingsService`, perche il nome
## globale dell'autoload non esiste in --check-only ne nei test.
##
## Dal restyling 2026-10-11 (D-077): preset grafici (Steam Deck, Basso, Medio, Alto,
## Massimo, Personalizzato) con ogni opzione regolabile una a una (la tabella e in
## GraphicsQuality), file versionato che conserva chiavi e sezioni sconosciute, limite
## di fps fino a 240 e Illimitato con default 60, preset Deck scelto da solo al primo
## avvio sul Deck.

signal changed

enum WindowModeChoice { WINDOWED, EXCLUSIVE_FULLSCREEN, BORDERLESS_FULLSCREEN }
enum Preset { STEAM_DECK, LOW, MEDIUM, HIGH, MAX, CUSTOM }

## Versione del file: le voci sconosciute si conservano e si riscrivono.
const VERSION := 2
const DEFAULT_FPS_CAP := 60
const DEFAULT_VSYNC_MODE := DisplayServer.VSYNC_MAILBOX
const DEFAULT_MSAA_3D := Viewport.MSAA_4X
const DEFAULT_RENDER_SCALE := 1.0
const DEFAULT_WINDOW_MODE := WindowModeChoice.WINDOWED
const DEFAULT_PRESET := Preset.HIGH
const DEFAULT_MASTER_VOLUME := 1.0
const DEFAULT_SFX_VOLUME := 0.8
const MASTER_BUS := &"Master"
const SFX_BUS := &"SFX"
## Eventi del mondo per livello (D-097): scelte possibili e predefinita.
const WORLD_EVENT_COUNTS: Array[int] = [1, 2, 3, 4, 5]
const DEFAULT_WORLD_EVENT_COUNT := 1
## 0 = Illimitato, in cima alla scala (scelta del proprietario, 11 ottobre 2026).
const FPS_CAPS: Array[int] = [30, 60, 90, 120, 144, 165, 240, 0]
const MSAA_MODES: Array[int] = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
const VSYNC_MODES: Array[int] = [DisplayServer.VSYNC_MAILBOX, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_DISABLED]
const WINDOW_MODES: Array[int] = [WindowModeChoice.WINDOWED, WindowModeChoice.EXCLUSIVE_FULLSCREEN, WindowModeChoice.BORDERLESS_FULLSCREEN]
const PRESET_VALUES: Array[int] = [Preset.STEAM_DECK, Preset.LOW, Preset.MEDIUM, Preset.HIGH, Preset.MAX, Preset.CUSTOM]
## Campi di qualita governati dai preset (nome -> valore massimo per gli interi).
const QUALITY_RANGES: Dictionary = {
	"screen_aa": 2, "shadow_quality": 3, "ssao_quality": 2, "gi_mode": 2, "glow_quality": 2,
	"texture_quality": 1, "vegetation_density": 2,
}
## Chiavi note per sezione: tutto il resto si conserva com'e.
const KNOWN_KEYS: Dictionary = {
	"graphics": ["version", "fps_cap", "vsync_mode", "msaa_3d", "render_scale", "window_mode", "preset",
		"preset_chosen", "screen_aa", "shadow_quality", "ssao_quality", "gi_mode", "glow_quality",
		"volumetric_fog", "texture_quality", "vegetation_density", "fsr_upscaling"],
	"controls": ["invert_aim_x", "invert_aim_y", "camera_distance", "manual_aim"],
	"audio": ["master_volume", "sfx_volume"],
	"gameplay": ["world_event_count", "quake_enabled", "train_enabled", "night_enabled"],
}

var settings_path := "user://settings.cfg"
var fps_cap := DEFAULT_FPS_CAP
var vsync_mode := DEFAULT_VSYNC_MODE
var msaa_3d := DEFAULT_MSAA_3D
var render_scale := DEFAULT_RENDER_SCALE
var window_mode := DEFAULT_WINDOW_MODE
## Preset grafico corrente; CUSTOM quando un'opzione e stata toccata a mano.
var preset: int = DEFAULT_PRESET
## True dopo che il giocatore (o il rilevamento del Deck) ha scelto un preset.
var preset_chosen := false
## 0 off, 1 FXAA, 2 TAA.
var screen_aa := 0
## 0 off, 1 bassa (1 split 1024), 2 media (2 split 2048), 3 alta (4 split 4096).
var shadow_quality := 2
## 0 off, 1 bassa, 2 alta.
var ssao_quality := 2
## 0 off, 1 SSIL, 2 SDFGI.
var gi_mode := 1
## 0 off, 1 basso, 2 alto.
var glow_quality := 2
var volumetric_fog := false
## 0 bassa (mip +1), 1 alta.
var texture_quality := 1
## 0 bassa, 1 media, 2 alta.
var vegetation_density := 2
## Upscaling FSR 2 quando la scala di rendering e sotto 1.
var fsr_upscaling := false
var invert_aim_x := false
var invert_aim_y := false
## Mira della chiodatrice (D-089): false = automatica, true = manuale (mouse o stick destro).
var manual_aim := false
## Preset di distanza della camera (D-078): 0 vicina, 1 normale, 2 lontana.
var camera_distance := 1
## Scheda Gameplay (D-097): quanti eventi del mondo per livello (tipo e istante casuali),
## quali eventi possono capitare, e se arriva la notte. Valgono dalla prossima partenza.
var world_event_count := DEFAULT_WORLD_EVENT_COUNT
var quake_enabled := true
var train_enabled := true
var night_enabled := true
## Volumi lineari 0.0-1.0; 0 silenzia il bus.
var master_volume := DEFAULT_MASTER_VOLUME
var sfx_volume := DEFAULT_SFX_VOLUME
## Scritture su disco eseguite (per i test del salvataggio differito).
var save_count := 0

var _save_pending := false
## Sezione -> {chiave: valore} delle voci sconosciute lette dal file, riscritte al salvataggio.
var _unknown: Dictionary = {}


func _ready() -> void:
	# Sotto i test e gli strumenti (SceneTree con script) si parte dai default e si scrive
	# su un file temporaneo per processo: le impostazioni reali del giocatore non devono
	# cambiare l'esito dei test, ne essere riscritte da una suite (review dell'11 ottobre 2026).
	if Engine.get_main_loop().get_script() == null:
		load_settings()
	else:
		settings_path = "user://settings_test_%d.cfg" % OS.get_process_id()
	apply_settings()


func _exit_tree() -> void:
	# Uscita dal gioco con una scrittura ancora in attesa: non si perde.
	_flush_save()
	if settings_path.begins_with("user://settings_test_"):
		for suffix: String in ["", ".tmp", ".bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path + suffix))


## Ripristina i valori iniziali (preset Alto) senza salvare automaticamente.
func reset_to_defaults() -> void:
	fps_cap = DEFAULT_FPS_CAP
	vsync_mode = DEFAULT_VSYNC_MODE
	window_mode = DEFAULT_WINDOW_MODE
	invert_aim_x = false
	invert_aim_y = false
	manual_aim = false
	camera_distance = 1
	world_event_count = DEFAULT_WORLD_EVENT_COUNT
	quake_enabled = true
	train_enabled = true
	night_enabled = true
	master_volume = DEFAULT_MASTER_VOLUME
	sfx_volume = DEFAULT_SFX_VOLUME
	_unknown = {}
	_apply_preset_values(DEFAULT_PRESET)
	preset = DEFAULT_PRESET
	preset_chosen = false


## Steam imposta `SteamDeck=1` nell'ambiente dei giochi avviati sul Deck (anche via Proton).
static func is_steam_deck() -> bool:
	return OS.get_environment("SteamDeck") == "1"


## Carica un file; valori assenti o non validi mantengono i default. Senza file, sul
## Deck parte il preset Steam Deck (non ancora "scelto": si salva al primo cambiamento).
func load_settings(path_override: String = "") -> Error:
	if not path_override.is_empty():
		settings_path = path_override
	reset_to_defaults()
	# Ripiego su .tmp e .bak e copia del file illeggibile (audit S-01/S-02, `ConfigIO`).
	var result := ConfigIO.load_recovering(settings_path)
	var error: Error = result.error
	if error == ERR_FILE_NOT_FOUND:
		_apply_deck_if_unchosen()
		return OK
	if error != OK:
		return error
	var config: ConfigFile = result.config
	if result.source != "main":
		print("PROTOTYPE01_SETTINGS_RECOVERED from=%s" % result.source)
	fps_cap = _validated_int(config.get_value("graphics", "fps_cap", fps_cap), FPS_CAPS, DEFAULT_FPS_CAP)
	vsync_mode = _validated_int(config.get_value("graphics", "vsync_mode", vsync_mode), VSYNC_MODES, DEFAULT_VSYNC_MODE)
	msaa_3d = _validated_int(config.get_value("graphics", "msaa_3d", msaa_3d), MSAA_MODES, DEFAULT_MSAA_3D)
	render_scale = _validated_render_scale(config.get_value("graphics", "render_scale", render_scale))
	window_mode = _validated_int(config.get_value("graphics", "window_mode", window_mode), WINDOW_MODES, DEFAULT_WINDOW_MODE)
	preset = _validated_int(config.get_value("graphics", "preset", preset), PRESET_VALUES, DEFAULT_PRESET)
	preset_chosen = _validated_bool(config.get_value("graphics", "preset_chosen", preset_chosen), false)
	for field: String in QUALITY_RANGES:
		var allowed: Array[int] = []
		for v in QUALITY_RANGES[field] + 1:
			allowed.append(v)
		set(field, _validated_int(config.get_value("graphics", field, get(field)), allowed, get(field)))
	volumetric_fog = _validated_bool(config.get_value("graphics", "volumetric_fog", volumetric_fog), volumetric_fog)
	fsr_upscaling = _validated_bool(config.get_value("graphics", "fsr_upscaling", fsr_upscaling), fsr_upscaling)
	invert_aim_x = _validated_bool(config.get_value("controls", "invert_aim_x", invert_aim_x), false)
	invert_aim_y = _validated_bool(config.get_value("controls", "invert_aim_y", invert_aim_y), false)
	manual_aim = _validated_bool(config.get_value("controls", "manual_aim", manual_aim), false)
	camera_distance = _validated_int(config.get_value("controls", "camera_distance", camera_distance), [0, 1, 2], 1)
	world_event_count = _validated_int(config.get_value("gameplay", "world_event_count", world_event_count), WORLD_EVENT_COUNTS, DEFAULT_WORLD_EVENT_COUNT)
	quake_enabled = _validated_bool(config.get_value("gameplay", "quake_enabled", quake_enabled), true)
	train_enabled = _validated_bool(config.get_value("gameplay", "train_enabled", train_enabled), true)
	night_enabled = _validated_bool(config.get_value("gameplay", "night_enabled", night_enabled), true)
	master_volume = _validated_volume(config.get_value("audio", "master_volume", master_volume), DEFAULT_MASTER_VOLUME)
	sfx_volume = _validated_volume(config.get_value("audio", "sfx_volume", sfx_volume), DEFAULT_SFX_VOLUME)
	_collect_unknown(config)
	_apply_deck_if_unchosen()
	return OK


## Sul Deck il preset Steam Deck vale finche il giocatore non ne sceglie uno (anche con un
## file vecchio, senza le chiavi dei preset).
func _apply_deck_if_unchosen() -> void:
	if preset_chosen or not is_steam_deck():
		return
	_apply_preset_values(Preset.STEAM_DECK)
	preset = Preset.STEAM_DECK


## Salva tutti i valori correnti nel percorso configurato, piu le voci sconosciute.
func save_settings(path_override: String = "") -> Error:
	if not path_override.is_empty():
		settings_path = path_override
	var config := ConfigFile.new()
	for section: String in _unknown:
		for key: String in _unknown[section]:
			config.set_value(section, key, _unknown[section][key])
	config.set_value("graphics", "version", VERSION)
	config.set_value("graphics", "fps_cap", fps_cap)
	config.set_value("graphics", "vsync_mode", vsync_mode)
	config.set_value("graphics", "msaa_3d", msaa_3d)
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("graphics", "window_mode", window_mode)
	config.set_value("graphics", "preset", preset)
	config.set_value("graphics", "preset_chosen", preset_chosen)
	for field: String in QUALITY_RANGES:
		config.set_value("graphics", field, get(field))
	config.set_value("graphics", "volumetric_fog", volumetric_fog)
	config.set_value("graphics", "fsr_upscaling", fsr_upscaling)
	config.set_value("controls", "invert_aim_x", invert_aim_x)
	config.set_value("controls", "invert_aim_y", invert_aim_y)
	config.set_value("controls", "manual_aim", manual_aim)
	config.set_value("controls", "camera_distance", camera_distance)
	config.set_value("gameplay", "world_event_count", world_event_count)
	config.set_value("gameplay", "quake_enabled", quake_enabled)
	config.set_value("gameplay", "train_enabled", train_enabled)
	config.set_value("gameplay", "night_enabled", night_enabled)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	save_count += 1
	return ConfigIO.save_atomic(config, settings_path)


## Applica le opzioni grafiche e audio; il viewport esplicito rende la logica testabile.
## Ogni opzione grafica si tocca solo se cambia: rifare la modalita finestra o la
## scala di rendering a ogni passo di un cursore costa un ricreare di buffer (U-05).
func apply_settings(target_viewport: Viewport = null) -> void:
	if Engine.max_fps != fps_cap:
		Engine.max_fps = fps_cap
	# Il display server headless non ha una finestra su cui applicare queste opzioni.
	if DisplayServer.get_name() != "headless":
		if DisplayServer.window_get_vsync_mode() != vsync_mode:
			DisplayServer.window_set_vsync_mode(vsync_mode)
		_apply_window_mode()
	var viewport := target_viewport if target_viewport != null else get_viewport()
	if viewport != null:
		if viewport.msaa_3d != msaa_3d:
			viewport.msaa_3d = msaa_3d
		var wanted_screen_aa := Viewport.SCREEN_SPACE_AA_FXAA if screen_aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
		if viewport.screen_space_aa != wanted_screen_aa:
			viewport.screen_space_aa = wanted_screen_aa
		if viewport.use_taa != (screen_aa == 2):
			viewport.use_taa = screen_aa == 2
		var wanted_mode := Viewport.SCALING_3D_MODE_FSR2 if fsr_upscaling and render_scale < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
		if viewport.scaling_3d_mode != wanted_mode:
			viewport.scaling_3d_mode = wanted_mode
		if not is_equal_approx(viewport.scaling_3d_scale, render_scale):
			viewport.scaling_3d_scale = render_scale
		var wanted_bias := 0.0 if texture_quality == 1 else 1.0
		if not is_equal_approx(viewport.texture_mipmap_bias, wanted_bias):
			viewport.texture_mipmap_bias = wanted_bias
	apply_audio()


## Applica ombre, occlusione, illuminazione globale, bagliore e nebbia volumetrica a un
## Environment e al sole dell'arena (OvergrownArena la chiama e la ripete a ogni `changed`).
func apply_to_world(environment: Environment, sun: DirectionalLight3D) -> void:
	GraphicsQuality.apply(self, environment, sun)


## Moltiplicatore delle istanze di vegetazione (erba, fiori, detriti) per la densita scelta.
func vegetation_multiplier() -> float:
	return GraphicsQuality.VEGETATION[vegetation_density]


## Porta i volumi sui bus audio. Un bus assente dal layout viene ignorato.
func apply_audio() -> void:
	_apply_bus_volume(MASTER_BUS, master_volume)
	_apply_bus_volume(SFX_BUS, sfx_volume)


## Sceglie un preset: imposta tutte le opzioni di qualita in un colpo solo.
func set_preset(value: int) -> void:
	preset = _validated_int(value, PRESET_VALUES, DEFAULT_PRESET)
	if preset != Preset.CUSTOM:
		_apply_preset_values(preset)
	preset_chosen = true
	_apply_and_save()


func set_fps_cap(value: int) -> void:
	fps_cap = _validated_int(value, FPS_CAPS, DEFAULT_FPS_CAP)
	_apply_and_save()


func set_vsync_mode(value: int) -> void:
	vsync_mode = _validated_int(value, VSYNC_MODES, DEFAULT_VSYNC_MODE)
	_apply_and_save()


func set_msaa_3d(value: int) -> void:
	_set_quality(&"msaa_3d", _validated_int(value, MSAA_MODES, DEFAULT_MSAA_3D))


func set_render_scale(value: float) -> void:
	_set_quality(&"render_scale", clampf(value, 0.5, 1.0))


func set_window_mode(value: int) -> void:
	window_mode = _validated_int(value, WINDOW_MODES, DEFAULT_WINDOW_MODE)
	_apply_and_save()


func set_screen_aa(value: int) -> void:
	_set_quality(&"screen_aa", clampi(value, 0, 2))


func set_shadow_quality(value: int) -> void:
	_set_quality(&"shadow_quality", clampi(value, 0, 3))


func set_ssao_quality(value: int) -> void:
	_set_quality(&"ssao_quality", clampi(value, 0, 2))


func set_gi_mode(value: int) -> void:
	_set_quality(&"gi_mode", clampi(value, 0, 2))


func set_glow_quality(value: int) -> void:
	_set_quality(&"glow_quality", clampi(value, 0, 2))


func set_volumetric_fog(value: bool) -> void:
	_set_quality(&"volumetric_fog", value)


func set_texture_quality(value: int) -> void:
	_set_quality(&"texture_quality", clampi(value, 0, 1))


func set_vegetation_density(value: int) -> void:
	_set_quality(&"vegetation_density", clampi(value, 0, 2))


func set_fsr_upscaling(value: bool) -> void:
	_set_quality(&"fsr_upscaling", value)


func set_invert_aim_x(value: bool) -> void:
	invert_aim_x = value
	_save_and_emit()


func set_invert_aim_y(value: bool) -> void:
	invert_aim_y = value
	_save_and_emit()


func set_manual_aim(value: bool) -> void:
	manual_aim = value
	_save_and_emit()


func set_world_event_count(value: int) -> void:
	var clamped := clampi(value, WORLD_EVENT_COUNTS[0], WORLD_EVENT_COUNTS[-1])
	if clamped == world_event_count:
		return
	world_event_count = clamped
	_save_and_emit()


func set_quake_enabled(value: bool) -> void:
	quake_enabled = value
	_save_and_emit()


func set_train_enabled(value: bool) -> void:
	train_enabled = value
	_save_and_emit()


func set_night_enabled(value: bool) -> void:
	night_enabled = value
	_save_and_emit()


## Vero se l'evento [param kind] (`&"quake"`, `&"train"`) e acceso nella scheda Gameplay.
func world_event_enabled(kind: StringName) -> bool:
	match kind:
		&"quake":
			return quake_enabled
		&"train":
			return train_enabled
	return true


func set_camera_distance(value: int) -> void:
	var clamped := clampi(value, 0, 2)
	if clamped == camera_distance:
		return
	camera_distance = clamped
	_save_and_emit()


func set_master_volume(value: float) -> void:
	master_volume = _validated_volume(value, DEFAULT_MASTER_VOLUME)
	apply_audio()
	_save_and_emit()


func set_sfx_volume(value: float) -> void:
	sfx_volume = _validated_volume(value, DEFAULT_SFX_VOLUME)
	apply_audio()
	_save_and_emit()


## Un'opzione di qualita toccata a mano porta il preset a Personalizzato.
func _set_quality(field: StringName, value: Variant) -> void:
	if get(field) == value:
		return
	set(field, value)
	preset = Preset.CUSTOM
	preset_chosen = true
	_apply_and_save()


func _apply_preset_values(which: int) -> void:
	var values: Dictionary = GraphicsQuality.PRESETS[which]
	for key: String in values:
		set(key, values[key])


func _collect_unknown(config: ConfigFile) -> void:
	_unknown = {}
	for section in config.get_sections():
		var known: Array = KNOWN_KEYS.get(section, [])
		for key in config.get_section_keys(section):
			if key in known:
				continue
			if not _unknown.has(section):
				_unknown[section] = {}
			_unknown[section][key] = config.get_value(section, key)


func _apply_and_save() -> void:
	apply_settings()
	_save_and_emit()


## Salvataggio differito: molti setter nello stesso frame (un cursore trascinato)
## producono una sola scrittura a fine frame (U-05).
func _save_and_emit() -> void:
	changed.emit()
	if _save_pending:
		return
	_save_pending = true
	_flush_save.call_deferred()


func _flush_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	var error := save_settings()
	if error != OK:
		push_error("Impossibile salvare le impostazioni: %s" % error_string(error))


func _apply_window_mode() -> void:
	var target := DisplayServer.WINDOW_MODE_WINDOWED
	match window_mode:
		WindowModeChoice.EXCLUSIVE_FULLSCREEN:
			target = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		WindowModeChoice.BORDERLESS_FULLSCREEN:
			target = DisplayServer.WINDOW_MODE_FULLSCREEN
	if DisplayServer.window_get_mode() != target:
		DisplayServer.window_set_mode(target)


static func _apply_bus_volume(bus: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	# linear_to_db(0) e -inf: a zero il bus viene silenziato.
	AudioServer.set_bus_mute(index, volume <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))


static func _validated_volume(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var parsed := float(value)
	return fallback if is_nan(parsed) else clampf(parsed, 0.0, 1.0)


## Solo interi veri: `int("abc")` sarebbe 0, che per il limite fps vale "Illimitato" (U-04).
static func _validated_int(value: Variant, allowed: Array[int], fallback: int) -> int:
	if typeof(value) != TYPE_INT:
		return fallback
	return value if value in allowed else fallback


## Solo booleani veri: `bool("false")` sarebbe true (U-04).
static func _validated_bool(value: Variant, fallback: bool) -> bool:
	return value if typeof(value) == TYPE_BOOL else fallback


static func _validated_render_scale(value: Variant) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return DEFAULT_RENDER_SCALE
	var parsed := float(value)
	return DEFAULT_RENDER_SCALE if is_nan(parsed) else clampf(parsed, 0.5, 1.0)
