class_name RuinModules
extends RefCounted
## Moduli dei muri in rovina (playtest del 14 ottobre 2026, O-10, D-090): tratti di muro con
## la cima spezzata a gradini di mattoni, al posto del cubo scalato. Ogni modulo e
## l'estrusione di un profilo a "skyline" nello spazio unitario x in [-0.5, 0.5],
## y in [0, 1], z in [-0.5, 0.5]: si scala come il cubo che sostituisce (lunghezza,
## altezza, spessore) e lo shader delle rovine, triplanare in coordinate mondo, non
## ha bisogno di UV. La collisione resta il blocco pieno del guscio.
## Meta delle varianti ha una finestra vera (vano con davanzale, architrave e stipiti),
## al posto di quelle dipinte dallo shader: dalla camera si vede attraverso.

const VARIANTS := 6
## Colonne del profilo per modulo (un tratto da 3 m: circa 30-50 cm a colonna).
const COLUMNS := Vector2i(12, 18)
## Passo dei gradini (corsi di mattoni) in frazione dell'altezza del tratto.
const COURSE := 0.035
## Vano della finestra in frazioni del modulo: larghezza, davanzale, architrave.
const WINDOW_WIDTH := 0.28
const WINDOW_SILL := 0.30
const WINDOW_LINTEL := 0.62

static var _broken: Array[ArrayMesh] = []
static var _whole: Array[ArrayMesh] = []


## Tratto crollato: cima molto frastagliata, fra il 55 e il 100 % dell'altezza.
static func broken_wall(index: int) -> ArrayMesh:
	if _broken.is_empty():
		for v in VARIANTS:
			_broken.append(_build(1000 + v, 0.55, 0.45, v % 2 == 0))
	return _broken[posmod(index, VARIANTS)]


## Tratto intero: cima appena sbrecciata, fra il 92 e il 100 %.
static func whole_wall(index: int) -> ArrayMesh:
	if _whole.is_empty():
		for v in VARIANTS:
			_whole.append(_build(2000 + v, 0.92, 0.0, v % 2 == 0))
	return _whole[posmod(index, VARIANTS)]


