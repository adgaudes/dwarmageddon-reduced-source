class_name TuningSwitcher
extends CanvasLayer
## Strumento di playtest: alterna preset di PlayerTuning a caldo con l'azione
## `debug_next_tuning` (Tab) e la modalita VSync con `debug_cycle_vsync` (F2),
## mostrando lo stato per qualche secondo. Solo tastiera: la croce direzionale e
## la navigazione dei menu (U-12).
## Serve a scegliere provando invece che descrivendo. Non e UI di gioco.

@export var player: PlayerCharacter
## Il primo e il default (Scattante); l'ordine e quello di rotazione.
@export var presets: Array[PlayerTuning] = []
@export var label_seconds := 2.5

var current_index := 0

const VSYNC_MODES: Array[DisplayServer.VSyncMode] = [
	DisplayServer.VSYNC_MAILBOX, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_DISABLED,
]
const VSYNC_NAMES: Array[String] = [
	"Mailbox (default)", "Classico", "Off: latenza minima, possibile tearing",
]

var _label: Label
var _label_left := 0.0


func _ready() -> void:
	_label = Label.new()
	_label.name = "PresetLabel"
	# Mai interattiva: non deve rubare focus o input al gioco (vedi ui_accept).
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.focus_mode = Control.FOCUS_NONE
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override(&"font_size", 22)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.visible = false
	add_child(_label)
	if player != null and not presets.is_empty():
		current_index = maxi(presets.find(player.tuning), 0)
	# Modalita effettiva: il driver puo rifiutare Mailbox e ripiegare su un'altra.
	print("PROTOTYPE01_VSYNC %s" % _vsync_name())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_next_tuning") and not presets.is_empty() and player != null:
		select(posmod(current_index + 1, presets.size()))
	elif event.is_action_pressed(&"debug_cycle_vsync"):
		cycle_vsync()


func cycle_vsync() -> void:
	var current := VSYNC_MODES.find(DisplayServer.window_get_vsync_mode())
	var next := posmod(current + 1, VSYNC_MODES.size())
	# Passa da GameSettings (salva la scelta) se l'autoload c'e; a runtime, non per nome
	# globale, perche i test precaricano le scene prima degli autoload.
	var settings := get_node_or_null(^"/root/GameSettings")
	if settings != null:
		settings.set_vsync_mode(VSYNC_MODES[next])
	else:
		DisplayServer.window_set_vsync_mode(VSYNC_MODES[next])
	# Il driver puo non supportare la modalita richiesta: si mostra quella effettiva.
	_show("VSync: %s   F2 / croce sinistra" % _vsync_name())
	print("PROTOTYPE01_VSYNC %s" % _vsync_name())


func _vsync_name() -> String:
	var actual := VSYNC_MODES.find(DisplayServer.window_get_vsync_mode())
	return VSYNC_NAMES[actual] if actual >= 0 else "sconosciuta"


func select(index: int) -> void:
	current_index = index
	var preset := presets[index]
	player.apply_tuning(preset)
	_show("Feel: %s  (%d/%d)   Tab / croce destra" % [preset.display_name, index + 1, presets.size()])
	print("PROTOTYPE01_TUNING %s" % preset.display_name)


func _show(text: String) -> void:
	_label.text = text
	_label.visible = true
	_label_left = label_seconds


func _process(delta: float) -> void:
	if _label_left > 0.0:
		_label_left -= delta
		if _label_left <= 0.0:
			_label.visible = false
