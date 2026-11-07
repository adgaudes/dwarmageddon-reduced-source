extends SceneTree
## Catture della carovana (D-093, piano A task 10 e piano B task 8), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 6000 --script res://tests/tools/capture_caravan.gd -- --out=../output/caravan --quake-at=0
## Seme fisso 20261014 (quello del gate) se `PROTOTYPE01_SEED` non e gia un intero: relitti e
## casse stanno sempre negli stessi punti. Produce, in quest'ordine:
##   wreck_glint    giocatore a 2 m dal primo relitto: bagliore arancione e telaio che spunta;
##   wreck_menu     il suolo del relitto torna alla base: menu "RELITTO SEPOLTO" (sceglie il Faro
##                  se c'e, altrimenti un modulo del grappolo, altrimenti la prima carta);
##   cluster_day    sei macchine (Torretta, Faro, Sirena, Trivella, Pala finche c'e posto)
##                  attorno al giocatore con 16 rottamatori robusti attorno;
##   broken         Torretta guasta a 1,2 m, 3 s dopo il guasto: fumo, punto esclamativo, anello
##                  rosso, tasto Ripara (campo `smoke=`: emettitore acceso);
##   retreat        una macchina a 1 PV si ritira dal lato opposto a 8 rottamatori;
##   cluster_night  il grappolo di notte con l'orda: luce dai soli Faro;
##   strip          striscia della carovana (Torretta in riparazione da 0,7 s, una macchina a 1 PV
##                  con la tinta della vita bassa: senza nemici non si ritira) con tre frecce
##                  degli indicatori verso il basso; poi la run resta ferma;
##   event_arrow    avviso di un evento con la freccia verso il basso a destra, sopra o dentro la
##                  colonna in basso a destra (osservazione HUD-2 del task 7, solo documentata);
##   machine_parts  primo piano dei sette pezzi dei moduli (Torretta, Calamita, Faro, Trivella,
##                  Pala, Saldatore, Sirena) su sette macchine fuori dalla carovana;
## poi quelle del piano B (la run riparte, camera di gioco, macchine riparate):
##   fusion_pad       pedana di fusione atterrata sotto il giocatore, col grappolo attorno e il
##                    tasto Banco acceso nella striscia;
##   fusion_pad_night la pedana di notte da circa 25 m (camera fissa, HUD nascosto): lampada e
##                    fascio di luce;
##   fusion_bench     banco aperto sulla pedana (Interagisci), base la Trivella e focus sulla
##                    Calamita: anteprima "Trivella + Calamita" con la combinazione "???";
##   fused_machine    la Trivella fusa con Calamita, Torretta e Sirena (Grande, quattro pezzi
##                    impilati) nel grappolo, 9 m a sud della pedana, camera vicina (11 m), casella
##                    larga nella striscia.
## Una riga `PROTOTYPE01_CAPTURE_CARAVAN shot=<nome> err=<n> ...` per cattura. Ogni teletrasporto
## azzera la velocita e chiama `reset_physics_interpolation()`; le attese sono in secondi di gioco.
## Il giocatore mira col controller e guarda verso la camera: l'anello del pennello sta davanti a
## lui, non sopra il relitto o le macchine.

const MACHINE_SCENE := preload("res://scenes/caravan/machine.tscn")
## Moduli del grappolo, nell'ordine in cui si aggiungono (il Faro presto: serve alla notte).
const CLUSTER: Array[StringName] = [&"turret", &"beacon", &"siren", &"drill", &"shovel"]
## Pezzi del primo piano: id del modulo e script (non una costante: le classi non lo sono).
var _parts: Array = [
	[&"turret", TurretModule], [&"magnet", MagnetModule], [&"beacon", BeaconModule],
	[&"drill", DrillModule], [&"shovel", ShovelModule], [&"welder", WelderModule], [&"siren", SirenModule],
]
const WRECK_TITLE := "RELITTO SEPOLTO"

