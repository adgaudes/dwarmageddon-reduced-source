class_name TrainEvent
extends WorldEvent
## Il treno della ferrovia (D-066, D-087, docs/RAILWAY_LEVEL_SPEC.md sezione 3): quando lo
## programma ArenaRun (D-097: istanti casuali) un convoglio attraversa tutta l'arena lungo uno dei due binari e
## **riporta la fascia alla base** (7,2 m attorno a z = 0): argini, barricate e vagoni
## spariscono senza lasciare rottami (le vene dei vagoni si azzerano), i solchi si
## riempiono, i rottami a terra e i lampioni spariscono. Chi sta sulla fascia viene travolto:
## i rottamatori muoiono (e contano come abbattuti dal giocatore), il giocatore
## subisce danno e viene spinto fuori, le macchine della carovana si guastano e vengono spinte
## fuori (una fusa perde un modulo, scagliato oltre il bordo: D-093, piano C), il boss
## subisce `boss_damage` e viene spinto.
##
## Non ha un passo fisico proprio: `ArenaRun` lo fa avanzare con il tempo di
## livello, cosi la pausa e la fine del livello lo fermano da sole.
## Il treno arriva alternativamente da est e da ovest; il binario e a caso (`rng`).

signal train_warned(direction: Vector3, seconds: float)
signal train_passing(direction: Vector3)
## Qualcosa e stato travolto: "terrain", "wagon", "enemy", "player", "companion" (una macchina
## della carovana), "boss", "lamp", "scrap".
signal train_hit(what: StringName)
signal train_passed(passes: int)

enum State { IDLE, WARNING, PASSING }

const CARRIAGE_MODEL := preload("res://assets/models/train_carriage.glb")
## Lunghezza di un vagone (modello) e spazio fra due vagoni.
const CARRIAGE_LENGTH := 13.0
const CARRIAGE_GAP := 0.7
const LOCOMOTIVE_PAINT := Color(0.12, 0.11, 0.1)
const CARRIAGE_PAINTS: Array[Color] = [
	Color(0.62, 0.20, 0.14), Color(0.88, 0.68, 0.14), Color(0.30, 0.36, 0.52), Color(0.72, 0.32, 0.12),
]
## Chi viene spinto fuori finisce a questa distanza oltre il bordo della fascia.
const PUSH_MARGIN := 0.8
## Passi di PUSH_STEP_M provati oltre il bordo per far atterrare chi e spinto fuori (F-01).
const PUSH_LANDING_STEPS := 6
const PUSH_STEP_M := 1.2
## Terra spianata, per i frammenti: una zolla ogni DEBRIS_PER_M3, al piu DEBRIS_PER_STEP a passo.
const EARTH_COLOR := Color(0.44, 0.33, 0.21)
const DEBRIS_PER_M3 := 2.0
const DEBRIS_PER_STEP := 4
const DIRECTION_NAMES: Dictionary[int, String] = {-1: "EST", 1: "OVEST"}

@export var terrain_field: TerrainField
@export var district: RailwayDistrict
@export var player: PlayerCharacter
@export var caravan: Caravan
@export var director: EnemyDirector
@export var lamp_field: LampField
@export var scrap_field: ScrapField
@export var hud: RunHud
## Casse sepolte nei vagoni (D-092): il treno le spazza via come le vene, senza aprirle.
var buried_caches: BuriedCaches
## Relitti sepolti (D-093): come le casse, spazzati via senza aprirsi.
var machine_wrecks: MachineWrecks
## Moduli staccati a terra (D-093, piano C): spazzati via come i relitti sepolti.
var module_relics: ModuleRelics
## Moduli che perde una macchina fusa investita e quanto lontano oltre il bordo della fascia
## cadono (`CaravanTuning.train_detach_count`, `train_throw_min/max`; li copia ArenaRun).
var module_detach_count := 1
var throw_min := 6.0
var throw_max := 8.0

var warning_seconds := 10.0
var speed := 18.0
var carriages := 5
var player_damage := 2
var boss_damage := 30
## Il boss in campo, se c'e (lo imposta ArenaRun).
var boss: Enemy
var rng := RandomNumberGenerator.new()

