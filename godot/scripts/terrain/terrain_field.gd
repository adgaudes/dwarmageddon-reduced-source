class_name TerrainField
extends Node3D
## Rilievo continuo del livello (D-082, D-085). Le quote vivono in `_heights` (un
## valore ogni SPACING metri, origine al centro, sorgente di verita anche in headless);
## il nodo Terrain3D, se c'e, le rispecchia per la resa. Nessun altro script parla con
## Terrain3D: tutto passa da qui. Scrive solo `sculpt`/`level`; chi vuole reagire a un
## cambio si collega a `region_changed`. `player_sculpted` e per cio che dipende dal
## tool del giocatore (rottami, suoni, impronte, contatori).
## Il campo e rettangolare (tappa B): `size_m` (X, Z), regioni Terrain3D e chunk di
## collisione per asse; l'indice dei vertici e `iz * resolution_x + ix`.

signal region_changed(aabb: AABB)
## Terrain3D e pronto per colori e strati (solo con finestra, un fotogramma dopo `_ready`).
signal render_ready
signal player_sculpted(center: Vector3, radius: float, volume: float, mode: int)

enum ToolMode { DIG, RAISE, LEVEL, LAMP }

const SPACING := 0.5
## Bordo di paint_layer: lo strato sfuma come overlay sull'ultima fascia del disco, larga
## PAINT_SOFT_WIDTH_M ma non oltre il 40 % del raggio (i dischi piccoli restano pieni al centro).
const PAINT_SOFT_WIDTH_M := 1.5
const PAINT_SOFT_MAX_FRACTION := 0.4
const MIN_HEIGHT := -2.5
const MAX_HEIGHT := 4.0
const REGION_SIZE := 256
const SAVE_MAGIC := "TFLD"
const SAVE_VERSION := 3
const TOOL_MODE_NAMES: Array[String] = ["Dig", "Raise", "Level", "Lamp"]

## Lato lungo X e lungo Z, metri.
@export var size_m := Vector2(204.0, 204.0)
@export var tuning: TerrainTuning
## Senza resa (test headless, benchmark) il nodo Terrain3D non viene creato.
@export var render := true

var resolution_x := 0
var resolution_z := 0
var volume_moved := 0.0
var _half := Vector2.ZERO
var _heights := PackedFloat32Array()
var _base := PackedFloat32Array()
var _protected := PackedByteArray()
var _terrain: Terrain3D
var _terrain_ready := false
var _collision: TerrainCollision
## Scritture a lotti (audit E-12): fra `begin_batch` ed `end_batch` le pennellate scrivono
## le quote ma specchio, collisione e `region_changed` aspettano l'unione delle aree.
var _batch_depth := 0
var _batch_rect: Array[int] = []
## Tipi di mappa di Terrain3D da caricare a fine lotto.
var _batch_maps: Dictionary[int, bool] = {}


func _ready() -> void:
	if tuning == null:
		tuning = TerrainTuning.new()
	resolution_x = int(round(size_m.x / SPACING)) + 1
	resolution_z = int(round(size_m.y / SPACING)) + 1
	_half = Vector2((resolution_x - 1) * SPACING * 0.5, (resolution_z - 1) * SPACING * 0.5)
	_heights.resize(resolution_x * resolution_z)
	_heights.fill(0.0)
	_base = _heights.duplicate()
	_protected.resize(resolution_x * resolution_z)
	_protected.fill(0)
	_collision = TerrainCollision.new()
	_collision.name = "Collision"
	add_child(_collision)
	_collision.setup(self)
	if render and not DisplayServer.get_name() == "headless":
		_build_terrain3d()
	print("PROTOTYPE01_TERRAIN_FIELD_READY resolution=%dx%d size_m=%.0fx%.0f" % [resolution_x, resolution_z, size_m.x, size_m.y])


## Semilato lungo X (comodita per i chiamanti quadrati); per le scale usare `half_extents()`.
func half_extent() -> float:
	return _half.x


func half_extents() -> Vector2:
	return _half


func terrain3d() -> Terrain3D:
	return _terrain if _terrain_ready else null


func collision_body() -> StaticBody3D:
	return _collision.body