var _out := "../output/caravan"
var _run: ArenaRun
var _player: PlayerCharacter
var _director: EnemyDirector
var _field: TerrainField
var _caravan: Caravan


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	if not OS.get_environment("PROTOTYPE01_SEED").is_valid_int():
		OS.set_environment("PROTOTYPE01_SEED", "20261014")
	var scene: Node3D = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(scene)
	_run = scene.get_node(^"Run")
	_player = scene.get_node(^"Player")
	_director = scene.get_node(^"EnemyDirector")
	_field = scene.get_node(^"TerrainField")
	_caravan = _run.caravan
	_director.spawning = false
	# Nessun level-up durante le catture: il menu metterebbe in pausa.
	_run.progression.xp_first_level = 1000000
	await _frames(20)
	_run._start_protect_left = 0.0
	_field.set_protected(Vector3.ZERO, _field.tuning.start_protected_radius_m, false)
	_player.grant_invulnerability(3000.0)
	_player._set_aim_device(PlayerCharacter.AimDevice.GAMEPAD)
	_place_player(Vector3.ZERO)
	var weapon := scene.get_node(^"PlayerWeapon") as AutoWeapon

	# La scritta del livello resta 4 s: le catture iniziano dopo.
	await _seconds(3.5)
	if _run.wrecks == null or _run.wrecks.count() == 0 or _run.wrecks.frame_of(0) == null:
		push_warning("capture_caravan: nessun relitto chiuso, salto wreck_glint e wreck_menu")
		print("PROTOTYPE01_CAPTURE_CARAVAN shot=wreck_glint skipped=no_wrecks")
		print("PROTOTYPE01_CAPTURE_CARAVAN shot=wreck_menu skipped=no_wrecks")
	else:
		await _wreck_shots()

	# Grappolo di giorno, nel cortile di partenza (piano, aperto).
	_place_player(Vector3.ZERO)
	await _seconds(1.0)
	var skipped: PackedStringArray = []
	for id in CLUSTER:
		if _caravan.count_of(id) > 0:
			continue
		if not _caravan.has_room() or _caravan.add_machine(id) == null:
			skipped.append(String(id))
	for machine in _caravan.machines:
		machine.grant_invulnerability(3000.0)
	weapon.set_physics_process(false)
	await _seconds(1.5)
	_ring(16)
	await _seconds(1.2)
	await _shot("cluster_day", "machines=%d modules=%s enemies=%d skipped=%s" % [_caravan.machines.size(),
		_module_list(), _director.enemies.size(), ",".join(skipped) if not skipped.is_empty() else "none"])

	# Torretta guasta accanto al giocatore: fumo, punto esclamativo, anello rosso, tasto Ripara.
	# Senza l'orda attorno, che la coprirebbe.
	_director.clear_horde()
	await _seconds(0.5)
	var turret := _machine_with(&"turret")
	if turret == null:
		_abort("nessuna Torretta nella carovana per broken")
		return
	_break_beside_player(turret)
	# Il fumo (10 sbuffi in 1,6 s che salgono e crescono) e pieno dopo un ciclo intero: 3 s,
	# dentro la finestra di 1-6 s prima del Saldatore.
	var broken_at := _run.elapsed
	await _seconds(3.0)
	var smoke := turret.get_node_or_null(^"Smoke") as CPUParticles3D
	await _shot("broken", "state=%s prompt=%s smoke=%s smoke_s=%.1f" % [Machine.State.keys()[turret.state],
		_run.hud.caravan_strip().prompt_visible(), smoke != null and smoke.visible and smoke.emitting,
		_run.elapsed - broken_at])
	turret.repair(1.0)
	turret.grant_invulnerability(3000.0)

	# Ritirata: una macchina a 1 PV, otto rottamatori da un lato soltanto (nessun altro nemico).
	_director.clear_horde()
	await _seconds(0.5)
	turret.health = 1
	for i in 8:
		var at := _player.global_position + Vector3(8.0 + 2.0 * (i % 2), 0.0, -3.0 + i * 0.85)
		var enemy := _director.spawn_at(at)
		enemy.health = 1000
		enemy.max_health = 1000
	await _seconds(1.75)
	await _shot("retreat", "state=%s distance=%.1f" % [Machine.State.keys()[turret.state],
		Machine.planar_distance(turret.global_position, _player.global_position)])
	turret.health = turret.max_health
	_director.clear_horde()

	# Notte: il grappolo con l'orda, la luce viene solo dai Faro. Dopo 3,5 s la scritta E NOTTE
	# (3 s) e sparita.
	var day_elapsed := _run.elapsed
	_run.elapsed = _run.day_night.night_start_seconds + _run.day_night.dusk_seconds + 2.0
	await _seconds(2.5)
	_ring(16)
	await _seconds(1.2)
	var lit := 0
	for entry in _caravan.beacon_lights():
		if (entry.light as OmniLight3D).visible:
			lit += 1
	await _shot("cluster_night", "beacons_lit=%d enemies=%d" % [lit, _director.enemies.size()])
	# Di nuovo giorno (la run gira ancora): striscia e primo piano dei pezzi si leggono meglio.
	_run.elapsed = day_elapsed
	_director.clear_horde()
	weapon.set_physics_process(true)
	await _seconds(1.0)

	# Striscia della carovana, come capture_weapons.gd -- --caravan: dopo, la run resta ferma.
	# Senza nemici nessuna macchina si ritira: quella a 1 PV mostra solo la tinta della vita bassa.
	turret = _machine_with(&"turret")
	if turret == null:
		_abort("nessuna Torretta nella carovana per strip")
		return
	_break_beside_player(turret)
	var retreating := _first_other(turret)
	if retreating != null:
		retreating.health = 1
	_player.interact_held = true
	await _seconds(0.7)
	_run.set_physics_process(false)
	_player.interact_held = false
	var markers: Array[Dictionary] = []
	for direction: Vector2 in [Vector2(0.0, 1.0), Vector2(0.9, 0.44), Vector2(1.0, 0.6)]:
		markers.append({direction = direction, distance = 30.0, color = Color.WHITE, text = "X"})
	_run.hud.set_markers(markers)
	await _shot("strip", "column_top=%.0f marker_y=%.0f" % [_run.hud._corner.get_global_rect().position.y,
		_run.hud._marker_arrows[0].position.y])

	# Avviso di un evento con la freccia (HUD-2): la freccia ignora la colonna piu alta.
	_run.hud.set_markers([] as Array[Dictionary])
	_run.hud.set_event_warning("TERREMOTO", Vector3(1.0, 0.0, 0.6), 9.0, Color.WHITE)
	await _frames(2)
	await _shot("event_arrow", "arrow_y=%.0f column_top=%.0f" % [_run.hud._boss_arrow.position.y,
		_run.hud._corner.get_global_rect().position.y])

	await _parts_closeup(scene)
	await _fusion_shots(scene)
	quit()