var state := State.IDLE
## +1: il treno va verso +X (viene da ovest); -1: verso -X (viene da est).
var heading := -1
var track_z := 0.0
var passes := 0
## Terra spostata (m3), vagoni azzerati, nemici travolti e colpi al giocatore nell'ultimo passaggio.
var volume_flattened := 0.0
var wagons_swept := 0
var enemies_hit := 0
var player_hits := 0
var _train: Node3D
## Posizione X del muso e ultimo X gia spazzato.
var _head_x := 0.0
var _swept_x := 0.0
var _debris_budget := 0.0
var _hit: Dictionary[Node, bool] = {}
var _first_warning := true


func event_kind() -> StringName:
	return &"train"


func is_enabled() -> bool:
	return district != null and terrain_field != null


func is_passing() -> bool:
	return state == State.PASSING


func direction_name() -> String:
	return DIRECTION_NAMES[heading]


## Verso del mondo da cui arriva il treno (per la freccia dell'HUD).
func arrival_direction() -> Vector3:
	return Vector3(-heading, 0.0, 0.0)


## Lunghezza del convoglio, locomotiva compresa.
func train_length() -> float:
	return (carriages + 1) * (CARRIAGE_LENGTH + CARRIAGE_GAP)


## Posizione X del muso; la coda e `train_length()` dietro.
func head_x() -> float:
	return _head_x


## Un passo, dal tempo di livello.
func advance(elapsed: float, delta: float) -> void:
	if not is_enabled():
		return
	match state:
		State.IDLE:
			if elapsed >= next_at - warning_seconds:
				_start_warning()
			else:
				return
			_tick_warning(elapsed)
		State.WARNING:
			_tick_warning(elapsed)
		State.PASSING:
			_tick_passing(delta)


func _start_warning() -> void:
	state = State.WARNING
	# Il primo viene da est (heading -1); poi si alterna.
	if _first_warning:
		_first_warning = false
	else:
		heading = -heading
	track_z = RailwayDistrict.TRACK_Z[rng.randi_range(0, RailwayDistrict.TRACK_Z.size() - 1)]
	print("PROTOTYPE01_TRAIN_WARNING from=%s track_z=%.1f at=%.1f" % [direction_name(), track_z, next_at])
	train_warned.emit(arrival_direction(), warning_seconds)


func _tick_warning(elapsed: float) -> void:
	var left := next_at - elapsed
	if hud != null:
		hud.set_event_warning("TRENO DA %s" % direction_name(), arrival_direction(), left, RunHud.TRAIN_COLOR)
	if left <= 0.0:
		_start_passing()


func _start_passing() -> void:
	state = State.PASSING
	volume_flattened = 0.0
	wagons_swept = 0
	enemies_hit = 0
	player_hits = 0
	_debris_budget = 0.0
	_hit.clear()
	# Parte oltre il portale, tutto fuori dall'arena.
	_head_x = -heading * (district.half_x() + RailwayDistrict.PORTAL_DEPTH + 4.0)
	_swept_x = _head_x
	_build_train()
	if hud != null:
		hud.clear_event_warning()
	print("PROTOTYPE01_TRAIN_PASS from=%s track_z=%.1f" % [direction_name(), track_z])
	train_passing.emit(arrival_direction())


func _tick_passing(delta: float) -> void:
	_head_x += heading * speed * delta
	_place_train()
	_sweep_band()
	_sweep_actors()
	var tail_x := _head_x - heading * train_length()
	if heading * tail_x > district.half_x() + RailwayDistrict.PORTAL_DEPTH + 4.0:
		_finish_pass()


func _finish_pass() -> void:
	state = State.IDLE
	passes += 1
	_advance_schedule()
	if _train != null:
		_train.queue_free()
		_train = null
	print("PROTOTYPE01_TRAIN_PASSED passes=%d volume=%.1f wagons=%d enemies=%d player_hits=%d" % [passes, volume_flattened, wagons_swept, enemies_hit, player_hits])
	train_passed.emit(passes)


# --- Effetti sul mondo ----------------------------------------------------------------

