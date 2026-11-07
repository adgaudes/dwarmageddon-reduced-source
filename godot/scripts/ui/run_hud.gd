class_name RunHud
extends CanvasLayer
## HUD della run (D-038): barra esperienza in alto, livello, vita, tempo e
## rottamatori abbattuti; annuncio del boss con freccia di direzione e barra
## della sua vita (D-043). Solo lettura: mai focus ne input.

## Priorita dell'annuncio unico: treno e terremoto, poi boss, poi piazzola di estrazione, poi
## piazzola di fusione (D-093). I chiamanti usano sempre i nomi, mai i numeri.
enum WarningPriority { FUSION, EXTRACTION, BOSS, EVENT }
const XP_COLOR := UiPalette.XP
const BOSS_COLOR := Color(0.95, 0.6, 0.08)
const DAY_COLOR := Color(1.0, 0.9, 0.55)
const NIGHT_COLOR := Color(0.6, 0.65, 1.0)
const TRAIN_COLOR := Color(1.0, 0.45, 0.3)
const QUAKE_COLOR := Color(0.9, 0.62, 0.32)
const EXTRACTION_COLOR := Color(0.35, 0.9, 0.6)
const FUSION_COLOR := Color(0.45, 0.8, 1.0)
const TITLE_COLOR := UiPalette.TEXT
## Distanza della freccia di direzione dal centro dello schermo, in frazione del lato corto.
const ARROW_RADIUS_RATIO := 0.36
## Ingombro di una scritta degli indicatori, per non sovrapporle.
const MARKER_LABEL_SIZE := Vector2(120.0, 20.0)
## Aria fra le frecce degli indicatori verso il basso e la colonna in basso a destra.
const MARKER_CLEARANCE := 20.0

