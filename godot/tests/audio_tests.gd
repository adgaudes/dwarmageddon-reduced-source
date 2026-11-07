extends SceneTree
## Test degli effetti sonori (file registrati e sintesi di riserva) e del loro collegamento alla run.
## In headless il driver audio e fittizio: si contano le riproduzioni, non si
## ascolta nulla. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/audio_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")
const GameSettingsScript := preload("res://scripts/services/game_settings.gd")
const EXPECTED_IDS: Array[StringName] = [
	&"nail_shot", &"enemy_death", &"player_hurt", &"player_death", &"dash",
	&"terrain_dig", &"terrain_raise", &"tool_reject", &"xp_pickup",
	&"scrap_pickup", &"scrap_spend", &"level_up", &"upgrade_chosen",
	&"boss_warning", &"victory",
	&"boss_spawn", &"boss_demolish", &"boss_barricade", &"carrier_pickup",
	&"dusk", &"nightfall", &"train_horn", &"driller_charge", &"quake_rumble",
	&"ui_move", &"ui_confirm", &"ui_back", &"ui_open",
]
const FREQUENT_IDS: Array[StringName] = [&"nail_shot", &"enemy_death", &"xp_pickup", &"scrap_pickup"]
## Piano 5 delle armi: suoni che ogni arma chiede (`fire` allo sparo, `hit` all'impatto); solo
## campioni, nessuna sintesi di riserva.
const WEAPON_SOUNDS: Dictionary[StringName, Array] = {
	&"seismic_stake": [&"fire", &"hit"], &"scrap_launcher": [&"fire", &"hit"], &"dig_charge": [&"fire", &"hit"],
	&"welder": [&"fire"], &"crane_magnet": [&"fire", &"hit"], &"scythe": [&"hit"], &"bramble": [&"fire", &"hit"],
	&"site_blade": [&"fire", &"hit"], &"jackhammer": [&"fire"], &"ram": [&"fire", &"hit"], &"cement_mixer": [&"fire", &"hit"],
}

var _failures := 0
var _scene: Node3D
var _audio: RunAudio
var _run: ArenaRun
var _field: TerrainField
var _player: PlayerCharacter
var _caravan: Caravan
var _director: EnemyDirector
var _weapon: AutoWeapon
var _path: PathField
var _xp: XpField
var _menu: LevelUpMenu


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _test_precache()
	_test_library()
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_audio = _scene.get_node(^"RunAudio")
	_run = _scene.get_node(^"Run")
	_field = _scene.get_node(^"TerrainField")
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_director = _scene.get_node(^"EnemyDirector")
	_weapon = _scene.get_node(^"PlayerWeapon")
	_path = _scene.get_node(^"PathField")
	_xp = _scene.get_node(^"XpField")
	_menu = _scene.get_node(^"LevelUpMenu")
	_director.spawning = false
	await _frames(5)
	# Dopo il _ready della scena, che riattiverebbe il passo fisico.
	_weapon.set_physics_process(false)
	_test_node_setup()
	await _test_rate_limit()
	await _test_pool()
	_test_buses_and_volume()
	await _test_combat_events()
	await _test_weapon_sounds()
	await _test_player_events()
	await _test_terrain_events()
	await _test_scrap_events()
	await _test_level_up_events()
	await _test_boss_and_end_events()
	# T-12: i nodi messi in coda con queue_free vanno liberati prima di uscire, o
	# il motore segnala istanze ObjectDB perse all'uscita.
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for weapon_id: StringName in WEAPON_SOUNDS:
		for kind: StringName in WEAPON_SOUNDS[weapon_id]:
			ids.append(StringName("w_%s_%s" % [weapon_id, kind]))
	return ids


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _count(id: StringName) -> int:
	return _audio.play_count(id)


func _place_player(at: Vector3) -> void:
	_player.global_position = Vector3(at.x, 0.88, at.z)
	_player.velocity = Vector3.ZERO
	_player._invulnerable_left = 0.0
	_path.solve()