## Il tratto percorso dal muso in questo passo torna alla base per tutta la larghezza
## della fascia: argini, barricate e vagoni spariscono senza rottami (a differenza del
## Demolitore), i solchi si riempiono e cio che c'e sopra sparisce.
func _sweep_band() -> void:
	var lo := minf(_swept_x, _head_x) - 0.6
	var hi := maxf(_swept_x, _head_x) + 0.6
	_swept_x = _head_x
	lo = maxf(lo, -district.half_x())
	hi = minf(hi, district.half_x())
	if hi <= lo:
		return
	var center := Vector3((lo + hi) * 0.5, 0.0, 0.0)
	var half := Vector2((hi - lo) * 0.5, RailwayDistrict.TRACK_HALF_WIDTH)
	# Prima di spianare: col suolo alla base casse e relitti si aprirebbero da soli. reset_to_base
	# arriva al vertice della griglia oltre il bordo e la quota di un punto viene dai vertici
	# entro una cella: si scarta con due celle di margine, o uno appena fuori si aprirebbe.
	var buried_rect := Rect2(lo, -half.y, hi - lo, half.y * 2.0).grow(TerrainField.SPACING * 2.0)
	if buried_caches != null:
		buried_caches.discard_in_rect(buried_rect)
	if machine_wrecks != null:
		machine_wrecks.discard_in_rect(buried_rect)
	if module_relics != null:
		module_relics.discard_in_rect(buried_rect)
	var volume := terrain_field.reset_to_base(center, half)
	if volume > 0.01:
		# Il tratto spianato torna massicciata di ghiaia (i cumuli dei vagoni erano ruggine).
		terrain_field.paint_layer_rect(center, half, TerrainSurface.LAYER_GRAVEL)
		terrain_field.tint_rect(center, half, RailwayDistrict.BALLAST_TINT, 0.8)
		volume_flattened += volume
		_debris_budget += volume
		var bursts := 0
		while _debris_budget >= DEBRIS_PER_M3 and bursts < DEBRIS_PER_STEP:
			_debris_budget -= DEBRIS_PER_M3
			bursts += 1
			var at := Vector3(rng.randf_range(lo, hi), 0.0, rng.randf_range(-half.y, half.y))
			DebrisBurst.spawn(get_parent(), at + Vector3(0.0, 0.8, 0.0), EARTH_COLOR, 12, 5.0, 0.2)
		train_hit.emit(&"terrain")
	var rect := Rect2(lo, -half.y, hi - lo, half.y * 2.0)
	if scrap_field != null:
		var swept := scrap_field.exhaust_veins_in_rect(rect)
		if swept > 0:
			wagons_swept += swept
			train_hit.emit(&"wagon")
		if scrap_field.take_in_rect(rect, 16) > 0:
			train_hit.emit(&"scrap")
	if lamp_field != null and lamp_field.knock_down_in_rect(rect) > 0:
		train_hit.emit(&"lamp")


## Chi sta sulla fascia fra coda e muso viene travolto, una volta per passaggio.
func _sweep_actors() -> void:
	var tail_x := _head_x - heading * train_length()
	if player != null and _covers(player.global_position, tail_x) and not _hit.has(player):
		_hit[player] = true
		player_hits += 1
		player.take_damage(player_damage)
		_push_out(player)
		train_hit.emit(&"player")
		print("PROTOTYPE01_TRAIN_HIT what=player")
	if caravan != null:
		for machine in caravan.machines:
			if _covers(machine.global_position, tail_x) and not _hit.has(machine):
				_hit[machine] = true
				_throw_modules(machine)
				machine.break_down()
				print("PROTOTYPE01_MACHINE_BROKEN_BY_TRAIN module=%s" % machine.primary_module_id())
				_push_out(machine)
				train_hit.emit(&"companion")
	if director == null:
		return
	for enemy in director.enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.is_dead or _hit.has(enemy) or not _covers(enemy.global_position, tail_x):
			continue
		_hit[enemy] = true
		if enemy == boss or enemy.self_driven:
			enemy.take_damage(boss_damage)
			if not enemy.is_dead:
				_push_out(enemy)
			train_hit.emit(&"boss")
			print("PROTOTYPE01_TRAIN_HIT what=boss damage=%d" % boss_damage)
		else:
			enemies_hit += 1
			enemy.take_damage(enemy.health)
			train_hit.emit(&"enemy")


