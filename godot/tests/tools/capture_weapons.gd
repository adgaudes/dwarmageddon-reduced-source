extends SceneTree
## Catture delle armi dell'impianto (D-092, piano 1), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 6000 --script res://tests/tools/capture_weapons.gd -- --out=../output/weapons
## Produce: burst (chiodatrice con Raffica sull'orda), incendiary (macchie di fuoco degli
## Incandescenti), stake_rising e stake_ring (anello del picchetto che sale e chiude l'orda,
## striscia del HUD in ricarica), branch_screen (scelta della trasformazione); kit comune
## (piano 2): blade, hammer, ram, dozer (Ruspa a dischi), mixer; Fortino (piano 3): fort.
## Con `--class=sapper|mechanic|weeder` (piano 3) solo il kit della classe:
## <classe>_auto, <classe>_active (livello 1), <classe>_auto5, <classe>_active5 (livello 5 coi
## bivi di PICKS), <classe>_fusion; la tuta e tinta del colore di classe.
## Con `--fx` (piano 5) una cattura per arma e fusione, `fx_<id>`, scattata FX_DELAY passi dopo
## che il suo primo effetto (gruppo `weapon_fx`) e comparso: gli effetti durano mezzo secondo.
## Con `--caravan` (carovana D-093, task 7) una cattura sola, `caravan_strip`: striscia della
## carovana sopra quella delle armi (Torretta guasta in riparazione, Calamita in ritirata, Faro,
## Saldatore), tasto Ripara e frecce degli indicatori verso il basso; stampa
## `PROTOTYPE01_CAPTURE_CARAVAN column_top=... marker_y=...` (cima della colonna, freccia in basso).

## Bivi delle catture di classe: quelli che si vedono di piu.
const PICKS := {
	&"scrap_launcher": [&"a", &"a"], &"dig_charge": [&"b", &"a"],
	&"welder": [&"a", &"b"], &"crane_magnet": [&"b", &"a"],
	&"scythe": [&"a", &"b"], &"bramble": [&"a", &"a"],
}

var _out := "../output/weapons"
var _fx := false
var _caravan_shot := false
## Passi di fisica fra la comparsa dell'effetto e la cattura.
const FX_DELAY := 10
var _run: ArenaRun
var _player: PlayerCharacter
var _director: EnemyDirector


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		_fx = _fx or arg == "--fx"
		_caravan_shot = _caravan_shot or arg == "--caravan"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	var scene: Node3D = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(scene)
	_run = scene.get_node(^"Run")
	_player = scene.get_node(^"Player")
	_director = scene.get_node(^"EnemyDirector")
	var field: TerrainField = scene.get_node(^"TerrainField")
	_director.spawning = false
	# Nessun level-up durante le catture: il menu metterebbe in pausa.
	_run.progression.xp_first_level = 1000000
	await _frames(20)
	_run._start_protect_left = 0.0
	field.set_protected(Vector3.ZERO, field.tuning.start_protected_radius_m, false)
	_player.global_position = Vector3(0.0, field.height_at(Vector3.ZERO) + 0.88, 0.0)
	_player.velocity = Vector3.ZERO
	var loadout := _run.loadout
	if _fx:
		await _fx_all(loadout)
		quit()
		return
	if _caravan_shot:
		await _caravan_strip()
		quit()
		return
	if _run.class_id != ClassCatalog.DEFAULT:
		await _class_kit(loadout, _run.class_id)
		quit()
		return

	loadout.level_up(&"nailgun")
	loadout.choose_branch(&"nailgun", &"a")
	_horde(Vector3(0.0, 0.0, -7.0), 8)
	await _frames(70)
	await _save("burst")

	loadout.level_up(&"nailgun")
	loadout.choose_branch(&"nailgun", &"b")
	_horde(Vector3(5.0, 0.0, -5.0), 8)
	await _frames(90)
	await _save("incendiary")

	# Picchetto: chiodatrice ferma, cosi si vede solo l'anello (i rottamatori poi lo rosicchiano).
	_director.clear_horde()
	loadout.weapon(&"nailgun").process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(int(2.5 * Engine.physics_ticks_per_second))
	_player.set_aim_mode(PlayerCharacter.AimMode.MANUAL)
	_player.rotation.y = 0.0
	_horde(Vector3(0.0, 0.0, -6.0), 6, 1.2)
	loadout.trigger_active(0)
	await _frames(int(0.75 * Engine.physics_ticks_per_second))
	await _save("stake_rising")
	await _frames(int(0.45 * Engine.physics_ticks_per_second))
	await _save("stake_ring")

	_run._pending_level_ups = 1
	loadout.level_up(&"seismic_stake")
	_run._on_upgrade_chosen(&"w:branch:seismic_stake")
	await _frames(30)
	await _save("branch_screen")
	await _common_kit(loadout)
	await _fort(loadout)
	quit()


