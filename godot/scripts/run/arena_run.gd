class_name ArenaRun
extends Node
## Regia del prototipo della promessa A (D-038, docs/PROMISE_A_PROTOTYPE_SPEC.md):
## collega nemici, arma, esperienza, level-up, vita e fine run, applica alla
## griglia la disposizione del terreno (cortili, depositi, trincee) prodotta
## dall'arena grande (D-042) e gli effetti degli upgrade.
## Chiude il livello col boss (D-043): chiamata a tempo, direzione annunciata,
## arrivo del Demolitore, vittoria alla sua morte.
## Seed: `-- --seed=N` sulla riga di comando, altrimenti casuale; sempre nel log.
## `-- --boss-at=N` anticipa la chiamata del boss a N secondi.

signal boss_called(direction: Vector3)
signal boss_spawned(boss: Enemy)
## Boss battuto e piazzola di estrazione chiamata (D-076).
signal extraction_called
signal level_completed
## Rilancio di DayNightCycle.phase_changed: HUD e audio non dipendono dal nodo del ciclo.
signal night_phase_changed(phase: DayNightCycle.Phase)

enum BossPhase { WAITING, WARNING, ACTIVE, EXTRACTION, DEFEATED }

## Indicatori a bordo schermo (D-044): oltre questa distanza un punto e fuori vista.
const MARKER_MIN_DISTANCE := 14.0
## Scala degli indicatori con la distanza della camera (D-078): la soglia "fuori vista"
## segue la finestra visibile come l'anello di comparsa.
var marker_scale := 1.0
const MARKER_MAX_DISTANCE := 130.0
## Quanti cortili e quanti depositi indicare, i piu vicini.
const MARKERS_PER_KIND := 2
const MARKER_COURTYARD_COLOR := Color(0.95, 0.85, 0.55)
const MARKER_DEPOSIT_COLOR := Color(0.95, 0.5, 0.15)
const MARKER_BOSS_COLOR := Color(1.0, 0.25, 0.15)
const MARKER_FUSION_COLOR := Color(0.5, 0.82, 1.0)
## Ogni quanto si ricontrolla quali punti di interesse hanno ancora celle Raised.
const MARKER_REFRESH_SECONDS := 1.0
const MAIN_MENU_SCENE := "res://scenes/main/main_menu.tscn"
## Raggio della carta ripetibile Barattolo di chiodi.

## Nome a schermo di ogni boss (annuncio e barra vita).
const BOSS_NAMES: Dictionary[StringName, String] = {&"demolisher": "IL DEMOLITORE", &"driller": "LA TRIVELLA"}
## Direzioni di arrivo annunciate: nome e verso nel mondo (nord = -Z = alto dello schermo).
## Rilievo di base cotto da `tests/tools/bake_terrain_base.gd` (LFS); se manca si ricalcola.
const BOSS_DIRECTIONS := [
	["NORD", Vector3(0.0, 0.0, -1.0)], ["EST", Vector3(1.0, 0.0, 0.0)],
	["SUD", Vector3(0.0, 0.0, 1.0)], ["OVEST", Vector3(-1.0, 0.0, 0.0)],
]

@export var tuning: RunTuning
## Quale livello della campagna e questa scena (LevelCatalog, D-066).
@export var level_id: StringName = &"district"
## Arena grande con i punti di interesse del terreno; senza, si costruisce il solo
## cortile centrale di `tuning.wall_ring_radius`.
@export var district: RuinsDistrict
@export var player: PlayerCharacter
@export var caravan: Caravan
## Rilievo continuo del livello (D-085); con questo nodo la griglia non c'e piu.
@export var terrain_field: TerrainField
@export var director: EnemyDirector
@export var weapon: AutoWeapon
@export var xp_field: XpField
@export var hud: RunHud
@export var level_up_menu: LevelUpMenu
@export var game_over: GameOverPanel
## Officina fra i livelli (D-049); opzionale.
@export var workshop: WorkshopPanel
## Ciclo giorno/notte (D-058); senza nodo il livello resta diurno.
@export var day_night: DayNightCycle
## Lampioni (D-058, tappa 2); senza nodo il tool ha due modalita.
@export var lamp_field: LampField
## Treno della ferrovia (D-066, livello 2); senza nodo non passa nessun treno.
@export var train_event: TrainEvent
## Terremoto del quartiere (D-075), solo nel livello 1.
@export var quake_event: QuakeEvent
## Piazzola di estrazione (D-076): battuto il boss, il livello finisce solo con un 3x3
## piano tenuto; senza nodo (o con `extraction_enabled` spento) la vittoria e immediata.
@export var extraction_pad: ExtractionPad

var progression := RunProgression.new()
var elapsed := 0.0
var is_over := false
var run_seed := 0
## Classe del giocatore (D-092) e i suoi slot d'arma; la chiodatrice della scena e `weapon`.
var class_id: StringName = ClassCatalog.DEFAULT
var loadout: WeaponLoadout
var write_queue: TerrainWriteQueue
## Piazzola di fusione (D-093, piano B): creata nel codice con carovana e rilievo; seme + 8.
var fusion_pad: FusionPad
## Banco di fusione (piano B): creato con la pedana; si apre solo da `_open_next_level_up`.
var fusion_bench: FusionBench
## Prato logico (Falce rotante, Erba alta): riempito dal distretto con il rilievo.
var meadow: MeadowMap
## Carte dei mazzi di classe che non sono armi (spec D-092, par. 5).
var class_perks: ClassPerks
## Luci logiche della notte: torcia del giocatore, Faro della carovana (le sorgenti le
## registrano i moduli Faro) e lampioni (tappa 2).
var light_field := LightField.new()
var torch_light_id := 0
var torch_radius := 0.0
var _torch: OmniLight3D
var _night_factor_applied := -1.0
var _day_second_shown := -1
var dig_blast_radius := 0.0
var boss_phase := BossPhase.WAITING
var boss: Enemy
var boss_direction := Vector3.ZERO
var boss_direction_name := ""
## Secondi di livello a cui il boss viene chiamato (tuning o riga di comando); 0 = mai.
var boss_call_at := 0.0
## Eventi del mondo di questo livello (D-097): `[{at, kind}]` scelti a caso alla partenza.
var world_event_plan: Array[Dictionary] = []
var _boss_warning_left := 0.0
var _boss_rng := RandomNumberGenerator.new()
var _pending_level_ups := 0
## Casse sepolte (D-092, par. 6.3): aperte e non ancora scelte; `_cache_menu` vale se la
## scelta aperta (o la sua trasformazione) viene da una cassa.
var caches: BuriedCaches
var _pending_caches := 0
var _cache_menu := false
const CACHE_FALLBACK_SCRAP := 2
## Relitti sepolti (D-093): aperti e non ancora scelti; `_wreck_menu` vale se la scelta aperta
## viene da un relitto; carte estratte col seme della run + 7. I numeri sono in CaravanTuning.
var wrecks: MachineWrecks
var _pending_wrecks := 0
var _wreck_menu := false
var _wreck_rng := RandomNumberGenerator.new()
## Moduli staccati a terra (D-093, piano C): li posano terremoto e treno, Interagisci li riprende.
var module_relics: ModuleRelics
## Punti di interesse ancora da indicare: { center: Vector3, text: String, color: Color, kind: StringName }.
var _marker_targets: Array[Dictionary] = []
var _marker_refresh_left := 0.0
## Controlli `highest_bump` degli indicatori (audit R-03, per i test).
var marker_bump_checks := 0
## Barricate del Demolitore copiate alla sua morte (audit B-01).
var _boss_barricades: Array[Vector3] = []
## Esito per pennellata del quartiere (indice): l'argine sporge ancora? Si ricontrolla solo
## se il terreno e cambiato sopra di lei dall'ultimo aggiornamento.
var _marker_alive: Dictionary[int, bool] = {}
var _marker_dirty := Rect2()
var _marker_has_dirty := false
var _marker_step := 0
## Profilo permanente (autoload PlayerProfile); null se la scena gira senza.
var _profile: PlayerProfileService
var _death_scrap_share := 0.0
## Fotografia della griglia a inizio livello e conteggi del tool, per la mappa finale (D-052).
## Quote iniziali del rilievo continuo per la mappa di fine livello (Task 13: RunMap.snapshot_heights).
var _initial_heights := PackedFloat32Array()
## Secondi in cui il cortile di partenza resta non scolpibile.
var _start_protect_left := 0.0
## Mappa di fine run catturata alla vittoria, prima che l'orda e il boss siano liberati.
var _final_map: Image
var _start_position := Vector3.ZERO
## Rilievo continuo: metri cubi scavati e alzati dal giocatore.
var volume_dug := 0.0
var volume_raised := 0.0
## Secondi di scavo continuo accumulati per lo scavo esplosivo (scatta ogni `every_seconds`)
## e passo fisico dell'ultima pennellata (tempo di gioco, non reale).
var _blast_charge := 0.0
var _last_sculpt_frame := -1
## Le zolle che saltano mentre si scava: al piu una ogni DEBRIS_EVERY_SECONDS.
const DEBRIS_EVERY_SECONDS := 0.2
var _debris_left := 0.0
## Striscia della carovana: vita, stato e riparazione mostrati per macchina (indice della
## carovana), confrontati a ogni passo senza allocare.
var _caravan_health_shown := PackedInt32Array()
var _caravan_state_shown := PackedInt32Array()
var _caravan_repair_shown := PackedFloat64Array()


