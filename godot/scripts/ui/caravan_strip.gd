class_name CaravanStrip
extends PanelContainer
## Striscia della carovana del HUD (spec D-093, Sezione 6; scelta 11 del piano A), sopra quella
## delle armi. A sinistra i rottami ("3/5"), poi una casella per macchina: icona del modulo,
## cornice del colore del modulo, tacche di vita, bordo rosso e barra diagonale da guasta, tinta
## da ritirata, spicchio della riparazione dalle 12 in senso orario. In fondo il tasto Interagisci
## ("Ripara"), acceso solo vicino a una macchina guasta, o nello stesso posto "Banco" sulla pedana
## di fusione (uno alla volta, Ripara prima): il suo posto resta, le caselle non si spostano.
## Solo lettura: mai focus ne input.
## Taglia (piano B, scelta 11 di D-093): la casella e larga `SLOT_SIZE + SIZE_STEP x taglia`, ha un
## quadratino del colore di ogni modulo oltre il primo e mostra la vita a tacche fino a
## `MAX_PIPS` PV, a barra oltre.
## Voci di `set_machines`: {icon, color, health, max_health, state (Machine.State), repair (0..1),
## size (MachineFusion.Size, 0 se manca), extra (Array[Color], vuoto se manca)}.

const SLOT_SIZE := 40.0
const ROW_HEIGHT := 52.0
## Pixel di larghezza in piu per ogni taglia oltre la piccola.
const SIZE_STEP := 14.0
## Oltre tanti PV la vita e una barra, non tacche.
const MAX_PIPS := 12

var _slot_row: HBoxContainer
var _slots: Array[CaravanSlot] = []
var _scrap_label: Label
var _prompt: ButtonPrompts
var _prompt_shown := false
var _bench_prompt: ButtonPrompts
var _bench_prompt_shown := false
var _relic_prompt: ButtonPrompts
var _relic_prompt_shown := false
## "Pilota" e "Scendi" (task 5 del piano C); `_pilot_shown` e il testo acceso, "" se spento.
var _pilot_prompt: ButtonPrompts
var _unpilot_prompt: ButtonPrompts
var _pilot_shown := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel", UiPalette.plate("strip", UiPalette.panel_box(true), 18.0, 0.0, Vector4(14, 6, 14, 6)))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = ROW_HEIGHT
	row.add_theme_constant_override(&"separation", 8)
	add_child(row)
	var scrap := UiIcon.make(&"scrap", 24.0, UiPalette.SCRAP)
	scrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(scrap)
	_scrap_label = Label.new()
	_scrap_label.name = "ScrapLabel"
	_scrap_label.theme_type_variation = &"HudLabel"
	_scrap_label.add_theme_font_size_override(&"font_size", 20)
	_scrap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_scrap_label)
	_slot_row = HBoxContainer.new()
	_slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_row.add_theme_constant_override(&"separation", 4)
	_slot_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_slot_row)
	# I tasti di Interagisci uno sopra l'altro: il posto e quello del piu largo.
	var prompts := MarginContainer.new()
	prompts.name = "InteractPrompts"
	prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(prompts)
	_prompt = _make_prompt("Ripara")
	prompts.add_child(_prompt)
	_bench_prompt = _make_prompt("Banco")
	prompts.add_child(_bench_prompt)
	_relic_prompt = _make_prompt("Riprendi")
	prompts.add_child(_relic_prompt)
	_pilot_prompt = _make_prompt("Pilota")
	prompts.add_child(_pilot_prompt)
	_unpilot_prompt = _make_prompt("Scendi")
	prompts.add_child(_unpilot_prompt)


func _make_prompt(text: String) -> ButtonPrompts:
	var prompt := ButtonPrompts.create([[&"interact", text]])
	prompt.icon_size = 24
	prompt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prompt.modulate.a = 0.0
	return prompt


