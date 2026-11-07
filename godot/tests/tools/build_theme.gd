extends SceneTree
## Genera il tema di progetto (D-080) da UiPalette e lo salva in
## `res://resources/ui/theme.tres`, registrato in `gui/theme/custom`: cosi vale anche
## dentro i CanvasLayer (pausa, HUD, level-up, Officina...), che il tema della radice
## non raggiunge. Da rilanciare dopo ogni modifica a `ui_palette.gd`:
##   godot_console --headless --path godot --script res://tests/tools/build_theme.gd

const THEME_PATH := "res://resources/ui/theme.tres"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(THEME_PATH.get_base_dir()))
	var error := ResourceSaver.save(UiPalette.build_theme(), THEME_PATH)
	print("THEME_BUILT %s err=%d" % [THEME_PATH, error])
	quit(0 if error == OK else 1)