func _ready() -> void:
	# Ultimo nel passo fisico, qualunque sia l'ordine dei fratelli: aprire la pausa
	# (level-up, game over) da qui non lascia nodi a meta passo (T-05).
	process_physics_priority = 100
	if tuning == null:
		tuning = RunTuning.new()
	run_seed = _seed_from_command_line()
	progression.setup(run_seed)
	progression.xp_first_level = tuning.xp_first_level
	progression.xp_growth = tuning.xp_growth
	progression.pity_level_ups = tuning.pity_level_ups
	progression.has_caravan = caravan != null
	if caravan != null:
		progression.module_count = caravan.count_of
	director.rng.seed = run_seed + 1
	_boss_rng.seed = run_seed + 2
	_check_scale()
	_setup_night()
	_setup_train()
	_setup_quake()
	_setup_extraction()
	_setup_camera_distance()
	boss_call_at = _boss_call_from_command_line(tuning.boss_call_seconds)
	_schedule_world_events()

	player.invulnerability_seconds = tuning.player_invulnerability
	player.set_max_health(tuning.player_max_health)
	# Il chiodo parte dalla canna, all'altezza della mano (O-04); i valori vengono dal catalogo.
	weapon.muzzle_height = 0.15
	weapon.muzzle_forward = 0.55
	_setup_loadout()
	_setup_aim_mode()
	xp_field.player_radius = tuning.pickup_radius
	xp_field.terrain_field = terrain_field
	_death_scrap_share = tuning.death_scrap_share
	_apply_permanent_upgrades()
	_build_terrain_layout()
	_start_position = player.global_position
	_setup_fusion_pad()
	# Una sola pressione di Interagisci per tutto: la smista `_on_interact_pressed`.
	player.interact_pressed.connect(_on_interact_pressed)

	player.health_changed.connect(hud.set_health)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	director.enemy_killed.connect(_on_enemy_killed)
	xp_field.collected.connect(_on_xp_collected)
	level_up_menu.chosen.connect(_on_upgrade_chosen)
	game_over.restart_requested.connect(restart)
	game_over.menu_requested.connect(return_to_menu)
	game_over.next_level_requested.connect(start_next_level)
	if workshop != null:
		game_over.workshop_requested.connect(workshop.open)
		# Tornando dall'Officina il passo successivo e ripartire.
		workshop.closed.connect(game_over.focus_default.bind(false))
	if terrain_field != null:
		terrain_field.player_sculpted.connect(_on_player_sculpted)
		terrain_field.region_changed.connect(_on_marker_terrain_changed)
	hud.set_health(player.health, player.max_health)
	_refresh_xp()
	var title := LevelCatalog.title_of(level_id)
	if not title.is_empty():
		hud.show_notice("LIVELLO %d: %s" % [LevelCatalog.index_of(level_id) + 1, title.to_upper()], 4.0, RunHud.TITLE_COLOR)
	print("PROTOTYPE01_RUN_START seed=%d level=%s class=%s" % [run_seed, level_id, class_id])


func _physics_process(delta: float) -> void:
	if is_over:
		return
	elapsed += delta
	hud.set_time(elapsed)
	_tick_night()
	# Ogni evento puo chiudere la run (treno o terremoto mortali, piazzola tenuta): dopo,
	# niente boss chiamato ne altri eventi nello stesso passo (audit B-02).
	if train_event != null:
		train_event.advance(elapsed, delta)
	if is_over:
		return
	if quake_event != null:
		quake_event.advance(elapsed, delta)
	if is_over:
		return
	if extraction_pad != null:
		extraction_pad.advance(delta)
	if is_over:
		return
	if fusion_pad != null:
		fusion_pad.advance(elapsed, delta)
	_tick_boss(delta)
	_tick_start_protection(delta)
	_tick_markers(delta)
	_tick_weapon_hud()
	_tick_caravan_hud()
	_open_next_level_up()


# --- Indicatori a bordo schermo ----------------------------------------------------

func _tick_markers(delta: float) -> void:
	if district == null:
		return
	_marker_refresh_left -= delta
	if _marker_refresh_left <= 0.0:
		_marker_refresh_left = MARKER_REFRESH_SECONDS
		_refresh_marker_targets()
	# Un passo si e uno no (60 Hz): gli indicatori non hanno bisogno dei 120 Hz della fisica (R-22).
	_marker_step += 1
	if _marker_step % 2 == 0:
		hud.set_markers(current_markers())


## Un cortile o un deposito resta indicato finche il suo argine o cumulo sporge dalla
## base (rilievo continuo) o finche ha almeno una cella Raised (griglia): un deposito
## spianato del tutto sparisce dagli indicatori.
func _refresh_marker_targets() -> void:
	_marker_targets.clear()
	if terrain_field != null:
		for index in district.terrain_strokes.size():
			var stroke: Dictionary = district.terrain_strokes[index]
			if stroke.height <= 0.0:
				continue
			var center := Vector3(stroke.center.x, 0.0, stroke.center.y)
			var is_deposit: bool = stroke.scrap > 0
			if is_deposit and _scrap_field() != null:
				# Un deposito vale finche la sua vena ha rottami, anche se il cumulo e spianato.
				if _scrap_field().vein_scrap_left(center) <= 0:
					continue
			elif not _stroke_still_raised(index, center, stroke.radius + 2.0):
				continue
			_add_marker_target(is_deposit, stroke.marker)
		_marker_has_dirty = false



## L'argine della pennellata [param index] sporge ancora? Il disco di 9-14 m si riscandisce
## solo se il terreno e cambiato li sopra (audit R-03: prima ogni secondo, per ogni cortile).
func _stroke_still_raised(index: int, center: Vector3, radius: float) -> bool:
	var disc := Rect2(center.x - radius, center.z - radius, radius * 2.0, radius * 2.0)
	if not _marker_alive.has(index) or (_marker_has_dirty and _marker_dirty.intersects(disc)):
		marker_bump_checks += 1
		_marker_alive[index] = terrain_field.highest_bump(center, radius, 0.8) != null
	return _marker_alive[index]


func _on_marker_terrain_changed(aabb: AABB) -> void:
	var rect := Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z)
	_marker_dirty = _marker_dirty.merge(rect) if _marker_has_dirty else rect
	_marker_has_dirty = true


func _scrap_field() -> ScrapField:
	return caravan.scrap_field if caravan != null else null


func _add_marker_target(is_deposit: bool, marker: Vector2) -> void:
	_marker_targets.append({
		center = Vector3(marker.x, 0.0, marker.y),
		kind = &"deposit" if is_deposit else &"courtyard",
		text = "ROTTAMI" if is_deposit else "CORTILE",
		color = MARKER_DEPOSIT_COLOR if is_deposit else MARKER_COURTYARD_COLOR,
	})


## I due cortili e i due depositi piu vicini fuori vista, piu il boss se e in campo.
func current_markers() -> Array[Dictionary]:
	var origin := player.global_position
	var by_kind := {&"courtyard": [], &"deposit": []}
	for target in _marker_targets:
		var offset: Vector3 = target.center - origin
		var distance := Vector2(offset.x, offset.z).length()
		if distance < marker_min_distance() or distance > MARKER_MAX_DISTANCE:
			continue
		by_kind[target.kind].append({
			direction = Vector2(offset.x, offset.z), distance = distance, color = target.color, text = target.text,
		})
	var markers: Array[Dictionary] = []
	for kind: StringName in by_kind:
		var list: Array = by_kind[kind]
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
		for i in mini(MARKERS_PER_KIND, list.size()):
			markers.append(list[i])
	if boss_phase == BossPhase.ACTIVE and is_instance_valid(boss):
		var offset := boss.global_position - origin
		var distance := Vector2(offset.x, offset.z).length()
		if distance >= marker_min_distance():
			markers.append({direction = Vector2(offset.x, offset.z), distance = distance, color = MARKER_BOSS_COLOR, text = "BOSS"})
	if fusion_pad != null and fusion_pad.is_open():
		var offset := fusion_pad.center - origin
		var distance := Vector2(offset.x, offset.z).length()
		if distance >= marker_min_distance():
			markers.append({direction = Vector2(offset.x, offset.z), distance = distance, color = MARKER_FUSION_COLOR, text = "PIAZZOLA"})
	return markers


# --- Boss di fine livello ----------------------------------------------------------

func _tick_boss(delta: float) -> void:
	match boss_phase:
		BossPhase.WAITING:
			if boss_call_at > 0.0 and elapsed >= boss_call_at:
				call_boss()
		BossPhase.WARNING:
			_boss_warning_left -= delta
			hud.set_boss_warning(boss_name(), boss_direction_name, boss_direction, _boss_warning_left)
			if _boss_warning_left <= 0.0:
				_spawn_boss()
		BossPhase.ACTIVE:
			if is_instance_valid(boss):
				hud.set_boss_health(boss.health, boss.max_health)


## Annuncia la direzione di arrivo: il giocatore ha il preavviso per preparare il terreno.
func call_boss() -> void:
	if boss_phase != BossPhase.WAITING:
		return
	# La piazzola di fusione si richiude (prima dell'avviso: non atterra piu).
	if fusion_pad != null:
		fusion_pad.close()
	# Solo direzioni in cui c'e spazio per arrivare da lontano (vicino ai bordi no).
	var limit := _play_half_extents() - Vector2(3.0, 3.0)
	var options: Array = []
	var path := director.path_field
	for entry: Array in BOSS_DIRECTIONS:
		var point: Vector3 = player.global_position + entry[1] * tuning.boss_spawn_distance
		if absf(point.x) > limit.x or absf(point.z) > limit.y:
			continue
		# E con un punto d'ingresso percorribile (T-01: non dentro una rovina).
		if path != null and path.is_ready() and _walkable_near(point, 9.0) == null:
			continue
		options.append(entry)
	if options.is_empty():
		options = BOSS_DIRECTIONS
	var chosen: Array = options[_boss_rng.randi_range(0, options.size() - 1)]
	boss_direction_name = chosen[0]
	boss_direction = chosen[1]
	boss_phase = BossPhase.WARNING
	_boss_warning_left = tuning.boss_warning_seconds
	hud.set_boss_warning(boss_name(), boss_direction_name, boss_direction, _boss_warning_left)
	print("PROTOTYPE01_BOSS_CALLED direction=%s time=%.1f" % [boss_direction_name, elapsed])
	boss_called.emit(boss_direction)