## Una casella per voce: si aggiungono o tolgono solo quando cambia il numero, le altre si
## aggiornano sul posto.
func set_machines(entries: Array) -> void:
	while _slots.size() > entries.size():
		var last: CaravanSlot = _slots.pop_back()
		_slot_row.remove_child(last)
		last.queue_free()
	while _slots.size() < entries.size():
		var slot := CaravanSlot.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		_slot_row.add_child(slot)
		_slots.append(slot)
	for i in entries.size():
		_slots[i].custom_minimum_size = Vector2(SLOT_SIZE + SIZE_STEP * int(entries[i].get(&"size", 0)), SLOT_SIZE)
		_slots[i].show_entry(entries[i])


func set_scrap(carried: int, capacity: int) -> void:
	var text := "%d/%d" % [carried, capacity]
	if _scrap_label.text != text:
		_scrap_label.text = text


## Un tasto di Interagisci acceso alla volta, in quest'ordine: "Ripara", poi [param pilot]
## ("Pilota" o "Scendi", "" nessuno), poi "Riprendi" (un modulo staccato in portata), poi "Banco".
## Spento tiene il suo posto (trasparente).
func set_prompt(repair: bool, bench := false, relic := false, pilot := "") -> void:
	var show_pilot := "" if repair else pilot
	var show_relic := relic and not repair and show_pilot.is_empty()
	var show_bench := bench and not repair and show_pilot.is_empty() and not relic
	if repair != _prompt_shown:
		_prompt_shown = repair
		_prompt.modulate.a = 1.0 if repair else 0.0
	if show_pilot != _pilot_shown:
		_pilot_shown = show_pilot
		_pilot_prompt.modulate.a = 1.0 if show_pilot == "Pilota" else 0.0
		_unpilot_prompt.modulate.a = 1.0 if show_pilot == "Scendi" else 0.0
	if show_relic != _relic_prompt_shown:
		_relic_prompt_shown = show_relic
		_relic_prompt.modulate.a = 1.0 if show_relic else 0.0
	if show_bench != _bench_prompt_shown:
		_bench_prompt_shown = show_bench
		_bench_prompt.modulate.a = 1.0 if show_bench else 0.0


func slot_count() -> int:
	return _slots.size()


func slot_state(index: int) -> int:
	return int(_slots[index].entry.get(&"state", Machine.State.OK))


func slot_health(index: int) -> int:
	return int(_slots[index].entry.get(&"health", 0))


func slot_repair(index: int) -> float:
	return float(_slots[index].entry.get(&"repair", 0.0))


## Larghezza minima della casella [param index] (cresce con la taglia).
func slot_width(index: int) -> float:
	return _slots[index].custom_minimum_size.x


func slot_size(index: int) -> int:
	return int(_slots[index].entry.get(&"size", 0))


## Vero se la casella [param index] mostra la vita a barra (oltre MAX_PIPS PV).
func slot_uses_bar(index: int) -> bool:
	return _slots[index].uses_bar()


func scrap_text() -> String:
	return _scrap_label.text


func prompt_visible() -> bool:
	return _prompt_shown


func bench_prompt_visible() -> bool:
	return _bench_prompt_shown


func relic_prompt_visible() -> bool:
	return _relic_prompt_shown


## "Pilota" o "Scendi" se acceso, altrimenti "".
func pilot_prompt_text() -> String:
	return _pilot_shown


