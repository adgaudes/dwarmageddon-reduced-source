class_name Welder
extends Weapon
## Saldatrice (spec D-092, par. 4.3), automatica del Meccanico: ogni `fire_interval` un arco dal
## giocatore al nemico piu vicino entro `weapon_range`, che salta al piu vicino non ancora colpito
## entro `jump_range` (`ditch_jump_range` se parte da un fossato) fino a `jumps` bersagli, `damage`
## ciascuno. Col capofila della carovana entro `lead_range` parte un arco uguale anche da
## lui; in una scarica nessuno e colpito due volte. Bivi: Arco doppio (la seconda catena parte dal
## piu vicino non ancora colpito), Punto di fusione (3 danni, un bersaglio), Carica statica (i
## colpiti feriscono chi toccano), Filo teso (fra giocatore e capofila). Fusa con la Calamita
## diventa la Bobina di Tesla: un campo attorno a giocatore e capofila che attira piano e scarica
## archi su chi c'e.
## Gli archi sono segmenti spezzati di una sola MultiMesh: nessun nodo per colpo.

const ARC_COLOR := Color(0.2, 0.95, 0.9)
const ARC_SHOW_SECONDS := 0.12
const ARC_THICKNESS := 0.05
## Ogni tratto d'arco e spezzato in ARC_PIECES pezzi, con le giunture spostate fino a ARC_JITTER.
const ARC_PIECES := 3
const ARC_JITTER := 0.25
const MAX_SEGMENTS := 192
## Gli archi partono un po' sopra l'origine di chi li lancia.
const SOURCE_LIFT := 0.5
## Un nemico sta in un fossato sotto questo scostamento dalla base.
const DITCH_DEPTH := -0.5
const STATIC_TICK := 0.5
const STATIC_REACH := 0.8
const STATIC_DAMAGE := 1
const WIRE_TICK := 0.5
const WIRE_REACH := 0.5
const WIRE_DAMAGE := 1
const BLOCKED_RETRY := 0.1
## Nell'ultimo metro verso il centro la deriva cala: chi e arrivato non trema attorno al punto.
const PULL_EASE := 1.0

## Carovana (dal WeaponLoadout, dopo `add_child`): archi, filo e campo partono dal capofila;
## puo mancare, e allora niente arco ne filo.
var caravan: Caravan
var fire_interval := 1.2
var weapon_range := 6.0
var jumps := 3
var jump_range := 2.5
var ditch_jump_range := 4.0
var damage := 1
var lead_range := 8.0
var arcs := 1
var static_seconds := 0.0
var wire := false
var _cooldown := 0.3
var _wire_left := WIRE_TICK
var _tesla_left := 0.0
## Colpiti ancora elettrici (Carica statica): {enemy, left, tick}.
var _static: Array[Dictionary] = []
## Archi visibili: {points: PackedVector3Array, left}.
var _arcs: Array[Dictionary] = []
var _wire_drawn := false
var _dirty := false
var _rng := RandomNumberGenerator.new()
var _multimesh: MultiMesh