## Nome a schermo del boss di questo livello.
func boss_name() -> String:
	return BOSS_NAMES.get(tuning.boss_kind, "IL BOSS")


func _spawn_boss() -> void:
	boss_phase = BossPhase.ACTIVE
	hud.clear_boss_warning()
	hud.set_boss_name(boss_name())
	match tuning.boss_kind:
		&"driller":
			boss = _make_driller()
		_:
			boss = _make_demolisher()
	var point := _boss_spawn_point()
	director.add_enemy(boss, Vector3(point.x, boss.spawn_center_height(), point.z))
	boss.rotation.y = atan2(boss_direction.x, boss_direction.z)
	boss.died.connect(_on_boss_died)
	if train_event != null:
		train_event.boss = boss
	if quake_event != null:
		quake_event.boss = boss
	hud.set_boss_health(boss.health, boss.max_health)
	boss_spawned.emit(boss)
	print("PROTOTYPE01_BOSS_SPAWNED direction=%s x=%.1f z=%.1f health=%d" % [boss_direction_name, point.x, point.z, boss.health])


func _make_demolisher() -> Demolisher:
	var demolisher := Demolisher.new()
	demolisher.setup_demolisher(tuning.boss_health, director.flash_material())
	demolisher.player = player
	demolisher.terrain_field = terrain_field
	demolisher.path_field = director.path_field
	demolisher.director = director
	demolisher.caravan = caravan
	demolisher.speed = tuning.boss_speed
	demolisher.contact_damage = tuning.boss_contact_damage
	demolisher.contact_radius = tuning.boss_contact_radius
	demolisher.demolish_seconds = tuning.boss_demolish_seconds
	demolisher.wall_attraction_radius = tuning.boss_wall_attraction_radius
	demolisher.walls_per_barricade = tuning.boss_walls_per_barricade
	demolisher.max_barricades = tuning.boss_max_barricades
	demolisher.scrap_field = _scrap_field()
	demolisher.lamp_field = lamp_field
	demolisher.max_carriers = tuning.boss_max_carriers
	demolisher.carrier_scrap_radius = tuning.boss_carrier_scrap_radius
	demolisher.carrier_recruit_radius = tuning.boss_carrier_recruit_radius
	demolisher.carrier_timeout = tuning.boss_carrier_timeout
	return demolisher


func _make_driller() -> Driller:
	var driller := Driller.new()
	driller.setup_driller(tuning.driller_health, director.flash_material())
	driller.player = player
	driller.terrain_field = terrain_field
	driller.path_field = director.path_field
	driller.director = director
	driller.caravan = caravan
	driller.scrap_field = _scrap_field()
	driller.lamp_field = lamp_field
	driller.contact_damage = tuning.boss_contact_damage
	driller.contact_radius = tuning.boss_contact_radius
	driller.charge_speed = tuning.driller_charge_speed
	driller.charge_length = tuning.driller_charge_length
	driller.aim_seconds = tuning.driller_aim_seconds
	driller.rest_seconds = tuning.driller_rest_seconds
	driller.stun_seconds = tuning.driller_stun_seconds
	driller.stun_damage_multiplier = tuning.driller_stun_damage_multiplier
	driller.furrow_depth_m = tuning.driller_furrow_depth_m
	driller.wall_min_delta_m = tuning.driller_wall_min_delta_m
	return driller


## Punto di ingresso nella direzione annunciata: dentro l'arena e su terreno libero.
func _boss_spawn_point() -> Vector3:
	var path := director.path_field
	var side := Vector3(-boss_direction.z, 0.0, boss_direction.x)
	for lateral in [0.0, 3.0, -3.0, 6.0, -6.0, 9.0, -9.0]:
		for back in [0.0, -3.0, 3.0, -6.0]:
			var point: Vector3 = player.global_position + boss_direction * (tuning.boss_spawn_distance + back) + side * lateral
			point = _clamp_inside(point)
			if path == null or (path.is_walkable(point) and path.is_walkable(point + Vector3(1.0, 0.0, 1.0)) \
					and path.is_walkable(point - Vector3(1.0, 0.0, 1.0))):
				return point
	var fallback := _clamp_inside(player.global_position + boss_direction * tuning.boss_spawn_distance)
	# Ripiego verificato: la cella percorribile piu vicina a spirale (T-01).
	var near: Variant = _walkable_near(fallback, 24.0)
	return near if near != null else fallback


## Punto percorribile (dentro l'arena) piu vicino a [param origin] entro [param radius],
## cercato a spirale a passi di una cella del campo; null se non c'e.
func _walkable_near(origin: Vector3, radius: float) -> Variant:
	var path := director.path_field
	if path == null:
		return origin
	var step := path.cell_size
	var rings := int(ceil(radius / step))
	for ring in rings + 1:
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var point := _clamp_inside(origin + Vector3(dx * step, 0.0, dz * step))
				if path.is_walkable(point) and path.is_walkable(point + Vector3(1.0, 0.0, 1.0)) \
						and path.is_walkable(point - Vector3(1.0, 0.0, 1.0)):
					return point
	return null


## La scala e scritta in quattro posti (R-27): se non coincidono le feature del quartiere
## finirebbero su celle sbagliate in silenzio. Qui si grida all'avvio.
func _check_scale() -> void:
	if district != null and terrain_field != null \
			and (terrain_field.half_extents() - district.half_extents()).length() > 0.5:
		push_error("Scala incoerente: rilievo %s m di semilati, distretto %s" % [terrain_field.half_extents(), district.half_extents()])
	if director.path_field != null and district != null \
			and not Vector2(director.path_field.half_extent, director.path_field.half_z()).is_equal_approx(district.half_extents()):
		push_error("Scala incoerente: campo di percorso %.1f x %.1f m, distretto %s"
			% [director.path_field.half_extent, director.path_field.half_z(), district.half_extents()])


## Mezzi lati dell'area giocabile (X, Z).
func _play_half_extents() -> Vector2:
	if district != null:
		return district.half_extents()
	if director.path_field != null:
		return Vector2(director.path_field.half_extent, director.path_field.half_z())
	return Vector2(24.0, 24.0)


## Il punto riportato dentro l'arena, a 3 m dal bordo, a quota zero.
func _clamp_inside(point: Vector3) -> Vector3:
	var limit := _play_half_extents() - Vector2(3.0, 3.0)
	return Vector3(clampf(point.x, -limit.x, limit.x), 0.0, clampf(point.z, -limit.y, limit.y))


## Rottami di recupero: per i livelli guadagnati (`recovery_scrap_levels`) e, se
## accesa, per il tempo di livello (`survival_scrap_seconds`).
func recovery_scrap() -> int:
	var total := 0
	if tuning.recovery_scrap_levels > 0.0:
		total += int((progression.level - 1) / tuning.recovery_scrap_levels)
	if tuning.survival_scrap_seconds > 0.0:
		total += int(elapsed / tuning.survival_scrap_seconds)
	return total


## Rottami che escono dal livello: quelli nei Cassoni della carovana e quelli di recupero, piu il
## premio del boss se battuto.
func scrap_out(victory: bool) -> int:
	var carried := (caravan.carried if caravan != null else 0) + recovery_scrap()
	if victory:
		return carried + tuning.boss_scrap_bonus
	return int(floor(carried * _death_scrap_share))


## Boss battuto: con la piazzola (D-076) il livello continua finche il giocatore non tiene
## un 3x3 piano; altrimenti vittoria subito (D-043).
func _on_boss_died(_enemy: Enemy) -> void:
	# Il boss viene liberato subito dopo: la mappa di fine livello (dopo l'estrazione) ha
	# bisogno delle sue barricate (audit B-01).
	if boss is Demolisher:
		_boss_barricades = (boss as Demolisher).barricade_points.duplicate()
	if extraction_pad != null and tuning.extraction_enabled and not is_over:
		boss_phase = BossPhase.EXTRACTION
		hud.clear_boss()
		extraction_pad.begin()
		extraction_called.emit()
		return
	_end_level(true)


func _on_extraction_completed() -> void:
	_end_level(true)


## Fine del livello, vittoria o morte (R-14): prima il conto e l'incasso nel profilo,
## poi log, mappa e pannello, cosi un errore nella parte cosmetica non salta l'incasso
## (F-04: la mappa viene dopo l'incasso ma prima di congedare l'orda, che le serve, T-08).
func _end_level(victory: bool) -> void:
	if is_over:
		return
	is_over = true
	director.spawning = false
	if level_up_menu.is_open:
		level_up_menu.close()
	if fusion_bench != null and fusion_bench.is_open:
		fusion_bench.close()
	var scrap := scrap_out(victory)
	var banked := _bank(scrap, victory)
	var save_failed := _profile != null and _profile.last_save_error != OK
	print("%s time=%.1f level=%d kills=%d scrap=%d seed=%d"
		% ["PROTOTYPE01_LEVEL_COMPLETE" if victory else "PROTOTYPE01_PLAYER_DIED", elapsed, progression.level, director.kills, scrap, run_seed])
	if victory:
		boss_phase = BossPhase.DEFEATED
		_final_map = build_run_map()
		director.clear_horde()
		hud.clear_boss()
		level_completed.emit()
	_show_run_map()
	var next := LevelCatalog.next_of(level_id)
	game_over.set_next_level(LevelCatalog.title_of(next) if victory and LevelCatalog.is_playable(next) else "")
	game_over.open(elapsed, progression.level, director.kills, victory, scrap, banked, save_failed)


