extends SceneTree
## Catture della mappa di campagna (D-066), non e una suite. Con finestra reale:
##   godot_console --path godot --resolution 1280x800 --fixed-fps 60 --quit-after 600 --script res://tests/tools/capture_campaign.gd -- --out=../output/campaign
## Produce: map_new (profilo nuovo: solo il quartiere), map_unlocked (dopo una vittoria:
## ferrovia sbloccata, quartiere completato), victory_next (fine livello con "Prossimo livello").

var _out := "../output/campaign"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	var profile := root.get_node("PlayerProfile") as PlayerProfileService
	profile.reset()
	var menu: MainMenu = preload("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	for i in 5:
		await process_frame
	var map: CampaignMapPanel = menu.get_node(^"CampaignMapPanel")
	map.level_chosen.disconnect(menu.start_level)
	menu.start_run()
	for i in 5:
		await process_frame
	await _save("map_new")
	map.close()
	profile.bank_run(23, true, 0, &"district")
	menu.start_run()
	for i in 5:
		await process_frame
	await _save("map_unlocked")
	root.remove_child(menu)
	menu.queue_free()
	var scene: Node3D = preload("res://scenes/main/arena_run.tscn").instantiate()
	root.add_child(scene)
	(scene.get_node(^"EnemyDirector") as EnemyDirector).spawning = false
	for i in 10:
		await physics_frame
	(scene.get_node(^"Run") as ArenaRun)._end_level(true)
	for i in 70:
		await process_frame
	await _save("victory_next")
	quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(_out).path_join("%s.png" % name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s err=%d" % [path, err])
