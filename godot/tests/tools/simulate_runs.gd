extends SceneTree
## Simulatore di run complete (non e una suite): gioca `arena_run.tscn` vero, senza
## finestra, con un bot al posto del giocatore, per misurare quando si muore, se il
## boss viene raggiunto e quanti rottami escono dal livello. Serve a bilanciare i
## prezzi dell'Officina prima del playtest; un bot non e un giocatore.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/tools/simulate_runs.gd -- --bots=kiter --seeds=1-10
## Opzioni (dopo `--`):
##   --bots=passive,novice,kiter,scrapper   bot da provare (default: tutti)
##   --seeds=1-10 | --seeds=3,7,9    semi delle run (default 1-5); `--seed=N` = una sola, mai
##                                   insieme a `--seeds=`: ArenaRun legge prima `--seed=`
##                                   (RunLaunchOptions) e casse, relitti ed eventi seguirebbero quello
##   --profile=base_health:1,cargo:2 upgrade permanenti gia comprati (profilo in memoria)
##   --max-seconds=1500              oltre questo tempo di gioco la run e interrotta
##   --hz=60                         passi fisici al secondo (il gioco ne usa 120)
##   --boss-at=N                     letto da ArenaRun: anticipa il boss
##   --night-at=N                    letto da ArenaRun: anticipa il tramonto (0 = niente notte)
##   --level=railway                 livello da simulare (LevelCatalog; default il quartiere)
##   Lo scrapper, di notte, piazza un lampione dove sta (3 rottami, max 6): riga `lamps=`.
##   --caravan=turret,drill,...      macchine in piu alla partenza (un modulo ciascuna, fino al
##                                   limite della carovana): serve a provare la regola della fusione
## Con `--fixed-fps 60` e 60 passi fisici al secondo una run e ripetibile: stesso
## seme e stesso bot danno la stessa riga (il seme arriva ad ArenaRun dalla variabile
## `PROTOTYPE01_SEED`, impostata prima di istanziare la scena: casse, relitti, treno,
## terremoto ed eventi del mondo lo seguono). Senza finestra gira gia alla massima
## velocita della CPU (una run fino al boss costa 2-5 minuti): per fare prima si
## lanciano piu processi in parallelo, uno per bot o per gruppo di semi. Piu passi
## fisici per frame (`--fixed-fps 10`) non accelerano in modo misurabile e possono
## dare un risultato diverso: un nemico che striscia contro un muro riceve dalla
## fisica del motore una posizione diversa di frazioni di millimetro (verificato con
## `--trace`), e da li la run si separa. Non usarli per confronti.
##   --trace=N                       stampa lo stato ogni N secondi di gioco
## Bot:
##   passive   fermo nel cortile di partenza;
##   novice    vede solo i nemici vicini, reagisce ogni mezzo secondo, non cerca
##             l'esperienza e prende sempre la prima carta (anche una Nuova macchina);
##   kiter     si allontana dai nemici e raccoglie esperienza, non tocca il terreno;
##   scrapper  come kiter, e in piu scava quando puo per riempire il cassone e
##             prende presto la carta del cassone. Sul rilievo continuo (D-085) scava
##             la vena piu vicina (entro 70 m) tenendo il pennello finche ha rottami e,
##             dopo 60 s di livello, alza una volta un argine di 3 s dove sta. Prima delle
##             vene, anche col cassone pieno, scava il relitto sepolto piu vicino (D-093)
##             se e a portata o ci puo andare (campo libero); altrimenti scava le vene. Lo
##             lascia per la run se in 20 s il suolo sul relitto non scende di 5 cm (a
##             portata) o il bot non gli si avvicina di 0,5 m (fuori portata): riga
##             `PROTOTYPE01_SIM_WRECK_SKIP`. Fuori dal campo di percorso lo dimentica.
## Carovana (D-093): tutti i bot tranne passive riparano. Con una macchina guasta e nessun
## nemico entro 3,5 m vanno alla guasta piu vicina e, entro 1,5 m, tengono Interagisci
## finche non e riparata, anche coi nemici addosso; si staccano oltre 1,8 m. Nessuna soglia
## di rottami (scelta 3 del piano A: sotto i 2 la riparazione e gratis e dura 4,5 s). Fra le
## carte, "Nuova macchina" viene subito dopo le armi (kiter e scrapper; il novice prende la prima).
## Fusione (D-093, piano B): con la pedana aperta, la carovana al limite dei moduli, piu di una
## macchina, nessuna guasta, nei Cassoni funzionanti i rottami per fondere tutto nel capofila e
## nessun nemico entro 3,5 m, i bot tranne passive vanno al centro della pedana e, sul quadrato,
## premono Interagisci; col banco aperto fondono una macchina per passo nel capofila e lo chiudono.
## Viene prima della riparazione: con una guasta la regola non vale e la riparazione resta com'era.
## Col boss in campo i bot che si muovono gli girano attorno a portata di chiodatrice.
## Movimento e mira passano dalle azioni di input (`Input.action_press`), il tool
## da un `InputEventAction`; le carte del level-up da `LevelUpMenu.press`.
## Marker: PROTOTYPE01_SIM (una riga per run; con `machines` = macchine a fine run, Cassone
## compreso, `repairs` = riparazioni finite dal bot, `repairs_free` = quelle gratis, `wrecks` =
## relitti aperti da chiunque: il novice non scava, per lui sono armi o boss; `fusions` = fusioni
## fatte dal bot al banco, `colossus` = 1 se una sua fusione ha dato un Colosso),
## PROTOTYPE01_SIM_SUMMARY, PROTOTYPE01_SIM_AFFORD (run necessarie per ogni livello
## dell'Officina), PROTOTYPE01_SIM_BRUSH (ogni pennellata del bot sul rilievo: tempo, modo,
## punto), PROTOTYPE01_SIM_WRECK_SKIP (relitto lasciato dallo scrapper).

## Scena del livello scelto con `--level=` (default: il primo del catalogo).
var _scene_path := LevelCatalog.scene_of(LevelCatalog.first())

