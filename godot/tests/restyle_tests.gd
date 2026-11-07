extends SceneTree
## Restyling grafico (spec 2026-10-11) sul rilievo continuo (D-085): tile di superficie,
## strati di Terrain3D e shader del rilievo, texture negli shader, prato e prop appoggiati
## al rilievo, preset grafici, camera a tre distanze. Con finestra si controlla anche
## Terrain3D (`godot_console --path godot --resolution 1280x800 --fixed-fps 60 --script ...`).
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/restyle_tests.gd

const SURFACE_DIR := "res://assets/textures/surfaces"
## Gruppo -> numero di strati, nell'ordine fissato dal piano (Task 2).
const SURFACE_LAYERS := {"ground": 6, "walls": 4, "plants": 2}
## Lato per gruppo: il suolo copre lo schermo, muri e piante no (VRAM).
const SURFACE_SIZES := {"ground": 512, "walls": 256, "plants": 256}  # Meridian copy: textures at 1/4
const COMPRESSED_FORMATS: Array[int] = [Image.FORMAT_DXT1, Image.FORMAT_DXT5, Image.FORMAT_BPTC_RGBA,
	Image.FORMAT_RGTC_RG, Image.FORMAT_DXT5_RA_AS_RG, Image.FORMAT_BPTC_RGBF, Image.FORMAT_ETC2_RGBA8]

const RunScene := preload("res://scenes/main/arena_run.tscn")

var _failures := 0
var _scene: Node


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_test_surface_tiles()
	await _test_terrain_textures()
	await _test_ruin_textures()
	await _test_vegetation_and_props()
	await _test_sky_and_post()
	await _test_world_applies_preset()
	await _test_camera_distance()
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_surface_tiles() -> void:
	print("surface tiles")
	for group: String in SURFACE_LAYERS:
		for map in ["albedo", "normal", "orm"]:
			var path := "%s/%s_%s.png" % [SURFACE_DIR, group, map]
			var texture: Resource = load(path) if ResourceLoader.exists(path) else null
			# L'import produce una CompressedTexture2DArray, che deriva da TextureLayered
			# (non da Texture2DArray): si controlla il tipo di strati.
			var is_array := texture is TextureLayered and (texture as TextureLayered).get_layered_type() == TextureLayered.LAYERED_TYPE_2D_ARRAY
			_check(is_array, "%s e un array 2D di texture" % path)
			if not is_array:
				continue
			var array := texture as TextureLayered
			_check(array.get_layers() == SURFACE_LAYERS[group], "%s ha %d strati" % [path, SURFACE_LAYERS[group]])
			var side: int = SURFACE_SIZES[group]
			_check(array.get_width() == side and array.get_height() == side, "%s e %dx%d per strato" % [path, side, side])
			_check(array.get_format() in COMPRESSED_FORMATS, "%s e compressa in VRAM (formato %d)" % [path, array.get_format()])