# --- Letture ---------------------------------------------------------------------------

func height_at(p: Vector3) -> float:
	return _sample(_heights, p)


func base_height_at(p: Vector3) -> float:
	return _sample(_base, p)


func delta_at(p: Vector3) -> float:
	return height_at(p) - base_height_at(p)


func normal_at(p: Vector3) -> Vector3:
	var dx := height_at(p + Vector3(SPACING, 0.0, 0.0)) - height_at(p - Vector3(SPACING, 0.0, 0.0))
	var dz := height_at(p + Vector3(0.0, 0.0, SPACING)) - height_at(p - Vector3(0.0, 0.0, SPACING))
	return Vector3(-dx, 2.0 * SPACING, -dz).normalized()


## Pendenza locale in metri di quota per metro (0 = piano).
func slope_at(p: Vector3) -> float:
	var n := normal_at(p)
	return Vector2(n.x, n.z).length() / maxf(n.y, 0.001)


## Dislivello per metro da [param a] a [param b], positivo in salita.
func grade_between(a: Vector3, b: Vector3) -> float:
	var run := Vector2(b.x - a.x, b.z - a.z).length()
	if run < 0.0001:
		return 0.0
	return (height_at(b) - height_at(a)) / run


## In discesa sempre; in salita solo se nessun tratto di SPACING supera [param max_grade].
func can_step(from: Vector3, to: Vector3, max_grade: float) -> bool:
	var run := Vector2(to.x - from.x, to.z - from.z).length()
	if run < 0.0001:
		return true
	var steps := maxi(int(ceil(run / SPACING)), 1)
	var previous := height_at(from)
	for i in range(1, steps + 1):
		var point := from.lerp(to, float(i) / steps)
		var h := height_at(point)
		if h - previous > max_grade * (run / steps):
			return false
		previous = h
	return true


## Vero se nel disco la differenza fra quota massima e minima resta sotto [param tolerance].
func is_flat(center: Vector3, radius: float, tolerance: float) -> bool:
	var lo := INF
	var hi := -INF
	for p in _disc_points(center, radius):
		var h := _heights[p]
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo <= tolerance


## Punto (Vector3 con quota) entro [param radius] con il maggior delta sopra [param min_delta], o null.
func highest_bump(center: Vector3, radius: float, min_delta: float) -> Variant:
	var best: Variant = null
	var best_delta := min_delta
	for p in _disc_points(center, radius):
		var d := _heights[p] - _base[p]
		if d > best_delta:
			best_delta = d
			best = _vertex_world(p)
	return best


## Per dischi concentrici di raggio step, 2 step, ... fino a [param max_radius]: la cima
## piu sporgente dalla base (oltre [param min_delta]) dentro ciascun disco, Vector3 o null.
## Una sola passata (audit E-16): equivale a `highest_bump` per ogni raggio.
func highest_bumps_by_ring(center: Vector3, step: float, max_radius: float, min_delta: float) -> Array:
	var rings := maxi(int(floor(max_radius / step)), 0)
	var out := []
	if rings == 0:
		return out
	var ring_delta := PackedFloat32Array()
	ring_delta.resize(rings)
	ring_delta.fill(min_delta)
	var ring_index := PackedInt32Array()
	ring_index.resize(rings)
	ring_index.fill(-1)
	var outer := rings * step
	var r := _rect_indices(center, Vector2(outer, outer))
	for iz in range(r[1], r[3] + 1):
		var wz := iz * SPACING - _half.y
		for ix in range(r[0], r[2] + 1):
			var wx := ix * SPACING - _half.x
			var d2 := (wx - center.x) * (wx - center.x) + (wz - center.z) * (wz - center.z)
			if d2 > outer * outer:
				continue
			var i := iz * resolution_x + ix
			var d := _heights[i] - _base[i]
			if d <= min_delta:
				continue
			var k := clampi(int(ceil(sqrt(d2) / step)) - 1, 0, rings - 1)
			if d > ring_delta[k]:
				ring_delta[k] = d
				ring_index[k] = i
	var best_delta := min_delta
	var best := -1
	for k in rings:
		if ring_delta[k] > best_delta:
			best_delta = ring_delta[k]
			best = ring_index[k]
		out.append(_vertex_world(best) if best >= 0 else null)
	return out