func _peak(stream: AudioStreamWAV) -> int:
	var peak := 0
	for i in stream.data.size() / 2:
		peak = maxi(peak, absi(stream.data.decode_s16(i * 2)))
	return peak


## R-40: la libreria si precarica in thread (avviata dal menu): file con le richieste
## del ResourceLoader, sintesi di riserva nel WorkerThreadPool; a lavoro finito
## build_all sul thread principale costa quasi nulla.
func _test_precache() -> void:
	print("precache")
	_check(not SfxLibrary.is_precached(), "all'avvio la cache e vuota")
	# Costo della sintesi sincrona di tutto, per confronto con la libreria di D-048.
	var start := Time.get_ticks_usec()
	for id in EXPECTED_IDS:
		SfxLibrary.synthesize(id)
	var sync_us := Time.get_ticks_usec() - start
	SfxLibrary.precache_async()
	var started := Time.get_ticks_msec()
	var frames := 0
	while not SfxLibrary.is_precached() and Time.get_ticks_msec() - started < 10000:
		await process_frame
		frames += 1
	var wait_ms := Time.get_ticks_msec() - started
	_check(SfxLibrary.is_precached(), "il precaricamento in thread finisce (%d ms, %d frame)" % [wait_ms, frames])
	start = Time.get_ticks_usec()
	var streams := SfxLibrary.build_all()
	var build_us := Time.get_ticks_usec() - start
	print("PROTOTYPE01_SFX_PRECACHE sync_us=%d thread_wait_ms=%d build_all_us=%d" % [sync_us, wait_ms, build_us])
	_check(build_us < 5000, "dopo il precaricamento build_all costa < 5 ms (%d us)" % build_us)
	_check(streams.size() == EXPECTED_IDS.size() + _weapon_ids().size() and streams[&"nail_shot"] == SfxLibrary.build(&"nail_shot"),
		"gli stream precaricati sono le stesse risorse di un caricamento diretto")
	_check(SfxLibrary.build_all() == streams, "build_all restituisce sempre la stessa cache")


## D-084: ogni id ha il suo file registrato; la sintesi di D-048 resta come riserva.
func _test_library() -> void:
	print("library")
	var streams := SfxLibrary.build_all()
	var expected := EXPECTED_IDS.size() + _weapon_ids().size()
	_check(streams.size() == expected, "%d suoni nella libreria (%d)" % [expected, streams.size()])
	for id in _weapon_ids():
		var stream := streams.get(id) as AudioStreamOggVorbis
		var seconds := SfxLibrary.duration_of(stream) if stream != null else 0.0
		_check(SfxLibrary.has_sample(id) and stream != null and not stream.loop and seconds >= 0.05 and seconds <= 1.2,
			"%s: campione OGG dell'arma, %.2f s" % [id, seconds])
	var uncovered: Array[String] = []
	for entry in WeaponCatalog.all():
		if entry.slot != &"fusion" and entry.id != &"nailgun" and not WEAPON_SOUNDS.has(entry.id):
			uncovered.append(String(entry.id))
	_check(uncovered.is_empty(), "ogni arma del catalogo ha i suoi suoni (senza: %s)" % ", ".join(uncovered))
	for id in EXPECTED_IDS:
		var stream: AudioStream = streams.get(id)
		if stream == null:
			_check(false, "%s: stream mancante" % id)
			continue
		var seconds := SfxLibrary.duration_of(stream)
		var ogg := stream as AudioStreamOggVorbis
		_check(SfxLibrary.has_sample(id) and ogg != null and not ogg.loop and seconds >= 0.03 and seconds <= 2.0,
			"%s: file OGG senza loop, %.2f s" % [id, seconds])
	for id in FREQUENT_IDS:
		_check(SfxLibrary.duration_of(streams[id]) <= 0.15, "%s e corto: suona spesso" % id)
	for id in EXPECTED_IDS:
		var synth := SfxLibrary.synthesize(id)
		if synth == null:
			_check(false, "%s: sintesi di riserva mancante" % id)
			continue
		var seconds := SfxLibrary.duration_of(synth)
		var format_ok := synth.format == AudioStreamWAV.FORMAT_16_BITS and not synth.stereo 			and synth.mix_rate == SfxLibrary.MIX_RATE and synth.loop_mode == AudioStreamWAV.LOOP_DISABLED
		var peak := _peak(synth)
		var tail := absi(synth.data.decode_s16(synth.data.size() - 2))
		_check(format_ok and seconds >= 0.03 and seconds <= 2.0 and peak > 12000 and peak <= 32767 and tail < 400,
			"%s di riserva: PCM 16 bit mono, %.2f s, picco %d, coda %d" % [id, seconds, peak, tail])
	var again := SfxLibrary.synthesize(&"nail_shot")
	_check(again.data == SfxLibrary.synthesize(&"nail_shot").data, "sintesi deterministica (rumore con seme fisso)")
	_check(SfxLibrary.synthesize(&"enemy_death").data != again.data, "suoni diversi hanno dati diversi")
	_check(SfxLibrary.build(&"missing_sound") == null and SfxLibrary.synthesize(&"missing_sound") == null,
		"id sconosciuto: nessuno stream")