var _xp_bar: ProgressBar
var _level_label: Label
var _time_label: Label
var _day_label: Label
var _day_dial: DayDial
var _dusk_total := -1.0
var _tool_label: Label
var _pack_label: Label
var _tool_icon: UiIcon
var _kills_label: Label
var _day_phase_shown := -1
var _day_second_shown := -1
var _night_notice_left := 0.0
var _night_notice_text := ""
var _health_row: HealthBolts
var _health_label: Label
## Indicatore del tool sopra la barra dell'esperienza (playtest O-02): modo, terra nello
## zaino e cosa fa il modo.
var _gauge: PanelContainer
var _gauge_mode: Label
var _gauge_bar: ProgressBar
var _gauge_hint: Label
var _gauge_amount := 0.0
var _gauge_capacity := 0.0
var _gauge_mode_id := 0
var _gauge_lamp_cost := 0
var _aim_label: Label
var _damage_flash: TextureRect
var _boss_warning: Label
var _warning_plate: PanelContainer
var _boss_name_label: Label
var _boss_arrow: Polygon2D
## Passo fisico e priorita dell'ultima scrittura dell'annuncio (audit R-01).
var _warning_frame := -1
var _warning_priority := -1
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _root: Control
var _controls: ButtonPrompts
## Colonna in basso a destra: carovana (D-093) sopra le armi (D-092).
var _corner: VBoxContainer
var _caravan_strip: CaravanStrip
var _weapons: WeaponStrip
## Indicatori a bordo schermo (punti di interesse, boss): freccia e distanza, riusati.
var _marker_arrows: Array[Polygon2D] = []
var _marker_labels: Array[Label] = []
var _markers_shown := 0
## Ultimi valori scritti nelle etichette: la stringa si rifa solo quando cambiano (U-06).
var _time_shown := -1
var _boss_seconds_shown := -1
var _boss_direction_shown := ""


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root

	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.custom_minimum_size = Vector2(520, 16)
	root.add_child(_xp_bar)
	_xp_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)
	_xp_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_xp_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_tool_gauge(root)

	# Riga superiore: livello a sinistra, tempo al centro, abbattuti a destra.
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 16
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	# Sinistra: vita e livello su una striscia; centro: tempo e giorno; destra: abbattuti.
	var left := _strip(top, &"bolt", UiPalette.DANGER)
	_health_row = HealthBolts.new()
	_health_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(_health_row)
	# Vita anche in numero (O-01): con 10 bulloni il conto a occhio non basta.
	_health_label = _label(left, HORIZONTAL_ALIGNMENT_LEFT)
	_health_label.name = "HealthLabel"
	_health_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_health_label.add_theme_font_size_override(&"font_size", 22)
	_health_label.add_theme_color_override(&"font_color", UiPalette.DANGER.lightened(0.25))
	_build_damage_flash(root)
	_level_label = _label(left, HORIZONTAL_ALIGNMENT_LEFT)
	_level_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_level_label.add_theme_font_size_override(&"font_size", 20)
	_spacer(top)
	var center := _strip(top, &"clock", UiPalette.TEXT_MUTED)
	_time_label = _label(center, HORIZONTAL_ALIGNMENT_CENTER)
	_time_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_time_label.add_theme_font_size_override(&"font_size", 26)
	_day_dial = DayDial.new()
	_day_dial.hide()
	center.add_child(_day_dial)
	_day_label = _label(center, HORIZONTAL_ALIGNMENT_LEFT)
	_day_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_day_label.add_theme_font_size_override(&"font_size", 20)
	_day_label.add_theme_color_override(&"font_color", DAY_COLOR)
	_day_label.hide()
	_spacer(top)
	var right := _strip(top, &"skull", UiPalette.TEXT_MUTED)
	_kills_label = _label(right, HORIZONTAL_ALIGNMENT_RIGHT)
	_kills_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_kills_label.add_theme_font_size_override(&"font_size", 20)

	# Modalita del tool quando non e la solita (lampione: icona, costo e contatore).
	var tool_row := HBoxContainer.new()
	tool_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tool_row.offset_left = 24
	tool_row.offset_top = 70
	tool_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_row.add_theme_constant_override(&"separation", 8)
	root.add_child(tool_row)
	_tool_icon = UiIcon.make(&"lamp", 22.0, Color("ffd45a"))
	_tool_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tool_icon.hide()
	tool_row.add_child(_tool_icon)
	_tool_label = Label.new()
	_tool_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_label.theme_type_variation = &"HudLabel"
	_tool_label.add_theme_font_size_override(&"font_size", 18)
	_tool_label.hide()
	tool_row.add_child(_tool_label)
	_pack_label = Label.new()
	_pack_label.name = "PackLabel"
	_pack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pack_label.theme_type_variation = &"HudLabel"
	_pack_label.add_theme_font_size_override(&"font_size", 18)
	_pack_label.hide()
	_gauge_row().add_child(_pack_label)

	# Annuncio del boss: scritta sotto la riga superiore e freccia verso la direzione di arrivo.
	_warning_plate = PanelContainer.new()
	_warning_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning_plate.hide()
	root.add_child(_warning_plate)
	_warning_plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 96)
	_warning_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warning_plate.rotation_degrees = -1.5
	# Ruota attorno al centro della dimensione attuale, anche dopo un testo piu lungo.
	_warning_plate.resized.connect(func() -> void: _warning_plate.pivot_offset = _warning_plate.size * 0.5)
	_boss_warning = Label.new()
	_boss_warning.theme_type_variation = &"HudLabel"
	_boss_warning.add_theme_font_size_override(&"font_size", 28)
	_boss_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_warning.add_theme_color_override(&"font_color", BOSS_COLOR)
	_boss_warning.hide()
	_warning_plate.add_child(_boss_warning)
	_boss_arrow = Polygon2D.new()
	_boss_arrow.polygon = PackedVector2Array([Vector2(0, -34), Vector2(26, 22), Vector2(0, 8), Vector2(-26, 22)])
	_boss_arrow.color = BOSS_COLOR
	_boss_arrow.hide()
	root.add_child(_boss_arrow)

	# Barra della vita del boss, in basso al centro.
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_boss_box.offset_left = -260
	_boss_box.offset_right = 260
	_boss_box.offset_top = -92
	_boss_box.offset_bottom = -36
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.hide()
	root.add_child(_boss_box)
	_boss_name_label = _label(_boss_box, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_name_label.text = "IL DEMOLITORE"
	_boss_name_label.add_theme_font_size_override(&"font_size", 20)
	_boss_name_label.add_theme_color_override(&"font_color", BOSS_COLOR)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.custom_minimum_size = Vector2(520, 16)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var boss_fill := StyleBoxFlat.new()
	boss_fill.bg_color = BOSS_COLOR
	_boss_bar.add_theme_stylebox_override(&"fill", UiPalette.plate("gauge_fill", boss_fill, 6.0, 0.0, Vector4(3, 3, 3, 3), BOSS_COLOR))
	_boss_box.add_child(_boss_bar)

	# Comandi di gioco, in basso a sinistra.
	_controls = ButtonPrompts.create([[&"dash", "Scatto"], [&"terrain_tool", "Scava o rialza"],
		[&"terrain_mode", "Cambia modo"], [&"weapon_active_1", "Attiva 1"], [&"weapon_active_2", "Attiva 2"],
		[&"weapon_aim_mode", "Mira auto/manuale"], [&"camera_zoom_cycle", "Distanza camera"], [&"pause", "Pausa"]], true)
	_controls.modulate.a = 0.85
	root.add_child(_controls)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	_controls.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Carovana (D-093) sopra le armi (D-092), in una colonna in basso a destra: il basso a
	# sinistra e della riga dei comandi. Senza carovana la sua striscia resta nascosta.
	_corner = VBoxContainer.new()
	_corner.name = "CornerColumn"
	_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_corner.alignment = BoxContainer.ALIGNMENT_END
	_caravan_strip = CaravanStrip.new()
	_caravan_strip.name = "CaravanStrip"
	_caravan_strip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_caravan_strip.hide()
	_corner.add_child(_caravan_strip)
	_weapons = WeaponStrip.new()
	_weapons.name = "WeaponStrip"
	_weapons.size_flags_horizontal = Control.SIZE_SHRINK_END
	_corner.add_child(_weapons)
	root.add_child(_corner)
	_corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_corner.grow_vertical = Control.GROW_DIRECTION_BEGIN

	set_xp(0, 1, 1)
	set_time(0.0)
	set_kills(0)


## Armi negli slot (WeaponStrip.set_slots).
func set_weapons(autos: Array, actives: Array) -> void:
	_weapons.set_slots(autos, actives)


func set_weapon_cooldowns(values: Array) -> void:
	_weapons.set_cooldowns(values)


func weapon_strip() -> WeaponStrip:
	return _weapons


## Carovana (D-093): una casella per macchina (CaravanStrip.set_machines) e i rottami; la striscia
## compare alla prima chiamata.
func set_caravan(entries: Array, carried: int, capacity: int) -> void:
	_caravan_strip.set_machines(entries)
	_caravan_strip.set_scrap(carried, capacity)
	_caravan_strip.show()


## Tasto Interagisci nella striscia della carovana, uno alla volta in quest'ordine: "Ripara"
## vicino a una macchina guasta, [param pilot] ("Pilota"/"Scendi"), "Riprendi" vicino a un modulo
## staccato, "Banco" sulla pedana di fusione.
func set_caravan_prompt(repair: bool, bench := false, relic := false, pilot := "") -> void:
	_caravan_strip.set_prompt(repair, bench, relic, pilot)


func caravan_strip() -> CaravanStrip:
	return _caravan_strip


## Annuncio dell'arrivo del boss: [param direction] e nel mondo (-Z = alto dello schermo).
func set_boss_warning(boss_name: String, direction_name: String, direction: Vector3, seconds_left: float) -> void:
	set_event_warning("%s ARRIVA DA %s" % [boss_name, direction_name], direction, seconds_left, BOSS_COLOR, true,
		WarningPriority.BOSS)


## Nome sopra la barra vita del boss.
func set_boss_name(boss_name: String) -> void:
	_boss_name_label.text = boss_name


func boss_name_text() -> String:
	return _boss_name_label.text


## Annuncio con conto alla rovescia e freccia a bordo schermo verso [param direction]
## (nel mondo): boss in arrivo, treno in arrivo (livello 2). Gli eventi lo riscrivono a ogni
## passo e la riga e una sola: nello stesso passo fisico vince la [param priority] piu alta
## (audit R-01: prima vinceva l'ultimo, e la piazzola nascondeva treno e terremoto).
func set_event_warning(text: String, direction: Vector3, seconds_left: float, color: Color, with_arrow := true,
		priority := WarningPriority.EVENT) -> void:
	if not _claim_warning(priority):
		return
	var seconds := int(ceil(maxf(seconds_left, 0.0)))
	if seconds != _boss_seconds_shown or text != _boss_direction_shown:
		_boss_seconds_shown = seconds
		_boss_direction_shown = text
		_boss_warning.text = "%s  -  %d" % [text, seconds]
		_boss_warning.add_theme_color_override(&"font_color", color)
		_night_notice_left = 0.0
	_boss_warning.show()
	_warning_plate.show()
	if not with_arrow:
		_boss_arrow.hide()
		return
	var size := _root.size
	var screen_direction := Vector2(direction.x, direction.z).normalized()
	_boss_arrow.position = size * 0.5 + screen_direction * minf(size.x, size.y) * ARROW_RADIUS_RATIO
	_boss_arrow.rotation = screen_direction.angle() + PI * 0.5
	# Lampeggio lento: si nota senza coprire il campo.
	_boss_arrow.modulate.a = 0.55 + 0.45 * absf(sin(seconds_left * 4.0))
	_boss_arrow.show()


## Indicatori a bordo schermo. Ogni voce: { direction: Vector2 (schermo, x destra e
## y basso), distance: float (metri), color: Color, text: String }.
func set_markers(markers: Array[Dictionary]) -> void:
	while _marker_arrows.size() < markers.size():
		var arrow := Polygon2D.new()
		arrow.polygon = PackedVector2Array([Vector2(0, -16), Vector2(12, 10), Vector2(0, 4), Vector2(-12, 10)])
		_root.add_child(arrow)
		_marker_arrows.append(arrow)
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override(&"font_size", 15)
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(&"outline_size", 5)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(120, 0)
		_root.add_child(label)
		_marker_labels.append(label)
	var size := _root.size
	var center := size * 0.5
	# Margini: in alto e in basso ci sono le righe dell'HUD e la barra del boss. Con la striscia
	# della carovana la colonna in basso a destra e piu alta: le frecce verso il basso restano
	# sopra di lei (senza carovana, come prima).
	var half_x := maxf(center.x - 70.0, 10.0)
	var half_up := maxf(center.y - 160.0, 10.0)
	var bottom_inset := 160.0
	if _caravan_strip.visible:
		bottom_inset = maxf(160.0, 24.0 + _corner.get_combined_minimum_size().y + MARKER_CLEARANCE)
	var half_down := maxf(center.y - bottom_inset, 10.0)
	var placed: Array[Rect2] = []
	for i in _marker_arrows.size():
		var shown := i < markers.size()
		_marker_arrows[i].visible = shown
		_marker_labels[i].visible = shown
		if not shown:
			continue
		var marker := markers[i]
		var direction: Vector2 = marker.direction
		if direction.is_zero_approx():
			direction = Vector2.UP
		direction = direction.normalized()
		var half_y := half_down if direction.y > 0.0 else half_up
		var reach := minf(half_x / maxf(absf(direction.x), 0.001), half_y / maxf(absf(direction.y), 0.001))
		var spot := center + direction * reach
		_marker_arrows[i].position = spot
		_marker_arrows[i].rotation = direction.angle() + PI * 0.5
		_marker_arrows[i].color = marker.color
		var label := _marker_labels[i]
		label.text = "%s %d m" % [marker.text, int(round(marker.distance))]
		label.add_theme_color_override(&"font_color", marker.color)
		# Due punti nella stessa direzione: le scritte si impilano verso il centro
		# invece di sovrapporsi.
		var rect := Rect2(spot - direction * 30.0 - Vector2(60.0, 11.0), MARKER_LABEL_SIZE)
		var stack_step := MARKER_LABEL_SIZE.y if spot.y < center.y else -MARKER_LABEL_SIZE.y
		for attempt in markers.size():
			if not placed.any(func(other: Rect2) -> bool: return other.intersects(rect)):
				break
			rect.position.y += stack_step
		placed.append(rect)
		label.position = rect.position
	_markers_shown = markers.size()


func marker_count() -> int:
	return _markers_shown


func clear_boss_warning() -> void:
	clear_event_warning(WarningPriority.BOSS)


## [param priority]: chi toglie l'annuncio non cancella quello piu importante scritto nello stesso passo.
func clear_event_warning(priority := WarningPriority.EVENT) -> void:
	if not _claim_warning(priority):
		return
	_boss_warning.hide()
	_warning_plate.hide()
	_boss_arrow.hide()
	_boss_seconds_shown = -1
	_boss_direction_shown = ""


## Vero se [param priority] puo scrivere l'annuncio in questo passo fisico.
func _claim_warning(priority: int) -> bool:
	var frame := Engine.get_physics_frames()
	if frame == _warning_frame and priority < _warning_priority:
		return false
	_warning_frame = frame
	_warning_priority = priority
	return true


func event_warning_text() -> String:
	return _boss_warning.text if _boss_warning.visible else ""


## Un annuncio con la freccia (boss o treno) e a schermo; gli avvisi semplici
## (notte, titolo del livello) non contano.
func is_boss_warning_visible() -> bool:
	return _boss_warning.visible and _boss_arrow.visible


func set_boss_health(health: int, max_health: int) -> void:
	_boss_bar.max_value = maxi(max_health, 1)
	_boss_bar.value = maxi(health, 0)
	_boss_box.show()


func clear_boss() -> void:
	clear_boss_warning()
	_boss_box.hide()


func is_boss_bar_visible() -> bool:
	return _boss_box.visible


func set_xp(xp: int, needed: int, level: int) -> void:
	_xp_bar.max_value = maxi(needed, 1)
	_xp_bar.value = xp
	_level_label.text = "LIVELLO %d" % level


## Bulloni esagonali, ridisegnati solo quando cambiano i valori (U-07).
func set_health(health: int, max_health: int) -> void:
	_health_row.set_health(health, max_health)
	_health_label.text = "%d/%d" % [health, max_health]


## Bordo rosso sullo schermo quando il giocatore e colpito (O-01).
func flash_damage() -> void:
	if _damage_flash == null:
		return
	_damage_flash.modulate.a = 0.85
	var tween := create_tween()
	tween.tween_property(_damage_flash, ^"modulate:a", 0.0, 0.45).set_ease(Tween.EASE_OUT)


func damage_flash_alpha() -> float:
	return _damage_flash.modulate.a if _damage_flash != null else 0.0


func _build_damage_flash(root: Control) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.75, 0.05, 0.02, 0.0))
	gradient.set_color(1, Color(0.75, 0.05, 0.02, 0.75))
	gradient.add_point(0.62, Color(0.75, 0.05, 0.02, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 256
	texture.height = 256
	_damage_flash = TextureRect.new()
	_damage_flash.name = "DamageFlash"
	_damage_flash.texture = texture
	_damage_flash.stretch_mode = TextureRect.STRETCH_SCALE
	_damage_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.modulate.a = 0.0
	root.add_child(_damage_flash)
	root.move_child(_damage_flash, 0)


## Modalita del tool: visibile solo in LAMP, con costo e contatore (specifica, sezione 9).
func set_tool_mode(mode: int, lamps: int, max_lamps: int, cost: int) -> void:
	_set_gauge_mode(mode, cost)
	if mode != TerrainField.ToolMode.LAMP:
		_tool_label.hide()
		_tool_icon.hide()
		return
	_tool_label.text = "LAMPIONE  %d rottami  %d/%d" % [cost, lamps, max_lamps]
	_tool_label.add_theme_color_override(&"font_color", BrushPreview.LAMP_COLOR.linear_to_srgb())
	_tool_label.show()
	_tool_icon.show()


## Zainetto di terra del rilievo continuo: barra e "quanta/capacita m3" nell'indicatore.
func set_pack(amount: float, capacity: float) -> void:
	_pack_label.text = "%d/%d m\u00b3" % [roundi(amount), roundi(capacity)]
	_pack_label.show()
	_gauge_amount = amount
	_gauge_capacity = capacity
	_gauge_bar.max_value = maxf(capacity, 0.001)
	_gauge_bar.value = amount
	_gauge.show()
	_update_gauge_text()


## Modo e testo dell'indicatore del tool (anche fuori dal modo lampione).
func _set_gauge_mode(mode: int, cost: int) -> void:
	_gauge_mode_id = mode
	_gauge_lamp_cost = cost
	_update_gauge_text()


## Mira della chiodatrice (D-089) nell'indicatore del tool.
func set_aim_mode(manual: bool) -> void:
	_aim_label.text = "MIRA MANUALE" if manual else "MIRA AUTO"
	_aim_label.add_theme_color_override(&"font_color", Color("8fd0ff") if manual else UiPalette.TEXT_MUTED)


func aim_text() -> String:
	return _aim_label.text


func gauge_text() -> String:
	return "%s | %s | %s" % [_gauge_mode.text, _pack_label.text, _gauge_hint.text]


func _update_gauge_text() -> void:
	var names := ["SCAVA", "ALZA", "SPIANA", "LAMPIONE"]
	var colors := [BrushPreview.DIG_COLOR, BrushPreview.RAISE_COLOR, BrushPreview.LEVEL_COLOR, BrushPreview.LAMP_COLOR]
	var mode := clampi(_gauge_mode_id, 0, names.size() - 1)
	_gauge_mode.text = names[mode]
	_gauge_mode.add_theme_color_override(&"font_color", (colors[mode] as Color).linear_to_srgb())
	var empty := _gauge_amount <= 0.5
	var full := _gauge_capacity > 0.0 and _gauge_amount >= _gauge_capacity - 0.5
	match mode:
		TerrainField.ToolMode.DIG:
			_gauge_hint.text = "lo zaino e pieno: la terra in piu si perde" if full else "scavando riempi lo zaino di terra"
		TerrainField.ToolMode.RAISE:
			_gauge_hint.text = "zaino vuoto: scava per avere terra" if empty else "alzi argini con la terra dello zaino"
		TerrainField.ToolMode.LEVEL:
			_gauge_hint.text = "spiani: prendi o rendi terra allo zaino"
		_:
			_gauge_hint.text = "un lampione costa %d rottami dei Cassoni" % _gauge_lamp_cost
	_gauge_hint.add_theme_color_override(&"font_color", UiPalette.DANGER.lightened(0.3) if (empty and mode == TerrainField.ToolMode.RAISE) else UiPalette.TEXT_MUTED)


func _gauge_row() -> HBoxContainer:
	return _gauge_mode.get_parent() as HBoxContainer


func _build_tool_gauge(root: Control) -> void:
	_gauge = PanelContainer.new()
	_gauge.name = "ToolGauge"
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.add_theme_stylebox_override(&"panel", UiPalette.plate("strip", UiPalette.panel_box(true), 18.0, 0.0, Vector4(16, 4, 16, 4)))
	root.add_child(_gauge)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	_gauge.add_child(row)
	var icon := UiIcon.make(&"shovel", 24.0, UiPalette.BORDER)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	_gauge_mode = Label.new()
	_gauge_mode.theme_type_variation = &"HudLabel"
	_gauge_mode.add_theme_font_size_override(&"font_size", 20)
	_gauge_mode.custom_minimum_size = Vector2(96, 0)
	_gauge_mode.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_gauge_mode)
	_gauge_bar = ProgressBar.new()
	_gauge_bar.name = "SoilBar"
	_gauge_bar.show_percentage = false
	_gauge_bar.custom_minimum_size = Vector2(170, 14)
	_gauge_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gauge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.42, 0.22)
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.07, 0.05, 0.85)
	back.set_corner_radius_all(3)
	back.border_color = UiPalette.OUTLINE
	back.set_border_width_all(1)
	_gauge_bar.add_theme_stylebox_override(&"fill", fill)
	_gauge_bar.add_theme_stylebox_override(&"background", back)
	row.add_child(_gauge_bar)
	_gauge_hint = Label.new()
	_gauge_hint.theme_type_variation = &"HudLabel"
	_gauge_hint.add_theme_font_size_override(&"font_size", 16)
	_gauge_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_hint.custom_minimum_size = Vector2(330, 0)
	_gauge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 36)
	_gauge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gauge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# L'etichetta dei m3 si aggiunge in mezzo (in _ready), suggerimento e mira in fondo.
	row.add_child.call_deferred(_gauge_hint)
	_aim_label = Label.new()
	_aim_label.name = "AimLabel"
	_aim_label.theme_type_variation = &"HudLabel"
	_aim_label.add_theme_font_size_override(&"font_size", 16)
	_aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_label.text = "MIRA AUTO"
	row.add_child.call_deferred(_aim_label)
	_gauge.hide()