# --- Profilo permanente e Officina (D-049) ------------------------------------------

## Upgrade permanenti comprati in Officina: valgono dall'inizio di ogni livello.
func _apply_permanent_upgrades() -> void:
	_profile = get_node_or_null(^"/root/PlayerProfile") as PlayerProfileService
	if _profile == null:
		return
	var applied: PackedStringArray = []
	for entry in PermanentCatalog.all():
		var id: StringName = entry.id
		var owned := _profile.level_of(id)
		# Gli upgrade di una classe valgono solo giocandola (D-092, par. 6.2).
		if owned <= 0 or (entry.group != &"common" and entry.group != class_id):
			continue
		applied.append("%s=%d" % [id, owned])
		match id:
			&"tool_reach":
				player.tool_range_bonus_m = 1.2 * owned
			&"pack_size":
				if player.pack != null:
					player.pack.add_capacity(20.0 * owned)
			&"base_health":
				player.set_max_health(tuning.player_max_health + owned)
			&"reflexes":
				player.invulnerability_seconds += 0.2 * owned
			&"cargo":
				if caravan != null:
					caravan.add_cargo_capacity(2 * owned)
			&"stock":
				if caravan != null:
					caravan.add_scrap(2 * owned)
			&"fixed_turret":
				# Una seconda macchina, con la Torretta (scelta 6 di D-093).
				if caravan != null:
					caravan.add_machine(&"turret")
			&"salvage":
				_death_scrap_share = maxf(_death_scrap_share, 0.75)
			&"toolbox":
				loadout.level_up(&"nailgun")
				if owned >= 2:
					loadout.level_up(&"seismic_stake")
			&"spare_stakes":
				loadout.set_weapon_mods(&"seismic_stake", {cooldown_mul = 0.9})
			&"dry_powder":
				loadout.set_weapon_mods(&"dig_charge", {damage_add = float(owned)})
			&"charge_pack":
				apply_upgrade(&"dig_blast", progression.choose(&"dig_blast"))
			&"good_oil":
				class_perks.boost_machine_speed(0.15)
			&"good_seeds":
				loadout.set_weapon_mods(&"bramble", {hedge_seconds_add = 3.0 * owned})
			&"green_thumb":
				apply_upgrade(&"tall_grass", progression.choose(&"tall_grass"))
	if not applied.is_empty():
		print("PROTOTYPE01_PERMANENT_APPLIED %s" % ",".join(applied))


## Incassa i rottami nel profilo; restituisce il totale in Officina, -1 senza profilo.
func _bank(scrap: int, victory: bool) -> int:
	if _profile == null:
		return -1
	_profile.bank_run(scrap, victory, maxi(LevelCatalog.index_of(level_id), 0), level_id)
	return _profile.scrap


## Disposizione iniziale del terreno: il rilievo del livello con le sue pennellate.
func _build_terrain_layout() -> void:
	if district == null or terrain_field == null:
		return
	_build_terrain_relief()


## Rilievo di base cotto del livello (`bake_terrain_base.gd -- --level=<id>`), in LFS.
func base_relief_path() -> String:
	return "res://levels/%s/base.bin" % level_id


## Rilievo continuo (D-085): base cotta (`base_relief_path()`) o ricalcolata dal quartiere,
## poi le pennellate dei punti di interesse; dischi protetti attorno alle rovine e, per i
## primi secondi, al cortile di partenza. Le quote iniziali per la mappa arrivano col Task 13.
func _build_terrain_relief() -> void:
	if not terrain_field.load_base(base_relief_path(), district.layout_seed):
		district.apply_base_relief(terrain_field)
	district.apply_strokes(terrain_field, _scrap_field())
	_place_caches()
	_place_wrecks()
	_place_module_relics()
	var margin: float = terrain_field.tuning.protected_radius_m
	for rect: Rect2 in district.block_rects():
		var center := rect.get_center()
		terrain_field.set_protected(Vector3(center.x, 0.0, center.y), rect.size.length() * 0.5 + margin, true)
	_start_protect_left = terrain_field.tuning.start_protected_seconds
	terrain_field.set_protected(Vector3.ZERO, terrain_field.tuning.start_protected_radius_m, true)
	_initial_heights = RunMap.snapshot_heights(terrain_field)
	if meadow != null:
		district.fill_meadow(meadow, terrain_field)
	# Prato, prop e rovine sulle quote; strati e tinte quando Terrain3D e pronto (con finestra).
	district.settle_on_relief()
	terrain_field.render_ready.connect(district.paint_surface.bind(terrain_field))
	# Terrain3D puo essere gia pronto (le pennellate dipingono subito): allora il prato parte ora.
	terrain_field.render_ready.connect(_spawn_grass_field)
	if terrain_field.terrain3d() != null:
		_spawn_grass_field.call_deferred()
	print("PROTOTYPE01_TERRAIN_LAYOUT_READY strokes=%d" % district.terrain_strokes.size())


## Casse sepolte (D-092, par. 6.3): 3 o 4 per livello (seme della run), sotto i cumuli e i
## vagoni ancora in piedi dopo le pennellate (sulla fascia dei binari i cumuli sono spianati).
func _place_caches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed + 5
	var raised := _raised_strokes()
	caches = BuriedCaches.new()
	caches.name = "BuriedCaches"
	caches.terrain_field = terrain_field
	caches.player = player
	add_child(caches)
	caches.place(BuriedCaches.pick_points(raised, rng, rng.randi_range(3, 4)))
	caches.cache_opened.connect(_on_cache_opened)
	if train_event != null:
		train_event.buried_caches = caches
	print("PROTOTYPE01_CACHE_PLACED count=%d" % caches.count())


## Relitti sepolti (D-093, Sezione 5): `wrecks_per_level` sotto i cumuli e i vagoni ancora in
## piedi, mai sotto la pennellata di una cassa (seme della run + 6). Solo con la carovana.
func _place_wrecks() -> void:
	if caravan == null:
		return
	_wreck_rng.seed = run_seed + 7
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed + 6
	var exclude: Array[Vector3] = []
	for i in caches.count():
		exclude.append(caches.position_of(i))
	wrecks = MachineWrecks.new()
	wrecks.name = "MachineWrecks"
	wrecks.terrain_field = terrain_field
	wrecks.player = player
	add_child(wrecks)
	wrecks.place(BuriedCaches.pick_points(_raised_strokes(), rng, caravan.tuning.wrecks_per_level, exclude))
	wrecks.cache_opened.connect(_on_wreck_opened)
	if train_event != null:
		train_event.machine_wrecks = wrecks
	print("PROTOTYPE01_WRECK_PLACED count=%d" % wrecks.count())


## Moduli staccati dagli eventi (D-093, piano C): stanno in superficie, li prende Interagisci.
func _place_module_relics() -> void:
	module_relics = ModuleRelics.new()
	module_relics.name = "ModuleRelics"
	module_relics.terrain_field = terrain_field
	module_relics.player = player
	add_child(module_relics)
	if train_event != null:
		train_event.module_relics = module_relics
	if quake_event != null:
		quake_event.module_relics = module_relics


## Pennellate del quartiere ancora alte dopo la posa (sulla fascia dei binari i cumuli sono
## spianati): sotto ci vanno casse e relitti.
func _raised_strokes() -> Array:
	return district.terrain_strokes.filter(func(stroke: Dictionary) -> bool:
		var center := Vector3(stroke.center.x, 0.0, stroke.center.y)
		return terrain_field.height_at(center) > terrain_field.base_height_at(center) + BuriedCaches.OPEN_MARGIN)


## Casse e relitti chiusi col centro nel rettangolo XZ: persi senza aprirsi. Va chiamata prima
## di riportare il suolo alla base, altrimenti si aprono e la loro scelta ferma il gioco.
func discard_buried_in_rect(rect: Rect2) -> void:
	if caches != null:
		caches.discard_in_rect(rect)
	if wrecks != null:
		wrecks.discard_in_rect(rect)


## Prato a particelle quando Terrain3D e pronto (playtest del 14 ottobre 2026, O-09).
func _spawn_grass_field() -> void:
	if terrain_field.terrain3d() == null or district.has_node(^"GrassField"):
		return
	district.drop_tuft_cover()
	var grass := GrassField.new()
	grass.name = "GrassField"
	district.add_child(grass)
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	grass.setup(terrain_field, player, settings.vegetation_density if settings != null else 2)


func _tick_start_protection(delta: float) -> void:
	if terrain_field == null or _start_protect_left <= 0.0:
		return
	_start_protect_left -= delta
	if _start_protect_left <= 0.0:
		terrain_field.set_protected(Vector3.ZERO, terrain_field.tuning.start_protected_radius_m, false)


## Con il velo il gioco resta fermo finche la scena nuova non e caricata (lo sblocca
## UiFx al cambio); senza velo si riparte subito.
func restart() -> void:
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx == null:
		get_tree().paused = false
		get_tree().reload_current_scene()
	else:
		fx.fade_reload()


func return_to_menu() -> void:
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx == null:
		get_tree().paused = false
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	else:
		fx.fade_to_scene(MAIN_MENU_SCENE)


## Il livello successivo della campagna (dalla schermata di vittoria).
func start_next_level() -> void:
	var next := LevelCatalog.next_of(level_id)
	if not LevelCatalog.is_playable(next):
		return
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx == null:
		get_tree().paused = false
		get_tree().change_scene_to_file(LevelCatalog.scene_of(next))
	else:
		fx.fade_to_scene(LevelCatalog.scene_of(next))


