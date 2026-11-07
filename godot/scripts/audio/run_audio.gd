class_name RunAudio
extends Node
## Effetti sonori della run. Nodo autonomo: si collega da solo ai segnali dei
## sistemi di gioco e suona gli stream di SfxLibrary su un piccolo gruppo di
## AudioStreamPlayer non posizionali (la camera segue il giocatore) sul bus SFX.
## I suoni frequenti sono bassi, con intonazione leggermente casuale e una
## distanza minima fra due ripetizioni, per non stancare.

const SFX_BUS := &"SFX"
const POOL_SIZE := 10
## Per id: volume di base in dB, variazione casuale di intonazione (+/-),
## intervallo minimo in secondi fra due riproduzioni dello stesso id.
const DEFAULT_SETTINGS: Array[float] = [-6.0, 0.0, 0.03]
const SOUND_SETTINGS: Dictionary[StringName, Array] = {
	&"nail_shot": [-16.0, 0.08, 0.07],
	&"enemy_death": [-13.0, 0.12, 0.06],
	&"xp_pickup": [-15.0, 0.06, 0.05],
	&"scrap_pickup": [-11.0, 0.06, 0.08],
	&"scrap_spend": [-11.0, 0.05, 0.05],
	&"terrain_dig": [-8.0, 0.08, 0.05],
	&"terrain_raise": [-8.0, 0.05, 0.05],
	&"tool_reject": [-10.0, 0.0, 0.15],
	&"dash": [-10.0, 0.05, 0.05],
	&"player_hurt": [-5.0, 0.04, 0.1],
	&"player_death": [-4.0, 0.0, 0.5],
	&"level_up": [-6.0, 0.0, 0.2],
	&"upgrade_chosen": [-7.0, 0.0, 0.1],
	&"boss_warning": [-4.0, 0.0, 0.5],
	&"boss_spawn": [-3.0, 0.0, 0.5],
	&"boss_demolish": [-7.0, 0.06, 0.15],
	&"boss_barricade": [-7.0, 0.05, 0.15],
	&"carrier_pickup": [-10.0, 0.05, 0.08],
	&"victory": [-4.0, 0.0, 0.5],
	&"dusk": [-6.0, 0.0, 1.0],
	&"nightfall": [-4.0, 0.0, 1.0],
	&"train_horn": [-4.0, 0.0, 0.8],
	&"driller_charge": [-5.0, 0.0, 0.6],
	&"quake_rumble": [-4.0, 0.0, 1.2],
	# Armi (piano 5): le frequenti piu basse e distanziate.
	&"w_seismic_stake_fire": [-9.0, 0.05, 0.20],
	&"w_seismic_stake_hit": [-8.0, 0.05, 0.20],
	&"w_scrap_launcher_fire": [-12.0, 0.08, 0.10],
	&"w_scrap_launcher_hit": [-9.0, 0.08, 0.10],
	&"w_dig_charge_fire": [-11.0, 0.05, 0.15],
	&"w_dig_charge_hit": [-6.0, 0.06, 0.12],
	&"w_welder_fire": [-14.0, 0.10, 0.12],
	&"w_crane_magnet_fire": [-9.0, 0.00, 0.30],
	&"w_crane_magnet_hit": [-8.0, 0.05, 0.30],
	&"w_scythe_hit": [-16.0, 0.10, 0.10],
	&"w_bramble_fire": [-11.0, 0.05, 0.20],
	&"w_bramble_hit": [-9.0, 0.05, 0.20],
	&"w_site_blade_fire": [-14.0, 0.08, 0.10],
	&"w_site_blade_hit": [-15.0, 0.10, 0.08],
	&"w_jackhammer_fire": [-11.0, 0.06, 0.15],
	&"w_ram_fire": [-9.0, 0.03, 0.30],
	&"w_ram_hit": [-7.0, 0.03, 0.30],
	&"w_cement_mixer_fire": [-10.0, 0.04, 0.25],
	&"w_cement_mixer_hit": [-10.0, 0.05, 0.20],
	# Interfaccia (D-081): li suona UiFx, qui restano solo per il catalogo.
	&"ui_move": [-14.0, 0.03, 0.03],
	&"ui_confirm": [-10.0, 0.0, 0.05],
	&"ui_back": [-10.0, 0.0, 0.05],
	&"ui_open": [-9.0, 0.0, 0.1],
}
## Suoni che un player occupato non cede mai a un altro (R-36): sono rari e
## portano un'informazione che il giocatore deve sentire fino in fondo.
## Suoni delle armi (piano 5): `w_<arma>_<kind>`; senza campione si ripiega su questi.
const WEAPON_FALLBACK: Dictionary[StringName, StringName] = {&"fire": &"nail_shot", &"hit": &"terrain_raise"}
const PROTECTED_IDS: Array[StringName] = [&"boss_warning", &"victory", &"train_horn", &"quake_rumble"]

