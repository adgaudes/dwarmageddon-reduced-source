class_name HealthBolts
extends Control
## Vita come bulloni esagonali (D-080): pieni `DANGER`, vuoti scuri. Si ridisegna
## solo quando cambiano i valori; nessun nodo figlio.

## Playtest O-01: a 22 px la vita non si notava.
const SIZE := 28.0
const GAP := 5.0
const OFF_COLOR := Color(0.12, 0.08, 0.07, 0.85)
const OFF_CENTER := Color(0.25, 0.18, 0.15)

var _health := 0
var _max := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_health(health: int, max_health: int) -> void:
	if health == _health and max_health == _max:
		return
	_health = health
	_max = max_health
	custom_minimum_size = Vector2((SIZE + GAP) * max_health, SIZE)
	queue_redraw()


func bolt_count() -> int:
	return _max


func lit_count() -> int:
	return clampi(_health, 0, _max)


func _draw() -> void:
	for i in _max:
		var center := Vector2(i * (SIZE + GAP) + SIZE * 0.5, SIZE * 0.5)
		var points := PackedVector2Array()
		for k in 6:
			var angle := PI / 6.0 + k * PI / 3.0
			points.append(center + Vector2(cos(angle), sin(angle)) * SIZE * 0.5)
		var lit := i < _health
		draw_colored_polygon(points, UiPalette.DANGER if lit else OFF_COLOR)
		points.append(points[0])
		draw_polyline(points, UiPalette.OUTLINE, 2.0)
		draw_circle(center, SIZE * 0.16, UiPalette.OUTLINE if lit else OFF_CENTER)
