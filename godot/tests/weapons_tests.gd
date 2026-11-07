extends SceneTree
## Armi (spec D-092): danno, valori per livello, bivi che cambiano davvero il comportamento.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/weapons_tests.gd

var _failures := 0
var _root: Node3D
var _director: EnemyDirector
var _field: TerrainField
var _queue: TerrainWriteQueue


func _initialize() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	_director = EnemyDirector.new()
	_director.spawning = false
	_root.add_child(_director)
	_field = TerrainField.new()
	_field.render = false
	_field.size_m = Vector2(40.0, 40.0)
	get_root().add_child(_field)
	_queue = TerrainWriteQueue.new()
	_queue.terrain_field = _field
	get_root().add_child(_queue)
	await process_frame
	await _test_nailgun_base()
	await _test_nailgun_levels()
	await _test_bridge_pierces_all()
	await _test_ricochet()
	await _test_incendiary()
	await _test_legacy_turret()
	await _test_no_node_per_nail()
	await _test_stake_cooldown()
	await _test_stake_ring()
	await _test_stake_permanent()
	await _test_stake_shock()
	await _test_stake_spiked()
	await _test_active_auto_aim()
	await _test_active_fallback_and_cursor()
	await _test_shock_keeps_trapped_inside()
	await _test_blade_base()
	await _test_blade_downhill()
	await _test_blade_ditch()
	await _test_blade_twin()
	await _test_blade_rebound()
	await _test_blade_groove()
	await _test_hammer_base()
	await _test_hammer_wall()
	await _test_hammer_wide_and_stun()
	await _test_hammer_cracks()
	await _test_hammer_echo()
	await _test_mixer_base()
	await _test_mixer_wall_and_quickset()
	await _test_mixer_pavement()
	await _test_mixer_double()
	await _test_disc_dozer()
	await _test_compactor()
	await _test_groove_does_not_compound()
	await _test_cracks_do_not_compound()
	await _test_dozer_keeps_ditches()
	await _test_mixer_lifts_bodies()
	await _test_fort()
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _enemy_at(p: Vector3, hp := 50) -> Enemy:
	var enemy := _director.spawn_at(p)
	enemy.health = hp
	enemy.max_health = hp
	enemy.global_position = p
	return enemy


func _shooter(at: Vector3) -> Node3D:
	var shooter := Node3D.new()
	_root.add_child(shooter)
	shooter.global_position = at
	return shooter


func _nailgun(at := Vector3.ZERO) -> AutoWeapon:
	var weapon := AutoWeapon.new()
	weapon.weapon_id = &"nailgun"
	weapon.shooter = _shooter(at)
	weapon.director = _director
	_root.add_child(weapon)
	return weapon


func _seconds(s: float) -> void:
	for i in int(s * Engine.physics_ticks_per_second):
		await physics_frame


func _clear() -> void:
	for enemy in _director.enemies:
		enemy.queue_free()
	_director.enemies.clear()
	for child in _root.get_children():
		if child != _director:
			child.queue_free()
	await process_frame
	await physics_frame


func _test_nailgun_base() -> void:
	print("chiodatrice liv. 1")
	var enemy := _enemy_at(Vector3(0, 0, -5))
	var weapon := _nailgun()
	_check(is_equal_approx(weapon.fire_interval, 0.5) and weapon.damage == 1, "valori dal catalogo")
	await _seconds(0.65)
	_check(enemy.health == 49, "un chiodo colpisce entro 0,65 s (vita %d)" % enemy.health)
	await _clear()


func _test_nailgun_levels() -> void:
	print("livelli e Raffica")
	var weapon := _nailgun()
	await process_frame
	weapon.set_level(2)
	_check(is_equal_approx(weapon.fire_interval, 0.4), "liv. 2: un colpo ogni 0,4 s")
	weapon.set_level(3)
	weapon.choose_branch(3, &"a")
	_check(is_equal_approx(weapon.fire_interval, 0.2), "Raffica: un colpo ogni 0,2 s")
	_check(weapon.has_branch(&"burst") and not weapon.has_branch(&"bridge"), "has_branch riconosce il bivio preso")
	await _clear()


