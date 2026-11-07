class_name GameLogo
extends Control
## Logo "Dwarmageddon: Dig or Die" (D-079), vettoriale: una Label per lettera su una
## linea di base ad arco (sempre su una riga), chiodo piantato nella prima "O" con crepa, zolla con ciuffi
## d'erba sotto, sottotitolo su targa inclinata. I metodi `set_*_progress` (0..1)
## servono all'intro (BootIntro) per animarlo; `set_all(1.0)` lo mostra finito.

const TITLE := "DWARMAGEDDON"
const SUBTITLE := "DIG OR DIE"
const NAIL_LETTER := 10
const ARC_PIXELS := 0.09
const DROP_PIXELS := 1.6
const SUBTITLE_TILT := -2.0
const GLYPH_SPACING := 0.96
const SHADOW_OFFSET := Vector2(0.06, 0.07)
const SHADOW_COLOR := Color(0.05, 0.03, 0.02, 0.55)

@export_enum("wide", "stacked") var layout := "wide"
@export var show_subtitle := true
@export var letter_size := 96

var _letters: Array[Label] = []
var _shadows: Array[Label] = []
var _rest_positions: Array[Vector2] = []
var _letter_progress := 1.0
var _nail_progress := 1.0
var _subtitle_progress := 1.0
var _grass_progress := 1.0
var _subtitle: Label
var _plate: Control
var _rows: Array[String] = []
var _nail_anchor := Vector2.ZERO
var _ground_rect := Rect2()
var _material: ShaderMaterial
var _overlay: Control
var _font_height := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.clear()
	# Il nome resta sempre su una riga (scelta del proprietario, 12 ottobre 2026: la
	# divisione DWARMA / GEDDON non gli piaceva). "stacked" cambia solo la targa del
	# sottotitolo, piu larga e piu alta per i formati quadrati.
	_rows.append(TITLE)
	_material = ShaderMaterial.new()
	_material.shader = load("res://resources/materials/logo_letters.gdshader")
	_material.set_shader_parameter(&"top_y", float(letter_size) * 0.15)
	_material.set_shader_parameter(&"bottom_y", float(letter_size) * 1.1)
	_material.set_shader_parameter(&"bevel_px", maxf(letter_size / 40.0, 1.5))
	_build_letters()
	_overlay = Control.new()
	_overlay.name = "Decor"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_build_subtitle()
	queue_redraw()


func letter_count() -> int:
	return _letters.size()


func shadow_count() -> int:
	return _shadows.size()


func letter_material() -> ShaderMaterial:
	return _material


func is_complete() -> bool:
	return _letter_progress >= 1.0 and _nail_progress >= 1.0 and _subtitle_progress >= 1.0 and _grass_progress >= 1.0


func set_all(p: float) -> void:
	set_letter_progress(p)
	set_nail_progress(p)
	set_subtitle_progress(p)
	set_grass_progress(p)


## Le lettere cadono una alla volta: la lettera i parte a i/n e atterra a (i+1)/n.
func set_letter_progress(p: float) -> void:
	_letter_progress = clampf(p, 0.0, 1.0)
	var n := _letters.size()
	for i in n:
		var local := clampf(_letter_progress * n - i, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - local, 3.0)
		var drop := DROP_PIXELS * letter_size * (1.0 - eased)
		_letters[i].position = _rest_positions[i] + Vector2(0, -drop)
		_letters[i].modulate.a = minf(local * 3.0, 1.0)
		# L'ombra resta a terra e si scurisce quando la lettera atterra.
		_shadows[i].position = _rest_positions[i] + SHADOW_OFFSET * letter_size
		_shadows[i].modulate.a = eased


func set_nail_progress(p: float) -> void:
	_nail_progress = clampf(p, 0.0, 1.0)
	if _overlay != null:
		_overlay.queue_redraw()


func set_subtitle_progress(p: float) -> void:
	_subtitle_progress = clampf(p, 0.0, 1.0)
	if _plate == null:
		return
	var s := lerpf(1.3, 1.0, 1.0 - pow(1.0 - _subtitle_progress, 2.0))
	_plate.scale = Vector2(s, s)
	_plate.modulate.a = minf(_subtitle_progress * 4.0, 1.0)


func set_grass_progress(p: float) -> void:
	_grass_progress = clampf(p, 0.0, 1.0)
	if _overlay != null:
		_overlay.queue_redraw()


func _glyph_width(font: Font, ch: String) -> float:
	return font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, letter_size).x * GLYPH_SPACING


