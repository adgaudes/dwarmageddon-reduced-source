class_name ClassPerks
extends Node
## Carte dei mazzi di classe che non sono armi (spec D-092, par. 5): Argini rinforzati, Getto
## rapido, Miccia corta, Reazione a catena, Motore truccato, Saldatura al volo, Erba alta,
## Cespuglio medicinale, Semi in tasca. ArenaRun passa qui le carte che `handles` riconosce;
## ogni `apply` imposta l'effetto al livello dato (si puo richiamare con lo stesso livello).
## Valori in UpgradeCatalog (`values`).

const IDS: Array[StringName] = [
	&"reinforced_banks", &"quick_cast", &"short_fuse", &"chain_reaction", &"tuned_engine",
	&"field_weld", &"tall_grass", &"healing_bush", &"pocket_seeds",
]
## Reazione a catena: esplosioni al massimo per passo, cosi una fila di morti non fa valanga.
const CHAIN_PER_STEP := 3
## Quota sotto la base oltre la quale un nemico e "dentro un cratere".
const CRATER_DEPTH := -0.3
const ENGINE_HIT_EVERY := 0.5
const ENGINE_HIT_RADIUS := 0.9
## Velocita oltre la quale una macchina della carovana travolge.
const ENGINE_MIN_SPEED := 1.0
## Semi in tasca: la pennellata arriva a ogni passo, la tinta (mappe di Terrain3D) non oltre questa cadenza.
const SEED_EVERY := 0.25

var director: EnemyDirector
var player: Node3D
var caravan: Caravan
var loadout: WeaponLoadout
var terrain_field: TerrainField
var meadow: MeadowMap
var levels: Dictionary[StringName, int] = {}
var _chain_left := CHAIN_PER_STEP
var _engine_left := 0.0
var _weld_time := 0.0
var _bush_time := 0.0
## Olio buono (Officina): frazione di velocita in piu delle macchine, sotto Motore truccato.
var _oil := 0.0
var _engine_level := 0
var _seed_left := 0.0
## Valori letti in `apply` (UpgradeCatalog.value ricostruisce il catalogo: non a ogni passo).
var _engine_damage := 1
var _weld_range := 4.0
var _weld_every := 45.0
var _bush_every := 60.0
var _chain_damage := 1
var _chain_radius := 1.5


static func handles(id: StringName) -> bool:
	return IDS.has(id)


func apply(id: StringName, level: int) -> void:
	levels[id] = level
	match id:
		&"reinforced_banks":
			if director != null:
				director.gnaw_scale = 1.0 / maxf(1.0 - _percent(id) * level, 0.1)
		&"quick_cast":
			if player != null and &"raise_cost_scale" in player:
				player.set(&"raise_cost_scale", maxf(1.0 - _percent(id) * level, 0.1))
		&"short_fuse":
			if loadout != null:
				loadout.set_active_cooldown_scale(maxf(1.0 - _percent(id) * level, 0.1))
		&"chain_reaction":
			_chain_damage = int(UpgradeCatalog.value(id, &"damage", 1.0))
			_chain_radius = UpgradeCatalog.value(id, &"radius", 1.5)
			if director != null and not director.enemy_killed.is_connected(_on_enemy_killed):
				director.enemy_killed.connect(_on_enemy_killed)
		&"tuned_engine":
			_engine_damage = int(UpgradeCatalog.value(id, &"damage", 1.0))
			_engine_level = level
			_tune_speed()
		&"field_weld":
			_weld_range = UpgradeCatalog.value(id, &"range", 4.0)
			_weld_every = UpgradeCatalog.value(id, &"seconds", 45.0)
		&"healing_bush":
			_bush_every = UpgradeCatalog.value(id, &"seconds" if level < 2 else &"seconds_level_2", 60.0)
		&"tall_grass":
			if director != null:
				director.meadow_slow = _percent(id) * level
		&"pocket_seeds":
			if terrain_field != null and not terrain_field.player_sculpted.is_connected(_on_player_sculpted):
				terrain_field.player_sculpted.connect(_on_player_sculpted)


