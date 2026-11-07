class_name Scythe
extends Weapon
## Falce rotante (spec D-092, par. 4.4), automatica dell'Erbacciaia: `blades` falci equidistanti
## girano attorno a chi spara a `orbit_radius`, un giro in `orbit_seconds` (piu veloci di
## `meadow_speed` quando chi spara e sul prato). Chi sta entro BLADE_REACH da una falce prende
## `damage`, al massimo una volta ogni `hit_interval`. Bivi: Falce lunga, Falce affilata,
## Fienagione (dove muore un nemico vicino cresce il prato), Pale da scavo (l'anello delle falci
## rallenta e lascia terra smossa dipinta). Fusa col Roveto diventa la Falciarovi: le falci
## lasciano una scia di rovi.

const BLADE_COLOR := Color(0.78, 0.8, 0.84)
const BLADE_GLOW := Color(0.9, 0.12, 0.6)
const MAX_BLADES := 8
const BLADE_REACH := 0.5
## Fienagione: raggio del ciuffo di prato e margine oltre il giro delle falci.
const HAY_RADIUS := 1.0
const HAY_MARGIN := 1.0
const GRASS_STRENGTH := 0.55
## Pale da scavo: mezza larghezza dell'anello che rallenta, fattore, pittura a scatti.
const FURROW_HALF_WIDTH := 0.4
const FURROW_SLOW := 0.7
const FURROW_HOLD := 0.15
const FURROW_PAINT_EVERY := 0.5
const FURROW_PAINT_MOVE := 1.0
const FURROW_PAINT_POINTS := 8
const FURROW_PAINT_RADIUS := 0.5
## Falciarovi: tratti di scia vivi al massimo.
const MAX_TRAIL := 40
const TRAIL_GROW := 0.3
## Scia delle falci: copie traslucide dietro ogni lama, GHOST_STEP radianti l'una dall'altra.
const GHOSTS := 3
const GHOST_STEP := 0.3

## Prato logico (MeadowMap), dal WeaponLoadout; puo mancare.
var meadow: MeadowMap
var blades := 2
var orbit_radius := 2.2
var orbit_seconds := 1.5
var damage := 1
var hit_interval := 0.5
var meadow_speed := 1.3
var haymaking := false
var furrow := false
var _angle := 0.0
## Colpi recenti: {id nemico: secondi prima del prossimo}.
var _cooldowns: Dictionary = {}
var _bound: EnemyDirector
var _paint_left := 0.0
var _painted_at := Vector3.ZERO
var _painted := false
var _trail: BrambleField
var _trail_id := -1
var _trail_left := 0.0
var _view: MultiMeshInstance3D
var _ghost_view: MultiMeshInstance3D


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.05, 0.18)
	var material := StandardMaterial3D.new()
	material.albedo_color = BLADE_COLOR.linear_to_srgb()
	material.metallic = 0.8
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = BLADE_GLOW.linear_to_srgb()
	material.emission_energy_multiplier = 0.35
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_BLADES
	multimesh.visible_instance_count = 0
	_view = MultiMeshInstance3D.new()
	_view.multimesh = multimesh
	_view.top_level = true
	_view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_view)
	_ghost_view = _make_ghost_view(mesh.size)
	super._ready()


func _apply_stats() -> void:
	blades = clampi(int(stat(&"blades")), 1, MAX_BLADES)
	orbit_radius = stat(&"orbit_radius")
	orbit_seconds = maxf(stat(&"orbit_seconds"), 0.1)
	damage = int(stat(&"damage"))
	hit_interval = stat(&"hit_interval")
	meadow_speed = stat(&"meadow_speed")
	haymaking = stat(&"haymaking") > 0.0
	furrow = stat(&"furrow") > 0.0


## Posizioni delle falci in questo passo.
func blade_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if shooter == null:
		return out
	var center := shooter.global_position
	for i in blades:
		var a := _angle + TAU * i / blades
		out.append(center + Vector3(cos(a), 0.0, sin(a)) * orbit_radius)
	return out


## Rovi della Falciarovi (null prima della prima scia).
func trail() -> BrambleField:
	return _trail


func _physics_process(delta: float) -> void:
	if shooter == null:
		_view.multimesh.visible_instance_count = 0
		_ghost_view.multimesh.visible_instance_count = 0
		return
	_bind_director()
	var center := shooter.global_position
	var speed := meadow_speed if meadow != null and meadow.is_meadow(center) else 1.0
	_angle = fposmod(_angle + TAU * delta / orbit_seconds * speed, TAU)
	for key: int in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			_cooldowns.erase(key)
	var positions := blade_positions()
	if director != null:
		_cut(center, positions)
	if furrow:
		_paint_furrow(center, delta)
	if fusion_id != &"":
		_drop_trail(positions, delta)
	_refresh_view(center, positions)


## Colpi delle falci e, con le Pale da scavo, l'anello che rallenta: una sola ricerca.
func _cut(center: Vector3, positions: Array[Vector3]) -> void:
	var reach := orbit_radius + maxf(BLADE_REACH, FURROW_HALF_WIDTH) + 1.0
	var cut := false
	var clipped := false
	for enemy in director.enemies_near(center, reach):
		if enemy.is_dead:
			continue
		var p := enemy.global_position
		if furrow and absf(Vector2(p.x - center.x, p.z - center.z).length() - orbit_radius) <= FURROW_HALF_WIDTH:
			enemy.slow(FURROW_SLOW, FURROW_HOLD)
		var id := enemy.get_instance_id()
		if _cooldowns.has(id):
			continue
		var limit := BLADE_REACH + enemy.hit_radius_bonus
		for blade in positions:
			if Vector2(p.x - blade.x, p.z - blade.z).length() <= limit:
				_cooldowns[id] = hit_interval
				enemy.take_damage(damage)
				cut = true
				if not clipped and _fx_ready(&"cut", 0.15):
					clipped = true
					WeaponFx.burst(fx_parent(), enemy.global_position + Vector3(0.0, 0.5, 0.0), WeaponFx.LEAF, 8, 4.0, 0.12, true)
				break
	if cut:
		_sound(&"hit")


