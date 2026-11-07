extends SceneTree
## Benchmark dell'arena grande (D-042), non e una suite. Misura costruzione e
## costo per frame con l'orda al massimo. In --headless misura solo CPU
## (script e fisica); con finestra anche il frame completo e le draw call:
##   godot_console --path godot --resolution 1280x800 --script res://tests/tools/benchmark_arena.gd -- --enemies=70
## `--enemies=N` (default: max_alive del tuning) per isolare il costo dell'orda; `--level=railway` misura il livello 2.
## `--no-motion` spegne il movimento procedurale degli attori (ActorMotion) per confronto;
## `--motion-ab` misura nello stesso processo il passo del direttore con e senza (riga `motion_ab`).
## `--no-fx` spegne gli effetti delle armi (WeaponFx, piano 5) per confronto con la riga `weapons_frame`.
## `--preset=deck|low|medium|high|max` (restyling 2026-10-11) applica il preset grafico prima di
## costruire l'arena; il limite di fps viene tolto, cosi il frame misurato e il costo reale.
## Sul rilievo continuo (D-085) misura anche la base (`apply_base_relief`), 100 pennellate
## casuali del giocatore e l'aggiornamento dei chunk di collisione (riga `terrain`); poi una
## corsa di 6 s con il costo massimo del ricentro del campo di percorso (riga `run`).
## `--night` porta il ciclo alla notte con sei lampioni e sei Faro accesi (carovana D-093: la
## luce viene solo dai Faro; tuning della carovana copiato in memoria col settimo posto): 13
## luci logiche con la torcia (riga `night`).
## Carovana (D-093, budget 0,5 ms per passo sul preset Deck): righe `caravan` (passo medio e
## peggiore della carovana in un ciclo della Sirena, contatto dei rottamatori come A/B del
## direttore), `caravan_writes` (scritture della coda nel ciclo) e `caravan_slots` (calcolo del
## posto di ogni macchina); di giorno Cassone, due Torrette, Trivella, Pala e Sirena, di notte
## il Cassone e i sei Faro. Di giorno poi la riga `caravan_colossus` (piano B): le sei macchine
## fuse nel capofila, un Colosso di sei moduli, misurato nella stessa finestra. Poi le armi
## (`weapons`, `weapons_fused`, `weapons_frame`), con le macchine immuni e i moduli fermi tranne il
## Cassone del capofila.
## Marker: PROTOTYPE01_ARENA_BENCH ...

const WARMUP_FRAMES := 120
## Anello dei robusti durante la finestra della carovana (`_bench_caravan`), dal giocatore: 7 e 9 m.
const WRITE_RING_M := 7.0
const MEASURE_FRAMES := 600
const PRESET_ARGS := {"deck": GameSettingsService.Preset.STEAM_DECK, "low": GameSettingsService.Preset.LOW,
	"medium": GameSettingsService.Preset.MEDIUM, "high": GameSettingsService.Preset.HIGH, "max": GameSettingsService.Preset.MAX}


## Bivi del caso peggiore per le armi di classe (i piu pesanti: piu colpi, piu oggetti a terra).
const HEAVY_PICKS := {
	&"nailgun": [&"a", &"b"], &"seismic_stake": [&"b", &"a"],
	&"scrap_launcher": [&"a", &"a"], &"dig_charge": [&"a", &"b"],
	&"welder": [&"a", &"a"], &"crane_magnet": [&"b", &"a"],
	&"scythe": [&"a", &"b"], &"bramble": [&"a", &"a"],
}


