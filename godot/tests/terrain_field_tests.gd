extends SceneTree
## Suite del rilievo continuo (D-082, D-085): quote, pennello, livella, pendenza,
## aree protette, base, bump, salvataggio. Headless: Terrain3D viene rispecchiato
## solo quando esiste (`terrain3d()` puo essere null).
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/terrain_field_tests.gd

var _failures := 0
var _field: TerrainField


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _open()
	_test_flat_start()
	await _test_rectangular_field()
	_test_collision_chunks()
	await _test_body_pushed_up()
	_test_sculpt_volume_and_bell()
	_test_sculpt_across_region_border()
	_test_level()
	_test_brush_outside_field()
	_test_brush_without_change_is_silent()
	_test_highest_bumps_by_ring()
	_test_reset_to_base()
	_test_bump_along()
	_test_dig_to_base_offset()
	_test_grade_and_can_step()
	_test_protected()
	_test_base_delta_and_bump()
	_test_is_flat()
	_test_save_load_base()
	await _test_player_sculpt_signals()
	_test_soil_pack()
	await _frames(2)
	# File di prova nella cartella utente del gioco: non restano (audit K-11).
	for file: String in ["user://rect_base_test.bin", "user://rect_base_v2.bin"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _open() -> void:
	_field = TerrainField.new()
	_field.size_m = Vector2(64.0, 64.0)
	_field.tuning = TerrainTuning.new()
	root.add_child(_field)
	await _frames(3)


func _test_flat_start() -> void:
	print("flat start")
	_check(_field.resolution_x == 129 and _field.resolution_z == 129, "64 m a passo 0,5 = 129 vertici per lato (%d)" % _field.resolution_x)
	_check(is_zero_approx(_field.height_at(Vector3(3.3, 0, -7.1))), "quota zero all'inizio")
	_check(_field.normal_at(Vector3.ZERO).is_equal_approx(Vector3.UP), "normale verticale su un piano")


## Campo rettangolare (spec tappa B, sezione 2): indici, quote, regioni e chunk per asse.
func _test_rectangular_field() -> void:
	print("rectangular field")
	var field := TerrainField.new()
	field.size_m = Vector2(96.0, 32.0)
	field.tuning = TerrainTuning.new()
	root.add_child(field)
	await _frames(2)
	_check(field.resolution_x == 193 and field.resolution_z == 65, "96 x 32 m -> 193 x 65 vertici (%d x %d)" % [field.resolution_x, field.resolution_z])
	_check(field.half_extents().is_equal_approx(Vector2(48.0, 16.0)), "semilati 48 x 16 (%s)" % field.half_extents())
	field.sculpt(Vector3(40.0, 0.0, -10.0), 2.4, 1.0)
	_check(absf(field.height_at(Vector3(40.0, 0.0, -10.0)) - 1.0) < 0.01, "pennellata vicino all'angolo lontano: quota 1 al centro")
	_check(is_zero_approx(field.height_at(Vector3(-40.0, 0.0, 10.0))), "l'angolo opposto resta a zero")
	var collision: TerrainCollision = field.get_node(^"Collision")
	_check(collision.chunk_count() == 7 * 3, "chunk 7 x 3 (%d)" % collision.chunk_count())
	var space := root.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(40.0, 5.0, -10.0), Vector3(40.0, -5.0, -10.0), 1))
	_check(not hit.is_empty() and absf(hit.position.y - 1.0) < 0.1, "la collisione segue la quota anche in un campo rettangolare")
	var path := "user://rect_base_test.bin"
	field.commit_base()
	var bytes := field.save_base(path, 5)
	var other := TerrainField.new()
	other.size_m = Vector2(96.0, 32.0)
	other.tuning = TerrainTuning.new()
	root.add_child(other)
	await _frames(2)
	_check(bytes > 0 and other.load_base(path, 5), "salvataggio versione 3 e ricarica su un campo uguale")
	_check(absf(other.height_at(Vector3(40.0, 0.0, -10.0)) - 1.0) < 0.01, "le quote ricaricate sono le stesse")
	var square := TerrainField.new()
	square.size_m = Vector2(96.0, 96.0)
	square.tuning = TerrainTuning.new()
	root.add_child(square)
	await _frames(2)
	_check(not square.load_base(path, 5), "un campo di altra forma rifiuta il file")
	var old := FileAccess.open("user://rect_base_v2.bin", FileAccess.WRITE)
	old.store_buffer("TFLD".to_ascii_buffer())
	old.store_32(2)
	old.close()
	_check(not other.load_base("user://rect_base_v2.bin", 5), "la versione 2 non si legge piu")
	for node in [field, other, square]:
		node.queue_free()
	await _frames(2)


