class_name BrushPreview
extends Decal
## Anello di luce proiettato sul rilievo dove agisce il pennello (spec sezione 3).
## La texture e un anello generato in codice; il colore dice il modo o il rifiuto.

const DIG_COLOR := Color(0.2, 0.9, 1.0)
const RAISE_COLOR := Color(1.0, 0.85, 0.2)
const LEVEL_COLOR := Color(1.0, 1.0, 1.0)
const LAMP_COLOR := Color(1.0, 0.95, 0.7)
const INVALID_COLOR := Color(1.0, 0.2, 0.15)

var last_color := Color.TRANSPARENT
static var _ring: ImageTexture


func _ready() -> void:
	texture_albedo = ring_texture()
	texture_emission = ring_texture()
	emission_energy = 1.5
	size = Vector3(4.8, 6.0, 4.8)
	cull_mask = 1
	visible = false


## Texture ad anello condivisa (anche dagli anelli a terra delle macchine), generata una volta.
static func ring_texture() -> ImageTexture:
	if _ring == null:
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var d := Vector2(x - 63.5, y - 63.5).length() / 63.5
				var a := clampf(1.0 - absf(d - 0.9) / 0.1, 0.0, 1.0)
				# RGB pari all'alfa: l'emissione del Decal non guarda l'alfa e col bianco
				# pieno riempirebbe tutto il quadrato (visto sulle catture del rilievo).
				image.set_pixel(x, y, Color(a, a, a, a))
		_ring = ImageTexture.create_from_image(image)
	return _ring


func show_ring(center: Vector3, radius: float, color: Color) -> void:
	global_position = center
	size = Vector3(radius * 2.0, 6.0, radius * 2.0)
	modulate = color
	last_color = color
	visible = true


func hide_ring() -> void:
	visible = false
	last_color = Color.TRANSPARENT
