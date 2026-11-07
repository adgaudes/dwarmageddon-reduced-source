class_name TerrainSurface
extends RefCounted
## Resa del rilievo continuo (spec 6.2, D-082): sette strati da texture CC0 (impacchettate
## da `tools/textures/fetch_terrain_textures.py`, playtest del 14 ottobre 2026), shader di Terrain3D con il blocco "Rilievo"
## (tinte di alzato e scavato dal delta rispetto alla base, fango nelle conche) e scelta
## dello strato dal control map (`TerrainField.paint_layer`). Solo con finestra: in
## headless Terrain3D non c'e e nessuno chiama queste funzioni.

const LAYERS: Array[String] = ["dirt", "slabs", "asphalt", "dug_soil", "mud", "rubble", "gravel"]
const LAYER_DIRT := 0
const LAYER_SLABS := 1
const LAYER_ASPHALT := 2
const LAYER_DUG_SOIL := 3
const LAYER_MUD := 4
const LAYER_RUBBLE := 5
const LAYER_GRAVEL := 6
## Metri coperti da una ripetizione di ogni strato (uv_scale = 1 / metri). Le texture CC0
## del 14 ottobre 2026 (`tools/textures/fetch_terrain_textures.py`) misurano 1,3-3 m dal
## vero; un po' piu grandi si ripetono meno senza sembrare giganti dalla camera.
const LAYER_METERS: Array[float] = [3.0, 2.2, 3.5, 4.0, 2.0, 2.6, 2.2]
## Tinta per strato (moltiplica l'albedo): le lastre CC0 sono quasi bianche al sole.
const LAYER_TINTS: Array[Color] = [Color.WHITE, Color(0.9, 0.88, 0.84), Color.WHITE, Color(0.9, 0.85, 0.8), Color.WHITE, Color.WHITE, Color.WHITE]
## Strati con un disegno regolare: niente rotazione di detiling, che ne spezzerebbe le
## fughe in una griglia di quadrati (playtest del 14 ottobre, O-08).
## Correzione di rugosita per strato (-1..1): l'asfalto CC0 controsole sembrava bagnato.
const LAYER_ROUGHNESS: Array[float] = [0.0, 0.0, 0.35, 0.0, 0.0, 0.0, 0.0]
const PATTERNED_LAYERS: Array[int] = [LAYER_SLABS]
const DETILE_ROTATION := 0.12
const DETILE_SHIFT := 0.5
## Variazione su grande scala (rumore di Terrain3D) contro la ripetizione: due tinte lievi.
const MACRO_VARIATION_1 := Color(0.86, 0.84, 0.78)
const MACRO_VARIATION_2 := Color(0.92, 0.95, 0.88)
const TEXTURE_DIR := "res://assets/textures/terrain/"
const SHADER := preload("res://resources/materials/terrain_relief.gdshader")
const RAISED_TINT := Color(0.62, 0.42, 0.24)
const DUG_TINT := Color(0.30, 0.20, 0.12)
const MUD_LEVEL := -0.6


## Strati, materiale e shader del rilievo.
static func apply(terrain: Terrain3D) -> void:
	var assets := Terrain3DAssets.new()
	for i in LAYERS.size():
		var asset := Terrain3DTextureAsset.new()
		asset.name = LAYERS[i]
		asset.albedo_texture = load(TEXTURE_DIR + "%s_albedo_height.png" % LAYERS[i])
		asset.normal_texture = load(TEXTURE_DIR + "%s_normal_rough.png" % LAYERS[i])
		asset.uv_scale = 1.0 / LAYER_METERS[i]
		asset.albedo_color = LAYER_TINTS[i]
		asset.roughness = LAYER_ROUGHNESS[i]
		asset.detiling_rotation = 0.0 if i in PATTERNED_LAYERS else DETILE_ROTATION
		asset.detiling_shift = DETILE_SHIFT
		assets.set_texture(i, asset)
	terrain.assets = assets
	var material: Terrain3DMaterial = terrain.material
	material.world_background = Terrain3DMaterial.NONE
	material.auto_shader = false
	material.shader_override = SHADER
	material.shader_override_enabled = true
	set_raised_tint(terrain, RAISED_TINT)
	material.set_shader_param("dug_tint", _rgb(DUG_TINT))
	material.set_shader_param("mud_level", MUD_LEVEL)
	material.set_shader_param("macro_variation1", _rgb(MACRO_VARIATION_1))
	material.set_shader_param("macro_variation2", _rgb(MACRO_VARIATION_2))


## Tinta degli argini alzati dal giocatore (spiked_wall la cambia in metallo chiaro).
static func set_raised_tint(terrain: Terrain3D, color: Color) -> void:
	terrain.material.set_shader_param("raised_tint", _rgb(color))


## La base del livello come texture R32F (stessa risoluzione del campo): lo shader ne
## ricava il delta per le tinte di alzato e scavato.
static func update_base(terrain: Terrain3D, base: PackedFloat32Array, resolution_x: int, resolution_z: int, half: Vector2) -> void:
	var image := Image.create_from_data(resolution_x, resolution_z, false, Image.FORMAT_RF, base.to_byte_array())
	terrain.material.set_shader_param("base_map", ImageTexture.create_from_image(image))
	terrain.material.set_shader_param("base_half", half)


static func _rgb(color: Color) -> Vector3:
	return Vector3(color.r, color.g, color.b)