func _test_bridge_pierces_all() -> void:
	print("Chiodi da ponte")
	var a := _enemy_at(Vector3(0, 0, -3))
	var b := _enemy_at(Vector3(0, 0, -4))
	var c := _enemy_at(Vector3(0, 0, -5))
	var weapon := _nailgun()
	await process_frame
	weapon.set_level(3)
	weapon.choose_branch(3, &"b")
	await _seconds(0.6)
	_check(a.health == 48 and b.health == 48 and c.health == 48,
		"un colpo trapassa tre nemici, 2 danni ciascuno (%d, %d, %d)" % [a.health, b.health, c.health])
	await _clear()


func _wall_at(z: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 3, 0.4)
	shape.shape = box
	body.add_child(shape)
	_root.add_child(body)
	body.global_position = Vector3(0, 0, z)


func _test_ricochet() -> void:
	print("Rimbalzanti")
	_wall_at(-3.0)
	var enemy := _enemy_at(Vector3(0, 0, 2))
	var plain := _nailgun()
	await physics_frame
	plain._cooldown = 1000.0
	plain._fire_toward(Vector3.FORWARD)
	await _seconds(0.8)
	_check(enemy.health == 50, "senza bivio il chiodo si ferma sull'argine")
	plain.queue_free()
	var weapon := _nailgun()
	await physics_frame
	weapon.set_level(5)
	weapon.choose_branch(3, &"a")
	weapon.choose_branch(5, &"a")
	weapon._cooldown = 1000.0
	weapon._fire_toward(Vector3.FORWARD)
	await _seconds(0.8)
	_check(enemy.health == 49, "col bivio rimbalza sull'argine e colpisce dietro (vita %d)" % enemy.health)
	await _clear()


func _test_incendiary() -> void:
	print("Incandescenti")
	var enemy := _enemy_at(Vector3(0, 0, -4))
	var weapon := _nailgun()
	await physics_frame
	weapon.set_level(5)
	weapon.choose_branch(3, &"a")
	weapon.choose_branch(5, &"b")
	weapon._cooldown = 1000.0
	weapon._fire_toward(Vector3.FORWARD)
	await _seconds(0.3)
	_check(weapon.fire_patch_count() == 1, "all'impatto resta una macchia di fuoco")
	await _seconds(2.2)
	_check(enemy.health <= 47, "la macchia brucia chi ci sta dentro (vita %d)" % enemy.health)
	_check(weapon.fire_patch_count() == 0, "dopo 2 s la macchia si spegne")
	await _clear()


func _test_legacy_turret() -> void:
	print("Torretta senza catalogo")
	var weapon := AutoWeapon.new()
	weapon.shooter = _shooter(Vector3.ZERO)
	weapon.director = _director
	weapon.fire_interval = 0.9
	weapon.weapon_range = 8.0
	_root.add_child(weapon)
	await process_frame
	_check(is_equal_approx(weapon.fire_interval, 0.9) and is_equal_approx(weapon.weapon_range, 8.0), "senza weapon_id i valori impostati restano")
	await _clear()


func _test_no_node_per_nail() -> void:
	print("chiodi senza nodi")
	_enemy_at(Vector3(0, 0, -8), 500)
	var weapon := _nailgun()
	await physics_frame
	var children := weapon.get_child_count()
	weapon.set_level(3)
	weapon.choose_branch(3, &"a")
	await _seconds(2.0)
	_check(weapon.get_child_count() == children, "sparando i figli dell'arma restano %d" % children)
	await _clear()


func _stake(level := 1, picks: Dictionary = {}) -> SeismicStake:
	var stake := SeismicStake.new()
	stake.weapon_id = &"seismic_stake"
	stake.shooter = _shooter(Vector3.ZERO)
	stake.director = _director
	stake.terrain_field = _field
	stake.write_queue = _queue
	stake.manual_aim = true
	_root.add_child(stake)
	stake.set_level(level)
	for at: int in picks:
		stake.choose_branch(at, picks[at])
	return stake


func _reset_field() -> void:
	_queue.clear()
	_field.begin_batch()
	_field.reset_to_base(Vector3.ZERO, Vector2(20.0, 20.0))
	_field.end_batch()


## Quota sull'anello del picchetto piantato a 6 m davanti (verso -Z), al punto a est.
func _ring_height(radius := 3.0) -> float:
	return _field.height_at(Vector3(radius, 0.0, -6.0))