func _covers(at: Vector3, tail_x: float) -> bool:
	if not RailwayDistrict.is_on_tracks(Vector2(at.x, at.z)):
		return false
	return minf(_head_x, tail_x) - 0.5 <= at.x and at.x <= maxf(_head_x, tail_x) + 0.5


## Una macchina fusa investita perde `module_detach_count` moduli (mai sotto uno), scagliati alla
## sua x oltre il bordo della fascia, fra `throw_min` e `throw_max` m, dal lato in cui `_push_out`
## la spingera; il relitto poggia al suolo (`ModuleRelics.drop`).
func _throw_modules(machine: Machine) -> void:
	var at := machine.global_position
	var side := 1.0 if at.z >= 0.0 else -1.0
	var reach := district.half_z() - 1.0
	for i in module_detach_count:
		var module_id := caravan.detach_random(machine, rng, &"train")
		if module_id == &"":
			return
		var z := side * minf(RailwayDistrict.TRACK_HALF_WIDTH + rng.randf_range(throw_min, throw_max), reach)
		if module_relics != null:
			module_relics.drop(module_id, Vector3(at.x, 0.0, z))


## Spinto fuori dalla fascia dal lato dove gia pende (a z = 0 verso sud, dove sta la camera),
## sul primo punto calpestabile (niente argini, niente pendii ripidi) allontanandosi dal
## bordo (F-01); poi sull'altro lato; se tutto e murato resta il bordo della fascia.
func _push_out(body: Node3D) -> void:
	var at := body.global_position
	var lift := clampf(at.y - terrain_field.height_at(at), 0.3, 1.5)
	var side := 1.0 if at.z >= 0.0 else -1.0
	var edge := RailwayDistrict.TRACK_HALF_WIDTH + PUSH_MARGIN
	var chosen := Vector3(at.x, 0.0, side * edge)
	var found := false
	for candidate: float in [side, -side]:
		for step in PUSH_LANDING_STEPS:
			var probe := Vector3(at.x, 0.0, candidate * (edge + step * PUSH_STEP_M))
			if absf(probe.z) > district.half_z() - 1.0:
				break
			if terrain_field.delta_at(probe) < 0.5 and terrain_field.slope_at(probe) <= terrain_field.tuning.max_grade:
				chosen = probe
				found = true
				break
		if found:
			break
	chosen.y = terrain_field.height_at(chosen) + lift
	body.global_position = chosen
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	body.reset_physics_interpolation()


# --- Convoglio visivo ----------------------------------------------------------------

func _build_train() -> void:
	if _train != null:
		_train.queue_free()
	_train = Node3D.new()
	_train.name = "Train"
	add_child(_train)
	for i in carriages + 1:
		var paint := LOCOMOTIVE_PAINT if i == 0 else CARRIAGE_PAINTS[(i - 1) % CARRIAGE_PAINTS.size()]
		var carriage: Node3D = district.spawn_model(CARRIAGE_MODEL, _train, Transform3D.IDENTITY,
			{&"tint": paint, &"rust": 0.25 if i == 0 else 0.5, &"overgrowth": 0.0})
		carriage.name = "Locomotive" if i == 0 else "Carriage%d" % i
		if i == 0:
			var stack := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.35
			mesh.bottom_radius = 0.45
			mesh.height = 1.4
			stack.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.08, 0.08, 0.08)
			stack.material_override = material
			stack.position = Vector3(0.0, 3.9, -CARRIAGE_LENGTH * 0.35)
			carriage.add_child(stack)
	_place_train()


## Il modello del vagone e lungo l'asse Z locale: imbardata di 90 gradi per correre lungo X.
func _place_train() -> void:
	if _train == null:
		return
	var pitch := CARRIAGE_LENGTH + CARRIAGE_GAP
	for i in _train.get_child_count():
		var carriage := _train.get_child(i) as Node3D
		var center_x := _head_x - heading * (pitch * i + CARRIAGE_LENGTH * 0.5)
		carriage.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * heading), Vector3(center_x, 0.0, track_z))