func level_of(id: StringName) -> int:
	return levels.get(id, 0)


func _percent(id: StringName) -> float:
	return UpgradeCatalog.value(id, &"percent") / 100.0


func _physics_process(delta: float) -> void:
	_chain_left = CHAIN_PER_STEP
	_seed_left -= delta
	if level_of(&"tuned_engine") > 0:
		_tick_engine(delta)
	if level_of(&"field_weld") > 0:
		_tick_weld(delta)
	if level_of(&"healing_bush") > 0:
		_tick_bush(delta)


## Olio buono (Officina): le macchine vanno [param fraction] piu veloci (0,15 = +15%).
func boost_machine_speed(fraction: float) -> void:
	_oil = fraction
	_tune_speed()


## Velocita massima delle macchine con Olio buono e Motore truccato: un fattore della carovana,
## che le macchine leggono a ogni passo (la taratura condivisa non si tocca).
func _tune_speed() -> void:
	if caravan == null:
		return
	var bonus := UpgradeCatalog.value(&"tuned_engine", &"speed_percent") / 100.0
	caravan.speed_scale = (1.0 + _oil) * (1.0 + bonus * _engine_level)


## Motore truccato: ogni macchina non guasta in moto travolge i rottamatori che tocca.
func _tick_engine(delta: float) -> void:
	_engine_left -= delta
	if _engine_left > 0.0 or caravan == null or director == null:
		return
	_engine_left = ENGINE_HIT_EVERY
	for machine in caravan.machines:
		if machine.is_broken() or Vector2(machine.velocity.x, machine.velocity.z).length() < ENGINE_MIN_SPEED:
			continue
		for enemy in director.enemies_near(machine.global_position, ENGINE_HIT_RADIUS):
			if not enemy.is_dead and not enemy.self_driven:
				enemy.take_damage(_engine_damage)


## Saldatura al volo: il tempo conta solo con una macchina non guasta vicina.
func _tick_weld(delta: float) -> void:
	if caravan == null or player == null or not _machine_within(_weld_range):
		return
	_weld_time += delta
	if _weld_time >= _weld_every:
		_weld_time = 0.0
		_heal()


## Cespuglio medicinale: il tempo conta solo stando sul prato.
func _tick_bush(delta: float) -> void:
	if meadow == null or player == null or not meadow.is_meadow(player.global_position):
		return
	_bush_time += delta
	if _bush_time >= _bush_every:
		_bush_time = 0.0
		_heal()


func _heal() -> void:
	if player != null and player.has_method(&"heal"):
		player.heal(1)
		print("PROTOTYPE01_PERK_HEAL")


## Reazione a catena: un nemico ucciso dentro un cratere esplode.
func _on_enemy_killed(world_position: Vector3, _total: int) -> void:
	if terrain_field == null or _chain_left <= 0 or terrain_field.delta_at(world_position) >= CRATER_DEPTH:
		return
	_chain_left -= 1
	for enemy in director.enemies_near(world_position, _chain_radius):
		if not enemy.is_dead:
			enemy.take_damage(_chain_damage)
	print("PROTOTYPE01_PERK_CHAIN x=%.1f z=%.1f" % [world_position.x, world_position.z])


## Semi in tasca: gli argini alzati diventano prato (anche sopra la base).
func _on_player_sculpted(center: Vector3, radius: float, volume: float, mode: int) -> void:
	if mode != TerrainField.ToolMode.RAISE or volume <= 0.0 or meadow == null or _seed_left > 0.0:
		return
	_seed_left = SEED_EVERY
	meadow.mark(center, radius, true)
	terrain_field.tint(center, radius, RuinsDistrict.GRASS_PAINT, 0.4)


## Una macchina non guasta della carovana entro [param distance] dal giocatore?
func _machine_within(distance: float) -> bool:
	for machine in caravan.machines:
		if not machine.is_broken() and _planar(machine.global_position, player.global_position) <= distance:
			return true
	return false


static func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
