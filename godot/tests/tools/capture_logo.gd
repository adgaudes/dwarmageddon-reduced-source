extends SceneTree
## Esporta il logo (D-079) in PNG: `logo_wide` (2048 di larghezza, trasparente),
## `logo_stacked` (1024x1024, trasparente), `icon` (256x256 su fondo terracotta).
## Uso: godot_console --path godot --resolution 1280x800 --quit-after 900 --script res://tests/tools/capture_logo.gd -- --out=../output/identity

var _out := "../output/identity"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	await process_frame
	await _render("logo_wide", "wide", 150, Vector2i(2048, 640), Color(0, 0, 0, 0), true)
	await _render("logo_stacked", "stacked", 84, Vector2i(1024, 1024), Color(0, 0, 0, 0), true)
	await _render("icon", "stacked", 20, Vector2i(256, 256), Color("b5652d"), false)
	quit()


func _render(name: String, layout: String, letter_size: int, size: Vector2i, background: Color, subtitle: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = background.a == 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	if background.a > 0.0:
		var fill := ColorRect.new()
		fill.color = background
		fill.size = size
		viewport.add_child(fill)
	var logo := GameLogo.new()
	logo.layout = layout
	logo.letter_size = letter_size
	logo.show_subtitle = subtitle
	viewport.add_child(logo)
	await process_frame
	logo.position = (Vector2(size) - logo.custom_minimum_size) * 0.5
	logo.set_all(1.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://").path_join(_out)
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("%s.png" % name)
	var error := viewport.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, error])
	viewport.queue_free()
