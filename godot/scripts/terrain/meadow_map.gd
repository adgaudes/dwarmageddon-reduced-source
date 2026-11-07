class_name MeadowMap
extends RefCounted
## Prato logico (piano 3 delle armi, D-092): il prato a particelle (GrassField) vive solo sulla
## GPU, ma Falce rotante, Erba alta e Cespuglio medicinale devono sapere se un punto e "sul
## prato". Celle da CELL metri sul campo: il distretto segna quelle dipinte di verde, Fienagione
## e Semi in tasca ne aggiungono; un punto e prato se la sua cella e segnata e la quota non si
## scosta dalla base (scavi e argini tolgono i ciuffi, come fa lo shader del prato).

const CELL := 1.0
## Scarto massimo dalla quota di base per restare prato.
const MAX_DELTA := 0.25
## Valori delle celle: prato sulla base, prato anche su argini e scavi.
const FLAT := 1
const RELIEF := 2

var _field: TerrainField
var _cells := PackedByteArray()
var _width := 0
var _depth := 0
var _half := Vector2.ZERO
var _count := 0


func setup(field: TerrainField) -> void:
	_field = field
	_half = field.half_extents()
	_width = ceili(_half.x * 2.0 / CELL) + 1
	_depth = ceili(_half.y * 2.0 / CELL) + 1
	_cells.resize(_width * _depth)
	_cells.fill(0)
	_count = 0


## Segna come prato le celle con il centro entro [param radius] da [param center]. Con
## [param on_relief] restano prato anche lontano dalla base (Semi in tasca: argini coperti).
func mark(center: Vector3, radius: float, on_relief := false) -> void:
	if _cells.is_empty():
		return
	var reach := ceili(radius / CELL)
	var origin := _cell_of(center)
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := origin + Vector2i(dx, dz)
			if cell.x < 0 or cell.y < 0 or cell.x >= _width or cell.y >= _depth:
				continue
			var world := Vector2(cell.x * CELL - _half.x, cell.y * CELL - _half.y)
			if world.distance_to(Vector2(center.x, center.z)) > radius:
				continue
			var i := cell.y * _width + cell.x
			if _cells[i] == 0:
				_count += 1
			_cells[i] = maxi(_cells[i], RELIEF if on_relief else FLAT)


func is_meadow(p: Vector3) -> bool:
	if _cells.is_empty():
		return false
	var cell := _cell_of(p)
	if cell.x < 0 or cell.y < 0 or cell.x >= _width or cell.y >= _depth:
		return false
	var value := _cells[cell.y * _width + cell.x]
	return value == RELIEF or (value == FLAT and absf(_field.delta_at(p)) < MAX_DELTA)


func cell_count() -> int:
	return _count


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(roundi((p.x + _half.x) / CELL), roundi((p.z + _half.y) / CELL))