func _build_letters() -> void:
	var font := UiPalette.title_font()
	_font_height = font.get_height(letter_size)
	var row_height := _font_height * 0.92
	var widest := 0.0
	var row_widths: Array[float] = []
	for row in _rows:
		var w := 0.0
		for ch in row:
			w += _glyph_width(font, ch)
		row_widths.append(w)
		widest = maxf(widest, w)
	var subtitle_height := float(letter_size) * 0.55 if show_subtitle else 0.0
	var ground_height := float(letter_size) * 0.35
	custom_minimum_size = Vector2(widest + letter_size * 0.6, row_height * _rows.size() + letter_size * 0.02 + subtitle_height + ground_height)
	size = custom_minimum_size
	var y := 0.0
	var index := 0
	for r in _rows.size():
		var row := _rows[r]
		var x := (custom_minimum_size.x - row_widths[r]) * 0.5
		var count := row.length()
		for c in count:
			var glyph_w := _glyph_width(font, row[c])
			var t := float(c) / maxf(count - 1, 1)
			var arc := -ARC_PIXELS * letter_size * sin(PI * t)
			var rest := Vector2(x, y + arc)
			# Ombra portata: stessa lettera, scura, dietro e spostata in basso a destra.
			var shadow := Label.new()
			shadow.text = row[c]
			shadow.add_theme_font_override(&"font", font)
			shadow.add_theme_font_size_override(&"font_size", letter_size)
			shadow.add_theme_color_override(&"font_color", SHADOW_COLOR)
			shadow.add_theme_color_override(&"font_outline_color", SHADOW_COLOR)
			shadow.add_theme_constant_override(&"outline_size", maxi(letter_size / 12, 4))
			shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			shadow.position = rest + SHADOW_OFFSET * letter_size
			add_child(shadow)
			_shadows.append(shadow)
			var label := Label.new()
			label.text = row[c]
			label.theme_type_variation = &"TitleLabel"
			label.add_theme_font_override(&"font", font)
			label.add_theme_font_size_override(&"font_size", letter_size)
			label.add_theme_color_override(&"font_color", Color.WHITE)
			label.add_theme_color_override(&"font_outline_color", UiPalette.OUTLINE)
			label.add_theme_constant_override(&"outline_size", maxi(letter_size / 12, 4))
			label.material = _material
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(label)
			_rest_positions.append(rest)
			label.position = rest
			_letters.append(label)
			if index == NAIL_LETTER:
				_nail_anchor = rest + Vector2(glyph_w * 0.5, _font_height * 0.56)
			x += glyph_w
			index += 1
		y += row_height
	_ground_rect = Rect2(letter_size * 0.1, y + letter_size * 0.02, custom_minimum_size.x - letter_size * 0.2, ground_height)
	for label in _letters:
		move_child(label, get_child_count() - 1)


func _build_subtitle() -> void:
	if not show_subtitle:
		return
	_plate = Control.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	var plate_size := Vector2(letter_size * 3.4, letter_size * 0.42)
	if layout == "stacked":
		plate_size = Vector2(custom_minimum_size.x * 0.6, letter_size * 0.5)
	_plate.position = Vector2((custom_minimum_size.x - plate_size.x) * 0.5, _ground_rect.position.y + _ground_rect.size.y * 0.25)
	_plate.size = plate_size
	_plate.pivot_offset = plate_size * 0.5
	_plate.rotation_degrees = SUBTITLE_TILT
	var panel := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiPalette.OUTLINE
	box.border_color = UiPalette.BORDER
	box.set_border_width_all(maxi(letter_size / 32, 2))
	box.set_corner_radius_all(3)
	panel.add_theme_stylebox_override(&"panel", box)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(panel)
	_subtitle = Label.new()
	_subtitle.text = SUBTITLE
	_subtitle.theme_type_variation = &"SectionLabel"
	_subtitle.add_theme_font_override(&"font", UiPalette.title_font())
	_subtitle.add_theme_font_size_override(&"font_size", int(letter_size * (0.34 if layout == "stacked" else 0.28)))
	_subtitle.add_theme_color_override(&"font_color", UiPalette.TEXT)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_subtitle)


func _draw() -> void:
	_draw_ground()


func _draw_overlay() -> void:
	_draw_grass()
	_draw_nail()