## Con `--trace=N` stampa lo stato ogni N secondi di gioco (PROTOTYPE01_SIM_TRACE):
## serve a trovare dove due run che dovrebbero essere uguali si separano.
var _trace_every := 0.0
var _trace_next := 0.0
const BOT_NAMES: Array[StringName] = [&"passive", &"novice", &"kiter", &"scrapper"]
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back"]
const AIM_ACTIONS: Array[StringName] = [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]
const DIRECTIONS := 16
## Metri davanti al bot a cui si valuta il pericolo di una direzione.
const LOOKAHEAD := 3.0
## Distanza dal boss che i bot cercano di tenere: dentro la portata della chiodatrice.
const BOSS_ORBIT_DISTANCE := 5.5
const BOSS_TOO_CLOSE := 3.0
## Priorita fissa delle carte dopo le armi (D-092: carte arma e trasformazioni vincono
## sempre) e dopo le carte "Nuova macchina" (D-093; riconosciute dal nome, il menu non
## espone gli id): prima il danno, poi la vita, poi il resto. Torretta veloce e Calamita
## potente compaiono solo con quel modulo in carovana.
const CARD_PRIORITY: Array[StringName] = [
	&"turret_rate", &"patch", &"boots",
	&"magnet_range", &"reach", &"companion_cargo", &"dig_blast", &"spiked_wall",
]
## Lo scrapper vuole il cassone grande subito dopo le armi e le macchine.
const CARD_PRIORITY_SCRAPPER: Array[StringName] = [
	&"companion_cargo", &"turret_rate", &"patch",
	&"boots", &"magnet_range", &"reach", &"dig_blast", &"spiked_wall",
]
## Secondi fra due decisioni, raggio entro cui vede i nemici, peso dell'esperienza.
const BOT_PARAMS := {
	&"passive": {interval = 1.0, awareness = 0.0, xp_weight = 0.0, digs = false, first_card = true},
	&"novice": {interval = 0.5, awareness = 6.0, xp_weight = 0.0, digs = false, first_card = true},
	&"kiter": {interval = 0.25, awareness = 12.0, xp_weight = 0.12, digs = false, first_card = false},
	&"scrapper": {interval = 0.25, awareness = 12.0, xp_weight = 0.12, digs = true, first_card = false},
}

var _bots: Array[StringName] = []
var _seeds: Array[int] = []
var _profile_levels: Dictionary[StringName, int] = {}
var _max_seconds := 1500.0
var _hz := 60
## Moduli delle macchine aggiunte alla partenza (`--caravan=`).
var _extra_machines: Array[StringName] = []

var _scene: Node3D
var _run: ArenaRun
var _player: PlayerCharacter
var _caravan: Caravan
var _field: TerrainField
## Vena puntata dal bot (centro XZ) e argine gia alzato in questa run.
var _vein_target := Vector3.INF
var _rampart_left := 0.0
var _rampart_done := false
## Raggio entro cui il bot cerca una vena, distanza minima dai nemici per scolpire.
## I depositi del quartiere stanno a 50 m e oltre dal cortile: il bot ci cammina solo
## quando nessun nemico e entro VEIN_WALK_SAFE_M.
const VEIN_SEARCH_M := 70.0
const VEIN_WALK_SAFE_M := 8.0
const BRUSH_SAFE_M := 3.5
const RAMPART_AT_SECONDS := 60.0
const RAMPART_HOLD_SECONDS := 3.0
## Riparazione: il bot si ferma entro REPAIR_STOP_M dalla guasta e tiene Interagisci finche
## resta entro REPAIR_HOLD_M (`repair_range` 2 m meno 0,2 di margine).
const REPAIR_STOP_M := 1.5
const REPAIR_HOLD_M := 1.8
## Fusione: secondi di attesa dopo un banco chiuso senza fusioni (regola vera ma `fuse` rifiutato),
## cosi il bot non riapre il banco a ogni passo.
const FUSION_RETRY_S := 5.0
## Un relitto a portata il cui suolo non scende di WRECK_PROGRESS_M in WRECK_GIVE_UP_S
## secondi (punto protetto, bot troppo vicino), o fuori portata senza che il bot gli si
## avvicini di WRECK_APPROACH_M in WRECK_GIVE_UP_S secondi, si lascia per il resto della run.
const WRECK_GIVE_UP_S := 20.0
const WRECK_PROGRESS_M := 0.05
const WRECK_APPROACH_M := 0.5
## Esito di `_dig_toward`: nulla (lontano, campo non libero), in marcia verso il bersaglio, a portata.
enum Dig { IDLE, WALKING, IN_REACH }
## Inizio del nome delle carte macchina: il menu non espone gli id.
const MACHINE_CARD_NAME := MachineOffers.NAME_PREFIX
var _director: EnemyDirector
var _path: PathField
var _scrap: ScrapField
var _xp: XpField
var _menu: LevelUpMenu

var _bot: StringName = &"passive"
var _params: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _decision_left := 0.0
## Decisioni del bot prese al buio (notte, fuori dalle luci).
var _dark_samples := 0
var _lamps_bought := 0
var _move := Vector2.ZERO
var _aim := Vector2.ZERO
var _dig_cooldown := 0.0
## Armi attive usate nella run (D-092): il bot le usa appena cariche con un nemico in portata.
var _actives_used := 0
var _stuck_seconds := 0.0
var _escape_left := 0.0
var _digs := 0
var _hits := 0
## Riparazione (D-093): macchina guasta puntata, Interagisci tenuto, e se il prossimo fine
## riparazione e del bot (la riparazione in corso e la sua, quasi finita) e gratis.
var _repair_target: Machine
var _repair_holding := false
var _repair_mine := false
var _repair_free := false
var _repairs := 0
var _repairs_free := 0
## Fusione (piano B): fusioni fatte, Colosso ottenuto, fusioni di questo banco, attesa dopo un rifiuto.
var _fusions := 0
var _colossus := false
var _bench_fusions := 0
var _fusion_wait := 0.0
## Relitti aperti nella run (da chiunque), relitto puntato, quelli lasciati e lo scavo a portata
## senza progresso: quota piu bassa vista sul relitto e secondi da allora.
var _wrecks := 0
var _wreck_index := -1
var _wrecks_skipped: Array[int] = []
var _wreck_best := INF
var _wreck_best_distance := INF
var _wreck_stall := 0.0
## Stato all'arrivo del boss: vita e livello (-1 se non e mai arrivato).
var _health_at_boss := -1
var _level_at_boss := -1
var _results: Array[Dictionary] = []