## Primo punto lungo il segmento (campionato ogni SPACING) che sporge dalla base di
## almeno [param min_delta]: Vector3 con la quota, o null. Serve alla Trivella.
func bump_along(from: Vector3, to: Vector3, min_delta: float) -> Variant:
	var run := Vector2(to.x - from.x, to.z - from.z).length()
	var steps := maxi(int(ceil(run / SPACING)), 1)
	for i in range(0, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		if delta_at(p) >= min_delta:
			return Vector3(p.x, height_at(p), p.z)
	return null


func is_protected(p: Vector3) -> bool:
	var i := _index_of(p)
	return i >= 0 and _protected[i] != 0


func set_protected(center: Vector3, radius: float, on: bool) -> void:
	for p in _disc_points(center, radius):
		_protected[p] = 1 if on else 0


## Protezione dei vertici del disco com'e ora (`{indices, flags}`): chi protegge per un tempo
## la rimette con `restore_protected` senza togliere quella di altri (rovine, cortile).
func snapshot_protected(center: Vector3, radius: float) -> Dictionary:
	var indices := _disc_points(center, radius)
	var values := PackedByteArray()
	values.resize(indices.size())
	for i in indices.size():
		values[i] = _protected[indices[i]]
	return {"indices": indices, "flags": values}


func restore_protected(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var indices: PackedInt32Array = snapshot["indices"]
	var values: PackedByteArray = snapshot["flags"]
	for i in mini(indices.size(), values.size()):
		_protected[indices[i]] = values[i]


# --- Scritture -------------------------------------------------------------------------

## Pennello a campana: [param amount] metri al centro, zero sul bordo; negativo scava.
## Restituisce il volume spostato in m3, col segno; i pixel protetti non cambiano.
func sculpt(center: Vector3, radius: float, amount: float) -> float:
	return _brush(center, radius, func(h: float, falloff: float) -> float:
		return h + amount * falloff)


## Avvicina il disco a [param target]: strength 1 al centro lo porta esattamente li.
func level(center: Vector3, radius: float, target: float, strength: float) -> float:
	return _brush(center, radius, func(h: float, falloff: float) -> float:
		return h + (target - h) * clampf(strength * falloff, 0.0, 1.0))


## Riporta alla base i vertici del rettangolo XZ (centro e semilati), anche se protetti:
## e la pennellata del treno. Ritorna il volume assoluto spostato (m3).
func reset_to_base(center: Vector3, half_size: Vector2) -> float:
	var r := _rect_indices(center, half_size)
	if r[2] < r[0] or r[3] < r[1]:
		return 0.0
	var volume := 0.0
	var changed := 0
	for iz in range(r[1], r[3] + 1):
		for ix in range(r[0], r[2] + 1):
			var i := iz * resolution_x + ix
			if _heights[i] == _base[i]:
				continue
			volume += absf(_heights[i] - _base[i]) * SPACING * SPACING
			_heights[i] = _base[i]
			changed += 1
	# Fascia gia alla base (quasi ogni passo del treno): niente specchio, chunk ne segnale.
	if changed == 0:
		return 0.0
	_flush_rect(r[0], r[1], r[2], r[3])
	return volume


## Scava il disco fino a [param depth] metri sotto la base, vertice per vertice e solo
## verso il basso (campana al bordo): un fossato gia piu profondo resta com'e, un pendio
## di base non viene scavato oltre la profondita. E il solco della Trivella. Ritorna il
## volume (negativo o zero).
func dig_to_base_offset(center: Vector3, radius: float, depth: float) -> float:
	var volume := 0.0
	var r2 := radius * radius
	var r := _rect_indices(center, Vector2(radius, radius))
	if r[2] < r[0] or r[3] < r[1]:
		return 0.0
	var changed := 0
	for iz in range(r[1], r[3] + 1):
		var wz := iz * SPACING - _half.y
		for ix in range(r[0], r[2] + 1):
			var wx := ix * SPACING - _half.x
			var d2 := ((wx - center.x) * (wx - center.x) + (wz - center.z) * (wz - center.z)) / r2
			if d2 >= 1.0:
				continue
			var i := iz * resolution_x + ix
			if _protected[i] != 0:
				continue
			var falloff := (1.0 - d2) * (1.0 - d2)
			var before := _heights[i]
			var floor_h := _base[i] - depth
			if before <= floor_h:
				continue
			var after := clampf(before + (floor_h - before) * falloff, MIN_HEIGHT, MAX_HEIGHT)
			if after >= before:
				continue
			_heights[i] = after
			volume += (after - before) * SPACING * SPACING
			changed += 1
	if changed == 0:
		return 0.0
	_flush_rect(r[0], r[1], r[2], r[3])
	return volume


func player_sculpt(center: Vector3, radius: float, amount: float, mode: int) -> float:
	var volume := sculpt(center, radius, amount)
	volume_moved += absf(volume)
	player_sculpted.emit(center, radius, volume, mode)
	return volume


func player_level(center: Vector3, radius: float, strength: float) -> float:
	var volume := level(center, radius, height_at(center), strength)
	volume_moved += absf(volume)
	player_sculpted.emit(center, radius, volume, ToolMode.LEVEL)
	return volume


## Livella del giocatore con la terra disponibile: se per alzare i dintorni servirebbero
## piu di [param max_raise_m3], la pennellata viene scalata (spec sezione 3: Livella
## scambia terra nei due versi, non la crea).
func player_level_budget(center: Vector3, radius: float, strength: float, max_raise_m3: float) -> float:
	var target := height_at(center)
	var needed := _raise_volume(center, radius, target, strength)
	if needed > max_raise_m3:
		strength *= maxf(max_raise_m3, 0.0) / needed
	if strength <= 0.0:
		return 0.0
	return player_level(center, radius, strength)


## Terra (m3) che `level` aggiungerebbe nel disco, senza scrivere.
func _raise_volume(center: Vector3, radius: float, target: float, strength: float) -> float:
	var raised := 0.0
	var r2 := radius * radius
	var r := _rect_indices(center, Vector2(radius, radius))
	for iz in range(r[1], r[3] + 1):
		var wz := iz * SPACING - _half.y
		for ix in range(r[0], r[2] + 1):
			var wx := ix * SPACING - _half.x
			var d2 := ((wx - center.x) * (wx - center.x) + (wz - center.z) * (wz - center.z)) / r2
			if d2 >= 1.0:
				continue
			var i := iz * resolution_x + ix
			if _protected[i] != 0:
				continue
			var falloff := (1.0 - d2) * (1.0 - d2)
			var before := _heights[i]
			var after := clampf(before + (target - before) * clampf(strength * falloff, 0.0, 1.0), MIN_HEIGHT, MAX_HEIGHT)
			raised += maxf(after - before, 0.0) * SPACING * SPACING
	return raised


## Fissa il rilievo attuale come "naturale": delta e bump si misurano da qui.
func commit_base() -> void:
	_base = _heights.duplicate()
	if _terrain_ready:
		TerrainSurface.update_base(_terrain, _base, resolution_x, resolution_z, _half)


## Strato di tile (TerrainSurface.LAYER_*) sul control map di Terrain3D in un disco; niente in headless.
func paint_layer(center: Vector3, radius: float, layer: int) -> void:
	if not _terrain_ready:
		return
	var data := _terrain.data
	var pixel := Color(Terrain3DUtil.as_float(Terrain3DUtil.enc_base(layer)), 0.0, 0.0, 0.0)
	var soft_start := 1.0 - minf(PAINT_SOFT_WIDTH_M / radius, PAINT_SOFT_MAX_FRACTION)
	for p in _disc_points(center, radius):
		var world := _vertex_world(p)
		var d := Vector2(world.x - center.x, world.z - center.z).length() / radius
		if d <= soft_start:
			data.set_pixel(Terrain3DRegion.TYPE_CONTROL, world, pixel)
			continue
		# Bordo morbido (playtest del 14 ottobre, O-08): fuori dal nucleo lo strato entra come
		# overlay sopra quello che c'era, con peso che cala verso il bordo, invece di un
		# cambio netto per vertice che disegnava scalini da 0,5 m.
		var old := Terrain3DUtil.as_uint(data.get_pixel(Terrain3DRegion.TYPE_CONTROL, world).r)
		var old_base := Terrain3DUtil.get_base(old)
		if old_base == layer:
			continue
		var weight := roundi(255.0 * smoothstep(1.0, soft_start, d))
		if Terrain3DUtil.get_overlay(old) == layer:
			weight = maxi(weight, Terrain3DUtil.get_blend(old))
		var mixed := Terrain3DUtil.enc_base(old_base) | Terrain3DUtil.enc_overlay(layer) | Terrain3DUtil.enc_blend(weight)
		data.set_pixel(Terrain3DRegion.TYPE_CONTROL, world, Color(Terrain3DUtil.as_float(mixed), 0.0, 0.0, 0.0))
	_mark_regions(center, radius)
	_update_maps(Terrain3DRegion.TYPE_CONTROL)


## Strato di tile su un rettangolo XZ (la fascia dei binari); niente in headless.
func paint_layer_rect(center: Vector3, half_size: Vector2, layer: int) -> void:
	if not _terrain_ready:
		return
	var data := _terrain.data
	var pixel := Color(Terrain3DUtil.as_float(Terrain3DUtil.enc_base(layer)), 0.0, 0.0, 0.0)
	var r := _rect_indices(center, half_size)
	for iz in range(r[1], r[3] + 1):
		for ix in range(r[0], r[2] + 1):
			data.set_pixel(Terrain3DRegion.TYPE_CONTROL, _vertex_world(iz * resolution_x + ix), pixel)
	_mark_rect_regions(r)
	_update_maps(Terrain3DRegion.TYPE_CONTROL)


## Pittura sul color map di Terrain3D (strade, piazza, cumuli, barricate); niente in headless.
func tint(center: Vector3, radius: float, color: Color, strength: float) -> void:
	if not _terrain_ready:
		return
	_tint_disc(center, radius, color, strength)
	_update_maps(Terrain3DRegion.TYPE_COLOR)


## Tante pennellate di colore con un solo aggiornamento delle mappe (prato dipinto).
func tint_points(points: Array[Vector3], radius: float, color: Color, strength: float) -> void:
	if not _terrain_ready or points.is_empty():
		return
	for center in points:
		_tint_disc(center, radius, color, strength)
	_update_maps(Terrain3DRegion.TYPE_COLOR)


## Tinta uniforme su un rettangolo XZ; strength 0 la toglie (torna al bianco).
func tint_rect(center: Vector3, half_size: Vector2, color: Color, strength: float) -> void:
	if not _terrain_ready:
		return
	var data := _terrain.data
	var r := _rect_indices(center, half_size)
	var target := Color.WHITE if strength <= 0.0 else color
	var w := 1.0 if strength <= 0.0 else clampf(strength, 0.0, 1.0)
	for iz in range(r[1], r[3] + 1):
		for ix in range(r[0], r[2] + 1):
			var world := _vertex_world(iz * resolution_x + ix)
			var old: Color = data.get_pixel(Terrain3DRegion.TYPE_COLOR, world)
			data.set_pixel(Terrain3DRegion.TYPE_COLOR, world, old.lerp(Color(target.r, target.g, target.b, old.a), w))
	_mark_rect_regions(r)
	_update_maps(Terrain3DRegion.TYPE_COLOR)


func _tint_disc(center: Vector3, radius: float, color: Color, strength: float) -> void:
	var data := _terrain.data
	for p in _disc_points(center, radius):
		var world := _vertex_world(p)
		var d := Vector2(world.x - center.x, world.z - center.z).length() / radius
		var w := clampf(strength * (1.0 - d * d), 0.0, 1.0)
		var old: Color = data.get_pixel(Terrain3DRegion.TYPE_COLOR, world)
		var mixed := Color(old.r, old.g, old.b, old.a).lerp(Color(color.r, color.g, color.b, old.a), w)
		data.set_pixel(Terrain3DRegion.TYPE_COLOR, world, mixed)
	_mark_regions(center, radius)


# --- Salvataggio del rilievo di base ------------------------------------------------

## Scrive le quote e il seme del layout che le ha prodotte ([param layout_seed]):
## un file cotto con un altro quartiere viene rifiutato da `load_base`.
func save_base(path: String, layout_seed := 0) -> int:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return 0
	file.store_buffer(SAVE_MAGIC.to_ascii_buffer())
	file.store_32(SAVE_VERSION)
	file.store_32(resolution_x)
	file.store_32(resolution_z)
	file.store_float(size_m.x)
	file.store_float(size_m.y)
	file.store_32(layout_seed)
	var raw := _heights.to_byte_array()
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	file.store_32(raw.size())
	file.store_32(packed.size())
	file.store_buffer(packed)
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	return 32 + packed.size()


func load_base(path: String, layout_seed := 0) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_buffer(4).get_string_from_ascii() != SAVE_MAGIC or file.get_32() != SAVE_VERSION:
		return false
	if file.get_32() != resolution_x or file.get_32() != resolution_z:
		return false
	if not is_equal_approx(file.get_float(), size_m.x) or not is_equal_approx(file.get_float(), size_m.y):
		return false
	if file.get_32() != layout_seed:
		return false
	var raw_size := file.get_32()
	var packed_size := file.get_32()
	var raw := file.get_buffer(packed_size).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != resolution_x * resolution_z * 4:
		return false
	_heights = raw.to_float32_array()
	_base = _heights.duplicate()
	_mirror_all()
	region_changed.emit(_full_aabb())
	return true


# --- Interni ---------------------------------------------------------------------------

func _index_of(p: Vector3) -> int:
	var ix := int(round((p.x + _half.x) / SPACING))
	var iz := int(round((p.z + _half.y) / SPACING))
	if ix < 0 or iz < 0 or ix >= resolution_x or iz >= resolution_z:
		return -1
	return iz * resolution_x + ix


func _vertex_world(i: int) -> Vector3:
	var ix := i % resolution_x
	var iz := i / resolution_x
	return Vector3(ix * SPACING - _half.x, _heights[i], iz * SPACING - _half.y)


func _sample(array: PackedFloat32Array, p: Vector3) -> float:
	var fx := clampf((p.x + _half.x) / SPACING, 0.0, resolution_x - 1.001)
	var fz := clampf((p.z + _half.y) / SPACING, 0.0, resolution_z - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * resolution_x + ix
	var top := lerpf(array[i], array[i + 1], tx)
	var bottom := lerpf(array[i + resolution_x], array[i + resolution_x + 1], tx)
	return lerpf(top, bottom, tz)


## Indici (x0, z0, x1, z1) dei vertici del rettangolo XZ, tagliati al campo.
func _rect_indices(center: Vector3, half_size: Vector2) -> Array[int]:
	return [
		maxi(int(floor((center.x - half_size.x + _half.x) / SPACING)), 0),
		maxi(int(floor((center.z - half_size.y + _half.y) / SPACING)), 0),
		mini(int(ceil((center.x + half_size.x + _half.x) / SPACING)), resolution_x - 1),
		mini(int(ceil((center.z + half_size.y + _half.y) / SPACING)), resolution_z - 1),
	]


func _full_aabb() -> AABB:
	return AABB(Vector3(-_half.x, MIN_HEIGHT, -_half.y), Vector3(_half.x * 2.0, MAX_HEIGHT - MIN_HEIGHT, _half.y * 2.0))


func _emit_rect_changed(x0: int, z0: int, x1: int, z1: int) -> void:
	var lo := Vector3(x0 * SPACING - _half.x, MIN_HEIGHT, z0 * SPACING - _half.y)
	var hi := Vector3(x1 * SPACING - _half.x, MAX_HEIGHT, z1 * SPACING - _half.y)
	region_changed.emit(AABB(lo, hi - lo))


## Indici dei vertici dentro il disco (XZ).
func _disc_points(center: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r := _rect_indices(center, Vector2(radius, radius))
	var r2 := radius * radius
	for iz in range(r[1], r[3] + 1):
		var wz := iz * SPACING - _half.y
		for ix in range(r[0], r[2] + 1):
			var wx := ix * SPACING - _half.x
			if (wx - center.x) * (wx - center.x) + (wz - center.z) * (wz - center.z) <= r2:
				out.append(iz * resolution_x + ix)
	return out


func _brush(center: Vector3, radius: float, shape: Callable) -> float:
	# Raggio nullo: nessuna pennellata (0/0 scriverebbe NaN nelle quote, audit T-05).
	if radius <= 0.0:
		return 0.0
	var volume := 0.0
	var changed := 0
	var r2 := radius * radius
	var r := _rect_indices(center, Vector2(radius, radius))
	# Pennellata tutta fuori dal campo: niente da scrivere e nessun AABB vuoto da emettere.
	if r[2] < r[0] or r[3] < r[1]:
		return 0.0
	for iz in range(r[1], r[3] + 1):
		var wz := iz * SPACING - _half.y
		for ix in range(r[0], r[2] + 1):
			var wx := ix * SPACING - _half.x
			var d2 := ((wx - center.x) * (wx - center.x) + (wz - center.z) * (wz - center.z)) / r2
			if d2 >= 1.0:
				continue
			var i := iz * resolution_x + ix
			if _protected[i] != 0:
				continue
			var falloff := (1.0 - d2) * (1.0 - d2)
			var before := _heights[i]
			var after := clampf(shape.call(before, falloff), MIN_HEIGHT, MAX_HEIGHT)
			if after == before:
				continue
			_heights[i] = after
			volume += (after - before) * SPACING * SPACING
			changed += 1
	# Niente di cambiato (disco protetto, fondo o cima gia raggiunti): niente specchio,
	# collisione ne campo di percorso da rifare (audit T-03).
	if changed == 0:
		return 0.0
	_flush_rect(r[0], r[1], r[2], r[3])
	return volume


## Comincia un lotto di pennellate con un solo aggiornamento finale (annidabile).
func begin_batch() -> void:
	_batch_depth += 1


## Chiude il lotto: specchio, collisione e `region_changed` una volta sola sull'unione.
func end_batch() -> void:
	_batch_depth = maxi(_batch_depth - 1, 0)
	if _batch_depth > 0:
		return
	# Prima le mappe rimandate (strati, tinte, quote scritte direttamente), tutte insieme e
	# smarcando le regioni una volta sola: smarcarle dopo il primo tipo perderebbe gli altri.
	if not _batch_maps.is_empty():
		var pending := _batch_maps.keys()
		_batch_maps.clear()
		if _terrain_ready:
			for map_type: int in pending:
				_terrain.data.update_maps(map_type, false)
			_clear_edited_regions()
	if _batch_rect.is_empty():
		return
	var r := _batch_rect
	_batch_rect = []
	_mirror_rect(r[0], r[1], r[2], r[3])
	_emit_rect_changed(r[0], r[1], r[2], r[3])


## Fine di una pennellata sul rettangolo di indici: subito, o nell'unione del lotto aperto.
func _flush_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	if _batch_depth == 0:
		_mirror_rect(x0, z0, x1, z1)
		_emit_rect_changed(x0, z0, x1, z1)
		return
	if _batch_rect.is_empty():
		_batch_rect = [x0, z0, x1, z1]
	else:
		_batch_rect = [mini(_batch_rect[0], x0), mini(_batch_rect[1], z0), maxi(_batch_rect[2], x1), maxi(_batch_rect[3], z1)]


# --- Terrain3D (solo resa) ------------------------------------------------------------

func _build_terrain3d() -> void:
	_terrain = Terrain3D.new()
	_terrain.name = "Terrain3D"
	_terrain.vertex_spacing = SPACING
	_terrain.region_size = REGION_SIZE
	add_child(_terrain)
	# La collisione di Terrain3D non serve (D-085: chunk nostri); l'oggetto nasce con il nodo.
	_disable_terrain3d_collision()
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_terrain.set_camera(camera)
	# In headless (e nel primo fotogramma) `data` non esiste ancora.
	if _terrain.data == null:
		await get_tree().process_frame
	if _terrain.data == null or not is_inside_tree():
		return
	_disable_terrain3d_collision()
	# Regioni da 128 m centrate sull'origine, quante ne servono per asse (tappa B).
	var region_m := REGION_SIZE * SPACING
	var nx := int(ceil(_half.x / region_m))
	var nz := int(ceil(_half.y / region_m))
	for gx in range(-nx, nx):
		for gz in range(-nz, nz):
			_terrain.data.add_region_blankp(Vector3((gx + 0.5) * region_m, 0.0, (gz + 0.5) * region_m), false)
	_apply_quality_preset()
	_terrain_ready = true
	TerrainSurface.apply(_terrain)
	TerrainSurface.update_base(_terrain, _base, resolution_x, resolution_z, _half)
	_mirror_all()
	render_ready.emit()


## Steam Deck e Basso: meno anelli di LOD e piu piccoli (spec 6.3).
func _apply_quality_preset() -> void:
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	if settings == null:
		return
	if reduced_detail(settings):
		_terrain.mesh_lods = 5
		_terrain.mesh_size = 32


## Dettaglio ridotto del terreno (meno anelli di LOD, piu piccoli). Segue la qualita delle
## ombre, come le ombre leggere dei preset bassi (audit Q-02): prima valeva solo con i
## preset Deck e Basso esatti, e toccare un'opzione qualsiasi (Personalizzato) lo toglieva.
static func reduced_detail(settings: GameSettingsService) -> bool:
	return settings.shadow_quality <= 1


func _disable_terrain3d_collision() -> void:
	if _terrain != null and _terrain.collision != null:
		_terrain.collision.mode = Terrain3DCollision.DISABLED


func _mirror_all() -> void:
	if not _terrain_ready:
		return
	_mirror_rect(0, 0, resolution_x - 1, resolution_z - 1)


func _mirror_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	if not _terrain_ready:
		return
	var data := _terrain.data
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			data.set_height(Vector3(ix * SPACING - _half.x, 0.0, iz * SPACING - _half.y), _heights[iz * resolution_x + ix])
	_mark_rect_regions([x0, z0, x1, z1])
	_update_maps(Terrain3DRegion.TYPE_HEIGHT)


## Ricarica sulla GPU le mappe di [param map_type] delle regioni marcate `edited`, poi
## le smarca. Terrain3D non le smarca da solo (lo fa il suo editor dopo ogni
## operazione): lasciate marcate, ogni aggiornamento ricaricava tutte le regioni del
## livello, fino a 23 ms a pennellata sulla ferrovia.
func _update_maps(map_type: int) -> void:
	# Dentro un lotto: un solo caricamento per tipo a fine lotto (audit PF-03: dipingere il
	# quartiere ne faceva centinaia, 478 ms al caricamento).
	if _batch_depth > 0:
		_batch_maps[map_type] = true
		return
	_terrain.data.update_maps(map_type, false)
	_clear_edited_regions()


func _clear_edited_regions() -> void:
	for region: Terrain3DRegion in _terrain.data.get_regions_active():
		region.edited = false


func _mark_regions(center: Vector3, radius: float) -> void:
	for offset in [Vector3(-radius, 0, -radius), Vector3(radius, 0, -radius), Vector3(-radius, 0, radius), Vector3(radius, 0, radius)]:
		var region: Terrain3DRegion = _terrain.data.get_regionp(center + offset)
		if region != null:
			region.edited = true


## Marca `edited` ogni regione toccata dal rettangolo di indici (anche quelle interne,
## se il rettangolo e piu largo di una regione: il treno).
func _mark_rect_regions(r: Array[int]) -> void:
	var lo := Vector3(r[0] * SPACING - _half.x, 0.0, r[1] * SPACING - _half.y)
	var hi := Vector3(r[2] * SPACING - _half.x, 0.0, r[3] * SPACING - _half.y)
	var region_m := REGION_SIZE * SPACING
	var x := lo.x
	while true:
		var z := lo.z
		while true:
			var region: Terrain3DRegion = _terrain.data.get_regionp(Vector3(minf(x, hi.x), 0.0, minf(z, hi.z)))
			if region != null:
				region.edited = true
			if z >= hi.z:
				break
			z += region_m
		if x >= hi.x:
			break
		x += region_m
