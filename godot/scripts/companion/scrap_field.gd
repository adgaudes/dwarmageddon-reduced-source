class_name ScrapField
extends Node3D
## Rottami a terra: nascono quando una cella viene scavata (griglia) o quando il pennello
## asporta terra da una vena sepolta sotto un cumulo (rilievo continuo, spec 5.1), e
## restano finche un Cassone della carovana non li raccoglie. Nessuna fisica: posizioni e
## distanze bastano.

signal scrap_spawned(position: Vector3)

## Ruggine, lineare.
const SCRAP_COLOR := Color(0.55, 0.22, 0.06)
const SCRAP_SIZE := 0.3
## Nell'arena grande (D-042) i depositi scavati restano a terra lontano dai Cassoni.
const MAX_SCRAPS := 60
const BOB_HEIGHT := 0.08
const BOB_SPEED := 3.0
## Rilievo continuo: un rottame ogni tanti metri cubi asportati da una vena sotto la sua base.
const SCRAP_PER_M3 := 0.8
## Sopra questo dislivello fra la quota di posa e il suolo nuovo il rottame rotola.
const ROLL_RISE_M := 0.5

## Rilievo continuo (D-085): i rottami poggiano sulle quote e vengono solo dalle vene (D-056).
@export var terrain_field: TerrainField

## Quante volte il tetto `MAX_SCRAPS` ha fatto riciclare un rottame (per i test).
var capped_count := 0

var _scraps: Array[MeshInstance3D] = []
## Vene di rottami (spec 5.1): { center: Vector3, radius: float, scrap_left: int,
## base_height: float, dug_m3: float }.
var _veins: Array[Dictionary] = []
## Quota del suolo sotto ogni rottame al momento della posa (rilievo continuo).
var _rest_heights: Dictionary[MeshInstance3D, float] = {}
var _mesh := BoxMesh.new()
var _material := StandardMaterial3D.new()
var _time := 0.0


func _ready() -> void:
	_mesh.size = Vector3.ONE * SCRAP_SIZE
	_material.albedo_color = SCRAP_COLOR.linear_to_srgb()
	# Di notte i rottami si vedono da lontano (specifica giorno/notte, sezione 6).
	_material.emission_enabled = true
	_material.emission = SCRAP_COLOR.linear_to_srgb()
	_material.emission_energy_multiplier = 0.6
	# Il bob gira solo quando c'e almeno un rottame (P-04).
	set_process(false)
	if terrain_field != null:
		terrain_field.player_sculpted.connect(_on_player_sculpted)
		terrain_field.region_changed.connect(_on_region_changed)


func count() -> int:
	return _scraps.size()


func spawn(world_position: Vector3) -> void:
	if _scraps.size() >= MAX_SCRAPS:
		# Al tetto si ricicla il rottame piu lontano dal nuovo (cioe dal giocatore che
		# sta scavando): uno scavo produce sempre qualcosa di visibile (R-09).
		_remove_at(_farthest_index(world_position))
		capped_count += 1
		print("PROTOTYPE01_SCRAP_CAPPED")
	var scrap := MeshInstance3D.new()
	scrap.mesh = _mesh
	scrap.material_override = _material
	add_child(scrap)
	scrap.global_position = world_position
	# Quota di riposo del bob in coordinate locali: il campo puo non stare all'origine (P-03).
	scrap.set_meta(&"base_y", scrap.position.y)
	_scraps.append(scrap)
	set_process(true)
	print("PROTOTYPE01_SCRAP_SPAWNED")
	scrap_spawned.emit(world_position)


## Rottame piu vicino a [param origin] entro [param radius] (piano XZ), o null.
func nearest(origin: Vector3, radius: float) -> Variant:
	var best: Variant = null
	var best_distance := radius
	for scrap in _scraps:
		var distance := _planar_distance(scrap.global_position, origin)
		if distance <= best_distance:
			best_distance = distance
			best = scrap.global_position
	return best