func _initialize() -> void:
	_parse_arguments()
	Engine.physics_ticks_per_second = _hz
	var started := Time.get_ticks_msec()
	for bot in _bots:
		for run_seed in _seeds:
			_results.append(await _simulate(bot, run_seed))
	for bot in _bots:
		_print_summary(bot)
	print("PROTOTYPE01_SIM_DONE runs=%d wall_s=%.1f" % [_results.size(), (Time.get_ticks_msec() - started) / 1000.0])
	quit()


func _parse_arguments() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bots="):
			for bot_name in arg.trim_prefix("--bots=").split(",", false):
				if BOT_NAMES.has(StringName(bot_name)):
					_bots.append(StringName(bot_name))
		elif arg.begins_with("--seeds="):
			_seeds = _parse_seeds(arg.trim_prefix("--seeds="))
		elif arg.begins_with("--seed=") and _seeds.is_empty():
			_seeds = [arg.trim_prefix("--seed=").to_int()]
		elif arg.begins_with("--profile="):
			for pair in arg.trim_prefix("--profile=").split(",", false):
				var parts := pair.split(":")
				var id := StringName(parts[0])
				var level := parts[1].to_int() if parts.size() > 1 else 1
				_profile_levels[id] = clampi(level, 0, PermanentCatalog.max_level(id))
		elif arg.begins_with("--max-seconds="):
			_max_seconds = arg.trim_prefix("--max-seconds=").to_float()
		elif arg.begins_with("--trace="):
			_trace_every = arg.trim_prefix("--trace=").to_float()
		elif arg.begins_with("--level="):
			var level := StringName(arg.trim_prefix("--level="))
			if LevelCatalog.is_playable(level):
				_scene_path = LevelCatalog.scene_of(level)
		elif arg.begins_with("--hz="):
			_hz = maxi(arg.trim_prefix("--hz=").to_int(), 30)
		elif arg.begins_with("--caravan="):
			for module_id in arg.trim_prefix("--caravan=").split(",", false):
				if not MachineCatalog.find(StringName(module_id)).is_empty():
					_extra_machines.append(StringName(module_id))
				else:
					push_warning("simulate_runs: modulo sconosciuto in --caravan: %s" % module_id)
	if _bots.is_empty():
		_bots = BOT_NAMES.duplicate()
	if _seeds.is_empty():
		_seeds = [1, 2, 3, 4, 5]


static func _parse_seeds(text: String) -> Array[int]:
	var seeds: Array[int] = []
	for part in text.split(",", false):
		var bounds := part.split("-", false)
		if bounds.size() == 2:
			for value in range(bounds[0].to_int(), bounds[1].to_int() + 1):
				seeds.append(value)
		else:
			seeds.append(part.to_int())
	return seeds


# --- Una run -----------------------------------------------------------------------

