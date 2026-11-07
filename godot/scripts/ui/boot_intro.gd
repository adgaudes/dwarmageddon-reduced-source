class_name BootIntro
extends Control
## Intro all'avvio (D-080): rivelazione del logo in 4 s, saltabile con qualunque
## tasto; poi il menu iniziale. Salta da sola quando la riga di comando chiede un
## livello (`RunLaunchOptions.AUTOSTART_PREFIXES`) o in headless, cosi gate, smoke
## test e catture non la vedono. Aggancio per la vignetta futura: `vignette`, una
## PackedScene che emette `finished`; se impostata, gira prima del logo.

signal finished

const MENU_SCENE := "res://scenes/main/main_menu.tscn"
const WINDOW_TITLE := "Dwarmageddon: Dig or Die"
## Suoni dell'intro, sintetizzati prima che parta l'animazione (niente intoppi a t=0).
const SOUND_IDS: Array[StringName] = [&"quake_rumble", &"terrain_raise", &"nail_shot", &"scrap_pickup"]

@export var vignette: PackedScene
## Test e catture: gira anche in headless e non cambia scena alla fine.
var force_play := false
var change_scene_on_finish := true
var is_playing := false

var _logo: GameLogo
var _ground: ColorRect
var _dust: CPUParticles2D
var _tween: Tween
var _audio: AudioStreamPlayer
var _streams: Dictionary[StringName, AudioStream] = {}
var _fade: ColorRect
var _pause_menu: Node
var _ending := false
var _logo_rest := Vector2.ZERO


static func should_skip(args: PackedStringArray, headless: bool) -> bool:
	if RunLaunchOptions.wants_intro_test(args):
		return false
	return headless or RunLaunchOptions.wants_autostart(args)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_title(WINDOW_TITLE)
	_pause_menu = get_node_or_null(^"/root/PauseMenu")
	var headless := DisplayServer.get_name() == "headless"
	if not force_play and should_skip(OS.get_cmdline_user_args(), headless):
		_go_to_menu()
		return
	if _pause_menu != null:
		_pause_menu.set(&"enabled", false)
	SfxLibrary.precache_async()
	_build()
	is_playing = true
	if vignette != null:
		await _play_vignette()
	if is_playing and not _ending:
		_play_logo()


## Vignetta futura: la scena deve emettere `finished`; se lo fa gia nel proprio
## `_ready` non resta nulla appeso, se non ha il segnale viene saltata con un avviso.
func _play_vignette() -> void:
	var scene := vignette.instantiate()
	if not scene.has_signal(&"finished"):
		push_warning("BootIntro: la vignetta non ha il segnale `finished`, saltata")
		scene.free()
		return
	var done := [false]
	scene.connect(&"finished", func() -> void: done[0] = true)
	add_child(scene)
	while not done[0] and is_playing and not _ending:
		await get_tree().process_frame
	scene.queue_free()


func _exit_tree() -> void:
	# Un suono ancora in riproduzione all'uscita lascerebbe il playback orfano.
	if _audio != null:
		_audio.stop()


func logo() -> GameLogo:
	return _logo


func prebuilt_sound_count() -> int:
	return _streams.size()


## Opacita del velo finale (0 = intro visibile, 1 = colore di fondo pieno).
func fade_alpha() -> float:
	return _fade.color.a if _fade != null else 0.0


## Qualunque tasto, pulsante o click salta alla fine.
func _unhandled_input(event: InputEvent) -> void:
	if not is_playing or _ending:
		return
	if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed():
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	if not is_playing or _ending:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_logo.position = _logo_rest
	_logo.set_all(1.0)
	_finish()


func _build() -> void:
	var background := ColorRect.new()
	background.color = UiPalette.BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_ground = ColorRect.new()
	_ground.color = Color("2a1a10")
	_ground.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_ground.offset_top = 0
	add_child(_ground)
	_dust = CPUParticles2D.new()
	_dust.emitting = false
	_dust.amount = 80
	_dust.one_shot = true
	_dust.explosiveness = 0.9
	_dust.lifetime = 1.6
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(420, 10)
	_dust.direction = Vector2(0, -1)
	_dust.spread = 40.0
	_dust.gravity = Vector2(0, 120)
	_dust.initial_velocity_min = 120.0
	_dust.initial_velocity_max = 260.0
	_dust.scale_amount_min = 2.0
	_dust.scale_amount_max = 5.0
	_dust.color = Color(0.85, 0.6, 0.35, 0.7)
	add_child(_dust)
	_logo = GameLogo.new()
	_logo.letter_size = 96
	add_child(_logo)
	_logo.set_all(0.0)
	_logo_rest = (get_viewport_rect().size - _logo.custom_minimum_size) * 0.5 - Vector2(0, 30)
	_logo.position = _logo_rest
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"SFX"
	add_child(_audio)
	for id in SOUND_IDS:
		var stream := SfxLibrary.build(id)
		if stream != null:
			_streams[id] = stream
	# Velo finale: un ColorRect del colore di fondo che si opacizza (modulate
	# moltiplicherebbe BG per se stesso e finirebbe quasi al nero).
	_fade = ColorRect.new()
	_fade.color = Color(UiPalette.BG, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _play_logo() -> void:
	var viewport_size := get_viewport_rect().size
	_dust.position = Vector2(viewport_size.x * 0.5, _logo_rest.y + _logo.custom_minimum_size.y)
	_tween = create_tween()
	_tween.tween_callback(_sound.bind(&"quake_rumble", -8.0))
	_tween.tween_property(_ground, "offset_top", -viewport_size.y * 0.3, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_callback(func() -> void: _dust.emitting = true).set_delay(0.3)
	_tween.tween_method(_logo.set_letter_progress, 0.0, 1.0, 1.2)
	_tween.parallel().tween_callback(_sound.bind(&"terrain_raise", -4.0)).set_delay(0.5)
	_tween.tween_callback(_sound.bind(&"nail_shot", 0.0))
	_tween.tween_method(_logo.set_nail_progress, 0.0, 1.0, 0.35)
	_tween.parallel().tween_method(_shake, 1.0, 0.0, 0.35)
	_tween.tween_callback(_sound.bind(&"scrap_pickup", -2.0))
	_tween.tween_method(_logo.set_subtitle_progress, 0.0, 1.0, 0.25)
	_tween.tween_method(_logo.set_grass_progress, 0.0, 1.0, 0.8)
	_tween.tween_interval(0.4)
	_tween.tween_callback(_finish)


func _shake(strength: float) -> void:
	_logo.position = _logo_rest + Vector2(randf_range(-6, 6), randf_range(-4, 4)) * strength


func _sound(id: StringName, volume_db: float) -> void:
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		return
	_audio.stream = stream
	_audio.volume_db = volume_db
	_audio.play()


func _finish() -> void:
	if _ending:
		return
	_ending = true
	var fade := create_tween()
	fade.tween_property(_fade, "color:a", 1.0, 0.5)
	fade.tween_callback(_on_faded)


func _on_faded() -> void:
	is_playing = false
	# Con il cambio di scena la pausa resta disattivata: la riattiva il menu quando
	# esce (`MainMenu._exit_tree`). Riattivarla qui aprirebbe il pannello di pausa a
	# un Esc premuto nel frame del cambio scena.
	if not change_scene_on_finish and _pause_menu != null:
		_pause_menu.set(&"enabled", true)
	finished.emit()
	if change_scene_on_finish:
		_go_to_menu()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