## Fortino: chiodatrice e picchetto al 5 e fusi; la prima torretta nasce dopo 10 s.
func _fort(loadout: WeaponLoadout) -> void:
	_director.clear_horde()
	loadout.weapon(&"nailgun").process_mode = Node.PROCESS_MODE_INHERIT
	for id in [&"nailgun", &"seismic_stake"]:
		_max_out(loadout, id, [&"a", &"a"])
	loadout.fuse(&"nailgun")
	await _frames(int(9.0 * Engine.physics_ticks_per_second))
	_horde(Vector3(0.0, 0.0, -9.0), 6, 1.5)
	await _frames(int(2.5 * Engine.physics_ticks_per_second))
	await _save("fort")


## Kit di una classe (piano 3): automatica e attiva al livello 1, poi al 5, poi la fusione.
func _class_kit(loadout: WeaponLoadout, class_id: StringName) -> void:
	_player._set_aim_device(PlayerCharacter.AimDevice.GAMEPAD)
	_player.rotation.y = 0.0
	var kit := ClassCatalog.start_weapons(class_id)
	if kit.size() < 2:
		push_error("classe senza kit: %s" % class_id)
		return
	var auto_id := kit[0]
	var active_id := kit[1]
	var active := loadout.weapon(active_id) as ActiveWeapon
	_horde(Vector3(0.0, 0.0, -6.0), 8, 2.0)
	await _frames(int(1.6 * Engine.physics_ticks_per_second))
	await _save("%s_auto" % class_id)
	loadout.trigger_active(0)
	await _frames(int(0.8 * Engine.physics_ticks_per_second))
	await _save("%s_active" % class_id)
	_director.clear_horde()
	await _frames(60)
	_max_out(loadout, auto_id, PICKS.get(auto_id, [&"a", &"a"]))
	_max_out(loadout, active_id, PICKS.get(active_id, [&"a", &"a"]))
	_horde(Vector3(0.0, 0.0, -6.0), 8, 2.0)
	await _frames(int(2.0 * Engine.physics_ticks_per_second))
	await _save("%s_auto5" % class_id)
	active.cooldown_left = 0.0
	loadout.trigger_active(0)
	await _frames(int(1.2 * Engine.physics_ticks_per_second))
	await _save("%s_active5" % class_id)
	_director.clear_horde()
	await _frames(int(2.0 * Engine.physics_ticks_per_second))
	loadout.fuse(auto_id)
	_horde(Vector3(0.0, 0.0, -5.0), 10, 2.5)
	await _frames(int(2.0 * Engine.physics_ticks_per_second))
	await _save("%s_fusion" % class_id)


static func _max_out(loadout: WeaponLoadout, id: StringName, picks: Array) -> void:
	while loadout.level_of(id) > 0 and loadout.level_of(id) < WeaponCatalog.MAX_LEVEL:
		if loadout.needs_branch(id):
			loadout.choose_branch(id, picks[0] if loadout.level_of(id) < 3 else picks[1])
		else:
			loadout.level_up(id)