## Relitto 0: bagliore e telaio a 2 m, poi il suolo torna alla base e si apre la scelta.
func _wreck_shots() -> void:
	var wrecks := _run.wrecks
	var at := wrecks.position_of(0)
	_place_player(at + Vector3(0.0, 0.0, 2.0))
	await _seconds(1.0)
	await _shot("wreck_glint", "glint=%s frame=%s" % [wrecks.glint_visible(0), wrecks.frame_of(0) != null])

	_field.reset_to_base(at, Vector2(1.5, 1.5))
	# Una cassa nello stesso punto apre prima la sua scelta (e un'arma col bivio un'altra).
	for attempt in 4:
		if not await _wait_menu():
			break
		if _run.level_up_menu.title_text() == WRECK_TITLE:
			break
		await create_timer(0.6, true).timeout
		_run.level_up_menu.press(0)
		await _frames(2)
	var menu := _run.level_up_menu
	if not menu.is_open or menu.title_text() != WRECK_TITLE:
		push_warning("capture_caravan: il menu del relitto non si e aperto")
		print("PROTOTYPE01_CAPTURE_CARAVAN shot=wreck_menu skipped=no_menu title=%s" % menu.title_text())
		return
	await create_timer(0.6, true).timeout
	var pick := _wreck_pick(menu)
	var names: PackedStringArray = []
	for i in menu.card_count():
		names.append(_card_name(menu, i))
	await _shot("wreck_menu", "title=%s cards=%d pick=%s offer=%s" % [menu.title_text().replace(" ", "_"),
		menu.card_count(), _card_name(menu, pick).replace(" ", "_"), "|".join(names).replace(" ", "_")])
	menu.press(pick)
	await _frames(2)