func _test_stake_cooldown() -> void:
	print("Picchetto: ricarica")
	var stake := _stake()
	await physics_frame
	_check(stake.can_trigger() and stake.trigger(), "carico: si pianta")
	_check(not stake.can_trigger() and is_equal_approx(stake.cooldown_left, 15.0), "poi ricarica 15 s")
	_check(not stake.trigger(), "scarico: non si pianta")
	await _seconds(15.1)
	_check(stake.can_trigger(), "dopo 15 s e di nuovo carico")
	paused = true
	_check(not stake.can_trigger(), "a gioco in pausa non si usa")
	paused = false
	await _clear()
	_reset_field()


func _test_stake_ring() -> void:
	print("Picchetto: anello")
	var stake := _stake()
	await physics_frame
	stake.trigger()
	await _seconds(1.2)
	_check(_ring_height() > 1.0, "dopo il ritardo l'anello e alto (%.2f m)" % _ring_height())
	_check(_field.height_at(Vector3(0.0, 0.0, -6.0)) < 0.3, "il centro resta basso: chi e dentro e chiuso")
	_check(_field.height_at(Vector3(3.0 * cos(PI / 7.0), 0.0, -6.0 + 3.0 * sin(PI / 7.0))) > 0.9, "l'anello non ha buchi fra un disco e l'altro")
	_check(stake.ring_count() == 1, "un anello vivo")
	await _seconds(12.5)
	_check(_ring_height() < 0.2, "dopo 12 s torna giu (%.2f m)" % _ring_height())
	_check(stake.ring_count() == 0, "nessun anello vivo")
	await _clear()
	_reset_field()


func _test_stake_permanent() -> void:
	print("Picchetto: Argine permanente")
	var stake := _stake(3, {3: &"b"})
	await physics_frame
	stake.trigger()
	await _seconds(14.0)
	_check(_ring_height() > 1.0, "dopo 14 s l'anello e ancora su")
	await _clear()
	_reset_field()


func _test_stake_shock() -> void:
	print("Picchetto: Scossa")
	var enemy := _enemy_at(Vector3(3.0, 0.0, -6.0))
	var stake := _stake(5, {3: &"b", 5: &"b"})
	await physics_frame
	stake.trigger()
	await _seconds(0.8)
	_check(enemy.health == 47, "3 danni a chi sta sull'anello (vita %d)" % enemy.health)
	await _clear()
	_reset_field()


func _test_stake_spiked() -> void:
	print("Picchetto: Argine chiodato")
	var enemy := _enemy_at(Vector3(3.4, 0.0, -6.0))
	var stake := _stake(5, {3: &"b", 5: &"a"})
	await physics_frame
	stake.trigger()
	await _seconds(2.5)
	_check(enemy.health <= 48, "chi sta contro l'anello si fa male (vita %d)" % enemy.health)
	await _clear()
	_reset_field()


## Review: senza nemici la mira automatica pianta alla portata piena (a meta l'anello passava
## sotto i piedi); col mouse il punto e il cursore, limitato alla portata.
func _test_active_fallback_and_cursor() -> void:
	print("Attive: senza nemici e col cursore")
	var stake := _stake()
	stake.manual_aim = false
	await physics_frame
	var at := stake.aim_point()
	_check(is_equal_approx(Vector2(at.x, at.z).length(), 6.0), "senza nemici alla portata piena (%.2f m)" % Vector2(at.x, at.z).length())
	stake.shooter.set_script(preload("res://tests/support/cursor_shooter.gd"))
	stake.manual_aim = true
	stake.shooter.cursor = Vector3(2.0, 0.0, -2.0)
	at = stake.aim_point()
	_check(Vector2(at.x, at.z).is_equal_approx(Vector2(2.0, -2.0)), "col mouse pianta sul cursore (%s)" % at)
	stake.shooter.cursor = Vector3(20.0, 0.0, 0.0)
	at = stake.aim_point()
	_check(Vector2(at.x, at.z).is_equal_approx(Vector2(6.0, 0.0)), "cursore lontano: alla portata (%s)" % at)
	await _clear()
	_reset_field()


## Review I-3: la Scossa scaglia fuori chi sta sull'anello, non chi e chiuso dentro.
func _test_shock_keeps_trapped_inside() -> void:
	print("Picchetto: Scossa e chi e dentro")
	var inside := _enemy_at(Vector3(0.0, 0.0, -6.0))
	var on_ring := _enemy_at(Vector3(3.0, 0.0, -6.0))
	var stake := _stake(5, {3: &"b", 5: &"b"})
	await physics_frame
	stake.trigger()
	await _seconds(0.7)
	_check(inside.velocity.length() < 0.1, "chi e dentro non viene spinto (%.2f m/s)" % inside.velocity.length())
	_check(on_ring.velocity.x > 1.0, "chi sta sull'anello e scagliato fuori (%.2f m/s)" % on_ring.velocity.x)
	await _clear()
	_reset_field()


