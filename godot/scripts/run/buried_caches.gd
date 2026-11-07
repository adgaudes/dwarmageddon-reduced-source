class_name BuriedCaches
extends Node3D
## Casse sepolte (spec D-092, par. 6.3): stanno alla quota di base sotto un cumulo di rottami o
## un vagone, come le vene di ScrapField. Da vicino (GLINT_RANGE) un luccichio a terra le rivela;
## quando il suolo nel loro punto scende entro OPEN_MARGIN dalla base (scavo del giocatore,
## del Demolitore o delle armi) la cassa sale, sparisce e arriva `cache_opened`. La scelta
## delle carte la fa ArenaRun. Le sottoclassi (MachineWrecks) cambiano colore del luccichio,
## nome del marker, telaio a vista (`_make_frame`) e oggetto che sale (`_make_marker`).

signal cache_opened(at: Vector3)

const GLINT_RANGE := 3.0
## Come l'estrazione delle vene (0,05 m in ScrapField), con un po' di margine in piu.
const OPEN_MARGIN := 0.1
const GLINT_COLOR := Color(1.0, 0.85, 0.4)
## Lato della stella a quattro punte (billboard), in metri.
const GLINT_SIZE := 0.8
## Il luccichio poggia sul suolo sopra la cassa, sollevato di poco.
const GLINT_LIFT := 0.2
const GLINT_TEXTURE_SIZE := 64
const PULSE_SPEED := 6.0
const PULSE_AMOUNT := 0.35
const CRATE_COLOR := Color(0.42, 0.27, 0.12)
const CRATE_SIZE := 0.6
const RISE_SECONDS := 0.6
const RISE_HEIGHT := 1.2
const VANISH_SECONDS := 0.12

@export var terrain_field: TerrainField
## Chi deve stare entro GLINT_RANGE perche il luccichio si veda (il giocatore).
@export var player: Node3D
## Colore del luccichio e nome nel marker `PROTOTYPE01_<nome>_OPENED`: le sottoclassi li
## cambiano nel loro `_init()`.
var glint_color := GLINT_COLOR
var marker_name := "CACHE"

## { position: Vector3 (alla quota di base), opened: bool, glint: MeshInstance3D,
## frame: Node3D (null per le casse) }.
var _caches: Array[Dictionary] = []
var _glint_mesh := QuadMesh.new()
var _glint_material := StandardMaterial3D.new()
var _crate_mesh := BoxMesh.new()
var _crate_material := StandardMaterial3D.new()
var _time := 0.0


func _ready() -> void:
	_glint_mesh.size = Vector2.ONE * GLINT_SIZE
	# Stella a quattro punte sempre rivolta alla camera, additiva, sopra il suolo del cumulo.
	_glint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glint_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glint_material.billboard_keep_scale = true
	_glint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glint_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glint_material.no_depth_test = true
	_glint_material.albedo_color = glint_color
	_glint_material.albedo_texture = _star_texture()
	_crate_mesh.size = Vector3.ONE * CRATE_SIZE
	_crate_material.albedo_color = CRATE_COLOR.linear_to_srgb()
	# Il luccichio gira solo finche c'e una cassa chiusa.
	set_process(false)
	if terrain_field != null:
		terrain_field.player_sculpted.connect(_on_player_sculpted)
		terrain_field.region_changed.connect(_on_region_changed)


## Posa una cassa in ogni punto (XZ), alla quota di base del campo. Un punto gia scoperto
## (suolo entro OPEN_MARGIN dalla base) non riceve cassa: si aprirebbe da sola.
func place(points: Array[Vector3]) -> void:
	for point in points:
		var at := Vector3(point.x, terrain_field.base_height_at(point), point.z)
		var ground := terrain_field.height_at(at)
		if ground <= at.y + OPEN_MARGIN:
			continue
		var glint := MeshInstance3D.new()
		glint.mesh = _glint_mesh
		glint.material_override = _glint_material
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glint.visible = false
		add_child(glint)
		glint.global_position = Vector3(at.x, ground + GLINT_LIFT, at.z)
		var index := _caches.size()
		_caches.append({position = at, opened = false, glint = glint, frame = null})
		var frame := _make_frame(index)
		if frame != null:
			add_child(frame)
			frame.global_position = Vector3(at.x, ground, at.z)
			_caches[index].frame = frame
	set_process(closed_count() > 0)


func count() -> int:
	return _caches.size()


func closed_count() -> int:
	var closed := 0
	for cache in _caches:
		if not cache.opened:
			closed += 1
	return closed


## Punto della cassa [param index] alla quota di base (test, catture).
func position_of(index: int) -> Vector3:
	return _caches[index].position


func glint_visible(index: int) -> bool:
	var glint: MeshInstance3D = _caches[index].glint
	return not _caches[index].opened and glint.visible


## Telaio a vista della voce [param index]: null per le casse e dopo l'apertura o lo scarto.
func frame_of(index: int) -> Node3D:
	return _caches[index].frame


## Telaio sempre a vista dalla posa all'apertura (o allo scarto), alla quota del suolo:
## le casse non ne hanno.
func _make_frame(_index: int) -> Node3D:
	return null


## Cio che sale dal suolo all'apertura (la cassa), poi rimpicciolisce e sparisce.
func _make_marker(_index: int) -> Node3D:
	var crate := MeshInstance3D.new()
	crate.mesh = _crate_mesh
	crate.material_override = _crate_material
	return crate