## Il menu e aperto (lo apre ArenaRun a fine passo): falso se non arriva entro 2 s.
func _wait_menu() -> bool:
	for i in int(2.0 * Engine.physics_ticks_per_second):
		if _run.level_up_menu.is_open:
			return true
		await physics_frame
	return _run.level_up_menu.is_open


## La carta "Nuova macchina: Faro"; altrimenti la prima di un modulo del grappolo; altrimenti 0.
func _wreck_pick(menu: LevelUpMenu) -> int:
	var wanted: Array[String] = []
	for id in [&"beacon"] + CLUSTER:
		wanted.append(MachineOffers.NAME_PREFIX + MachineCatalog.name_of(id))
	for name in wanted:
		for i in menu.card_count():
			if _card_name(menu, i) == name:
				return i
	return 0


static func _card_name(menu: LevelUpMenu, index: int) -> String:
	var lines := menu.card_text(index).split("\n")
	return lines[1] if lines.size() > 1 else ""


## Primo piano dei sette pezzi, HUD nascosto, su sette macchine fuori dalla carovana (passo
## spento, anello a terra nascosto); giocatore e carovana nascosti, come capture_actors.gd.
func _parts_closeup(scene: Node3D) -> void:
	_run.hud.visible = false
	_player.visible = false
	_caravan.visible = false
	var count := 0
	var closeup_machines: Array[Machine] = []
	var spacing := 1.4
	var first := -spacing * (_parts.size() - 1) * 0.5
	for i in _parts.size():
		var entry: Array = _parts[i]
		var id: StringName = entry[0]
		var machine: Machine = MACHINE_SCENE.instantiate()
		scene.add_child(machine)
		closeup_machines.append(machine)
		machine.set_physics_process(false)
		(machine.get_node(^"GroundRing") as Decal).visible = false
		var at := Vector3(first + i * spacing, 0.0, 0.0)
		machine.global_position = Vector3(at.x, _field.height_at(at) + Caravan.GROUND_CLEARANCE, at.z)
		machine.velocity = Vector3.ZERO
		machine.reset_physics_interpolation()
		var module: MachineModule = (entry[1] as GDScript).new()
		machine.mount_part(StringName("%sPart" % String(id).capitalize()), module.build_part())
		module.free()
		if machine.get_node_or_null(NodePath("%sPart" % String(id).capitalize())) != null:
			count += 1
	var closeup := Camera3D.new()
	closeup.fov = 35.0
	scene.add_child(closeup)
	closeup.make_current()
	var target := Vector3(0.0, _field.height_at(Vector3.ZERO) + 0.6, 0.0)
	var yaw := deg_to_rad(160.0)
	var pitch := deg_to_rad(24.0)
	closeup.look_at_from_position(target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 10.5, target)
	await _frames(6)
	await _shot("machine_parts", "parts=%d" % count)
	# Via le sette macchine e la camera del primo piano: dopo vengono gli scatti del piano B.
	for machine in closeup_machines:
		machine.queue_free()
	closeup.queue_free()
	_run.hud.visible = true
	_player.visible = true
	_caravan.visible = true