## Kit comune (piano 2): una cattura per arma, la chiodatrice resta ferma. Mira da controller:
## col mouse le attive andrebbero verso il cursore della finestra.
func _common_kit(loadout: WeaponLoadout) -> void:
	_player._set_aim_device(PlayerCharacter.AimDevice.GAMEPAD)
	# La schermata del bivio resta senza scelta: niente level-up in coda dopo.
	_run._pending_level_ups = 0
	_run.level_up_menu.close()
	_director.clear_horde()
	await _frames(int(2.5 * Engine.physics_ticks_per_second))
	loadout.add(&"site_blade")
	_horde(Vector3(0.0, 0.0, -8.0), 6, 1.5)
	await _frames(int(1.2 * Engine.physics_ticks_per_second))
	await _save("blade")
	_director.clear_horde()
	loadout.add(&"jackhammer")
	var hammer := loadout.weapon(&"jackhammer") as Jackhammer
	_horde(Vector3.ZERO, 8, 2.6)
	for i in 600:
		await physics_frame
		if hammer._ring_left > 0.0 and hammer._ring_left < 0.1:
			break
	await _save("hammer")
	_director.clear_horde()
	await _frames(60)
	loadout.add(&"ram")
	_player._set_aim_device(PlayerCharacter.AimDevice.GAMEPAD)
	_player.rotation.y = 0.0
	_horde(Vector3(0.0, 0.0, -5.0), 5, 1.0)
	loadout.trigger_active(1)
	await _frames(int(0.25 * Engine.physics_ticks_per_second))
	await _save("ram")
	await _frames(int(1.0 * Engine.physics_ticks_per_second))
	_director.clear_horde()
	for id in [&"site_blade", &"ram"]:
		while loadout.level_of(id) < WeaponCatalog.MAX_LEVEL:
			if loadout.needs_branch(id):
				loadout.choose_branch(id, &"b")
			else:
				loadout.level_up(id)
	loadout.fuse(&"site_blade")
	_horde(Vector3(4.0, 0.0, -7.0), 6, 1.5)
	await _frames(int(1.4 * Engine.physics_ticks_per_second))
	await _save("dozer")
	_director.clear_horde()
	await _frames(60)
	loadout.add(&"cement_mixer")
	_player._set_aim_device(PlayerCharacter.AimDevice.GAMEPAD)
	_player.rotation.y = 0.0
	_horde(Vector3(0.0, 0.0, -6.0), 6, 1.2)
	loadout.trigger_active(1)
	await _frames(int(1.0 * Engine.physics_ticks_per_second))
	await _save("mixer")


## Carovana (task 7): cinque macchine, la Torretta guasta a 1,2 m in riparazione da 0,7 s, la
## Calamita in ritirata; poi la run si ferma (indicatori e HUD restano come sono) e tre frecce
## verso il basso mostrano dove si fermano sopra la colonna.
func _caravan_strip() -> void:
	var caravan := _run.caravan
	_player.grant_invulnerability(60.0)
	var machines: Dictionary[StringName, Machine] = {}
	for id: StringName in [&"turret", &"magnet", &"beacon", &"welder"]:
		machines[id] = caravan.add_machine(id)
	await _frames(int(1.0 * Engine.physics_ticks_per_second))
	var turret := machines[&"turret"]
	var at := _player.global_position + Vector3(1.2, 0.0, 0.0)
	turret.global_position = Vector3(at.x, _run.terrain_field.height_at(at) + Caravan.GROUND_CLEARANCE, at.z)
	turret.velocity = Vector3.ZERO
	turret.reset_physics_interpolation()
	turret._hit_cooldown_left = 0.0
	turret._invulnerable_left = 0.0
	turret.take_hit(turret.health)
	machines[&"magnet"].health = 1
	_player.interact_held = true
	await _frames(int(0.7 * Engine.physics_ticks_per_second))
	_run.set_physics_process(false)
	_player.interact_held = false
	var markers: Array[Dictionary] = []
	for direction: Vector2 in [Vector2(0.0, 1.0), Vector2(0.9, 0.44), Vector2(1.0, 0.6)]:
		markers.append({direction = direction, distance = 30.0, color = Color.WHITE, text = "X"})
	_run.hud.set_markers(markers)
	await _save("caravan_strip")
	print("PROTOTYPE01_CAPTURE_CARAVAN column_top=%.0f marker_y=%.0f"
		% [_run.hud._corner.get_global_rect().position.y, _run.hud._marker_arrows[0].position.y])