## Caso peggiore delle armi (D-092, budget 1,0 ms per passo), per la classe di `--class=`:
## cinque slot pieni al livello 5, kit della classe coi bivi di HEAVY_PICKS, Ruspa a dischi
## (Lama fusa con l'Ariete), Martello e Betoniera; attive appena usate; si misura il passo di
## tutte le armi del loadout e della coda delle scritture (riga `weapons`). Poi la classe si
## fonde e si rimisura (riga `weapons_fused`).
func _bench_loadout(scene: Node, step: float) -> void:
	var run: ArenaRun = scene.get_node(^"Run")
	var loadout := run.loadout
	var kit := ClassCatalog.start_weapons(run.class_id)
	if loadout == null or kit.size() < 2:
		return
	for id in kit:
		var picks: Array = HEAVY_PICKS.get(id, [&"a", &"a"])
		loadout.level_up(id)
		loadout.choose_branch(id, picks[0])
		loadout.level_up(id)
		loadout.choose_branch(id, picks[1])
	for id in [&"site_blade", &"jackhammer", &"ram"]:
		loadout.add(id)
		_max_out(loadout, id)
	loadout.fuse(&"site_blade")
	loadout.add(&"cement_mixer")
	_max_out(loadout, &"cement_mixer")
	# L'orda nasce oltre la portata: per il caso peggiore 20 nemici robusti entro 6 m.
	var player: PlayerCharacter = scene.get_node(^"Player")
	# L'orda robusta lo morde per tutta la misura: morto, il pannello di fine mette in pausa.
	player.grant_invulnerability(120.0)
	# Anche le macchine della carovana (D-093): i robusti le mordono, e una guasta cambierebbe
	# la misura.
	if run.caravan != null:
		for machine in run.caravan.machines:
			machine.grant_invulnerability(120.0)
	for i in 20:
		var angle := TAU * i / 20.0
		var enemy := run.director.spawn_at(player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * (3.0 + 3.0 * (i % 2)))
		enemy.health = 1000
		enemy.max_health = 1000
	loadout.trigger_active(0)
	loadout.trigger_active(1)
	for i in 120:
		await physics_frame
	var weapons_ms := _time_weapons(run, step)
	await _weapons_frame(run)
	var auto_id := kit[0]
	var fused_ms := -1.0
	if loadout.fuse(auto_id):
		# Il Fortino alza la prima torretta dopo 10 s.
		for i in int(12.0 * Engine.physics_ticks_per_second):
			await physics_frame
		fused_ms = _time_weapons(run, step)
	print("PROTOTYPE01_ARENA_BENCH weapons_fused class=%s worst_ms=%.3f slots=%s"
		% [run.class_id, fused_ms, ",".join(PackedStringArray(loadout.all_ids()))])
	_bench_writes(run, player, step, weapons_ms)


## Frame medio con le armi del caso peggiore che sparano davvero, effetti compresi (piano 5):
## la riga `weapons` misura il passo delle armi, non le particelle che ne nascono. Le attive
## ripartono ogni secondo; con `--no-fx` lo stesso senza effetti.
func _weapons_frame(run: ArenaRun) -> void:
	# I livelli presi sopra (e l'esperienza dell'orda) aprono il menu di level-up, che mette in
	# pausa: qui serve il gioco vivo, quindi la corsa non apre menu durante la misura.
	var was_paused := paused
	run.set_physics_process(false)
	run.level_up_menu.close()
	paused = false
	await process_frame
	if paused:
		push_error("weapons_frame: albero ancora in pausa, misura non valida")
	var frames := 900
	var total := 0.0
	var process_total := 0.0
	var fx_total := 0
	var fx_most := 0
	var last := Time.get_ticks_usec()
	for i in frames:
		if i % 120 == 0:
			for active in run.loadout.actives():
				active.cooldown_left = 0.0
			run.loadout.trigger_active(0)
			run.loadout.trigger_active(1)
		await process_frame
		var now := Time.get_ticks_usec()
		total += (now - last) / 1000.0
		last = now
		process_total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var fx := get_node_count_in_group(WeaponFx.GROUP)
		fx_total += fx
		fx_most = maxi(fx_most, fx)
	paused = was_paused
	run.set_physics_process(true)
	print("PROTOTYPE01_ARENA_BENCH weapons_frame class=%s fx=%s avg_frame_ms=%.2f avg_process_ms=%.2f fx_avg=%.1f fx_max=%d"
		% [run.class_id, WeaponFx.enabled, total / frames, process_total / frames, float(fx_total) / frames, fx_most])


## Passo medio (ms) di tutte le armi del loadout e della coda delle scritture, su 240 passi.
func _time_weapons(run: ArenaRun, step: float) -> float:
	var loadout := run.loadout
	# Anche i figli che hanno un passo proprio: torrette del Fortino, rovi del Roveto e della Falciarovi.
	var nodes: Array[Node] = []
	for weapon: Node in loadout.autos() + loadout.actives():
		nodes.append(weapon)
		for child in weapon.find_children("*", "", true, false):
			if child.is_physics_processing():
				nodes.append(child)
	nodes.append(run.write_queue)
	for node in nodes:
		node.set_physics_process(false)
	var t0 := Time.get_ticks_usec()
	for i in 240:
		for node in nodes:
			node._physics_process(step)
	var ms := (Time.get_ticks_usec() - t0) / 240000.0
	for node in nodes:
		node.set_physics_process(true)
	return ms