# --- Treno della ferrovia (D-066) ---------------------------------------------------

func _setup_train() -> void:
	if train_event == null:
		return
	train_event.warning_seconds = tuning.train_warning_seconds
	train_event.speed = tuning.train_speed
	train_event.carriages = tuning.train_carriages
	train_event.player_damage = tuning.train_player_damage
	train_event.boss_damage = tuning.train_boss_damage
	train_event.rng.seed = run_seed + 3
	if caravan != null and caravan.tuning != null:
		train_event.module_detach_count = caravan.tuning.train_detach_count
		train_event.throw_min = caravan.tuning.train_throw_min
		train_event.throw_max = caravan.tuning.train_throw_max


func _setup_extraction() -> void:
	if extraction_pad == null:
		return
	extraction_pad.hold_seconds = tuning.extraction_hold_seconds
	extraction_pad.extraction_completed.connect(_on_extraction_completed)


## Piazzola di fusione (D-093, piano B): solo con carovana e rilievo. L'arrivo a
## `pad_boss_fraction` della chiamata del boss si decide qui, una volta: chi cambia
## `boss_call_at` dopo non sposta la pedana.
func _setup_fusion_pad() -> void:
	if caravan == null or terrain_field == null:
		return
	fusion_pad = FusionPad.new()
	fusion_pad.name = "FusionPad"
	fusion_pad.terrain_field = terrain_field
	fusion_pad.player = player
	fusion_pad.hud = hud
	fusion_pad.caravan = caravan
	fusion_pad.path_field = director.path_field
	fusion_pad.lamp_field = lamp_field
	if caravan.tuning != null:
		fusion_pad.tuning = caravan.tuning
	fusion_pad.rng.seed = run_seed + 8
	fusion_pad.fallback_point = _start_position
	if train_event != null:
		fusion_pad.on_tracks = func(p: Vector3) -> bool: return RailwayDistrict.is_on_tracks(Vector2(p.x, p.z))
	add_child(fusion_pad)
	# La lampada nasce all'atterraggio: le luci si rifanno al passo dopo.
	fusion_pad.landed.connect(func(_center: Vector3) -> void: _night_factor_applied = -1.0)
	if boss_call_at > 0.0:
		fusion_pad.schedule(boss_call_at * fusion_pad.tuning.pad_boss_fraction)
	# Interagisci sulla pedana chiede il banco (da `_on_interact_pressed`); si apre a fine passo,
	# chiuso tornano i menu in coda.
	fusion_bench = FusionBench.new()
	fusion_bench.name = "FusionBench"
	add_child(fusion_bench)
	fusion_bench.closed.connect(func() -> void: _open_next_level_up.call_deferred())
	# Le combinazioni formate in partita entrano nel profilo (task 7); il banco le nomina da
	# conosciute. Senza profilo il banco resta col suo default ("???" per tutte).
	if _profile != null:
		caravan.combo_formed.connect(_profile.discover_combo)
		fusion_bench.combo_known = _profile.has_combo


## Smistatore di Interagisci premuto (D-093, piano C), con la precedenza fissa: la riparazione e
## a tenuta e la fa la carovana (vicino a una guasta qui non si prende nulla); a bordo nulla (salire
## e scendere sono a tenuta, task 5); poi un modulo staccato in portata, con posto in carovana,
## torna macchina piccola; altrimenti la pedana segna la richiesta del banco, se disponibile.
func _on_interact_pressed() -> void:
	if is_over or player.pilot != null:
		return
	var index := _relic_in_reach()
	if index >= 0:
		caravan.add_machine(module_relics.take(index))
		return
	if fusion_pad != null:
		fusion_pad.request_bench()


## Vero se Interagisci ora riprenderebbe un modulo staccato (tasto "Riprendi" del HUD).
func relic_available() -> bool:
	return _relic_in_reach() >= 0


## Relitto entro `relic_pickup_range` dal giocatore vivo e a piedi, con posto in carovana e
## nessuna macchina guasta da riparare vicino; -1 altrimenti.
func _relic_in_reach() -> int:
	if module_relics == null or caravan == null or caravan.tuning == null:
		return -1
	if not player.is_alive() or player.pilot != null or not caravan.has_room() or caravan.repair_target() != null:
		return -1
	return module_relics.nearest_index(player.global_position, caravan.tuning.relic_pickup_range)


func _setup_quake() -> void:
	if quake_event == null:
		return
	quake_event.warning_seconds = tuning.quake_warning_seconds
	quake_event.length_cells = tuning.quake_length_cells
	quake_event.distance_min = tuning.quake_distance_min
	quake_event.distance_max = tuning.quake_distance_max
	quake_event.player_damage = tuning.quake_player_damage
	quake_event.rng.seed = run_seed + 4
	if caravan != null and caravan.tuning != null:
		quake_event.module_detach_count = caravan.tuning.quake_detach_count
	# I binari ci sono solo dove c'e il treno (come per la pedana).
	if train_event != null:
		quake_event.on_tracks = func(p: Vector3) -> bool: return RailwayDistrict.is_on_tracks(Vector2(p.x, p.z))


## Eventi del mondo (D-097): quanti ne dice la scheda Gameplay, di tipo e istante casuali fra
## gli eventi che la scena ha e che sono accesi, prima della chiamata del boss.
## `--quake-at=S` mette un terremoto a S secondi al posto della scelta (prove e catture).
func _schedule_world_events() -> void:
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	var count := settings.world_event_count if settings != null else tuning.world_events_count
	var events: Array[WorldEvent] = []
	for event: WorldEvent in [train_event, quake_event]:
		if event != null and event.is_enabled() and (settings == null or settings.world_event_enabled(event.event_kind())):
			events.append(event)
	var kinds: Array[StringName] = []
	for event in events:
		kinds.append(event.event_kind())
	var end := (boss_call_at if boss_call_at > 0.0 else tuning.boss_call_seconds) - tuning.world_events_boss_margin
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed + 5
	world_event_plan = WorldEventScheduler.plan(kinds, count, tuning.world_events_start_seconds, end,
		tuning.world_events_min_gap, rng)
	for event: WorldEvent in [train_event, quake_event]:
		if event != null:
			event.schedule(WorldEventScheduler.times_of(world_event_plan, event.event_kind()))
	var forced_quake := RunLaunchOptions.quake_seconds()
	if quake_event != null and forced_quake >= 0.0:
		var forced: Array[float] = []
		if forced_quake > 0.0:
			forced.append(forced_quake)
		quake_event.schedule(forced)
	print("PROTOTYPE01_WORLD_EVENTS count=%d plan=%s" % [world_event_plan.size(), world_event_plan])


# --- Ciclo giorno/notte (D-058, tappa 1) -----------------------------------------

func _setup_night() -> void:
	torch_radius = tuning.torch_radius
	torch_light_id = light_field.add_source(player, torch_radius)
	# I Faro (BeaconModule) registrano da se le loro sorgenti; una macchina nuova, un livello o
	# un modulo spento o riacceso rifanno le luci al passo dopo, anche a fattore di notte fermo.
	if caravan != null:
		caravan.changed.connect(_on_caravan_changed)
	director.light_field = light_field
	if lamp_field != null:
		lamp_field.scrap_cost = tuning.lamp_scrap_cost
		lamp_field.max_count = tuning.lamp_max_count
		lamp_field.light_radius = tuning.lamp_light_radius
		lamp_field.light_field = light_field
		lamp_field.lamps_changed.connect(func(_count: int) -> void: _refresh_tool_hud())
		player.terrain_mode_changed.connect(func(_mode: int) -> void: _refresh_tool_hud())
		_refresh_tool_hud()
	# Terra nello zaino nel HUD (playtest O-02): prima `set_pack` non lo chiamava nessuno.
	if player.pack != null and hud != null:
		player.pack.changed.connect(hud.set_pack)
		hud.set_pack(player.pack.amount, player.pack.capacity)
	if day_night == null:
		return
	# Notte spenta nella scheda Gameplay (D-097): 0 = niente notte; `--night-at=` vince comunque.
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	var night_default := tuning.night_start_seconds if settings == null or settings.night_enabled else 0.0
	day_night.night_start_seconds = RunLaunchOptions.night_start_seconds(night_default)
	day_night.dusk_seconds = tuning.dusk_seconds
	if day_night.district == null:
		day_night.district = district
	day_night.phase_changed.connect(_on_night_phase_changed)


func _tick_night() -> void:
	if day_night == null:
		return
	day_night.advance(elapsed)
	var to_dusk := day_night.seconds_to_dusk(elapsed)
	var second := int(to_dusk) if is_finite(to_dusk) else -2
	if second != _day_second_shown or day_night.phase != DayNightCycle.Phase.DAY:
		_day_second_shown = second
		hud.set_day_phase(day_night.phase, to_dusk)
	_update_game_lights()


func _on_night_phase_changed(phase: DayNightCycle.Phase) -> void:
	director.night_active = phase == DayNightCycle.Phase.NIGHT
	match phase:
		DayNightCycle.Phase.DUSK:
			hud.show_night_notice("CALA LA NOTTE", 4.0)
		DayNightCycle.Phase.NIGHT:
			hud.show_night_notice("E NOTTE", 3.0)
	night_phase_changed.emit(phase)