func _test_node_setup() -> void:
	print("node")
	_check(_audio.process_mode == Node.PROCESS_MODE_ALWAYS, "RunAudio lavora anche a gioco fermo")
	var has_all := true
	for id in EXPECTED_IDS + _weapon_ids():
		has_all = has_all and _audio.has_sound(id) and _audio.stream_for(id) != null
	_check(has_all and _audio.sound_ids().size() == EXPECTED_IDS.size() + _weapon_ids().size(), "tutti gli id disponibili sul nodo")
	var players := 0
	var on_bus := true
	for child in _audio.get_children():
		var stream_player := child as AudioStreamPlayer
		if stream_player != null:
			players += 1
			on_bus = on_bus and stream_player.bus == &"SFX"
	_check(players == RunAudio.POOL_SIZE and on_bus, "%d player sul bus SFX" % players)
	var configured := true
	for id in EXPECTED_IDS:
		configured = configured and RunAudio.SOUND_SETTINGS.has(id)
	_check(configured, "ogni id ha volume, variazione e intervallo")
	_check(_audio.play_counts.is_empty(), "l'avvio della scena non suona nulla")


func _test_rate_limit() -> void:
	print("rate limit")
	_check(not _audio.play(&"missing_sound") and _count(&"missing_sound") == 0, "id sconosciuto: false, non contato")
	_check(_audio.play(&"nail_shot") and _count(&"nail_shot") == 1, "prima riproduzione accettata")
	_check(_audio.last_played == &"nail_shot", "last_played aggiornato")
	_check(not _audio.play(&"nail_shot") and _count(&"nail_shot") == 1, "ripetizione immediata scartata")
	_check(_audio.play(&"xp_pickup"), "il limite e per id: un altro suono passa")
	await _frames(8)
	_check(_audio.play(&"nail_shot", -3.0) and _count(&"nail_shot") == 2, "dopo l'intervallo minimo suona di nuovo")
	var accepted := 0
	for i in 70:
		if _audio.play(&"enemy_death"):
			accepted += 1
	_check(accepted == 1, "70 morti nello stesso frame: un solo suono (%d)" % accepted)
	await _frames(40)
	# Piu richieste dei player disponibili: nessun errore, si riusa il piu vecchio.
	var played := 0
	for id in EXPECTED_IDS:
		if _audio.play(id):
			played += 1
	_check(played == EXPECTED_IDS.size(), "tutti gli id riproducibili, compresi quelli del boss (%d)" % played)
	await _frames(40)