func _test_collision_chunks() -> void:
	print("collision chunks")
	var collision: TerrainCollision = _field.get_node(^"Collision")
	_check(collision.chunk_count() == 25, "64 m -> 5 x 5 chunk da 16 m (%d)" % collision.chunk_count())
	_check(collision.body.collision_layer == 1, "il corpo del terreno sta sul layer 1")
	var before := collision.refreshed_count()
	_field.sculpt(Vector3(0, 0, 0), 2.4, 1.0)
	_check(collision.refreshed_count() - before == 4, "una pennellata sul confine aggiorna i quattro chunk toccati (%d)" % (collision.refreshed_count() - before))
	var space := root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, -5, 0), 1)
	var hit := space.intersect_ray(query)
	_check(not hit.is_empty() and absf(hit.position.y - 1.0) < 0.1, "il raggio tocca la collisione alla quota nuova (%.2f)" % (hit.position.y if not hit.is_empty() else -99.0))
	_field.sculpt(Vector3(0, 0, 0), 2.4, -1.0)


func _test_body_pushed_up() -> void:
	print("body pushed up")
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	shape.shape = capsule
	body.add_child(shape)
	body.floor_max_angle = atan(0.8)
	body.position = Vector3(15, 0.7, 15)
	root.add_child(body)
	for i in 10:
		body.velocity = Vector3(0, -2, 0)
		body.move_and_slide()
		await physics_frame
	_check(body.is_on_floor(), "la capsula poggia sul terreno piano")
	# Il rilievo sale a gradini di 0,1 m come con un pennello: un salto di 1 m in un colpo
	# infila la capsula nel terreno, e Jolt non la spinge su (corpo incassato, vedi report).
	for s in 10:
		_field.sculpt(Vector3(15, 0, 15), 2.4, 0.1)
		for i in 3:
			body.velocity = Vector3(0, -2, 0)
			body.move_and_slide()
			await physics_frame
	for i in 10:
		body.velocity = Vector3(0, -2, 0)
		body.move_and_slide()
		await physics_frame
	_check(body.is_on_floor() and body.position.y > 1.5, "alzare sotto la capsula la spinge su (%.2f)" % body.position.y)
	body.queue_free()
	_field.sculpt(Vector3(15, 0, 15), 2.4, -1.0)


func _test_sculpt_volume_and_bell() -> void:
	print("sculpt")
	var volume := _field.sculpt(Vector3(10, 0, 10), 2.4, 1.0)
	_check(absf(_field.height_at(Vector3(10, 0, 10)) - 1.0) < 0.02, "al centro sale di 1 m (%.2f)" % _field.height_at(Vector3(10, 0, 10)))
	_check(_field.height_at(Vector3(11.2, 0, 10)) > 0.2 and _field.height_at(Vector3(11.2, 0, 10)) < 0.8, "a meta raggio sale a campana")
	_check(is_zero_approx(_field.height_at(Vector3(13, 0, 10))), "fuori dal raggio non cambia")
	# Volume della campana (1-d^2)^2 su un disco: pi * r^2 / 3 = 6,03 m3 per 1 m al centro.
	_check(absf(volume - 6.03) < 0.5, "volume firmato circa pi r^2 / 3 (%.2f)" % volume)
	var dug := _field.sculpt(Vector3(10, 0, 10), 2.4, -1.0)
	_check(absf(dug + volume) < 0.05 and absf(_field.height_at(Vector3(10, 0, 10))) < 0.02, "scavare la stessa quantita riporta a zero")
	_field.sculpt(Vector3(-20, 0, -20), 2.4, 10.0)
	_check(absf(_field.height_at(Vector3(-20, 0, -20)) - TerrainField.MAX_HEIGHT) < 0.01, "clamp alla quota massima")
	_field.sculpt(Vector3(-20, 0, 20), 2.4, -10.0)
	_check(absf(_field.height_at(Vector3(-20, 0, 20)) - TerrainField.MIN_HEIGHT) < 0.01, "clamp alla quota minima")


