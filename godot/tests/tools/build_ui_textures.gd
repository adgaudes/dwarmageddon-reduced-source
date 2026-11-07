extends SceneTree
## Genera le texture dell'interfaccia (D-081) in `assets/textures/ui/`: piastre di
## cuoio e rame, pulsanti in lamiera, pergamena, nastro, linea, tubo, striscia. Tutto
## da rumore, gradienti e forme: nessun asset esterno. Da rilanciare dopo ogni modifica
## qui, poi `--editor --quit` per importare:
##   godot_console --headless --path godot --script res://tests/tools/build_ui_textures.gd

const DIR := "res://assets/textures/ui/"

const LEATHER := Color("2a1f18")
const LEATHER_LIGHT := Color("3b2c22")
const COPPER := Color("b5652d")
const COPPER_LIGHT := Color("e0a060")
const COPPER_DARK := Color("6e3a1a")
const OUTLINE := Color("130d0a")
const METAL := Color("3e2c21")
const METAL_LIGHT := Color("6a4a35")
const METAL_DARK := Color("241a14")
const PARCHMENT := Color("e9d9b8")
const PARCHMENT_DARK := Color("c9a97a")
const BURN := Color("7a4a26")
const FOCUS := Color("3fc1b5")
const CREAM := Color("f2e6cf")

var _grain: FastNoiseLite
var _mottle: FastNoiseLite
var _wear: FastNoiseLite