## Gruppo di player con stato "occupato" finto (P-08): in headless `playing` non torna
## mai falso, quindi il predicato `is_busy` si sostituisce e si controlla chi viene
## scelto. I suoni protetti (boss_warning, victory) non si rubano mai (R-36).
func _test_pool() -> void:
	print("pool")
	var busy := {}
	_audio.is_busy = func(stream_player: AudioStreamPlayer) -> bool: return busy.has(stream_player)
	_audio._player_ids.fill(&"")
	_audio._next_player = 0
	await _frames(40)
	var first: Array[StringName] = [&"boss_warning", &"victory", &"nail_shot", &"enemy_death", &"xp_pickup",
		&"scrap_pickup", &"scrap_spend", &"terrain_dig", &"terrain_raise", &"tool_reject"]
	var played := 0
	for id in first:
		var index: int = _audio._next_player
		if _audio.play(id):
			played += 1
		busy[_audio._players[index]] = true
	_check(played == first.size() and _audio._player_ids == first, "dieci suoni su dieci player liberi: uno ciascuno, nessun furto")
	_check(busy.size() == RunAudio.POOL_SIZE, "ora sono tutti occupati")
	await _frames(40)
	# Tutti occupati: si ruba il piu vecchio, saltando i protetti anche dopo il giro completo.
	var stolen: Array[StringName] = [&"dash", &"player_hurt", &"level_up", &"upgrade_chosen", &"boss_spawn",
		&"boss_demolish", &"boss_barricade", &"carrier_pickup", &"player_death", &"nail_shot", &"enemy_death", &"xp_pickup"]
	played = 0
	var protected_kept := true
	for id in stolen:
		if _audio.play(id):
			played += 1
		protected_kept = protected_kept and _audio._player_ids[0] == &"boss_warning" and _audio._player_ids[1] == &"victory"
	_check(played == stolen.size(), "tutti occupati: %d suoni rubano un player (%d)" % [stolen.size(), played])
	# Otto slot liberi (2-9): il nono furto riparte dal 2, il dodicesimo arriva al 5.
	_check(_audio._player_ids[2] == &"player_death" and _audio._player_ids[5] == &"xp_pickup", "ruba il piu vecchio non protetto, in giro")
	_check(protected_kept and _audio._players[0].stream == _audio.stream_for(&"boss_warning") and _audio._players[1].stream == _audio.stream_for(&"victory"),
		"boss_warning e victory non vengono mai interrotti")
	# Solo suoni protetti in corso: meglio perdere l'effetto che tagliarli.
	await _frames(40)
	_audio._player_ids.fill(&"victory")
	var dashes := _count(&"dash")
	_check(not _audio.play(&"dash") and _count(&"dash") == dashes, "con soli suoni protetti in corso il nuovo effetto si perde")
	_audio._player_ids.fill(&"")
	_audio._next_player = 0
	_audio.is_busy = func(stream_player: AudioStreamPlayer) -> bool: return stream_player.playing
	await _frames(40)
	_check(_audio.play(&"dash") and _count(&"dash") == dashes + 1, "ripristinato il predicato reale, suona di nuovo")


func _test_buses_and_volume() -> void:
	print("buses")
	var sfx := AudioServer.get_bus_index(&"SFX")
	var music := AudioServer.get_bus_index(&"Music")
	var master := AudioServer.get_bus_index(&"Master")
	_check(sfx > 0 and music > 0 and master == 0, "bus SFX e Music nel layout")
	if sfx < 0 or music < 0:
		return
	_check(AudioServer.get_bus_send(sfx) == &"Master" and AudioServer.get_bus_send(music) == &"Master", "entrambi inviano a Master")
	var settings := GameSettingsScript.new()
	_check(is_equal_approx(settings.master_volume, 1.0) and is_equal_approx(settings.sfx_volume, 0.8), "default: generale 100%, effetti 80%")
	settings.master_volume = 0.5
	settings.sfx_volume = 0.25
	settings.apply_audio()
	_check(absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.5)) < 0.01, "volume generale sul bus Master (%.2f dB)" % AudioServer.get_bus_volume_db(master))
	_check(absf(AudioServer.get_bus_volume_db(sfx) - linear_to_db(0.25)) < 0.01, "volume effetti sul bus SFX (%.2f dB)" % AudioServer.get_bus_volume_db(sfx))
	_check(not AudioServer.is_bus_mute(master) and not AudioServer.is_bus_mute(sfx), "bus attivi sopra zero")
	settings.sfx_volume = 0.0
	settings.apply_audio()
	_check(AudioServer.is_bus_mute(sfx) and not AudioServer.is_bus_mute(master), "a zero il bus SFX e muto")
	settings.free()
	var service: GameSettingsService = root.get_node(^"GameSettings")
	service.apply_audio()
	_check(not AudioServer.is_bus_mute(sfx) and absf(AudioServer.get_bus_volume_db(sfx) - linear_to_db(service.sfx_volume)) < 0.01,
		"il servizio ripristina i propri volumi")