# --- Lama da cantiere (piano 2) ----------------------------------------------------------

func _blade(level := 1, picks: Dictionary = {}, at := Vector3.ZERO) -> SiteBlade:
	var blade := SiteBlade.new()
	blade.weapon_id = &"site_blade"
	blade.shooter = _shooter(at)
	blade.director = _director
	blade.terrain_field = _field
	blade.write_queue = _queue
	_root.add_child(blade)
	blade.set_level(level)
	for pick_at: int in picks:
		blade.choose_branch(pick_at, picks[pick_at])
	return blade


## Argine dritto di traverso, da x = -4 a 4 alla quota [param z], alto 1,5 m.
func _wall_on_field(z: float) -> void:
	for x in range(-4, 5):
		_field.level(Vector3(x, 0.0, z), 0.9, 1.5, 1.0)


func _test_blade_base() -> void:
	print("Lama: base")
	var a := _enemy_at(Vector3(0, 0, -3))
	var b := _enemy_at(Vector3(0, 0, -5))
	_blade()
	await _seconds(1.3)
	_check(a.health == 48 and b.health == 48, "il disco rotola e colpisce tutti sul percorso, 2 danni (%d, %d)" % [a.health, b.health])
	await _clear()
	_reset_field()


func _test_blade_downhill() -> void:
	print("Lama: discesa")
	_field.sculpt(Vector3(0.0, 0.0, -14.0), 12.0, -2.4)
	var down := _blade(1, {}, Vector3(0.0, 0.0, -2.0))
	var flat := _blade(1, {}, Vector3(14.0, 0.0, 14.0))
	await physics_frame
	down._cooldown = 1000.0
	flat._cooldown = 1000.0
	down._launch(Vector3.FORWARD)
	flat._launch(Vector3.LEFT)
	await _seconds(0.6)
	var down_run := Vector2(0.0, -2.0).distance_to(Vector2(down.disc_positions()[0].x, down.disc_positions()[0].z))
	var flat_run := Vector2(14.0, 14.0).distance_to(Vector2(flat.disc_positions()[0].x, flat.disc_positions()[0].z))
	_check(down_run > flat_run + 0.4, "in discesa va piu lontano (%.2f contro %.2f m)" % [down_run, flat_run])
	await _clear()
	_reset_field()


func _test_blade_ditch() -> void:
	print("Lama: fossato")
	_field.sculpt(Vector3(0.0, 0.0, -5.0), 2.5, -1.6)
	var blade := _blade()
	await physics_frame
	blade._cooldown = 1000.0
	blade._launch(Vector3.FORWARD)
	await _seconds(2.0)
	_check(blade.disc_count() == 1, "nel fossato il disco gira oltre la sua corsa (1,25 s)")
	await _seconds(3.0)
	_check(blade.disc_count() == 0, "dopo 3 s si ferma")
	await _clear()
	_reset_field()


func _test_blade_twin() -> void:
	print("Lama: Due lame")
	var blade := _blade(3, {3: &"a"})
	await physics_frame
	blade._cooldown = 1000.0
	blade._launch(Vector3.FORWARD)
	_check(blade.disc_count() == 2, "due dischi per lancio")
	await _clear()
	_reset_field()


func _test_blade_rebound() -> void:
	print("Lama: Rimbalzo")
	_wall_on_field(-4.0)
	var plain := _blade()
	await physics_frame
	plain._cooldown = 1000.0
	plain._launch(Vector3.FORWARD)
	await _seconds(0.8)
	_check(plain.disc_count() == 0, "senza bivio il disco si ferma sull'argine")
	plain.queue_free()
	var blade := _blade(5, {3: &"a", 5: &"a"})
	await physics_frame
	blade._cooldown = 1000.0
	blade._launch(Vector3.FORWARD)
	await _seconds(0.9)
	_check(blade.disc_count() >= 1 and blade.disc_positions()[0].z > -3.0, "col bivio rimbalza e torna indietro")
	await _clear()
	_reset_field()