func _test_sculpt_across_region_border() -> void:
	print("sculpt across border")
	var aabb_seen: Array[AABB] = []
	var handler := func(aabb: AABB) -> void: aabb_seen.append(aabb)
	_field.region_changed.connect(handler)
	_field.sculpt(Vector3(0, 0, 0), 2.4, 0.8)
	_field.region_changed.disconnect(handler)
	_check(aabb_seen.size() == 1, "una pennellata = un solo region_changed")
	_check(aabb_seen[0].has_point(Vector3(-2.3, 0, -2.3)) and aabb_seen[0].has_point(Vector3(2.3, 0, 2.3)), "l'AABB copre tutto il pennello")
	_check(absf(_field.height_at(Vector3(-0.25, 0, -0.25)) - _field.height_at(Vector3(0.25, 0, 0.25))) < 0.05, "nessuna cucitura sul confine")
	_field.sculpt(Vector3(0, 0, 0), 2.4, -0.8)


func _test_level() -> void:
	print("level")
	_field.sculpt(Vector3(20, 0, -20), 2.4, 1.5)
	var moved := _field.level(Vector3(20, 0, -20), 3.0, 0.0, 1.0)
	_check(absf(_field.height_at(Vector3(20, 0, -20))) < 0.05, "livella porta il centro alla quota data")
	_check(moved < 0.0, "livellare un cumulo restituisce volume negativo (terra tolta)")


## Una pennellata del tutto fuori dal campo non tocca nulla e non emette `region_changed`
## (un AABB vuoto darebbe un Rect2 negativo al campo di percorso).
func _test_brush_outside_field() -> void:
	print("brush outside")
	var emitted := [0]
	var watcher := func(_aabb: AABB) -> void: emitted[0] += 1
	_field.region_changed.connect(watcher)
	var volume := _field.sculpt(Vector3(90.0, 0.0, 0.0), 2.4, 1.0)
	var levelled := _field.level(Vector3(0.0, 0.0, -95.0), 2.4, 1.0, 1.0)
	var reset := _field.reset_to_base(Vector3(90.0, 0.0, 90.0), Vector2(3.0, 3.0))
	_field.region_changed.disconnect(watcher)
	_check(is_zero_approx(volume) and is_zero_approx(levelled) and is_zero_approx(reset), "fuori dal campo il volume e zero")
	_check(emitted[0] == 0, "fuori dal campo nessun region_changed (%d)" % emitted[0])


## Il treno riporta la fascia alla base (spec tappa B, sezione 4): rettangolo a cavallo del
## confine delle regioni e di piu chunk, aree protette comprese, volume assoluto.
func _test_reset_to_base() -> void:
	print("reset to base")
	var collision: TerrainCollision = _field.get_node(^"Collision")
	_field.sculpt(Vector3(0.0, 0.0, 0.0), 2.4, 1.0)
	_field.sculpt(Vector3(4.0, 0.0, 1.0), 2.0, -0.8)
	_field.sculpt(Vector3(14.0, 0.0, 0.0), 2.0, 1.0)
	_field.set_protected(Vector3(-3.0, 0.0, 0.0), 1.5, true)
	_field.sculpt(Vector3(-3.0, 0.0, 0.0), 1.5, 0.5)
	_check(is_zero_approx(_field.height_at(Vector3(-3.0, 0.0, 0.0))), "la pennellata protetta non alza nulla (setup)")
	_field._protected.fill(0)
	_field.sculpt(Vector3(-3.0, 0.0, 0.0), 1.5, 0.5)
	_field.set_protected(Vector3(-3.0, 0.0, 0.0), 1.5, true)
	var before := collision.refreshed_count()
	var volume := _field.reset_to_base(Vector3(0.0, 0.0, 0.0), Vector2(8.0, 3.6))
	_check(volume > 2.0, "volume assoluto spostato (%.2f m3)" % volume)
	_check(is_zero_approx(_field.height_at(Vector3.ZERO)) and is_zero_approx(_field.height_at(Vector3(4.0, 0.0, 1.0))),
		"argine e solco nel rettangolo tornano alla base")
	_check(is_zero_approx(_field.height_at(Vector3(-3.0, 0.0, 0.0))), "anche il pixel protetto torna alla base")
	_check(absf(_field.height_at(Vector3(14.0, 0.0, 0.0)) - 1.0) < 0.01, "fuori dal rettangolo nulla cambia")
	_check(collision.refreshed_count() - before >= 2, "i chunk toccati sono stati rigenerati (%d)" % (collision.refreshed_count() - before))
	_field._protected.fill(0)
	_field.sculpt(Vector3(14.0, 0.0, 0.0), 2.0, -1.0)
	_check(_field.collision_body() == collision.body, "collision_body espone il corpo del terreno")
	# Fascia gia alla base: niente da fare, nessun segnale (il treno lo chiama a ogni passo).
	var emitted := [0]
	var watcher := func(_aabb: AABB) -> void: emitted[0] += 1
	_field.region_changed.connect(watcher)
	var again := _field.reset_to_base(Vector3(0.0, 0.0, 0.0), Vector2(8.0, 3.6))
	_field.region_changed.disconnect(watcher)
	_check(is_zero_approx(again) and emitted[0] == 0, "un secondo reset sulla fascia piatta non emette nulla (%d)" % emitted[0])