class CaravanSlot:
	extends Control

	## Tinta della casella di una macchina in ritirata.
	const RETREAT_TINT := Color(0.95, 0.72, 0.2, 0.45)
	const REPAIR_COLOR := Color(0.5, 0.85, 0.35, 0.55)
	const HEALTH_ON := Color("7fc24f")
	const HEALTH_OFF := Color(0.25, 0.2, 0.16)
	## Quadratini dei moduli oltre il primo: lato e passo (px), in alto a destra.
	const EXTRA_SIDE := 5.0
	const EXTRA_STEP := 7.0
	var entry: Dictionary = {}
	var _icon: UiIcon
	## Sopra l'icona: spicchio della riparazione, barra del guasto e tacche di vita.
	var _overlay: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon = UiIcon.make(&"crate", 0.0)
		_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		_icon.offset_left = 5.0
		_icon.offset_top = 3.0
		_icon.offset_right = -5.0
		_icon.offset_bottom = -9.0
		add_child(_icon)
		_overlay = Control.new()
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.draw.connect(_draw_overlay)
		add_child(_overlay)
		_apply()

	## Ridisegna solo se la voce cambia.
	func show_entry(next: Dictionary) -> void:
		if next == entry:
			return
		entry = next
		_apply()

	func _apply() -> void:
		if _icon == null:
			return
		_icon.kind = entry.get(&"icon", &"crate")
		# L'icona si centra a sinistra dei quadratini: nessuna sovrapposizione.
		_icon.offset_right = -5.0 - EXTRA_STEP * (entry.get(&"extra", []) as Array).size()
		queue_redraw()
		_overlay.queue_redraw()

	func _state() -> int:
		return int(entry.get(&"state", Machine.State.OK))

	func uses_bar() -> bool:
		return int(entry.get(&"max_health", 0)) > MAX_PIPS

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.08, 0.06, 0.05, 0.85))
		if _state() == Machine.State.RETREAT:
			draw_rect(rect, RETREAT_TINT)
		var frame: Color = UiPalette.DANGER if _state() == Machine.State.BROKEN else entry.get(&"color", UiPalette.BORDER)
		draw_rect(rect.grow(-1.0), frame, false, 2.0)

	func _draw_overlay() -> void:
		var repair := float(entry.get(&"repair", 0.0))
		if repair >= 0.005:
			# Spicchio che cresce dalle 12 in senso orario mentre si tiene Interagisci, nel cerchio
			# inscritto: punti tutti distinti (ritagliati al quadrato si sovrapporrebbero sul bordo).
			var center := size * 0.5
			var radius := minf(size.x, size.y) * 0.5 - 2.0
			if repair >= 0.999:
				_overlay.draw_circle(center, radius, REPAIR_COLOR)
			else:
				var steps := maxi(ceili(32.0 * repair), 2)
				var points := PackedVector2Array([center])
				for s in steps + 1:
					var angle := -PI * 0.5 + TAU * repair * float(s) / steps
					points.append(center + Vector2(cos(angle), sin(angle)) * radius)
				_overlay.draw_colored_polygon(points, REPAIR_COLOR)
		if _state() == Machine.State.BROKEN:
			_overlay.draw_line(Vector2(4.0, size.y - 4.0), Vector2(size.x - 4.0, 4.0), UiPalette.DANGER, 4.0, true)
		# Un quadratino per modulo oltre il primo, da destra verso sinistra in alto.
		var extra: Array = entry.get(&"extra", [])
		for k in extra.size():
			var square := Rect2(size.x - 4.0 - EXTRA_SIDE - k * EXTRA_STEP, 4.0, EXTRA_SIDE, EXTRA_SIDE)
			_overlay.draw_rect(square, extra[k])
			_overlay.draw_rect(square, HEALTH_OFF, false, 1.0)
		# Vita in basso: tacche piene fino ai PV attuali, o una barra oltre MAX_PIPS.
		var max_health := maxi(int(entry.get(&"max_health", 0)), 1)
		var health := int(entry.get(&"health", 0))
		if uses_bar():
			var track := Rect2(4.0, size.y - 7.0, size.x - 8.0, 4.0)
			_overlay.draw_rect(track, HEALTH_OFF)
			var fill := track.size.x * clampf(float(health) / max_health, 0.0, 1.0)
			_overlay.draw_rect(Rect2(track.position, Vector2(fill, track.size.y)), HEALTH_ON)
			return
		var pip_w := (size.x - 8.0) / max_health
		for p in max_health:
			var pip := Rect2(4.0 + p * pip_w + 0.5, size.y - 7.0, pip_w - 1.0, 4.0)
			_overlay.draw_rect(pip, HEALTH_ON if p < health else HEALTH_OFF)
