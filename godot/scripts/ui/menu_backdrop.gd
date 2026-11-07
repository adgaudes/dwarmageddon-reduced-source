class_name MenuBackdrop
extends Control
## Sfondo a strati del menu iniziale (D-081), disegnato con poligoni: in lontananza
## torri in rovina e un viadotto spezzato, in mezzo colline con ciuffi d'erba, davanti
## un terrapieno con sassi. I tre strati scorrono piano in parallasse e si ripetono.
## Sta sopra il cielo dipinto e sotto la colonna dei pulsanti; non prende il mouse.

const HORIZON := 0.62
const SPEEDS: Array[float] = [1.2, 3.0, 6.0]
const FAR := Color("2f2236")
const FAR_HAZE := Color("4a3346")
const MID := Color("231914")
const MID_GRASS := Color("2f3a1a")
const NEAR := Color("150e0a")
const NEAR_GRASS := Color("3a4a1f")
const ROCK := Color("221812")

@export var seed := 7

var _layers: Array[Control] = []
var _offsets: Array[float] = [0.0, 0.0, 0.0]
var _rng := RandomNumberGenerator.new()
var _towers: Array[Dictionary] = []
var _hill: PackedFloat32Array = []
var _bank: PackedFloat32Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = seed
	_build_shapes()
	var drawers: Array[Callable] = [_draw_far, _draw_mid, _draw_near]
	for i in 3:
		var layer := Control.new()
		layer.name = ["Far", "Mid", "Near"][i]
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.draw.connect(drawers[i].bind(layer))
		add_child(layer)
		_layers.append(layer)
	resized.connect(_redraw_all)


func layer_count() -> int:
	return _layers.size()


func layer_offset(index: int) -> float:
	return _offsets[index]


func _process(delta: float) -> void:
	var period := maxf(size.x, 1.0)
	for i in 3:
		_offsets[i] = fmod(_offsets[i] + SPEEDS[i] * delta, period)
	_redraw_all()


func _redraw_all() -> void:
	for layer in _layers:
		layer.queue_redraw()


func _build_shapes() -> void:
	# Torri: posizione (0..1 della larghezza), larghezza, altezza, cima spezzata.
	# Le torri stanno nella meta destra: a sinistra c'e la colonna dei pulsanti.
	_towers.clear()
	var x := 0.4
	while x < 1.0:
		var width := _rng.randf_range(0.03, 0.08)
		_towers.append({x = x, w = width, h = _rng.randf_range(0.08, 0.26), broken = _rng.randf() < 0.6, windows = _rng.randi_range(1, 3)})
		x += width + _rng.randf_range(0.03, 0.12)
	# Colline e terrapieno: profili campionati (0..1 della larghezza), ripetibili.
	_hill.clear()
	_bank.clear()
	for i in 41:
		var t := i / 40.0
		_hill.append(0.5 + 0.5 * sin(t * TAU * 1.0 + 0.4) * 0.5 + 0.5 * sin(t * TAU * 3.0) * 0.3 + _rng.randf_range(-0.05, 0.05))
		_bank.append(0.5 + 0.5 * sin(t * TAU * 2.0 + 1.3) * 0.6 + _rng.randf_range(-0.08, 0.08))
	_hill[40] = _hill[0]
	_bank[40] = _bank[0]


## Disegna [param draw] due volte (x e x + larghezza) cosi lo scorrimento si ripete.
func _wrapped(layer: Control, index: int, draw: Callable) -> void:
	var width := size.x
	var shift := -_offsets[index]
	draw.call(layer, shift)
	draw.call(layer, shift + width)


func _draw_far(layer: Control) -> void:
	_wrapped(layer, 0, _draw_far_at)