## Primo argine lungo un segmento (Trivella): punto con quota, o null.
func _test_bump_along() -> void:
	print("bump along")
	_field.sculpt(Vector3(6.0, 0.0, 0.0), 2.0, 1.2)
	var hit: Variant = _field.bump_along(Vector3(0.0, 0.0, 0.0), Vector3(12.0, 0.0, 0.0), 0.8)
	_check(hit != null and absf((hit as Vector3).x - 6.0) < 2.0 and (hit as Vector3).y >= 0.8, "argine trovato lungo la rotta (%s)" % str(hit))
	_check(_field.bump_along(Vector3(0.0, 0.0, 0.0), Vector3(-12.0, 0.0, 0.0), 0.8) == null, "nessun argine dall'altra parte")
	_field.sculpt(Vector3(6.0, 0.0, 0.0), 2.0, -1.2)
	_field.tint_rect(Vector3.ZERO, Vector2(10.0, 3.6), Color.RED, 1.0)
	_field.paint_layer_rect(Vector3.ZERO, Vector2(10.0, 3.6), 2)
	_check(true, "tint_rect e paint_layer_rect non fanno nulla in headless")


## Il solco della Trivella: porta il disco a [depth] sotto la base, vertice per vertice,
## solo scavando. Un fossato gia piu profondo non viene riempito, un pendio di base non
## viene scavato oltre la profondita.
func _test_dig_to_base_offset() -> void:
	print("dig to base offset")
	_field.sculpt(Vector3(0.0, 0.0, 0.0), 2.0, -1.6)
	var deep_before := _field.height_at(Vector3.ZERO)
	var volume := _field.dig_to_base_offset(Vector3(0.0, 0.0, 0.0), 1.2, 0.8)
	_check(volume <= 0.0, "scavare non aggiunge terra (volume %.2f)" % volume)
	_check(absf(_field.height_at(Vector3.ZERO) - deep_before) < 0.001, "un fossato piu profondo del solco resta com'era")
	_field.sculpt(Vector3(0.0, 0.0, 0.0), 2.0, 1.6)
	var dug := _field.dig_to_base_offset(Vector3(6.0, 0.0, 0.0), 1.2, 0.8)
	_check(dug < -0.1 and absf(_field.delta_at(Vector3(6.0, 0.0, 0.0)) + 0.8) < 0.01, "sul piano il solco arriva a 0,8 m sotto la base (%.2f)" % _field.delta_at(Vector3(6.0, 0.0, 0.0)))
	var twice := _field.dig_to_base_offset(Vector3(6.0, 0.0, 0.0), 1.2, 0.8)
	# La campana porta al fondo il centro in un colpo e i bordi in piu passate (convergenza geometrica).
	_check(absf(twice) < absf(dug) * 0.5, "un secondo passaggio scava meno della meta (%.2f contro %.2f): converge al fondo" % [twice, dug])
	_field.sculpt(Vector3(6.0, 0.0, 0.0), 1.2, 0.8)