func _test_combat_events() -> void:
	print("combat")
	_place_player(Vector3.ZERO)
	var enemy := _director.spawn_at(Vector3(4.0, 0.0, 0.0))
	_director.set_physics_process(false)
	var shots := _count(&"nail_shot")
	var fired := [0]
	_weapon.fired.connect(func(_n: int) -> void: fired[0] += 1)
	_weapon.set_physics_process(true)
	await _frames(45)
	_weapon.set_physics_process(false)
	_check(fired[0] > 0 and _count(&"nail_shot") == shots + fired[0], "ogni raffica della chiodatrice suona (%d)" % fired[0])
	var deaths := _count(&"enemy_death")
	var pickups := _count(&"xp_pickup")
	if is_instance_valid(enemy) and not enemy.is_dead:
		enemy.take_damage(enemy.health)
	else:
		enemy = _director.spawn_at(Vector3(3.0, 0.0, 0.0))
		enemy.take_damage(enemy.health)
	await _frames(2)
	_check(_count(&"enemy_death") > deaths, "nemico abbattuto: enemy_death")
	_xp.spawn(_player.global_position + Vector3(0.5, 0.0, 0.0), 1)
	await _frames(40)
	_check(_count(&"xp_pickup") > pickups, "frammento raccolto: xp_pickup")
	_director.set_physics_process(true)


## Piano 5 delle armi: ogni arma chiede i suoi suoni al loadout, RunAudio suona `w_<arma>_<kind>`
## o ripiega sui suoni di oggi; in pausa niente.
func _test_weapon_sounds() -> void:
	print("weapon sounds")
	var loadout := _run.loadout
	_check(loadout != null and loadout.weapon_sound.is_connected(_audio._on_loadout_weapon_sound), "RunAudio ascolta i suoni del loadout")
	var silent: Array[String] = []
	for entry in WeaponCatalog.all():
		if entry.slot == &"fusion" or entry.id == &"nailgun":
			continue
		for kind: StringName in [&"fire", &"hit"]:
			var sound := _audio.weapon_sound_id(entry.id, kind)
			var before := _count(sound)
			_audio._next_allowed.clear()
			loadout.weapon_sound.emit(entry.id, kind)
			if _count(sound) != before + 1:
				silent.append("%s/%s" % [entry.id, kind])
	_check(silent.is_empty(), "ogni arma suona allo sparo e all'impatto (muti: %s)" % ", ".join(silent))
	var fallback: Array[String] = []
	for weapon_id: StringName in WEAPON_SOUNDS:
		for kind: StringName in WEAPON_SOUNDS[weapon_id]:
			if _audio.weapon_sound_id(weapon_id, kind) != StringName("w_%s_%s" % [weapon_id, kind]):
				fallback.append("%s/%s" % [weapon_id, kind])
	_check(fallback.is_empty(), "i suoni chiesti dalle armi hanno il loro campione (in ripiego: %s)" % ", ".join(fallback))
	_check(_audio.weapon_sound_id(&"nobody", &"fire") == &"nail_shot" and _audio.weapon_sound_id(&"nobody", &"hit") == &"terrain_raise",
		"arma senza campioni: ripiego su nail_shot e terrain_raise")
	# Un'arma vera del loadout: il suo segnale arriva fino a RunAudio.
	var added := loadout.add(&"seismic_stake")
	var stake: Weapon = added if added != null else loadout.weapon(&"seismic_stake")
	if stake != null:
		var sound := _audio.weapon_sound_id(&"seismic_stake", &"fire")
		var before := _count(sound)
		_audio._next_allowed.clear()
		stake.sound_requested.emit(&"fire")
		_check(_count(sound) == before + 1, "il picchetto nel loadout suona attraverso il loadout")
		_audio._next_allowed.clear()
		paused = true
		before = _count(sound)
		stake.sound_requested.emit(&"fire")
		paused = false
		_check(_count(sound) == before, "in pausa le armi non suonano")
	else:
		_check(false, "picchetto aggiunto al loadout")
	await _frames(1)