func _test_terrain_textures() -> void:
	print("terrain textures")
	await _open_scene()
	var district: RuinsDistrict = _scene.get_node(^"District")
	var field: TerrainField = _scene.get_node(^"TerrainField")
	_check(district.terrain_field == field, "il quartiere conosce il rilievo")
	_check(district.find_child("Ground", true, false) == null, "niente lastra piatta: il suolo e il rilievo")
	for layer: String in TerrainSurface.LAYERS:
		var albedo_path := "res://assets/textures/terrain/%s_albedo_height.png" % layer
		var normal_path := "res://assets/textures/terrain/%s_normal_rough.png" % layer
		_check(ResourceLoader.exists(albedo_path) and ResourceLoader.exists(normal_path), "tile %s impacchettate per Terrain3D" % layer)
	var dirt: Texture2D = load("res://assets/textures/terrain/dirt_albedo_height.png")
	_check(dirt is CompressedTexture2D and dirt.get_width() == 256 and dirt.get_image().get_format() in COMPRESSED_FORMATS,
		"tile del rilievo a 256 px compresse in VRAM")
	var code: String = TerrainSurface.SHADER.code
	_check(code.contains("delta_tint") and code.contains("base_map") and code.contains("raised_tint"), "lo shader del rilievo legge il delta dalla base e tinge gli argini")
	var terrain := field.terrain3d()
	if terrain != null:
		_check(terrain.material.shader_override_enabled and terrain.material.shader_override == TerrainSurface.SHADER, "shader del rilievo attivo")
		_check(terrain.assets.get_texture_count() == TerrainSurface.LAYERS.size(), "cinque strati di tile (%d)" % terrain.assets.get_texture_count())
		_check(terrain.material.get_shader_param("base_map") != null, "la base del rilievo e nello shader")
		# Terrain3D ricarica sulla GPU ogni regione marcata `edited` a ogni update_maps:
		# lasciate marcate, ogni pennellata ricaricava tutto il livello (picchi di 23 ms).
		field.player_sculpt(Vector3(10.0, 0.0, 10.0), 2.4, -0.03, TerrainField.ToolMode.DIG)
		field.paint_layer(Vector3(10.0, 0.0, 10.0), 2.4, 0)
		field.tint(Vector3(10.0, 0.0, 10.0), 2.4, Color.BROWN, 0.5)
		var still_edited := 0
		for region: Terrain3DRegion in terrain.data.get_regions_active():
			still_edited += 1 if region.edited else 0
		_check(still_edited == 0, "dopo pennellata, strato e tinta nessuna regione resta da ricaricare (%d)" % still_edited)
	else:
		print("  skip controlli Terrain3D (headless)")
	await _close_scene()


func _test_ruin_textures() -> void:
	print("ruin textures")
	await _open_scene()
	var district: Node3D = _scene.get_node(^"District")
	var block := district.find_child("Block0", true, false)
	_check(block != null, "esiste il guscio Block0")
	var pieces: Array[Node] = block.find_children("*", "MeshInstance3D", true, false) if block != null else []
	var piece: MeshInstance3D = pieces[0] as MeshInstance3D if pieces.size() > 0 else null
	var material := piece.material_override as ShaderMaterial if piece != null else null
	for map in ["albedo", "orm"]:
		_check(material != null and material.get_shader_parameter("walls_%s" % map) is TextureLayered, "i muri delle rovine usano l'array walls_%s" % map)
	_check(piece != null and piece.get_instance_shader_parameter(&"base_tint") != null, "base_tint per istanza ancora impostata sui pezzi")
	var crowns: MultiMeshInstance3D = district.find_child("RuinCrowns", true, false)
	var crown_material := crowns.material_override as ShaderMaterial if crowns != null else null
	_check(crown_material != null and crown_material.get_shader_parameter(&"batched") == true, "le corone restano batched")
	_check(crown_material != null and crown_material.get_shader_parameter(&"walls_albedo") is TextureLayered, "le corone usano l'array walls_albedo")
	await _close_scene()