func _simulate(bot: StringName, run_seed: int) -> Dictionary:
	var wall_start := Time.get_ticks_msec()
	_bot = bot
	_params = BOT_PARAMS[bot]
	# Sotto --script il profilo e in memoria: lo si riporta allo stato richiesto.
	var profile := root.get_node("PlayerProfile") as PlayerProfileService
	profile.reset()
	for id: StringName in _profile_levels:
		if _profile_levels[id] > 0:
			profile.levels[id] = _profile_levels[id]

	# Il seme arriva al `_ready` di ArenaRun da qui (RunLaunchOptions.run_seed), sopra a quello
	# del gate: casse (+5), relitti (+6, +7), treno (+3), terremoto (+4), eventi (+5).
	OS.set_environment("PROTOTYPE01_SEED", str(run_seed))
	_scene = (load(_scene_path) as PackedScene).instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	# I bot non sanno tenere la piazzola di estrazione (D-076): vittoria alla morte del boss.
	_run.extraction_pad = null
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_field = _scene.get_node_or_null(^"TerrainField")
	_director = _scene.get_node(^"EnemyDirector")
	_path = _scene.get_node(^"PathField")
	_scrap = _scene.get_node(^"ScrapField")
	_xp = _scene.get_node(^"XpField")
	_menu = _scene.get_node(^"LevelUpMenu")
	# Il seme e gia arrivato al `_ready` della scena (primo frame) dalla variabile d'ambiente
	# impostata prima di istanziarla; qui i generatori tornano al seme dopo il primo frame,
	# come prima (deterministico).
	await physics_frame
	if _run.wrecks != null:
		_run.wrecks.cache_opened.connect(func(_at: Vector3) -> void: _wrecks += 1)
	_run.run_seed = run_seed
	_run.progression.setup(run_seed)
	_director.rng.seed = run_seed + 1
	_run._boss_rng.seed = run_seed + 2
	_rng.seed = run_seed + 3
	_decision_left = 0.0
	_move = Vector2.ZERO
	_aim = Vector2.ZERO
	_dig_cooldown = 0.0
	_vein_target = Vector3.INF
	_rampart_left = 0.0
	_rampart_done = false
	_stuck_seconds = 0.0
	_escape_left = 0.0
	_digs = 0
	_actives_used = 0
	_repair_target = null
	_repair_holding = false
	_repair_mine = false
	_repair_free = false
	_repairs = 0
	_repairs_free = 0
	_fusions = 0
	_colossus = false
	_bench_fusions = 0
	_fusion_wait = 0.0
	_wrecks = 0
	_wreck_index = -1
	_wrecks_skipped.clear()
	_wreck_best = INF
	_wreck_best_distance = INF
	_wreck_stall = 0.0
	_hits = 0
	_dark_samples = 0
	_lamps_bought = 0
	_health_at_boss = -1
	_level_at_boss = -1
	_player.health_changed.connect(_on_health_changed.bind([_player.health]))
	_run.boss_spawned.connect(_on_boss_spawned)
	if _run.lamp_field != null:
		_run.lamp_field.lamp_placed.connect(func(_at: Vector3) -> void: _lamps_bought += 1)
	for module_id in _extra_machines:
		if _caravan.add_machine(module_id) == null:
			push_warning("simulate_runs: --caravan=%s non entra (carovana piena)" % module_id)

	var step := 1.0 / Engine.physics_ticks_per_second
	var timed_out := false
	_trace_next = 0.0
	while not _run.is_over:
		if _run.elapsed >= _max_seconds:
			timed_out = true
			break
		if _trace_every > 0.0 and _run.elapsed >= _trace_next:
			_trace_next += _trace_every
			print("PROTOTYPE01_SIM_TRACE t=%.3f pos=%.4f,%.4f kills=%d alive=%d level=%d xp=%d hp=%d rng=%d carried=%d frags=%d"
				% [_run.elapsed, _player.global_position.x, _player.global_position.z, _director.kills,
					_director.enemies.size(), _run.progression.level, _run.progression.xp, _player.health,
					_director.rng.state, _caravan.carried, _xp.count()])
		if _menu.is_open:
			_release_inputs()
			_pick_card()
		elif _run.fusion_bench != null and _run.fusion_bench.is_open:
			_release_inputs()
			_drive_bench()
		else:
			_tick_bot(step)
		await physics_frame
	_release_inputs()

	var victory := _run.boss_phase == ArenaRun.BossPhase.DEFEATED
	var boss_state := "none"
	var boss_health := 0
	if victory:
		boss_state = "killed"
	elif _run.boss_phase == ArenaRun.BossPhase.ACTIVE:
		boss_state = "reached"
		boss_health = _run.boss.health if is_instance_valid(_run.boss) else 0
	var upgrades: PackedStringArray = []
	for id: StringName in _run.progression.levels:
		upgrades.append("%s:%d" % [id, _run.progression.levels[id]])
	var result := {
		bot = bot, seed = run_seed, time = _run.elapsed, victory = victory, timed_out = timed_out,
		level = _run.progression.level, kills = _director.kills, boss = boss_state, boss_health = boss_health,
		health = _player.health, digs = _digs, carried = _caravan.carried, capacity = _caravan.capacity,
		scrap_out = _run.scrap_out(victory), hits = _hits, machines = _caravan.machines.size(),
		repairs = _repairs, repairs_free = _repairs_free, wrecks = _wrecks,
		fusions = _fusions, colossus = 1 if _colossus else 0,
	}
	var outcome := "victory_at" if victory else ("timeout_at" if timed_out else "died_at")
	var night_phase := DayNightCycle.PHASE_NAMES[_run.day_night.phase] if _run.day_night != null else "DAY"
	print("PROTOTYPE01_SIM seed=%d bot=%s %s=%.1f level=%d kills=%d boss=%s boss_hp=%d hp=%d hits=%d hp_at_boss=%d level_at_boss=%d digs=%d scrap_carried=%d capacity=%d scrap_out=%d upgrades=%s night=%s dark_contacts=%d dark_decisions=%d lamps=%d actives=%d machines=%d repairs=%d repairs_free=%d wrecks=%d fusions=%d colossus=%d class=%s wall_s=%.1f"
		% [run_seed, bot, outcome, result.time, result.level, result.kills, boss_state, boss_health, result.health,
			_hits, _health_at_boss, _level_at_boss, _digs, result.carried, result.capacity, result.scrap_out, ",".join(upgrades),
			night_phase, _director.dark_contacts, _dark_samples, _lamps_bought, _actives_used, result.machines,
			_repairs, _repairs_free, _wrecks, result.fusions, result.colossus, _run.class_id, (Time.get_ticks_msec() - wall_start) / 1000.0])

	paused = false
	root.remove_child(_scene)
	_scene.queue_free()
	await physics_frame
	await physics_frame
	return result


func _on_health_changed(health: int, _max_health: int, last: Array) -> void:
	if health < last[0]:
		_hits += 1
	last[0] = health


func _on_boss_spawned(_boss: Enemy) -> void:
	_health_at_boss = _player.health
	_level_at_boss = _run.progression.level


# --- Bot ---------------------------------------------------------------------------

func _tick_bot(step: float) -> void:
	_dig_cooldown = maxf(_dig_cooldown - step, 0.0)
	_escape_left = maxf(_escape_left - step, 0.0)
	_fusion_wait = maxf(_fusion_wait - step, 0.0)
	_decision_left -= step
	if _bot != &"passive":
		_track_stuck(step)
		if _decision_left <= 0.0:
			_decision_left = _params.interval
			if _director.is_in_dark(_player.global_position):
				_dark_samples += 1
			if _escape_left <= 0.0:
				_move = _choose_direction()
		var repairing := _tick_fusion()
		if repairing:
			_drop_repair()  # la fusione ha la precedenza: niente Interagisci tenuto dalla riparazione
		else:
			repairing = _tick_repair()
		if not repairing and _params.digs and not _tick_lamps():
			_tick_relief_brush(step)
		# Tenendo Interagisci nessuna attiva: la carica dell'Ariete lo porterebbe fuori portata.
		if not _repair_holding:
			_tick_actives()
	_apply_inputs()


## Riparazione (D-093, scelta 3 del piano A: nessuna soglia di rottami). Con una macchina
## guasta e il nemico piu vicino oltre BRUSH_SAFE_M il bot punta la guasta piu vicina, ci va e,
## entro REPAIR_STOP_M, tiene Interagisci a ogni passo (la ripresa dalla pausa lo azzera) finche
## non e riparata, senza staccarsi per i nemici; oltre REPAIR_HOLD_M lascia, e con un nemico
## entro BRUSH_SAFE_M rinuncia. Conta come sua una riparazione che vede quasi finita (>= 0,9)
## sulla macchina puntata: non quelle del Saldatore. Vero finche ha un bersaglio (niente pennello).
func _tick_repair() -> bool:
	if _repair_target != null and (not is_instance_valid(_repair_target) or not _repair_target.is_broken()):
		if _repair_mine:
			_repairs += 1
			if _repair_free:
				_repairs_free += 1
		_drop_repair()
	if _repair_target == null:
		if _caravan.broken_machines().is_empty() or _nearest_enemy_distance() < BRUSH_SAFE_M:
			return false
		_repair_target = _nearest_broken()
		if _repair_target == null:
			return false
	# La carovana ripara la guasta piu vicina al giocatore: se e un'altra, il bot punta quella.
	var repairing := _caravan.repairing_machine()
	if repairing != null and repairing != _repair_target and repairing.is_broken():
		_repair_target = repairing
		_repair_mine = false
	_player.tool_held = false
	_aim = Vector2.ZERO
	var distance := Machine.planar_distance(_repair_target.global_position, _player.global_position)
	if distance > (REPAIR_HOLD_M if _repair_holding else REPAIR_STOP_M):
		_player.interact_held = false
		_repair_holding = false
		_repair_mine = false
		if _nearest_enemy_distance() < BRUSH_SAFE_M:
			_drop_repair()
			return false
		if _escape_left <= 0.0:
			_move = (_planar(_repair_target.global_position) - _planar(_player.global_position)).normalized()
		return true
	_repair_holding = true
	_move = Vector2.ZERO
	_player.interact_held = true
	_repair_mine = _caravan.repairing_machine() == _repair_target and _caravan.repair_progress() >= 0.9
	_repair_free = _caravan.carried < _caravan.tuning.repair_cost
	return true