## Anello che sale e indurimento della Betoniera, poi la riga `weapons`.
func _bench_writes(run: ArenaRun, player: Node3D, step: float, weapons_ms: float) -> void:
	var loadout := run.loadout
	var t0 := 0
	# Un anello che sale: una pennellata del picchetto (con collisione e segnale) per passo.
	var queue := run.write_queue
	queue.set_physics_process(false)
	var center := player.global_position + Vector3(0.0, 0.0, -10.0)
	for i in 40:
		var angle := TAU * i / 40.0
		var p := center + Vector3(cos(angle), 0.0, sin(angle)) * 3.0
		queue.push_level(p, 0.9, run.terrain_field.base_height_at(p) + 1.2)
	var jobs := queue.pending()
	t0 = Time.get_ticks_usec()
	while queue.pending() > 0:
		queue._physics_process(step)
	var raise_ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(jobs, 1.0)
	# Indurimento della Betoniera (review I5): la pittura dello strato e sincrona su Terrain3D
	# (con finestra); le sue pennellate passano poi dalla coda, misurata sopra.
	var mixer := loadout.weapon(&"cement_mixer") as CementMixer
	var harden_ms := -1.0
	if mixer != null:
		t0 = Time.get_ticks_usec()
		mixer._harden({center = center + Vector3(6.0, 0.0, 0.0), radius = 3.0, stuck = []})
		harden_ms = (Time.get_ticks_usec() - t0) / 1000.0
		queue.clear()
	queue.set_physics_process(true)
	print("PROTOTYPE01_ARENA_BENCH weapons_harden ms=%.3f (una volta per pozza)" % harden_ms)
	print("PROTOTYPE01_ARENA_BENCH weapons class=%s worst_ms=%.3f ring_write_ms=%.3f"
		% [run.class_id, weapons_ms, raise_ms])