func _test_vegetation_and_props() -> void:
	print("vegetation and props")
	await _open_scene()
	var district: Node3D = _scene.get_node(^"District")
	# Con finestra il prato lo fa GrassField a particelle (O-09): si controlla quello e si
	# saltano le prove dei ciuffi del MultiMesh, che restano per l'headless.
	var gpu_grass := district.get_node_or_null(^"GrassField") as GrassField
	if gpu_grass != null:
		_check(gpu_grass.particle_nodes.size() > 9, "prato a particelle diviso in celle (%d)" % gpu_grass.particle_nodes.size())
		_check(gpu_grass.blade_material.shader.code.contains("wind.gdshaderinc"), "il prato a particelle usa il campo di vento condiviso")
		_check(district.find_child("GrassTufts", true, false) == null, "con il prato a particelle i ciuffi del MultiMesh non ci sono")
		await _close_scene()
		return
	# Audit V-01: il prato e diviso in porzioni sotto il nodo GrassTufts.
	var tuft_holder := district.find_child("GrassTufts", true, false)
	var tiles: Array[Node] = tuft_holder.get_children() if tuft_holder != null else []
	_check(tiles.size() > 9, "prato diviso in porzioni scartabili dal frustum (%d)" % tiles.size())
	var tufts: MultiMeshInstance3D = tiles[0] as MultiMeshInstance3D if not tiles.is_empty() else null
	var grass_material := tufts.material_override as ShaderMaterial if tufts != null else null
	_check(grass_material != null and grass_material.get_shader_parameter(&"plants_albedo") is TextureLayered, "l'erba usa l'array plants_albedo")
	# Prato basso al vento (D-083): due quad per ciuffo, vento dal campo condiviso.
	_check(tufts != null and tufts.multimesh.mesh.get_faces().size() == 36, "ogni chiazza di prato e fatta di sei quad (dodici triangoli)")
	_check(grass_material != null and float(grass_material.get_shader_parameter(&"wind_strength")) > 0.0, "l'erba ha una forza di vento maggiore di zero")
	_check(grass_material != null and grass_material.shader.code.contains("wind.gdshaderinc"), "l'erba usa il campo di vento condiviso")
	var bush := district.find_child("Bush", true, false)
	var cards: Array[Node] = bush.find_children("*", "MeshInstance3D", true, false) if bush != null else []
	var card: MeshInstance3D = cards[0] as MeshInstance3D if cards.size() > 0 else null
	var card_uv: Variant = card.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] if card != null else null
	_check(card != null and card_uv != null and (card_uv as PackedVector2Array).size() > 0, "i cespugli sono cartelle con UV")
	var bush_material := card.material_override as ShaderMaterial if card != null else null
	_check(bush_material != null and bush_material.get_shader_parameter(&"textured") == true and bush_material.get_shader_parameter(&"plants_albedo") is TextureLayered, "i cespugli usano le cartelle di foglie dipinte")
	_check(bush_material != null and bush_material.shader.code.contains("wind.gdshaderinc"), "i cespugli si muovono con lo stesso campo di vento del prato")
	var car := district.find_child("WreckedCar", true, false)
	var meshes: Array[Node] = car.find_children("*", "MeshInstance3D", true, false) if car != null else []
	var found_maps := false
	for node in meshes:
		var mi := node as MeshInstance3D
		for surface in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(surface) as ShaderMaterial
			if mat != null and mat.get_shader_parameter(&"has_maps") == true 					and mat.get_shader_parameter(&"normal_tex") != null and mat.get_shader_parameter(&"orm_tex") != null:
				found_maps = true
	_check(found_maps, "i prop cotti hanno normal e ORM nel materiale env_baked")
	var tree := district.find_child("Tree", true, false)
	var tree_meshes: Array[Node] = tree.find_children("*", "MeshInstance3D", true, false) if tree != null else []
	var leaves_textured := false
	for node in tree_meshes:
		var mi := node as MeshInstance3D
		# Chioma generata (playtest del 14 ottobre): materiale su tutto il nodo "Crown".
		var whole := mi.material_override as ShaderMaterial
		if mi.name == "Crown" and whole != null and whole.get_shader_parameter(&"textured") == true:
			leaves_textured = true
		for surface in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(surface) as ShaderMaterial
			if mat != null and mat.get_shader_parameter(&"textured") == true:
				leaves_textured = true
	_check(leaves_textured, "la chioma dell'albero usa le cartelle di foglie dipinte")
	# Rilievo continuo (D-085): prato e prop poggiano sulle quote, niente prato sui fianchi.
	var field: TerrainField = _scene.get_node(^"TerrainField")
	var sample := tufts.multimesh.get_instance_transform(0).origin
	_check(absf(sample.y - field.height_at(sample)) < 0.15, "il prato poggia sul rilievo (%.2f vs %.2f)" % [sample.y, field.height_at(sample)])
	var on_steep := 0
	var off_ground := 0
	for i in range(0, tufts.multimesh.instance_count, 97):
		var origin := tufts.multimesh.get_instance_transform(i).origin
		if field.slope_at(origin) > 0.6:
			on_steep += 1
		if absf(origin.y - field.height_at(origin)) > 0.15:
			off_ground += 1
	_check(on_steep == 0, "niente prato sui fianchi ripidi (%d)" % on_steep)
	_check(off_ground == 0, "tutto il prato campionato poggia sul rilievo (%d fuori quota)" % off_ground)
	var settled := 0
	var floating := 0
	for child in district.get_children():
		if child is StaticBody3D and (child.name.begins_with("Block") or child.name.begins_with("Tree") or child.name.begins_with("WreckedCar")):
			settled += 1
			var at: Vector3 = (child as Node3D).global_position
			if absf(at.y - field.height_at(at)) > 0.4:
				floating += 1
	_check(settled > 10 and floating == 0, "rovine, alberi e auto appoggiati al rilievo (%d controllati, %d fuori quota)" % [settled, floating])
	await _close_scene()