## Piano B: pedana, pedana di notte, banco e macchina fusa. La striscia ha spento il passo di
## ArenaRun (pedana e banco ne hanno bisogno: il banco si apre a fine passo) e lasciato un avviso.
func _fusion_shots(scene: Node3D) -> void:
	var pad := _run.fusion_pad
	var bench := _run.fusion_bench
	if pad == null or bench == null:
		_abort("nessuna pedana o banco nella run")
		return
	_run.set_physics_process(true)
	_run.hud.clear_event_warning()
	_run.hud.set_markers([] as Array[Dictionary])
	var game_camera := scene.get_node(^"CameraRig/Camera") as Camera3D
	game_camera.make_current()
	for machine in _caravan.machines:
		if machine.is_broken():
			machine.repair(1.0)
		machine.health = machine.max_health
		machine.grant_invulnerability(3000.0)
	_place_player(Vector3.ZERO)
	await _seconds(1.5)

	# Pedana atterrata sotto il giocatore, nel cortile (piano): discesa di 1,5 s, poi la scritta.
	pad.land_at(_player.global_position)
	await _seconds(2.5)
	await _shot("fusion_pad", "open=%s center=%.1f,%.1f on_pad=%s machines=%d bench_prompt=%s" % [pad.is_open(),
		pad.center.x, pad.center.z, pad.contains(_player.global_position), _caravan.machines.size(),
		_run.hud.caravan_strip().bench_prompt_visible()])

	# Di notte da circa 25 m: camera fissa a sud della pedana, HUD nascosto (non e la camera di gioco).
	var day_elapsed := _run.elapsed
	_run.elapsed = _run.day_night.night_start_seconds + _run.day_night.dusk_seconds + 2.0
	await _seconds(2.5)
	var far := Camera3D.new()
	far.fov = 50.0
	scene.add_child(far)
	var eye := pad.center + Vector3(0.0, 8.0, 24.0)
	far.look_at_from_position(eye, pad.center + Vector3.UP * 3.0)
	far.make_current()
	_run.hud.visible = false
	await _frames(6)
	var lamp := pad.light()
	await _shot("fusion_pad_night", "distance=%.1f lamp=%s energy=%.2f range=%.1f" % [eye.distance_to(pad.center),
		lamp != null and lamp.visible, lamp.light_energy if lamp != null else 0.0, lamp.omni_range if lamp != null else 0.0])
	far.queue_free()
	game_camera.make_current()
	_run.hud.visible = true
	_run.elapsed = day_elapsed
	await _seconds(1.5)

	# Trivella e Calamita piccole nella carovana (si fa posto togliendo un'altra macchina), rottami
	# per pagare le fusioni, giocatore al centro della pedana; Interagisci apre il banco.
	var drill := await _small_machine(&"drill", [] as Array[Machine])
	var magnet := await _small_machine(&"magnet", [drill] as Array[Machine])
	if drill == null or magnet == null:
		_abort("Trivella o Calamita non entrano nella carovana")
		return
	_caravan.add_cargo_capacity(10)
	_caravan.add_scrap(10)
	_place_player(pad.center)
	await _seconds(1.5)
	_player.interact_pressed.emit()
	for i in int(2.0 * Engine.physics_ticks_per_second):
		if bench.is_open:
			break
		await physics_frame
	if not bench.is_open:
		_abort("il banco non si e aperto sulla pedana")
		return
	# Grazia del banco (0,4 s), poi base la Trivella e focus sulla Calamita.
	await _seconds(0.6)
	bench.select(_caravan.machines.find(drill))
	await _frames(2)
	bench.card(_caravan.machines.find(magnet)).grab_focus()
	await _frames(3)
	await _shot("fusion_bench", "open=%s cards=%d preview=%s" % [bench.is_open, bench.card_count(),
		bench.preview_text().replace("\n", "|").replace(" ", "_")])

	# Conferma, poi Torretta e Sirena nella stessa macchina: una Grande coi quattro pezzi impilati.
	bench.select(_caravan.machines.find(magnet))
	for id: StringName in [&"turret", &"siren"]:
		var other := _single_machine(id, drill)
		if other != null:
			bench.fuse(_caravan.machines.find(drill), _caravan.machines.find(other))
	bench.close()
	drill.grant_invulnerability(3000.0)
	# Giocatore 9 m a sud della pedana: il grappolo lo segue e il fascio resta fuori dal quadro.
	_place_player(pad.center + Vector3(0.0, 0.0, 9.0))
	await _seconds(3.0)
	var rig := scene.get_node(^"CameraRig") as IsometricCameraRig
	rig.set_distance_index(0, true)
	await _seconds(1.0)
	var index := _caravan.machines.find(drill)
	var strip := _run.hud.caravan_strip()
	await _shot("fused_machine", "size=%s modules=%s slot_size=%d slot_w=%.0f machines=%d" % [
		MachineFusion.SIZE_NAMES[drill.size], ",".join(drill.module_ids()), strip.slot_size(index),
		strip.slot_width(index), _caravan.machines.size()])