## Carovana (D-093, piano A; budget 0,5 ms per passo sul preset Deck). Di giorno sei macchine
## (Cassone, due Torrette, Trivella, Pala, Sirena), di notte il Cassone e i sei Faro accesi messi
## dalla riga `night`; giocatore e macchine immuni, 20 rottamatori robusti a 2-4 m dal grappolo
## (i 70 dell'orda restano lontani e contano solo nelle scansioni su tutti i nemici). Si misura un ciclo intero della Sirena
## (attiva e ferma) passo per passo, come `_time_weapons`: carovana, macchine coi figli che hanno
## un passo (le torrette) e la coda delle scritture (buche della Trivella, argini della Pala; per
## la finestra i robusti stanno a 7-9 m dal giocatore, cosi Trivella e Pala scrivono davvero);
## `step_ms` e la media, `max_ms` il passo peggiore. Il contatto coi rottamatori sta nel passo del
## direttore: A/B a blocchi alterni con e senza carovana, come `--motion-ab` (la scansione gira
## anche sulle macchine immuni). Riga `caravan_slots`: `slot_target` di tutte le macchine, il
## posto che ogni macchina ricalcola a ogni passo. Il costo delle luci dei Faro accesi sta nelle
## righe `step`, `frame` e `render` (di notte il direttore rinfresca il campo di luce a ogni passo).
## Di giorno, coi robusti ancora sul grappolo, `_bench_colossus` fonde tutto nel capofila e
## rimisura (riga `caravan_colossus`); di notte no (i sei Faro restano macchine piccole).
## Alla fine i moduli si spengono (tranne il Cassone del capofila) e i robusti spariscono.
func _bench_caravan(scene: Node, step: float, preset: String, night: bool) -> void:
	var run: ArenaRun = scene.get_node(^"Run")
	var caravan := run.caravan
	if caravan == null or caravan.lead() == null:
		print("PROTOTYPE01_ARENA_BENCH caravan skipped=no_caravan")
		return
	var director := run.director
	var player: PlayerCharacter = scene.get_node(^"Player")
	var queue := run.write_queue
	# Gioco vivo e niente menu, come `_weapons_frame`: l'esperienza dell'orda aprirebbe il level-up.
	var was_paused := paused
	var run_was_on := run.is_physics_processing()
	run.set_physics_process(false)
	run.level_up_menu.close()
	paused = false
	# `--motion-ab` lascia spento il passo del direttore: qui l'orda deve arrivare al grappolo.
	var director_was_on := director.is_physics_processing()
	director.set_physics_process(true)
	if not night:
		for id: StringName in [&"turret", &"turret", &"drill", &"shovel", &"siren"]:
			if caravan.add_machine(id) == null:
				push_error("caravan bench: add_machine(%s) e null" % id)
		if caravan.module_count() != 6:
			push_error("caravan bench: %d moduli invece di 6" % caravan.module_count())
		# La Pala paga 1 rottame solo se ne restano 2 per una riparazione: Cassone pieno.
		caravan.add_cargo_capacity(18)
		caravan.add_scrap(18)
	player.grant_invulnerability(120.0)
	for machine in caravan.machines:
		machine.grant_invulnerability(120.0)
	for i in 60:
		await physics_frame
	var centroid := Vector3.ZERO
	for machine in caravan.machines:
		centroid += machine.global_position
	centroid /= caravan.machines.size()
	var robust: Array[Enemy] = []
	for i in 20:
		var angle := TAU * i / 20.0
		var enemy := director.spawn_at(centroid + Vector3(cos(angle), 0.0, sin(angle)) * (2.0 + 2.0 * (i % 2)))
		enemy.health = 1000
		enemy.max_health = 1000
		robust.append(enemy)
	for i in 120:
		await physics_frame

	var window := _caravan_window(run, player, robust, step)
	print("PROTOTYPE01_ARENA_BENCH caravan_writes writes=%d steps=%d" % [window.writes, window.steps])

	# Contatto dei rottamatori (EnemyDirector._apply_machine_contacts): stesso processo, blocchi
	# alterni con e senza carovana nel direttore.
	director.set_physics_process(false)
	var totals := [0, 0]
	for block in 40:
		director.caravan = caravan if block % 2 == 0 else null
		var b0 := Time.get_ticks_usec()
		for i in 30:
			director._physics_process(step)
		totals[block % 2] += Time.get_ticks_usec() - b0
	director.caravan = caravan
	var modules: PackedStringArray = []
	for machine in caravan.machines:
		modules.append(String(machine.primary_module_id()))
	print("PROTOTYPE01_ARENA_BENCH caravan preset=%s machines=%d modules=%s enemies=%d step_ms=%.3f director_on_ms=%.3f director_off_ms=%.3f max_ms=%.3f"
		% [preset, caravan.machines.size(), ",".join(modules), director.enemies.size(), window.step_ms,
			totals[0] / 600000.0, totals[1] / 600000.0, window.max_ms])
	# Posto nel grappolo (task 6): ogni macchina lo ricalcola a ogni passo; un passo = tutte.
	var s0 := Time.get_ticks_usec()
	for i in 240:
		for machine in caravan.machines:
			caravan.slot_target(machine)
	print("PROTOTYPE01_ARENA_BENCH caravan_slots machines=%d slot_target_ms=%.4f"
		% [caravan.machines.size(), (Time.get_ticks_usec() - s0) / 240.0 / 1000.0])

	if not night:
		await _bench_colossus(run, player, robust, step, preset)

	# Pulizia: moduli spenti tranne il Cassone del capofila (di giorno il Colosso ha anche gli
	# altri cinque), robusti tolti senza esperienza (non con `clear_horde`, il cui tween a gioco
	# fermo non finisce), coda vuota, stati di prima.
	var lead := caravan.lead()
	for machine in caravan.machines:
		for module in machine.modules:
			if machine != lead or module.module_id != &"cargo":
				module.set_active(false)
	for enemy in robust:
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue
		enemy.is_dead = true
		enemy.collision_layer = 0
		enemy.collision_mask = 0
		director.enemies.erase(enemy)
		enemy.queue_free()
	queue.clear()
	director.set_physics_process(director_was_on)
	run.set_physics_process(run_was_on)
	paused = was_paused


## Colosso (D-093, piano B; budget 0,5 ms per passo sul preset Deck, come le sei macchine): coi
## 20 robusti ancora sul grappolo, i rottami per fondere tutto nel capofila (`fuse_cost_per_module`
## per modulo assorbito) entrano prima nei Cassoni; poi le altre cinque macchine entrano nel
## capofila con `Caravan.fuse` (fuori dal banco: fra due passi, nessun nodo e a meta del suo),
## 60 passi di assestamento e la stessa finestra della riga `caravan`. `trampled` = rottamatori
## travolti dal Colosso dalla fusione alla fine della finestra (il travolgere sta nel passo del
## direttore, che gira nei 60 passi di assestamento, non nella finestra).
func _bench_colossus(run: ArenaRun, player: PlayerCharacter, robust: Array[Enemy], step: float, preset: String) -> void:
	var caravan := run.caravan
	var lead := caravan.lead()
	var others: Array[Machine] = []
	var cost := 0
	for machine in caravan.machines:
		if machine != lead:
			others.append(machine)
			cost += MachineFusion.fuse_cost(machine.modules.size(), caravan.tuning)
	caravan.add_cargo_capacity(cost)
	caravan.add_scrap(cost)
	# L'A/B del contatto ha lasciato spento il passo del direttore: nell'assestamento i robusti
	# devono muoversi e il Colosso travolgerli (la pulizia rimette lo stato di prima).
	run.director.set_physics_process(true)
	for machine in others:
		if not caravan.fuse(lead, machine):
			push_error("colossus bench: fuse(%s) rifiutata" % machine.primary_module_id())
	if lead.size != MachineFusion.Size.COLOSSUS:
		push_error("colossus bench: taglia %d invece del Colosso" % lead.size)
	lead.grant_invulnerability(120.0)
	var trampled_before := lead.trampled
	for i in 60:
		await physics_frame
	var window := _caravan_window(run, player, robust, step)
	print("PROTOTYPE01_ARENA_BENCH caravan_colossus preset=%s machines=%d modules=%d size=%d enemies=%d step_ms=%.3f max_ms=%.3f trampled=%d"
		% [preset, caravan.machines.size(), caravan.module_count(), lead.size, run.director.enemies.size(),
			window.step_ms, window.max_ms, lead.trampled - trampled_before])


