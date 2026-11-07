class_name ModuleRelics
extends Node3D
## Relitti dei moduli staccati (D-093, piano C): terremoto e treno staccano moduli dalla carovana e
## li lasciano a terra, in superficie (non sepolti come casse e relitti di MachineWrecks). Ogni
## relitto e il pezzo del suo modulo poggiato al suolo, con il luccichio arancione dei relitti
## sepolti sopra; Interagisci vicino lo riprende (lo decide ArenaRun) e torna macchina piccola.
## I pezzi seguono la quota del suolo (`region_changed`); il treno li spazza via come le casse.
## Gli indici restano stabili: un relitto ripreso o spazzato resta in lista, spento.

const GLINT_RANGE := 3.0
## Quello dei relitti sepolti (MachineWrecks).
const GLINT_COLOR := Color(1.0, 0.45, 0.1)
## Il luccichio sta sopra il pezzo, che e alto al piu un metro (Faro).
const GLINT_LIFT := 0.7
## Lato del cubo di ripiego (modulo senza pezzo, come il Cassone), in metri.
const FALLBACK_SIZE := 0.4

@export var terrain_field: TerrainField
## Chi deve stare entro GLINT_RANGE perche il luccichio si veda (il giocatore).
@export var player: Node3D

## { module_id: StringName, position: Vector3 (alla quota del suolo), taken: bool,
## piece: Node3D, glint: MeshInstance3D }.
var _relics: Array[Dictionary] = []
var _glint_mesh := QuadMesh.new()
var _glint_material := StandardMaterial3D.new()
var _time := 0.0


func _ready() -> void:
	_glint_mesh.size = Vector2.ONE * BuriedCaches.GLINT_SIZE
	# Stella a quattro punte come quella delle casse sepolte, nel colore dei relitti.
	_glint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glint_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glint_material.billboard_keep_scale = true
	_glint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glint_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glint_material.no_depth_test = true
	_glint_material.albedo_color = GLINT_COLOR
	_glint_material.albedo_texture = BuriedCaches._star_texture()
	# Il luccichio gira solo finche c'e un relitto a terra.
	set_process(false)
	if terrain_field != null:
		terrain_field.region_changed.connect(refresh_heights)


## Posa a terra in [param at] (XZ) il relitto del modulo [param module_id]; ritorna il suo indice.
func drop(module_id: StringName, at: Vector3) -> int:
	var ground := terrain_field.height_at(at) if terrain_field != null else at.y
	var p := Vector3(at.x, ground, at.z)
	var piece := _build_piece(module_id, p)
	add_child(piece)
	piece.global_position = p
	var glint := MeshInstance3D.new()
	glint.mesh = _glint_mesh
	glint.material_override = _glint_material
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glint.visible = false
	add_child(glint)
	glint.global_position = p + Vector3(0.0, GLINT_LIFT, 0.0)
	var index := _relics.size()
	_relics.append({module_id = module_id, position = p, taken = false, piece = piece, glint = glint})
	set_process(true)
	print("PROTOTYPE01_MODULE_RELIC_DROPPED module=%s x=%.1f z=%.1f" % [module_id, p.x, p.z])
	return index


## Relitti ancora a terra.
func count() -> int:
	var on_ground := 0
	for relic in _relics:
		if not relic.taken:
			on_ground += 1
	return on_ground


## Relitto a terra piu vicino a [param point] (distanza in XZ) entro [param range], o -1.
func nearest_index(point: Vector3, range: float) -> int:
	var best := -1
	var best_distance := range
	for i in _relics.size():
		var relic: Dictionary = _relics[i]
		if relic.taken:
			continue
		var p: Vector3 = relic.position
		var distance := Vector2(p.x - point.x, p.z - point.z).length()
		if distance <= best_distance:
			best = i
			best_distance = distance
	return best


## Modulo del relitto [param index]; &"" per un indice fuori lista.
func module_of(index: int) -> StringName:
	if not _has_index(index):
		return &""
	return _relics[index].module_id


## Punto del relitto [param index] alla quota del suolo; `Vector3.INF` per un indice fuori lista.
func position_of(index: int) -> Vector3:
	if not _has_index(index):
		return Vector3.INF
	return _relics[index].position


## Pezzo a terra del relitto [param index] (test, catture); dopo la presa e gia liberato.
func piece_of(index: int) -> Node3D:
	return _relics[index].piece