func _initialize() -> void:
	_grain = _noise(11, 0.35, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_mottle = _noise(23, 0.045, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_wear = _noise(37, 0.6, FastNoiseLite.TYPE_CELLULAR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_save("plate_panel", _plate_panel())
	_save("plate_button", _plate_button(0))
	_save("plate_button_hover", _plate_button(1))
	_save("plate_button_pressed", _plate_button(2))
	_save("plate_button_focus", _plate_button(3))
	_save("plate_card", _plate_card(false))
	_save("plate_card_focus", _plate_card(true))
	_save("ribbon", _ribbon())
	_save("rule", _rule())
	_save("gauge", _gauge(false))
	_save("gauge_fill", _gauge(true))
	_save("strip", _strip())
	_save("knob", _knob())
	quit()


func _noise(seed: int, frequency: float, type: FastNoiseLite.NoiseType) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = frequency
	n.noise_type = type
	return n


func _save(name: String, image: Image) -> void:
	var path := DIR + name + ".png"
	var error := image.save_png(path)
	print("UI_TEXTURE %s err=%d" % [path, error])


## Distanza con segno dal bordo di un rettangolo arrotondato centrato (negativa dentro).
func _rounded_sdf(x: int, y: int, w: int, h: int, radius: float) -> float:
	var p := Vector2(x + 0.5 - w * 0.5, y + 0.5 - h * 0.5)
	var half := Vector2(w * 0.5, h * 0.5) - Vector2(radius, radius)
	var q := p.abs() - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


func _grain_at(x: int, y: int, amp: float, stretch_x := 1.0) -> float:
	return _grain.get_noise_2d(x / stretch_x, float(y)) * amp


func _mottle_at(x: int, y: int, amp: float) -> float:
	return _mottle.get_noise_2d(float(x), float(y)) * amp


func _wear_at(x: int, y: int) -> float:
	return clampf(_wear.get_noise_2d(float(x), float(y)) * 0.5 + 0.5, 0.0, 1.0)


## Rivetto a cupola: luce in alto a sinistra, bordo scuro.
func _rivet(image: Image, cx: float, cy: float, radius: float) -> void:
	for y in range(int(cy - radius - 1), int(cy + radius + 2)):
		for x in range(int(cx - radius - 1), int(cx + radius + 2)):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy)
			var dist := d.length()
			if dist > radius + 0.8:
				continue
			var n := d / radius
			var light := clampf(0.55 - 0.45 * (n.x + n.y) * 0.7 - n.length_squared() * 0.25, 0.0, 1.0)
			var color := COPPER_DARK.lerp(CREAM, light)
			if dist > radius - 1.0:
				color = OUTLINE.lerp(color, clampf(radius + 0.8 - dist, 0.0, 1.0) * 0.6)
			var alpha := clampf(radius + 0.8 - dist, 0.0, 1.0)
			image.set_pixel(x, y, image.get_pixel(x, y).lerp(color, alpha))


## Pannello: cuoio con grana, cornice di rame battuto con bisello, rivetti negli angoli.
func _plate_panel() -> Image:
	var w := 96
	var h := 96
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var sdf := _rounded_sdf(x, y, w, h, 7.0)
			if sdf > 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var inside := -sdf
			var color: Color
			if inside < 1.6:
				color = OUTLINE
			elif inside < 8.0:
				# Cornice di rame: chiara verso l'esterno-alto, scura verso l'interno-basso.
				var t := (inside - 1.6) / 6.4
				var vertical := float(y) / h
				var base := COPPER_LIGHT.lerp(COPPER, t).lerp(COPPER_DARK, vertical * 0.45)
				base = base.lightened(_grain_at(x, y, 0.12))
				if _wear_at(x, y) > 0.82:
					base = base.lightened(0.18)
				color = base
			elif inside < 9.5:
				color = OUTLINE.lerp(LEATHER, 0.5)
			else:
				var shade := clampf((inside - 9.5) / 10.0, 0.0, 1.0)
				color = LEATHER.darkened(0.25).lerp(LEATHER, shade)
				color = color.lightened(_grain_at(x, y, 0.05) + _mottle_at(x, y, 0.06))
			var edge := clampf(-sdf, 0.0, 1.0)
			image.set_pixel(x, y, Color(color, edge))
	for corner in [Vector2(13, 13), Vector2(w - 13, 13), Vector2(13, h - 13), Vector2(w - 13, h - 13)]:
		_rivet(image, corner.x, corner.y, 3.6)
	return image


## Pulsante: lamiera spazzolata in rilievo con bordo di rame. state: 0 normale, 1 hover,
## 2 premuto (incassato), 3 focus (bordo turchese e alone fuori dal rettangolo).
func _plate_button(state: int) -> Image:
	var w := 96
	var h := 96
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var inset := 8.0 if state == 3 else 0.0
	for y in h:
		for x in w:
			var sdf := _rounded_sdf(x, y, w, h, 6.0 + inset) + inset
			var color: Color
			var alpha := 1.0
			if sdf > 0.0:
				if state == 3 and sdf < 8.0:
					color = FOCUS
					alpha = (1.0 - sdf / 8.0) * 0.45
				else:
					alpha = 0.0
					color = Color(0, 0, 0, 0)
				image.set_pixel(x, y, Color(color, alpha))
				continue
			var inside := -sdf
			var vertical := float(y) / h
			if inside < 1.5:
				color = OUTLINE
			elif inside < 4.0:
				if state == 3:
					color = FOCUS.lerp(Color("8fe6dc"), 1.0 - vertical)
				else:
					color = (COPPER_LIGHT if state == 1 else COPPER).lerp(COPPER_DARK, vertical * 0.5)
					color = color.lightened(_grain_at(x, y, 0.1))
			else:
				var body := METAL.lightened(0.07) if state == 1 else METAL
				if state == 2:
					body = METAL_DARK
				color = body.lightened(_grain_at(x, y, 0.06, 6.0))
				# Rilievo: luce in alto e ombra in basso (invertite se premuto).
				var top := clampf((8.0 - (inside - 4.0)) / 8.0, 0.0, 1.0) * (1.0 - vertical)
				var bottom := clampf((8.0 - (inside - 4.0)) / 8.0, 0.0, 1.0) * vertical
				if state == 2:
					color = color.darkened(top * 0.35).lightened(bottom * 0.12)
				else:
					color = color.lightened(top * 0.22).darkened(bottom * 0.3)
			image.set_pixel(x, y, Color(color, clampf(inside, 0.0, 1.0)))
	return image


## Carta: pergamena con grana, macchie, bordi bruciacchiati; con focus bordo turchese e alone.
func _plate_card(focus: bool) -> Image:
	var w := 96
	var h := 96
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var inset := 8.0 if focus else 0.0
	for y in h:
		for x in w:
			var sdf := _rounded_sdf(x, y, w, h, 5.0 + inset) + inset
			if sdf > 0.0:
				if focus and sdf < 8.0:
					image.set_pixel(x, y, Color(FOCUS, (1.0 - sdf / 8.0) * 0.45))
				else:
					image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var inside := -sdf
			var burn_depth := 5.0 + _wear_at(x, y) * 4.0
			var color: Color
			if inside < 1.4:
				color = OUTLINE.lerp(BURN, 0.3)
			elif focus and inside < 4.0:
				color = FOCUS
			elif inside < burn_depth:
				var t := (inside - 1.4) / maxf(burn_depth - 1.4, 1.0)
				color = BURN.lerp(PARCHMENT_DARK, t)
			else:
				color = PARCHMENT.lightened(_grain_at(x, y, 0.05)).lerp(PARCHMENT_DARK, clampf(_mottle_at(x, y, 0.9), 0.0, 0.35))
				var shade := clampf((inside - burn_depth) / 10.0, 0.0, 1.0)
				color = color.darkened((1.0 - shade) * 0.12)
			image.set_pixel(x, y, Color(color, clampf(inside, 0.0, 1.0)))
	return image


## Nastro bianco (da tingere) con luce in alto, ombra in basso e pieghe alle estremita.
func _ribbon() -> Image:
	var w := 96
	var h := 32
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var vertical := float(y) / h
			var color := Color.WHITE.darkened(vertical * 0.3).lightened(clampf(0.25 - vertical, 0.0, 0.25) * 0.6)
			var fold := 0.0
			if x < 12:
				fold = clampf((12 - x) / 12.0, 0.0, 1.0)
			elif x >= w - 12:
				fold = clampf((x - (w - 13)) / 12.0, 0.0, 1.0)
			color = color.darkened(fold * 0.35)
			var alpha := 1.0
			if y == 0 or y == h - 1:
				color = OUTLINE.lerp(color, 0.4)
			# Code a coda di rondine alle estremita.
			var notch := absf(y - h * 0.5) / (h * 0.5)
			if x < 6 and x < 6 * (1.0 - notch):
				alpha = 0.0
			if x >= w - 6 and (w - 1 - x) < 6 * (1.0 - notch):
				alpha = 0.0
			image.set_pixel(x, y, Color(color, alpha))
	return image


## Linea di rame disegnata a mano, con un nodo al centro.
func _rule() -> Image:
	var w := 256
	var h := 12
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in w:
		var wobble := sin(x * 0.11) * 0.6 + _grain.get_noise_1d(x * 1.7) * 1.2
		var thickness := 1.6 + _grain.get_noise_1d(x * 0.9 + 100.0) * 0.6
		var center := 6.0 + wobble
		var taper := minf(1.0, minf(x, w - 1 - x) / 20.0)
		for y in h:
			var d := absf(y + 0.5 - center)
			var alpha := clampf(thickness * taper - d + 0.5, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var color := COPPER_LIGHT.lerp(COPPER, clampf((y + 0.5 - center) / thickness + 0.5, 0.0, 1.0))
			image.set_pixel(x, y, Color(color, alpha))
			if y + 1 < h:
				var below := image.get_pixel(x, y + 1)
				image.set_pixel(x, y + 1, below.lerp(Color(OUTLINE, 0.6), alpha * 0.5 * (1.0 - below.a)))
	_rivet(image, w * 0.5, 6.0, 3.2)
	return image


## Tubo di metallo con terminali; il riempimento e chiaro da tingere, con un bagliore.
func _gauge(fill: bool) -> Image:
	var w := 64
	var h := 24
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var sdf := _rounded_sdf(x, y, w, h, 10.0)
			if sdf > 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var inside := -sdf
			var vertical := float(y) / h
			var color: Color
			if fill:
				var core := Color.WHITE.darkened(absf(vertical - 0.4) * 0.5)
				color = core if inside > 2.0 else Color.WHITE.darkened(0.35)
			else:
				if inside < 1.5:
					color = OUTLINE
				elif inside < 3.5:
					color = COPPER.lerp(COPPER_DARK, vertical)
				else:
					color = METAL_DARK.darkened(0.3).lightened(clampf(0.2 - vertical, 0.0, 0.2) * 0.4)
			image.set_pixel(x, y, Color(color, clampf(inside, 0.0, 1.0)))
	return image


## Pomello dello slider: un rivetto grande con bordo di rame.
func _knob() -> Image:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in 24:
		for x in 24:
			var d := Vector2(x + 0.5 - 12.0, y + 0.5 - 12.0).length()
			if d <= 11.0:
				image.set_pixel(x, y, Color(COPPER if d > 9.0 else OUTLINE, clampf(11.0 - d, 0.0, 1.0)))
	_rivet(image, 12.0, 12.0, 8.0)
	return image


## Striscia di lamiera scura con bordo rame sopra e sotto e due rivetti.
func _strip() -> Image:
	var w := 96
	var h := 48
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var sdf := _rounded_sdf(x, y, w, h, 6.0)
			if sdf > 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var inside := -sdf
			var color: Color
			if inside < 1.2:
				color = OUTLINE
			elif inside < 3.0:
				color = COPPER.lerp(COPPER_DARK, float(y) / h)
			else:
				color = METAL_DARK.lightened(_grain_at(x, y, 0.07, 5.0)).darkened(clampf((inside - 3.0) / 6.0, 0.0, 1.0) * -0.08 + 0.08)
			image.set_pixel(x, y, Color(color, clampf(inside, 0.0, 1.0)))
	_rivet(image, 11.0, h * 0.5, 3.2)
	_rivet(image, w - 11.0, h * 0.5, 3.2)
	return image