func _test_sky_and_post() -> void:
	print("sky and post")
	await _open_scene()
	var env: Environment = (_scene.get_node(^"District/WorldEnvironment") as WorldEnvironment).environment
	var sky_material := env.sky.sky_material if env.sky != null else null
	_check(sky_material is ShaderMaterial, "il cielo e dipinto (ShaderMaterial)")
	# D-094: AgX al posto di ACES, che sbiancava le alte luci.
	_check(env.tonemap_mode == Environment.TONE_MAPPER_AGX, "tonemap AgX")
	_check(env.adjustment_enabled and env.adjustment_saturation >= 1.2, "saturazione alzata")
	_check(env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and env.ambient_light_color.b > env.ambient_light_color.r, "ambiente freddo: ombre blu-viola")
	# D-094: sole in controluce (la luce va verso la camera, +Z), riempimento senza ombre,
	# ombre delle nuvole.
	var key_light := _scene.get_node(^"District/SunLight") as DirectionalLight3D
	_check(key_light != null and (-key_light.basis.z).z > 0.0, "sole in controluce: la luce scende verso la camera")
	var fill := _scene.get_node_or_null(^"District/FillLight") as FillLight
	_check(fill != null and not fill.shadow_enabled and fill.light_specular == 0.0, "luce di riempimento senza ombre ne riflessi")
	_check(_scene.get_node_or_null(^"District/CloudShadows") is CloudShadows, "ombre delle nuvole presenti")
	var sun: DirectionalLight3D = _scene.get_node(^"District/SunLight")
	_check(sun.light_angular_distance > 0.0, "il sole ha un diametro angolare (ombre morbide)")
	var day_night: DayNightCycle = _scene.get_node(^"Run").day_night
	var day_top: Color = (sky_material as ShaderMaterial).get_shader_parameter(&"top_color") if sky_material is ShaderMaterial else Color.WHITE
	day_night.night_start_seconds = 1.0  # 0 spegnerebbe il ciclo
	day_night.dusk_seconds = 1.0
	day_night.advance(5.0)
	var night_top: Color = (sky_material as ShaderMaterial).get_shader_parameter(&"top_color") if sky_material is ShaderMaterial else Color.WHITE
	_check(night_top.v < day_top.v, "di notte il cielo dipinto si scurisce")
	var player := _scene.get_node(^"Player")
	var suit_rim := false
	for mi: MeshInstance3D in player.find_children("*", "MeshInstance3D", true, false):
		for surface in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(surface) as StandardMaterial3D
			if mat != null and mat.rim_enabled:
				suit_rim = true
	_check(suit_rim, "l'ingegnere ha la rim light nel materiale della tuta")
	await _close_scene()