## Fusione (D-093, piano B): vero se il bot va alla pedana per fondere (niente pennello). La
## regola: pedana aperta, carovana al limite dei moduli, piu di una macchina, nessuna guasta, nei
## Cassoni funzionanti i rottami per fondere tutto nel capofila, nemico piu vicino oltre
## BRUSH_SAFE_M. Va al centro della pedana e, entro un quarto del lato dal centro, preme
## Interagisci (il banco si apre a fine passo, da ArenaRun); una richiesta segnata non si ripete.
func _tick_fusion() -> bool:
	var pad := _run.fusion_pad
	if pad == null or not pad.is_open() or _fusion_wait > 0.0:
		return false
	if _caravan.module_count() < _caravan.module_limit() or _caravan.machines.size() < 2:
		return false
	if not _caravan.broken_machines().is_empty() or _caravan.working_carried() < _fuse_all_cost():
		return false
	if _nearest_enemy_distance() < BRUSH_SAFE_M:
		return false
	_player.tool_held = false
	_aim = Vector2.ZERO
	if Machine.planar_distance(pad.center, _player.global_position) <= pad.half_size() * 0.5:
		_move = Vector2.ZERO
		if not pad.has_bench_request():
			_bench_fusions = 0
			_player.interact_pressed.emit()
		return true
	if _escape_left <= 0.0:
		_move = (_planar(pad.center) - _planar(_player.global_position)).normalized()
	return true


## Rottami per fondere nel capofila tutte le altre macchine.
func _fuse_all_cost() -> int:
	var lead := _caravan.lead()
	var cost := 0
	for machine in _caravan.machines:
		if machine != lead:
			cost += MachineFusion.fuse_cost(machine.modules.size(), _caravan.tuning)
	return cost


## Banco aperto: una macchina per passo entra nel capofila (`FusionBench.fuse`, la via della
## conferma); quando nessuna puo piu entrare il banco si chiude. Senza fusioni in questo banco il
## bot aspetta FUSION_RETRY_S prima di riprovare.
func _drive_bench() -> void:
	var bench := _run.fusion_bench
	var lead := _caravan.lead()
	if lead != null:
		for machine in _caravan.machines:
			if machine != lead and _caravan.can_fuse(lead, machine):
				if bench.fuse(_caravan.machines.find(lead), _caravan.machines.find(machine)):
					_fusions += 1
					_bench_fusions += 1
					if lead.size == MachineFusion.Size.COLOSSUS:
						_colossus = true
					return
	if _bench_fusions == 0:
		_fusion_wait = FUSION_RETRY_S
	bench.close()


## La guasta piu vicina al giocatore (piano XZ), o null.
func _nearest_broken() -> Machine:
	var best: Machine = null
	var best_distance := INF
	for machine in _caravan.broken_machines():
		var distance := Machine.planar_distance(machine.global_position, _player.global_position)
		if distance < best_distance:
			best = machine
			best_distance = distance
	return best


func _drop_repair() -> void:
	_repair_target = null
	_repair_holding = false
	_repair_mine = false
	_repair_free = false
	if is_instance_valid(_player):
		_player.interact_held = false


## Attive appena cariche, se un nemico e entro la loro portata (il punto lo sceglie la mira).
func _tick_actives() -> void:
	if _run.loadout == null:
		return
	var actives := _run.loadout.actives()
	for slot in actives.size():
		var active := actives[slot]
		if active.cooldown_left > 0.0 or _nearest_enemy_distance() > active.stat(&"aim_range"):
			continue
		if _run.loadout.trigger_active(slot):
			_actives_used += 1


## Fermo contro un ostacolo mentre vuole muoversi: per mezzo secondo prova una
## direzione a caso, come chi si accorge di essere incastrato.
func _track_stuck(step: float) -> void:
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if _move.is_zero_approx() or speed > 1.5:
		_stuck_seconds = 0.0
		return
	_stuck_seconds += step
	if _stuck_seconds >= 0.4:
		_stuck_seconds = 0.0
		_escape_left = 0.5
		_move = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))


