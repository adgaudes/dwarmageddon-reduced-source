class_name CloudShadows
extends Decal
## Ombre delle nuvole (D-094): macchie d'ombra morbide e lente che scorrono sul terreno e
## rompono la luce uniforme delle grandi distese viste dall'alto. Un solo Decal grande
## tre periodi del rumore, con la texture ripetuta 3x3: si sposta a scatti di un periodo
## per seguire la camera e scivola col vento dentro il periodo, quindi il disegno nel
## mondo resta continuo. Scurisce l'albedo verso un blu d'ombra; si spegne col sole
## (notte) leggendo l'energia del sole rispetto a quella di giorno.

## Lato in metri di un periodo del rumore (la texture lo ripete 3x3).
const PERIOD_M := 80.0
const TILE_PX := 256
## Vento in m/s sul piano XZ.
const WIND := Vector2(0.9, 0.35)
## Opacita massima dell'ombra e suo colore (blu-viola come l'ambiente).
const MAX_ALPHA := 0.6
const SHADOW_COLOR := Color(0.05, 0.07, 0.20)

var sun: DirectionalLight3D
var _day_energy := 1.0
var _drift := Vector2.ZERO


func _init() -> void:
	name = "CloudShadows"
	size = Vector3(PERIOD_M * 3.0, 80.0, PERIOD_M * 3.0)
	upper_fade = 0.0
	lower_fade = 0.0
	normal_fade = 0.0
	albedo_mix = 1.0
	# Layer 1 (mondo, giocatore, nemici) e il layer delle macchine della carovana: le macchine
	# stanno sul 2 perche l'anello del pennello (solo layer 1) non le dipinga, ma le nuvole
	# devono scurirle come scurivano il compagno.
	cull_mask = 1 | Machine.VISUAL_LAYER
	texture_albedo = _build_texture()


func _ready() -> void:
	if sun != null:
		_day_energy = maxf(sun.light_energy, 0.001)


func _process(delta: float) -> void:
	_drift = (_drift + WIND * delta).posmod(PERIOD_M)
	var camera := get_viewport().get_camera_3d()
	var focus := camera.global_position if camera != null else Vector3.ZERO
	# Il centro si sposta solo a multipli del periodo: il disegno nel mondo non salta.
	var snapped_x := floorf(focus.x / PERIOD_M) * PERIOD_M
	var snapped_z := floorf(focus.z / PERIOD_M) * PERIOD_M
	global_position = Vector3(snapped_x + _drift.x, 0.0, snapped_z + _drift.y)
	var strength := clampf(sun.light_energy / _day_energy, 0.0, 1.0) if sun != null else 1.0
	modulate = Color(1.0, 1.0, 1.0, strength)
	visible = strength > 0.02


## Rumore ripetibile a celle grandi, soglia morbida (cielo per meta sereno), ripetuto 3x3.
static func _build_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	noise.seed = 4242
	var tile := noise.get_seamless_image(TILE_PX, TILE_PX, false, false, 0.2, true)
	var cell := Image.create_empty(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	for y in TILE_PX:
		for x in TILE_PX:
			var alpha := smoothstep(0.40, 0.62, tile.get_pixel(x, y).r) * MAX_ALPHA
			cell.set_pixel(x, y, Color(SHADOW_COLOR.r, SHADOW_COLOR.g, SHADOW_COLOR.b, alpha))
	var image := Image.create_empty(TILE_PX * 3, TILE_PX * 3, false, Image.FORMAT_RGBA8)
	for ty in 3:
		for tx in 3:
			image.blit_rect(cell, Rect2i(0, 0, TILE_PX, TILE_PX), Vector2i(tx * TILE_PX, ty * TILE_PX))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