## La torcia e di ArenaRun, non della scena del giocatore (piano, sezione 14): nasce alla
## prima chiamata. Le luci dei Faro accesi le tengono i moduli (Caravan.beacon_lights); il
## fattore di notte vale per tutte. A fattore 0 costano zero.
func _update_game_lights() -> void:
	var factor := day_night.night_factor
	if _torch == null:
		_torch = _make_game_light("TorchLight", player)
	if is_equal_approx(factor, _night_factor_applied):
		return
	_night_factor_applied = factor
	director.set_night(factor)
	var lights: Array[Dictionary] = [{light = _torch, radius = torch_radius}]
	if caravan != null:
		lights.append_array(caravan.beacon_lights())
	for entry in lights:
		var light: OmniLight3D = entry.light
		light.visible = factor > 0.0
		light.light_energy = 2.2 * factor
		light.omni_range = float(entry.radius) * 1.15
	# Lampada della piazzola di fusione: solo visiva, nessuna sorgente di LightField.
	if fusion_pad != null and fusion_pad.light() != null:
		var pad_light := fusion_pad.light()
		pad_light.visible = factor > 0.0
		pad_light.light_energy = 2.2 * factor
		pad_light.omni_range = fusion_pad.tuning.pad_light_radius


## Macchine, livelli o moduli accesi cambiati: le luci si rifanno al prossimo passo.
func _on_caravan_changed() -> void:
	_night_factor_applied = -1.0


func _make_game_light(light_name: String, owner_node: Node3D) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = Vector3(0.0, 1.6, 0.0)
	light.light_color = Color(1.0, 0.9, 0.72)
	light.shadow_enabled = false
	light.visible = false
	owner_node.add_child.call_deferred(light)
	return light


func _refresh_tool_hud() -> void:
	if lamp_field == null:
		return
	hud.set_tool_mode(player.terrain_tool_mode, lamp_field.count(), lamp_field.max_count, lamp_field.scrap_cost)


func is_night() -> bool:
	return day_night != null and day_night.phase == DayNightCycle.Phase.NIGHT


## Abbandono dalla pausa (R-20, D-064): vale come una morte, si incassa la stessa quota.
## Niente mappa ne pannello: chi abbandona vuole uscire.
func abandon_run() -> void:
	if is_over:
		return
	is_over = true
	director.spawning = false
	var scrap := scrap_out(false)
	var banked := _bank(scrap, false)
	print("PROTOTYPE01_RUN_ABANDONED time=%.1f level=%d kills=%d scrap=%d banked=%d seed=%d"
		% [elapsed, progression.level, director.kills, scrap, banked, run_seed])


## Mappa del campo come l'ha lasciato il giocatore, per la schermata di fine livello.
## Barricate del Demolitore per la mappa: dal boss vivo, o quelle copiate alla sua morte.
func map_barricade_points() -> Array[Vector3]:
	if is_instance_valid(boss) and boss is Demolisher:
		return (boss as Demolisher).barricade_points
	return _boss_barricades


func build_run_map() -> Image:
	var buildings: Array[Rect2] = []
	if district != null:
		for child in district.get_children():
			if not (child is StaticBody3D) or not child.name.begins_with("Block"):
				continue
			for part in child.get_children():
				if part is CollisionShape3D and (part as CollisionShape3D).shape is BoxShape3D:
					var size := ((part as CollisionShape3D).shape as BoxShape3D).size
					var at := (child as StaticBody3D).global_position
					buildings.append(Rect2(at.x - size.x * 0.5, at.z - size.z * 0.5, size.x, size.z))
	var boss_position: Variant = boss.global_position if is_instance_valid(boss) else null
	var barricade_points := map_barricade_points()
	var lamp_points: Array[Vector3] = []
	if lamp_field != null:
		lamp_points = lamp_field.positions()
	return RunMap.render_heights(terrain_field, _initial_heights, barricade_points, buildings, _start_position, player.global_position, boss_position, lamp_points)


func _show_run_map() -> void:
	var stats := "Terra spostata: %d m3   (scavati %d, alzati %d)" % [roundi(terrain_field.volume_moved), roundi(volume_dug), roundi(volume_raised)]
	game_over.set_map(_final_map if _final_map != null else build_run_map(), stats, "run_%d" % run_seed)


func _on_enemy_killed(world_position: Vector3, total: int) -> void:
	xp_field.spawn(world_position, tuning.xp_per_enemy)
	hud.set_kills(total)


func _on_xp_collected(amount: int) -> void:
	if is_over:
		return
	_pending_level_ups += progression.add_xp(amount)
	_refresh_xp()
	# Il menu (e la pausa) si aprono a fine passo, in `_physics_process`: fermare
	# il gioco qui, a meta passo, lascerebbe indietro i nodi non ancora elaborati.


## Fine del passo (e dopo ogni menu chiuso): casse, relitti e level-up in coda (D-092, D-093),
## un menu alla volta in quest'ordine; poi il banco di fusione, se Interagisci l'ha chiesto sulla
## pedana in questo passo. Un altro menu aperto scarta la richiesta (scelta 9 di D-093).
func _open_next_level_up() -> void:
	if fusion_bench != null and fusion_bench.is_open:
		return
	if level_up_menu.is_open or is_over or _open_next_cache() or _open_next_wreck():
		_drop_bench_request()
		return
	if _pending_level_ups > 0:
		_cache_menu = false
		_wreck_menu = false
		var offer := progression.roll_offer()
		if not offer.is_empty():
			var ids := offer.map(func(u: Dictionary) -> String: return str(u.id))
			var shown_level := progression.level - _pending_level_ups + 1
			print("PROTOTYPE01_LEVEL_UP level=%d offer=%s" % [shown_level, ",".join(PackedStringArray(ids))])
			level_up_menu.open(offer, progression.levels, shown_level)
			_drop_bench_request()
			return
		_pending_level_ups = 0
	if fusion_pad != null and fusion_bench != null and fusion_pad.take_bench_request():
		fusion_bench.open(caravan)


func _drop_bench_request() -> void:
	if fusion_pad != null:
		fusion_pad.drop_bench_request()


func _on_upgrade_chosen(id: StringName) -> void:
	if _wreck_menu:
		_on_wreck_card(id)
		return
	if WeaponOffers.is_weapon_card(id):
		_on_weapon_card(id)
		return
	if MachineOffers.is_machine_card(id):
		_on_machine_card(id)
		return
	_pending_level_ups -= 1
	var new_level := progression.choose(id)
	apply_upgrade(id, new_level)
	print("PROTOTYPE01_UPGRADE_CHOSEN id=%s level=%d" % [id, new_level])
	_open_next_level_up.call_deferred()


## Carta arma (D-092): arma nuova, livello, bivio (apre le due trasformazioni senza consumare
## il level-up) o trasformazione scelta.
func _on_weapon_card(id: StringName) -> void:
	var card := WeaponOffers.parse(id)
	match card.get(&"kind", &""):
		&"new":
			loadout.add(card.weapon_id)
		&"level":
			loadout.level_up(card.weapon_id)
		&"branch":
			var at := loadout.level_of(card.weapon_id) + 1
			var title := String(WeaponCatalog.find(card.weapon_id).get(&"name", "")).to_upper()
			print("PROTOTYPE01_WEAPON_BRANCH id=%s at=%d" % [card.weapon_id, at])
			level_up_menu.open(WeaponOffers.branch_cards(card.weapon_id, at), {}, progression.level, title, "scegli una trasformazione")
			return
		&"choose":
			loadout.choose_branch(card.weapon_id, card.pick)
		&"fusion":
			loadout.fuse(card.weapon_id)
	if _cache_menu:
		_cache_menu = false
		_pending_caches -= 1
	else:
		_pending_level_ups -= 1
	print("PROTOTYPE01_UPGRADE_CHOSEN id=%s level=%d" % [id, loadout.level_of(card.get(&"weapon_id", &""))])
	_open_next_level_up.call_deferred()


## Carta "Nuova macchina" (D-093): una macchina col modulo, che riceve dalla carovana livelli,
## bonus e servizi. Consuma il level-up senza `progression.choose`: la carta resta "NUOVO".
func _on_machine_card(id: StringName) -> void:
	var module := MachineOffers.module_of(id)
	_pending_level_ups -= 1
	if caravan != null:
		caravan.add_machine(module)
	print("PROTOTYPE01_MACHINE_CARD module=%s" % module)
	_open_next_level_up.call_deferred()


## Cassa scoperta (dallo scavo, a meta passo): la scelta si apre a fine passo come il level-up.
func _on_cache_opened(_at: Vector3) -> void:
	if is_over:
		return
	_pending_caches += 1


## Prossima cassa in coda: tre carte arma; senza carte possibili (slot pieni, tutto al 5)
## 2 rottami e un avviso al posto del menu. Vero se ha aperto il menu.
func _open_next_cache() -> bool:
	while _pending_caches > 0:
		var offer := progression.roll_weapon_offer(WeaponOffers.cards(loadout, class_id, _unlocked_weapons()))
		if not offer.is_empty():
			_cache_menu = true
			_wreck_menu = false
			var ids := offer.map(func(u: Dictionary) -> String: return str(u.id))
			print("PROTOTYPE01_CACHE_OFFER offer=%s" % ",".join(PackedStringArray(ids)))
			level_up_menu.open(offer, {}, progression.level, "CASSA SEPOLTA", "scegli un'arma")
			return true
		_pending_caches -= 1
		_cache_scrap_fallback()
	return false


## Cassa senza carte: i rottami vanno nei Cassoni della carovana; quelli che non ci stanno (o
## tutti, senza carovana che li porti) restano a terra vicino al giocatore se c'e un campo di rottami.
func _cache_scrap_fallback() -> void:
	var given := 0
	if caravan != null:
		given = caravan.add_scrap(CACHE_FALLBACK_SCRAP)
	if _scrap_field() != null:
		for i in CACHE_FALLBACK_SCRAP - given:
			_scrap_field().spawn_on_ground(player.global_position + Vector3(0.8 * (i + 1), 0.0, 0.0))
	hud.show_notice("CASSA SEPOLTA: +%d ROTTAMI" % CACHE_FALLBACK_SCRAP, 3.0, RunHud.TITLE_COLOR)
	print("PROTOTYPE01_CACHE_SCRAP given=%d" % given)