## Direzione di marcia (piano XZ) col punteggio migliore fra 16, o zero per restare
## fermo: lontano dai nemici e dagli ostacoli, verso l'esperienza quando e sicuro.
func _choose_direction() -> Vector2:
	var here := _planar(_player.global_position)
	var awareness: float = _params.awareness
	# Ogni minaccia: x, y = posizione; z = raggio del corpo in piu.
	var threats: Array[Vector3] = []
	var weights: Array[float] = []
	var nearest := INF
	# Il boss si vede sempre (barra vita e freccia a schermo): non lo si fugge, lo si aggira.
	var boss_active := _run.boss_phase == ArenaRun.BossPhase.ACTIVE and is_instance_valid(_run.boss)
	var boss_at := _planar(_run.boss.global_position) if boss_active else Vector2.ZERO
	var boss_radius := _run.boss.hit_radius_bonus if boss_active else 0.0
	for enemy in _director.enemies:
		if enemy.is_dead or enemy.self_driven:
			continue
		var at := _planar(enemy.global_position)
		var distance := at.distance_to(here)
		if distance > awareness:
			continue
		nearest = minf(nearest, distance)
		# Fra mezzo secondo sara piu vicino: i nemici puntano il bot.
		var predicted := at.move_toward(here, _run.tuning.enemy_speed * 0.5)
		threats.append(Vector3(predicted.x, predicted.y, 0.0))
		weights.append(1.0)

	var xp_direction := Vector2.ZERO
	var xp_weight: float = _params.xp_weight
	if xp_weight > 0.0:
		var best_xp := 20.0
		for fragment: Dictionary in _xp._fragments:
			var node: Node3D = fragment.node
			var offset := _planar(node.global_position) - here
			if offset.length() < best_xp:
				best_xp = offset.length()
				xp_direction = offset.normalized()
		if nearest < 3.0:
			xp_weight *= 0.3

	if threats.is_empty() and xp_direction.is_zero_approx() and not boss_active:
		return Vector2.ZERO

	var limit := _run._play_half_extents() - Vector2(6.0, 6.0)
	var best := Vector2.ZERO
	var best_score := -INF
	for i in DIRECTIONS + 1:
		var direction := Vector2.ZERO if i == DIRECTIONS else Vector2.RIGHT.rotated(TAU * i / DIRECTIONS)
		var score := 0.0
		var future := here + direction * LOOKAHEAD
		var middle := here + direction * (LOOKAHEAD * 0.4)
		for t in threats.size():
			var at := Vector2(threats[t].x, threats[t].y)
			var far := maxf(future.distance_to(at) - threats[t].z, 0.3)
			var near := maxf(middle.distance_to(at) - threats[t].z, 0.3)
			score -= weights[t] * (1.0 / (far * far) + 1.0 / (near * near))
		if boss_active:
			var boss_distance := future.distance_to(boss_at) - boss_radius
			score -= 0.3 * absf(boss_distance - BOSS_ORBIT_DISTANCE)
			if boss_distance < BOSS_TOO_CLOSE:
				score -= 4.0 * (BOSS_TOO_CLOSE - boss_distance)
		if i < DIRECTIONS:
			if not _walkable(here + direction * 1.0):
				score -= 100.0
			if not _walkable(here + direction * 2.0):
				score -= 3.0
			if not _walkable(future):
				score -= 1.0
			if _field != null and _field.slope_at(_world(middle)) > 0.4:
				score -= 0.3
			if absf(future.x) > limit.x or absf(future.y) > limit.y:
				score -= 5.0
			score += 0.1 * direction.dot(_move.normalized()) if not _move.is_zero_approx() else 0.0
			score += xp_weight * direction.dot(xp_direction)
		if score > best_score:
			best_score = score
			best = direction
	return best


## Scava un passo quando il cassone ha posto: mira a una cella a portata (meglio
## un muro o un deposito, che rende senza lasciare una buca) e preme il tool.
## Lo scrapper di notte compra un lampione sulla cella davanti a se, quando puo.
## Vero se ha usato il tool (niente scavo nello stesso passo).
func _tick_lamps() -> bool:
	var lamps: LampField = _run.lamp_field
	if lamps == null:
		return false
	var in_lamp_mode := _player.terrain_tool_mode == TerrainField.ToolMode.LAMP
	var wanted := _run.is_night() and _dig_cooldown <= 0.0 and lamps.count() < lamps.max_count 		and _caravan.carried >= lamps.scrap_cost and _nearest_enemy_distance() >= 3.5
	var spot_ok := false
	if wanted:
		spot_ok = lamps.can_place(_player.terrain_target) and lamps.can_afford(_player.terrain_target)
		# Nessun lampione a meno di 1,6 raggi da uno gia piazzato: copertura, non ammassi.
		for other in lamps.positions():
			if _planar(other).distance_to(_planar(_player.terrain_target)) < lamps.light_radius * 1.6:
				spot_ok = false
				break
	if not (wanted and spot_ok):
		# Torna a scavare: il tool premuto in modo lampione agirebbe al passo dopo.
		if in_lamp_mode:
			while _player.terrain_tool_mode != TerrainField.ToolMode.DIG:
				_player._toggle_terrain_mode()
		return false
	if not in_lamp_mode:
		# Prima il modo, poi il colpo al passo successivo (l'evento arriva al frame dopo).
		while _player.terrain_tool_mode != TerrainField.ToolMode.LAMP:
			_player._toggle_terrain_mode()
		return true
	if _field != null:
		# Sul rilievo il lampione si pianta tenendo il pennello un passo in modo Lampione.
		_hold_brush(TerrainField.ToolMode.LAMP)
		_player.tool_held = false
	else:
		_press_tool()
	_dig_cooldown = 1.0
	return true