## Finestra della carovana (righe `caravan` e `caravan_colossus`): un ciclo della Sirena passo per
## passo coi nodi della carovana spenti e chiamati a mano, i robusti su un anello a WRITE_RING_M dal
## giocatore e poi rimessi dov'erano. `{step_ms, max_ms, writes, steps}`.
func _caravan_window(run: ArenaRun, player: PlayerCharacter, robust: Array[Enemy], step: float) -> Dictionary:
	var caravan := run.caravan
	var queue := run.write_queue
	# Nodi col passo della carovana: lei (riparazione), ogni macchina e i suoi discendenti col
	# passo (TurretWeapon), poi la coda delle scritture; spenti durante la misura.
	var nodes: Array[Node] = [caravan]
	for machine in caravan.machines:
		nodes.append(machine)
		for child in machine.find_children("*", "", true, false):
			if child.is_physics_processing() and not nodes.has(child):
				nodes.append(child)
	nodes.append(queue)
	var was_on: Array[bool] = []
	for node in nodes:
		was_on.append(node.is_physics_processing())
		node.set_physics_process(false)
	# Trivella e Pala scrivono solo verso un nemico lontano dalla macchina: la buca nasce a 1 m da
	# lui e l'argine a `shovel_gap`, mai entro `keep_clear` da macchine e giocatore. I robusti
	# arrivati addosso al grappolo (circa 2,4 m dalla Trivella e dalla Pala) non danno scritture,
	# e nella finestra non si muovono (il direttore e fermo). Per la finestra vanno su un anello a
	# WRITE_RING_M dal giocatore: dai posti a 3,5 m di Trivella e Pala il piu vicino sta a 3,5-4 m,
	# dentro `drill_reach` e `shovel_reach`, e buca e argine cadono fuori da ogni `keep_clear`.
	# Dopo la finestra tornano dov'erano, per l'A/B del contatto.
	var field := run.terrain_field
	var held_at: Array[Vector3] = []
	for i in robust.size():
		var enemy := robust[i]
		held_at.append(enemy.global_position if is_instance_valid(enemy) else Vector3.ZERO)
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue
		var angle := TAU * i / robust.size()
		var ring := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * (WRITE_RING_M + 2.0 * (i % 2))
		ring.y = (field.height_at(ring) if field != null else player.global_position.y) + enemy.spawn_center_height()
		_teleport_enemy(enemy, ring)
	# Coda vuota prima della misura (senza tempo) e moduli all'inizio della loro fase: Trivella e
	# Pala lavorano al primo passo, la Sirena parte attiva.
	while queue.pending() > 0:
		queue._physics_process(step)
	for module in caravan.modules_of(&"drill"):
		(module as DrillModule)._drill_left = 0.0
	for module in caravan.modules_of(&"shovel"):
		(module as ShovelModule)._shovel_left = 0.0
	for module in caravan.modules_of(&"siren"):
		(module as SirenModule)._cycle_time = 0.0
	var steps := int(round(caravan.tuning.siren_period * Engine.physics_ticks_per_second))
	var total_usec := 0
	var max_usec := 0
	var writes := 0
	for i in steps:
		var t0 := Time.get_ticks_usec()
		for node in nodes:
			if node == queue:
				var before := queue.pending()
				queue._physics_process(step)
				writes += before - queue.pending()
			else:
				node._physics_process(step)
		var took := Time.get_ticks_usec() - t0
		total_usec += took
		max_usec = maxi(max_usec, took)
	for i in nodes.size():
		nodes[i].set_physics_process(was_on[i])
	for i in robust.size():
		if is_instance_valid(robust[i]) and not robust[i].is_dead:
			# Un argine alzato nella finestra puo stare sotto il punto di prima: mai sotto il suolo.
			var back := held_at[i]
			if field != null:
				back.y = maxf(back.y, field.height_at(back) + robust[i].spawn_center_height())
			_teleport_enemy(robust[i], back)
	return {step_ms = total_usec / float(steps) / 1000.0, max_ms = max_usec / 1000.0, writes = writes, steps = steps}


