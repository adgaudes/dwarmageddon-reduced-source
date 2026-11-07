class_name HeightTerrain
extends Node3D
## SPIKE (docs/TERRAIN_SYSTEM.md, "Spike tecnico di deformazione continua"): terreno a
## rilievo continuo. Una quota per vertice su una maglia regolare, scolpita con un
## pennello a campana; niente celle, niente collisioni fisiche: chi cammina chiede la
## quota ([method height_at]) e il passo ammesso ([method slide_move]).
## Si disegna con una sola mesh piana spostata dallo shader: scolpire aggiorna una
## texture, non ricostruisce geometria.
## Codice di prova: non e usato dal livello vero.

signal changed

## Lato di una maglia, in metri.
const CELL := 0.5
const MIN_HEIGHT := -2.0
const MAX_HEIGHT := 3.5
const SHADER := preload("res://resources/materials/height_terrain.gdshader")
## File del rilievo: magic, versione, vertici per lato, byte non compressi, poi zstd.
const SAVE_MAGIC := "HTER"
const SAVE_VERSION := 1
const SAVE_HEADER_SIZE := 16

## Lato del terreno in metri (centrato sull'origine).
@export var size_m := 96.0

## Vertici per lato.
var resolution := 0
var heights := PackedFloat32Array()

var _base := PackedFloat32Array()
var _half := 0.0
var _image: Image
var _texture: ImageTexture
var _texture_dirty := false


func _ready() -> void:
	if resolution == 0:
		build()


## Crea la maglia piatta e la mesh. Da richiamare se cambia [member size_m].
func build() -> void:
	resolution = int(round(size_m / CELL)) + 1
	_half = (resolution - 1) * CELL * 0.5
	heights.resize(resolution * resolution)
	heights.fill(0.0)
	_base = heights.duplicate()
	_image = Image.create_empty(resolution, resolution, false, Image.FORMAT_RGF)
	_texture = ImageTexture.create_from_image(_image)

	for child in get_children():
		child.queue_free()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (resolution - 1) * CELL
	plane.subdivide_width = resolution - 2
	plane.subdivide_depth = resolution - 2
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"height_map", _texture)
	material.set_shader_parameter(&"resolution", float(resolution))
	material.set_shader_parameter(&"cell", CELL)
	var instance := MeshInstance3D.new()
	instance.name = "Surface"
	instance.mesh = plane
	instance.material_override = material
	# I vertici si spostano nello shader: il volume vero va dichiarato a mano.
	instance.custom_aabb = AABB(Vector3(-_half, MIN_HEIGHT, -_half), Vector3(_half * 2.0, MAX_HEIGHT - MIN_HEIGHT, _half * 2.0))
	add_child(instance)


func half_extent() -> float:
	return _half


## Fissa il rilievo attuale come "naturale": da qui in poi lo shader colora di terra
## smossa solo cio che il giocatore cambia.
func commit_base() -> void:
	_base = heights.duplicate()
	_refresh_all()