func _test_grade_and_can_step() -> void:
	print("grade")
	_field.sculpt(Vector3(-10, 0, 0), 2.4, 1.6)
	var foot := Vector3(-13.0, 0, 0)
	var top := Vector3(-10.0, 0, 0)
	_check(_field.grade_between(foot, top) > 0.4, "salita positiva verso il cumulo (%.2f)" % _field.grade_between(foot, top))
	_check(_field.grade_between(top, foot) < 0.0, "discesa negativa")
	_check(_field.can_step(top, foot, 0.8), "in discesa si passa sempre")
	_check(not _field.can_step(Vector3(-11.2, 0, 0), Vector3(-10.4, 0, 0), 0.3), "salita ripida oltre la soglia bloccata")
	_check(_field.can_step(Vector3(-11.2, 0, 0), Vector3(-10.4, 0, 0), 3.0), "con soglia alta si passa")
	_check(_field.slope_at(Vector3(-11.2, 0, 0)) > 0.3, "pendenza locale sul fianco")
	_field.sculpt(Vector3(-10, 0, 0), 2.4, -1.6)


func _test_protected() -> void:
	print("protected")
	_field.set_protected(Vector3(5, 0, -5), 1.5, true)
	_check(_field.is_protected(Vector3(5.5, 0, -5)), "dentro il disco protetto")
	_check(not _field.is_protected(Vector3(8, 0, -5)), "fuori dal disco")
	var volume := _field.sculpt(Vector3(5, 0, -5), 2.4, 1.0)
	_check(is_zero_approx(_field.height_at(Vector3(5, 0, -5))), "i pixel protetti non cambiano")
	_check(_field.height_at(Vector3(7.0, 0, -5)) > 0.05, "i pixel liberi dello stesso pennello cambiano")
	_check(volume > 0.0 and volume < 6.0, "il volume conta solo i pixel scritti")
	_field.set_protected(Vector3(5, 0, -5), 1.5, false)
	_field.level(Vector3(5, 0, -5), 3.0, 0.0, 1.0)


func _test_base_delta_and_bump() -> void:
	print("base and bump")
	_field.sculpt(Vector3(0, 0, 15), 3.0, 0.6)
	_field.commit_base()
	_check(absf(_field.base_height_at(Vector3(0, 0, 15)) - 0.6) < 0.02, "commit_base fissa la quota di base")
	_check(is_zero_approx(_field.delta_at(Vector3(0, 0, 15))), "delta zero subito dopo il commit")
	_field.sculpt(Vector3(4, 0, 15), 2.4, 1.2)
	_check(absf(_field.delta_at(Vector3(4, 0, 15)) - 1.2) < 0.02, "delta = attuale - base")
	var bump: Variant = _field.highest_bump(Vector3(0, 0, 15), 10.0, 0.8)
	_check(bump != null and Vector2((bump as Vector3).x - 4.0, (bump as Vector3).z - 15.0).length() < 0.8 and absf((bump as Vector3).y - _field.height_at(bump)) < 0.01, "highest_bump trova la cima alzata dal giocatore")
	_check(_field.highest_bump(Vector3(-20, 0, 0), 5.0, 0.8) == null, "nessun bump dove non c'e nulla")
	_field.sculpt(Vector3(4, 0, 15), 2.4, -1.2)


func _test_is_flat() -> void:
	print("is_flat")
	_check(_field.is_flat(Vector3(-25, 0, 25), 3.0, 0.35), "piano dove e piano")
	_field.sculpt(Vector3(-25, 0, 25), 2.4, 0.5)
	_check(not _field.is_flat(Vector3(-25, 0, 25), 3.0, 0.35), "non piano con un cumulo di 0,5 m")
	_field.sculpt(Vector3(-25, 0, 25), 2.4, -0.5)


func _test_save_load_base() -> void:
	print("save/load")
	var path := "user://terrain_field_test_%d.bin" % OS.get_process_id()
	_field.sculpt(Vector3(12, 0, -12), 2.4, 0.9)
	_field.commit_base()
	var bytes := _field.save_base(path, 7)
	_check(bytes > 0, "salvataggio scritto (%d byte)" % bytes)
	var other := TerrainField.new()
	other.size_m = Vector2(64.0, 64.0)
	other.tuning = TerrainTuning.new()
	root.add_child(other)
	_check(not other.load_base(path, 8), "un file cotto con un altro seme del layout viene rifiutato")
	_check(other.load_base(path, 7), "caricamento riuscito")
	_check(absf(other.height_at(Vector3(12, 0, -12)) - 0.9) < 0.02, "le quote caricate coincidono")
	_check(absf(other.base_height_at(Vector3(12, 0, -12)) - 0.9) < 0.02, "la base caricata coincide")
	other.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_field.sculpt(Vector3(12, 0, -12), 2.4, -0.9)
	_field.commit_base()


