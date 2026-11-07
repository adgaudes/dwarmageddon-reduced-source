extends SceneTree
## Test di UiFx (D-081): cursore a chiodo, suoni, pop-in e transizioni. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/ui_fx_tests.gd

var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _frames(2)
	await _test_cursor_follows_focus()
	await _test_pop_in()
	await _test_fade_once()
	await _test_existing_buttons_and_reparent()
	await _test_polyphony()
	await _test_transition_blocks_pause_and_cursor()
	await _test_pulse()
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _fx() -> UiFxService:
	return root.get_node("UiFx") as UiFxService


## Il cursore segue l'ultimo Control con il focus; i pulsanti liberati non rompono nulla.
func _test_cursor_follows_focus() -> void:
	var fx := _fx()
	_check(fx != null and fx.cursor_enabled, "autoload UiFx presente con il cursore attivo")
	var column := VBoxContainer.new()
	column.position = Vector2(300, 200)
	root.add_child(column)
	var buttons: Array[Button] = []
	for i in 5:
		var button := Button.new()
		button.text = "Voce %d" % i
		button.custom_minimum_size = Vector2(200, 48)
		column.add_child(button)
		buttons.append(button)
	await _frames(2)
	var moves_before := fx.play_count(&"ui_move")
	buttons[0].grab_focus()
	await _frames(10)
	_check(fx.cursor_target() == buttons[0] and fx.cursor_visible(), "cursore sul primo pulsante")
	var rect := buttons[0].get_global_rect()
	var cursor := fx.cursor_position()
	_check(cursor.x < rect.position.x and absf(cursor.y - (rect.position.y + rect.size.y * 0.5)) < rect.size.y, "cursore a sinistra del pulsante, allineato in verticale")
	for i in 5:
		buttons[i].grab_focus()
		await _frames(1)
	await _frames(10)
	_check(fx.cursor_target() == buttons[4], "cambi rapidi di focus: vince l'ultimo")
	_check(fx.play_count(&"ui_move") > moves_before, "il cursore suona ui_move")
	var confirms := fx.play_count(&"ui_confirm")
	buttons[4].pressed.emit()
	await _frames(12)
	_check(fx.play_count(&"ui_confirm") == confirms + 1 and buttons[4].scale.is_equal_approx(Vector2.ONE), "pressione: ui_confirm e rimbalzo che torna a 1")
	# Il bersaglio si sposta dopo il focus (layout, scroll, pop-in): il cursore lo segue.
	column.position = Vector2(500, 400)
	await _frames(12)
	var moved := buttons[4].get_global_rect()
	var cursor_after := fx.cursor_position()
	_check(cursor_after.x < moved.position.x and absf(cursor_after.x - moved.position.x) < 60.0 and absf(cursor_after.y - (moved.position.y + moved.size.y * 0.5)) < moved.size.y, "il cursore segue il bersaglio spostato (%s vs %s)" % [cursor_after, moved.position])
	buttons[4].queue_free()
	await _frames(3)
	_check(not fx.cursor_visible(), "pulsante liberato: cursore nascosto, nessun errore")
	column.queue_free()
	await _frames(2)


func _test_pop_in() -> void:
	var fx := _fx()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 100)
	root.add_child(panel)
	await _frames(1)
	var opens := fx.play_count(&"ui_open")
	fx.pop_in(panel)
	_check(panel.scale.x < 1.0 and panel.modulate.a < 1.0, "pop-in parte piccolo e trasparente")
	await _frames(14)
	_check(panel.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(panel.modulate.a, 1.0), "pop-in finisce a scala 1 e opaco")
	_check(fx.play_count(&"ui_open") == opens + 1, "pop-in suona ui_open")
	panel.queue_free()
	await _frames(1)


## Due richieste di transizione di fila cambiano scena una volta sola.
func _test_fade_once() -> void:
	var fx := _fx()
	var changes := fx.scene_changes()
	fx.fade_to_scene("res://scenes/main/main_menu.tscn")
	fx.fade_to_scene("res://scenes/main/main_menu.tscn")
	_check(fx.is_transitioning, "transizione in corso")
	await _frames(60)
	_check(fx.scene_changes() == changes + 1, "una sola scena caricata (%d)" % (fx.scene_changes() - changes))
	_check(not fx.is_transitioning and fx.veil_alpha() < 0.01, "velo riaperto alla fine")


## I pulsanti gia nell'albero prima di UiFx (autoload PauseMenu) sono agganciati, e un
## pulsante che rientra nell'albero non viene collegato due volte.
func _test_existing_buttons_and_reparent() -> void:
	var fx := _fx()
	var resume: Button = root.get_node("PauseMenu/%ResumeButton")
	_check(fx.is_hooked(resume), "Riprendi della pausa e agganciato a UiFx")
	var holder := Control.new()
	root.add_child(holder)
	var button := Button.new()
	holder.add_child(button)
	await _frames(1)
	holder.remove_child(button)
	holder.add_child(button)
	await _frames(1)
	var links := 0
	for connection in button.pressed.get_connections():
		if connection.callable.get_object() == fx:
			links += 1
	_check(links == 1, "un pulsante che rientra nell'albero resta collegato una volta (%d)" % links)
	button.queue_free()
	holder.queue_free()
	await _frames(1)


## Piu suoni nello stesso frame non si cancellano, e il tic del cursore cede il passo.
func _test_polyphony() -> void:
	var fx := _fx()
	_check(fx.polyphony() >= 4, "almeno quattro voci per i suoni di interfaccia (%d)" % fx.polyphony())
	var button := Button.new()
	root.add_child(button)
	await _frames(1)
	var moves := fx.play_count(&"ui_move")
	fx.play(&"ui_confirm")
	button.grab_focus()
	_check(fx.play_count(&"ui_move") == moves, "ui_move saltato se nello stesso frame suona gia un altro suono")
	await _frames(2)
	var other := Button.new()
	root.add_child(other)
	await _frames(1)
	other.grab_focus()
	_check(fx.play_count(&"ui_move") == moves + 1, "ui_move suona quando e solo")
	button.queue_free()
	other.queue_free()
	await _frames(1)


## Durante il velo l'azione `pause` non apre la pausa e il cursore non compare.
func _test_transition_blocks_pause_and_cursor() -> void:
	var fx := _fx()
	var pause := root.get_node("PauseMenu")
	pause.set(&"enabled", true)
	var button := Button.new()
	root.add_child(button)
	await _frames(1)
	fx.fade_to_scene("res://scenes/main/main_menu.tscn")
	await _frames(3)
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	button.grab_focus()
	await _frames(2)
	_check(not fx.cursor_visible(), "niente cursore sopra il velo")
	await _frames(60)
	_check(not pause.call(&"is_open"), "la pausa premuta durante il velo non resta aperta")
	if is_instance_valid(button):
		button.queue_free()
	await _frames(1)


## Il controllo con il focus respira (self_modulate che oscilla) e torna bianco quando lo perde.
func _test_pulse() -> void:
	var fx := _fx()
	var a := Button.new()
	var b := Button.new()
	root.add_child(a)
	root.add_child(b)
	await _frames(1)
	a.grab_focus()
	var seen_bright := false
	for i in 40:
		await process_frame
		if a.self_modulate.r > 1.02:
			seen_bright = true
	_check(seen_bright, "il pulsante a fuoco respira (self_modulate sopra 1)")
	b.grab_focus()
	await _frames(3)
	_check(a.self_modulate.is_equal_approx(Color.WHITE), "perso il focus torna bianco")
	a.queue_free()
	b.queue_free()
	await _frames(1)