## Posizioni dei rottami entro [param radius] (piano XZ) da [param origin].
func positions_near(origin: Vector3, radius: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for scrap in _scraps:
		if _planar_distance(scrap.global_position, origin) <= radius:
			result.append(scrap.global_position)
	return result


## Rottame lasciato cadere in un punto qualunque: resta li, alla quota del terreno sotto.
func spawn_on_ground(world: Vector3) -> void:
	var ground := terrain_field.height_at(world) if terrain_field != null else 0.0
	spawn(Vector3(world.x, ground + SCRAP_SIZE, world.z))
	_rest_heights[_scraps.back()] = ground


## Rimuove fino a [param max_count] rottami entro [param radius]; restituisce quanti.
func take_near(origin: Vector3, radius: float, max_count: int) -> int:
	var taken := 0
	# All'indietro: rimuovere non sposta gli indici ancora da visitare, niente copia (P-04).
	for i in range(_scraps.size() - 1, -1, -1):
		if taken >= max_count:
			break
		if _planar_distance(_scraps[i].global_position, origin) <= radius:
			_remove_at(i)
			taken += 1
	return taken


func _remove_at(index: int) -> void:
	_rest_heights.erase(_scraps[index])
	_scraps[index].queue_free()
	_scraps.remove_at(index)
	if _scraps.is_empty():
		set_process(false)


## Indice del rottame piu lontano (piano XZ) da [param origin].
func _farthest_index(origin: Vector3) -> int:
	var best := 0
	var best_distance := -1.0
	for i in _scraps.size():
		var distance := _planar_distance(_scraps[i].global_position, origin)
		if distance > best_distance:
			best_distance = distance
			best = i
	return best


func _process(delta: float) -> void:
	_time += delta
	for scrap in _scraps:
		var base_y: float = scrap.get_meta(&"base_y")
		scrap.position.y = base_y + sin(_time * BOB_SPEED + scrap.position.x) * BOB_HEIGHT
		scrap.rotation.y += delta


# --- Vene di rottami sul rilievo continuo (spec 5.1) --------------------------------------

func add_vein(center: Vector3, radius: float, scrap: int, base_height: float) -> void:
	_veins.append({ center = center, radius = radius, scrap_left = scrap, base_height = base_height, dug_m3 = 0.0, exhausted_tint = Color.WHITE })


func veins() -> Array[Dictionary]:
	return _veins


## Vene con il centro nel rettangolo XZ: azzerate senza rottami (il treno spazza i
## vagoni). Ritorna quante ne ha azzerate.
func exhaust_veins_in_rect(rect: Rect2) -> int:
	var count := 0
	for vein in _veins:
		if vein.scrap_left > 0 and rect.has_point(Vector2(vein.center.x, vein.center.z)):
			vein.scrap_left = 0
			vein.dug_m3 = 0.0
			if terrain_field != null:
				terrain_field.tint(vein.center, vein.radius, vein.get("exhausted_tint", Color.WHITE), 1.0)
			count += 1
	return count


## Rimuove fino a [param max_count] rottami con la base nel rettangolo XZ; ritorna quanti.
func take_in_rect(rect: Rect2, max_count: int) -> int:
	var taken := 0
	for i in range(_scraps.size() - 1, -1, -1):
		if taken >= max_count:
			break
		var p := _scraps[i].global_position
		if rect.has_point(Vector2(p.x, p.z)):
			_remove_at(i)
			taken += 1
	return taken


## Rottami ancora sepolti nella vena centrata entro 0,5 m da [param center]; 0 se non c'e.
func vein_scrap_left(center: Vector3) -> int:
	for vein in _veins:
		if _planar_distance(vein.center, center) <= 0.5:
			return vein.scrap_left
	return 0


## Volume (positivo, m3) asportato da un pennello in [param center]: se il centro e gia
## sotto la quota di base della vena, scala `dug_m3` e ogni SCRAP_PER_M3 fa nascere un
## rottame nel punto piu basso vicino. Usato dal tool del giocatore e dal Demolitore.
func extract_from_veins(center: Vector3, radius: float, volume: float) -> int:
	var spawned := 0
	for vein in _veins:
		if vein.scrap_left <= 0 or _planar_distance(vein.center, center) > vein.radius + radius:
			continue
		if terrain_field.height_at(center) > vein.base_height + 0.05:
			continue
		vein.dug_m3 += volume
		while vein.dug_m3 >= SCRAP_PER_M3 and vein.scrap_left > 0:
			vein.dug_m3 -= SCRAP_PER_M3
			vein.scrap_left -= 1
			spawn_on_ground(lowest_point_near(center, radius))
			spawned += 1
			print("PROTOTYPE01_VEIN_SCRAP left=%d" % vein.scrap_left)
		if vein.scrap_left == 0:
			# Vena finita: il cumulo perde la tinta di ruggine (niente in headless).
			terrain_field.tint(vein.center, vein.radius, vein.get("exhausted_tint", Color.WHITE), 1.0)
	return spawned


## Prima vena (nell'ordine di aggiunta) con rottami il cui disco tocca il cerchio di
## [param radius] attorno a [param center] (piano XZ), o un dizionario vuoto.
func vein_touching(center: Vector3, radius: float) -> Dictionary:
	for vein in _veins:
		if vein.scrap_left > 0 and _planar_distance(vein.center, center) <= vein.radius + radius:
			return vein
	return {}


## La vena di `vein_touching` cede un rottame, che nasce a terra in [param drop_at] (la
## Trivella): stessa contabilita e stessa tinta a vena finita di `extract_from_veins`, senza
## toccare `dug_m3`. Falso se nessuna vena tocca il cerchio.
func take_from_vein(center: Vector3, radius: float, drop_at: Vector3) -> bool:
	var vein := vein_touching(center, radius)
	if vein.is_empty():
		return false
	vein.scrap_left -= 1
	spawn_on_ground(drop_at)
	print("PROTOTYPE01_VEIN_SCRAP left=%d" % vein.scrap_left)
	if vein.scrap_left == 0 and terrain_field != null:
		terrain_field.tint(vein.center, vein.radius, vein.get("exhausted_tint", Color.WHITE), 1.0)
	return true


## Il piu basso fra [param world] e ventiquattro punti su due anelli attorno (XZ).
func lowest_point_near(world: Vector3, radius: float) -> Vector3:
	var best := world
	var best_h := terrain_field.height_at(world)
	for k in 12:
		var angle := TAU * k / 12.0
		for r in [radius * 0.5, radius]:
			var p := world + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
			var h := terrain_field.height_at(p)
			if h < best_h:
				best_h = h
				best = p
	return best


func _on_player_sculpted(center: Vector3, radius: float, volume: float, mode: int) -> void:
	if mode != TerrainField.ToolMode.DIG or volume >= 0.0:
		return
	extract_from_veins(center, radius, -volume)


## I rottami nell'area cambiata si riappoggiano al suolo; se il suolo e salito di oltre
## ROLL_RISE_M dalla posa, rotolano al punto piu basso vicino.
func _on_region_changed(aabb: AABB) -> void:
	for scrap in _scraps:
		var p := scrap.global_position
		if not aabb.has_point(Vector3(p.x, aabb.position.y + 0.1, p.z)):
			continue
		var rest: float = _rest_heights.get(scrap, p.y - SCRAP_SIZE)
		var ground := terrain_field.height_at(p)
		if ground - rest > ROLL_RISE_M:
			var to := lowest_point_near(p, 2.4)
			ground = terrain_field.height_at(to)
			scrap.global_position = Vector3(to.x, ground + SCRAP_SIZE, to.z)
			print("PROTOTYPE01_SCRAP_ROLLED")
		else:
			scrap.global_position = Vector3(p.x, ground + SCRAP_SIZE, p.z)
		_rest_heights[scrap] = ground
		scrap.set_meta(&"base_y", scrap.position.y)


static func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