func _test_blade_groove() -> void:
	print("Lama: Solco")
	var blade := _blade(5, {3: &"b", 5: &"b"})
	await physics_frame
	blade._cooldown = 1000.0
	blade._launch(Vector3.FORWARD)
	await _seconds(1.5)
	_check(_field.height_at(Vector3(0.0, 0.0, -4.0)) < -0.1, "dietro il disco resta un solco (%.2f m)" % _field.height_at(Vector3(0.0, 0.0, -4.0)))
	await _clear()
	_reset_field()


# --- Martello pneumatico (piano 2) --------------------------------------------------------

func _hammer(level := 1, picks: Dictionary = {}) -> Jackhammer:
	var hammer := Jackhammer.new()
	hammer.weapon_id = &"jackhammer"
	hammer.shooter = _shooter(Vector3.ZERO)
	hammer.director = _director
	hammer.terrain_field = _field
	hammer.write_queue = _queue
	_root.add_child(hammer)
	hammer.set_level(level)
	for pick_at: int in picks:
		hammer.choose_branch(pick_at, picks[pick_at])
	return hammer


func _test_hammer_base() -> void:
	print("Martello: onda")
	var right := _enemy_at(Vector3(2, 0, 0))
	var left := _enemy_at(Vector3(-2, 0, 0))
	var far := _enemy_at(Vector3(0, 0, -6))
	_hammer()
	await _seconds(0.7)
	_check(right.health == 49 and left.health == 49 and far.health == 50, "1 danno entro 3 m, niente oltre (%d, %d, %d)" % [right.health, left.health, far.health])
	_check(right.velocity.x > 1.0 and left.velocity.x < -1.0, "e li spinge via")
	await _clear()
	_reset_field()


func _test_hammer_wall() -> void:
	print("Martello: contro l'argine")
	for x in range(-3, 4):
		_field.level(Vector3(x, 0.0, 3.0), 0.9, 1.5, 1.0)
	var pinned := _enemy_at(Vector3(0, 0, 2))
	var free := _enemy_at(Vector3(0, 0, -2))
	_hammer()
	await _seconds(0.7)
	_check(pinned.health == 48 and free.health == 49, "chi ha un argine dietro prende il doppio (%d, %d)" % [pinned.health, free.health])
	await _clear()
	_reset_field()


func _test_hammer_wide_and_stun() -> void:
	print("Martello: Onda larga e Stordente")
	var enemy := _enemy_at(Vector3(4.5, 0, 0))
	_hammer(3, {3: &"a"})
	await _seconds(0.7)
	_check(enemy.health == 49, "Onda larga arriva a 4,5 m")
	await _clear()
	var stunned := _enemy_at(Vector3(2, 0, 0))
	_hammer(3, {3: &"b"})
	await _seconds(0.7)
	_check(stunned.stun_left > 0.3, "Stordente ferma chi e colpito")
	await _clear()
	_reset_field()


func _test_hammer_cracks() -> void:
	print("Martello: Crepe")
	_enemy_at(Vector3(2, 0, 0))
	_hammer(5, {3: &"a", 5: &"a"})
	await _seconds(1.0)
	var lowest := 0.0
	for i in 32:
		var angle := TAU * i / 32.0
		lowest = minf(lowest, _field.height_at(Vector3(cos(angle) * 2.0, 0.0, sin(angle) * 2.0)))
	_check(lowest < -0.15, "attorno si aprono crateri (%.2f m)" % lowest)
	await _clear()
	_reset_field()


func _test_hammer_echo() -> void:
	print("Martello: Eco nei fossati")
	_field.sculpt(Vector3(7.0, 0.0, 0.0), 2.5, -1.6)
	var in_ditch := _enemy_at(Vector3(7, 0, 0))
	var on_flat := _enemy_at(Vector3(0, 0, 7))
	_enemy_at(Vector3(-2, 0, 0))
	_hammer(5, {3: &"a", 5: &"b"})
	await _seconds(0.7)
	_check(in_ditch.health < 50 and on_flat.health == 50, "colpisce chi sta in basso a 7 m, non chi e in piano (%d, %d)" % [in_ditch.health, on_flat.health])
	await _clear()
	_reset_field()


# --- Betoniera (piano 2) -------------------------------------------------------------------