@export var player: PlayerCharacter
@export var weapon: AutoWeapon
@export var director: EnemyDirector
@export var xp_field: XpField
@export var caravan: Caravan
@export var level_up_menu: LevelUpMenu
@export var run: ArenaRun
@export var workshop: WorkshopPanel

## Riproduzioni andate a buon fine per id (per i test: in headless non si sente nulla).
var play_counts: Dictionary[StringName, int] = {}
## Ultimo id riprodotto.
var last_played: StringName = &""
## Dice se un player del gruppo e ancora occupato. In headless il driver fittizio
## non fa mai finire una riproduzione: i test lo sostituiscono con player finti (P-08).
var is_busy: Callable = func(stream_player: AudioStreamPlayer) -> bool: return stream_player.playing

var _streams: Dictionary[StringName, AudioStream] = {}
var _players: Array[AudioStreamPlayer] = []
## Per player: id dell'ultimo suono assegnato.
var _player_ids: Array[StringName] = []
var _next_player := 0
var _clock := 0.0
var _next_allowed: Dictionary[StringName, float] = {}
var _rng := RandomNumberGenerator.new()
var _last_health := 0
var _last_carried := 0
@export var terrain_field: TerrainField
var _sculpt_sound_left := 0.0


func _ready() -> void:
	# Vittoria, sconfitta e level-up suonano a gioco fermo.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Cache gia pronta (o in arrivo dal thread avviato dal menu); altrimenti sintesi sincrona.
	_streams = SfxLibrary.build_all()
	var bus := SFX_BUS if AudioServer.get_bus_index(SFX_BUS) >= 0 else &"Master"
	for i in POOL_SIZE:
		var stream_player := AudioStreamPlayer.new()
		stream_player.bus = bus
		add_child(stream_player)
		_players.append(stream_player)
		_player_ids.append(&"")
	_connect_signals()
	if terrain_field != null:
		terrain_field.player_sculpted.connect(_on_player_sculpted)


func _process(delta: float) -> void:
	_clock += delta
	_sculpt_sound_left = maxf(_sculpt_sound_left - delta, 0.0)


## Riproduce il suono [param id]; [param volume_db] si somma al volume di base.
## Restituisce false se l'id non esiste o se e stato appena riprodotto.
func play(id: StringName, volume_db := 0.0) -> bool:
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		return false
	if _clock < _next_allowed.get(id, 0.0):
		return false
	var settings: Array = SOUND_SETTINGS.get(id, DEFAULT_SETTINGS)
	var base_db: float = settings[0]
	var jitter: float = settings[1]
	var min_interval: float = settings[2]
	var index := _take_player()
	if index < 0:
		return false
	_next_allowed[id] = _clock + min_interval
	_player_ids[index] = id
	var stream_player := _players[index]
	stream_player.stream = stream
	stream_player.volume_db = base_db + volume_db
	stream_player.pitch_scale = 1.0 + _rng.randf_range(-jitter, jitter)
	stream_player.play()
	play_counts[id] = play_counts.get(id, 0) + 1
	last_played = id
	return true


## Quante volte [param id] e stato riprodotto da quando il nodo esiste.
func play_count(id: StringName) -> int:
	return play_counts.get(id, 0)


func has_sound(id: StringName) -> bool:
	return _streams.has(id)


func stream_for(id: StringName) -> AudioStream:
	return _streams.get(id)


func sound_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_streams.keys())
	return ids


## Indice del primo player libero a partire dall'ultimo usato; se sono tutti
## occupati ruba il piu vecchio che non stia suonando un id protetto. -1 se
## restano solo suoni protetti: meglio perdere un effetto che tagliarli.
func _take_player() -> int:
	var count := _players.size()
	for i in count:
		var index := (_next_player + i) % count
		if not is_busy.call(_players[index]):
			_next_player = (index + 1) % count
			return index
	for i in count:
		var index := (_next_player + i) % count
		if _player_ids[index] not in PROTECTED_IDS:
			_next_player = (index + 1) % count
			return index
	return -1


