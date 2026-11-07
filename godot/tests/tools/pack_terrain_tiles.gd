extends SceneTree
## Impacchetta le tile del suolo per Terrain3D (Task 14 del terreno continuo): dai fogli
## verticali `assets/textures/surfaces/ground_{albedo,normal,orm}.png` (sei strati da
## 2048, cotti da `tools/blender/build_surface_tiles.py`) ricava, per i cinque strati
## del rilievo, `assets/textures/terrain/<nome>_albedo_height.png` (RGB albedo, A =
## altezza macro dalla luminanza sfocata) e `<nome>_normal_rough.png` (RGB normal, A =
## rugosita dall'ORM), a SIDE px, con gli `.import` VRAM. Poi `--editor --quit`.
##   godot_console --headless --path godot --script res://tests/tools/pack_terrain_tiles.gd

const SRC := "res://assets/textures/surfaces/"
const DST := "res://assets/textures/terrain/"
## Strati di `ground` nell'ordine del foglio; `grass` (5) non serve: il prato e dipinto a parte.
const LAYERS := ["dirt", "slabs", "asphalt", "dug_soil", "mud"]
const SIDE := 1024
## Lato della luminanza sfocata che fa da altezza (rilievo macro della tile).
const HEIGHT_SIDE := 48


func _initialize() -> void:
	var albedo := _load_sheet("ground_albedo.png")
	var normal := _load_sheet("ground_normal.png")
	var orm := _load_sheet("ground_orm.png")
	if albedo == null or normal == null or orm == null:
		print("PACK_TERRAIN_TILES FAIL reason=missing_sheet")
		quit(1)
		return
	var tile := albedo.get_width()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	for i in LAYERS.size():
		var rect := Rect2i(0, i * tile, tile, tile)
		var a := _square(albedo.get_region(rect))
		var n := _square(normal.get_region(rect))
		var o := _square(orm.get_region(rect))
		_save("%s_albedo_height" % LAYERS[i], _with_alpha(a, _height_of(a)), false)
		_save("%s_normal_rough" % LAYERS[i], _with_alpha(n, _channel(o, 1)), true)
	print("PACK_TERRAIN_TILES PASS layers=%d side=%d" % [LAYERS.size(), SIDE])
	quit(0)


func _load_sheet(name: String) -> Image:
	var path := ProjectSettings.globalize_path(SRC + name)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return image


func _square(image: Image) -> Image:
	image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != SIDE:
		image.resize(SIDE, SIDE, Image.INTERPOLATE_LANCZOS)
	return image


## Altezza macro: luminanza sfocata (riduzione a HEIGHT_SIDE e ritorno), normalizzata 0..1.
func _height_of(albedo: Image) -> PackedByteArray:
	var small := albedo.duplicate() as Image
	small.resize(HEIGHT_SIDE, HEIGHT_SIDE, Image.INTERPOLATE_LANCZOS)
	small.convert(Image.FORMAT_L8)
	var lo := 255
	var hi := 0
	for b in small.get_data():
		lo = mini(lo, b)
		hi = maxi(hi, b)
	small.resize(SIDE, SIDE, Image.INTERPOLATE_CUBIC)
	var data := small.get_data()
	var span := maxi(hi - lo, 1)
	for i in data.size():
		data[i] = clampi((data[i] - lo) * 255 / span, 0, 255)
	return data


## Un canale (0 = R, 1 = G, 2 = B) di un'immagine RGBA8 come byte.
func _channel(image: Image, channel: int) -> PackedByteArray:
	var data := image.get_data()
	var out := PackedByteArray()
	out.resize(SIDE * SIDE)
	for i in out.size():
		out[i] = data[i * 4 + channel]
	return out


func _with_alpha(rgb: Image, alpha: PackedByteArray) -> Image:
	var data := rgb.get_data()
	for i in alpha.size():
		data[i * 4 + 3] = alpha[i]
	return Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_RGBA8, data)


func _save(name: String, image: Image, normal_map: bool) -> void:
	var path := DST + name + ".png"
	image.save_png(path)
	var import := FileAccess.open(path + ".import", FileAccess.WRITE)
	import.store_string("""[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=%d
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
""" % [path, 1 if normal_map else 0])
	import.close()
	print("PACK_TERRAIN_TILE %s %dx%d" % [name, image.get_width(), image.get_height()])