## Punti per le casse: fra le pennellate con rottami (cumuli, vagoni), una cassa per pennellata
## a meta raggio dal centro in una direzione a caso; mai piu punti di quante sono le pennellate.
## Le pennellate che contengono (XZ) un punto di [param exclude] si saltano.
static func pick_points(district_strokes: Array, rng: RandomNumberGenerator, count: int, exclude: Array[Vector3] = []) -> Array[Vector3]:
	var candidates: Array[Dictionary] = []
	for stroke: Dictionary in district_strokes:
		if int(stroke.get(&"scrap", 0)) > 0 and not _holds_any(stroke, exclude):
			candidates.append(stroke)
	var points: Array[Vector3] = []
	while points.size() < count and not candidates.is_empty():
		var stroke: Dictionary = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		var angle := rng.randf() * TAU
		var center: Vector2 = stroke.center
		var offset := Vector2(cos(angle), sin(angle)) * float(stroke.radius) * 0.5
		points.append(Vector3(center.x + offset.x, 0.0, center.y + offset.y))
	return points


static func _holds_any(stroke: Dictionary, points: Array[Vector3]) -> bool:
	var center: Vector2 = stroke.center
	for e in points:
		if Vector2(e.x, e.z).distance_to(center) <= float(stroke.radius):
			return true
	return false


## Casse chiuse col centro nel rettangolo XZ: perse senza aprirsi (il treno spazza i vagoni,
## come le vene). Va chiamata prima di riportare il suolo alla base. Ritorna quante.
func discard_in_rect(rect: Rect2) -> int:
	var discarded := 0
	for cache in _caches:
		var p: Vector3 = cache.position
		if not cache.opened and rect.has_point(Vector2(p.x, p.z)):
			cache.opened = true
			(cache.glint as MeshInstance3D).queue_free()
			_free_frame(cache)
			discarded += 1
	if discarded > 0:
		set_process(closed_count() > 0)
	return discarded


func _process(delta: float) -> void:
	_time += delta
	var pulse := 1.0 + sin(_time * PULSE_SPEED) * PULSE_AMOUNT
	for cache in _caches:
		if cache.opened:
			continue
		var glint: MeshInstance3D = cache.glint
		var p: Vector3 = cache.position
		var near := player != null and Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() <= GLINT_RANGE
		glint.visible = near
		if near:
			glint.scale = Vector3.ONE * pulse


## Stella a quattro punte bianca su fondo trasparente, disegnata una volta (niente asset).
static func _star_texture() -> ImageTexture:
	var image := Image.create_empty(GLINT_TEXTURE_SIZE, GLINT_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var half := GLINT_TEXTURE_SIZE * 0.5
	for y in GLINT_TEXTURE_SIZE:
		for x in GLINT_TEXTURE_SIZE:
			var u := (x + 0.5 - half) / half
			var v := (y + 0.5 - half) / half
			var core := exp(-(u * u + v * v) * 14.0)
			var rays := exp(-absf(v) * 24.0) * maxf(1.0 - absf(u), 0.0) + exp(-absf(u) * 24.0) * maxf(1.0 - absf(v), 0.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(core + rays, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)


func _on_player_sculpted(center: Vector3, radius: float, _volume: float, _mode: int) -> void:
	_check_rect(Rect2(center.x - radius, center.z - radius, radius * 2.0, radius * 2.0))


func _on_region_changed(aabb: AABB) -> void:
	_check_rect(Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z))


## Casse chiuse nel rettangolo: si aprono se il suolo e sceso alla base, altrimenti il
## luccichio segue il suolo nuovo.
func _check_rect(rect: Rect2) -> void:
	var area := rect.grow(0.5)
	for i in _caches.size():
		var cache: Dictionary = _caches[i]
		if cache.opened:
			continue
		var p: Vector3 = cache.position
		if not area.has_point(Vector2(p.x, p.z)):
			continue
		var ground := terrain_field.height_at(p)
		if ground <= p.y + OPEN_MARGIN:
			_open(i, ground)
		else:
			(cache.glint as MeshInstance3D).global_position.y = ground + GLINT_LIFT
			if cache.frame != null:
				(cache.frame as Node3D).global_position.y = ground


func _open(index: int, ground: float) -> void:
	var cache: Dictionary = _caches[index]
	cache.opened = true
	(cache.glint as MeshInstance3D).queue_free()
	_free_frame(cache)
	var p: Vector3 = cache.position
	# La cassa sale dal suolo in RISE_SECONDS e sparisce; anche a gioco fermo (si apre la scelta).
	var rising := _make_marker(index)
	add_child(rising)
	rising.global_position = Vector3(p.x, ground, p.z)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(rising, "position:y", rising.position.y + RISE_HEIGHT, RISE_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(rising, "rotation:y", PI, RISE_SECONDS)
	tween.tween_property(rising, "scale", Vector3.ONE * 0.05, VANISH_SECONDS)
	tween.tween_callback(rising.queue_free)
	if closed_count() == 0:
		set_process(false)
	print("PROTOTYPE01_%s_OPENED x=%.1f z=%.1f" % [marker_name, p.x, p.z])
	cache_opened.emit(p)


func _free_frame(cache: Dictionary) -> void:
	if cache.frame != null:
		(cache.frame as Node3D).queue_free()
		cache.frame = null