func _test_player_sculpt_signals() -> void:
	print("player signals")
	var got: Array = []
	var handler := func(center: Vector3, radius: float, volume: float, mode: int) -> void: got.append([center, radius, volume, mode])
	_field.player_sculpted.connect(handler)
	var v := _field.player_sculpt(Vector3(0, 0, -20), 2.4, -0.3, TerrainField.ToolMode.DIG)
	_field.player_sculpted.disconnect(handler)
	_check(got.size() == 1 and got[0][3] == TerrainField.ToolMode.DIG and absf(got[0][2] - v) < 0.001, "player_sculpt emette player_sculpted con volume e modo")
	_check(absf(_field.volume_moved - absf(v)) < 0.001, "volume_moved accumula il valore assoluto")
	await _frames(1)


func _test_soil_pack() -> void:
	print("soil pack")
	var pack := SoilPack.new(60.0, 20.0)
	var seen: Array = []
	pack.changed.connect(func(a: float, c: float) -> void: seen.append([a, c]))
	_check(absf(pack.take(5.0) - 5.0) < 0.001 and absf(pack.amount - 15.0) < 0.001, "take toglie quello che chiede")
	_check(absf(pack.take(50.0) - 15.0) < 0.001 and pack.is_empty(), "take oltre il contenuto da solo cio che c'e e svuota")
	_check(absf(pack.give(70.0) - 60.0) < 0.001 and absf(pack.fill_ratio() - 1.0) < 0.001, "give oltre la capacita accoglie fino al tetto, il resto si perde")
	pack.add_capacity(20.0)
	_check(absf(pack.capacity - 80.0) < 0.001 and absf(pack.fill_ratio() - 0.75) < 0.001, "add_capacity alza il tetto")
	_check(seen.size() == 4, "ogni cambio emette changed (%d)" % seen.size())


## Audit E-16: la ricerca a anelli in una passata da le stesse cime di `highest_bump`
## chiamata per ogni raggio, su un rilievo casuale.
func _test_highest_bumps_by_ring() -> void:
	print("highest bumps by ring")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var center := Vector3(10.0, 0.0, -8.0)
	for i in 14:
		_field.sculpt(center + Vector3(rng.randf_range(-11.0, 11.0), 0.0, rng.randf_range(-11.0, 11.0)), rng.randf_range(1.0, 2.5), rng.randf_range(0.3, 1.6))
	var rings := _field.highest_bumps_by_ring(center, 3.0, 12.01, 0.4)
	var same := rings.size() == 4
	for k in rings.size():
		var single: Variant = _field.highest_bump(center, 3.0 * (k + 1), 0.4)
		var by_ring: Variant = rings[k]
		if (single == null) != (by_ring == null):
			same = false
		elif single != null and _field.delta_at(single) != _field.delta_at(by_ring):
			same = false
	_check(same, "quattro anelli: stesse cime della ricerca disco per disco")
	_field.reset_to_base(center, Vector2(15.0, 15.0))


## Audit T-03 e T-05: una pennellata che non cambia nessun vertice (disco protetto,
## quantita nulla) non rifa specchio, collisione e campo; raggio zero non scrive NaN.
func _test_brush_without_change_is_silent() -> void:
	print("brush without change")
	var emits := [0]
	var counter := func(_aabb: AABB) -> void: emits[0] += 1
	_field.region_changed.connect(counter)
	var at := Vector3(-20.0, 0.0, -20.0)
	_field.set_protected(at, 3.0, true)
	_field.sculpt(at, 2.4, 0.5)
	_check(emits[0] == 0, "disco tutto protetto: nessun aggiornamento")
	_field.set_protected(at, 3.0, false)
	_field.sculpt(at, 2.4, 0.0)
	_check(emits[0] == 0, "quantita nulla: nessun aggiornamento")
	_field.sculpt(at, 2.4, -0.5)
	_check(emits[0] == 1, "una pennellata vera aggiorna una volta")
	_check(_field.sculpt(at, 0.0, 1.0) == 0.0 and not is_nan(_field.height_at(at)) and emits[0] == 1, "raggio zero: nessuna pennellata e nessun NaN")
	_field.region_changed.disconnect(counter)
	_field.level(at, 3.0, _field.base_height_at(at), 1.0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