## Relitto scoperto (dallo scavo, a meta passo): la scelta si apre a fine passo, dopo le casse.
func _on_wreck_opened(_at: Vector3) -> void:
	if is_over:
		return
	_pending_wrecks += 1


## Prossimo relitto in coda: `wreck_choices` carte "Nuova macchina" di moduli diversi; a
## carovana piena `wreck_full_scrap` rottami e un avviso al posto del menu. Vero se ha aperto il menu.
func _open_next_wreck() -> bool:
	while _pending_wrecks > 0:
		var offer: Array[Dictionary] = []
		if caravan != null and caravan.has_room():
			offer = MachineOffers.wreck_cards(_available_modules(), class_id, _wreck_rng, caravan.tuning.wreck_choices)
		if not offer.is_empty():
			_wreck_menu = true
			_cache_menu = false
			var ids := offer.map(func(u: Dictionary) -> String: return str(u.id))
			print("PROTOTYPE01_WRECK_OFFER offer=%s" % ",".join(PackedStringArray(ids)))
			level_up_menu.open(offer, {}, progression.level, "RELITTO SEPOLTO", "scegli una macchina")
			return true
		_pending_wrecks -= 1
		_wreck_scrap_fallback()
	return false


## Carta del relitto (D-093): la macchina col modulo scelto, al suo posto nella carovana.
## Consuma il relitto, non un level-up, e non scrive i livelli: la carta resta "NUOVO".
func _on_wreck_card(id: StringName) -> void:
	var module := MachineOffers.module_of(id)
	_wreck_menu = false
	_pending_wrecks -= 1
	if caravan != null:
		caravan.add_machine(module)
	print("PROTOTYPE01_WRECK_CHOSEN module=%s" % module)
	_open_next_level_up.call_deferred()


## Relitto a carovana piena: i rottami vanno nei Cassoni, quelli che non ci stanno restano a
## terra vicino al giocatore, come per la cassa.
func _wreck_scrap_fallback() -> void:
	if caravan == null:
		return
	var amount := caravan.tuning.wreck_full_scrap
	var given := caravan.add_scrap(amount)
	if _scrap_field() != null:
		for i in amount - given:
			_scrap_field().spawn_on_ground(player.global_position + Vector3(0.8 * (i + 1), 0.0, 0.0))
	hud.show_notice("RELITTO: +%d ROTTAMI" % amount, 3.0, RunHud.TITLE_COLOR)
	print("PROTOTYPE01_WRECK_SCRAP given=%d" % given)


## Effetto di un upgrade al suo nuovo livello.
func apply_upgrade(id: StringName, new_level: int) -> void:
	match id:
		# Carte di livello dei moduli: il livello del tipo, per le macchine presenti e future.
		&"turret_rate":
			if caravan != null:
				caravan.set_module_level(&"turret", new_level)
		&"magnet_range":
			if caravan != null:
				caravan.set_module_level(&"magnet", new_level)
		&"beacon_range":
			if caravan != null:
				caravan.set_module_level(&"beacon", new_level)
		&"companion_cargo":
			if caravan != null:
				caravan.add_cargo_capacity(int(UpgradeCatalog.value(id, &"capacity")))
				caravan.add_scrap(int(UpgradeCatalog.value(id, &"scrap_now")))
		&"dig_blast":
			dig_blast_radius = UpgradeCatalog.value(id, &"radius") + UpgradeCatalog.value(id, &"radius_per_level") * (new_level - 1)
		&"spiked_wall":
			director.spike_damage = int(UpgradeCatalog.value(id, &"damage"))
			director.spike_interval = UpgradeCatalog.value(id, &"interval") if new_level == 1 else UpgradeCatalog.value(id, &"interval_level_2")
			_set_raised_tint(Color(0.85, 0.75, 0.7))
		&"brush_size":
			player.brush_radius_bonus_m = UpgradeCatalog.value(id, &"radius_per_level") * new_level
		&"boots":
			player.speed_bonus *= 1.0 + UpgradeCatalog.value(id, &"speed_percent") / 100.0
		&"patch":
			player.set_max_health(player.max_health + int(UpgradeCatalog.value(id, &"health")))
		&"reach":
			xp_field.player_radius *= 1.0 + UpgradeCatalog.value(id, &"radius_percent") / 100.0
		&"field_patch":
			player.heal(int(UpgradeCatalog.value(id, &"heal")))
		&"lucky_scrap":
			if caravan != null:
				caravan.add_scrap(int(UpgradeCatalog.value(id, &"scrap_now")))
		&"torch_range":
			torch_radius = tuning.torch_radius + tuning.torch_radius_per_level * new_level
			light_field.set_radius(torch_light_id, torch_radius)
			_night_factor_applied = -1.0
		&"nail_jar":
			var radius := UpgradeCatalog.value(id, &"radius")
			var center := Vector3(player.global_position.x, 0.1, player.global_position.z)
			for enemy in director.enemies_near(center, radius):
				enemy.take_damage(int(UpgradeCatalog.value(id, &"damage")))
			_blast_effect(center, radius)
		_:
			if ClassPerks.handles(id) and class_perks != null:
				class_perks.apply(id, new_level)


## Rilievo continuo: contatori in metri cubi, zolle e scavo esplosivo a tempo (scatta
## ogni `every_seconds` di scavo continuo, non a ogni passo).
func _on_player_sculpted(center: Vector3, radius: float, volume: float, mode: int) -> void:
	volume_dug += maxf(-volume, 0.0)
	volume_raised += maxf(volume, 0.0)
	var frame := Engine.get_physics_frames()
	var since := float(frame - _last_sculpt_frame) / Engine.physics_ticks_per_second if _last_sculpt_frame >= 0 else 0.0
	_last_sculpt_frame = frame
	var top := Vector3(center.x, terrain_field.height_at(center) + 0.1, center.z)
	_debris_left -= since if since < 0.5 else _debris_left
	if absf(volume) > 0.05 and _debris_left <= 0.0:
		_debris_left = DEBRIS_EVERY_SECONDS
		DebrisBurst.spawn(get_parent(), top, Demolisher.EARTH_COLOR, 4, 2.6, 0.12)
	if mode != TerrainField.ToolMode.DIG or dig_blast_radius <= 0.0 or volume >= 0.0:
		_blast_charge = 0.0
		return
	# Un buco di oltre mezzo secondo fra due passi vuol dire che lo scavo era fermo.
	_blast_charge += since if since < 0.5 else 0.0
	var every := UpgradeCatalog.value(&"dig_blast", &"every_seconds", 0.5)
	if _blast_charge < every:
		return
	_blast_charge -= every
	for enemy in director.enemies_near(top, dig_blast_radius + radius * 0.5):
		enemy.take_damage(int(UpgradeCatalog.value(&"dig_blast", &"damage", 2.0)))
	_blast_effect(top, dig_blast_radius)
	print("PROTOTYPE01_DIG_BLAST x=%.1f z=%.1f" % [center.x, center.z])


func _blast_effect(center: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.05
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.6, 0.15, 0.7)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ring)
	ring.global_position = center
	ring.scale = Vector3(0.2, 1.0, 0.2)
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, ^"scale", Vector3(radius, 1.0, radius), 0.25)
	tween.tween_property(material, ^"albedo_color:a", 0.0, 0.25)
	tween.chain().tween_callback(ring.queue_free)


## Terrapieni spinati: gli argini alzati dal giocatore prendono un colore metallico chiaro.
func _set_raised_tint(color: Color) -> void:
	if terrain_field != null and terrain_field.terrain3d() != null:
		TerrainSurface.set_raised_tint(terrain_field.terrain3d(), color)


func _refresh_xp() -> void:
	hud.set_xp(progression.xp, progression.xp_to_next(), progression.level)


## Armi (D-092): la classe viene da `--class=` (la scelta nella campagna arriva col piano 4),
## il loadout adotta la chiodatrice della scena e crea le altre armi del kit. Coda delle
## scritture e loadout entrano subito nell'albero: la Torretta fissa e le carte li usano.
func _setup_loadout() -> void:
	# `--class=` (test, catture) vince sulla classe scelta nella campagna (profilo).
	var requested := RunLaunchOptions.class_id()
	var profile := get_node_or_null(^"/root/PlayerProfile") as PlayerProfileService
	if ClassCatalog.find(requested).is_empty() and profile != null:
		requested = profile.last_class
	if not ClassCatalog.find(requested).is_empty():
		class_id = requested
	write_queue = TerrainWriteQueue.new()
	write_queue.name = "WeaponTerrainQueue"
	write_queue.terrain_field = terrain_field
	write_queue.director = director
	if player != null:
		write_queue.bodies.append(player)
	add_child(write_queue)
	# Servizi della run ai moduli della carovana; le macchine entrano in `write_queue.bodies`
	# (restano alla stessa altezza sul suolo quando le armi alzano il terreno).
	if caravan != null:
		caravan.configure({director = director, terrain_field = terrain_field, write_queue = write_queue,
			xp_field = xp_field, light_field = light_field, run_tuning = tuning, lamp_field = lamp_field,
			extraction_pad = extraction_pad})
	loadout = WeaponLoadout.new()
	loadout.name = "WeaponLoadout"
	loadout.player = player
	loadout.director = director
	loadout.terrain_field = terrain_field
	loadout.write_queue = write_queue
	loadout.caravan = caravan
	loadout.xp_field = xp_field
	loadout.scrap_field = _scrap_field()
	if terrain_field != null:
		meadow = MeadowMap.new()
		meadow.setup(terrain_field)
		director.meadow = meadow
	loadout.meadow = meadow
	add_child(loadout)
	loadout.adopt(weapon)
	loadout.setup_class(class_id)
	progression.class_id = class_id
	# Segnaposto (spec par. 8): le classi senza modello usano l'Ingegnere con la tuta tinta.
	if class_id != ClassCatalog.DEFAULT:
		player.set_class_color((ClassCatalog.find(class_id).color as Color).srgb_to_linear())
	class_perks = ClassPerks.new()
	class_perks.name = "ClassPerks"
	class_perks.director = director
	class_perks.player = player
	class_perks.caravan = caravan
	class_perks.loadout = loadout
	class_perks.terrain_field = terrain_field
	class_perks.meadow = meadow
	add_child(class_perks)
	for card in ClassCatalog.start_cards(class_id):
		apply_upgrade(card, progression.choose(card))
	progression.weapon_cards = func() -> Array[Dictionary]: return WeaponOffers.cards(loadout, class_id, _unlocked_weapons())
	if caravan != null:
		progression.machine_cards = func() -> Array[Dictionary]: return MachineOffers.cards(caravan, class_id, _available_modules())
	loadout.changed.connect(_refresh_weapon_hud)
	# Striscia della carovana: macchine, stato e capienza (`changed`) e rottami (`carried_changed`).
	if caravan != null and hud != null:
		caravan.changed.connect(_refresh_caravan_hud)
		caravan.carried_changed.connect(func(_carried: int) -> void: _refresh_caravan_hud())
	if profile != null:
		loadout.fused.connect(func(fusion_id: StringName) -> void: profile.discover_recipe(fusion_id))
	_refresh_weapon_hud()
	# Il primo Cassone ha gia avvisato (`changed` nel _ready della carovana, prima del nostro).
	_refresh_caravan_hud()