func _test_world_applies_preset() -> void:
	print("world applies preset")
	var settings: GameSettingsService = root.get_node("GameSettings")
	settings.set_preset(GameSettingsService.Preset.MAX)
	await _open_scene()
	var env: Environment = (_scene.get_node(^"District/WorldEnvironment") as WorldEnvironment).environment
	_check(env.sdfgi_enabled and env.volumetric_fog_enabled, "l'arena nasce con il preset Massimo applicato")
	settings.set_preset(GameSettingsService.Preset.STEAM_DECK)
	await _frames(1)
	_check(not env.sdfgi_enabled and not env.volumetric_fog_enabled and env.ssao_enabled, "cambiare preset a scena aperta aggiorna l'ambiente")
	var sun: DirectionalLight3D = _scene.find_child("SunLight", true, false)
	_check(sun != null and is_zero_approx(sun.light_angular_distance) and sun.directional_shadow_max_distance <= 60.0,
		"preset Steam Deck: niente ombre PCSS e distanza d'ombra ridotta (audit V-04)")
	settings.set_preset(GameSettingsService.Preset.HIGH)
	await _frames(1)
	_check(sun != null and sun.light_angular_distance > 1.0 and sun.directional_shadow_max_distance >= 90.0, "preset Alto: sole morbido e ombre lontane come prima")
	settings.set_preset(GameSettingsService.Preset.STEAM_DECK)
	await _frames(1)
	var district := _scene.get_node(^"District")
	var full_count := _grass_instances(district)
	await _close_scene()
	await _open_scene()
	district = _scene.get_node(^"District")
	var medium_count := _grass_instances(district)
	_check(medium_count < full_count, "con densita media l'erba ha meno istanze (%d < %d)" % [medium_count, full_count])
	settings.set_preset(GameSettingsService.Preset.HIGH)
	await _close_scene()


## Istanze del prato: con finestra le particelle di GrassField (O-09), in headless i
## ciuffi del MultiMesh.
func _grass_instances(district: Node) -> int:
	var grass := district.get_node_or_null(^"GrassField") as GrassField
	if grass == null:
		return _cover_instances(district, "GrassTufts")
	var total := 0
	for node in grass.particle_nodes:
		total += node.amount
	return total


## Istanze totali di una copertura divisa in porzioni (audit V-01).
func _cover_instances(district: Node, cover_name: String) -> int:
	var total := 0
	var holder := district.find_child(cover_name, true, false)
	if holder != null:
		for tile in holder.get_children():
			total += (tile as MultiMeshInstance3D).multimesh.instance_count
	return total


func _test_camera_distance() -> void:
	print("camera distance")
	await _open_scene()
	var director: EnemyDirector = _scene.get_node(^"EnemyDirector")
	var rig: IsometricCameraRig = _scene.get_node(^"CameraRig")
	_check(is_equal_approx(rig.current_arm_m(), 15.0), "parte a 15 m")
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_Y
	press.pressed = true
	Input.parse_input_event(press)
	var release := press.duplicate() as InputEventJoypadButton
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(2)
	_check(rig.distance_index == 2, "Y passa al preset lontano")
	var settings: GameSettingsService = root.get_node("GameSettings")
	_check(settings.camera_distance == 2, "la distanza lontana si salva subito nelle impostazioni")
	var run: ArenaRun = _scene.get_node(^"Run")
	_check(run.marker_min_distance() > 18.0, "gli indicatori a bordo schermo seguono la camera lontana (%.1f m)" % run.marker_min_distance())
	await _frames(45)
	_check(absf(rig.current_arm_m() - 20.0) < 0.2, "il braccio arriva a 20 m in meno di 0,75 s (%.2f)" % rig.current_arm_m())
	_check(director.ring_scale > 1.3 and director.ring_scale * director.tuning.spawn_ring_min >= 22.0, "l'anello di comparsa si allarga con la camera lontana (%.2f)" % director.ring_scale)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(640, 400)
	wheel.global_position = wheel.position
	Input.parse_input_event(wheel)
	await _frames(2)
	_check(rig.distance_index == 1, "la rotellina in su avvicina di un preset")
	_check(settings.camera_distance == 1, "la distanza normale si salva nelle impostazioni")
	_check(absf(run.marker_min_distance() - 14.0) < 0.01 or run.marker_min_distance() < 18.0, "gli indicatori tornano alla soglia normale")
	settings.set_camera_distance(0)
	await _frames(2)
	_check(rig.distance_index == 0, "cambiare la distanza dalle impostazioni muove la camera")
	settings.set_camera_distance(1)
	await _close_scene()


func _open_scene() -> void:
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_scene.get_node(^"EnemyDirector").spawning = false
	await _frames(5)


func _close_scene() -> void:
	root.remove_child(_scene)
	_scene.queue_free()
	_scene = null
	await _frames(2)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