func _draw_far_at(layer: Control, shift: float) -> void:
	var width := size.x
	var horizon := size.y * HORIZON
	# Viadotto spezzato: travata con arcate, interrotta per un tratto.
	var beam_y := horizon - size.y * 0.06
	var beam_h := size.y * 0.025
	for segment in [[0.0, 0.42], [0.58, 1.0]]:
		var x0: float = shift + segment[0] * width
		var x1: float = shift + segment[1] * width
		layer.draw_rect(Rect2(x0, beam_y, x1 - x0, beam_h), FAR_HAZE)
		var pillar_x := x0
		while pillar_x < x1 - width * 0.02:
			layer.draw_rect(Rect2(pillar_x, beam_y + beam_h, width * 0.012, horizon - beam_y - beam_h), FAR_HAZE)
			pillar_x += width * 0.06
	# Torri a gradoni con la cima spezzata e finestre vuote.
	for tower in _towers:
		var tx: float = shift + tower.x * width
		var tw: float = tower.w * width
		var th: float = tower.h * size.y
		var top := horizon - th
		var polygon := PackedVector2Array([Vector2(tx, horizon), Vector2(tx, top)])
		if tower.broken:
			polygon.append(Vector2(tx + tw * 0.3, top + th * 0.12))
			polygon.append(Vector2(tx + tw * 0.55, top - th * 0.05))
			polygon.append(Vector2(tx + tw * 0.8, top + th * 0.2))
		else:
			polygon.append(Vector2(tx + tw, top))
		polygon.append(Vector2(tx + tw, horizon))
		layer.draw_colored_polygon(polygon, FAR)
		for k in tower.windows:
			var wy: float = top + th * (0.3 + 0.22 * k)
			if wy < horizon - th * 0.1:
				layer.draw_rect(Rect2(tx + tw * 0.35, wy, tw * 0.3, th * 0.08), FAR_HAZE)


func _draw_mid(layer: Control) -> void:
	_wrapped(layer, 1, _draw_mid_at)


func _draw_mid_at(layer: Control, shift: float) -> void:
	var width := size.x
	var horizon := size.y * HORIZON
	var polygon := PackedVector2Array()
	for i in _hill.size():
		var x := shift + width * i / 40.0
		polygon.append(Vector2(x, horizon - size.y * 0.02 - _hill[i] * size.y * 0.06))
	polygon.append(Vector2(shift + width, size.y))
	polygon.append(Vector2(shift, size.y))
	layer.draw_colored_polygon(polygon, MID)
	# Ciuffi d'erba sul profilo.
	for i in range(0, _hill.size() - 1, 2):
		var base := polygon[i]
		for blade in 3:
			var dx := (blade - 1) * 4.0
			layer.draw_colored_polygon(PackedVector2Array([base + Vector2(dx - 2, 0), base + Vector2(dx * 1.5, -10.0 - 4.0 * absf(blade - 1)), base + Vector2(dx + 2, 0)]), MID_GRASS)


func _draw_near(layer: Control) -> void:
	_wrapped(layer, 2, _draw_near_at)


func _draw_near_at(layer: Control, shift: float) -> void:
	var width := size.x
	var top := size.y * 0.82
	var polygon := PackedVector2Array()
	for i in _bank.size():
		var x := shift + width * i / 40.0
		polygon.append(Vector2(x, top - _bank[i] * size.y * 0.05))
	polygon.append(Vector2(shift + width, size.y))
	polygon.append(Vector2(shift, size.y))
	layer.draw_colored_polygon(polygon, NEAR)
	# Sassi e ciuffi lungo il bordo.
	for i in range(1, _bank.size() - 1, 3):
		var base := polygon[i]
		if i % 2 == 0:
			layer.draw_circle(base + Vector2(0, 6), 5.0 + 2.0 * _bank[i], ROCK)
		else:
			for blade in 3:
				var dx := (blade - 1) * 5.0
				layer.draw_colored_polygon(PackedVector2Array([base + Vector2(dx - 2, 2), base + Vector2(dx * 1.6, -16.0 - 5.0 * absf(blade - 1)), base + Vector2(dx + 2, 2)]), NEAR_GRASS)
