extends SceneTree
## Test dei suggerimenti dei tasti (D-059). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/button_prompts_tests.gd

const MenuScene := preload("res://scenes/main/main_menu.tscn")

var _failures := 0


func _initialize() -> void:
	await process_frame
	await _test_prompts()
	await _test_screens()
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _find_prompts(node: Node) -> Array[ButtonPrompts]:
	var found: Array[ButtonPrompts] = []
	for child in node.get_children():
		if child is ButtonPrompts:
			found.append(child)
		found.append_array(_find_prompts(child))
	return found


func _test_prompts() -> void:
	print("prompts")
	var prompts := ButtonPrompts.create([[&"ui_accept", "Conferma"], [&"ui_cancel", "Indietro"], [&"azione_inesistente", "Senza icona"]])
	root.add_child(prompts)
	await process_frame
	_check(prompts.prompt_count() == 3, "una voce per coppia")
	_check(prompts.text_of(0) == "Conferma" and prompts.text_of(1) == "Indietro", "testi nell'ordine dato")
	_check(prompts.icon_of(0) != null and prompts.icon_of(1) != null, "le azioni note hanno un'icona")
	_check(prompts.icon_of(0) != prompts.icon_of(1), "azioni diverse, icone diverse")
	_check(prompts.icon_of(2) == null, "un'azione sconosciuta resta solo testo")
	_check(prompts.mouse_filter == Control.MOUSE_FILTER_IGNORE and prompts.focus_mode == Control.FOCUS_NONE, "mai focus ne mouse")
	_check(not prompts.vertical, "in riga se non richiesto altrimenti")
	prompts.queue_free()
	var column := ButtonPrompts.create([[&"dash", "Scatto"]], true)
	root.add_child(column)
	await process_frame
	_check(column.vertical and column.icon_of(0) != null, "in colonna, con l'icona di un'azione di gioco")
	column.queue_free()
	await process_frame


func _test_screens() -> void:
	print("schermate")
	var menu := MenuScene.instantiate() as MainMenu
	root.add_child(menu)
	await process_frame
	await process_frame
	var in_menu := _find_prompts(menu).filter(func(p: ButtonPrompts) -> bool: return p.get_parent() == menu)
	_check(in_menu.size() == 1 and in_menu[0].is_visible_in_tree(), "il menu iniziale mostra i suoi suggerimenti")
	_check(menu.focused_control() is Button, "il focus resta su un pulsante")
	menu.open_workshop()
	await process_frame
	_check(not in_menu[0].is_visible_in_tree(), "con l'Officina aperta quelli del menu spariscono")
	var in_workshop := _find_prompts(menu.workshop)
	_check(in_workshop.size() == 1 and in_workshop[0].prompt_count() == 2 and in_workshop[0].is_visible_in_tree(),
		"l'Officina mostra Compra e Torna")
	menu.workshop.close()
	await process_frame
	_check(in_menu[0].is_visible_in_tree(), "chiusa l'Officina tornano")
	var pause := root.get_node_or_null(^"PauseMenu")
	_check(pause != null and _find_prompts(pause).size() == 1, "la pausa ha i suoi suggerimenti")
	var hud := RunHud.new()
	root.add_child(hud)
	await process_frame
	var in_hud := _find_prompts(hud)
	var columns := in_hud.filter(func(p: ButtonPrompts) -> bool: return p.vertical)
	_check(columns.size() == 1 and columns[0].prompt_count() == 8, "l'HUD elenca gli otto comandi di gioco (mira D-089, due attive D-092)")
	_check(in_hud.size() == 8, "piu i tasti dei due slot attivi nella striscia delle armi e Interagisci (Ripara, Pilota, Scendi, Riprendi e Banco) nella striscia della carovana")
	hud.queue_free()
	menu.queue_free()
	await process_frame
