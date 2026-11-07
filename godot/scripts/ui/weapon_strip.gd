class_name WeaponStrip
extends PanelContainer
## Striscia delle armi del HUD (spec D-092, par. 7): tre slot automatici e due attivi. Ogni slot
## mostra l'icona dell'arma, cinque tacche di livello e le lettere dei bivi presi; gli attivi
## anche la ricarica a spicchio e il tasto (ButtonPrompts). Uno slot vuoto e una cornice spenta.
## Voci: {icon, level, branches ("A", "AB"...), cooldown (0 = carica, 1 = appena usata)}.

const SLOT_SIZE := 52.0
const ACTIVE_ACTIONS: Array[StringName] = [&"weapon_active_1", &"weapon_active_2"]

var _slots: Array[WeaponSlot] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel", UiPalette.plate("strip", UiPalette.panel_box(true), 18.0, 0.0, Vector4(14, 6, 14, 6)))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	add_child(row)
	for i in WeaponLoadout.AUTO_SLOTS + WeaponLoadout.ACTIVE_SLOTS:
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override(&"separation", 2)
		row.add_child(column)
		if i == WeaponLoadout.AUTO_SLOTS:
			# Le attive si staccano dalle automatiche con un po' d'aria.
			column.custom_minimum_size.x = SLOT_SIZE + 14.0
		var slot := WeaponSlot.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_END
		column.add_child(slot)
		_slots.append(slot)
		if i >= WeaponLoadout.AUTO_SLOTS:
			slot.action = ACTIVE_ACTIONS[i - WeaponLoadout.AUTO_SLOTS]
			var prompt := ButtonPrompts.create([[slot.action, ""]])
			prompt.size_flags_horizontal = Control.SIZE_SHRINK_END
			prompt.custom_minimum_size.x = SLOT_SIZE
			column.add_child(prompt)


func set_slots(autos: Array, actives: Array) -> void:
	for i in _slots.size():
		var entry: Dictionary = {}
		if i < WeaponLoadout.AUTO_SLOTS:
			if i < autos.size():
				entry = autos[i]
		elif i - WeaponLoadout.AUTO_SLOTS < actives.size():
			entry = actives[i - WeaponLoadout.AUTO_SLOTS]
		_slots[i].show_entry(entry)


## Ricarica degli attivi (0..1), nell'ordine degli slot; aggiorna solo il disegno.
func set_cooldowns(values: Array) -> void:
	for k in WeaponLoadout.ACTIVE_SLOTS:
		_slots[WeaponLoadout.AUTO_SLOTS + k].set_cooldown(float(values[k]) if k < values.size() else 0.0)


func slot_count() -> int:
	return _slots.size()


## "3 A" per un'arma al livello 3 con la trasformazione A; vuoto per uno slot vuoto.
func slot_text(index: int) -> String:
	return _slots[index].text()


func cooldown_of(index: int) -> float:
	return _slots[index].cooldown


func prompt_action(index: int) -> StringName:
	return _slots[index].action


class WeaponSlot:
	extends Control

	const PIPS := 5
	var action: StringName = &""
	var cooldown := 0.0
	var _entry: Dictionary = {}
	var _icon: UiIcon
	var _letters: Label

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon = UiIcon.make(&"nail", 0.0, UiPalette.BORDER)
		# L'icona riempie lo slot sopra le tacche: UiIcon disegna nel quadrato centrale.
		_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		_icon.offset_left = 6.0
		_icon.offset_top = 4.0
		_icon.offset_right = -6.0
		_icon.offset_bottom = -12.0
		_icon.hide()
		add_child(_icon)
		_letters = Label.new()
		_letters.theme_type_variation = &"HudLabel"
		_letters.add_theme_font_size_override(&"font_size", 14)
		_letters.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_letters.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
		add_child(_letters)
		show_entry(_entry)

	func show_entry(entry: Dictionary) -> void:
		_entry = entry
		cooldown = float(entry.get(&"cooldown", 0.0))
		if _icon == null:
			return
		_icon.visible = not entry.is_empty()
		if not entry.is_empty():
			_icon.kind = entry.get(&"icon", &"nail")
		_letters.text = String(entry.get(&"branches", ""))
		queue_redraw()

	func set_cooldown(value: float) -> void:
		if absf(value - cooldown) < 0.01 and not (value == 0.0 and cooldown != 0.0):
			return
		cooldown = clampf(value, 0.0, 1.0)
		queue_redraw()

	func text() -> String:
		if _entry.is_empty():
			return ""
		return ("%d %s" % [int(_entry.get(&"level", 1)), _entry.get(&"branches", "")]).strip_edges()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var empty := _entry.is_empty()
		draw_rect(rect, Color(0.08, 0.06, 0.05, 0.55 if empty else 0.85))
		draw_rect(rect, UiPalette.BORDER if not empty else UiPalette.OUTLINE, false, 2.0)
		if empty:
			return
		# Tacche di livello in basso: piene fino al livello raggiunto.
		var level := int(_entry.get(&"level", 1))
		var pip_w := (size.x - 10.0) / PIPS
		for p in PIPS:
			var pip := Rect2(5.0 + p * pip_w + 1.0, size.y - 8.0, pip_w - 2.0, 4.0)
			draw_rect(pip, UiPalette.XP if p < level else Color(0.25, 0.2, 0.16))
		if cooldown > 0.0:
			# Spicchio scuro che si ritira in senso orario mentre l'arma si ricarica.
			var center := size * 0.5
			var radius := size.length() * 0.5
			var points := PackedVector2Array([center])
			var steps := 24
			for s in steps + 1:
				var angle := -PI * 0.5 + TAU * cooldown * float(s) / steps
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(_clip(points), Color(0.0, 0.0, 0.0, 0.6))

	## I punti del ventaglio stanno fuori dal quadrato: si portano sul bordo.
	func _clip(points: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in points:
			out.append(Vector2(clampf(p.x, 0.0, size.x), clampf(p.y, 0.0, size.y)))
		return out