## Rilievo continuo: scava la vena piu vicina con rottami finche ne ha, se nessun nemico e
## a meno di BRUSH_SAFE_M; una volta per run, dopo RAMPART_AT_SECONDS, alza un argine di
## RAMPART_HOLD_SECONDS dove sta (D-085, spec sezione 7).
func _tick_relief_brush(step: float) -> void:
	_aim = Vector2.ZERO
	if _rampart_left > 0.0:
		_rampart_left -= step
		if _rampart_left <= 0.0 or _nearest_enemy_distance() < VEIN_WALK_SAFE_M * 0.6:
			_rampart_left = 0.0
			_player.tool_held = false
		else:
			_hold_brush(TerrainField.ToolMode.RAISE)
		return
	if _nearest_enemy_distance() < BRUSH_SAFE_M or _player.pack == null:
		_player.tool_held = false
		return
	# Ferrovia (D-087): con un treno annunciato o in corsa non si scava sulla fascia; durante
	# la mira della Trivella si alza un argine sulla sua rotta, se non ce n'e gia uno.
	if _run.train_event != null and _run.train_event.state != TrainEvent.State.IDLE 			and RailwayDistrict.is_on_tracks(_planar(_player.terrain_target)):
		_player.tool_held = false
		return
	if _run.boss is Driller and (_run.boss as Driller).is_aiming() and _player.pack.amount >= 8.0:
		var boss := _run.boss as Driller
		var route_end := boss.global_position + boss.charge_direction * 12.0
		var spot := boss.global_position + boss.charge_direction * 8.0
		var here_xz := _planar(_player.global_position)
		var reach := _planar(_player.terrain_target).distance_to(here_xz)
		if _field.bump_along(boss.global_position, route_end, 0.8) == null 				and _planar(spot).distance_to(here_xz) <= reach + 1.0 and not _field.is_protected(spot):
			_aim = (_planar(spot) - here_xz).normalized()
			_rampart_left = RAMPART_HOLD_SECONDS
			_hold_brush(TerrainField.ToolMode.RAISE)
			return
	if not _rampart_done and _run.elapsed >= RAMPART_AT_SECONDS and not _player.pack.is_empty() 			and _nearest_enemy_distance() > VEIN_WALK_SAFE_M:
		_rampart_done = true
		_rampart_left = RAMPART_HOLD_SECONDS
		_hold_brush(TerrainField.ToolMode.RAISE)
		return
	# Relitti sepolti (D-093) prima delle vene e anche col cassone pieno: la macchina conta
	# piu dei rottami. Il relitto puntato resta finche il suo telaio c'e e sta dentro la finestra
	# del campo di percorso (non conta la pendenza: lo scavo rende ripida la sua stessa cella);
	# toglie il posto alle vene solo se il bot e a portata o ci sta andando, altrimenti si passa
	# alle vene senza toccare il pennello (e il tempo senza avvicinarsi conta per l'abbandono).
	if _field != null and _run.wrecks != null:
		if _wreck_index >= 0 and (_run.wrecks.frame_of(_wreck_index) == null
				or not _path.is_inside(_path.cell_of(_run.wrecks.position_of(_wreck_index)))):
			_wreck_index = -1
		if _wreck_index < 0:
			_pick_wreck()
		if _wreck_index >= 0:
			var wreck_at := _run.wrecks.position_of(_wreck_index)
			var state := _dig_toward(wreck_at, true)
			_track_wreck(wreck_at, state == Dig.IN_REACH, step)
			if state != Dig.IDLE:
				return
	var waiting := _scrap.positions_near(_player.global_position, _caravan.tuning.pickup_radius_from_player).size()
	if _caravan.carried + waiting >= _caravan.capacity:
		_player.tool_held = false
		return
	if _vein_target == Vector3.INF or _scrap.vein_scrap_left(_vein_target) <= 0:
		_vein_target = _nearest_vein()
	if _vein_target == Vector3.INF:
		_player.tool_held = false
		return
	_dig_toward(_vein_target)


## Si avvicina a [param target] (centro di una vena o punto di un relitto) solo col campo
## libero, poi lo mira e scava tenendo il pennello (Dig: IDLE, WALKING, IN_REACH). Per un
## relitto ([param wreck]) la marcia continua finche `_move` lo punta ancora (la direzione resta
## fra i passi fino alla prossima decisione) e un IDLE non tocca il pennello: decide la vena
## che viene dopo, cosi una pennellata non si riconta a ogni passo. Le vene come prima.
func _dig_toward(target: Vector3, wreck := false) -> Dig:
	var here := _planar(_player.global_position)
	var to_target := _planar(target) - here
	var reach := _planar(_player.terrain_target).distance_to(here)
	if to_target.length() > reach + 1.0:
		# Troppo lontano: ci si avvicina solo col campo libero (la mira segue la marcia).
		var direction := to_target.normalized()
		var heading := _move.is_zero_approx() or (wreck and _move.normalized().dot(direction) > 0.95)
		if heading and _nearest_enemy_distance() > VEIN_WALK_SAFE_M:
			_player.tool_held = false
			_move = direction
			return Dig.WALKING
		if not wreck:
			_player.tool_held = false
		return Dig.IDLE
	_aim = to_target.normalized()
	var facing := _planar(-_player.global_basis.z).normalized()
	if facing.dot(_aim) > 0.95:
		_hold_brush(TerrainField.ToolMode.DIG)
	else:
		_player.tool_held = false
	return Dig.IN_REACH


## Il relitto chiuso piu vicino (entro VEIN_SEARCH_M e raggiungibile, come le vene), o -1.
func _nearest_wreck() -> int:
	var wrecks := _run.wrecks
	if wrecks == null:
		return -1
	var here := _planar(_player.global_position)
	var best := -1
	var best_distance := VEIN_SEARCH_M
	for i in wrecks.count():
		if wrecks.frame_of(i) == null or _wrecks_skipped.has(i):
			continue
		var at := wrecks.position_of(i)
		var distance := _planar(at).distance_to(here)
		if distance < best_distance and _path.cost_at(at) != PathField.UNREACHABLE:
			best_distance = distance
			best = i
	return best


func _pick_wreck() -> void:
	_wreck_index = _nearest_wreck()
	_wreck_best = INF
	_wreck_best_distance = INF
	_wreck_stall = 0.0


## Avanzamento sul relitto puntato: a portata il suolo sul relitto deve scendere di
## WRECK_PROGRESS_M sotto la quota piu bassa vista, fuori portata il bot deve avvicinarsi di
## WRECK_APPROACH_M; dopo WRECK_GIVE_UP_S secondi senza, il relitto si lascia per la run.
func _track_wreck(at: Vector3, in_reach: bool, step: float) -> void:
	if in_reach:
		var ground := _field.height_at(at)
		if ground < _wreck_best - WRECK_PROGRESS_M:
			_wreck_best = ground
			_wreck_stall = 0.0
			return
	else:
		var distance := _planar(at).distance_to(_planar(_player.global_position))
		if distance < _wreck_best_distance - WRECK_APPROACH_M:
			_wreck_best_distance = distance
			_wreck_stall = 0.0
			return
	_wreck_stall += step
	if _wreck_stall < WRECK_GIVE_UP_S:
		return
	_wrecks_skipped.append(_wreck_index)
	print("PROTOTYPE01_SIM_WRECK_SKIP seed=%d bot=%s x=%.1f z=%.1f" % [_run.run_seed, _bot, at.x, at.z])
	_player.tool_held = false
	_pick_wreck()