## Indicatore sole/luna nella riga superiore: tempo al tramonto di giorno, poi la fase.
## Con ciclo spento (`seconds_to_dusk` infinito) resta nascosto.
func set_day_phase(phase: int, seconds_to_dusk: float) -> void:
	if not is_finite(seconds_to_dusk):
		_day_label.hide()
		_day_dial.hide()
		_dusk_total = -1.0
		return
	if _dusk_total < 0.0:
		_dusk_total = maxf(seconds_to_dusk, 1.0)
	_day_dial.set_phase(phase, 1.0 - clampf(seconds_to_dusk / _dusk_total, 0.0, 1.0) if phase == DayNightCycle.Phase.DAY else 1.0)
	_day_dial.show()
	var second := int(ceil(seconds_to_dusk))
	if phase == _day_phase_shown and (phase != DayNightCycle.Phase.DAY or second == _day_second_shown):
		return
	_day_phase_shown = phase
	_day_second_shown = second
	match phase:
		DayNightCycle.Phase.DAY:
			_day_label.text = "SOLE %s" % format_time(seconds_to_dusk)
			_day_label.add_theme_color_override(&"font_color", DAY_COLOR)
		DayNightCycle.Phase.DUSK:
			_day_label.text = "TRAMONTO"
			_day_label.add_theme_color_override(&"font_color", DAY_COLOR)
		_:
			_day_label.text = "NOTTE"
			_day_label.add_theme_color_override(&"font_color", NIGHT_COLOR)
	_day_label.show()


