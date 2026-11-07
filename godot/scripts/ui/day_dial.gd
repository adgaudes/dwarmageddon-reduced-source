class_name DayDial
extends Control
## Quadrante giorno/notte (D-080): un semicerchio con il sole che scende verso
## l'orizzonte di giorno e la luna di notte. Accompagna il testo dell'HUD.

const RADIUS := 16.0

var _phase := 0
var _fraction := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(RADIUS * 2.0 + 4.0, RADIUS + 8.0)


## [param fraction]: 0..1 di giorno trascorso (il sole scende verso destra).
func set_phase(phase: int, fraction: float) -> void:
	if phase == _phase and is_equal_approx(fraction, _fraction):
		return
	_phase = phase
	_fraction = clampf(fraction, 0.0, 1.0)
	queue_redraw()


func phase() -> int:
	return _phase


func _draw() -> void:
	var center := Vector2(RADIUS + 2.0, RADIUS + 4.0)
	draw_arc(center, RADIUS, PI, TAU, 24, UiPalette.OUTLINE, 4.0)
	draw_arc(center, RADIUS, PI, TAU, 24, UiPalette.TEXT_MUTED, 2.0)
	var night := _phase >= 2
	var angle := PI + PI * (0.15 + 0.7 * _fraction)
	var body := center + Vector2(cos(angle), sin(angle)) * RADIUS
	draw_circle(body, 6.0, UiPalette.OUTLINE)
	draw_circle(body, 4.5, Color("9aa3ff") if night else Color("ffd45a"))
	if night:
		draw_circle(body + Vector2(2.0, -1.0), 3.5, UiPalette.OUTLINE)