static func _build(seed_value: int, low: float, notch_chance: float, with_window: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := rng.randi_range(COLUMNS.x, COLUMNS.y)
	# Larghezze irregolari delle colonne, normalizzate a 1.
	var widths: Array[float] = []
	var total := 0.0
	for i in count:
		var w := rng.randf_range(0.6, 1.4)
		widths.append(w)
		total += w
	var xs: Array[float] = [-0.5]
	for w in widths:
		xs.append(xs[-1] + w / total)
	xs[-1] = 0.5
	# Quote della cima: una frana morbida verso un lato, una breccia a V in un punto a
	# caso, piccole irregolarita, tutto a gradini di corsi di mattoni.
	var slope_side := rng.randf_range(-1.0, 1.0)
	var dip_at := rng.randf_range(-0.35, 0.35)
	var dip_depth := rng.randf_range(0.15, 0.4) * (1.0 - low) / 0.45
	var dip_width := rng.randf_range(0.12, 0.25)
	var heights: Array[float] = []
	for i in count:
		var t := (float(i) + 0.5) / float(count) - 0.5
		var h := lerpf(1.0, low, clampf(0.5 + slope_side * t * 1.4, 0.0, 1.0))
		h -= dip_depth * maxf(0.0, 1.0 - absf(t - dip_at) / dip_width)
		h += rng.randf_range(-0.05, 0.03)
		if rng.randf() < notch_chance * 0.4:
			h -= rng.randf_range(0.04, 0.1)
		heights.append(clampf(snappedf(h, COURSE), low - 0.15, 1.0))
	if low >= 0.9:
		for i in count:
			heights[i] = clampf(1.0 - absf(rng.randfn(0.0, 0.03)), low, 1.0)
	# Finestra: colonne consecutive larghe circa WINDOW_WIDTH, con muro pieno sopra
	# l'architrave in tutte e nelle due vicine (altrimenti niente finestra).
	var win_from := -1
	var win_to := -1
	if with_window:
		var want := rng.randf_range(-0.2, 0.2)
		for first in range(1, count - 1):
			var last := first
			while last < count - 2 and xs[last + 1] - xs[first] < WINDOW_WIDTH:
				last += 1
			var ok := true
			for k in range(first - 1, last + 2):
				if heights[k] < WINDOW_LINTEL + 0.08:
					ok = false
			var mid: float = (xs[first] + xs[last + 1]) * 0.5
			if ok and (win_from < 0 or absf(mid - want) < absf((xs[win_from] + xs[win_to + 1]) * 0.5 - want)):
				win_from = first
				win_to = last
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		var h: float = heights[i]
		# Fronte (+z) e retro (-z); dentro la finestra due fasce, sotto e sopra il vano.
		if i >= win_from and i <= win_to and win_from >= 0:
			for span: Vector2 in [Vector2(0.0, WINDOW_SILL), Vector2(WINDOW_LINTEL, h)]:
				_quad(st, Vector3(x0, span.x, 0.5), Vector3(x1, span.x, 0.5), Vector3(x1, span.y, 0.5), Vector3(x0, span.y, 0.5), Vector3.BACK)
				_quad(st, Vector3(x1, span.x, -0.5), Vector3(x0, span.x, -0.5), Vector3(x0, span.y, -0.5), Vector3(x1, span.y, -0.5), Vector3.FORWARD)
			# Davanzale (guarda in su) e architrave (guarda in giu).
			_quad(st, Vector3(x0, WINDOW_SILL, 0.5), Vector3(x1, WINDOW_SILL, 0.5), Vector3(x1, WINDOW_SILL, -0.5), Vector3(x0, WINDOW_SILL, -0.5), Vector3.UP)
			_quad(st, Vector3(x0, WINDOW_LINTEL, -0.5), Vector3(x1, WINDOW_LINTEL, -0.5), Vector3(x1, WINDOW_LINTEL, 0.5), Vector3(x0, WINDOW_LINTEL, 0.5), Vector3.DOWN)
		else:
			_quad(st, Vector3(x0, 0, 0.5), Vector3(x1, 0, 0.5), Vector3(x1, h, 0.5), Vector3(x0, h, 0.5), Vector3.BACK)
			_quad(st, Vector3(x1, 0, -0.5), Vector3(x0, 0, -0.5), Vector3(x0, h, -0.5), Vector3(x1, h, -0.5), Vector3.FORWARD)
		# Cima della colonna, appena inclinata: i mattoni spezzati non sono un piano.
		var tilt := rng.randf_range(-0.03, 0.03)
		_quad(st, Vector3(x0, h + tilt, 0.5), Vector3(x1, h - tilt, 0.5), Vector3(x1, h - tilt, -0.5), Vector3(x0, h + tilt, -0.5), Vector3.UP)
		# Gradino verso la colonna successiva (o la testata a destra).
		var next_h: float = heights[i + 1] if i + 1 < count else 0.0
		if absf(next_h - h) > 0.001:
			var lo := minf(h, next_h)
			var hi := maxf(h, next_h)
			var facing := Vector3.RIGHT if h > next_h else Vector3.LEFT
			if facing == Vector3.RIGHT:
				_quad(st, Vector3(x1, lo, 0.5), Vector3(x1, lo, -0.5), Vector3(x1, hi, -0.5), Vector3(x1, hi, 0.5), facing)
			else:
				_quad(st, Vector3(x1, lo, -0.5), Vector3(x1, lo, 0.5), Vector3(x1, hi, 0.5), Vector3(x1, hi, -0.5), facing)
	# Stipiti: il muro pieno a sinistra guarda dentro il vano (+x), quello a destra (-x).
	if win_from >= 0:
		var left: float = xs[win_from]
		var right: float = xs[win_to + 1]
		_quad(st, Vector3(left, WINDOW_SILL, 0.5), Vector3(left, WINDOW_SILL, -0.5), Vector3(left, WINDOW_LINTEL, -0.5), Vector3(left, WINDOW_LINTEL, 0.5), Vector3.RIGHT)
		_quad(st, Vector3(right, WINDOW_SILL, -0.5), Vector3(right, WINDOW_SILL, 0.5), Vector3(right, WINDOW_LINTEL, 0.5), Vector3(right, WINDOW_LINTEL, -0.5), Vector3.LEFT)
	# Testata sinistra.
	var h0: float = heights[0]
	_quad(st, Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(-0.5, h0, 0.5), Vector3(-0.5, h0, -0.5), Vector3.LEFT)
	return st.commit()


## Quad a-b-c-d in senso antiorario visto da fuori; Godot vuole le facce frontali in
## senso orario, quindi i triangoli si emettono rovesciati.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	for v in [a, c, b, a, d, c]:
		st.set_normal(normal)
		st.set_color(Color.WHITE)
		st.add_vertex(v)