## Zolla: poligono scuro con bordo superiore ondulato e una riga di luce.
func _draw_ground() -> void:
	var r := _ground_rect
	var top := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var t := float(i) / steps
		top.append(Vector2(r.position.x + r.size.x * t, r.position.y + sin(t * 9.0) * r.size.y * 0.12))
	var polygon := PackedVector2Array(top)
	polygon.append(Vector2(r.end.x - r.size.x * 0.03, r.end.y))
	polygon.append(Vector2(r.position.x + r.size.x * 0.03, r.end.y))
	draw_colored_polygon(polygon, Color("3b2718"))
	draw_polyline(top, Color("7a4a2a"), maxf(letter_size / 40.0, 2.0))
	# Sassi incastrati nella terra e radici che scendono.
	for k in 5:
		var t := 0.08 + 0.21 * k
		var center := Vector2(r.position.x + r.size.x * t, r.position.y + r.size.y * (0.45 + 0.25 * (k % 2)))
		var radius := letter_size * (0.045 + 0.015 * (k % 3))
		draw_circle(center, radius, Color("5a4030"))
		draw_circle(center + Vector2(-radius * 0.25, -radius * 0.3), radius * 0.55, Color("7a5a44"))
	for k in 3:
		var sx := r.position.x + r.size.x * (0.3 + 0.2 * k)
		var points := PackedVector2Array([Vector2(sx, r.position.y + r.size.y * 0.5), Vector2(sx - letter_size * 0.05, r.end.y - r.size.y * 0.2), Vector2(sx + letter_size * 0.03, r.end.y)])
		draw_polyline(points, Color("2a1a10"), maxf(letter_size / 48.0, 1.5))


## Tre ciuffi d'erba che crescono con il progresso.
func _draw_grass() -> void:
	if _grass_progress <= 0.0:
		return
	var r := _ground_rect
	for k in 3:
		var base := Vector2(r.position.x + r.size.x * (0.18 + 0.32 * k), r.position.y + r.size.y * 0.05)
		var h := letter_size * 0.3 * _grass_progress
		var tones: Array[Color] = [Color("5e9a3a"), UiPalette.SUCCESS, Color("a6d65a")]
		for blade in 5:
			var dx := (blade - 2) * letter_size * 0.04
			var tip := base + Vector2(dx * 1.7, -h * (1.0 - 0.18 * absf(blade - 2)))
			_overlay.draw_colored_polygon(PackedVector2Array([base + Vector2(dx - 2.5, 0), tip, base + Vector2(dx + 2.5, 0)]), tones[blade % 3])


## Chiodo piantato di sbieco nella prima "O": entra con il progresso, poi la crepa.
func _draw_nail() -> void:
	if _nail_progress <= 0.0:
		return
	var enter := clampf(_nail_progress / 0.6, 0.0, 1.0)
	var length := letter_size * 0.62
	var direction := Vector2(-0.5, 1.0).normalized()
	var head := _nail_anchor - direction * length * (1.0 + (1.0 - enter) * 0.9)
	var tip := _nail_anchor + direction * length * 0.3 * enter
	var width := maxf(letter_size * 0.11, 3.0)
	var c := _overlay
	c.draw_line(head, tip, UiPalette.OUTLINE, width + 4.0)
	c.draw_line(head, tip, Color("b9bcc2"), width)
	c.draw_line(head, head + (tip - head) * 0.5, Color("e6e8ec"), width * 0.4)
	var side := Vector2(direction.y, -direction.x)
	var head_w := width * 1.9
	var cap := PackedVector2Array([head + side * head_w, head - side * head_w, head - side * head_w * 0.8 + direction * width * 0.9, head + side * head_w * 0.8 + direction * width * 0.9])
	c.draw_colored_polygon(cap, Color("d9dbe0"))
	cap.append(cap[0])
	c.draw_polyline(cap, UiPalette.OUTLINE, 3.0)
	if _nail_progress > 0.6:
		var crack := clampf((_nail_progress - 0.6) / 0.4, 0.0, 1.0)
		var points := PackedVector2Array([_nail_anchor])
		var offsets: Array[Vector2] = [Vector2(0.3, 0.25), Vector2(0.5, 0.55), Vector2(0.42, 0.85), Vector2(0.7, 1.1)]
		var shown := int(ceil(crack * offsets.size()))
		for i in shown:
			points.append(_nail_anchor + offsets[i] * letter_size * 0.3)
		if points.size() > 1:
			c.draw_polyline(points, UiPalette.OUTLINE, maxf(letter_size / 28.0, 2.0))