func _connect_signals() -> void:
	if player != null:
		_last_health = player.health
		player.health_changed.connect(_on_health_changed)
		player.died.connect(play.bind(&"player_death", 0.0))
		player.dash_started.connect(play.bind(&"dash", 0.0))
		player.terrain_tool_rejected.connect(play.bind(&"tool_reject", 0.0))
	if weapon != null:
		weapon.fired.connect(_on_weapon_fired)
	# Il loadout nasce nel _ready della regia, che puo venire dopo il nostro.
	_connect_loadout.call_deferred()
	if director != null:
		director.enemy_killed.connect(_on_enemy_killed)
	if xp_field != null:
		xp_field.collected.connect(_on_xp_collected)
	if caravan != null:
		_last_carried = caravan.carried
		caravan.carried_changed.connect(_on_carried_changed)
	if level_up_menu != null:
		level_up_menu.opened.connect(play.bind(&"level_up", 0.0))
		level_up_menu.chosen.connect(_on_upgrade_chosen)
	if workshop != null:
		workshop.purchased.connect(func(_id: StringName) -> void: play(&"upgrade_chosen"))
		workshop.rejected.connect(func(_id: StringName) -> void: play(&"tool_reject"))
	if run != null:
		run.boss_called.connect(_on_boss_called)
		run.boss_spawned.connect(_on_boss_spawned)
		run.level_completed.connect(play.bind(&"victory", 0.0))
		run.night_phase_changed.connect(_on_night_phase)
		if run.lamp_field != null:
			run.lamp_field.lamp_placed.connect(func(_at: Vector3) -> void: play(&"terrain_raise"))
		if run.train_event != null:
			# Fischio al preavviso e all'ingresso; un tonfo per ogni cosa travolta.
			run.train_event.train_warned.connect(func(_direction: Vector3, _seconds: float) -> void: play(&"train_horn"))
			run.train_event.train_passing.connect(func(_direction: Vector3) -> void: play(&"train_horn"))
			run.train_event.train_hit.connect(func(_what: StringName) -> void: play(&"boss_demolish"))
		if run.extraction_pad != null:
			run.extraction_pad.extraction_started.connect(func() -> void: play(&"boss_warning"))
		if run.quake_event != null:
			run.quake_event.quake_warned.connect(func(_direction: Vector3, _seconds: float) -> void: play(&"quake_rumble"))
			run.quake_event.quake_started.connect(func(_center: Vector3) -> void: play(&"quake_rumble"))
			run.quake_event.quake_hit.connect(func(what: StringName) -> void:
				play(&"terrain_raise" if what == &"cell" else &"boss_demolish"))


func _on_health_changed(health: int, _max_health: int) -> void:
	# Il colpo mortale lo copre player_death.
	if health < _last_health and health > 0:
		play(&"player_hurt")
	_last_health = health


func _connect_loadout() -> void:
	if run != null and run.loadout != null and not run.loadout.weapon_sound.is_connected(_on_loadout_weapon_sound):
		run.loadout.weapon_sound.connect(_on_loadout_weapon_sound)


## Id del campione per il suono [param kind] dell'arma [param id], ripiego compreso.
func weapon_sound_id(id: StringName, kind: StringName) -> StringName:
	var wanted := StringName("w_%s_%s" % [id, kind])
	return wanted if _streams.has(wanted) else WEAPON_FALLBACK.get(kind, &"nail_shot")


func _on_loadout_weapon_sound(id: StringName, kind: StringName) -> void:
	if not is_inside_tree() or get_tree().paused:
		return
	play(weapon_sound_id(id, kind))


func _on_weapon_fired(_count: int) -> void:
	play(&"nail_shot")


func _on_enemy_killed(_world_position: Vector3, _total: int) -> void:
	play(&"enemy_death")


func _on_player_sculpted(_center: Vector3, _radius: float, volume: float, mode: int) -> void:
	if _sculpt_sound_left > 0.0:
		return
	_sculpt_sound_left = 0.25
	play(&"terrain_raise" if mode == TerrainField.ToolMode.RAISE else &"terrain_dig", -6.0 + 6.0 * clampf(absf(volume) / 0.2, 0.0, 1.0))


func _on_xp_collected(_amount: int) -> void:
	play(&"xp_pickup")


func _on_carried_changed(carried: int) -> void:
	if carried > _last_carried:
		play(&"scrap_pickup")
	elif carried < _last_carried:
		play(&"scrap_spend")
	_last_carried = carried


func _on_upgrade_chosen(_id: StringName) -> void:
	play(&"upgrade_chosen")


func _on_boss_called(_direction: Vector3) -> void:
	play(&"boss_warning")


## Il Demolitore entra in campo: da qui si sentono muri smontati, rottami
## raccolti dalla sua squadra e barricate che si alzano (D-045).
func _on_night_phase(phase: DayNightCycle.Phase) -> void:
	match phase:
		DayNightCycle.Phase.DUSK:
			play(&"dusk")
		DayNightCycle.Phase.NIGHT:
			play(&"nightfall")


func _on_boss_spawned(boss: Enemy) -> void:
	play(&"boss_spawn")
	if boss is Demolisher:
		var demolisher := boss as Demolisher
		demolisher.wall_demolished.connect(func(_at: Vector3) -> void: play(&"boss_demolish"))
		demolisher.scrap_taken.connect(play.bind(&"carrier_pickup", 0.0))
		demolisher.barricade_built.connect(func(_at: Vector3) -> void: play(&"boss_barricade"))
	elif boss is Driller:
		# La Trivella (D-066): carica annunciata, terrapieno sfondato, stordimento.
		var driller := boss as Driller
		driller.charge_started.connect(func(_target: Vector3) -> void: play(&"driller_charge"))
		driller.wall_broken.connect(func(_at: Vector3) -> void: play(&"boss_demolish"))
		driller.stunned.connect(func(_seconds: float) -> void: play(&"boss_barricade"))