func _mixer(level := 1, picks: Dictionary = {}) -> CementMixer:
	var mixer := CementMixer.new()
	mixer.weapon_id = &"cement_mixer"
	mixer.shooter = _shooter(Vector3.ZERO)
	mixer.director = _director
	mixer.terrain_field = _field
	mixer.write_queue = _queue
	mixer.manual_aim = true
	_root.add_child(mixer)
	mixer.set_level(level)
	for at: int in picks:
		mixer.choose_branch(at, picks[at])
	return mixer


func _test_mixer_base() -> void:
	print("Betoniera: pozza e dosso")
	var enemy := _enemy_at(Vector3(0.5, 0, -6))
	var mixer := _mixer()
	await physics_frame
	_check(mixer.trigger(), "si getta")
	await _seconds(1.0)
	_check(enemy.stun_left > 0.0, "chi e nella pozza e bloccato")
	await _seconds(1.7)
	_check(enemy.stun_left > 0.0, "e lo resta per 3 s")
	await _seconds(1.2)
	_check(_field.height_at(Vector3(0, 0, -6)) > 0.3, "poi indurisce in un dosso (%.2f m)" % _field.height_at(Vector3(0, 0, -6)))
	_check(mixer.pool_count() == 0, "la pozza non c'e piu")
	await _clear()
	_reset_field()


func _test_mixer_wall_and_quickset() -> void:
	print("Betoniera: Muro di getto e Presa rapida")
	var enemy := _enemy_at(Vector3(0.5, 0, -6))
	var mixer := _mixer(5, {3: &"b", 5: &"a"})
	await physics_frame
	mixer.trigger()
	# Al livello 4 il blocco dura 4 s, poi le scritture.
	await _seconds(5.0)
	_check(_field.height_at(Vector3(0, 0, -6)) > 1.0, "il dosso sale oltre il metro (%.2f m)" % _field.height_at(Vector3(0, 0, -6)))
	_check(enemy.health == 47, "all'indurimento 3 danni ai bloccati (%d)" % enemy.health)
	await _clear()
	_reset_field()


func _test_mixer_pavement() -> void:
	print("Betoniera: Pavimento")
	_field.level(Vector3(0, 0, -6), 1.5, 0.8, 1.0)
	var mixer := _mixer(5, {3: &"b", 5: &"b"})
	await physics_frame
	mixer.trigger()
	# Al livello 4 il blocco dura 4 s, poi le scritture.
	await _seconds(5.0)
	_check(_field.height_at(Vector3(0, 0, -6)) < 0.15, "spiana alla base invece di alzare (%.2f m)" % _field.height_at(Vector3(0, 0, -6)))
	await _clear()
	_reset_field()


func _test_mixer_double() -> void:
	print("Betoniera: Doppia colata")
	var mixer := _mixer(3, {3: &"a"})
	await physics_frame
	mixer.trigger()
	_check(mixer.pool_count() == 2, "due pozze")
	await _clear()
	_reset_field()


# --- Fusioni comuni (piano 2) ---------------------------------------------------------------

func _test_disc_dozer() -> void:
	print("Ruspa a dischi")
	_field.sculpt(Vector3(0.0, 0.0, -4.0), 1.5, 0.35)
	var blade := _blade()
	blade.fusion_id = &"disc_dozer"
	blade.set_level(1)
	_check(is_equal_approx(blade.disc_radius, 0.8), "dischi grandi il doppio")
	await physics_frame
	blade._cooldown = 1000.0
	blade._launch(Vector3.FORWARD)
	await _seconds(1.5)
	_check(_field.height_at(Vector3(0.0, 0.0, -4.0)) < 0.15, "spianano dove passano (%.2f m)" % _field.height_at(Vector3(0.0, 0.0, -4.0)))
	_enemy_at(Vector3(0.0, 0.0, -6.0), 500)
	await _seconds(10.5)
	_check(blade.big_launched >= 1, "ogni 10 s un disco enorme")
	await _clear()
	_reset_field()


func _test_compactor() -> void:
	print("Costipatore")
	var enemy := _enemy_at(Vector3(2, 0, 0), 500)
	var hammer := _hammer()
	hammer.fusion_id = &"compactor"
	hammer.set_level(1)
	await _seconds(0.7)
	_check(enemy.stun_left > 0.0, "ogni onda blocca")
	await _seconds(4.5)
	_check(hammer.waves >= 3 and _field.height_at(Vector3(0.0, 0.0, 3.0)) > 0.15, "la terza onda lascia un anello di cemento (%.2f m)" % _field.height_at(Vector3(0.0, 0.0, 3.0)))
	await _clear()
	_reset_field()


