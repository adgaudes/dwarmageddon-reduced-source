class_name Ram
extends ActiveWeapon
## Ariete (spec D-092, par. 4.5), attiva del kit comune: chi spara carica verso il punto di mira
## (`charge_distance` metri in `charge_seconds`, intoccabile: PlayerCharacter.start_charge). Chi
## sta sul percorso prende `damage` ed e spinto di lato; la coda spiana il terreno verso la base
## un metro e mezzo davanti (un argine basso sul percorso si apre). Bivi: Rincorsa, Scudo
## (intoccabile all'arrivo), Trincea (scava un fossato dietro), Botto (onda all'arrivo). Se la
## carica non puo partire la ricarica non si consuma.

## Spianata (o trincea) ogni tanti metri di carica, raggio, forza e anticipo sul giocatore.
const WRITE_EVERY := 0.8
const WRITE_RADIUS := 1.2
const FLATTEN_STRENGTH := 1.0
const FLATTEN_AHEAD := 1.5
const TRENCH_DEPTH := 0.6
const BLAST_RADIUS := 3.0

var _charging := false
var _hit: Array[Enemy] = []
var _direction := Vector3.ZERO
var _last_write := Vector3.ZERO


func can_trigger() -> bool:
	return super.can_trigger() and shooter.has_method(&"start_charge") and not _charging


func trigger() -> bool:
	if not can_trigger():
		return false
	var at := aim_point()
	var origin := shooter.global_position
	var direction := Vector3(at.x - origin.x, 0.0, at.z - origin.z)
	if direction.length_squared() < 1e-4:
		direction = shooter.facing_direction() if shooter.has_method(&"facing_direction") else Vector3.FORWARD
	direction = direction.normalized()
	if not shooter.start_charge(direction, stat(&"charge_distance"), stat(&"charge_seconds")):
		return false
	cooldown_left = cooldown_total()
	_charging = true
	_hit.clear()
	_direction = direction
	_last_write = origin
	_flatten_ahead(origin)
	_sound(&"fire")
	triggered.emit(at)
	changed.emit()
	return true


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _charging:
		return
	_ram_enemies()
	_write_path()
	if not shooter.is_charging():
		_charging = false
		_arrive()


func _ram_enemies() -> void:
	if director == null:
		return
	var p := shooter.global_position
	var side := _direction.cross(Vector3.UP).normalized()
	for enemy in director.enemies_near(p, stat(&"hit_radius")):
		if enemy.is_dead or _hit.has(enemy):
			continue
		_hit.append(enemy)
		enemy.take_damage(int(stat(&"damage")))
		if _fx_ready(&"hit", 0.08):
			WeaponFx.burst(fx_parent(), enemy.global_position + Vector3(0.0, 0.5, 0.0), WeaponFx.DUST, 8, 5.0, 0.13, true)
		if enemy.self_driven:
			continue
		var offset := Vector3(enemy.global_position.x - p.x, 0.0, enemy.global_position.z - p.z)
		var push := side if offset.dot(side) >= 0.0 else -side
		var speed := stat(&"shove_speed")
		enemy.velocity = Vector3(push.x * speed, enemy.velocity.y, push.z * speed)


func _write_path() -> void:
	if write_queue == null or terrain_field == null:
		return
	var p := shooter.global_position
	if Vector2(p.x - _last_write.x, p.z - _last_write.z).length() < WRITE_EVERY:
		return
	_last_write = p
	if _fx_ready(&"trail", 0.1):
		WeaponFx.dust(fx_parent(), Vector3(p.x, terrain_field.height_at(p), p.z), WeaponFx.EARTH if stat(&"trench") > 0.0 else WeaponFx.DUST, 0.5, 4, 0.0, true)
	if stat(&"trench") > 0.0:
		write_queue.push_level(p, WRITE_RADIUS, terrain_field.base_height_at(p) - TRENCH_DEPTH, 1.0)
	_flatten_ahead(p)


## Spiana davanti alla carica: anche la Trincea, che scava dietro, ha bisogno di passare.
func _flatten_ahead(p: Vector3) -> void:
	if write_queue == null or terrain_field == null:
		return
	var ahead := p + _direction * FLATTEN_AHEAD
	if terrain_field.height_at(ahead) > terrain_field.base_height_at(ahead) + 0.05:
		# Urgente: con la coda piena (anello, pozza) arriverebbe dopo il giocatore.
		write_queue.push_level(ahead, WRITE_RADIUS, terrain_field.base_height_at(ahead), FLATTEN_STRENGTH, true)


func _arrive() -> void:
	_sound(&"hit")
	var p := shooter.global_position
	var ground := Vector3(p.x, terrain_field.height_at(p) if terrain_field != null else p.y, p.z)
	var blasting := int(stat(&"blast")) > 0
	WeaponFx.shockwave(fx_parent(), ground, BLAST_RADIUS if blasting else 1.5, WeaponFx.DUST if not blasting else WeaponFx.SPARK)
	WeaponFx.dust(fx_parent(), ground, WeaponFx.DUST, 0.8, 8)
	var shield := stat(&"shield")
	if shield > 0.0 and shooter.has_method(&"grant_invulnerability"):
		shooter.grant_invulnerability(shield)
	var blast := int(stat(&"blast"))
	if blast > 0 and director != null:
		for enemy in director.enemies_near(shooter.global_position, BLAST_RADIUS):
			if not enemy.is_dead:
				enemy.take_damage(blast)
		director.shove_from(shooter.global_position, BLAST_RADIUS, 7.0)