## Il segnale delle uccisioni segue il direttore (il loadout lo passa dopo `add_child`).
func _bind_director() -> void:
	if director == _bound:
		return
	if _bound != null and is_instance_valid(_bound) and _bound.enemy_killed.is_connected(_on_enemy_killed):
		_bound.enemy_killed.disconnect(_on_enemy_killed)
	_bound = director
	if director != null:
		director.enemy_killed.connect(_on_enemy_killed)


## Fienagione: dove muore un nemico vicino cresce un ciuffo di prato (logico e dipinto).
func _on_enemy_killed(world_position: Vector3, _total: int) -> void:
	if not haymaking or shooter == null:
		return
	var center := shooter.global_position
	if Vector2(world_position.x - center.x, world_position.z - center.z).length() > orbit_radius + HAY_MARGIN:
		return
	if meadow != null:
		meadow.mark(world_position, HAY_RADIUS)
	if terrain_field != null:
		terrain_field.begin_batch()
		terrain_field.tint(world_position, HAY_RADIUS, RuinsDistrict.GRASS_PAINT, GRASS_STRENGTH)
		terrain_field.end_batch()


## Pale da scavo: terra smossa dipinta sull'anello, a scatti e solo se chi spara si e spostato.
func _paint_furrow(center: Vector3, delta: float) -> void:
	_paint_left -= delta
	if _paint_left > 0.0 or terrain_field == null:
		return
	_paint_left = FURROW_PAINT_EVERY
	if _painted and Vector2(center.x - _painted_at.x, center.z - _painted_at.z).length() <= FURROW_PAINT_MOVE:
		return
	_painted = true
	_painted_at = center
	terrain_field.begin_batch()
	for i in FURROW_PAINT_POINTS:
		var a := TAU * i / FURROW_PAINT_POINTS
		terrain_field.paint_layer(center + Vector3(cos(a), 0.0, sin(a)) * orbit_radius, FURROW_PAINT_RADIUS,
			TerrainSurface.LAYER_DUG_SOIL)
	terrain_field.end_batch()


## Falciarovi: ogni `trail_every` ogni falce lascia un tratto di rovi coi valori base del Roveto.
func _drop_trail(positions: Array[Vector3], delta: float) -> void:
	if _trail == null:
		_trail = BrambleField.new()
		_trail.name = "Trail"
		_trail.max_segments = MAX_TRAIL
		_trail.grow_seconds = TRAIL_GROW
		add_child(_trail)
	_trail.director = director
	_trail.terrain_field = terrain_field
	_trail_left -= delta
	if _trail_left > 0.0:
		return
	_trail_left = fusion_stat(&"trail_every")
	var seconds := fusion_stat(&"trail_seconds")
	if not positions.is_empty():
		var p := positions[0]
		var ground := terrain_field.height_at(p) if terrain_field != null else p.y
		_fusion_fx(WeaponFx.burst(fx_parent(), Vector3(p.x, ground + 0.3, p.z), BrambleField.LEAF_COLOR, 5, 2.5, 0.13))
	for p in positions:
		if not _trail.add_segment(_trail_id, p, seconds):
			var first: Array[Vector3] = [p]
			_trail_id = _trail.add_hedge(first, seconds, _bramble_stat(&"slow"), int(_bramble_stat(&"damage")),
				_bramble_stat(&"damage_interval"), int(_bramble_stat(&"hedge_hp")), 0.0)


static func _bramble_stat(key: StringName) -> float:
	return WeaponCatalog.stat(&"bramble", key, 1, {})


func _refresh_view(center: Vector3, positions: Array[Vector3]) -> void:
	var multimesh := _view.multimesh
	multimesh.visible_instance_count = positions.size()
	for i in positions.size():
		multimesh.set_instance_transform(i, _blade_transform(center, positions[i]))
	var ghosts := _ghost_view.multimesh
	ghosts.visible_instance_count = positions.size() * GHOSTS
	for i in positions.size():
		var a := _angle + TAU * i / blades
		for g in range(1, GHOSTS + 1):
			var back := a - GHOST_STEP * g
			var p := center + Vector3(cos(back), 0.0, sin(back)) * orbit_radius
			var n := i * GHOSTS + g - 1
			ghosts.set_instance_transform(n, _blade_transform(center, p))
			ghosts.set_instance_color(n, Color(1.0, 1.0, 1.0, 0.4 * (1.0 - float(g) / (GHOSTS + 1))))


## La lama punta verso l'esterno del giro, un poco inclinata nel verso della corsa.
func _blade_transform(center: Vector3, p: Vector3) -> Transform3D:
	var out := Vector3(p.x - center.x, 0.0, p.z - center.z).normalized()
	var ground := terrain_field.height_at(p) if terrain_field != null else center.y
	var basis := Basis(out, Vector3.UP, out.cross(Vector3.UP)) * Basis(Vector3.RIGHT, 0.3)
	return Transform3D(basis, Vector3(p.x, ground + 0.45, p.z))


func _make_ghost_view(size: Vector3) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, size.y * 0.5, size.z * 1.6)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = BLADE_GLOW.linear_to_srgb()
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_BLADES * GHOSTS
	multimesh.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.multimesh = multimesh
	view.top_level = true
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	return view