## Tiene premuto il pennello nel modo voluto (lo stesso flag che imposta l'input del giocatore).
func _hold_brush(mode: int) -> void:
	while _player.terrain_tool_mode != mode:
		_player._toggle_terrain_mode()
	if not _player.tool_held:
		var target := _player.terrain_target
		print("PROTOTYPE01_SIM_BRUSH t=%.2f mode=%s x=%.1f z=%.1f" % [_run.elapsed, TerrainField.TOOL_MODE_NAMES[mode], target.x, target.z])
		_digs += 1
	_player.tool_held = true


func _nearest_vein() -> Vector3:
	var here := _planar(_player.global_position)
	var best := Vector3.INF
	var best_distance := VEIN_SEARCH_M
	for vein in _scrap.veins():
		if vein.scrap_left <= 0:
			continue
		var distance := _planar(vein.center).distance_to(here)
		if distance < best_distance and _path.cost_at(vein.center) != PathField.UNREACHABLE:
			best_distance = distance
			best = vein.center
	return best


func _nearest_enemy_distance() -> float:
	var here := _planar(_player.global_position)
	var nearest := INF
	for enemy in _director.enemies:
		if not enemy.is_dead:
			nearest = minf(nearest, _planar(enemy.global_position).distance_to(here) - enemy.hit_radius_bonus)
	return nearest


func _walkable(point: Vector2) -> bool:
	return _path.is_walkable(_world(point))


# --- Input -------------------------------------------------------------------------

## Stick sinistro e destro: x = destra, y = verso la camera (+Z).
func _apply_inputs() -> void:
	_set_stick(MOVE_ACTIONS, _move)
	_set_stick(AIM_ACTIONS, _aim)


func _set_stick(actions: Array[StringName], value: Vector2) -> void:
	var strengths: Array[float] = [maxf(-value.x, 0.0), maxf(value.x, 0.0), maxf(-value.y, 0.0), maxf(value.y, 0.0)]
	for i in actions.size():
		if strengths[i] > 0.01:
			Input.action_press(actions[i], minf(strengths[i], 1.0))
		else:
			Input.action_release(actions[i])


func _release_inputs() -> void:
	for action in MOVE_ACTIONS + AIM_ACTIONS:
		Input.action_release(action)


## Una pressione del tool: evento vero (pressione e rilascio), consegnato subito
## invece che al prossimo frame, cosi il comando parte al passo fisico in cui e deciso.
func _press_tool() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"terrain_tool"
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


## Sceglie la carta con la priorita piu alta; durante la pausa di cortesia del
## menu la pressione e ignorata e si riprova al passo successivo.
func _pick_card() -> void:
	var priority := CARD_PRIORITY_SCRAPPER if _bot == &"scrapper" else CARD_PRIORITY
	var best_index := 0
	var unknown := priority.size() + 2
	var best_rank := unknown
	# Il novice (`first_card`) non guarda le carte: preme sempre la prima, anche una macchina.
	for i in (0 if _params.first_card else _menu.card_count()):
		# Righe della carta: rarita, nome, tipo, testo. Un'arma o una sua trasformazione (D-092)
		# vince su tutto, poi una "Nuova macchina" (D-093, anche nel menu del relitto); le altre
		# seguono la priorita (spostata di due).
		var lines := _menu.card_text(i).split("\n")
		var card_name := lines[1] if lines.size() > 1 else ""
		var rank := unknown
		if _is_weapon_card_name(card_name):
			rank = 0
		elif card_name.begins_with(MACHINE_CARD_NAME):
			rank = 1
		else:
			for upgrade in UpgradeCatalog.all():
				if upgrade.name == card_name:
					var found := priority.find(upgrade.id)
					rank = found + 2 if found >= 0 else unknown
					break
		if rank < best_rank:
			best_rank = rank
			best_index = i
	_menu.press(best_index)


static func _is_weapon_card_name(card_name: String) -> bool:
	for entry in WeaponCatalog.all():
		if entry.name == card_name:
			return true
		for at in WeaponCatalog.BRANCH_LEVELS:
			for option in WeaponCatalog.branch_options(entry.id, at):
				if option.name == card_name:
					return true
	return false


# --- Riepilogo ---------------------------------------------------------------------

func _print_summary(bot: StringName) -> void:
	var runs := _results.filter(func(r: Dictionary) -> bool: return r.bot == bot)
	if runs.is_empty():
		return
	var victories := runs.filter(func(r: Dictionary) -> bool: return r.victory).size()
	var reached := runs.filter(func(r: Dictionary) -> bool: return r.boss != "none").size()
	var timeouts := runs.filter(func(r: Dictionary) -> bool: return r.timed_out).size()
	var total_scrap := 0.0
	for r: Dictionary in runs:
		total_scrap += r.scrap_out
	var mean_scrap := total_scrap / runs.size()
	print("PROTOTYPE01_SIM_SUMMARY bot=%s runs=%d deaths=%d victories=%d timeouts=%d boss_reached=%d end_time=%s level=%s kills=%s scrap_carried=%s scrap_out=%s scrap_out_mean=%.2f"
		% [bot, runs.size(), runs.size() - victories - timeouts, victories, timeouts, reached,
			_spread(runs, &"time"), _spread(runs, &"level"), _spread(runs, &"kills"),
			_spread(runs, &"carried"), _spread(runs, &"scrap_out"), mean_scrap])
	# Run necessarie per pagare ogni livello dell'Officina col reddito medio di questo bot.
	for entry in PermanentCatalog.all():
		var costs: Array = entry.costs
		var parts: PackedStringArray = []
		for cost: int in costs:
			parts.append("%d>%s" % [cost, "mai" if mean_scrap <= 0.0 else "%.1f" % (cost / mean_scrap)])
		print("PROTOTYPE01_SIM_AFFORD bot=%s id=%s cost>runs=%s" % [bot, entry.id, ",".join(parts)])


## "mediana/minimo/massimo" di un campo dei risultati.
static func _spread(runs: Array, field: StringName) -> String:
	var values: Array[float] = []
	for r: Dictionary in runs:
		values.append(float(r[field]))
	values.sort()
	var middle := values.size() / 2
	var median := values[middle] if values.size() % 2 == 1 else (values[middle - 1] + values[middle]) * 0.5
	return "%.1f/%.1f/%.1f" % [median, values[0], values[values.size() - 1]]


static func _planar(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _world(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, v.y)