## Una macchina di un solo modulo [param module_id] nella carovana: quella che c'e, altrimenti una
## nuova; se non c'e posto esce l'ultima macchina che non e il capofila ne in [param keep].
func _small_machine(module_id: StringName, keep: Array[Machine]) -> Machine:
	var found := _single_machine(module_id, null)
	if found != null:
		return found
	if not _caravan.has_room():
		for i in range(_caravan.machines.size() - 1, -1, -1):
			var machine := _caravan.machines[i]
			if machine != _caravan.lead() and not keep.has(machine):
				_caravan.remove_machine(machine)
				break
		await _frames(2)
	var added := _caravan.add_machine(module_id)
	if added != null:
		added.grant_invulnerability(3000.0)
	return added


## La prima macchina con il solo modulo [param module_id], diversa da [param other], o null.
func _single_machine(module_id: StringName, other: Machine) -> Machine:
	for machine in _caravan.machines:
		if machine != other and machine.modules.size() == 1 and machine.has_module(module_id):
			return machine
	return null


## Rompe [param machine] a 1,2 m dal giocatore nello stesso passo (come capture_weapons), a
## nord-est: la camera la vede accanto al giocatore, non dietro di lui.
func _break_beside_player(machine: Machine) -> void:
	var at := _player.global_position + Vector3(0.85, 0.0, -0.85)
	machine.global_position = Vector3(at.x, _field.height_at(at) + Caravan.GROUND_CLEARANCE, at.z)
	machine.velocity = Vector3.ZERO
	machine.reset_physics_interpolation()
	machine._hit_cooldown_left = 0.0
	machine._invulnerable_left = 0.0
	machine.take_hit(machine.health)


## Giocatore in [param at] (XZ), sul suolo, fermo, rivolto verso la camera.
func _place_player(at: Vector3) -> void:
	_player.global_position = Vector3(at.x, _field.height_at(at) + 0.88, at.z)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = PI
	_player.reset_physics_interpolation()


## [param count] rottamatori robusti (1000 PV) a 6-8 m dal centro del grappolo.
func _ring(count: int) -> void:
	var center := Vector3.ZERO
	for machine in _caravan.machines:
		center += machine.global_position
	center /= maxi(_caravan.machines.size(), 1)
	for i in count:
		var angle := TAU * i / count
		var enemy := _director.spawn_at(center + Vector3(cos(angle), 0.0, sin(angle)) * (6.0 + 2.0 * (i % 2)))
		enemy.health = 1000
		enemy.max_health = 1000


## Uscita con errore da uno scatto impossibile (invece di un accesso a null fino a `--quit-after`).
func _abort(reason: String) -> void:
	push_warning("capture_caravan: %s" % reason)
	print("PROTOTYPE01_CAPTURE_CARAVAN aborted=%s" % reason.replace(" ", "_"))
	quit(1)


func _machine_with(module_id: StringName) -> Machine:
	for machine in _caravan.machines:
		if machine.has_module(module_id):
			return machine
	return null


## La prima macchina che non e ne il capofila ne [param other].
func _first_other(other: Machine) -> Machine:
	for machine in _caravan.machines:
		if machine != other and machine != _caravan.lead():
			return machine
	return null


func _module_list() -> String:
	var ids: PackedStringArray = []
	for machine in _caravan.machines:
		ids.append(String(machine.primary_module_id()))
	return ",".join(ids)


func _seconds(seconds: float) -> void:
	await _frames(int(seconds * Engine.physics_ticks_per_second))


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _shot(name: String, fields: String) -> void:
	var err := await _save(name)
	print("PROTOTYPE01_CAPTURE_CARAVAN shot=%s err=%d %s" % [name, err, fields])


func _save(name: String) -> int:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
	return err
