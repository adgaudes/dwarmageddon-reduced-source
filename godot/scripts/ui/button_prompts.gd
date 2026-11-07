class_name ButtonPrompts
extends BoxContainer
## Suggerimenti "icona del tasto + testo" (D-059), in riga o in colonna. Le icone
## vengono dall'addon Controller Icons (D-057) e seguono il dispositivo in uso:
## controller Xbox, PlayStation, Switch, Steam Deck, oppure tastiera e mouse.
## Solo lettura: mai focus ne input. L'autoload si raggiunge per percorso e si
## chiama con `call`, perche il suo nome globale non esiste nei test.

const ICONS_PATH := ^"/root/ControllerIcons"
## ControllerIcons.InputType.CONTROLLER.
const INPUT_CONTROLLER := 1
## Le icone di tastiera e mouse dell'addon sono scure e sui nostri fondi scuri
## si perdono: questo shader le schiarisce. Quelle dei controller restano com'e.
const LIGHTEN_SHADER := """shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(mix(c.rgb, vec3(1.0), 0.5), c.a * COLOR.a);
}
"""

static var _lighten: ShaderMaterial

var icon_size := 34.0
var font_size := 17

var _entries: Array[Array] = []
var _icons: Node
var _rects: Array[TextureRect] = []
var _labels: Array[Label] = []


## [param entries]: coppie [azione della mappa input, testo], nell'ordine di lettura.
static func create(entries: Array[Array], in_column := false) -> ButtonPrompts:
	var prompts := ButtonPrompts.new()
	prompts.vertical = in_column
	prompts._entries = entries
	return prompts


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", 6 if vertical else 28)
	for entry in _entries:
		_add_prompt(entry[1])
	_icons = get_node_or_null(ICONS_PATH)
	if _icons == null:
		return
	if not _icons.is_node_ready():
		await _icons.ready
	_icons.connect(&"input_type_changed", _on_input_type_changed)
	refresh()


func prompt_count() -> int:
	return _rects.size()


func icon_of(index: int) -> Texture2D:
	return _rects[index].texture


func text_of(index: int) -> String:
	return _labels[index].text


## Ricarica le icone per il dispositivo in uso. Senza icona resta il solo testo.
func refresh() -> void:
	if _icons == null:
		return
	var keyboard := not _shows_controller()
	for i in _rects.size():
		var texture := _icon_for(String(_entries[i][0]))
		_rects[i].texture = texture
		_rects[i].visible = texture != null
		_rects[i].material = _lighten_material() if keyboard else null


## Vero se le icone mostrate sono quelle del controller.
func _shows_controller() -> bool:
	# In headless il display server non converte i tasti fisici della tastiera e
	# l'addon stamperebbe un errore: li si mostrano sempre le icone del controller.
	return DisplayServer.get_name() == "headless" or int(_icons.call(&"get_last_input_type")) == INPUT_CONTROLLER


func _icon_for(action: String) -> Texture2D:
	if _shows_controller():
		return _icons.call(&"parse_path", action, INPUT_CONTROLLER) as Texture2D
	return _icons.call(&"parse_path", action) as Texture2D


static func _lighten_material() -> ShaderMaterial:
	if _lighten == null:
		var shader := Shader.new()
		shader.code = LIGHTEN_SHADER
		_lighten = ShaderMaterial.new()
		_lighten.shader = shader
	return _lighten


func _add_prompt(text: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	add_child(row)
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(icon_size, icon_size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.hide()
	row.add_child(rect)
	_rects.append(rect)
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"PromptLabel"
	if font_size != 17:
		label.add_theme_font_size_override(&"font_size", font_size)
	row.add_child(label)
	_labels.append(label)


func _on_input_type_changed(_input_type: int, _controller: int) -> void:
	refresh()