func _ready() -> void:
	_rng.seed = 23
	var mesh := BoxMesh.new()
	mesh.size = Vector3(ARC_THICKNESS, ARC_THICKNESS, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = ARC_COLOR.linear_to_srgb()
	material.emission_enabled = true
	material.emission = ARC_COLOR.linear_to_srgb()
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = mesh
	_multimesh.instance_count = MAX_SEGMENTS
	_multimesh.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.multimesh = _multimesh
	view.top_level = true
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	super._ready()


func _apply_stats() -> void:
	fire_interval = stat(&"fire_interval")
	weapon_range = stat(&"weapon_range")
	jumps = maxi(int(stat(&"jumps")), 1)
	jump_range = stat(&"jump_range")
	ditch_jump_range = stat(&"ditch_jump_range")
	damage = int(stat(&"damage"))
	lead_range = stat(&"lead_range")
	arcs = maxi(int(stat(&"arcs")), 1)
	static_seconds = stat(&"static")
	wire = stat(&"wire") > 0.0


## Segmenti d'arco disegnati ora (per i test).
func drawn_segments() -> int:
	return _multimesh.visible_instance_count


func _physics_process(delta: float) -> void:
	_tick_arcs(delta)
	if shooter != null and director != null:
		var mate := _lead_near()
		if not _static.is_empty():
			_tick_static(delta)
		_tick_wire(delta, mate)
		if fusion_id != &"":
			_tick_tesla(delta)
		_cooldown -= delta
		if _cooldown <= 0.0:
			_cooldown = fire_interval if not discharge().is_empty() else BLOCKED_RETRY
	if _dirty or _wire_drawn:
		_redraw()


## Una scarica: le catene dal giocatore e, se e vicino, dal capofila. Restituisce i colpiti.
func discharge() -> Array[Enemy]:
	var hit: Array[Enemy] = []
	var sources: Array[Node3D] = [shooter]
	var mate := _lead_near()
	if mate != null:
		sources.append(mate)
	for source in sources:
		for i in arcs:
			_chain(source.global_position, hit)
	if not hit.is_empty():
		_sound(&"fire")
	return hit


func _chain(origin: Vector3, hit: Array[Enemy]) -> void:
	var current := _nearest(origin, weapon_range, hit)
	if current == null:
		return
	var points := PackedVector3Array([origin + Vector3.UP * SOURCE_LIFT])
	for count in jumps:
		hit.append(current)
		var at := current.global_position
		points.append(at)
		var reach := jump_range
		if terrain_field != null and terrain_field.delta_at(at) < DITCH_DEPTH:
			reach = ditch_jump_range
		_strike(current, damage)
		WeaponFx.sparks(fx_parent(), at + Vector3.UP * SOURCE_LIFT, ARC_COLOR, 8, 5.0)
		if count + 1 >= jumps:
			break
		current = _nearest(at, reach, hit)
		if current == null:
			break
	_add_arc(points)


func _strike(enemy: Enemy, amount: int) -> void:
	enemy.take_damage(amount)
	if static_seconds > 0.0 and not enemy.is_dead:
		for entry in _static:
			if entry.enemy == enemy:
				entry.left = static_seconds
				return
		_static.append({enemy = enemy, left = static_seconds, tick = STATIC_TICK})


## Nemico vivo piu vicino a [param origin] entro [param reach], fuori da [param skip].
func _nearest(origin: Vector3, reach: float, skip: Array[Enemy]) -> Enemy:
	var best: Enemy = null
	var best_distance := INF
	for enemy in director.enemies_near(origin, reach):
		if enemy.is_dead or skip.has(enemy):
			continue
		var d := _planar(enemy.global_position - origin).length()
		if d < best_distance:
			best_distance = d
			best = enemy
	return best


## Il capofila della carovana se c'e ed e entro `lead_range` da chi spara, altrimenti null.
func _lead_near() -> Node3D:
	var lead := _lead()
	if lead == null or _planar(lead.global_position - shooter.global_position).length() > lead_range:
		return null
	return lead


## Il capofila della carovana se c'e ed e nell'albero, altrimenti null.
func _lead() -> Node3D:
	if not is_instance_valid(caravan) or not caravan.is_inside_tree():
		return null
	var lead := caravan.lead()
	return lead if is_instance_valid(lead) and lead.is_inside_tree() else null


## Carica statica: ogni STATIC_TICK chi e ancora elettrico ferisce i vivi che tocca.
func _tick_static(delta: float) -> void:
	for k in range(_static.size() - 1, -1, -1):
		var entry: Dictionary = _static[k]
		entry.left -= delta
		if not is_instance_valid(entry.enemy) or entry.enemy.is_dead or entry.left <= 0.0:
			_static.remove_at(k)
			continue
		entry.tick -= delta
		if entry.tick > 0.0:
			continue
		entry.tick += STATIC_TICK
		var source: Enemy = entry.enemy
		for other in director.enemies_near(source.global_position, STATIC_REACH):
			if other != source and not other.is_dead:
				other.take_damage(STATIC_DAMAGE)


## Filo teso: col capofila vicino, ogni WIRE_TICK ferisce chi sta sul segmento fra i due.
func _tick_wire(delta: float, mate: Node3D) -> void:
	var on := wire and mate != null
	if on != _wire_drawn:
		_dirty = true
	_wire_drawn = on
	if not on:
		_wire_left = WIRE_TICK
		return
	_wire_left -= delta
	if _wire_left > 0.0:
		return
	_wire_left += WIRE_TICK
	var a := shooter.global_position
	var b := mate.global_position
	var half := _planar(b - a).length() * 0.5
	for enemy in director.enemies_near((a + b) * 0.5, half + WIRE_REACH):
		if not enemy.is_dead and _segment_distance(enemy.global_position, a, b) <= WIRE_REACH:
			enemy.take_damage(WIRE_DAMAGE)


## Bobina di Tesla: campi attorno a giocatore e capofila che attirano; ogni `arc_interval` un
## arco senza salti su un nemico a caso dentro uno dei due.
func _tick_tesla(delta: float) -> void:
	var radius := fusion_stat(&"field_radius")
	var speed := fusion_stat(&"field_pull")
	var centers: Array[Vector3] = [shooter.global_position]
	var lead := _lead()
	if lead != null:
		centers.append(lead.global_position)
	_tesla_left -= delta
	var arcing := _tesla_left <= 0.0
	var inside: Array[Enemy] = []
	var origins: Array[Vector3] = []
	for center in centers:
		for enemy in director.enemies_near(center, radius):
			if enemy.is_dead:
				continue
			pull_toward(enemy, center, speed)
			if arcing and not inside.has(enemy):
				inside.append(enemy)
				origins.append(center)
	if not arcing or inside.is_empty():
		_tesla_left = maxf(_tesla_left, 0.0)
		return
	_tesla_left = fusion_stat(&"arc_interval")
	var pick := _rng.randi_range(0, inside.size() - 1)
	var target := inside[pick]
	_add_arc(PackedVector3Array([origins[pick] + Vector3.UP * SOURCE_LIFT, target.global_position]))
	_fusion_fx(WeaponFx.sparks(fx_parent(), target.global_position + Vector3.UP * SOURCE_LIFT, ARC_COLOR, 8, 4.5))
	_strike(target, damage)


## Deriva verso [param center] a [param speed] m/s nel piano, piu piano nell'ultimo metro. Si
## somma alle altre del passo senza superare la piu forte: niente accumulo se il direttore non la
## consuma. I boss (`self_driven`) non si tirano.
static func pull_toward(enemy: Enemy, center: Vector3, speed: float) -> void:
	if enemy.self_driven:
		return
	var to := Vector3(center.x - enemy.global_position.x, 0.0, center.z - enemy.global_position.z)
	var distance := to.length()
	if distance < 0.05:
		return
	var pull := to / distance * speed * minf(distance / PULL_EASE, 1.0)
	enemy.drift = (enemy.drift + pull).limit_length(maxf(enemy.drift.length(), pull.length()))


func _add_arc(points: PackedVector3Array) -> void:
	var jagged := PackedVector3Array([points[0]])
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		for piece in range(1, ARC_PIECES):
			var jitter := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1.0, 1.0)) * ARC_JITTER
			jagged.append(a.lerp(b, float(piece) / ARC_PIECES) + jitter)
		jagged.append(b)
	_arcs.append({points = jagged, left = ARC_SHOW_SECONDS})
	_dirty = true