## Quota (m) nel punto mondo, interpolata fra i quattro vertici vicini.
func height_at(point: Vector3) -> float:
	var fx := clampf((point.x + _half) / CELL, 0.0, resolution - 1.001)
	var fz := clampf((point.z + _half) / CELL, 0.0, resolution - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * resolution + ix
	var top := lerpf(heights[i], heights[i + 1], tx)
	var bottom := lerpf(heights[i + resolution], heights[i + resolution + 1], tx)
	return lerpf(top, bottom, tz)


## Normale della superficie nel punto mondo.
func normal_at(point: Vector3) -> Vector3:
	var dx := height_at(point + Vector3(CELL, 0.0, 0.0)) - height_at(point - Vector3(CELL, 0.0, 0.0))
	var dz := height_at(point + Vector3(0.0, 0.0, CELL)) - height_at(point - Vector3(0.0, 0.0, CELL))
	return Vector3(-dx, 2.0 * CELL, -dz).normalized()


## Aggiunge [param amount] metri al centro del pennello, a campana fino a zero sul
## bordo (negativo = scava). Restituisce il volume spostato in m3, col segno.
func sculpt(center: Vector3, radius: float, amount: float) -> float:
	return _brush(center, radius, func(height: float, falloff: float) -> float:
		return height + amount * falloff)


## Avvicina la zona a [param target_height]: [param strength] 1 al centro la porta
## esattamente li. Restituisce il volume spostato in m3, col segno.
func level(center: Vector3, radius: float, target_height: float, strength: float) -> float:
	return _brush(center, radius, func(height: float, falloff: float) -> float:
		return height + (target_height - height) * clampf(strength * falloff, 0.0, 1.0))


## Si puo salire da [param from] a [param to]? In discesa sempre; in salita solo se la
## pendenza del tratto non supera [param max_grade] (metri di quota per metro).
func can_step(from: Vector3, to: Vector3, max_grade: float) -> bool:
	var run := Vector2(to.x - from.x, to.z - from.z).length()
	if run < 0.0001:
		return true
	return height_at(to) - height_at(from) <= max_grade * run


## Passo in piano da [param from] verso [param to] rispettando la pendenza: se il tratto
## e troppo ripido prova a scorrere lungo un asse. Restituisce il punto raggiunto, gia
## posato sulla superficie e dentro i bordi.
func slide_move(from: Vector3, to: Vector3, max_grade: float) -> Vector3:
	var limit := _half - CELL
	to.x = clampf(to.x, -limit, limit)
	to.z = clampf(to.z, -limit, limit)
	var reached := from
	if can_step(from, to, max_grade):
		reached = to
	else:
		var along_x := Vector3(to.x, from.y, from.z)
		var along_z := Vector3(from.x, from.y, to.z)
		# Prima l'asse lungo cui ci si muove di piu.
		var first := along_x if absf(to.x - from.x) >= absf(to.z - from.z) else along_z
		var second := along_z if first == along_x else along_x
		if can_step(from, first, max_grade):
			reached = first
		elif can_step(from, second, max_grade):
			reached = second
	reached.y = height_at(reached)
	return reached


## Scrive il rilievo in [param path]; restituisce i byte scritti, 0 se fallisce.
## Scrittura su `.tmp` e rinomina: un crash a meta lascia intatto il file precedente.
func save_heights(path: String) -> int:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return 0
	var bytes := heights.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)
	file.store_buffer(SAVE_MAGIC.to_ascii_buffer())
	file.store_32(SAVE_VERSION)
	file.store_32(resolution)
	file.store_32(heights.size() * 4)
	file.store_buffer(bytes)
	file.close()
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	if DirAccess.rename_absolute(absolute_temp, ProjectSettings.globalize_path(path)) != OK:
		DirAccess.remove_absolute(absolute_temp)
		return 0
	return bytes.size() + SAVE_HEADER_SIZE


## Legge un file di [method save_heights] della stessa misura; falso (e rilievo
## intatto) se manca, e troncato, di altra versione o di altra misura.
func load_heights(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= SAVE_HEADER_SIZE:
		return false
	if file.get_buffer(4).get_string_from_ascii() != SAVE_MAGIC or file.get_32() != SAVE_VERSION:
		return false
	if file.get_32() != resolution:
		return false
	var raw_size := file.get_32()
	# Dimensione dichiarata controllata prima di decomprimere: niente buffer a piacere.
	if raw_size != resolution * resolution * 4:
		return false
	var packed := file.get_buffer(file.get_length() - SAVE_HEADER_SIZE)
	var loaded := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD).to_float32_array()
	if loaded.size() != heights.size():
		return false
	heights = loaded
	_refresh_all()
	changed.emit()
	return true


func _process(_delta: float) -> void:
	if _texture_dirty:
		_texture_dirty = false
		_texture.update(_image)


func _brush(center: Vector3, radius: float, shape: Callable) -> float:
	var x0 := maxi(int(ceil((center.x - radius + _half) / CELL)), 0)
	var x1 := mini(int(floor((center.x + radius + _half) / CELL)), resolution - 1)
	var z0 := maxi(int(ceil((center.z - radius + _half) / CELL)), 0)
	var z1 := mini(int(floor((center.z + radius + _half) / CELL)), resolution - 1)
	var moved := 0.0
	for iz in range(z0, z1 + 1):
		var dz := (iz * CELL - _half - center.z) / radius
		for ix in range(x0, x1 + 1):
			var dx := (ix * CELL - _half - center.x) / radius
			var d2 := dx * dx + dz * dz
			if d2 >= 1.0:
				continue
			var i := iz * resolution + ix
			var height := clampf(shape.call(heights[i], (1.0 - d2) * (1.0 - d2)), MIN_HEIGHT, MAX_HEIGHT)
			moved += height - heights[i]
			heights[i] = height
			_image.set_pixel(ix, iz, Color(height, height - _base[i], 0.0))
	_texture_dirty = true
	changed.emit()
	return moved * CELL * CELL


func _refresh_all() -> void:
	for iz in resolution:
		for ix in resolution:
			var i := iz * resolution + ix
			_image.set_pixel(ix, iz, Color(heights[i], heights[i] - _base[i], 0.0))
	_texture_dirty = true