## Avviso del tramonto o della notte, nello spazio dell'annuncio del boss, che ha la precedenza.
func show_night_notice(text: String, seconds: float) -> void:
	show_notice(text, seconds, NIGHT_COLOR)


## Avviso semplice senza freccia (notte, titolo del livello), nel colore dato.
func show_notice(text: String, seconds: float, color: Color) -> void:
	# Solo l'annuncio del boss (quello con la freccia) ha la precedenza; un avviso
	# precedente viene sostituito.
	if _boss_arrow.visible:
		return
	_night_notice_text = text
	_night_notice_left = seconds
	_boss_warning.text = text
	_boss_warning.add_theme_color_override(&"font_color", color)
	_boss_warning.show()
	_warning_plate.show()


func is_night_notice_visible() -> bool:
	return _night_notice_left > 0.0 and _boss_warning.visible and _boss_warning.text == _night_notice_text


func _process(delta: float) -> void:
	if _night_notice_left <= 0.0:
		return
	_night_notice_left -= delta
	if _night_notice_left <= 0.0 and _boss_warning.text == _night_notice_text:
		_boss_warning.hide()
		_warning_plate.hide()
		_boss_warning.add_theme_color_override(&"font_color", BOSS_COLOR)


func set_time(seconds: float) -> void:
	var total := int(seconds)
	if total == _time_shown:
		return
	_time_shown = total
	_time_label.text = format_time(seconds)


func set_kills(kills: int) -> void:
	_kills_label.text = "ROTTAMATI %d" % kills


static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]


## Striscia di lamiera (strip.png) con un'icona a sinistra; il contenuto va nell'HBox restituito.
func _strip(parent: Control, icon_kind: StringName, icon_tint: Color) -> HBoxContainer:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override(&"panel", UiPalette.plate("strip", UiPalette.panel_box(true), 18.0, 0.0, Vector4(16, 4, 16, 4)))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(plate)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	plate.add_child(row)
	var icon := UiIcon.make(icon_kind, 24.0, icon_tint)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	return row


func _spacer(parent: Control) -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)


## La striscia (PanelContainer) che contiene [param control], o null.
func strip_of(control: Control) -> PanelContainer:
	var node := control.get_parent()
	while node != null and not (node is PanelContainer):
		node = node.get_parent()
	return node as PanelContainer


## L'icona (UiIcon) che precede [param control] nella sua riga, o null.
func icon_before(control: Control) -> UiIcon:
	var row := control.get_parent()
	if row == null:
		return null
	for child in row.get_children():
		if child is UiIcon:
			return child
	return null


func _label(parent: Control, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"HudLabel"
	parent.add_child(label)
	return label