static func _teleport_enemy(enemy: Enemy, at: Vector3) -> void:
	enemy.global_position = at
	enemy.velocity = Vector3.ZERO
	enemy.reset_physics_interpolation()


static func _max_out(loadout: WeaponLoadout, id: StringName) -> void:
	while loadout.level_of(id) > 0 and loadout.level_of(id) < WeaponCatalog.MAX_LEVEL:
		if loadout.needs_branch(id):
			loadout.choose_branch(id, &"a")
		else:
			loadout.level_up(id)


func _initialize() -> void:
	var preset_name := "high"
	var settings := root.get_node_or_null("GameSettings") as GameSettingsService
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset=") and settings != null:
			preset_name = arg.trim_prefix("--preset=")
			settings.set_preset(PRESET_ARGS.get(preset_name, GameSettingsService.Preset.HIGH))
	# Il limite di fps (default 60) coprirebbe il costo reale del frame.
	Engine.max_fps = 0
	var level_id := &"district"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_id = StringName(arg.trim_prefix("--level="))
	var start := Time.get_ticks_usec()
	var scene: Node3D = (load(LevelCatalog.scene_of(level_id)) as PackedScene).instantiate()
	root.add_child(scene)
	var instantiate_usec := Time.get_ticks_usec() - start
	var district: RuinsDistrict = scene.get_node(^"District")
	var field: TerrainField = scene.get_node_or_null(^"TerrainField")
	var director: EnemyDirector = scene.get_node(^"EnemyDirector")
	var path: PathField = scene.get_node(^"PathField")
	var player: PlayerCharacter = scene.get_node(^"Player")
	var tuning: RunTuning = director.tuning
	var enemy_target := tuning.max_alive
	var night := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			enemy_target = arg.trim_prefix("--enemies=").to_int()
		elif arg == "--no-motion":
			# Senza il movimento procedurale degli attori: misura quanto costa.
			ActorMotion.enabled = false
		elif arg == "--no-fx":
			# Senza gli effetti delle armi (piano 5): confronto della riga `weapons_frame`.
			WeaponFx.enabled = false
		elif arg == "--night":
			# Misura di notte: il ciclo e portato oltre il tramonto prima dell'orda.
			night = true
	director.spawning = false
	# Il campo di percorso legge gli ostacoli dopo due passi fisici.
	for i in 5:
		await physics_frame
	# La scena riapplica le impostazioni (e il limite di fps) al suo avvio: si toglie di nuovo.
	Engine.max_fps = 0

	var t := Time.get_ticks_usec()
	district.rebuild()
	var arena_usec := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	var grid_usec := 0
	var layout_usec := 0
	if field != null:
		# Base del rilievo ricalcolata (come senza `base.bin`), poi le pennellate del quartiere.
		district.apply_base_relief(field)
		grid_usec = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		district.apply_strokes(field)
		district.settle_on_relief()
		layout_usec = Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	path.scan_static_obstacles()
	var scan_usec := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	path.solve()
	var solve_usec := Time.get_ticks_usec() - t

	print("PROTOTYPE01_ARENA_BENCH build instantiate_ms=%.1f arena_ms=%.1f base_ms=%.1f layout_ms=%.1f scan_ms=%.1f (%d chunk) solve_ms=%.2f"
		% [instantiate_usec / 1000.0, arena_usec / 1000.0, grid_usec / 1000.0, layout_usec / 1000.0,
			scan_usec / 1000.0, path.chunks_scanned, solve_usec / 1000.0])
	if field != null:
		var collision: TerrainCollision = field.get_node(^"Collision")
		print("PROTOTYPE01_ARENA_BENCH content vertices=%d chunks=%d strokes=%d blocks=%d props=%d trees=%d tufts=%d flowers=%d"
			% [field.resolution_x * field.resolution_z, collision.chunk_count(), district.terrain_strokes.size(),
				district.stats.blocks, district.stats.props, district.stats.trees, district.stats.tufts, district.stats.flowers])
		# Cento pennellate casuali del giocatore (raggio del tuning) fuori dalle aree protette.
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var brush_total := 0
		var brush_max := 0
		var refreshed_before := collision.refreshed_count()
		for i in 100:
			var at := Vector3(rng.randf_range(-80.0, 80.0), 0.0, rng.randf_range(-80.0, 80.0))
			var b0 := Time.get_ticks_usec()
			field.player_sculpt(at, field.tuning.brush_radius_m, -0.03 if i % 2 == 0 else 0.03, TerrainField.ToolMode.DIG if i % 2 == 0 else TerrainField.ToolMode.RAISE)
			var took := Time.get_ticks_usec() - b0
			brush_total += took
			brush_max = maxi(brush_max, took)
		var refreshed := collision.refreshed_count() - refreshed_before
		print("PROTOTYPE01_ARENA_BENCH terrain brush_avg_ms=%.2f brush_max_ms=%.2f chunks=%d chunks_refreshed=%d chunk_refresh_ms=%.3f base_bake_ms=%.1f strokes_ms=%.1f"
			% [brush_total / 100000.0, brush_max / 1000.0, collision.chunk_count(), refreshed,
				(brush_total / 1000.0) / maxi(refreshed, 1), grid_usec / 1000.0, layout_usec / 1000.0])

	var run: ArenaRun = scene.get_node(^"Run")
	var lamps: LampField = scene.get_node_or_null(^"LampField")
	var caravan: Caravan = scene.get_node_or_null(^"Caravan")
	var lead: Machine = caravan.lead() if caravan != null else null
	if night:
		run.elapsed = run.day_night.night_start_seconds + run.day_night.dusk_seconds + 1.0
		await physics_frame
		# Sei lampioni attorno al giocatore: il massimo di luci logiche della tappa 2. Il punto
		# dell'esagono a 8 m puo non essere piano (cumuli, terremoto del seme): si prova
		# piu lontano o un poco girato, finche LampField lo accetta.
		caravan.add_cargo_capacity(18)
		caravan.add_scrap(18)
		lead.grant_invulnerability(120.0)
		for i in 6:
			var world: Variant = null
			for radius: float in [8.0, 9.5, 6.5, 11.0]:
				for turn: float in [0.0, 0.25, -0.25, 0.5, -0.5]:
					var angle := i * TAU / 6.0 + turn
					var candidate: Vector3 = player.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
					if world == null and lamps.can_place(candidate):
						world = candidate
			if world == null:
				continue
			lead.global_position = world + Vector3(0.0, 0.3, 1.5)
			lead.reset_physics_interpolation()
			lamps.place_at(world)
		lead.global_position = player.global_position + Vector3(3.0, 0.3, 0.0)
		lead.reset_physics_interpolation()
		# Sei Faro accesi (D-093: di notte illuminano solo i Faro). Il settimo posto sta nella
		# carovana (`extra_module_slots`), il tuning condiviso resta com'e: Cassone + sei Faro.
		caravan.extra_module_slots = 1
		for i in 6:
			var beacon := caravan.add_machine(&"beacon")
			if beacon == null:
				push_error("night bench: add_machine(beacon) e null")
				quit(1)
				return
			beacon.grant_invulnerability(120.0)
		# La ricostruzione del rilievo qui sopra apre casse e relitti, e il loro menu ferma l'albero:
		# ArenaRun non passa e non accenderebbe le luci dei Faro nuovi. Il fattore di notte si
		# applica ora, come al suo passo (`_update_game_lights`).
		run._update_game_lights()
	# Orda piena: tutti i nemici vivi, giocatore invulnerabile.
	for i in WARMUP_FRAMES:
		await physics_frame
	if night:
		# Dopo il riscaldamento (a albero fermo dal menu di casse e relitti: il fattore di notte
		# sui Faro viene dalla chiamata a `_update_game_lights` qui sopra, non dal passo di ArenaRun).
		var beacons := caravan.beacon_lights()
		var lights := run.light_field.source_count()
		print("PROTOTYPE01_ARENA_BENCH night phase=%s lamps=%d beacons=%d lights=%d"
			% [DayNightCycle.PHASE_NAMES[run.day_night.phase], lamps.count(), beacons.size(), lights])
		if beacons.size() != 6 or lights != 13:
			push_error("night bench: %d Faro e %d luci invece di 6 e 13" % [beacons.size(), lights])
		for entry in beacons:
			if not (entry.light as OmniLight3D).visible:
				push_error("night bench: la luce di un Faro e spenta")
	while director.enemies.size() < enemy_target:
		var spot: Variant = director._find_spawn_point()
		if spot == null:
			break
		director.spawn_at(spot)
	# Costo CPU diretto di un passo del direttore (percorsi, separazione, move_and_slide)
	# e di un passo dei frammenti: indipendente dal loop e dal vsync.
	var step := 1.0 / Engine.physics_ticks_per_second
	director.set_physics_process(false)
	var t0 := Time.get_ticks_usec()
	for i in 240:
		director._physics_process(step)
	var director_ms := (Time.get_ticks_usec() - t0) / 240000.0
	director.set_physics_process(true)
	var weapon: AutoWeapon = scene.get_node(^"PlayerWeapon")
	weapon.set_physics_process(false)
	t0 = Time.get_ticks_usec()
	for i in 240:
		weapon._physics_process(step)
	var weapon_ms := (Time.get_ticks_usec() - t0) / 240000.0
	weapon.set_physics_process(true)
	print("PROTOTYPE01_ARENA_BENCH step enemies=%d director_ms=%.2f weapon_ms=%.2f solve_ms=%.2f"
		% [director.enemies.size(), director_ms, weapon_ms, path.last_solve_usec / 1000.0])
	var physics_total := 0.0
	var process_total := 0.0
	var frame_total := 0.0
	var frames := 0
	var last := Time.get_ticks_usec()
	for i in MEASURE_FRAMES:
		player.set_max_health(5)
		player._invulnerable_left = 1.0
		await process_frame
		var now := Time.get_ticks_usec()
		frame_total += (now - last) / 1000.0
		last = now
		physics_total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		process_total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		frames += 1
	var headless := DisplayServer.get_name() == "headless"
	print("PROTOTYPE01_ARENA_BENCH frame headless=%s enemies=%d frames=%d avg_frame_ms=%.2f avg_physics_ms=%.2f avg_process_ms=%.2f fps=%.0f"
		% [headless, director.enemies.size(), frames, frame_total / frames, physics_total / frames, process_total / frames,
			Performance.get_monitor(Performance.TIME_FPS)])
	if not headless:
		print("PROTOTYPE01_ARENA_BENCH render preset=%s draw_calls=%d primitives=%d objects=%d video_mem_mb=%.0f"
			% [preset_name, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	print("PROTOTYPE01_ARENA_BENCH path solve_ms=%.2f recenter_ms=%.2f chunks=%d leashed=%d"
		% [path.last_solve_usec / 1000.0, path.last_recenter_usec / 1000.0, path.chunks_scanned, director.leashed])
	# Corsa (audit PF-02): il ricentro del campo e stato per mesi il passo piu caro del
	# gioco (51-64 ms) senza che il benchmark, a giocatore fermo, lo vedesse.
	var recenter_max := 0.0
	var recenters := path.recenter_count
	for i in 720:
		player._invulnerable_left = 1.0
		player.global_position += Vector3(7.0 / 120.0, 0.0, 0.0) if i < 360 else Vector3(0.0, 0.0, 7.0 / 120.0)
		await physics_frame
		recenter_max = maxf(recenter_max, path.last_recenter_usec / 1000.0)
	print("PROTOTYPE01_ARENA_BENCH run recenters=%d recenter_max_ms=%.2f terrain_chunks_sync=%d"
		% [path.recenter_count - recenters, recenter_max, path.terrain_chunks_sync])
	if OS.get_cmdline_user_args().has("--motion-ab"):
		# Stesso processo, blocchi alternati con e senza movimento procedurale: il
		# rumore della macchina pesa uguale sui due lati.
		director.set_physics_process(false)
		var totals := [0, 0]
		for block in 40:
			ActorMotion.enabled = block % 2 == 0
			var b0 := Time.get_ticks_usec()
			for i in 30:
				director._physics_process(step)
			totals[block % 2] += Time.get_ticks_usec() - b0
		ActorMotion.enabled = true
		print("PROTOTYPE01_ARENA_BENCH motion_ab enemies=%d director_on_ms=%.3f director_off_ms=%.3f delta=%.1f%%"
			% [director.enemies.size(), totals[0] / 600000.0, totals[1] / 600000.0, (float(totals[0]) / totals[1] - 1.0) * 100.0])
	# Ultime due: aggiungono nemici (la carovana anche macchine e scritture, le armi anelli
	# permanenti), non devono sporcare le misure sopra.
	await _bench_caravan(scene, step, preset_name, night)
	await _bench_loadout(scene, 1.0 / Engine.physics_ticks_per_second)
	quit()