func _test_player_events() -> void:
	print("player")
	if _menu.is_open:
		_menu.close()
	_place_player(Vector3.ZERO)
	var dashes := _count(&"dash")
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = &"dash"
		event.pressed = pressed
		Input.parse_input_event(event)
	await _frames(6)
	_check(_count(&"dash") == dashes + 1, "dash: un soffio")
	await _frames(30)
	var hurts := _count(&"player_hurt")
	_player._invulnerable_left = 0.0
	_player.take_damage(1)
	_check(_count(&"player_hurt") == hurts + 1, "colpo subito: player_hurt")
	_player.set_max_health(_run.tuning.player_max_health)
	_check(_count(&"player_hurt") == hurts + 1, "la cura non suona come un colpo")


func _test_terrain_events() -> void:
	print("terrain")
	_place_player(Vector3.ZERO)
	# Il disco di partenza e protetto nei primi 10 s: via, per scolpire subito.
	_run._start_protect_left = 0.0
	_field.set_protected(Vector3.ZERO, _field.tuning.start_protected_radius_m, false)
	var digs := _count(&"terrain_dig")
	var raises := _count(&"terrain_raise")
	var dig_target := Vector3(4.8, 0.0, 4.8)
	# Tre pennellate nello stesso passo: un suono solo (al piu uno ogni 0,25 s).
	for i in 3:
		_field.player_sculpt(dig_target, 2.4, -0.3, TerrainField.ToolMode.DIG)
	_check(_count(&"terrain_dig") == digs + 1, "scavo continuo: un terrain_dig per passo (%d)" % (_count(&"terrain_dig") - digs))
	await _frames(20)
	_field.player_sculpt(Vector3(-4.8, 0.0, 4.8), 2.4, 0.3, TerrainField.ToolMode.RAISE)
	_check(_count(&"terrain_raise") == raises + 1, "rialzo: terrain_raise")
	_check(_count(&"terrain_dig") == digs + 1, "il rialzo non suona come uno scavo")
	await _frames(20)
	# Lo strumento del giocatore su un'area protetta: rifiuto.
	var rejects := _count(&"tool_reject")
	_player.terrain_tool_mode = TerrainField.ToolMode.DIG
	_player.look_at(Vector3(dig_target.x, _player.global_position.y, dig_target.z))
	_player._update_terrain_target()
	_field.set_protected(_player.terrain_target, 3.0, true)
	digs = _count(&"terrain_dig")
	_player.tool_held = true
	await _frames(3)
	_player.tool_held = false
	_check(_count(&"tool_reject") == rejects + 1 and _count(&"terrain_dig") == digs, "comando rifiutato: tool_reject")
	_field.set_protected(_player.terrain_target, 3.0, false)
	await _frames(12)
	# Alzare a zaino vuoto: stesso suono di rifiuto.
	_player.terrain_tool_mode = TerrainField.ToolMode.RAISE
	_player.pack.take(_player.pack.capacity)
	_player._update_terrain_target()
	_player.tool_held = true
	await _frames(3)
	_player.tool_held = false
	_check(_count(&"tool_reject") == rejects + 2, "alzare a zaino vuoto: tool_reject")
	_player.pack.give(20.0)
	_player.terrain_tool_mode = TerrainField.ToolMode.DIG
	await _frames(12)