func glint_visible(index: int) -> bool:
	var relic: Dictionary = _relics[index]
	return not relic.taken and (relic.glint as MeshInstance3D).visible


## Toglie da terra il relitto [param index] (pezzo e luccichio) e ritorna il suo modulo; &"" se
## era gia stato ripreso o spazzato o se l'indice e fuori lista.
func take(index: int) -> StringName:
	if not _has_index(index):
		return &""
	var relic: Dictionary = _relics[index]
	if relic.taken:
		return &""
	_remove(relic)
	print("PROTOTYPE01_MODULE_RELIC_TAKEN module=%s" % relic.module_id)
	return relic.module_id


## Relitti a terra col centro nel rettangolo XZ: persi (il treno li spazza). Ritorna quanti.
func discard_in_rect(rect: Rect2) -> int:
	var discarded := 0
	for relic in _relics:
		var p: Vector3 = relic.position
		if not relic.taken and rect.has_point(Vector2(p.x, p.z)):
			_remove(relic)
			discarded += 1
	return discarded


## Collegata a `terrain_field.region_changed`: i relitti nella regione seguono la quota nuova.
func refresh_heights(aabb: AABB) -> void:
	if terrain_field == null:
		return
	var area := Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z).grow(0.5)
	for relic in _relics:
		if relic.taken:
			continue
		var p: Vector3 = relic.position
		if not area.has_point(Vector2(p.x, p.z)):
			continue
		p.y = terrain_field.height_at(p)
		relic.position = p
		(relic.piece as Node3D).global_position.y = p.y
		(relic.glint as MeshInstance3D).global_position.y = p.y + GLINT_LIFT


func _process(delta: float) -> void:
	_time += delta
	var pulse := 1.0 + sin(_time * BuriedCaches.PULSE_SPEED) * BuriedCaches.PULSE_AMOUNT
	for relic in _relics:
		if relic.taken:
			continue
		var glint: MeshInstance3D = relic.glint
		var p: Vector3 = relic.position
		var near := player != null and Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() <= GLINT_RANGE
		glint.visible = near
		if near:
			glint.scale = Vector3.ONE * pulse


func _has_index(index: int) -> bool:
	return index >= 0 and index < _relics.size()


func _remove(relic: Dictionary) -> void:
	relic.taken = true
	(relic.piece as Node3D).queue_free()
	(relic.glint as MeshInstance3D).queue_free()
	if count() == 0:
		set_process(false)


## Pezzo del modulo (il suo `build_part`, poggiato al suolo) o un cubo del colore del modulo; la
## sua imbardata viene dal punto, come i telai di MachineWrecks. Sul layer visivo delle macchine.
func _build_piece(module_id: StringName, p: Vector3) -> Node3D:
	var piece := Node3D.new()
	piece.name = "Relic%s" % String(module_id).capitalize()
	piece.rotation.y = fposmod(p.x * 0.37 + p.z * 0.61, 1.0) * TAU
	var module := Caravan.module_script_for(module_id).new() as MachineModule
	module.module_id = module_id
	var part := module.build_part()
	module.free()
	if part == null:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * FALLBACK_SIZE
		box.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = MachineCatalog.find(module_id).get(&"color", Color.GRAY)
		box.material_override = material
		box.position.y = FALLBACK_SIZE * 0.5
		part = box
	else:
		# Il pezzo nasce alzato sul telaio della macchina: a terra poggia sul suolo col suo
		# punto piu basso (la base della Torretta, centrata nell'origine, finirebbe sotto).
		part.position = Vector3.ZERO
		part.position.y = -_bottom_of(part)
	piece.add_child(part)
	_set_visual_layer(piece)
	return piece


## Quota piu bassa delle mesh di [param part] nello spazio del suo genitore (0 senza mesh).
static func _bottom_of(part: Node3D) -> float:
	var meshes: Array[Node] = part.find_children("*", "MeshInstance3D", true, false)
	if part is MeshInstance3D:
		meshes.append(part)
	var bottom := INF
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var walker: Node3D = mesh_instance
		while walker != null:
			xform = walker.transform * xform
			if walker == part:
				break
			walker = walker.get_parent() as Node3D
		bottom = minf(bottom, (xform * mesh_instance.mesh.get_aabb()).position.y)
	return bottom if bottom != INF else 0.0


static func _set_visual_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = Machine.VISUAL_LAYER
	for child in node.get_children():
		_set_visual_layer(child)
