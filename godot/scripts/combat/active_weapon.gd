class_name ActiveWeapon
extends Weapon
## Base delle armi attive su tasto (spec D-092, par. 3): ricarica a tempo, punto di mira secondo
## la mira manuale (col mouse il cursore, entro la portata; con lo stick davanti a chi spara, alla
## portata) o automatica (centro del gruppo di nemici piu fitto entro la portata; senza nemici,
## davanti alla portata piena: a meta l'anello del picchetto passava sotto i piedi).

signal triggered(at: Vector3)

## Lato della griglia con cui si contano i gruppi di nemici per la mira automatica.
const CLUSTER_CELL := 2.0

## Coda delle scritture sul terreno condivisa dalle armi (TerrainWriteQueue).
var write_queue: TerrainWriteQueue
var cooldown_left := 0.0
## Moltiplica la ricarica (Miccia corta: 0,9 al primo livello), dal WeaponLoadout.
var cooldown_scale := 1.0


func cooldown_total() -> float:
	return stat(&"cooldown") * cooldown_scale


func can_trigger() -> bool:
	return cooldown_left <= 0.0 and shooter != null and is_inside_tree() and not get_tree().paused


## Usa l'arma se e carica; vero se e partita.
func trigger() -> bool:
	if not can_trigger():
		return false
	cooldown_left = cooldown_total()
	var at := aim_point()
	_fire(at)
	_sound(&"fire")
	triggered.emit(at)
	changed.emit()
	return true


func aim_point() -> Vector3:
	var reach := stat(&"aim_range")
	var origin := shooter.global_position
	if manual_aim and shooter.has_method(&"cursor_ground_point"):
		var cursor: Variant = shooter.cursor_ground_point()
		if cursor != null:
			var offset := Vector3(cursor.x - origin.x, 0.0, cursor.z - origin.z)
			return origin + offset.limit_length(reach)
	if not manual_aim and director != null:
		var cluster: Variant = densest_cluster(origin, reach)
		if cluster != null:
			return cluster
	var forward: Vector3 = shooter.facing_direction() if shooter.has_method(&"facing_direction") else -shooter.global_basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	return origin + forward * reach


## Centro dei nemici della cella di CLUSTER_CELL metri piu affollata entro [param reach], o null.
func densest_cluster(origin: Vector3, reach: float) -> Variant:
	return cluster_center(director, origin, reach)


## Come `densest_cluster`, per le armi che non sono attive (il Lanciarottami).
static func cluster_center(enemy_director: EnemyDirector, origin: Vector3, reach: float) -> Variant:
	var cells: Dictionary[Vector2i, Array] = {}
	for enemy in enemy_director.enemies_near(origin, reach):
		if enemy.is_dead:
			continue
		var key := Vector2i(floori(enemy.global_position.x / CLUSTER_CELL), floori(enemy.global_position.z / CLUSTER_CELL))
		cells.get_or_add(key, []).append(enemy.global_position)
	var best: Array = []
	for key in cells:
		if cells[key].size() > best.size():
			best = cells[key]
	if best.is_empty():
		return null
	var sum := Vector3.ZERO
	for p: Vector3 in best:
		sum += p
	var center := sum / best.size()
	return Vector3(center.x, origin.y, center.z)


func _physics_process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)


func _fire(_at: Vector3) -> void:
	pass
