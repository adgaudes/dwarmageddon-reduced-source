extends SceneTree
## Test degli addon di terze parti (D-057): caricati, senza effetti sul gioco. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/addons_tests.gd

var _failures := 0


func _initialize() -> void:
	await process_frame
	_test_debug_menu()
	_test_controller_icons()
	_test_debug_draw()
	_test_grass_disabled()
	_test_terrain3d_and_jolt()
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _test_debug_menu() -> void:
	print("debug menu")
	var menu := root.get_node_or_null("DebugMenu") as CanvasLayer
	_check(menu != null, "autoload DebugMenu presente")
	if menu == null:
		return
	_check(not menu.visible, "nascosto all'avvio")
	_check(InputMap.has_action("cycle_debug_menu"), "azione cycle_debug_menu registrata (F3)")


func _test_controller_icons() -> void:
	print("controller icons")
	var icons := root.get_node_or_null("ControllerIcons")
	_check(icons != null, "autoload ControllerIcons presente")
	if icons == null:
		return
	# Tipo di input esplicito: in headless la conversione dei tasti fisici della tastiera
	# non e supportata dal display server e stampa un errore.
	const CONTROLLER := 1  # ControllerIcons.InputType.CONTROLLER
	_check(icons.call("parse_path", "ui_accept", CONTROLLER) is Texture2D, "ui_accept ha un'icona controller")
	_check(icons.call("parse_path", "dash", CONTROLLER) is Texture2D, "un'azione di gioco (dash) ha un'icona controller")
	_check(icons.call("parse_path", "steamdeck/a") is Texture2D, "icone Steam Deck disponibili")


func _test_debug_draw() -> void:
	print("debug draw 3d")
	_check(ClassDB.class_exists("DebugDraw3D"), "GDExtension DebugDraw3D caricata")
	_check(Engine.has_singleton("DebugDraw3D"), "singleton DebugDraw3D registrato")


func _test_grass_disabled() -> void:
	print("simple grass textured")
	_check(FileAccess.file_exists("res://addons/simplegrasstextured/plugin.cfg"), "addon installato")
	_check(root.get_node_or_null("SimpleGrass") == null, "plugin non attivo: nessun autoload SimpleGrass")


func _test_terrain3d_and_jolt() -> void:
	print("terrain3d and jolt")
	_check(FileAccess.file_exists("res://addons/terrain_3d/plugin.cfg"), "Terrain3D installato")
	_check(FileAccess.file_exists("res://addons/terrain_3d/bin/libterrain.windows.release.x86_64.dll"), "binario Windows presente")
	_check(FileAccess.file_exists("res://addons/terrain_3d/bin/libterrain.linux.release.x86_64.so"), "binario Linux presente")
	_check(ClassDB.class_exists("Terrain3D"), "estensione caricata (classe Terrain3D)")
	_check(ProjectSettings.get_setting("physics/3d/physics_engine", "") == "Jolt Physics", "motore fisico Jolt")