## Piano 5: ogni arma e fusione da sola, creata a mano accanto al giocatore come nella suite
## weapon_fx_tests; le armi del loadout restano ferme.
func _fx_all(loadout: WeaponLoadout) -> void:
	_player._set_aim_device(PlayerCharacter.AimDevice.GAMEPAD)
	for w: Weapon in loadout.autos() + loadout.actives():
		w.process_mode = Node.PROCESS_MODE_DISABLED
	loadout.telegraph.process_mode = Node.PROCESS_MODE_DISABLED
	loadout.telegraph.hide()
	var cases: Array = [
		[&"nailgun", &"", AutoWeapon], [&"seismic_stake", &"", SeismicStake], [&"nailgun", &"fort", AutoWeapon],
		[&"scrap_launcher", &"", ScrapLauncher], [&"dig_charge", &"", DigCharge], [&"scrap_launcher", &"mortar", ScrapLauncher],
		[&"welder", &"", Welder], [&"crane_magnet", &"", CraneMagnet], [&"welder", &"tesla_coil", Welder],
		[&"scythe", &"", Scythe], [&"bramble", &"", Bramble], [&"scythe", &"scythe_bramble", Scythe],
		[&"site_blade", &"", SiteBlade], [&"ram", &"", Ram], [&"site_blade", &"disc_dozer", SiteBlade],
		[&"jackhammer", &"", Jackhammer], [&"cement_mixer", &"", CementMixer], [&"jackhammer", &"compactor", Jackhammer],
	]
	for case: Array in cases:
		var id: StringName = case[0]
		var fusion: StringName = case[1]
		_player.global_position = Vector3(0.0, _run.terrain_field.height_at(Vector3.ZERO) + 0.88, 0.0)
		_player.velocity = Vector3.ZERO
		_player.rotation.y = 0.0
		# L'orda attorno lo morde per tutte le catture: deve arrivare in fondo.
		_player.grant_invulnerability(60.0)
		var weapon: Weapon = (case[2] as GDScript).new()
		weapon.weapon_id = id
		weapon.shooter = _player
		weapon.director = _director
		weapon.terrain_field = _run.terrain_field
		_run.add_child(weapon)
		loadout.give_services(weapon)
		if fusion != &"":
			weapon.fusion_id = fusion
			weapon.set_level(WeaponCatalog.MAX_LEVEL)
			# Il colpo della fusione subito, invece che dopo 4-10 s.
			for key: StringName in [&"_fort_left", &"_big_left"]:
				if key in weapon:
					weapon.set(key, 0.05)
			if weapon is ScrapLauncher:
				(weapon as ScrapLauncher).shots = 3
			if weapon is Jackhammer:
				(weapon as Jackhammer).waves = 2
		_horde(Vector3(0.0, 0.0, -5.0), 8, 1.6)
		_horde(Vector3.ZERO, 6, 2.6)
		var seen := false
		for step in int(6.0 * Engine.physics_ticks_per_second):
			if weapon is ActiveWeapon and step % 60 == 0:
				(weapon as ActiveWeapon).cooldown_left = 0.0
				(weapon as ActiveWeapon).trigger()
			await physics_frame
			if _fx_wanted(fusion):
				seen = true
				break
		await _frames(FX_DELAY)
		await _save("fx_%s" % (fusion if fusion != &"" else id))
		if not seen:
			push_warning("nessun effetto per %s" % id)
		weapon.queue_free()
		_director.clear_horde()
		await _frames(int(1.2 * Engine.physics_ticks_per_second))


## Vero quando c'e un effetto in scena (della fusione, se [param fusion] non e vuota).
func _fx_wanted(fusion: StringName) -> bool:
	for node in get_nodes_in_group(WeaponFx.GROUP):
		if fusion == &"" or node.get_meta(&"fx_fusion", &"") == fusion:
			return true
	return false


func _horde(center: Vector3, count: int, spread := 2.0) -> void:
	for i in count:
		var angle := TAU * i / count
		var enemy := _director.spawn_at(center + Vector3(cos(angle), 0.0, sin(angle)) * spread * (0.5 + 0.5 * (i % 2)))
		enemy.health = 30
		enemy.max_health = 30


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