## Armi comuni sbloccate in Officina (D-092, par. 6.2); senza profilo nessuna.
func _unlocked_weapons() -> Array[StringName]:
	var profile := get_node_or_null(^"/root/PlayerProfile") as PlayerProfileService
	return profile.unlocked_weapons() if profile != null else ([] as Array[StringName])


## Moduli delle carte "Nuova macchina" (D-093): nel piano A quelli del catalogo che hanno uno
## script (come le armi, i moduli ancora inerti non si offrono); il piano C filtrera col profilo.
func _available_modules() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in MachineCatalog.MODULES:
		if Caravan.module_script_for(id) != MachineModule:
			out.append(id)
	return out


## Striscia delle armi del HUD (D-092): slot ricostruiti quando il loadout cambia, ricarica
## degli attivi a ogni passo (la striscia ridisegna solo se cambia).
func _refresh_weapon_hud() -> void:
	if hud == null or loadout == null:
		return
	hud.set_weapons(loadout.autos().map(_weapon_entry), loadout.actives().map(_weapon_entry))


func _weapon_entry(w: Weapon) -> Dictionary:
	var letters := ""
	for at in WeaponCatalog.BRANCH_LEVELS:
		if w.branches.has(at):
			letters += String(w.branches[at]).to_upper()
	var shown := w.fusion_id if w.fusion_id != &"" else w.weapon_id
	var entry := {icon = WeaponCatalog.find(shown).get(&"icon", &"nail"), level = w.level, branches = letters}
	if w is ActiveWeapon:
		entry.cooldown = (w as ActiveWeapon).cooldown_left / maxf((w as ActiveWeapon).cooldown_total(), 0.01)
	return entry


func _tick_weapon_hud() -> void:
	if hud == null or loadout == null:
		return
	var values: Array[float] = []
	for active in loadout.actives():
		values.append(active.cooldown_left / maxf(active.cooldown_total(), 0.01))
	hud.set_weapon_cooldowns(values)


## Striscia della carovana (D-093): caselle rifatte quando la carovana cambia (macchine, stato,
## capienza, moduli e taglia dopo fusione o sgancio) o cambiano i rottami; vita, stato e
## riparazione li segue `_tick_caravan_hud`.
func _refresh_caravan_hud() -> void:
	if hud == null or caravan == null:
		return
	var machines := caravan.machines
	var repairing := caravan.repairing_machine()
	_caravan_health_shown.resize(machines.size())
	_caravan_state_shown.resize(machines.size())
	_caravan_repair_shown.resize(machines.size())
	var entries: Array[Dictionary] = []
	for i in machines.size():
		var machine := machines[i]
		var module := MachineCatalog.find(machine.primary_module_id())
		var repair := caravan.repair_progress() if machine == repairing else 0.0
		# Un colore per ogni modulo oltre il primo (scelta 11 di D-093).
		var extra: Array[Color] = []
		for k in range(1, machine.modules.size()):
			extra.append(MachineCatalog.find(machine.modules[k].module_id).get(&"color", UiPalette.BORDER))
		entries.append({icon = module.get(&"icon", &"crate"), color = module.get(&"color", UiPalette.BORDER),
			health = machine.health, max_health = machine.max_health, state = machine.state, repair = repair,
			size = machine.size, extra = extra})
		_caravan_health_shown[i] = machine.health
		_caravan_state_shown[i] = machine.state
		_caravan_repair_shown[i] = repair
	hud.set_caravan(entries, caravan.carried, caravan.capacity)


## A ogni passo: tasto Interagisci (Ripara, Riprendi o Banco, la striscia ne accende uno); le
## caselle si rifanno solo se vita, stato o riparazione di una macchina sono cambiati (i rottami
## arrivano coi segnali).
func _tick_caravan_hud() -> void:
	if hud == null or caravan == null:
		return
	var repair_shown := caravan.repair_target() != null
	hud.set_caravan_prompt(repair_shown, fusion_pad != null and fusion_pad.bench_available(), relic_available())
	var machines := caravan.machines
	if machines.size() != _caravan_health_shown.size():
		_refresh_caravan_hud()
		return
	var repairing := caravan.repairing_machine()
	var progress := caravan.repair_progress()
	for i in machines.size():
		var machine := machines[i]
		var repair := progress if machine == repairing else 0.0
		if machine.health != _caravan_health_shown[i] or machine.state != _caravan_state_shown[i] \
				or repair != _caravan_repair_shown[i]:
			_refresh_caravan_hud()
			return


## Mira commutabile (D-089): la scelta del giocatore resta nelle impostazioni.
func _setup_aim_mode() -> void:
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	if not player.aim_mode_changed.is_connected(_on_aim_mode_changed):
		player.aim_mode_changed.connect(_on_aim_mode_changed)
	player.set_aim_mode(PlayerCharacter.AimMode.MANUAL if settings != null and settings.manual_aim else PlayerCharacter.AimMode.AUTO)
	# Cambiata dalle Impostazioni in pausa: vale subito.
	if settings != null and not settings.changed.is_connected(_on_settings_aim):
		settings.changed.connect(_on_settings_aim)


func _on_settings_aim() -> void:
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	if settings != null and weapon != null and settings.manual_aim != weapon.manual_aim:
		player.set_aim_mode(PlayerCharacter.AimMode.MANUAL if settings.manual_aim else PlayerCharacter.AimMode.AUTO)


func _on_aim_mode_changed(mode: int) -> void:
	weapon.manual_aim = mode == PlayerCharacter.AimMode.MANUAL
	if loadout != null:
		loadout.set_manual_aim(weapon.manual_aim)
	if hud != null:
		hud.set_aim_mode(weapon.manual_aim)
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	if settings != null and settings.manual_aim != weapon.manual_aim:
		settings.set_manual_aim(weapon.manual_aim)


## Colpo al giocatore (O-01): i nemici attorno arretrano e lo schermo lampeggia di rosso.
func _on_player_damaged(_amount: int) -> void:
	if director != null:
		director.shove_from(player.global_position, tuning.hit_shove_radius, tuning.hit_shove_speed)
	if hud != null:
		hud.flash_damage()


func _on_player_died() -> void:
	_end_level(false)


static func _boss_call_from_command_line(default_seconds: float) -> float:
	return RunLaunchOptions.boss_call_seconds(default_seconds)


static func _seed_from_command_line() -> int:
	return RunLaunchOptions.run_seed()


# --- Distanza della camera (D-078) ------------------------------------------------

## Oltre questa distanza un punto e fuori vista con la distanza di camera corrente.
func marker_min_distance() -> float:
	return MARKER_MIN_DISTANCE * marker_scale


## Il rig della camera e fratello di questo nodo nelle scene dei livelli.
func _camera_rig() -> IsometricCameraRig:
	var parent := get_parent()
	return parent.get_node_or_null(^"CameraRig") as IsometricCameraRig if parent != null else null


func _setup_camera_distance() -> void:
	var rig := _camera_rig()
	if rig == null:
		return
	rig.distance_changed.connect(_on_camera_distance_changed)
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	rig.set_distance_index(settings.camera_distance if settings != null else IsometricCameraRig.DEFAULT_DISTANCE_INDEX, true)
	_on_camera_distance_changed(rig.distance_index, rig.target_arm_m())
	if settings != null and not settings.changed.is_connected(_on_settings_changed_camera):
		settings.changed.connect(_on_settings_changed_camera)


## L'anello di comparsa segue la finestra visibile: a 20 m di braccio si allarga di 4/3.
func _on_camera_distance_changed(index: int, arm_m: float) -> void:
	director.ring_scale = arm_m / 15.0
	marker_scale = arm_m / 15.0
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	if settings != null and settings.camera_distance != index:
		settings.set_camera_distance(index)


func _on_settings_changed_camera() -> void:
	var settings := get_node_or_null(^"/root/GameSettings") as GameSettingsService
	var rig := _camera_rig()
	if settings != null and rig != null and rig.distance_index != settings.camera_distance:
		rig.set_distance_index(settings.camera_distance)