func _tick_arcs(delta: float) -> void:
	for k in range(_arcs.size() - 1, -1, -1):
		_arcs[k].left -= delta
		if _arcs[k].left <= 0.0:
			_arcs.remove_at(k)
			_dirty = true


func _redraw() -> void:
	_dirty = false
	var n := 0
	for arc in _arcs:
		var points: PackedVector3Array = arc.points
		for i in range(1, points.size()):
			n = _put_segment(n, points[i - 1], points[i])
	var lead := _lead()
	if _wire_drawn and lead != null:
		var lift := Vector3.UP * SOURCE_LIFT
		n = _put_segment(n, shooter.global_position + lift, lead.global_position + lift)
	_multimesh.visible_instance_count = n


func _put_segment(n: int, a: Vector3, b: Vector3) -> int:
	var along := b - a
	var length := along.length()
	if n >= MAX_SEGMENTS or length < 0.01:
		return n
	var dir := along / length
	var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	var basis := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1.0, 1.0, length))
	_multimesh.set_instance_transform(n, Transform3D(basis, (a + b) * 0.5))
	return n + 1


static func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var p2 := Vector2(p.x, p.z)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ab := b2 - a2
	var t := clampf((p2 - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p2.distance_to(a2 + ab * t)


static func _planar(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