func _test_scrap_events() -> void:
	print("scrap")
	_check(_audio.caravan == _caravan and _audio._last_carried == _caravan.carried, "l'audio ascolta i rottami della carovana (%d)" % _caravan.carried)
	# Posto per un rottame in piu (la carovana avvisa solo quando il totale cambia).
	_caravan.carried = mini(_caravan.carried, _caravan.capacity - 1)
	var pickups := _count(&"scrap_pickup")
	var spends := _count(&"scrap_spend")
	_caravan.add_scrap(1)
	_check(_count(&"scrap_pickup") == pickups + 1 and _count(&"scrap_spend") == spends, "cassone che cresce: scrap_pickup")
	_caravan.spend()
	_check(_count(&"scrap_spend") == spends + 1 and _count(&"scrap_pickup") == pickups + 1, "rottame speso: scrap_spend")
	_caravan.carried_changed.emit(_caravan.carried)
	_check(_count(&"scrap_spend") == spends + 1 and _count(&"scrap_pickup") == pickups + 1, "cassone invariato: silenzio")
	await _frames(12)


func _test_level_up_events() -> void:
	print("level up")
	_place_player(Vector3.ZERO)
	var level_ups := _count(&"level_up")
	var chosen := _count(&"upgrade_chosen")
	_xp.spawn(_player.global_position + Vector3(1.0, 0.0, 0.0), _run.progression.xp_to_next())
	await _frames(20)
	_check(_menu.is_open and paused, "menu aperto, gioco fermo")
	_check(_count(&"level_up") == level_ups + 1, "apertura del menu: level_up")
	# L'orologio del limite avanza anche in pausa.
	_check(not _audio.play(&"level_up"), "ripetizione immediata scartata anche in pausa")
	await _frames(30)
	_check(paused and _audio.play(&"level_up"), "in pausa il limite scade e il suono riparte")
	_menu.press(0)
	await _frames(2)
	_check(_count(&"upgrade_chosen") == chosen + 1, "carta scelta: upgrade_chosen")
	await _frames(10)
	if _menu.is_open:
		_menu.close()
	paused = false


func _test_boss_and_end_events() -> void:
	print("boss and end")
	_place_player(Vector3.ZERO)
	var warnings := _count(&"boss_warning")
	_run.boss_call_at = _run.elapsed + 0.05
	await _frames(6)
	_check(_run.boss_phase == ArenaRun.BossPhase.WARNING and _count(&"boss_warning") == warnings + 1, "boss annunciato: boss_warning")
	_run._boss_warning_left = 0.05
	await _frames(6)
	var boss := _run.boss as Demolisher
	_check(boss != null, "boss in campo")
	if boss == null:
		return
	var victories := _count(&"victory")
	var deaths := _count(&"player_death")
	# La piazzola di estrazione (D-076) ha la sua suite: qui la vittoria diretta.
	_run.extraction_pad = null
	boss.take_damage(boss.health)
	await _frames(2)
	_check(_run.is_over and paused, "livello completato, gioco fermo")
	_check(_count(&"victory") == victories + 1, "vittoria: victory, a gioco fermo")
	_check(_count(&"player_death") == deaths, "nessun suono di sconfitta sulla vittoria")
	# Il segnale died del giocatore basta: la run e gia chiusa.
	var hurts := _count(&"player_hurt")
	_player._invulnerable_left = 0.0
	_player.take_damage(_player.health)
	_check(_count(&"player_death") == deaths + 1, "giocatore abbattuto: player_death")
	_check(_count(&"player_hurt") == hurts, "il colpo mortale non suona anche come ferita")
	paused = false