# --- Correzioni della review del piano 2 -----------------------------------------------------

func _test_groove_does_not_compound() -> void:
	print("Solco: profondita fissa")
	var blade := _blade(5, {3: &"b", 5: &"b"})
	await physics_frame
	blade._cooldown = 1000.0
	for i in 3:
		blade._launch(Vector3.FORWARD)
		await _seconds(2.2)
	var depth := _field.height_at(Vector3(0.0, 0.0, -4.0))
	_check(depth < -0.15 and depth > -0.32, "tre passaggi lasciano un solco da 0,25 m (%.2f m)" % depth)
	await _clear()
	_reset_field()


func _test_cracks_do_not_compound() -> void:
	print("Crepe: profondita fissa")
	_enemy_at(Vector3(2, 0, 0), 500)
	_hammer(5, {3: &"a", 5: &"a"})
	await _seconds(9.0)
	var lowest := 0.0
	for i in 64:
		var angle := TAU * i / 64.0
		lowest = minf(lowest, _field.height_at(Vector3(cos(angle) * 2.0, 0.0, sin(angle) * 2.0)))
	_check(lowest > -0.4, "cinque onde ferme non scavano oltre 0,3 m (%.2f m)" % lowest)
	await _clear()
	_reset_field()


func _test_dozer_keeps_ditches() -> void:
	print("Ruspa: i fossati restano")
	_field.sculpt(Vector3(0.0, 0.0, -5.0), 2.5, -1.6)
	var blade := _blade()
	blade.fusion_id = &"disc_dozer"
	blade.set_level(1)
	await physics_frame
	blade._cooldown = 1000.0
	blade._big_left = 1000.0
	blade._launch(Vector3.FORWARD)
	await _seconds(4.0)
	_check(_field.height_at(Vector3(0.0, 0.0, -5.0)) < -1.0, "spiana i dossi ma non riempie il fossato (%.2f m)" % _field.height_at(Vector3(0.0, 0.0, -5.0)))
	await _clear()
	_reset_field()


func _test_mixer_lifts_bodies() -> void:
	print("Betoniera: chi e bloccato sale col dosso")
	_queue.director = _director
	var enemy := _enemy_at(Vector3(0.3, 0, -6))
	var mixer := _mixer(3, {3: &"b"})
	await physics_frame
	mixer.trigger()
	await _seconds(4.5)
	var ground := _field.height_at(enemy.global_position)
	_check(ground > 1.0 and enemy.global_position.y >= ground + enemy.spawn_center_height() - 0.01,
		"il nemico sta sopra il muro di getto, non dentro (%.2f su %.2f)" % [enemy.global_position.y, ground])
	_queue.director = null
	await _clear()
	_reset_field()


func _test_active_auto_aim() -> void:
	print("Attive: mira automatica")
	for offset in [Vector3(-0.3, 0, -0.2), Vector3(0.3, 0, 0.2), Vector3(0.1, 0, -0.1), Vector3(-0.2, 0, 0.25)]:
		_enemy_at(Vector3(5.0, 0.0, 0.6) + offset)
	_enemy_at(Vector3(0.0, 0.0, -4.0))
	var stake := _stake()
	stake.manual_aim = false
	await physics_frame
	var at := stake.aim_point()
	_check(Vector2(at.x, at.z).distance_to(Vector2(5.0, 0.6)) < 0.6, "punta al gruppo piu fitto, non al nemico isolato (%s)" % at)
	await _clear()
	_reset_field()


# --- Fusioni di classe (piano 3) -------------------------------------------------------------

## Chiodatrice della scena adottata da un loadout dell'Ingegnere (come in ArenaRun), portata al
## 5 col picchetto (bivi "a": Raffica e Rimbalzanti) e fusa in Fortino.
func _fort() -> AutoWeapon:
	var shooter := _shooter(Vector3.ZERO)
	var scene_weapon := AutoWeapon.new()
	scene_weapon.shooter = shooter
	scene_weapon.director = _director
	_root.add_child(scene_weapon)
	var loadout := WeaponLoadout.new()
	loadout.player = shooter
	loadout.director = _director
	loadout.terrain_field = _field
	loadout.write_queue = _queue
	_root.add_child(loadout)
	loadout.adopt(scene_weapon)
	loadout.setup_class(&"engineer")
	for id: StringName in [&"nailgun", &"seismic_stake"]:
		while loadout.level_of(id) < WeaponCatalog.MAX_LEVEL:
			if loadout.needs_branch(id):
				loadout.choose_branch(id, &"a")
			else:
				loadout.level_up(id)
	loadout.fuse(&"nailgun")
	return scene_weapon


