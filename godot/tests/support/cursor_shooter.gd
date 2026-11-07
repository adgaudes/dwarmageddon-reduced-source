extends Node3D
## Tiratore finto per i test delle attive: espone il punto del cursore come PlayerCharacter
## quando si mira col mouse (D-092, review I-4).

var cursor: Variant = null


func cursor_ground_point() -> Variant:
	return cursor