func _health_of(enemies: Array[Enemy]) -> int:
	var total := 0
	for enemy in enemies:
		total += enemy.health
	return total


## Scarto massimo della quota dalla base nell'area davanti a chi spara (dove nascono i coni).
func _fort_residual() -> float:
	var worst := 0.0
	for iz in 41:
		for ix in 49:
			var p := Vector3(-6.0 + ix * 0.25, 0.0, -9.0 + iz * 0.25)
			worst = maxf(worst, absf(_field.height_at(p) - _field.base_height_at(p)))
	return worst


func _test_fort() -> void:
	print("Fortino")
	var gun := _fort()
	_check(gun.fusion_id == &"fort" and gun.write_queue == _queue, "fusa dal loadout, con la coda delle scritture")
	await physics_frame
	var children := gun.get_child_count()
	var enemies: Array[Enemy] = []
	for x: float in [-0.4, 0.0, 0.4]:
		enemies.append(_enemy_at(Vector3(x, 0.0, -6.0), 5000))
	var turret: AutoWeapon = null
	for i in 11 * Engine.physics_ticks_per_second:
		await physics_frame
		if not gun.fort_turrets().is_empty():
			turret = gun.fort_turrets()[0]
			break
	_check(turret != null, "entro 11 s nasce una torretta")
	if turret == null:
		await _clear()
		_reset_field()
		return
	await _seconds(0.2)
	var top := turret.global_position
	var rise := _field.height_at(top) - _field.base_height_at(top)
	_check(rise > 1.0, "la quota sotto la torretta sale di oltre 1 m (%.2f m)" % rise)
	_check(Vector2(top.x, top.z).length() <= 5.01, "il cono e entro 5 m da chi spara (%.2f m)" % Vector2(top.x, top.z).length())
	_check(turret.level == 5 and turret.has_branch(&"burst") and turret.has_branch(&"ricochet") and turret.fusion_id == &"",
		"la torretta ha livello e bivi della chiodatrice, senza fusione")
	_check(is_equal_approx(turret.fire_interval, gun.fire_interval / 0.7), "spara al 70%% (un colpo ogni %.2f s)" % turret.fire_interval)
	# Chi spara si allontana: la chiodatrice principale non ha piu nemici in portata.
	gun.shooter.global_position = Vector3(0.0, 0.0, 16.0)
	await _seconds(0.5)
	var shots := [0]
	turret.fired.connect(func(count: int) -> void: shots[0] += count)
	var before := _health_of(enemies)
	await _seconds(2.0)
	var after := _health_of(enemies)
	_check(shots[0] > 0 and after < before, "la torretta colpisce da sola (%d chiodi, vita %d -> %d)" % [shots[0], before, after])
	_check(turret.global_position.is_equal_approx(top), "la torretta non segue chi spara")
	await _seconds(8.0 - 2.7 + 0.5)
	_check(gun.fort_turrets().is_empty() and not is_instance_valid(turret), "dopo 8 s la torretta sparisce")
	var back := _field.height_at(top) - _field.base_height_at(top)
	_check(absf(back) < 0.2, "il cono torna alla base (%.2f m)" % back)
	_check(gun.get_child_count() == children, "i figli tornano %d (%d)" % [children, gun.get_child_count()])
	print("Fortino: al massimo due torrette")
	gun.shooter.global_position = Vector3.ZERO
	var most := 0
	for i in 40 * Engine.physics_ticks_per_second:
		gun._fort_left = 0.0
		await physics_frame
		most = maxi(most, gun.fort_turrets().size())
	_check(most == 2, "chiamate di continuo per 40 s, mai piu di due torrette (%d)" % most)
	gun.shooter.global_position = Vector3(0.0, 0.0, 16.0)
	await _seconds(8.5)
	_check(gun.fort_turrets().is_empty() and gun.get_child_count() == children,
		"dopo oltre 60 s nessun nodo in piu (%d figli)" % gun.get_child_count())
	_check(_fort_residual() < 0.2, "nessun cono resta nel terreno (%.2f m)" % _fort_residual())
	await _clear()
	_reset_field()
